import Foundation
import Testing
@testable import OneBudsCore
@testable import OneBudsProtocol

private let buds3 = DeviceRegistry.onePlusBuds3

/// A session wired to the documented-behaviour simulator.
private func simulatedSession(timeout: Duration = .milliseconds(400),
                              configure: (MockEarbudsSimulator) async -> Void = { _ in }) async throws -> (OPOv1Session, MockTransport, MockEarbudsSimulator) {
    let simulator = MockEarbudsSimulator(profile: buds3)
    await configure(simulator)
    let transport = MockTransport(framesOnConnect: simulator.framesOnConnect()) { await simulator.handle($0) }
    try await transport.connect()
    let session = OPOv1Session(transport: transport, profile: buds3, replyTimeout: timeout,
                               now: { Date(timeIntervalSince1970: 1_772_114_101) })
    try await session.startSession()
    return (session, transport, simulator)
}

@Suite struct SessionStartTests {
    @Test func startsAndIdentifiesTheModel() async throws {
        let (session, _, _) = try await simulatedSession()
        let info = await session.currentDeviceInfo()
        #expect(info.productID == "063C14")
        #expect(info.firmwareSummary == "151.151.105")
        #expect(!info.capabilityBits.isEmpty)
    }

    @Test func answersTheTimeRequestWithEchoedSequence() async throws {
        let (_, transport, _) = try await simulatedSession()
        let reply = await transport.sentFrames.first { $0.command == 0x8500 }
        #expect(reply?.sequence == 0x01)
        #expect(reply?.payload == [0x00, 0xB5, 0x50, 0xA0, 0x69])
    }

    @Test func subscribesOnlyToOfferedEvents() async throws {
        let (_, transport, _) = try await simulatedSession()
        let subscribe = await transport.sentFrames.first { $0.command == 0x0205 }
        #expect(subscribe?.payload == [0x03, 0x01, 0x02, 0x03])
    }

    @Test func refusesAModelWithAnotherProductID() async throws {
        let nord = DeviceRegistry.nordBuds3Pro
        let simulator = MockEarbudsSimulator(profile: nord) // answers 064414
        let transport = MockTransport { await simulator.handle($0) }
        try await transport.connect()
        let session = OPOv1Session(transport: transport, profile: buds3, replyTimeout: .milliseconds(400), now: { Date() })
        await #expect(throws: ProtocolError.profileMismatch(expected: ["063C14"], found: "064414")) {
            try await session.startSession()
        }
    }

    @Test func silentDeviceFailsOnTheMandatoryProductIDQuery() async throws {
        let transport = MockTransport() // never answers; the handshake is optional, the product id is not
        try await transport.connect()
        let session = OPOv1Session(transport: transport, profile: buds3, replyTimeout: .milliseconds(150), now: { Date() })
        await #expect(throws: ProtocolError.timeout(command: 0x0103)) { try await session.startSession() }
    }

    @Test func commandsBeforeStartAreRejected() async throws {
        let session = OPOv1Session(transport: MockTransport(), profile: buds3)
        await #expect(throws: ProtocolError.sessionNotStarted) { _ = try await session.perform(.readBattery) }
    }

    @Test func capabilitiesComeFromTheProfile() {
        let session = OPOv1Session(transport: MockTransport(), profile: DeviceRegistry.nordBuds3Pro)
        #expect(session.capabilities().contains(.noiseControl))
        #expect(!session.capabilities().contains(.equalizer))
    }
}

