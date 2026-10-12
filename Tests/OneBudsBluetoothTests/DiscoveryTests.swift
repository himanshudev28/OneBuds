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
