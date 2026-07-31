import Foundation

public enum WorkspaceRepositoryRole: String, Codable, Equatable, Sendable {
    case primary
    case secondary
    case dependency
}

public struct WorkspaceRepositoryReference: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var role: WorkspaceRepositoryRole

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        role: WorkspaceRepositoryRole = .secondary
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.role = role
    }
}

public struct WorkspaceRemoteBinding: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var hostAlias: String
    public var tmuxSession: String?
    public var workingDirectory: String?

    public init(
        id: UUID = UUID(),
        name: String,
        hostAlias: String,
        tmuxSession: String? = nil,
        workingDirectory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.hostAlias = hostAlias
        self.tmuxSession = tmuxSession
        self.workingDirectory = workingDirectory
    }
}

public struct WorkspaceEnvironmentReference: Codable, Equatable, Sendable {
    public var profileID: String
    public var displayName: String

    public init(profileID: String, displayName: String) {
        self.profileID = profileID
        self.displayName = displayName
    }
}

public enum WorkspaceLaunchStep: Codable, Equatable, Sendable {
    case openLocalShell(workingDirectory: String?)
    case attachRemote(hostAlias: String, tmuxSession: String?)
    case runAction(actionID: String)
}

public struct WorkspaceLaunchConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var steps: [WorkspaceLaunchStep]
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        steps: [WorkspaceLaunchStep] = [],
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.isDefault = isDefault
    }
}

public struct WorkspaceAgentBinding: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var target: GagTarget
    public var performance: GagPerformance
    public var workingDirectory: String?

    public init(
        id: UUID = UUID(),
        name: String,
        target: GagTarget = .local,
        performance: GagPerformance = .high,
        workingDirectory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.performance = performance
        self.workingDirectory = workingDirectory
    }
}

public struct WorkspaceRunbookReference: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var relativePath: String

    public init(
        id: UUID = UUID(),
        title: String,
        relativePath: String
    ) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
    }
}

public struct WorkspacePinnedCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var command: String
    public var workingDirectory: String?
    public var requiresConfirmation: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        command: String,
        workingDirectory: String? = nil,
        requiresConfirmation: Bool = true
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.workingDirectory = workingDirectory
        self.requiresConfirmation = requiresConfirmation
    }
}

public enum WorkspaceTaskState: String, Codable, Equatable, Sendable {
    case planned
    case active
    case blocked
    case completed
    case cancelled
}

public struct WorkspaceTaskRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var detail: String?
    public var state: WorkspaceTaskState
    public var linkedAgentRunID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String? = nil,
        state: WorkspaceTaskState = .planned,
        linkedAgentRunID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
        self.linkedAgentRunID = linkedAgentRunID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WorkspaceArtifactReference: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var relativePath: String
    public var kind: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        relativePath: String,
        kind: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.kind = kind
        self.createdAt = createdAt
    }
}

public struct WorkspaceNote: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WorkspaceContext: Codable, Equatable, Sendable {
    public var repositories: [WorkspaceRepositoryReference]
    public var remoteBindings: [WorkspaceRemoteBinding]
    public var environment: WorkspaceEnvironmentReference?
    public var launchConfigurations: [WorkspaceLaunchConfiguration]
    public var agentBindings: [WorkspaceAgentBinding]
    public var runbooks: [WorkspaceRunbookReference]
    public var pinnedCommands: [WorkspacePinnedCommand]
    public var tasks: [WorkspaceTaskRecord]
    public var artifacts: [WorkspaceArtifactReference]
    public var notes: [WorkspaceNote]

    public init(
        repositories: [WorkspaceRepositoryReference] = [],
        remoteBindings: [WorkspaceRemoteBinding] = [],
        environment: WorkspaceEnvironmentReference? = nil,
        launchConfigurations: [WorkspaceLaunchConfiguration] = [],
        agentBindings: [WorkspaceAgentBinding] = [],
        runbooks: [WorkspaceRunbookReference] = [],
        pinnedCommands: [WorkspacePinnedCommand] = [],
        tasks: [WorkspaceTaskRecord] = [],
        artifacts: [WorkspaceArtifactReference] = [],
        notes: [WorkspaceNote] = []
    ) {
        self.repositories = repositories
        self.remoteBindings = remoteBindings
        self.environment = environment
        self.launchConfigurations = launchConfigurations
        self.agentBindings = agentBindings
        self.runbooks = runbooks
        self.pinnedCommands = pinnedCommands
        self.tasks = tasks
        self.artifacts = artifacts
        self.notes = notes
    }

    public static let empty = WorkspaceContext()
}
