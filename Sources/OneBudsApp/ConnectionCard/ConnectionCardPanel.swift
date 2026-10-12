import AppKit
import OneBudsCore
import SwiftUI

/// Hosts the connection card in a borderless, non-activating floating panel at the top right of
/// the screen the pointer is on. It never takes focus from the app in front, joins every Space and shows over
/// full-screen apps. Motion is SwiftUI's; the panel itself only appears and disappears.
@MainActor
final class ConnectionCardPanel: ConnectionCardHost {
    /// Transparent margin around the card so its shadow is not clipped.
    static let shadowInset: CGFloat = 20
    /// Gap between the card and the screen edges / menu bar.
    private static let screenMargin: CGFloat = 10

    private let presenter: ConnectionCardPresenter
    private let manager: DeviceManager
    private let settings: AppSettings
    /// Created on the first card, so a Mac that never shows one never pays for the window.
    private var panel: CardPanel?
    /// The card's size per layout (with or without a second name line); it never changes otherwise.
    private var cardSizes: [Bool: CGSize] = [:]

    init(presenter: ConnectionCardPresenter, manager: DeviceManager, settings: AppSettings) {
        self.presenter = presenter
        self.manager = manager
        self.settings = settings
    }

    private func makePanel() -> CardPanel {
        let panel = CardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.contentView = FirstClickHostingView(rootView: AnyView(
            ConnectionCardOverlay(presenter: presenter)
                .environment(manager)
                .environment(settings)
        ))
        return panel
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = cardSize()
        let inset = Self.shadowInset
        let panelSize = CGSize(width: size.width + inset * 2, height: size.height + inset * 2)
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let origin = CGPoint(x: visible.maxX - Self.screenMargin - size.width - inset,
                                 y: visible.maxY - Self.screenMargin + inset - panelSize.height)
            panel.setFrame(CGRect(origin: origin, size: panelSize), display: false)
        }
        panel.orderFrontRegardless()
        if let presentation = presenter.presentation {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: "\(presentation.modelName) connected",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ])
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// The card's natural size for the current presentation (it does not change while shown).
    private func cardSize() -> CGSize {
        guard let presentation = presenter.presentation else { return CGSize(width: Theme.Size.cardWidth, height: 180) }
        let layout = presentation.deviceName != nil
        if let size = cardSizes[layout] { return size }
        // Measured without artwork: the artwork has a fixed size, and laying out a 3D view here
        // would create and load a second, offscreen renderer.
        let measured = ConnectionCardPresenter.Presentation(modelName: presentation.modelName, deviceName: presentation.deviceName,
                                                            profileID: presentation.profileID, isDemo: presentation.isDemo, artwork: .none)
        let sizing = NSHostingView(rootView: LiveConnectionCard(presentation: measured).environment(manager))
        let size = sizing.fittingSize
        cardSizes[layout] = size
        return size
    }
}

/// The card never needs keyboard focus (`becomesKeyOnlyIfNeeded`), so it never takes it from the
/// app in front; buttons still work on the first click via `FirstClickHostingView`.
private final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// The transparent shadow margin may overlap the menu bar; the card itself never does.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Buttons respond to the first click even though the panel is not key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Panel content: the card with its material, shadow and enter/exit transitions.
struct ConnectionCardOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    let presenter: ConnectionCardPresenter

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Size.cardRadius, style: .continuous) }

    private var animation: Animation {
        if reduceMotion { return Theme.Motion.reduced }
        return presenter.isVisible ? Theme.Motion.cardEnter : Theme.Motion.cardExit
    }

    var body: some View {
        ZStack(alignment: .top) {
            if presenter.isVisible, let presentation = presenter.presentation {
                LiveConnectionCard(presentation: presentation,
                                   animatesArtwork: settings.animateCardModel,
                                   onOpen: { presenter.openDeviceOverview() },
                                   onDismiss: { presenter.dismiss() })
                    .background(VisualEffectBackground(material: .popover, state: .active))
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                    .onHover { presenter.setHovering($0) }
                    .contextMenu {
                        Button("Don’t Show When Earbuds Connect") {
                            settings.showConnectionCard = false
                            presenter.dismiss()
                        }
                    }
                    .transition(reduceMotion ? .opacity : .connectionCard)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(ConnectionCardPanel.shadowInset)
        .animation(animation, value: presenter.isVisible)
    }
}

/// Binds the card to live device state; only the model name is frozen at presentation time.
struct LiveConnectionCard: View {
    @Environment(DeviceManager.self) private var manager
    let presentation: ConnectionCardPresenter.Presentation
    var animatesArtwork = true
    var onOpen: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        ConnectionCard(modelName: presentation.modelName,
                       deviceName: presentation.deviceName,
                       connection: manager.connection,
                       transport: manager.transportKind?.displayName,
                       battery: BatteryReading.resolve(battery: manager.battery,
                                                       presentation: manager.presentation(.battery),
                                                       refresh: manager.status(of: .refresh)),
                       isDemo: presentation.isDemo,
                       artwork: presentation.artwork,
                       animatesArtwork: animatesArtwork,
                       onOpen: onOpen,
                       onDismiss: onDismiss)
    }
}

extension AnyTransition {
    /// Drops in from just under the menu bar, scaling up from the top edge; leaves with a fade
    /// and a slight shrink.
    static var connectionCard: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).combined(with: .offset(y: -12)),
            removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
        )
    }
}
