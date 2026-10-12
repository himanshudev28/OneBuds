/// UUIDs the probe annotates in its report. Vendor entries cite Documentation/ProtocolSources.md;
/// nothing here is used to send data. Labels describe what sources *document*, not what was verified.
public struct KnownUUID: Sendable, Equatable {
    public let uuid: String
    public let label: String
    public let provenance: String
    /// True for the OPPO/OnePlus control services the probe should highlight.
    public let isVendorControl: Bool
}

public enum KnownUUIDs {
    public static let opoService = "0000079A-D102-11E1-9B23-00025B00A5A5"
    public static let opoLegacyService = "00001107-D102-11E1-9B23-00025B00A5A5"
    public static let opoWrite = "0100079A-D102-11E1-9B23-00025B00A5A5"
    public static let opoNotify = "0200079A-D102-11E1-9B23-00025B00A5A5"
    public static let opoExtended = "0000079C-D102-11E1-9B23-00025B00A5A5"
    public static let fastPair = "0000FE2C-0000-1000-8000-00805F9B34FB"
    public static let serialPort = "00001101-0000-1000-8000-00805F9B34FB"

    /// Vendor services used for `retrieveConnectedPeripherals` and SDP lookups.
    public static let vendorServices = [opoService, opoLegacyService, opoExtended, fastPair]

    public static let all: [KnownUUID] = [
        KnownUUID(uuid: opoService, label: "OPO / HeyMelody control service (SDP service on RFCOMM; GATT service on BLE)",
                  provenance: "Documented: ProtocolSources §3 (S1, S2, S4, S5, S8, S12)", isVendorControl: true),
        KnownUUID(uuid: opoLegacyService, label: "OPO legacy control service (older models)",
                  provenance: "Documented: ProtocolSources §3 (S4, S8)", isVendorControl: true),
        KnownUUID(uuid: opoWrite, label: "OPO GATT write characteristic (write without response)",
                  provenance: "Documented: ProtocolSources §3 (S1, S2, S8)", isVendorControl: true),
        KnownUUID(uuid: opoNotify, label: "OPO GATT notify characteristic",
                  provenance: "Documented: ProtocolSources §3 (S1, S2, S8)", isVendorControl: true),
        KnownUUID(uuid: opoExtended, label: "OPO extended service (reported to require encryption; never touched)",
                  provenance: "Documented: ProtocolSources §3 (S1)", isVendorControl: false),
        KnownUUID(uuid: fastPair, label: "Google Fast Pair service (Hypothesis C7: not part of OPO)",
                  provenance: "Bluetooth SIG assigned 0xFE2C", isVendorControl: false),
        KnownUUID(uuid: "FE2C1234-8366-4814-8EB0-01DE32100BEA", label: "Fast Pair Key-based Pairing characteristic",
                  provenance: "Google Fast Pair spec; seen in S3", isVendorControl: false),
        KnownUUID(uuid: "FE2C123A-8366-4814-8EB0-01DE32100BEA", label: "Fast Pair characteristic subscribed to by S2",
                  provenance: "Documented: ProtocolSources §3 (S2)", isVendorControl: false),
        KnownUUID(uuid: serialPort, label: "Serial Port Profile (generic SPP)",
                  provenance: "Bluetooth SIG assigned 0x1101", isVendorControl: false),
        KnownUUID(uuid: sig(0x1800), label: "Generic Access", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x1801), label: "Generic Attribute", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x180A), label: "Device Information", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x180F), label: "Battery Service", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x2A00), label: "Device Name", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x2A19), label: "Battery Level", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x2A24), label: "Model Number String", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x2A25), label: "Serial Number String (redacted by default)", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x2A26), label: "Firmware Revision String", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x2A27), label: "Hardware Revision String", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x2A28), label: "Software Revision String", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x2A29), label: "Manufacturer Name String", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x2A50), label: "PnP ID", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x2902), label: "Client Characteristic Configuration", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x0003), label: "RFCOMM (protocol)", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x0100), label: "L2CAP (protocol)", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x0017), label: "AVCTP (protocol)", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x0019), label: "AVDTP (protocol)", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x1108), label: "Headset", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x110A), label: "Audio Source", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x110B), label: "Audio Sink (A2DP)", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x110C), label: "A/V Remote Control Target", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x110D), label: "Advanced Audio Distribution", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x110E), label: "A/V Remote Control (AVRCP)", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x110F), label: "A/V Remote Control Controller", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x1112), label: "Headset Audio Gateway", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x111E), label: "Handsfree (HFP)", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x111F), label: "Handsfree Audio Gateway", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x1131), label: "Headset HS", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x1200), label: "PnP Information (Device ID)", provenance: "Bluetooth SIG", isVendorControl: false),
        KnownUUID(uuid: sig(0x1203), label: "Generic Audio", provenance: "Bluetooth SIG", isVendorControl: false),
    ]

    private static let byUUID: [String: KnownUUID] = Dictionary(uniqueKeysWithValues: all.map { ($0.uuid, $0) })

    public static func lookup(_ canonical: String) -> KnownUUID? { byUUID[canonical.uppercased()] }

    private static func sig(_ short: UInt16) -> String {
        BluetoothUUID.canonical(fromBytes: [UInt8(short >> 8), UInt8(short & 0xFF)])!
    }
}