@Suite struct SessionCommandTests {
    @Test func readsBattery() async throws {
        let (session, _, _) = try await simulatedSession()
        let response = try await session.perform(.readBattery)
        #expect(response == .battery(BatteryStatus(left: .init(percent: 82, isCharging: false),
                                                  right: .init(percent: 79, isCharging: false),
                                                  chargingCase: .init(percent: 55, isCharging: true))))
    }

    @Test func noiseControlIsConfirmedByReadBack() async throws {
        let (session, transport, _) = try await simulatedSession()
        let response = try await session.perform(.setNoiseControl(.transparency))
        #expect(response == .noiseControl(.transparency))
        let commands = await transport.sentFrames.map(\.command)
        let setIndex = try #require(commands.lastIndex(of: 0x0404))
        #expect(commands[(setIndex + 1)...].contains(0x010C)) // read back after the set
        #expect(await transport.sentFrames.last { $0.command == 0x0404 }?.payload == [0x01, 0x01, 0x04])
    }

    @Test func genericNoiseCancellingAcceptsAnyLevel() async throws {
        let (session, _, _) = try await simulatedSession()
        #expect(try await session.perform(.setNoiseControl(.noiseCancelling(nil))) == .noiseControl(.noiseCancelling(.smart)))
    }

    @Test func refusalIsReportedNotAssumedApplied() async throws {
        let (session, _, _) = try await simulatedSession { await $0.setRefusesNoiseControl(true) }
        await #expect(throws: ProtocolError.rejected(command: 0x0404, status: 0x0E)) {
            _ = try await session.perform(.setNoiseControl(.off))
        }
    }

    @Test func unsupportedModeIsNeverSent() async throws {
        let (session, transport, _) = try await simulatedSession()
        await #expect(throws: ProtocolError.unsupported("noise mode Adaptive")) {
            _ = try await session.perform(.setNoiseControl(.adaptive))
        }
        #expect(await !transport.sentFrames.contains { $0.command == 0x0404 })
    }

    @Test func equalizerAndFeatures() async throws {
        let (session, _, _) = try await simulatedSession()
        #expect(try await session.perform(.setEqualizer(presetID: 2)) == .equalizer(presetID: 2))
        #expect(try await session.perform(.setFeature(id: 0x06, enabled: true)) == .features([0x06: true]))
    }

    @Test func dangerousFeatureSwitchesAreBlocked() async throws {
        let (session, transport, _) = try await simulatedSession()
        for id: UInt8 in [0x17, 0x18] {
            await #expect(throws: ProtocolError.self) { _ = try await session.perform(.setFeature(id: id, enabled: true)) }
        }
        #expect(await !transport.sentFrames.contains { $0.command == 0x0403 })
    }

    @Test func gesturesAreValidatedAndConfirmed() async throws {
        let (session, _, _) = try await simulatedSession()
        let binding = GestureBinding(side: 1, button: 1, action: GestureAction.double.rawValue, function: 0x01)
        guard case .gestures(let after) = try await session.perform(.setGestures([binding])) else { Issue.record("wrong response"); return }
        #expect(after.contains(binding))
        let invalid = GestureBinding(side: 1, button: 1, action: GestureAction.single.rawValue, function: 0x11)
        await #expect(throws: ProtocolError.self) { _ = try await session.perform(.setGestures([invalid])) }
    }

    @Test func oneOutstandingRequestPerCommandType() async throws {
        let (session, transport, _) = try await simulatedSession()
        async let first = session.perform(.readBattery)
        async let second = session.perform(.readBattery)
        _ = try await (first, second)
        let batteryFrames = await transport.sentFrames.filter { $0.command == 0x0106 }
        #expect(batteryFrames.count == 2)
        #expect(batteryFrames[0].sequence != batteryFrames[1].sequence)
    }
}

@Suite struct SessionEventTests {
    @Test func unsolicitedPushesBecomeEvents() async throws {
        let (session, transport, simulator) = try await simulatedSession()
        let push = await simulator.batteryPush(left: 0x80 | 40, right: 41)
        await transport.inject(push)
        await transport.inject(Data(OPOFrame(command: 0x0204, sequence: 0xFF, payload: [0x03, 0x01, 0x01, 0x00, 0x01]).encoded()))
        var received: [EarbudEvent] = []
        for await event in session.events {
            if case .packet = event { continue }
            received.append(event)
            if received.count == 2 { break }
        }
        #expect(received[0] == .battery(BatteryStatus(left: .init(percent: 40, isCharging: true), right: .init(percent: 41, isCharging: false))))
        #expect(received[1] == .noiseControl(.transparency))
    }

    @Test func malformedBytesDoNotBreakTheSession() async throws {
        let (session, transport, _) = try await simulatedSession()
        await transport.inject(Data([0x01, 0xAA, 0x03, 0xFF, 0xAA]))
        _ = try await session.perform(.readBattery)
    }

    @Test func disconnectMidCommandFailsWithDisconnected() async throws {
        let simulator = MockEarbudsSimulator(profile: buds3)
        let transport = MockTransport { data in
            // Disconnect instead of answering the battery query.
            if data.count > 5, data[4] == 0x06, data[5] == 0x01 { return .disconnect("out of range") }
            return await simulator.handle(data)
        }
        try await transport.connect()
        let session = OPOv1Session(transport: transport, profile: buds3, replyTimeout: .seconds(2), now: { Date() })
        try await session.startSession()
        await #expect(throws: ProtocolError.disconnected("out of range")) { _ = try await session.perform(.readBattery) }
        var ended: String?? = nil
        for await event in session.events { if case .sessionEnded(let reason) = event { ended = reason; break } }
        #expect(ended == .some("out of range"))
    }
}
