import Foundation

public enum SplitTreeOperations {
    /// Kept for source compatibility. A split-tree leaf is now a terminal column.
    public static let maximumPaneCount = 64
    public static let maximumColumnCount = maximumPaneCount

    public static func normalizedColumns(in node: SplitNode) -> SplitNode {
        switch node {
        case let .pane(sessionID):
            return .column(TerminalColumn(id: sessionID, sessionIDs: [sessionID], selectedSessionID: sessionID))
        case .column:
            return node
        case let .split(axis, ratio, first, second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: normalizedColumns(in: first),
                second: normalizedColumns(in: second)
            )
        }
    }

    public static func sessionIDs(in node: SplitNode) -> [UUID] {
        var result: [UUID] = []
        result.reserveCapacity(8)
        appendSessionIDs(from: node, to: &result)
        return result
    }

    public static func contains(sessionID: UUID, in node: SplitNode) -> Bool {
        switch node {
        case let .pane(existingID):
            return existingID == sessionID
        case let .column(column):
            return column.sessionIDs.contains(sessionID)
        case let .split(_, _, first, second):
            return contains(sessionID: sessionID, in: first)
                || contains(sessionID: sessionID, in: second)
        }
    }

    public static func firstSelectedSessionID(in node: SplitNode) -> UUID? {
        switch node {
        case let .pane(sessionID):
            return sessionID
        case let .column(column):
            return column.sessionIDs.contains(column.selectedSessionID)
                ? column.selectedSessionID
                : column.sessionIDs.first
        case let .split(_, _, first, second):
            return firstSelectedSessionID(in: first) ?? firstSelectedSessionID(in: second)
        }
    }

    public static func column(containing sessionID: UUID, in node: SplitNode) -> TerminalColumn? {
        switch node {
        case let .pane(existingID):
            guard existingID == sessionID else { return nil }
            return TerminalColumn(id: existingID, sessionIDs: [existingID], selectedSessionID: existingID)
        case let .column(column):
            return column.sessionIDs.contains(sessionID) ? column : nil
        case let .split(_, _, first, second):
            return column(containing: sessionID, in: first)
                ?? column(containing: sessionID, in: second)
        }
    }

    public static func column(id columnID: UUID, in node: SplitNode) -> TerminalColumn? {
        switch node {
        case let .pane(sessionID):
            return sessionID == columnID
                ? TerminalColumn(id: sessionID, sessionIDs: [sessionID], selectedSessionID: sessionID)
                : nil
        case let .column(column):
            return column.id == columnID ? column : nil
        case let .split(_, _, first, second):
            return column(id: columnID, in: first) ?? column(id: columnID, in: second)
        }
    }

    public static func splitAnchorSessionID(
        sourceSessionID: UUID,
        targetSessionID: UUID,
        in node: SplitNode
    ) -> UUID? {
        guard contains(sessionID: sourceSessionID, in: node),
              contains(sessionID: targetSessionID, in: node) else {
            return nil
        }
        guard sourceSessionID == targetSessionID else {
            return targetSessionID
        }
        guard let sourceColumn = column(containing: sourceSessionID, in: node) else {
            return nil
        }
        return sourceColumn.sessionIDs.first(where: { $0 != sourceSessionID })
    }

    public static func selectingSession(_ sessionID: UUID, in node: SplitNode) -> SplitNode {
        switch node {
        case let .pane(existingID):
            guard existingID == sessionID else { return node }
            return .column(
                TerminalColumn(
                    id: existingID,
                    sessionIDs: [existingID],
                    selectedSessionID: existingID
                )
            )
        case var .column(column):
            guard column.sessionIDs.contains(sessionID) else { return node }
            column.selectedSessionID = sessionID
            return .column(column)
        case let .split(axis, ratio, first, second):
            if contains(sessionID: sessionID, in: first) {
                return .split(
                    axis: axis,
                    ratio: ratio,
                    first: selectingSession(sessionID, in: first),
                    second: second
                )
            }
            if contains(sessionID: sessionID, in: second) {
                return .split(
                    axis: axis,
                    ratio: ratio,
                    first: first,
                    second: selectingSession(sessionID, in: second)
                )
            }
            return node
        }
    }

