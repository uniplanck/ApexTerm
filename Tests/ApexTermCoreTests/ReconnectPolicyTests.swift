import XCTest
@testable import ApexTermCore

final class ReconnectPolicyTests: XCTestCase {
    func testExponentialBackoffIsBoundedAndFinite() {
        let policy = ReconnectPolicy(
            maximumAttempts: 5,
            initialDelaySeconds: 0.5,
            maximumDelaySeconds: 8,
            multiplier: 2
        )

        XCTAssertEqual(
            (1...5).compactMap(policy.delaySeconds(forAttempt:)),
            [0.5, 1, 2, 4, 8]
        )
        XCTAssertNil(policy.delaySeconds(forAttempt: 0))
        XCTAssertNil(policy.delaySeconds(forAttempt: 6))
    }

    func testMaximumDelayCapsLargeMultiplier() {
        let policy = ReconnectPolicy(
            maximumAttempts: 4,
            initialDelaySeconds: 1,
            maximumDelaySeconds: 3,
            multiplier: 10
        )

        XCTAssertEqual(
            (1...4).compactMap(policy.delaySeconds(forAttempt:)),
            [1, 3, 3, 3]
        )
    }

    func testTrackerKeepsSessionsIndependentAndResetsAfterSuccess() async {
        let tracker = ReconnectAttemptTracker(
            policy: ReconnectPolicy(
                maximumAttempts: 2,
                initialDelaySeconds: 0.1,
                maximumDelaySeconds: 0.2
            )
        )
        let first = UUID()
        let second = UUID()

        let firstAttempt = await tracker.begin(sessionID: first)
        let secondAttempt = await tracker.begin(sessionID: second)
        let firstRetry = await tracker.begin(sessionID: first)
        let exhausted = await tracker.begin(sessionID: first)

        XCTAssertEqual(firstAttempt?.attempt, 1)
        XCTAssertEqual(secondAttempt?.attempt, 1)
        XCTAssertEqual(firstRetry?.attempt, 2)
        XCTAssertNil(exhausted)

        await tracker.reset(sessionID: first)
        let resetCount = await tracker.attempts(sessionID: first)
        let restarted = await tracker.begin(sessionID: first)
        XCTAssertEqual(resetCount, 0)
        XCTAssertEqual(restarted?.attempt, 1)
    }
}
