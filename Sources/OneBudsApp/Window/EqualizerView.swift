import OneBudsCore
import SwiftUI

struct EqualizerView: View {
    @Environment(DeviceManager.self) private var manager

    /// Presets the profile offers, minus those that need newer firmware than the earbuds report.
    private var presets: [EQPresetOption] {
        let firmware = manager.deviceInfo?.firmwareSummary.flatMap { Int($0.split(separator: ".").first ?? "") }
        return (manager.profile?.opo?.equalizerPresets ?? []).filter { preset in
            guard let minimum = preset.minimumFirmware else { return true }
            return firmware.map { $0 >= minimum } ?? false
        }
    }

    var body: some View {
        RequiresCapability(capability: .equalizer) {
            Form {
                Section {
                    VStack(spacing: 0) {
                        EqualizerPresetGrid(presets: presets)
                        OperationStatusLine(status: manager.status(of: .equalizer))
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                } header: {
                    SectionHeader(title: "Equalizer Presets", presentation: manager.presentation(.equalizer))
                } footer: {
                    FormFooter("Custom EQ curves aren't supported yet.")
                }
            }
            .screenFormStyle()
        }
    }
}
