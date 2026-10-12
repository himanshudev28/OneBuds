import Foundation

/// Everything the Phase B probe observed. Every field is an observation from macOS APIs;
/// interpretation (labels from ``KnownUUIDs``) is added only when rendering.
public struct ProbeReport: Sendable, Codable {
    public var tool = "onebuds-probe"
    public var toolVersion: String
    public var generatedAt: Date
    public var macOSVersion: String
    public var options: Options
    public var permissions = Permissions()
    public var classic = ClassicSection()
    public var ble = BLESection()
    /// API or permission limitations encountered during this run.
    public var limitations: [String] = []

    public init(toolVersion: String, generatedAt: Date, macOSVersion: String, options: Options) {
        self.toolVersion = toolVersion
        self.generatedAt = generatedAt
        self.macOSVersion = macOSVersion
        self.options = options
    }

    public struct Options: Sendable, Codable {
        public var scanSeconds: Int
        public var sdpRefresh: Bool
        public var readStandardCharacteristics: Bool
        public var redact: Bool
        public var namePattern: String
        public init(scanSeconds: Int, sdpRefresh: Bool, readStandardCharacteristics: Bool, redact: Bool, namePattern: String) {
            self.scanSeconds = scanSeconds
            self.sdpRefresh = sdpRefresh
            self.readStandardCharacteristics = readStandardCharacteristics
            self.redact = redact
            self.namePattern = namePattern
        }
    }

    public struct Permissions: Sendable, Codable {
        public var bluetoothAuthorization = "notChecked"
        public var centralManagerState = "notChecked"
        public var waitedSeconds = 0.0
        public init() {}
    }

    // MARK: Classic (IOBluetooth)

    public struct ClassicSection: Sendable, Codable {
        public var pairedDeviceCount = 0
        public var devices: [ClassicDevice] = []
        public init() {}
    }

    public struct ClassicDevice: Sendable, Codable {
        public var name: String?
        public var address: String?
        public var isCandidate: Bool
        public var isConnected: Bool
        public var isPaired: Bool
        public var classOfDevice: UInt32
        public var majorClass: UInt32
        public var minorClass: UInt32
        public var sdpRefresh: SDPRefresh?
        public var lastServicesUpdate: Date?
        public var services: [SDPRecord] = []
        /// Explicit `getServiceRecord(for:)` lookups of the vendor service UUIDs.
        public var vendorLookups: [VendorLookup] = []

        public init(name: String?, address: String?, isCandidate: Bool, isConnected: Bool, isPaired: Bool,
                    classOfDevice: UInt32, majorClass: UInt32, minorClass: UInt32) {
            self.name = name
            self.address = address
            self.isCandidate = isCandidate
            self.isConnected = isConnected
            self.isPaired = isPaired
            self.classOfDevice = classOfDevice
            self.majorClass = majorClass
            self.minorClass = minorClass
        }
    }

    public struct SDPRefresh: Sendable, Codable {
        public var attempted: Bool
        public var outcome: String
        public var seconds: Double
        public init(attempted: Bool, outcome: String, seconds: Double) {
            self.attempted = attempted
            self.outcome = outcome
            self.seconds = seconds
        }
    }

    public struct SDPRecord: Sendable, Codable {
        public var serviceName: String?
        public var serviceClassUUIDs: [String]
        /// From `IOBluetoothSDPServiceRecord.getRFCOMMChannelID`.
        public var rfcommChannelAPI: UInt8?
        /// Parsed from the ProtocolDescriptorList attribute, as a cross-check.
        public var rfcommChannelParsed: UInt8?
        public var l2capPSM: UInt16?
        public var attributes: [SDPAttribute]

        public init(serviceName: String?, serviceClassUUIDs: [String], rfcommChannelAPI: UInt8?,
                    rfcommChannelParsed: UInt8?, l2capPSM: UInt16?, attributes: [SDPAttribute]) {
            self.serviceName = serviceName
            self.serviceClassUUIDs = serviceClassUUIDs
            self.rfcommChannelAPI = rfcommChannelAPI
            self.rfcommChannelParsed = rfcommChannelParsed
            self.l2capPSM = l2capPSM
            self.attributes = attributes
        }
    }

    public struct SDPAttribute: Sendable, Codable {
        public var id: UInt16
        public var value: SDPValue
        public init(id: UInt16, value: SDPValue) {
            self.id = id
            self.value = value
        }
    }

    public struct VendorLookup: Sendable, Codable {
        public var uuid: String
        public var found: Bool
        public var rfcommChannel: UInt8?
        public var serviceName: String?
        public init(uuid: String, found: Bool, rfcommChannel: UInt8?, serviceName: String?) {
            self.uuid = uuid
            self.found = found
            self.rfcommChannel = rfcommChannel
            self.serviceName = serviceName
        }
    }

    // MARK: BLE (Core Bluetooth)

    public struct BLESection: Sendable, Codable {
        public var retrieveConnectedServiceFilter: [String] = []
        public var scanPerformed = false
        /// Advertisers seen during the scan that did not match the filter. Not listed, for privacy.
        public var nonCandidateAdvertiserCount = 0
        public var peripherals: [Peripheral] = []
        public init() {}
    }

    public struct Peripheral: Sendable, Codable {
        public var name: String?
        public var identifier: String
        public var isCandidate: Bool
        /// "retrieveConnectedPeripherals" and/or "scan".
        public var discoveryPaths: [String]
        public var advertisement: Advertisement?
        public var connection: String = "notAttempted"
        public var services: [GATTService] = []
        public init(name: String?, identifier: String, isCandidate: Bool, discoveryPaths: [String]) {
            self.name = name
            self.identifier = identifier
            self.isCandidate = isCandidate
            self.discoveryPaths = discoveryPaths
        }
    }

    public struct Advertisement: Sendable, Codable {
        public var localName: String?
        public var rssi: Int?
        public var isConnectable: Bool?
        public var txPower: Int?
        public var serviceUUIDs: [String] = []
        public var overflowServiceUUIDs: [String] = []
        public var solicitedServiceUUIDs: [String] = []
        public var serviceDataUUIDs: [String] = []
        public var manufacturerDataHex: String?
        public init() {}
    }

    public struct GATTService: Sendable, Codable {
        public var uuid: String
        public var isPrimary: Bool
        public var includedServiceUUIDs: [String] = []
        public var characteristics: [GATTCharacteristic] = []
        public init(uuid: String, isPrimary: Bool) {
            self.uuid = uuid
            self.isPrimary = isPrimary
        }
    }

    public struct GATTCharacteristic: Sendable, Codable {
        public var uuid: String
        public var properties: [String]
        public var rawProperties: UInt
        public var isNotifying: Bool
        public var descriptorUUIDs: [String] = []
        /// Only filled for standard SIG characteristics when `--read-standard` is given.
        public var readValue: ReadValue?
        public init(uuid: String, properties: [String], rawProperties: UInt, isNotifying: Bool) {
            self.uuid = uuid
            self.properties = properties
            self.rawProperties = rawProperties
            self.isNotifying = isNotifying
        }
    }

    public struct ReadValue: Sendable, Codable {
        public var hex: String?
        public var utf8: String?
        public var error: String?
        public init(hex: String?, utf8: String?, error: String?) {
            self.hex = hex
            self.utf8 = utf8
            self.error = error
        }
    }
}
