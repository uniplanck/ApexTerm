import XCTest
@testable import ApexTermCore

final class TerminalIntelligenceTests: XCTestCase {
    func testSmartPasteAllowsSimpleSingleLineText() {
        let assessment = SmartPastePolicy().assess("git status")
        XCTAssertFalse(assessment.requiresConfirmation)
        XCTAssertEqual(assessment.lineCount, 1)
        XCTAssertEqual(assessment.riskDecision.level, .allow)
    }

    func testSmartPasteConfirmsMultilineTrailingNewlineAndRisk() {
        let policy = SmartPastePolicy()
        XCTAssertTrue(policy.assess("echo one\necho two").requiresConfirmation)
        XCTAssertTrue(policy.assess("git status\n").requiresConfirmation)
        let dangerous = policy.assess("sudo rm -rf /")
        XCTAssertTrue(dangerous.requiresConfirmation)
        XCTAssertEqual(dangerous.riskDecision.level, .requireApproval)
    }

    func testSmartPasteCanSkipMultilineOnlyConfirmation() {
        let policy = SmartPastePolicy()
        XCTAssertFalse(
            policy.assess(
                "echo one\necho two",
                confirmMultiline: false
            ).requiresConfirmation
        )
        XCTAssertTrue(
            policy.assess(
                "echo one\necho two\n",
                confirmMultiline: false
            ).requiresConfirmation
        )
        XCTAssertTrue(
            policy.assess(
                "sudo rm -rf /\necho done",
                confirmMultiline: false
            ).requiresConfirmation
        )
    }

    func testSmartPastePreviewKeepsBeginningAndEnd() {
        let text = String(repeating: "A", count: 1_500) + "END"
        let preview = SmartPastePolicy(maximumPreviewCharacters: 300).preview(text)
        XCTAssertTrue(preview.hasPrefix("AAA"))
        XCTAssertTrue(preview.hasSuffix("END"))
        XCTAssertTrue(preview.contains("省略"))
    }

    func testTerminalPastePayloadWrapsMultilineTextAsOneBracketedPaste() {
        let text = "echo one\necho two"
        XCTAssertEqual(
            TerminalPastePayload.bytes(for: text, bracketed: false),
            Array(text.utf8)
        )
        XCTAssertEqual(
            TerminalPastePayload.bytes(for: text, bracketed: true),
            Array("\u{001B}[200~\(text)\u{001B}[201~".utf8)
        )
    }

    func testQuickFixExtractsGitUpstreamCommand() {
        let record = CommandExecutionRecord(
            sessionID: UUID(),
            command: "git push",
            output: "fatal: no upstream branch\n  git push --set-upstream origin feature/apex",
            exitCode: 128,
            startedAt: Date(),
            finishedAt: Date()
        )
        XCTAssertEqual(
            TerminalQuickFixEngine().suggestions(for: record).first?.command,
            "git push --set-upstream origin feature/apex"
        )
    }

    func testQuickFixDetectsPortAndGitTypo() {
        let portRecord = CommandExecutionRecord(
            sessionID: UUID(),
            command: "npm run dev",
            output: "Error: listen EADDRINUSE: address already in use :::3000",
            exitCode: 1,
            startedAt: Date(),
            finishedAt: Date()
        )
        XCTAssertEqual(
            TerminalQuickFixEngine().suggestions(for: portRecord).first?.command,
            "lsof -nP -iTCP:3000 -sTCP:LISTEN"
        )

        let gitRecord = CommandExecutionRecord(
            sessionID: UUID(),
            command: "git statsu",
            output: "git: 'statsu' is not a git command.\n\nThe most similar command is\n\tstatus",
            exitCode: 1,
            startedAt: Date(),
            finishedAt: Date()
        )
        XCTAssertTrue(
            TerminalQuickFixEngine().suggestions(for: gitRecord).contains {
                $0.command == "git status"
            }
        )
    }

    func testSuccessfulCommandsDoNotReceiveQuickFixes() {
        let record = CommandExecutionRecord(
            sessionID: UUID(),
            command: "git status",
            output: "clean",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )
        XCTAssertTrue(TerminalQuickFixEngine().suggestions(for: record).isEmpty)
    }

    func testOutputDetectorFindsURLFileLineAndHashWithoutDuplicates() {
        let output = """
        Open https://example.com/docs.
        Error at Sources/App.swift:42
        commit abcdef1234567890 and abcdef1234567890
        """
        let items = TerminalOutputDetector().detect(in: output)
        XCTAssertTrue(items.contains { $0.kind == .url && $0.value == "https://example.com/docs" })
        XCTAssertTrue(items.contains { $0.kind == .fileLine && $0.value == "Sources/App.swift" && $0.line == 42 })
        XCTAssertEqual(items.filter { $0.kind == .gitHash }.count, 1)
    }

    func testOutputPresentationBoundsRenderedTextButPreservesTail() {
        let output = String(repeating: "x", count: 40_000) + "TAIL"
        let preview = TerminalOutputPresentation.preview(output, maximumCharacters: 10_000)
        XCTAssertTrue(preview.isTruncated)
        XCTAssertEqual(preview.omittedCharacterCount, output.count - 10_000)
        XCTAssertTrue(preview.text.hasSuffix("TAIL"))
        XCTAssertLessThan(preview.text.count, output.count)
    }

    func testInsightCacheReturnsStableBoundedAnalysis() {
        let record = CommandExecutionRecord(
            sessionID: UUID(),
            command: "npm run dev",
            output: "EADDRINUSE :::4173 https://localhost:4173",
            exitCode: 1,
            startedAt: Date(),
            finishedAt: Date()
        )
        let cache = TerminalInsightCache(maximumCount: 20)
        let first = cache.insights(for: record)
        let second = cache.insights(for: record)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.quickFixes.first?.command, "lsof -nP -iTCP:4173 -sTCP:LISTEN")
        XCTAssertTrue(first.detectedItems.contains { $0.kind == .url })
    }
}
