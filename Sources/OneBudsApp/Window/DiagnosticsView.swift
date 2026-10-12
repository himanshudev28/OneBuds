import OneBudsCore
import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(DeviceManager.self) private var manager
    @State private var exportDocument: TextExportDocument?

    var body: some View {
        Form {
            Section("Connection") {
                Text(model.connectionSummary)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }

            Section {
                HStack {
                    Button(model.diagnostics.isRunning ? "Inspecting…" : "Run Bluetooth Inspection", systemImage: "antenna.radiowaves.left.and.right", action: runInspection)
                        .disabled(model.diagnostics.isRunning)
                    if model.diagnostics.isRunning { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Export Report…", systemImage: "square.and.arrow.up", action: prepareExport)
                }
                if let text = model.diagnostics.reportText {
                    InspectionReportView(text: text)
                }
            } header: {
                Text("Services and Characteristics")
            } footer: {
                FormFooter("Read-only: lists SDP records, RFCOMM channels and BLE GATT services. It never changes earbud settings. Addresses and serial numbers are redacted, and nothing is uploaded. Use it to help add an unsupported model.")
            }

            PacketLogSection()
        }
        .screenFormStyle()
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument, contentType: .plainText, defaultFilename: "OneBuds-diagnostics") { _ in
            exportDocument = nil
        }
    }

    private func runInspection() { Task { await model.diagnostics.run() } }

    private func prepareExport() {
        exportDocument = TextExportDocument(text: model.diagnostics.exportText(connectionSummary: model.connectionSummary,
                                                                               packets: manager.packetLog))
    }
}
