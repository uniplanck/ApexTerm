import ApexTermCore
import Foundation

struct QuickTerminalTab: Codable, Equatable, Identifiable {
    var id: UUID
    var sessionID: UUID
    var title: String
    var kind: SessionKind
    var workingDirectory: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID = UUID(),
        title: String,
        kind: SessionKind = .local,
        workingDirectory: String? = FileManager.default.homeDirectoryForCurrentUser.path,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.kind = kind
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
    }
}

struct QuickTerminalGroup: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var tabs: [QuickTerminalTab]
    var selectedTabID: UUID?

    init(
        id: UUID = UUID(),
        name: String = "Terminal Group",
        tabs: [QuickTerminalTab]
    ) {
        self.id = id
        self.name = name
        self.tabs = tabs
        self.selectedTabID = tabs.first?.id
    }
}

indirect enum QuickTerminalLayoutNode: Codable, Equatable {
    case group(id: UUID)
    case split(
        axis: SplitNode.SplitAxis,
        ratio: Double,
        first: QuickTerminalLayoutNode,
        second: QuickTerminalLayoutNode
    )
}

enum QuickTerminalDropPlacement: Equatable {
    case center
    case left
    case right
    case top
    case bottom
}

private struct QuickTerminalDocument: Codable {
    var groups: [QuickTerminalGroup]
    var layout: QuickTerminalLayoutNode
    var selectedGroupID: UUID?
}

@MainActor
final class QuickTerminalModel: ObservableObject {
    @Published private(set) var groups: [QuickTerminalGroup]
    @Published private(set) var layout: QuickTerminalLayoutNode
    @Published var selectedGroupID: UUID?

    private let fileURL: URL

    init() {
        fileURL = ApexTermPaths.supportDirectory()
            .appendingPathComponent("quick-terminal.json")

        if let data = try? Data(contentsOf: fileURL),
           let document = try? JSONDecoder().decode(QuickTerminalDocument.self, from: data),
           !document.groups.isEmpty {
            groups = document.groups
            layout = document.layout
            selectedGroupID = document.selectedGroupID ?? document.groups.first?.id
        } else {
            let tab = QuickTerminalTab(title: "zsh")
            let group = QuickTerminalGroup(name: "Main", tabs: [tab])
            groups = [group]
            layout = .group(id: group.id)
            selectedGroupID = group.id
            persist()
        }
        repairSelection()
    }

    func group(id: UUID) -> QuickTerminalGroup? {
        groups.first { $0.id == id }
    }

    func tab(id: UUID) -> QuickTerminalTab? {
        groups.lazy.compactMap { group in
            group.tabs.first { $0.id == id }
        }.first
    }

    func selectedTab(in groupID: UUID) -> QuickTerminalTab? {
        guard let group = group(id: groupID) else { return nil }
        return group.tabs.first { $0.id == group.selectedTabID } ?? group.tabs.first
    }

    @discardableResult
    func addLocalTab(to groupID: UUID? = nil) -> UUID {
        addTab(
            QuickTerminalTab(title: "zsh"),
            to: groupID ?? selectedGroupID ?? groups[0].id
        )
    }

    @discardableResult
    func addNamedTmuxTab(name: String, to groupID: UUID? = nil) -> UUID? {
        let normalized = LocalSessionLaunchPlanBuilder(
            tmuxExecutable: "tmux",
            shellExecutable: "/bin/zsh"
        ).normalizedSessionName(name)
        guard let normalized else { return nil }
        return addTab(
            QuickTerminalTab(
                title: normalized,
                kind: .localTmux(session: normalized)
            ),
            to: groupID ?? selectedGroupID ?? groups[0].id
        )
    }

