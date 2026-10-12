import AppKit
import OneBudsCore
import SwiftUI

/// Popover version of the empty state (the header already names the state).
struct CompactConnectionStateView: View {
    @Environment(AppModel.self) private var model
    @Environment(DeviceManager.self) private var manager
    @Environment(\.openWindow) private var openWindow

    private var content: ConnectionStateContent { ConnectionStateContent(state: manager.connection) }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: content.symbol)
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let detail = content.detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if manager.connection.isBusy {
                ProgressView().controlSize(.small)
            } else if content.action != nil {
                Button(content.actionTitle, action: performAction)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.m)
    }

    private func performAction() {
        switch content.action {
        case .openPrivacySettings: model.openBluetoothPrivacySettings()
        case .helpAddModel:
            model.selection = .diagnostics
            openWindow(id: AppModel.mainWindowID)
            NSApp.activate(ignoringOtherApps: true)
        case .retry: Task { await manager.connect() }
        case nil: break
        }
    }
}
