import Foundation
import XCTest
@testable import ApexTermCore

final class WorkflowScorecardTests: XCTestCase {
    func testVerifiedEvidenceScoresAgainstCategoryMaximums() {
        let date = Date(timeIntervalSince1970: 100)
        let scorecard = UserWorkflowScorecard(
            project: "ApexTerm",
            evidence: [
                evidence(
                    id: "daily-a",
                    category: .dailyDriver,
                    points: 10,
                    verifiedAt: date
                ),
                evidence(
                    id: "daily-b",
                    category: .dailyDriver,
                    points: 10,
                    verifiedAt: date
                ),
                WorkflowScoreEvidence(
                    id: "planned",
                    category: .agentOS,
                    points: 25,
                    status: .planned,
                    source: .integrationTest,
                    reference: "future",
                    userJourney: "Future agent workflow",
                    note: "Not implemented"
                )
            ]
        )

        XCTAssertEqual(scorecard.points(for: .dailyDriver), 15)
        XCTAssertEqual(scorecard.points(for: .agentOS), 0)
        XCTAssertEqual(scorecard.total, 15)
    }

    func testGateProgressionUsesThirtyToHundredRoadmapThresholds() {
        let date = Date(timeIntervalSince1970: 100)
        let evidenceItems = WorkflowScoreCategory.allCases.map { category in
            evidence(
                id: category.rawValue,
                category: category,
                points: category.maximumPoints,
                verifiedAt: date
            )
        }
        let complete = UserWorkflowScorecard(
            project: "ApexTerm",
            targetGate: .complete,
            evidence: evidenceItems
        )

        XCTAssertEqual(complete.total, 100)
        XCTAssertEqual(complete.highestReachedGate, .complete)
        XCTAssertNil(complete.nextGate)
        XCTAssertTrue(complete.passesTargetGate)
        XCTAssertEqual(complete.pointsToTarget, 0)

        let partial = UserWorkflowScorecard(
            project: "ApexTerm",
            targetGate: .agentOS,
            evidence: Array(evidenceItems.prefix(4))
        )
        XCTAssertEqual(partial.total, 70)
        XCTAssertEqual(partial.highestReachedGate, .workspaceOS)
        XCTAssertEqual(partial.nextGate, .agentOS)
        XCTAssertEqual(partial.pointsToTarget, 8)
    }

    func testCriticalFailureBlocksGateEvenWhenPointsAreHigh() {
        let date = Date(timeIntervalSince1970: 100)
        var evidenceItems = WorkflowScoreCategory.allCases.map { category in
            evidence(
                id: category.rawValue,
                category: category,
                points: category.maximumPoints,
                verifiedAt: date
            )
        }
        evidenceItems.append(
            WorkflowScoreEvidence(
                id: "critical-crash",
                category: .trustAndPolish,
                points: 0,
                status: .failed,
                source: .endToEnd,
                reference: "crash-loop-e2e",
                userJourney: "Restore after a forced quit",
                note: "Known critical failure",
                verifiedAt: date,
                isCritical: true
            )
        )
        let scorecard = UserWorkflowScorecard(
            project: "ApexTerm",
            targetGate: .complete,
            evidence: evidenceItems
        )

        XCTAssertEqual(scorecard.total, 100)
        XCTAssertTrue(scorecard.hasCriticalFailure)
        XCTAssertFalse(scorecard.passes(.dailyDriver))
        XCTAssertFalse(scorecard.passesTargetGate)
    }

    func testValidationRejectsDuplicateFutureAndStaleManualEvidence() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let staleDate = now.addingTimeInterval(-91 * 24 * 60 * 60)
        let futureDate = now.addingTimeInterval(10 * 60)
        let scorecard = UserWorkflowScorecard(
            schemaVersion: 1,
            project: "ApexTerm",
            evidence: [
                evidence(
                    id: "duplicate",
                    category: .dailyDriver,
                    points: 3,
                    source: .manualDogfood,
                    verifiedAt: staleDate
                ),
                evidence(
                    id: "duplicate",
                    category: .agentOS,
                    points: 3,
                    verifiedAt: futureDate
                ),
                WorkflowScoreEvidence(
                    id: "missing",
                    category: .workspaceOS,
                    points: 3,
                    status: .verified,
                    source: .unitTest,
                    reference: "",
                    userJourney: "",
                    note: "Missing evidence",
                    verifiedAt: nil
                )
            ]
        )

        let errors = scorecard.validationErrors(now: now)
        XCTAssertTrue(errors.contains(where: { $0.contains("Unsupported") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("Duplicate") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("stale") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("future") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("no reference") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("no user journey") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("no verification date") }))
    }

    private func evidence(
        id: String,
        category: WorkflowScoreCategory,
        points: Int,
        source: WorkflowEvidenceSource = .unitTest,
        verifiedAt: Date
    ) -> WorkflowScoreEvidence {
        WorkflowScoreEvidence(
            id: id,
            category: category,
            points: points,
            status: .verified,
            source: source,
            reference: "test:\(id)",
            userJourney: "Complete \(category.title) journey",
            note: "Verified fixture",
            verifiedAt: verifiedAt
        )
    }
}
