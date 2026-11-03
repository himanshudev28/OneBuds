import OneBudsCore
import SwiftUI

/// BassWave strength, shown while BassWave is on. The value moves only once the earbuds confirm it;
/// while dragging, the slider shows the requested value.
struct BassWaveStrength: View {
    @Environment(DeviceManager.self) private var manager
    @State private var draft: Double?

    var body: some View {
        if let range = manager.profile?.opo?.bassLevels, let level = manager.bassLevel,
           let id = manager.featureID(for: .bassWave), manager.features[id] == true {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text("Strength").foregroundStyle(.secondary)
                    Spacer()
                    Text(signedText(Int(draft ?? Double(level))))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: draft ?? Double(level)))
                    if manager.status(of: .bassLevel) == .pending { ProgressView().controlSize(.mini) }
                }
                .font(.callout)
                Slider(value: Binding(get: { draft ?? Double(level) }, set: { draft = $0 }),
                       in: Double(range.lowerBound)...Double(range.upperBound), step: 1) {
                    Text("BassWave strength")
                } minimumValueLabel: {
                    Image(systemName: "minus").imageScale(.small)
                } maximumValueLabel: {
                    Image(systemName: "plus").imageScale(.small)
                } onEditingChanged: { editing in
                    if !editing { commit() }
                }
                .labelsHidden()
                .disabled(manager.status(of: .bassLevel) == .pending)
                OperationStatusLine(status: manager.status(of: .bassLevel), topSpacing: Theme.Spacing.xs)
            }
            .animateState(value: level)
            .revealTransition()
        }
    }

    private func signedText(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    private func commit() {
        guard let draft else { return }
        let level = Int(draft.rounded())
        Task {
            await manager.setBassLevel(level)
            self.draft = nil
        }
    }
}

/// The modes touch-and-hold cycles through. At least one must stay selected.
struct NoiseCycleEditor: View {
    @Environment(DeviceManager.self) private var manager

    private var offered: [NoiseCategory] {
        let bits = manager.profile?.opo?.noiseCycleBits ?? [:]
        return [NoiseCategory.noiseCancelling, .adaptive, .transparency, .off].filter { bits[$0] != nil }
    }

    var body: some View {
        if let cycle = manager.noiseCycle {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Touch and hold cycles through")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: Theme.Spacing.xsPlus) {
                    ForEach(offered, id: \.self) { category in
                        chip(category, isOn: cycle.contains(category), isLast: cycle.contains(category) && cycle.count == 1, cycle: cycle)
                    }
                }
                OperationStatusLine(status: manager.status(of: .noiseCycle), topSpacing: Theme.Spacing.xs)
            }
            .animateState(value: cycle)
        }
    }

    private func chip(_ category: NoiseCategory, isOn: Bool, isLast: Bool, cycle: Set<NoiseCategory>) -> some View {
        Button {
            var next = cycle
            if isOn { next.remove(category) } else { next.insert(category) }
            Task { await manager.setNoiseCycle(next) }
        } label: {
            Label(category.popoverTitle, systemImage: isOn ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xs + 1)
                .background(isOn ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.quinary), in: Capsule())
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.pressable)
        .disabled(isLast || manager.status(of: .noiseCycle) == .pending)
        .help(isLast ? "Keep at least one mode" : category.explanation)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Built-in and custom presets as compact rows, for the popover.
struct PresetList: View {
    @Environment(DeviceManager.self) private var manager
    @State private var requested: UInt8?

    private var isPending: Bool { manager.status(of: .equalizer) == .pending }

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ForEach(EqualizerPresets.builtIn(for: manager)) { preset in
                row(id: preset.id, name: preset.name, bands: nil)
            }
            ForEach(manager.customPresets) { preset in
                row(id: preset.id, name: preset.name, bands: preset.bands)
            }
        }
        .animateState(Theme.Motion.selection, value: manager.equalizerPreset)
    }

    private func row(id: UInt8, name: String, bands: [EQBand]?) -> some View {
        let selected = manager.equalizerPreset == id
        return Button {
            guard !selected else { return }
            requested = id
            Task { await manager.setEqualizer(presetID: id) }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                if let bands {
                    EQCurve(bands: bands, maximumGain: 6)
                        .stroke(selected ? Color.accentColor : .secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 28, height: 14)
                } else {
                    Image(systemName: "waveform").foregroundStyle(selected ? Color.accentColor : .secondary).frame(width: 28)
                }
                Text(name).lineLimit(1)
                Spacer(minLength: 0)
                if isPending, requested == id {
                    ProgressView().controlSize(.mini)
                } else if selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold).transition(.opacity)
                }
            }
            .font(.callout)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xsPlus)
            .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(isPending)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Presets the profile offers, minus those that need newer firmware than the earbuds report.
enum EqualizerPresets {
    @MainActor
    static func builtIn(for manager: DeviceManager) -> [EQPresetOption] {
        let firmware = manager.deviceInfo?.firmwareSummary.flatMap { Int($0.split(separator: ".").first ?? "") }
        return (manager.profile?.opo?.equalizerPresets ?? []).filter { preset in
            guard let minimum = preset.minimumFirmware else { return true }
            return firmware.map { $0 >= minimum } ?? false
        }
    }

    @MainActor
    static func currentName(for manager: DeviceManager) -> String? {
        guard let id = manager.equalizerPreset else { return nil }
        return builtIn(for: manager).first { $0.id == id }?.name ?? manager.customPresets.first { $0.id == id }?.name
    }
}

/// A smooth line through a preset's band gains, centred on 0 dB. Gain changes animate.
struct EQCurve: Shape {
    var gains: AnimatableVector
    var maximumGain: Int
    /// Place points at the centres of equal columns (behind a row of faders) instead of edge to edge.
    var columns = false

    init(bands: [EQBand], maximumGain: Int, columns: Bool = false) {
        gains = AnimatableVector(bands.map { Double($0.gain) })
        self.maximumGain = maximumGain
        self.columns = columns
    }

    var animatableData: AnimatableVector {
        get { gains }
        set { gains = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let values = gains.values
        guard values.count > 1, maximumGain > 0 else { return Path() }
        let points = values.enumerated().map { index, gain in
            CGPoint(x: columns ? rect.minX + rect.width * (CGFloat(index) + 0.5) / CGFloat(values.count)
                               : rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: rect.midY - rect.height / 2 * CGFloat(gain) / CGFloat(maximumGain))
        }
        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1], point = points[index]
            let mid = (previous.x + point.x) / 2
            path.addCurve(to: point, control1: CGPoint(x: mid, y: previous.y), control2: CGPoint(x: mid, y: point.y))
        }
        return path
    }
}

/// Minimal vector so a curve's gains can animate.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]
    init(_ values: [Double]) { self.values = values }
    static var zero: AnimatableVector { AnimatableVector([]) }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector { combine(lhs, rhs, +) }
    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector { combine(lhs, rhs, -) }

    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }

    private static func combine(_ lhs: AnimatableVector, _ rhs: AnimatableVector, _ op: (Double, Double) -> Double) -> AnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        return AnimatableVector((0..<count).map { index in
            op(index < lhs.values.count ? lhs.values[index] : 0, index < rhs.values.count ? rhs.values[index] : 0)
        })
    }
}
