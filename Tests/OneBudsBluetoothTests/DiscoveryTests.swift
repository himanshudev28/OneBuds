import CoreBluetooth
import Foundation
import Testing
@testable import OneBudsBluetooth
import OneBudsCore

/// Advertisement layout observed on OnePlus Buds 3 (PhaseB-Report §4.3), with a synthetic address.
@Suite struct RenamedDeviceIdentificationTests {
    let address = "88:92:CC:11:22:33"
    // 9A 07 | 14 3C 06 (063C14 LE) | 7F 90 03 98 04 | address byte-reversed | 1F B5 B5 00 03 00
    let advertisement = Data([0x9A, 0x07, 0x14, 0x3C, 0x06, 0x7F, 0x90, 0x03, 0x98, 0x04,
                              0x33, 0x22, 0x11, 0xCC, 0x92, 0x88, 0x1F, 0xB5, 0xB5, 0x00, 0x03, 0x00])

    @Test func productIDFromManufacturerData() {
        #expect(BluetoothConnector.productID(fromManufacturerData: advertisement) == "063C14")
        #expect(BluetoothConnector.productID(fromManufacturerData: Data([0x4C, 0x00, 0x14, 0x3C, 0x06])) == nil) // not OPPO
        #expect(BluetoothConnector.productID(fromManufacturerData: Data([0x9A, 0x07])) == nil)
    }

    @Test func renamedDeviceIsIdentifiedOnlyByItsOwnAdvertisement() {
        #expect(BluetoothConnector.productID(fromManufacturerData: advertisement, matchingAddress: address) == "063C14")
        #expect(BluetoothConnector.productID(fromManufacturerData: advertisement, matchingAddress: "88:92:CC:99:99:99") == nil)
        let renamed = DiscoveredEarbuds(name: "Someone's OnePlus Buds 3", productID: "063C14", discoveryPaths: [], transports: [.rfcomm])
        #expect(renamed.profile?.id == "oneplus-buds-3")
    }

    @Test func addressKeyIsStableAndDoesNotContainTheAddress() {
        let key = BluetoothConnector.addressKey(address)
        #expect(key == BluetoothConnector.addressKey("88-92-cc-11-22-33"))
        #expect(!key.uppercased().contains("8892CC"))
        #expect(key.count == 16)
    }
}

/// GATT write sizing: no split unless nothing else fits.
@Suite struct BLEWritePlanTests {
    @Test func smallFrameUsesWriteWithoutResponse() {
        let plan = BLETransport.writePlan(length: 20, withoutResponse: true, withResponse: true, maxWithoutResponse: 182, maxWithResponse: 512)
        #expect(plan.0 == .withoutResponse)
        #expect(plan.1 == 20)
    }

    @Test func largeFrameUsesALongWriteInsteadOfSplitting() {
        let plan = BLETransport.writePlan(length: 300, withoutResponse: true, withResponse: true, maxWithoutResponse: 182, maxWithResponse: 512)
        #expect(plan.0 == .withResponse)
        #expect(plan.1 == 300)
    }

    @Test func splitsOnlyWhenNothingFits() {
        let withoutOnly = BLETransport.writePlan(length: 50, withoutResponse: true, withResponse: false, maxWithoutResponse: 20, maxWithResponse: 512)
        #expect(withoutOnly.0 == .withoutResponse)
        #expect(withoutOnly.1 == 20)
        let withOnly = BLETransport.writePlan(length: 600, withoutResponse: false, withResponse: true, maxWithoutResponse: 0, maxWithResponse: 512)
        #expect(withOnly.0 == .withResponse)
        #expect(withOnly.1 == 512)
    }

    @Test func degenerateSizesNeverProduceAnEmptyChunk() {
        let plan = BLETransport.writePlan(length: 10, withoutResponse: true, withResponse: false, maxWithoutResponse: 0, maxWithResponse: 0)
        #expect(plan.1 >= 1)
    }

