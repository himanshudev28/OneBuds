import OneBudsCore
import SwiftUI

/// Connected content of the popover; each group appears only if the model supports it.
struct PopoverControls: View {
    @Environment(DeviceManager.self) private var manager

    var body: some View {
        VStack(spacing: Theme.Spacing.m - 2) {
            if manager.presentation(.battery) != .hidden, let battery = manager.battery, !battery.isEmpty {
                Card {
                    SectionHeader(title: "Battery", presentation: manager.presentation(.battery))
                        .font(.subheadline.bold())
                    BatteryRow(battery: battery)
                }
            }

            if manager.presentation(.noiseControl) != .hidden {
                Card {
                    SectionHeader(title: "Noise Control", presentation: manager.presentation(.noiseControl))
                        .font(.subheadline.bold())
                    NoiseModeSelector()
                }
            }

            if manager.presentation(.gameMode) != .hidden, let id = manager.profile?.opo?.gameModeFeatureID, manager.features[id] != nil {
                Card {
                    FeatureToggleRow(capability: .gameMode, featureID: id, symbol: "gamecontroller")
                }
            }
        }
    }
}
