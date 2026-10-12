import OneBudsCore
import SwiftUI

extension NoiseCategory {
    /// The mode requested when this category is chosen; for noise cancelling the earbuds pick the level.
    var requestedMode: NoiseControlMode {
        switch self {
        case .off: .off
        case .transparency: .transparency
        case .noiseCancelling: .noiseCancelling(nil)
        case .adaptive: .adaptive
        }
    }

    /// Full name for menus and descriptions (the segmented label uses the short "ANC").
    var menuTitle: String {
        self == .noiseCancelling ? "Noise Cancelling" : displayName
    }

    /// Same key for the same mode on every model: ⌘1 Off, ⌘2 ANC, ⌘3 Transparency, ⌘4 Adaptive.
    var shortcutKey: KeyEquivalent {
        switch self {
        case .off: "1"
        case .noiseCancelling: "2"
        case .transparency: "3"
        case .adaptive: "4"
        }
    }

    var explanation: String {
        switch self {
        case .off: "No processing; normal listening."
        case .noiseCancelling: "Reduces background noise. Choose a level where the model offers them."
        case .transparency: "Lets surrounding sound in so you can hear what's around you."
        case .adaptive: "Adjusts noise cancelling to your surroundings automatically."
        }
    }
}
