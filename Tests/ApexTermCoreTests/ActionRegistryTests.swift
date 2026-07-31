import XCTest
@testable import ApexTermCore

final class ActionRegistryTests: XCTestCase {
    func testDefaultActionIDsAreUniqueAndStable() {
        let registry = ApexActionRegistry()
        let ids = registry.actions.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertNotNil(registry.action(id: "search.universal"))
        XCTAssertNotNil(registry.action(id: "workspace.new"))
        XCTAssertNotNil(registry.action(id: "terminal.quick"))
        XCTAssertNotNil(registry.action(id: "terminal.find"))
        XCTAssertNotNil(registry.action(id: "pane.select.1"))
        XCTAssertNotNil(registry.action(id: "pane.select.4"))
        XCTAssertNotNil(registry.action(id: "tab.next"))
        XCTAssertNotNil(registry.action(id: "tab.previous"))
        XCTAssertNotNil(registry.action(id: "terminal.latestOutput.copy"))
        XCTAssertTrue(
            Set(ApexSettingsDocument.defaultKeybindings.map(\.actionID))
                .isSubset(of: Set(ids))
        )
    }

    func testSearchMatchesEnglishJapaneseAndKeywords() {
        let registry = ApexActionRegistry()

        XCTAssertEqual(registry.search("横断").first?.id, "search.universal")
        XCTAssertEqual(registry.search("quick").first?.id, "terminal.quick")
        XCTAssertEqual(registry.search("検索").first?.id, "terminal.find")
        XCTAssertEqual(registry.search("codex").first?.id, "agent.toggleRail")
        XCTAssertEqual(registry.search("context").first?.id, "terminal.context.copy")
        XCTAssertEqual(registry.search("失敗").first?.id, "terminal.failure.launchpad")
        XCTAssertEqual(registry.search("最新出力").first?.id, "terminal.latestOutput.copy")
        XCTAssertEqual(registry.search("タブ").first?.id, "tab.select.1")
    }

    func testExactAndPrefixMatchesRankAboveSubtitleMatches() {
        let registry = ApexActionRegistry(actions: [
            ApexActionDescriptor(
                id: "subtitle",
                title: "Other",
                subtitle: "Open Workspace later",
                keywords: [],
                systemImage: "circle"
            ),
            ApexActionDescriptor(
                id: "exact",
                title: "Workspace",
                subtitle: "Exact",
                keywords: [],
                systemImage: "circle"
            )
        ])

        XCTAssertEqual(registry.search("workspace").map(\.id), ["exact", "subtitle"])
    }

    func testDuplicateActionIDsAreDropped() {
        let first = ApexActionDescriptor(
            id: "duplicate",
            title: "First",
            subtitle: "First",
            keywords: [],
            systemImage: "circle"
        )
        let second = ApexActionDescriptor(
            id: "duplicate",
            title: "Second",
            subtitle: "Second",
            keywords: [],
            systemImage: "circle"
        )

        XCTAssertEqual(ApexActionRegistry(actions: [first, second]).actions, [first])
    }
}
