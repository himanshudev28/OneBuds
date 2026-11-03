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
        case customEqualizer, bassLevel, noiseCycle, findEarbuds, fitTest, hearing
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
    /// Every control channel tried by the latest connect attempt, in order, with its outcome.
    public private(set) var transportAttempts: [TransportAttempt] = []
    /// True while the session moves from a fallback route back to the preferred one.
    public private(set) var isSwitchingRoute = false
    public private(set) var battery: BatteryStatus?
    public private(set) var noiseControl: NoiseControlMode?
    /// The mode being applied; the UI shows it as pending until the earbuds confirm.
    public private(set) var pendingNoiseControl: NoiseControlMode?
    public private(set) var equalizerPreset: UInt8?
    public private(set) var features: [UInt8: Bool] = [:]
    public private(set) var gestures: [GestureBinding] = []
    public private(set) var deviceInfo: DeviceInfo?
    public private(set) var wear: [UInt8: UInt8] = [:]
    public private(set) var customPresets: [CustomEQPreset] = []
    public private(set) var bassLevel: Int?
    public private(set) var noiseCycle: Set<NoiseCategory>?
    public private(set) var fitResult: FitResult?
    public private(set) var hearingProfile: HearingProfile?
    /// Latest hearing-test status pushed by the earbuds (5 a bud is out, 6 it is back, 7 timed out).
    public private(set) var hearingStatus: UInt8?
    /// True between a confirmed "ring" and a confirmed "stop".
    public private(set) var isRinging = false
    public private(set) var operations: [Operation: OperationStatus] = [:]
    public private(set) var lastError: String?
    public private(set) var lastUpdated: Date?
    public private(set) var packetLog: [PacketLogEntry] = []
    public private(set) var isDemo: Bool
    /// The capability engine's verdicts for the connected earbuds, with evidence (CapabilityEngine.swift).
    public private(set) var capabilityReport: CapabilityReport?
    /// The model's last confirmed report, available while a new session starts. A hint only:
    /// it never decides what is shown, and it is cleared once the live report exists.
    public private(set) var cachedCapabilities: CapabilityCache.Entry?

    /// Raw packet logging is opt-in (Diagnostics screen) and kept in memory only.
    public var isPacketLoggingEnabled = false {
        didSet {
            if !isPacketLoggingEnabled { packetLog = [] }
            let enabled = isPacketLoggingEnabled
            if let session { Task { await session.setPacketLogging(enabled) } }
        }
    }

    public static let packetLogLimit = 1000

    /// Which control channels may be used. Takes effect on the next connect.
    public var transportPreference: TransportPreference = .automatic {
        didSet { if transportPreference != oldValue { lastGoodTransport = [:] } }
    }

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
    /// The transport that last opened a session, per device name. Automatic reconnects try it first
    /// so a route that keeps failing does not delay every reconnect; user-initiated connects always
    /// follow the full preference order.
    private var lastGoodTransport: [String: (kind: TransportKind, at: Date)] = [:]
    /// Profiles picked by reported product id, per device name, so reconnects skip the mismatch.
    private var identifiedProfiles: [String: (profileID: String, productID: String)] = [:]
    /// How long a fallback route stays first for automatic reconnects before the preferred route is
    /// tried first again (so a transient GATT failure does not pin RFCOMM forever).
    public static let fallbackMemory: TimeInterval = 600
    /// Waits before retrying the preferred route after a failed switch back (10 min, 30 min, 2 h).
    public static let routeUpgradeBackoff: [TimeInterval] = [600, 1800, 7200]
    private let routeCheckInterval: Duration
    private var routeUpgradeTask: Task<Void, Never>?
    private var routeUpgradeFailures = 0
    private var nextRouteUpgrade = Date.distantPast
    private var hearingTestActive = false
    private let now: @Sendable () -> Date
    private let capabilityCache: CapabilityCache?
    private let reconnectDelays: [Duration]
    private let logger = Logger(subsystem: "com.local.onebuds", category: "manager")

    public init(connector: any DeviceConnector,
                reconnectDelays: [Duration] = [.seconds(1), .seconds(3), .seconds(10), .seconds(30), .seconds(120)],
                sessionFactory: @escaping (any EarbudTransport, DeviceProfile) -> any EarbudProtocol = { OPOv1Session(transport: $0, profile: $1) },
                now: @escaping @Sendable () -> Date = { Date() },
                routeCheckInterval: Duration = .seconds(60),
                capabilityCache: CapabilityCache? = nil) {
        self.now = now
        self.routeCheckInterval = routeCheckInterval
        self.capabilityCache = capabilityCache
        self.connector = connector
        self.reconnectDelays = reconnectDelays
        self.sessionFactory = sessionFactory
        isDemo = connector.isDemo
    }

    // MARK: Capability presentation

    public func presentation(_ capability: Capability) -> CapabilityPresentation {
        guard connection.isConnected, let profile else { return .hidden }
        // The earbuds' own capability bitmap can only take a feature away, never add one.
        guard OPOFeatureCodec.bitmap(deviceInfo?.capabilityBits ?? [], offers: capability) else { return .hidden }
        let base = profile.presentation(capability, over: transportKind)
        // The capability engine can also only take a feature away (e.g. an identity conflict, or a
        // profile missing what the command needs).
        if base != .hidden, capabilityReport?.presentation(capability) == .hidden { return .hidden }
        return base
    }

    /// The `0x0403` switch id behind a switch-style capability, when the profile has one.
    public func featureID(for capability: Capability) -> UInt8? {
        guard let opo = profile?.opo else { return nil }
        switch capability {
        case .gameMode: return opo.gameModeFeatureID
        case .wearDetection: return opo.wearDetectionFeatureID
        case .dualConnection: return opo.dualConnectionFeatureID
        case .smartVolume: return opo.smartVolumeFeatureID
        case .bassWave: return opo.bassWaveFeatureID
        case .spatialAudio: return opo.spatialAudioFeatureID
        case .hearingTest: return opo.goldenSoundFeatureID
        default: return nil
        }
    }

    /// A switch to show: the profile offers it and the earbuds reported its value.
    public func visibleFeatureID(for capability: Capability) -> UInt8? {
        guard presentation(capability) != .hidden, let id = featureID(for: capability), features[id] != nil else { return nil }
        return id
    }

    public func status(of operation: Operation) -> OperationStatus { operations[operation] ?? .idle }

    /// When connected over a fallback route, why the preferred one was not used, e.g.
    /// "GATT: Timed out: GATT discovery; using RFCOMM". Nil when the first route worked.
    public var fallbackNote: String? {
        guard connection.isConnected, !isSwitchingRoute, let kind = transportKind else { return nil }
        let failures = transportAttempts.filter { if case .failed = $0.outcome { true } else { false } }
        guard !failures.isEmpty else { return nil }
        return failures.map(\.summary).joined(separator: " · ") + "; using \(kind.shortName)"
    }

    // MARK: Lifecycle

    /// Starts watching for devices and connects to the first supported one.
    public func start() {
        watchTask?.cancel()
        let changes = connector.deviceChanges()
        watchTask = Task { [weak self] in
            for await _ in changes {
                guard let self, !self.connection.isConnected, !self.userDisconnected else { continue }
                // A device (re)connected: start from the preferred route, not a remembered fallback.
                self.lastGoodTransport = [:]
                self.routeUpgradeFailures = 0
                self.nextRouteUpgrade = .distantPast
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
        transportAttempts = []
        connection = .searching
        let availability = await connector.availability()
        guard isCurrent() else { return }
        switch availability {
        case .poweredOff: return fail(as: .bluetoothOff)
        case .unauthorized: return fail(as: .unauthorized)
        case .unsupported: return fail(as: .bluetoothUnsupported)
        case .ready, .unknown: break
        }

        var found = await connector.discover(thorough: thorough)
        guard isCurrent() else { return }
        for index in found.indices {
            if let known = identifiedProfiles[found[index].name] {
                found[index].identifiedProfileID = known.profileID
                found[index].productID = found[index].productID ?? known.productID
            }
        }
        guard let target = found.first(where: { $0.profile?.allowsControlSession == true }) ?? found.first else {
            resetDeviceState()
            connection = .noDevice
            scheduleReconnect()
            return
        }
        earbuds = target
        profile = target.profile
        cachedCapabilities = isDemo ? nil : target.profile.flatMap { capabilityCache?.entry(for: $0) }
        guard let profile = target.profile, profile.allowsControlSession else {
            connection = .unrecognised(name: target.name)
            return
        }

        var lastFailure: String?
        let remembered = lastGoodTransport[target.name].flatMap { now().timeIntervalSince($0.at) < Self.fallbackMemory ? $0.kind : nil }
        var order = Self.transportOrder(profile: profile, earbuds: target, preference: transportPreference,
                                        lastGood: thorough ? nil : remembered)
        if order.isEmpty {
            lastFailure = "\(target.name) offers no control channel allowed by the Connection setting (\(transportPreference.displayName))."
        }
        var activeTarget = target
        var activeProfile = profile
        var switchedProfile = false
        var index = 0
        while index < order.count {
            let kind = order[index]
            switch await openSession(kind, target: activeTarget, profile: activeProfile, showProgress: true, isCurrent: isCurrent) {
            case .cancelled:
                return
            case .failed(let attempt, let message):
                lastFailure = message
                transportAttempts.append(TransportAttempt(kind: kind, outcome: .failed(attempt)))
                index += 1
                continue
            case .mismatch(let message, let found):
                // The earbuds' own product id outranks the name (special editions share names): if
                // exactly one controllable profile claims it, retry once on this route with that profile.
                if !switchedProfile, let found, let other = DeviceRegistry.match(name: nil, productID: found),
                   other.id != activeProfile.id, other.allowsControlSession {
                    switchedProfile = true
                    logger.notice("Product id \(found, privacy: .public) belongs to \(other.id, privacy: .public); switching profile")
                    activeProfile = other
                    activeTarget.productID = found
                    activeTarget.identifiedProfileID = other.id  // transports now use the new profile's services
                    identifiedProfiles[activeTarget.name] = (other.id, found)
                    earbuds = activeTarget
                    self.profile = other
                    cachedCapabilities = isDemo ? nil : capabilityCache?.entry(for: other)
                    // The new profile decides the routes; retry this one first if it allows it.
                    order = Self.transportOrder(profile: other, earbuds: activeTarget, preference: transportPreference)
                    if let same = order.firstIndex(of: kind) { order.swapAt(0, same) }
                    index = 0
                    continue
                }
                // Wrong or unknown model: do not try other transports or send anything else.
                transportAttempts.append(TransportAttempt(kind: kind, outcome: .failed("session: \(message)")))
                resetDeviceState()
                lastError = message
                connection = .failed(message)
                return
            case .opened:
                connection = .connected
                transportAttempts.append(TransportAttempt(kind: kind, outcome: .connected))
                lastGoodTransport[activeTarget.name] = (kind, now())
                reconnectAttempt = 0
                updateCapabilityReport()
                startRouteUpgradeMonitor()
                await refresh()
                return
            }
        }
        guard isCurrent() else { return }
        resetDeviceState()
        lastGoodTransport[target.name] = nil
        let failures = transportAttempts.compactMap { if case .failed = $0.outcome { $0.summary } else { nil } }
        let message = failures.count > 1 ? "Could not open a control channel. " + failures.joined(separator: " · ") : lastFailure
        lastError = message
        connection = .failed(message ?? "Could not open a control channel to the earbuds.")
        scheduleReconnect()
    }

    private enum OpenResult {
        case opened
        case failed(attempt: String, message: String)
        case mismatch(String, found: String?)
        case cancelled
    }

    /// Opens one route: transport, then the OPO session. On success `session`, `transportKind`,
    /// `transportDetail` and `deviceInfo` describe the new route; the caller sets the connection
    /// state. `showProgress` shows connecting/handshaking (false while switching routes, so the UI
    /// stays connected and the connection card does not announce again).
    private func openSession(_ kind: TransportKind, target: DiscoveredEarbuds, profile: DeviceProfile,
                             showProgress: Bool, isCurrent: () -> Bool) async -> OpenResult {
        guard let transport = connector.makeTransport(for: target, kind: kind) else {
            return .failed(attempt: "not available for this device", message: "\(kind.displayName) is not available for this device.")
        }
        if showProgress { connection = .connecting(kind) }
        do {
            try await transport.connect()
        } catch {
            guard isCurrent() else { return .cancelled }
            logger.notice("Transport \(kind.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return .failed(attempt: error.localizedDescription, message: error.localizedDescription)
        }
        guard isCurrent() else { await transport.disconnect(); return .cancelled }
        transportKind = kind
        transportDetail = connector.describe(transport)

        let session = sessionFactory(transport, profile)
        self.session = session
        await session.setPacketLogging(isPacketLoggingEnabled)
        startEvents(from: session)
        if showProgress { connection = .handshaking }
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
            guard isCurrent() else { return .cancelled }
            if case ProtocolError.profileMismatch(_, let found) = error { return .mismatch(error.localizedDescription, found: found) }
            return .failed(attempt: "session: \(error.localizedDescription)", message: error.localizedDescription)
        }
        guard isCurrent() else { await session.end(); return .cancelled }
        deviceInfo = await session.currentDeviceInfo()
        guard isCurrent(), self.session != nil else { return .cancelled }
        return .opened
    }

    // MARK: Switching back to the preferred route

    /// The route the preference and profile put first, whether or not discovery saw it.
    private var preferredRoute: TransportKind? {
        guard let profile, !isDemo else { return nil }
        return transportPreference.filter(profile.transports).first
    }

    /// Checks right away (instead of at the next periodic check) and switches to the preferred route
    /// if it is available. Does nothing when already on it or while the user is busy.
    public func switchToPreferredRouteIfAvailable() async {
        guard connection.isConnected, let preferred = preferredRoute, let current = transportKind, preferred != current,
              !isBusyForRouteSwitch, let earbuds, connector.isRouteAvailable(preferred, for: earbuds) else { return }
        await switchRoute(to: preferred)
    }

    /// Something the user started that a route switch would interrupt.
    private var isBusyForRouteSwitch: Bool {
        isRinging || hearingTestActive || operations.values.contains(.pending)
    }

    /// While connected over a fallback route, checks every `routeCheckInterval` (local state only)
    /// whether the preferred route is available again, and switches back when it is.
    private func startRouteUpgradeMonitor() {
        routeUpgradeTask?.cancel()
        routeUpgradeTask = nil
        guard let preferred = preferredRoute, let current = transportKind, preferred != current else { return }
        let id = sessionID
        let interval = routeCheckInterval
        routeUpgradeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, self.sessionID == id, self.connection.isConnected else { return }
                guard self.now() >= self.nextRouteUpgrade, !self.isBusyForRouteSwitch, let earbuds = self.earbuds,
                      self.connector.isRouteAvailable(preferred, for: earbuds) else { continue }
                await self.switchRoute(to: preferred)
                return
            }
        }
    }

    /// Moves the session to `preferred`: closes the current route first (the earbuds may allow
    /// only one control channel), opens the preferred one, and reopens the old one if that fails.
    /// The UI stays connected and keeps its values; a failed switch backs off before the next try.
    private func switchRoute(to preferred: TransportKind) async {
        guard connectTask == nil, connection.isConnected, let target = earbuds, let profile,
              let fallback = transportKind, fallback != preferred, let old = session else { return }
        let attempt = generation
        func isCurrent() -> Bool { attempt == generation && !userDisconnected }
        let task = Task {
            isSwitchingRoute = true
            defer { isSwitchingRoute = false }
            logger.notice("Switching control channel \(fallback.rawValue, privacy: .public) → \(preferred.rawValue, privacy: .public)")
            session = nil
            sessionID = nil
            eventTask?.cancel()
            await old.end()

            var target = target
            if !target.transports.contains(preferred) { target.transports.append(preferred) }
            for name in profile.bluetoothNames where !target.bleNames.contains(name) && name != target.name { target.bleNames.append(name) }
            var attempts: [TransportAttempt] = []
            for kind in [preferred, fallback] {
                switch await openSession(kind, target: target, profile: profile, showProgress: false, isCurrent: isCurrent) {
                case .cancelled:
                    return
                case .failed(let reason, _), .mismatch(let reason, _):
                    attempts.append(TransportAttempt(kind: kind, outcome: .failed(reason)))
                case .opened:
                    attempts.append(TransportAttempt(kind: kind, outcome: .connected))
                    transportAttempts = attempts
                    earbuds = target
                    lastGoodTransport[target.name] = (kind, now())
                    if kind == preferred {
                        routeUpgradeFailures = 0
                        nextRouteUpgrade = .distantPast
                    } else {
                        let backoff = Self.routeUpgradeBackoff[min(routeUpgradeFailures, Self.routeUpgradeBackoff.count - 1)]
                        routeUpgradeFailures += 1
                        nextRouteUpgrade = now().addingTimeInterval(backoff)
                    }
                    updateCapabilityReport()
                    startRouteUpgradeMonitor()
                    await refresh()
                    return
                }
            }
            // Neither route reopened: the normal reconnect path takes over.
            guard isCurrent() else { return }
            transportAttempts = attempts
            resetDeviceState()
            lastError = "Lost the control channel while switching to \(preferred.displayName)."
            connection = .noDevice
            scheduleReconnect()
        }
        connectTask = task
        await task.value
        connectTask = nil
    }

    public func disconnect() async {
        // Never leave the locating sound playing after OneBuds lets go of the earbuds.
        if isRinging, let session { _ = try? await session.perform(.findEarbuds(ringing: false)) }
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
        if presentation(.gestures) != .hidden, case .gestures(let bindings)? = await read(.readGestures), stillCurrent() {
            gestures = bindings
        }
        if wear.isEmpty, presentation(.battery) != .hidden, deviceInfo?.capabilityBits.contains(4) == true,
           case .wear(let values)? = await read(.readWear), stillCurrent() {
            wear.merge(values) { current, _ in current }
        }
        if presentation(.customEqualizer) != .hidden, case .customEqualizers(let presets)? = await read(.readCustomEqualizers), stillCurrent() {
            customPresets = presets
        }
        if presentation(.bassWave) != .hidden, profile.opo?.bassLevels != nil, case .bassLevel(let level)? = await read(.readBassLevel), stillCurrent() {
            bassLevel = level
        }
        if presentation(.noiseCycle) != .hidden, case .noiseCycle(let cycle)? = await read(.readNoiseCycle), stillCurrent() {
            noiseCycle = cycle
        }
        if presentation(.hearingTest) != .hidden, case .hearingProfile(let stored)? = await read(.readHearingProfile), stillCurrent() {
            hearingProfile = stored
        }
        guard stillCurrent() else { return }
        updateCapabilityReport()
        if successes > 0 {
            lastUpdated = Date()
            operations[.refresh] = .confirmed(Date())
        } else {
            operations[.refresh] = timeouts > 0 ? .timedOut : .failed("The earbuds did not answer any query.")
        }
    }

    private func featureIDs(for profile: DeviceProfile) -> [UInt8] {
        let switches: [Capability] = [.gameMode, .wearDetection, .dualConnection, .smartVolume, .bassWave, .spatialAudio, .hearingTest]
        var seen = Set<UInt8>()
        return switches.compactMap { capability in
            guard presentation(capability) != .hidden, let id = featureID(for: capability), seen.insert(id).inserted else { return nil }
            return id
        }
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

    public func createCustomPreset(name: String, bands: [EQBand]) async {
        await run(.customEqualizer, .createCustomEqualizer(name: name, bands: bands))
        await rereadEqualizerAfterPresetChange()
    }

    public func saveCustomPreset(_ preset: CustomEQPreset) async {
        await run(.customEqualizer, .saveCustomEqualizer(preset))
        await rereadEqualizerAfterPresetChange()
    }

    public func deleteCustomPreset(_ preset: CustomEQPreset) async {
        await run(.customEqualizer, .deleteCustomEqualizer(preset))
        await rereadEqualizerAfterPresetChange()
    }

    /// Ids can be renumbered by a preset change, so the selected id is read again.
    private func rereadEqualizerAfterPresetChange() async {
        guard case .confirmed = status(of: .customEqualizer), let session, connection.isConnected else { return }
        let id = sessionID
        if case .equalizer(let preset)? = try? await session.perform(.readEqualizer), sessionID == id { equalizerPreset = preset }
    }

    public func setBassLevel(_ level: Int) async {
        await run(.bassLevel, .setBassLevel(level))
    }

    public func setNoiseCycle(_ categories: Set<NoiseCategory>) async {
        await run(.noiseCycle, .setNoiseCycle(categories))
    }

    /// Starts or stops the loud locating sound. Only the acknowledgement can be checked.
    public func findEarbuds(ringing: Bool) async {
        await run(.findEarbuds, .findEarbuds(ringing: ringing))
        switch status(of: .findEarbuds) {
        case .confirmed: isRinging = ringing
        // No answer: the buds may be ringing anyway, so Stop stays available.
        case .timedOut: isRinging = true
        // A failed stop leaves the sound possibly playing; a refused start means it never began.
        case .failed: isRinging = ringing ? isRinging : true
        default: break
        }
    }

    public func runFitTest() async {
        fitResult = nil
        await run(.fitTest, .runFitTest)
    }

    // Golden Sound test steps. They throw so the test screen can stop and explain.
    public func startHearingTest() async throws {
        hearingTestActive = true
        hearingStatus = nil
        operations[.hearing] = nil
        try await perform(.startHearingTest)
    }

    public func playHearingTone(_ tone: HearingTone) async throws {
        try await perform(.playHearingTone(tone))
    }

    public func stopHearingTone() async {
        try? await perform(.stopHearingTone)
    }

    public func endHearingTest() async {
        try? await perform(.endHearingTest)
        hearingTestActive = false
        hearingStatus = nil
    }

    public func applyHearingProfile(_ levels: [Int]) async {
        await run(.hearing, .applyHearingProfile(levels))
    }

    /// Sends a command outside the one-status-per-control bookkeeping (test tones are many and quick).
    private func perform(_ command: EarbudCommand) async throws {
        guard let session, connection.isConnected else { throw ProtocolError.disconnected(nil) }
        _ = try await session.perform(command)
    }

    private func run(_ operation: Operation, _ command: EarbudCommand) async {
        guard let session, connection.isConnected else {
            operations[operation] = .failed(isSwitchingRoute ? "Switching connection; try again in a moment" : "Not connected")
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
        case .wear(let values): wear.merge(values) { $1 }
        case .customEqualizers(let presets): customPresets = presets
        case .bassLevel(let level): bassLevel = level
        case .noiseCycle(let cycle): noiseCycle = cycle
        case .fitResult(let result): fitResult = result
        case .hearingProfile(let stored):
            hearingProfile = stored
            if let id = profile?.opo?.goldenSoundFeatureID, stored != nil { features[id] = true }
        case .acknowledged: break
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
        case .noiseCycle(let cycle): noiseCycle = cycle
        case .hearingStatus(let value): hearingStatus = value
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

    /// Transports to try: the profile's preference order, limited to what discovery found and to
    /// the user's preference. `lastGood` (automatic reconnects only) moves the route that last
    /// worked to the front; it never adds a route that is not otherwise allowed.
    public static func transportOrder(profile: DeviceProfile, earbuds: DiscoveredEarbuds,
                                      preference: TransportPreference = .automatic,
                                      lastGood: TransportKind? = nil) -> [TransportKind] {
        if earbuds.isDemo { return [.mock] }
        var order = preference.filter(profile.transports.filter(earbuds.transports.contains))
        if let lastGood, let index = order.firstIndex(of: lastGood), index > 0 {
            order.remove(at: index)
            order.insert(lastGood, at: 0)
        }
        return order
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

    /// Re-runs the capability engine on what the session has learned, and caches confirmed results.
    private func updateCapabilityReport() {
        guard connection.isConnected, let earbuds else {
            capabilityReport = nil
            return
        }
        let report = CapabilityEngine.evaluate(CapabilityInput(
            name: earbuds.name, advertisedProductID: earbuds.productID, discoveredTransports: earbuds.transports,
            activeTransport: transportKind, attempts: transportAttempts, deviceInfo: deviceInfo,
            reported: reportedCapabilities()), now: now())
        capabilityReport = report
        cachedCapabilities = nil
        // Demo reports describe the simulator, not real earbuds.
        if !isDemo { capabilityCache?.store(report, now: now()) }
    }

    /// Capabilities whose current value the earbuds reported this session (evidence only).
    private func reportedCapabilities() -> Set<Capability> {
        var reported = Set<Capability>()
        if battery != nil { reported.insert(.battery) }
        if noiseControl != nil { reported.insert(.noiseControl) }
        if equalizerPreset != nil { reported.insert(.equalizer) }
        if !gestures.isEmpty { reported.insert(.gestures) }
        if deviceInfo?.firmwareSummary != nil { reported.insert(.deviceInfo) }
        if !customPresets.isEmpty { reported.insert(.customEqualizer) }
        if noiseCycle != nil { reported.insert(.noiseCycle) }
        if hearingProfile != nil { reported.insert(.hearingTest) }
        let switches: [Capability] = [.gameMode, .wearDetection, .dualConnection, .smartVolume, .bassWave, .spatialAudio]
        for capability in switches where featureID(for: capability).map({ features[$0] != nil }) == true {
            reported.insert(capability)
        }
        return reported
    }

    /// Clears everything learned from a device so no stale values survive a disconnect or switch.
    private func resetDeviceState() {
        routeUpgradeTask?.cancel()
        routeUpgradeTask = nil
        hearingTestActive = false
        capabilityReport = nil
        cachedCapabilities = nil
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
        customPresets = []
        bassLevel = nil
        noiseCycle = nil
        fitResult = nil
        hearingProfile = nil
        hearingStatus = nil
        isRinging = false
        operations = [:]
        lastUpdated = nil
    }
}
