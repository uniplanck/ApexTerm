import XCTest
@testable import ApexTermCore

final class MainTabOrderTests: XCTestCase {
    func testNormalizationPreservesMixedOrderAndAppendsMissingTabs() {
        let workspaceA = UUID()
        let workspaceB = UUID()
        let chat = UUID()
        let stale = UUID()

        let result = MainTabOrder.normalized(
            [
                .agentChat(chat),
                .workspace(workspaceA),
                .workspace(workspaceA),
                .agentChat(stale)
            ],
            workspaceIDs: [workspaceA, workspaceB],
            agentChatIDs: [chat]
        )

        XCTAssertEqual(
            result,
            [.agentChat(chat), .workspace(workspaceA), .workspace(workspaceB)]
        )
    }

    func testMoveSupportsWorkspaceAndAgentChatInterleaving() {
        let workspaceA = MainTabReference.workspace(UUID())
        let workspaceB = MainTabReference.workspace(UUID())
        let chat = MainTabReference.agentChat(UUID())
        let original = [workspaceA, workspaceB, chat]

        XCTAssertEqual(
            MainTabOrder.moving(chat, relativeTo: workspaceA, after: false, in: original),
            [chat, workspaceA, workspaceB]
        )
        XCTAssertEqual(
            MainTabOrder.moving(workspaceA, relativeTo: chat, after: true, in: original),
            [workspaceB, chat, workspaceA]
        )
    }
}
