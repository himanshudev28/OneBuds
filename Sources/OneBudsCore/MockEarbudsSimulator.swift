import Foundation
import OneBudsProtocol

/// A simulated pair of earbuds that answers OPOv1 frames using the *documented* layouts and a
/// profile's parameters. Used by Demo mode and tests. Its values are fictional by design.
public actor MockEarbudsSimulator {
    private let profile: DeviceProfile
    private var decoder = OPOFrameDecoder()
    private var batteries: [(component: UInt8, raw: UInt8)] = [(1, 82), (2, 79), (3, 0x80 | 55)]
    private var noiseValue: UInt16
    private var equalizerPreset: UInt8 = 0
    private var features: [UInt8: UInt8]
    private var gestures: [GestureBinding]
    /// When true, noise-control sets are refused with status 0x0E ("no bud in ear").
    public var refusesNoiseControl = false

    public init(profile: DeviceProfile) {
        self.profile = profile
        noiseValue = profile.opo?.noiseModes.first { $0.mode == .noiseCancelling(.smart) }?.readValue
            ?? profile.opo?.noiseModes.first?.readValue ?? 0
        features = Dictionary(uniqueKeysWithValues: (profile.opo?.featureStatusIDs ?? []).map { ($0, $0 == 0x04 ? 1 : 0) })
        // One binding per documented action on each earbud, using that model's own function list,
        // with different defaults on the left and right so per-earbud handling is exercised.
        var bindings: [GestureBinding] = []
        for side: UInt8 in [1, 2] {
            for (action, functions) in (profile.opo?.gestureFunctions ?? [:]).sorted(by: { $0.key < $1.key }) {
                let choices = functions.filter { $0 != 0x00 }
                let function = choices.isEmpty ? (functions.first ?? 0) : choices[side == 1 ? 0 : min(1, choices.count - 1)]
                bindings.append(GestureBinding(side: side, button: 1, action: action, function: function))
            }
        }
        gestures = bindings
    }

    public func setRefusesNoiseControl(_ value: Bool) { refusesNoiseControl = value }

    /// Frames the buds send right after the link opens: a time request, as Nord Buds 3 Pro does (S4).
    public nonisolated func framesOnConnect() -> [Data] {
        [Data(OPOFrame(command: OPOCommand.timeRequest, sequence: 0x01).encoded())]
    }

    public func handle(_ data: Data) -> MockTransport.Reaction {
        var replies: [Data] = []
        for case .frame(let frame) in decoder.append([UInt8](data)) {
            replies += respond(to: frame).map { Data($0.encoded()) }
        }
        return replies.isEmpty ? .none : .reply(replies)
    }

    /// A battery push, for exercising unsolicited updates.
    public func batteryPush(left: UInt8, right: UInt8) -> Data {
        batteries[0].raw = left
        batteries[1].raw = right
        return Data(OPOFrame(command: 0x0204, sequence: 0xFF, payload: [0x01, 0x02, 0x01, left, 0x02, right]).encoded())
    }

    private func respond(to frame: OPOFrame) -> [OPOFrame] {
        func reply(_ payload: [UInt8]) -> OPOFrame {
            OPOFrame(command: frame.command | OPOCommand.replyBit, sequence: frame.sequence, payload: payload)
        }
        let p = frame.payload
        switch frame.command {
        case OPOCommand.handshake:
            return [reply([0x00, 0xFF, 0x77, 0x5A, 0xEA, 0x67, 0x0E, 0x20, 0x07])]
        case OPOCommand.productID:
            let id = profile.opo?.productIDs.first.flatMap { UInt32($0, radix: 16) } ?? 0
            return [reply([0x00, UInt8(id & 0xFF), UInt8((id >> 8) & 0xFF), UInt8((id >> 16) & 0xFF)])]
        case OPOCommand.firmware:
            return [reply([0x00, 0x03] + Array("1,2,151,2,2,151,3,2,105".utf8))]
        case OPOCommand.battery:
            return [reply([0x00, UInt8(batteries.count)] + batteries.flatMap { [$0.component, $0.raw] })]
        case 0x010C:
            return [reply([0x00, 0x01, 0x01, UInt8(noiseValue & 0xFF), UInt8(noiseValue >> 8)])]
        case 0x0404:
            guard !refusesNoiseControl else { return [reply([0x0E])] }
            let mask = Array(p.dropFirst(2))
            guard let option = profile.opo?.noiseModes.first(where: { $0.setMask == mask }) else { return [reply([0x01])] }
            // A generic "noise cancelling" set lands on the model's default level (Smart here).
            noiseValue = option.mode == .noiseCancelling(nil)
                ? (profile.opo?.noiseModes.first { $0.mode == .noiseCancelling(.smart) }?.readValue ?? option.readValue)
                : option.readValue
            let push = OPOFrame(command: 0x0204, sequence: 0xFF,
                                payload: [0x03, 0x01, 0x01, UInt8(noiseValue & 0xFF), UInt8(noiseValue >> 8)])
            return [reply([0x00]), push]
        case 0x010F:
            return [reply([0x00, equalizerPreset])]
        case 0x0406:
            equalizerPreset = p.first ?? equalizerPreset
            return [reply([0x00])]
        case 0x010D:
            let ids = Array(p.dropFirst().prefix(Int(p.first ?? 0)))
            let known = ids.filter { features[$0] != nil }
            return [reply([0x00, UInt8(known.count)] + known.flatMap { [$0, features[$0] ?? 0] })]
        case 0x0403:
            guard p.count >= 2, features[p[0]] != nil else { return [reply([0x01])] }
            features[p[0]] = p[1]
            return [reply([0x00])]
        case 0x0108:
            return [reply([0x00, UInt8(gestures.count)] + gestures.flatMap(\.bytes))]
        case 0x0401:
            let count = Int(p.first ?? 0)
            guard p.count >= 1 + count * 4 else { return [reply([0x01])] }
            for index in 0..<count {
                let base = 1 + index * 4
                let new = GestureBinding(side: p[base], button: p[base + 1], action: p[base + 2], function: p[base + 3])
                gestures.removeAll { $0.side == new.side && $0.button == new.button && $0.action == new.action }
                gestures.append(new)
            }
            return [reply([0x00])]
        case 0x0200:
            return [reply([0x00, 0x03, 0x01, 0x02, 0x03])]
        case 0x0205:
            return [reply([0x00])]
        default:
            return [] // includes the host's 0x8500 time reply, which needs no answer
        }
    }
}
