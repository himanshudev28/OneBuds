import CoreBluetooth
import Foundation
import OneBudsCore
import os

/// Bluetooth LE transport: OPO frames written to the write characteristic and received as
/// notifications on the notify characteristic of the vendor GATT service (ProtocolSources §3,
/// observed on OnePlus Buds 3 in PhaseB-Report §4.3). The UUIDs come from the model's profile.
///
/// Buds 3 shows two BLE peripherals with the same name (PhaseB-Report §4.3), so every matching
/// peripheral is tried in turn until one actually offers the vendor service with a writable and a
/// notifying characteristic. Nothing is assumed about a peripheral before its GATT table is read.
///
/// The central uses the main queue, so all Core Bluetooth objects stay on the main actor.
@MainActor
public final class BLETransport: NSObject, EarbudTransport {
    public struct Target: Sendable {
        /// Names the peripheral may use: the classic name and any BLE name seen at discovery.
        public var names: [String]
        public var name: String { names.first ?? "" }
        public var serviceUUID: String
        public var writeUUID: String
        public var notifyUUID: String
        /// The classic address of the same earbuds, when known: a scanned advertisement that carries
        /// it is preferred over a name-only match. Never logged or stored.
        public var classicAddress: String?
        public init(name: String, serviceUUID: String, writeUUID: String, notifyUUID: String, classicAddress: String? = nil) {
            self.init(names: [name], serviceUUID: serviceUUID, writeUUID: writeUUID, notifyUUID: notifyUUID, classicAddress: classicAddress)
        }

        public init(names: [String], serviceUUID: String, writeUUID: String, notifyUUID: String, classicAddress: String? = nil) {
            self.names = names
            self.serviceUUID = serviceUUID
            self.writeUUID = writeUUID
            self.notifyUUID = notifyUUID
            self.classicAddress = classicAddress
        }
    }

    /// How one frame is written: the write type and the largest chunk per write.
    enum WriteMode: Equatable {
        case withResponse, withoutResponse
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
    /// Scan matches in the order seen; address matches are moved to the front.
    private var scanned: [CBPeripheral] = []
    private var connectResult: Result<Void, TransportError>?
    private var discoveryDone = false
    private var notifyError: String?
    /// With-response writes awaiting `didWriteValueFor`, oldest first (Core Bluetooth answers in order).
    private var pendingWrites: [Int] = []
    private var completedWrites: [Int: String?] = [:]
    private var nextWriteID = 0
    private var used = false
    /// True from a successful `connect()` until the link ends; disconnects before that only reject
    /// the candidate being checked.
    private var isOpen = false
    private var sendInProgress = false
    /// Scanned peripherals whose advertisement carries the target's classic address.
    private var addressMatched: Set<UUID> = []
    private var finished = false
    private let logger = Logger(subsystem: "com.local.onebuds", category: "ble")

    /// How the peripheral was found: `retrieveConnectedPeripherals` or `scan`.
    public private(set) var discoveryPath: String?

    /// Human-readable channel details for diagnostics, e.g. `GATT service 0000079A… via scan`.
    public var channelDescription: String? {
        discoveryPath.map { "GATT service \(target.serviceUUID.prefix(8))… via \($0)" }
    }

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
            var lastError: Error = TransportError.deviceNotFound
            for (candidate, path) in await candidates(central) {
                do {
                    try await open(candidate, central: central)
                    // Bluetooth may have turned off while this candidate was being opened.
                    guard !finished else { throw TransportError.bluetoothUnavailable("Bluetooth turned off") }
                    isOpen = true
                    discoveryPath = path
                    stateContinuation.yield(.connected)
                    return
                } catch {
                    logger.notice("GATT candidate via \(path, privacy: .public) rejected: \(error.localizedDescription, privacy: .public)")
                    lastError = error
                    detach(from: central)
                }
            }
            throw lastError
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
        // One frame at a time, so the chunks of two frames can never interleave across suspensions.
        if sendInProgress {
            guard await waitUntil(timeout: .seconds(10), { !self.sendInProgress || self.finished }), !finished else {
                throw finished ? TransportError.notConnected : TransportError.writeFailed("previous write still pending")
            }
        }
        sendInProgress = true
        defer { sendInProgress = false }
        guard let peripheral, peripheral.state == .connected, let characteristic = writeCharacteristic else {
            throw TransportError.notConnected
        }
        let (mode, chunkSize) = Self.writePlan(
            length: frame.count,
            withoutResponse: characteristic.properties.contains(.writeWithoutResponse),
            withResponse: characteristic.properties.contains(.write),
            maxWithoutResponse: peripheral.maximumWriteValueLength(for: .withoutResponse),
            maxWithResponse: peripheral.maximumWriteValueLength(for: .withResponse))
        if chunkSize < frame.count {
            // Splitting is only a last resort: the OPO decoder reassembles split notifications, but
            // whether the earbuds reassemble split writes is not documented.
            logger.notice("Frame of \(frame.count) bytes split into \(chunkSize)-byte GATT writes")
        }
        var offset = frame.startIndex
        while offset < frame.endIndex {
            let end = frame.index(offset, offsetBy: chunkSize, limitedBy: frame.endIndex) ?? frame.endIndex
            try await write(Data(frame[offset..<end]), to: characteristic, on: peripheral, mode: mode)
            offset = end
        }
    }

