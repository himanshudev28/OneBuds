import Foundation

/// The data-driven compatibility registry. Adding a model means adding a profile here, with
/// sources and hardware evidence. Never mark something Verified without the owner's hardware test.
public enum DeviceRegistry {
    public static let opoService = "0000079A-D102-11E1-9B23-00025B00A5A5"
    static let opoBLE = BLEParameters(serviceUUID: opoService,
                                      writeUUID: "0100079A-D102-11E1-9B23-00025B00A5A5",
                                      notifyUUID: "0200079A-D102-11E1-9B23-00025B00A5A5")

    /// Noise-control values for the "NC tree" models (Buds 3, Buds Pro 2/3, Nord Buds 3 Pro).
    /// Hypothesis from S4's set/read tables and S12's values verified on the OPPO Enco Air5 Pro,
    /// which has an identical tree; S11 disagrees on the level bits (ProtocolSources §7, C2).
    static let ncTreeModes: [NoiseModeOption] = [
        NoiseModeOption(.off, set: [0x01], read: 0x0008),
        NoiseModeOption(.transparency, set: [0x04], read: 0x0100),
        NoiseModeOption(.noiseCancelling(nil), set: [0x02], read: 0x0002),
        NoiseModeOption(.noiseCancelling(.smart), set: [0x80], read: 0x0080),
        NoiseModeOption(.noiseCancelling(.deep), set: [0x10], read: 0x0010),
        NoiseModeOption(.noiseCancelling(.medium), set: [0x20], read: 0x0020),
        NoiseModeOption(.noiseCancelling(.light), set: [0x40], read: 0x0040),
    ]

    public static let onePlusBuds3 = DeviceProfile(
        id: "oneplus-buds-3",
        manufacturer: .onePlus,
        model: "OnePlus Buds 3 (E509A)",
        displayName: "OnePlus Buds 3",
        bluetoothNames: ["OnePlus Buds 3"],
        // Both bearers are exposed (Observed, PhaseB-Report §4). RFCOMM is HeyMelody's SPP route.
        transports: [.rfcomm, .ble],
        rfcommServiceUUIDs: [opoService],
        ble: opoBLE,
        protocolKind: .opoV1,
        opo: OPOParameters(
            productIDs: ["063C14"],
            noiseModes: ncTreeModes,
            equalizerPresets: [
                EQPresetOption(id: 0, name: "Balanced"),
                EQPresetOption(id: 1, name: "Deep Sea Bass"),
                EQPresetOption(id: 2, name: "Pure Vocals"),
                EQPresetOption(id: 3, name: "Bright & Crisp", minimumFirmware: 119),
            ],
            featureStatusIDs: [0x05, 0x04, 0x0B, 0x11, 0x18, 0x06, 0x1B, 0x1D, 0x1C],
            gameModeFeatureID: 0x06,
            wearDetectionFeatureID: 0x04,
            dualConnectionFeatureID: 0x11,
            gestureFunctions: [
                GestureAction.single.rawValue: [0x00, 0x01],
                GestureAction.double.rawValue: [0x03, 0x01, 0x05, 0x06, 0x11, 0x00],
                GestureAction.triple.rawValue: [0x03, 0x05, 0x06, 0x11, 0x00],
                GestureAction.hold.rawValue: [0x08],
                GestureAction.slide.rawValue: [0x07, 0x0A, 0x00],
            ]),
        status: .verified,
        capabilities: [
            .battery: .verified, .noiseControl: .verified, .equalizer: .verified,
            .gestures: .verified, .gameMode: .verified, .wearDetection: .experimental,
            .dualConnection: .experimental, .deviceInfo: .verified,
        ],
        testedFirmware: ["127.127.101"],
        limitations: [
            "Verified on firmware 127.127.101 (2026-10-12): every read, all 7 noise modes, 4 EQ presets, game mode, one gesture change; pushes for noise and EQ.",
            "In-ear detection: switch 0x04 toggles and is confirmed, but its effect is not yet confirmed (sources disagree on the id).",
            "Dual connection: read only so far; not toggled (switching it off could drop the Mac's link).",
            "No Adaptive mode in the vendor model list.",
            "Custom EQ curves are not implemented.",
        ],
        sources: ["S4", "S5", "S7", "S10", "S11", "S12", "PhaseB-Report §4"],
        evidence: [
            HardwareEvidence(date: "2026-10-12", firmware: nil,
                             what: "Read-only: SDP 079A on RFCOMM channel 15 and BLE GATT 0100/0200079A observed; advertisement product id 063C14",
                             by: "owner"),
            HardwareEvidence(date: "2026-10-12", firmware: "127.127.101",
                             what: "Observed over RFCOMM ch 15 (owner-approved): handshake, product id 063C14, firmware, battery, noise/EQ/feature/gesture reads; awaiting owner confirmation and set-command tests",
                             by: "owner-approved probe"),
            HardwareEvidence(date: "2026-10-12", firmware: "127.127.101",
                             what: "Feature test at the owner's request: 17/17 changes acknowledged and read back (noise Off/Transparency/ANC + Smart/Deep/Medium/Light, EQ 0-3, game mode, in-ear switch, left double-tap gesture), all restored; noise and EQ push events observed",
                             by: "owner-requested test"),
        ])

