import SwiftUI

private struct VisualStyleKey: EnvironmentKey {
    static let defaultValue = VisualStyle.standard
}

extension EnvironmentValues {
    /// The user's chosen surface style, injected at each scene root.
    var visualStyle: VisualStyle {
        get { self[VisualStyleKey.self] }
        set { self[VisualStyleKey.self] = newValue }
    }
}
