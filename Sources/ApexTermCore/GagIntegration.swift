import Foundation

public enum GagTarget: String, Codable, CaseIterable, Sendable {
    case local
    case gae

    public var displayName: String {
        switch self {
        case .local: "Local Agent"
        case .gae: "Remote Agent"
        }
    }
}

public enum GagPerformance: String, Codable, CaseIterable, Sendable {
    case fastest
    case high

    public static func parse(_ rawValue: String) -> GagPerformance? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "fastest", "fast", "instant", "gpt-5.5-instant", "gpt-5-5-instant", "最速":
            .fastest
        case "high", "thinking", "gpt-5.6-thinking", "gpt-5-6-thinking", "高い",
             "balanced", "balance", "medium", "中程度", "sol", "gpt-5.6-sol", "gpt-5-6-sol":
            .high
        default:
            nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let performance = Self.parse(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown GAG performance: \(rawValue)"
            )
        }
        self = performance
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String {
        self == .fastest ? "最速" : "高い"
    }

    public var compactName: String {
        self == .fastest ? "最速" : "高"
    }
}

public enum GagJobStatus: String, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelling
    case cancelled
    case waitingApproval = "waiting_approval"
    case interrupted

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled:
            true
        case .queued, .running, .cancelling, .waitingApproval, .interrupted:
            false
        }
    }

    public var agentRunState: AgentRunState {
        switch self {
        case .queued:
            .queued
        case .running:
            .running
        case .waitingApproval:
            .waitingApproval
        case .succeeded:
            .succeeded
        case .failed:
            .failed
        case .cancelling, .cancelled:
            .cancelled
        case .interrupted:
            .disconnected
        }
    }
}

public struct GagJobInput: Codable, Equatable, Sendable {
    public var prompt: String?
    public var timeoutMs: Int?
    public var expectedMarker: String?
    public var performance: GagPerformance?

    public init(
        prompt: String? = nil,
        timeoutMs: Int? = nil,
        expectedMarker: String? = nil,
        performance: GagPerformance? = nil
    ) {
        self.prompt = prompt
        self.timeoutMs = timeoutMs
        self.expectedMarker = expectedMarker
        self.performance = performance
    }
}

public struct GagAPICostEstimate: Codable, Equatable, Sendable {
    public var status: String
    public var requestedModel: String?
    public var selectedModel: String?
    public var selectedModelLabel: String?
    public var pricingModel: String?
    public var pricingLabel: String?
    public var inputTokens: Int
    public var outputTokens: Int
    public var usdJpyRate: Double
    public var usd: Double?
    public var jpy: Double?
    public var maxUsd: Double?
    public var maxJpy: Double?
    public var note: String

    public init(
        status: String,
        requestedModel: String? = nil,
        selectedModel: String? = nil,
        selectedModelLabel: String? = nil,
        pricingModel: String? = nil,
        pricingLabel: String? = nil,
        inputTokens: Int,
        outputTokens: Int,
        usdJpyRate: Double,
        usd: Double? = nil,
        jpy: Double? = nil,
        maxUsd: Double? = nil,
        maxJpy: Double? = nil,
        note: String
    ) {
        self.status = status
        self.requestedModel = requestedModel
        self.selectedModel = selectedModel
        self.selectedModelLabel = selectedModelLabel
        self.pricingModel = pricingModel
        self.pricingLabel = pricingLabel
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.usdJpyRate = usdJpyRate
        self.usd = usd
        self.jpy = jpy
        self.maxUsd = maxUsd
        self.maxJpy = maxJpy
        self.note = note
    }

    public var isRegistered: Bool { status == "registered" }
}

public struct GagJobState: Codable, Equatable, Sendable {
    public var phase: String?
    public var conversationUrl: String?
    public var responseText: String?
    public var imageUrls: [String]?
    public var requestedPerformance: GagPerformance?
    public var requestedModel: String?
    public var selectedModel: String?
    public var selectedModelLabel: String?
    public var modelSelectionStatus: String?
    public var modelSelectionError: String?
    public var apiCostEstimate: GagAPICostEstimate?

    public init(
        phase: String? = nil,
        conversationUrl: String? = nil,
        responseText: String? = nil,
        imageUrls: [String]? = nil,
        requestedPerformance: GagPerformance? = nil,
        requestedModel: String? = nil,
        selectedModel: String? = nil,
        selectedModelLabel: String? = nil,
        modelSelectionStatus: String? = nil,
        modelSelectionError: String? = nil,
        apiCostEstimate: GagAPICostEstimate? = nil
    ) {
        self.phase = phase
        self.conversationUrl = conversationUrl
        self.responseText = responseText
        self.imageUrls = imageUrls
        self.requestedPerformance = requestedPerformance
        self.requestedModel = requestedModel
        self.selectedModel = selectedModel
        self.selectedModelLabel = selectedModelLabel
        self.modelSelectionStatus = modelSelectionStatus
        self.modelSelectionError = modelSelectionError
        self.apiCostEstimate = apiCostEstimate
    }
}

