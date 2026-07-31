import Foundation
import XCTest
@testable import ApexTermCore

final class CommandHistoryTests: XCTestCase {
    func testRecorderKeepsNewestRecordsAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let recorder = CommandHistoryRecorder(fileURL: fileURL, maximumCount: 3)
        let sessionID = UUID()

        for index in 0..<4 {
            recorder.append(
                CommandExecutionRecord(
                    sessionID: sessionID,
                    command: "echo \(index)",
                    output: "\(index)",
                    exitCode: 0,
                    startedAt: Date(timeIntervalSince1970: Double(index)),
                    finishedAt: Date(timeIntervalSince1970: Double(index + 1))
                )
            )
        }

        XCTAssertEqual(recorder.snapshot().map(\.command), ["echo 3", "echo 2", "echo 1"])
        XCTAssertEqual(
            try CommandHistoryStore.load(from: fileURL).map(\.command),
            ["echo 3", "echo 2", "echo 1"]
        )
    }

    func testDeferredAppendPersistsInOrderAfterFlush() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let recorder = CommandHistoryRecorder(fileURL: fileURL, maximumCount: 3)
        let sessionID = UUID()

        for index in 0..<4 {
            recorder.appendDeferred(
                CommandExecutionRecord(
                    sessionID: sessionID,
                    command: "deferred \(index)",
                    output: "\(index)",
                    exitCode: 0,
                    startedAt: Date(timeIntervalSince1970: Double(index)),
                    finishedAt: Date(timeIntervalSince1970: Double(index + 1))
                )
            )
        }
        recorder.flush()

        XCTAssertEqual(
            try CommandHistoryStore.load(from: fileURL).map(\.command),
            ["deferred 3", "deferred 2", "deferred 1"]
        )
    }

    func testRecorderMigratesLegacyJSONIntoSQLiteAndStopsDualWriting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("history.json")
        let databaseURL = directory.appendingPathComponent("events.sqlite")
        let sessionID = UUID()
        let legacyRecords = [
            CommandExecutionRecord(
                sessionID: sessionID,
                command: "legacy 2",
                output: "two",
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 2),
                finishedAt: Date(timeIntervalSince1970: 3)
            ),
            CommandExecutionRecord(
                sessionID: sessionID,
                command: "legacy 1",
                output: "one",
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 1),
                finishedAt: Date(timeIntervalSince1970: 2)
            )
        ]
        try CommandHistoryStore.save(legacyRecords, to: legacyURL)
        let eventStore = try ApexEventStore(fileURL: databaseURL)
        let recorder = CommandHistoryRecorder(
            fileURL: legacyURL,
            eventStore: eventStore,
            maximumCount: 3
        )

        XCTAssertEqual(recorder.snapshot(), legacyRecords)
        XCTAssertEqual(
            try eventStore.commandHistory(limit: 10),
            legacyRecords
        )

        let newest = CommandExecutionRecord(
            sessionID: sessionID,
            command: "sqlite only",
            output: "three",
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 3),
            finishedAt: Date(timeIntervalSince1970: 4)
        )
        recorder.appendDeferred(newest)
        recorder.flush()

        XCTAssertEqual(
            try eventStore.commandHistory(limit: 10).map(\.command),
            ["sqlite only", "legacy 2", "legacy 1"]
        )
        XCTAssertEqual(
            try CommandHistoryStore.load(from: legacyURL),
            legacyRecords
        )

        XCTAssertEqual(recorder.clear(), [])
        XCTAssertEqual(try eventStore.commandHistory(limit: 10), [])
    }

    func testCommandAndOutputCopyFormatIncludesExitCode() {
        let record = CommandExecutionRecord(
            sessionID: UUID(),
            command: "pwd",
            output: "/tmp",
            exitCode: 7,
            startedAt: Date(),
            finishedAt: Date()
        )

        XCTAssertEqual(record.commandAndOutput, "$ pwd\n/tmp\n[exit 7]")
    }
}
