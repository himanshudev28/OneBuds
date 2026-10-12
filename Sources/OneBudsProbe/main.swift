import AppKit
import Foundation
import OneBudsBluetooth
import OneBudsDiagnostics

let toolVersion = "0.1.0"

func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let options: ProbeOptions
do {
    guard let parsed = try ProbeOptions.parse(Array(CommandLine.arguments.dropFirst())) else {
        print(ProbeOptions.usage)
        exit(0)
    }
    options = parsed
} catch {
    writeStandardError("onebuds-probe: \(error)\n\n\(ProbeOptions.usage)")
    exit(64)
}

/// Runs the probe inside an accessory NSApplication so the main run loop is pumped for
/// IOBluetooth and Core Bluetooth callbacks, and so macOS shows the Bluetooth prompt for this app.
final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    let options: ProbeOptions
    init(options: ProbeOptions) { self.options = options }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let code = options.mode == .session ? await runSession(options: options) : await runProbe(options: options)
            exit(code)
        }
    }
}

@MainActor
func runProbe(options: ProbeOptions) async -> Int32 {
    let redactor = Redactor(enabled: options.redact)
    var report = ProbeReport(toolVersion: toolVersion, generatedAt: Date(),
                             macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                             options: options.reportOptions)
    if Bundle.main.bundleIdentifier == nil {
        report.limitations.append("Not running from the app bundle: macOS attributes Bluetooth permission to the parent process (e.g. Terminal). Use scripts/run-probe.sh.")
    }

    writeStandardError("onebuds-probe: waiting for Bluetooth (approve the permission prompt if one appears)…")
    let ble = BLEInspector(options: options.inspection, redactor: redactor)
    report.permissions = await ble.start()
    if report.permissions.bluetoothAuthorization != "allowedAlways" {
        report.limitations.append("Bluetooth permission is \(report.permissions.bluetoothAuthorization). Grant it in System Settings → Privacy & Security → Bluetooth (\"OneBuds Probe\") and run again.")
    }

    writeStandardError("onebuds-probe: inspecting paired classic devices and SDP records…")
    let classicInspector = ClassicInspector(options: options.inspection, redactor: redactor)
    let (classic, classicLimits) = await classicInspector.inspect()
    ble.knownAddresses = classicInspector.pairedAddresses
    report.classic = classic
    report.limitations += classicLimits

    writeStandardError("onebuds-probe: inspecting BLE (scan \(options.scanSeconds)s, then GATT discovery on candidates)…")
    let (bleSection, bleLimits) = await ble.inspect()
    report.ble = bleSection
    report.limitations += bleLimits

    let text = ReportRenderer.text(report)
    print(text)
    do {
        try FileManager.default.createDirectory(at: options.outDir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = "onebuds-probe-\(formatter.string(from: report.generatedAt))"
        let textURL = options.outDir.appendingPathComponent(stem + ".txt")
        let jsonURL = options.outDir.appendingPathComponent(stem + ".json")
        try Data(text.utf8).write(to: textURL)
        try ReportRenderer.json(report).write(to: jsonURL)
        writeStandardError("onebuds-probe: wrote \(textURL.path)\nonebuds-probe: wrote \(jsonURL.path)")
        return 0
    } catch {
        writeStandardError("onebuds-probe: could not write report: \(error)")
        return 1
    }
}

@MainActor
func runSession(options: ProbeOptions) async -> Int32 {
    let redactor = Redactor(enabled: options.redact)
    // Bluetooth permission must be settled before IOBluetooth or Core Bluetooth are used.
    let permissions = await BLEInspector(options: options.inspection, redactor: redactor).start()
    guard permissions.bluetoothAuthorization == "allowedAlways" else {
        writeStandardError("onebuds-probe: Bluetooth permission is \(permissions.bluetoothAuthorization); cannot run the session probe.")
        return 2
    }
    let routes = options.routes.compactMap(SessionProbe.Route.init(rawValue:))
    let text = await SessionProbe(deviceName: options.deviceName, routes: routes, redactor: redactor).run()
    print(text)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let url = options.outDir.appendingPathComponent("onebuds-session-\(formatter.string(from: Date())).txt")
    do {
        try FileManager.default.createDirectory(at: options.outDir, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        writeStandardError("onebuds-probe: wrote \(url.path)")
        return 0
    } catch {
        writeStandardError("onebuds-probe: could not write report: \(error)")
        return 1
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let appDelegate = ProbeAppDelegate(options: options)
application.delegate = appDelegate
application.run()