public struct GagJobRecord: Codable, Equatable, Sendable {
    public var id: String
    public var workspaceId: String?
    public var workspaceRoot: String
    public var title: String
    public var preset: String
    public var status: GagJobStatus
    public var progress: Int
    public var currentStep: String
    public var exitCode: Int?
    public var error: String?
    public var input: GagJobInput?
    public var state: GagJobState?
    public var createdAt: String
    public var startedAt: String?
    public var finishedAt: String?
    public var updatedAt: String

    public init(
        id: String,
        workspaceId: String? = nil,
        workspaceRoot: String,
        title: String,
        preset: String = "chatgpt-task",
        status: GagJobStatus,
        progress: Int,
        currentStep: String,
        exitCode: Int? = nil,
        error: String? = nil,
        input: GagJobInput? = nil,
        state: GagJobState? = nil,
        createdAt: String,
        startedAt: String? = nil,
        finishedAt: String? = nil,
        updatedAt: String
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.workspaceRoot = workspaceRoot
        self.title = title
        self.preset = preset
        self.status = status
        self.progress = progress
        self.currentStep = currentStep
        self.exitCode = exitCode
        self.error = error
        self.input = input
        self.state = state
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.updatedAt = updatedAt
    }
}

public struct GagJobEvent: Codable, Equatable, Sendable {
    public var id: Int
    public var jobId: String
    public var timestamp: String
    public var level: String
    public var message: String
}

public struct GagTokenEstimate: Codable, Equatable, Sendable {
    public var input: Int
    public var output: Int

    public init(input: Int, output: Int) {
        self.input = max(0, input)
        self.output = max(0, output)
    }

    public var total: Int { input + output }

    public static func estimate(input: String?, output: String?) -> GagTokenEstimate {
        GagTokenEstimate(
            input: estimateText(input ?? ""),
            output: estimateText(output ?? "")
        )
    }

    public static func estimateText(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var units = 0.0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30ff, 0x3400...0x9fff, 0xac00...0xd7af:
                units += 0.9
            case 0x0000...0x007f:
                if CharacterSet.alphanumerics.contains(scalar) {
                    units += 0.25
                } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    units += 0.04
                } else {
                    units += 0.35
                }
            default:
                units += 0.65
            }
        }
        return max(1, Int(ceil(units)))
    }
}

public struct GagRuntimeMetrics: Codable, Equatable, Sendable {
    public var reference: String
    public var progress: Double
    public var elapsedSeconds: TimeInterval
    public var estimatedRemainingSeconds: TimeInterval?
    public var estimatedCompletionAt: Date?
    public var tokens: GagTokenEstimate
    public var requestedPerformance: GagPerformance
    public var selectedModel: String?
    public var selectedModelLabel: String?
    public var apiCostEstimate: GagAPICostEstimate?
    public var conversationURL: URL?

    public init(
        reference: String,
        progress: Double,
        elapsedSeconds: TimeInterval,
        estimatedRemainingSeconds: TimeInterval?,
        estimatedCompletionAt: Date?,
        tokens: GagTokenEstimate,
        requestedPerformance: GagPerformance = .high,
        selectedModel: String? = nil,
        selectedModelLabel: String? = nil,
        apiCostEstimate: GagAPICostEstimate? = nil,
        conversationURL: URL?
    ) {
        self.reference = reference
        self.progress = min(1, max(0, progress))
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.estimatedRemainingSeconds = estimatedRemainingSeconds.map { max(0, $0) }
        self.estimatedCompletionAt = estimatedCompletionAt
        self.tokens = tokens
        self.requestedPerformance = requestedPerformance
        self.selectedModel = selectedModel
        self.selectedModelLabel = selectedModelLabel
        self.apiCostEstimate = apiCostEstimate
        self.conversationURL = conversationURL
    }

