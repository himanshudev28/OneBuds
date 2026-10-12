import OneBudsCore
import SwiftUI

/// One registry entry: status at a glance, details on demand.
struct ProfileCompatibilityRow: View {
    let profile: DeviceProfile

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.Spacing.m - 2) {
                LabeledContent("Product ID", value: profile.opo?.productIDs.joined(separator: ", ") ?? "—")
                LabeledContent("Transports", value: profile.transports.map(\.displayName).joined(separator: " → "))
                if !profile.capabilities.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.l, verticalSpacing: Theme.Spacing.xs) {
                        ForEach(Capability.allCases) { capability in
                            GridRow {
                                Text(capability.displayName)
                                Badge.status(profile.support(capability))
                            }
                        }
                    }
                }
                ForEach(profile.limitations, id: \.self) { limitation in
                    Label(limitation, systemImage: "info.circle").font(.caption)
                }
                ForEach(profile.evidence) { evidence in
                    Label("\(evidence.date): \(evidence.what)", systemImage: "checkmark.seal").font(.caption)
                }
                Text("Sources: \(profile.sources.joined(separator: ", ")) (Documentation/ProtocolSources.md)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Theme.Spacing.s - 2)
        } label: {
            HStack {
                Text(profile.displayName)
                Spacer()
                Badge.status(profile.status)
            }
        }
    }
}
