import Foundation

// The capability detection engine. It decides, per connected device, which features OneBuds may
// offer, and records why. A feature is offered only when every check passes:
//
//   1. The device is identified: a registry profile matches its Bluetooth name or product id, and
//      the product id the earbuds report in the session agrees with that profile.
//   2. The profile rates the feature (from hardware evidence or documented protocol sources).
//   3. The profile holds the protocol parameters the command needs (switch id, value table…).
//   4. The earbuds' own `0x8100` capability bitmap offers it, where a bit is documented.
//   5. Verified only counts over a transport it was verified on (otherwise Experimental).
//
// Detecting a device never adds a feature on its own. Values the earbuds report are recorded as
// extra evidence, but a missing reply does not hide a control (replies can time out).
// Adding a model means adding a `DeviceProfile` to `DeviceRegistry`; the engine needs no changes.

/// How the connected device was matched to a profile.
public enum DeviceIdentification: String, Sendable, Codable, Equatable {
    /// The product id the earbuds reported in the control session matches the profile.
    case reportedProductID
    /// Matched by the product id in the BLE advertisement (no session yet).
    case advertisedProductID
    /// Matched by exact Bluetooth name only.
    case bluetoothName
    /// The name points at one profile but the earbuds report another model's product id.
    case conflict
    /// No profile matches: diagnostics only.
    case unrecognised

    public var displayName: String {
        switch self {
        case .reportedProductID: "Confirmed by the product id the earbuds reported"
        case .advertisedProductID: "Matched by the advertised product id"
        case .bluetoothName: "Matched by Bluetooth name"
        case .conflict: "Name and reported product id point at different models"
        case .unrecognised: "Not a model OneBuds knows"
        }
    }
}

/// What OneBuds knows about one Bluetooth control route (GATT or RFCOMM) on this device.
public struct ProtocolSupport: Sendable, Codable, Equatable, Identifiable {
    public var kind: TransportKind
    /// The model's profile lists this route.
    public var listedInProfile: Bool
    /// Discovery found it on the device (vendor GATT service, or a paired classic device).
    public var foundOnDevice: Bool
    /// The latest connect attempt: true opened, false failed, nil not tried.
    public var opened: Bool?
    public var failure: String?
    /// Verified hardware results exist for this route.
    public var verified: Bool

    public var id: TransportKind { kind }

    public init(kind: TransportKind, listedInProfile: Bool, foundOnDevice: Bool, opened: Bool? = nil,
                failure: String? = nil, verified: Bool) {
        self.kind = kind
        self.listedInProfile = listedInProfile
        self.foundOnDevice = foundOnDevice
        self.opened = opened
        self.failure = failure
        self.verified = verified
    }
}

/// One reason behind a capability verdict.
public enum CapabilityEvidence: Sendable, Codable, Equatable {
    case unrecognisedDevice
    case identificationConflict
    /// The registry lists the model but it is not controllable (Unknown or Unsupported).
    case modelNotControllable(SupportStatus)
    /// The profile's rating, from hardware evidence or documented sources.
    case profileRating(SupportStatus)
    /// The profile lacks what the command needs (e.g. a switch id or value table).
    case missingProtocolParameters(String)
    /// Verified, but not over the transport in use.
    case notVerifiedOver(TransportKind)
    case bitmapOffers(bits: [Int])
    case bitmapLacks(bits: [Int])
    /// The feature is gated by a bitmap bit, but the earbuds sent no bitmap.
    case noBitmapReported
    /// The earbuds answered a read for this feature in this session.
    case deviceReportedValue

    public var description: String {
        switch self {
        case .unrecognisedDevice: "No profile matches this device."
        case .identificationConflict: "The earbuds report a different model than their name suggests."
        case .modelNotControllable(let status): "Model status is \(status.displayName): diagnostics only."
        case .profileRating(let status): "Model profile rates it \(status.displayName)."
        case .missingProtocolParameters(let what): "The profile has no \(what)."
        case .notVerifiedOver(let kind): "Verified only over another route, not \(kind.shortName)."
        case .bitmapOffers(let bits): "The earbuds' capability list offers it (bit \(bits.map(String.init).joined(separator: ", ")))."
        case .bitmapLacks(let bits): "The earbuds' capability list lacks bit \(bits.map(String.init).joined(separator: ", "))."
        case .noBitmapReported: "The earbuds sent no capability list to check."
        case .deviceReportedValue: "The earbuds reported its current value."
        }
    }
}

