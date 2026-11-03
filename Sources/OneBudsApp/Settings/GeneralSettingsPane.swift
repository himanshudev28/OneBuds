import SwiftUI
import OneBudsCore

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
            Section("Connection") {
                Picker(selection: Binding(get: { model.settings.transportPreference }, set: { setTransport($0) })) {
                    ForEach(TransportPreference.allCases, id: \.self) { Text($0.displayName).tag($0) }
                } label: {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Control channel")
                        Text(AppModel.transportOverride.map { "Set by ONEBUDS_TRANSPORT for this run: \($0.displayName)." }
                             ?? "Automatic uses Bluetooth LE (GATT) when the earbuds offer it and falls back to Classic Bluetooth (RFCOMM). Only routes this model supports are tried.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(AppModel.transportOverride != nil)
            }
            Section("Notifications") {
                Toggle(isOn: Binding(get: { model.settings.lowBatteryAlerts }, set: { setAlerts($0) })) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Low-battery alerts")
                        Text("A notification when an earbud runs low, once each time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                Picker("Alert at", selection: Binding(get: { model.settings.lowBatteryThreshold }, set: { model.settings.lowBatteryThreshold = $0 })) {
                    ForEach(AppSettings.lowBatteryChoices, id: \.self) { Text("\($0)%").tag($0) }
                }
                .disabled(!model.settings.lowBatteryAlerts)
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

    private func setTransport(_ preference: TransportPreference) {
        Task { await model.setTransportPreference(preference) }
    }

    private func setAlerts(_ enabled: Bool) {
        model.settings.lowBatteryAlerts = enabled
        if enabled { model.batteryAlerts.requestPermission() }
    }
}
