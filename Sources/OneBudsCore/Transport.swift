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
