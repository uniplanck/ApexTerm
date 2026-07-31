import Foundation

public enum WorkflowScoreCategory: String, CaseIterable, Codable, Sendable {
    case dailyDriver
    case workspaceOS
    case agentOS
    case remoteOps
    case platformAndAutomation
    case trustAndPolish

    public var title: String {
        switch self {
        case .dailyDriver: "Daily Driver"
        case .workspaceOS: "Workspace OS"
        case .agentOS: "Agent OS"
        case .remoteOps: "Remote Ops"
        case .platformAndAutomation: "Platform & Automation"
        case .trustAndPolish: "Trust & Polish"
        }
    }

    public var maximumPoints: Int {
        switch self {
        case .agentOS: 25
        case .dailyDriver, .workspaceOS, .remoteOps,
             .platformAndAutomation, .trustAndPolish:
            15
        }
    }
}

public enum WorkflowEvidenceSource: String, Codable, CaseIterable, Sendable {
    case unitTest
    case integrationTest
    case endToEnd
    case benchmark
    case manualDogfood
    case releaseRecord
}

public struct WorkflowScoreEvidence: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var category: WorkflowScoreCategory
    public var points: Int
    public var status: EvidenceStatus
    public var source: WorkflowEvidenceSource
    public var reference: String
    public var userJourney: String
    public var note: String
    public var verifiedAt: Date?
    public var isCritical: Bool

    public init(
        id: String,
        category: WorkflowScoreCategory,
        points: Int,
        status: EvidenceStatus,
        source: WorkflowEvidenceSource,
        reference: String,
        userJourney: String,
        note: String,
        verifiedAt: Date? = nil,
        isCritical: Bool = false
    ) {
        self.id = id
        self.category = category
        self.points = points
        self.status = status
        self.source = source
        self.reference = reference
        self.userJourney = userJourney
        self.note = note
        self.verifiedAt = verifiedAt
        self.isCritical = isCritical
    }
}

public enum WorkflowMaturityGate: String, CaseIterable, Codable, Sendable {
    case dailyDriver
    case workspaceOS
    case agentOS
    case remoteOps
    case platform
    case complete

    public var requiredPoints: Int {
        switch self {
        case .dailyDriver: 45
        case .workspaceOS: 60
        case .agentOS: 78
        case .remoteOps: 88
        case .platform: 95
        case .complete: 100
        }
    }

    public var title: String {
        switch self {
        case .dailyDriver: "Daily Driver"
        case .workspaceOS: "Workspace OS"
        case .agentOS: "Agent OS"
        case .remoteOps: "Remote Ops"
        case .platform: "Platform"
        case .complete: "100-point Complete"
        }
    }
}

public struct UserWorkflowScorecard: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var project: String
    public var generatedAt: Date
    public var targetGate: WorkflowMaturityGate
    public var evidence: [WorkflowScoreEvidence]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        project: String,
        generatedAt: Date = Date(),
        targetGate: WorkflowMaturityGate = .dailyDriver,
        evidence: [WorkflowScoreEvidence]
    ) {
        self.schemaVersion = schemaVersion
        self.project = project
        self.generatedAt = generatedAt
        self.targetGate = targetGate
        self.evidence = evidence
    }

    public func points(for category: WorkflowScoreCategory) -> Int {
        min(
            category.maximumPoints,
            evidence
                .filter {
                    $0.category == category && $0.status == .verified
                }
                .reduce(0) { $0 + max(0, $1.points) }
        )
    }

    public var total: Int {
        WorkflowScoreCategory.allCases.reduce(0) {
            $0 + points(for: $1)
        }
    }

    public var highestReachedGate: WorkflowMaturityGate? {
        WorkflowMaturityGate.allCases.last(where: { passes($0) })
    }

    public var nextGate: WorkflowMaturityGate? {
        WorkflowMaturityGate.allCases.first(where: { !passes($0) })
    }

    public var pointsToTarget: Int {
        max(0, targetGate.requiredPoints - total)
    }

    public func passes(_ gate: WorkflowMaturityGate) -> Bool {
        total >= gate.requiredPoints && !hasCriticalFailure
    }

    public var passesTargetGate: Bool {
        passes(targetGate)
    }

    public var hasCriticalFailure: Bool {
        evidence.contains {
            $0.isCritical && $0.status == .failed
        }
    }

    public func validationErrors(
        now: Date = Date(),
        manualEvidenceLifetime: TimeInterval = 90 * 24 * 60 * 60
    ) -> [String] {
        var errors: [String] = []
        if schemaVersion != Self.currentSchemaVersion {
            errors.append(
                "Unsupported workflow scorecard schema: \(schemaVersion)"
            )
        }

        let duplicateIDs = Dictionary(grouping: evidence, by: \.id)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        if !duplicateIDs.isEmpty {
            errors.append(
                "Duplicate workflow evidence IDs: \(duplicateIDs.joined(separator: ", "))"
            )
        }

        for item in evidence {
            if item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Workflow evidence has an empty ID")
            }
            if item.points < 0 || item.points > item.category.maximumPoints {
                errors.append(
                    "Workflow evidence \(item.id) has invalid points: \(item.points)"
                )
            }
            if item.status == .verified {
                if item.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append(
                        "Verified workflow evidence \(item.id) has no reference"
                    )
                }
                if item.userJourney.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append(
                        "Verified workflow evidence \(item.id) has no user journey"
                    )
                }
                guard let verifiedAt = item.verifiedAt else {
                    errors.append(
                        "Verified workflow evidence \(item.id) has no verification date"
                    )
                    continue
                }
                if verifiedAt > now.addingTimeInterval(5 * 60) {
                    errors.append(
                        "Workflow evidence \(item.id) is dated in the future"
                    )
                }
                if item.source == .manualDogfood,
                   now.timeIntervalSince(verifiedAt) > manualEvidenceLifetime {
                    errors.append(
                        "Manual workflow evidence \(item.id) is stale"
                    )
                }
            }
        }
        return errors
    }
}
