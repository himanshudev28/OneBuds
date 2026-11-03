import OneBudsCore
import SwiftUI

/// Device name and connection state, with a connect / disconnect button.
struct PopoverHeader: View {
    @Environment(DeviceManager.self) private var manager

    private var subtitle: String {
        guard manager.connection.isConnected else { return manager.connection.displayText }
        return ["Connected", manager.transportKind?.displayName].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m - 2) {
            DeviceIcon(isConnected: manager.connection.isConnected, diameter: Theme.Size.popoverDeviceIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(manager.profile?.displayName ?? manager.earbuds?.name ?? "OneBuds")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.xs) {
                    if manager.connection.isBusy { ProgressView().controlSize(.mini) }
                    Text(subtitle)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if manager.isDemo { Badge.demo }
            ConnectionButton()
        }
        .animateState(value: subtitle)
    }
}

/// Power-style button: disconnects a connected pair, or connects again.
private struct ConnectionButton: View {
    @Environment(DeviceManager.self) private var manager
    @State private var isHovering = false

    private var connected: Bool { manager.connection.isConnected }

    var body: some View {
        Button {
            Task { if connected { await manager.disconnect() } else { await manager.connect() } }
        } label: {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(connected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 28, height: 28)
                .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: Circle())
        }
        .buttonStyle(.pressable)
        .disabled(manager.connection.isBusy)
        .onHover { isHovering = $0 }
        .help(connected ? "Disconnect OneBuds from the earbuds (audio stays connected)" : "Connect")
        .accessibilityLabel(connected ? "Disconnect" : "Connect")
    }
}
