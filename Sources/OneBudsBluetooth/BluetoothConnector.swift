import CoreBluetooth
import CryptoKit
import Foundation
import IOBluetooth
import OneBudsCore
import OneBudsDiagnostics
import os

/// Finds earbuds connected to this Mac and creates the matching transports.
///
/// Discovery order (connected buds often stop advertising):
/// 1. BLE peripherals already connected to the Mac exposing the vendor service;
/// 2. paired classic devices that are connected, matched by name;
/// 3. a short BLE scan, matching by name or OPPO manufacturer data, only if 1 and 2 found nothing.
/// Discovery never pages a disconnected device.
@MainActor
public final class BluetoothConnector: NSObject, DeviceConnector {
    public let isDemo = false
    private var central: CBCentralManager?
    private var centralState: CBManagerState = .unknown
    private var scanResults: [String: (productID: String?, path: String)] = [:]
    /// OPPO manufacturer-data payloads seen during the last scan.
    private var scannedManufacturerData: [Data] = []
    /// Product ids learned for renamed devices, keyed by a hash of the classic address (never the address).
    private var knownProductIDs: [String: String] = UserDefaults.standard.dictionary(forKey: "knownProductIDs") as? [String: String] ?? [:]
    private var scanning = false
    private var changeContinuations: [AsyncStream<Void>.Continuation] = []
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private let logger = Logger(subsystem: "com.local.onebuds", category: "discovery")

    /// OPPO's Bluetooth SIG company identifier (observed as the first manufacturer-data bytes).
    nonisolated static let oppoCompanyID: UInt16 = 0x079A

    public override init() {
        super.init()
    }

    // MARK: DeviceConnector

    public func availability() async -> BluetoothAvailability {
        let central = ensureCentral()
        _ = await waitUntil(timeout: .seconds(30)) {
            self.centralState != .unknown && self.centralState != .resetting && CBManager.authorization != .notDetermined
        }
        _ = central
        if CBManager.authorization == .denied || CBManager.authorization == .restricted { return .unauthorized }
        switch centralState {
        case .poweredOn: return .ready
        case .poweredOff: return .poweredOff
        case .unauthorized: return .unauthorized
        case .unsupported: return .unsupported
        default: return .unknown
        }
    }

    public func discover(thorough: Bool) async -> [DiscoveredEarbuds] {
        var found: [String: DiscoveredEarbuds] = [:]
        func add(_ name: String, path: String, transport: TransportKind, productID: String? = nil) {
            var entry = found[name] ?? DiscoveredEarbuds(name: name, discoveryPaths: [], transports: [])
            if !entry.discoveryPaths.contains(path) { entry.discoveryPaths.append(path) }
            if !entry.transports.contains(transport) { entry.transports.append(transport) }
            entry.productID = entry.productID ?? productID
            found[name] = entry
        }

        // 1. BLE peripherals already connected to the Mac that expose a known vendor GATT service
        //    (the service list comes from the device profiles). This is what marks GATT as offered.
        if let central, centralState == .poweredOn {
            let services = DeviceRegistry.bleServiceUUIDs.map { CBUUID(string: $0) }
            for peripheral in central.retrieveConnectedPeripherals(withServices: services) {
                guard let name = peripheral.name, Self.isCandidate(name) else { continue }
                add(name, path: "BLE connected peripheral (vendor GATT service)", transport: .ble)
            }
        }

        // 2. Paired classic devices that are connected (never paged).
        var unidentified: [(name: String, address: String)] = []
        for device in (IOBluetoothDevice.pairedDevices() ?? []).compactMap({ $0 as? IOBluetoothDevice }) {
            guard device.isConnected(), let name = device.name, Self.isCandidate(name) else { continue }
            let cached = device.addressString.flatMap { knownProductIDs[Self.addressKey($0)] }
            add(name, path: "paired classic device", transport: .rfcomm, productID: cached)
            // Cached SDP records only (no traffic): note whether a control service is already known.
            if let profile = DeviceRegistry.match(name: name, productID: cached), !profile.rfcommServiceUUIDs.isEmpty {
                let cachedRecord = profile.rfcommServiceUUIDs.contains { uuid in
                    ClassicInspector.sdpUUID(uuid).flatMap { device.getServiceRecord(for: $0) } != nil
                }
                found[name]?.discoveryPaths.append(cachedRecord ? "RFCOMM control service in SDP cache" : "RFCOMM service not cached yet (checked on connect)")
            }
            watchDisconnect(of: device)
            if DeviceRegistry.match(name: name, productID: cached) == nil, let address = device.addressString {
                unidentified.append((name, address))
            }
        }

        // 3. Short passive BLE scan when nothing was found, or when a connected device was renamed and
        //    must be identified from its advertisement (OPPO company id + product id + its classic
        //    address, observed on OnePlus Buds 3). Nothing is sent to the earbuds.
        if (found.isEmpty && thorough) || !unidentified.isEmpty, let central, centralState == .poweredOn {
            scanResults = [:]
            scannedManufacturerData = []
            scanning = true
            central.scanForPeripherals(withServices: nil, options: nil)
            try? await Task.sleep(for: .seconds(5))
            central.stopScan()
            scanning = false
            for (name, address) in unidentified {
                guard let productID = scannedManufacturerData.lazy.compactMap({ Self.productID(fromManufacturerData: $0, matchingAddress: address) }).first else { continue }
                found[name]?.productID = productID
                found[name]?.discoveryPaths.append("identified from BLE advertisement")
                knownProductIDs[Self.addressKey(address)] = productID
                UserDefaults.standard.set(knownProductIDs, forKey: "knownProductIDs")
            }
            if unidentified.isEmpty {
                for (name, result) in scanResults { add(name, path: result.path, transport: .ble, productID: result.productID) }
            }
        }

        Self.mergeRenamedBLEEntries(&found)
        if thorough { Self.offerGATTByAdvertisement(&found) }

        // Prefer models with a profile, then those allowing a control session.
        return found.values.sorted { lhs, rhs in
            let l = lhs.profile.map { $0.allowsControlSession ? 0 : 1 } ?? 2
            let r = rhs.profile.map { $0.allowsControlSession ? 0 : 1 } ?? 2
            return l != r ? l < r : lhs.name < rhs.name
        }
    }

