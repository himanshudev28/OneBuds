import SwiftUI

struct MenuBarSettingsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Toggle(isOn: $settings.showBatteryInMenuBar) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Show battery percentage")
                        Text("Shows the lower of the two earbud levels next to the icon.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .settingsPaneStyle()
    }
}
