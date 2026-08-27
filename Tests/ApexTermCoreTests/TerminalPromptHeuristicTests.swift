import ApexTermCore
import XCTest

final class TerminalPromptHeuristicTests: XCTestCase {
    func testRecognizesLocalAndRemoteShellPrompts() {
        XCTAssertTrue(
            TerminalPromptHeuristic.looksLikePromptLine(
                "(base) naomac@MacBook-Nao ~ %"
            )
        )
        XCTAssertTrue(
            TerminalPromptHeuristic.looksLikePromptLine(
                "ubuntu@ip-172-31-10-18:~$"
            )
        )
        XCTAssertTrue(
            TerminalPromptHeuristic.looksLikePromptLine("root@server:/etc#")
        )
    }

    func testRejectsOrdinaryOutputAndUsesLastNonEmptyLine() {
        XCTAssertFalse(
            TerminalPromptHeuristic.looksLikePromptLine(
                "PASS: runtime-api-key installed"
            )
        )
        XCTAssertTrue(
            TerminalPromptHeuristic.isPromptReady(
                bufferText: "output line\nubuntu@host:~$   \n"
            )
        )
        XCTAssertFalse(
            TerminalPromptHeuristic.isPromptReady(
                bufferText: "ubuntu@host:~$\ncommand output still running\n"
            )
        )
    }
}
