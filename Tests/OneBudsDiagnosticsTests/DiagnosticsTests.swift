import Foundation
import Testing
@testable import OneBudsDiagnostics

@Suite struct BluetoothUUIDTests {
    @Test func expands16BitUUIDsOntoTheBaseUUID() {
        #expect(BluetoothUUID.canonical(fromBytes: [0xFE, 0x2C]) == "0000FE2C-0000-1000-8000-00805F9B34FB")
    }

    @Test func expands32BitUUIDs() {
        #expect(BluetoothUUID.canonical(fromBytes: [0x00, 0x00, 0x11, 0x01]) == KnownUUIDs.serialPort)
    }

    @Test func formats128BitUUIDs() {
        let bytes = Hex.bytes("0000079AD10211E19B2300025B00A5A5")!
        #expect(BluetoothUUID.canonical(fromBytes: bytes) == KnownUUIDs.opoService)
    }

    @Test func rejectsOtherLengths() {
        #expect(BluetoothUUID.canonical(fromBytes: [0x01, 0x02, 0x03]) == nil)
        #expect(BluetoothUUID.canonical(fromBytes: []) == nil)
    }

    @Test func canonicalisesStrings() {
        #expect(BluetoothUUID.canonical(fromString: "fe2c") == KnownUUIDs.fastPair)
        #expect(BluetoothUUID.canonical(fromString: "0100079a-d102-11e1-9b23-00025b00a5a5") == KnownUUIDs.opoWrite)
        #expect(BluetoothUUID.canonical(fromString: "xyz") == nil)
    }

    @Test func shortFormOnlyForBaseUUIDs() {
        #expect(BluetoothUUID.shortForm(KnownUUIDs.fastPair) == "FE2C")
        #expect(BluetoothUUID.shortForm(KnownUUIDs.opoService) == nil)
    }

    @Test func hexRoundTrip() {
        #expect(Hex.string([0xAA, 0x07, 0x00]) == "AA 07 00")
        #expect(Hex.bytes("AA 07 00") == [0xAA, 0x07, 0x00])
        #expect(Hex.bytes("ABC") == nil)
        #expect(Hex.bytes("ZZ") == nil)
    }
}

@Suite struct KnownUUIDTests {
    @Test func vendorServicesAreKnownAndCanonical() {
        for uuid in KnownUUIDs.vendorServices {
            #expect(KnownUUIDs.lookup(uuid) != nil)
            #expect(BluetoothUUID.canonical(fromString: uuid) == uuid)
        }
    }

    @Test func lookupIsCaseInsensitive() {
        #expect(KnownUUIDs.lookup(KnownUUIDs.opoNotify.lowercased())?.isVendorControl == true)
    }

    @Test func noDuplicateEntries() {
        #expect(Set(KnownUUIDs.all.map(\.uuid)).count == KnownUUIDs.all.count)
    }
}

@Suite struct SDPParsingTests {
    let rfcomm = BluetoothUUID.canonical(fromBytes: [0x00, 0x03])!
    let l2cap = BluetoothUUID.canonical(fromBytes: [0x01, 0x00])!

    @Test func extractsRFCOMMChannel() {
        let list = SDPValue.sequence([
            .sequence([.uuid(l2cap)]),
            .sequence([.uuid(rfcomm), .unsignedInt(15, bytes: 1)]),
        ])
        #expect(SDPParsing.rfcommChannel(fromProtocolDescriptorList: list) == 15)
        #expect(SDPParsing.l2capPSM(fromProtocolDescriptorList: list) == nil)
    }

    @Test func noRFCOMMChannelForL2CAPOnlyServices() {
        let avdtp = BluetoothUUID.canonical(fromBytes: [0x00, 0x19])!
        let list = SDPValue.sequence([
            .sequence([.uuid(l2cap), .unsignedInt(0x0019, bytes: 2)]),
            .sequence([.uuid(avdtp), .unsignedInt(0x0103, bytes: 2)]),
        ])
        #expect(SDPParsing.rfcommChannel(fromProtocolDescriptorList: list) == nil)
        #expect(SDPParsing.l2capPSM(fromProtocolDescriptorList: list) == 0x0019)
    }

