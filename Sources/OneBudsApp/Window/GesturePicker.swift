import OneBudsCore
import SwiftUI

/// Function picker for one earbud gesture. It shows the confirmed function; choosing another sends
/// it, and the picker updates once the earbuds confirm.
struct GesturePicker: View {
    @Environment(DeviceManager.self) private var manager
    let binding: GestureBinding
    let accessibilityTitle: String

    private var allowed: [UInt8] { manager.profile?.opo?.gestureFunctions[binding.action] ?? [] }
    private var choices: [UInt8] { allowed.contains(binding.function) ? allowed : [binding.function] + allowed }

    var body: some View {
        Picker(accessibilityTitle, selection: Binding(get: { binding.function }, set: { choose($0) })) {
            ForEach(choices, id: \.self) { code in
                Text(functionName(code)).tag(code)
            }
        }
        .labelsHidden()
        .fixedSize()
        .disabled(allowed.isEmpty || manager.status(of: .gestures) == .pending)
        .accessibilityLabel(accessibilityTitle)
        .help(allowed.isEmpty ? "Not editable on this model" : accessibilityTitle)
    }

    private func functionName(_ code: UInt8) -> String {
        manager.profile?.opo?.functionName(code) ?? GestureFunction.name(code)
    }

    private func choose(_ function: UInt8) {
        guard function != binding.function else { return }
        var updated = binding
        updated.function = function
        Task { await manager.setGesture(updated) }
    }
}
