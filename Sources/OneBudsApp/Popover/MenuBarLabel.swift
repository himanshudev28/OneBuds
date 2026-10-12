import OneBudsCore
import SwiftUI

/// Menu-bar icon (template symbol), optional battery percentage, and a Demo marker.
struct MenuBarLabel: View {
    let manager: DeviceManager
    let settings: AppSettings
    /// Receives the scene's window opener once the label is on screen.
    var onAppear: (OpenWindowAction) -> Void = { _ in }
    @Environment(\.openWindow) private var openWindow

    private var symbol: String {
        switch manager.connection {
        case .connected: "earbuds"
        case .unauthorized, .failed, .bluetoothOff, .bluetoothUnsupported: "exclamationmark.triangle"
        default: "earbuds.case"
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs - 1) {
            Image(systemName: symbol)
            if settings.showBatteryInMenuBar, manager.connection.isConnected, let bud = manager.battery?.lowestBud {
                Text("\(bud.percent)%").monospacedDigit()
            }
            if manager.isDemo { Text("Demo") }
        }
        .accessibilityLabel("OneBuds: \(manager.connection.displayText)")
        .onAppear { onAppear(openWindow) }
    }
}
