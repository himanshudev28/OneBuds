import AppKit
import SwiftUI

struct PopoverFooter: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            Button("Open OneBuds", systemImage: "macwindow", action: showMainWindow)
            Button("Settings…", systemImage: "gearshape", action: showSettings)
                .keyboardShortcut(",")
            Spacer()
            Button("Quit", systemImage: "power", action: quit)
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .font(.callout)
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
