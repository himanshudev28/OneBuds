import OneBudsCore
import SwiftUI

struct GesturesView: View {
    @Environment(DeviceManager.self) private var manager

    private var sharedBindings: [GestureBinding] {
        manager.gestures.filter { $0.button == 1 && $0.side == GestureSide.both.rawValue }
    }

    var body: some View {
        RequiresCapability(capability: .gestures) {
            Form {
                Section {
                    if manager.gestures.isEmpty {
                        Text("The earbuds haven't reported their gesture settings.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ViewThatFits(in: .horizontal) {
                                GestureTable()
                                GestureStack()
                            }
                            OperationStatusLine(status: manager.status(of: .gestures), topSpacing: Theme.Spacing.m)
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                } header: {
                    HStack(spacing: Theme.Spacing.s) {
                        SectionHeader(title: "Touch Gestures", presentation: manager.presentation(.gestures))
                        if manager.status(of: .gestures) == .pending { ProgressView().controlSize(.mini) }
                    }
                } footer: {
                    FormFooter("Each earbud is set separately. Only functions documented for this model are offered; call controls aren't editable.")
                }

                if !sharedBindings.isEmpty {
                    Section("Both Earbuds") {
                        ForEach(sharedBindings, id: \.self) { binding in
                            let name = GestureAction(rawValue: binding.action)?.displayName ?? "Action \(binding.action)"
                            LabeledContent(name) {
                                GesturePicker(binding: binding, accessibilityTitle: "Both earbuds, \(name)")
                            }
                        }
                    }
                }
            }
            .screenFormStyle()
        }
    }
}
