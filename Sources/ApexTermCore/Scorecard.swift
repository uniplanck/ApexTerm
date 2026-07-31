import Foundation

public enum ScoreCategory: String, CaseIterable, Codable, Sendable {
    case renderingPerformance
    case inputLatency
    case terminalCompatibility
    case nativeMacUX
    case workspaceManagement
    case remoteResilience
    case automationAPI
    case agentOrchestration
    case searchAndHistory
    case security
    case extensibility
    case accessibilityAndI18n
    case reliabilityAndRecovery
    case resourceEfficiency
    case testabilityAndObservability

    public var title: String {
        switch self {
        case .renderingPerformance: "Rendering performance"
        case .inputLatency: "Input latency"
        case .terminalCompatibility: "Terminal compatibility"
        case .nativeMacUX: "Native macOS UX"
        case .workspaceManagement: "Workspace management"
        case .remoteResilience: "Remote resilience"
        case .automationAPI: "Automation API"
        case .agentOrchestration: "Agent orchestration"
        case .searchAndHistory: "Search and history"
        case .security: "Security"
        case .extensibility: "Extensibility"
        case .accessibilityAndI18n: "Accessibility and i18n"
        case .reliabilityAndRecovery: "Reliability and recovery"
        case .resourceEfficiency: "Resource efficiency"
        case .testabilityAndObservability: "Testability and observability"
        }
    }
}

public enum EvidenceStatus: String, Codable, Sendable {
    case verified
    case planned
    case failed
    case stale
}

public struct ScoreEvidence: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var category: ScoreCategory
    public var points: Int
    public var status: EvidenceStatus
    public var reference: String
    public var note: String

    public init(
        id: String,
        category: ScoreCategory,
        points: Int,
        status: EvidenceStatus,
        reference: String,
        note: String
    ) {
        self.id = id
        self.category = category
        self.points = points
        self.status = status
        self.reference = reference
        self.note = note
    }
}

public struct Scorecard: Codable, Equatable, Sendable {
    public var project: String
    public var generatedAt: Date
    public var evidence: [ScoreEvidence]

    public init(project: String, generatedAt: Date = Date(), evidence: [ScoreEvidence]) {
        self.project = project
        self.generatedAt = generatedAt
        self.evidence = evidence
    }

    public func points(for category: ScoreCategory) -> Int {
        min(
            10,
            evidence
                .filter { $0.category == category && $0.status == .verified }
                .reduce(0) { $0 + max(0, $1.points) }
        )
    }

    public var total: Int {
        ScoreCategory.allCases.reduce(0) { $0 + points(for: $1) }
    }

    public var passesReleaseGate: Bool {
        total >= 136 && evidence.allSatisfy { item in
            item.status != .verified || !item.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func validationErrors() -> [String] {
        var errors: [String] = []
        let duplicateIDs = Dictionary(grouping: evidence, by: \.id)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        if !duplicateIDs.isEmpty {
            errors.append("Duplicate evidence IDs: \(duplicateIDs.joined(separator: ", "))")
        }

        for item in evidence {
            if item.points < 0 || item.points > 10 {
                errors.append("Evidence \(item.id) has invalid points: \(item.points)")
            }
            if item.status == .verified && item.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Verified evidence \(item.id) has no reference")
            }
        }
        return errors
    }
}
