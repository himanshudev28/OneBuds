import OneBudsCore
import SwiftUI

/// Shows `content` only when a supporting device is connected; otherwise a native empty state.
struct RequiresCapability<Content: View>: View {
    @Environment(DeviceManager.self) private var manager
    let capability: Capability
    @ViewBuilder let content: () -> Content

    var body: some View {
        if !manager.connection.isConnected {
            ConnectionStateView()
        } else if manager.presentation(capability) == .hidden {
            ContentUnavailableView("Not Available", systemImage: "nosign",
                                   description: Text("\(capability.displayName) isn't supported for \(manager.profile?.displayName ?? "this model") in OneBuds."))
        } else {
            content()
        }
    }
}
