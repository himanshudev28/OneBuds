import AppKit
import Observation
import OneBudsCore
import SwiftUI

/// The menu-bar item and its panel (macOS 15+). Replaces `MenuBarExtra`, which opens with no
/// animation and stops closing on outside clicks once the app has switched activation policy.
///
/// The panel opens on mouse-down like a system menu: a short fade with a slight drop from the
/// menu bar (fade only under Reduce Motion). It closes on a click anywhere outside it, Escape,
/// a second click on the icon, switching apps or Spaces, or when one of our windows comes forward.
@MainActor
final class MenuBarPanelController: NSObject {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let presentation = PanelPresentation()
    private var panel: MenuBarPanel?
    private var hosting: NSHostingController<AnyView>?
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Bumped on every open so the popover starts on its home page, like a fresh menu.
    private var session = 0
    private var isOpen = false

    init(model: AppModel) {
        self.model = model
        super.init()
        // Remembers where the user ⌘-drags the icon.
        statusItem.autosaveName = "OneBudsStatusItem"
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        installWindowOpener(in: button)
        updateLabel()
    }

    // MARK: Label

    /// Keeps the icon and battery text in step with the device, re-arming after each change.
    private func updateLabel() {
        let content = withObservationTracking {
            MenuBarLabelContent(manager: model.manager, settings: model.settings)
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateLabel() }
        }
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: content.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        image?.isTemplate = true
        button.image = image
        button.title = content.text.map { " \($0)" } ?? ""
        button.setAccessibilityLabel(content.accessibilityLabel)
    }

    /// SwiftUI's window opener only exists inside a SwiftUI view, so a tiny invisible one lives in
    /// the status item from launch. The connection card and popover use it to open the main window.
    private func installWindowOpener(in button: NSStatusBarButton) {
        let opener = PassthroughHostingView(rootView: WindowOpenerCapture { [model] openWindow in
            model.openWindow = { openWindow(id: $0) }
        })
        // Fully opaque (it draws nothing) so SwiftUI treats it as on screen and runs onAppear.
        opener.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        button.addSubview(opener)
    }

    // MARK: Open and close

    @objc private func togglePanel() {
        isOpen ? close() : open()
    }

    private func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let panel = self.panel ?? makePanel()
        session += 1
        hosting?.rootView = rootView()
        hosting?.view.layoutSubtreeIfNeeded()

        let size = hosting?.view.fittingSize ?? NSSize(width: Theme.Size.popoverWidth, height: 400)
        let itemFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let margin = Theme.Spacing.s
        // An icon hidden by a crowded menu bar (behind the notch) has no usable position:
        // open at the top-right corner instead, under the menu bar.
        let itemIsVisible = screen.map { itemFrame.intersects($0.frame) && itemFrame.minX >= $0.frame.minX } ?? false
        var x = itemIsVisible ? itemFrame.minX - Theme.Spacing.s : visible.maxX - size.width - margin
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        panel.anchorTop = (itemIsVisible ? itemFrame.minY : visible.maxY) - Theme.Spacing.xs - 1
        panel.setFrame(NSRect(x: x, y: panel.anchorTop! - size.height, width: size.width, height: size.height), display: false)

        isOpen = true
        button.highlight(true)
        // The button un-highlights when its mouse-up tracking ends; restore it once tracking is over.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isOpen else { return }
                self.statusItem.button?.highlight(true)
            }
        }
        presentation.isShown = false
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        installDismissTriggers()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0)) { presentation.isShown = true }
    }

    func close() {
        guard isOpen, let panel else { return }
        isOpen = false
        removeDismissTriggers()
        statusItem.button?.highlight(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                // A quick reopen during the fade owns the panel now.
                guard let self, !self.isOpen else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel() -> MenuBarPanel {
        let hosting = NSHostingController(rootView: rootView())
        hosting.sizingOptions = [.preferredContentSize]
        let panel = MenuBarPanel(contentViewController: hosting)
        panel.onCancel = { [weak self] in self?.close() }
        self.hosting = hosting
        self.panel = panel
        return panel
    }

    private func rootView() -> AnyView {
        AnyView(
            MenuBarPanelContent(presentation: presentation) {
                PopoverView()
            }
            .id(session)
            .environment(model)
            .environment(model.manager)
            .environment(\.visualStyle, model.settings.visualStyle)
        )
    }

    // MARK: Dismissal

    private func installDismissTriggers() {
        removeDismissTriggers()
        // Clicks in other apps, the desktop, or other menu-bar items.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.close() }
        }) { monitors.append(global) }
        // Clicks in our own other windows (the status item's own click toggles instead).
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            // Menus, tooltips and anything attached to the panel belong to it.
            if let window = event.window, window !== self.panel, window !== self.statusItem.button?.window,
               window.parent !== self.panel, window.level <= .normal {
                self.close()
            }
            return event
        }) { monitors.append(local) }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.close() }
        // Switching apps (e.g. ⌘Tab). Activation notices arrive late, so one for the app that was
        // already in front when the panel opened is a leftover and must not close it.
        let frontAtOpen = NSWorkspace.shared.frontmostApplication?.processIdentifier
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            guard pid != ProcessInfo.processInfo.processIdentifier, pid != frontAtOpen else { return }
            self?.close()
        }
        // One of our windows (main window, Settings) came forward from a popover button.
        observe(.default, NSWindow.didBecomeKeyNotification) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, window !== self.panel, window.level == .normal else { return }
            self.close()
        }
        // Popover buttons that open a window also activate the app. Menus inside the panel don't
        // move the key window, so the panel stays open for those.
        observe(.default, NSApplication.didBecomeActiveNotification) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel?.isKeyWindow != true else { return }
                self.close()
            }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
            // Delivered on the main queue, so the notification never actually crosses threads.
            nonisolated(unsafe) let note = note
            MainActor.assumeIsolated { handler(note) }
        }
        observers.append((center, token))
    }

    private func removeDismissTriggers() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }
}

