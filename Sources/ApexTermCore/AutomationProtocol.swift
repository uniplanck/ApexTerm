import Foundation

public enum AutomationCapability: String, Codable, CaseIterable, Sendable {
    case readStatus
    case focusSession
    case openWorkspace
    case createSplit
    case sendText
    case runCommand
    case attachRemote
    case manageRemoteHosts
    case reportAgentRun
}

public enum AutomationAction: Codable, Equatable, Sendable {
    case readStatus
    case focusSession(sessionID: UUID)
    case openWorkspace(workspaceID: UUID)
    case createSplit(sessionID: UUID, axis: SplitNode.SplitAxis)
    case sendText(sessionID: UUID, text: String)
    case runCommand(sessionID: UUID, command: String)
    case attachRemote(hostAlias: String, tmuxSession: String?)
    case hideRemoteHost(alias: String)
    case restoreRemoteHost(alias: String)
    case deleteRemoteHost(alias: String)
    case reportAgentRun(report: AgentRunReport)

    public var requiredCapability: AutomationCapability {
        switch self {
        case .readStatus: .readStatus
        case .focusSession: .focusSession
        case .openWorkspace: .openWorkspace
        case .createSplit: .createSplit
        case .sendText: .sendText
        case .runCommand: .runCommand
        case .attachRemote: .attachRemote
        case .hideRemoteHost, .restoreRemoteHost, .deleteRemoteHost: .manageRemoteHosts
        case .reportAgentRun: .reportAgentRun
        }
    }
}

public struct AgentRunReport: Codable, Equatable, Sendable {
    public var runID: UUID
    public var provider: String?
    public var label: String?
    public var workingDirectory: String?
    public var sessionID: UUID?
    public var state: AgentRunState
    public var progress: Double?
    public var message: String?
    public var estimatedCompletionAt: Date?
    public var estimatedInputTokens: Int?
    public var estimatedOutputTokens: Int?
    public var requestedPerformance: GagPerformance?
    public var selectedModel: String?
    public var selectedModelLabel: String?
    public var apiCostEstimate: GagAPICostEstimate?
    public var conversationURL: URL?
    public var jobReference: String?
    public var timestamp: Date

    public init(
        runID: UUID,
        provider: String? = nil,
        label: String? = nil,
        workingDirectory: String? = nil,
        sessionID: UUID? = nil,
        state: AgentRunState,
        progress: Double? = nil,
        message: String? = nil,
        estimatedCompletionAt: Date? = nil,
        estimatedInputTokens: Int? = nil,
        estimatedOutputTokens: Int? = nil,
        requestedPerformance: GagPerformance? = nil,
        selectedModel: String? = nil,
        selectedModelLabel: String? = nil,
        apiCostEstimate: GagAPICostEstimate? = nil,
        conversationURL: URL? = nil,
        jobReference: String? = nil,
        timestamp: Date = Date()
    ) {
        self.runID = runID
        self.provider = provider
        self.label = label
        self.workingDirectory = workingDirectory
        self.sessionID = sessionID
        self.state = state
        self.progress = progress
        self.message = message
        self.estimatedCompletionAt = estimatedCompletionAt
        self.estimatedInputTokens = estimatedInputTokens
        self.estimatedOutputTokens = estimatedOutputTokens
        self.requestedPerformance = requestedPerformance
        self.selectedModel = selectedModel
        self.selectedModelLabel = selectedModelLabel
        self.apiCostEstimate = apiCostEstimate
        self.conversationURL = conversationURL
        self.jobReference = jobReference
        self.timestamp = timestamp
    }
}

public struct AutomationRequest: Codable, Equatable, Identifiable, Sendable {
    public static let currentProtocolVersion = 1

    public var id: UUID
    public var protocolVersion: Int
    public var clientID: String
    public var action: AutomationAction

    public init(
        id: UUID = UUID(),
        protocolVersion: Int = AutomationRequest.currentProtocolVersion,
        clientID: String,
        action: AutomationAction
    ) {
        self.id = id
        self.protocolVersion = protocolVersion
        self.clientID = clientID
        self.action = action
    }
}

