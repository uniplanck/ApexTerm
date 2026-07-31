import Foundation

public enum SplitTreeOperations {
    public static let maximumPaneCount = 64

    public static func sessionIDs(in node: SplitNode) -> [UUID] {
        var result: [UUID] = []
        result.reserveCapacity(8)
        appendSessionIDs(from: node, to: &result)
        return result
    }

    public static func contains(sessionID: UUID, in node: SplitNode) -> Bool {
        switch node {
        case let .pane(existingID):
            existingID == sessionID
        case let .split(_, _, first, second):
            contains(sessionID: sessionID, in: first)
                || contains(sessionID: sessionID, in: second)
        }
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
        guard paneCount(in: node) < maximumPaneCount else {
            return node
        }
        let clampedRatio = min(0.9, max(0.1, ratio))
        return replacingPane(
            sessionID: sessionID,
            in: node
        ) { existingID in
            let existing = SplitNode.pane(sessionID: existingID)
            let inserted = SplitNode.pane(sessionID: newSessionID)
            return .split(
                axis: axis,
                ratio: clampedRatio,
                first: newPaneFirst ? inserted : existing,
                second: newPaneFirst ? existing : inserted
            )
        }.node
    }

    public static func inserting(
        subtree: SplitNode,
        at sessionID: UUID,
        axis: SplitNode.SplitAxis,
        newPaneFirst: Bool,
        ratio: Double = 0.5,
        in node: SplitNode
    ) -> SplitNode {
        guard paneCount(in: node) + paneCount(in: subtree) <= maximumPaneCount else {
            return node
        }
        let clampedRatio = min(0.9, max(0.1, ratio))
        return replacingPane(
            sessionID: sessionID,
            in: node
        ) { existingID in
            let existing = SplitNode.pane(sessionID: existingID)
            return .split(
                axis: axis,
                ratio: clampedRatio,
                first: newPaneFirst ? subtree : existing,
                second: newPaneFirst ? existing : subtree
            )
        }.node
    }

    public static func replacing(
        sessionID: UUID,
        with replacementID: UUID,
        in node: SplitNode
    ) -> SplitNode {
        replacingPane(sessionID: sessionID, in: node) { _ in
            .pane(sessionID: replacementID)
        }.node
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
        switch node {
        case let .pane(existingID):
            return existingID == sessionID ? nil : node
        case let .split(axis, ratio, first, second):
            let newFirst = removing(sessionID: sessionID, from: first)
            let newSecond = removing(sessionID: sessionID, from: second)

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

    public static func paneCount(in node: SplitNode) -> Int {
        switch node {
        case .pane:
            1
        case let .split(_, _, first, second):
            paneCount(in: first) + paneCount(in: second)
        }
    }

    private static func appendSessionIDs(from node: SplitNode, to result: inout [UUID]) {
        switch node {
        case let .pane(sessionID):
            result.append(sessionID)
        case let .split(_, _, first, second):
            appendSessionIDs(from: first, to: &result)
            appendSessionIDs(from: second, to: &result)
        }
    }

    private static func replacingPane(
        sessionID: UUID,
        in node: SplitNode,
        replacement: (UUID) -> SplitNode
    ) -> (node: SplitNode, replaced: Bool) {
        switch node {
        case let .pane(existingID):
            guard existingID == sessionID else { return (node, false) }
            return (replacement(existingID), true)

        case let .split(axis, ratio, first, second):
            let firstResult = replacingPane(
                sessionID: sessionID,
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

            let secondResult = replacingPane(
                sessionID: sessionID,
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