    @Test func pairingErrorsAreNamed() {
        let error = NSError(domain: CBATTErrorDomain, code: CBATTError.insufficientEncryption.rawValue)
        #expect(BLETransport.describe(error).contains("pairing"))
        let other = NSError(domain: CBATTErrorDomain, code: CBATTError.writeNotPermitted.rawValue)
        #expect(!BLETransport.describe(other).contains("pairing"))
    }
}

/// A renamed Buds 3 shows its custom name over classic Bluetooth but the model name over BLE.
@MainActor @Suite struct RenamedDeviceMergeTests {
    let classic = DiscoveredEarbuds(name: "Sam's OnePlus Buds 3", productID: "063C14", discoveryPaths: ["paired classic device"], transports: [.rfcomm])
    let ble = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: ["BLE connected peripheral (vendor GATT service)"], transports: [.ble])

    @Test func foldsTheBLEEntryIntoTheRenamedClassicDevice() throws {
        var found = [classic.name: classic, ble.name: ble]
        BluetoothConnector.mergeRenamedBLEEntries(&found)
        #expect(found.count == 1)
        let merged = try #require(found[classic.name])
        #expect(merged.transports == [.rfcomm, .ble])
        #expect(merged.bleNames == ["OnePlus Buds 3"])
        #expect(DeviceManager.transportOrder(profile: try #require(merged.profile), earbuds: merged) == [.ble, .rfcomm])
    }

    @Test func leavesAmbiguousOrUnidentifiedEntriesAlone() {
        let second = DiscoveredEarbuds(name: "Kim's OnePlus Buds 3", productID: "063C14", discoveryPaths: [], transports: [.rfcomm])
        var twoClassic = [classic.name: classic, second.name: second, ble.name: ble]
        BluetoothConnector.mergeRenamedBLEEntries(&twoClassic)
        #expect(twoClassic.count == 3)

        let unidentified = DiscoveredEarbuds(name: "My buds", discoveryPaths: [], transports: [.rfcomm])
        var noProfile = [unidentified.name: unidentified, ble.name: ble]
        BluetoothConnector.mergeRenamedBLEEntries(&noProfile)
        #expect(noProfile.count == 2)
    }

    @Test func neverFoldsASecondPairIntoADeviceThatAlreadyHasGATT() {
        let first = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: [], transports: [.rfcomm, .ble])
        let otherPair = DiscoveredEarbuds(name: "Buds 3 (2)", productID: "063C14", discoveryPaths: [], transports: [.ble])
        var found = [first.name: first, otherPair.name: otherPair]
        BluetoothConnector.mergeRenamedBLEEntries(&found)
        #expect(found.count == 2)
        #expect(found[first.name]?.transports == [.rfcomm, .ble])
    }

    @Test func offersGATTToAClassicOnlyDeviceWhoseModelHasIt() {
        var found = [classic.name: classic]
        BluetoothConnector.offerGATTByAdvertisement(&found)
        #expect(found[classic.name]?.transports == [.rfcomm, .ble])

        let realme = DiscoveredEarbuds(name: "realme Buds Air 5", discoveryPaths: [], transports: [.rfcomm])
        var noGATT = [realme.name: realme]
        BluetoothConnector.offerGATTByAdvertisement(&noGATT)
        #expect(noGATT[realme.name]?.transports == [.rfcomm]) // its profile has no GATT parameters

        let both = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: [], transports: [.ble, .rfcomm])
        var already = [both.name: both]
        BluetoothConnector.offerGATTByAdvertisement(&already)
        #expect(already[both.name]?.transports == [.ble, .rfcomm])
    }

    @Test func sameNameEntriesNeedNoMerge() {
        let both = DiscoveredEarbuds(name: "OnePlus Buds 3", discoveryPaths: [], transports: [.ble, .rfcomm])
        var found = [both.name: both]
        BluetoothConnector.mergeRenamedBLEEntries(&found)
        #expect(found[both.name]?.bleNames.isEmpty == true)
    }
}
