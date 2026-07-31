import Foundation
import XCTest
@testable import ApexTermCore

final class EventStoreTests: XCTestCase {
    private struct WorkflowPayload: Codable, Equatable {
        var title: String
        var status: String
    }

    func testGenericEventsRoundTripWithFiltersAndSecurePermissions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("events.sqlite")
        let store = try ApexEventStore(fileURL: fileURL)
        let workspaceID = UUID()
        let sessionID = UUID()

        try store.appendJSON(
            kind: .workflow,
            workspaceID: workspaceID,
            subjectID: "build",
            occurredAt: Date(timeIntervalSince1970: 10),
            payload: WorkflowPayload(title: "Build", status: "running")
        )
        try store.appendJSON(
            kind: .command,
            workspaceID: workspaceID,
            sessionID: sessionID,
            subjectID: "pwd",
            occurredAt: Date(timeIntervalSince1970: 20),
            payload: WorkflowPayload(title: "Command", status: "done")
        )

        let workflowEvents = try store.events(
            kind: .workflow,
            workspaceID: workspaceID
        )
        XCTAssertEqual(workflowEvents.count, 1)
        XCTAssertEqual(workflowEvents[0].subjectID, "build")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(
            try decoder.decode(
                WorkflowPayload.self,
                from: workflowEvents[0].payload
            ),
            WorkflowPayload(title: "Build", status: "running")
        )
        XCTAssertEqual(try store.count(), 2)
        XCTAssertEqual(try store.count(kind: .command), 1)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue ?? 0, 0o600)
    }

    func testCommandHistoryImportOrderingPruningAndDeletion() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ApexEventStore(
            fileURL: directory.appendingPathComponent("events.sqlite")
        )
        let sessionID = UUID()
        var records: [CommandExecutionRecord] = []
        for index in 0..<4 {
            let startedAt = Date(timeIntervalSince1970: Double(index))
            let finishedAt = Date(timeIntervalSince1970: Double(index + 1))
            records.append(
                CommandExecutionRecord(
                    id: UUID(),
                    sessionID: sessionID,
                    command: "echo \(index)",
                    output: String(index),
                    exitCode: index == 3 ? 1 : 0,
                    startedAt: startedAt,
                    finishedAt: finishedAt
                )
            )
        }

        try store.importCommandHistory(records)
        try store.importCommandHistory(records)
        XCTAssertEqual(try store.count(kind: .command), 4)
        XCTAssertEqual(
            try store.commandHistory(limit: 10).map(\.command),
            ["echo 3", "echo 2", "echo 1", "echo 0"]
        )

        try store.prune(kind: .command, keeping: 2)
        XCTAssertEqual(
            try store.commandHistory(limit: 10).map(\.command),
            ["echo 3", "echo 2"]
        )

        try store.delete(kind: .command)
        XCTAssertEqual(try store.commandHistory(limit: 10), [])
    }

    func testEventsCanBeQueriedBySessionAndSubject() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ApexEventStore(
            fileURL: directory.appendingPathComponent("events.sqlite")
        )
        let firstSessionID = UUID()
        let secondSessionID = UUID()

        for (sessionID, subject) in [
            (firstSessionID, "first"),
            (secondSessionID, "second")
        ] {
            try store.appendJSON(
                kind: .system,
                sessionID: sessionID,
                subjectID: subject,
                payload: WorkflowPayload(title: subject, status: "ok")
            )
        }

        XCTAssertEqual(
            try store.events(sessionID: secondSessionID).map(\.subjectID),
            ["second"]
        )
        XCTAssertEqual(
            try store.events(subjectID: "first").map(\.sessionID),
            [firstSessionID]
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
