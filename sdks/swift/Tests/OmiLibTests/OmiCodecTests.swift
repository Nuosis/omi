import XCTest
@testable import omi_lib

final class OmiCodecTests: XCTestCase {
    func testRetailFirmwareOpusFS320CodecIsSupported() {
        XCTAssertNotNil(Friend.FriendCodec(rawValue: 21))
    }

    func testLegacyOpusCodecRemainsSupported() {
        XCTAssertNotNil(Friend.FriendCodec(rawValue: 20))
    }

    func testUnknownCodecIsRejected() {
        XCTAssertNil(Friend.FriendCodec(rawValue: 255))
    }
}
