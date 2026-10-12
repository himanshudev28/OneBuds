import OneBudsCore

extension FirmwareComponent {
    /// Stable identity for lists (a component is unique by device and version type).
    var displayID: String { "\(deviceType)-\(versionType)" }

    var componentName: String {
        switch deviceType {
        case 1: "Left earbud"
        case 2: "Right earbud"
        case 3: "Case"
        default: "Component \(deviceType)"
        }
    }
}
