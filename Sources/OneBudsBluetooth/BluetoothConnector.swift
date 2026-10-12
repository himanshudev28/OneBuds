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

        // 1. BLE peripherals already connected to the Mac.
        if let central, centralState == .poweredOn {
            let services = [DeviceRegistry.opoService, "00001107-D102-11E1-9B23-00025B00A5A5"].map { CBUUID(string: $0) }
            for peripheral in central.retrieveConnectedPeripherals(withServices: services) {
                guard let name = peripheral.name, Self.isCandidate(name) else { continue }
                add(name, path: "BLE connected peripheral", transport: .ble)
            }
        }

        // 2. Paired classic devices that are connected (never paged).
        var unidentified: [(name: String, address: String)] = []
        for device in (IOBluetoothDevice.pairedDevices() ?? []).compactMap({ $0 as? IOBluetoothDevice }) {
            guard device.isConnected(), let name = device.name, Self.isCandidate(name) else { continue }
            let cached = device.addressString.flatMap { knownProductIDs[Self.addressKey($0)] }
            add(name, path: "paired classic device", transport: .rfcomm, productID: cached)
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

        // Prefer models with a profile, then those allowing a control session.
        return found.values.sorted { lhs, rhs in
            let l = lhs.profile.map { $0.allowsControlSession ? 0 : 1 } ?? 2
            let r = rhs.profile.map { $0.allowsControlSession ? 0 : 1 } ?? 2
            return l != r ? l < r : lhs.name < rhs.name
        }
    }

    public func makeTransport(for earbuds: DiscoveredEarbuds, kind: TransportKind) -> (any EarbudTransport)? {
        guard let profile = earbuds.profile else { return nil }
        switch kind {
        case .rfcomm:
            guard let device = (IOBluetoothDevice.pairedDevices() ?? []).compactMap({ $0 as? IOBluetoothDevice })
                .first(where: { $0.name == earbuds.name && $0.isConnected() }) else { return nil }
            return RFCOMMTransport(device: device, serviceUUIDs: profile.rfcommServiceUUIDs.isEmpty ? [DeviceRegistry.opoService] : profile.rfcommServiceUUIDs)
        case .ble:
            guard let ble = profile.ble else { return nil }
            return BLETransport(target: .init(name: earbuds.name, serviceUUID: ble.serviceUUID, writeUUID: ble.writeUUID, notifyUUID: ble.notifyUUID))
        case .mock:
            return nil
        }
    }

    public func describe(_ transport: any EarbudTransport) -> String? {
        if let rfcomm = transport as? RFCOMMTransport { return rfcomm.channelDescription }
        if let ble = transport as? BLETransport { return ble.discoveryPath.map { "GATT 0x079A via \($0)" } }
        return nil
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
