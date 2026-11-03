import Foundation
import Testing
@testable import OneBudsCore

@MainActor
@Suite struct CapabilityEngineTests {
    nonisolated static let controllableIDs = DeviceRegistry.all.filter(\.allowsControlSession).map(\.id)

    private func profile(_ id: String) throws -> DeviceProfile {
        try #require(DeviceRegistry.all.first { $0.id == id })
    }

    private func info(_ productID: String?, bits: [Int] = [], firmware: String? = nil) -> DeviceInfo {
        var info = DeviceInfo(productID: productID)
        info.capabilityBits = bits
        info.firmwareRaw = firmware
        return info
    }

    // MARK: Agreement with today's behaviour

    /// For every controllable model, the engine offers exactly what the app offers today.
    @Test(arguments: controllableIDs)
    func matchesManagerPresentation(_ id: String) async throws {
        let profile = try profile(id)
        let manager = DeviceManager(connector: DemoConnector(profile: profile), reconnectDelays: [])
        await manager.connect()
        try #require(manager.connection == .connected)
        let input = CapabilityInput(name: manager.earbuds?.name, advertisedProductID: manager.earbuds?.productID,
                                    discoveredTransports: manager.earbuds?.transports ?? [],
                                    activeTransport: manager.transportKind, deviceInfo: manager.deviceInfo)
        let report = CapabilityEngine.evaluate(input)
        #expect(report.profileID == id)
        #expect(report.identification == .reportedProductID)
        for capability in Capability.allCases {
            #expect(report.presentation(capability) == manager.presentation(capability), "\(id) \(capability)")
        }
    }

    /// The same agreement over the GATT and RFCOMM routes, where Verified depends on the route.
    @Test(arguments: controllableIDs, [TransportKind.ble, .rfcomm])
    func matchesManagerOverRealRoutes(_ id: String, _ route: TransportKind) async throws {
        let profile = try profile(id)
        guard profile.transports.contains(route) else { return }
        let manager = DeviceManager(connector: RouteConnector(profile: profile, route: route), reconnectDelays: [])
        await manager.connect()
        try #require(manager.connection == .connected)
        #expect(manager.transportKind == route)
        let report = CapabilityEngine.evaluate(CapabilityInput(name: manager.earbuds?.name, discoveredTransports: [route],
                                                               activeTransport: route, attempts: manager.transportAttempts,
                                                               deviceInfo: manager.deviceInfo))
        for capability in Capability.allCases {
            #expect(report.presentation(capability) == manager.presentation(capability), "\(id) over \(route) \(capability)")
        }
        #expect(report.protocols.first { $0.kind == route }?.opened == true)
    }

    /// Special editions (no name of their own) connected under the base model's name, as real ones are.
    nonisolated static let editions: [(edition: String, baseName: String)] = DeviceRegistry.all.compactMap { edition in
        guard edition.allowsControlSession, edition.bluetoothNames.isEmpty,
              let cut = edition.displayName.range(of: " (") else { return nil }
        let baseName = String(edition.displayName[..<cut.lowerBound])
        guard DeviceRegistry.match(name: baseName) != nil else { return nil }
        return (edition.id, baseName)
    }

    @Test(arguments: editions.map(\.edition))
    func editionUnderBaseNameKeepsItsControls(_ id: String) async throws {
        let edition = try profile(id)
        let baseName = try #require(Self.editions.first { $0.edition == id }?.baseName)
        let route = edition.transports.first ?? .rfcomm
        let manager = DeviceManager(connector: RouteConnector(profile: edition, route: route, name: baseName, advertises: false),
                                    reconnectDelays: [])
        await manager.connect()
        try #require(manager.connection == .connected, "\(id) under \(baseName): \(manager.connection)")
        #expect(manager.profile?.id == id)
        let report = try #require(manager.capabilityReport)
        #expect(report.profileID == id)
        #expect(report.identification == .reportedProductID)
        #expect(!report.offered.isEmpty)
        for capability in Capability.allCases {
            #expect(report.presentation(capability) == manager.presentation(capability), "\(id) \(capability)")
        }
    }

