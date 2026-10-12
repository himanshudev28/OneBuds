import Foundation
import IOBluetooth
import OneBudsBluetooth
import OneBudsCore
import OneBudsDiagnostics
import OneBudsProtocol

/// Phase B active probe, approved by the owner on 2026-10-12. It sends exactly:
/// handshake `0x0100`, product id `0x0103`, firmware `0x0105`, battery `0x0106` (all queries),
/// and answers the buds' `0x0500` time request with the current time. Nothing else is sent;
/// other buds→host requests are logged and left unanswered.
@MainActor
final class SessionProbe {
    enum Route: String { case rfcomm, ble }

    private let deviceName: String
    private let routes: [Route]
    private let redactor: Redactor
    private var knownAddresses: [String] = []
    private var lines: [String] = []
    private let clock = ContinuousClock()
    private let started: ContinuousClock.Instant
    private var decoder = OPOFrameDecoder()
    private var received: [OPOFrame] = []
    private var transport: (any EarbudTransport)?
    private var sequence: UInt8 = 0
    private var summary: [String] = []

    init(deviceName: String, routes: [Route], redactor: Redactor) {
        self.deviceName = deviceName
        self.routes = routes
        self.redactor = redactor
        started = clock.now
    }

    func run() async -> String {
        log("ACTIVE session probe (approved 2026-10-12). Allowed frames: 0x0100, 0x0103, 0x0105, 0x0106 queries; 0x8500 time reply.")
        let paired = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
        knownAddresses = paired.compactMap(\.addressString)

        for route in routes {
            decoder = OPOFrameDecoder()
            received = []
            let replied = await attempt(route, paired: paired)
            summary.append("\(route.rawValue): \(replied ? "earbuds REPLIED to queries" : "no replies")")
            if replied { break }
        }
        return (["OneBuds Phase B session probe", "summary: " + summary.joined(separator: " · "), ""] + lines).joined(separator: "\n") + "\n"
    }

    // MARK: One route

    private func attempt(_ route: Route, paired: [IOBluetoothDevice]) async -> Bool {
        log("── route \(route.rawValue) ──")
        let transport: any EarbudTransport
        switch route {
        case .rfcomm:
            guard let device = paired.first(where: { $0.name == deviceName && $0.isConnected() }) else {
                log("no connected classic device named \"\(deviceName)\"")
                return false
            }
            log("device \(device.name ?? "") \(redactor.address(device.addressString) ?? "")")
            transport = RFCOMMTransport(device: device, serviceUUIDs: [KnownUUIDs.opoService, KnownUUIDs.serialPort])
        case .ble:
            transport = BLETransport(target: .init(name: deviceName, serviceUUID: KnownUUIDs.opoService,
                                                   writeUUID: KnownUUIDs.opoWrite, notifyUUID: KnownUUIDs.opoNotify))
        }
        self.transport = transport

        let stateTask = Task { @MainActor in
            for await state in transport.state { self.log("STATE \(state)") }
        }
        let rxTask = Task { @MainActor in
            for await data in transport.incoming { self.handle([UInt8](data)) }
        }
        defer { stateTask.cancel(); rxTask.cancel() }

        do {
            try await transport.connect()
        } catch {
            log("OPEN FAILED: \(error.localizedDescription)")
            return false
        }
        if let rfcomm = transport as? RFCOMMTransport { log("OPEN \(rfcomm.channelDescription ?? "")") }
        if let ble = transport as? BLETransport { log("OPEN BLE via \(ble.discoveryPath ?? "?"); notifications enabled on 0200079A") }

        log("listening 2 s before sending anything…")
        try? await Task.sleep(for: .seconds(2))

        var anyReply = false
        let handshake = await query(OPOCommand.handshake)
        anyReply = anyReply || handshake != nil
        if let handshake, let bits = OPOReplyParser.capabilityBits(handshake.payload) {
            log("   decode (Hypothesis): capability bits \(bits.map(String.init).joined(separator: ","))")
        }
        if let reply = await query(OPOCommand.productID) {
            anyReply = true
            log("   decode (Hypothesis): product id \(OPOReplyParser.productID(reply.payload) ?? "unparsed") (HeyMelody list: OnePlus Buds 3 = 063C14)")
        }
        if let reply = await query(OPOCommand.firmware) {
            anyReply = true
            log("   decode (Hypothesis): firmware \(OPOReplyParser.firmware(reply.payload).map { "count \($0.count), \"\($0.text)\"" } ?? "unparsed")")
        }
        if let reply = await query(OPOCommand.battery) {
            anyReply = true
            let text = OPOReplyParser.battery(reply.payload)?.map { level in
                let name = [1: "L", 2: "R", 3: "case"][Int(level.component)] ?? "#\(level.component)"
                return "\(name) \(level.percent)%\(level.isCharging ? " charging" : "")"
            }.joined(separator: ", ")
            log("   decode (Hypothesis): battery \(text ?? "unparsed")")
        }