    public static func addingSession(
        _ sessionID: UUID,
        toColumnContaining targetSessionID: UUID,
        select: Bool = true,
        in node: SplitNode
    ) -> SplitNode {
        replacingLeaf(containing: targetSessionID, in: node) { leaf in
            var column = terminalColumn(from: leaf)
            guard !column.sessionIDs.contains(sessionID) else { return leaf }
            column.sessionIDs.append(sessionID)
            if select {
                column.selectedSessionID = sessionID
            }
            return .column(column)
        }.node
    }

    public static func movingSession(
        _ sourceSessionID: UUID,
        relativeTo targetSessionID: UUID,
        after: Bool,
        in node: SplitNode
    ) -> SplitNode {
        guard sourceSessionID != targetSessionID,
              let sourceColumn = column(containing: sourceSessionID, in: node),
              let targetColumn = column(containing: targetSessionID, in: node) else {
            return node
        }

        if sourceColumn.id == targetColumn.id {
            return replacingLeaf(containing: targetSessionID, in: node) { leaf in
                var column = terminalColumn(from: leaf)
                guard let sourceIndex = column.sessionIDs.firstIndex(of: sourceSessionID),
                      let targetIndex = column.sessionIDs.firstIndex(of: targetSessionID) else {
                    return leaf
                }
                let moved = column.sessionIDs.remove(at: sourceIndex)
                var insertion = after ? targetIndex + 1 : targetIndex
                if sourceIndex < insertion { insertion -= 1 }
                insertion = min(max(0, insertion), column.sessionIDs.count)
                column.sessionIDs.insert(moved, at: insertion)
                column.selectedSessionID = moved
                return .column(column)
            }.node
        }

        guard let reduced = removing(sessionID: sourceSessionID, from: node),
              contains(sessionID: targetSessionID, in: reduced) else {
            return node
        }
        return replacingLeaf(containing: targetSessionID, in: reduced) { leaf in
            var column = terminalColumn(from: leaf)
            guard let targetIndex = column.sessionIDs.firstIndex(of: targetSessionID) else {
                return leaf
            }
            let insertion = after ? targetIndex + 1 : targetIndex
            column.sessionIDs.insert(sourceSessionID, at: insertion)
            column.selectedSessionID = sourceSessionID
            return .column(column)
        }.node
    }

    public static func movingSessionToColumnEnd(
        _ sourceSessionID: UUID,
        targetSessionID: UUID,
        in node: SplitNode
    ) -> SplitNode {
        guard sourceSessionID != targetSessionID,
              let sourceColumn = column(containing: sourceSessionID, in: node),
              let targetColumn = column(containing: targetSessionID, in: node) else {
            return node
        }
        if sourceColumn.id == targetColumn.id {
            return selectingSession(sourceSessionID, in: node)
        }
        guard let reduced = removing(sessionID: sourceSessionID, from: node),
              contains(sessionID: targetSessionID, in: reduced) else {
            return node
        }
        return addingSession(
            sourceSessionID,
            toColumnContaining: targetSessionID,
            select: true,
            in: reduced
        )
    }

    public static func split(
        sessionID: UUID,
        newSessionID: UUID,
        axis: SplitNode.SplitAxis,
        ratio: Double = 0.5,
        in node: SplitNode
    ) -> SplitNode {
        split(
            sessionID: sessionID,
            newSessionID: newSessionID,
            axis: axis,
            newPaneFirst: false,
            ratio: ratio,
            in: node
        )
    }

    public static func split(
        sessionID: UUID,
        newSessionID: UUID,
        axis: SplitNode.SplitAxis,
        newPaneFirst: Bool,
        ratio: Double = 0.5,
        in node: SplitNode
    ) -> SplitNode {
        guard columnCount(in: node) < maximumColumnCount else {
            return node
        }
        let clampedRatio = min(0.9, max(0.1, ratio))
        let result = replacingLeaf(containing: sessionID, in: node) { existingLeaf in
            let existing = normalizedColumns(in: existingLeaf)
            let inserted = SplitNode.column(TerminalColumn(sessionID: newSessionID))
            return .split(
                axis: axis,
                ratio: clampedRatio,
                first: newPaneFirst ? inserted : existing,
                second: newPaneFirst ? existing : inserted
            )
        }.node
        return horizontalSpanUnits(in: result) == horizontalSpanUnits(in: node)
            ? result
            : rebalancedColumnWidths(in: result)
    }

