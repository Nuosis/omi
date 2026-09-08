import XCTest
@testable import omi_lib

final class OmiPeripheralNameTests: XCTestCase {
    func testRetailOmiNameIsDiscoverable() {
        XCTAssertTrue(isSupportedOmiPeripheralName("Omi"))
    }

    func testRetailOmiAdvertisementNameIsDiscoverableWhenPeripheralNameIsMissing() {
        XCTAssertTrue(isSupportedOmiPeripheral(
            peripheralName: nil,
            advertisedName: "Omi"
        ))
    }

    func testLegacyOmiNamesRemainDiscoverable() {
        XCTAssertTrue(isSupportedOmiPeripheralName("Friend"))
        XCTAssertTrue(isSupportedOmiPeripheralName("Friend DevKit 2"))
        XCTAssertTrue(isSupportedOmiPeripheralName("Omi DevKit 2"))
    }

    func testUnrelatedPeripheralNameIsRejected() {
        XCTAssertFalse(isSupportedOmiPeripheralName("AirPods"))
        XCTAssertFalse(isSupportedOmiPeripheralName(nil))
        XCTAssertFalse(isSupportedOmiPeripheral(
            peripheralName: "AirPods",
            advertisedName: "Headphones"
        ))
    }
}
