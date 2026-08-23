import ApexTermCore
import XCTest

final class ResponsiveLayoutPolicyTests: XCTestCase {
    func testCompactWidthHidesBothSidePanelsWithoutSwitchingToolbarMode() {
        let layout = ResponsiveLayoutPolicy(width: 320, agentRailPreferred: true)

        XCTAssertEqual(layout.mode, .compact)
        XCTAssertFalse(layout.showsWorkspaceSidebar)
        XCTAssertFalse(layout.showsAgentRail)
        XCTAssertFalse(layout.usesCompactToolbar)
        XCTAssertEqual(layout.mainToolbarControlCapacity, 2)
    }

    func testBalancedWidthPreservesTerminalByHidingAgentRail() {
        let layout = ResponsiveLayoutPolicy(width: 980, agentRailPreferred: true)

        XCTAssertEqual(layout.mode, .balanced)
        XCTAssertTrue(layout.showsWorkspaceSidebar)
        XCTAssertFalse(layout.showsAgentRail)
        XCTAssertFalse(layout.usesCompactToolbar)
        XCTAssertEqual(layout.mainToolbarControlCapacity, Int.max)
    }

    func testToolbarCapacityGrowsProgressivelyWithWidth() {
        XCTAssertEqual(
            ResponsiveLayoutPolicy(width: 620, agentRailPreferred: false).mainToolbarControlCapacity,
            4
        )
        XCTAssertEqual(
            ResponsiveLayoutPolicy(width: 780, agentRailPreferred: false).mainToolbarControlCapacity,
            7
        )
        XCTAssertEqual(
            ResponsiveLayoutPolicy(width: 920, agentRailPreferred: false).mainToolbarControlCapacity,
            11
        )
    }

    func testWideWidthHonorsAgentRailPreference() {
        XCTAssertTrue(
            ResponsiveLayoutPolicy(width: 1_280, agentRailPreferred: true).showsAgentRail
        )
        XCTAssertFalse(
            ResponsiveLayoutPolicy(width: 1_280, agentRailPreferred: false).showsAgentRail
        )
        XCTAssertEqual(
            ResponsiveLayoutPolicy(width: 1_280, agentRailPreferred: true).mainToolbarControlCapacity,
            Int.max
        )
    }

    func testNegativeWidthIsHandledAsCompact() {
        let layout = ResponsiveLayoutPolicy(width: -10, agentRailPreferred: true)
        XCTAssertEqual(layout.mode, .compact)
        XCTAssertEqual(layout.mainToolbarControlCapacity, 2)
    }
}
