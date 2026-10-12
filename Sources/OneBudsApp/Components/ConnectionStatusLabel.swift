import OneBudsCore
import SwiftUI

/// Coloured dot plus connection text; a native spinner replaces the dot while busy.
struct ConnectionStatusLabel: View {
    @Environment(DeviceManager.self) private var manager

    private var color: Color {
        switch manager.connection {
        case .connected: .green
        case .searching, .connecting, .handshaking: .yellow
        case .failed, .unauthorized, .bluetoothOff, .bluetoothUnsupported: .red
        default: .secondary
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s - 3) {
            if manager.connection.isBusy {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: Theme.Size.statusDot, height: Theme.Size.statusDot)
                    .accessibilityHidden(true)
            }
            Text(manager.connection.displayText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
