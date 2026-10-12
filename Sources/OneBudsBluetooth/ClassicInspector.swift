import Foundation
import IOBluetooth
import OneBudsCore
import OneBudsDiagnostics

/// Read-only inspection of paired classic Bluetooth devices through IOBluetooth.
/// The only traffic it can cause is an SDP query (standard service discovery) to a candidate
/// that is already connected; it never opens an RFCOMM channel.
@MainActor
public final class ClassicInspector {
    private let options: InspectionOptions
    private let redactor: Redactor
    /// Raw addresses of every paired device, used only to mask them inside BLE advertisement payloads.
    public private(set) var pairedAddresses: [String] = []

    public init(options: InspectionOptions, redactor: Redactor) {
        self.options = options
        self.redactor = redactor
    }

    public func inspect() async -> (ProbeReport.ClassicSection, [String]) {
        var section = ProbeReport.ClassicSection()
        var limitations: [String] = []

        let paired = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
        section.pairedDeviceCount = paired.count
        pairedAddresses = paired.compactMap(\.addressString)
        if paired.isEmpty {
            limitations.append("IOBluetoothDevice.pairedDevices() returned no devices. Either nothing is paired or Bluetooth access is not granted to this app.")
        }

        var notConnected: [String] = []
        for device in paired {
            let isCandidate = CandidateFilter.matches(device.name, pattern: options.namePattern)
            var entry = ProbeReport.ClassicDevice(
                name: isCandidate ? device.name : "<non-candidate device>",
                address: isCandidate ? redactor.address(device.addressString) : nil,
                isCandidate: isCandidate,
                isConnected: device.isConnected(),
                isPaired: device.isPaired(),
                classOfDevice: device.classOfDevice,
                majorClass: device.deviceClassMajor,
                minorClass: device.deviceClassMinor)

            if isCandidate {
                if !device.isConnected() { notConnected.append(device.name ?? "candidate") }
                entry.sdpRefresh = await refreshSDP(device, limitations: &limitations)
                entry.lastServicesUpdate = device.getLastServicesUpdate()
                entry.services = (device.services ?? []).compactMap { $0 as? IOBluetoothSDPServiceRecord }.map(Self.record)
                entry.vendorLookups = [KnownUUIDs.opoService, KnownUUIDs.opoLegacyService, KnownUUIDs.serialPort]
                    .map { Self.lookup($0, on: device) }
                if entry.services.isEmpty && device.isConnected() {
                    limitations.append("\(device.name ?? "candidate") is connected but has no SDP records, so its RFCOMM services are unknown.")
                }
            }
            section.devices.append(entry)
        }
        if !notConnected.isEmpty {
            limitations.append("Not connected, so SDP was not refreshed and only cached records (often none) are shown: \(notConnected.joined(separator: ", ")).")
        }
        // Observed 2026-10-12: getLastServicesUpdate() returned the probe's run time for every device,
        // connected or not, so it is recorded but never used as evidence of a fresh SDP query.
        section.devices.sort { ($0.isCandidate ? 0 : 1, $0.name ?? "") < ($1.isCandidate ? 0 : 1, $1.name ?? "") }
        return (section, limitations)
    }

    // MARK: SDP refresh

    private func refreshSDP(_ device: IOBluetoothDevice, limitations: inout [String]) async -> ProbeReport.SDPRefresh {
        guard options.sdpRefresh else {
            return .init(attempted: false, outcome: "disabled by --no-sdp-refresh", seconds: 0)
        }
        // Querying a device that is not connected would page it; the probe does not do that.
        guard device.isConnected() else {
            return .init(attempted: false, outcome: "device not connected; cached records only", seconds: 0)
        }
        let target = SDPQueryTarget()
        let clock = ContinuousClock()
        let start = clock.now
        // The UUID-filtered variant is unreliable since macOS 13 (ProtocolSources §8), so query everything.
        let status = device.performSDPQuery(target)
        guard status == kIOReturnSuccess else {
            return .init(attempted: true, outcome: String(format: "performSDPQuery failed immediately (IOReturn 0x%08X)", UInt32(bitPattern: status)),
                         seconds: (clock.now - start).seconds)
        }
        _ = await waitUntil(timeout: .seconds(12)) { target.completion != nil }
        let elapsed = (clock.now - start).seconds
        if let code = target.completion {
            let outcome = code == kIOReturnSuccess ? "completed" : String(format: "completed with IOReturn 0x%08X", UInt32(bitPattern: code))
            return .init(attempted: true, outcome: outcome, seconds: elapsed)
        }
        limitations.append("SDP query to \(device.name ?? "candidate") sent no completion callback within 12 s; the records shown may be cached rather than fresh.")
        return .init(attempted: true, outcome: "no completion callback within 12 s; records may be cached", seconds: elapsed)
    }

    // MARK: Conversion

