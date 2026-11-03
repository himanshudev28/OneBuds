import SwiftUI

/// Design tokens shared by every view, so spacing, shape and motion stay consistent.
enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        /// Icon-to-label gaps inside compact rows.
        static let xsPlus: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        /// Small controls: chips, compact buttons.
        static let control: CGFloat = 8
        /// Selectable tiles (noise modes, EQ presets).
        static let tile: CGFloat = 10
        /// Popover modules (Control Center style).
        static let module: CGFloat = 14
    }

    enum Stroke {
        /// Hairline borders on tiles and cards.
        static let hairline: CGFloat = 1
        /// Keyboard focus ring.
        static let focus: CGFloat = 2.5
    }

    enum Size {
        static let popoverWidth: CGFloat = 340
        static let popoverDeviceIcon: CGFloat = 32
        static let heroDeviceIcon: CGFloat = 56
        static let statusDot: CGFloat = 7
        static let detailMinWidth: CGFloat = 480
        static let detailMinHeight: CGFloat = 440
        /// Rows of rings or tiles stop growing here, so they stay a single glance wide.
        static let controlRowMaxWidth: CGFloat = 520
        static let cardWidth: CGFloat = 360
        static let cardArtwork: CGFloat = 88
        /// Battery ring plus its caption, reserved even before the first read.
        static let cardBatteryArea: CGFloat = 66
        static let cardRadius: CGFloat = 18
        static let dismissButton: CGFloat = 20
        /// Popover noise buttons.
        static let noiseCircle: CGFloat = 46
        static let noiseSymbol: CGFloat = 18
        /// Popover navigation tile icon.
        static let tileIcon: CGFloat = 30
        static let eqEditorHeight: CGFloat = 200
        /// Label rows above and below each EQ fader track (including their spacing).
        static let faderTopLabel: CGFloat = 20
        static let faderBottomLabel: CGFloat = 18
        /// Leading symbol column in switch rows, so labels line up whatever the symbol.
        static let rowIcon: CGFloat = 22
        /// Popover sub-pages scroll beyond this height.
        static let popoverPageMaxHeight: CGFloat = 430
    }

    /// Noise-mode tiles: icon over label, equal widths.
    enum Tile {
        static let iconCompact: CGFloat = 15
        static let iconRegular: CGFloat = 19
        static let heightCompact: CGFloat = 54
        static let heightRegular: CGFloat = 68
        /// Window tiles: quieter and shorter than the popover's.
        static let heightWindow: CGFloat = 58
        static let iconWindow: CGFloat = 17
    }

    /// Battery ring metrics per context.
    enum Ring {
        case compact, regular, large

        var diameter: CGFloat {
            switch self {
            case .compact: 42
            case .regular: 48
            case .large: 64
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .compact: 4
            case .regular: 4.5
            case .large: 6
            }
        }

        var numberFont: Font {
            switch self {
            case .compact: .system(.footnote, design: .rounded).weight(.semibold)
            case .regular: .system(.callout, design: .rounded).weight(.semibold)
            case .large: .system(.title3, design: .rounded).weight(.semibold)
            }
        }

        var percentFont: Font {
            switch self {
            case .compact, .regular: .system(size: 8, weight: .semibold, design: .rounded)
            case .large: .system(.caption2, design: .rounded).weight(.semibold)
            }
        }
    }

    enum Battery {
        /// Levels below these read as low / critical.
        static let low = 30
        static let critical = 15

        static func tint(for percent: Int) -> Color {
            switch percent {
            case ..<critical: .red
            case ..<low: .orange
            default: .green
            }
        }

        /// Opacity of the unfilled track behind the level arc.
        static let trackOpacity: Double = 0.2
        static let trackOpacityIncreasedContrast: Double = 0.4
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
        /// Moving between the popover's pages.
        static let page = Animation.spring(duration: 0.32, bounce: 0)
        /// How long a "confirmed by the earbuds" note stays visible.
        static let confirmationVisible: Duration = .seconds(2)
    }
}
