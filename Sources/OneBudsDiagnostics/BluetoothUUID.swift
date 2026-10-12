import Foundation

/// Converts 16-, 32- and 128-bit Bluetooth UUIDs to one canonical, upper-case 128-bit form
/// so that UUIDs from Core Bluetooth (`CBUUID.data`) and IOBluetooth (`IOBluetoothSDPUUID`)
/// can be compared and looked up in ``KnownUUIDs``.
public enum BluetoothUUID {
    /// The Bluetooth Base UUID suffix: `xxxxxxxx-0000-1000-8000-00805F9B34FB`.
    static let baseSuffix: [UInt8] = [0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB]

    /// Returns the canonical 128-bit string for big-endian UUID bytes of length 2, 4 or 16,
    /// or `nil` for any other length.
    public static func canonical(fromBytes bytes: [UInt8]) -> String? {
        let full: [UInt8]
        switch bytes.count {
        case 2: full = [0x00, 0x00] + bytes + baseSuffix
        case 4: full = bytes + baseSuffix
        case 16: full = bytes
        default: return nil
        }
        let hex = full.map { String(format: "%02X", $0) }.joined()
        let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                     hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
        return parts.map(String.init).joined(separator: "-")
    }

    /// Canonicalises a UUID string in short (`FE2C`, `0000FE2C`) or full form.
    public static func canonical(fromString string: String) -> String? {
        let hex = string.replacingOccurrences(of: "-", with: "")
        guard [4, 8, 32].contains(hex.count), let bytes = Hex.bytes(hex) else { return nil }
        return canonical(fromBytes: bytes)
    }

    /// The 16-bit short form (`"FE2C"`) when the UUID is built on the Bluetooth Base UUID.
    public static func shortForm(_ canonical: String) -> String? {
        guard canonical.count == 36, canonical.hasPrefix("0000"),
              canonical.hasSuffix("-0000-1000-8000-00805F9B34FB") else { return nil }
        return String(canonical.dropFirst(4).prefix(4))
    }
}

public enum Hex {
    public static func string(_ bytes: some Sequence<UInt8>, separator: String = " ") -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: separator)
    }

    public static func bytes(_ hex: String) -> [UInt8]? {
        let clean = hex.filter { !$0.isWhitespace }
        guard clean.count.isMultiple(of: 2) else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}
