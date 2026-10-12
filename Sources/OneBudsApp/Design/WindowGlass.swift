import SwiftUI

/// Window-level style: under Glass the content area becomes translucent (desktop blur shows through
/// grouped forms); otherwise the normal opaque window background is kept.
struct WindowGlass: ViewModifier {
    @Environment(\.visualStyle) private var visualStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if visualStyle == .glass && !reduceTransparency {
            content
                .scrollContentBackground(.hidden)
                .background(VisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
        } else {
            content
        }
    }
}

extension View {
    /// Grouped form styling for main-window screens, translucent under the Glass style.
    func screenFormStyle() -> some View {
        formStyle(.grouped).modifier(WindowGlass())
    }

    func windowGlass() -> some View {
        modifier(WindowGlass())
    }
}
