import Foundation

public struct ApexActionDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var keywords: [String]
    public var systemImage: String

    public init(
        id: String,
        title: String,
        subtitle: String,
        keywords: [String],
        systemImage: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.systemImage = systemImage
    }
}

public struct ApexActionRegistry: Sendable {
    public let actions: [ApexActionDescriptor]

    public init(actions: [ApexActionDescriptor] = ApexActionRegistry.defaultActions) {
        var seen: Set<String> = []
        self.actions = actions.filter { descriptor in
            !descriptor.id.isEmpty && seen.insert(descriptor.id).inserted
        }
    }

    public func action(id: String) -> ApexActionDescriptor? {
        actions.first { $0.id == id }
    }

    public func search(_ query: String) -> [ApexActionDescriptor] {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return actions }

        return actions
            .compactMap { action -> (ApexActionDescriptor, Int)? in
                let title = normalize(action.title)
                let subtitle = normalize(action.subtitle)
                let keywords = action.keywords.map(normalize)
                var score = 0
                if title == normalized { score += 100 }
                if title.hasPrefix(normalized) { score += 60 }
                if title.contains(normalized) { score += 35 }
                if subtitle.contains(normalized) { score += 15 }
                if keywords.contains(where: { $0 == normalized }) { score += 30 }
                if keywords.contains(where: { $0.contains(normalized) }) { score += 12 }
                guard score > 0 else { return nil }
                return (action, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.title.localizedStandardCompare(rhs.0.title) == .orderedAscending
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static let defaultActions: [ApexActionDescriptor] = [
        ApexActionDescriptor(
            id: "search.universal",
            title: "Universal Search",
            subtitle: "Search workspaces, terminals, commands, and agents",
            keywords: ["search", "universal", "workspace", "command", "agent", "検索", "横断"],
            systemImage: "sparkle.magnifyingglass"
        ),
        ApexActionDescriptor(
            id: "command.palette",
            title: "Command Palette",
            subtitle: "Search and run every ApexTerm action",
            keywords: ["command", "palette", "action", "コマンド", "操作"],
            systemImage: "command"
        ),
        ApexActionDescriptor(
            id: "workspace.new",
            title: "New Workspace",
            subtitle: "Create a durable local workspace",
            keywords: ["workspace", "new", "project", "作業", "新規"],
            systemImage: "plus.square.on.square"
        ),
        ApexActionDescriptor(
            id: "pane.split.vertical",
            title: "Split Left / Right",
            subtitle: "Create a vertical split beside the selected pane",
            keywords: ["split", "vertical", "pane", "左右", "分割"],
            systemImage: "rectangle.split.2x1"
        ),
        ApexActionDescriptor(
            id: "pane.split.horizontal",
            title: "Split Top / Bottom",
            subtitle: "Create a horizontal split below the selected pane",
            keywords: ["split", "horizontal", "pane", "上下", "分割"],
            systemImage: "rectangle.split.1x2"
        ),
        ApexActionDescriptor(
            id: "terminal.find",
            title: "Find in Terminal",
            subtitle: "Search the selected terminal scrollback",
            keywords: ["find", "search", "scrollback", "検索"],
            systemImage: "magnifyingglass"
        ),
        ApexActionDescriptor(
            id: "terminal.quick",
            title: "Open Quick Terminal",
            subtitle: "Open a separate durable terminal window",
            keywords: ["quick", "terminal", "window", "クイック"],
            systemImage: "macwindow.on.rectangle"
        ),
        ApexActionDescriptor(
            id: "terminal.compact.toggle",
            title: "Toggle Compact Mode",
            subtitle: "Move the tab strip into the native titlebar",
            keywords: ["compact", "titlebar", "terminal", "コンパクト"],
            systemImage: "rectangle.compress.vertical"
        ),
        ApexActionDescriptor(
            id: "terminal.secureInput.toggle",
            title: "Toggle Secure Keyboard Entry",
            subtitle: "Protect sensitive keyboard input from global event observation",
            keywords: ["secure", "keyboard", "password", "secret", "安全", "入力"],
            systemImage: "keyboard.badge.ellipsis"
        ),
        ApexActionDescriptor(
            id: "history.timeline",
            title: "Command Timeline",
            subtitle: "Review commands and Agent events in one chronological view",
            keywords: ["timeline", "history", "command", "agent", "時系列", "履歴"],
            systemImage: "clock.arrow.2.circlepath"
        ),
        ApexActionDescriptor(
            id: "history.search",
            title: "Search Command History",
            subtitle: "Search input and output across terminal sessions",
            keywords: ["history", "command", "output", "recent", "履歴", "検索"],
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        ),
        ApexActionDescriptor(
            id: "pane.maximize",
            title: "Maximize or Restore Pane",
            subtitle: "Focus the selected pane without changing its split layout",
            keywords: ["maximize", "zoom", "focus", "pane", "最大化", "集中"],
            systemImage: "arrow.up.left.and.arrow.down.right"
        ),
        ApexActionDescriptor(
            id: "pane.next",
            title: "Focus Next Pane",
            subtitle: "Move focus to the next pane in layout order",
            keywords: ["next", "pane", "focus", "move", "次", "移動"],
            systemImage: "arrow.right.square"
        ),
        ApexActionDescriptor(
            id: "pane.previous",
            title: "Focus Previous Pane",
            subtitle: "Move focus to the previous pane in layout order",
            keywords: ["previous", "pane", "focus", "move", "前", "移動"],
            systemImage: "arrow.left.square"
        ),
        ApexActionDescriptor(
            id: "pane.select.1",
            title: "Focus Pane 1",
            subtitle: "Focus the first pane in the active tab",
            keywords: ["pane", "one", "1", "focus", "split", "ペイン", "分割"],
            systemImage: "1.square"
        ),
        ApexActionDescriptor(
            id: "pane.select.2",
            title: "Focus Pane 2",
            subtitle: "Focus the second pane in the active tab",
            keywords: ["pane", "two", "2", "focus", "split", "ペイン", "分割"],
            systemImage: "2.square"
        ),
        ApexActionDescriptor(
            id: "pane.select.3",
            title: "Focus Pane 3",
            subtitle: "Focus the third pane in the active tab",
            keywords: ["pane", "three", "3", "focus", "split", "ペイン", "分割"],
            systemImage: "3.square"
        ),
        ApexActionDescriptor(
            id: "pane.select.4",
            title: "Focus Pane 4",
            subtitle: "Focus the fourth pane in the active tab",
            keywords: ["pane", "four", "4", "focus", "split", "ペイン", "分割"],
            systemImage: "4.square"
        ),
        ApexActionDescriptor(
            id: "terminal.context.copy",
            title: "Copy Context Pack",
            subtitle: "Copy a bounded, secret-redacted command and output handoff",
            keywords: ["context", "copy", "handoff", "prompt", "共有", "引継ぎ"],
            systemImage: "doc.on.doc"
        ),
        ApexActionDescriptor(
            id: "terminal.failure.launchpad",
            title: "Open Last Failure in Agent Chat",
            subtitle: "Prepare a safe diagnostic draft without executing it",
            keywords: ["failure", "fix", "agent", "debug", "error", "修正", "失敗"],
            systemImage: "wrench.and.screwdriver"
        ),
        ApexActionDescriptor(
            id: "agent.toggleRail",
            title: "Toggle Agent Rail",
            subtitle: "Show or hide structured agent runs",
            keywords: ["agent", "rail", "gag", "gae", "codex", "エージェント"],
            systemImage: "sidebar.right"
        ),
        ApexActionDescriptor(
            id: "pane.close",
            title: "Close Selected Pane",
            subtitle: "Detach and close the selected pane",
            keywords: ["close", "pane", "detach", "閉じる"],
            systemImage: "xmark.rectangle"
        ),
        ApexActionDescriptor(
            id: "tab.next",
            title: "Next Tab",
            subtitle: "Select the next workspace or Agent Chat tab",
            keywords: ["tab", "next", "switch", "cycle", "次", "切替"],
            systemImage: "arrow.right.to.line"
        ),
        ApexActionDescriptor(
            id: "tab.previous",
            title: "Previous Tab",
            subtitle: "Select the previous workspace or Agent Chat tab",
            keywords: ["tab", "previous", "switch", "cycle", "前", "切替"],
            systemImage: "arrow.left.to.line"
        ),
        ApexActionDescriptor(
            id: "terminal.tab.next",
            title: "Next Terminal Tab",
            subtitle: "Select the next terminal tab from top to bottom, then left to right",
            keywords: ["terminal", "tab", "next", "cycle", "次", "下", "右"],
            systemImage: "arrow.down.right.square"
        ),
        ApexActionDescriptor(
            id: "terminal.tab.previous",
            title: "Previous Terminal Tab",
            subtitle: "Select the previous terminal tab in visual traversal order",
            keywords: ["terminal", "tab", "previous", "cycle", "前", "上", "左"],
            systemImage: "arrow.up.left.square"
        ),
        ApexActionDescriptor(
            id: "tab.moveLeft",
            title: "Move Current Tab Left",
            subtitle: "Move the selected workspace or Agent Chat tab one position left",
            keywords: ["tab", "move", "left", "reorder", "移動", "左", "並び替え"],
            systemImage: "arrow.left"
        ),
        ApexActionDescriptor(
            id: "tab.moveRight",
            title: "Move Current Tab Right",
            subtitle: "Move the selected workspace or Agent Chat tab one position right",
            keywords: ["tab", "move", "right", "reorder", "移動", "右", "並び替え"],
            systemImage: "arrow.right"
        ),
        ApexActionDescriptor(
            id: "tab.select.1",
            title: "Select Tab 1",
            subtitle: "Select the first main tab",
            keywords: ["tab", "one", "1", "first", "タブ"],
            systemImage: "1.square"
        ),
        ApexActionDescriptor(
            id: "tab.select.2",
            title: "Select Tab 2",
            subtitle: "Select the second main tab",
            keywords: ["tab", "two", "2", "second", "タブ"],
            systemImage: "2.square"
        ),
        ApexActionDescriptor(
            id: "tab.select.3",
            title: "Select Tab 3",
            subtitle: "Select the third main tab",
            keywords: ["tab", "three", "3", "third", "タブ"],
            systemImage: "3.square"
        ),
        ApexActionDescriptor(
            id: "tab.select.4",
            title: "Select Tab 4",
            subtitle: "Select the fourth main tab",
            keywords: ["tab", "four", "4", "fourth", "タブ"],
            systemImage: "4.square"
        ),
        ApexActionDescriptor(
            id: "tab.select.5",
            title: "Select Tab 5",
            subtitle: "Select the fifth main tab",
            keywords: ["tab", "five", "5", "fifth", "タブ"],
            systemImage: "5.square"
        ),
        ApexActionDescriptor(
            id: "tab.select.6",
            title: "Select Tab 6",
            subtitle: "Select the sixth main tab",
            keywords: ["tab", "six", "6", "sixth", "タブ"],
            systemImage: "6.square"
        ),
        ApexActionDescriptor(
            id: "tab.select.7",
            title: "Select Tab 7",
            subtitle: "Select the seventh main tab",
            keywords: ["tab", "seven", "7", "seventh", "タブ"],
            systemImage: "7.square"
        ),
        ApexActionDescriptor(
            id: "tab.select.8",
            title: "Select Tab 8",
            subtitle: "Select the eighth main tab",
            keywords: ["tab", "eight", "8", "eighth", "タブ"],
            systemImage: "8.square"
        ),
        ApexActionDescriptor(
            id: "tab.select.9",
            title: "Select Tab 9",
            subtitle: "Select the ninth main tab",
            keywords: ["tab", "nine", "9", "ninth", "タブ"],
            systemImage: "9.square"
        ),
        ApexActionDescriptor(
            id: "terminal.latestOutput.copy",
            title: "Copy Latest Output",
            subtitle: "Copy the latest terminal output or Agent response from the active tab",
            keywords: ["copy", "latest", "output", "agent", "clipboard", "最新", "出力", "最新出力", "コピー"],
            systemImage: "doc.on.clipboard"
        ),
        ApexActionDescriptor(
            id: "terminal.conversation.send",
            title: "Send in C Mode",
            subtitle: "Send the command from the conversation-mode composer",
            keywords: ["terminal", "conversation", "chat", "send", "command", "送信", "会話"],
            systemImage: "arrow.up.circle.fill"
        ),
        ApexActionDescriptor(
            id: "terminal.transcript.cycle",
            title: "Cycle Transcript Mode",
            subtitle: "Cycle command transcript through On, Off, Ex, and C",
            keywords: ["transcript", "history", "on", "off", "ex", "conversation", "chat", "履歴", "表示", "会話"],
            systemImage: "rectangle.3.group"
        ),
        ApexActionDescriptor(
            id: "history.toggle",
            title: "Toggle Command History",
            subtitle: "Show or hide the command history rail",
            keywords: ["history", "toggle", "command", "履歴", "表示"],
            systemImage: "clock"
        ),
        ApexActionDescriptor(
            id: "sidebar.toggleLeft",
            title: "Toggle Left Sidebar",
            subtitle: "Show or hide the workspace sidebar",
            keywords: ["sidebar", "left", "workspace", "左", "サイドバー"],
            systemImage: "sidebar.left"
        ),
        ApexActionDescriptor(
            id: "sidebar.toggleRight",
            title: "Toggle Right Sidebar",
            subtitle: "Show or hide the right sidebar",
            keywords: ["sidebar", "right", "history", "agent", "右", "サイドバー"],
            systemImage: "sidebar.right"
        ),
        ApexActionDescriptor(
            id: "agent.new.local",
            title: "New Agent Chat",
            subtitle: "Create a new local Agent Chat tab",
            keywords: ["agent", "chat", "new", "local", "新規", "エージェント"],
            systemImage: "bubble.left.and.bubble.right"
        )
    ]
}
