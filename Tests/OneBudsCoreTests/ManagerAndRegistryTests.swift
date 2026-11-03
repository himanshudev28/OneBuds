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
        // Brand or family names never match; "OnePlus Buds" is a real model of its own (2020).
        for family in ["OnePlus", "OPPO Enco", "realme Buds", "Enco"] { #expect(DeviceRegistry.match(name: family) == nil) }
        #expect(DeviceRegistry.match(name: "OnePlus Buds")?.id == "oneplus-buds")
    }

    @Test func fallsBackToProductID() {
        #expect(DeviceRegistry.match(name: "Renamed buds", productID: "063c14")?.id == "oneplus-buds-3")
        #expect(DeviceRegistry.match(name: nil, productID: "FFFFFF") == nil)
    }

    @Test func unknownModelsAreDiagnosticsOnly() throws {
        // Legacy 1107 service: handshake not implemented, so diagnostics only.
        let budsPro = try #require(DeviceRegistry.match(name: "OnePlus Buds Pro"))
        #expect(!budsPro.allowsControlSession)
        #expect(Capability.allCases.allSatisfy { budsPro.presentation($0) == .hidden })
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
        #expect(DeviceRegistry.nordBuds3Pro.presentation(.customEqualizer) == .hidden)
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
    /// Routes `isRouteAvailable` reports as usable right now.
    var availableRoutes: Set<TransportKind> = []
    private(set) var routeChecks = 0
    func isRouteAvailable(_ kind: TransportKind, for earbuds: DiscoveredEarbuds) -> Bool {
        routeChecks += 1
        return availableRoutes.contains(kind)
    }
}

