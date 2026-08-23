import Foundation

public enum UIControlZone: String, Codable, CaseIterable, Identifiable, Sendable {
    case tabBar
    case mainToolbar
    case compactToolbar
    case sidebarHeader
    case compactLeftRail
    case compactRightRail

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tabBar: "Tab Bar"
        case .mainToolbar: "Main Toolbar"
        case .compactToolbar: "Compact Toolbar"
        case .sidebarHeader: "Sidebar Header"
        case .compactLeftRail: "Sidebar"
        case .compactRightRail: "Legacy Right Sidebar"
        }
    }
}

public enum UIControlID: String, Codable, CaseIterable, Identifiable, Sendable {
    case newTab
    case remoteHostLaunch
    case tmuxManager
    case tabBarPinWindow
    case compactMode
    case tabCloseButtons
    case tabSeparators

    case toggleLeftSidebar
    case commandPalette
    case findTerminal
    case quickTerminal
    case historySearch
    case copyContextPack
    case openFailureInAgent
    case toggleCommandHistory
    case toolbarPinWindow
    case splitVertical
    case splitHorizontal
    case closePane
    case maximizePane
    case toggleRightSidebar

    case compactWorkspaces
    case compactFind
    case compactHistorySearch
    case compactOverflow

    case sidebarSettings
    case sidebarNewWorkspace

    case expandLeftSidebar
    case remoteHostSettings

    case expandRightSidebar
    case rightRailHistory
    case rightRailAgents

    public var id: String { rawValue }

    public var zone: UIControlZone {
        switch self {
        case .newTab, .remoteHostLaunch, .tmuxManager, .tabBarPinWindow, .compactMode,
             .tabCloseButtons, .tabSeparators:
            .tabBar
        case .toggleLeftSidebar, .commandPalette, .findTerminal, .quickTerminal,
             .historySearch, .copyContextPack, .openFailureInAgent, .toggleCommandHistory,
             .toolbarPinWindow, .splitVertical, .splitHorizontal, .closePane, .maximizePane,
             .toggleRightSidebar:
            .mainToolbar
        case .compactWorkspaces, .compactFind, .compactHistorySearch, .compactOverflow:
            .compactToolbar
        case .sidebarSettings, .sidebarNewWorkspace:
            .sidebarHeader
        case .expandLeftSidebar, .remoteHostSettings:
            .compactLeftRail
        case .expandRightSidebar, .rightRailHistory, .rightRailAgents:
            .compactRightRail
        }
    }

    public var title: String {
        switch self {
        case .newTab: "New Tab"
        case .remoteHostLaunch: "Remote Hosts"
        case .tmuxManager: "tmux Sessions"
        case .tabBarPinWindow, .toolbarPinWindow: "Pin Window"
        case .compactMode: "Compact Mode"
        case .tabCloseButtons: "Tab Close Buttons"
        case .tabSeparators: "Tab Separators"
        case .toggleLeftSidebar: "Left Sidebar"
        case .commandPalette: "Command Palette"
        case .findTerminal, .compactFind: "Find in Terminal"
        case .quickTerminal: "Quick Terminal"
        case .historySearch, .compactHistorySearch: "Search Command History"
        case .copyContextPack: "Copy Context Pack"
        case .openFailureInAgent: "Open Failure in Agent Chat"
        case .toggleCommandHistory: "Command History"
        case .splitVertical: "Split Left / Right"
        case .splitHorizontal: "Split Top / Bottom"
        case .closePane: "Close Pane"
        case .maximizePane: "Maximize Pane"
        case .toggleRightSidebar: "Right Sidebar"
        case .compactWorkspaces: "Workspaces"
        case .compactOverflow: "More Menu"
        case .sidebarSettings: "Settings"
        case .sidebarNewWorkspace: "New Workspace"
        case .expandLeftSidebar: "Sidebar Toggle"
        case .remoteHostSettings: "Remote Host Settings"
        case .expandRightSidebar: "Expand Right Sidebar"
        case .rightRailHistory: "Command History"
        case .rightRailAgents: "Agent Runs"
        }
    }

