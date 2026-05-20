import XCTest
@testable import OlcRTCClient

final class OlcRTCURIParserTests: XCTestCase {
    func testParsesDatachannelURI() throws {
        let profile = try OlcRTCProfile(
            uri: "olcrtc://wbstream?datachannel@room-01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799$CH data"
        )

        XCTAssertEqual(profile.carrier, "wbstream")
        XCTAssertEqual(profile.transport, "datachannel")
        XCTAssertEqual(profile.roomID, "room-01")
        XCTAssertTrue(profile.clientID.hasPrefix("ios-"))
        XCTAssertEqual(profile.comment, "CH data")
        XCTAssertTrue(profile.payload.isEmpty)
    }

    func testKeepsLegacyClientIDWhenPresent() throws {
        let profile = try OlcRTCProfile(
            uri: "olcrtc://wbstream?datachannel@room-01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799%iphone-01$CH data"
        )

        XCTAssertEqual(profile.clientID, "iphone-01")
    }

    func testGeneratesStableInstallScopedClientIDForCurrentURIFormat() throws {
        let uri = "olcrtc://jitsi?datachannel@https://meet.cryptopro.ru/myroom#\(String(repeating: "a", count: 64))$Jitsi data"
        let first = try OlcRTCProfile(uri: uri)
        let second = try OlcRTCProfile(uri: uri)

        XCTAssertTrue(first.clientID.hasPrefix("ios-"))
        XCTAssertEqual(first.clientID, second.clientID)
        XCTAssertNotEqual(
            first.clientID,
            DeviceIdentity.legacyProfileClientID(
                carrier: first.carrier,
                roomID: first.roomID,
                keyHex: first.keyHex
            )
        )
    }

    func testParsesVP8Payload() throws {
        let profile = try OlcRTCProfile(
            uri: "olcrtc://wbstream?vp8channel<vp8-fps=60&vp8-batch=64>@room-01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799%iphone-01$CH vp8"
        )

        XCTAssertEqual(profile.transport, "vp8channel")
        XCTAssertEqual(profile.payload["vp8-fps"], "60")
        XCTAssertEqual(profile.payload["vp8-batch"], "64")
    }

    func testParsesSEIPayload() throws {
        let key = String(repeating: "c", count: 64)
        let profile = try OlcRTCProfile(
            uri: "olcrtc://jazz?seichannel<fps=60&batch=64&frag=900&ack-ms=2000>@room-01#\(key)$Jazz SEI"
        )

        XCTAssertEqual(profile.carrier, "jazz")
        XCTAssertEqual(profile.transport, "seichannel")
        XCTAssertEqual(profile.payload["fps"], "60")
        XCTAssertEqual(profile.payload["batch"], "64")
        XCTAssertEqual(profile.payload["frag"], "900")
        XCTAssertEqual(profile.payload["ack-ms"], "2000")
        XCTAssertTrue(profile.clientID.hasPrefix("ios-"))
        XCTAssertEqual(profile.startReadyTimeoutMilliseconds, 30_000)
        XCTAssertEqual(profile.tunnelCheckTimeoutNanoseconds, 16_000_000_000)
    }

    func testParsesVideoPayload() throws {
        let key = String(repeating: "d", count: 64)
        let profile = try OlcRTCProfile(
            uri: "olcrtc://telemost?videochannel<video-w=1080&video-h=1080&video-fps=60&video-bitrate=5000k&video-hw=none&video-codec=qrcode>@room-01#\(key)$Telemost video"
        )

        XCTAssertEqual(profile.carrier, "telemost")
        XCTAssertEqual(profile.transport, "videochannel")
        XCTAssertEqual(profile.payload["video-w"], "1080")
        XCTAssertEqual(profile.payload["video-h"], "1080")
        XCTAssertEqual(profile.payload["video-fps"], "60")
        XCTAssertEqual(profile.payload["video-bitrate"], "5000k")
        XCTAssertEqual(profile.payload["video-hw"], "none")
        XCTAssertEqual(profile.payload["video-codec"], "qrcode")
        XCTAssertEqual(profile.compatibilityLabel, "best effort")
        XCTAssertEqual(profile.startReadyTimeoutMilliseconds, 30_000)
    }

