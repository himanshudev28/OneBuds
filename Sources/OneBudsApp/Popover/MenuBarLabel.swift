import OneBudsCore
import SwiftUI

/// What the menu-bar item shows: a symbol, optional battery text, and a Demo marker.
/// Shared by the SwiftUI label (macOS 14) and the AppKit status item (macOS 15+).
@MainActor
struct MenuBarLabelContent: Equatable {
    var symbol: String
    var text: String?
    var accessibilityLabel: String

    init(manager: DeviceManager, settings: AppSettings) {
        switch manager.connection {
        case .connected: symbol = "earbuds"
        case .unauthorized, .failed, .bluetoothOff, .bluetoothUnsupported: symbol = "exclamationmark.triangle"
        default: symbol = "earbuds.case"
        }
        var parts: [String] = []
        if settings.showBatteryInMenuBar, manager.connection.isConnected, let bud = manager.battery?.lowestBud {
            parts.append("\(bud.percent)%")
        }
        if manager.isDemo { parts.append("Demo") }
        text = parts.isEmpty ? nil : parts.joined(separator: " ")
        accessibilityLabel = "OneBuds: \(manager.connection.displayText)"
    }
}

/// Menu-bar label for the macOS 14 `MenuBarExtra` path.
struct MenuBarLabel: View {
    let manager: DeviceManager
    let settings: AppSettings
    /// Receives the scene's window opener once the label is on screen.
    var onAppear: (OpenWindowAction) -> Void = { _ in }
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let content = MenuBarLabelContent(manager: manager, settings: settings)
        HStack(spacing: Theme.Spacing.xs - 1) {
            Image(systemName: content.symbol)
            if let text = content.text { Text(text).monospacedDigit() }
        }
        .accessibilityLabel(content.accessibilityLabel)
        .onAppear { onAppear(openWindow) }
    }
}
