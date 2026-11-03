import Foundation

/// Payload builders and reply parsers for the features beyond the basics. Layouts are from
/// ProtocolSources §6 and S4 (QuickBuds docs/PROTOCOL.md, GPL-3.0; facts only, written here from
/// scratch). Every parser checks lengths and returns nil rather than trapping on odd input.
public enum OPOFeatureCodec {
    // MARK: Capability bitmap

    /// `0x8100` bitmap bits that gate a feature (S4 bit table; QuickBuds marks the table as taken from
    /// the vendor app, so a missing bit only ever hides a control, it never enables one).
    /// Only the newer features are gated; the basics stay as each profile rates them.
    public static let requiredBits: [Capability: [Int]] = [
        .callControls: [3], .findEarbuds: [5], .noiseCycle: [8],
        .fitTest: [9], .hearingTest: [19, 25], .customEqualizer: [34], .bassWave: [38],
    ]

    /// True when the reported bitmap offers the capability, or when there is no bitmap to check.
    public static func bitmap(_ bits: [Int], offers capability: Capability) -> Bool {
        guard !bits.isEmpty, let needed = requiredBits[capability] else { return true }
        let set = Set(bits)
        return needed.allSatisfy(set.contains)
    }

    // MARK: Little-endian helpers

    static func minimalLE(_ value: Int) -> [UInt8] {
        var out: [UInt8] = []
        var v = value
        repeat {
            out.append(UInt8(v & 0xFF))
            v >>= 8
        } while v > 0
        return out
    }

    static func le(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
    }

    static func signed(_ byte: UInt8) -> Int { Int(Int8(bitPattern: byte)) }
    static func byte(_ value: Int) -> UInt8 { UInt8(bitPattern: Int8(clamping: value)) }

    // MARK: Wear (0x0109)

    /// `0x8109`: `<n> [<component> <status>]…`, with or without a leading `00` status byte.
    public static func wear(_ p: [UInt8]) -> [UInt8: UInt8]? {
        for offset in [0, 1] {
            if offset == 1, p.first != 0x00 { continue }
            guard p.count > offset else { continue }
            let count = Int(p[offset])
            guard count <= 3, p.count == offset + 1 + count * 2 else { continue }
            var result: [UInt8: UInt8] = [:]
            for index in 0..<count { result[p[offset + 1 + index * 2]] = p[offset + 2 + index * 2] }
            return result
        }
        return nil
    }

    // MARK: Noise cycle (0x010C 02 01 / 0x0404 02 01)

    public static func noiseCycleMask(_ categories: Set<NoiseCategory>, bits: [NoiseCategory: Int]) -> Int? {
        var mask = 0
        for category in categories {
            guard let bit = bits[category] else { return nil }
            mask |= 1 << bit
        }
        return mask == 0 ? nil : mask
    }

    public static func noiseCyclePayload(_ categories: Set<NoiseCategory>, bits: [NoiseCategory: Int]) -> [UInt8]? {
        noiseCycleMask(categories, bits: bits).map { [0x02, 0x01] + minimalLE($0) }
    }

    /// `0x810C` for `02 01`: `00 02 01 <mask LE>`; also the `03 02 01 …` push with a `00` prepended.
    public static func noiseCycle(_ p: [UInt8], bits: [NoiseCategory: Int]) -> Set<NoiseCategory>? {
        guard p.count >= 4, p.count <= 7, p[0] == 0x00, p[1] == 0x02, p[2] == 0x01 else { return nil }
        let mask = le(p[3...])
        return Set(bits.compactMap { category, bit in mask & (1 << bit) != 0 ? category : nil })
    }

    // MARK: Custom EQ (0x0122 list, 0x0418 write)

    /// `0x8122`: `00 <n>` then per preset `<selected> <min gain> <max gain> <id> <name len> <name>
    /// <band count> [<freq LE16> <gain>]…`.
    public static func customPresets(_ p: [UInt8]) -> [CustomEQPreset]? {
        guard p.count >= 2, p[0] == 0x00, p[1] <= 10 else { return nil }
        var cursor = 2
        var result: [CustomEQPreset] = []
        for _ in 0..<Int(p[1]) {
            guard cursor + 5 <= p.count else { return nil }
            let low = signed(p[cursor + 1]), high = signed(p[cursor + 2])
            let id = p[cursor + 3], nameLength = Int(p[cursor + 4])
            cursor += 5
            guard cursor + nameLength + 1 <= p.count else { return nil }
            let name = String(decoding: p[cursor..<(cursor + nameLength)], as: UTF8.self)
            cursor += nameLength
            let count = Int(p[cursor])
            cursor += 1
            guard count <= 16, cursor + count * 3 <= p.count else { return nil }
            let bands = (0..<count).map { index in
                let base = cursor + index * 3
                return EQBand(frequency: Int(p[base]) | Int(p[base + 1]) << 8, gain: signed(p[base + 2]))
            }
            cursor += count * 3
            result.append(CustomEQPreset(id: id, name: name, bands: bands,
                                         minimumGain: min(low, high), maximumGain: max(low, high)))
        }
        return cursor == p.count ? result : nil
    }

