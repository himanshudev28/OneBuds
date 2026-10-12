import SwiftUI

/// The standard macOS Settings window (⌘,), with toolbar-style tabs.
struct SettingsView: View {
    @State private var selection: SettingsTab

    init(tab: SettingsTab = .general) {
        _selection = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsPane()
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage) }
                .tag(SettingsTab.general)
            AppearanceSettingsPane()
                .tabItem { Label(SettingsTab.appearance.title, systemImage: SettingsTab.appearance.systemImage) }
                .tag(SettingsTab.appearance)
            MenuBarSettingsPane()
                .tabItem { Label(SettingsTab.menuBar.title, systemImage: SettingsTab.menuBar.systemImage) }
                .tag(SettingsTab.menuBar)
            ConnectionCardSettingsPane()
                .tabItem { Label(SettingsTab.connectionCard.title, systemImage: SettingsTab.connectionCard.systemImage) }
                .tag(SettingsTab.connectionCard)
            DemoSettingsPane()
                .tabItem { Label(SettingsTab.demo.title, systemImage: SettingsTab.demo.systemImage) }
                .tag(SettingsTab.demo)
            AboutSettingsPane()
                .tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.systemImage) }
                .tag(SettingsTab.about)
        }
        .frame(width: 520)
        .frame(minHeight: 300)
        .windowGlass()
        .onAppear(perform: AppActivationPolicy.enter)
        .onDisappear(perform: AppActivationPolicy.leave)
    }
}
