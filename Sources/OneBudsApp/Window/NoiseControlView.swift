import OneBudsCore
import SwiftUI

struct NoiseControlView: View {
    @Environment(DeviceManager.self) private var manager

    private var categories: [NoiseCategory] {
        let modes = manager.profile?.opo?.noiseModes ?? []
        return NoiseCategory.allCases.filter { category in modes.contains { $0.mode.category == category } }
    }

    var body: some View {
        RequiresCapability(capability: .noiseControl) {
            Form {
                Section {
                    NoiseModeSelector(large: true)
                        .padding(.vertical, Theme.Spacing.s)
                } header: {
                    SectionHeader(title: "Noise Control", presentation: manager.presentation(.noiseControl))
                } footer: {
                    FormFooter("The selection moves only after the earbuds confirm the new mode. Changes made on the earbuds or in the phone app appear here automatically.")
                }

                Section("Modes on \(manager.profile?.displayName ?? "These Earbuds")") {
                    ForEach(categories, id: \.self) { category in
                        Label {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(category.menuTitle)
                                Text(category.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: category.symbolName)
                                .foregroundStyle(manager.noiseControl?.category == category ? Color.accentColor : .secondary)
                        }
                    }
                    LabeledContent("Reported by the earbuds", value: manager.noiseControl?.displayName ?? "Not reported")
                }
            }
            .screenFormStyle()
        }
    }
}