    nonisolated private static func lookup(_ uuid: String, on device: IOBluetoothDevice) -> ProbeReport.VendorLookup {
        guard let sdpUUID = sdpUUID(uuid), let record = device.getServiceRecord(for: sdpUUID) else {
            return .init(uuid: uuid, found: false, rfcommChannel: nil, serviceName: nil)
        }
        return .init(uuid: uuid, found: true, rfcommChannel: rfcommChannel(record), serviceName: record.getServiceName())
    }

    nonisolated private static func record(_ record: IOBluetoothSDPServiceRecord) -> ProbeReport.SDPRecord {
        let attributes: [ProbeReport.SDPAttribute] = (record.attributes ?? [:]).compactMap { key, value in
            guard let id = (key.base as? NSNumber)?.uint16Value, let element = value as? IOBluetoothSDPDataElement else { return nil }
            return .init(id: id, value: convert(element))
        }.sorted { $0.id < $1.id }
        let value = { (id: UInt16) in attributes.first { $0.id == id }?.value }
        let protocols = value(SDPAttributeID.protocolDescriptorList)
        return .init(serviceName: record.getServiceName(),
                     serviceClassUUIDs: SDPParsing.serviceClassUUIDs(value(SDPAttributeID.serviceClassIDList)),
                     rfcommChannelAPI: rfcommChannel(record),
                     rfcommChannelParsed: SDPParsing.rfcommChannel(fromProtocolDescriptorList: protocols),
                     l2capPSM: SDPParsing.l2capPSM(fromProtocolDescriptorList: protocols),
                     attributes: attributes)
    }

    nonisolated static func rfcommChannel(_ record: IOBluetoothSDPServiceRecord) -> UInt8? {
        var channel: BluetoothRFCOMMChannelID = 0
        return record.getRFCOMMChannelID(&channel) == kIOReturnSuccess ? channel : nil
    }

    nonisolated static func sdpUUID(_ canonical: String) -> IOBluetoothSDPUUID? {
        guard let bytes = Hex.bytes(canonical.replacingOccurrences(of: "-", with: "")) else { return nil }
        return bytes.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: bytes.count) }
    }

    nonisolated static func convert(_ element: IOBluetoothSDPDataElement) -> SDPValue {
        let size = Int(element.getSize())
        switch Int(element.getTypeDescriptor()) {
        case kBluetoothSDPDataElementTypeNil:
            return .null
        case kBluetoothSDPDataElementTypeUnsignedInt:
            if size <= 8, let number = element.getNumberValue() { return .unsignedInt(number.uint64Value, bytes: size) }
            return .wideInt(hex: Hex.string(rawBytes(element), separator: ""), signed: false)
        case kBluetoothSDPDataElementTypeSignedInt:
            if size <= 8, let number = element.getNumberValue() { return .signedInt(number.int64Value, bytes: size) }
            return .wideInt(hex: Hex.string(rawBytes(element), separator: ""), signed: true)
        case kBluetoothSDPDataElementTypeUUID:
            guard let uuid = element.getUUIDValue() else { return .unknown(typeDescriptor: 3) }
            let bytes = [UInt8](Data(referencing: uuid))
            return .uuid(BluetoothUUID.canonical(fromBytes: bytes) ?? Hex.string(bytes, separator: ""))
        case kBluetoothSDPDataElementTypeString:
            if let string = element.getStringValue() { return .string(string) }
            return .string("<undecodable: \(Hex.string(rawBytes(element)))>")
        case kBluetoothSDPDataElementTypeBoolean:
            return .bool(element.getNumberValue()?.boolValue ?? false)
        case kBluetoothSDPDataElementTypeDataElementSequence:
            return .sequence(children(element))
        case kBluetoothSDPDataElementTypeDataElementAlternative:
            return .alternative(children(element))
        case kBluetoothSDPDataElementTypeURL:
            return .url(element.getStringValue() ?? Hex.string(rawBytes(element)))
        case let other:
            return .unknown(typeDescriptor: other)
        }
    }

    nonisolated private static func children(_ element: IOBluetoothSDPDataElement) -> [SDPValue] {
        (element.getArrayValue() ?? []).compactMap { ($0 as? IOBluetoothSDPDataElement).map(convert) }
    }

    nonisolated private static func rawBytes(_ element: IOBluetoothSDPDataElement) -> [UInt8] {
        element.getDataValue().map { [UInt8]($0) } ?? []
    }
}

/// Receives IOBluetooth's informal `sdpQueryComplete:status:` callback.
final class SDPQueryTarget: NSObject, @unchecked Sendable {
    // Written from the IOBluetooth callback, read by the main-actor poller.
    private let lock = NSLock()
    private var _completion: IOReturn?

    var completion: IOReturn? { lock.withLock { _completion } }

    @objc(sdpQueryComplete:status:)
    func sdpQueryComplete(_ device: IOBluetoothDevice?, status: IOReturn) {
        lock.withLock { _completion = status }
    }
}
