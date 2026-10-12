import Foundation
import OneBudsBluetooth
import OneBudsCore

/// Development aid: when `ONEBUDS_SELFTEST_OUT` is set, the app runs its normal startup against real
/// Bluetooth (connect, session start, read every visible setting), writes a redacted summary to that
/// file, disconnects and quits. It never changes a setting.
@MainActor
enum SelfTest {
    static var outputFile: URL? {
        ProcessInfo.processInfo.environment["ONEBUDS_SELFTEST_OUT"].map { URL(fileURLWithPath: $0) }
    }

    static func run(model: AppModel, to file: URL) async {
        let manager = model.manager
        manager.isPacketLoggingEnabled = true
        await manager.useConnector(BluetoothConnector())
        let clock = ContinuousClock()
        let start = clock.now
        _ = await waitUntil(timeout: .seconds(45)) {
            (manager.connection.isConnected && manager.lastUpdated != nil) || isTerminal(manager.connection)
        }
        var lines = ["OneBuds self-test (read-only startup) · \(Date().formatted()) · \(String(format: "%.1f", (clock.now - start).seconds)) s",
                     "", model.connectionSummary, ""]
        if let battery = manager.battery {
            lines.append("Battery: " + [("L", battery.left), ("R", battery.right), ("case", battery.chargingCase)]
                .compactMap { name, value in value.map { "\(name) \($0.percent)%\($0.isCharging ? " charging" : "")" } }
                .joined(separator: ", "))
        }
        lines.append("Noise control: \(manager.noiseControl?.displayName ?? "not reported")")
        let presetName = manager.equalizerPreset.flatMap { id in manager.profile?.opo?.equalizerPresets.first { $0.id == id }?.name }
        lines.append("Equalizer: \(manager.equalizerPreset.map { "id \($0)" } ?? "not reported")\(presetName.map { " (\($0))" } ?? "")")
        lines.append("Features: " + manager.features.sorted { $0.key < $1.key }.map { String(format: "0x%02X=%@", $0.key, $0.value ? "on" : "off") }.joined(separator: ", "))
        let opo = manager.profile?.opo
        func functionName(_ code: UInt8) -> String { opo?.functionName(code) ?? GestureFunction.name(code) }
        lines.append("Gestures: " + manager.gestures.map { binding in
            "\(GestureSide(rawValue: binding.side)?.displayName ?? "\(binding.side)")/btn\(binding.button)/\(GestureAction(rawValue: binding.action)?.displayName ?? "\(binding.action)") → \(functionName(binding.function))"
        }.joined(separator: "; "))
        if let error = manager.lastError { lines.append("Last error: \(error)") }
        lines.append("")
        lines.append("Packet log (\(manager.packetLog.count)):")
        lines += manager.packetLog.map { "\($0.direction.rawValue) \($0.summary)  [\($0.hex)]" }
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        await manager.disconnect()
        exit(manager.lastUpdated != nil ? 0 : 1)
    }

    private static func isTerminal(_ state: DeviceManager.ConnectionState) -> Bool {
        switch state {
        case .failed, .unauthorized, .bluetoothOff, .bluetoothUnsupported, .unrecognised, .noDevice: true
        default: false
        }
    }
}
