import Foundation
import XCTest
@testable import omi_lib

final class OmiAudioSnapshotTests: XCTestCase {
    func testSnapshotRemainsReadableAfterSourceIsRemoved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("recording.wav")
        let expected = Data((0..<128).map(UInt8.init))
        try expected.write(to: source)

        let snapshot = try makeOmiAudioSnapshot(from: source)
        defer { try? FileManager.default.removeItem(at: snapshot) }
        try FileManager.default.removeItem(at: source)

        XCTAssertEqual(try Data(contentsOf: snapshot), expected)
    }

    func testMissingRecordingCannotManufactureASnapshot() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        XCTAssertThrowsError(try makeOmiAudioSnapshot(from: missing))
    }
}
