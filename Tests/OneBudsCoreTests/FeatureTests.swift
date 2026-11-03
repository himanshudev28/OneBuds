import Foundation
import Testing
@testable import OneBudsCore
@testable import OneBudsProtocol

private let buds3 = DeviceRegistry.onePlusBuds3

private func session(profile: DeviceProfile = buds3) async throws -> (OPOv1Session, MockTransport) {
    let simulator = MockEarbudsSimulator(profile: profile)
    let transport = MockTransport(framesOnConnect: simulator.framesOnConnect()) { await simulator.handle($0) }
    try await transport.connect()
    let session = OPOv1Session(transport: transport, profile: profile, replyTimeout: .milliseconds(400),
                               now: { Date(timeIntervalSince1970: 1_772_114_101) })
    try await session.startSession()
    return (session, transport)
}

@Suite struct FeatureCodecTests {
    @Test func noiseCycleRoundTrips() {
        let bits = buds3.opo!.noiseCycleBits
        #expect(OPOFeatureCodec.noiseCyclePayload([.off, .transparency], bits: bits) == [0x02, 0x01, 0x05])
        #expect(OPOFeatureCodec.noiseCycle([0x00, 0x02, 0x01, 0x07], bits: bits) == [.off, .noiseCancelling, .transparency])
        // Adaptive has no bit on Buds 3, so a cycle with it cannot be written.
        #expect(OPOFeatureCodec.noiseCyclePayload([.adaptive], bits: bits) == nil)
        #expect(OPOFeatureCodec.noiseCyclePayload([], bits: bits) == nil)
    }

    @Test func customPresetListParsesAndRejectsTruncation() {
        let reply: [UInt8] = [0x00, 0x01, 0x01, 0xFA, 0x06, 0x04, 0x02, 0x48, 0x69, 0x02, 0x3E, 0x00, 0x03, 0xE8, 0x03, 0xFE]
        let presets = OPOFeatureCodec.customPresets(reply)
        #expect(presets == [CustomEQPreset(id: 4, name: "Hi", bands: [EQBand(frequency: 62, gain: 3), EQBand(frequency: 1000, gain: -2)])])
        #expect(OPOFeatureCodec.customPresets(Array(reply.dropLast())) == nil)
        #expect(OPOFeatureCodec.customPresets([0x01, 0x00]) == nil)
    }

    @Test func customPresetPayloadMatchesTheDocumentedLayout() {
        let payload = OPOFeatureCodec.customPresetPayload(.create, id: 9, name: "Hi", bands: [EQBand(frequency: 62, gain: -6)], maximumGain: 6)
        #expect(payload == [0x01, 0xFA, 0x06, 0x00, 0x02, 0x48, 0x69, 0x01, 0x3E, 0x00, 0xFA])
        // Out-of-range gain, an empty name and non-ASCII names are refused before anything is sent.
        #expect(OPOFeatureCodec.customPresetPayload(.save, id: 4, name: "Hi", bands: [EQBand(frequency: 62, gain: 7)], maximumGain: 6) == nil)
        #expect(OPOFeatureCodec.customPresetPayload(.save, id: 4, name: "", bands: [EQBand(frequency: 62, gain: 0)], maximumGain: 6) == nil)
        #expect(OPOFeatureCodec.customPresetPayload(.save, id: 4, name: "Café", bands: [EQBand(frequency: 62, gain: 0)], maximumGain: 6) == nil)
    }