        log("listening 3 s for unsolicited frames…")
        try? await Task.sleep(for: .seconds(3))
        await transport.disconnect()
        log("CLOSED by probe")
        return anyReply
    }

    // MARK: Frames

    private func query(_ command: UInt16) async -> OPOFrame? {
        sequence = sequence &+ 1
        if sequence == 0 || sequence == 0xFF { sequence = 1 }
        let frame = OPOFrame(command: command, sequence: sequence)
        let seq = sequence
        guard send(frame, note: OPOCommand.describe(command)) else { return nil }
        let expected = command | OPOCommand.replyBit
        let gotReply = await waitUntil(timeout: .milliseconds(2500)) { self.received.contains { $0.command == expected } }
        guard gotReply, let reply = received.last(where: { $0.command == expected }) else {
            log("   no reply to \(String(format: "0x%04X", command)) within 2.5 s")
            return nil
        }
        if reply.sequence != seq { log(String(format: "   note: reply sequence 0x%02X differs from request 0x%02X", reply.sequence, seq)) }
        return reply
    }

    @discardableResult
    private func send(_ frame: OPOFrame, note: String) -> Bool {
        guard let transport else { return false }
        let bytes = frame.encoded()
        log(String(format: "TX 0x%04X seq=%02X %@  [%@]", frame.command, frame.sequence, note, Hex.string(bytes)))
        Task { @MainActor in
            do { try await transport.send(Data(bytes)) } catch { self.log("   send failed: \(error.localizedDescription)") }
        }
        return true
    }

    private func handle(_ bytes: [UInt8]) {
        // Raw chunks may contain the multi-device list (other devices' names and addresses), so
        // only decoded, redacted frames are logged.
        log("RX \(bytes.count) bytes")
        for event in decoder.append(bytes) {
            switch event {
            case .discarded(let junk, let reason):
                log("   discarded \(junk.count) bytes: \(reason)")
            case .frame(let frame):
                received.append(frame)
                let shown = OPORedaction.containsPersonalData(frame) && redactor.enabled
                    ? "<redacted: lists other devices' names and addresses>"
                    : redactor.payloadHex(frame.payload, knownAddresses: knownAddresses)
                log(String(format: "   frame 0x%04X seq=%02X ctrl=%02X %@ payload(%d)=[%@]", frame.command, frame.sequence, frame.control,
                           OPOCommand.describe(frame.command), frame.payload.count, shown))
                if frame.command == OPOCommand.timeRequest {
                    send(TimeReply.frame(answering: frame, now: Date()), note: "time reply (approved)")
                } else if !frame.isReply, frame.command >> 8 == 0x05 {
                    log("   buds→host request not answered (not in the approved probe)")
                }
            }
        }
    }

    private func log(_ message: String) {
        let elapsed = (clock.now - started).seconds
        let line = String(format: "+%7.3fs  ", elapsed) + message
        lines.append(line)
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
