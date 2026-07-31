import Foundation

public enum AgentChatRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
}

public struct AgentChatMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var role: AgentChatRole
    public var text: String
    public var jobReference: String?
    public var requestedPerformance: GagPerformance?
    public var selectedModel: String?
    public var selectedModelLabel: String?
    public var apiCostEstimate: GagAPICostEstimate?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: AgentChatRole,
        text: String,
        jobReference: String? = nil,
        requestedPerformance: GagPerformance? = nil,
        selectedModel: String? = nil,
        selectedModelLabel: String? = nil,
        apiCostEstimate: GagAPICostEstimate? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.jobReference = jobReference
        self.requestedPerformance = requestedPerformance
        self.selectedModel = selectedModel
        self.selectedModelLabel = selectedModelLabel
        self.apiCostEstimate = apiCostEstimate
        self.createdAt = createdAt
    }
}

public struct AgentChatTab: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var target: GagTarget
    public var performance: GagPerformance?
    public var draft: String
    public var messages: [AgentChatMessage]
    public var activeJob: GagTargetedJob?
    public var metrics: GagRuntimeMetrics?
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "Agent Chat",
        target: GagTarget = .local,
        performance: GagPerformance = .high,
        draft: String = "",
        messages: [AgentChatMessage] = [],
        activeJob: GagTargetedJob? = nil,
        metrics: GagRuntimeMetrics? = nil,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.target = target
        self.performance = performance
        self.draft = draft
        self.messages = messages
        self.activeJob = activeJob
        self.metrics = metrics
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var selectedPerformance: GagPerformance { performance ?? .high }

    public var cumulativeAPICostJPY: ClosedRange<Double>? {
        let estimates = messages.compactMap(\.apiCostEstimate).filter(\.isRegistered)
        guard !estimates.isEmpty else { return nil }
        let minimum = estimates.reduce(0) { $0 + ($1.jpy ?? 0) }
        let maximum = estimates.reduce(0) { $0 + ($1.maxJpy ?? $1.jpy ?? 0) }
        return minimum...maximum
    }

    public var isRunning: Bool {
        guard let job = activeJob?.job else { return false }
        return !job.status.isTerminal
            && job.status != .waitingApproval
            && job.status != .interrupted
    }
}

public enum AgentChatStore {
    public static func load(from fileURL: URL) throws -> [AgentChatTab] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AgentChatTab].self, from: data)
    }

    public static func save(_ tabs: [AgentChatTab], to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tabs)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
