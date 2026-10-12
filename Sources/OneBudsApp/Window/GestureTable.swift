import OneBudsCore
import SwiftUI

/// Gestures as a table: one row per gesture, one column per earbud, so the two sides compare at a glance.
struct GestureTable: View {
    @Environment(DeviceManager.self) private var manager

    private var perEarbud: [GestureBinding] {
        manager.gestures.filter { $0.button == 1 && ($0.side == GestureSide.left.rawValue || $0.side == GestureSide.right.rawValue) }
    }

    private var actions: [UInt8] { Array(Set(perEarbud.map(\.action))).sorted() }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.xl, verticalSpacing: Theme.Spacing.m - 2) {
            GridRow {
                Text("Gesture")
                Text("Left Earbud")
                Text("Right Earbud")
            }
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)

            Divider().gridCellUnsizedAxes(.horizontal)

            ForEach(actions, id: \.self) { action in
                let name = GestureAction(rawValue: action)?.displayName ?? "Action \(action)"
                GridRow {
                    Text(name)
                    cell(side: .left, action: action, name: name)
                    cell(side: .right, action: action, name: name)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(side: GestureSide, action: UInt8, name: String) -> some View {
        if let binding = perEarbud.first(where: { $0.side == side.rawValue && $0.action == action }) {
            GesturePicker(binding: binding, accessibilityTitle: "\(side.displayName) earbud, \(name)")
        } else {
            Text("—").foregroundStyle(.tertiary).accessibilityLabel("Not available")
        }
    }
}
