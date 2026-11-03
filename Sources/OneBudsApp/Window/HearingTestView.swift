import OneBudsCore
import SwiftUI

/// Finds the quietest tone the user can hear at six frequencies per ear, then stores that profile
/// on the earbuds (Golden Sound). Each tone starts comfortably quiet; "Yes" steps quieter until
/// the tone is lost, "No" steps louder until it is heard. Nothing plays before Start is pressed.
struct HearingTestView: View {
    @Environment(DeviceManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case intro, testing, review }

    /// The loudest step the test will play.
    private static let loudestIndex = 21

    @State private var phase = Phase.intro
    @State private var step = 0
    @State private var index = HearingTest.startIndex
    @State private var lastHeard: Int?
    @State private var results: [Int] = []
    @State private var error: String?
    @State private var isSending = false

    private var side: UInt8 { step < 6 ? 1 : 2 }
    private var isSaving: Bool { manager.status(of: .hearing) == .pending }
    /// The earbuds paused the test (a bud is out) or ended it: no tones until that clears.
    private var isPaused: Bool { manager.hearingStatus == 5 || manager.hearingStatus == 7 }
    private var frequency: UInt8 { UInt8(step % 6 + 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Text("Golden Sound Hearing Test").font(.title3.bold())
                Badge.experimental
                Spacer()
            }
            switch phase {
            case .intro: intro
            case .testing: testing
            case .review: review
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = statusNote {
                Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 440)
        .animateState(value: phase)
        .animateState(value: step)
        .interactiveDismissDisabled(isSaving)
        .onDisappear {
            // Only a test that was started needs ending; never while a profile is being stored.
            guard phase != .intro, !isSaving else { return }
            Task { await manager.endHearingTest() }
        }
    }

    private var statusNote: String? {
        switch manager.hearingStatus {
        case 5: "An earbud is out of your ear. Put it back to continue."
        case 7: "The earbuds ended the test. Close this and start again."
        default: nil
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Wear both earbuds in a quiet room. You'll hear short tones, one ear at a time. Answer whether you can hear each one; tones get quieter until you can't.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Takes about two minutes. The result tunes the sound to your hearing and turns Golden Sound on.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Start") { start() }.keyboardShortcut(.defaultAction).disabled(isSending)
            }
        }
    }

    private var testing: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ProgressView(value: Double(step), total: 12)
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "ear")
                    .font(.largeTitle)
                    .scaleEffect(x: side == 1 ? -1 : 1)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isSending)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("\(side == 1 ? "Left" : "Right") ear · \(HearingTest.frequencies[Int(frequency) - 1])").font(.headline)
                    Text("Can you hear the tone?").foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Play again") { Task { await play() } }.disabled(isSending || isPaused)
                Spacer()
                Button("No") { answer(heard: false) }.disabled(isSending || isPaused)
                Button("Yes") { answer(heard: true) }.keyboardShortcut(.defaultAction).disabled(isSending || isPaused)
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Test complete").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.xs) {
                GridRow {
                    Text("")
                    ForEach(HearingTest.frequencies, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(0..<2, id: \.self) { ear in
                    GridRow {
                        Text(ear == 0 ? "Left" : "Right").font(.caption)
                        ForEach(0..<6, id: \.self) { column in
                            Text("\(results[ear * 6 + column])").font(.caption.monospacedDigit())
                        }
                    }
                }
            }
            OperationStatusLine(status: manager.status(of: .hearing), topSpacing: 0)
            HStack {
                Spacer()
                Button("Discard", role: .cancel) { dismiss() }.disabled(isSaving)
                Button(manager.status(of: .hearing) == .pending ? "Saving…" : "Save to Earbuds") {
                    Task {
                        await manager.applyHearingProfile(results)
                        if case .confirmed = manager.status(of: .hearing) { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(manager.status(of: .hearing) == .pending)
            }
        }
    }

    private func start() {
        Task {
            isSending = true
            defer { isSending = false }
            do {
                try await manager.startHearingTest()
                error = nil
                phase = .testing
                await play()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func play() async {
        isSending = true
        defer { isSending = false }
        do {
            try await manager.playHearingTone(HearingTone(side: side, frequency: frequency, level: HearingTest.levels[index]))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func answer(heard: Bool) {
        // Block a second answer (double click, key repeat) before the next tone is even queued.
        guard !isSending, !isPaused else { return }
        isSending = true
        if heard {
            lastHeard = index
            if index == 0 { record(index) } else { index -= 1; Task { await play() } }
        } else if let lastHeard {
            record(lastHeard)
        } else if index < Self.loudestIndex {
            index += 1
            Task { await play() }
        } else {
            record(Self.loudestIndex)
        }
    }

    private func record(_ heardIndex: Int) {
        results.append(HearingTest.snap(HearingTest.levels[heardIndex]))
        lastHeard = nil
        index = HearingTest.startIndex
        if results.count == 12 {
            phase = .review
            isSending = false
            Task { await manager.stopHearingTone() }
        } else {
            step += 1
            Task { await play() }
        }
    }
}
