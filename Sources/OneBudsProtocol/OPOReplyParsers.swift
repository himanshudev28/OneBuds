/// Interpretations of query replies from the *documented* layouts (ProtocolSources §5–§6).
/// Until a layout is verified on hardware, callers must present results as Hypothesis.
/// Every parser validates lengths and returns `nil` instead of trapping on malformed input.
public enum OPOReplyParser {
    /// `0x8103`: `00 <3-byte product id, little-endian>` → e.g. `"063C14"`.
    public static func productID(_ payload: [UInt8]) -> String? {
        guard payload.count >= 4, payload[0] == 0x00 else { return nil }
        return String(format: "%02X%02X%02X", payload[3], payload[2], payload[1])
    }

    /// `0x8105`: `00 <count>` + UTF-8 text of comma-separated `deviceType,versionType,version` triples.
    public static func firmware(_ payload: [UInt8]) -> (count: Int, text: String)? {
        guard payload.count >= 2, payload[0] == 0x00 else { return nil }
        guard let text = String(bytes: payload[2...], encoding: .utf8) else { return nil }
        return (Int(payload[1]), text)
    }

    public struct BatteryLevel: Sendable, Equatable {
        /// `1` left, `2` right, `3` case.
        public var component: UInt8
        public var percent: Int
        public var isCharging: Bool

        public init(component: UInt8, percent: Int, isCharging: Bool) {
            self.component = component
            self.percent = percent
            self.isCharging = isCharging
        }
    }

    /// `0x8106`: `00 <n> [<component> <raw>]…`, where level = `raw & 0x7F` and charging = `raw & 0x80`.
    public static func battery(_ payload: [UInt8]) -> [BatteryLevel]? {
        guard payload.count >= 2, payload[0] == 0x00 else { return nil }
        let count = Int(payload[1])
        guard payload.count >= 2 + count * 2 else { return nil }
        return (0..<count).map { index in
            let raw = payload[3 + index * 2]
            return BatteryLevel(component: payload[2 + index * 2], percent: Int(raw & 0x7F), isCharging: raw & 0x80 != 0)
        }
    }

    /// `0x8100`: `00` + LSB-first capability bitmap. Returns the set bit indexes.
    public static func capabilityBits(_ payload: [UInt8]) -> [Int]? {
        guard !payload.isEmpty, payload[0] == 0x00 else { return nil }
        var bits: [Int] = []
        for (byteIndex, byte) in payload.dropFirst().enumerated() {
            for bit in 0..<8 where byte & (1 << bit) != 0 { bits.append(byteIndex * 8 + bit) }
        }
        return bits
    }
}
