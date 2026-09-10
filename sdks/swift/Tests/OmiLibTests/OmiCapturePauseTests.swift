import AVFoundation
import CoreBluetooth
import XCTest
@testable import omi_lib

final class OmiCapturePauseTests: XCTestCase {
    func testPausedPacketsAreNotWrittenAndResumeWritesNewAudio() throws {
        let manager = FriendManager()
        let ble = BLEManager(deviceRegistry: WearableDeviceRegistry.shared)
        let friend = Friend(bleManager: ble, name: "test")
        var capture = true
        var snapshots: [URL] = []
        friend.shouldCaptureAudio = { capture }
        manager.getRawAudio(device: friend) { if let url = $0 { snapshots.append(url) } }
        manager.startRecordingWhenReady(device: friend)
        ble.valueChanges.send((CBUUID(string: "19B10002-E8F2-537E-4F6C-D104768A1214"), Data([0])))
        func packet(_ id: UInt8, byte: UInt8) {
            ble.valueChanges.send((CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214"),
                Data([id, 0, 0]) + Data(repeating: byte, count: 320)))
        }
        packet(0, byte: 1); packet(1, byte: 1)
        capture = false
        packet(2, byte: 2); packet(3, byte: 2)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(try AVAudioFile(forReading: snapshots[0]).length, 160)
        capture = true
        packet(4, byte: 3); packet(5, byte: 3)
        manager.stopLiveTranscription(device: friend)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(try AVAudioFile(forReading: snapshots[1]).length, 320)
        let audio = try AVAudioFile(forReading: snapshots[1])
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 320))
        try audio.read(into: buffer)
        XCTAssertEqual(buffer.floatChannelData![0][0], Float(0x0303) / 32768, accuracy: 0.00001)
        for url in snapshots { try? FileManager.default.removeItem(at: url) }
    }
}
