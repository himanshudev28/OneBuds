import OneBudsCore
import SwiftUI

struct ConnectionCardSettingsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(DeviceManager.self) private var manager

    /// The connected model, else the Demo model, for the artwork status line.
    private var profile: DeviceProfile { manager.profile ?? model.settings.demoProfile }

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Toggle(isOn: $settings.showConnectionCard) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Show when earbuds connect")
                        Text("Appears at the top of the screen once per connection. Earbuds ▸ Show Connection Card (⇧⌘I) brings it back any time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                Picker("Hide after", selection: $settings.cardDuration) {
                    ForEach(CardDuration.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Artwork") {
                Picker("Show", selection: $settings.cardArtworkStyle) {
                    ForEach(CardArtworkStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $settings.animateCardModel) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Gently rotate 3D model")
                        Text("A slow sway while the card is up. Always still when Reduce Motion is on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                LabeledContent(profile.displayName) {
                    Text(EarbudArtwork.lookup(profileID: profile.id).summary)
                        .foregroundStyle(.secondary)
                }
                Text("Only licensed artwork of the exact model is used. Without it, the card shows the earbuds symbol.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Show Card Now", action: showCard)
                    .disabled(!manager.connection.isConnected)
            }
        }
        .settingsPaneStyle()
    }

    private func showCard() { model.connectionCard.present() }
}
