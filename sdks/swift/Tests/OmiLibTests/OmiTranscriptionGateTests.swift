import XCTest
@testable import omi_lib

final class OmiTranscriptionGateTests: XCTestCase {
    func testOnlyOneWhisperIntervalCanRunAtATime() {
        var gate = OmiTranscriptionGate()
        let generation = gate.start()

        XCTAssertTrue(gate.beginInterval(for: generation))
        XCTAssertFalse(gate.beginInterval(for: generation))
        XCTAssertTrue(gate.finishInterval(for: generation))
        XCTAssertTrue(gate.beginInterval(for: generation))
    }

    func testStopRejectsAnInFlightTranscript() {
        var gate = OmiTranscriptionGate()
        let generation = gate.start()

        XCTAssertTrue(gate.beginInterval(for: generation))
        gate.stop()

        XCTAssertFalse(gate.finishInterval(for: generation))
        XCTAssertFalse(gate.beginInterval(for: generation))
    }
}
