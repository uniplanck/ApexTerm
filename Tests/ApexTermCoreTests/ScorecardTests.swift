import XCTest
@testable import ApexTermCore

final class ScorecardTests: XCTestCase {
    func testOnlyVerifiedEvidenceScores() {
        let scorecard = Scorecard(project: "ApexTerm", evidence: [
            ScoreEvidence(
                id: "verified",
                category: .security,
                points: 4,
                status: .verified,
                reference: "CommandRiskEngineTests",
                note: "Verified"
            ),
            ScoreEvidence(
                id: "planned",
                category: .security,
                points: 6,
                status: .planned,
                reference: "future",
                note: "Not implemented"
            )
        ])

        XCTAssertEqual(scorecard.points(for: .security), 4)
        XCTAssertEqual(scorecard.total, 4)
    }

    func testCategoryScoreIsCappedAtTen() {
        let scorecard = Scorecard(project: "ApexTerm", evidence: [
            ScoreEvidence(
                id: "a",
                category: .workspaceManagement,
                points: 8,
                status: .verified,
                reference: "A",
                note: "A"
            ),
            ScoreEvidence(
                id: "b",
                category: .workspaceManagement,
                points: 8,
                status: .verified,
                reference: "B",
                note: "B"
            )
        ])

        XCTAssertEqual(scorecard.points(for: .workspaceManagement), 10)
    }

    func testReleaseGateRequires136Points() {
        let evidence = ScoreCategory.allCases.enumerated().map { index, category in
            ScoreEvidence(
                id: "evidence-\(index)",
                category: category,
                points: index == 0 ? 6 : 10,
                status: .verified,
                reference: "test-\(index)",
                note: "Synthetic threshold fixture"
            )
        }
        let scorecard = Scorecard(project: "ApexTerm", evidence: evidence)

        XCTAssertEqual(scorecard.total, 146)
        XCTAssertTrue(scorecard.passesReleaseGate)
    }

    func testDuplicateEvidenceIDsFailValidation() {
        let evidence = [
            ScoreEvidence(
                id: "duplicate",
                category: .security,
                points: 1,
                status: .verified,
                reference: "A",
                note: "A"
            ),
            ScoreEvidence(
                id: "duplicate",
                category: .reliabilityAndRecovery,
                points: 1,
                status: .verified,
                reference: "B",
                note: "B"
            )
        ]

        let errors = Scorecard(project: "ApexTerm", evidence: evidence).validationErrors()

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("Duplicate evidence IDs"))
    }
}
