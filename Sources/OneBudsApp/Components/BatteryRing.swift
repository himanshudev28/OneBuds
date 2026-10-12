import OneBudsCore
import SwiftUI

/// Battery level as a ring. Level changes animate (state indication); nothing animates on appear,
/// because the popover opens many times a day.
struct BatteryRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let battery: BudBattery
    var large = false

    private var diameter: CGFloat { large ? Theme.Size.batteryRingLarge : Theme.Size.batteryRing }
    private var lineWidth: CGFloat { large ? 6 : 5 }

    private var tint: Color {
        switch battery.percent {
        case ..<15: .red
        case ..<30: .orange
        default: .green
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s - 2) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(battery.percent) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(battery.percent, format: .number)
                    .font(.system(large ? .title2 : .callout, design: .rounded).bold())
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(battery.percent)))
            }
            .frame(width: diameter, height: diameter)
            .animateState(value: battery.percent)

            Label {
                Text(title)
            } icon: {
                if battery.isCharging {
                    Image(systemName: "bolt.fill").foregroundStyle(.green)
                }
            }
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) battery")
        .accessibilityValue("\(battery.percent) percent\(battery.isCharging ? ", charging" : "")")
    }
}
