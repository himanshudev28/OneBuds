import Foundation
import OneBudsBluetooth
import OneBudsDiagnostics

struct ProbeOptions: Sendable {
    enum Mode: Sendable { case inspect, session }
    var mode = Mode.inspect
    /// Session mode: routes to try, in order, and the classic/BLE device name to use.
    var routes = ["rfcomm", "ble"]
    var deviceName = "OnePlus Buds 3"
    var outDir: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var scanSeconds = 12
    var sdpRefresh = true
    var readStandard = false
    var redact = true
    var namePattern = CandidateFilter.defaultPattern
    var maxGATTConnections = 4
    var permissionWaitSeconds = 60

    var inspection: InspectionOptions {
        .init(scanSeconds: scanSeconds, sdpRefresh: sdpRefresh, readStandard: readStandard, namePattern: namePattern,
              maxGATTConnections: maxGATTConnections, permissionWaitSeconds: permissionWaitSeconds)
    }

    var reportOptions: ProbeReport.Options {
        .init(scanSeconds: scanSeconds, sdpRefresh: sdpRefresh, readStandardCharacteristics: readStandard,
              redact: redact, namePattern: namePattern)
    }

    static let usage = """
    onebuds-probe: read-only Bluetooth diagnostics for OneBuds (Phase B)

    Lists paired classic devices with their SDP service records and RFCOMM channels, and BLE
    peripherals (already connected, then scanned) with their GATT services and characteristics.
    It never sends protocol messages, never writes a characteristic, never enables notifications.

    Usage: run through scripts/run-probe.sh (recommended), or
      open -W -n "build/OneBuds Probe.app" --args [options]

    Active mode (approved 2026-10-12; sends only 0x0100/0x0103/0x0105/0x0106 queries and the
    0x0500 time reply):
      onebuds-probe session [--route rfcomm|ble|auto] [--device-name NAME] [--out-dir PATH]

    Options:
      --out-dir PATH        Directory for the .txt and .json reports (default: current directory)
      --scan-seconds N      BLE scan duration, 0 to skip scanning (default 12)
      --no-sdp-refresh      Use cached SDP records only (default: refresh connected candidates)
      --read-standard       Also read standard Device Information (0x180A) and Battery (0x180F)
                            characteristics on candidates. Vendor characteristics are never read.
      --name-pattern REGEX  Candidate name filter, case-insensitive (default "\(CandidateFilter.defaultPattern)")
      --no-redact           Show full Bluetooth addresses, identifiers and serial numbers
      --help                Show this help
    """

    enum ParseError: Error, CustomStringConvertible {
        case missingValue(String), badValue(String, String), unknown(String)
        var description: String {
            switch self {
            case .missingValue(let flag): "missing value for \(flag)"
            case .badValue(let flag, let value): "invalid value \"\(value)\" for \(flag)"
            case .unknown(let flag): "unknown option \(flag)"
            }
        }
    }

    /// Returns `nil` when `--help` was requested.
    static func parse(_ arguments: [String]) throws -> ProbeOptions? {
        var options = ProbeOptions()
        var arguments = arguments
        if let index = arguments.firstIndex(of: "session") {
            options.mode = .session
            arguments.remove(at: index)
        }
        var iterator = arguments.makeIterator()
        func value(for flag: String) throws -> String {
            guard let next = iterator.next() else { throw ParseError.missingValue(flag) }
            return next
        }
        while let argument = iterator.next() {
            switch argument {
            case "--help", "-h": return nil
            case "--out-dir": options.outDir = URL(fileURLWithPath: (try value(for: argument) as NSString).expandingTildeInPath)
            case "--scan-seconds":
                let raw = try value(for: argument)
                guard let seconds = Int(raw), (0...120).contains(seconds) else { throw ParseError.badValue(argument, raw) }
                options.scanSeconds = seconds
            case "--route":
                let raw = try value(for: argument)
                switch raw {
                case "auto": options.routes = ["rfcomm", "ble"]
                case "rfcomm", "ble": options.routes = [raw]
                default: throw ParseError.badValue(argument, raw)
                }
            case "--device-name": options.deviceName = try value(for: argument)
            case "--no-sdp-refresh": options.sdpRefresh = false
            case "--read-standard": options.readStandard = true
            case "--no-redact": options.redact = false
            case "--name-pattern":
                let raw = try value(for: argument)
                guard (try? NSRegularExpression(pattern: raw)) != nil else { throw ParseError.badValue(argument, raw) }
                options.namePattern = raw
            default:
                // LaunchServices may append its own arguments (e.g. -psn_…, -NS…); ignore those.
                if argument.hasPrefix("-psn") || argument.hasPrefix("-NS") || argument.hasPrefix("-Apple") {
                    _ = argument.hasPrefix("-psn") ? nil : iterator.next()
                    continue
                }
                throw ParseError.unknown(argument)
            }
        }
        return options
    }
}
