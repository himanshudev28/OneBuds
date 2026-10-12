import OneBudsCore
import SwiftUI

/// Noise-control modes offered by the connected model's profile, with an inline level picker for
/// models that have levels. Selection always reflects the mode the earbuds confirmed.
struct NoiseModeSelector: View {
    @Environment(DeviceManager.self) private var manager
    var large = false
    @Namespace private var selection

    private var options: [NoiseModeOption] { manager.profile?.opo?.noiseModes ?? [] }

    private var categories: [NoiseCategory] {
        NoiseCategory.allCases.filter { category in options.contains { $0.mode.category == category } }
    }

    private var levels: [ANCLevel] {
        ANCLevel.allCases.filter { level in options.contains { $0.mode == .noiseCancelling(level) } }
    }

    private var confirmed: NoiseCategory? { manager.noiseControl?.category }
    private var pending: NoiseControlMode? { manager.pendingNoiseControl }
    private var isPending: Bool { manager.status(of: .noiseControl) == .pending }

    private var confirmedLevel: ANCLevel? {
        guard case .noiseCancelling(let level)? = manager.noiseControl else { return nil }
        return level
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: large ? Theme.Spacing.l : Theme.Spacing.s - 2) {
                ForEach(categories, id: \.self) { category in
                    NoiseModeButton(category: category,
                                    isSelected: confirmed == category,
                                    isPending: pending?.category == category && confirmed != category,
                                    large: large,
                                    namespace: selection) {
                        select(category)
                    }
                    .disabled(isPending)
                }
            }
            .frame(maxWidth: .infinity)
            .animateState(Theme.Motion.selection, value: confirmed)

            if confirmed == .noiseCancelling, !levels.isEmpty {
                Picker("Noise cancelling level", selection: Binding(get: { confirmedLevel }, set: { selectLevel($0) })) {
                    ForEach(levels, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(isPending)
                .padding(.top, Theme.Spacing.m)
                .revealTransition()
            }

            if let pending {
                Label("Switching to \(pending.displayName)…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Spacing.s)
                    .transition(.opacity)
            }
            OperationStatusLine(status: manager.status(of: .noiseControl))
        }
        .animateState(value: confirmed == .noiseCancelling)
        .animateState(value: pending)
    }

    private func select(_ category: NoiseCategory) {
        guard category != confirmed else { return }
        Task { await manager.setNoiseControl(category.requestedMode) }
    }

    private func selectLevel(_ level: ANCLevel?) {
        guard let level, level != confirmedLevel else { return }
        Task { await manager.setNoiseControl(.noiseCancelling(level)) }
    }
}
