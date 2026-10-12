import Foundation
import IOBluetooth
import OneBudsCore
import OneBudsDiagnostics
import os

/// Classic Bluetooth transport: an RFCOMM channel opened by SDP service UUID through IOBluetooth.
///
/// Follows ProtocolSources §8 (documented IOBluetooth lessons, re-implemented independently):
/// unfiltered SDP query, channel taken from the service record and cross-checked against the
/// ProtocolDescriptorList (observed mismatch on another record, PhaseB-Report §4.2), the channel
/// opened on the main run loop, completion detected by callback *or* `isOpen()`, writes chunked to
/// the MTU, and data copied inside the callback.
///
/// It never pages the buds: if they are not already connected to this Mac, `connect()` fails.
@MainActor
public final class RFCOMMTransport: NSObject, EarbudTransport {
    public nonisolated let kind = TransportKind.rfcomm
    public nonisolated let incoming: AsyncStream<Data>
    public nonisolated let state: AsyncStream<TransportState>
    private let incomingContinuation: AsyncStream<Data>.Continuation
    private let stateContinuation: AsyncStream<TransportState>.Continuation

    private let device: IOBluetoothDevice
    private let serviceUUIDs: [String]
    private var channel: IOBluetoothRFCOMMChannel?
    private var openCompletion: IOReturn?
    private var used = false
    private var finished = false
    private let logger = Logger(subsystem: "com.local.onebuds", category: "rfcomm")

    /// Human-readable channel details for diagnostics, e.g. `RFCOMM channel 15 ("enco link")`.
    public private(set) var channelDescription: String?

    /// - Parameter serviceUUIDs: SDP services to try in order (e.g. 079A, then standard SPP 0x1101).
    public init(device: IOBluetoothDevice, serviceUUIDs: [String]) {
        self.device = device
        self.serviceUUIDs = serviceUUIDs
        (incoming, incomingContinuation) = AsyncStream.makeStream(of: Data.self)
        (state, stateContinuation) = AsyncStream.makeStream(of: TransportState.self)
        super.init()
    }

    public func connect() async throws {
        guard !used else { throw TransportError.alreadyUsed }
        used = true
        stateContinuation.yield(.connecting)
        do {
            guard device.isConnected() else { throw TransportError.deviceNotFound }
            let record = try await serviceRecord()
            let channelID = try channelID(of: record)
            channelDescription = "RFCOMM channel \(channelID)" + (record.getServiceName().map { " (\"\($0.trimmingCharacters(in: .whitespaces))\")" } ?? "")
            try await openChannel(channelID)
            logger.info("Opened \(self.channelDescription ?? "", privacy: .public)")
            stateContinuation.yield(.connected)
        } catch {
            finish(.failed(error.localizedDescription))
            throw error
        }
    }

    public func disconnect() async {
        if let channel {
            _ = channel.setDelegate(nil)
            _ = channel.close()
        }
        channel = nil
        finish(.disconnected(reason: "closed by OneBuds"))
    }

    public func send(_ frame: Data) async throws {
        guard let channel, channel.isOpen() else { throw TransportError.notConnected }
        let bytes = [UInt8](frame)
        let mtu = max(1, Int(channel.getMTU()))
        var offset = 0
        while offset < bytes.count {
            var chunk = Array(bytes[offset..<min(offset + mtu, bytes.count)])
            let status = chunk.withUnsafeMutableBytes { buffer in
                channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
            }
            guard status == kIOReturnSuccess else {
                throw TransportError.writeFailed(String(format: "IOReturn 0x%08X", UInt32(bitPattern: status)))
            }
            offset += chunk.count
        }
    }

    // MARK: Steps

    private func serviceRecord() async throws -> IOBluetoothSDPServiceRecord {
        let target = SDPQueryTarget()
        if device.performSDPQuery(target) == kIOReturnSuccess {
            _ = await waitUntil(timeout: .seconds(8)) { target.completion != nil }
        }
        // Fall back to cached records when the query does not call back.
        for uuid in serviceUUIDs {
            if let sdpUUID = ClassicInspector.sdpUUID(uuid), let record = device.getServiceRecord(for: sdpUUID) { return record }
        }
        throw TransportError.serviceNotFound(serviceUUIDs.joined(separator: " / "))
    }

    private func channelID(of record: IOBluetoothSDPServiceRecord) throws -> BluetoothRFCOMMChannelID {
        let api = ClassicInspector.rfcommChannel(record)
        let parsed = record.getAttributeDataElement(BluetoothSDPServiceAttributeID(SDPAttributeID.protocolDescriptorList))
            .flatMap { SDPParsing.rfcommChannel(fromProtocolDescriptorList: ClassicInspector.convert($0)) }
        if let api, let parsed, api != parsed {
            logger.warning("RFCOMM channel mismatch: API \(api) vs record \(parsed); using the record")
        }
        guard let channel = parsed ?? api else { throw TransportError.serviceNotFound("RFCOMM channel for \(serviceUUIDs.joined(separator: " / "))") }
        return channel
    }

    private func openChannel(_ channelID: BluetoothRFCOMMChannelID) async throws {
        var opened: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
        guard status == kIOReturnSuccess, let opened else {
            throw TransportError.openFailed(String(format: "openRFCOMMChannelAsync returned 0x%08X", UInt32(bitPattern: status)))
        }
        channel = opened
        // The completion callback is unreliable on some macOS builds; also accept isOpen().
        let done = await waitUntil(timeout: .seconds(10)) { self.openCompletion != nil || opened.isOpen() }
        if let completion = openCompletion, completion != kIOReturnSuccess, !opened.isOpen() {
            _ = opened.setDelegate(nil)
            _ = opened.close()
            channel = nil
            throw TransportError.openFailed(String(format: "open completed with 0x%08X", UInt32(bitPattern: completion)))
        }
        guard done, opened.isOpen() else {
            _ = opened.setDelegate(nil)
            _ = opened.close()
            channel = nil
            throw TransportError.timeout("opening RFCOMM channel \(channelID)")
        }
    }

    private func received(_ data: Data) {
        guard !finished else { return }
        incomingContinuation.yield(data)
    }

    private func finish(_ final: TransportState) {
        guard !finished else { return }
        finished = true
        stateContinuation.yield(final)
        stateContinuation.finish()
        incomingContinuation.finish()
    }

    private func channelClosedByRemote() {
        channel = nil
        finish(.disconnected(reason: "channel closed by the earbuds"))
    }

    private func openCompleted(_ status: IOReturn) {
        openCompletion = status
    }

    /// Runs `body` on the main actor, synchronously when already on the main thread so that the
    /// order of data callbacks is preserved.
    private nonisolated func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(body) }
        }
    }
}

extension RFCOMMTransport: IOBluetoothRFCOMMChannelDelegate {
    public nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        // Copy inside the callback: the buffer is only valid for its duration.
        let data = Data(bytes: dataPointer, count: dataLength)
        onMain { self.received(data) }
    }

    public nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        onMain { self.openCompleted(error) }
    }

    public nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        onMain { self.channelClosedByRemote() }
    }
}
