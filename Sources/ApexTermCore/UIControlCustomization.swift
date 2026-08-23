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

public enum UIControlRecommendation: String, Equatable, Sendable {
    case high
    case medium
    case low

    public var title: String {
        switch self {
        case .high: "Recommended"
        case .medium: "Useful"
        case .low: "Optional"
        }
    }

    public var systemImage: String {
        switch self {
        case .high: "star.fill"
        case .medium: "star.leadinghalf.filled"
        case .low: "star"
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

    public var shortDescription: String {
        switch self {
        case .newTab: "Create a new terminal tab."
        case .remoteHostLaunch: "Open a saved remote connection."
        case .tmuxManager: "Browse and attach to tmux sessions."
        case .tabBarPinWindow, .toolbarPinWindow: "Keep ApexTerm above other windows."
        case .compactMode: "Reduce interface chrome for more terminal space."
        case .tabCloseButtons: "Show the close button on the active terminal tab."
        case .tabSeparators: "Show visual separators between terminal tabs."
        case .toggleLeftSidebar: "Legacy control for opening the left sidebar."
        case .commandPalette: "Search and run ApexTerm actions from one place."
        case .findTerminal, .compactFind: "Search text in the active terminal."
        case .quickTerminal: "Open the lightweight Quick Terminal window."
        case .historySearch, .compactHistorySearch: "Search commands you ran previously."
        case .copyContextPack: "Copy useful terminal context for sharing or AI tools."
        case .openFailureInAgent: "Send the latest failed command context to Agent Chat."
        case .toggleCommandHistory: "Legacy shortcut for the command-history panel."
        case .splitVertical: "Legacy toolbar control for a left/right column split."
        case .splitHorizontal: "Legacy toolbar control for a top/bottom column split."
        case .closePane: "Close the currently selected terminal tab."
        case .maximizePane: "Maximize the active column or restore the layout."
        case .toggleRightSidebar: "Legacy control for the retired right sidebar."
        case .compactWorkspaces: "Open the workspace list in compact mode."
        case .compactOverflow: "Open less frequently used compact-mode actions."
        case .sidebarSettings: "Open ApexTerm Settings from the sidebar."
        case .sidebarNewWorkspace: "Create a new workspace."
        case .expandLeftSidebar: "Expand or collapse the workspace sidebar."
        case .remoteHostSettings: "Open remote-host connection settings."
        case .expandRightSidebar: "Legacy control for the retired right sidebar."
        case .rightRailHistory: "Legacy command-history shortcut from the right rail."
        case .rightRailAgents: "Legacy Agent Runs shortcut from the right rail."
        }
    }

    public var detailDescription: String {
        switch self {
        case .newTab: "Adds a local shell to the current workspace. Its context menu can also create other supported session types."
        case .remoteHostLaunch: "Shows configured SSH and remote-host destinations so you can open a remote terminal without typing the connection command manually."
        case .tmuxManager: "Opens the tmux session manager for discovering, attaching to, and managing persistent terminal sessions."
        case .tabBarPinWindow, .toolbarPinWindow: "Pins the main ApexTerm window above normal application windows until you turn the option off again."
        case .compactMode: "Switches the main window to a denser layout that gives more room to terminal content and reduces surrounding UI."
        case .tabCloseButtons: "Controls whether the selected terminal tab shows its close button. Inactive tabs stay visually quieter."
        case .tabSeparators: "Adds subtle dividers between terminal tabs when you want stronger visual boundaries in dense columns."
        case .toggleLeftSidebar: "Kept for settings migration. The current interface opens and closes the workspace sidebar from the sidebar itself."
        case .commandPalette: "Provides a keyboard-friendly searchable list of ApexTerm commands, useful when you know what you want to do but not where the control lives."
        case .findTerminal, .compactFind: "Searches the visible terminal buffer for text without leaving the current terminal workflow."
        case .quickTerminal: "Opens a separate lightweight terminal window for short commands without changing the main workspace layout."
        case .historySearch, .compactHistorySearch: "Searches recorded command history across the current ApexTerm data so you can reuse or inspect earlier commands."
        case .copyContextPack: "Copies a bounded context bundle from the selected terminal so it can be pasted into another tool or conversation with useful surrounding information."
        case .openFailureInAgent: "Prepares the most recent failed command and related context in Agent Chat so the failure can be investigated without manual copying."
        case .toggleCommandHistory: "Retained for older layouts. Command-history search now has its own action instead of a persistent history sidebar."
        case .splitVertical: "Retained for older layouts. New left or right columns are now created from each column's + context menu."
        case .splitHorizontal: "Retained for older layouts. New columns above or below are now created from each column's + context menu."
        case .closePane: "Closes the selected terminal tab. Because active tabs also expose an inline ×, this top-bar action is optional for many workflows."
        case .maximizePane: "Temporarily gives the selected terminal column the available content area, then restores the previous multi-column layout."
        case .toggleRightSidebar: "The persistent right sidebar was removed from the current interface. This identifier remains only for compatibility with older saved settings."
        case .compactWorkspaces: "Shows the workspace selector when the main workspace sidebar is hidden by a compact window layout."
        case .compactOverflow: "Collects secondary actions into one menu when compact mode does not have enough room to show every control individually."
        case .sidebarSettings: "Opens the Settings window directly from the workspace sidebar."
        case .sidebarNewWorkspace: "Creates another workspace and makes it available in the workspace sidebar."
        case .expandLeftSidebar: "Expands the compact workspace rail into the full sidebar, or collapses it back to save horizontal space."
        case .remoteHostSettings: "Opens the screen used to add, edit, hide, or remove remote-host connection profiles."
        case .expandRightSidebar: "Retained only for compatibility with the retired right-sidebar layout."
        case .rightRailHistory: "Retained only for compatibility with the retired right rail. Command-history search remains available elsewhere."
        case .rightRailAgents: "Retained only for compatibility with the retired right rail. Agent workflows remain available through current Agent Chat surfaces."
        }
    }

    public var isLegacy: Bool {
        switch self {
        case .toggleLeftSidebar, .toggleCommandHistory, .toolbarPinWindow,
             .splitVertical, .splitHorizontal, .toggleRightSidebar,
             .expandRightSidebar, .rightRailHistory, .rightRailAgents:
            true
        default:
            false
        }
    }

    public var placementTitle: String {
        if isLegacy { return "Legacy" }
        if isTopBarReorderable { return "Top Bar" }
        return zone.title
    }

    public var recommendation: UIControlRecommendation {
        if isLegacy { return .low }
        switch self {
        case .newTab, .commandPalette, .findTerminal, .historySearch, .maximizePane:
            return .high
        case .remoteHostLaunch, .tmuxManager, .compactMode, .quickTerminal,
             .openFailureInAgent, .compactWorkspaces, .compactFind,
             .compactHistorySearch, .compactOverflow, .sidebarSettings,
             .sidebarNewWorkspace, .expandLeftSidebar, .remoteHostSettings:
            return .medium
        case .tabBarPinWindow, .tabCloseButtons, .tabSeparators,
             .copyContextPack, .closePane:
            return .low
        case .toggleLeftSidebar, .toggleCommandHistory, .toolbarPinWindow,
             .splitVertical, .splitHorizontal, .toggleRightSidebar,
             .expandRightSidebar, .rightRailHistory, .rightRailAgents:
            return .low
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

    public var isTopBarReorderable: Bool {
        switch self {
        case .newTab, .remoteHostLaunch, .tmuxManager, .tabBarPinWindow, .compactMode:
            return true
        default:
            return zone == .mainToolbar && isMainToolbarSurfaceAvailable
        }
    }

    public static func controls(in zone: UIControlZone) -> [UIControlID] {
        allCases.filter { $0.zone == zone }
    }
}

public struct UIControlCustomization: Codable, Equatable, Sendable {
    public static let defaultTopBarOrder: [UIControlID] = [
        .newTab,
        .remoteHostLaunch,
        .tmuxManager,
        .tabBarPinWindow,
        .compactMode,
        .commandPalette,
        .findTerminal,
        .quickTerminal,
        .historySearch,
        .copyContextPack,
        .openFailureInAgent,
        .closePane,
        .maximizePane
    ]

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
    public var topBarOrder: [UIControlID]

    public init(
        hiddenControls: Set<UIControlID> = [],
        mainToolbarOrder: [UIControlID] = Self.defaultMainToolbarOrder,
        topBarOrder: [UIControlID]? = nil
    ) {
        self.hiddenControls = hiddenControls
        self.mainToolbarOrder = Self.normalizedToolbarOrder(mainToolbarOrder)
        self.topBarOrder = Self.normalizedTopBarOrder(
            topBarOrder ?? Self.migratedTopBarOrder(from: self.mainToolbarOrder)
        )
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

    public mutating func moveTopBarControl(
        _ control: UIControlID,
        relativeTo target: UIControlID,
        after: Bool
    ) {
        guard control != target,
              control.isTopBarReorderable,
              target.isTopBarReorderable,
              topBarOrder.contains(control),
              topBarOrder.contains(target) else {
            return
        }

        topBarOrder.removeAll { $0 == control }
        guard let targetIndex = topBarOrder.firstIndex(of: target) else { return }
        let insertionIndex = targetIndex + (after ? 1 : 0)
        topBarOrder.insert(control, at: max(0, min(insertionIndex, topBarOrder.count)))
    }

    public mutating func resetTopBar() {
        topBarOrder = Self.defaultTopBarOrder
        for control in Self.defaultTopBarOrder {
            hiddenControls.remove(control)
        }
    }

    public mutating func resetMainToolbar() {
        mainToolbarOrder = Self.defaultMainToolbarOrder
        for control in UIControlID.controls(in: .mainToolbar) {
            hiddenControls.remove(control)
        }
    }

    private static func migratedTopBarOrder(from mainToolbarOrder: [UIControlID]) -> [UIControlID] {
        let tabBarActions: [UIControlID] = [
            .newTab,
            .remoteHostLaunch,
            .tmuxManager,
            .tabBarPinWindow,
            .compactMode
        ]
        return tabBarActions + mainToolbarOrder.filter(\.isMainToolbarSurfaceAvailable)
    }

    private static func normalizedTopBarOrder(_ order: [UIControlID]) -> [UIControlID] {
        var seen = Set<UIControlID>()
        var normalized = order.filter { control in
            control.isTopBarReorderable && seen.insert(control).inserted
        }
        for control in defaultTopBarOrder where !seen.contains(control) {
            normalized.append(control)
        }
        return normalized
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
        case topBarOrder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenControls = try container.decodeIfPresent(Set<UIControlID>.self, forKey: .hiddenControls) ?? []
        let storedOrder = try container.decodeIfPresent([UIControlID].self, forKey: .mainToolbarOrder)
            ?? Self.defaultMainToolbarOrder
        mainToolbarOrder = Self.normalizedToolbarOrder(storedOrder)
        let storedTopBarOrder = try container.decodeIfPresent([UIControlID].self, forKey: .topBarOrder)
        topBarOrder = Self.normalizedTopBarOrder(
            storedTopBarOrder ?? Self.migratedTopBarOrder(from: mainToolbarOrder)
        )
    }
}
