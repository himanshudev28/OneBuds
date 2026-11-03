import AppKit
import SwiftUI

/// Keyboard focus for custom-styled buttons: the system focus colour, drawn just outside `shape`.
/// The caller owns the focus state (`@FocusState` + `.focused(_:)` on the button) and pairs this
/// with `.focusEffectDisabled()`, so exactly one ring is drawn.
struct FocusRing<S: InsettableShape>: ViewModifier {
    let shape: S
    let isFocused: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isFocused {
                shape
                    .inset(by: -Theme.Stroke.focus - 1)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: Theme.Stroke.focus)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func focusRing<S: InsettableShape>(_ shape: S, isFocused: Bool) -> some View {
        modifier(FocusRing(shape: shape, isFocused: isFocused))
    }
}
