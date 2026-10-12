import OneBudsCore
import SwiftUI

/// Header of the Overview screen: device, status and connection summary.
struct DeviceHeroCard: View {
    @Environment(DeviceManager.self) private var manager

    private var subtitle: String? {
        guard let kind = manager.transportKind else { return nil }
        return [kind.displayName, manager.deviceInfo?.firmwareSummary.map { "Firmware \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            DeviceIcon(isConnected: manager.connection.isConnected, diameter: Theme.Size.heroDeviceIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s - 2) {
                    Text(manager.earbuds?.name ?? "No Earbuds")
                        .font(.title2.bold())
                        .lineLimit(1)
                    if manager.isDemo { Badge.demo }
                    if let profile = manager.profile { Badge.status(profile.status) }
                }
                ConnectionStatusLabel()
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let updated = manager.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .animateState(value: manager.connection)
    }
}
