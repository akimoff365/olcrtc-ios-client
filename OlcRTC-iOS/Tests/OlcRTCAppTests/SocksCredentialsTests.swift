import XCTest
@testable import OlcRTCClient

final class SocksCredentialsTests: XCTestCase {
    func testBuildsSocks5URL() {
        let credentials = SocksCredentials(username: "olc_user", password: "pass123")

        XCTAssertEqual(
            credentials.socks5URL(port: 18080),
            "socks5://olc_user:pass123@127.0.0.1:18080#OlcRTC"
        )
    }

    func testBuildsLegacySocksURL() {
        let credentials = SocksCredentials(username: "olc_user", password: "pass123")

        XCTAssertEqual(
            credentials.legacySocksURL(port: 18080),
            "socks://b2xjX3VzZXI6cGFzczEyM0AxMjcuMC4wLjE6MTgwODA=#OlcRTC"
        )
    }
}
