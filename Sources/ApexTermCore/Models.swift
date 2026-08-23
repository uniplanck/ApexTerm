import Foundation

public struct Workspace: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var rootDirectory: String?
    public var layout: SplitNode
    public var context: WorkspaceContext
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        rootDirectory: String? = nil,
        layout: SplitNode,
        context: WorkspaceContext = .empty,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rootDirectory = rootDirectory
        self.layout = layout
        self.context = context
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case rootDirectory
        case layout
        case context
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        rootDirectory = try container.decodeIfPresent(String.self, forKey: .rootDirectory)
        layout = try container.decode(SplitNode.self, forKey: .layout)
        context = try container.decodeIfPresent(WorkspaceContext.self, forKey: .context) ?? .empty
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(rootDirectory, forKey: .rootDirectory)
        try container.encode(layout, forKey: .layout)
        try container.encode(context, forKey: .context)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct TerminalColumn: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionIDs: [UUID]
    public var selectedSessionID: UUID

    public init(
        id: UUID = UUID(),
        sessionIDs: [UUID],
        selectedSessionID: UUID? = nil
    ) {
        var uniqueSessionIDs: [UUID] = []
        uniqueSessionIDs.reserveCapacity(sessionIDs.count)
        for sessionID in sessionIDs where !uniqueSessionIDs.contains(sessionID) {
            uniqueSessionIDs.append(sessionID)
        }
        let fallback = uniqueSessionIDs.first ?? selectedSessionID ?? UUID()
        self.id = id
        self.sessionIDs = uniqueSessionIDs.isEmpty ? [fallback] : uniqueSessionIDs
        self.selectedSessionID = self.sessionIDs.contains(selectedSessionID ?? fallback)
            ? (selectedSessionID ?? fallback)
            : self.sessionIDs[0]
    }

    public init(sessionID: UUID) {
        self.init(sessionIDs: [sessionID], selectedSessionID: sessionID)
    }
}

public indirect enum SplitNode: Codable, Equatable, Sendable {
    /// Legacy schema-v1/v2 leaf. WorkspaceStore migrates these to `.column`.
    case pane(sessionID: UUID)
    case column(TerminalColumn)
    case split(axis: SplitAxis, ratio: Double, first: SplitNode, second: SplitNode)

    public enum SplitAxis: String, Codable, Equatable, Sendable {
        case horizontal
        case vertical
    }
}

public struct TerminalSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: SessionKind
    public var state: SessionState
    public var workingDirectory: String?
    public var createdAt: Date
    public var lastAttachedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        kind: SessionKind = .local,
        state: SessionState = .created,
        workingDirectory: String? = nil,
        createdAt: Date = Date(),
        lastAttachedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.state = state
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.lastAttachedAt = lastAttachedAt
    }
}

public enum SessionKind: Codable, Equatable, Sendable {
    case local
    case localTmux(session: String)
    case ssh(host: String)
    case tmux(host: String, session: String)
}

public enum SessionState: String, Codable, Equatable, Sendable {
    case created
    case starting
    case attached
    case detached
    case reconnecting
    case exited
    case failed
}

public struct WorkspaceDocument: Codable, Equatable, Sendable {
    public static let minimumSupportedSchemaVersion = 1
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var workspaces: [Workspace]
    public var sessions: [TerminalSession]

    public init(
        schemaVersion: Int = WorkspaceDocument.currentSchemaVersion,
        workspaces: [Workspace],
        sessions: [TerminalSession]
    ) {
        self.schemaVersion = schemaVersion
        self.workspaces = workspaces
        self.sessions = sessions
    }

    @discardableResult
    public mutating func resetTransientSessionStates() -> Bool {
        var changed = false
        for index in sessions.indices where sessions[index].state != .created {
            sessions[index].state = .created
            changed = true
        }
        return changed
    }
}

public enum AgentRunState: String, Codable, Equatable, Sendable {
    case queued
    case running
    case waitingApproval
    case succeeded
    case failed
    case cancelled
    case disconnected
}

public struct AgentRun: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var provider: String
    public var label: String
    public var workingDirectory: String
    public var state: AgentRunState
    public var progress: Double?
    public var lastEvent: String?
    public var sessionID: UUID?
    public var startedAt: Date?
    public var estimatedCompletionAt: Date?
    public var estimatedInputTokens: Int?
    public var estimatedOutputTokens: Int?
    public var requestedPerformance: GagPerformance?
    public var selectedModel: String?
    public var selectedModelLabel: String?
    public var apiCostEstimate: GagAPICostEstimate?
    public var conversationURL: URL?
    public var jobReference: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        provider: String,
        label: String,
        workingDirectory: String,
        state: AgentRunState,
        progress: Double? = nil,
        lastEvent: String? = nil,
        sessionID: UUID? = nil,
        startedAt: Date? = nil,
        estimatedCompletionAt: Date? = nil,
        estimatedInputTokens: Int? = nil,
        estimatedOutputTokens: Int? = nil,
        requestedPerformance: GagPerformance? = nil,
        selectedModel: String? = nil,
        selectedModelLabel: String? = nil,
        apiCostEstimate: GagAPICostEstimate? = nil,
        conversationURL: URL? = nil,
        jobReference: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.label = label
        self.workingDirectory = workingDirectory
        self.state = state
        self.progress = progress
        self.lastEvent = lastEvent
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.estimatedCompletionAt = estimatedCompletionAt
        self.estimatedInputTokens = estimatedInputTokens
        self.estimatedOutputTokens = estimatedOutputTokens
        self.requestedPerformance = requestedPerformance
        self.selectedModel = selectedModel
        self.selectedModelLabel = selectedModelLabel
        self.apiCostEstimate = apiCostEstimate
        self.conversationURL = conversationURL
        self.jobReference = jobReference
        self.updatedAt = updatedAt
    }
}
