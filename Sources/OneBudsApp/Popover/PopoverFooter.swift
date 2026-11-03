import AppKit
import SwiftUI

struct PopoverFooter: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button("Open OneBuds", systemImage: "macwindow", action: showMainWindow)
            Spacer()
            Button("Settings", systemImage: "gearshape", action: showSettings)
                .labelStyle(.iconOnly)
                .keyboardShortcut(",")
                .help("Settings (⌘,)")
            Button("Quit OneBuds", systemImage: "xmark.circle", action: quit)
                .labelStyle(.iconOnly)
                .keyboardShortcut("q")
                .help("Quit OneBuds (⌘Q)")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private func showMainWindow() {
        openWindow(id: AppModel.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettings() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func quit() { NSApp.terminate(nil) }
}