    public func makeTransport(for earbuds: DiscoveredEarbuds, kind: TransportKind) -> (any EarbudTransport)? {
        guard let profile = earbuds.profile else { return nil }
        let classicDevice = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
            .first { $0.name == earbuds.name && $0.isConnected() }
        switch kind {
        case .rfcomm:
            // Only the profile's own SDP services; nothing is guessed for a model without them.
            guard let classicDevice, !profile.rfcommServiceUUIDs.isEmpty else { return nil }
            return RFCOMMTransport(device: classicDevice, serviceUUIDs: profile.rfcommServiceUUIDs)
        case .ble:
            guard let ble = profile.ble else { return nil }
            return BLETransport(target: .init(names: [earbuds.name] + earbuds.bleNames, serviceUUID: ble.serviceUUID, writeUUID: ble.writeUUID,
                                              notifyUUID: ble.notifyUUID, classicAddress: classicDevice?.addressString))
        case .mock:
            return nil
        }
    }

    public func describe(_ transport: any EarbudTransport) -> String? {
        if let rfcomm = transport as? RFCOMMTransport { return rfcomm.channelDescription }
        if let ble = transport as? BLETransport { return ble.channelDescription }
        return nil
    }

    public func isRouteAvailable(_ kind: TransportKind, for earbuds: DiscoveredEarbuds) -> Bool {
        guard let profile = earbuds.profile else { return false }
        switch kind {
        case .ble:
            // A BLE link to this Mac exposing the model's vendor service. Renamed devices use the
            // model name over BLE, hence the profile's names too.
            guard let central, centralState == .poweredOn, let ble = profile.ble else { return false }
            let names = Set([earbuds.name] + earbuds.bleNames + profile.bluetoothNames)
            return central.retrieveConnectedPeripherals(withServices: [CBUUID(string: ble.serviceUUID)])
                .contains { $0.name.map(names.contains) == true }
        case .rfcomm:
            guard !profile.rfcommServiceUUIDs.isEmpty else { return false }
            return (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
                .contains { $0.name == earbuds.name && $0.isConnected() }
        case .mock:
            return false
        }
    }

    public func deviceChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        changeContinuations.append(continuation)
        ensureCentral()
        if connectNotification == nil {
            connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        }
        return stream
    }

    // MARK: Helpers

    /// For a classic-connected device whose model has a GATT route that discovery did not see (the
    /// Mac holds no BLE link to it), still offer GATT on user-initiated connects. BLETransport then
    /// scans and accepts only an advertisement carrying this device's classic address; if none
    /// appears, the connect falls through to RFCOMM. Automatic reconnects skip this (no scanning).
    nonisolated static func offerGATTByAdvertisement(_ found: inout [String: DiscoveredEarbuds]) {
        for (name, entry) in found where entry.transports.contains(.rfcomm) && !entry.transports.contains(.ble) {
            guard let profile = entry.profile, profile.ble != nil, profile.transports.contains(.ble) else { continue }
            found[name]?.transports.append(.ble)
            found[name]?.discoveryPaths.append("GATT not seen yet (checked on connect by this device's advertisement)")
        }
    }

