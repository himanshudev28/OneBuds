import Foundation
import Testing
@testable import OneBudsCore
import OneBudsProtocol

@Suite struct RegistryTests {
    @Test func matchesExactNameCaseInsensitively() {
        #expect(DeviceRegistry.match(name: "oneplus buds 3")?.id == "oneplus-buds-3")
        #expect(DeviceRegistry.match(name: "OnePlus Nord Buds 3 Pro")?.id == "oneplus-nord-buds-3-pro")
    }

    @Test func neverMatchesByFamilyName() {
        #expect(DeviceRegistry.match(name: "OnePlus Buds 3 Pro") == nil)
        #expect(DeviceRegistry.match(name: "OnePlus Buds") == nil)
    }

    @Test func fallsBackToProductID() {
        #expect(DeviceRegistry.match(name: "Renamed buds", productID: "063c14")?.id == "oneplus-buds-3")
        #expect(DeviceRegistry.match(name: nil, productID: "FFFFFF") == nil)
    }

    @Test func unknownModelsAreDiagnosticsOnly() throws {
        let buds4 = try #require(DeviceRegistry.match(name: "OnePlus Buds 4"))
        #expect(!buds4.allowsControlSession)
        #expect(Capability.allCases.allSatisfy { buds4.presentation($0) == .hidden })
    }

    @Test func nothingIsClaimedVerifiedWithoutEvidence() {
        for profile in DeviceRegistry.all {
            for capability in Capability.allCases where profile.support(capability) == .verified {
                #expect(!profile.evidence.isEmpty, "\(profile.id) claims \(capability) verified without evidence")
            }
        }
    }

    @Test func profileIDsAreUnique() {
        #expect(Set(DeviceRegistry.all.map(\.id)).count == DeviceRegistry.all.count)
    }
}

@Suite struct PresentationTests {
    @Test func unsupportedHiddenExperimentalBadged() {
        #expect(CapabilityPresentation(.unsupported) == .hidden)
        #expect(CapabilityPresentation(.unknown) == .hidden)
        #expect(CapabilityPresentation(.experimental) == .experimental)
        #expect(CapabilityPresentation(.verified) == .supported)
    }

    @Test func profileWithoutACapabilityHidesIt() {
        #expect(DeviceRegistry.nordBuds3Pro.presentation(.equalizer) == .hidden)
        #expect(DeviceRegistry.onePlusBuds3.presentation(.equalizer) == .supported)
        #expect(DeviceRegistry.onePlusBuds3.presentation(.wearDetection) == .experimental)
    }
}

@Suite struct ModelTests {
    @Test func batteryMergeKeepsMissingComponents() {
        let full = BatteryStatus(left: .init(percent: 80, isCharging: false), right: .init(percent: 70, isCharging: false),
                                 chargingCase: .init(percent: 50, isCharging: false))
        let update = BatteryStatus(left: .init(percent: 79, isCharging: false))
        #expect(full.merging(update).left?.percent == 79)
        #expect(full.merging(update).chargingCase?.percent == 50)
        #expect(full.lowestBud?.percent == 70)
    }

    @Test func zeroLevelsAreUnknown() {
        let status = BatteryStatus(levels: [.init(component: 1, percent: 0, isCharging: false), .init(component: 2, percent: 50, isCharging: false)])
        #expect(status.left == nil)
        #expect(status.right?.percent == 50)
    }

    @Test func firmwareTriples() {
        let parsed = DeviceInfo.parseFirmware("1,2,138,2,2,138,3,2,105")
        #expect(parsed.count == 3)
        var info = DeviceInfo()
        info.firmware = parsed
        #expect(info.firmwareSummary == "138.138.105")
        #expect(DeviceInfo.parseFirmware("garbage").isEmpty)
    }
}