    /// Picks the write type and chunk size for a frame. Prefers write-without-response when the frame
    /// fits; otherwise a with-response write (Core Bluetooth performs long writes itself); splits
    /// only when neither fits.
    nonisolated static func writePlan(length: Int, withoutResponse: Bool, withResponse: Bool,
                                      maxWithoutResponse: Int, maxWithResponse: Int) -> (WriteMode, Int) {
        let length = max(1, length)
        if withoutResponse, length <= maxWithoutResponse { return (.withoutResponse, length) }
        if withResponse { return (.withResponse, min(length, max(1, maxWithResponse))) }
        return (.withoutResponse, min(length, max(1, maxWithoutResponse)))
    }

    /// A readable message for a GATT error, naming the pairing case explicitly.
    nonisolated static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == CBATTErrorDomain,
           [CBATTError.insufficientAuthentication.rawValue, CBATTError.insufficientEncryption.rawValue,
            CBATTError.insufficientEncryptionKeySize.rawValue].contains(nsError.code) {
            return "the earbuds require Bluetooth LE pairing for this channel"
        }
        return error.localizedDescription
    }

    // MARK: Steps

    /// Peripherals that may be the earbuds: already-connected ones exposing the service first, then a
    /// short scan. When the classic address is known, a scanned peripheral counts only if its
    /// advertisement carries that address, so same-model earbuds nearby are never tried; name-only
    /// scan matches are used only for earbuds with no classic link to this Mac.
    private func candidates(_ central: CBCentralManager) async -> [(CBPeripheral, String)] {
        let service = CBUUID(string: target.serviceUUID)
        var result: [(CBPeripheral, String)] = central.retrieveConnectedPeripherals(withServices: [service])
            .filter { $0.name.map(target.names.contains) == true }
            .map { ($0, "retrieveConnectedPeripherals") }
        // Many buds do not advertise the vendor service, so scan unfiltered and match by name or by
        // the classic address inside OPPO manufacturer data. Keep listening briefly after the first
        // match so a second peripheral with the same name is also found.
        central.scanForPeripherals(withServices: nil, options: nil)
        let found = await waitUntil(timeout: .seconds(result.isEmpty ? 6 : 2)) { !self.scanned.isEmpty }
        if found { try? await Task.sleep(for: .milliseconds(1500)) }
        central.stopScan()
        let strict = target.classicAddress != nil
        for peripheral in scanned where !result.contains(where: { $0.0.identifier == peripheral.identifier }) {
            if strict, !addressMatched.contains(peripheral.identifier) { continue }
            result.append((peripheral, strict ? "scan (advertisement carries this device's address)" : "scan (name match)"))
        }
        return result
    }

    /// Connects, discovers the vendor service, checks the characteristics' properties and enables
    /// notifications. Throws if this peripheral is not a usable control channel.
    private func open(_ candidate: CBPeripheral, central: CBCentralManager) async throws {
        peripheral = candidate
        candidate.delegate = self
        connectResult = nil
        discoveryDone = false
        notifyError = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil

        // Even a peripheral the system already has connected needs this central's own connect.
        central.connect(candidate, options: nil)
        guard await waitUntil(timeout: .seconds(10), { self.connectResult != nil }) else {
            throw TransportError.timeout("BLE connection")
        }
        if case .failure(let error)? = connectResult { throw error }

        candidate.discoverServices([CBUUID(string: target.serviceUUID)])
        guard await waitUntil(timeout: .seconds(10), { self.discoveryDone }) else {
            throw TransportError.timeout("GATT discovery")
        }
        guard candidate.state == .connected else { throw TransportError.openFailed("disconnected during GATT discovery") }
        guard let write = writeCharacteristic, let notify = notifyCharacteristic else {
            throw TransportError.serviceNotFound(target.serviceUUID)
        }
        guard !write.properties.isDisjoint(with: [.write, .writeWithoutResponse]) else {
            throw TransportError.openFailed("characteristic \(target.writeUUID) is not writable")
        }
        guard !notify.properties.isDisjoint(with: [.notify, .indicate]) else {
            throw TransportError.openFailed("characteristic \(target.notifyUUID) does not notify")
        }
        candidate.setNotifyValue(true, for: notify)
        guard await waitUntil(timeout: .seconds(5), { notify.isNotifying || self.notifyError != nil }) else {
            throw TransportError.timeout("enabling notifications")
        }
        if let notifyError, !notify.isNotifying { throw TransportError.openFailed("enabling notifications: \(notifyError)") }
    }

    private func write(_ chunk: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral, mode: WriteMode) async throws {
        switch mode {
        case .withoutResponse:
            if !peripheral.canSendWriteWithoutResponse {
                // Writing while the queue is full would be silently dropped by Core Bluetooth.
                guard await waitUntil(timeout: .seconds(2), { peripheral.canSendWriteWithoutResponse }) else {
                    throw TransportError.writeFailed("the Bluetooth LE write queue stayed full")
                }
            }
            guard peripheral.state == .connected else { throw TransportError.notConnected }
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
        case .withResponse:
            let id = nextWriteID
            nextWriteID += 1
            pendingWrites.append(id)
            peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
            let answered = await waitUntil(timeout: .seconds(5)) { self.completedWrites[id] != nil || self.finished }
            let failure = completedWrites.removeValue(forKey: id)
            guard !finished else { throw TransportError.notConnected }
            guard answered else {
                // Confirmations pair with writes by order, so a missing one makes every later one
                // ambiguous. Treat it as a broken link: the manager reconnects with a fresh transport.
                logger.error("GATT write not confirmed within 5 s; closing the link")
                teardown()
                finish(.disconnected(reason: "a write was not confirmed by the earbuds"))
                throw TransportError.writeFailed("no write confirmation from the earbuds")
            }
            if let message = failure ?? nil { throw TransportError.writeFailed(message) }
        }
    }

    /// Drops a rejected candidate so the next one starts clean.
    private func detach(from central: CBCentralManager) {
        if let peripheral {
            peripheral.delegate = nil
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
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

    /// True when a scanned advertisement carries the target's classic address (either byte order).
    private func advertisesTargetAddress(_ advertisementData: [String: Any]) -> Bool {
        guard let address = target.classicAddress,
              let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return false }
        return BluetoothConnector.productID(fromManufacturerData: data, matchingAddress: address) != nil
    }

    /// True once a session is running on `peripheral` (rejected candidates are ignored).
    private func isActive(_ peripheral: CBPeripheral) -> Bool {
        self.peripheral?.identifier == peripheral.identifier
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
        guard !scanned.contains(where: { $0.identifier == peripheral.identifier }) else { return }
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if advertisesTargetAddress(advertisementData) {
            addressMatched.insert(peripheral.identifier)
            scanned.insert(peripheral, at: 0)
        } else if let name, target.names.contains(name) {
            scanned.append(peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isActive(peripheral) else { return }
        connectResult = .success(())
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard isActive(peripheral) else { return }
        connectResult = .failure(.openFailed(error.map(Self.describe) ?? "connection failed"))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard isActive(peripheral) else { return }
        if connectResult == nil { connectResult = .failure(.openFailed(error.map(Self.describe) ?? "disconnected")) }
        discoveryDone = true
        // While candidates are still being checked, a drop only fails that candidate.
        guard isOpen else { return }
        isOpen = false
        finish(.disconnected(reason: error.map(Self.describe) ?? "disconnected by the earbuds"))
    }
}

extension BLETransport: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard isActive(peripheral) else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: target.serviceUUID) }) else {
            discoveryDone = true
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: target.writeUUID), CBUUID(string: target.notifyUUID)], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard isActive(peripheral) else { return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == CBUUID(string: target.writeUUID) { writeCharacteristic = characteristic }
            if characteristic.uuid == CBUUID(string: target.notifyUUID) { notifyCharacteristic = characteristic }
        }
        discoveryDone = true
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard isActive(peripheral), characteristic.uuid == CBUUID(string: target.notifyUUID),
              let value = characteristic.value, error == nil, !finished else { return }
        incomingContinuation.yield(value)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard isActive(peripheral), let error else { return }
        notifyError = Self.describe(error)
        logger.error("Notify state error: \(error.localizedDescription, privacy: .public)")
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard isActive(peripheral), !pendingWrites.isEmpty else { return }
        let id = pendingWrites.removeFirst()
        completedWrites[id] = .some(error.map(Self.describe))
    }
}