@MainActor
@Suite struct DeviceManagerTests {
    let buds3 = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["test"], transports: [.rfcomm, .ble])

    @Test func connectsAndPopulatesFromTheDevice() async {
        let manager = DeviceManager(connector: ScriptedConnector(found: [buds3]), reconnectDelays: [])
        await manager.connect()
        #expect(manager.connection == .connected)
        #expect(manager.transportKind == .ble) // GATT first (owner's choice, 2026-11-03)
        #expect(manager.transportAttempts == [TransportAttempt(kind: .ble, outcome: .connected)])
        #expect(manager.fallbackNote == nil)
        #expect(manager.battery?.left?.percent == 82)
        #expect(manager.noiseControl == .noiseCancelling(.smart))
        #expect(manager.deviceInfo?.productID == "063C14")
        #expect(manager.features[0x06] == false)
        #expect(!manager.gestures.isEmpty)
    }

    @Test func fallsBackToRFCOMMWhenGATTFails() async {
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.ble])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        #expect(connector.attempted == [.ble, .rfcomm])
        #expect(manager.transportKind == .rfcomm)
        #expect(manager.connection == .connected)
        #expect(manager.transportAttempts.map(\.kind) == [.ble, .rfcomm])
        #expect(manager.transportAttempts.last?.outcome == .connected)
        #expect(manager.fallbackNote?.hasSuffix("using RFCOMM") == true)
        #expect(manager.fallbackNote?.hasPrefix("GATT: ") == true)
    }

    @Test func rfcommFailureDoesNotMatterWhenGATTWorks() async {
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.rfcomm])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        #expect(connector.attempted == [.ble])
        #expect(manager.transportKind == .ble)
        #expect(manager.connection == .connected)
    }

    @Test func bothRoutesFailingNamesEachOne() async {
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.ble, .rfcomm])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        #expect(connector.attempted == [.ble, .rfcomm])
        guard case .failed(let message) = manager.connection else { Issue.record("expected failure"); return }
        #expect(message.contains("GATT: "))
        #expect(message.contains("RFCOMM: "))
        #expect(manager.transportKind == nil)
        #expect(manager.transportAttempts.count == 2)
    }

    @Test func transportOrderFollowsTheProfile() {
        let bleOnly = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["scan"], transports: [.ble])
        let classicOnly = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["paired"], transports: [.rfcomm])
        let buds3Profile = DeviceRegistry.onePlusBuds3
        #expect(DeviceManager.transportOrder(profile: buds3Profile, earbuds: buds3) == [.ble, .rfcomm])
        #expect(DeviceManager.transportOrder(profile: buds3Profile, earbuds: bleOnly) == [.ble])
        #expect(DeviceManager.transportOrder(profile: buds3Profile, earbuds: classicOnly) == [.rfcomm])
        #expect(DeviceManager.transportOrder(profile: DeviceRegistry.nordBuds3Pro, earbuds: buds3) == [.ble, .rfcomm])
        // A model without GATT parameters never gets GATT, even if discovery saw a BLE peripheral.
        #expect(DeviceManager.transportOrder(profile: DeviceRegistry.realmeBudsAir5, earbuds: buds3) == [.rfcomm])
    }

    @Test func transportOrderHonoursThePreference() {
        let buds3Profile = DeviceRegistry.onePlusBuds3
        let classicOnly = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["paired"], transports: [.rfcomm])
        #expect(DeviceManager.transportOrder(profile: buds3Profile, earbuds: buds3, preference: .rfcommOnly) == [.rfcomm])
        #expect(DeviceManager.transportOrder(profile: buds3Profile, earbuds: buds3, preference: .bleOnly) == [.ble])
        #expect(DeviceManager.transportOrder(profile: buds3Profile, earbuds: classicOnly, preference: .bleOnly) == [])
        let demo = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["demo"], transports: [.mock], isDemo: true)
        #expect(DeviceManager.transportOrder(profile: buds3Profile, earbuds: demo, preference: .rfcommOnly) == [.mock])
    }

    @Test func lastGoodRouteOnlyReorders() {
        let buds3Profile = DeviceRegistry.onePlusBuds3
        let classicOnly = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["paired"], transports: [.rfcomm])
        #expect(DeviceManager.transportOrder(profile: buds3Profile, earbuds: buds3, lastGood: .rfcomm) == [.rfcomm, .ble])
        #expect(DeviceManager.transportOrder(profile: buds3Profile, earbuds: classicOnly, lastGood: .ble) == [.rfcomm])
        #expect(DeviceManager.transportOrder(profile: buds3Profile, earbuds: buds3, preference: .bleOnly, lastGood: .rfcomm) == [.ble])
    }

    @Test func noAllowedRouteSendsNothingAndSaysWhy() async {
        let classicOnly = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["paired"], transports: [.rfcomm])
        let connector = ScriptedConnector(found: [classicOnly])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        manager.transportPreference = .bleOnly
        await manager.connect()
        #expect(connector.attempted.isEmpty)
        guard case .failed(let message) = manager.connection else { Issue.record("expected failure"); return }
        #expect(message.contains("Connection setting"))
    }

    @Test func automaticReconnectTriesTheLastGoodRouteFirst() async {
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.ble])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        #expect(manager.transportKind == .rfcomm)
        await manager.disconnect()
        await manager.connect(thorough: false) // automatic reconnect
        #expect(connector.attempted == [.ble, .rfcomm, .rfcomm])
        #expect(manager.fallbackNote == nil)
        await manager.disconnect()
        await manager.connect() // user-initiated: full order again, GATT first
        #expect(connector.attempted == [.ble, .rfcomm, .rfcomm, .ble, .rfcomm])
    }

    @Test func fallbackMemoryExpires() async {
        final class Clock: @unchecked Sendable { var date = Date(timeIntervalSince1970: 1_000_000) }
        let clock = Clock()
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.ble])
        let manager = DeviceManager(connector: connector, reconnectDelays: [], now: { clock.date })
        await manager.connect()
        await manager.disconnect()
        clock.date += DeviceManager.fallbackMemory - 1
        await manager.connect(thorough: false)
        #expect(connector.attempted == [.ble, .rfcomm, .rfcomm]) // still remembered
        await manager.disconnect()
        clock.date += DeviceManager.fallbackMemory + 1
        connector.failingKinds = []
        await manager.connect(thorough: false)
        #expect(connector.attempted == [.ble, .rfcomm, .rfcomm, .ble]) // expired: GATT first again
        #expect(manager.transportKind == .ble)
    }

    // MARK: Switching back to GATT

    private func fallbackManager(_ connector: ScriptedConnector) -> DeviceManager {
        DeviceManager(connector: connector, reconnectDelays: [], routeCheckInterval: .milliseconds(20))
    }

    @Test func switchesBackToGATTWhenItIsAvailableAgain() async throws {
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.ble])
        let manager = fallbackManager(connector)
        await manager.connect()
        #expect(manager.transportKind == .rfcomm)
        connector.failingKinds = []
        connector.availableRoutes = [.ble]
        for _ in 0..<100 where manager.transportKind != .ble || manager.isSwitchingRoute { try await Task.sleep(for: .milliseconds(20)) }
        #expect(manager.transportKind == .ble)
        #expect(manager.connection == .connected)
        #expect(connector.attempted == [.ble, .rfcomm, .ble])
        #expect(manager.transportAttempts == [TransportAttempt(kind: .ble, outcome: .connected)])
        #expect(manager.fallbackNote == nil)
        #expect(!manager.isSwitchingRoute)
        #expect(manager.battery != nil) // re-read over the new route
        await manager.disconnect()
    }

    @Test func failedSwitchReturnsToRFCOMMAndBacksOff() async throws {
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.ble])
        let manager = fallbackManager(connector)
        await manager.connect()
        connector.availableRoutes = [.ble] // visible, but opening it still fails
        for _ in 0..<100 where connector.attempted.count < 4 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(connector.attempted == [.ble, .rfcomm, .ble, .rfcomm])
        for _ in 0..<50 where manager.isSwitchingRoute { try await Task.sleep(for: .milliseconds(20)) }
        #expect(manager.transportKind == .rfcomm)
        #expect(manager.connection == .connected)
        try await Task.sleep(for: .milliseconds(200))
        #expect(connector.attempted.count == 4) // backing off (10 min) before the next try
        await manager.disconnect()
    }

    @Test func staysOnRFCOMMWhileGATTIsNotAvailable() async throws {
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.ble])
        let manager = fallbackManager(connector)
        await manager.connect()
        connector.failingKinds = []
        try await Task.sleep(for: .milliseconds(200))
        #expect(connector.routeChecks > 0)
        #expect(connector.attempted == [.ble, .rfcomm])
        #expect(manager.transportKind == .rfcomm)
        await manager.disconnect()
    }

    @Test func neverSwitchesWhileTheEarbudsAreRinging() async throws {
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.ble])
        let manager = fallbackManager(connector)
        await manager.connect()
        await manager.findEarbuds(ringing: true)
        #expect(manager.isRinging)
        connector.failingKinds = []
        connector.availableRoutes = [.ble]
        try await Task.sleep(for: .milliseconds(200))
        #expect(manager.transportKind == .rfcomm)
        await manager.findEarbuds(ringing: false)
        for _ in 0..<100 where manager.transportKind != .ble || manager.isSwitchingRoute { try await Task.sleep(for: .milliseconds(20)) }
        #expect(manager.transportKind == .ble)
        await manager.disconnect()
    }

    @Test func noSwitchBackUnderRFCOMMOnly() async throws {
        let connector = ScriptedConnector(found: [buds3])
        let manager = fallbackManager(connector)
        manager.transportPreference = .rfcommOnly
        await manager.connect()
        connector.availableRoutes = [.ble]
        try await Task.sleep(for: .milliseconds(150))
        #expect(connector.routeChecks == 0)
        #expect(connector.attempted == [.rfcomm])
        await manager.disconnect()
    }

    @Test func changingThePreferenceForgetsTheLastGoodRoute() async {
        let connector = ScriptedConnector(found: [buds3], failingKinds: [.ble])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        await manager.disconnect()
        manager.transportPreference = .rfcommOnly
        manager.transportPreference = .automatic
        connector.failingKinds = []
        await manager.connect(thorough: false)
        #expect(connector.attempted == [.ble, .rfcomm, .ble])
        #expect(manager.transportKind == .ble)
    }

    @Test func buds3IsVerifiedOnBothRoutes() async {
        let overGATT = DeviceManager(connector: ScriptedConnector(found: [buds3]), reconnectDelays: [])
        await overGATT.connect()
        #expect(overGATT.transportKind == .ble)
        #expect(overGATT.presentation(.battery) == .supported)
        #expect(overGATT.presentation(.noiseControl) == .supported)
        #expect(overGATT.presentation(.fitTest) != .supported) // Experimental stays Experimental

        let overRFCOMM = DeviceManager(connector: ScriptedConnector(found: [buds3]), reconnectDelays: [])
        overRFCOMM.transportPreference = .rfcommOnly
        await overRFCOMM.connect()
        #expect(overRFCOMM.transportKind == .rfcomm)
        #expect(overRFCOMM.presentation(.battery) == .supported)
        #expect(overRFCOMM.presentation(.noiseControl) == .supported)
    }

    @Test func profileSupportPerTransport() {
        #expect(DeviceRegistry.onePlusBuds3.verifiedTransports == [.rfcomm, .ble])
        var profile = DeviceRegistry.onePlusBuds3
        profile.verifiedTransports = [.rfcomm] // as before the GATT test
        #expect(profile.support(.battery, over: .rfcomm) == .verified)
        #expect(profile.support(.battery, over: .ble) == .experimental)
        #expect(profile.support(.battery, over: .mock) == .verified) // Demo mirrors the profile
        #expect(profile.support(.battery, over: nil) == .verified)
        #expect(profile.support(.fitTest, over: .rfcomm) == .experimental) // never upgraded
        #expect(DeviceRegistry.realmeBudsAir5.support(.battery, over: .rfcomm) == .experimental)
        // Nothing may claim Verified over a route without evidence for it.
        for profile in DeviceRegistry.all where profile.capabilities.values.contains(.verified) {
            #expect(!profile.verifiedTransports.isEmpty, "\(profile.id) has Verified capabilities but no verified transport")
        }
    }

    @Test func bleServiceListComesFromTheProfiles() {
        let services = DeviceRegistry.bleServiceUUIDs
        #expect(services == [DeviceRegistry.opoService.uppercased()])
        #expect(!services.contains { $0.hasPrefix("00001107") }) // legacy RFCOMM UUID, not a GATT service
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

    @Test func reportedProductIDPicksTheRightProfile() async {
        // Named like Buds 4, but the earbuds report Buds 3's product id (as a special edition would).
        let connector = ScriptedConnector(found: [DiscoveredEarbuds(name: "OnePlus Buds 4", discoveryPaths: ["test"], transports: [.rfcomm])])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        #expect(manager.connection == .connected)
        #expect(manager.profile?.id == "oneplus-buds-3")
        #expect(manager.earbuds?.productID == "063C14")
        #expect(connector.attempted == [.rfcomm, .rfcomm]) // retried once on the same route, nothing else
        #expect(manager.fallbackNote == nil) // a profile switch is not a route fallback
        #expect(manager.transportAttempts == [TransportAttempt(kind: .rfcomm, outcome: .connected)])
        await manager.disconnect()
        await manager.connect() // remembered: no second mismatch
        #expect(manager.profile?.id == "oneplus-buds-3")
        #expect(connector.attempted.count == 3)
        await manager.disconnect()
    }

    @Test func unknownOrSharedProductIDStillStops() async {
        // A product id no profile claims (or two claim) never switches profiles.
        #expect(DeviceRegistry.match(name: nil, productID: "060C12") == nil) // Enco Buds2 and realme Buds Q2s
        #expect(DeviceRegistry.match(name: nil, productID: "FFFFFF") == nil)
    }

    @Test func unknownModelGetsNoSession() async {
        // Legacy 1107 service: recognised, diagnostics only.
        let connector = ScriptedConnector(found: [DiscoveredEarbuds(name: "OnePlus Buds Pro", discoveryPaths: ["test"], transports: [.rfcomm])])
        let manager = DeviceManager(connector: connector, reconnectDelays: [])
        await manager.connect()
        #expect(manager.connection == .unrecognised(name: "OnePlus Buds Pro"))
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
