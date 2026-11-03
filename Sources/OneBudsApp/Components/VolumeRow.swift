import SwiftUI

/// The Mac's output volume. The speaker symbol fills with the level and toggles mute.
struct VolumeRow: View {
    @Environment(AppModel.self) private var model

    private var volume: SystemVolume { model.systemVolume }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button {
                volume.setMuted(!volume.isMuted)
            } label: {
                Image(systemName: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: Double(volume.volume))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(volume.isMuted ? "Unmute" : "Mute")

            Slider(value: Binding(get: { Double(volume.isMuted ? 0 : volume.volume) }, set: { volume.setVolume(Float($0)) }), in: 0...1)
                .controlSize(.small)
                .accessibilityLabel("Output volume")
                .accessibilityValue("\(Int((volume.volume * 100).rounded())) percent")
        }
        .help(volume.deviceName.map { "Volume of \($0)" } ?? "Output volume")
    }
}
