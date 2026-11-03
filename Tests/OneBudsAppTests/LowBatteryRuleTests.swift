import Testing
@testable import OneBudsApp
import OneBudsCore

@Suite struct LowBatteryRuleTests {
    private func status(_ left: Int?, _ right: Int?, charging: Bool = false) -> BatteryStatus {
        BatteryStatus(left: left.map { BudBattery(percent: $0, isCharging: charging) },
                      right: right.map { BudBattery(percent: $0, isCharging: charging) })
    }

    @Test func alertsOncePerCrossing() {
        var rule = LowBatteryRule(threshold: 20)
        #expect(rule.check(status(50, 40)).isEmpty)
        #expect(rule.check(status(20, 40)).map(\.name) == ["Left"])
        #expect(rule.check(status(19, 40)).isEmpty)          // still low: no repeat
        #expect(rule.check(status(23, 40)).isEmpty)          // inside the hysteresis band: stays armed off
        #expect(rule.check(status(20, 40)).isEmpty)
        #expect(rule.check(status(26, 40)).isEmpty)          // clearly recovered: re-armed
        #expect(rule.check(status(18, 40)).map(\.name) == ["Left"])
    }

    @Test func chargingRearmsAndIsNeverReported() {
        var rule = LowBatteryRule(threshold: 20)
        #expect(rule.check(status(10, 10, charging: true)).isEmpty)
        #expect(rule.check(status(10, 10)).map(\.name) == ["Left", "Right"])
        #expect(rule.check(status(10, 10, charging: true)).isEmpty)
        #expect(rule.check(status(10, 10)).count == 2)
    }

    @Test func missingBudsAreIgnored() {
        var rule = LowBatteryRule(threshold: 20)
        #expect(rule.check(status(nil, 5)).map(\.name) == ["Right"])
    }
}
