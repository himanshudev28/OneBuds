import AppKit

/// Menu-bar app activation: show a Dock icon while any window is open, hide it again when the last
/// one closes. Reference-counted because the main window and Settings can be open together.
@MainActor
enum AppActivationPolicy {
    private static var openWindows = 0

    static func enter() {
        openWindows += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func leave() {
        openWindows = max(0, openWindows - 1)
        guard openWindows == 0 else { return }
        Task { @MainActor in NSApp.setActivationPolicy(.accessory) }
    }
}