public struct CapabilityVerdict: Sendable, Codable, Equatable, Identifiable {
    public var capability: Capability
    /// Final status after every check.
    public var status: SupportStatus
    public var evidence: [CapabilityEvidence]

    public var id: Capability { capability }
    public var presentation: CapabilityPresentation { CapabilityPresentation(status) }
    public var reportedByDevice: Bool { evidence.contains(.deviceReportedValue) }
}

/// Everything the engine looks at. Built from discovery and session results; no Bluetooth types.
public struct CapabilityInput: Sendable {
    public var name: String?
    /// Product id from the BLE advertisement, if any.
    public var advertisedProductID: String?
    /// Routes discovery found on the device.
    public var discoveredTransports: [TransportKind]
    public var activeTransport: TransportKind?
    public var attempts: [TransportAttempt]
    /// From the session: reported product id, firmware, capability bitmap.
    public var deviceInfo: DeviceInfo?
    /// Features whose current value the earbuds reported this session.
    public var reported: Set<Capability>

    public init(name: String?, advertisedProductID: String? = nil, discoveredTransports: [TransportKind] = [],
                activeTransport: TransportKind? = nil, attempts: [TransportAttempt] = [],
                deviceInfo: DeviceInfo? = nil, reported: Set<Capability> = []) {
        self.name = name
        self.advertisedProductID = advertisedProductID
        self.discoveredTransports = discoveredTransports
        self.activeTransport = activeTransport
        self.attempts = attempts
        self.deviceInfo = deviceInfo
        self.reported = reported
    }
}

/// The engine's result for one device: identity, routes and a verdict for every capability.
public struct CapabilityReport: Sendable, Codable, Equatable {
    public var profileID: String?
    public var manufacturer: Manufacturer?
    public var model: String?
    public var identification: DeviceIdentification
    public var productID: String?
    public var firmware: String?
    public var capabilityBits: [Int]
    public var protocols: [ProtocolSupport]
    /// One per `Capability`, in declaration order.
    public var verdicts: [CapabilityVerdict]
    /// Summary of the profile the verdicts came from; a cached report from another app version
    /// whose profile has changed is not reused.
    public var profileFingerprint: String?
    public var createdAt: Date

    public func verdict(_ capability: Capability) -> CapabilityVerdict? {
        verdicts.first { $0.capability == capability }
    }

    public func presentation(_ capability: Capability) -> CapabilityPresentation {
        verdict(capability)?.presentation ?? .hidden
    }

    /// Capabilities OneBuds may offer on this device.
    public var offered: [Capability] { verdicts.filter { $0.presentation != .hidden }.map(\.capability) }

    /// True when the earbuds' reported product id confirmed the model. A report loaded from
    /// `CapabilityCache` keeps this value, so check where a report came from before trusting it.
    public var isConfirmed: Bool { identification == .reportedProductID }

    /// Equal apart from when it was made.
    public func hasSameContent(as other: CapabilityReport) -> Bool {
        var copy = other
        copy.createdAt = createdAt
        return copy == self
    }
}

public enum CapabilityEngine {
    // MARK: Identification

