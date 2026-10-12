import SwiftUI

/// Binds an animation to one value and swaps it for a short cross-fade under Reduce Motion.
struct StateAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Theme.Motion.reduced : animation, value: value)
    }
}
