import Foundation
import Observation
import OneBudsBluetooth
import OneBudsCore
import OneBudsDiagnostics

/// Runs the read-only Bluetooth inspection (the same code as `onebuds-probe`) for the Diagnostics
/// screen and the "Help add my model" export. Nothing is uploaded; exports are local files.
@MainActor
@Observable
final class DiagnosticsModel {
    private(set) var isRunning = false
    private(set) var reportText: String?
    private(set) var lastRun: Date?

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let options = InspectionOptions(scanSeconds: 8, permissionWaitSeconds: 30)
        let redactor = Redactor(enabled: true)
        var report = ProbeReport(toolVersion: AppModel.version, generatedAt: Date(),
                                 macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                 options: .init(scanSeconds: options.scanSeconds, sdpRefresh: options.sdpRefresh,
                                                readStandardCharacteristics: false, redact: true, namePattern: options.namePattern))
        report.tool = "OneBuds diagnostics"
        let ble = BLEInspector(options: options, redactor: redactor)
        report.permissions = await ble.start()
        let classic = ClassicInspector(options: options, redactor: redactor)
        let (classicSection, classicLimits) = await classic.inspect()
        ble.knownAddresses = classic.pairedAddresses
        let (bleSection, bleLimits) = await ble.inspect()
        report.classic = classicSection
        report.ble = bleSection
        report.limitations = classicLimits + bleLimits
        reportText = ReportRenderer.text(report)
        lastRun = Date()
    }

    /// A redacted report (plus the in-memory packet log, if any) for export.
    func exportText(connectionSummary: String, packets: [PacketLogEntry]) -> String {
        var text = "OneBuds diagnostics export · \(Date().formatted())\n\n== Connection ==\n\(connectionSummary)\n\n"
        text += reportText ?? "(Bluetooth inspection not run)\n"
        if !packets.isEmpty {
            text += "\n== Packet log (\(packets.count)) ==\n"
            text += packets.map { "\($0.date.formatted(date: .omitted, time: .standard)) \($0.direction.rawValue) \($0.summary)  [\($0.hex)]" }
                .joined(separator: "\n")
        }
        return text
    }
}