    /// Picks the profile for a device. A product id reported in the session is the strongest
    /// evidence; a name that disagrees with it is a conflict, and the device is not controlled.
    public static func identify(name: String?, advertisedProductID: String? = nil, reportedProductID: String? = nil,
                                in profiles: [DeviceProfile] = DeviceRegistry.all) -> (DeviceProfile?, DeviceIdentification) {
        let byName = DeviceRegistry.match(name: name, in: profiles)
        func normalised(_ id: String?) -> String? {
            guard let id = id?.trimmingCharacters(in: .whitespaces).uppercased(), !id.isEmpty else { return nil }
            return id
        }
        /// The one profile claiming this product id. An id claimed by two models (e.g. 060C12) never
        /// selects a profile on its own.
        func byProduct(_ id: String) -> DeviceProfile? {
            let claiming = profiles.filter { $0.opo?.productIDs.contains { $0.uppercased() == id } == true }
            return claiming.count == 1 ? claiming[0] : nil
        }
        /// Checks a name match against a product id; a profile without ids has nothing to check.
        /// As in `DeviceManager`, the earbuds' own id outranks the name when exactly one profile
        /// claims it (special editions share the base model's name).
        func checked(_ profile: DeviceProfile, against id: String, matched: DeviceIdentification) -> (DeviceProfile, DeviceIdentification) {
            let ids = profile.opo?.productIDs.map { $0.uppercased() } ?? []
            if ids.contains(id) { return (profile, matched) }
            if ids.isEmpty { return (profile, .bluetoothName) }
            if let edition = byProduct(id) {
                return (edition, matched == .bluetoothName ? .advertisedProductID : matched)
            }
            return (profile, .conflict)
        }

        if let reported = normalised(reportedProductID) {
            if let byName { return checked(byName, against: reported, matched: .reportedProductID) }
            if let profile = byProduct(reported) { return (profile, .reportedProductID) }
            return (nil, .unrecognised)
        }
        if let advertised = normalised(advertisedProductID) {
            if let byName { return checked(byName, against: advertised, matched: .bluetoothName) }
            if let profile = byProduct(advertised) { return (profile, .advertisedProductID) }
        }
        if let byName { return (byName, .bluetoothName) }
        return (nil, .unrecognised)
    }

    // MARK: Evaluation

    /// Builds the full report for a device.
    public static func evaluate(_ input: CapabilityInput, in profiles: [DeviceProfile] = DeviceRegistry.all,
                                now: Date = Date()) -> CapabilityReport {
        let (profile, identification) = identify(name: input.name, advertisedProductID: input.advertisedProductID,
                                                 reportedProductID: input.deviceInfo?.productID, in: profiles)
        return CapabilityReport(
            profileID: profile?.id, manufacturer: profile?.manufacturer, model: profile?.model,
            identification: identification,
            productID: input.deviceInfo?.productID ?? input.advertisedProductID,
            firmware: input.deviceInfo?.firmwareSummary,
            capabilityBits: input.deviceInfo?.capabilityBits ?? [],
            protocols: protocols(profile: profile, input: input),
            verdicts: Capability.allCases.map { verdict(for: $0, profile: profile, identification: identification, input: input) },
            profileFingerprint: profile.map(fingerprint(of:)),
            createdAt: now)
    }

    /// The verdict for one capability. Cheap enough to call from view bodies.
    public static func verdict(for capability: Capability, profile: DeviceProfile?, identification: DeviceIdentification,
                               input: CapabilityInput) -> CapabilityVerdict {
        func result(_ status: SupportStatus, _ evidence: [CapabilityEvidence]) -> CapabilityVerdict {
            CapabilityVerdict(capability: capability, status: status, evidence: evidence)
        }
        guard let profile, identification != .unrecognised else { return result(.unknown, [.unrecognisedDevice]) }
        guard identification != .conflict else { return result(.unsupported, [.identificationConflict]) }
        guard profile.allowsControlSession, let opo = profile.opo else {
            return result(profile.status == .unsupported ? .unsupported : .unknown, [.modelNotControllable(profile.status)])
        }

        let rating = profile.support(capability)
        var evidence: [CapabilityEvidence] = [.profileRating(rating)]
        guard rating == .verified || rating == .experimental else { return result(.unsupported, evidence) }

        if let missing = missingParameters(for: capability, in: opo) {
            evidence.append(.missingProtocolParameters(missing))
            return result(.unsupported, evidence)
        }

        let bits = input.deviceInfo?.capabilityBits ?? []
        if let needed = OPOFeatureCodec.requiredBits[capability] {
            if bits.isEmpty {
                evidence.append(.noBitmapReported)
            } else {
                let lacking = needed.filter { !bits.contains($0) }
                guard lacking.isEmpty else {
                    evidence.append(.bitmapLacks(bits: lacking))
                    return result(.unsupported, evidence)
                }
                evidence.append(.bitmapOffers(bits: needed))
            }
        }

        let status = profile.support(capability, over: input.activeTransport)
        if status != rating, let transport = input.activeTransport { evidence.append(.notVerifiedOver(transport)) }
        if input.reported.contains(capability) { evidence.append(.deviceReportedValue) }
        return result(status, evidence)
    }