    /// Product ids are compared as uppercase hex everywhere; keep the registry in that form.
    @Test func registryProductIDsAreUppercase() {
        for profile in DeviceRegistry.all {
            for id in profile.opo?.productIDs ?? [] { #expect(id == id.uppercased(), "\(profile.id): \(id)") }
        }
    }

    /// Every capability a profile rates has the protocol parameters its commands need. Guards new models.
    @Test(arguments: DeviceRegistry.all.map(\.id))
    func ratedCapabilitiesHaveParameters(_ id: String) throws {
        let profile = try profile(id)
        guard profile.allowsControlSession, let opo = profile.opo else { return }
        for (capability, status) in profile.capabilities where status == .verified || status == .experimental {
            #expect(CapabilityEngine.missingParameters(for: capability, in: opo) == nil, "\(id) rates \(capability) but lacks parameters")
        }
    }

    // MARK: Identification

    @Test func unrecognisedDeviceGetsNothing() {
        let report = CapabilityEngine.evaluate(CapabilityInput(name: "Some Headphones", discoveredTransports: [.rfcomm]))
        #expect(report.identification == .unrecognised)
        #expect(report.profileID == nil)
        #expect(report.offered.isEmpty)
        #expect(report.verdicts.allSatisfy { $0.status == .unknown && $0.evidence == [.unrecognisedDevice] })
    }

    // These use profile copies so registry updates (a model gaining support) do not change them.

    @Test func unknownRegistryModelIsDiagnosticsOnly() {
        var unknown = DeviceRegistry.onePlusBuds3
        unknown.status = .unknown
        let report = CapabilityEngine.evaluate(CapabilityInput(name: "OnePlus Buds 3", deviceInfo: info("063C14")), in: [unknown])
        #expect(report.profileID == unknown.id)
        #expect(report.offered.isEmpty)
        #expect(report.verdict(.battery)?.evidence == [.modelNotControllable(.unknown)])
    }

    @Test func unsupportedModelIsNeverControlled() {
        var unsupported = DeviceRegistry.onePlusBuds3
        unsupported.status = .unsupported
        let report = CapabilityEngine.evaluate(CapabilityInput(name: "OnePlus Buds 3", deviceInfo: info("063C14")), in: [unsupported])
        #expect(report.offered.isEmpty)
        #expect(report.verdict(.battery)?.status == .unsupported)
    }

    @Test func reportedProductIDIdentifiesARenamedDevice() {
        let report = CapabilityEngine.evaluate(CapabilityInput(name: "My earbuds", deviceInfo: info("063C14")))
        #expect(report.profileID == DeviceRegistry.onePlusBuds3.id)
        #expect(report.identification == .reportedProductID)
        #expect(report.offered.contains(.noiseControl))
    }

    @Test func advertisedProductIDIsOnlyAMatchNotConfirmation() {
        let (profile, how) = CapabilityEngine.identify(name: "My earbuds", advertisedProductID: "063C14")
        #expect(profile?.id == DeviceRegistry.onePlusBuds3.id)
        #expect(how == .advertisedProductID)
    }

    @Test func nameAndProductIDConflictHidesEverything() {
        // An id no profile claims: the name cannot be confirmed.
        let report = CapabilityEngine.evaluate(CapabilityInput(name: "OnePlus Buds 3", deviceInfo: info("FFFFFF")))
        #expect(report.identification == .conflict)
        #expect(report.offered.isEmpty)
        #expect(!report.isConfirmed)
    }

    @Test func advertisedProductIDConflictIsCaught() {
        let (_, how) = CapabilityEngine.identify(name: "OnePlus Buds 3", advertisedProductID: "FFFFFF")
        #expect(how == .conflict)
    }

    @Test func productIDsMatchWhateverTheCase() {
        let (profile, how) = CapabilityEngine.identify(name: nil, reportedProductID: "063c14")
        #expect(profile?.id == DeviceRegistry.onePlusBuds3.id)
        #expect(how == .reportedProductID)
    }

    /// A special edition shares the base model's name; its own product id selects it (as DeviceManager does).
    @Test func specialEditionIsSelectedByItsProductID() {
        let base = DeviceRegistry.nordBuds3Pro
        var edition = base
        edition.id = "edition"
        edition.bluetoothNames = []
        edition.opo?.productIDs = ["0ABCDE"]
        let (profile, how) = CapabilityEngine.identify(name: base.displayName, reportedProductID: "0ABCDE", in: [base, edition])
        #expect(profile?.id == "edition")
        #expect(how == .reportedProductID)
        let report = CapabilityEngine.evaluate(CapabilityInput(name: base.displayName, deviceInfo: info("0ABCDE")), in: [base, edition])
        #expect(!report.offered.isEmpty)
    }

    @Test func sharedProductIDNeverSelectsAProfileAlone() {
        var first = DeviceRegistry.realmeBudsT300, second = DeviceRegistry.realmeBudsAir5
        first.opo?.productIDs = ["060C12"]
        second.opo?.productIDs = ["060C12"]
        let (profile, how) = CapabilityEngine.identify(name: "Unnamed buds", reportedProductID: "060C12", in: [first, second])
        #expect(profile == nil)
        #expect(how == .unrecognised)
        // The exact name still decides, and the shared id then confirms it.
        let (named, namedHow) = CapabilityEngine.identify(name: second.displayName, reportedProductID: "060C12", in: [first, second])
        #expect(named?.id == second.id)
        #expect(namedHow == .reportedProductID)
    }

    @Test func profileWithoutProductIDsStaysMatchedByName() {
        var custom = DeviceRegistry.nordBuds3Pro
        custom.opo?.productIDs = []
        let (profile, how) = CapabilityEngine.identify(name: custom.displayName, reportedProductID: "ABCDEF", in: [custom])
        #expect(profile?.id == custom.id)
        #expect(how == .bluetoothName)
    }

    // MARK: Verification rules

    @Test func missingBitmapBitHidesAFeature() {
        // Bit 5 (find my earbuds) absent from the list the earbuds sent.
        let report = CapabilityEngine.evaluate(CapabilityInput(name: "OnePlus Buds 3", activeTransport: .rfcomm,
                                                               deviceInfo: info("063C14", bits: [3, 8, 9])))
        #expect(report.presentation(.findEarbuds) == .hidden)
        #expect(report.verdict(.findEarbuds)?.evidence.contains(.bitmapLacks(bits: [5])) == true)
        #expect(report.verdict(.noiseCycle)?.evidence.contains(.bitmapOffers(bits: [8])) == true)
        // Basics are not gated by bits.
        #expect(report.presentation(.noiseControl) == .supported)
    }

    @Test func noBitmapIsRecorded() {
        let report = CapabilityEngine.evaluate(CapabilityInput(name: "OnePlus Buds 3", deviceInfo: info("063C14")))
        #expect(report.verdict(.fitTest)?.evidence.contains(.noBitmapReported) == true)
    }

    @Test func ratingWithoutParametersIsUnsupported() {
        var profile = DeviceRegistry.nordBuds3Pro
        profile.capabilities[.dualConnection] = .experimental
        profile.opo?.dualConnectionFeatureID = nil  // rated, but no switch id to send
        let verdict = CapabilityEngine.verdict(for: .dualConnection, profile: profile, identification: .reportedProductID,
                                               input: CapabilityInput(name: profile.displayName))
        #expect(verdict.status == .unsupported)
        #expect(verdict.evidence.contains(.missingProtocolParameters("dual connection switch id")))
    }

    @Test func neverWritableSwitchIsNotOffered() {
        var opo = DeviceRegistry.onePlusBuds3.opo!
        opo.gameModeFeatureID = 0x18  // Hi-Res: never written
        #expect(CapabilityEngine.missingParameters(for: .gameMode, in: opo) != nil)
    }

    /// Buds 3 verified on RFCOMM only (a copy, so registry updates do not change the test).
    private var rfcommOnlyBuds3: DeviceProfile {
        var profile = DeviceRegistry.onePlusBuds3
        profile.verifiedTransports = [.rfcomm]
        return profile
    }

    @Test func verifiedOnlyOverItsTransport() {
        let profiles = [rfcommOnlyBuds3]
        let report = CapabilityEngine.evaluate(CapabilityInput(name: "OnePlus Buds 3", activeTransport: .ble, deviceInfo: info("063C14")), in: profiles)
        #expect(report.verdict(.noiseControl)?.status == .experimental)
        #expect(report.verdict(.noiseControl)?.evidence.contains(.notVerifiedOver(.ble)) == true)
        let overRFCOMM = CapabilityEngine.evaluate(CapabilityInput(name: "OnePlus Buds 3", activeTransport: .rfcomm, deviceInfo: info("063C14")), in: profiles)
        #expect(overRFCOMM.verdict(.noiseControl)?.status == .verified)
    }

    @Test func reportedValuesAreEvidenceNotRequirements() {
        let input = CapabilityInput(name: "OnePlus Buds 3", activeTransport: .rfcomm, deviceInfo: info("063C14"), reported: [.battery])
        let report = CapabilityEngine.evaluate(input)
        #expect(report.verdict(.battery)?.reportedByDevice == true)
        #expect(report.verdict(.equalizer)?.reportedByDevice == false)
        #expect(report.presentation(.equalizer) == .supported)
    }

    // MARK: Protocols

    @Test func protocolsReflectDiscoveryAndAttempts() {
        let input = CapabilityInput(name: "OnePlus Buds 3", discoveredTransports: [.rfcomm, .ble], activeTransport: .rfcomm,
                                    attempts: [TransportAttempt(kind: .ble, outcome: .failed("service not found")),
                                               TransportAttempt(kind: .rfcomm, outcome: .connected)],
                                    deviceInfo: info("063C14"))
        let protocols = CapabilityEngine.evaluate(input, in: [rfcommOnlyBuds3]).protocols
        let ble = protocols.first { $0.kind == .ble }, rfcomm = protocols.first { $0.kind == .rfcomm }
        #expect(ble == ProtocolSupport(kind: .ble, listedInProfile: true, foundOnDevice: true, opened: false,
                                       failure: "service not found", verified: false))
        #expect(rfcomm == ProtocolSupport(kind: .rfcomm, listedInProfile: true, foundOnDevice: true, opened: true, verified: true))
    }

    @Test func realmeHasNoGATTRoute() {
        let protocols = CapabilityEngine.evaluate(CapabilityInput(name: "realme Buds Air 5", discoveredTransports: [.rfcomm])).protocols
        #expect(protocols.first { $0.kind == .ble }?.listedInProfile == false)
    }

    // MARK: Cache

    /// A throwaway defaults suite, removed when the test ends.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "onebuds.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func confirmedReport(firmware: String? = "127.127.101", bits: [Int] = [3, 5, 8, 9],
                                 at time: TimeInterval = 1_000) -> CapabilityReport {
        CapabilityEngine.evaluate(CapabilityInput(name: "OnePlus Buds 3", activeTransport: .rfcomm,
                                                  deviceInfo: info("063C14", bits: bits, firmware: firmware)),
                                  now: Date(timeIntervalSince1970: time))
    }

    @Test func cacheStoresOnlyConfirmedReportsWithFirmware() {
        withDefaults { defaults in
            let cache = CapabilityCache(defaults: defaults)
            cache.store(CapabilityEngine.evaluate(CapabilityInput(name: "OnePlus Buds 3")))  // name only
            cache.store(confirmedReport(firmware: nil))
            #expect(cache.count == 0)
            cache.store(confirmedReport())
            #expect(cache.count == 1)
        }
    }

    @Test func cacheSurvivesRelaunchAndChecksTheLiveSession() {
        withDefaults { defaults in
            let buds3 = DeviceRegistry.onePlusBuds3
            let report = confirmedReport()
            CapabilityCache(defaults: defaults).store(report)
            let relaunched = CapabilityCache(defaults: defaults)
            #expect(relaunched.entry(for: buds3)?.report == report)
            #expect(relaunched.entry(for: buds3, live: info("063C14", bits: [3, 5, 8, 9], firmware: "127.127.101"))?.report == report)
            #expect(relaunched.entry(for: buds3, live: info("063C14", bits: [3, 5, 8, 9], firmware: "128.0.1")) == nil)
            #expect(relaunched.entry(for: buds3, live: info("063C14", bits: [3, 8], firmware: "127.127.101")) == nil)
            relaunched.removeAll()
            #expect(CapabilityCache(defaults: defaults).entry(for: buds3) == nil)
        }
    }

    @Test func cacheIgnoresEntriesFromAChangedProfile() {
        withDefaults { defaults in
            let cache = CapabilityCache(defaults: defaults)
            cache.store(confirmedReport())
            var changed = DeviceRegistry.onePlusBuds3
            changed.capabilities[.gameMode] = .unsupported
            #expect(cache.entry(for: changed) == nil)
            #expect(cache.entry(for: DeviceRegistry.onePlusBuds3) != nil)
        }
    }

    @Test func cacheDoesNotRewriteAnUnchangedReport() {
        withDefaults { defaults in
            let cache = CapabilityCache(defaults: defaults)
            cache.store(confirmedReport(at: 1_000), now: Date(timeIntervalSince1970: 1_000))
            cache.store(confirmedReport(at: 2_000), now: Date(timeIntervalSince1970: 2_000))
            #expect(cache.entry(for: DeviceRegistry.onePlusBuds3)?.savedAt == Date(timeIntervalSince1970: 1_000))
        }
    }

    @Test func cacheEvictsTheOldestEntries() {
        withDefaults { defaults in
            let cache = CapabilityCache(defaults: defaults)
            for index in 0..<(CapabilityCache.maximumEntries + 3) {
                var report = confirmedReport()
                report.profileID = "model-\(index)"
                cache.store(report, now: Date(timeIntervalSince1970: TimeInterval(index)))
            }
            #expect(cache.count == CapabilityCache.maximumEntries)
            var oldest = DeviceRegistry.onePlusBuds3
            oldest.id = "model-0"
            #expect(cache.entry(for: oldest) == nil)
        }
    }

    @Test func managerCachesRealSessionsButNotDemo() async throws {
        try await withDefaultsAsync { defaults in
            let cache = CapabilityCache(defaults: defaults)
            let buds3 = DeviceRegistry.onePlusBuds3
            let demo = DeviceManager(connector: DemoConnector(profile: buds3), reconnectDelays: [], capabilityCache: cache)
            await demo.connect()
            #expect(demo.capabilityReport?.isConfirmed == true)
            #expect(cache.count == 0)

            let manager = DeviceManager(connector: RouteConnector(profile: buds3, route: .rfcomm), reconnectDelays: [], capabilityCache: cache)
            await manager.connect()
            try #require(manager.connection == .connected)
            #expect(manager.capabilityReport?.verdict(.battery)?.reportedByDevice == true)
            #expect(manager.cachedCapabilities == nil)
            let saved = try #require(cache.entry(for: buds3))
            #expect(saved.report.hasSameContent(as: try #require(manager.capabilityReport)))

            await manager.disconnect()
            #expect(manager.capabilityReport == nil)
        }
    }

    private func withDefaultsAsync(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let name = "onebuds.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    @Test func reportRoundTripsThroughJSON() throws {
        let report = confirmedReport()
        let decoded = try JSONDecoder().decode(CapabilityReport.self, from: JSONEncoder().encode(report))
        #expect(decoded == report)
    }
}

