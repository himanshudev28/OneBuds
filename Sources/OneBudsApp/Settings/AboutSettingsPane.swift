import SwiftUI

struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: AppModel.version)
                LabeledContent("Data", value: "Stays on this Mac")
            } footer: {
                FormFooter("Unofficial. Not affiliated with OnePlus, OPPO or realme.")
            }
        }
        .settingsPaneStyle()
    }
}
