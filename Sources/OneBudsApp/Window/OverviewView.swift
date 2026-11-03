import OneBudsCore
import SwiftUI

struct OverviewView: View {
    @Environment(DeviceManager.self) private var manager

    var body: some View {
        Form {
            if manager.connection.isConnected {
                // Header sits on the window background rather than in a card.
                Section {
                    DeviceHeroCard()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if manager.presentation(.noiseControl) != .hidden {
                    Section {
                        NoiseModeSelector(large: true)
                            .padding(.vertical, Theme.Spacing.s)
                    } header: {
                        SectionHeader(title: "Noise Control", presentation: manager.presentation(.noiseControl))
                    }
                }
                FeatureTogglesSection()
            }

            if let error = manager.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .screenFormStyle()
        .overlay {
            if !manager.connection.isConnected {
                ConnectionStateView()
                    .padding(.top, 40)
            }
        }
        .animateState(value: manager.connection.isConnected)
    }
}
