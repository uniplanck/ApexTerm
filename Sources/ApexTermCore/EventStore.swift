import Foundation
import SQLite3

public enum ApexEventKind: String, Codable, CaseIterable, Sendable {
    case command
    case agent
    case workspace
    case workflow
    case system
}

public struct ApexStoredEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ApexEventKind
    public var workspaceID: UUID?
    public var sessionID: UUID?
    public var subjectID: String?
    public var occurredAt: Date
    public var payload: Data

    public init(
        id: UUID = UUID(),
        kind: ApexEventKind,
        workspaceID: UUID? = nil,
        sessionID: UUID? = nil,
        subjectID: String? = nil,
        occurredAt: Date = Date(),
        payload: Data
    ) {
        self.id = id
        self.kind = kind
        self.workspaceID = workspaceID
        self.sessionID = sessionID
        self.subjectID = subjectID
        self.occurredAt = occurredAt
        self.payload = payload
    }
}

public enum ApexEventStoreError: Error, Equatable {
    case openFailed(String)
    case unsupportedSchema(found: Int, supported: Int)
    case statementFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case decodeFailed(String)
}

public final class ApexEventStore: @unchecked Sendable {
    public static let currentSchemaVersion = 1

    public let fileURL: URL

    private let queue = DispatchQueue(
        label: "app.apexterm.event-store",
        qos: .utility
    )
    private var database: OpaquePointer?

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(fileURL.path, &opened, flags, nil)
        guard status == SQLITE_OK, let opened else {
            let message = opened.flatMap { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite3_open_v2 returned \(status)"
            if let opened { sqlite3_close_v2(opened) }
            throw ApexEventStoreError.openFailed(message)
        }
        database = opened
        sqlite3_busy_timeout(opened, 5_000)

        do {
            try configureAndMigrate()
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            sqlite3_close_v2(opened)
            database = nil
            throw error
        }
    }

    deinit {
        if let database {
            sqlite3_close_v2(database)
        }
    }

    public func append(_ event: ApexStoredEvent) throws {
        try queue.sync {
            try insert(event)
        }
    }

    public func appendJSON<Payload: Encodable>(
        kind: ApexEventKind,
        workspaceID: UUID? = nil,
        sessionID: UUID? = nil,
        subjectID: String? = nil,
        occurredAt: Date = Date(),
        payload: Payload
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try append(
            ApexStoredEvent(
                kind: kind,
                workspaceID: workspaceID,
                sessionID: sessionID,
                subjectID: subjectID,
                occurredAt: occurredAt,
                payload: data
            )
        )
    }

