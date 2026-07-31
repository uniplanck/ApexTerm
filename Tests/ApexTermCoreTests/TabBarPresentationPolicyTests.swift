import XCTest
@testable import ApexTermCore

final class TabBarPresentationPolicyTests: XCTestCase {
    func testNarrowWidthUsesIconOnlyTabsAndForcesSeparators() {
        let policy = TabBarPresentationPolicy(
            availableWidth: 320,
            separatorsEnabled: false
        )

        XCTAssertTrue(policy.usesIconOnlyTabs)
        XCTAssertTrue(policy.showsSeparators)
    }

    func testWideWidthKeepsLabelsAndRespectsSeparatorPreference() {
        XCTAssertFalse(
            TabBarPresentationPolicy(
                availableWidth: 640,
                separatorsEnabled: false
            ).usesIconOnlyTabs
        )
        XCTAssertFalse(
            TabBarPresentationPolicy(
                availableWidth: 640,
                separatorsEnabled: false
            ).showsSeparators
        )
        XCTAssertTrue(
            TabBarPresentationPolicy(
                availableWidth: 640,
                separatorsEnabled: true
            ).showsSeparators
        )
    }

    func testThresholdBoundaryKeepsLabels() {
        let policy = TabBarPresentationPolicy(
            availableWidth: TabBarPresentationPolicy.iconOnlyWidthThreshold,
            separatorsEnabled: true
        )

        XCTAssertFalse(policy.usesIconOnlyTabs)
    }
}
