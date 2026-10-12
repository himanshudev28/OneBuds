import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.launchAtLogin.isEnabled }, set: { setLaunchAtLogin($0) })) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Open OneBuds at login")
                        Text(model.launchAtLogin.errorMessage ?? model.launchAtLogin.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                if model.launchAtLogin.status == .requiresApproval {
                    Button("Open Login Items Settings…", action: model.launchAtLogin.openLoginItems)
                }
            }
            Section("Privacy") {
                Text("OneBuds works entirely on this Mac: no accounts, analytics or network access. Bluetooth addresses are redacted in exports.")
                    .foregroundStyle(.secondary)
                Button("Bluetooth Privacy Settings…", action: model.openBluetoothPrivacySettings)
            }
        }
        .settingsPaneStyle()
        .onAppear(perform: model.launchAtLogin.refresh)
    }

    private func setLaunchAtLogin(_ enabled: Bool) { model.launchAtLogin.set(enabled) }
}
