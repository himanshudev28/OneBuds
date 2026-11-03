import OneBudsCore
import SwiftUI

/// One battery slot as a ring. Level changes animate (state indication); nothing animates on
/// appear, because the popover opens many times a day. A slot the earbuds did not report shows a
/// dashed ring and a dash, never a made-up level.
struct BatteryRing: View {
    enum Reading: Equatable {
        case level(BudBattery)
        /// The first read has not finished yet.
        case waiting
        /// The earbuds did not report this slot.
        case notReported
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let title: String
    let reading: Reading
    var size: Theme.Ring = .regular
    /// Where the bud is ("In ear", "In case"); shown after the title when the earbuds report it.
    var detail: String?

    private var diameter: CGFloat { size.diameter }
    private var lineWidth: CGFloat { size.lineWidth }

    private var trackOpacity: Double {
        contrast == .increased ? Theme.Battery.trackOpacityIncreasedContrast : Theme.Battery.trackOpacity
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xsPlus) {
            ZStack {
                track
                center
            }
            .frame(width: diameter, height: diameter)
            .animateState(value: reading)

            caption
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) battery")
        .accessibilityValue(accessibilityValue)
        .modifier(NotReportedHelp(isActive: reading == .notReported))
    }

    @ViewBuilder
    private var track: some View {
        switch reading {
        case .level(let battery):
            let tint = Theme.Battery.tint(for: battery.percent)
            Circle()
                .stroke(tint.opacity(trackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(battery.percent, 0), 100)) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        case .waiting:
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
        case .notReported:
            Circle()
                .inset(by: lineWidth / 4)
                .stroke(.tertiary, style: StrokeStyle(lineWidth: lineWidth / 2, dash: [3, 3]))
        }
    }

    @ViewBuilder
    private var center: some View {
        switch reading {
        case .level(let battery):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(battery.percent, format: .number)
                    .font(size.numberFont)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(battery.percent)))
                Text("%")
                    .font(size.percentFont)
                    .foregroundStyle(.secondary)
            }
            // Optical centring: the % sign pulls the number left of the ring's centre.
            .offset(x: size == .large ? 2 : 1)
        case .waiting:
            ProgressView().controlSize(.mini)
        case .notReported:
            Text(verbatim: "–")
                .font(size.numberFont)
                .foregroundStyle(.tertiary)
        }
    }

    private var caption: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            if case .level(let battery) = reading, battery.isCharging {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                    .imageScale(.small)
            }
            Text(detail.map { "\(title), \($0.lowercased())" } ?? title)
                .contentTransition(.opacity)
        }
        .font(size == .large ? .subheadline : .caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }

    private var accessibilityValue: String {
        switch reading {
        case .level(let battery):
            var parts = ["\(battery.percent) percent"]
            if battery.isCharging { parts.append("charging") }
            if let detail { parts.append(detail.lowercased()) }
            if battery.percent < Theme.Battery.low, !battery.isCharging { parts.append("low") }
            return parts.joined(separator: ", ")
        case .waiting: return "Reading"
        case .notReported: return "Not reported"
        }
    }
}

/// Explains a dashed slot on hover; no tooltip region at all for slots with a level.
private struct NotReportedHelp: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.help("The earbuds haven't reported this level.")
        } else {
            content
        }
    }
}
