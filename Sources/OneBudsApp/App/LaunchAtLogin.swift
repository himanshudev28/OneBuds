import Observation
import ServiceManagement

/// Launch-at-login through ServiceManagement.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status = SMAppService.mainApp.status
    private(set) var errorMessage: String?

    var isEnabled: Bool { status == .enabled }

    var statusText: String {
        switch status {
        case .enabled: "OneBuds opens when you log in."
        case .requiresApproval: "Approve OneBuds in System Settings → General → Login Items."
        case .notFound: "Install OneBuds in the Applications folder to use this option."
        case .notRegistered: "OneBuds does not open at login."
        @unknown default: "Status unknown."
        }
    }

    func set(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }

    func refresh() { status = SMAppService.mainApp.status }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
