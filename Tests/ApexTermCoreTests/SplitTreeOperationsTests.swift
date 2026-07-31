import XCTest
@testable import ApexTermCore

final class SplitTreeOperationsTests: XCTestCase {
    func testSplitAddsSessionAndPreservesExistingSession() {
        let first = UUID()
        let second = UUID()
        let result = SplitTreeOperations.split(
            sessionID: first,
            newSessionID: second,
            axis: .vertical,
            in: .pane(sessionID: first)
        )

        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [first, second])
        XCTAssertTrue(SplitTreeOperations.contains(sessionID: first, in: result))
        XCTAssertTrue(SplitTreeOperations.contains(sessionID: second, in: result))
    }

    func testNestedSplitTargetsOnlyRequestedPane() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let root = SplitNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .pane(sessionID: first),
            second: .pane(sessionID: second)
        )

        let result = SplitTreeOperations.split(
            sessionID: second,
            newSessionID: third,
            axis: .vertical,
            in: root
        )

        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [first, second, third])
    }

    func testRemovingPaneCollapsesItsParentSplit() {
        let first = UUID()
        let second = UUID()
        let root = SplitNode.split(
            axis: .vertical,
            ratio: 0.5,
            first: .pane(sessionID: first),
            second: .pane(sessionID: second)
        )

        let result = SplitTreeOperations.removing(sessionID: second, from: root)

        XCTAssertEqual(result, .pane(sessionID: first))
    }

    func testPaneCountStopsAtSupportedLimit() {
        let rootID = UUID()
        var tree = SplitNode.pane(sessionID: rootID)
        var selectedID = rootID

        for _ in 1..<SplitTreeOperations.maximumPaneCount {
            let newID = UUID()
            tree = SplitTreeOperations.split(
                sessionID: selectedID,
                newSessionID: newID,
                axis: .vertical,
                in: tree
            )
            selectedID = newID
        }

        let rejectedID = UUID()
        let unchanged = SplitTreeOperations.split(
            sessionID: selectedID,
            newSessionID: rejectedID,
            axis: .horizontal,
            in: tree
        )

        XCTAssertEqual(
            SplitTreeOperations.paneCount(in: unchanged),
            SplitTreeOperations.maximumPaneCount
        )
        XCTAssertFalse(SplitTreeOperations.contains(sessionID: rejectedID, in: unchanged))
    }

    func testNewPaneCanBeInsertedBeforeTargetForDropPreview() {
        let existing = UUID()
        let inserted = UUID()
        let result = SplitTreeOperations.split(
            sessionID: existing,
            newSessionID: inserted,
            axis: .vertical,
            newPaneFirst: true,
            in: .pane(sessionID: existing)
        )

        XCTAssertEqual(
            result,
            .split(
                axis: .vertical,
                ratio: 0.5,
                first: .pane(sessionID: inserted),
                second: .pane(sessionID: existing)
            )
        )
    }

    func testNestedSubtreeCanBeInsertedAtSpecificPane() {
        let targetLeft = UUID()
        let targetRight = UUID()
        let movedTop = UUID()
        let movedBottom = UUID()
        let target = SplitNode.split(
            axis: .vertical,
            ratio: 0.5,
            first: .pane(sessionID: targetLeft),
            second: .pane(sessionID: targetRight)
        )
        let moved = SplitNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .pane(sessionID: movedTop),
            second: .pane(sessionID: movedBottom)
        )

        let result = SplitTreeOperations.inserting(
            subtree: moved,
            at: targetRight,
            axis: .vertical,
            newPaneFirst: true,
            in: target
        )

        XCTAssertEqual(
            SplitTreeOperations.sessionIDs(in: result),
            [targetLeft, movedTop, movedBottom, targetRight]
        )
        XCTAssertEqual(SplitTreeOperations.paneCount(in: result), 4)
    }

    func testReplacingSessionPreservesTreeShape() {
        let first = UUID()
        let second = UUID()
        let replacement = UUID()
        let tree = SplitNode.split(
            axis: .vertical,
            ratio: 0.4,
            first: .pane(sessionID: first),
            second: .pane(sessionID: second)
        )

        let result = SplitTreeOperations.replacing(
            sessionID: first,
            with: replacement,
            in: tree
        )

        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [replacement, second])
        guard case let .split(_, ratio, _, _) = result else {
            return XCTFail("Expected split")
        }
        XCTAssertEqual(ratio, 0.4)
    }

    func testSwappingSessionsSupportsPaneHeaderReordering() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let tree = SplitNode.split(
            axis: .vertical,
            ratio: 0.5,
            first: .pane(sessionID: first),
            second: .split(
                axis: .horizontal,
                ratio: 0.5,
                first: .pane(sessionID: second),
                second: .pane(sessionID: third)
            )
        )

        let result = SplitTreeOperations.swappingSessions(first, third, in: tree)

        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [third, second, first])
    }

    func testSplitRatioIsClamped() {
        let first = UUID()
        let second = UUID()
        let result = SplitTreeOperations.split(
            sessionID: first,
            newSessionID: second,
            axis: .horizontal,
            ratio: 5,
            in: .pane(sessionID: first)
        )

        guard case let .split(_, ratio, _, _) = result else {
            return XCTFail("Expected split")
        }
        XCTAssertEqual(ratio, 0.9)
    }
}
