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

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.bold())
            .tracking(0.4)
            .padding(.horizontal, Theme.Spacing.xs + 1)
            .padding(.vertical, Theme.Spacing.xxs)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
            .help(help ?? text)
            .accessibilityLabel(text)
    }
}
