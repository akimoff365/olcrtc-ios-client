import XCTest
@testable import OlcRTCClient

final class OlcRTCURIParserTests: XCTestCase {
    func testParsesDatachannelURI() throws {
        let profile = try OlcRTCProfile(
            uri: "olcrtc://wbstream?datachannel@room-01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799%iphone-01$CH data"
        )

        XCTAssertEqual(profile.carrier, "wbstream")
        XCTAssertEqual(profile.transport, "datachannel")
        XCTAssertEqual(profile.roomID, "room-01")
        XCTAssertEqual(profile.clientID, "iphone-01")
        XCTAssertEqual(profile.comment, "CH data")
        XCTAssertTrue(profile.payload.isEmpty)
    }

    func testParsesVP8Payload() throws {
        let profile = try OlcRTCProfile(
            uri: "olcrtc://wbstream?vp8channel<vp8-fps=60&vp8-batch=64>@room-01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799%iphone-01$CH vp8"
        )

        XCTAssertEqual(profile.transport, "vp8channel")
        XCTAssertEqual(profile.payload["vp8-fps"], "60")
        XCTAssertEqual(profile.payload["vp8-batch"], "64")
    }

    func testDecodesPercentEncodedFields() throws {
        let profile = try OlcRTCProfile(
            uri: "olcrtc://wbstream?datachannel@room%2D01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799%iphone%2D01$CH%20data"
        )

        XCTAssertEqual(profile.roomID, "room-01")
        XCTAssertEqual(profile.clientID, "iphone-01")
        XCTAssertEqual(profile.comment, "CH data")
    }

    func testRejectsNonHexKey() {
        XCTAssertThrowsError(
            try OlcRTCProfile(
                uri: "olcrtc://wbstream?datachannel@room-01#zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz%iphone-01$bad"
            )
        )
    }
}
