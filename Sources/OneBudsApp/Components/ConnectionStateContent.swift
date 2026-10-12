import OneBudsCore

/// Copy, symbol and action for every non-connected state, shared by the popover and the window.
struct ConnectionStateContent {
    enum Action {
        case retry, openPrivacySettings, helpAddModel
    }

    let state: DeviceManager.ConnectionState

    var title: String { state.displayText }

    var symbol: String {
        switch state {
        case .bluetoothOff, .bluetoothUnsupported: "antenna.radiowaves.left.and.right.slash"
        case .unauthorized: "lock.shield"
        case .unrecognised: "questionmark.circle"
        case .failed: "exclamationmark.triangle"
        default: "earbuds.case"
        }
    }

    var detail: String? {
        switch state {
        case .noDevice, .idle: "Take your earbuds out of the case and connect them to this Mac in System Settings → Bluetooth."
        case .unauthorized: "OneBuds needs Bluetooth access to talk to your earbuds. Allow it in System Settings → Privacy & Security → Bluetooth."
        case .bluetoothOff: "Turn Bluetooth on to use OneBuds."
        case .bluetoothUnsupported: "This Mac does not offer the Bluetooth features OneBuds needs."
        case .unrecognised: "OneBuds only controls models with a verified or experimental profile. You can export read-only diagnostics to help add this one."
        case .failed: "OneBuds will try again automatically."
        case .searching, .connecting, .handshaking: "This usually takes a second or two."
        case .connected: nil
        }
    }

    var action: Action? {
        switch state {
        case .unauthorized: .openPrivacySettings
        case .unrecognised: .helpAddModel
        case .noDevice, .failed, .idle, .bluetoothOff: .retry
        default: nil
        }
    }

    var actionTitle: String {
        switch action {
        case .openPrivacySettings: "Open Bluetooth Privacy Settings"
        case .helpAddModel: "Help Add My Model…"
        case .retry, nil: "Try Again"
        }
    }
}
