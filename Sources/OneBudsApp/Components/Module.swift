import OneBudsCore
import SwiftUI

/// A Control Center–style module: one rounded surface holding one group of controls. Modules sit
/// side by side on the popover's material; they are never nested inside each other.
struct Module<Content: View>: View {
    var title: String?
    var presentation: CapabilityPresentation = .supported
    var padding: CGFloat = Theme.Spacing.m
    @ViewBuilder let content: () -> Content

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.module, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            if let title {
                SectionHeader(title: title, presentation: presentation)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(shape, standardFill: .quinary)
    }
}
