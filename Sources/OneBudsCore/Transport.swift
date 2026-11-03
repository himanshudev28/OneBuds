import Foundation

public enum TransportKind: String, Sendable, Codable, CaseIterable {
    case ble, rfcomm, mock

    public var displayName: String {
        switch self {
        case .ble: "Bluetooth LE (GATT)"
        case .rfcomm: "Classic Bluetooth (RFCOMM)"
        case .mock: "Demo (simulated)"
        }
    }
}

/// Which control channels OneBuds may use. Automatic tries GATT first and falls back to RFCOMM,
/// always limited to what the model's profile lists and what discovery found on the earbuds.
public enum TransportPreference: String, Sendable, Codable, CaseIterable {
    case automatic, bleOnly, rfcommOnly

    public var displayName: String {
        switch self {
        case .automatic: "Automatic (GATT first, then RFCOMM)"
        case .bleOnly: "Bluetooth LE (GATT) only"
        case .rfcommOnly: "Classic Bluetooth (RFCOMM) only"
        }
    }

    /// Keeps `order` (already the profile's preference) but drops kinds this preference excludes.
    public func filter(_ order: [TransportKind]) -> [TransportKind] {
        switch self {
        case .automatic: order
        case .bleOnly: order.filter { $0 == .ble || $0 == .mock }
        case .rfcommOnly: order.filter { $0 == .rfcomm || $0 == .mock }
        }
    }
}

/// One try at opening a control channel, kept so the UI can say what was tried and why it failed.
public struct TransportAttempt: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case connected
        case failed(String)
    }

    public var kind: TransportKind
    public var outcome: Outcome

    public init(kind: TransportKind, outcome: Outcome) {
        self.kind = kind
        self.outcome = outcome
    }

    public var summary: String {
        switch outcome {
        case .connected: "\(kind.shortName): connected"
        case .failed(let reason): "\(kind.shortName): \(reason)"
        }
    }
}

extension TransportKind {
    /// Short label for compact UI, e.g. "GATT".
    public var shortName: String {
        switch self {
        case .ble: "GATT"
        case .rfcomm: "RFCOMM"
        case .mock: "Demo"
        }
    }
}

public enum TransportState: Sendable, Equatable {
    case idle
    case connecting
    case connected
    case disconnected(reason: String?)
    case failed(String)
}

public enum TransportError: Error, Equatable, LocalizedError {
    case bluetoothUnavailable(String)
    case deviceNotFound
    case serviceNotFound(String)
    case openFailed(String)
    case timeout(String)
    case notConnected
    case writeFailed(String)
    case alreadyUsed

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let detail): "Bluetooth is unavailable: \(detail)"
        case .deviceNotFound: "The earbuds were not found. Make sure they are connected to this Mac."
        case .serviceNotFound(let uuid): "The earbuds do not offer the control service \(uuid)."
        case .openFailed(let detail): "Could not open the control channel: \(detail)"
        case .timeout(let what): "Timed out: \(what)"
        case .notConnected: "The control channel is not connected."
        case .writeFailed(let detail): "Sending to the earbuds failed: \(detail)"
        case .alreadyUsed: "This connection was already used; create a new one."
        }
    }
}

/// A byte pipe to one pair of earbuds. The protocol layer depends only on this, never on
/// Core Bluetooth or IOBluetooth.
///
/// Lifecycle: a transport is **single-use**. Call `connect()` once; after it disconnects or fails,
/// both streams finish and a new transport must be created. `incoming` and `state` each support
/// one consumer.
public protocol EarbudTransport: Sendable {
    var kind: TransportKind { get }
    func connect() async throws
    func disconnect() async
    func send(_ frame: Data) async throws
    var incoming: AsyncStream<Data> { get }
    var state: AsyncStream<TransportState> { get }
}
