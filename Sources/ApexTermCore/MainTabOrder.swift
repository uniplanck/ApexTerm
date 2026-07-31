import Foundation

public struct MainTabReference: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case workspace
        case agentChat
    }

    public let kind: Kind
    public let uuid: UUID

    public init(kind: Kind, uuid: UUID) {
        self.kind = kind
        self.uuid = uuid
    }

    public static func workspace(_ id: UUID) -> MainTabReference {
        MainTabReference(kind: .workspace, uuid: id)
    }

    public static func agentChat(_ id: UUID) -> MainTabReference {
        MainTabReference(kind: .agentChat, uuid: id)
    }

    public var id: String {
        "\(kind.rawValue):\(uuid.uuidString)"
    }
}

public enum MainTabOrder {
    public static func normalized(
        _ existing: [MainTabReference],
        workspaceIDs: [UUID],
        agentChatIDs: [UUID]
    ) -> [MainTabReference] {
        let valid = Set(workspaceIDs.map(MainTabReference.workspace))
            .union(agentChatIDs.map(MainTabReference.agentChat))
        var seen: Set<MainTabReference> = []
        var result = existing.filter { valid.contains($0) && seen.insert($0).inserted }

        for id in workspaceIDs {
            let item = MainTabReference.workspace(id)
            if seen.insert(item).inserted { result.append(item) }
        }
        for id in agentChatIDs {
            let item = MainTabReference.agentChat(id)
            if seen.insert(item).inserted { result.append(item) }
        }
        return result
    }

    public static func moving(
        _ dragged: MainTabReference,
        relativeTo target: MainTabReference,
        after: Bool,
        in order: [MainTabReference]
    ) -> [MainTabReference] {
        guard dragged != target,
              let sourceIndex = order.firstIndex(of: dragged),
              let targetIndex = order.firstIndex(of: target) else {
            return order
        }

        var result = order
        let item = result.remove(at: sourceIndex)
        var insertion = targetIndex + (after ? 1 : 0)
        if sourceIndex < insertion { insertion -= 1 }
        insertion = min(max(0, insertion), result.count)
        result.insert(item, at: insertion)
        return result
    }
}
