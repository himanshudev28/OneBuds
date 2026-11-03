import OneBudsCore
import SwiftUI

/// Rings both earbuds so they can be found. The sound is loud, so it is never started automatically
/// and the warning stays visible next to the button.
struct FindEarbudsPanel: View {
    @Environment(DeviceManager.self) private var manager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPending: Bool { manager.status(of: .findEarbuds) == .pending }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.title2)
                    .foregroundStyle(manager.isRinging ? Color.orange : .secondary)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: manager.isRinging && !reduceMotion)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(manager.isRinging ? "Playing a sound…" : "Play a sound")
                        .contentTransition(.opacity)
                    Text("Loud. Take the earbuds out of your ears first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(manager.isRinging ? "Stop" : "Play") {
                    Task { await manager.findEarbuds(ringing: !manager.isRinging) }
                }
                .disabled(isPending)
                .tint(manager.isRinging ? .orange : nil)
            }
            OperationStatusLine(status: manager.status(of: .findEarbuds), topSpacing: 0)
        }
        .animateState(value: manager.isRinging)
    }
}

/// Measures how well each ear tip seals. The earbuds play a short sound and report per side.
struct FitTestPanel: View {
    @Environment(DeviceManager.self) private var manager

    private var isRunning: Bool { manager.status(of: .fitTest) == .pending }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "ear.badge.waveform")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: isRunning)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Ear tip fit")
                    Text(isRunning ? "Keep both earbuds in and stay still…" : "Wear both earbuds, then start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                if isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Button(manager.fitResult == nil ? "Start" : "Again") { Task { await manager.runFitTest() } }
                }
            }
            if let result = manager.fitResult {
                HStack(spacing: Theme.Spacing.s) {
                    seal("Left", result.left)
                    seal("Right", result.right)
                }
                .revealTransition()
            }
            OperationStatusLine(status: manager.status(of: .fitTest), topSpacing: 0)
        }
        .animateState(value: manager.fitResult)
        .animateState(value: isRunning)
    }

    private func seal(_ side: String, _ seal: FitSeal?) -> some View {
        let seal = seal ?? .notMeasured
        let (symbol, tint): (String, Color) = switch seal {
        case .good: ("checkmark.circle.fill", .green)
        case .average: ("exclamationmark.circle.fill", .yellow)
        case .poor: ("xmark.circle.fill", .red)
        case .notMeasured: ("minus.circle", .secondary)
        }
        return HStack(spacing: Theme.Spacing.xsPlus) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(side).font(.caption).foregroundStyle(.secondary)
                Text(seal.displayName).font(.callout)
            }
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
