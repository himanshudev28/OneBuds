import OneBudsCore
import SwiftUI

/// Noise-control modes offered by the connected model's profile, with a labelled intensity picker
/// for models that have ANC levels. Selection always reflects the mode the earbuds confirmed.
struct NoiseModeSelector: View {
    enum Style { case tiles, circles }

    @Environment(DeviceManager.self) private var manager
    var large = false
    /// Tiles in the window; round Control Center–style buttons in the popover.
    var style = Style.tiles
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
            controls
                .frame(maxWidth: large ? Theme.Size.controlRowMaxWidth : .infinity)
                .frame(maxWidth: .infinity)

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

    /// Mode tiles, plus the intensity picker while noise cancelling is confirmed.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: large ? Theme.Spacing.s : Theme.Spacing.xsPlus) {
                ForEach(categories, id: \.self) { category in
                    let selected = confirmed == category
                    let requested = pending?.category == category && confirmed != category
                    Group {
                        if style == .circles {
                            NoiseModeCircle(category: category, isSelected: selected, isPending: requested, namespace: selection) {
                                select(category)
                            }
                        } else {
                            NoiseModeButton(category: category, isSelected: selected, isPending: requested, large: large, namespace: selection) {
                                select(category)
                            }
                        }
                    }
                    .disabled(isPending)
                }
            }
            .animateState(Theme.Motion.selection, value: confirmed)

            if confirmed == .noiseCancelling, !levels.isEmpty {
                intensity
                    .padding(.top, large ? Theme.Spacing.l : Theme.Spacing.m)
                    .revealTransition()
            }
        }
    }

    /// Main window: label and control on one line. Popover: a caption over a full-width control.
    @ViewBuilder
    private var intensity: some View {
        let picker = Picker("Noise cancelling intensity", selection: Binding(get: { confirmedLevel }, set: { selectLevel($0) })) {
            ForEach(levels, id: \.self) { Text($0.displayName).tag(Optional($0)) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(isPending)

        if large {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                Text("Intensity")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityHidden(true)
                picker
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xsPlus) {
                Text("Intensity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                picker
                    .controlSize(.small)
            }
        }
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
