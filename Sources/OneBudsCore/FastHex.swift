/// Uppercase, space-separated hex without `String(format:)` (which is slow per byte).
enum FastHex {
    private static let digits = Array("0123456789ABCDEF".utf8)

    static func string(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        var out = [UInt8]()
        out.reserveCapacity(bytes.count * 3 - 1)
        for (index, byte) in bytes.enumerated() {
            if index > 0 { out.append(0x20) }
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }
}
