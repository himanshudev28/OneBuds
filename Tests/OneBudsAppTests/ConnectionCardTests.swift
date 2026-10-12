import Foundation
import Testing
@testable import OneBudsApp
import OneBudsCore

@MainActor
final class FakeCardHost: ConnectionCardHost {
    private(set) var shows = 0
    private(set) var hides = 0
    func show() { shows += 1 }
    func hide() { hides += 1 }
}

@MainActor
@Suite(.serialized) struct ConnectionCardPresenterTests {
    let host = FakeCardHost()
    let manager = DeviceManager(connector: DemoConnector(), reconnectDelays: [])
    let settings = AppSettings(defaults: UserDefaults(suiteName: "onebuds-tests-\(UUID().uuidString)")!)

    func makePresenter(visible: Duration = .seconds(30), afterHover: Duration = .milliseconds(100)) -> ConnectionCardPresenter {
        let presenter = ConnectionCardPresenter(manager: manager, settings: settings,
                                                timing: .init(visible: visible, afterHover: afterHover, exit: .milliseconds(20)))
        presenter.host = host
        presenter.start()
        return presenter
    }

    /// The card comes up during the handshake, before `connect()` returns; watch for it meanwhile.
    func connectUntilCardShows(_ presenter: ConnectionCardPresenter) async -> Bool {
        Task { await manager.connect() }
        return await waitUntil(timeout: .seconds(2), interval: .milliseconds(5)) { presenter.isVisible }
    }

    @Test func appearsOnceWhenEarbudsConnect() async {
        let presenter = makePresenter()
        #expect(!presenter.isVisible)
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { presenter.isVisible })
        #expect(presenter.presentation?.modelName == "OnePlus Buds 3")
        #expect(presenter.presentation?.isDemo == true)
        #expect(presenter.presentation?.artwork == EarbudArtwork.none, "no licensed artwork ships")
        // Routine refreshes and re-reads never bring it up again.
        await manager.refresh()
        await manager.handleWake()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(host.shows == 1)
        #expect(presenter.announcements == 1)
    }

    @Test func appearsWhileTheHandshakeIsStillRunning() async {
        let presenter = makePresenter()
        #expect(await connectUntilCardShows(presenter))
        // The session start includes ~300 ms of documented pacing; the card is already up by then.
        #expect(manager.connection == .handshaking)
        #expect(presenter.presentation?.modelName == "OnePlus Buds 3")
        #expect(await waitUntil(timeout: .seconds(3)) { manager.connection == .connected })
        #expect(host.shows == 1, "completing the handshake does not show it again")
    }

    @Test func quickReconnectsAreEachAnnounced() async {
        let presenter = makePresenter()
        for round in 1...3 {
            await manager.connect()
            #expect(await waitUntil(timeout: .seconds(2)) { presenter.isVisible })
            #expect(presenter.announcements == round)
            await manager.disconnect()
            #expect(await waitUntil(timeout: .seconds(2)) { !presenter.isVisible })
        }
        #expect(host.shows == 3)
    }

    @Test func dismissAnimatesOutThenHidesThePanel() async {
        let presenter = makePresenter()
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { presenter.isVisible })
        presenter.dismiss()
        #expect(!presenter.isVisible)
        #expect(presenter.presentation != nil, "kept for the exit transition")
        #expect(host.hides == 0)
        #expect(await waitUntil(timeout: .seconds(1)) { host.hides == 1 && presenter.presentation == nil })
    }

    @Test func dismissesItselfAfterTheVisibleTime() async {
        let presenter = makePresenter(visible: .milliseconds(150))
        #expect(await connectUntilCardShows(presenter))
        #expect(await waitUntil(timeout: .seconds(2)) { !presenter.isVisible && host.hides == 1 })
    }

    @Test func hoverKeepsItUntilThePointerLeaves() async {
        let presenter = makePresenter(visible: .milliseconds(100), afterHover: .milliseconds(100))
        #expect(await connectUntilCardShows(presenter))
        presenter.setHovering(true)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(presenter.isVisible)
        presenter.setHovering(false)
        #expect(await waitUntil(timeout: .seconds(2)) { !presenter.isVisible })
    }

    @Test func hoverDoesNotOutliveTheCard() async {
        let presenter = makePresenter(visible: .milliseconds(150))
        #expect(await connectUntilCardShows(presenter))
        // Pointer on the card when it is clicked away: no hover-exit arrives.
        presenter.setHovering(true)
        presenter.dismiss()
        presenter.present()
        #expect(await waitUntil(timeout: .seconds(2)) { !presenter.isVisible }, "auto-dismiss still runs")
    }

    @Test func reconnectShowsItAgain() async {
        let presenter = makePresenter()
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { presenter.isVisible })
        await manager.disconnect()
        // Disconnecting takes the card away.
        #expect(await waitUntil(timeout: .seconds(2)) { !presenter.isVisible && host.hides == 1 })
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { presenter.isVisible && host.shows == 2 })
        #expect(presenter.announcements == 2)
    }

    @Test func preferenceOffSuppressesAutomaticCardsOnly() async {
        settings.showConnectionCard = false
        let presenter = makePresenter()
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { presenter.announcements == 1 })
        #expect(!presenter.isVisible && host.shows == 0)
        // Earbuds ▸ Show Connection Card still works.
        presenter.present()
        #expect(presenter.isVisible && host.shows == 1)
    }

    @Test func manualPresentNeedsAConnection() {
        let presenter = makePresenter()
        presenter.present()
        #expect(!presenter.isVisible && host.shows == 0)
    }

    @Test func openOverviewRunsTheActionAndDismisses() async {
        let presenter = makePresenter()
        var opened = 0
        presenter.openOverview = { opened += 1 }
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { presenter.isVisible })
        presenter.openDeviceOverview()
        #expect(opened == 1)
        #expect(!presenter.isVisible)
    }
}

