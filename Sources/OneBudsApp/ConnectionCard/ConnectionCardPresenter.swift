import Foundation
import Observation
import OneBudsCore
import os

/// Puts the connection card on screen and takes it off again.
@MainActor
protocol ConnectionCardHost: AnyObject {
    func show()
    func hide()
}

/// Shows the connection card on every new connection, as soon as the control channel is open (see
/// `ConnectionAnnouncementGate`), dismisses it after the chosen time unless the pointer rests on
/// it, and dismisses it if the earbuds disconnect. Display only: it observes `DeviceManager` and never calls into it.
@MainActor
@Observable
final class ConnectionCardPresenter {
    /// The connection being announced. Captured when the card appears so the title stays put while
    /// the card animates out after a disconnect has already cleared the device state.
    struct Presentation: Equatable {
        let modelName: String
        let deviceName: String?
        let profileID: String?
        let isDemo: Bool
        let artwork: EarbudArtwork
    }

    struct Timing {
        /// Overrides Settings ▸ Connection Card ▸ Hide after (tests); nil follows the setting.
        var visible: Duration?
        /// Time left after the pointer moves off the card.
        var afterHover: Duration = .seconds(2.5)
        /// Matches `Theme.Motion.cardExit`, plus a frame of slack.
        var exit: Duration = .milliseconds(250)
    }

    private(set) var presentation: Presentation?
    /// Drives the enter and exit transitions; `presentation` outlives it until the exit finishes.
    private(set) var isVisible = false
    /// How many times a connection was announced (for tests and diagnostics).
    private(set) var announcements = 0

    @ObservationIgnored weak var host: (any ConnectionCardHost)?
    /// Opens the main window on the Overview screen.
    @ObservationIgnored var openOverview: () -> Void = {}

    @ObservationIgnored private let manager: DeviceManager
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let timing: Timing
    @ObservationIgnored private var gate = ConnectionAnnouncementGate()
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var isHovering = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.local.onebuds", category: "card")

    init(manager: DeviceManager, settings: AppSettings, timing: Timing = Timing()) {
        self.manager = manager
        self.settings = settings
        self.timing = timing
    }

    /// Begins following the manager's connection state.
    func start() {
        let (state, device) = withObservationTracking {
            (manager.connection, deviceKey)
        } onChange: { [weak self] in
            Task { @MainActor in self?.start() }
        }
        connectionChanged(state, device: device)
    }

    /// Simulated and real earbuds with the same name are different connections.
    private var deviceKey: String? {
        manager.earbuds.map { "\($0.isDemo ? "demo" : "bluetooth"):\($0.name)" }
    }

    func connectionChanged(_ state: DeviceManager.ConnectionState, device: String?, at now: Date = Date()) {
        if gate.observe(state, device: device, at: now) {
            announcements += 1
            logger.info("New connection (\(String(describing: state), privacy: .public)); card \(self.settings.showConnectionCard ? "shown" : "off", privacy: .public)")
            if settings.showConnectionCard { present() }
        } else if !ConnectionAnnouncementGate.isLinked(state), isVisible {
            dismiss()
        }
    }

    /// Shows the card for the connected earbuds. Also reachable from the Earbuds menu, so it works
    /// with automatic cards turned off.
    func present() {
        guard ConnectionAnnouncementGate.isLinked(manager.connection) else { return }
        let profile = manager.profile
        let name = manager.earbuds?.name
        let modelName = profile?.displayName ?? name ?? "Earbuds"
        presentation = Presentation(modelName: modelName,
                                    deviceName: name == modelName ? nil : name,
                                    profileID: profile?.id,
                                    isDemo: manager.isDemo,
                                    artwork: EarbudArtwork.lookup(profileID: profile?.id).restricted(to: settings.cardArtworkStyle))
        hideTask?.cancel()
        hideTask = nil
        if !isVisible { isHovering = false }
        host?.show()
        isVisible = true
        if !isHovering, let visibleDuration {
            scheduleDismiss(after: visibleDuration)
        } else {
            // e.g. re-shown after Hide after changed to Until closed: drop the old timer.
            dismissTask?.cancel()
            dismissTask = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard isVisible else { return }
        isVisible = false
        // The card leaves from under the pointer (a click on it, a disconnect) without a hover-exit.
        isHovering = false
        hideTask = Task { [weak self, timing] in
            try? await Task.sleep(for: timing.exit)
            guard !Task.isCancelled, let self, !self.isVisible else { return }
            self.host?.hide()
            self.presentation = nil
            self.hideTask = nil
        }
    }

    /// Opens the device overview and puts the card away.
    func openDeviceOverview() {
        openOverview()
        dismiss()
    }

    /// The card stays while the pointer is on it, then leaves shortly after.
    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        guard isVisible else { return }
        if hovering {
            dismissTask?.cancel()
            dismissTask = nil
        } else if visibleDuration != nil {
            scheduleDismiss(after: timing.afterHover)
        }
    }

    /// nil: stays until closed or the earbuds disconnect.
    private var visibleDuration: Duration? { timing.visible ?? settings.cardDuration.duration }

    private func scheduleDismiss(after delay: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}