    public static let nordBuds3Pro = DeviceProfile(
        id: "oneplus-nord-buds-3-pro",
        manufacturer: .onePlus,
        model: "OnePlus Nord Buds 3 Pro",
        displayName: "OnePlus Nord Buds 3 Pro",
        bluetoothNames: ["OnePlus Nord Buds 3 Pro"],
        transports: [.ble, .rfcomm],
        rfcommServiceUUIDs: [opoService],
        ble: opoBLE,
        protocolKind: .opoV1,
        opo: OPOParameters(
            productIDs: ["064414"],
            noiseModes: ncTreeModes,
            featureStatusIDs: [0x05, 0x04, 0x0B, 0x0C, 0x11, 0x18, 0x06, 0x1B, 0x1D],
            gameModeFeatureID: 0x06,
            wearDetectionFeatureID: 0x04),
        status: .experimental,
        capabilities: [.battery: .experimental, .noiseControl: .experimental, .gameMode: .experimental,
                       .wearDetection: .experimental, .deviceInfo: .experimental],
        testedFirmware: [],
        limitations: [
            "Protocol reference model (S1, S2 tested it over BLE); not tested with OneBuds.",
            "Reported to offer only battery and wear events (S4 issue #2).",
        ],
        sources: ["S1", "S2", "S3", "S4"],
        evidence: [])

    /// Listed by references as likely compatible. Unknown: diagnostics only, no control session.
    public static let unknownModels: [DeviceProfile] = [
        unknown("oneplus-buds-4", .onePlus, "OnePlus Buds 4", productID: "065414", note: "Fully documented by S4 on its own hardware; not tested with OneBuds."),
        unknown("oneplus-buds-pro-3", .onePlus, "OnePlus Buds Pro 3", productID: "064014", note: nil),
        unknown("oneplus-buds-pro-2", .onePlus, "OnePlus Buds Pro 2", productID: "062014", note: nil),
        unknown("oneplus-nord-buds-3", .onePlus, "OnePlus Nord Buds 3", productID: "065014",
                note: "Uses older noise-control bits: the Buds 4 'Off' value turns ANC on here (S4)."),
        unknown("oneplus-buds-pro", .onePlus, "OnePlus Buds Pro", productID: "060C14", note: "Uses the legacy 1107 service (S5)."),
    ]

    static let standardSPP = "00001101-0000-1000-8000-00805F9B34FB"

