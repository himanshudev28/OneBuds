import Foundation

/// Command identifiers documented in ProtocolSources §5–§6. Names are for logging; documenting a
/// command here does not mean OneBuds sends it.
public enum OPOCommand {
    public static let handshake: UInt16 = 0x0100
    public static let productID: UInt16 = 0x0103
    public static let firmware: UInt16 = 0x0105
    public static let battery: UInt16 = 0x0106
    public static let timeRequest: UInt16 = 0x0500
    public static let replyBit: UInt16 = 0x8000

    static let names: [UInt16: String] = [
        0x0100: "handshake / capabilities",
        0x0102: "send vendor id",
        0x0103: "product id",
        0x0105: "firmware version",
        0x0106: "battery",
        0x0108: "gestures",
        0x0109: "wear status",
        0x010B: "colour id",
        0x010C: "noise control read",
        0x010D: "feature switches read",
        0x010F: "EQ read",
        0x0112: "multi-device list",
        0x0114: "codec",
        0x0122: "custom EQ list",
        0x0200: "notification ids",
        0x0201: "subscribe one event",
        0x0204: "event push",
        0x0205: "subscribe events",
        0x0400: "find earbuds",
        0x0401: "set gestures",
        0x0403: "set feature switch",
        0x0404: "set noise control",
        0x0406: "set EQ preset",
        0x0418: "custom EQ write",
        0x0500: "time request (buds → host)",
        0x0504: "EQ changed (buds → host)",
        0x0506: "custom EQ list changed (buds → host)",
        0x050C: "buds → host request 0x050C",
        0x051C: "buds → host request 0x051C",
        0x051D: "buds → host request 0x051D",
    ]

    public static func describe(_ command: UInt16) -> String {
        let base = command & 0x7FFF
        let name = names[base] ?? "unknown"
        return command & replyBit != 0 ? "reply: \(name)" : name
    }
}

/// The host's answer to the buds' `0x0500` time request: command `0x8500`, the request's sequence
/// number, payload `00` + Unix seconds as u32 little-endian (ProtocolSources §5, Documented by S4;
/// it also explains the "auth token" `B5 50 A0 69` in S1/S2 as 2026-02-26 13:55:01 UTC).
public enum TimeReply {
    public static func frame(answering request: OPOFrame, now: Date) -> OPOFrame {
        let seconds = UInt32(clamping: Int64(now.timeIntervalSince1970.rounded(.down)))
        let payload: [UInt8] = [0x00,
                                UInt8(seconds & 0xFF), UInt8((seconds >> 8) & 0xFF),
                                UInt8((seconds >> 16) & 0xFF), UInt8(seconds >> 24)]
        return OPOFrame(command: OPOCommand.timeRequest | OPOCommand.replyBit, sequence: request.sequence, payload: payload)
    }
}