    func select(tabID: UUID, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }),
              groups[index].tabs.contains(where: { $0.id == tabID }) else { return }
        groups[index].selectedTabID = tabID
        selectedGroupID = groupID
        persist()
    }

    func renameTab(id: UUID, to value: String) {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        for index in groups.indices {
            guard let tabIndex = groups[index].tabs.firstIndex(where: { $0.id == id }) else { continue }
            groups[index].tabs[tabIndex].title = String(name.prefix(80))
            persist()
            return
        }
    }

    func renameGroup(id: UUID, to value: String) {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = String(name.prefix(80))
        persist()
    }

    func closeTab(id: UUID) {
        guard let sourceIndex = groups.firstIndex(where: { group in
            group.tabs.contains { $0.id == id }
        }) else { return }
        groups[sourceIndex].tabs.removeAll { $0.id == id }
        if groups[sourceIndex].tabs.isEmpty {
            removeGroup(id: groups[sourceIndex].id)
        } else {
            groups[sourceIndex].selectedTabID = groups[sourceIndex].tabs.first?.id
        }
        repairSelection()
        persist()
    }

    func reorderTab(
        id: UUID,
        relativeTo targetID: UUID,
        after: Bool
    ) {
        guard id != targetID,
              let sourceGroupIndex = groups.firstIndex(where: { $0.tabs.contains { $0.id == id } }),
              let targetGroupIndex = groups.firstIndex(where: { $0.tabs.contains { $0.id == targetID } }),
              let sourceTabIndex = groups[sourceGroupIndex].tabs.firstIndex(where: { $0.id == id }),
              let targetTabIndex = groups[targetGroupIndex].tabs.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        let tab = groups[sourceGroupIndex].tabs.remove(at: sourceTabIndex)
        var insertion = targetTabIndex + (after ? 1 : 0)
        if sourceGroupIndex == targetGroupIndex, sourceTabIndex < insertion {
            insertion -= 1
        }
        insertion = min(max(0, insertion), groups[targetGroupIndex].tabs.count)
        groups[targetGroupIndex].tabs.insert(tab, at: insertion)
        groups[targetGroupIndex].selectedTabID = tab.id
        selectedGroupID = groups[targetGroupIndex].id
        if sourceGroupIndex != targetGroupIndex, groups[sourceGroupIndex].tabs.isEmpty {
            removeGroup(id: groups[sourceGroupIndex].id)
        }
        repairSelection()
        persist()
    }

    func moveTab(
        id: UUID,
        to targetGroupID: UUID,
        placement: QuickTerminalDropPlacement
    ) {
        guard let tab = tab(id: id),
              let sourceGroupIndex = groups.firstIndex(where: { $0.tabs.contains { $0.id == id } }),
              groups.contains(where: { $0.id == targetGroupID }) else { return }

        if placement == .center {
            groups[sourceGroupIndex].tabs.removeAll { $0.id == id }
            guard let targetIndex = groups.firstIndex(where: { $0.id == targetGroupID }) else { return }
            groups[targetIndex].tabs.append(tab)
            groups[targetIndex].selectedTabID = tab.id
            selectedGroupID = targetGroupID
            if sourceGroupIndex != targetIndex, groups[sourceGroupIndex].tabs.isEmpty {
                removeGroup(id: groups[sourceGroupIndex].id)
            }
            repairSelection()
            persist()
            return
        }

        let sourceGroupID = groups[sourceGroupIndex].id
        if sourceGroupID == targetGroupID,
           groups[sourceGroupIndex].tabs.count == 1 {
            return
        }

        groups[sourceGroupIndex].tabs.removeAll { $0.id == id }
        let newGroup = QuickTerminalGroup(name: tab.title, tabs: [tab])
        groups.append(newGroup)
        layout = split(
            targetGroupID: targetGroupID,
            newGroupID: newGroup.id,
            placement: placement,
            in: layout
        )
        selectedGroupID = newGroup.id
        if groups.first(where: { $0.id == sourceGroupID })?.tabs.isEmpty == true {
            removeGroup(id: sourceGroupID)
        }
        repairSelection()
        persist()
    }

    private func addTab(_ tab: QuickTerminalTab, to groupID: UUID) -> UUID {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return tab.id }
        groups[index].tabs.append(tab)
        groups[index].selectedTabID = tab.id
        selectedGroupID = groupID
        persist()
        return tab.id
    }

    private func split(
        targetGroupID: UUID,
        newGroupID: UUID,
        placement: QuickTerminalDropPlacement,
        in node: QuickTerminalLayoutNode
    ) -> QuickTerminalLayoutNode {
        switch node {
        case let .group(id):
            guard id == targetGroupID else { return node }
            let axis: SplitNode.SplitAxis = [.left, .right].contains(placement) ? .vertical : .horizontal
            let newFirst = placement == .left || placement == .top
            return .split(
                axis: axis,
                ratio: 0.5,
                first: newFirst ? .group(id: newGroupID) : node,
                second: newFirst ? node : .group(id: newGroupID)
            )
        case let .split(axis, ratio, first, second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: split(targetGroupID: targetGroupID, newGroupID: newGroupID, placement: placement, in: first),
                second: split(targetGroupID: targetGroupID, newGroupID: newGroupID, placement: placement, in: second)
            )
        }
    }

    private func removeGroup(id: UUID) {
        guard groups.count > 1 else {
            if groups[0].tabs.isEmpty {
                let tab = QuickTerminalTab(title: "zsh")
                groups[0].tabs = [tab]
                groups[0].selectedTabID = tab.id
            }
            return
        }
        groups.removeAll { $0.id == id }
        layout = removing(groupID: id, from: layout) ?? .group(id: groups[0].id)
    }

    private func removing(
        groupID: UUID,
        from node: QuickTerminalLayoutNode
    ) -> QuickTerminalLayoutNode? {
        switch node {
        case let .group(id):
            return id == groupID ? nil : node
        case let .split(axis, ratio, first, second):
            let left = removing(groupID: groupID, from: first)
            let right = removing(groupID: groupID, from: second)
            switch (left, right) {
            case let (left?, right?):
                return .split(axis: axis, ratio: ratio, first: left, second: right)
            case let (left?, nil):
                return left
            case let (nil, right?):
                return right
            case (nil, nil):
                return nil
            }
        }
    }

    private func repairSelection() {
        for index in groups.indices {
            if groups[index].tabs.contains(where: { $0.id == groups[index].selectedTabID }) == false {
                groups[index].selectedTabID = groups[index].tabs.first?.id
            }
        }
        if groups.contains(where: { $0.id == selectedGroupID }) == false {
            selectedGroupID = groups.first?.id
        }
    }

    private func persist() {
        let document = QuickTerminalDocument(
            groups: groups,
            layout: layout,
            selectedGroupID: selectedGroupID
        )
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}
