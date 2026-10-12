/// Incremental decoder for a byte stream of OPO frames.
///
/// RFCOMM reads and BLE notifications can split one frame or merge several (ProtocolSources §4,
/// §8), so bytes are buffered and the decoder resynchronises on `0xAA` after anything invalid.
/// Every byte that is not part of a valid frame is reported, never silently dropped.
public struct OPOFrameDecoder: Sendable {
    public enum Event: Sendable, Equatable {
        case frame(OPOFrame)
        case discarded([UInt8], reason: String)
    }

    /// Upper bound on the length field; anything larger is treated as corruption.
    public static let maxBodyLength = 4096

    private var buffer: [UInt8] = []

    public init() {}

    /// Bytes still waiting for the rest of their frame.
    public var pendingByteCount: Int { buffer.count }

    public mutating func append(_ bytes: [UInt8]) -> [Event] {
        buffer += bytes
        var events: [Event] = []
        while !buffer.isEmpty {
            guard let start = buffer.firstIndex(of: OPOFrame.startOfFrame) else {
                events.append(.discarded(buffer, reason: "no start-of-frame byte"))
                buffer.removeAll()
                break
            }
            if start > 0 {
                events.append(.discarded(Array(buffer[..<start]), reason: "bytes before start-of-frame"))
                buffer.removeFirst(start)
            }

            let bodyLength: Int
            let lengthBytes: Int
            switch LEB128.decode(buffer, at: 1) {
            case .needMoreData:
                return events
            case .invalid:
                events.append(skipStartByte(reason: "invalid length field"))
                continue
            case .value(let value, let count):
                bodyLength = value
                lengthBytes = count
            }
            guard bodyLength >= OPOFrame.headerLength, bodyLength <= Self.maxBodyLength else {
                events.append(skipStartByte(reason: "length \(bodyLength) out of range"))
                continue
            }
            // Check the header as soon as it is complete, so a stray 0xAA that decodes to a long
            // length cannot stall the stream waiting for bytes that will never come.
            let headerEnd = 1 + lengthBytes + OPOFrame.headerLength
            guard buffer.count >= headerEnd else { return events }
            let payloadLength = Int(buffer[headerEnd - 2]) | Int(buffer[headerEnd - 1]) << 8
            guard payloadLength == bodyLength - OPOFrame.headerLength else {
                events.append(skipStartByte(reason: "payload length \(payloadLength) does not match frame length \(bodyLength)"))
                continue
            }
            let total = 1 + lengthBytes + bodyLength
            guard buffer.count >= total else { return events }

            let body = Array(buffer[(1 + lengthBytes)..<total])
            events.append(.frame(OPOFrame(command: UInt16(body[2]) | UInt16(body[3]) << 8,
                                          sequence: body[4],
                                          payload: Array(body[7...]),
                                          control: body[0],
                                          reserved: body[1])))
            buffer.removeFirst(total)
        }
        return events
    }

    /// Drops the current `0xAA` so the next search finds a later candidate start byte.
    private mutating func skipStartByte(reason: String) -> Event {
        buffer.removeFirst()
        return .discarded([OPOFrame.startOfFrame], reason: reason)
    }
}
