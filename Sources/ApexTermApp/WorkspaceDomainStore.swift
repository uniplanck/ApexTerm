import ApexTermCore
import Foundation

struct WorkspaceDomainStore: Equatable, Sendable {
    var workspaces: [Workspace]
    var sessions: [TerminalSession]
    var selectedWorkspaceID: UUID?
    var selectedSessionID: UUID?

    init(
        workspaces: [Workspace],
        sessions: [TerminalSession],
        selectedWorkspaceID: UUID?,
        selectedSessionID: UUID?
    ) {
        self.workspaces = workspaces
        self.sessions = sessions
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedSessionID = selectedSessionID
    }

    init(document: WorkspaceDocument) {
        let selectedWorkspaceID = document.workspaces.first?.id
        let selectedSessionID = document.workspaces.first.flatMap {
            SplitTreeOperations.sessionIDs(in: $0.layout).first
        }
        self.init(
            workspaces: document.workspaces,
            sessions: document.sessions,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedSessionID: selectedSessionID
        )
    }

    var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    var selectedSession: TerminalSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    func snapshot(
        schemaVersion: Int = WorkspaceDocument.currentSchemaVersion
    ) -> WorkspaceDocument {
        WorkspaceDocument(
            schemaVersion: schemaVersion,
            workspaces: workspaces,
            sessions: sessions
        )
    }
}