    public var systemImage: String {
        switch self {
        case .newTab, .sidebarNewWorkspace: "plus"
        case .remoteHostLaunch: "globe"
        case .tmuxManager: "rectangle.stack"
        case .tabBarPinWindow, .toolbarPinWindow: "pin"
        case .compactMode: "rectangle.compress.vertical"
        case .tabCloseButtons, .closePane: "xmark"
        case .tabSeparators: "line.vertical"
        case .toggleLeftSidebar, .expandLeftSidebar, .compactWorkspaces: "sidebar.left"
        case .commandPalette: "command"
        case .findTerminal, .compactFind: "magnifyingglass"
        case .quickTerminal: "macwindow.on.rectangle"
        case .historySearch, .compactHistorySearch: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .copyContextPack: "doc.on.doc"
        case .openFailureInAgent: "wrench.and.screwdriver"
        case .toggleCommandHistory, .rightRailHistory: "clock"
        case .splitVertical: "rectangle.split.2x1"
        case .splitHorizontal: "rectangle.split.1x2"
        case .maximizePane: "arrow.up.left.and.arrow.down.right"
        case .toggleRightSidebar, .expandRightSidebar: "sidebar.right"
        case .compactOverflow: "ellipsis.circle"
        case .sidebarSettings, .remoteHostSettings: "gearshape"
        case .rightRailAgents: "bolt.horizontal.circle"
        }
    }

    public var isMainToolbarSurfaceAvailable: Bool {
        guard zone == .mainToolbar else { return true }
        switch self {
        case .toggleLeftSidebar, .toggleRightSidebar, .splitVertical, .splitHorizontal,
             .toggleCommandHistory, .toolbarPinWindow:
            return false
        default:
            return true
        }
    }

    public static func controls(in zone: UIControlZone) -> [UIControlID] {
        allCases.filter { $0.zone == zone }
    }
}

public struct UIControlCustomization: Codable, Equatable, Sendable {
    public static let defaultMainToolbarOrder: [UIControlID] = [
        .toggleLeftSidebar,
        .commandPalette,
        .findTerminal,
        .quickTerminal,
        .historySearch,
        .copyContextPack,
        .openFailureInAgent,
        .toggleCommandHistory,
        .toolbarPinWindow,
        .splitVertical,
        .splitHorizontal,
        .closePane,
        .maximizePane,
        .toggleRightSidebar
    ]

    public var hiddenControls: Set<UIControlID>
    public var mainToolbarOrder: [UIControlID]

    public init(
        hiddenControls: Set<UIControlID> = [],
        mainToolbarOrder: [UIControlID] = Self.defaultMainToolbarOrder
    ) {
        self.hiddenControls = hiddenControls
        self.mainToolbarOrder = Self.normalizedToolbarOrder(mainToolbarOrder)
    }

    public func isVisible(_ control: UIControlID) -> Bool {
        !hiddenControls.contains(control)
    }

    public mutating func setVisible(_ visible: Bool, for control: UIControlID) {
        if visible {
            hiddenControls.remove(control)
        } else {
            hiddenControls.insert(control)
        }
    }

    public mutating func moveMainToolbarControl(_ control: UIControlID, before target: UIControlID) {
        guard control != target,
              control.zone == .mainToolbar,
              target.zone == .mainToolbar,
              let sourceIndex = mainToolbarOrder.firstIndex(of: control),
              let targetIndex = mainToolbarOrder.firstIndex(of: target) else {
            return
        }
        mainToolbarOrder.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        mainToolbarOrder.insert(control, at: max(0, min(insertionIndex, mainToolbarOrder.count)))
    }

    public mutating func resetMainToolbar() {
        mainToolbarOrder = Self.defaultMainToolbarOrder
        for control in UIControlID.controls(in: .mainToolbar) {
            hiddenControls.remove(control)
        }
    }

    private static func normalizedToolbarOrder(_ order: [UIControlID]) -> [UIControlID] {
        var seen = Set<UIControlID>()
        var normalized = order.filter { control in
            control.zone == .mainToolbar && seen.insert(control).inserted
        }
        for control in defaultMainToolbarOrder where !seen.contains(control) {
            normalized.append(control)
        }
        return normalized
    }

    private enum CodingKeys: String, CodingKey {
        case hiddenControls
        case mainToolbarOrder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenControls = try container.decodeIfPresent(Set<UIControlID>.self, forKey: .hiddenControls) ?? []
        let storedOrder = try container.decodeIfPresent([UIControlID].self, forKey: .mainToolbarOrder)
            ?? Self.defaultMainToolbarOrder
        mainToolbarOrder = Self.normalizedToolbarOrder(storedOrder)
    }
}
