import XCTest
@testable import ApexTermCore

final class CommandRiskEngineTests: XCTestCase {
    private let engine = CommandRiskEngine()

    func testOrdinaryCommandsAreAllowed() {
        XCTAssertEqual(engine.evaluate("git status").level, .allow)
        XCTAssertEqual(engine.evaluate("swift test").level, .allow)
        XCTAssertEqual(engine.evaluate("rm -rf .build").level, .allow)
    }

    func testRootDeletionRequiresApproval() {
        let decision = engine.evaluate("sudo rm -rf /")
        XCTAssertEqual(decision.level, .requireApproval)
        XCTAssertEqual(decision.ruleID, "filesystem.rm-root")
    }

    func testPlainForcePushToMainRequiresApproval() {
        let decision = engine.evaluate("git push origin main --force")
        XCTAssertEqual(decision.level, .requireApproval)
        XCTAssertEqual(decision.ruleID, "git.force-protected")
    }

    func testForceWithLeaseIsNotTreatedAsPlainForce() {
        XCTAssertEqual(
            engine.evaluate("git push --force-with-lease origin feature/test").level,
            .allow
        )
    }

    func testRemoteDatabaseMutationRequiresApproval() {
        let decision = engine.evaluate("wrangler d1 execute app --remote --command 'DELETE FROM users'")
        XCTAssertEqual(decision.level, .requireApproval)
        XCTAssertEqual(decision.ruleID, "database.remote-mutation")
    }

    func testProductionDeployWarns() {
        let decision = engine.evaluate("npm run deploy")
        XCTAssertEqual(decision.level, .warn)
        XCTAssertEqual(decision.ruleID, "production.deploy")
    }
}