    public static func calculate(
        target: GagTarget,
        job: GagJobRecord,
        now: Date = Date()
    ) -> GagRuntimeMetrics {
        let start = parseDate(job.startedAt ?? job.createdAt) ?? now
        let end = job.status.isTerminal
            ? (parseDate(job.finishedAt ?? job.updatedAt) ?? now)
            : now
        let elapsed = max(0, end.timeIntervalSince(start))
        let normalizedProgress = Double(max(0, min(100, job.progress))) / 100
        let remaining: TimeInterval?
        if job.status.isTerminal {
            remaining = 0
        } else if job.status == .waitingApproval || job.status == .interrupted {
            remaining = nil
        } else {
            let safeProgress = max(0.08, normalizedProgress)
            let linearRemaining = max(0, elapsed / safeProgress - elapsed)
            let phaseFloor: TimeInterval
            switch normalizedProgress {
            case ..<0.15: phaseFloor = 45
            case ..<0.55: phaseFloor = 30
            case ..<0.95: phaseFloor = 18
            default: phaseFloor = 5
            }
            let timeoutCeiling = TimeInterval(job.input?.timeoutMs ?? 600_000) / 1000
            remaining = min(timeoutCeiling, max(phaseFloor, linearRemaining))
        }
        let completion = remaining.map { now.addingTimeInterval($0) }
        let tokenEstimate = GagTokenEstimate.estimate(
            input: job.input?.prompt,
            output: job.state?.responseText
        )
        let conversationURL = job.state?.conversationUrl.flatMap(URL.init(string:))
        return GagRuntimeMetrics(
            reference: GagJobReference(target: target, jobID: job.id).serialized,
            progress: normalizedProgress,
            elapsedSeconds: elapsed,
            estimatedRemainingSeconds: remaining,
            estimatedCompletionAt: completion,
            tokens: tokenEstimate,
            requestedPerformance: job.state?.requestedPerformance ?? job.input?.performance ?? .high,
            selectedModel: job.state?.selectedModel,
            selectedModelLabel: job.state?.selectedModelLabel,
            apiCostEstimate: job.state?.apiCostEstimate,
            conversationURL: conversationURL
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

public struct GagTargetedJob: Codable, Equatable, Sendable {
    public var target: GagTarget
    public var job: GagJobRecord

    public init(target: GagTarget, job: GagJobRecord) {
        self.target = target
        self.job = job
    }
}

public struct GagTargetedJobEnvelope: Codable, Equatable, Sendable {
    public var target: GagTarget
    public var envelope: GagJobEnvelope

    public init(target: GagTarget, envelope: GagJobEnvelope) {
        self.target = target
        self.envelope = envelope
    }
}

public struct GagJobEnvelope: Codable, Equatable, Sendable {
    public var job: GagJobRecord
    public var events: [GagJobEvent]?
}

public struct GagJobListEnvelope: Codable, Equatable, Sendable {
    public var jobs: [GagJobRecord]
}

public struct GagJobReference: Codable, Equatable, Sendable {
    public var target: GagTarget
    public var jobID: String

    public init(target: GagTarget, jobID: String) {
        self.target = target
        self.jobID = jobID
    }

    public var serialized: String {
        "\(target.rawValue)/\(jobID)"
    }

    public static func parse(_ value: String, defaultTarget: GagTarget = .local) -> GagJobReference? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        for separator in ["/", ":"] {
            let pieces = normalized.split(separator: Character(separator), maxSplits: 1).map(String.init)
            if pieces.count == 2 {
                let targetValue = pieces[0] == "gag" ? "local" : pieces[0]
                guard let target = GagTarget(rawValue: targetValue), isJobID(pieces[1]) else {
                    return nil
                }
                return GagJobReference(target: target, jobID: pieces[1])
            }
        }
        guard isJobID(normalized) else { return nil }
        return GagJobReference(target: defaultTarget, jobID: normalized)
    }

    private static func isJobID(_ value: String) -> Bool {
        value.hasPrefix("job_")
            && value.dropFirst(4).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

public enum GagJobCodec {
    public static func decodeJobEnvelope(_ data: Data) throws -> GagJobEnvelope {
        try decoder.decode(GagJobEnvelope.self, from: data)
    }

    public static func decodeJobList(_ data: Data) throws -> GagJobListEnvelope {
        try decoder.decode(GagJobListEnvelope.self, from: data)
    }

    public static func parseStartedJobID(_ output: String) -> String? {
        output
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first(where: { GagJobReference.parse($0) != nil })
    }

    public static func stableRunID(target: GagTarget, jobID: String) -> UUID {
        let bytes = Array("\(target.rawValue):\(jobID)".utf8)
        let high = fnv1a64(bytes, seed: 0xcbf29ce484222325)
        let low = fnv1a64(bytes.reversed(), seed: 0x84222325cbf29ce4)
        let hex = String(format: "%016llx%016llx", high, low)
        let first = String(hex.prefix(8))
        let second = String(hex.dropFirst(8).prefix(4))
        let third = String(hex.dropFirst(12).prefix(4))
        let fourth = String(hex.dropFirst(16).prefix(4))
        let fifth = String(hex.dropFirst(20).prefix(12))
        let formatted = "\(first)-\(second)-\(third)-\(fourth)-\(fifth)"
        return UUID(uuidString: formatted) ?? UUID()
    }

    public static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private static func fnv1a64<S: Sequence>(_ bytes: S, seed: UInt64) -> UInt64 where S.Element == UInt8 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}
