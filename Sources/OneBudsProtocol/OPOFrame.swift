/// One OPO / HeyMelody headset-protocol frame (ProtocolSources §4, Documented by S4, S5, S8, S12):
///
///     AA | length (LEB128) | control | reserved | command (u16 LE) | sequence | payloadLength (u16 LE) | payload
///
/// `length` counts every byte after itself, i.e. `7 + payload.count`. There is no checksum.
/// Clean-room implementation from the documented layout; no reference code was copied.
public struct OPOFrame: Sendable, Equatable {
    public static let startOfFrame: UInt8 = 0xAA
    /// Bytes after the length field that precede the payload.
    static let headerLength = 7

    public var control: UInt8
    public var reserved: UInt8
    public var command: UInt16
    public var sequence: UInt8
    public var payload: [UInt8]

    public init(command: UInt16, sequence: UInt8, payload: [UInt8] = [], control: UInt8 = 0, reserved: UInt8 = 0) {
        precondition(payload.count <= Int(UInt16.max), "OPO payload too long")
        self.command = command
        self.sequence = sequence
        self.payload = payload
        self.control = control
        self.reserved = reserved
    }

    /// Replies set bit 15 of the request's command (`0x0106` → `0x8106`).
    public var isReply: Bool { command & 0x8000 != 0 }
    public var baseCommand: UInt16 { command & 0x7FFF }

    public func encoded() -> [UInt8] {
        let body: [UInt8] = [control, reserved,
                             UInt8(command & 0xFF), UInt8(command >> 8),
                             sequence,
                             UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)] + payload
        return [Self.startOfFrame] + LEB128.encode(body.count) + body
    }
}

/// Unsigned little-endian base-128 varint used by the frame length field.
public enum LEB128 {
    public enum Decoded: Equatable {
        case value(Int, byteCount: Int)
        case needMoreData
        case invalid
    }

    public static func encode(_ value: Int) -> [UInt8] {
        precondition(value >= 0)
        var remaining = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            out.append(byte)
        } while remaining != 0
        return out
    }

    /// Decodes at most `maxBytes` bytes starting at `index`.
    public static func decode(_ bytes: [UInt8], at index: Int, maxBytes: Int = 3) -> Decoded {
        var value = 0
        for offset in 0..<maxBytes {
            guard index + offset < bytes.count else { return .needMoreData }
            let byte = bytes[index + offset]
            value |= Int(byte & 0x7F) << (7 * offset)
            if byte & 0x80 == 0 { return .value(value, byteCount: offset + 1) }
        }
        return .invalid
    }
}
