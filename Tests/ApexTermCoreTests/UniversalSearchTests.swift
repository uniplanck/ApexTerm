import Foundation
import XCTest
@testable import ApexTermCore

final class UniversalSearchTests: XCTestCase {
    func testSearchFindsWorkspacesSessionsCommandsAndAgents() {
        let fixture = makeFixture()
        let engine = UniversalSearchEngine()

        XCTAssertEqual(
            engine.search("payments", in: fixture).first?.kind,
            .workspace
        )
        XCTAssertEqual(
            engine.search("deploy production", in: fixture).first?.kind,
            .command
        )
        XCTAssertEqual(
            engine.search("review pull request", in: fixture).first?.kind,
            .agentChat
        )
        XCTAssertEqual(
            engine.search("waitingApproval", in: fixture).first?.kind,
            .agentEvent
        )
        XCTAssertEqual(
            engine.search("ssh prod", in: fixture).first?.kind,
            .session
        )
    }

    func testScopeExcludesOtherKindsAndLimitIsBounded() {
        let fixture = makeFixture()
        let engine = UniversalSearchEngine()

        let commands = engine.search(
            "",
            in: fixture,
            scope: .commands,
            limit: 1
        )
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.kind, .command)

        let agents = engine.search(
            "",
            in: fixture,
            scope: .agents,
            limit: 100
        )
        XCTAssertTrue(
            agents.allSatisfy {
                $0.kind == .agentChat || $0.kind == .agentEvent
            }
        )
    }

    func testExactTitleAndPrefixOutrankOutputOnlyMatches() {
        let fixture = makeFixture()
        let results = UniversalSearchEngine().search("payments", in: fixture)

        XCTAssertEqual(results.first?.title, "Payments")
        XCTAssertEqual(results.first?.kind, .workspace)
        XCTAssertGreaterThan(
            results.first?.score ?? 0,
            results.last?.score ?? 0
        )
    }

    func testEmptyQueryOrdersRecentItemsFirst() {
        let fixture = makeFixture()
        let results = UniversalSearchEngine().search("", in: fixture)

        XCTAssertEqual(results.first?.kind, .agentEvent)
        XCTAssertEqual(results.first?.title, "Approve production deploy")
    }

    func testNonMatchingQueryReturnsNoResults() {
        let fixture = makeFixture()

        XCTAssertTrue(
            UniversalSearchEngine()
                .search("__definitely_not_present__", in: fixture)
                .isEmpty
        )
    }

    private func makeFixture() -> UniversalSearchSnapshot {
        let localSessionID = UUID()
        let remoteSessionID = UUID()
        let workspace = Workspace(
            name: "Payments",
            rootDirectory: "/tmp/payments",
            layout: .split(
                axis: .vertical,
                ratio: 0.5,
                first: .pane(sessionID: localSessionID),
                second: .pane(sessionID: remoteSessionID)
            ),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let sessions = [
            TerminalSession(
                id: localSessionID,
                title: "API",
                workingDirectory: "/tmp/payments/api",
                createdAt: Date(timeIntervalSince1970: 80)
            ),
            TerminalSession(
                id: remoteSessionID,
                title: "Production",
                kind: .ssh(host: "prod-payments"),
                workingDirectory: "/srv/payments",
                createdAt: Date(timeIntervalSince1970: 90)
            )
        ]
        let command = CommandExecutionRecord(
            sessionID: localSessionID,
            command: "deploy production",
            output: "payments deployment complete",
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 110),
            finishedAt: Date(timeIntervalSince1970: 111)
        )
        let agentChat = AgentChatTab(
            title: "Review pull request",
            target: .local,
            messages: [
                AgentChatMessage(
                    role: .assistant,
                    text: "Reviewed the payments service"
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 120)
        )
        let agentEvent = UniversalAgentEvent(
            id: UUID(),
            reference: "local/job_approval",
            title: "Approve production deploy",
            status: "waitingApproval",
            summary: "Approval is required before deployment",
            updatedAt: Date(timeIntervalSince1970: 130),
            conversationURL: URL(string: "https://chatgpt.com/c/example")
        )
        return UniversalSearchSnapshot(
            workspaces: [workspace],
            sessions: sessions,
            commands: [command],
            agentChats: [agentChat],
            agentEvents: [agentEvent]
        )
    }
}
