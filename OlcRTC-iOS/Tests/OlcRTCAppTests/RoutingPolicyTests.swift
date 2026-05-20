import XCTest
@testable import OlcRTCClient

final class RoutingPolicyTests: XCTestCase {
    func testSimpleRURoutingConfigTargetsOlcRTCSocks() throws {
        let credentials = SocksCredentials(username: "user", password: "pass")
        let config = try SingBoxRoutingConfigBuilder(
            socksPort: 18080,
            credentials: credentials,
            preset: .simpleRU
        ).makeConfig()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any]
        )

        let outbounds = try XCTUnwrap(object["outbounds"] as? [[String: Any]])
        let socksOutbound = try XCTUnwrap(outbounds.first { $0["tag"] as? String == "olcrtc" })
        XCTAssertEqual(socksOutbound["server"] as? String, "127.0.0.1")
        XCTAssertEqual(socksOutbound["server_port"] as? Int, 18080)
        XCTAssertEqual(socksOutbound["username"] as? String, "user")
        XCTAssertEqual(socksOutbound["password"] as? String, "pass")

        let route = try XCTUnwrap(object["route"] as? [String: Any])
        XCTAssertEqual(route["final"] as? String, "olcrtc")

        let ruleSets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])
        let tags = Set(ruleSets.compactMap { $0["tag"] as? String })
        XCTAssertTrue(tags.contains("geoip-ru"))
        XCTAssertTrue(tags.contains("geosite-youtube"))
    }

    func testBlockedOnlyFallsBackToDirect() throws {
        let config = try SingBoxRoutingConfigBuilder(
            socksPort: 18080,
            credentials: SocksCredentials(username: "u", password: "p"),
            preset: .blockedOnly
        ).makeConfig()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any]
        )
        let route = try XCTUnwrap(object["route"] as? [String: Any])

        XCTAssertEqual(route["final"] as? String, "direct")
    }
}
