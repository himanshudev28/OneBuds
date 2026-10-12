import Foundation
import Observation
import os

/// The single source of truth for the UI. All state reflects what the earbuds reported; a setting
/// changes here only after the earbuds confirm it (acknowledgement plus read-back), or when the
/// earbuds push a change made elsewhere (a button press, the phone app).
@MainActor
@Observable
public final class DeviceManager {
    public enum ConnectionState: Equatable, Sendable {
        case idle
        case searching
        case noDevice
        case connecting(TransportKind)
        case handshaking
        case connected
        /// A recognisable earbud whose model is not supported: diagnostics only.
        case unrecognised(name: String)
        case bluetoothOff
        case unauthorized
        case bluetoothUnsupported
        case failed(String)

        public var isConnected: Bool { self == .connected }

        public var isBusy: Bool {
            switch self {
            case .searching, .connecting, .handshaking: true
            default: false
            }
        }

        public var displayText: String {
            switch self {
            case .idle: "Not connected"
            case .searching: "Looking for earbuds…"
            case .noDevice: "No supported earbuds connected"
            case .connecting(let kind): "Connecting over \(kind == .rfcomm ? "Classic Bluetooth" : kind == .ble ? "Bluetooth LE" : "demo link")…"
            case .handshaking: "Starting session…"
            case .connected: "Connected"
            case .unrecognised(let name): "\(name) is not a supported model"
            case .bluetoothOff: "Bluetooth is off"
            case .unauthorized: "Bluetooth permission needed"
            case .bluetoothUnsupported: "Bluetooth is not available on this Mac"
            case .failed(let message): message
            }
        }
    }

    public enum Operation: Hashable, Sendable {
        case noiseControl, equalizer, gestures, refresh
        case feature(UInt8)
    }

    public enum OperationStatus: Equatable, Sendable {
        case idle
        case pending
        case confirmed(Date)
        case failed(String)
        case timedOut
    }

    // MARK: Observable state

    public private(set) var connection: ConnectionState = .idle
    public private(set) var earbuds: DiscoveredEarbuds?
    public private(set) var profile: DeviceProfile?
    public private(set) var transportKind: TransportKind?
    public private(set) var transportDetail: String?
    public private(set) var battery: BatteryStatus?
    public private(set) var noiseControl: NoiseControlMode?
    /// The mode being applied; the UI shows it as pending until the earbuds confirm.
    public private(set) var pendingNoiseControl: NoiseControlMode?
    public private(set) var equalizerPreset: UInt8?
    public private(set) var features: [UInt8: Bool] = [:]
    public private(set) var gestures: [GestureBinding] = []
    public private(set) var deviceInfo: DeviceInfo?
    public private(set) var wear: [UInt8: UInt8] = [:]
    public private(set) var operations: [Operation: OperationStatus] = [:]
    public private(set) var lastError: String?
    public private(set) var lastUpdated: Date?
    public private(set) var packetLog: [PacketLogEntry] = []
    public private(set) var isDemo: Bool

    /// Raw packet logging is opt-in (Diagnostics screen) and kept in memory only.
    public var isPacketLoggingEnabled = false {
        didSet {
            if !isPacketLoggingEnabled { packetLog = [] }
            let enabled = isPacketLoggingEnabled
            if let session { Task { await session.setPacketLogging(enabled) } }
        }
    }

    public static let packetLogLimit = 1000

    // MARK: Private

    private var connector: any DeviceConnector
    private let sessionFactory: (any EarbudTransport, DeviceProfile) -> any EarbudProtocol
    private var session: (any EarbudProtocol)?
    private var sessionID: UUID?
    private var eventTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    /// The connect attempt in flight, if any. Runs in its own task so it is never cancelled by the
    /// reconnect timer that started it.
    private var connectTask: Task<Void, Never>?
    /// Bumped by `disconnect()`/`useConnector()`; an in-flight connect with an older value aborts.
    private var generation = 0
    private var userDisconnected = false
    private var reconnectAttempt = 0
    private let reconnectDelays: [Duration]
    private let logger = Logger(subsystem: "com.local.onebuds", category: "manager")

