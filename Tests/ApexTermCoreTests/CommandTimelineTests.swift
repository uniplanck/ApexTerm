import Foundation
import XCTest
@testable import ApexTermCore

final class CommandTimelineTests: XCTestCase {
    func testEngineMergesCommandsAndAgentEventsNewestFirst() {
        let sessionID = UUID()
        let command = CommandExecutionRecord(
            sessionID: sessionID,
            command: "swift test",
            output: "passed",
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20)
        )
        let agent = UniversalAgentEvent(
            id: UUID(),
            reference: "GAG/job-1",
            title: "Review tests",
            status: "running",
            summary: "Inspecting failures",
            updatedAt: Date(timeIntervalSince1970: 30)
        )

        let entries = CommandTimelineEngine().entries(
            in: CommandTimelineSnapshot(
                commands: [command],
                agentEvents: [agent],
                sessionTitles: [sessionID: "Build"]
            )
        )

        XCTAssertEqual(entries.map(\.kind), [.agent, .command])
        XCTAssertEqual(entries[1].subtitle, "Build · exit 0")
    }

    func testEngineFiltersFailuresSearchAndSelectedSession() {
        let selectedSessionID = UUID()
        let otherSessionID = UUID()
        let snapshot = CommandTimelineSnapshot(
            commands: [
                CommandExecutionRecord(
                    sessionID: selectedSessionID,
                    command: "deploy preview",
                    output: "TOKEN=secret-value",
                    exitCode: 7,
                    startedAt: Date(timeIntervalSince1970: 1),
                    finishedAt: Date(timeIntervalSince1970: 2)
                ),
                CommandExecutionRecord(
                    sessionID: otherSessionID,
                    command: "swift build",
                    output: "done",
                    exitCode: 0,
                    startedAt: Date(timeIntervalSince1970: 3),
                    finishedAt: Date(timeIntervalSince1970: 4)
                )
            ],
            agentEvents: [
                UniversalAgentEvent(
                    id: UUID(),
                    reference: "GAG/job-failed",
                    title: "Deploy agent",
                    status: "failed",
                    summary: "Remote rejected",
                    updatedAt: Date(timeIntervalSince1970: 5)
                )
            ]
        )
        let engine = CommandTimelineEngine()

        XCTAssertEqual(
            engine.entries(in: snapshot, filter: .failures).count,
            2
        )
        XCTAssertEqual(
            engine.entries(in: snapshot, query: "preview").map(\.kind),
            [.command]
        )
        let selected = engine.entries(
            in: snapshot,
            sessionID: selectedSessionID
        )
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.sessionID, selectedSessionID)
    }

    func testRedactedExportRemovesSecretsAndMetadataExportOmitsContent() {
        let entry = CommandTimelineEntry(
            id: "command:test",
            kind: .command,
            title: "curl --token top-secret",
            subtitle: "Build · exit 1",
            detail: "Authorization: Bearer abcdefghijklmnop\nTOKEN=secret-value",
            status: "failed",
            timestamp: Date(timeIntervalSince1970: 100),
            sessionID: UUID(),
            target: .command(recordID: UUID(), sessionID: UUID()),
            isFailure: true
        )
        let exporter = CommandTimelineExporter()

        let redacted = exporter.markdown(
            entries: [entry],
            privacy: .redacted,
            generatedAt: Date(timeIntervalSince1970: 200),
            redactor: DiagnosticRedactor(homeDirectory: nil)
        )
        XCTAssertFalse(redacted.contains("top-secret"))
        XCTAssertFalse(redacted.contains("secret-value"))
        XCTAssertTrue(redacted.contains("<redacted>"))

        let metadata = exporter.markdown(
            entries: [entry],
            privacy: .metadataOnly,
            generatedAt: Date(timeIntervalSince1970: 200)
        )
        XCTAssertTrue(metadata.contains("Command content omitted"))
        XCTAssertFalse(metadata.contains("curl"))
        XCTAssertFalse(metadata.contains("Authorization"))
    }

    func testFullExportKeepsContentAndBoundsLargeDetails() {
        let marker = String(repeating: "x", count: 20_100)
        let entry = CommandTimelineEntry(
            id: "agent:test",
            kind: .agent,
            title: "Agent run",
            subtitle: "succeeded · GAG/job-1",
            detail: marker,
            status: "succeeded",
            timestamp: Date(timeIntervalSince1970: 100),
            target: .agentJob(reference: "GAG/job-1", conversationURL: nil),
            isFailure: false
        )

        let exported = CommandTimelineExporter().markdown(
            entries: [entry],
            privacy: .full,
            generatedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertTrue(exported.contains("Agent run"))
        XCTAssertTrue(exported.contains("[truncated]"))
        XCTAssertLessThan(exported.count, marker.count + 1_000)
    }
}
