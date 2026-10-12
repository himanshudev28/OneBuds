import Foundation
import Testing
@testable import OneBudsCore

/// Every model OneBuds can control gets its own settings from its profile. These tests drive each
/// controllable model (via the simulator) through every control it offers, and check that options
/// differ per model and that left and right earbuds are handled independently.
@MainActor
@Suite struct PerModelTests {
    nonisolated static let controllableIDs = DeviceRegistry.all.filter(\.allowsControlSession).map(\.id)

    private func connected(_ id: String) async throws -> (DeviceManager, DeviceProfile) {
        let profile = try #require(DeviceRegistry.all.first { $0.id == id })
        let manager = DeviceManager(connector: DemoConnector(profile: profile), reconnectDelays: [])
        await manager.connect()
        #expect(manager.connection == .connected, "\(id) did not connect")
        #expect(manager.profile?.id == id)
        return (manager, profile)
    }

    @Test(arguments: controllableIDs)
    func everyNoiseModeIsConfirmed(_ id: String) async throws {
        let (manager, profile) = try await connected(id)
        guard manager.presentation(.noiseControl) != .hidden else { return }
        for option in profile.opo?.noiseModes ?? [] {
            await manager.setNoiseControl(option.mode)
            guard case .confirmed = manager.status(of: .noiseControl) else {
                Issue.record("\(id): \(option.mode.displayName) not confirmed: \(manager.status(of: .noiseControl))")
                continue
            }
            #expect(manager.noiseControl?.category == option.mode.category)
        }
    }

    @Test(arguments: controllableIDs)
    func everyEqualizerPresetIsConfirmed(_ id: String) async throws {
        let (manager, profile) = try await connected(id)
        guard manager.presentation(.equalizer) != .hidden else {
            #expect(profile.opo?.equalizerPresets.isEmpty ?? true, "\(id) has presets but the equalizer is hidden")
            return
        }
        for preset in profile.opo?.equalizerPresets ?? [] {
            await manager.setEqualizer(presetID: preset.id)
            #expect(manager.equalizerPreset == preset.id, "\(id): preset \(preset.name)")
        }
    }

    @Test(arguments: controllableIDs)
    func featureSwitchesFlipAndRestore(_ id: String) async throws {
        let (manager, profile) = try await connected(id)
        for featureID in profile.opo?.writableFeatureIDs.sorted() ?? [] {
            guard let original = manager.features[featureID] else { continue }
            await manager.setFeature(featureID, enabled: !original)
            #expect(manager.features[featureID] == !original, "\(id): feature \(featureID)")
            await manager.setFeature(featureID, enabled: original)
            #expect(manager.features[featureID] == original)
        }
    }

    @Test(arguments: controllableIDs)
    func leftAndRightGesturesAreIndependent(_ id: String) async throws {
        let (manager, profile) = try await connected(id)
        guard manager.presentation(.gestures) != .hidden, let opo = profile.opo else { return }
        for left in manager.gestures where left.side == GestureSide.left.rawValue {
            guard let alternative = opo.gestureFunctions[left.action]?.first(where: { $0 != left.function }) else { continue }
            let rightBefore = manager.gestures.first { $0.side == GestureSide.right.rawValue && $0.action == left.action }
            var changed = left
            changed.function = alternative
            await manager.setGesture(changed)
            #expect(manager.gestures.contains(changed), "\(id): left \(left.action) not applied")
            let rightAfter = manager.gestures.first { $0.side == GestureSide.right.rawValue && $0.action == left.action }
            #expect(rightAfter == rightBefore, "\(id): changing the left earbud changed the right one")
        }
    }

    @Test func optionsDifferPerModel() {
        func categories(_ profile: DeviceProfile) -> Set<NoiseCategory> { Set(profile.opo?.noiseModes.map(\.mode.category) ?? []) }
        func levels(_ profile: DeviceProfile) -> Set<ANCLevel> {
            Set(profile.opo?.noiseModes.compactMap { if case .noiseCancelling(let level?) = $0.mode { level } else { nil } } ?? [])
        }
        let buds3 = DeviceRegistry.onePlusBuds3, air5 = DeviceRegistry.realmeBudsAir5, t300 = DeviceRegistry.realmeBudsT300
        #expect(levels(buds3) == [.smart, .deep, .medium, .light])
        #expect(levels(air5) == [.smart, .deep, .medium, .light])
        #expect(levels(t300).isEmpty)
        #expect(categories(t300) == [.off, .transparency, .noiseCancelling])
        // Same mode, different bytes per brand.
        #expect(buds3.opo?.noiseModes.first { $0.mode == .transparency }?.setMask == [0x04])
        #expect(air5.opo?.noiseModes.first { $0.mode == .transparency }?.setMask == [0x02])
        #expect(buds3.opo?.equalizerPresets.map(\.name).contains("Bright & Crisp") == true)
        #expect(air5.opo?.equalizerPresets.map(\.name) == ["Pure Raw", "Deep Bass", "Pure Vocals", "Pure Bass"])
        #expect(t300.presentation(.wearDetection) == .hidden)
        #expect(DeviceRegistry.nordBuds3Pro.presentation(.equalizer) == .hidden)
    }

    @Test func switchingModelsReplacesEverySetting() async throws {
        let manager = DeviceManager(connector: DemoConnector(profile: DeviceRegistry.onePlusBuds3), reconnectDelays: [])
        await manager.connect()
        #expect(manager.deviceInfo?.productID == "063C14")
        await manager.useConnector(DemoConnector(profile: DeviceRegistry.realmeBudsT300))
        for _ in 0..<100 where !(manager.connection == .connected && manager.lastUpdated != nil) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(manager.profile?.id == "realme-buds-t300")
        #expect(manager.deviceInfo?.productID == "062412")
        #expect(manager.presentation(.wearDetection) == .hidden)
        #expect(manager.features[0x04] == nil) // no in-ear switch carried over from the Buds 3
        if case .noiseCancelling(let level?)? = manager.noiseControl { Issue.record("T300 reported a level \(level)") }
    }
}