/// Connector whose transports can be made to fail per kind, for transport selection tests.
@MainActor
final class ScriptedConnector: DeviceConnector {
    let isDemo = false
    var found: [DiscoveredEarbuds]
    var failingKinds: Set<TransportKind>
    var availabilityValue: BluetoothAvailability = .ready
    var availabilityDelay: Duration = .zero
    /// Optional override of the simulator, e.g. to drop the link on a given command.
    var handlerOverride: MockTransport.Handler?
    private(set) var attempted: [TransportKind] = []
    private(set) var discoveries: [Bool] = []
    let simulator = MockEarbudsSimulator(profile: DeviceRegistry.onePlusBuds3)
    private(set) var transports: [MockTransport] = []

    init(found: [DiscoveredEarbuds], failingKinds: Set<TransportKind> = []) {
        self.found = found
        self.failingKinds = failingKinds
    }

    func availability() async -> BluetoothAvailability {
        if availabilityDelay > .zero { try? await Task.sleep(for: availabilityDelay) }
        return availabilityValue
    }
    func discover(thorough: Bool) async -> [DiscoveredEarbuds] {
        discoveries.append(thorough)
        return found
    }

    func makeTransport(for earbuds: DiscoveredEarbuds, kind: TransportKind) -> (any EarbudTransport)? {
        attempted.append(kind)
        if failingKinds.contains(kind) { return MockTransport(connectError: .openFailed("scripted")) }
        let simulator = self.simulator
        let transport = MockTransport(framesOnConnect: simulator.framesOnConnect(), handler: handlerOverride ?? { await simulator.handle($0) })
        transports.append(transport)
        return transport
    }

    func describe(_ transport: any EarbudTransport) -> String? { "scripted \(transport.kind.rawValue)" }
    func deviceChanges() -> AsyncStream<Void> { AsyncStream { _ in } }
}

