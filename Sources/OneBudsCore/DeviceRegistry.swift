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
        // Both bearers are exposed and both passed the feature test (RFCOMM 2026-10-12, GATT
        // 2026-11-03). GATT is tried first at the owner's request; RFCOMM is the fallback.
        transports: [.ble, .rfcomm],
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
            ],
            // Everything below is Experimental on Buds 3: the 0x8100 bitmap offers each command
            // (bits 5, 8, 9, 19, 25, 34, 38; PhaseB-Report §6), and the layouts are S4's
            // Buds 4 captures. None has been written to Buds 3 yet.
            callFunctions: [GestureAction.double.rawValue: [0x00, 0x1D], GestureAction.longHold.rawValue: [0x00, 0x1C]],
            smartVolumeFeatureID: 0x1C,
            bassWaveFeatureID: 0x1D,
            spatialAudioFeatureID: 0x1B,
            goldenSoundFeatureID: 0x0B,
            noiseCycleBits: [.off: 0, .noiseCancelling: 1, .transparency: 2],
            customEQ: CustomEQLayout(frequencies: [62, 250, 1000, 4000, 8000, 16000], maximumGain: 6, maximumPresets: 3),
            bassLevels: -5...5,
            findsEarbuds: true,
            runsFitTest: true,
            runsHearingTest: true),
        status: .verified,
        capabilities: [
            .battery: .verified, .noiseControl: .verified, .equalizer: .verified,
            .gestures: .verified, .gameMode: .verified, .wearDetection: .experimental,
            .dualConnection: .experimental, .deviceInfo: .verified,
            .customEqualizer: .experimental, .bassWave: .experimental, .spatialAudio: .experimental,
            .smartVolume: .experimental, .noiseCycle: .experimental, .callControls: .experimental,
            .findEarbuds: .experimental, .fitTest: .experimental, .hearingTest: .experimental,
        ],
        testedFirmware: ["127.127.101"],
        limitations: [
            "Verified on firmware 127.127.101 (2026-10-12): every read, all 7 noise modes, 4 EQ presets, game mode, one gesture change; pushes for noise and EQ.",
            "In-ear detection: switch 0x04 toggles and is confirmed, but its effect is not yet confirmed (sources disagree on the id).",
            "Dual connection: read only so far; not toggled (switching it off could drop the Mac's link).",
            "No Adaptive mode in the vendor model list.",
            "Custom EQ, BassWave, 3D audio, smart volume, the noise-control cycle, call controls, find my earbuds, the fit test and Golden Sound are Experimental: the earbuds advertise them, but they have not been tested on Buds 3 yet.",
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
            HardwareEvidence(date: "2026-11-03", firmware: "127.127.101",
                             what: "Same feature test over BLE GATT (0100/0200079A via retrieveConnectedPeripherals), owner-requested: 17/17 acknowledged and read back, all restored; read-only startup over GATT, Automatic and RFCOMM-only also OK",
                             by: "owner-requested test"),
        ],
        verifiedTransports: [.rfcomm, .ble])

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
            // EQ ids 3-5, switches and gestures: S4/S5 (Documentation/ModelCatalog/oneplus.json).
            equalizerPresets: [EQPresetOption(id: 3, name: "Balanced"), EQPresetOption(id: 4, name: "Pure Vocals"),
                               EQPresetOption(id: 5, name: "Deep Sea Bass")],
            featureStatusIDs: [0x05, 0x04, 0x0B, 0x0C, 0x11, 0x18, 0x06, 0x1B, 0x1D],
            gameModeFeatureID: 0x06,
            wearDetectionFeatureID: 0x04,
            dualConnectionFeatureID: 0x11,
            gestureFunctions: [GestureAction.single.rawValue: [0x01, 0x00],
                               GestureAction.double.rawValue: [0x03, 0x02, 0x01, 0x05, 0x06, 0x00, 0x11],
                               GestureAction.triple.rawValue: [0x03, 0x02, 0x05, 0x06, 0x00, 0x11],
                               GestureAction.longHold.rawValue: [0x0B, 0x0C, 0x00]],
            bassWaveFeatureID: 0x1D,
            spatialAudioFeatureID: 0x1B,
            findsEarbuds: true,
            runsFitTest: true),
        status: .experimental,
        capabilities: [.battery: .experimental, .noiseControl: .experimental, .equalizer: .experimental,
                       .gestures: .experimental, .gameMode: .experimental, .wearDetection: .experimental,
                       .dualConnection: .experimental, .bassWave: .experimental, .spatialAudio: .experimental,
                       .findEarbuds: .experimental, .fitTest: .experimental, .deviceInfo: .experimental],
        testedFirmware: [],
        limitations: [
            "Protocol reference model (S1, S2 tested it over BLE); not tested with OneBuds.",
            "Reported to offer only battery and wear events (S4 issue #2).",
            "Needs the 0x0500 time reply or the link drops after 3-5 s (S4 issue #2); OneBuds sends it.",
            "Noise level read-backs are assumed from the NC tree (verified on Buds 3, Pro 2 and Pro 3), not captured on this model.",
        ],
        sources: ["S1", "S2", "S3", "S4"],
        evidence: [])


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
        EQPresetOption(id: 2, name: "Pure Voice"), EQPresetOption(id: 3, name: "Pure Bass"),
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


    /// Vendor GATT services of every known model (used to find already-connected BLE peripherals).
    public static var bleServiceUUIDs: [String] { DeviceProfile.bleServiceUUIDs(in: all) }

    /// Hand-written profiles (hardware-backed or owner-specific) first, then the generated catalogue
    /// (DeviceCatalog.swift, from Documentation/ModelCatalog via scripts/generate-catalog.py).
    public static let all: [DeviceProfile] = [onePlusBuds3, nordBuds3Pro, realmeBudsAir5, realmeBudsT300]
        + catalogControlProfiles + catalogOtherProfiles + [realmeBudsWireless2]

    /// Selects a profile by exact Bluetooth name first, then by product id. Never by family name.
    public static func match(name: String?, productID: String? = nil, in profiles: [DeviceProfile] = all) -> DeviceProfile? {
        if let name {
            let lowered = name.trimmingCharacters(in: .whitespaces).lowercased()
            if let profile = profiles.first(where: { $0.bluetoothNames.contains { $0.lowercased() == lowered } }) {
                return profile
            }
        }
        // A product id shared by two models (OPPO Enco Buds2 reports realme Buds Q2s' 060C12) never
        // selects a profile on its own.
        if let productID = productID?.uppercased() {
            let claims = profiles.filter { $0.opo?.productIDs.contains(productID) == true }
            return claims.count == 1 ? claims[0] : nil
        }
        return nil
    }

    static func unknown(_ id: String, _ manufacturer: Manufacturer, _ name: String, productID: String, note: String?) -> DeviceProfile {
        DeviceProfile(id: id, manufacturer: manufacturer, model: name, displayName: name, bluetoothNames: [name],
                      transports: [.ble, .rfcomm], rfcommServiceUUIDs: [opoService], ble: opoBLE, protocolKind: .opoV1,
                      opo: OPOParameters(productIDs: [productID]), status: .unknown, capabilities: [:], testedFirmware: [],
                      limitations: ["Listed as likely compatible by reference projects; untested. Diagnostics only."] + (note.map { [$0] } ?? []),
                      sources: ["S5"], evidence: [])
    }
}
