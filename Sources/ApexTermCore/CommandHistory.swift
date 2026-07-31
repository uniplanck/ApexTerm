import Foundation

public struct CommandExecutionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var command: String
    public var output: String
    public var exitCode: Int
    public var startedAt: Date
    public var finishedAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        command: String,
        output: String,
        exitCode: Int,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var commandAndOutput: String {
        let body = output.isEmpty ? command : "$ \(command)\n\(output)"
        return body + "\n[exit \(exitCode)]"
    }
}

public enum CommandHistoryStore {
    public static func load(from fileURL: URL) throws -> [CommandExecutionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            [CommandExecutionRecord].self,
            from: Data(contentsOf: fileURL)
        )
    }

    public static func save(
        _ records: [CommandExecutionRecord],
        to fileURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(records).write(to: fileURL, options: [.atomic])
    }
}

public final class CommandHistoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(
        label: "app.apexterm.command-history.persistence",
        qos: .utility
    )
    private let fileURL: URL
    private let eventStore: ApexEventStore?
    private let maximumCount: Int
    private var records: [CommandExecutionRecord]

    public init(
        fileURL: URL,
        eventStore: ApexEventStore? = nil,
        maximumCount: Int = 200
    ) {
        self.fileURL = fileURL
        self.eventStore = eventStore
        self.maximumCount = max(3, maximumCount)

        let legacyRecords = (try? CommandHistoryStore.load(from: fileURL)) ?? []
        if let eventStore {
            let storedRecords = (try? eventStore.commandHistory(
                limit: self.maximumCount
            )) ?? []
            if storedRecords.isEmpty, !legacyRecords.isEmpty {
                try? eventStore.importCommandHistory(legacyRecords)
                try? eventStore.prune(
                    kind: .command,
                    keeping: self.maximumCount
                )
                self.records = Array(legacyRecords.prefix(self.maximumCount))
            } else {
                self.records = storedRecords
            }
        } else {
            self.records = Array(legacyRecords.prefix(self.maximumCount))
        }
    }

    @discardableResult
    public func append(_ record: CommandExecutionRecord) -> [CommandExecutionRecord] {
        let snapshot = insert(record)
        persistenceQueue.sync { [eventStore, fileURL, maximumCount] in
            if let eventStore {
                try? eventStore.appendCommand(record)
                try? eventStore.prune(
                    kind: .command,
                    keeping: maximumCount
                )
            } else {
                try? CommandHistoryStore.save(snapshot, to: fileURL)
            }
        }
        return snapshot
    }

    @discardableResult
    public func appendDeferred(
        _ record: CommandExecutionRecord
    ) -> [CommandExecutionRecord] {
        let snapshot = insert(record)
        persistenceQueue.async { [eventStore, fileURL, maximumCount] in
            if let eventStore {
                try? eventStore.appendCommand(record)
                try? eventStore.prune(
                    kind: .command,
                    keeping: maximumCount
                )
            } else {
                try? CommandHistoryStore.save(snapshot, to: fileURL)
            }
        }
        return snapshot
    }

    public func snapshot() -> [CommandExecutionRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    public func flush() {
        persistenceQueue.sync {}
    }

    public func clear() -> [CommandExecutionRecord] {
        lock.lock()
        records.removeAll()
        let snapshot = records
        lock.unlock()
        persistenceQueue.sync { [eventStore, fileURL] in
            if let eventStore {
                try? eventStore.delete(kind: .command)
            } else {
                try? CommandHistoryStore.save(snapshot, to: fileURL)
            }
        }
        return snapshot
    }

    private func insert(
        _ record: CommandExecutionRecord
    ) -> [CommandExecutionRecord] {
        lock.lock()
        defer { lock.unlock() }
        records.insert(record, at: 0)
        if records.count > maximumCount {
            records.removeLast(records.count - maximumCount)
        }
        return records
    }
}