    @Test func bassAndFitAndHearingLayouts() {
        #expect(OPOFeatureCodec.bassPayload(-3) == [0xFB, 0x05, 0xFD])
        #expect(OPOFeatureCodec.bassLevel([0x00, 0xFB, 0x05, 0xFD]) == -3)
        #expect(OPOFeatureCodec.bassLevel([0x00, 0xFB, 0x04, 0x01]) == nil)
        #expect(OPOFeatureCodec.fitResult([0x01, 0x01, 0x02, 0x06]) == FitResult(left: .good, right: .poor))
        #expect(OPOFeatureCodec.tonePayload(HearingTone(side: 1, frequency: 3, level: -30)) == [0x03, 0x01, 0x01, 0x03, 0xE2])
        #expect(OPOFeatureCodec.tonePayload(HearingTone(side: 1, frequency: 7, level: -30)) == nil)
        #expect(OPOFeatureCodec.tonePayload(HearingTone(side: 1, frequency: 3, level: 40)) == nil)
        #expect(HearingTest.snap(-29) == -25)
    }

    @Test func bitmapOnlyHides() {
        #expect(OPOFeatureCodec.bitmap([], offers: .customEqualizer))
        #expect(!OPOFeatureCodec.bitmap([1, 2, 3], offers: .customEqualizer))
        #expect(OPOFeatureCodec.bitmap([34], offers: .customEqualizer))
        #expect(OPOFeatureCodec.bitmap([1], offers: .battery))
        // Verified basics are never hidden by the bitmap.
        #expect(OPOFeatureCodec.bitmap([1], offers: .gestures) && OPOFeatureCodec.bitmap([1], offers: .equalizer))
    }

    @Test func buds3CapturedBitmapOffersEveryNewFeature() {
        // Owner capture, OnePlus Buds 3 fw 127.127.101 (PhaseB-Report §6).
        let bits = OPOReplyParser.capabilityBits([0x00, 0xFF, 0x77, 0x5A, 0xEE, 0xE7, 0x0E, 0x22, 0x00])!
        for capability: Capability in [.customEqualizer, .bassWave, .noiseCycle, .findEarbuds, .fitTest, .hearingTest] {
            #expect(OPOFeatureCodec.bitmap(bits, offers: capability), "\(capability)")
        }
    }
}

@Suite struct FeatureSessionTests {
    @Test func noiseCycleIsWrittenAndReadBack() async throws {
        let (session, transport) = try await session()
        let result = try await session.perform(.setNoiseCycle([.noiseCancelling, .transparency]))
        #expect(result == .noiseCycle([.noiseCancelling, .transparency]))
        let write = await transport.sentFrames.last { $0.command == 0x0404 }
        #expect(write?.payload == [0x02, 0x01, 0x06])
    }

    @Test func customPresetCreateSaveDelete() async throws {
        let (session, _) = try await session()
        let bands = [62, 250, 1000, 4000, 8000, 16000].map { EQBand(frequency: $0, gain: 1) }
        guard case .customEqualizers(let created) = try await session.perform(.createCustomEqualizer(name: "Commute", bands: bands)) else {
            Issue.record("no list"); return
        }
        let commute = try #require(created.first { $0.name == "Commute" })
        var louder = commute
        louder.bands[0].gain = 5
        guard case .customEqualizers(let saved) = try await session.perform(.saveCustomEqualizer(louder)) else { Issue.record("no list"); return }
        #expect(saved.first { $0.id == commute.id }?.bands.first?.gain == 5)
        guard case .customEqualizers(let left) = try await session.perform(.deleteCustomEqualizer(louder)) else { Issue.record("no list"); return }
        #expect(!left.contains { $0.name == "Commute" })
    }

    @Test func customPresetCanBeSelected() async throws {
        let (session, _) = try await session()
        guard case .customEqualizers(let list) = try await session.perform(.readCustomEqualizers), let first = list.first else {
            Issue.record("no presets"); return
        }
        #expect(try await session.perform(.setEqualizer(presetID: first.id)) == .equalizer(presetID: first.id))
        await #expect(throws: ProtocolError.self) { try await session.perform(.setEqualizer(presetID: 9)) }
    }

