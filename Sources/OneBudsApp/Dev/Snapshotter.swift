import AppKit
import OneBudsCore
import SwiftUI

/// Development aid: when `ONEBUDS_SNAPSHOT_DIR` is set, renders the popover and every main-window
/// section offscreen (Demo connector only, never Bluetooth) to PNG files in light and dark mode,
/// then quits. Used to review the UI without screen capture.
@MainActor
enum Snapshotter {
    static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["ONEBUDS_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func run(model: AppModel, to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model.systemVolume.start()
        await model.manager.useConnector(DemoConnector())
        _ = await waitUntil(timeout: .seconds(10)) { model.manager.connection.isConnected && model.manager.battery != nil }

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            await render(PopoverView(), model: model, width: Theme.Size.popoverWidth, height: nil, name: "popover-\(suffix)", appearance: appearance, in: directory)
            for page in PopoverPage.allCases {
                await render(PopoverPageView(page: page) {}.padding(Theme.Spacing.m + 2).frame(width: Theme.Size.popoverWidth),
                             model: model, width: Theme.Size.popoverWidth, height: nil, name: "popover-page-\(page.rawValue)-\(suffix)",
                             appearance: appearance, in: directory)
            }
            for item in SidebarItem.allCases {
                model.selection = item
                await render(MainWindow(), model: model, width: 820, height: 600, name: "window-\(item.rawValue)-\(suffix)", appearance: appearance, in: directory)
            }
        }
        if let layout = model.manager.profile?.opo?.customEQ {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                await render(CustomPresetEditor(mode: model.manager.customPresets.first.map { .edit($0) } ?? .new, layout: layout,
                                                existing: model.manager.customPresets),
                             model: model, width: 460, height: nil, name: "sheet-eq-editor-\(appearance == .aqua ? "light" : "dark")",
                             appearance: appearance, in: directory)
            }
            await render(HearingTestView(), model: model, width: 440, height: nil, name: "sheet-hearing-intro", appearance: .aqua, in: directory)
        }
        // Connection card: live levels, the first read still running, and a model without battery.
        let presentation = ConnectionCardPresenter.Presentation(modelName: model.manager.profile?.displayName ?? "Earbuds", deviceName: nil,
                                                                profileID: model.manager.profile?.id, isDemo: true, artwork: .none)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            await render(LiveConnectionCard(presentation: presentation), model: model, width: Theme.Size.cardWidth, height: nil,
                         name: "card-connected-\(suffix)", appearance: appearance, in: directory)
        }
        await render(ConnectionCard(modelName: "OnePlus Buds 3", deviceName: "Renamed Buds", connection: .connected, transport: "Classic Bluetooth", battery: .waiting),
                     model: model, width: Theme.Size.cardWidth, height: nil, name: "card-waiting", appearance: .aqua, in: directory)
        await render(ConnectionCard(modelName: "OnePlus Nord Buds 3 Pro", connection: .connected, transport: "Bluetooth LE", battery: .notReported),
                     model: model, width: Theme.Size.cardWidth, height: nil, name: "card-not-reported", appearance: .darkAqua, in: directory)
        let partial = BatteryStatus(left: .init(percent: 64, isCharging: false), right: .init(percent: 12, isCharging: true))
        await render(ConnectionCard(modelName: "OnePlus Buds 3", connection: .connected, battery: .levels(partial)),
                     model: model, width: Theme.Size.cardWidth, height: nil, name: "card-no-case", appearance: .aqua, in: directory)
        // Artwork fallbacks. The image is a stand-in (a system symbol), not product artwork.
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("onebuds-render-fixture.png")
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("onebuds-broken.usdz")
        try? Data("not a usdz".utf8).write(to: broken)
        if let symbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 120, weight: .regular)),
           let tiff = symbol.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: fixture)
        }
        let artworkCases: [(String, EarbudArtwork)] = [
            ("render", EarbudArtwork(render: fixture)),
            ("broken-model-then-render", EarbudArtwork(model: broken, render: fixture)),
            ("broken-model-then-symbol", EarbudArtwork(model: broken)),
        ]
        for (name, artwork) in artworkCases {
            await render(ConnectionCard(modelName: "OnePlus Buds 3", connection: .connected, battery: .levels(partial), artwork: artwork),
                         model: model, width: Theme.Size.cardWidth, height: nil, name: "card-artwork-\(name)", appearance: .aqua, in: directory)
        }

        // Battery slots: a missing level, low and charging levels, and the first read still running.
        let mixed = BatteryStatus(left: .init(percent: 9, isCharging: false), right: .init(percent: 27, isCharging: true))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            await render(VStack(spacing: Theme.Spacing.xl) {
                BatteryRow(battery: mixed, size: .large)
                BatteryRow(battery: mixed)
                BatteryRow(waitingWith: .regular)
            }.padding(Theme.Spacing.l), model: model, width: 420, height: nil, name: "battery-states-\(suffix)", appearance: appearance, in: directory)
        }
        // Overview at the narrowest useful and a wide window: rows must neither clip nor sprawl.
        model.selection = .overview
        await render(MainWindow(), model: model, width: 700, height: 640, name: "window-overview-narrow", appearance: .aqua, in: directory)
        await render(MainWindow(), model: model, width: 1280, height: 720, name: "window-overview-wide", appearance: .darkAqua, in: directory)

        model.settings.visualStyle = .glass
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            await render(PopoverView().environment(\.visualStyle, .glass), model: model, width: Theme.Size.popoverWidth, height: nil,
                         name: "glass-popover-\(suffix)", appearance: appearance, in: directory)
            model.selection = .overview
            await render(MainWindow().environment(\.visualStyle, .glass), model: model, width: 820, height: 600,
                         name: "glass-overview-\(suffix)", appearance: appearance, in: directory)
        }
        model.settings.visualStyle = .standard
        for tab in SettingsTab.allCases {
            await render(SettingsView(tab: tab), model: model, width: 500, height: nil, name: "settings-\(tab.rawValue)", appearance: .aqua, in: directory)
        }
        // Per-model: the controls must follow each model's profile.
        for profile in AppSettings.demoModels {
            await model.manager.useConnector(DemoConnector(profile: profile))
            _ = await waitUntil(timeout: .seconds(10)) { model.manager.connection.isConnected && model.manager.lastUpdated != nil }
            await render(PopoverView(), model: model, width: 320, height: nil, name: "model-\(profile.id)-popover", appearance: .aqua, in: directory)
            for item in [SidebarItem.equalizer, .gestures] {
                model.selection = item
                await render(MainWindow(), model: model, width: 820, height: 600, name: "model-\(profile.id)-\(item.rawValue)", appearance: .aqua, in: directory)
            }
        }
        await model.manager.disconnect()
        await render(PopoverView(), model: model, width: 320, height: nil, name: "popover-disconnected", appearance: .aqua, in: directory)
        exit(0)
    }

    private static func render<V: View>(_ view: V, model: AppModel, width: CGFloat, height: CGFloat?, name: String,
                                        appearance: NSAppearance.Name, in directory: URL) async {
        // The real popover sits on a system material; give offscreen renders an equivalent backdrop.
        let hosting = NSHostingView(rootView: view.environment(model).environment(model.manager).background(Color(nsColor: .windowBackgroundColor)))
        let size = CGSize(width: width, height: height ?? max(hosting.fittingSize.height, 100))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.orderBack(nil)
        try? await Task.sleep(for: .milliseconds(500))
        if height == nil {
            hosting.frame.size.height = max(hosting.fittingSize.height, 100)
            window.setContentSize(hosting.frame.size)
            try? await Task.sleep(for: .milliseconds(200))
        }
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
