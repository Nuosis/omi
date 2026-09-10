import CoreBluetooth
import XCTest
@testable import omi_lib

final class OmiRecordingReadinessTests: XCTestCase {
    func testCodecEventStartsCaptureAndStopCancelsPendingStart() {
        let manager = FriendManager()
        let ble = BLEManager(deviceRegistry: WearableDeviceRegistry.shared)
        let friend = Friend(bleManager: ble, name: "test")
        manager.startRecordingWhenReady(device: friend)
        XCTAssertFalse(friend.isRecording)
        manager.getLiveTranscription(device: friend) { _ in }
        ble.valueChanges.send((CBUUID(string: "19B10002-E8F2-537E-4F6C-D104768A1214"), Data([0])))
        XCTAssertTrue(friend.isRecording)
        let file = friend.recording?.fileURL
        manager.stopLiveTranscription(device: friend)
        ble.valueChanges.send((CBUUID(string: "19B10002-E8F2-537E-4F6C-D104768A1214"), Data([0])))
        XCTAssertFalse(friend.isRecording)
        if let file { try? FileManager.default.removeItem(at: file) }
    }
}
