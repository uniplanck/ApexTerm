import XCTest
@testable import ApexTermCore

final class CommandTranscriptLayoutPolicyTests: XCTestCase {
    func testExModeShrinksTranscriptToCollapsedContent() {
        let layout = CommandTranscriptLayoutPolicy.resolve(
            mode: .ex,
            showsTranscript: true,
            containerHeight: 700,
            measuredContentHeight: 82,
            preferredLivePaneHeight: 300,
            minimumLivePaneHeight: 76,
            maximumLivePaneHeight: 420,
            headerHeight: 26,
            resizeHandleHeight: 12
        )

        XCTAssertEqual(layout.transcriptHeight, 82)
        XCTAssertEqual(layout.livePaneHeight, 592)
        XCTAssertFalse(layout.showsResizeHandle)
    }

    func testExModeExpandsAndCapsTranscriptToPreserveTerminal() {
        let layout = CommandTranscriptLayoutPolicy.resolve(
            mode: .ex,
            showsTranscript: true,
            containerHeight: 700,
            measuredContentHeight: 900,
            preferredLivePaneHeight: 300,
            minimumLivePaneHeight: 76,
            maximumLivePaneHeight: 420,
            headerHeight: 26,
            resizeHandleHeight: 12
        )

        XCTAssertEqual(layout.transcriptHeight, 598)
        XCTAssertEqual(layout.livePaneHeight, 76)
        XCTAssertFalse(layout.showsResizeHandle)
    }

    func testOnModeKeepsManualTerminalHeightAndResizeHandle() {
        let layout = CommandTranscriptLayoutPolicy.resolve(
            mode: .on,
            showsTranscript: true,
            containerHeight: 700,
            measuredContentHeight: 82,
            preferredLivePaneHeight: 260,
            minimumLivePaneHeight: 76,
            maximumLivePaneHeight: 420,
            headerHeight: 26,
            resizeHandleHeight: 12
        )

        XCTAssertEqual(layout.transcriptHeight, 402)
        XCTAssertEqual(layout.livePaneHeight, 260)
        XCTAssertTrue(layout.showsResizeHandle)
    }

    func testHiddenTranscriptGivesAllRemainingHeightToTerminal() {
        let layout = CommandTranscriptLayoutPolicy.resolve(
            mode: .off,
            showsTranscript: false,
            containerHeight: 700,
            measuredContentHeight: 0,
            preferredLivePaneHeight: 260,
            minimumLivePaneHeight: 76,
            maximumLivePaneHeight: 420,
            headerHeight: 26,
            resizeHandleHeight: 12
        )

        XCTAssertEqual(layout.transcriptHeight, 0)
        XCTAssertEqual(layout.livePaneHeight, 674)
        XCTAssertFalse(layout.showsResizeHandle)
    }
}