    @Test func malformedDescriptorListsYieldNil() {
        #expect(SDPParsing.rfcommChannel(fromProtocolDescriptorList: nil) == nil)
        #expect(SDPParsing.rfcommChannel(fromProtocolDescriptorList: .string("x")) == nil)
        #expect(SDPParsing.rfcommChannel(fromProtocolDescriptorList: .sequence([.sequence([.uuid(rfcomm)])])) == nil)
        #expect(SDPParsing.rfcommChannel(fromProtocolDescriptorList: .sequence([.sequence([.uuid(rfcomm), .unsignedInt(300, bytes: 2)])])) == nil)
    }

    @Test func serviceClassList() {
        let value = SDPValue.sequence([.uuid(KnownUUIDs.opoService), .string("ignored")])
        #expect(SDPParsing.serviceClassUUIDs(value) == [KnownUUIDs.opoService])
        #expect(SDPParsing.serviceClassUUIDs(nil).isEmpty)
    }

    @Test func renderingAnnotatesKnownUUIDs() {
        let rendered = SDPParsing.render(.sequence([.uuid(rfcomm), .unsignedInt(15, bytes: 1)]))
        #expect(rendered == "(0x0003 [RFCOMM (protocol)], 0x0F)")
    }

    @Test func attributeNamesUsePnPMeaningsOnlyForDeviceIDRecords() {
        #expect(SDPAttributeID.name(for: 0x0201, serviceClasses: [SDPAttributeID.pnpInformation]) == "VendorID")
        #expect(SDPAttributeID.name(for: 0x0201) == "Attribute 0x0201")
        #expect(SDPAttributeID.name(for: 0x0100) == "ServiceName")
    }
}

@Suite struct RedactorTests {
    let salt: [UInt8] = Array(repeating: 7, count: 16)

    @Test func keepsOUIAndMasksTheRest() throws {
        let redacted = try #require(Redactor(enabled: true, salt: salt).address("a4-c1-38-12-34-56"))
        #expect(redacted.hasPrefix("A4:C1:38:XX:XX:XX #"))
        #expect(!redacted.contains("12:34:56"))
    }

    @Test func pseudonymIsStableWithinARunAndDiffersAcrossSalts() {
        let a = Redactor(enabled: true, salt: salt)
        let b = Redactor(enabled: true, salt: Array(repeating: 9, count: 16))
        #expect(a.address("A4:C1:38:12:34:56") == a.address("a4-c1-38-12-34-56"))
        #expect(a.address("A4:C1:38:12:34:56") != b.address("A4:C1:38:12:34:56"))
    }

    @Test func disabledRedactorPassesThrough() {
        let redactor = Redactor(enabled: false)
        #expect(redactor.address("A4:C1:38:12:34:56") == "A4:C1:38:12:34:56")
        #expect(redactor.serial("SN123") == "SN123")
    }

    @Test func serialsAreRemoved() {
        #expect(Redactor(enabled: true, salt: salt).serial("SN123") == "<redacted serial, 5 chars>")
    }

    @Test func malformedAddressesAreFullyMasked() throws {
        let redacted = try #require(Redactor(enabled: true, salt: salt).address("garbage"))
        #expect(redacted.hasPrefix("XX:XX:XX:XX:XX:XX #"))
    }
}

@Suite struct FilterAndPropertyTests {
    @Test(arguments: ["OnePlus Buds 3", "OPPO Enco Air3", "realme Buds Air 5", "Nord Buds 3 Pro"])
    func candidateNamesMatch(_ name: String) {
        #expect(CandidateFilter.matches(name))
    }

    @Test(arguments: ["MX Master 3", "Magic Keyboard", ""])
    func otherNamesDoNotMatch(_ name: String) {
        #expect(!CandidateFilter.matches(name))
    }

