import Foundation
import Testing
@testable import OneBudsProtocol

/// Fixtures are byte sequences printed in the cited sources (ProtocolSources §4–§6). They are
/// Documented, not captured from OnePlus Buds 3.
@Suite struct OPOFrameEncodingTests {
    @Test func encodesHandshake() {
        // S4 PROTOCOL.md L60-64: AA 07 00 00 00 01 01 00 00
        #expect(OPOFrame(command: 0x0100, sequence: 0x01).encoded() == [0xAA, 0x07, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00])
    }

    @Test func encodesBatteryQueryLikeS1() {
        // S1 OPOProtocol.swift L30-32: AA 07 00 00 06 01 25 00 00
        #expect(OPOFrame(command: 0x0106, sequence: 0x25).encoded() == [0xAA, 0x07, 0x00, 0x00, 0x06, 0x01, 0x25, 0x00, 0x00])
    }

    @Test func encodesPayloadFrame() {
        // S4: set ANC Off, AA 0A 00 00 04 04 06 03 00 01 01 01
        #expect(OPOFrame(command: 0x0404, sequence: 0x06, payload: [0x01, 0x01, 0x01]).encoded()
                == [0xAA, 0x0A, 0x00, 0x00, 0x04, 0x04, 0x06, 0x03, 0x00, 0x01, 0x01, 0x01])
    }

    @Test func usesTwoByteLengthAbove127() {
        let frame = OPOFrame(command: 0x8122, sequence: 0x0E, payload: Array(repeating: 0, count: 134))
        // S12 docs/PROTOCOL.md L11: aa 8d 01 00 00 22 81 0e 86 00 …
        #expect(Array(frame.encoded().prefix(10)) == [0xAA, 0x8D, 0x01, 0x00, 0x00, 0x22, 0x81, 0x0E, 0x86, 0x00])
    }

    @Test func leb128RoundTrip() {
        for value in [0, 7, 127, 128, 141, 300, 4096] {
            let encoded = LEB128.encode(value)
            #expect(LEB128.decode(encoded, at: 0) == .value(value, byteCount: encoded.count))
        }
        #expect(LEB128.decode([0x80], at: 0) == .needMoreData)
        #expect(LEB128.decode([0x80, 0x80, 0x80], at: 0) == .invalid)
    }

    @Test func replyBitHelpers() {
        let reply = OPOFrame(command: 0x8106, sequence: 1)
        #expect(reply.isReply)
        #expect(reply.baseCommand == 0x0106)
        #expect(OPOCommand.describe(0x8106) == "reply: battery")
        #expect(OPOCommand.describe(0x0777) == "unknown")
    }
}

@Suite struct TimeReplyTests {
    @Test func reproducesTheSoCalledAuthToken() {
        // S1/S2 "REGISTER": AA 0C 00 00 00 85 41 05 00 00 B5 50 A0 69 = time reply for 2026-02-26 13:55:01 UTC.
        let request = OPOFrame(command: 0x0500, sequence: 0x41)
        let reply = TimeReply.frame(answering: request, now: Date(timeIntervalSince1970: 1_772_114_101))
        #expect(reply.encoded() == [0xAA, 0x0C, 0x00, 0x00, 0x00, 0x85, 0x41, 0x05, 0x00, 0x00, 0xB5, 0x50, 0xA0, 0x69])
    }

    @Test func echoesTheRequestSequence() {
        let reply = TimeReply.frame(answering: OPOFrame(command: 0x0500, sequence: 0xFF), now: Date(timeIntervalSince1970: 0))
        #expect(reply.sequence == 0xFF)
        #expect(reply.command == 0x8500)
        #expect(reply.payload == [0, 0, 0, 0, 0])
    }
}

@Suite struct OPOFrameDecoderTests {
    let handshake: [UInt8] = [0xAA, 0x07, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00]
    // S12/S9 style concatenated pushes in one notification.
    let twoPushes: [UInt8] = [0xAA, 0x0B, 0x00, 0x00, 0x04, 0x02, 0x24, 0x04, 0x00, 0x03, 0x01, 0x01, 0x08,
                              0xAA, 0x0B, 0x00, 0x00, 0x04, 0x02, 0x25, 0x04, 0x00, 0x03, 0x02, 0x01, 0x0A]

    @Test func decodesOneFrame() {
        var decoder = OPOFrameDecoder()
        #expect(decoder.append(handshake) == [.frame(OPOFrame(command: 0x0100, sequence: 0x01))])
        #expect(decoder.pendingByteCount == 0)
    }

    @Test func splitsMergedFrames() {
        var decoder = OPOFrameDecoder()
        let events = decoder.append(twoPushes)
        #expect(events.count == 2)
        #expect(events.last == .frame(OPOFrame(command: 0x0204, sequence: 0x25, payload: [0x03, 0x02, 0x01, 0x0A])))
    }

    @Test func reassemblesSplitFrames() {
        var decoder = OPOFrameDecoder()
        #expect(decoder.append(Array(handshake.prefix(1))).isEmpty)
        #expect(decoder.append(Array(handshake[1..<5])).isEmpty)
        #expect(decoder.append(Array(handshake[5...])) == [.frame(OPOFrame(command: 0x0100, sequence: 0x01))])
    }