    /// realme TL-family noise values: the written value is also the reported value (realme Link data
    /// via S4; verified by S12 on realme Buds T500 Pro, by S15 on Air6 Pro/T200). Plain ANC and Deep
    /// share 0x08, so reads of 0x08 show as Deep. Values may be reported as a single byte.
    static let realmeLevelModes: [NoiseModeOption] = [
        NoiseModeOption(.off, set: [0x01], read: 0x01),
        NoiseModeOption(.transparency, set: [0x02], read: 0x02),
        NoiseModeOption(.noiseCancelling(.deep), set: [0x08], read: 0x08),
        NoiseModeOption(.noiseCancelling(nil), set: [0x08], read: 0x08),
        NoiseModeOption(.noiseCancelling(.light), set: [0x04], read: 0x04),
        NoiseModeOption(.noiseCancelling(.medium), set: [0x10], read: 0x10),
        NoiseModeOption(.noiseCancelling(.smart), set: [0x20], read: 0x20),
    ]

    static let realmeEQ: [EQPresetOption] = [
        EQPresetOption(id: 0, name: "Pure Raw"), EQPresetOption(id: 1, name: "Deep Bass"),
        EQPresetOption(id: 2, name: "Pure Vocals"), EQPresetOption(id: 3, name: "Pure Bass"),
    ]

    /// realme gesture masks from realme Link data (S4 models.json, S15): voice assistant is 0x04.
    static let realmeGestures: [UInt8: [UInt8]] = [
        GestureAction.double.rawValue: [0x00, 0x01, 0x06, 0x04],
        GestureAction.triple.rawValue: [0x00, 0x01, 0x05, 0x06, 0x0B, 0x0C, 0x0D, 0x11, 0x04],
        GestureAction.hold.rawValue: [0x00, 0x08, 0x04, 0x11],
    ]

    static let realmeLimitations = [
        "Experimental: built from realme Link data and other realme models' hardware evidence; not yet tested on this model with OneBuds.",
        "realme reports power saving as feature 0x05; OneBuds never writes it.",
        "If the 079A service is absent, the standard serial port (0x1101) is tried; the product id must still match.",
    ]

    public static let realmeBudsAir5 = DeviceProfile(
        id: "realme-buds-air-5", manufacturer: .realme, model: "realme Buds Air 5", displayName: "realme Buds Air 5",
        bluetoothNames: ["realme Buds Air 5"], transports: [.rfcomm], rfcommServiceUUIDs: [opoService, standardSPP], ble: nil,
        protocolKind: .opoV1,
        opo: OPOParameters(productIDs: ["062012"], noiseModes: realmeLevelModes, equalizerPresets: realmeEQ,
                           featureStatusIDs: [0x04, 0x06, 0x11], gameModeFeatureID: 0x06, wearDetectionFeatureID: 0x04,
                           dualConnectionFeatureID: 0x11, gestureFunctions: realmeGestures,
                           gestureFunctionNames: [0x04: "Voice assistant", 0x03: "Function 0x03"]),
        status: .experimental,
        capabilities: [.battery: .experimental, .noiseControl: .experimental, .equalizer: .experimental, .gestures: .experimental,
                       .gameMode: .experimental, .wearDetection: .experimental, .dualConnection: .experimental, .deviceInfo: .experimental],
        testedFirmware: [], limitations: realmeLimitations, sources: ["S4", "S5", "S10", "S12", "S15"], evidence: [])