    @Test func nilNameDoesNotMatch() {
        #expect(!CandidateFilter.matches(nil))
    }

    @Test func describesProperties() {
        #expect(GATTProperties.describe(rawValue: 0x014) == ["writeWithoutResponse", "notify"])
        #expect(GATTProperties.describe(rawValue: 0x402) == ["read", "unknown(0x400)"])
    }
}

@Suite struct ReportRendererTests {
    func sampleReport() -> ProbeReport {
        var report = ProbeReport(toolVersion: "test", generatedAt: Date(timeIntervalSince1970: 0), macOSVersion: "15",
                                 options: .init(scanSeconds: 12, sdpRefresh: true, readStandardCharacteristics: false,
                                                redact: true, namePattern: CandidateFilter.defaultPattern))
        var device = ProbeReport.ClassicDevice(name: "OnePlus Buds 3", address: "A4:C1:38:XX:XX:XX #0000", isCandidate: true,
                                               isConnected: true, isPaired: true, classOfDevice: 0x240404,
                                               majorClass: 4, minorClass: 1)
        device.vendorLookups = [.init(uuid: KnownUUIDs.opoService, found: true, rfcommChannel: 15, serviceName: "oppointeraction")]
        device.services = [.init(serviceName: "oppointeraction", serviceClassUUIDs: [KnownUUIDs.opoService],
                                 rfcommChannelAPI: 15, rfcommChannelParsed: 15, l2capPSM: nil,
                                 attributes: [.init(id: 0x0100, value: .string("oppointeraction"))])]
        report.classic.devices = [device]
        report.classic.pairedDeviceCount = 1
        return report
    }

    @Test func textStatesReadOnlyAndShowsRFCOMMChannel() {
        let text = ReportRenderer.text(sampleReport())
        #expect(text.contains("No protocol messages were sent"))
        #expect(text.contains("\(KnownUUIDs.opoService) FOUND · RFCOMM channel 15"))
        #expect(text.contains("0x0100 ServiceName = \"oppointeraction\""))
    }

    @Test func jsonRoundTrips() throws {
        let data = try ReportRenderer.json(sampleReport())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProbeReport.self, from: data)
        #expect(decoded.classic.devices.first?.services.first?.rfcommChannelAPI == 15)
        #expect(decoded.classic.devices.first?.services.first?.attributes.first?.value == .string("oppointeraction"))
    }
}

@Suite struct PayloadRedactionTests {
    let redactor = Redactor(enabled: true, salt: Array(repeating: 1, count: 16))
    // Synthetic address and payload shaped like the observed Buds 3 manufacturer data.
    let address = "88:92:CC:11:22:33"
    let payload = Hex.bytes("9A 07 14 3C 06 7F 80 03 98 04 33 22 11 CC 92 88 1F B5")!

    @Test func masksByteReversedAddress() {
        #expect(redactor.payloadHex(payload, knownAddresses: [address])
                == "9A 07 14 3C 06 7F 80 03 98 04 XX XX XX XX XX XX 1F B5")
    }

    @Test func masksForwardAddressAndLoneNIC() {
        let forward = Hex.bytes("01 88 92 CC 11 22 33 02 11 22 33")!
        #expect(redactor.payloadHex(forward, knownAddresses: [address]) == "01 XX XX XX XX XX XX 02 XX XX XX")
    }

    @Test func leavesPayloadAloneWhenRedactionIsOffOrNoMatch() {
        #expect(Redactor(enabled: false).payloadHex(payload, knownAddresses: [address]) == Hex.string(payload))
        #expect(redactor.payloadHex([0x9A, 0x07], knownAddresses: [address, "bogus"]) == "9A 07")
    }
}

@Suite struct ServiceClassShapeTests {
    @Test func acceptsBareUUIDAsObservedFromIOBluetooth() {
        #expect(SDPParsing.serviceClassUUIDs(.uuid(KnownUUIDs.opoService)) == [KnownUUIDs.opoService])
    }
}