    @Test func deleteRefusesWhenTheIDNowHoldsAnotherPreset() async throws {
        let (session, transport) = try await session()
        guard case .customEqualizers(let list) = try await session.perform(.readCustomEqualizers), var stale = list.first else {
            Issue.record("no presets"); return
        }
        stale.name = "Renamed elsewhere"
        await #expect(throws: ProtocolError.self) { try await session.perform(.deleteCustomEqualizer(stale)) }
        #expect(await transport.sentFrames.contains { $0.command == 0x0418 } == false)
    }

    @Test func builtInPresetsCanNeverBeOverwritten() async throws {
        let (session, transport) = try await session()
        let fake = CustomEQPreset(id: 1, name: "Bass", bands: [EQBand(frequency: 62, gain: 0)])
        await #expect(throws: ProtocolError.self) { try await session.perform(.saveCustomEqualizer(fake)) }
        await #expect(throws: ProtocolError.self) { try await session.perform(.deleteCustomEqualizer(fake)) }
        #expect(await transport.sentFrames.contains { $0.command == 0x0418 } == false)
    }

    @Test func bassLevelOutsideTheRangeIsRefusedBeforeSending() async throws {
        let (session, transport) = try await session()
        #expect(try await session.perform(.setBassLevel(-4)) == .bassLevel(-4))
        await #expect(throws: ProtocolError.self) { try await session.perform(.setBassLevel(9)) }
        #expect(await transport.sentFrames.filter { $0.command == 0x041B }.count == 1)
    }

    @Test func fitTestWaitsForThePushAndStopsAfterwards() async throws {
        let (session, transport) = try await session()
        #expect(try await session.perform(.runFitTest) == .fitResult(FitResult(left: .good, right: .average)))
        let fit = await transport.sentFrames.filter { $0.command == 0x0405 }.map(\.payload)
        #expect(fit == [[0x01], [0x00]])
    }

    @Test func hearingProfileIsStoredReadBackAndSwitchedOn() async throws {
        let (session, transport) = try await session()
        let levels = Array(repeating: -28, count: 12)
        guard case .hearingProfile(let stored?) = try await session.perform(.applyHearingProfile(levels)) else {
            Issue.record("no profile"); return
        }
        #expect(stored.values == Array(repeating: -25, count: 12)) // snapped to a storable level
        #expect(await transport.sentFrames.contains { $0.command == 0x0403 && $0.payload == [0x0B, 0x01] })
    }

    @Test func neverWritableSwitchesStayRefused() async throws {
        let (session, transport) = try await session()
        for id: UInt8 in [0x17, 0x18, 0x05] {
            await #expect(throws: ProtocolError.self) { try await session.perform(.setFeature(id: id, enabled: true)) }
        }
        #expect(await transport.sentFrames.contains { $0.command == 0x0403 } == false)
    }

    @Test func callGestureMustUseTheCallList() async throws {
        let (session, transport) = try await session()
        let answer = GestureBinding(side: GestureSide.both.rawValue, button: 6, action: GestureAction.double.rawValue, function: 0x1D)
        _ = try await session.perform(.setGestures([answer]))
        // Play/pause is a tap function, not a call function.
        var wrong = answer
        wrong.function = 0x01
        await #expect(throws: ProtocolError.self) { try await session.perform(.setGestures([wrong])) }
        #expect(await transport.sentFrames.filter { $0.command == 0x0401 }.count == 1)
    }

    @Test func modelsWithoutTheFeaturesRefuseThem() async throws {
        // realme Buds Air 5 lists none of these features.
        let (session, transport) = try await session(profile: DeviceRegistry.realmeBudsAir5)
        for command: EarbudCommand in [.findEarbuds(ringing: true), .runFitTest, .readCustomEqualizers, .setBassLevel(1), .readNoiseCycle, .startHearingTest] {
            await #expect(throws: ProtocolError.self) { try await session.perform(command) }
        }
        let sent = await transport.sentFrames.map(\.command)
        #expect(!sent.contains(0x0400) && !sent.contains(0x0405) && !sent.contains(0x0122) && !sent.contains(0x040D))
    }
}
