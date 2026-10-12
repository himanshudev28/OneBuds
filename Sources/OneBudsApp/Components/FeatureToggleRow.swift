import OneBudsCore
import SwiftUI

/// A feature switch whose state always shows what the earbuds confirmed: flipping it sends the
/// change, and the switch moves only once the earbuds report the new value.
struct FeatureToggleRow: View {
    @Environment(DeviceManager.self) private var manager
    let capability: Capability
    let featureID: UInt8
    var symbol: String?

    private var isOn: Bool { manager.features[featureID] ?? false }
    private var isPending: Bool { manager.status(of: .feature(featureID)) == .pending }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.s) {
                Toggle(isOn: Binding(get: { isOn }, set: { setEnabled($0) })) {
                    HStack(spacing: Theme.Spacing.s) {
                        if let symbol {
                            Image(systemName: symbol)
                                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                                .accessibilityHidden(true)
                        }
                        Text(capability.displayName)
                        CapabilityBadge(presentation: manager.presentation(capability))
                    }
                }
                .toggleStyle(.switch)
                .disabled(isPending)
                if isPending { ProgressView().controlSize(.small) }
            }
            OperationStatusLine(status: manager.status(of: .feature(featureID)), topSpacing: Theme.Spacing.xs)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        Task { await manager.setFeature(featureID, enabled: enabled) }
    }
}
