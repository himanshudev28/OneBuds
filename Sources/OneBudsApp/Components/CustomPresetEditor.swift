import OneBudsCore
import SwiftUI

/// Creates or edits a custom EQ preset stored on the earbuds. The sheet closes only once the
/// earbuds have confirmed the change by reading it back.
struct CustomPresetEditor: View {
    enum Mode: Identifiable, Equatable {
        case new
        case edit(CustomEQPreset)
        var id: String {
            switch self {
            case .new: "new"
            case .edit(let preset): "edit-\(preset.id)"
            }
        }
    }

    @Environment(DeviceManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var name: String
    @State private var bands: [EQBand]
    @State private var submitted = false

    init(mode: Mode, layout: CustomEQLayout, existing: [CustomEQPreset]) {
        self.mode = mode
        switch mode {
        case .new:
            _name = State(initialValue: "My preset \(existing.count + 1)")
            // Copy the band layout the earbuds already use, if they hold a preset; else the profile's.
            let frequencies = existing.first?.bands.map(\.frequency) ?? layout.frequencies
            _bands = State(initialValue: frequencies.map { EQBand(frequency: $0, gain: 0) })
        case .edit(let preset):
            _name = State(initialValue: preset.name)
            _bands = State(initialValue: preset.bands)
        }
        maximumGain = layout.maximumGain
    }

    private let maximumGain: Int
    private var status: DeviceManager.OperationStatus { manager.status(of: .customEqualizer) }
    private var isPending: Bool { status == .pending }
    private var nameIsValid: Bool { CustomEQPreset.isValidName(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Text(mode == .new ? "New Preset" : "Edit Preset").font(.title3.bold())
                Badge.experimental
                Spacer()
            }
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            if !nameIsValid {
                Text("Use 1–16 letters, numbers or symbols (no accents or emoji).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ZStack {
                // Same vertical span as the fader tracks (between the value and frequency labels).
                EQCurve(bands: bands, maximumGain: maximumGain, columns: true)
                    .stroke(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .padding(.top, Theme.Size.faderTopLabel)
                    .padding(.bottom, Theme.Size.faderBottomLabel)
                    .allowsHitTesting(false)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(bands.indices, id: \.self) { index in
                        GainSlider(gain: $bands[index].gain, maximum: maximumGain, label: bands[index].frequencyLabel)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: Theme.Size.eqEditorHeight)
            .animation(Theme.Motion.standard, value: bands)

            OperationStatusLine(status: submitted ? status : .idle, topSpacing: 0)

            HStack {
                if case .edit(let preset) = mode {
                    Button("Delete", role: .destructive) { submit { await manager.deleteCustomPreset(preset) } }
                        .disabled(isPending)
                }
                Button("Flatten") { for index in bands.indices { bands[index].gain = 0 } }
                    .disabled(isPending)
                Spacer()
                if isPending { ProgressView().controlSize(.small) }
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nameIsValid || isPending)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460)
        .onChange(of: status) { _, new in
            if submitted, case .confirmed = new { dismiss() }
        }
    }

    private func save() {
        switch mode {
        case .new:
            submit { await manager.createCustomPreset(name: name, bands: bands) }
        case .edit(var preset):
            preset.name = name
            preset.bands = bands
            submit { await manager.saveCustomPreset(preset) }
        }
    }

    private func submit(_ work: @escaping @MainActor () async -> Void) {
        submitted = true
        Task { await work() }
    }
}

/// A vertical gain fader: drag, click, scroll or use the arrow keys (VoiceOver: adjustable).
struct GainSlider: View {
    @Binding var gain: Int
    let maximum: Int
    let label: String
    @FocusState private var isFocused: Bool

    private var valueText: String { gain > 0 ? "+\(gain)" : "\(gain)" }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(gain == 0 ? .secondary : .primary)
                .contentTransition(.numericText(value: Double(gain)))
                .frame(height: Theme.Size.faderTopLabel - Theme.Spacing.xs)
            GeometryReader { proxy in track(height: proxy.size.height) }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: Theme.Size.faderBottomLabel - Theme.Spacing.xs)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(1) }
        .onKeyPress(.downArrow) { step(-1) }
        .accessibilityElement()
        .accessibilityLabel("\(label) hertz")
        .accessibilityValue("\(gain) decibels")
        .accessibilityAdjustableAction(adjust)
    }

    private func track(height: CGFloat) -> some View {
        let y = height / 2 - height / 2 * CGFloat(gain) / CGFloat(maximum)
        return ZStack(alignment: .top) {
            Capsule().fill(.quaternary).frame(width: 4)
            Rectangle().fill(.tertiary).frame(width: 12, height: 1).offset(y: height / 2)
            knob.offset(y: y - 8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in drag(to: value.location.y, height: height) })
    }

    private var knob: some View {
        Circle()
            .fill(.white)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            .overlay { Circle().strokeBorder(Color.accentColor, lineWidth: isFocused ? 2 : 0) }
            .frame(width: 16, height: 16)
    }

    private func drag(to y: CGFloat, height: CGFloat) {
        guard height > 0 else { return }
        let fraction = 1 - min(max(y / height, 0), 1)
        gain = Int((fraction * 2 - 1) * Double(maximum)).clamped(-maximum, maximum)
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: _ = step(1)
        case .decrement: _ = step(-1)
        @unknown default: break
        }
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        gain = (gain + delta).clamped(-maximum, maximum)
        return .handled
    }
}

private extension Int {
    func clamped(_ low: Int, _ high: Int) -> Int { Swift.min(Swift.max(self, low), high) }
}
