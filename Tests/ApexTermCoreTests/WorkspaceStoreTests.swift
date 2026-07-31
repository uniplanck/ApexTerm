import Foundation
import XCTest
@testable import ApexTermCore

final class WorkspaceStoreTests: XCTestCase {
    func testRoundTripPreservesWorkspaceContextAndSessionIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(fileURL: fileURL)

        let session = TerminalSession(title: "Build", workingDirectory: "/tmp/project")
        let repository = WorkspaceRepositoryReference(
            name: "project",
            path: "/tmp/project",
            role: .primary
        )
        let launchConfiguration = WorkspaceLaunchConfiguration(
            name: "Development",
            steps: [
                .openLocalShell(workingDirectory: "/tmp/project"),
                .runAction(actionID: "pane.split.vertical")
            ],
            isDefault: true
        )
        let note = WorkspaceNote(title: "Next", body: "Run the integration suite")
        let workspace = Workspace(
            name: "Project",
            rootDirectory: "/tmp/project",
            layout: .pane(sessionID: session.id),
            context: WorkspaceContext(
                repositories: [repository],
                launchConfigurations: [launchConfiguration],
                notes: [note]
            )
        )
        let document = WorkspaceDocument(workspaces: [workspace], sessions: [session])

        try await store.save(document)
        let loaded = try await store.loadResult()

        XCTAssertEqual(loaded.document, document)
        XCTAssertFalse(loaded.didMigrate)
        XCTAssertEqual(loaded.document.workspaces.first?.id, workspace.id)
        XCTAssertEqual(loaded.document.sessions.first?.id, session.id)
        XCTAssertEqual(
            loaded.document.workspaces.first?.context.repositories.first?.id,
            repository.id
        )
        XCTAssertEqual(
            loaded.document.workspaces.first?.context.launchConfigurations.first?.id,
            launchConfiguration.id
        )
        XCTAssertEqual(
            loaded.document.workspaces.first?.context.notes.first?.id,
            note.id
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testSchemaV1MigratesRootDirectoryIntoPrimaryRepository() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(fileURL: fileURL)

        let session = TerminalSession(title: "Legacy", workingDirectory: "/tmp/legacy-project")
        let workspace = LegacyWorkspaceV1(
            id: UUID(),
            name: "Legacy Workspace",
            rootDirectory: "/tmp/legacy-project",
            layout: .pane(sessionID: session.id),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let legacyDocument = LegacyWorkspaceDocumentV1(
            schemaVersion: 1,
            workspaces: [workspace],
            sessions: [session]
        )
        try JSONEncoder().encode(legacyDocument).write(to: fileURL, options: .atomic)

        let result = try await store.loadResult()

        XCTAssertEqual(result.migratedFromSchemaVersion, 1)
        XCTAssertEqual(result.document.schemaVersion, WorkspaceDocument.currentSchemaVersion)
        XCTAssertEqual(result.document.workspaces.first?.id, workspace.id)
        XCTAssertEqual(result.document.sessions.first?.id, session.id)
        XCTAssertEqual(result.document.workspaces.first?.context.repositories.count, 1)

        let repository = try XCTUnwrap(
            result.document.workspaces.first?.context.repositories.first
        )
        XCTAssertEqual(repository.id, workspace.id)
        XCTAssertEqual(repository.name, "legacy-project")
        XCTAssertEqual(repository.path, "/tmp/legacy-project")
        XCTAssertEqual(repository.role, .primary)

        try await store.save(result.document)
        let reloaded = try await store.loadResult()
        XCTAssertFalse(reloaded.didMigrate)
        XCTAssertEqual(reloaded.document, result.document)
    }

    func testSchemaV1WithoutRootDirectoryMigratesWithEmptyContext() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(fileURL: fileURL)

        let session = TerminalSession(title: "Legacy")
        let legacyDocument = LegacyWorkspaceDocumentV1(
            schemaVersion: 1,
            workspaces: [
                LegacyWorkspaceV1(
                    id: UUID(),
                    name: "No Root",
                    rootDirectory: nil,
                    layout: .pane(sessionID: session.id),
                    createdAt: Date(timeIntervalSince1970: 100),
                    updatedAt: Date(timeIntervalSince1970: 200)
                )
            ],
            sessions: [session]
        )
        try JSONEncoder().encode(legacyDocument).write(to: fileURL, options: .atomic)

        let result = try await store.loadResult()

        XCTAssertEqual(result.migratedFromSchemaVersion, 1)
        XCTAssertEqual(result.document.schemaVersion, WorkspaceDocument.currentSchemaVersion)
        XCTAssertEqual(result.document.workspaces.first?.context, .empty)
    }