    public init(connector: any DeviceConnector,
                reconnectDelays: [Duration] = [.seconds(1), .seconds(3), .seconds(10), .seconds(30), .seconds(120)],
                sessionFactory: @escaping (any EarbudTransport, DeviceProfile) -> any EarbudProtocol = { OPOv1Session(transport: $0, profile: $1) }) {
        self.connector = connector
        self.reconnectDelays = reconnectDelays
        self.sessionFactory = sessionFactory
        isDemo = connector.isDemo
    }

    // MARK: Capability presentation

    public func presentation(_ capability: Capability) -> CapabilityPresentation {
        guard connection.isConnected, let profile else { return .hidden }
        return profile.presentation(capability)
    }

    public func status(of operation: Operation) -> OperationStatus { operations[operation] ?? .idle }

    // MARK: Lifecycle

    /// Starts watching for devices and connects to the first supported one.
    public func start() {
        watchTask?.cancel()
        let changes = connector.deviceChanges()
        watchTask = Task { [weak self] in
            for await _ in changes {
                guard let self, !self.connection.isConnected, !self.userDisconnected else { continue }
                await self.connect(thorough: false)
            }
        }
        Task { await connect() }
    }

    /// - Parameter thorough: allow the BLE scan fallback (user-initiated connects and app start).
    ///   Automatic reconnects pass false and rely on connect notifications, to save energy.
    public func connect(thorough: Bool = true) async {
        if let running = connectTask {
            await running.value
            return
        }
        guard !connection.isConnected else { return }
        userDisconnected = false
        let task = Task { await self.performConnect(thorough: thorough) }
        connectTask = task
        await task.value
        connectTask = nil
    }

