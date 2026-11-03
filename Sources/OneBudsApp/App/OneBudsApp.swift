import AppKit
import OneBudsCore
import SwiftUI

/// Picks the app definition for this macOS: 15+ uses the custom menu-bar panel (animated, closes
/// on outside clicks); 14 keeps SwiftUI's `MenuBarExtra`, because hiding the main window at launch
/// without it needs a macOS 15 scene modifier.
@main
enum OneBudsMain {
    static func main() {
        if #available(macOS 15, *) {
            OneBudsApp.main()
        } else {
            OneBudsLegacyApp.main()
        }
    }
}

@available(macOS 15, *)
struct OneBudsApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        MenuBarAppDelegate.model = model
        model.start()
    }

    var body: some Scene {
        MainWindowScene(model: model)
            .defaultLaunchBehavior(.suppressed)
        SettingsScene(model: model)
    }
}

/// Owns the menu-bar item on macOS 15+, and keeps the app running with no windows open.
@MainActor
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?
    private var menuBar: MenuBarPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model = Self.model else { return }
        menuBar = MenuBarPanelController(model: model)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Opening the app from Finder or Spotlight while it's running shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { Self.model?.showOverview() }
        return true
    }
}

/// macOS 14: the original `MenuBarExtra` scene.
struct OneBudsLegacyApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(model)
                .environment(model.manager)
                .environment(\.visualStyle, model.settings.visualStyle)
        } label: {
            MenuBarLabel(manager: model.manager, settings: model.settings) { [model] openWindow in
                model.openWindow = { openWindow(id: $0) }
            }
        }
        .menuBarExtraStyle(.window)

        MainWindowScene(model: model)
        SettingsScene(model: model)
    }
}

struct MainWindowScene: Scene {
    let model: AppModel

    var body: some Scene {
        Window("OneBuds", id: AppModel.mainWindowID) {
            MainWindow()
                .environment(model)
                .environment(model.manager)
                .environment(\.visualStyle, model.settings.visualStyle)
        }
        .defaultSize(width: 880, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            EarbudsCommands(model: model)
        }
    }
}

struct SettingsScene: Scene {
    let model: AppModel

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(model)
                .environment(model.manager)
                .environment(\.visualStyle, model.settings.visualStyle)
        }
    }
}
