import OneBudsCore
import SwiftUI

/// Game mode, in-ear detection and dual connection, each shown only if the profile supports it
/// and the earbuds reported a value.
struct FeatureTogglesSection: View {
    @Environment(DeviceManager.self) private var manager

    private struct Row: Identifiable {
        let capability: Capability
        let featureID: UInt8
        let symbol: String
        var id: UInt8 { featureID }
    }

    private var rows: [Row] {
        guard let opo = manager.profile?.opo else { return [] }
        let candidates: [(Capability, UInt8?, String)] = [
            (.gameMode, opo.gameModeFeatureID, "gamecontroller"),
            (.wearDetection, opo.wearDetectionFeatureID, "ear"),
            (.dualConnection, opo.dualConnectionFeatureID, "laptopcomputer.and.iphone"),
        ]
        return candidates.compactMap { capability, id, symbol in
            guard let id, manager.presentation(capability) != .hidden, manager.features[id] != nil else { return nil }
            return Row(capability: capability, featureID: id, symbol: symbol)
        }
    }

    var body: some View {
        if !rows.isEmpty {
            Section("Features") {
                ForEach(rows) { row in
                    FeatureToggleRow(capability: row.capability, featureID: row.featureID, symbol: row.symbol)
                }
            }
        }
    }
}