/// Drives the panel's entrance: content settles from slightly above, scaled from the menu bar.
@MainActor
@Observable
final class PanelPresentation {
    var isShown = false
}

/// The panel's chrome: menu material, rounded corners and a hairline edge around the popover.
private struct MenuBarPanelContent<Content: View>: View {
    /// Close to Control Center's panels; wider than a menu's corners.
    static var cornerRadius: CGFloat { 16 }
    let presentation: PanelPresentation
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous) }

    var body: some View {
        content()
            .background(PanelMaterial(cornerRadius: Self.cornerRadius))
            .overlay(shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 0.5))
            .clipShape(shape)
            .scaleEffect(presentation.isShown ? 1 : 0.97, anchor: .top)
            .offset(y: presentation.isShown ? 0 : -6)
    }
}

/// Behind-window menu material, masked to the panel's rounded shape so the blur and the window
/// shadow follow the corners.
private struct PanelMaterial: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = .roundedMask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private extension NSImage {
    /// A stretchable rounded-rectangle mask.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Borderless, non-activating panel: it takes keyboard focus without pulling the user out of the
/// app they're in, and keeps its top edge pinned under the menu bar as the content changes height.
final class MenuBarPanel: NSPanel {
    var anchorTop: CGFloat?
    var onCancel: (() -> Void)?

    init(contentViewController: NSViewController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        self.contentViewController = contentViewController
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(pinned(frameRect), display: flag)
        invalidateShadow()
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(pinned(frameRect), display: displayFlag, animate: animateFlag)
        invalidateShadow()
    }

    override func setContentSize(_ size: NSSize) {
        setFrame(frameRect(forContentRect: NSRect(origin: frame.origin, size: size)), display: true)
    }

    private func pinned(_ rect: NSRect) -> NSRect {
        var rect = rect
        if let anchorTop { rect.origin.y = anchorTop - rect.height }
        return rect
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Hosting view that never takes clicks, so the status item button underneath gets them.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct WindowOpenerCapture: View {
    let capture: (OpenWindowAction) -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear { capture(openWindow) }
    }
}