    public enum PresetAction: UInt8 { case create = 1, save = 2, delete = 3 }

    /// `0x0418 <action> <-max> <max> <id, 0 to create> <name len> <name> <n> [<freq LE16> <gain>]…`.
    public static func customPresetPayload(_ action: PresetAction, id: UInt8, name: String, bands: [EQBand], maximumGain: Int) -> [UInt8]? {
        guard CustomEQPreset.isValidName(name), (1...10).contains(bands.count),
              bands.allSatisfy({ abs($0.gain) <= maximumGain && (20...20000).contains($0.frequency) }) else { return nil }
        let text = Array(name.utf8)
        return [action.rawValue, byte(-maximumGain), byte(maximumGain), action == .create ? 0 : id, UInt8(text.count)]
            + text + [UInt8(bands.count)]
            + bands.flatMap { [UInt8($0.frequency & 0xFF), UInt8($0.frequency >> 8), byte($0.gain)] }
    }

    // MARK: BassWave strength (0x0124 / 0x041B)

    public static func bassPayload(_ level: Int) -> [UInt8] { [0xFB, 0x05, byte(level)] }

    /// `0x8124`: `00 FB 05 <level>`.
    public static func bassLevel(_ p: [UInt8]) -> Int? {
        guard p.count == 4, p[0] == 0x00, p[1] == 0xFB, p[2] == 0x05 else { return nil }
        return signed(p[3])
    }

    // MARK: Fit test (push 0x0204 04 …)

    /// Push body after the `04` type byte: `[<side> <status>]…`, side 1 left, 2 right.
    public static func fitResult(_ p: ArraySlice<UInt8>) -> FitResult {
        var result = FitResult()
        var index = p.startIndex
        while index + 1 < p.endIndex {
            let seal = FitSeal(status: p[index + 1])
            if p[index] == 1 { result.left = seal }
            if p[index] == 2 { result.right = seal }
            index += 2
        }
        return result
    }

    // MARK: Golden Sound (0x040D, 0x040E, 0x0116, 0x0411, 0x0115)

    /// The 12 levels as `<side> <frequency> <level>` triples, left 1–6 then right 1–6.
    static func hearingInfo(_ values: [Int]) -> [UInt8] {
        values.enumerated().flatMap { index, value in [UInt8(index / 6 + 1), UInt8(index % 6 + 1), byte(value)] }
    }

    static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    public static func tonePayload(_ tone: HearingTone) -> [UInt8]? {
        guard [1, 2].contains(tone.side), (1...6).contains(tone.frequency), HearingTest.levels.contains(tone.level) else { return nil }
        return [0x03, 0x01, tone.side, tone.frequency, byte(tone.level)]
    }

    public static func hearingFilterPayload(uid: UInt32, values: [Int]) -> [UInt8] {
        [0x0C] + hearingInfo(values) + bigEndian(uid)
    }

    public static func hearingRecordPayload(uid: UInt32, name: String, values: [Int]) -> [UInt8] {
        [0x03, 0x0C] + hearingInfo(values) + bigEndian(uid) + Array(name.utf8)
    }

    /// `0x8116` reply: the enhance type is byte 9 when byte 5 is `04`.
    public static func hearingEnhanceType(_ p: [UInt8]) -> UInt8? {
        guard p.count >= 10, p[0] == 0x00, p[5] == 0x04 else { return nil }
        return p[9]
    }

    /// `0x8115`: `00 03 0C` + 12 triples + uid (BE32) + name. Nil when no profile is stored.
    public static func hearingProfile(_ p: [UInt8]) -> HearingProfile? {
        guard p.count >= 43, p[0] == 0x00, p[1] == 0x03, p[2] == 0x0C else { return nil }
        let values = stride(from: 3, to: 39, by: 3).map { signed(p[$0 + 2]) }
        let uid = UInt32(p[39]) << 24 | UInt32(p[40]) << 16 | UInt32(p[41]) << 8 | UInt32(p[42])
        return HearingProfile(values: values, uid: uid, name: String(decoding: p[43...], as: UTF8.self))
    }
}