    public static let realmeBudsT300 = DeviceProfile(
        id: "realme-buds-t300", manufacturer: .realme, model: "realme Buds T300", displayName: "realme Buds T300",
        bluetoothNames: ["realme Buds T300"], transports: [.rfcomm], rfcommServiceUUIDs: [opoService, standardSPP], ble: nil,
        protocolKind: .opoV1,
        opo: OPOParameters(productIDs: ["062412"],
                           noiseModes: [NoiseModeOption(.off, set: [0x01], read: 0x01),
                                        NoiseModeOption(.transparency, set: [0x02], read: 0x02),
                                        NoiseModeOption(.noiseCancelling(nil), set: [0x08], read: 0x08)],
                           equalizerPresets: realmeEQ, featureStatusIDs: [0x06, 0x11], gameModeFeatureID: 0x06,
                           dualConnectionFeatureID: 0x11, gestureFunctions: realmeGestures,
                           gestureFunctionNames: [0x04: "Voice assistant", 0x03: "Function 0x03"]),
        status: .experimental,
        capabilities: [.battery: .experimental, .noiseControl: .experimental, .equalizer: .experimental, .gestures: .experimental,
                       .gameMode: .experimental, .dualConnection: .experimental, .deviceInfo: .experimental],
        testedFirmware: [], limitations: realmeLimitations + ["No noise-cancelling levels; no in-ear detection in the vendor list."],
        sources: ["S4", "S5", "S10", "S15"], evidence: [])

    /// Older realme Link protocol (protocolType 2): not OPO, undocumented. Never controlled.
    public static let realmeBudsWireless2 = DeviceProfile(
        id: "realme-buds-wireless-2", manufacturer: .realme, model: "realme Buds Wireless 2", displayName: "realme Buds Wireless 2",
        bluetoothNames: ["realme Buds Wireless 2"], transports: [.rfcomm], rfcommServiceUUIDs: [standardSPP], ble: nil,
        protocolKind: .opoV1, opo: nil, status: .unsupported, capabilities: [:], testedFirmware: [],
        limitations: ["Uses realme's older realme Link protocol (protocolType 2), which no source documents. Needs an Android Bluetooth capture to add."],
        sources: ["S5", "S10"], evidence: [])

    static let realmeUnknownModels: [DeviceProfile] = [
        unknown("realme-buds-air-5-pro", .realme, "realme Buds Air 5 Pro", productID: "061C12", note: nil),
        unknown("realme-buds-air-6", .realme, "realme Buds Air6", productID: "063412", note: nil),
        unknown("realme-buds-air-6-pro", .realme, "realme Buds Air6 Pro", productID: "063012", note: "Gadgetbridge connects it over standard SPP (S15)."),
        unknown("realme-buds-air-7-pro", .realme, "realme Buds Air7 Pro", productID: "064C12", note: "Owner-confirmed in QuickBuds (S4)."),
        unknown("realme-buds-t310", .realme, "realme Buds T310", productID: "063C12", note: nil),
    ]

    public static let all: [DeviceProfile] = [onePlusBuds3, nordBuds3Pro, realmeBudsAir5, realmeBudsT300]
        + unknownModels + realmeUnknownModels + [realmeBudsWireless2]

    /// Selects a profile by exact Bluetooth name first, then by product id. Never by family name.
    public static func match(name: String?, productID: String? = nil, in profiles: [DeviceProfile] = all) -> DeviceProfile? {
        if let name {
            let lowered = name.trimmingCharacters(in: .whitespaces).lowercased()
            if let profile = profiles.first(where: { $0.bluetoothNames.contains { $0.lowercased() == lowered } }) {
                return profile
            }
        }
        if let productID = productID?.uppercased() {
            return profiles.first { $0.opo?.productIDs.contains(productID) == true }
        }
        return nil
    }

    private static func unknown(_ id: String, _ manufacturer: Manufacturer, _ name: String, productID: String, note: String?) -> DeviceProfile {
        DeviceProfile(id: id, manufacturer: manufacturer, model: name, displayName: name, bluetoothNames: [name],
                      transports: [.rfcomm, .ble], rfcommServiceUUIDs: [opoService], ble: opoBLE, protocolKind: .opoV1,
                      opo: OPOParameters(productIDs: [productID]), status: .unknown, capabilities: [:], testedFirmware: [],
                      limitations: ["Listed as likely compatible by reference projects; untested. Diagnostics only."] + (note.map { [$0] } ?? []),
                      sources: ["S5"], evidence: [])
    }
}
