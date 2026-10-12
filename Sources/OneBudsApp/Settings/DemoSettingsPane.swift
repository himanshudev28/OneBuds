import OneBudsCore
import SwiftUI

struct DemoSettingsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.settings.demoMode }, set: { setDemoMode($0) })) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Demo mode")
                        Text("Simulated earbuds with made-up values, labelled DEMO everywhere. No Bluetooth is used.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                Picker("Simulated model", selection: Binding(get: { model.settings.demoModelID }, set: { setDemoModel($0) })) {
                    ForEach(AppSettings.demoModels) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .disabled(!model.settings.demoMode)
            } footer: {
                FormFooter("Pick a model to preview how OneBuds adapts its controls to it.")
            }
        }
        .settingsPaneStyle()
    }

    private func setDemoMode(_ enabled: Bool) { Task { await model.setDemoMode(enabled) } }
    private func setDemoModel(_ id: String) { Task { await model.setDemoModel(id) } }
}
