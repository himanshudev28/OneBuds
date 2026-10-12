import CoreBluetooth
import Foundation
import OneBudsCore
import os

/// Bluetooth LE transport: OPO frames written to the write characteristic and received as
/// notifications on the notify characteristic of the vendor GATT service (ProtocolSources §3,
/// observed on OnePlus Buds 3 in PhaseB-Report §4.3).
///
/// The central uses the main queue, so all Core Bluetooth objects stay on the main actor.
@MainActor
public final class BLETransport: NSObject, EarbudTransport {
    public struct Target: Sendable {
        public var name: String
        public var serviceUUID: String
        public var writeUUID: String
        public var notifyUUID: String
        public init(name: String, serviceUUID: String, writeUUID: String, notifyUUID: String) {
            self.name = name
            self.serviceUUID = serviceUUID
            self.writeUUID = writeUUID
            self.notifyUUID = notifyUUID
        }
    }

    public nonisolated let kind = TransportKind.ble
    public nonisolated let incoming: AsyncStream<Data>
    public nonisolated let state: AsyncStream<TransportState>
    private let incomingContinuation: AsyncStream<Data>.Continuation
    private let stateContinuation: AsyncStream<TransportState>.Continuation

    private let target: Target
    private var central: CBCentralManager?
    private var centralState: CBManagerState = .unknown
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var scanned: CBPeripheral?
    private var connectResult: Result<Void, TransportError>?
    private var discoveryDone = false
    private var used = false
    private var finished = false
    private let logger = Logger(subsystem: "com.local.onebuds", category: "ble")

    /// How the peripheral was found: `retrieveConnectedPeripherals` or `scan`.
    public private(set) var discoveryPath: String?

    public init(target: Target) {
        self.target = target
        (incoming, incomingContinuation) = AsyncStream.makeStream(of: Data.self)
        (state, stateContinuation) = AsyncStream.makeStream(of: TransportState.self)
        super.init()
    }

    public func connect() async throws {
        guard !used else { throw TransportError.alreadyUsed }
        used = true
        stateContinuation.yield(.connecting)
        do {
            let central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            self.central = central
            _ = await waitUntil(timeout: .seconds(10)) { self.centralState != .unknown && self.centralState != .resetting }
            guard centralState == .poweredOn else {
                throw TransportError.bluetoothUnavailable(centralState == .unauthorized ? "permission denied" : "state \(centralState.rawValue)")
            }
            let peripheral = try await findPeripheral(central)
            self.peripheral = peripheral
            peripheral.delegate = self

            central.connect(peripheral, options: nil)
            guard await waitUntil(timeout: .seconds(15), { self.connectResult != nil }) else {
                central.cancelPeripheralConnection(peripheral)
                throw TransportError.timeout("BLE connection")
            }
            if case .failure(let error)? = connectResult { throw error }

            peripheral.discoverServices([CBUUID(string: target.serviceUUID)])
            guard await waitUntil(timeout: .seconds(15), { self.discoveryDone }) else {
                throw TransportError.timeout("GATT discovery")
            }
            guard let notify = notifyCharacteristic, writeCharacteristic != nil else {
                throw TransportError.serviceNotFound(target.serviceUUID)
            }
            peripheral.setNotifyValue(true, for: notify)
            guard await waitUntil(timeout: .seconds(5), { notify.isNotifying }) else {
                throw TransportError.timeout("enabling notifications")
            }
            stateContinuation.yield(.connected)
        } catch {
            teardown()
            finish(.failed(error.localizedDescription))
            throw error
        }
    }

    public func disconnect() async {
        teardown()
        finish(.disconnected(reason: "closed by OneBuds"))
    }

    public func send(_ frame: Data) async throws {
        guard let peripheral, peripheral.state == .connected, let write = writeCharacteristic else {
            throw TransportError.notConnected
        }
        if write.properties.contains(.writeWithoutResponse) {
            _ = await waitUntil(timeout: .seconds(2)) { peripheral.canSendWriteWithoutResponse }
            peripheral.writeValue(frame, for: write, type: .withoutResponse)
        } else {
            peripheral.writeValue(frame, for: write, type: .withResponse)
        }
    }

    // MARK: Steps

    private func findPeripheral(_ central: CBCentralManager) async throws -> CBPeripheral {
        let service = CBUUID(string: target.serviceUUID)
        if let connected = central.retrieveConnectedPeripherals(withServices: [service]).first(where: { $0.name == target.name }) {
            discoveryPath = "retrieveConnectedPeripherals"
            return connected
        }
        // Many buds do not advertise the vendor service, so scan unfiltered and match by name.
        central.scanForPeripherals(withServices: nil, options: nil)
        let found = await waitUntil(timeout: .seconds(10)) { self.scanned != nil }
        central.stopScan()
        guard found, let scanned else { throw TransportError.deviceNotFound }
        discoveryPath = "scan"
        return scanned
    }

    private func teardown() {
        if let peripheral, let central {
            if let notify = notifyCharacteristic, notify.isNotifying, peripheral.state == .connected {
                peripheral.setNotifyValue(false, for: notify)
            }
            central.cancelPeripheralConnection(peripheral)
        }
        central?.stopScan()
    }

    private func finish(_ final: TransportState) {
        guard !finished else { return }
        finished = true
        stateContinuation.yield(final)
        stateContinuation.finish()
        incomingContinuation.finish()
    }
}

extension BLETransport: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        centralState = central.state
        if central.state != .poweredOn, peripheral != nil, !finished {
            finish(.disconnected(reason: "Bluetooth turned off"))
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if scanned == nil, name == target.name { scanned = peripheral }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectResult = .success(())
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectResult = .failure(.openFailed(error?.localizedDescription ?? "connection failed"))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectResult == nil { connectResult = .failure(.openFailed(error?.localizedDescription ?? "disconnected")) }
        finish(.disconnected(reason: error?.localizedDescription ?? "disconnected by the earbuds"))
    }
}

extension BLETransport: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: target.serviceUUID) }) else {
            discoveryDone = true
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: target.writeUUID), CBUUID(string: target.notifyUUID)], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == CBUUID(string: target.writeUUID) { writeCharacteristic = characteristic }
            if characteristic.uuid == CBUUID(string: target.notifyUUID) { notifyCharacteristic = characteristic }
        }
        discoveryDone = true
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == CBUUID(string: target.notifyUUID), let value = characteristic.value, error == nil, !finished else { return }
        incomingContinuation.yield(value)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { logger.error("Notify state error: \(error.localizedDescription, privacy: .public)") }
    }
}
