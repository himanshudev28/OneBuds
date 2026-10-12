import OneBudsCore
import SwiftUI

/// The Earbuds menu: keyboard access to the most common actions. Commands call the same device
/// manager operations as the controls, so nothing changes until the earbuds confirm it.
struct EarbudsCommands: Commands {
    let model: AppModel

    private var manager: DeviceManager { model.manager }

    private var categories: [NoiseCategory] {
        let modes = manager.profile?.opo?.noiseModes ?? []
        return NoiseCategory.allCases.filter { category in modes.contains { $0.mode.category == category } }
    }

    var body: some Commands {
        CommandMenu("Earbuds") {
            Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                .keyboardShortcut("r")
                .disabled(!manager.connection.isConnected)
            if manager.connection.isConnected {
                Button("Disconnect", systemImage: "xmark.circle", action: disconnect)
            } else {
                Button("Connect", systemImage: "link", action: connect)
                    .disabled(manager.connection.isBusy)
            }

            Button("Show Connection Card", systemImage: "rectangle.on.rectangle", action: showConnectionCard)
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!manager.connection.isConnected)

            Divider()

            Section("Noise Control") {
                ForEach(categories, id: \.self) { category in
                    Button(category.menuTitle) { select(category) }
                        .keyboardShortcut(category.shortcutKey, modifiers: .command)
                        .disabled(manager.presentation(.noiseControl) == .hidden || manager.status(of: .noiseControl) == .pending)
                }
            }
        }
    }

    private func refresh() { Task { await manager.refresh() } }
    private func connect() { Task { await manager.connect() } }
    private func disconnect() { Task { await manager.disconnect() } }
    private func showConnectionCard() { model.connectionCard.present() }

    private func select(_ category: NoiseCategory) {
        guard category != manager.noiseControl?.category else { return }
        Task { await manager.setNoiseControl(category.requestedMode) }
    }
}
