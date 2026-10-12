import OneBudsCore
import SwiftUI

/// Section title with an optional capability badge.
struct SectionHeader: View {
    let title: String
    var presentation: CapabilityPresentation = .supported

    var body: some View {
        HStack(spacing: Theme.Spacing.s - 2) {
            Text(title)
            CapabilityBadge(presentation: presentation)
        }
    }
}
