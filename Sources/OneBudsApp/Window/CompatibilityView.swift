import OneBudsCore
import SwiftUI

struct CompatibilityView: View {
    var body: some View {
        Form {
            Section {
                Text("A model is controlled only when it has a profile, and each feature is rated separately: Verified (tested on hardware), Experimental (built from documented research), or hidden. Unknown models get read-only diagnostics.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(Manufacturer.allCases, id: \.self) { manufacturer in
                let profiles = DeviceRegistry.all.filter { $0.manufacturer == manufacturer }
                if !profiles.isEmpty {
                    Section(manufacturer.rawValue) {
                        ForEach(profiles) { profile in
                            ProfileCompatibilityRow(profile: profile)
                        }
                    }
                }
            }
        }
        .screenFormStyle()
    }
}
