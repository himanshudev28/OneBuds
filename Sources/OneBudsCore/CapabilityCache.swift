import Foundation

/// Remembers the capability report of each model's last confirmed session, so the next connection
/// can show what the earbuds supported last time while the new session is still starting.
///
/// A cached entry is a hint, never proof. It is returned as an `Entry` so it cannot be mistaken
/// for a live report, and it must be replaced by the live evaluation once the session confirms the
/// product id. An entry is not returned when the model's profile has changed since it was saved
/// (another app version) or when the earbuds now report different firmware or a different
/// capability list. Only confirmed reports with known firmware are stored. Nothing personal is
/// kept (no Bluetooth name or address).
@MainActor
public final class CapabilityCache {
    public struct Entry: Codable, Equatable, Sendable {
        public var report: CapabilityReport
        public var savedAt: Date
    }

    /// Bump when `CapabilityReport` changes shape; older entries are ignored.
    static let schemaVersion = 1
    static let maximumEntries = 20

    private let defaults: UserDefaults
    private let storageKey: String
    private var entries: [String: Entry]

    public init(defaults: UserDefaults = .standard, storageKey: String = "capabilityCache") {
        self.defaults = defaults
        self.storageKey = "\(storageKey).v\(Self.schemaVersion)"
        if let data = defaults.data(forKey: self.storageKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    /// The last confirmed report for this model, if it still applies.
    /// - Parameter live: what the current session reported, once known. Its firmware and
    ///   capability list must match the cached ones.
    public func entry(for profile: DeviceProfile, live: DeviceInfo? = nil) -> Entry? {
        guard let entry = entries[profile.id],
              entry.report.profileFingerprint == CapabilityEngine.fingerprint(of: profile) else { return nil }
        if let live {
            guard live.firmwareSummary == entry.report.firmware, live.capabilityBits == entry.report.capabilityBits else { return nil }
        }
        return entry
    }

    /// Stores a report made from a live session. Unconfirmed reports and reports without firmware
    /// are ignored; an unchanged report is not written again.
    public func store(_ report: CapabilityReport, now: Date = Date()) {
        guard report.isConfirmed, report.firmware != nil, let profileID = report.profileID else { return }
        if let existing = entries[profileID]?.report, existing.hasSameContent(as: report) { return }
        entries[profileID] = Entry(report: report, savedAt: now)
        if entries.count > Self.maximumEntries {
            let oldest = entries.sorted { $0.value.savedAt < $1.value.savedAt }.prefix(entries.count - Self.maximumEntries)
            for (key, _) in oldest { entries[key] = nil }
        }
        persist()
    }

    public func remove(profile profileID: String) {
        guard entries.removeValue(forKey: profileID) != nil else { return }
        persist()
    }

    public func removeAll() {
        entries = [:]
        defaults.removeObject(forKey: storageKey)
    }

    public var count: Int { entries.count }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
