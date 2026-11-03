import OneBudsCore
import SwiftUI

/// Left, right and case in fixed, equal-width slots, so the row never reflows when a level
/// arrives or goes away. Slots the earbuds did not report are shown as such, not hidden.
struct BatteryRow: View {
    private let readings: [(title: String, reading: BatteryRing.Reading)]
    private let size: Theme.Ring
    private let details: [String??]

    /// Levels the earbuds reported; with wear data, each bud also says whether it is in an ear.
    init(battery: BatteryStatus, wear: [UInt8: UInt8] = [:], size: Theme.Ring = .regular) {
        func reading(_ bud: BudBattery?) -> BatteryRing.Reading { bud.map { .level($0) } ?? .notReported }
        readings = [("Left", reading(battery.left)), ("Right", reading(battery.right)), ("Case", reading(battery.chargingCase))]
        details = [wear[1].map { WearState(raw: $0).budCaption }, wear[2].map { WearState(raw: $0).budCaption },
                   wear[3].map { WearState(raw: $0).isLidOpen ? "Open" : "Closed" }]
        self.size = size
    }

    /// The first read is still running: the same slots, without levels.
    init(waitingWith size: Theme.Ring) {
        readings = ["Left", "Right", "Case"].map { ($0, .waiting) }
        details = [nil, nil, nil]
        self.size = size
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            ForEach(Array(readings.enumerated()), id: \.element.title) { index, slot in
                BatteryRing(title: slot.title, reading: slot.reading, size: size, detail: details[index] ?? nil)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
