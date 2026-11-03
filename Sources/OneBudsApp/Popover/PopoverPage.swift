import OneBudsCore
import SwiftUI

/// The popover's sub-pages, opened from the navigation tiles.
enum PopoverPage: String, CaseIterable, Identifiable {
    case sound, controls, features, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sound: "Sound"
        case .controls: "Controls"
        case .features: "Features"
        case .tools: "Tools"
        }
    }

    var symbol: String {
        switch self {
        case .sound: "slider.vertical.3"
        case .controls: "hand.tap.fill"
        case .features: "switch.2"
        case .tools: "wrench.and.screwdriver.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sound: .pink
        case .controls: .blue
        case .features: .green
        case .tools: .orange
        }
    }

    /// The main-window screen with the full version of this page.
    var windowItem: SidebarItem {
        switch self {
        case .sound: .equalizer
        case .controls: .gestures
        case .features: .overview
        case .tools: .tools
        }
    }

    /// Whether the connected model has anything to show on this page.
    @MainActor
    func isAvailable(_ manager: DeviceManager) -> Bool {
        switch self {
        case .sound: manager.presentation(.equalizer) != .hidden
        case .controls: manager.presentation(.gestures) != .hidden && !manager.gestures.isEmpty
        case .features: !PopoverFeatures.capabilities.compactMap { manager.visibleFeatureID(for: $0) }.isEmpty
        case .tools: [Capability.findEarbuds, .fitTest, .hearingTest].contains { manager.presentation($0) != .hidden }
        }
    }

    /// One line under the tile title: the current state where there is one.
    @MainActor
    func subtitle(_ manager: DeviceManager) -> String {
        switch self {
        case .sound:
            return EqualizerPresets.currentName(for: manager) ?? "Equalizer"
        case .controls:
            return "Taps and holds"
        case .features:
            let on = PopoverFeatures.capabilities.compactMap { manager.visibleFeatureID(for: $0) }.filter { manager.features[$0] == true }.count
            return on == 0 ? "All off" : "\(on) on"
        case .tools:
            return manager.isRinging ? "Playing sound…" : "Find and fit"
        }
    }
}
