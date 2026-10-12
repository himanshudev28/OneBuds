import SwiftUI

/// A small accent-filled button that keeps its colour in windows that are never key, such as the
/// connection card's non-activating panel, where `.borderedProminent` would draw grey. Sized and
/// shaped like a small native prominent button; press darkens it (and scales unless Reduce Motion).
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.m - 2)
            .padding(.vertical, Theme.Spacing.xs - 1)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous)
                    .fill(Color.accentColor.gradient)
                    .brightness(configuration.isPressed ? -0.1 : isHovering ? 0.04 : 0)
            }
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .onHover { isHovering = $0 }
            .animation(Theme.Motion.hover, value: isHovering)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}
