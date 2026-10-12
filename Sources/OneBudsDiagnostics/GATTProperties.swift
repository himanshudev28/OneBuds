/// Names for `CBCharacteristicProperties` raw bits, kept framework-free for testing.
public enum GATTProperties {
    static let names: [(UInt, String)] = [
        (0x001, "broadcast"),
        (0x002, "read"),
        (0x004, "writeWithoutResponse"),
        (0x008, "write"),
        (0x010, "notify"),
        (0x020, "indicate"),
        (0x040, "authenticatedSignedWrites"),
        (0x080, "extendedProperties"),
        (0x100, "notifyEncryptionRequired"),
        (0x200, "indicateEncryptionRequired"),
    ]

    public static func describe(rawValue: UInt) -> [String] {
        var result = names.filter { rawValue & $0.0 != 0 }.map(\.1)
        let unknown = rawValue & ~names.reduce(0) { $0 | $1.0 }
        if unknown != 0 { result.append(String(format: "unknown(0x%X)", unknown)) }
        return result
    }
}

/// Default Bluetooth-name pattern for candidate earbuds (case-insensitive).
public enum CandidateFilter {
    public static let defaultPattern = "oneplus|oppo|realme|enco|buds"

    public static func matches(_ name: String?, pattern: String = defaultPattern) -> Bool {
        guard let name, !name.isEmpty else { return false }
        return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
