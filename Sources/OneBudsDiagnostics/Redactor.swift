import CryptoKit
import Foundation

/// Redacts device identifiers in reports. Addresses keep their OUI (manufacturer prefix, useful
/// for identifying the vendor) and get a short pseudonym that is stable *within one run* only,
/// because a random salt is generated per `Redactor`.
public struct Redactor: Sendable {
    public let enabled: Bool
    private let salt: [UInt8]

    public init(enabled: Bool, salt: [UInt8]? = nil) {
        self.enabled = enabled
        self.salt = salt ?? (0..<16).map { _ in UInt8.random(in: .min ... .max) }
    }

    /// `"A4:C1:38:12:34:56"` → `"A4:C1:38:XX:XX:XX #3f9a"`.
    public func address(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return raw }
        guard enabled else { return raw }
        let groups = raw.uppercased().split(whereSeparator: { $0 == ":" || $0 == "-" })
        let oui = groups.count == 6 ? groups.prefix(3).joined(separator: ":") + ":XX:XX:XX" : "XX:XX:XX:XX:XX:XX"
        // Hash the separator-free form so "a4-c1-…" and "A4:C1:…" get the same pseudonym.
        return "\(oui) #\(pseudonym(groups.joined()))"
    }

    /// Core Bluetooth peripheral identifiers are per-Mac UUIDs; replace them with a pseudonym.
    public func identifier(_ raw: String) -> String {
        enabled ? "peripheral #\(pseudonym(raw.uppercased()))" : raw
    }

    /// Hex for advertisement payloads with known device addresses masked. Observed 2026-10-12:
    /// OnePlus Buds 3 manufacturer data embeds the classic address byte-reversed. Both byte
    /// orders are masked, as is the device-specific lower half (NIC) on its own.
    public func payloadHex(_ bytes: [UInt8], knownAddresses: [String]) -> String {
        guard enabled else { return Hex.string(bytes) }
        var masked = Array(repeating: false, count: bytes.count)
        for address in knownAddresses {
            guard let raw = Hex.bytes(address.filter(\.isHexDigit)), raw.count == 6 else { continue }
            let nic = Array(raw.suffix(3))
            for pattern in [raw, Array(raw.reversed()), nic, Array(nic.reversed())] where bytes.count >= pattern.count {
                for start in 0...(bytes.count - pattern.count) where Array(bytes[start..<start + pattern.count]) == pattern {
                    for index in start..<start + pattern.count { masked[index] = true }
                }
            }
        }
        return zip(bytes, masked).map { $1 ? "XX" : String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Serial numbers are removed entirely.
    public func serial(_ raw: String) -> String {
        enabled ? "<redacted serial, \(raw.count) chars>" : raw
    }

    func pseudonym(_ value: String) -> String {
        let digest = SHA256.hash(data: salt + Array(value.utf8))
        return Hex.string(digest.prefix(2), separator: "").lowercased()
    }
}
