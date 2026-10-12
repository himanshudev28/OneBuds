import CoreBluetooth
import Foundation
import OneBudsCore
import OneBudsDiagnostics

/// Read-only GATT inspection through Core Bluetooth.
///
/// Allowed: retrieving already-connected peripherals, scanning, connecting, discovering services,
/// characteristics and descriptors, and (only with `--read-standard`) reading standard SIG
/// characteristics in Device Information (0x180A) and Battery (0x180F).
/// Never done: writes, `setNotifyValue`, reads of vendor characteristics, touching 0x079C.
@MainActor
public final class BLEInspector: NSObject {
    private let options: InspectionOptions
    private let redactor: Redactor
    /// Classic addresses to mask inside advertisement payloads (set before `inspect()`).
    public var knownAddresses: [String] = []
    private var central: CBCentralManager?
    private(set) var state: CBManagerState = .unknown

    private struct Seen {
        let peripheral: CBPeripheral
        var paths: [String]
        var advertisement: ProbeReport.Advertisement?
    }
    private var seen: [UUID: Seen] = [:]
    private var nonCandidates: Set<UUID> = []
    private var scanning = false

    private enum ConnectionState { case pending, connected, failed(String), disconnected(String) }
    private var connection: [UUID: ConnectionState] = [:]
    /// Outstanding discovery/read callbacks per peripheral.
    private var outstanding: [UUID: Int] = [:]
    private var readResults: [ReadKey: ProbeReport.ReadValue] = [:]
    private struct ReadKey: Hashable { let peripheral: UUID; let characteristic: CBUUID }

    private static let standardReadServices: Set<CBUUID> = [CBUUID(string: "180A"), CBUUID(string: "180F")]
    private static let serialNumber = CBUUID(string: "2A25")
    private static let neverDiscover: Set<CBUUID> = [CBUUID(string: KnownUUIDs.opoExtended)]

    public init(options: InspectionOptions, redactor: Redactor) {
        self.options = options
        self.redactor = redactor
    }

    // MARK: Permission

    /// Creates the central manager (this triggers the macOS Bluetooth permission prompt on first run)
    /// and waits for it to leave the `.unknown`/`.resetting` states.
    public func start() async -> ProbeReport.Permissions {
        let clock = ContinuousClock()
        let started = clock.now
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        _ = await waitUntil(timeout: .seconds(options.permissionWaitSeconds)) {
            self.state != .unknown && self.state != .resetting && CBManager.authorization != .notDetermined
        }
        var permissions = ProbeReport.Permissions()
        permissions.bluetoothAuthorization = Self.describe(CBManager.authorization)
        permissions.centralManagerState = Self.describe(state)
        permissions.waitedSeconds = (clock.now - started).seconds
        return permissions
    }

    // MARK: Inspection

    public func inspect() async -> (ProbeReport.BLESection, [String]) {
        var section = ProbeReport.BLESection()
        var limitations = ["Core Bluetooth on macOS does not expose Bluetooth device addresses, so BLE peripherals can only be matched to classic devices by name."]
        guard let central, state == .poweredOn else {
            limitations.append("BLE inspection skipped: central manager state is \(Self.describe(state)), authorization \(Self.describe(CBManager.authorization)).")
            return (section, limitations)
        }

        // 1. Peripherals already connected to the Mac that expose a vendor service.
        let filter = KnownUUIDs.vendorServices.map { CBUUID(string: $0) }
        section.retrieveConnectedServiceFilter = KnownUUIDs.vendorServices
        for peripheral in central.retrieveConnectedPeripherals(withServices: filter) {
            seen[peripheral.identifier, default: Seen(peripheral: peripheral, paths: [])].paths.append("retrieveConnectedPeripherals")
        }

        // 2. Scan without a service filter: many buds do not advertise 0x079A (ProtocolSources §8).
        if options.scanSeconds > 0 {
            scanning = true
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            try? await Task.sleep(for: .seconds(options.scanSeconds))
            central.stopScan()
            scanning = false
            section.scanPerformed = true
        }
        section.nonCandidateAdvertiserCount = nonCandidates.count

        // 3. GATT discovery on candidates.
        var connections = 0
        for (id, entry) in seen.sorted(by: { ($0.value.peripheral.name ?? "") < ($1.value.peripheral.name ?? "") }) {
            let peripheral = entry.peripheral
            let name = peripheral.name ?? entry.advertisement?.localName
            let isCandidate = isCandidate(name: name, advertisement: entry.advertisement)
            var report = ProbeReport.Peripheral(name: isCandidate ? name : "<non-candidate peripheral>",
                                                identifier: redactor.identifier(id.uuidString),
                                                isCandidate: isCandidate, discoveryPaths: entry.paths)
            report.advertisement = isCandidate ? entry.advertisement : nil
            if isCandidate {
                if connections < options.maxGATTConnections {
                    connections += 1
                    report = await discover(peripheral, into: report, limitations: &limitations)
                } else {
                    report.connection = "skipped (connection limit \(options.maxGATTConnections))"
                }
            }
            section.peripherals.append(report)
        }
        if !section.peripherals.contains(where: \.isCandidate) {
            limitations.append("No candidate BLE peripheral was found. The buds may not expose BLE GATT to macOS while connected over classic Bluetooth, or may not advertise while in use.")
        }
        return (section, limitations)
    }

