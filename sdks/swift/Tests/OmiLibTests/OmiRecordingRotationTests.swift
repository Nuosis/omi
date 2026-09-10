import AVFoundation
import XCTest
@testable import omi_lib

final class OmiRecordingRotationTests: XCTestCase {
    func testRotationFinalizesWavAndPreservesEveryFrameExactlyOnce() throws {
        let recording = Recording(filename: "test-\(UUID().uuidString).wav")
        XCTAssertTrue(recording.startRecording(usingCodec: PcmCodec(sampleRate: 16000)))
        let first = AudioPacket(packetNumber: 0)
        first.append(data: Data(repeating: 0, count: 32000))
        recording.append(packets: [first])
        let original = try XCTUnwrap(recording.snapshotRecording())
        defer { try? FileManager.default.removeItem(at: original) }
        XCTAssertEqual(try AVAudioFile(forReading: original).length, 16000)
        let second = AudioPacket(packetNumber: 1)
        second.append(data: Data(repeating: 0, count: 16000))
        recording.append(packets: [second])
        recording.closeRecording()
        defer { try? FileManager.default.removeItem(at: recording.fileURL) }
        XCTAssertEqual(try AVAudioFile(forReading: recording.fileURL).length, 8000)
        XCTAssertEqual(try AVAudioFile(forReading: original).length, 16000)
    }
}
