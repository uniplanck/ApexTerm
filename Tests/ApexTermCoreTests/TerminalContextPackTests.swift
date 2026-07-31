import Foundation
import XCTest
@testable import ApexTermCore

final class TerminalContextPackTests: XCTestCase {
    func testContextPackBoundsOutputAndRedactsSecretsAndHomePath() {
        let record = CommandExecutionRecord(
            sessionID: UUID(),
            command: "TOKEN=super-secret curl -H 'Authorization: Bearer abc.def.ghi' /Users/example/project",
            output: String(repeating: "x", count: 500) + "\nsk-abcdefghijklmnop\n/Users/example/project/error.swift:42",
            exitCode: 1,
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 12.5)
        )
        let redactor = DiagnosticRedactor(homeDirectory: "/Users/example")

        let pack = TerminalContextPackBuilder.markdown(
            record: record,
            sessionTitle: "Local Shell",
            workingDirectory: "/Users/example/project",
            maximumOutputCharacters: 240,
            redactor: redactor
        )

        XCTAssertTrue(pack.contains("ApexTerm Context Pack"))
        XCTAssertTrue(pack.contains("Exit code: 1"))
        XCTAssertTrue(pack.contains("Duration: 2.50s"))
        XCTAssertTrue(pack.contains("truncated to the last 240 characters"))
        XCTAssertTrue(pack.contains("TOKEN=<redacted>"))
        XCTAssertTrue(pack.contains("Authorization: Bearer <redacted>"))
        XCTAssertTrue(pack.contains("<redacted-openai-key>"))
        XCTAssertTrue(pack.contains("~/project"))
        XCTAssertFalse(pack.contains("super-secret"))
        XCTAssertFalse(pack.contains("abc.def.ghi"))
        XCTAssertFalse(pack.contains("/Users/example"))
    }

    func testAgentPromptIsReviewOnlyAndIncludesContext() {
        let record = CommandExecutionRecord(
            sessionID: UUID(),
            command: "swift test",
            output: "error: failed",
            exitCode: 1,
            startedAt: Date(),
            finishedAt: Date()
        )

        let prompt = TerminalContextPackBuilder.agentPrompt(
            record: record,
            sessionTitle: "Build",
            workingDirectory: "/tmp/project"
        )

        XCTAssertTrue(prompt.contains("most likely root cause"))
        XCTAssertTrue(prompt.contains("copy-paste verification command"))
        XCTAssertTrue(prompt.contains("Do not execute commands"))
        XCTAssertTrue(prompt.contains("swift test"))
        XCTAssertTrue(prompt.contains("error: failed"))
    }
}
