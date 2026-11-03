import Foundation
import OneBudsCore
import UserNotifications

/// Decides when an earbud has crossed the low-battery line. Pure logic, so it is unit-testable:
/// one alert per crossing, re-armed once the bud charges or climbs back above the line.
struct LowBatteryRule: Equatable {
    /// Re-arm only a few percent above the threshold, so a level wobbling on the line can't repeat the alert.
    static let hysteresis = 5
    var threshold: Int
    private(set) var alerted: Set<String> = []

    init(threshold: Int) { self.threshold = threshold }

    /// Buds that just went low, as (name, percent).
    mutating func check(_ battery: BatteryStatus) -> [(name: String, percent: Int)] {
        var fresh: [(String, Int)] = []
        for (name, bud) in [("Left", battery.left), ("Right", battery.right)] {
            guard let bud else { continue }
            if bud.isCharging || bud.percent > threshold + Self.hysteresis {
                alerted.remove(name)
            } else if bud.percent <= threshold, !alerted.contains(name) {
                alerted.insert(name)
                fresh.append((name, bud.percent))
            }
        }
        return fresh
    }

    mutating func reset() { alerted = [] }
}

/// Posts a notification when an earbud runs low. Off in Demo mode, tests and snapshots.
@MainActor
final class BatteryAlerts {
    private let manager: DeviceManager
    private let settings: AppSettings
    private var rule: LowBatteryRule
    private var authorized: Bool?

    init(manager: DeviceManager, settings: AppSettings) {
        self.manager = manager
        self.settings = settings
        rule = LowBatteryRule(threshold: settings.lowBatteryThreshold)
    }

    /// Notifications need a real app bundle; a bare test binary would crash in UserNotifications.
    private static var canNotify: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func start() {
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = manager.battery
            _ = manager.connection
            _ = settings.lowBatteryAlerts
            _ = settings.lowBatteryThreshold
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.evaluate()
                self?.observe()
            }
        }
    }

    private func evaluate() {
        if rule.threshold != settings.lowBatteryThreshold { rule = LowBatteryRule(threshold: settings.lowBatteryThreshold) }
        guard manager.connection.isConnected, let battery = manager.battery else {
            rule.reset()
            return
        }
        // While alerts can't be shown, nothing counts as alerted, so turning them on while low still alerts.
        guard settings.lowBatteryAlerts, !manager.isDemo, Self.canNotify else {
            rule.reset()
            return
        }
        let low = rule.check(battery)
        guard !low.isEmpty else { return }
        Task { await post(low) }
    }

    private func post(_ low: [(name: String, percent: Int)]) async {
        let center = UNUserNotificationCenter.current()
        if authorized == nil {
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard authorized == true else { return }
        let content = UNMutableNotificationContent()
        let model = manager.profile?.displayName ?? "Earbuds"
        content.title = "\(model) battery low"
        content.body = low.map { "\($0.name) earbud: \($0.percent)%" }.joined(separator: " · ")
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil))
    }

    /// Asks for permission when the user turns alerts on, so the first alert is not lost.
    func requestPermission() {
        guard Self.canNotify else { return }
        Task {
            authorized = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }
}
