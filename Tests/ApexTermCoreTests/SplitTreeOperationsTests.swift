import XCTest
@testable import ApexTermCore

final class SplitTreeOperationsTests: XCTestCase {
    func testLegacyPaneSplitBecomesTwoTerminalColumns() {
        let first = UUID()
        let second = UUID()
        let result = SplitTreeOperations.split(
            sessionID: first,
            newSessionID: second,
            axis: .vertical,
            in: .pane(sessionID: first)
        )

        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [first, second])
        XCTAssertEqual(SplitTreeOperations.columnCount(in: result), 2)
        XCTAssertTrue(SplitTreeOperations.contains(sessionID: first, in: result))
        XCTAssertTrue(SplitTreeOperations.contains(sessionID: second, in: result))
        XCTAssertNotNil(SplitTreeOperations.column(containing: first, in: result))
        XCTAssertNotNil(SplitTreeOperations.column(containing: second, in: result))
    }

    func testAddingSessionCreatesTabWithoutAddingColumn() {
        let first = UUID()
        let second = UUID()
        let column = TerminalColumn(id: UUID(), sessionIDs: [first], selectedSessionID: first)

        let result = SplitTreeOperations.addingSession(
            second,
            toColumnContaining: first,
            in: .column(column)
        )

        XCTAssertEqual(SplitTreeOperations.columnCount(in: result), 1)
        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [first, second])
        XCTAssertEqual(SplitTreeOperations.column(containing: first, in: result)?.selectedSessionID, second)
    }

    func testRemovingTabKeepsColumnAndSelectsSurvivingTab() {
        let first = UUID()
        let second = UUID()
        let columnID = UUID()
        let root = SplitNode.column(
            TerminalColumn(
                id: columnID,
                sessionIDs: [first, second],
                selectedSessionID: second
            )
        )

        let result = SplitTreeOperations.removing(sessionID: second, from: root)

        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: try! XCTUnwrap(result)), [first])
        XCTAssertEqual(SplitTreeOperations.columnCount(in: try! XCTUnwrap(result)), 1)
        XCTAssertEqual(
            SplitTreeOperations.column(id: columnID, in: try! XCTUnwrap(result))?.selectedSessionID,
            first
        )
    }

    func testMovingTabWithinColumnReordersIt() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let root = SplitNode.column(
            TerminalColumn(sessionIDs: [first, second, third], selectedSessionID: first)
        )

        let result = SplitTreeOperations.movingSession(
            third,
            relativeTo: first,
            after: false,
            in: root
        )

        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [third, first, second])
        XCTAssertEqual(SplitTreeOperations.column(containing: third, in: result)?.selectedSessionID, third)
    }

    func testMovingTabAcrossColumnsCollapsesEmptySourceColumn() {
        let source = UUID()
        let target = UUID()
        let sibling = UUID()
        let root = SplitNode.split(
            axis: .vertical,
            ratio: 0.5,
            first: .column(TerminalColumn(sessionID: source)),
            second: .column(
                TerminalColumn(sessionIDs: [target, sibling], selectedSessionID: target)
            )
        )

        let result = SplitTreeOperations.movingSession(
            source,
            relativeTo: target,
            after: true,
            in: root
        )

        XCTAssertEqual(SplitTreeOperations.columnCount(in: result), 1)
        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [target, source, sibling])
        XCTAssertEqual(SplitTreeOperations.column(containing: source, in: result)?.selectedSessionID, source)
    }

    func testMovingTabToColumnCenterAppendsAndSelects() {
        let source = UUID()
        let target = UUID()
        let sibling = UUID()
        let root = SplitNode.split(
            axis: .vertical,
            ratio: 0.5,
            first: .column(TerminalColumn(sessionID: source)),
            second: .column(
                TerminalColumn(sessionIDs: [target, sibling], selectedSessionID: target)
            )
        )

        let result = SplitTreeOperations.movingSessionToColumnEnd(
            source,
            targetSessionID: target,
            in: root
        )

        XCTAssertEqual(SplitTreeOperations.columnCount(in: result), 1)
        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [target, sibling, source])
        XCTAssertEqual(SplitTreeOperations.column(containing: source, in: result)?.selectedSessionID, source)
    }

    func testSameSessionSplitAnchorUsesSiblingTabInColumn() {
        let dragged = UUID()
        let sibling = UUID()
        let root = SplitNode.column(
            TerminalColumn(sessionIDs: [dragged, sibling], selectedSessionID: dragged)
        )

        XCTAssertEqual(
            SplitTreeOperations.splitAnchorSessionID(
                sourceSessionID: dragged,
                targetSessionID: dragged,
                in: root
            ),
            sibling
        )
        XCTAssertNil(
            SplitTreeOperations.splitAnchorSessionID(
                sourceSessionID: dragged,
                targetSessionID: dragged,
                in: .column(TerminalColumn(sessionID: dragged))
            )
        )
    }

    func testSplitPreservesExistingTabsInsideOriginalColumn() {
        let first = UUID()
        let second = UUID()
        let newSession = UUID()
        let root = SplitNode.column(
            TerminalColumn(sessionIDs: [first, second], selectedSessionID: second)
        )

        let result = SplitTreeOperations.split(
            sessionID: second,
            newSessionID: newSession,
            axis: .vertical,
            in: root
        )

        XCTAssertEqual(SplitTreeOperations.columnCount(in: result), 2)
        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [first, second, newSession])
        XCTAssertEqual(SplitTreeOperations.column(containing: first, in: result)?.sessionIDs, [first, second])
        XCTAssertEqual(SplitTreeOperations.column(containing: newSession, in: result)?.sessionIDs, [newSession])
    }

    func testThirdSideBySideColumnRebalancesToEqualWidths() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let root = SplitNode.split(
            axis: .vertical,
            ratio: 0.5,
            first: .column(TerminalColumn(sessionID: first)),
            second: .column(TerminalColumn(sessionID: second))
        )

        let result = SplitTreeOperations.inserting(
            subtree: .column(TerminalColumn(sessionID: third)),
            at: first,
            axis: .vertical,
            newPaneFirst: false,
            in: root
        )

        guard case let .split(.vertical, outerRatio, nested, _) = result,
              case let .split(.vertical, innerRatio, _, _) = nested else {
            return XCTFail("Expected three side-by-side columns")
        }
        XCTAssertEqual(outerRatio, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(innerRatio, 0.5, accuracy: 0.000_001)
    }

    func testRemovingSideBySideColumnRebalancesRemainingWidths() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let threeColumns = SplitNode.split(
            axis: .vertical,
            ratio: 2.0 / 3.0,
            first: .split(
                axis: .vertical,
                ratio: 0.5,
                first: .column(TerminalColumn(sessionID: first)),
                second: .column(TerminalColumn(sessionID: third))
            ),
            second: .column(TerminalColumn(sessionID: second))
        )

        let result = SplitTreeOperations.removing(sessionID: third, from: threeColumns)

        guard case let .split(.vertical, ratio, _, _) = try! XCTUnwrap(result) else {
            return XCTFail("Expected two remaining side-by-side columns")
        }
        XCTAssertEqual(ratio, 0.5, accuracy: 0.000_001)
    }

    func testHorizontalSplitPreservesExistingSideBySideRatio() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let root = SplitNode.split(
            axis: .vertical,
            ratio: 0.7,
            first: .column(TerminalColumn(sessionID: first)),
            second: .column(TerminalColumn(sessionID: second))
        )

        let result = SplitTreeOperations.split(
            sessionID: first,
            newSessionID: third,
            axis: .horizontal,
            in: root
        )

        guard case let .split(.vertical, ratio, _, _) = result else {
            return XCTFail("Expected existing side-by-side split")
        }
        XCTAssertEqual(ratio, 0.7, accuracy: 0.000_001)
    }

    func testNestedSplitTargetsOnlyRequestedColumn() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let root = SplitNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .column(TerminalColumn(sessionID: first)),
            second: .column(TerminalColumn(sessionID: second))
        )

        let result = SplitTreeOperations.split(
            sessionID: second,
            newSessionID: third,
            axis: .vertical,
            in: root
        )

        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [first, second, third])
        XCTAssertEqual(SplitTreeOperations.columnCount(in: result), 3)
    }

    func testRemovingLastTabCollapsesItsParentSplit() {
        let first = UUID()
        let second = UUID()
        let firstColumn = TerminalColumn(id: UUID(), sessionIDs: [first], selectedSessionID: first)
        let root = SplitNode.split(
            axis: .vertical,
            ratio: 0.5,
            first: .column(firstColumn),
            second: .column(TerminalColumn(sessionID: second))
        )

        let result = SplitTreeOperations.removing(sessionID: second, from: root)

        XCTAssertEqual(result, .column(firstColumn))
    }

    func testColumnCountStopsAtSupportedLimit() {
        let rootID = UUID()
        var tree = SplitNode.column(TerminalColumn(sessionID: rootID))
        var selectedID = rootID

        for _ in 1..<SplitTreeOperations.maximumColumnCount {
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
            SplitTreeOperations.columnCount(in: unchanged),
            SplitTreeOperations.maximumColumnCount
        )
        XCTAssertFalse(SplitTreeOperations.contains(sessionID: rejectedID, in: unchanged))
    }

    func testNewColumnCanBeInsertedBeforeTargetForDropPreview() {
        let existing = UUID()
        let inserted = UUID()
        let result = SplitTreeOperations.split(
            sessionID: existing,
            newSessionID: inserted,
            axis: .vertical,
            newPaneFirst: true,
            in: .column(TerminalColumn(sessionID: existing))
        )

        guard case let .split(axis, ratio, first, second) = result else {
            return XCTFail("Expected split")
        }
        XCTAssertEqual(axis, .vertical)
        XCTAssertEqual(ratio, 0.5)
        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: first), [inserted])
        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: second), [existing])
    }

    func testNestedSubtreeCanBeInsertedAtSpecificColumn() {
        let targetLeft = UUID()
        let targetRight = UUID()
        let movedTop = UUID()
        let movedBottom = UUID()
        let target = SplitNode.split(
            axis: .vertical,
            ratio: 0.5,
            first: .column(TerminalColumn(sessionID: targetLeft)),
            second: .column(TerminalColumn(sessionID: targetRight))
        )
        let moved = SplitNode.split(
            axis: .horizontal,
            ratio: 0.5,
            first: .column(TerminalColumn(sessionID: movedTop)),
            second: .column(TerminalColumn(sessionID: movedBottom))
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
        XCTAssertEqual(SplitTreeOperations.columnCount(in: result), 4)
    }

    func testReplacingSessionPreservesColumnAndTreeShape() {
        let first = UUID()
        let second = UUID()
        let replacement = UUID()
        let firstColumnID = UUID()
        let tree = SplitNode.split(
            axis: .vertical,
            ratio: 0.4,
            first: .column(
                TerminalColumn(
                    id: firstColumnID,
                    sessionIDs: [first],
                    selectedSessionID: first
                )
            ),
            second: .column(TerminalColumn(sessionID: second))
        )

        let result = SplitTreeOperations.replacing(
            sessionID: first,
            with: replacement,
            in: tree
        )

        XCTAssertEqual(SplitTreeOperations.sessionIDs(in: result), [replacement, second])
        XCTAssertEqual(
            SplitTreeOperations.column(id: firstColumnID, in: result)?.selectedSessionID,
            replacement
        )
        guard case let .split(_, ratio, _, _) = result else {
            return XCTFail("Expected split")
        }
        XCTAssertEqual(ratio, 0.4)
    }

    func testSplitRatioIsClamped() {
        let first = UUID()
        let second = UUID()
        let result = SplitTreeOperations.split(
            sessionID: first,
            newSessionID: second,
            axis: .horizontal,
            ratio: 5,
            in: .column(TerminalColumn(sessionID: first))
        )

        guard case let .split(_, ratio, _, _) = result else {
            return XCTFail("Expected split")
        }
        XCTAssertEqual(ratio, 0.9)
    }
}
