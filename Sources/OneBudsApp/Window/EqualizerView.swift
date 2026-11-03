import OneBudsCore
import SwiftUI

/// Sound: built-in and custom EQ presets, then the sound switches (BassWave, 3D audio).
struct EqualizerView: View {
    @Environment(DeviceManager.self) private var manager
    @State private var editing: CustomPresetEditor.Mode?

    private var layout: CustomEQLayout? { manager.profile?.opo?.customEQ }

    var body: some View {
        RequiresCapability(capability: .equalizer) {
            Form {
                Section {
                    VStack(spacing: 0) {
                        EqualizerPresetGrid(presets: EqualizerPresets.builtIn(for: manager))
                        OperationStatusLine(status: manager.status(of: .equalizer))
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                } header: {
                    SectionHeader(title: "Equalizer Presets", presentation: manager.presentation(.equalizer))
                }

                if manager.presentation(.customEqualizer) != .hidden, let layout {
                    customSection(layout)
                }

                soundSwitches
            }
            .screenFormStyle()
            .sheet(item: $editing) { mode in
                if let layout { CustomPresetEditor(mode: mode, layout: layout, existing: manager.customPresets) }
            }
        }
    }

    private func customSection(_ layout: CustomEQLayout) -> some View {
        Section {
            ForEach(manager.customPresets) { preset in
                let selected = manager.equalizerPreset == preset.id
                HStack(spacing: Theme.Spacing.m) {
                    EQCurve(bands: preset.bands, maximumGain: layout.maximumGain)
                        .stroke(selected ? Color.accentColor : .secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 48, height: 20)
                    Text(preset.name).bold(selected)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    Spacer()
                    if !selected {
                        Button("Use") { Task { await manager.setEqualizer(presetID: preset.id) } }
                            .disabled(manager.status(of: .equalizer) == .pending)
                    }
                    Button("Edit…") { editing = .edit(preset) }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                if manager.customPresets.count < layout.maximumPresets {
                    Button("New Preset…", systemImage: "plus") { editing = .new }
                } else {
                    Text("The earbuds hold \(layout.maximumPresets) custom presets. Delete one to add another.")
                        .foregroundStyle(.secondary)
                }
                // Outside the editor sheet (e.g. after "Use"), results still show here.
                if editing == nil { OperationStatusLine(status: manager.status(of: .customEqualizer)) }
            }
        } header: {
            SectionHeader(title: "Custom Presets", presentation: manager.presentation(.customEqualizer))
        } footer: {
            FormFooter("Custom presets live on the earbuds, so they follow them to your phone. Up to \(layout.maximumPresets).")
        }
        .animateState(value: manager.customPresets)
    }

    @ViewBuilder
    private var soundSwitches: some View {
        let bass = manager.visibleFeatureID(for: .bassWave)
        let spatial = manager.visibleFeatureID(for: .spatialAudio)
        if bass != nil || spatial != nil {
            Section("Sound Effects") {
                if let bass {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        FeatureToggleRow(capability: .bassWave, featureID: bass, symbol: "speaker.wave.2.bubble")
                        BassWaveStrength()
                    }
                    .animateState(value: manager.features[bass])
                }
                if let spatial {
                    FeatureToggleRow(capability: .spatialAudio, featureID: spatial, symbol: "airpods.gen3")
                }
            }
        }
    }
}
