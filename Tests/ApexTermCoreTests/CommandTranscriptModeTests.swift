import XCTest
@testable import ApexTermCore

final class CommandTranscriptModeTests: XCTestCase {
    func testOnShowsFullTranscript() {
        XCTAssertTrue(CommandTranscriptMode.on.showsTranscript)
        XCTAssertEqual(CommandTranscriptMode.on.recordLimit, 100)
        XCTAssertEqual(CommandTranscriptMode.on.title, "On")
    }

    func testOffHidesTranscript() {
        XCTAssertFalse(CommandTranscriptMode.off.showsTranscript)
        XCTAssertEqual(CommandTranscriptMode.off.recordLimit, 100)
        XCTAssertEqual(CommandTranscriptMode.off.title, "Off")
    }

    func testExUsesConversationHistoryWindow() {
        XCTAssertTrue(CommandTranscriptMode.ex.showsTranscript)
        XCTAssertEqual(CommandTranscriptMode.ex.recordLimit, 100)
        XCTAssertEqual(CommandTranscriptMode.ex.title, "Ex")
    }

    func testCycleOrderIsOnOffExOn() {
        XCTAssertEqual(CommandTranscriptMode.on.next, .off)
        XCTAssertEqual(CommandTranscriptMode.off.next, .ex)
        XCTAssertEqual(CommandTranscriptMode.ex.next, .on)
    }

    func testProfileDecodesLegacyDocumentWithoutTranscriptMode() throws {
        let profileID = UUID()
        let json = """
        {
          "id": "\(profileID.uuidString)",
          "name": "Legacy",
          "terminalFontSize": 13,
          "sidebarFontSize": 12,
          "inputColorHex": "#FFFFFF",
          "outputColorHex": "#FFFFFF",
          "environment": {},
          "commandBlocksEnabled": true,
          "smartPasteProtectionEnabled": true,
          "secureKeyboardEntryEnabled": false
        }
        """

        let profile = try JSONDecoder().decode(
            ApexTerminalProfile.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(profile.commandTranscriptMode)
        XCTAssertTrue(profile.commandBlocksEnabled)
    }
}
