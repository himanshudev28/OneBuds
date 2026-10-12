import Foundation
import OneBudsBluetooth
import OneBudsCore

/// Owner-requested hardware feature test (2026-10-12), enabled only by `ONEBUDS_FEATURETEST_OUT`.
/// Exercises every *settable* control through the same `DeviceManager` calls the UI uses, records
/// whether the earbuds confirmed each change (ack + read-back), then restores the original values.
/// Dual connection is deliberately not toggled: switching it off could drop this Mac's link before
/// it can be switched back on.
@MainActor
enum FeatureTest {
    static var outputFile: URL? {
        ProcessInfo.processInfo.environment["ONEBUDS_FEATURETEST_OUT"].map { URL(fileURLWithPath: $0) }
    }

    private static var lines: [String] = []
    private static var passed = 0
    private static var failed = 0

    static func run(model: AppModel, to file: URL) async {
        let manager = model.manager
        manager.isPacketLoggingEnabled = true
        await manager.useConnector(BluetoothConnector())
        _ = await waitUntil(timeout: .seconds(45)) { manager.connection.isConnected && manager.lastUpdated != nil }
        log("OneBuds hardware feature test · \(Date().formatted())")
        log(model.connectionSummary)
        guard manager.connection.isConnected, let profile = manager.profile, let opo = profile.opo else {
            log("NOT CONNECTED: \(manager.connection.displayText). Nothing was sent.")
            return finish(manager, file)
        }

        names = opo
        let baselineNoise = manager.noiseControl
        let baselineEQ = manager.equalizerPreset
        let baselineFeatures = manager.features
        let baselineGestures = manager.gestures
        log("Baseline: noise \(baselineNoise?.displayName ?? "?") · EQ \(baselineEQ.map(String.init) ?? "?") · features \(describe(baselineFeatures)) · \(baselineGestures.count) gestures")
        if let battery = manager.battery { log("Battery: L \(battery.left?.percent ?? -1) R \(battery.right?.percent ?? -1) case \(battery.chargingCase?.percent ?? -1)") }

        // Noise control: every mode in the profile, then restore.
        log("\n== Noise control ==")
        for option in opo.noiseModes where option.mode != baselineNoise {
            await manager.setNoiseControl(option.mode)
            record("set \(option.mode.displayName)", manager.status(of: .noiseControl), reported: manager.noiseControl?.displayName)
            try? await Task.sleep(for: .milliseconds(400))
        }
        if let baselineNoise {
            await manager.setNoiseControl(baselineNoise)
            record("restore \(baselineNoise.displayName)", manager.status(of: .noiseControl), reported: manager.noiseControl?.displayName)
        }

        // Equalizer presets available on this firmware, then restore.
        log("\n== Equalizer ==")
        let firmware = manager.deviceInfo?.firmwareSummary.flatMap { Int($0.split(separator: ".").first ?? "") } ?? 0
        for preset in opo.equalizerPresets where preset.id != baselineEQ && (preset.minimumFirmware ?? 0) <= firmware {
            await manager.setEqualizer(presetID: preset.id)
            record("set \(preset.name) (\(preset.id))", manager.status(of: .equalizer), reported: manager.equalizerPreset.map { "preset \($0)" })
            try? await Task.sleep(for: .milliseconds(400))
        }
        if let baselineEQ {
            await manager.setEqualizer(presetID: baselineEQ)
            record("restore preset \(baselineEQ)", manager.status(of: .equalizer), reported: manager.equalizerPreset.map { "preset \($0)" })
        }

        // Feature switches: game mode and in-ear detection, each flipped and restored.
        log("\n== Feature switches ==")
        for (name, id) in [("Game mode", opo.gameModeFeatureID), ("In-ear detection", opo.wearDetectionFeatureID)] {
            guard let id, let original = baselineFeatures[id] else { log("- \(name): not reported, skipped"); continue }
            await manager.setFeature(id, enabled: !original)
            record("\(name) → \(!original ? "on" : "off")", manager.status(of: .feature(id)), reported: manager.features[id].map { $0 ? "on" : "off" })
            try? await Task.sleep(for: .milliseconds(400))
            await manager.setFeature(id, enabled: original)
            record("\(name) restore → \(original ? "on" : "off")", manager.status(of: .feature(id)), reported: manager.features[id].map { $0 ? "on" : "off" })
        }
        log("- Dual connection: not toggled automatically (could drop this Mac's link). Test by hand.")

        // Gestures: change one documented binding, then restore it.
        log("\n== Touch gestures ==")
        if let original = baselineGestures.first(where: { $0.side == 1 && $0.action == GestureAction.double.rawValue }),
           let alternative = opo.gestureFunctions[original.action]?.first(where: { $0 != original.function && $0 != 0x00 }) {
            var changed = original
            changed.function = alternative
            await manager.setGesture(changed)
            record("Left double tap → \(functionName(alternative))", manager.status(of: .gestures),
                   reported: manager.gestures.first { $0.side == 1 && $0.action == original.action }.map { functionName($0.function) })
            try? await Task.sleep(for: .milliseconds(400))
            await manager.setGesture(original)
            record("Left double tap restore → \(functionName(original.function))", manager.status(of: .gestures),
                   reported: manager.gestures.first { $0.side == 1 && $0.action == original.action }.map { functionName($0.function) })
        } else {
            log("- no left double-tap gesture reported; skipped")
        }

        // Final read-back: everything should match the baseline.
        log("\n== Restore check ==")
        await manager.refresh()
        let restored = manager.noiseControl == baselineNoise && manager.equalizerPreset == baselineEQ
            && manager.features == baselineFeatures && Set(manager.gestures) == Set(baselineGestures)
        log("Settings back to baseline: \(restored ? "YES" : "NO") · noise \(manager.noiseControl?.displayName ?? "?") · EQ \(manager.equalizerPreset.map(String.init) ?? "?") · features \(describe(manager.features))")
        finish(manager, file)
    }

    private static func record(_ step: String, _ status: DeviceManager.OperationStatus, reported: String?) {
        let outcome: String
        switch status {
        case .confirmed: outcome = "PASS (confirmed by earbuds)"; passed += 1
        case .failed(let message): outcome = "FAIL: \(message)"; failed += 1
        case .timedOut: outcome = "FAIL: no confirmation (timeout)"; failed += 1
        case .pending, .idle: outcome = "FAIL: no result"; failed += 1
        }
        log("- \(step): \(outcome) · earbuds report: \(reported ?? "—")")
    }

    private static var names: OPOParameters?
    private static func functionName(_ code: UInt8) -> String { names?.functionName(code) ?? GestureFunction.name(code) }

    private static func describe(_ features: [UInt8: Bool]) -> String {
        features.sorted { $0.key < $1.key }.map { String(format: "0x%02X=%@", $0.key, $0.value ? "on" : "off") }.joined(separator: ", ")
    }

    private static func log(_ line: String) { lines.append(line) }

    private static func finish(_ manager: DeviceManager, _ file: URL) {
        lines.append("\nResult: \(passed) passed, \(failed) failed")
        lines.append("\nPacket log (\(manager.packetLog.count)):")
        lines += manager.packetLog.map { "\($0.direction.rawValue) \($0.summary)  [\($0.hex)]" }
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        Task {
            await manager.disconnect()
            exit(failed == 0 && passed > 0 ? 0 : 1)
        }
    }
}
