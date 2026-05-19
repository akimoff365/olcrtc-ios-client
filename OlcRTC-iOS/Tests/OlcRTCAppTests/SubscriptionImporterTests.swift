import XCTest
@testable import OlcRTCClient

final class SubscriptionImporterTests: XCTestCase {
    func testParsesPastedSubscription() throws {
        let key = String(repeating: "a", count: 64)
        let content = """
        #name: Mobile nodes
        olcrtc://wbstream?datachannel@room-01#\(key)$Old name
        ##name: RU bridge

        olcrtc://telemost?vp8channel<vp8-fps=60&vp8-batch=8>@room-02#\(key)$Second
        ##comment: CH exit

        olcrtc://jitsi?datachannel@https://meet.cryptopro.ru/team-room#\(key)$Third
        ##name: Jitsi stable
        """

        let result = try SubscriptionImporter.parseSubscription(content)

        XCTAssertEqual(result.title, "Mobile nodes")
        XCTAssertEqual(result.profiles.count, 3)
        XCTAssertEqual(result.profiles[0].displayName, "RU bridge")
        XCTAssertEqual(result.profiles[1].displayName, "CH exit")
        XCTAssertEqual(result.profiles[1].payload["vp8-batch"], "8")
        XCTAssertEqual(result.profiles[2].carrier, "jitsi")
        XCTAssertEqual(result.profiles[2].roomID, "https://meet.cryptopro.ru/team-room")
        XCTAssertEqual(result.profiles[2].displayName, "Jitsi stable")
    }

    func testRejectsSubscriptionWithoutProfiles() {
        XCTAssertThrowsError(
            try SubscriptionImporter.parseSubscription("#name: empty")
        )
    }

    func testUsesRussianFallbackProfileNames() throws {
        let key = String(repeating: "b", count: 64)
        let content = """
        olcrtc://wbstream?datachannel@room-01#\(key)
        olcrtc://wbstream?datachannel@room-02#\(key)
        """

        let result = try SubscriptionImporter.parseSubscription(content)

        XCTAssertEqual(result.profiles.map(\.displayName), ["Профиль 1", "Профиль 2"])
    }

    func testKeepsInlineOlcRTCCommentsAsNames() throws {
        let key = String(repeating: "c", count: 64)
        let content = "olcrtc://wbstream?datachannel@room-01#\(key)$Домашний"

        let result = try SubscriptionImporter.parseSubscription(content)

        XCTAssertEqual(result.profiles.first?.displayName, "Домашний")
    }
}
