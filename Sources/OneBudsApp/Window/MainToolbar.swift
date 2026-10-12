import OneBudsCore
import SwiftUI

/// Window toolbar: connection actions and the Demo marker.
struct MainToolbar: ToolbarContent {
    let manager: DeviceManager

    private var isRefreshing: Bool { manager.status(of: .refresh) == .pending }

    var body: some ToolbarContent {
        ToolbarItem(placement: .status) {
            if manager.isDemo { Badge.demo }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if manager.connection.isConnected {
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(isRefreshing)
                    .help("Read every setting from the earbuds again (⌘R)")
                Button("Disconnect", systemImage: "xmark.circle", action: disconnect)
                    .help("Close the control channel")
            } else {
                Button("Connect", systemImage: "link", action: connect)
                    .disabled(manager.connection.isBusy)
                    .help("Look for connected earbuds")
            }
        }
    }

    private func refresh() { Task { await manager.refresh() } }
    private func connect() { Task { await manager.connect() } }
    private func disconnect() { Task { await manager.disconnect() } }
}
