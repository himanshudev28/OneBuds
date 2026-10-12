import Foundation

public enum Manufacturer: String, Sendable, Codable, CaseIterable {
    case onePlus = "OnePlus", oppo = "OPPO", realme
}

public enum ProtocolKind: String, Sendable, Codable {
    case opoV1 = "OPOv1"
}

/// Maps a noise-control mode to the bytes OneBuds writes and the value the earbuds report back.
public struct NoiseModeOption: Sendable, Hashable {
    public var mode: NoiseControlMode
    /// Bytes after `01 01` in a `0x0404` set command.
    public var setMask: [UInt8]
    /// 16-bit value in `0x810C` replies and `03` pushes.
    public var readValue: UInt16

    public init(_ mode: NoiseControlMode, set setMask: [UInt8], read readValue: UInt16) {
        self.mode = mode
        self.setMask = setMask
        self.readValue = readValue
    }
}

public struct EQPresetOption: Sendable, Hashable, Identifiable {
    public var id: UInt8
    public var name: String
    /// Minimum firmware (first number of the firmware summary) where documented.
    public var minimumFirmware: Int?

    public init(id: UInt8, name: String, minimumFirmware: Int? = nil) {
        self.id = id
        self.name = name
        self.minimumFirmware = minimumFirmware
    }
}

/// Parameters of the OPOv1 protocol for one model. Nothing model-specific is hard-coded in the
/// protocol implementation.
public struct OPOParameters: Sendable {
    /// Product ids accepted after the `0x0103` query; a mismatch stops the session.
    public var productIDs: [String]
    /// Answer the buds' `0x0500` time request with the current time.
    public var answersTimeRequest: Bool
    /// Query `0x0200` and subscribe with `0x0205` after the handshake.
    public var subscribesToEvents: Bool
    public var noiseModes: [NoiseModeOption]
    public var equalizerPresets: [EQPresetOption]
    /// Feature switch ids the model lists for `0x010D` (only these are ever queried).
    public var featureStatusIDs: [UInt8]
    public var gameModeFeatureID: UInt8?
    public var wearDetectionFeatureID: UInt8?
    public var dualConnectionFeatureID: UInt8?
    /// Allowed gesture functions per action (`GestureAction` raw value → function codes).
    public var gestureFunctions: [UInt8: [UInt8]]
    /// Model-specific function names that override `GestureFunction.names` (e.g. realme uses
    /// `04` for the voice assistant where OnePlus uses `03`).
    public var gestureFunctionNames: [UInt8: String]

    public func functionName(_ code: UInt8) -> String { gestureFunctionNames[code] ?? GestureFunction.name(code) }

    /// Feature ids OneBuds may ever write with `0x0403`. Power saving (0x17, restarts the buds)
    /// and Hi-Res (0x18, drops the link) are deliberately never writable.
    public var writableFeatureIDs: Set<UInt8> {
        Set([gameModeFeatureID, wearDetectionFeatureID, dualConnectionFeatureID].compactMap { $0 })
    }

    public init(productIDs: [String], answersTimeRequest: Bool = true, subscribesToEvents: Bool = true,
                noiseModes: [NoiseModeOption] = [], equalizerPresets: [EQPresetOption] = [],
                featureStatusIDs: [UInt8] = [], gameModeFeatureID: UInt8? = nil, wearDetectionFeatureID: UInt8? = nil,
                dualConnectionFeatureID: UInt8? = nil, gestureFunctions: [UInt8: [UInt8]] = [:],
                gestureFunctionNames: [UInt8: String] = [:]) {
        self.productIDs = productIDs
        self.answersTimeRequest = answersTimeRequest
        self.subscribesToEvents = subscribesToEvents
        self.noiseModes = noiseModes
        self.equalizerPresets = equalizerPresets
        self.featureStatusIDs = featureStatusIDs
        self.gameModeFeatureID = gameModeFeatureID
        self.wearDetectionFeatureID = wearDetectionFeatureID
        self.dualConnectionFeatureID = dualConnectionFeatureID
        self.gestureFunctions = gestureFunctions
        self.gestureFunctionNames = gestureFunctionNames
    }
}

public struct BLEParameters: Sendable {
    public var serviceUUID: String
    public var writeUUID: String
    public var notifyUUID: String
}

public struct HardwareEvidence: Sendable, Identifiable {
    public var id: String { "\(date)-\(what)" }
    public var date: String
    public var firmware: String?
    public var what: String
    public var by: String
}

public struct DeviceProfile: Sendable, Identifiable {
    public var id: String
    public var manufacturer: Manufacturer
    public var model: String
    public var displayName: String
    /// Exact Bluetooth names (case-insensitive) that select this profile.
    public var bluetoothNames: [String]
    /// Transports in preference order.
    public var transports: [TransportKind]
    /// SDP service UUIDs to try, in order, for the RFCOMM control channel.
    public var rfcommServiceUUIDs: [String]
    public var ble: BLEParameters?
    public var protocolKind: ProtocolKind
    public var opo: OPOParameters?
    public var status: SupportStatus
    public var capabilities: [Capability: SupportStatus]
    public var testedFirmware: [String]
    public var limitations: [String]
    /// Keys into Documentation/ProtocolSources.md (S1…S15, PhaseB-Report).
    public var sources: [String]
    public var evidence: [HardwareEvidence]

    public func support(_ capability: Capability) -> SupportStatus {
        guard status != .unknown, status != .unsupported else { return .unsupported }
        return capabilities[capability] ?? .unsupported
    }

    public func presentation(_ capability: Capability) -> CapabilityPresentation {
        CapabilityPresentation(support(capability))
    }

    /// Whether OneBuds may open a control session at all. Unknown models get diagnostics only.
    public var allowsControlSession: Bool {
        (status == .verified || status == .experimental) && opo != nil
    }
}
