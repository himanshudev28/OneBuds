import SwiftUI

extension View {
    /// Animates changes of `value` with `animation` (cross-fade under Reduce Motion).
    func animateState<Value: Equatable>(_ animation: Animation = Theme.Motion.standard, value: Value) -> some View {
        modifier(StateAnimation(animation: animation, value: value))
    }

    /// Transition for content that appears inline below or above its trigger.
    func revealTransition(from edge: Edge = .top) -> some View {
        modifier(RevealTransition(edge: edge))
    }
}
