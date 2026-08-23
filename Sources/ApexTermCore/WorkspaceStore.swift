import Foundation

public enum WorkspaceStoreError: Error, Equatable {
    case unsupportedSchema(found: Int, supported: Int)
    case corruptFile(quarantinedAt: URL)
}

public struct WorkspaceLoadResult: Equatable, Sendable {
    public var document: WorkspaceDocument
    public var migratedFromSchemaVersion: Int?

    public init(
        document: WorkspaceDocument,
        migratedFromSchemaVersion: Int? = nil
    ) {
        self.document = document
        self.migratedFromSchemaVersion = migratedFromSchemaVersion
    }

    public var didMigrate: Bool {
        migratedFromSchemaVersion != nil
    }
}

public actor WorkspaceStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> WorkspaceDocument {
        try loadResult().document
    }

    public func loadResult() throws -> WorkspaceLoadResult {
        try Self.loadResultSynchronously(from: fileURL)
    }

    public func save(_ document: WorkspaceDocument) throws {
        try Self.saveSynchronously(document, to: fileURL)
    }

    public nonisolated static func loadSynchronously(
        from fileURL: URL
    ) throws -> WorkspaceDocument {
        try loadResultSynchronously(from: fileURL).document
    }

    public nonisolated static func loadResultSynchronously(
        from fileURL: URL
    ) throws -> WorkspaceLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return WorkspaceLoadResult(
                document: WorkspaceDocument(workspaces: [], sessions: [])
            )
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try decoder().decode(SchemaEnvelope.self, from: data)
            guard envelope.schemaVersion >= WorkspaceDocument.minimumSupportedSchemaVersion,
                  envelope.schemaVersion <= WorkspaceDocument.currentSchemaVersion else {
                throw WorkspaceStoreError.unsupportedSchema(
                    found: envelope.schemaVersion,
                    supported: WorkspaceDocument.currentSchemaVersion
                )
            }

            let document = try decoder().decode(WorkspaceDocument.self, from: data)
            return migrateToCurrentSchema(document)
        } catch let error as WorkspaceStoreError {
            throw error
        } catch {
            let quarantineURL = try quarantineCorruptFile(at: fileURL)
            throw WorkspaceStoreError.corruptFile(quarantinedAt: quarantineURL)
        }
    }

    public nonisolated static func saveSynchronously(
        _ document: WorkspaceDocument,
        to fileURL: URL
    ) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try encoder().encode(document)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private nonisolated static func migrateToCurrentSchema(
        _ source: WorkspaceDocument
    ) -> WorkspaceLoadResult {
        guard source.schemaVersion < WorkspaceDocument.currentSchemaVersion else {
            return WorkspaceLoadResult(document: source)
        }

        var document = source
        let sourceVersion = source.schemaVersion

        if sourceVersion == 1 {
            for index in document.workspaces.indices {
                guard document.workspaces[index].context.repositories.isEmpty,
                      let rootDirectory = document.workspaces[index].rootDirectory,
                      !rootDirectory.isEmpty else {
                    continue
                }
                let pathURL = URL(fileURLWithPath: rootDirectory, isDirectory: true)
                let inferredName = pathURL.lastPathComponent.isEmpty
                    ? document.workspaces[index].name
                    : pathURL.lastPathComponent
                document.workspaces[index].context.repositories = [
                    WorkspaceRepositoryReference(
                        id: document.workspaces[index].id,
                        name: inferredName,
                        path: rootDirectory,
                        role: .primary
                    )
                ]
            }
            document.schemaVersion = 2
        }

        if document.schemaVersion == 2 {
            for index in document.workspaces.indices {
                document.workspaces[index].layout = migratePaneLeavesToColumns(
                    document.workspaces[index].layout
                )
            }
            document.schemaVersion = 3
        }

        return WorkspaceLoadResult(
            document: document,
            migratedFromSchemaVersion: sourceVersion
        )
    }

    private nonisolated static func migratePaneLeavesToColumns(
        _ node: SplitNode
    ) -> SplitNode {
        switch node {
        case let .pane(sessionID):
            return .column(TerminalColumn(sessionID: sessionID))
        case .column:
            return node
        case let .split(axis, ratio, first, second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: migratePaneLeavesToColumns(first),
                second: migratePaneLeavesToColumns(second)
            )
        }
    }

    private struct SchemaEnvelope: Decodable {
        var schemaVersion: Int
    }

    private nonisolated static func encoder() -> JSONEncoder {
        JSONEncoder()
    }

    private nonisolated static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    private nonisolated static func quarantineCorruptFile(
        at fileURL: URL
    ) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantineURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp).json")
        try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
        return quarantineURL
    }
}
