import ApexTermCore
import XCTest

final class ResponsiveLayoutPolicyTests: XCTestCase {
    func testCompactWidthHidesBothSidePanels() {
        let layout = ResponsiveLayoutPolicy(width: 320, agentRailPreferred: true)

        XCTAssertEqual(layout.mode, .compact)
        XCTAssertFalse(layout.showsWorkspaceSidebar)
        XCTAssertFalse(layout.showsAgentRail)
        XCTAssertTrue(layout.usesCompactToolbar)
    }

    func testBalancedWidthPreservesTerminalByHidingAgentRail() {
        let layout = ResponsiveLayoutPolicy(width: 980, agentRailPreferred: true)

        XCTAssertEqual(layout.mode, .balanced)
        XCTAssertTrue(layout.showsWorkspaceSidebar)
        XCTAssertFalse(layout.showsAgentRail)
        XCTAssertTrue(layout.usesCompactToolbar)
    }

    func testWideWidthHonorsAgentRailPreference() {
        XCTAssertTrue(
            ResponsiveLayoutPolicy(width: 1_280, agentRailPreferred: true).showsAgentRail
        )
        XCTAssertFalse(
            ResponsiveLayoutPolicy(width: 1_280, agentRailPreferred: false).showsAgentRail
        )
    }

    func testNegativeWidthIsHandledAsCompact() {
        XCTAssertEqual(
            ResponsiveLayoutPolicy(width: -10, agentRailPreferred: true).mode,
            .compact
        )
    }
}
