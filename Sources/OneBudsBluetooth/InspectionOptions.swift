import OneBudsDiagnostics

/// Settings for the read-only inspectors (shared by `onebuds-probe` and the app's Diagnostics screen).
public struct InspectionOptions: Sendable {
    public var scanSeconds: Int
    public var sdpRefresh: Bool
    public var readStandard: Bool
    public var namePattern: String
    public var maxGATTConnections: Int
    public var permissionWaitSeconds: Int

    public init(scanSeconds: Int = 12, sdpRefresh: Bool = true, readStandard: Bool = false,
                namePattern: String = CandidateFilter.defaultPattern, maxGATTConnections: Int = 4,
                permissionWaitSeconds: Int = 60) {
        self.scanSeconds = scanSeconds
        self.sdpRefresh = sdpRefresh
        self.readStandard = readStandard
        self.namePattern = namePattern
        self.maxGATTConnections = maxGATTConnections
        self.permissionWaitSeconds = permissionWaitSeconds
    }
}