    func testDecodesPercentEncodedFields() throws {
        let profile = try OlcRTCProfile(
            uri: "olcrtc://wbstream?datachannel@room%2D01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799%iphone%2D01$CH%20data"
        )

        XCTAssertEqual(profile.roomID, "room-01")
        XCTAssertEqual(profile.clientID, "iphone-01")
        XCTAssertEqual(profile.comment, "CH data")
    }

    func testParsesJitsiRoomURL() throws {
        let key = String(repeating: "a", count: 64)
        let profile = try OlcRTCProfile(
            uri: "olcrtc://jitsi?datachannel@https://meet.cryptopro.ru/myroom#\(key)$Jitsi data"
        )

        XCTAssertEqual(profile.carrier, "jitsi")
        XCTAssertEqual(profile.transport, "datachannel")
        XCTAssertEqual(profile.roomID, "https://meet.cryptopro.ru/myroom")
        XCTAssertEqual(profile.carrierDisplayName, "Jitsi")
        XCTAssertEqual(profile.transportDisplayName, "Data")
        XCTAssertEqual(profile.compatibilityLabel, "stable")
        XCTAssertEqual(profile.roomLabel, "meet.cryptopro.ru")
        XCTAssertTrue(profile.isJitsiDatachannel)
        XCTAssertEqual(profile.startAttemptCount, 3)
        XCTAssertEqual(profile.startReadyTimeoutMilliseconds, 90_000)
        XCTAssertEqual(profile.tunnelCheckTimeoutNanoseconds, 20_000_000_000)

        let runtimeClientID = profile.runtimeClientID()
        XCTAssertTrue(runtimeClientID.hasPrefix("\(profile.clientID)-r"))
        XCTAssertNotEqual(runtimeClientID, profile.clientID)
    }

    func testParsesPercentEncodedJitsiRoomURL() throws {
        let key = String(repeating: "b", count: 64)
        let profile = try OlcRTCProfile(
            uri: "olcrtc://jitsi?datachannel@https%3A%2F%2Fmeet.jit.si%2Fpasklove-room#\(key)$Jitsi%20public"
        )

        XCTAssertEqual(profile.roomID, "https://meet.jit.si/pasklove-room")
        XCTAssertTrue(profile.clientID.hasPrefix("ios-"))
        XCTAssertEqual(profile.comment, "Jitsi public")
        XCTAssertEqual(profile.roomLabel, "meet.jit.si")
    }

    func testNormalizesJitsiHostSlashRoom() throws {
        let key = "70523e50350dc853718227eee3b16d7d32f47d354a9678b41e97e91a81fc4269"
        let profile = try OlcRTCProfile(
            uri: "olcrtc://jitsi?datachannel@meet.bl3ndr.io/heisenberg#\(key)$Jitsi2"
        )

        XCTAssertEqual(profile.roomID, "https://meet.bl3ndr.io/heisenberg")
        XCTAssertEqual(profile.roomLabel, "meet.bl3ndr.io")
        XCTAssertEqual(profile.comment, "Jitsi2")
    }

    func testAcceptsAccidentalDollarBeforeKey() throws {
        let key = "70523e50350dc853718227eee3b16d7d32f47d354a9678b41e97e91a81fc4269"
        let profile = try OlcRTCProfile(
            uri: "olcrtc://jitsi?datachannel@meet.bl3ndr.io/heisenberg#$\(key)$Jitsi2"
        )

        XCTAssertEqual(profile.keyHex, key)
        XCTAssertEqual(profile.roomID, "https://meet.bl3ndr.io/heisenberg")
        XCTAssertEqual(profile.comment, "Jitsi2")
    }

    func testNonJitsiProfilesKeepFastStartupPolicy() throws {
        let profile = try OlcRTCProfile(
            uri: "olcrtc://wbstream?datachannel@room-01#d823fa01cb3e0609b67322f7cf984c4ee2e4ce2e294936fc24ef38c9e59f4799%iphone-01$CH data"
        )

        XCTAssertFalse(profile.isJitsiDatachannel)
        XCTAssertEqual(profile.startAttemptCount, 3)
        XCTAssertEqual(profile.startReadyTimeoutMilliseconds, 12_000)
        XCTAssertEqual(profile.tunnelCheckTimeoutNanoseconds, 12_000_000_000)
        XCTAssertEqual(profile.runtimeClientID(), "iphone-01")
    }

    func testRejectsNonHexKey() {
        XCTAssertThrowsError(
            try OlcRTCProfile(
                uri: "olcrtc://wbstream?datachannel@room-01#zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz$bad"
            )
        )
    }
}