    private func isCandidate(name: String?, advertisement: ProbeReport.Advertisement?) -> Bool {
        if CandidateFilter.matches(name, pattern: options.namePattern) { return true }
        let advertised = (advertisement?.serviceUUIDs ?? []) + (advertisement?.overflowServiceUUIDs ?? [])
        return advertised.contains(KnownUUIDs.opoService) || advertised.contains(KnownUUIDs.opoLegacyService)
    }

    private func discover(_ peripheral: CBPeripheral, into report: ProbeReport.Peripheral,
                          limitations: inout [String]) async -> ProbeReport.Peripheral {
        guard let central else { return report }
        var report = report
        let id = peripheral.identifier
        peripheral.delegate = self
        connection[id] = .pending
        central.connect(peripheral, options: nil)
        let connected = await waitUntil(timeout: .seconds(15)) {
            if case .pending = self.connection[id] { return false }
            return true
        }
        switch connection[id] {
        case .connected?: break
        case .failed(let reason)?:
            report.connection = "failed: \(reason)"
            return report
        default:
            central.cancelPeripheralConnection(peripheral)
            report.connection = connected ? "disconnected during connect" : "timed out after 15 s"
            limitations.append("GATT connection to \(report.name ?? "candidate") did not complete.")
            return report
        }

        outstanding[id] = 1
        peripheral.discoverServices(nil)
        let complete = await waitUntil(timeout: .seconds(20)) { (self.outstanding[id] ?? 0) <= 0 }
        if !complete { limitations.append("GATT discovery on \(report.name ?? "candidate") did not finish within 20 s; partial results shown.") }

        if options.readStandard {
            await readStandardCharacteristics(of: peripheral)
        }

        report.connection = complete ? "connected; discovery complete" : "connected; discovery incomplete"
        if case .disconnected(let reason)? = connection[id] { report.connection += "; disconnected: \(reason)" }
        report.services = (peripheral.services ?? []).map { serviceReport($0, of: id) }
        central.cancelPeripheralConnection(peripheral)
        return report
    }

    private func readStandardCharacteristics(of peripheral: CBPeripheral) async {
        let id = peripheral.identifier
        let targets = (peripheral.services ?? [])
            .filter { Self.standardReadServices.contains($0.uuid) }
            .flatMap { $0.characteristics ?? [] }
            .filter { $0.properties.contains(.read) }
        guard !targets.isEmpty else { return }
        outstanding[id, default: 0] += targets.count
        targets.forEach(peripheral.readValue(for:))
        _ = await waitUntil(timeout: .seconds(10)) { (self.outstanding[id] ?? 0) <= 0 }
    }

    private func serviceReport(_ service: CBService, of peripheral: UUID) -> ProbeReport.GATTService {
        var result = ProbeReport.GATTService(uuid: Self.canonical(service.uuid), isPrimary: service.isPrimary)
        result.includedServiceUUIDs = (service.includedServices ?? []).map { Self.canonical($0.uuid) }
        result.characteristics = (service.characteristics ?? []).map { characteristic in
            var entry = ProbeReport.GATTCharacteristic(
                uuid: Self.canonical(characteristic.uuid),
                properties: GATTProperties.describe(rawValue: characteristic.properties.rawValue),
                rawProperties: characteristic.properties.rawValue,
                isNotifying: characteristic.isNotifying)
            entry.descriptorUUIDs = (characteristic.descriptors ?? []).map { Self.canonical($0.uuid) }
            entry.readValue = readResults[ReadKey(peripheral: peripheral, characteristic: characteristic.uuid)]
            return entry
        }
        return result
    }

