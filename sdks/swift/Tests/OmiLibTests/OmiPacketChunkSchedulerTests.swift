import XCTest
@testable import omi_lib

final class OmiPacketChunkSchedulerTests: XCTestCase {
    func testEmitsAtTheFirstPacketBoundaryAtOrAfterInterval() {
        var scheduler = OmiPacketChunkScheduler(interval: 8)

        XCTAssertFalse(scheduler.observePacket(at: 100))
        XCTAssertFalse(scheduler.observePacket(at: 107.99))
        XCTAssertTrue(scheduler.observePacket(at: 108))
    }

    func testStartsANewIntervalAfterEmitting() {
        var scheduler = OmiPacketChunkScheduler(interval: 8)

        XCTAssertFalse(scheduler.observePacket(at: 100))
        XCTAssertTrue(scheduler.observePacket(at: 108))
        XCTAssertFalse(scheduler.observePacket(at: 115.99))
        XCTAssertTrue(scheduler.observePacket(at: 116))
    }

    func testResetRequiresANewFullInterval() {
        var scheduler = OmiPacketChunkScheduler(interval: 8)

        XCTAssertFalse(scheduler.observePacket(at: 100))
        scheduler.reset()
        XCTAssertFalse(scheduler.observePacket(at: 200))
        XCTAssertFalse(scheduler.observePacket(at: 207.99))
        XCTAssertTrue(scheduler.observePacket(at: 208))
    }

    func testClockMovingBackRestartsTheInterval() {
        var scheduler = OmiPacketChunkScheduler(interval: 8)

        XCTAssertFalse(scheduler.observePacket(at: 100))
        XCTAssertFalse(scheduler.observePacket(at: 50))
        XCTAssertFalse(scheduler.observePacket(at: 57.99))
        XCTAssertTrue(scheduler.observePacket(at: 58))
    }
}