    /// A renamed classic device ("Alex's OnePlus Buds 3") still advertises the model name over BLE,
    /// so its GATT route shows up as a separate entry. Folds a BLE-only entry into the classic entry
    /// of the same model, but only when that pairing is unambiguous: exactly one classic entry and
    /// one BLE-only entry resolve to that profile. Core Bluetooth exposes no addresses (PhaseB L1),
    /// so anything less certain is left as found.
    nonisolated static func mergeRenamedBLEEntries(_ found: inout [String: DiscoveredEarbuds]) {
        let byProfile = Dictionary(grouping: found.values.filter { $0.profile != nil }) { $0.profile!.id }
        for (_, entries) in byProfile {
            let classic = entries.filter { $0.transports.contains(.rfcomm) }
            let bleOnly = entries.filter { $0.transports == [.ble] }
            guard classic.count == 1, bleOnly.count == 1, !classic[0].transports.contains(.ble), classic[0].bleNames.isEmpty,
                  var merged = found[classic[0].name] else { continue }
            let ble = bleOnly[0]
            merged.transports.append(.ble)
            merged.bleNames.append(ble.name)
            merged.discoveryPaths += ble.discoveryPaths.map { "\($0), same model as the classic device" }
            merged.productID = merged.productID ?? ble.productID
            found[classic[0].name] = merged
            found[ble.name] = nil
        }
    }

    /// Registry names first; otherwise the generic candidate filter (for unknown-model diagnostics).
    nonisolated static func isCandidate(_ name: String) -> Bool {
        DeviceRegistry.match(name: name) != nil || CandidateFilter.matches(name)
    }

    /// `9A 07 <product id, 3 bytes LE> …` (observed on OnePlus Buds 3; layout is a strong Hypothesis).
    nonisolated static func productID(fromManufacturerData data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count >= 5, UInt16(bytes[0]) | UInt16(bytes[1]) << 8 == oppoCompanyID else { return nil }
        return String(format: "%02X%02X%02X", bytes[4], bytes[3], bytes[2])
    }

    /// The product id from OPPO manufacturer data, only if the payload also carries `address`
    /// (in either byte order), which ties the advertisement to that classic device.
    nonisolated static func productID(fromManufacturerData data: Data, matchingAddress address: String) -> String? {
        guard let productID = productID(fromManufacturerData: data) else { return nil }
        let addressBytes = address.split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { UInt8($0, radix: 16) }
        guard addressBytes.count == 6 else { return nil }
        let bytes = [UInt8](data)
        for pattern in [addressBytes, Array(addressBytes.reversed())] where bytes.count >= 6 {
            for start in 0...(bytes.count - 6) where Array(bytes[start..<start + 6]) == pattern { return productID }
        }
        return nil
    }

    /// Stable, non-reversible key for an address (the address itself is never stored).
    nonisolated static func addressKey(_ address: String) -> String {
        let normalized = address.uppercased().filter(\.isHexDigit)
        return SHA256.hash(data: Data(("onebuds:" + normalized).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func ensureCentral() -> CBCentralManager {
        if let central { return central }
        let central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        self.central = central
        return central
    }

    private func notifyChange() {
        changeContinuations.forEach { $0.yield() }
    }

    private func watchDisconnect(of device: IOBluetoothDevice) {
        guard let address = device.addressString, disconnectNotifications[address] == nil else { return }
        // Disconnect notifications are one-shot per connection; re-armed on each discovery.
        disconnectNotifications[address] = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
    }

    @objc private nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name
        Self.onMain { [weak self] in
            guard let self, let name, Self.isCandidate(name) else { return }
            self.logger.info("Candidate connected")
            self.notifyChange()
        }
    }

    @objc private nonisolated func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString
        Self.onMain { [weak self] in
            guard let self else { return }
            if let address { self.disconnectNotifications[address]?.unregister(); self.disconnectNotifications[address] = nil }
            self.notifyChange()
        }
    }

    private nonisolated static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated(body) } else { DispatchQueue.main.async { MainActor.assumeIsolated(body) } }
    }
}

extension BluetoothConnector: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let previous = centralState
        centralState = central.state
        if previous != .unknown, previous != central.state { notifyChange() }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning else { return }
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let productID = manufacturerData.flatMap(Self.productID(fromManufacturerData:))
        if let manufacturerData, productID != nil { scannedManufacturerData.append(manufacturerData) }
        guard let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String else { return }
        guard Self.isCandidate(name) || productID != nil else { return }
        if scanResults[name]?.productID == nil { scanResults[name] = (productID, "BLE scan") }
    }
}