    public func events(
        kind: ApexEventKind? = nil,
        workspaceID: UUID? = nil,
        sessionID: UUID? = nil,
        subjectID: String? = nil,
        limit: Int = 200
    ) throws -> [ApexStoredEvent] {
        try queue.sync {
            var sql = """
                SELECT id, kind, workspace_id, session_id, subject_id, occurred_at, payload
                FROM events
                WHERE 1 = 1
                """
            var values: [SQLiteValue] = []
            if let kind {
                sql += " AND kind = ?"
                values.append(.text(kind.rawValue))
            }
            if let workspaceID {
                sql += " AND workspace_id = ?"
                values.append(.text(workspaceID.uuidString))
            }
            if let sessionID {
                sql += " AND session_id = ?"
                values.append(.text(sessionID.uuidString))
            }
            if let subjectID {
                sql += " AND subject_id = ?"
                values.append(.text(subjectID))
            }
            sql += " ORDER BY occurred_at DESC, rowid DESC LIMIT ?"
            values.append(.integer(Int64(max(1, min(limit, 10_000)))))

            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(values, to: statement)

            var result: [ApexStoredEvent] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_ROW {
                    result.append(try readEvent(from: statement))
                } else if status == SQLITE_DONE {
                    return result
                } else {
                    throw ApexEventStoreError.stepFailed(errorMessage())
                }
            }
        }
    }

    public func count(kind: ApexEventKind? = nil) throws -> Int {
        try queue.sync {
            let sql = kind == nil
                ? "SELECT COUNT(*) FROM events"
                : "SELECT COUNT(*) FROM events WHERE kind = ?"
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            if let kind {
                try bind([.text(kind.rawValue)], to: statement)
            }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw ApexEventStoreError.stepFailed(errorMessage())
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    public func delete(kind: ApexEventKind) throws {
        try queue.sync {
            let statement = try prepare("DELETE FROM events WHERE kind = ?")
            defer { sqlite3_finalize(statement) }
            try bind([.text(kind.rawValue)], to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ApexEventStoreError.stepFailed(errorMessage())
            }
        }
    }

    public func prune(kind: ApexEventKind, keeping maximumCount: Int) throws {
        try queue.sync {
            let keep = max(0, maximumCount)
            if keep == 0 {
                let statement = try prepare("DELETE FROM events WHERE kind = ?")
                defer { sqlite3_finalize(statement) }
                try bind([.text(kind.rawValue)], to: statement)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw ApexEventStoreError.stepFailed(errorMessage())
                }
                return
            }

            let statement = try prepare(
                """
                DELETE FROM events
                WHERE kind = ?
                  AND id NOT IN (
                    SELECT id
                    FROM events
                    WHERE kind = ?
                    ORDER BY occurred_at DESC, rowid DESC
                    LIMIT ?
                  )
                """
            )
            defer { sqlite3_finalize(statement) }
            try bind(
                [
                    .text(kind.rawValue),
                    .text(kind.rawValue),
                    .integer(Int64(keep))
                ],
                to: statement
            )
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ApexEventStoreError.stepFailed(errorMessage())
            }
        }
    }

    public func appendCommand(_ record: CommandExecutionRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try append(
            ApexStoredEvent(
                id: record.id,
                kind: .command,
                sessionID: record.sessionID,
                subjectID: record.command,
                occurredAt: record.finishedAt,
                payload: try encoder.encode(record)
            )
        )
    }

    public func importCommandHistory(
        _ records: [CommandExecutionRecord]
    ) throws {
        guard !records.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try queue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                for record in records {
                    try insert(
                        ApexStoredEvent(
                            id: record.id,
                            kind: .command,
                            sessionID: record.sessionID,
                            subjectID: record.command,
                            occurredAt: record.finishedAt,
                            payload: try encoder.encode(record)
                        )
                    )
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func commandHistory(limit: Int = 200) throws -> [CommandExecutionRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try events(kind: .command, limit: limit).map { event in
            do {
                return try decoder.decode(
                    CommandExecutionRecord.self,
                    from: event.payload
                )
            } catch {
                throw ApexEventStoreError.decodeFailed(
                    "Command event \(event.id.uuidString): \(error.localizedDescription)"
                )
            }
        }
    }

    private func configureAndMigrate() throws {
        try queue.sync {
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("PRAGMA foreign_keys = ON")

            let version = try schemaVersion()
            guard version <= Self.currentSchemaVersion else {
                throw ApexEventStoreError.unsupportedSchema(
                    found: version,
                    supported: Self.currentSchemaVersion
                )
            }
            if version == 0 {
                try execute(
                    """
                    CREATE TABLE IF NOT EXISTS events (
                        id TEXT PRIMARY KEY NOT NULL,
                        kind TEXT NOT NULL,
                        workspace_id TEXT,
                        session_id TEXT,
                        subject_id TEXT,
                        occurred_at REAL NOT NULL,
                        payload BLOB NOT NULL
                    )
                    """
                )
                try execute(
                    "CREATE INDEX IF NOT EXISTS idx_events_kind_time ON events(kind, occurred_at DESC)"
                )
                try execute(
                    "CREATE INDEX IF NOT EXISTS idx_events_workspace_time ON events(workspace_id, occurred_at DESC)"
                )
                try execute(
                    "CREATE INDEX IF NOT EXISTS idx_events_session_time ON events(session_id, occurred_at DESC)"
                )
                try execute(
                    "PRAGMA user_version = \(Self.currentSchemaVersion)"
                )
            }
        }
    }

    private func schemaVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ApexEventStoreError.stepFailed(errorMessage())
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func insert(_ event: ApexStoredEvent) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO events (
                id, kind, workspace_id, session_id, subject_id, occurred_at, payload
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(
            [
                .text(event.id.uuidString),
                .text(event.kind.rawValue),
                .optionalText(event.workspaceID?.uuidString),
                .optionalText(event.sessionID?.uuidString),
                .optionalText(event.subjectID),
                .double(event.occurredAt.timeIntervalSince1970),
                .blob(event.payload)
            ],
            to: statement
        )
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ApexEventStoreError.stepFailed(errorMessage())
        }
    }

    private func readEvent(
        from statement: OpaquePointer
    ) throws -> ApexStoredEvent {
        guard let idText = textColumn(statement, index: 0),
              let id = UUID(uuidString: idText),
              let kindText = textColumn(statement, index: 1),
              let kind = ApexEventKind(rawValue: kindText) else {
            throw ApexEventStoreError.decodeFailed("Invalid event identity")
        }
        let workspaceID = textColumn(statement, index: 2).flatMap(UUID.init)
        let sessionID = textColumn(statement, index: 3).flatMap(UUID.init)
        let subjectID = textColumn(statement, index: 4)
        let occurredAt = Date(
            timeIntervalSince1970: sqlite3_column_double(statement, 5)
        )
        let payloadLength = Int(sqlite3_column_bytes(statement, 6))
        let payload: Data
        if payloadLength == 0 {
            payload = Data()
        } else if let bytes = sqlite3_column_blob(statement, 6) {
            payload = Data(bytes: bytes, count: payloadLength)
        } else {
            throw ApexEventStoreError.decodeFailed("Missing event payload")
        }
        return ApexStoredEvent(
            id: id,
            kind: kind,
            workspaceID: workspaceID,
            sessionID: sessionID,
            subjectID: subjectID,
            occurredAt: occurredAt,
            payload: payload
        )
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else {
            throw ApexEventStoreError.openFailed("Database is closed")
        }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw ApexEventStoreError.statementFailed(errorMessage())
        }
        return statement
    }

    private func bind(
        _ values: [SQLiteValue],
        to statement: OpaquePointer
    ) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case let .text(text):
                status = sqlite3_bind_text(
                    statement,
                    index,
                    text,
                    -1,
                    sqliteTransient
                )
            case let .optionalText(text):
                if let text {
                    status = sqlite3_bind_text(
                        statement,
                        index,
                        text,
                        -1,
                        sqliteTransient
                    )
                } else {
                    status = sqlite3_bind_null(statement, index)
                }
            case let .integer(integer):
                status = sqlite3_bind_int64(statement, index, integer)
            case let .double(double):
                status = sqlite3_bind_double(statement, index, double)
            case let .blob(data):
                status = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(
                        statement,
                        index,
                        bytes.baseAddress,
                        Int32(data.count),
                        sqliteTransient
                    )
                }
            }
            guard status == SQLITE_OK else {
                throw ApexEventStoreError.bindFailed(errorMessage())
            }
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw ApexEventStoreError.openFailed("Database is closed")
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        if status != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) }
                ?? errorMessage()
            sqlite3_free(errorPointer)
            throw ApexEventStoreError.statementFailed(message)
        }
    }

    private func errorMessage() -> String {
        guard let database else { return "Database is closed" }
        return String(cString: sqlite3_errmsg(database))
    }

    private func textColumn(
        _ statement: OpaquePointer,
        index: Int32
    ) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }
}

private enum SQLiteValue {
    case text(String)
    case optionalText(String?)
    case integer(Int64)
    case double(Double)
    case blob(Data)
}

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
