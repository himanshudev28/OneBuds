import Foundation
import OneBudsProtocol

/// Features OneBuds knows how to present. Each device profile rates each one independently.
public enum Capability: String, CaseIterable, Sendable, Codable, Identifiable {
    case battery, noiseControl, equalizer, gestures, gameMode, wearDetection, dualConnection, deviceInfo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .battery: "Battery"
        case .noiseControl: "Noise control"
        case .equalizer: "Equalizer"
        case .gestures: "Touch gestures"
        case .gameMode: "Game mode"
        case .wearDetection: "In-ear detection"
        case .dualConnection: "Dual connection"
        case .deviceInfo: "Device information"
        }
    }
}

/// Compatibility status, used both for whole models and for single capabilities.
public enum SupportStatus: String, Sendable, Codable, CaseIterable, Comparable {
    case verified, experimental, unsupported, unknown

    public var displayName: String { rawValue.capitalized }

    private var rank: Int {
        switch self {
        case .verified: 0
        case .experimental: 1
        case .unknown: 2
        case .unsupported: 3
        }
    }

    public static func < (lhs: SupportStatus, rhs: SupportStatus) -> Bool { lhs.rank < rhs.rank }
}

/// How the UI treats a capability: unsupported/unknown controls are hidden, experimental ones badged.
public enum CapabilityPresentation: Sendable, Equatable {
    case hidden, experimental, supported

    public init(_ status: SupportStatus) {
        switch status {
        case .verified: self = .supported
        case .experimental: self = .experimental
        case .unsupported, .unknown: self = .hidden
        }
    }
}

// MARK: Noise control

public enum ANCLevel: String, CaseIterable, Sendable, Codable, Hashable {
    case smart, deep, medium, light

    public var displayName: String {
        switch self {
        case .smart: "Smart"
        case .deep: "Deep"
        case .medium: "Medium"
        case .light: "Light"
        }
    }
}

public enum NoiseControlMode: Hashable, Sendable, Codable {
    case off
    case transparency
    /// `nil` level means "noise cancelling, device-chosen level".
    case noiseCancelling(ANCLevel?)
    case adaptive

    public var category: NoiseCategory {
        switch self {
        case .off: .off
        case .transparency: .transparency
        case .noiseCancelling: .noiseCancelling
        case .adaptive: .adaptive
        }
    }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .transparency: "Transparency"
        case .noiseCancelling(let level?): "Noise cancelling (\(level.displayName))"
        case .noiseCancelling(nil): "Noise cancelling"
        case .adaptive: "Adaptive"
        }
    }
}

public enum NoiseCategory: String, CaseIterable, Sendable, Hashable {
    case off, noiseCancelling, transparency, adaptive

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .noiseCancelling: "ANC"
        case .transparency: "Transparency"
        case .adaptive: "Adaptive"
        }
    }

    public var symbolName: String {
        switch self {
        case .off: "speaker.wave.2"
        case .noiseCancelling: "person.wave.2.fill"
        case .transparency: "ear"
        case .adaptive: "waveform.badge.magnifyingglass"
        }
    }
}

// MARK: Battery & info

public struct BudBattery: Sendable, Equatable, Codable {
    public var percent: Int
    public var isCharging: Bool
    public init(percent: Int, isCharging: Bool) {
        self.percent = percent
        self.isCharging = isCharging
    }
}

public struct BatteryStatus: Sendable, Equatable, Codable {
    public var left: BudBattery?
    public var right: BudBattery?
    public var chargingCase: BudBattery?

    public init(left: BudBattery? = nil, right: BudBattery? = nil, chargingCase: BudBattery? = nil) {
        self.left = left
        self.right = right
        self.chargingCase = chargingCase
    }

    /// Builds a status from `[component, raw]` levels; level 0 means "unknown/absent" (ProtocolSources §6).
    public init(levels: [OPOReplyParser.BatteryLevel]) {
        self.init()
        for level in levels where level.percent > 0 && level.percent <= 100 {
            let value = BudBattery(percent: level.percent, isCharging: level.isCharging)
            switch level.component {
            case 1: left = value
            case 2: right = value
            case 3: chargingCase = value
            default: break
            }
        }
    }

    /// Merges a partial update (pushes may omit components, e.g. the case when its lid is closed).
    public func merging(_ update: BatteryStatus) -> BatteryStatus {
        BatteryStatus(left: update.left ?? left, right: update.right ?? right, chargingCase: update.chargingCase ?? chargingCase)
    }

    /// Lowest bud level, for the menu-bar label.
    public var lowestBud: BudBattery? {
        [left, right].compactMap { $0 }.min { $0.percent < $1.percent }
    }

    public var isEmpty: Bool { left == nil && right == nil && chargingCase == nil }
}

public struct FirmwareComponent: Sendable, Equatable, Codable {
    /// 1 left, 2 right, 3 case (ProtocolSources §6).
    public var deviceType: Int
    public var versionType: Int
    public var version: String
}

public struct DeviceInfo: Sendable, Equatable, Codable {
    public var productID: String?
    public var firmware: [FirmwareComponent] = []
    public var firmwareRaw: String?
    public var capabilityBits: [Int] = []

    public init(productID: String? = nil) { self.productID = productID }

