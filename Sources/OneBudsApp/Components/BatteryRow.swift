import OneBudsCore
import SwiftUI

/// Left, right and case, each shown only when the earbuds reported it.
struct BatteryRow: View {
    let battery: BatteryStatus
    var large = false

    var body: some View {
        HStack(alignment: .top) {
            if let left = battery.left { BatteryRing(title: "Left", battery: left, large: large) }
            if let right = battery.right { BatteryRing(title: "Right", battery: right, large: large) }
            if let chargingCase = battery.chargingCase {
                BatteryRing(title: "Case", battery: chargingCase, large: large)
                    .transition(.opacity)
            }
        }
        .animateState(value: battery.chargingCase == nil)
    }
}