public enum AutomationResponseStatus: String, Codable, Sendable {
    case accepted
    case denied
    case invalid
    case failed
}

public struct AutomationResponse: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var status: AutomationResponseStatus
    public var message: String
    public var payload: String?

    public init(
        requestID: UUID,
        status: AutomationResponseStatus,
        message: String,
        payload: String? = nil
    ) {
        self.requestID = requestID
        self.status = status
        self.message = message
        self.payload = payload
    }
}

public struct AutomationStatusSnapshot: Codable, Equatable, Sendable {
    public var workspaces: [WorkspaceSummary]
    public var sessions: [SessionSummary]
    public var selectedWorkspaceID: UUID?
    public var selectedSessionID: UUID?
    public var activeAgentCount: Int
    public var agents: [AgentSummary]

    public init(
        workspaces: [WorkspaceSummary],
        sessions: [SessionSummary],
        selectedWorkspaceID: UUID?,
        selectedSessionID: UUID?,
        activeAgentCount: Int,
        agents: [AgentSummary] = []
    ) {
        self.workspaces = workspaces
        self.sessions = sessions
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedSessionID = selectedSessionID
        self.activeAgentCount = activeAgentCount
        self.agents = agents
    }

    public struct WorkspaceSummary: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var paneCount: Int

        public init(id: UUID, name: String, paneCount: Int) {
            self.id = id
            self.name = name
            self.paneCount = paneCount
        }
    }

    public struct AgentSummary: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var provider: String
        public var label: String
        public var state: AgentRunState
        public var progress: Double?
        public var message: String?
        public var estimatedCompletionAt: Date?
        public var estimatedInputTokens: Int?
        public var estimatedOutputTokens: Int?
        public var conversationURL: URL?
        public var jobReference: String?

        public init(
            id: UUID,
            provider: String,
            label: String,
            state: AgentRunState,
            progress: Double?,
            message: String?,
            estimatedCompletionAt: Date? = nil,
            estimatedInputTokens: Int? = nil,
            estimatedOutputTokens: Int? = nil,
            conversationURL: URL? = nil,
            jobReference: String? = nil
        ) {
            self.id = id
            self.provider = provider
            self.label = label
            self.state = state
            self.progress = progress
            self.message = message
            self.estimatedCompletionAt = estimatedCompletionAt
            self.estimatedInputTokens = estimatedInputTokens
            self.estimatedOutputTokens = estimatedOutputTokens
            self.conversationURL = conversationURL
            self.jobReference = jobReference
        }
    }

    public struct SessionSummary: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        public var state: SessionState
        public var kind: String

        public init(id: UUID, title: String, state: SessionState, kind: String) {
            self.id = id
            self.title = title
            self.state = state
            self.kind = kind
        }
    }
}

public final class AutomationStatusStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AutomationStatusSnapshot?

    public init() {}

    public func update(_ snapshot: AutomationStatusSnapshot) {
        lock.lock()
        value = snapshot
        lock.unlock()
    }

    @discardableResult
    public func updateSelection(
        workspaceID: UUID?,
        sessionID: UUID?
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard value != nil else { return false }
        value?.selectedWorkspaceID = workspaceID
        value?.selectedSessionID = sessionID
        return true
    }

    public func snapshot() -> AutomationStatusSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

public struct AutomationGrant: Codable, Equatable, Sendable {
    public var clientID: String
    public var capabilities: Set<AutomationCapability>
    public var expiresAt: Date?

    public init(
        clientID: String,
        capabilities: Set<AutomationCapability>,
        expiresAt: Date? = nil
    ) {
        self.clientID = clientID
        self.capabilities = capabilities
        self.expiresAt = expiresAt
    }

    public func permits(_ request: AutomationRequest, now: Date = Date()) -> Bool {
        guard request.protocolVersion == AutomationRequest.currentProtocolVersion,
              request.clientID == clientID,
              expiresAt.map({ $0 > now }) ?? true else {
            return false
        }
        return capabilities.contains(request.action.requiredCapability)
    }
}
