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

    /// Call-control functions per action, for the shared call group (button 6, side "both").
    public var callFunctions: [UInt8: [UInt8]]
    public var smartVolumeFeatureID: UInt8?
    public var bassWaveFeatureID: UInt8?
    public var spatialAudioFeatureID: UInt8?
    /// The Golden Sound switch, turned on after a hearing profile is stored.
    public var goldenSoundFeatureID: UInt8?
    /// Bits of the touch-and-hold noise cycle mask (`0x0404 02 01`); empty means not offered.
    public var noiseCycleBits: [NoiseCategory: Int]
    /// Layout used for a new custom preset when the earbuds hold none to copy it from.
    public var customEQ: CustomEQLayout?
    /// BassWave strength range (`0x041B FB 05 <level>`); nil means not offered.
    public var bassLevels: ClosedRange<Int>?
    public var findsEarbuds: Bool
    public var runsFitTest: Bool
    public var runsHearingTest: Bool

    public func functionName(_ code: UInt8) -> String { gestureFunctionNames[code] ?? GestureFunction.name(code) }

    /// Feature ids OneBuds may ever write with `0x0403`. Power saving (0x17, restarts the buds)
    /// and Hi-Res (0x18, drops the link) are deliberately never writable.
    public var writableFeatureIDs: Set<UInt8> {
        Set([gameModeFeatureID, wearDetectionFeatureID, dualConnectionFeatureID, smartVolumeFeatureID,
             bassWaveFeatureID, spatialAudioFeatureID, goldenSoundFeatureID].compactMap { $0 })
            .subtracting(Self.neverWritable)
    }

    /// Power saving restarts the buds; Hi-Res drops the link (S4); 0x05 is realme's power-saving
    /// status, which the vendor app never writes (S4). Never written, whatever a profile says.
    public static let neverWritable: Set<UInt8> = [0x05, 0x17, 0x18]

    public init(productIDs: [String], answersTimeRequest: Bool = true, subscribesToEvents: Bool = true,
                noiseModes: [NoiseModeOption] = [], equalizerPresets: [EQPresetOption] = [],
                featureStatusIDs: [UInt8] = [], gameModeFeatureID: UInt8? = nil, wearDetectionFeatureID: UInt8? = nil,
                dualConnectionFeatureID: UInt8? = nil, gestureFunctions: [UInt8: [UInt8]] = [:],
                gestureFunctionNames: [UInt8: String] = [:], callFunctions: [UInt8: [UInt8]] = [:],
                smartVolumeFeatureID: UInt8? = nil, bassWaveFeatureID: UInt8? = nil, spatialAudioFeatureID: UInt8? = nil,
                goldenSoundFeatureID: UInt8? = nil, noiseCycleBits: [NoiseCategory: Int] = [:],
                customEQ: CustomEQLayout? = nil, bassLevels: ClosedRange<Int>? = nil,
                findsEarbuds: Bool = false, runsFitTest: Bool = false, runsHearingTest: Bool = false) {
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
        self.callFunctions = callFunctions
        self.smartVolumeFeatureID = smartVolumeFeatureID
        self.bassWaveFeatureID = bassWaveFeatureID
        self.spatialAudioFeatureID = spatialAudioFeatureID
        self.goldenSoundFeatureID = goldenSoundFeatureID
        self.noiseCycleBits = noiseCycleBits
        self.customEQ = customEQ
        self.bassLevels = bassLevels
        self.findsEarbuds = findsEarbuds
        self.runsFitTest = runsFitTest
        self.runsHearingTest = runsHearingTest
    }
}

/// Custom EQ limits for one model.
public struct CustomEQLayout: Sendable, Equatable {
    /// Band centre frequencies for a new preset.
    public var frequencies: [Int]
    /// Largest gain step either way, in dB.
    public var maximumGain: Int
    /// How many custom presets the earbuds store.
    public var maximumPresets: Int

    public init(frequencies: [Int], maximumGain: Int, maximumPresets: Int) {
        self.frequencies = frequencies
        self.maximumGain = maximumGain
        self.maximumPresets = maximumPresets
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
    /// Transports the Verified hardware results were obtained over. A Verified capability used over
    /// any other transport is shown as Experimental until it has been tested there too.
    public var verifiedTransports: Set<TransportKind> = []

    public func support(_ capability: Capability) -> SupportStatus {
        guard status != .unknown, status != .unsupported else { return .unsupported }
        return capabilities[capability] ?? .unsupported
    }

    /// Support over one transport: Verified only counts on a transport it was verified on. The
    /// labelled Demo transport mirrors the profile unchanged.
    public func support(_ capability: Capability, over transport: TransportKind?) -> SupportStatus {
        let base = support(capability)
        guard base == .verified, let transport, transport != .mock, !verifiedTransports.contains(transport) else { return base }
        return .experimental
    }

    public func presentation(_ capability: Capability) -> CapabilityPresentation {
        CapabilityPresentation(support(capability))
    }

    public func presentation(_ capability: Capability, over transport: TransportKind?) -> CapabilityPresentation {
        CapabilityPresentation(support(capability, over: transport))
    }

    /// Vendor GATT service UUIDs of every profile, for discovering already-connected BLE peripherals.
    public static func bleServiceUUIDs(in profiles: [DeviceProfile]) -> [String] {
        var seen = Set<String>()
        return profiles.compactMap { $0.ble?.serviceUUID.uppercased() }.filter { seen.insert($0).inserted }
    }

    /// Whether OneBuds may open a control session at all. Unknown models get diagnostics only.
    public var allowsControlSession: Bool {
        (status == .verified || status == .experimental) && opo != nil
    }
}