    private func performConnect(thorough: Bool) async {
        let attempt = generation
        let connector = self.connector
        /// False once the user disconnected or switched connector while this attempt was running.
        func isCurrent() -> Bool { attempt == generation && !userDisconnected }

        lastError = nil
        connection = .searching
        let availability = await connector.availability()
        guard isCurrent() else { return }
        switch availability {
        case .poweredOff: return fail(as: .bluetoothOff)
        case .unauthorized: return fail(as: .unauthorized)
        case .unsupported: return fail(as: .bluetoothUnsupported)
        case .ready, .unknown: break
        }

        let found = await connector.discover(thorough: thorough)
        guard isCurrent() else { return }
        guard let target = found.first(where: { $0.profile?.allowsControlSession == true }) ?? found.first else {
            resetDeviceState()
            connection = .noDevice
            scheduleReconnect()
            return
        }
        earbuds = target
        profile = target.profile
        guard let profile = target.profile, profile.allowsControlSession else {
            connection = .unrecognised(name: target.name)
            return
        }

        var lastFailure: String?
        for kind in Self.transportOrder(profile: profile, earbuds: target) {
            guard let transport = connector.makeTransport(for: target, kind: kind) else { continue }
            connection = .connecting(kind)
            do {
                try await transport.connect()
            } catch {
                guard isCurrent() else { return }
                lastFailure = error.localizedDescription
                logger.notice("Transport \(kind.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }
            guard isCurrent() else { await transport.disconnect(); return }
            transportKind = kind
            transportDetail = connector.describe(transport)

            let session = sessionFactory(transport, profile)
            self.session = session
            await session.setPacketLogging(isPacketLoggingEnabled)
            startEvents(from: session)
            connection = .handshaking
            do {
                try await session.startSession()
            } catch {
                // Detach first so the session's end event is ignored.
                if self.session.map({ $0 as AnyObject }) === (session as AnyObject) {
                    self.session = nil
                    sessionID = nil
                }
                eventTask?.cancel()
                await session.end()
                guard isCurrent() else { return }
                lastFailure = error.localizedDescription
                if case ProtocolError.profileMismatch = error {
                    // Wrong model: do not try other transports or send anything else.
                    resetDeviceState()
                    lastError = error.localizedDescription
                    connection = .failed(error.localizedDescription)
                    return
                }
                continue
            }
            guard isCurrent() else { await session.end(); return }
            deviceInfo = await session.currentDeviceInfo()
            guard isCurrent(), self.session != nil else { return }
            connection = .connected
            reconnectAttempt = 0
            await refresh()
            return
        }
        guard isCurrent() else { return }
        resetDeviceState()
        lastError = lastFailure
        connection = .failed(lastFailure ?? "Could not open a control channel to the earbuds.")
        scheduleReconnect()
    }

    public func disconnect() async {
        userDisconnected = true
        generation += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        let session = self.session
        self.session = nil
        sessionID = nil
        eventTask?.cancel()
        await session?.end()
        // Let an in-flight connect notice the new generation and clean up after itself.
        if let running = connectTask { await running.value }
        resetDeviceState()
        connection = .idle
    }

    /// Replaces the device source, e.g. when Demo mode is toggled. All state is reset first.
    public func useConnector(_ newConnector: any DeviceConnector) async {
        await disconnect()
        connector = newConnector
        isDemo = newConnector.isDemo
        userDisconnected = false
        start()
    }

    /// After sleep: forget unconfirmed operations and re-check the earbuds.
    public func handleWake() async {
        for (operation, status) in operations where status == .pending { operations[operation] = .idle }
        pendingNoiseControl = nil
        if connection.isConnected {
            await refresh()
        } else if !userDisconnected {
            await connect(thorough: false)
        }
    }

    // MARK: Reading

    public func refresh() async {
        guard let session, connection.isConnected, let profile else { return }
        let id = sessionID
        operations[.refresh] = .pending
        var successes = 0
        var timeouts = 0
        func read(_ command: EarbudCommand) async -> EarbudResponse? {
            do {
                let response = try await session.perform(command)
                successes += 1
                return response
            } catch ProtocolError.timeout {
                timeouts += 1
                return nil
            } catch {
                return nil
            }
        }
        func stillCurrent() -> Bool { sessionID == id && id != nil }

        if profile.presentation(.battery) != .hidden, case .battery(let value)? = await read(.readBattery), stillCurrent() {
            battery = value
        }
        if profile.presentation(.noiseControl) != .hidden, case .noiseControl(let mode)? = await read(.readNoiseControl), stillCurrent() {
            noiseControl = mode
        }
        if profile.presentation(.equalizer) != .hidden, case .equalizer(let preset)? = await read(.readEqualizer), stillCurrent() {
            equalizerPreset = preset
        }
        let featureIDs = featureIDs(for: profile)
        if !featureIDs.isEmpty, case .features(let values)? = await read(.readFeatures(featureIDs)), stillCurrent() {
            features.merge(values) { $1 }
        }
        if profile.presentation(.gestures) != .hidden, case .gestures(let bindings)? = await read(.readGestures), stillCurrent() {
            gestures = bindings
        }
        guard stillCurrent() else { return }
        if successes > 0 {
            lastUpdated = Date()
            operations[.refresh] = .confirmed(Date())
        } else {
            operations[.refresh] = timeouts > 0 ? .timedOut : .failed("The earbuds did not answer any query.")
        }
    }

    private func featureIDs(for profile: DeviceProfile) -> [UInt8] {
        guard let opo = profile.opo else { return [] }
        return [(Capability.gameMode, opo.gameModeFeatureID), (.wearDetection, opo.wearDetectionFeatureID), (.dualConnection, opo.dualConnectionFeatureID)]
            .compactMap { capability, id in profile.presentation(capability) != .hidden ? id : nil }
    }

    // MARK: Changing settings

    public func setNoiseControl(_ mode: NoiseControlMode) async {
        pendingNoiseControl = mode
        defer { pendingNoiseControl = nil }
        await run(.noiseControl, .setNoiseControl(mode))
    }

    public func setEqualizer(presetID: UInt8) async {
        await run(.equalizer, .setEqualizer(presetID: presetID))
    }

    public func setFeature(_ id: UInt8, enabled: Bool) async {
        await run(.feature(id), .setFeature(id: id, enabled: enabled))
    }

    public func setGesture(_ binding: GestureBinding) async {
        await run(.gestures, .setGestures([binding]))
    }

    private func run(_ operation: Operation, _ command: EarbudCommand) async {
        guard let session, connection.isConnected else {
            operations[operation] = .failed("Not connected")
            return
        }
        let id = sessionID
        operations[operation] = .pending
        let result: Result<EarbudResponse, Error>
        do { result = .success(try await session.perform(command)) } catch { result = .failure(error) }
        // A reply for a session that has since ended must not touch the new session's state.
        guard sessionID == id, id != nil else { return }
        switch result {
        case .success(let response):
            apply(response)
            operations[operation] = .confirmed(Date())
            lastError = nil
        case .failure(ProtocolError.timeout):
            operations[operation] = .timedOut
            lastError = "The earbuds did not confirm the change in time."
        case .failure(let error):
            operations[operation] = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    private func apply(_ response: EarbudResponse) {
        switch response {
        case .battery(let value): battery = value
        case .noiseControl(let mode): noiseControl = mode
        case .equalizer(let id): equalizerPreset = id
        case .features(let values): features.merge(values) { $1 }
        case .gestures(let bindings): gestures = bindings
        case .deviceInfo(let info): deviceInfo = info
        }
    }

    // MARK: Events

    private func startEvents(from session: any EarbudProtocol) {
        let id = UUID()
        sessionID = id
        eventTask?.cancel()
        let events = session.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self, self.sessionID == id else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: EarbudEvent) {
        switch event {
        case .battery(let update): battery = (battery ?? BatteryStatus()).merging(update)
        case .noiseControl(let mode): noiseControl = mode
        case .equalizer(let id): equalizerPreset = id
        case .feature(let id, let enabled): features[id] = enabled
        case .wear(let values): wear.merge(values) { $1 }
        case .packet(let entry):
            guard isPacketLoggingEnabled else { return }
            packetLog.append(entry)
            if packetLog.count > Self.packetLogLimit { packetLog.removeFirst(packetLog.count - Self.packetLogLimit) }
        case .sessionEnded(let reason):
            sessionEnded(reason: reason)
        }
    }

    private func sessionEnded(reason: String?) {
        guard session != nil else { return }
        session = nil
        sessionID = nil
        resetDeviceState()
        lastError = reason.map { "Disconnected: \($0)" }
        connection = userDisconnected ? .idle : .noDevice
        if !userDisconnected { scheduleReconnect() }
    }

    // MARK: Helpers

    /// Transports to try, in the profile's preference order, limited to what discovery found.
    public static func transportOrder(profile: DeviceProfile, earbuds: DiscoveredEarbuds) -> [TransportKind] {
        if earbuds.isDemo { return [.mock] }
        return profile.transports.filter(earbuds.transports.contains)
    }

    private func fail(as state: ConnectionState) {
        resetDeviceState()
        connection = state
    }

    private func scheduleReconnect() {
        guard !userDisconnected, !reconnectDelays.isEmpty else { return }
        let delay = reconnectDelays[min(reconnectAttempt, reconnectDelays.count - 1)]
        reconnectAttempt += 1
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.userDisconnected else { return }
            self.reconnectTask = nil
            await self.connect(thorough: false)
        }
    }

    /// Clears everything learned from a device so no stale values survive a disconnect or switch.
    private func resetDeviceState() {
        earbuds = nil
        profile = nil
        transportKind = nil
        transportDetail = nil
        battery = nil
        noiseControl = nil
        pendingNoiseControl = nil
        equalizerPreset = nil
        features = [:]
        gestures = []
        deviceInfo = nil
        wear = [:]
        operations = [:]
        lastUpdated = nil
    }
}
