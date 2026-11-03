import SwiftUI

/// Main-window destinations, grouped as in the sidebar.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview, noiseControl, equalizer, gestures, tools, deviceInfo, compatibility, diagnostics

    static let earbuds: [SidebarItem] = [.overview, .noiseControl, .equalizer, .gestures, .tools]
    static let information: [SidebarItem] = [.deviceInfo, .compatibility, .diagnostics]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .noiseControl: "Noise Control"
        case .equalizer: "Sound"
        case .gestures: "Controls"
        case .tools: "Tools"
        case .deviceInfo: "Device Info"
        case .compatibility: "Compatibility"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "earbuds"
        case .noiseControl: "waveform"
        case .equalizer: "slider.vertical.3"
        case .gestures: "hand.tap.fill"
        case .tools: "wrench.and.screwdriver.fill"
        case .deviceInfo: "info.circle.fill"
        case .compatibility: "checklist"
        case .diagnostics: "stethoscope"
        }
    }

    /// Icon tile colour, as in System Settings.
    var tint: Color {
        switch self {
        case .overview: .blue
        case .noiseControl: .indigo
        case .equalizer: .pink
        case .gestures: .orange
        case .tools: .gray
        case .deviceInfo: .gray
        case .compatibility: .green
        case .diagnostics: .teal
        }
    }
}
