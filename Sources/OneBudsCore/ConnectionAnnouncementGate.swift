import Foundation

/// Decides when earbuds count as newly connected, for one-shot UI such as the connection card.
///
/// It looks only at the connection state `DeviceManager` publishes. The earbuds count as linked
/// from `.handshaking` (the control channel is open and the model identified) through `.connected`,
/// so the announcement comes as early as possible; becoming linked counts once, while refreshes,
/// battery pushes and wake re-reads never count. Every reconnect is announced by default; set
/// `blipTolerance` to treat a quick drop of the same earbuds as the same connection.
public struct ConnectionAnnouncementGate: Sendable {
    public var blipTolerance: TimeInterval
    private var isLinked = false
    private var lastDevice: String?
    /// When the link last dropped on its own; nil after a user disconnect.
    private var droppedAt: Date?

    public init(blipTolerance: TimeInterval = 0) {
        self.blipTolerance = blipTolerance
    }

    /// The earbuds are present and talking to OneBuds (or about to, once the handshake finishes).
    public static func isLinked(_ state: DeviceManager.ConnectionState) -> Bool {
        state == .handshaking || state == .connected
    }

    /// - Parameter device: identifies the earbuds, e.g. their name plus whether they are simulated.
    /// - Returns: true when this observation is a new connection worth announcing.
    public mutating func observe(_ state: DeviceManager.ConnectionState, device: String?, at now: Date = Date()) -> Bool {
        let linked = Self.isLinked(state)
        guard linked != isLinked else { return false }
        isLinked = linked
        guard linked else {
            droppedAt = state == .idle ? nil : now
            return false
        }
        let isBlip = blipTolerance > 0 && device == lastDevice
            && droppedAt.map { now.timeIntervalSince($0) < blipTolerance } == true
        lastDevice = device
        droppedAt = nil
        return !isBlip
    }
}
