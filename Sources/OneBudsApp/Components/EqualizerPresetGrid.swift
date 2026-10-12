import OneBudsCore
import SwiftUI

/// Preset cards; adapts its column count to the window width.
struct EqualizerPresetGrid: View {
    @Environment(DeviceManager.self) private var manager
    let presets: [EQPresetOption]
    @State private var requestedPreset: UInt8?

    private var isPending: Bool { manager.status(of: .equalizer) == .pending }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Theme.Spacing.m - 2)], spacing: Theme.Spacing.m - 2) {
            ForEach(presets) { preset in
                EqualizerPresetCard(preset: preset,
                                    isSelected: manager.equalizerPreset == preset.id,
                                    isPending: isPending && requestedPreset == preset.id) {
                    select(preset)
                }
                .disabled(isPending)
            }
        }
        .animateState(value: manager.equalizerPreset)
    }

    private func select(_ preset: EQPresetOption) {
        guard preset.id != manager.equalizerPreset else { return }
        requestedPreset = preset.id
        Task { await manager.setEqualizer(presetID: preset.id) }
    }
}
