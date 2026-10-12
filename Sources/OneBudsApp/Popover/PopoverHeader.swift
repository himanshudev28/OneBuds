import OneBudsCore
import SwiftUI

struct PopoverHeader: View {
    @Environment(DeviceManager.self) private var manager

    var body: some View {
        HStack(spacing: Theme.Spacing.m - 2) {
            DeviceIcon(isConnected: manager.connection.isConnected, diameter: Theme.Size.popoverDeviceIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(manager.earbuds?.name ?? "OneBuds")
                    .font(.headline)
                    .lineLimit(1)
                ConnectionStatusLabel()
            }
            Spacer(minLength: 0)
            if manager.isDemo { Badge.demo }
        }
        .accessibilityElement(children: .combine)
    }
}