    /// What a capability's commands need from the profile, mirroring the session's own checks.
    /// Nil when everything is there. Runtime-only conditions are left to the session: the fit test
    /// also needs the earbuds to accept its result event, and the BassWave strength slider needs
    /// `bassLevels` (the switch itself only needs its id).
    public static func missingParameters(for capability: Capability, in opo: OPOParameters) -> String? {
        func writable(_ id: UInt8?) -> Bool { id.map(opo.writableFeatureIDs.contains) ?? false }
        switch capability {
        case .battery, .deviceInfo: return nil
        case .noiseControl: return opo.noiseModes.isEmpty ? "noise-control value table" : nil
        case .equalizer: return opo.equalizerPresets.isEmpty ? "equalizer preset list" : nil
        case .gestures: return opo.gestureFunctions.isEmpty ? "gesture function list" : nil
        case .gameMode: return writable(opo.gameModeFeatureID) ? nil : "game mode switch id"
        case .wearDetection: return writable(opo.wearDetectionFeatureID) ? nil : "in-ear detection switch id"
        case .dualConnection: return writable(opo.dualConnectionFeatureID) ? nil : "dual connection switch id"
        case .smartVolume: return writable(opo.smartVolumeFeatureID) ? nil : "smart volume switch id"
        case .bassWave: return writable(opo.bassWaveFeatureID) ? nil : "BassWave switch id"
        case .spatialAudio: return writable(opo.spatialAudioFeatureID) ? nil : "3D audio switch id"
        case .customEqualizer: return opo.customEQ == nil ? "custom EQ layout" : nil
        case .noiseCycle: return opo.noiseCycleBits.isEmpty ? "noise-control cycle bits" : nil
        case .callControls: return opo.callFunctions.isEmpty ? "call-control function list" : nil
        case .findEarbuds: return opo.findsEarbuds ? nil : "find-my-earbuds command"
        case .fitTest: return opo.runsFitTest ? nil : "fit-test command"
        case .hearingTest: return opo.runsHearingTest && opo.goldenSoundFeatureID != nil ? nil : "Golden Sound commands"
        }
    }

    /// A stable summary of everything in a profile that affects verdicts.
    public static func fingerprint(of profile: DeviceProfile) -> String {
        let ratings = Capability.allCases.map { capability -> String in
            let missing = profile.opo.flatMap { missingParameters(for: capability, in: $0) } != nil ? "-" : "+"
            return "\(capability.rawValue)=\(profile.support(capability).rawValue)\(missing)"
        }
        let bits = OPOFeatureCodec.requiredBits.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):\($0.value.map(String.init).joined(separator: "."))" }
        return [profile.id, profile.status.rawValue, ratings.joined(separator: ","),
                profile.transports.map(\.rawValue).joined(separator: ">"),
                profile.verifiedTransports.map(\.rawValue).sorted().joined(separator: "+"),
                (profile.opo?.productIDs ?? []).joined(separator: "/"), bits.joined(separator: ",")].joined(separator: "|")
    }

    // MARK: Protocols

    /// GATT and RFCOMM as the profile, discovery and the latest connect attempt describe them.
    public static func protocols(profile: DeviceProfile?, input: CapabilityInput) -> [ProtocolSupport] {
        let kinds: [TransportKind] = input.discoveredTransports.contains(.mock) ? [.mock] : [.ble, .rfcomm]
        return kinds.map { kind in
            let attempt = input.attempts.last { $0.kind == kind }
            var opened: Bool?
            var failure: String?
            switch attempt?.outcome {
            case .connected?: opened = true
            case .failed(let reason)?:
                opened = false
                failure = reason
            case nil: opened = input.activeTransport == kind ? true : nil
            }
            return ProtocolSupport(kind: kind,
                                   listedInProfile: kind == .mock || profile?.transports.contains(kind) == true,
                                   foundOnDevice: input.discoveredTransports.contains(kind),
                                   opened: opened, failure: failure,
                                   verified: profile?.verifiedTransports.contains(kind) == true)
        }
    }
}
