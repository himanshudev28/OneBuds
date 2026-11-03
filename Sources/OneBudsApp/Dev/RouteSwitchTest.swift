import Foundation
import OneBudsBluetooth
import OneBudsCore

/// Development aid, enabled only by `ONEBUDS_ROUTESWITCHTEST_OUT`: connects over RFCOMM, then lets
/// the manager switch back to the preferred route (GATT) exactly as it does after a fallback, and
/// writes a redacted summary. Only reads are sent; no setting is changed.
@MainActor
enum RouteSwitchTest {
    static var outputFile: URL? {
        ProcessInfo.processInfo.environment["ONEBUDS_ROUTESWITCHTEST_OUT"].map { URL(fileURLWithPath: $0) }
    }

    static func run(model: AppModel, to file: URL) async {
        let manager = model.manager
        var lines = ["OneBuds route-switch test · \(Date().formatted())", ""]
        manager.transportPreference = .rfcommOnly
        await manager.useConnector(BluetoothConnector())
        _ = await waitUntil(timeout: .seconds(45)) { manager.connection.isConnected && manager.lastUpdated != nil }
        lines += ["== Before (RFCOMM only)", model.connectionSummary, values(manager), ""]
        guard manager.connection.isConnected, manager.transportKind == .rfcomm else {
            lines.append("NOT CONNECTED OVER RFCOMM: \(manager.connection.displayText). Nothing else was tried.")
            return finish(lines, manager, file, passed: false)
        }

        let before = manager.lastUpdated
        manager.transportPreference = .automatic
        let clock = ContinuousClock()
        let start = clock.now
        await manager.switchToPreferredRouteIfAvailable()
        _ = await waitUntil(timeout: .seconds(20)) { !manager.isSwitchingRoute && manager.lastUpdated != before }
        let elapsed = String(format: "%.1f", (clock.now - start).seconds)
        lines += ["== After switching to Automatic (\(elapsed) s)", model.connectionSummary, values(manager), ""]
        let passed = manager.connection.isConnected && manager.transportKind == .ble && manager.battery != nil
        lines.append("Result: \(passed ? "PASS" : "FAIL") · now on \(manager.transportKind?.displayName ?? "nothing")")
        finish(lines, manager, file, passed: passed)
    }

    private static func values(_ manager: DeviceManager) -> String {
        let battery = manager.battery.map { "L \($0.left?.percent ?? -1) R \($0.right?.percent ?? -1)" } ?? "not reported"
        return "Battery: \(battery) · noise \(manager.noiseControl?.displayName ?? "?") · EQ \(manager.equalizerPreset.map(String.init) ?? "?")"
    }

    private static func finish(_ lines: [String], _ manager: DeviceManager, _ file: URL, passed: Bool) {
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        Task {
            await manager.disconnect()
            exit(passed ? 0 : 1)
        }
    }
}
