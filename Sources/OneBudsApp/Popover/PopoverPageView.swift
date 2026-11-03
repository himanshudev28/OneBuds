import AppKit
import OneBudsCore
import SwiftUI

/// One sub-page: a back button and title, then its modules (scrolling when tall).
struct PopoverPageView: View {
    @Environment(AppModel.self) private var model
    let page: PopoverPage
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            HStack(spacing: Theme.Spacing.xs) {
                Button(action: back) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .background(.quinary, in: Circle())
                }
                .buttonStyle(.pressable)
                .keyboardShortcut(.cancelAction)
                .help("Back")
                Text(page.title).font(.headline)
                Spacer()
                Button("More…") { model.show(page.windowItem) }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .help("Open \(page.title) in the OneBuds window")
            }

            ScrollView {
                VStack(spacing: Theme.Spacing.s + 2) {
                    switch page {
                    case .sound: PopoverSoundPage()
                    case .controls: PopoverControlsPage()
                    case .features: PopoverFeatures()
                    case .tools: PopoverToolsPage()
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: Theme.Size.popoverPageMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PopoverSoundPage: View {
    @Environment(DeviceManager.self) private var manager
    @Environment(AppModel.self) private var model

    var body: some View {
        Module(title: "Equalizer", presentation: manager.presentation(.equalizer)) {
            PresetList()
            OperationStatusLine(status: manager.status(of: .equalizer), topSpacing: 0)
            if manager.presentation(.customEqualizer) != .hidden {
                Button("Custom presets…", systemImage: "slider.horizontal.3") { model.show(.equalizer) }
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
        }
        let bass = manager.visibleFeatureID(for: .bassWave)
        let spatial = manager.visibleFeatureID(for: .spatialAudio)
        let golden = manager.visibleFeatureID(for: .hearingTest)
        if bass != nil || spatial != nil || golden != nil {
            Module {
                if let bass {
                    FeatureToggleRow(capability: .bassWave, featureID: bass, symbol: "speaker.wave.2.bubble")
                    BassWaveStrength()
                }
                if let spatial { FeatureToggleRow(capability: .spatialAudio, featureID: spatial, symbol: "airpods.gen3") }
                if let golden { FeatureToggleRow(capability: .hearingTest, featureID: golden, symbol: "sparkles") }
            }
            .animateState(value: bass.flatMap { manager.features[$0] })
        }
    }
}

struct PopoverControlsPage: View {
    @Environment(DeviceManager.self) private var manager
    @State private var side = GestureSide.left

    private var bindings: [GestureBinding] {
        manager.gestures.filter { $0.side == side.rawValue && $0.button == 1 }.sorted { $0.action < $1.action }
    }

    private var calls: [GestureBinding] {
        guard manager.presentation(.callControls) != .hidden else { return [] }
        return manager.gestures.filter { $0.button == 6 && $0.side == GestureSide.both.rawValue }
    }

    var body: some View {
        Module(title: "Touch Controls", presentation: manager.presentation(.gestures)) {
            Picker("Earbud", selection: $side) {
                Text("Left").tag(GestureSide.left)
                Text("Right").tag(GestureSide.right)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ForEach(bindings, id: \.self) { binding in
                let name = GestureAction(rawValue: binding.action)?.displayName ?? "Action \(binding.action)"
                HStack {
                    Text(name).font(.callout)
                    Spacer()
                    GesturePicker(binding: binding, accessibilityTitle: "\(side.displayName) earbud, \(name)")
                        .controlSize(.small)
                }
            }
            OperationStatusLine(status: manager.status(of: .gestures), topSpacing: 0)
        }
        .animateState(value: side)
        if manager.presentation(.noiseCycle) != .hidden, manager.noiseCycle != nil {
            Module(title: "Noise-Control Cycle", presentation: manager.presentation(.noiseCycle)) { NoiseCycleEditor() }
        }
        if !calls.isEmpty {
            Module(title: "During Calls", presentation: manager.presentation(.callControls)) {
                ForEach(calls, id: \.self) { binding in
                    let name = GestureAction(rawValue: binding.action)?.displayName ?? "Action \(binding.action)"
                    HStack {
                        Text(name).font(.callout)
                        Spacer()
                        GesturePicker(binding: binding, accessibilityTitle: "During calls, \(name)").controlSize(.small)
                    }
                }
            }
        }
    }
}

/// Feature switches, each only when the model has it and the earbuds reported a value.
struct PopoverFeatures: View {
    @Environment(DeviceManager.self) private var manager

    static let capabilities: [Capability] = [.gameMode, .wearDetection, .dualConnection, .smartVolume]

    private static let symbols: [Capability: String] = [
        .gameMode: "gamecontroller", .wearDetection: "ear", .dualConnection: "laptopcomputer.and.iphone",
        .smartVolume: "speaker.badge.exclamationmark",
    ]

    var body: some View {
        Module {
            ForEach(Self.capabilities, id: \.self) { capability in
                if let id = manager.visibleFeatureID(for: capability) {
                    FeatureToggleRow(capability: capability, featureID: id, symbol: Self.symbols[capability])
                }
            }
        }
    }
}

struct PopoverToolsPage: View {
    @Environment(DeviceManager.self) private var manager
    @Environment(AppModel.self) private var model

    var body: some View {
        if manager.presentation(.findEarbuds) != .hidden {
            Module(title: "Find My Earbuds", presentation: manager.presentation(.findEarbuds)) { FindEarbudsPanel() }
        }
        if manager.presentation(.fitTest) != .hidden {
            Module(title: "Fit Test", presentation: manager.presentation(.fitTest)) { FitTestPanel() }
        }
        if manager.presentation(.hearingTest) != .hidden {
            Module(title: "Golden Sound", presentation: manager.presentation(.hearingTest)) {
                HStack {
                    Text(manager.hearingProfile == nil ? "Tune the sound to your hearing." : "Hearing profile stored.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Hearing Test…") { model.show(.tools) }
                }
            }
        }
    }
}