@MainActor
@Suite struct DeviceManagerTests {
    let buds3 = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["test"], transports: [.rfcomm, .ble])

    @Test func connectsAndPopulatesFromTheDevice() async {
        let manager = DeviceManager(connector: ScriptedConnector(found: [buds3]), reconnectDelays: [])
        await manager.connect()
        #expect(manager.connection == .connected)
        #expect(manager.transportKind == .rfcomm)
        #expect(manager.battery?.left?.percent == 82)
        #expect(manager.noiseControl == .noiseCancelling(.smart))
        #expect(manager.deviceInfo?.productID == "063C14")
        #expect(manager.features[0x06] == false)
        #expect(!manager.gestures.isEmpty)
    }

    @Test func fallsBackToBLEWhenRFCOMMFails() async {
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.rfcomm])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        #expect(connector.attempted == [.rfcomm, .ble])
        #expect(manager.transportKind == .ble)
        #expect(manager.connection == .connected)
    }

    @Test func transportOrderFollowsTheProfile() {
        let bleOnly = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["scan"], transports: [.ble])
        #expect(DeviceManager.transportOrder(profile: DeviceRegistry.onePlusBuds3, earbuds: buds3) == [.rfcomm, .ble])
        #expect(DeviceManager.transportOrder(profile: DeviceRegistry.onePlusBuds3, earbuds: bleOnly) == [.ble])
        #expect(DeviceManager.transportOrder(profile: DeviceRegistry.nordBuds3Pro, earbuds: buds3) == [.ble, .rfcomm])
    }

    @Test func settingIsShownOnlyAfterConfirmation() async {
        let manager = DeviceManager(connector: ScriptedConnector(found: [buds3]), reconnectDelays: [])
        await manager.connect()
        await manager.setNoiseControl(.transparency)
        #expect(manager.noiseControl == .transparency)
        #expect(manager.pendingNoiseControl == nil)
        if case .confirmed = manager.status(of: .noiseControl) {} else { Issue.record("not confirmed") }
    }

    @Test func refusedSettingKeepsThePreviousValue() async {
        let connector = ScriptedConnector(found: [buds3])
        await connector.simulator.setRefusesNoiseControl(true)
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        await manager.setNoiseControl(.off)
        #expect(manager.noiseControl == .noiseCancelling(.smart))
        if case .failed = manager.status(of: .noiseControl) {} else { Issue.record("expected failure") }
        #expect(manager.lastError?.contains("ear") == true)
    }

    @Test func disconnectResetsAllDeviceState() async {
        let manager = DeviceManager(connector: ScriptedConnector(found: [buds3]), reconnectDelays: [])
        await manager.connect()
        await manager.disconnect()
        #expect(manager.connection == .idle)
        #expect(manager.battery == nil && manager.noiseControl == nil && manager.deviceInfo == nil)
        #expect(manager.features.isEmpty && manager.gestures.isEmpty && manager.profile == nil)
    }

    @Test func remoteDisconnectResetsState() async throws {
        let connector = ScriptedConnector(found: [buds3])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        await connector.transports.last?.simulateDisconnect(reason: "case closed")
        for _ in 0..<50 where manager.connection == .connected { try await Task.sleep(for: .milliseconds(20)) }
        #expect(manager.connection == .noDevice)
        #expect(manager.battery == nil)
        #expect(manager.lastError == "Disconnected: case closed")
    }

    @Test func unknownModelGetsNoSession() async {
        let connector = ScriptedConnector(found: [DiscoveredEarbuds(name: "OnePlus Buds 4", discoveryPaths: ["test"], transports: [.rfcomm])])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        #expect(manager.connection == .unrecognised(name: "OnePlus Buds 4"))
        #expect(connector.attempted.isEmpty)
    }

    @Test func permissionAndPowerStates() async {
        let connector = ScriptedConnector(found: [buds3])
        connector.availabilityValue = .unauthorized
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        #expect(manager.connection == .unauthorized)
        connector.availabilityValue = .poweredOff
        await manager.connect()
        #expect(manager.connection == .bluetoothOff)
    }

    @Test func noDeviceFound() async {
        let manager = DeviceManager(connector: ScriptedConnector(found: []), reconnectDelays: [])
        await manager.connect()
        #expect(manager.connection == .noDevice)
    }

    @Test func demoModeIsLabelledAndUsesMockTransport() async {
        let manager = DeviceManager(connector: DemoConnector(), reconnectDelays: [])
        await manager.connect()
        #expect(manager.isDemo)
        #expect(manager.transportKind == .mock)
        #expect(manager.connection == .connected)
    }

    @Test func switchingConnectorResetsState() async {
        let manager = DeviceManager(connector: DemoConnector(), reconnectDelays: [])
        await manager.connect()
        await manager.useConnector(ScriptedConnector(found: []))
        for _ in 0..<50 where manager.connection != .noDevice { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(!manager.isDemo)
        #expect(manager.battery == nil)
    }

    @Test func packetLoggingIsOptIn() async {
        let manager = DeviceManager(connector: ScriptedConnector(found: [buds3]), reconnectDelays: [])
        await manager.connect()
        #expect(manager.packetLog.isEmpty)
        manager.isPacketLoggingEnabled = true
        await manager.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!manager.packetLog.isEmpty)
        manager.isPacketLoggingEnabled = false
        #expect(manager.packetLog.isEmpty)
    }
}

/// Replies captured from the owner's OnePlus Buds 3 over RFCOMM channel 15 on 2026-10-12
/// (Diagnostics/onebuds-session-20261012-113019.txt, owner-approved query-only probe).
@Suite struct CapturedBuds3Fixtures {
    func decode(_ hex: String) -> OPOFrame? {
        var decoder = OPOFrameDecoder()
        let bytes = hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        return decoder.append(bytes).compactMap { if case .frame(let frame) = $0 { frame } else { nil } }.first
    }

    @Test func productIDReply() throws {
        let frame = try #require(decode("AA 0B 00 00 03 81 02 04 00 00 14 3C 06"))
        #expect(frame.command == 0x8103 && frame.sequence == 0x02)
        #expect(OPOReplyParser.productID(frame.payload) == "063C14")
        #expect(DeviceRegistry.match(name: nil, productID: OPOReplyParser.productID(frame.payload))?.id == "oneplus-buds-3")
    }

