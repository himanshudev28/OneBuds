import Foundation
import Testing
@testable import OneBudsCore

@Suite struct ConnectionAnnouncementGateTests {
    typealias Step = (state: DeviceManager.ConnectionState, device: String?, at: TimeInterval)

    /// Feeds the steps through a fresh gate; returns which ones were announced.
    func run(_ steps: [Step], tolerance: TimeInterval = 0) -> [Bool] {
        var gate = ConnectionAnnouncementGate(blipTolerance: tolerance)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return steps.map { gate.observe($0.state, device: $0.device, at: start + $0.at) }
    }

    @Test func announcesOnlyTheTransitionIntoConnected() {
        let states: [DeviceManager.ConnectionState] = [.idle, .searching, .connecting(.rfcomm), .handshaking, .connected, .connected, .connected]
        // Announced at the handshake (channel open, model known), not again when it completes.
        #expect(run(states.map { ($0, "buds", 0) }) == [false, false, false, true, false, false, false])
    }

    @Test func everyReconnectIsAnnouncedByDefault() {
        #expect(run([(.connected, "buds", 0), (.noDevice, nil, 1), (.searching, nil, 2), (.handshaking, "buds", 3), (.connected, "buds", 3.5)], tolerance: 0)
                == [true, false, false, true, false])
        #expect(ConnectionAnnouncementGate().blipTolerance == 0)
    }

    @Test func failedHandshakeEndsTheLink() {
        #expect(ConnectionAnnouncementGate.isLinked(.handshaking) && ConnectionAnnouncementGate.isLinked(.connected))
        #expect(!ConnectionAnnouncementGate.isLinked(.connecting(.rfcomm)) && !ConnectionAnnouncementGate.isLinked(.failed("x")))
        #expect(run([(.handshaking, "buds", 0), (.failed("x"), nil, 1), (.handshaking, "buds", 5)]) == [true, false, true])
    }

    @Test func optionalToleranceTreatsABriefDropAsTheSameConnection() {
        #expect(run([(.connected, "buds", 0), (.noDevice, nil, 1), (.searching, nil, 2), (.connected, "buds", 4)], tolerance: 10) == [true, false, false, false])
    }

    @Test func reconnectAfterTheToleranceIsAnnounced() {
        #expect(run([(.connected, "buds", 0), (.noDevice, nil, 60), (.connected, "buds", 75)], tolerance: 10) == [true, false, true])
    }

    @Test func differentEarbudsAreAlwaysAnnounced() {
        #expect(run([(.connected, "demo:OnePlus Buds 3", 0), (.noDevice, nil, 1), (.connected, "bluetooth:OnePlus Buds 3", 2)], tolerance: 10) == [true, false, true])
    }

    @Test func userDisconnectThenConnectIsAnnounced() {
        #expect(run([(.connected, "buds", 0), (.idle, nil, 1), (.connected, "buds", 2)], tolerance: 10) == [true, false, true])
    }

    @Test func failuresNeverAnnounce() {
        let states: [DeviceManager.ConnectionState] = [.bluetoothOff, .unauthorized, .unrecognised(name: "x"), .failed("x"), .noDevice]
        #expect(run(states.map { ($0, "buds", 0) }) == [false, false, false, false, false])
    }
}

/// The gate driven by the real device manager's published states.
@MainActor
@Suite struct ConnectionAnnouncementManagerTests {
    let buds3 = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["test"], transports: [.rfcomm])

    /// Records every state the manager publishes, as an observer in the app would see them.
    @MainActor
    final class Recorder {
        var gate = ConnectionAnnouncementGate(blipTolerance: 0)
        var announcements = 0
        let manager: DeviceManager

        init(_ manager: DeviceManager) {
            self.manager = manager
            track()
        }

        func track() {
            let state = withObservationTracking { manager.connection } onChange: { [weak self] in
                Task { @MainActor in self?.track() }
            }
            if gate.observe(state, device: manager.earbuds?.name) { announcements += 1 }
        }
    }

    @Test func refreshAndWakeDoNotAnnounceAgain() async {
        let manager = DeviceManager(connector: ScriptedConnector(found: [buds3]), reconnectDelays: [])
        let recorder = Recorder(manager)
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { recorder.announcements == 1 })
        await manager.refresh()
        await manager.handleWake()
        await manager.connect()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recorder.announcements == 1)
        #expect(manager.battery != nil)
    }

    @Test func remoteDropAndReconnectAnnouncesAgain() async {
        let connector = ScriptedConnector(found: [buds3])
        let manager = DeviceManager(connector: connector, reconnectDelays: [.milliseconds(50)])
        let recorder = Recorder(manager)
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { recorder.announcements == 1 })
        await connector.transports.last?.simulateDisconnect(reason: "case closed")
        // The manager's own reconnect timer brings the earbuds back.
        #expect(await waitUntil(timeout: .seconds(3)) { recorder.announcements == 2 && manager.connection.isConnected })
        await manager.disconnect()
    }

    @Test func userDisconnectAndConnectAnnouncesAgain() async {
        let manager = DeviceManager(connector: ScriptedConnector(found: [buds3]), reconnectDelays: [])
        let recorder = Recorder(manager)
        await manager.connect()
        await manager.disconnect()
        await manager.connect()
        #expect(await waitUntil(timeout: .seconds(2)) { recorder.announcements == 2 })
    }
}
