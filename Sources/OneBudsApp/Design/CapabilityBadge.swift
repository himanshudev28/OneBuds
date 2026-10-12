import OneBudsCore
import SwiftUI

/// Badge shown next to a capability: "Experimental" when unverified, nothing when verified.
struct CapabilityBadge: View {
    let presentation: CapabilityPresentation

    var body: some View {
        if presentation == .experimental { Badge.experimental }
    }
}
