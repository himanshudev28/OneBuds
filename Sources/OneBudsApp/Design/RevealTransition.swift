import SwiftUI

/// Insertion/removal for inline content: a short slide plus fade, or only a fade under Reduce Motion.
struct RevealTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let edge: Edge

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: edge)))
    }
}
