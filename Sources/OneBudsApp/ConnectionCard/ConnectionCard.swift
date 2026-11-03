import OneBudsCore
import SwiftUI

/// What the card can say about the battery. Levels are only ever the earbuds' own report.
enum BatteryReading: Equatable {
    case levels(BatteryStatus)
    /// Connected and the model reports battery, but the first read has not completed yet.
    case waiting
    /// The model does not report battery, or the read finished without levels.
    case notReported
    /// The read failed or timed out.
    case unavailable

    static func resolve(battery: BatteryStatus?, presentation: CapabilityPresentation, refresh: DeviceManager.OperationStatus) -> BatteryReading {
        if let battery, !battery.isEmpty, presentation != .hidden { return .levels(battery) }
        guard presentation != .hidden else { return .notReported }
        switch refresh {
        case .idle, .pending: return .waiting
        case .failed, .timedOut: return .unavailable
        case .confirmed: return .notReported
        }
    }
}

/// Compact "your earbuds are connected" card: device artwork, model, live status and the battery
/// levels the earbuds reported. Pure inputs, so it renders the same in the floating panel,
/// snapshots and tests.
struct ConnectionCard: View {
    let modelName: String
    /// The Bluetooth name, when it differs from the model name (e.g. renamed earbuds).
    var deviceName: String?
    let connection: DeviceManager.ConnectionState
    var transport: String?
    let battery: BatteryReading
    var isDemo = false
    var artwork: EarbudArtwork = .none
    var animatesArtwork = true
    var onOpen: () -> Void = {}
    var onDismiss: () -> Void = {}

    private var statusColor: Color {
        switch connection {
        case .connected: .green
        case .searching, .connecting, .handshaking: .yellow
        default: .secondary
        }
    }

    /// "Connecting…" covers the last half second of the handshake, while the card is already up.
    private var statusText: String { connection.isBusy ? "Connecting…" : connection.displayText }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Spacing.l) {
                EarbudVisual(artwork: artwork, size: Theme.Size.cardArtwork, animates: animatesArtwork)
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    header
                    batteryArea
                }
            }
            .padding(.leading, Theme.Spacing.m)
            .padding([.top, .bottom, .trailing], Theme.Spacing.l)

            Divider()

            HStack(spacing: Theme.Spacing.s) {
                if let transport {
                    Label(transport, systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.s)
                // The card's panel is never key (it must not take focus from the app in front), so
                // the native prominent style would draw grey; this one keeps the accent.
                Button("Open OneBuds", action: onOpen)
                    .buttonStyle(.accent)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m - 2)
        }
        .frame(width: Theme.Size.cardWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(modelName), \(statusText)")
    }

    /// Model name and the dismiss button share the first line; the status sits under the name.
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(alignment: .center, spacing: Theme.Spacing.xsPlus) {
                Text(modelName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isDemo { Badge.demo }
                Spacer(minLength: Theme.Spacing.s)
                dismissButton
            }
            if let deviceName {
                Text(deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: Theme.Spacing.xsPlus) {
                Circle()
                    .fill(statusColor)
                    .frame(width: Theme.Size.statusDot, height: Theme.Size.statusDot)
                    .accessibilityHidden(true)
                Text(statusText)
                    .contentTransition(.opacity)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.dismissButton, height: Theme.Size.dismissButton)
                .background(.quaternary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .help("Dismiss")
        .accessibilityLabel("Dismiss")
    }

    /// Fixed height, so the card does not change size when the first battery read arrives. Waiting
    /// shows the same three slots as the levels will, so nothing moves when they land.
    private var batteryArea: some View {
        ZStack(alignment: .leading) {
            switch battery {
            case .levels(let status):
                BatteryRow(battery: status, size: .compact)
                    .transition(.opacity)
            case .waiting:
                BatteryRow(waitingWith: .compact)
                    .transition(.opacity)
            case .notReported, .unavailable:
                Label(battery == .unavailable ? "Battery unavailable" : "Battery not reported", systemImage: "battery.0percent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Size.cardBatteryArea, alignment: .leading)
        .animateState(value: battery)
    }
}
