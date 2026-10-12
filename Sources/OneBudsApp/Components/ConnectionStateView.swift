import AppKit
import OneBudsCore
import SwiftUI

/// Native empty state for the main window when nothing controllable is connected.
struct ConnectionStateView: View {
    @Environment(AppModel.self) private var model
    @Environment(DeviceManager.self) private var manager

    private var content: ConnectionStateContent { ConnectionStateContent(state: manager.connection) }

    var body: some View {
        ContentUnavailableView {
            Label(content.title, systemImage: content.symbol)
        } description: {
            if let detail = content.detail { Text(detail) }
        } actions: {
            if manager.connection.isBusy {
                ProgressView().controlSize(.small)
            } else if content.action != nil {
                Button(content.actionTitle, action: performAction)
            }
        }
    }

    private func performAction() {
        switch content.action {
        case .openPrivacySettings: model.openBluetoothPrivacySettings()
        case .helpAddModel: model.selection = .diagnostics
        case .retry: Task { await manager.connect() }
        case nil: break
        }
    }
}
