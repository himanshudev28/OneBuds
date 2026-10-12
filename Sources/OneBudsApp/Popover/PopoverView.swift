import OneBudsCore
import SwiftUI

/// The primary interface: battery, noise control and quick toggles, one click from the menu bar.
struct PopoverView: View {
    @Environment(DeviceManager.self) private var manager

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            PopoverHeader()

            if manager.connection.isConnected {
                PopoverControls()
                    .transition(.opacity)
            } else {
                CompactConnectionStateView()
                    .transition(.opacity)
            }

            if let error = manager.lastError, manager.connection.isConnected {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            Divider()
            PopoverFooter()
        }
        .padding(Theme.Spacing.l - 2)
        .frame(width: Theme.Size.popoverWidth)
        .animateState(value: manager.connection.isConnected)
        .animateState(value: manager.lastError)
    }
}
