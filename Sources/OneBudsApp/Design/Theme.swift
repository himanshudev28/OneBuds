import SwiftUI

/// Design tokens shared by every view, so spacing, shape and motion stay consistent.
enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 12
    }

    enum Size {
        static let popoverWidth: CGFloat = 340
        static let popoverDeviceIcon: CGFloat = 30
        static let heroDeviceIcon: CGFloat = 56
        static let modeButton: CGFloat = 40
        static let modeButtonLarge: CGFloat = 52
        static let batteryRing: CGFloat = 50
        static let batteryRingLarge: CGFloat = 68
        static let statusDot: CGFloat = 7
        static let detailMinWidth: CGFloat = 480
        static let detailMinHeight: CGFloat = 440
        static let cardWidth: CGFloat = 360
        static let cardArtwork: CGFloat = 96
        /// Battery ring plus its caption, reserved even before the first read.
        static let cardBatteryArea: CGFloat = 72
        static let cardRadius: CGFloat = 18
    }

    /// Motion follows Emil Kowalski's and Apple's guidance: critically damped springs (no bounce),
    /// under 300 ms, only for state changes; cross-fades replace movement under Reduce Motion.
    enum Motion {
        /// Content appearing, disappearing or changing state.
        static let standard = Animation.spring(duration: 0.25, bounce: 0)
        /// A selection highlight moving between options.
        static let selection = Animation.spring(duration: 0.3, bounce: 0)
        /// Press feedback.
        static let press = Animation.easeOut(duration: 0.12)
        /// Hover tint.
        static let hover = Animation.easeOut(duration: 0.12)
        /// Reduce Motion: a short cross-fade instead of movement.
        static let reduced = Animation.easeInOut(duration: 0.15)
        /// The connection card arriving: the one moment that earns a slight overshoot.
        static let cardEnter = Animation.spring(duration: 0.45, bounce: 0.18)
        /// The connection card leaving: quicker than it arrived.
        static let cardExit = Animation.easeOut(duration: 0.2)
        /// How long a "confirmed by the earbuds" note stays visible.
        static let confirmationVisible: Duration = .seconds(2)
    }
}
