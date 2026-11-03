import OneBudsCore
import SwiftUI

/// Header of the Overview screen, in the System Settings AirPods style: a centred glyph, the
/// name, status and details, then the battery levels directly beneath.
struct DeviceHeroCard: View {
    @Environment(DeviceManager.self) private var manager

    /// Transport · firmware · last update, whichever are known.
    private var details: String? {
        guard let kind = manager.transportKind else { return nil }
        return [kind.displayName,
                manager.deviceInfo?.firmwareSummary.map { "Firmware \($0)" },
                manager.lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var showsBattery: Bool {
        manager.connection.isConnected && manager.presentation(.battery) != .hidden
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            glyph
            VStack(spacing: Theme.Spacing.xsPlus) {
                Text(manager.earbuds?.name ?? "No Earbuds")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: Theme.Spacing.xsPlus) {
                    ConnectionStatusLabel(font: .subheadline)
                    if manager.isDemo { Badge.demo }
                    if let profile = manager.profile { Badge.status(profile.status) }
                }
                if let details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                if manager.isSwitchingRoute {
                    Label("Switching back to the preferred control channel…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if let note = manager.fallbackNote {
                    Label(note, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .help("OneBuds tried the preferred control channel first and fell back to the next one.")
                }
            }
            if showsBattery { battery }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.m)
        .animateState(value: manager.connection)
    }

    private var glyph: some View {
        let connected = manager.connection.isConnected
        return Image(systemName: connected ? "earbuds" : "earbuds.case")
            .font(.system(size: 52))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(connected ? Color.accentColor : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 96, height: 96)
            .background(
                Circle().fill(connected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.12))
            )
            .accessibilityHidden(true)
    }

    private var battery: some View {
        VStack(spacing: Theme.Spacing.s) {
            if manager.presentation(.battery) == .experimental {
                HStack(spacing: Theme.Spacing.xsPlus) {
                    Text("Battery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CapabilityBadge(presentation: .experimental)
                }
            }
            if let battery = manager.battery, !battery.isEmpty {
                BatteryRow(battery: battery, size: .regular)
                    .frame(maxWidth: 340)
            } else {
                Label("The earbuds haven't reported battery levels yet.", systemImage: "battery.0percent")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }
}