    public static func inserting(
        subtree: SplitNode,
        at sessionID: UUID,
        axis: SplitNode.SplitAxis,
        newPaneFirst: Bool,
        ratio: Double = 0.5,
        in node: SplitNode
    ) -> SplitNode {
        guard columnCount(in: node) + columnCount(in: subtree) <= maximumColumnCount else {
            return node
        }
        let clampedRatio = min(0.9, max(0.1, ratio))
        let result = replacingLeaf(containing: sessionID, in: node) { existingLeaf in
            let existing = normalizedColumns(in: existingLeaf)
            return .split(
                axis: axis,
                ratio: clampedRatio,
                first: newPaneFirst ? normalizedColumns(in: subtree) : existing,
                second: newPaneFirst ? existing : normalizedColumns(in: subtree)
            )
        }.node
        return horizontalSpanUnits(in: result) == horizontalSpanUnits(in: node)
            ? result
            : rebalancedColumnWidths(in: result)
    }

    public static func replacing(
        sessionID: UUID,
        with replacementID: UUID,
        in node: SplitNode
    ) -> SplitNode {
        switch node {
        case let .pane(existingID):
            return existingID == sessionID ? .pane(sessionID: replacementID) : node
        case var .column(column):
            guard let index = column.sessionIDs.firstIndex(of: sessionID) else { return node }
            column.sessionIDs[index] = replacementID
            if column.selectedSessionID == sessionID {
                column.selectedSessionID = replacementID
            }
            return .column(column)
        case let .split(axis, ratio, first, second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: replacing(sessionID: sessionID, with: replacementID, in: first),
                second: replacing(sessionID: sessionID, with: replacementID, in: second)
            )
        }
    }

    public static func swappingSessions(
        _ firstID: UUID,
        _ secondID: UUID,
        in node: SplitNode
    ) -> SplitNode {
        switch node {
        case let .pane(sessionID):
            if sessionID == firstID { return .pane(sessionID: secondID) }
            if sessionID == secondID { return .pane(sessionID: firstID) }
            return node
        case var .column(column):
            for index in column.sessionIDs.indices {
                if column.sessionIDs[index] == firstID {
                    column.sessionIDs[index] = secondID
                } else if column.sessionIDs[index] == secondID {
                    column.sessionIDs[index] = firstID
                }
            }
            if column.selectedSessionID == firstID {
                column.selectedSessionID = secondID
            } else if column.selectedSessionID == secondID {
                column.selectedSessionID = firstID
            }
            return .column(column)
        case let .split(axis, ratio, first, second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: swappingSessions(firstID, secondID, in: first),
                second: swappingSessions(firstID, secondID, in: second)
            )
        }
    }

    public static func removing(sessionID: UUID, from node: SplitNode) -> SplitNode? {
        guard let result = removingWithoutRebalancing(sessionID: sessionID, from: node) else {
            return nil
        }
        return horizontalSpanUnits(in: result) == horizontalSpanUnits(in: node)
            ? result
            : rebalancedColumnWidths(in: result)
    }

    public static func paneCount(in node: SplitNode) -> Int {
        columnCount(in: node)
    }

    public static func columnCount(in node: SplitNode) -> Int {
        switch node {
        case .pane, .column:
            return 1
        case let .split(_, _, first, second):
            return columnCount(in: first) + columnCount(in: second)
        }
    }