    func testResetTransientSessionStatesClearsPersistedRuntimeState() {
        let sessions = [
            TerminalSession(title: "Local", state: .attached),
            TerminalSession(title: "Remote", kind: .ssh(host: "prod"), state: .reconnecting),
            TerminalSession(title: "Fresh", state: .created)
        ]
        var document = WorkspaceDocument(workspaces: [], sessions: sessions)

        XCTAssertTrue(document.resetTransientSessionStates())
        XCTAssertEqual(document.sessions.map(\.state), [.created, .created, .created])
        XCTAssertFalse(document.resetTransientSessionStates())
    }

    func testMissingFileReturnsCurrentEmptyDocument() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.json")
        let store = WorkspaceStore(fileURL: fileURL)

        let loaded = try await store.loadResult()

        XCTAssertEqual(loaded.document.schemaVersion, WorkspaceDocument.currentSchemaVersion)
        XCTAssertEqual(loaded.document.workspaces, [])
        XCTAssertEqual(loaded.document.sessions, [])
        XCTAssertFalse(loaded.didMigrate)
    }

    func testCorruptFileIsQuarantinedInsteadOfOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("workspaces.json")
        try Data("not-json".utf8).write(to: fileURL)
        let store = WorkspaceStore(fileURL: fileURL)

        do {
            _ = try await store.load()
            XCTFail("Expected corrupt file error")
        } catch let WorkspaceStoreError.corruptFile(quarantinedAt) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedAt.path))
        }
    }

    func testFutureSchemaIsRejectedWithoutQuarantine() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(fileURL: fileURL)
        let document = WorkspaceDocument(
            schemaVersion: WorkspaceDocument.currentSchemaVersion + 1,
            workspaces: [],
            sessions: []
        )
        try await store.save(document)

        do {
            _ = try await store.load()
            XCTFail("Expected unsupported schema")
        } catch let WorkspaceStoreError.unsupportedSchema(found, supported) {
            XCTAssertEqual(found, WorkspaceDocument.currentSchemaVersion + 1)
            XCTAssertEqual(supported, WorkspaceDocument.currentSchemaVersion)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    func testTooOldSchemaIsRejectedWithoutQuarantine() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("workspaces.json")
        let data = Data("{\"schemaVersion\":0,\"workspaces\":[],\"sessions\":[]}".utf8)
        try data.write(to: fileURL)
        let store = WorkspaceStore(fileURL: fileURL)

        do {
            _ = try await store.load()
            XCTFail("Expected unsupported schema")
        } catch let WorkspaceStoreError.unsupportedSchema(found, supported) {
            XCTAssertEqual(found, 0)
            XCTAssertEqual(supported, WorkspaceDocument.currentSchemaVersion)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }
}

private struct LegacyWorkspaceDocumentV1: Encodable {
    var schemaVersion: Int
    var workspaces: [LegacyWorkspaceV1]
    var sessions: [TerminalSession]
}

private struct LegacyWorkspaceV1: Encodable {
    var id: UUID
    var name: String
    var rootDirectory: String?
    var layout: SplitNode
    var createdAt: Date
    var updatedAt: Date
}
