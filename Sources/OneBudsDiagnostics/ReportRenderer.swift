import Foundation

/// Renders a ``ProbeReport`` as plain text (for pasting into chat) or JSON (for tooling).
public enum ReportRenderer {
    public static func json(_ report: ProbeReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    public static func text(_ report: ProbeReport) -> String {
        var out: [String] = []
        let iso = ISO8601DateFormatter()
        out.append("OneBuds Phase B probe report (read-only)")
        out.append("tool \(report.tool) \(report.toolVersion) · generated \(iso.string(from: report.generatedAt)) · macOS \(report.macOSVersion)")
        let o = report.options
        out.append("options: scan \(o.scanSeconds)s · SDP refresh \(o.sdpRefresh ? "on (connected candidates only)" : "off") · read standard GATT \(o.readStandardCharacteristics ? "on" : "off") · redaction \(o.redact ? "on" : "OFF") · name filter /\(o.namePattern)/i")
        out.append("No protocol messages were sent. No characteristic was written. No notification was enabled.")
        out.append("")

        out.append("== Permissions ==")
        out.append("Bluetooth authorization: \(report.permissions.bluetoothAuthorization)")
        out.append("Central manager state:   \(report.permissions.centralManagerState) (waited \(String(format: "%.1f", report.permissions.waitedSeconds))s)")
        out.append("")

        out.append("== Classic Bluetooth (IOBluetooth paired devices) ==")
        out.append("paired devices: \(report.classic.pairedDeviceCount); candidates are listed in full, others summarised")
        for device in report.classic.devices {
            out.append("")
            out.append("• \(device.name ?? "<no name>")  \(device.address ?? "")  \(device.isCandidate ? "[CANDIDATE]" : "")")
            out.append(String(format: "  connected: %@ · paired: %@ · class of device: 0x%06X (major 0x%X, minor 0x%X)",
                              yesNo(device.isConnected), yesNo(device.isPaired), device.classOfDevice, device.majorClass, device.minorClass))
            guard device.isCandidate else { continue }
            if let refresh = device.sdpRefresh {
                out.append("  SDP refresh: \(refresh.attempted ? refresh.outcome : "not attempted (\(refresh.outcome))") \(refresh.attempted ? String(format: "(%.1fs)", refresh.seconds) : "")")
            }
            if let date = device.lastServicesUpdate { out.append("  services last updated: \(iso.string(from: date))") }
            out.append("  vendor service lookups:")
            for lookup in device.vendorLookups {
                let label = KnownUUIDs.lookup(lookup.uuid)?.label ?? ""
                if lookup.found {
                    out.append("    \(lookup.uuid) FOUND · RFCOMM channel \(lookup.rfcommChannel.map(String.init) ?? "none") · name \(lookup.serviceName.map { "\"\($0)\"" } ?? "none")  (\(label))")
                } else {
                    out.append("    \(lookup.uuid) not found  (\(label))")
                }
            }
            out.append("  SDP service records: \(device.services.count)")
            for (index, record) in device.services.enumerated() {
                out.append("  [\(index)] \(record.serviceName.map { "\"\($0)\"" } ?? "<unnamed>")")
                out.append("      classes: " + (record.serviceClassUUIDs.isEmpty ? "none" : record.serviceClassUUIDs.map(describeUUID).joined(separator: "; ")))
                out.append("      RFCOMM channel: API \(record.rfcommChannelAPI.map(String.init) ?? "none") / parsed \(record.rfcommChannelParsed.map(String.init) ?? "none") · L2CAP PSM: \(record.l2capPSM.map { String(format: "0x%04X", $0) } ?? "none")")
                for attribute in record.attributes {
                    let name = SDPAttributeID.name(for: attribute.id, serviceClasses: record.serviceClassUUIDs)
                    out.append(String(format: "      0x%04X %@ = %@", attribute.id, name, SDPParsing.render(attribute.value)))
                }
            }
        }
        out.append("")

        out.append("== BLE (Core Bluetooth) ==")
        out.append("retrieveConnectedPeripherals filter: " + report.ble.retrieveConnectedServiceFilter.map(describeUUID).joined(separator: "; "))
        out.append("scan performed: \(yesNo(report.ble.scanPerformed)) · non-candidate advertisers seen (not listed): \(report.ble.nonCandidateAdvertiserCount)")
        if report.ble.peripherals.isEmpty { out.append("no candidate peripherals found") }
        for peripheral in report.ble.peripherals {
            out.append("")
            out.append("• \(peripheral.name ?? "<no name>")  \(peripheral.identifier)  \(peripheral.isCandidate ? "[CANDIDATE]" : "[non-candidate: listed only, never connected]")")
            out.append("  discovery path: \(peripheral.discoveryPaths.joined(separator: " + ")) · GATT connection: \(peripheral.connection)")
            if let ad = peripheral.advertisement {
                out.append("  advertisement: name \(ad.localName.map { "\"\($0)\"" } ?? "none") · RSSI \(ad.rssi.map(String.init) ?? "?") · connectable \(ad.isConnectable.map(yesNo) ?? "?") · tx \(ad.txPower.map(String.init) ?? "?")")
                if !ad.serviceUUIDs.isEmpty { out.append("    services: " + ad.serviceUUIDs.map(describeUUID).joined(separator: "; ")) }
                if !ad.overflowServiceUUIDs.isEmpty { out.append("    overflow services: " + ad.overflowServiceUUIDs.map(describeUUID).joined(separator: "; ")) }
                if !ad.solicitedServiceUUIDs.isEmpty { out.append("    solicited services: " + ad.solicitedServiceUUIDs.map(describeUUID).joined(separator: "; ")) }
                if !ad.serviceDataUUIDs.isEmpty { out.append("    service data for: " + ad.serviceDataUUIDs.map(describeUUID).joined(separator: "; ")) }
                if let mfr = ad.manufacturerDataHex { out.append("    manufacturer data: \(mfr)") }
            }
            for service in peripheral.services {
                out.append("  service \(describeUUID(service.uuid))\(service.isPrimary ? "" : " (secondary)")")
                if !service.includedServiceUUIDs.isEmpty {
                    out.append("    includes: " + service.includedServiceUUIDs.map(describeUUID).joined(separator: "; "))
                }
                for characteristic in service.characteristics {
                    out.append("    char \(describeUUID(characteristic.uuid))")
                    out.append(String(format: "      properties 0x%03lX: %@%@", characteristic.rawProperties,
                                      characteristic.properties.joined(separator: ", "),
                                      characteristic.isNotifying ? " · already notifying" : ""))
                    if !characteristic.descriptorUUIDs.isEmpty {
                        out.append("      descriptors: " + characteristic.descriptorUUIDs.map(describeUUID).joined(separator: "; "))
                    }
                    if let value = characteristic.readValue {
                        if let error = value.error {
                            out.append("      read: error \(error)")
                        } else {
                            out.append("      read: \(value.hex ?? "")\(value.utf8.map { "  \"\($0)\"" } ?? "")")
                        }
                    }
                }
            }
        }
        out.append("")

        out.append("== Limitations encountered ==")
        if report.limitations.isEmpty { out.append("none") }
        out.append(contentsOf: report.limitations.map { "- \($0)" })
        return out.joined(separator: "\n") + "\n"
    }

    static func describeUUID(_ uuid: String) -> String {
        let shown = BluetoothUUID.shortForm(uuid).map { "0x\($0)" } ?? uuid
        guard let known = KnownUUIDs.lookup(uuid) else { return shown }
        return "\(shown) [\(known.label)]"
    }

    private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
}