@Suite struct BatteryReadingTests {
    let levels = BatteryStatus(left: .init(percent: 80, isCharging: false), right: .init(percent: 76, isCharging: false))

    @Test func showsOnlyReportedLevels() {
        #expect(BatteryReading.resolve(battery: levels, presentation: .supported, refresh: .confirmed(Date())) == .levels(levels))
        if case .levels(let status) = BatteryReading.resolve(battery: levels, presentation: .experimental, refresh: .pending) {
            #expect(status.chargingCase == nil, "a missing case level is not invented")
        } else {
            Issue.record("expected levels")
        }
    }

    @Test func waitsWhileTheFirstReadRuns() {
        #expect(BatteryReading.resolve(battery: nil, presentation: .supported, refresh: .pending) == .waiting)
        #expect(BatteryReading.resolve(battery: nil, presentation: .supported, refresh: .idle) == .waiting)
        #expect(BatteryReading.resolve(battery: BatteryStatus(), presentation: .supported, refresh: .pending) == .waiting)
    }

    @Test func saysNotReportedWhenNothingCame() {
        #expect(BatteryReading.resolve(battery: nil, presentation: .supported, refresh: .confirmed(Date())) == .notReported)
        #expect(BatteryReading.resolve(battery: nil, presentation: .supported, refresh: .timedOut) == .unavailable)
        #expect(BatteryReading.resolve(battery: nil, presentation: .supported, refresh: .failed("x")) == .unavailable)
        #expect(BatteryReading.resolve(battery: levels, presentation: .hidden, refresh: .confirmed(Date())) == .notReported)
    }
}

@Suite struct EarbudArtworkTests {
    /// A throwaway bundle directory with the given files in `EarbudAssets/`.
    func bundle(with files: [String]) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("onebuds-artwork-\(UUID().uuidString)")
        let folder = root.appendingPathComponent(EarbudArtwork.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files { try Data("x".utf8).write(to: folder.appendingPathComponent(file)) }
        return try #require(Bundle(url: root))
    }