    @Test func firmwareReply() throws {
        let frame = try #require(decode("AA 2E 00 00 05 81 03 27 00 00 05 31 2C 31 2C 30 31 2C 31 2C 32 2C 31 32 37 2C 32 2C 31 2C 30 31 2C 32 2C 32 2C 31 32 37 2C 33 2C 32 2C 31 30 31"))
        let firmware = try #require(OPOReplyParser.firmware(frame.payload))
        #expect(firmware.count == 5)
        var info = DeviceInfo()
        info.firmware = DeviceInfo.parseFirmware(firmware.text)
        #expect(info.firmware.count == 5)
        #expect(info.firmwareSummary == "127.127.101")
    }

    @Test func batteryReply() throws {
        let frame = try #require(decode("AA 0F 00 00 06 81 04 08 00 00 03 01 64 02 64 03 64"))
        let status = BatteryStatus(levels: try #require(OPOReplyParser.battery(frame.payload)))
        #expect(status == BatteryStatus(left: .init(percent: 100, isCharging: false), right: .init(percent: 100, isCharging: false),
                                        chargingCase: .init(percent: 100, isCharging: false)))
    }

    @Test func handshakeReply() throws {
        let frame = try #require(decode("AA 10 00 00 00 81 01 09 00 00 FF 77 5A EE E7 0E 22 00"))
        let bits = try #require(OPOReplyParser.capabilityBits(frame.payload))
        #expect(bits.contains(8))   // 0x010C / 0x0404 noise control (S5 bit table)
        #expect(bits.contains(22))  // 0x0205 subscribe
        #expect(bits.count == 35)
    }
}


/// Regression tests for the 2026-10-12 code review findings.
@MainActor
@Suite struct ReviewRegressionTests {
    let buds3 = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["test"], transports: [.rfcomm, .ble])

    func fastSessions(_ transport: any EarbudTransport, _ profile: DeviceProfile) -> any EarbudProtocol {
        OPOv1Session(transport: transport, profile: profile, replyTimeout: .milliseconds(150), now: { Date() })
    }

    @Test func linkLostDuringFirstRefreshIsNotLeftConnected() async throws {
        let connector = ScriptedConnector(found: [buds3])
        let simulator = connector.simulator
        connector.handlerOverride = { data in
            if data.count > 5, data[4] == 0x06, data[5] == 0x01 { return .disconnect("case closed") } // battery read
            return await simulator.handle(data)
        }
        let manager = DeviceManager(connector: connector, reconnectDelays: [], sessionFactory: fastSessions)
        await manager.connect()
        for _ in 0..<50 where manager.connection == .connected { try await Task.sleep(for: .milliseconds(20)) }
        #expect(manager.connection == .noDevice)
        #expect(manager.lastUpdated == nil)
        #expect(manager.battery == nil)
    }

    @Test func automaticReconnectActuallyReconnects() async throws {
        let connector = ScriptedConnector(found: [])
        let manager = DeviceManager(connector: connector, reconnectDelays: [.milliseconds(50)], sessionFactory: fastSessions)
        await manager.connect()
        #expect(manager.connection == .noDevice)
        connector.found = [buds3]
        for _ in 0..<100 where manager.connection != .connected { try await Task.sleep(for: .milliseconds(20)) }
        #expect(manager.connection == .connected)
        await manager.disconnect()
    }

    @Test func disconnectDuringConnectWins() async throws {
        let connector = ScriptedConnector(found: [buds3])
        connector.availabilityDelay = .milliseconds(200)
        let manager = DeviceManager(connector: connector, reconnectDelays: [], sessionFactory: fastSessions)
        let connecting = Task { await manager.connect() }
        try await Task.sleep(for: .milliseconds(50))
        await manager.disconnect()
        await connecting.value
        #expect(manager.connection == .idle)
        #expect(connector.attempted.isEmpty)
        #expect(manager.battery == nil)
    }

    @Test func demoToggleDuringConnectNeverMixesSources() async throws {
        let connector = ScriptedConnector(found: [buds3])
        connector.availabilityDelay = .milliseconds(200)
        let manager = DeviceManager(connector: connector, reconnectDelays: [], sessionFactory: fastSessions)
        let connecting = Task { await manager.connect() }
        try await Task.sleep(for: .milliseconds(50))
        await manager.useConnector(DemoConnector())
        await connecting.value
        for _ in 0..<100 where manager.connection != .connected { try await Task.sleep(for: .milliseconds(20)) }
        #expect(manager.isDemo)
        #expect(manager.transportKind == .mock)
        #expect(connector.attempted.isEmpty)
        await manager.disconnect()
    }

    @Test func refreshWithNoAnswersIsNotReportedAsSuccess() async throws {
        let connector = ScriptedConnector(found: [buds3])
        let simulator = connector.simulator
        connector.handlerOverride = { data in
            // Answer session start (group 0x00 commands, product id, firmware); ignore every later read.
            let command = data.count > 5 ? UInt16(data[4]) | UInt16(data[5]) << 8 : 0
            return [0x0100, 0x0103, 0x0105, 0x0200, 0x0205].contains(command) ? await simulator.handle(data) : .none
        }
        let manager = DeviceManager(connector: connector, reconnectDelays: [], sessionFactory: fastSessions)
        await manager.connect()
        #expect(manager.connection == .connected)
        #expect(manager.lastUpdated == nil)
        #expect(manager.status(of: .refresh) == .timedOut)
        await manager.disconnect()
    }
}

