enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, menuBar, connectionCard, demo, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .menuBar: "Menu Bar"
        case .connectionCard: "Connection Card"
        case .demo: "Demo"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .menuBar: "menubar.rectangle"
        case .connectionCard: "rectangle.on.rectangle"
        case .demo: "play.rectangle"
        case .about: "info.circle"
        }
    }
}
