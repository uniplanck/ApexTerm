import XCTest
@testable import ApexTermCore

final class AutomationProtocolTests: XCTestCase {
    func testCapabilityGrantAllowsOnlyMatchingClientAndAction() {
        let grant = AutomationGrant(
            clientID: "gag",
            capabilities: [.readStatus, .focusSession]
        )
        let allowed = AutomationRequest(
            clientID: "gag",
            action: .focusSession(sessionID: UUID())
        )
        let deniedAction = AutomationRequest(
            clientID: "gag",
            action: .runCommand(sessionID: UUID(), command: "git status")
        )
        let deniedClient = AutomationRequest(
            clientID: "other",
            action: .readStatus
        )

        XCTAssertTrue(grant.permits(allowed))
        XCTAssertFalse(grant.permits(deniedAction))
        XCTAssertFalse(grant.permits(deniedClient))
    }

    func testExpiredGrantIsDenied() {
        let grant = AutomationGrant(
            clientID: "gag",
            capabilities: [.readStatus],
            expiresAt: Date(timeIntervalSince1970: 100)
        )
        let request = AutomationRequest(clientID: "gag", action: .readStatus)

        XCTAssertFalse(grant.permits(request, now: Date(timeIntervalSince1970: 101)))
    }

    func testProtocolVersionMismatchIsDenied() {
        let grant = AutomationGrant(clientID: "gag", capabilities: [.readStatus])
        let request = AutomationRequest(
            protocolVersion: AutomationRequest.currentProtocolVersion + 1,
            clientID: "gag",
            action: .readStatus
        )

        XCTAssertFalse(grant.permits(request))
    }

    func testRunCommandRequiresSeparateCapabilityFromSendText() {
        let grant = AutomationGrant(clientID: "gag", capabilities: [.sendText])
        let request = AutomationRequest(
            clientID: "gag",
            action: .runCommand(sessionID: UUID(), command: "npm run deploy")
        )

        XCTAssertFalse(grant.permits(request))
    }

    func testStatusStoreUpdatesSelectionWithoutRebuildingSnapshot() {
        let workspaceID = UUID()
        let sessionID = UUID()
        let store = AutomationStatusStore()
        let snapshot = AutomationStatusSnapshot(
            workspaces: [
                .init(id: workspaceID, name: "Main", paneCount: 1)
            ],
            sessions: [
                AutomationStatusSnapshot.SessionSummary(
                    id: sessionID,
                    title: "Shell",
                    state: .attached,
                    kind: "local"
                )
            ],
            selectedWorkspaceID: nil,
            selectedSessionID: nil,
            activeAgentCount: 0
        )
        store.update(snapshot)

        XCTAssertTrue(
            store.updateSelection(
                workspaceID: workspaceID,
                sessionID: sessionID
            )
        )
        let updated = store.snapshot()
        XCTAssertEqual(updated?.workspaces, snapshot.workspaces)
        XCTAssertEqual(updated?.sessions, snapshot.sessions)
        XCTAssertEqual(updated?.selectedWorkspaceID, workspaceID)
        XCTAssertEqual(updated?.selectedSessionID, sessionID)
    }

    func testStatusStoreSelectionUpdateRequiresExistingSnapshot() {
        let store = AutomationStatusStore()

        XCTAssertFalse(
            store.updateSelection(
                workspaceID: UUID(),
                sessionID: UUID()
            )
        )
        XCTAssertNil(store.snapshot())
    }
}
