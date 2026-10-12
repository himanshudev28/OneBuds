import AppKit
import Observation
import OneBudsBluetooth
import OneBudsCore

/// App-level state and actions shared by the popover, the main window and Settings.
@MainActor
@Observable
final class AppModel {
    static let mainWindowID = "main"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let bluetoothPrivacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!

    let manager: DeviceManager
    let settings: AppSettings
    let launchAtLogin = LaunchAtLogin()
    let diagnostics = DiagnosticsModel()
    let connectionCard: ConnectionCardPresenter
    private var connectionCardPanel: ConnectionCardPanel?
    /// Opens a SwiftUI window by id; captured from the menu-bar label, which is always in the scene.
    var openWindow: ((String) -> Void)?
    /// Main-window sidebar selection.
    var selection: SidebarItem? = .overview
    private var wakeObserver: NSObjectProtocol?

    init() {
        let settings = AppSettings()
        self.settings = settings
        let manager = DeviceManager(connector: settings.demoMode ? DemoConnector(profile: settings.demoProfile) : BluetoothConnector())
        self.manager = manager
        connectionCard = ConnectionCardPresenter(manager: manager, settings: settings)
        connectionCard.openOverview = { [weak self] in self?.showOverview() }
    }

    func start() {
        Task { @MainActor in self.settings.appearance.apply() }
        if let file = FeatureTest.outputFile {
            Task { await FeatureTest.run(model: self, to: file) }
            return
        }
        if let file = SelfTest.outputFile {
            Task { await SelfTest.run(model: self, to: file) }
            return
        }
        if let directory = ArtworkCheck.outputDirectory {
            Task { await ArtworkCheck.run(to: directory) }
            return
        }
        if let directory = Snapshotter.outputDirectory {
            Task { await Snapshotter.run(model: self, to: directory) }
            return
        }
        let panel = ConnectionCardPanel(presenter: connectionCard, manager: manager, settings: settings)
        connectionCardPanel = panel
        connectionCard.host = panel
        connectionCard.start()
        manager.start()
        // After sleep, wait for Bluetooth to settle, then re-check the earbuds.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [manager] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                await manager.handleWake()
            }
        }
    }

    func setDemoMode(_ enabled: Bool) async {
        settings.setDemoMode(enabled)
        await manager.useConnector(enabled ? DemoConnector(profile: settings.demoProfile) : BluetoothConnector())
    }

    /// Switches the simulated model; the app re-reads everything and adapts its controls.
    func setDemoModel(_ id: String) async {
        settings.setDemoModel(id)
        if settings.demoMode { await manager.useConnector(DemoConnector(profile: settings.demoProfile)) }
    }

    /// Brings up the main window on the Overview screen.
    func showOverview() {
        selection = .overview
        openWindow?(Self.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openBluetoothPrivacySettings() {
        NSWorkspace.shared.open(Self.bluetoothPrivacyURL)
    }

    var connectionSummary: String {
        var lines = ["State: \(manager.connection.displayText)"]
        if let earbuds = manager.earbuds {
            lines.append("Device: \(earbuds.name)\(manager.isDemo ? " (DEMO)" : "")")
            lines.append("Discovery: \(earbuds.discoveryPaths.joined(separator: ", "))")
        }
        if let kind = manager.transportKind { lines.append("Transport: \(kind.displayName)") }
        if let detail = manager.transportDetail { lines.append("Channel: \(detail)") }
        if let profile = manager.profile { lines.append("Profile: \(profile.displayName) (\(profile.status.displayName))") }
        if let info = manager.deviceInfo {
            lines.append("Product id: \(info.productID ?? "—") · Firmware: \(info.firmwareSummary ?? "—")")
        }
        return lines.joined(separator: "\n")
    }
}