/// Connects to the simulator over a named route, so the manager behaves as on GATT or RFCOMM.
@MainActor
private final class RouteConnector: DeviceConnector {
    let isDemo = false
    let profile: DeviceProfile
    let route: TransportKind
    let name: String?
    let advertises: Bool
    let simulator: MockEarbudsSimulator

    /// - Parameters:
    ///   - name: the Bluetooth name to report (default: the profile's own).
    ///   - advertises: include the product id as a BLE advertisement would.
    init(profile: DeviceProfile, route: TransportKind, name: String? = nil, advertises: Bool = true) {
        self.profile = profile
        self.route = route
        self.name = name
        self.advertises = advertises
        simulator = MockEarbudsSimulator(profile: profile)
    }

    func availability() async -> BluetoothAvailability { .ready }

    func discover(thorough: Bool) async -> [DiscoveredEarbuds] {
        // Variants without a name of their own are found by product id, as in the demo connector.
        [DiscoveredEarbuds(name: name ?? profile.bluetoothNames.first ?? profile.displayName,
                           productID: advertises ? profile.opo?.productIDs.first : nil,
                           discoveryPaths: ["test"], transports: [route])]
    }

    func makeTransport(for earbuds: DiscoveredEarbuds, kind: TransportKind) -> (any EarbudTransport)? {
        let simulator = self.simulator
        return MockTransport(framesOnConnect: simulator.framesOnConnect()) { data in await simulator.handle(data) }
    }

    func describe(_ transport: any EarbudTransport) -> String? { nil }

    func deviceChanges() -> AsyncStream<Void> { AsyncStream { _ in } }
}
