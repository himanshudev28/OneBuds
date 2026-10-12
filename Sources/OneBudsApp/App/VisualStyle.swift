/// Surface style. `glass` uses translucent, glass-like surfaces (real Liquid Glass on macOS 26+
/// when built with the macOS 26 SDK); it falls back to `standard` under Reduce Transparency.
enum VisualStyle: String, CaseIterable, Identifiable {
    case standard, glass

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .glass: "Glass"
        }
    }
}