    /// Display version: the versionType 2 values joined by dots (documented by S4), else the raw text.
    public var firmwareSummary: String? {
        let primary = firmware.filter { $0.versionType == 2 }.map(\.version)
        if !primary.isEmpty { return primary.joined(separator: ".") }
        return firmwareRaw
    }

    /// Parses `deviceType,versionType,version` triples.
    public static func parseFirmware(_ text: String) -> [FirmwareComponent] {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return [] }
        return stride(from: 0, to: parts.count - 2, by: 3).compactMap { index in
            guard let type = Int(parts[index]), let versionType = Int(parts[index + 1]) else { return nil }
            return FirmwareComponent(deviceType: type, versionType: versionType, version: parts[index + 2])
        }
    }
}

// MARK: Gestures

public enum GestureSide: UInt8, Sendable, Codable, CaseIterable {
    case left = 1, right = 2, both = 4
    public var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .both: "Both"
        }
    }
}

public enum GestureAction: UInt8, Sendable, Codable, CaseIterable {
    case single = 1, double = 2, triple = 3, hold = 4, slide = 5, longHold = 6
    public var displayName: String {
        switch self {
        case .single: "Single tap"
        case .double: "Double tap"
        case .triple: "Triple tap"
        case .hold: "Press and hold"
        case .slide: "Slide"
        case .longHold: "Long hold"
        }
    }
}

/// Gesture function codes documented in ProtocolSources §6 (S4).
public enum GestureFunction {
    public static let names: [UInt8: String] = [
        0x00: "None", 0x01: "Play / pause", 0x03: "Voice assistant", 0x05: "Previous track",
        0x06: "Next track", 0x07: "Volume", 0x08: "Noise control cycle", 0x0A: "Switch track",
        0x0B: "Volume up", 0x0C: "Volume down", 0x0D: "Switch device", 0x11: "Game mode",
        0x1C: "Decline call", 0x1D: "Answer / end call",
    ]

    public static func name(_ code: UInt8) -> String { names[code] ?? String(format: "Function 0x%02X", code) }
}

public struct GestureBinding: Sendable, Hashable, Codable {
    public var side: UInt8
    public var button: UInt8
    public var action: UInt8
    public var function: UInt8

    public init(side: UInt8, button: UInt8, action: UInt8, function: UInt8) {
        self.side = side
        self.button = button
        self.action = action
        self.function = function
    }

    public var bytes: [UInt8] { [side, button, action, function] }
}

// MARK: Commands, responses, events

public enum EarbudCommand: Sendable, Equatable {
    case readBattery
    case readNoiseControl
    case setNoiseControl(NoiseControlMode)
    case readEqualizer
    case setEqualizer(presetID: UInt8)
    case readFeatures([UInt8])
    case setFeature(id: UInt8, enabled: Bool)
    case readGestures
    case setGestures([GestureBinding])
    case readDeviceInfo
}

public enum EarbudResponse: Sendable, Equatable {
    case battery(BatteryStatus)
    case noiseControl(NoiseControlMode)
    case equalizer(presetID: UInt8)
    case features([UInt8: Bool])
    case gestures([GestureBinding])
    case deviceInfo(DeviceInfo)
}

public struct PacketLogEntry: Sendable, Equatable, Identifiable {
    public enum Direction: String, Sendable { case sent = "TX", received = "RX" }
    public let id: UUID
    public let date: Date
    public let direction: Direction
    public let summary: String
    public let hex: String

    public init(direction: Direction, summary: String, hex: String, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.direction = direction
        self.summary = summary
        self.hex = hex
    }
}

public enum EarbudEvent: Sendable, Equatable {
    case battery(BatteryStatus)
    case noiseControl(NoiseControlMode)
    case equalizer(presetID: UInt8)
    case feature(id: UInt8, enabled: Bool)
    case wear([UInt8: UInt8])
    case packet(PacketLogEntry)
    case sessionEnded(reason: String?)
}

public enum ProtocolError: Error, Equatable, LocalizedError {
    case timeout(command: UInt16)
    case disconnected(String?)
    case rejected(command: UInt16, status: UInt8)
    case notApplied(expected: String, actual: String)
    case malformedReply(command: UInt16)
    case unsupported(String)
    case profileMismatch(expected: [String], found: String?)
    case unrecognisedValue(String)
    case sessionNotStarted

    public var errorDescription: String? {
        switch self {
        case .timeout(let command): String(format: "The earbuds did not answer (command 0x%04X).", command)
        case .disconnected(let reason): "The earbuds disconnected\(reason.map { ": \($0)" } ?? ".")"
        case .rejected(_, 0x0E): "The earbuds refused: put at least one earbud in your ear and try again."
        case .rejected(let command, let status): String(format: "The earbuds refused command 0x%04X (status 0x%02X).", command, status)
        case .notApplied(let expected, let actual): "The earbuds reported \(actual) instead of \(expected)."
        case .malformedReply(let command): String(format: "Unexpected reply format (command 0x%04X).", command)
        case .unsupported(let what): "Not supported on this model: \(what)."
        case .profileMismatch(let expected, let found): "These earbuds report product id \(found ?? "unknown"), not \(expected.joined(separator: "/")). Controls are disabled to avoid sending the wrong commands."
        case .unrecognisedValue(let what): "The earbuds reported a value OneBuds does not recognise: \(what)."
        case .sessionNotStarted: "The control session is not ready yet."
        }
    }
}
