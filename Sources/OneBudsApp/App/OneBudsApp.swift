import OneBudsCore
import SwiftUI

@main
struct OneBudsApp: App {
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

        Settings {
            SettingsView()
                .environment(model)
                .environment(model.manager)
                .environment(\.visualStyle, model.settings.visualStyle)
        }
    }
}