    private func finishOne(_ peripheral: CBPeripheral) {
        outstanding[peripheral.identifier, default: 0] -= 1
    }

    // MARK: Helpers

    nonisolated static func canonical(_ uuid: CBUUID) -> String {
        BluetoothUUID.canonical(fromBytes: [UInt8](uuid.data)) ?? uuid.uuidString
    }

    nonisolated static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "poweredOff"
        case .poweredOn: "poweredOn"
        @unknown default: "unrecognised(\(state.rawValue))"
        }
    }

    nonisolated static func describe(_ authorization: CBManagerAuthorization) -> String {
        switch authorization {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .allowedAlways: "allowedAlways"
        @unknown default: "unrecognised(\(authorization.rawValue))"
        }
    }
}

// The central manager is created with `queue: .main`, so every callback arrives on the main actor.
extension BLEInspector: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning else { return }
        var ad = ProbeReport.Advertisement()
        ad.localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        ad.rssi = RSSI.intValue == 127 ? nil : RSSI.intValue
        ad.isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        ad.txPower = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        ad.serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(Self.canonical)
        ad.overflowServiceUUIDs = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []).map(Self.canonical)
        ad.solicitedServiceUUIDs = (advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? []).map(Self.canonical)
        ad.serviceDataUUIDs = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]).keys.map(Self.canonical).sorted()
        ad.manufacturerDataHex = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)
            .map { redactor.payloadHex([UInt8]($0), knownAddresses: knownAddresses) }

        let id = peripheral.identifier
        if isCandidate(name: peripheral.name ?? ad.localName, advertisement: ad) {
            nonCandidates.remove(id)
            var entry = seen[id] ?? Seen(peripheral: peripheral, paths: [])
            if !entry.paths.contains("scan") { entry.paths.append("scan") }
            entry.advertisement = ad
            seen[id] = entry
        } else if seen[id] == nil {
            // Neighbouring devices are only counted, never recorded.
            nonCandidates.insert(id)
        } else {
            seen[id]?.advertisement = ad
            if seen[id]?.paths.contains("scan") == false { seen[id]?.paths.append("scan") }
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connection[peripheral.identifier] = .connected
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connection[peripheral.identifier] = .failed(error?.localizedDescription ?? "unknown error")
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if case .pending? = connection[peripheral.identifier] {
            connection[peripheral.identifier] = .failed(error?.localizedDescription ?? "disconnected")
        } else if let error {
            connection[peripheral.identifier] = .disconnected(error.localizedDescription)
        }
    }
}

extension BLEInspector: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where !Self.neverDiscover.contains(service.uuid) {
            outstanding[peripheral.identifier, default: 0] += 2
            peripheral.discoverIncludedServices(nil, for: service)
            peripheral.discoverCharacteristics(nil, for: service)
        }
        finishOne(peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        finishOne(peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            outstanding[peripheral.identifier, default: 0] += 1
            peripheral.discoverDescriptors(for: characteristic)
        }
        finishOne(peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        finishOne(peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        defer { finishOne(peripheral) }
        // Only reads the probe itself requested reach here: no notifications are ever enabled.
        if let error {
            readResults[ReadKey(peripheral: peripheral.identifier, characteristic: characteristic.uuid)] = .init(hex: nil, utf8: nil, error: error.localizedDescription)
            return
        }
        let bytes = characteristic.value.map { [UInt8]($0) } ?? []
        var utf8 = String(bytes: bytes, encoding: .utf8).flatMap { $0.allSatisfy { !$0.isASCII || $0.isLetter || $0.isNumber || $0.isPunctuation || $0 == " " } ? $0 : nil }
        var hex: String? = Hex.string(bytes)
        if characteristic.uuid == Self.serialNumber, redactor.enabled {
            utf8 = utf8.map(redactor.serial)
            hex = nil
        }
        readResults[ReadKey(peripheral: peripheral.identifier, characteristic: characteristic.uuid)] = .init(hex: hex, utf8: utf8, error: nil)
    }
}
