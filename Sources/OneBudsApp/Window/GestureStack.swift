import OneBudsCore
import SwiftUI

/// Narrow-window fallback for `GestureTable`: one group per earbud.
struct GestureStack: View {
    @Environment(DeviceManager.self) private var manager

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach([GestureSide.left, .right], id: \.self) { side in
                let bindings = manager.gestures.filter { $0.side == side.rawValue && $0.button == 1 }
                if !bindings.isEmpty {
                    Text("\(side.displayName) Earbud").font(.subheadline.bold()).foregroundStyle(.secondary)
                    ForEach(bindings, id: \.self) { binding in
                        let name = GestureAction(rawValue: binding.action)?.displayName ?? "Action \(binding.action)"
                        LabeledContent(name) {
                            GesturePicker(binding: binding, accessibilityTitle: "\(side.displayName) earbud, \(name)")
                        }
                    }
                }
            }
        }
    }
}
