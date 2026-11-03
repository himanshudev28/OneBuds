import OneBudsCore
import SwiftUI

/// A small capsule label for status such as Demo, Experimental or Verified.
struct Badge: View {
    let text: String
    let color: Color
    var help: String?

    static let experimental = Badge(text: "Experimental", color: .orange,
                                    help: "Built from documented protocol research but not yet verified on these earbuds.")
    static let demo = Badge(text: "Demo", color: .purple,
                            help: "Demo mode: simulated earbuds, no Bluetooth. Turn it off in Settings.")

    static func status(_ status: SupportStatus) -> Badge {
        switch status {
        case .verified: Badge(text: "Verified", color: .green, help: "Tested on hardware.")
        case .experimental: .experimental
        case .unsupported: Badge(text: "Unsupported", color: .secondary)
        case .unknown: Badge(text: "Unknown", color: .secondary, help: "Diagnostics only.")
        }
    }

    @Environment(\.quietBadges) private var quiet
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    /// System greens and oranges are too light to read on their own tint in Light mode.
    private var textBrightness: Double {
        guard colorScheme == .light else { return 0 }
        return contrast == .increased ? -0.35 : -0.2
    }

    var body: some View {
        Group {
            if quiet {
                // Main window: metadata, not a call to action.
                Text(text)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, Theme.Spacing.xsPlus - 1)
                    .padding(.vertical, 1)
                    .foregroundStyle(color)
                    .brightness(textBrightness)
                    .background(color.opacity(contrast == .increased ? 0.2 : 0.1), in: Capsule())
            } else {
                Text(text.uppercased())
                    .font(.caption2.bold())
                    .tracking(0.4)
                    .padding(.horizontal, Theme.Spacing.xs + 1)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .foregroundStyle(color)
                    .brightness(textBrightness)
                    .background(color.opacity(contrast == .increased ? 0.24 : 0.14), in: Capsule())
            }
        }
        .fixedSize()
        .help(help ?? text)
        .accessibilityLabel(text)
    }
}

private struct QuietBadgesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True in the main window, where badges are smaller and quieter than in the popover.
    var quietBadges: Bool {
        get { self[QuietBadgesKey.self] }
        set { self[QuietBadgesKey.self] = newValue }
    }
}