@Suite struct LateReplyTests {
    @Test func lateReplyToATimedOutRequestIsDropped() async throws {
        let simulator = MockEarbudsSimulator(profile: DeviceRegistry.onePlusBuds3)
        let firstSequence = LockedValue<UInt8?>(nil)
        let transport = MockTransport { data in
            guard data.count > 6, data[4] == 0x0F, data[5] == 0x01 else { return await simulator.handle(data) }
            if let first = firstSequence.value {
                // Late answer (preset 7) to the first read, then the real answer (preset 1) to this one.
                let late = OPOFrame(command: 0x810F, sequence: first, payload: [0x00, 0x07])
                let current = OPOFrame(command: 0x810F, sequence: data[6], payload: [0x00, 0x01])
                return .reply([Data(late.encoded()), Data(current.encoded())])
            }
            firstSequence.value = data[6]
            return .none // first EQ read times out
        }
        try await transport.connect()
        let session = OPOv1Session(transport: transport, profile: DeviceRegistry.onePlusBuds3, replyTimeout: .milliseconds(150), now: { Date() })
        try await session.startSession()
        await #expect(throws: ProtocolError.timeout(command: 0x010F)) { _ = try await session.perform(.readEqualizer) }
        #expect(try await session.perform(.readEqualizer) == .equalizer(presetID: 1))
    }
}

final class LockedValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}


@MainActor
@Suite struct OptimisationTests {
    @Test func automaticReconnectsDoNotScan() async throws {
        let connector = ScriptedConnector(found: [])
        let manager = DeviceManager(connector: connector, reconnectDelays: [.milliseconds(30)])
        await manager.connect()
        for _ in 0..<50 where connector.discoveries.count < 3 { try await Task.sleep(for: .milliseconds(20)) }
        await manager.disconnect()
        #expect(connector.discoveries.first == true)             // user/startup connect may scan
        #expect(connector.discoveries.dropFirst().allSatisfy { !$0 }) // timer reconnects never scan
    }

    @Test func fastHexMatchesFormat() {
        let bytes: [UInt8] = [0x00, 0x0A, 0xAA, 0xFF, 0x3C]
        #expect(FastHex.string(bytes) == bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
        #expect(FastHex.string([]) == "")
    }
}
