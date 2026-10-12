import SwiftUI

extension View {
    /// Grouped-form styling shared by every Settings pane (macos-settings-ui guidance).
    func settingsPaneStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, Theme.Spacing.s, for: .scrollContent)
    }
}
