import XCTest
@testable import OlcRTCClient

final class SubscriptionImporterTests: XCTestCase {
    func testParsesPastedSubscription() throws {
        let key = String(repeating: "a", count: 64)
        let content = """
        #name: Mobile nodes
        olcrtc://wbstream?datachannel@room-01#\(key)%iphone-01$Old name
        ##name: RU bridge

        olcrtc://telemost?vp8channel<vp8-fps=60&vp8-batch=8>@room-02#\(key)%iphone-02$Second
        ##comment: CH exit
        """

        let result = try SubscriptionImporter.parseSubscription(content)

        XCTAssertEqual(result.title, "Mobile nodes")
        XCTAssertEqual(result.profiles.count, 2)
        XCTAssertEqual(result.profiles[0].displayName, "RU bridge")
        XCTAssertEqual(result.profiles[1].displayName, "CH exit")
        XCTAssertEqual(result.profiles[1].payload["vp8-batch"], "8")
    }

    func testRejectsSubscriptionWithoutProfiles() {
        XCTAssertThrowsError(
            try SubscriptionImporter.parseSubscription("#name: empty")
        )
    }
}
