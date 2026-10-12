import Foundation

public enum BluetoothAvailability: Sendable, Equatable {
    case ready, poweredOff, unauthorized, unsupported, unknown
}

/// A pair of earbuds found by discovery, before any control session.
public struct DiscoveredEarbuds: Sendable, Identifiable, Equatable {
    public var name: String
    /// From BLE manufacturer data when available (Hypothesis layout, PhaseB-Report §4.4).
    public var productID: String?
    /// How each route found it, e.g. "BLE connected peripheral", "paired classic device", "BLE scan".
    public var discoveryPaths: [String]
    public var transports: [TransportKind]
    public var isDemo: Bool

    public var id: String { name }

    public init(name: String, productID: String? = nil, discoveryPaths: [String], transports: [TransportKind], isDemo: Bool = false) {
        self.name = name
        self.productID = productID
        self.discoveryPaths = discoveryPaths
        self.transports = transports
        self.isDemo = isDemo
    }

    public var profile: DeviceProfile? { DeviceRegistry.match(name: name, productID: productID) }
}

/// Finds earbuds and creates transports. The Bluetooth implementation lives in OneBudsBluetooth;
/// `DemoConnector` provides the simulated device.
@MainActor
public protocol DeviceConnector: AnyObject {
    var isDemo: Bool { get }
    func availability() async -> BluetoothAvailability
    /// - Parameter thorough: also run the BLE scan fallback. False for automatic reconnects, which
    ///   rely on connect notifications instead of repeatedly scanning (energy).
    func discover(thorough: Bool) async -> [DiscoveredEarbuds]
    func makeTransport(for earbuds: DiscoveredEarbuds, kind: TransportKind) -> (any EarbudTransport)?
    /// Details for the diagnostics screen, e.g. "RFCOMM channel 15 ("enco link")".
    func describe(_ transport: any EarbudTransport) -> String?
    /// Yields when a relevant device connects/disconnects or Bluetooth changes state.
    func deviceChanges() -> AsyncStream<Void>
}

/// Simulated earbuds for the labelled Demo mode. Uses only `MockTransport`.
@MainActor
public final class DemoConnector: DeviceConnector {
    public let isDemo = true
    public let profile: DeviceProfile
    public let simulator: MockEarbudsSimulator
    private let changes: AsyncStream<Void>
    private let changesContinuation: AsyncStream<Void>.Continuation

    public init(profile: DeviceProfile = DeviceRegistry.onePlusBuds3) {
        self.profile = profile
        simulator = MockEarbudsSimulator(profile: profile)
        (changes, changesContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    public func availability() async -> BluetoothAvailability { .ready }

    public func discover(thorough: Bool) async -> [DiscoveredEarbuds] {
        [DiscoveredEarbuds(name: profile.bluetoothNames.first ?? profile.displayName, productID: profile.opo?.productIDs.first,
                           discoveryPaths: ["demo (simulated)"], transports: [.mock], isDemo: true)]
    }

    public func makeTransport(for earbuds: DiscoveredEarbuds, kind: TransportKind) -> (any EarbudTransport)? {
        guard kind == .mock else { return nil }
        let simulator = self.simulator
        return MockTransport(framesOnConnect: simulator.framesOnConnect()) { data in await simulator.handle(data) }
    }

    public func describe(_ transport: any EarbudTransport) -> String? { "Simulated earbuds (no Bluetooth traffic)" }

    public func deviceChanges() -> AsyncStream<Void> { changes }
}