    @Test func reportsAndSkipsLeadingGarbage() {
        var decoder = OPOFrameDecoder()
        let events = decoder.append([0x01, 0x02] + handshake)
        #expect(events.first == .discarded([0x01, 0x02], reason: "bytes before start-of-frame"))
        #expect(events.count == 2)
    }

    @Test func resyncsAfterLengthMismatch() {
        var decoder = OPOFrameDecoder()
        // Length 7 but payload length field says 1: invalid, then a valid frame follows.
        let bad: [UInt8] = [0xAA, 0x07, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x00]
        let events = decoder.append(bad + handshake)
        #expect(events.contains(.frame(OPOFrame(command: 0x0100, sequence: 0x01))))
        #expect(events.contains { if case .discarded(_, let reason) = $0 { reason.contains("does not match") } else { false } })
    }

    @Test func rejectsTooShortLength() {
        var decoder = OPOFrameDecoder()
        let events = decoder.append([0xAA, 0x03, 0x00, 0x00, 0x00])
        #expect(events.first == .discarded([0xAA], reason: "length 3 out of range"))
    }

    @Test func keepsRealmeControlByte() {
        // S15: realme replies carry control byte 4.
        var decoder = OPOFrameDecoder()
        let events = decoder.append([0xAA, 0x07, 0x04, 0x00, 0x00, 0x81, 0x01, 0x00, 0x00])
        #expect(events == [.frame(OPOFrame(command: 0x8100, sequence: 0x01, control: 0x04))])
    }

    @Test func roundTripsRandomFrames() {
        var decoder = OPOFrameDecoder()
        var stream: [UInt8] = []
        var expected: [OPOFrameDecoder.Event] = []
        for index in 0..<50 {
            let frame = OPOFrame(command: UInt16(index * 37), sequence: UInt8(index), payload: Array(repeating: UInt8(index), count: index * 5))
            stream += frame.encoded()
            expected.append(.frame(frame))
        }
        var events: [OPOFrameDecoder.Event] = []
        var offset = 0
        while offset < stream.count {
            let size = min(1 + offset % 23, stream.count - offset)
            events += decoder.append(Array(stream[offset..<offset + size]))
            offset += size
        }
        #expect(events == expected)
    }
}

@Suite struct OPOReplyParserTests {
    @Test func productID() {
        // S4 L169-171: Buds 4 reply 00 14 54 06 = 065414; Buds 3 would be 063C14.
        #expect(OPOReplyParser.productID([0x00, 0x14, 0x54, 0x06]) == "065414")
        #expect(OPOReplyParser.productID([0x00, 0x14, 0x3C, 0x06]) == "063C14")
        #expect(OPOReplyParser.productID([0x01, 0x14, 0x3C, 0x06]) == nil)
        #expect(OPOReplyParser.productID([0x00, 0x14]) == nil)
    }

    @Test func battery() {
        // S4 L459-469 example 03 01 64 02 64 03 50, prefixed with status 00; plus a charging case.
        let levels = OPOReplyParser.battery([0x00, 0x03, 0x01, 0x64, 0x02, 0x64, 0x03, 0xD0])
        #expect(levels == [.init(component: 1, percent: 100, isCharging: false),
                           .init(component: 2, percent: 100, isCharging: false),
                           .init(component: 3, percent: 80, isCharging: true)])
        #expect(OPOReplyParser.battery([0x00, 0x03, 0x01, 0x64]) == nil)
    }

    @Test func firmware() {
        let payload: [UInt8] = [0x00, 0x01] + Array("1,2,138".utf8)
        #expect(OPOReplyParser.firmware(payload)?.text == "1,2,138")
        #expect(OPOReplyParser.firmware([0x00]) == nil)
    }

    @Test func capabilityBits() {
        #expect(OPOReplyParser.capabilityBits([0x00, 0x03, 0x80]) == [0, 1, 15])
        #expect(OPOReplyParser.capabilityBits([0x01, 0xFF]) == nil)
    }
}

@Suite struct DecoderStallTests {
    @Test func strayStartByteBeforeARealFrameDoesNotStall() {
        // Found by SessionEventTests: a lone 0xAA followed by a real frame decoded as a ~2 KB length.
        var decoder = OPOFrameDecoder()
        let reply = OPOFrame(command: 0x8106, sequence: 0x05, payload: [0x00, 0x01, 0x01, 0x50]).encoded()
        let events = decoder.append([0xAA] + reply)
        #expect(events.last == .frame(OPOFrame(command: 0x8106, sequence: 0x05, payload: [0x00, 0x01, 0x01, 0x50])))
        #expect(decoder.pendingByteCount == 0)
    }
}

@Suite struct RedactionRuleTests {
    @Test func multiDeviceFramesAreFlagged() {
        #expect(OPORedaction.containsPersonalData(OPOFrame(command: 0x0204, sequence: 3, payload: [0x06, 0x02])))
        #expect(OPORedaction.containsPersonalData(OPOFrame(command: 0x8112, sequence: 3, payload: [0x00])))
        #expect(!OPORedaction.containsPersonalData(OPOFrame(command: 0x0204, sequence: 3, payload: [0x01, 0x02])))
    }
}
