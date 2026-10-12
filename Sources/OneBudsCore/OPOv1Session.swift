import Foundation
import OneBudsProtocol
import os

/// A control session with one pair of earbuds. Implementations depend only on `EarbudTransport`.
public protocol EarbudProtocol: Sendable {
    init(transport: any EarbudTransport, profile: DeviceProfile)
    /// Handshake, identification and (where the profile allows) event subscription.
    func startSession() async throws
    /// Capabilities the profile rates Verified or Experimental.
    func capabilities() -> Set<Capability>
    func perform(_ command: EarbudCommand) async throws -> EarbudResponse
    /// Unsolicited changes (battery, mode changed on the buds or from the phone), raw packets, and the end of the session.
    var events: AsyncStream<EarbudEvent> { get }
    func currentDeviceInfo() async -> DeviceInfo
    /// Raw packet events are produced only while enabled (formatting every frame costs CPU).
    func setPacketLogging(_ enabled: Bool) async
    func end() async
}

/// OPOv1 / HeyMelody headset protocol over any transport (ProtocolSources §4–§6).
///
/// - One outstanding request per command type; replies are matched on `command | 0x8000` and the
///   echoed sequence number (late replies to timed-out requests are dropped).
/// - Every request has a timeout and fails with `ProtocolError.timeout`.
/// - A disconnect fails every outstanding request with `ProtocolError.disconnected`.
/// - Settings are only reported as applied after a read-back confirms them.
public actor OPOv1Session: EarbudProtocol {
    public nonisolated let events: AsyncStream<EarbudEvent>
    private let eventContinuation: AsyncStream<EarbudEvent>.Continuation
    private let transport: any EarbudTransport
    private nonisolated let profile: DeviceProfile
    private let replyTimeout: Duration
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.local.onebuds", category: "opo")

    private struct Pending {
        let sequence: UInt8
        var continuation: CheckedContinuation<OPOFrame, Error>?
        var early: Result<OPOFrame, Error>?
    }

    private var decoder = OPOFrameDecoder()
    private var sequence: UInt8 = 0
    private var pending: [UInt16: Pending] = [:]
    private var busyCommands: Set<UInt16> = []
    private var commandWaiters: [UInt16: [CheckedContinuation<Void, Never>]] = [:]
    private var readers: [Task<Void, Never>] = []
    private var started = false
    private var ended = false
    private var endReason: String?
    private var deviceInfo = DeviceInfo()
    private var packetLogging = false

    public init(transport: any EarbudTransport, profile: DeviceProfile) {
        self.init(transport: transport, profile: profile, replyTimeout: .milliseconds(2500), now: { Date() })
    }

    public init(transport: any EarbudTransport, profile: DeviceProfile, replyTimeout: Duration, now: @escaping @Sendable () -> Date) {
        self.transport = transport
        self.profile = profile
        self.replyTimeout = replyTimeout
        self.now = now
        (events, eventContinuation) = AsyncStream.makeStream(of: EarbudEvent.self)
    }

    public nonisolated func capabilities() -> Set<Capability> {
        Set(Capability.allCases.filter { [.verified, .experimental].contains(profile.support($0)) })
    }

    public func currentDeviceInfo() -> DeviceInfo { deviceInfo }

    public func setPacketLogging(_ enabled: Bool) { packetLogging = enabled }

    // MARK: Session

    public func startSession() async throws {
        guard let parameters = profile.opo else { throw ProtocolError.unsupported("no OPOv1 parameters for \(profile.displayName)") }
        startReading()
        // Documented init pacing (S4): ~300 ms before the first frame.
        try? await Task.sleep(for: .milliseconds(300))

        // Some realme clients skip the handshake (S15), so its absence is tolerated; the product-id
        // check below is what gates the session.
        if let hello = try? await request(OPOCommand.handshake) {
            deviceInfo.capabilityBits = OPOReplyParser.capabilityBits(hello.payload) ?? []
        }

        let product = try await request(OPOCommand.productID)
        let productID = OPOReplyParser.productID(product.payload)
        deviceInfo.productID = productID
        if !parameters.productIDs.isEmpty, !(productID.map(parameters.productIDs.contains) ?? false) {
            throw ProtocolError.profileMismatch(expected: parameters.productIDs, found: productID)
        }

        if let firmware = try? await request(OPOCommand.firmware), let parsed = OPOReplyParser.firmware(firmware.payload) {
            deviceInfo.firmwareRaw = parsed.text
            deviceInfo.firmware = DeviceInfo.parseFirmware(parsed.text)
        }
        if parameters.subscribesToEvents { await subscribeToEvents() }
        started = true
    }

    public func end() async {
        guard !ended else { return }
        await transport.disconnect()
        finishSession(reason: "closed by OneBuds")
    }

    private func subscribeToEvents() async {
        // 0x0200 → 00 <count> <event ids>; subscribe with 0x0205 <count> <ids> (S4, S10). Ids ≥ 0xF0 are diagnostic.
        guard let offered = try? await request(0x0200), offered.payload.count >= 2, offered.payload[0] == 0x00 else { return }
        let count = Int(offered.payload[1])
        let ids = Array(offered.payload.dropFirst(2).prefix(count)).filter { $0 < 0xF0 }
        guard !ids.isEmpty else { return }
        _ = try? await request(0x0205, payload: [UInt8(ids.count)] + ids)
    }

    // MARK: Commands

    public func perform(_ command: EarbudCommand) async throws -> EarbudResponse {
        guard started else { throw ProtocolError.sessionNotStarted }
        guard let parameters = profile.opo else { throw ProtocolError.unsupported("OPOv1") }
        switch command {
        case .readBattery:
            let reply = try await request(OPOCommand.battery)
            guard let levels = OPOReplyParser.battery(reply.payload) else { throw ProtocolError.malformedReply(command: OPOCommand.battery) }
            return .battery(BatteryStatus(levels: levels))

        case .readNoiseControl:
            return .noiseControl(try await readNoiseControl(parameters))

        case .setNoiseControl(let mode):
            guard let option = parameters.noiseModes.first(where: { $0.mode == mode }) else {
                throw ProtocolError.unsupported("noise mode \(mode.displayName)")
            }
            try await acknowledged(0x0404, payload: [0x01, 0x01] + option.setMask)
            let actual = try await readNoiseControl(parameters)
            let matches: Bool = switch mode {
            case .noiseCancelling(nil): actual.category == .noiseCancelling
            default: actual == mode
            }
            guard matches else { throw ProtocolError.notApplied(expected: mode.displayName, actual: actual.displayName) }
            return .noiseControl(actual)

        case .readEqualizer:
            return .equalizer(presetID: try await readEqualizer())

        case .setEqualizer(let presetID):
            guard parameters.equalizerPresets.contains(where: { $0.id == presetID }) else {
                throw ProtocolError.unsupported("EQ preset \(presetID)")
            }
            try await acknowledged(0x0406, payload: [presetID])
            let actual = try await readEqualizer()
            guard actual == presetID else { throw ProtocolError.notApplied(expected: "preset \(presetID)", actual: "preset \(actual)") }
            return .equalizer(presetID: actual)

        case .readFeatures(let ids):
            return .features(try await readFeatures(ids.filter(parameters.featureStatusIDs.contains)))

        case .setFeature(let id, let enabled):
            guard parameters.writableFeatureIDs.contains(id) else {
                throw ProtocolError.unsupported(String(format: "feature 0x%02X", id))
            }
            try await acknowledged(0x0403, payload: [id, enabled ? 0x01 : 0x00])
            let values = try await readFeatures([id])
            guard values[id] == enabled else {
                throw ProtocolError.notApplied(expected: enabled ? "on" : "off", actual: values[id].map { $0 ? "on" : "off" } ?? "no value")
            }
            return .features(values)

        case .readGestures:
            return .gestures(try await readGestures())

        case .setGestures(let bindings):
            for binding in bindings {
                guard parameters.gestureFunctions[binding.action]?.contains(binding.function) == true else {
                    throw ProtocolError.unsupported("\(parameters.functionName(binding.function)) for this gesture")
                }
            }
            try await acknowledged(0x0401, payload: [UInt8(bindings.count)] + bindings.flatMap(\.bytes))
            let actual = try await readGestures()
            let missing = bindings.filter { wanted in
                !actual.contains { $0.side == wanted.side && $0.button == wanted.button && $0.action == wanted.action && $0.function == wanted.function }
            }
            guard missing.isEmpty else { throw ProtocolError.notApplied(expected: "new gesture", actual: "previous gesture") }
            return .gestures(actual)

        case .readDeviceInfo:
            let product = try await request(OPOCommand.productID)
            deviceInfo.productID = OPOReplyParser.productID(product.payload) ?? deviceInfo.productID
            if let firmware = try? await request(OPOCommand.firmware), let parsed = OPOReplyParser.firmware(firmware.payload) {
                deviceInfo.firmwareRaw = parsed.text
                deviceInfo.firmware = DeviceInfo.parseFirmware(parsed.text)
            }
            return .deviceInfo(deviceInfo)
        }
    }

    private func readNoiseControl(_ parameters: OPOParameters) async throws -> NoiseControlMode {
        // 0x010C 01 01 → 00 01 01 <LO> <HI>
        let reply = try await request(0x010C, payload: [0x01, 0x01])
        let p = reply.payload
        guard p.count >= 4, p[0] == 0x00 else { throw ProtocolError.malformedReply(command: 0x010C) }
        let value = Self.noiseValue(p, at: 3)
        guard let mode = noiseMode(forRead: value, parameters) else {
            throw ProtocolError.unrecognisedValue(String(format: "noise control 0x%04X", value))
        }
        return mode
    }

    private func readEqualizer() async throws -> UInt8 {
        let reply = try await request(0x010F)
        guard reply.payload.count >= 2, reply.payload[0] == 0x00 else { throw ProtocolError.malformedReply(command: 0x010F) }
        return reply.payload[1]
    }

    private func readFeatures(_ ids: [UInt8]) async throws -> [UInt8: Bool] {
        guard !ids.isEmpty else { return [:] }
        // 0x010D <n> <ids> → 00 <n> [<id> <value>]…
        let reply = try await request(0x010D, payload: [UInt8(ids.count)] + ids)
        let p = reply.payload
        guard p.count >= 2, p[0] == 0x00, p.count >= 2 + Int(p[1]) * 2 else { throw ProtocolError.malformedReply(command: 0x010D) }
        var values: [UInt8: Bool] = [:]
        for index in 0..<Int(p[1]) { values[p[2 + index * 2]] = p[3 + index * 2] != 0 }
        return values
    }

    private func readGestures() async throws -> [GestureBinding] {
        // 0x0108 → <status> <count> [dev btn act fn]…
        let reply = try await request(0x0108)
        let p = reply.payload
        guard p.count >= 2, p[0] == 0x00, p.count >= 2 + Int(p[1]) * 4 else { throw ProtocolError.malformedReply(command: 0x0108) }
        return (0..<Int(p[1])).map { index in
            let base = 2 + index * 4
            return GestureBinding(side: p[base], button: p[base + 1], action: p[base + 2], function: p[base + 3])
        }
    }

    private func acknowledged(_ command: UInt16, payload: [UInt8]) async throws {
        let reply = try await request(command, payload: payload)
        guard let status = reply.payload.first else { throw ProtocolError.malformedReply(command: command) }
        guard status == 0x00 else { throw ProtocolError.rejected(command: command, status: status) }
    }

    /// Noise values are 2 bytes LE on OnePlus/OPPO and may be 1 byte on realme (S10, S12).
    static func noiseValue(_ bytes: [UInt8], at index: Int) -> UInt16 {
        UInt16(bytes[index]) | (bytes.count > index + 1 ? UInt16(bytes[index + 1]) << 8 : 0)
    }

    private nonisolated func noiseMode(forRead value: UInt16, _ parameters: OPOParameters) -> NoiseControlMode? {
        parameters.noiseModes.first { $0.readValue == value }?.mode
    }

    // MARK: Request/reply machinery

    func request(_ command: UInt16, payload: [UInt8] = []) async throws -> OPOFrame {
        while busyCommands.contains(command) {
            await withCheckedContinuation { commandWaiters[command, default: []].append($0) }
        }
        guard !ended else { throw ProtocolError.disconnected(endReason) }
        busyCommands.insert(command)
        defer { releaseCommand(command) }

        let sequence = nextSequence()
        let key = command | OPOCommand.replyBit
        pending[key] = Pending(sequence: sequence)
        do {
            try await write(OPOFrame(command: command, sequence: sequence, payload: payload))
        } catch {
            pending[key] = nil
            throw error
        }
        let timeout = replyTimeout
        return try await withCheckedThrowingContinuation { continuation in
            guard var entry = pending[key], entry.sequence == sequence else {
                continuation.resume(throwing: ProtocolError.disconnected(endReason))
                return
            }
            if let early = entry.early {
                pending[key] = nil
                continuation.resume(with: early)
                return
            }
            entry.continuation = continuation
            pending[key] = entry
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.expire(key: key, sequence: sequence, command: command)
            }
        }
    }

    private func releaseCommand(_ command: UInt16) {
        busyCommands.remove(command)
        if var waiters = commandWaiters[command], !waiters.isEmpty {
            let next = waiters.removeFirst()
            commandWaiters[command] = waiters
            next.resume()
        }
    }

    private func expire(key: UInt16, sequence: UInt8, command: UInt16) {
        guard let entry = pending[key], entry.sequence == sequence, let continuation = entry.continuation else { return }
        pending[key] = nil
        logger.notice("Timeout waiting for \(String(format: "0x%04X", key), privacy: .public)")
        continuation.resume(throwing: ProtocolError.timeout(command: command))
    }

    private func nextSequence() -> UInt8 {
        // 0xFF marks unsolicited pushes (S4), so it is never used for requests.
        sequence = sequence >= 0xFE ? 1 : sequence + 1
        return sequence
    }

    private func write(_ frame: OPOFrame) async throws {
        let bytes = frame.encoded()
        if packetLogging { emitPacket(.sent, frame: frame, bytes: bytes) }
        try await transport.send(Data(bytes))
    }

    // MARK: Receiving

    private func startReading() {
        let transport = self.transport
        readers.append(Task { [weak self] in
            for await state in transport.state {
                switch state {
                case .disconnected(let reason): await self?.noteEndReason(reason)
                case .failed(let reason): await self?.noteEndReason(reason)
                default: break
                }
            }
        })
        readers.append(Task { [weak self] in
            for await data in transport.incoming { await self?.receive([UInt8](data)) }
            // Give the state stream a moment to report why the link ended.
            try? await Task.sleep(for: .milliseconds(50))
            await self?.finishSession(reason: nil)
        })
    }

    private func noteEndReason(_ reason: String?) {
        if endReason == nil { endReason = reason }
    }

    func receive(_ bytes: [UInt8]) async {
        for event in decoder.append(bytes) {
            switch event {
            case .discarded(let junk, let reason):
                logger.debug("Discarded \(junk.count) bytes: \(reason, privacy: .public)")
                if packetLogging {
                    eventContinuation.yield(.packet(PacketLogEntry(direction: .received, summary: "discarded: \(reason)", hex: hex(junk))))
                }
            case .frame(let frame):
                if packetLogging {
                    emitPacket(.received, frame: frame, bytes: OPORedaction.containsPersonalData(frame) ? nil : frame.encoded())
                }
                await handle(frame)
            }
        }
    }

    private func handle(_ frame: OPOFrame) async {
        if frame.isReply, var entry = pending[frame.command] {
            // The buds echo the request sequence (observed on OnePlus Buds 3). A mismatch is a late
            // reply to an earlier, timed-out request and must not answer the current one.
            guard frame.sequence == entry.sequence else {
                logger.notice("Dropped late reply \(String(format: "0x%04X seq %02X", frame.command, frame.sequence), privacy: .public)")
                return
            }
            if let continuation = entry.continuation {
                pending[frame.command] = nil
                continuation.resume(returning: frame)
            } else {
                entry.early = .success(frame)
                pending[frame.command] = entry
            }
            return
        }
        switch frame.command {
        case OPOCommand.timeRequest:
            if profile.opo?.answersTimeRequest == true {
                try? await write(TimeReply.frame(answering: frame, now: now()))
            }
        case 0x0204:
            handlePush(frame.payload)
        case 0x0504:
            if let id = frame.payload.first { eventContinuation.yield(.equalizer(presetID: id)) }
        default:
            break // logged as a packet; unknown buds→host requests are not answered
        }
    }

    private func handlePush(_ payload: [UInt8]) {
        guard let type = payload.first, let parameters = profile.opo else { return }
        switch type {
        case 0x01:
            // 01 <n> [<component> <raw>]…
            if let levels = OPOReplyParser.battery([0x00] + payload.dropFirst()) {
                eventContinuation.yield(.battery(BatteryStatus(levels: levels)))
            }
        case 0x02:
            // 02 <n> [<component> <status>]…
            guard payload.count >= 2, payload.count >= 2 + Int(payload[1]) * 2 else { return }
            var wear: [UInt8: UInt8] = [:]
            for index in 0..<Int(payload[1]) { wear[payload[2 + index * 2]] = payload[3 + index * 2] }
            eventContinuation.yield(.wear(wear))
        case 0x03:
            // 03 01 01 <LO> <HI>
            guard payload.count >= 4, payload[1] == 0x01 else { return }
            let value = Self.noiseValue(payload, at: 3)
            if let mode = noiseMode(forRead: value, parameters) { eventContinuation.yield(.noiseControl(mode)) }
        case 0x05:
            if let id = parameters.gameModeFeatureID, payload.count >= 2 {
                eventContinuation.yield(.feature(id: id, enabled: payload[1] != 0))
            }
        default:
            break
        }
    }

    private func finishSession(reason: String?) {
        guard !ended else { return }
        ended = true
        let finalReason = reason ?? endReason
        for (key, entry) in pending {
            if let continuation = entry.continuation {
                continuation.resume(throwing: ProtocolError.disconnected(finalReason))
                pending[key] = nil
            } else {
                pending[key]?.early = .failure(ProtocolError.disconnected(finalReason))
            }
        }
        for waiters in commandWaiters.values { waiters.forEach { $0.resume() } }
        commandWaiters = [:]
        readers.forEach { $0.cancel() }
        eventContinuation.yield(.sessionEnded(reason: finalReason))
        eventContinuation.finish()
    }

    private func emitPacket(_ direction: PacketLogEntry.Direction, frame: OPOFrame, bytes: [UInt8]?) {
        let summary = String(format: "0x%04X seq %02X %@", frame.command, frame.sequence, OPOCommand.describe(frame.command))
        let shown = bytes.map(hex) ?? "<\(frame.payload.count) bytes redacted: other devices' names and addresses>"
        eventContinuation.yield(.packet(PacketLogEntry(direction: direction, summary: summary, hex: shown)))
    }

    private nonisolated func hex(_ bytes: [UInt8]) -> String { FastHex.string(bytes) }
}
