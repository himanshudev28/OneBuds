import OneBudsCore
import SwiftUI

/// Find my earbuds, the fit test and the Golden Sound hearing test.
struct ToolsView: View {
    @Environment(DeviceManager.self) private var manager
    @State private var showsHearingTest = false

    private var hasAnyTool: Bool {
        [Capability.findEarbuds, .fitTest, .hearingTest].contains { manager.presentation($0) != .hidden }
    }

    var body: some View {
        if !manager.connection.isConnected {
            ConnectionStateView()
        } else if !hasAnyTool {
            ContentUnavailableView("No Tools", systemImage: "wrench.and.screwdriver",
                                   description: Text("\(manager.profile?.displayName ?? "These earbuds") offer no tools in OneBuds."))
        } else {
            Form {
                if manager.presentation(.findEarbuds) != .hidden {
                    Section {
                        FindEarbudsPanel()
                    } header: {
                        SectionHeader(title: "Find My Earbuds", presentation: manager.presentation(.findEarbuds))
                    } footer: {
                        FormFooter("Both earbuds play a loud sound until you press Stop.")
                    }
                }
                if manager.presentation(.fitTest) != .hidden {
                    Section {
                        FitTestPanel()
                    } header: {
                        SectionHeader(title: "Fit Test", presentation: manager.presentation(.fitTest))
                    } footer: {
                        FormFooter("A good seal gives fuller bass and better noise cancelling. If a side is poor, try another ear-tip size.")
                    }
                }
                if manager.presentation(.hearingTest) != .hidden {
                    Section {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: "ear.and.waveform")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text("Hearing test")
                                Text(manager.hearingProfile.map { "Stored profile from \($0.name)" } ?? "No hearing profile stored yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(manager.hearingProfile == nil ? "Start Test…" : "Retake…") { showsHearingTest = true }
                        }
                        if let id = manager.visibleFeatureID(for: .hearingTest) {
                            FeatureToggleRow(capability: .hearingTest, featureID: id, symbol: "sparkles")
                        }
                    } header: {
                        SectionHeader(title: "Golden Sound", presentation: manager.presentation(.hearingTest))
                    }
                }
            }
            .screenFormStyle()
            .sheet(isPresented: $showsHearingTest) { HearingTestView() }
        }
    }
}