    @Test func nothingInstalledMeansTheSymbol() throws {
        let artwork = EarbudArtwork.lookup(profileID: "oneplus-buds-3", in: try bundle(with: []))
        #expect(artwork == .none)
        #expect(artwork.summary == "No licensed artwork installed")
        #expect(EarbudArtwork.lookup(profileID: nil, in: try bundle(with: ["oneplus-buds-3.usdz"])) == .none)
    }

    @Test func findsModelAndRenderByProfileIDOnly() throws {
        let assets = try bundle(with: ["oneplus-buds-3.usdz", "oneplus-buds-3.png", "oneplus-nord-buds-3-pro.heic"])
        let buds3 = EarbudArtwork.lookup(profileID: "oneplus-buds-3", in: assets)
        #expect(buds3.model?.lastPathComponent == "oneplus-buds-3.usdz")
        #expect(buds3.render?.lastPathComponent == "oneplus-buds-3.png")
        let nord = EarbudArtwork.lookup(profileID: "oneplus-nord-buds-3-pro", in: assets)
        #expect(nord.model == nil && nord.render?.pathExtension == "heic")
        #expect(EarbudArtwork.lookup(profileID: "realme-buds-air-5", in: assets) == .none, "never borrows another model's artwork")
    }

    @Test func settingNarrowsButNeverAddsArtwork() {
        let both = EarbudArtwork(model: URL(fileURLWithPath: "/a.usdz"), render: URL(fileURLWithPath: "/a.png"))
        #expect(both.restricted(to: .automatic) == both)
        #expect(both.restricted(to: .image) == EarbudArtwork(render: both.render))
        #expect(both.restricted(to: .symbol) == .none)
        #expect(EarbudArtwork(model: both.model).restricted(to: .image) == .none)
    }
}

@MainActor
@Suite(.serialized) struct ConnectionCardSettingsTests {
    @Test func untilClosedNeverDismissesOnItsOwn() async {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "onebuds-tests-\(UUID().uuidString)")!)
        settings.cardDuration = .untilClosed
        let manager = DeviceManager(connector: DemoConnector(), reconnectDelays: [])
        let presenter = ConnectionCardPresenter(manager: manager, settings: settings, timing: .init(afterHover: .milliseconds(50), exit: .milliseconds(20)))
        let host = FakeCardHost()
        presenter.host = host
        presenter.start()
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { presenter.isVisible })
        presenter.setHovering(true)
        presenter.setHovering(false)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(presenter.isVisible)
        await manager.disconnect()
        #expect(await waitUntil(timeout: .seconds(2)) { !presenter.isVisible }, "a disconnect still takes it away")
    }

    @Test func artworkSettingAppliesToTheCard() async {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "onebuds-tests-\(UUID().uuidString)")!)
        settings.cardArtworkStyle = .symbol
        let manager = DeviceManager(connector: DemoConnector(), reconnectDelays: [])
        let presenter = ConnectionCardPresenter(manager: manager, settings: settings)
        presenter.start()
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { presenter.isVisible })
        #expect(presenter.presentation?.artwork == EarbudArtwork.none)
        presenter.dismiss()
    }

    @Test func preferencesPersist() {
        let defaults = UserDefaults(suiteName: "onebuds-tests-\(UUID().uuidString)")!
        let first = AppSettings(defaults: defaults)
        #expect(first.cardDuration == .standard && first.cardArtworkStyle == .automatic && first.animateCardModel)
        first.cardDuration = .long
        first.cardArtworkStyle = .image
        first.animateCardModel = false
        let second = AppSettings(defaults: defaults)
        #expect(second.cardDuration == .long && second.cardArtworkStyle == .image && !second.animateCardModel)
    }
}
