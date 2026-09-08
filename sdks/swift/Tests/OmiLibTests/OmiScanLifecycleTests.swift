import XCTest
@testable import omi_lib

final class OmiScanLifecycleTests: XCTestCase {
    func testPoweredOnBluetoothDoesNotScanBeforeListenRequestsIt() {
        XCTAssertFalse(shouldRunOmiScan(
            scanRequested: false,
            bluetoothPoweredOn: true
        ))
    }

    func testListenRequestStartsScanWhenBluetoothIsPoweredOn() {
        XCTAssertTrue(shouldRunOmiScan(
            scanRequested: true,
            bluetoothPoweredOn: true
        ))
    }

    func testPendingListenRequestWaitsForBluetoothPower() {
        XCTAssertFalse(shouldRunOmiScan(
            scanRequested: true,
            bluetoothPoweredOn: false
        ))
    }
}
