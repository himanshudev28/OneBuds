import Foundation
import Testing
@testable import OneBudsCore
import OneBudsProtocol

@Suite struct RealmeProfileTests {
    @Test func realmeModelsMatchByNameAndProductID() {
        #expect(DeviceRegistry.match(name: "realme Buds Air 5")?.id == "realme-buds-air-5")
        #expect(DeviceRegistry.match(name: "realme Buds T300")?.id == "realme-buds-t300")
        #expect(DeviceRegistry.match(name: "Renamed", productID: "062012")?.id == "realme-buds-air-5")
        #expect(DeviceRegistry.match(name: "realme Buds Air 5 Pro")?.id == "realme-buds-air-5-pro") // Unknown, not the Air 5
    }

    @Test func wireless2IsNeverControlled() throws {
        let profile = try #require(DeviceRegistry.match(name: "realme Buds Wireless 2"))
        #expect(profile.status == .unsupported)
        #expect(!profile.allowsControlSession)
    }

    @Test func realmeTriesVendorServiceThenStandardSerialPort() {
        #expect(DeviceRegistry.realmeBudsAir5.rfcommServiceUUIDs == [DeviceRegistry.opoService, DeviceRegistry.standardSPP])
        #expect(DeviceRegistry.onePlusBuds3.rfcommServiceUUIDs == [DeviceRegistry.opoService])
    }

    @Test func realmePowerSavingIsNeverWritable() {
        #expect(!(DeviceRegistry.realmeBudsAir5.opo?.writableFeatureIDs.contains(0x05) ?? true))
    }

    @Test func realmeVoiceAssistantName() {
        #expect(DeviceRegistry.realmeBudsAir5.opo?.functionName(0x04) == "Voice assistant")
        #expect(DeviceRegistry.onePlusBuds3.opo?.functionName(0x03) == "Voice assistant")
    }
}

@Suite struct RealmeSessionTests {
    let air5 = DeviceRegistry.realmeBudsAir5

    func session(handler: @escaping MockTransport.Handler) async throws -> (OPOv1Session, MockTransport) {
        let transport = MockTransport(handler: handler)
        try await transport.connect()
        let session = OPOv1Session(transport: transport, profile: air5, replyTimeout: .milliseconds(150), now: { Date() })
        try await session.startSession()
        return (session, transport)
    }

    @Test func noiseLevelsUseTheRealmeTable() async throws {
        let simulator = MockEarbudsSimulator(profile: air5)
        let (session, transport) = try await session { await simulator.handle($0) }
        #expect(try await session.perform(.setNoiseControl(.noiseCancelling(.light))) == .noiseControl(.noiseCancelling(.light)))
        #expect(await transport.sentFrames.last { $0.command == 0x0404 }?.payload == [0x01, 0x01, 0x04])
        #expect(try await session.perform(.setNoiseControl(.transparency)) == .noiseControl(.transparency))
        // Plain ANC (0x08) reads back as Deep, which shares the value.
        #expect(try await session.perform(.setNoiseControl(.noiseCancelling(nil))) == .noiseControl(.noiseCancelling(.deep)))
    }

    @Test func oneByteNoiseValuesAndPushesAreAccepted() async throws {
        let simulator = MockEarbudsSimulator(profile: air5)
        let (session, transport) = try await session { data in
            if data.count > 5, data[4] == 0x0C, data[5] == 0x01 { // 0x010C read → 1-byte value, as documented for realme
                return .reply([Data(OPOFrame(command: 0x810C, sequence: data[6], payload: [0x00, 0x01, 0x01, 0x20]).encoded())])
            }
            return await simulator.handle(data)
        }
        #expect(try await session.perform(.readNoiseControl) == .noiseControl(.noiseCancelling(.smart)))
        // S12's realme T500 Pro push: AA 0B 00 00 04 02 9B 04 00 03 01 01 01 = Off.
        await transport.inject(Data([0xAA, 0x0B, 0x00, 0x00, 0x04, 0x02, 0x9B, 0x04, 0x00, 0x03, 0x01, 0x01, 0x01]))
        for await event in session.events {
            if case .noiseControl(let mode) = event { #expect(mode == .off); break }
        }
    }

    @Test func sessionStartsWithoutAHandshakeReply() async throws {
        let simulator = MockEarbudsSimulator(profile: air5)
        let (session, _) = try await session { data in
            if data.count > 5, data[4] == 0x00, data[5] == 0x01 { return .none } // ignore 0x0100
            return await simulator.handle(data)
        }
        #expect(await session.currentDeviceInfo().productID == "062012")
    }

    @Test func realmeControlByteFourIsAccepted() async throws {
        let simulator = MockEarbudsSimulator(profile: air5)
        let (session, _) = try await session { data in
            // Reply to battery with control byte 0x04 (S15 notes realme may use it).
            if data.count > 5, data[4] == 0x06, data[5] == 0x01 {
                return .reply([Data(OPOFrame(command: 0x8106, sequence: data[6], payload: [0x00, 0x02, 0x01, 0x40, 0x02, 0x41], control: 0x04).encoded())])
            }
            return await simulator.handle(data)
        }
        guard case .battery(let battery) = try await session.perform(.readBattery) else { Issue.record("no battery"); return }
        #expect(battery.left?.percent == 64 && battery.right?.percent == 65)
    }
}