    public static func rebalancedColumnWidths(in node: SplitNode) -> SplitNode {
        switch node {
        case .pane, .column:
            return node
        case let .split(axis, ratio, first, second):
            let balancedFirst = rebalancedColumnWidths(in: first)
            let balancedSecond = rebalancedColumnWidths(in: second)
            guard axis == .vertical else {
                return .split(
                    axis: axis,
                    ratio: ratio,
                    first: balancedFirst,
                    second: balancedSecond
                )
            }
            let firstUnits = horizontalSpanUnits(in: balancedFirst)
            let secondUnits = horizontalSpanUnits(in: balancedSecond)
            let totalUnits = max(1, firstUnits + secondUnits)
            return .split(
                axis: axis,
                ratio: Double(firstUnits) / Double(totalUnits),
                first: balancedFirst,
                second: balancedSecond
            )
        }
    }

    private static func horizontalSpanUnits(in node: SplitNode) -> Int {
        switch node {
        case .pane, .column:
            return 1
        case let .split(axis, _, first, second):
            let firstUnits = horizontalSpanUnits(in: first)
            let secondUnits = horizontalSpanUnits(in: second)
            return axis == .vertical
                ? firstUnits + secondUnits
                : max(firstUnits, secondUnits)
        }
    }

    private static func removingWithoutRebalancing(
        sessionID: UUID,
        from node: SplitNode
    ) -> SplitNode? {
        switch node {
        case let .pane(existingID):
            return existingID == sessionID ? nil : node
        case var .column(column):
            guard let removedIndex = column.sessionIDs.firstIndex(of: sessionID) else {
                return node
            }
            column.sessionIDs.remove(at: removedIndex)
            guard !column.sessionIDs.isEmpty else { return nil }
            if column.selectedSessionID == sessionID {
                let nextIndex = min(removedIndex, column.sessionIDs.count - 1)
                column.selectedSessionID = column.sessionIDs[nextIndex]
            }
            return .column(column)
        case let .split(axis, ratio, first, second):
            let newFirst = removingWithoutRebalancing(sessionID: sessionID, from: first)
            let newSecond = removingWithoutRebalancing(sessionID: sessionID, from: second)

            switch (newFirst, newSecond) {
            case let (first?, second?):
                return .split(axis: axis, ratio: ratio, first: first, second: second)
            case let (first?, nil):
                return first
            case let (nil, second?):
                return second
            case (nil, nil):
                return nil
            }
        }
    }

    private static func appendSessionIDs(from node: SplitNode, to result: inout [UUID]) {
        switch node {
        case let .pane(sessionID):
            result.append(sessionID)
        case let .column(column):
            result.append(contentsOf: column.sessionIDs)
        case let .split(_, _, first, second):
            appendSessionIDs(from: first, to: &result)
            appendSessionIDs(from: second, to: &result)
        }
    }

    private static func terminalColumn(from leaf: SplitNode) -> TerminalColumn {
        switch leaf {
        case let .pane(sessionID):
            return TerminalColumn(id: sessionID, sessionIDs: [sessionID], selectedSessionID: sessionID)
        case let .column(column):
            return column
        case .split:
            preconditionFailure("Expected a terminal-column leaf")
        }
    }

    private static func replacingLeaf(
        containing sessionID: UUID,
        in node: SplitNode,
        replacement: (SplitNode) -> SplitNode
    ) -> (node: SplitNode, replaced: Bool) {
        switch node {
        case let .pane(existingID):
            guard existingID == sessionID else { return (node, false) }
            return (replacement(node), true)
        case let .column(column):
            guard column.sessionIDs.contains(sessionID) else { return (node, false) }
            return (replacement(node), true)
        case let .split(axis, ratio, first, second):
            let firstResult = replacingLeaf(
                containing: sessionID,
                in: first,
                replacement: replacement
            )
            if firstResult.replaced {
                return (
                    .split(
                        axis: axis,
                        ratio: ratio,
                        first: firstResult.node,
                        second: second
                    ),
                    true
                )
            }

            let secondResult = replacingLeaf(
                containing: sessionID,
                in: second,
                replacement: replacement
            )
            guard secondResult.replaced else { return (node, false) }
            return (
                .split(
                    axis: axis,
                    ratio: ratio,
                    first: first,
                    second: secondResult.node
                ),
                true
            )
        }
    }
}
