import ApexTermCore
import AppKit
import SwiftUI

struct QuickTerminalView: View {
    @StateObject private var model = QuickTerminalModel()
    @State private var window: NSWindow?
    @AppStorage(AppLanguage.defaultsKey) private var languageCode = AppLanguage.system.rawValue
    @State private var renameTabID: UUID?
    @State private var renameGroupID: UUID?
    @State private var renameDraft = ""
    @State private var tmuxTargetGroupID: UUID?
    @State private var tmuxDraft = ""
    @State private var isRenameTabPresented = false
    @State private var isRenameGroupPresented = false
    @State private var isTmuxPromptPresented = false
    @AppStorage("quickTerminalPinned") private var isPinned = false

    var body: some View {
        QuickTerminalLayoutView(
            node: model.layout,
            model: model,
            isPinned: $isPinned,
            onRenameTab: beginRenameTab,
            onRenameGroup: beginRenameGroup,
            onNamedTmux: beginNamedTmux
        )
        .frame(minWidth: 360, minHeight: 220)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, AppLanguage.resolve(languageCode).locale)
        .background(
            WindowAccessor { resolved in
                resolved?.identifier = ApexTermWindowRole.quickTerminal
                WindowPinController.apply(pinned: isPinned, to: resolved)
                guard let resolved, window !== resolved else { return }
                window = resolved
                Task { @MainActor in
                    activateQuickTerminalWindow(resolved)
                }
            }
            .frame(width: 0, height: 0)
        )
        .onChange(of: isPinned) { _, pinned in
            WindowPinController.apply(pinned: pinned, to: window)
        }
        .task {
            await runProbeIfRequested()
            await runActivationProbeIfRequested()
        }
        .alert("Rename Terminal Tab", isPresented: $isRenameTabPresented) {
            TextField("Tab name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renameTabID {
                    model.renameTab(id: renameTabID, to: renameDraft)
                }
            }
        }
        .alert("Rename Terminal Group", isPresented: $isRenameGroupPresented) {
            TextField("Group name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renameGroupID {
                    model.renameGroup(id: renameGroupID, to: renameDraft)
                }
            }
        }
        .alert("Open Named tmux Session", isPresented: $isTmuxPromptPresented) {
            TextField("Session name", text: $tmuxDraft)
            Button("Cancel", role: .cancel) {}
            Button("Open") {
                _ = model.addNamedTmuxTab(
                    name: tmuxDraft,
                    to: tmuxTargetGroupID
                )
            }
        } message: {
            Text("Creates or attaches to the named local tmux session in a new tab.")
        }
    }

    private func runProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_QUICK_TERMINAL_PROBE_FILE"] else { return }
        guard let firstGroupID = model.groups.first?.id else { return }

        let disposableTabID = model.addLocalTab(to: firstGroupID)
        model.closeTab(id: disposableTabID)
        let closeTabPassed = model.tab(id: disposableTabID) == nil

        let logsTabID = model.addLocalTab(to: firstGroupID)
        model.renameTab(id: logsTabID, to: "logs")
        guard let namedTmuxID = model.addNamedTmuxTab(name: "probe-session", to: firstGroupID) else {
            return
        }
        model.reorderTab(id: namedTmuxID, relativeTo: logsTabID, after: false)
        let reorderPassed = model.group(id: firstGroupID)?.tabs.map(\.id).contains(namedTmuxID) == true
        model.moveTab(id: namedTmuxID, to: firstGroupID, placement: .right)
        let newGroupID = model.selectedGroupID
        if let newGroupID {
            model.moveTab(id: logsTabID, to: newGroupID, placement: .center)
            model.select(tabID: namedTmuxID, in: newGroupID)
        }
        let centerDropPassed = newGroupID.flatMap { model.group(id: $0) }?.tabs.contains {
            $0.id == logsTabID
        } == true
        model.renameGroup(id: firstGroupID, to: "Main Group")
        try? await Task.sleep(for: .milliseconds(900))

        let reloaded = QuickTerminalModel()
        let tabCount = reloaded.groups.reduce(0) { $0 + $1.tabs.count }
        let namedTmuxExists = reloaded.groups
            .flatMap(\.tabs)
            .contains { tab in
                if case .localTmux(session: "probe-session") = tab.kind { return true }
                return false
            }
        let splitExists: Bool
        if case .split = reloaded.layout {
            splitExists = true
        } else {
            splitExists = false
        }
        let documentExists = FileManager.default.fileExists(
            atPath: ApexTermPaths.supportDirectory()
                .appendingPathComponent("quick-terminal.json")
                .path
        )
        let payload = "groups=\(reloaded.groups.count)\n"
            + "tabs=\(tabCount)\n"
            + "split=\(splitExists ? 1 : 0)\n"
            + "named_tmux=\(namedTmuxExists ? 1 : 0)\n"
            + "tab_reorder=\(reorderPassed ? 1 : 0)\n"
            + "center_drop=\(centerDropPassed ? 1 : 0)\n"
            + "close_tab=\(closeTabPassed ? 1 : 0)\n"
            + "persisted=\(documentExists ? 1 : 0)\n"
        try? Data(payload.utf8).write(
            to: URL(fileURLWithPath: outputPath),
            options: [.atomic]
        )
    }

    @MainActor
    private func runActivationProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_QUICK_ACTIVATION_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        for _ in 0..<40 where window == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let window else { return }

        let originalPinned = isPinned
        isPinned = true
        WindowPinController.apply(pinned: true, to: window)
        activateQuickTerminalWindow(window)
        for _ in 0..<30 where !window.isKeyWindow {
            try? await Task.sleep(for: .milliseconds(50))
            activateQuickTerminalWindow(window)
        }

        let mainWindow = NSApp.windows.first {
            $0.identifier == ApexTermWindowRole.main
        }
        let result = [
            "quick_key=\(window.isKeyWindow ? 1 : 0)",
            "main_key=\(mainWindow?.isKeyWindow == true ? 1 : 0)",
            "quick_floating=\(window.level == .floating ? 1 : 0)",
            "window_roles_distinct=\(mainWindow?.identifier != window.identifier ? 1 : 0)"
        ].joined(separator: "\n") + "\n"

        isPinned = originalPinned
        WindowPinController.apply(pinned: originalPinned, to: window)
        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: outputPath),
            options: [.atomic]
        )
    }

    @MainActor
    private func activateQuickTerminalWindow(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private func beginRenameTab(_ tab: QuickTerminalTab) {
        renameTabID = tab.id
        renameDraft = tab.title
        isRenameTabPresented = true
    }

    private func beginRenameGroup(_ group: QuickTerminalGroup) {
        renameGroupID = group.id
        renameDraft = group.name
        isRenameGroupPresented = true
    }

    private func beginNamedTmux(_ groupID: UUID) {
        tmuxTargetGroupID = groupID
        tmuxDraft = ""
        isTmuxPromptPresented = true
    }
}

private struct QuickTerminalLayoutView: View {
    let node: QuickTerminalLayoutNode
    @ObservedObject var model: QuickTerminalModel
    @Binding var isPinned: Bool
    let onRenameTab: (QuickTerminalTab) -> Void
    let onRenameGroup: (QuickTerminalGroup) -> Void
    let onNamedTmux: (UUID) -> Void

    @ViewBuilder
    var body: some View {
        switch node {
        case let .group(id):
            if let group = model.group(id: id) {
                QuickTerminalGroupView(
                    group: group,
                    model: model,
                    isPinned: $isPinned,
                    onRenameTab: onRenameTab,
                    onRenameGroup: onRenameGroup,
                    onNamedTmux: onNamedTmux
                )
            }
        case let .split(axis, _, first, second):
            if axis == .vertical {
                HSplitView {
                    child(first)
                    child(second)
                }
            } else {
                VSplitView {
                    child(first)
                    child(second)
                }
            }
        }
    }

    private func child(_ node: QuickTerminalLayoutNode) -> some View {
        QuickTerminalLayoutView(
            node: node,
            model: model,
            isPinned: $isPinned,
            onRenameTab: onRenameTab,
            onRenameGroup: onRenameGroup,
            onNamedTmux: onNamedTmux
        )
    }
}

private struct QuickTerminalGroupView: View {
    let group: QuickTerminalGroup
    @ObservedObject var model: QuickTerminalModel
    @Binding var isPinned: Bool
    let onRenameTab: (QuickTerminalTab) -> Void
    let onRenameGroup: (QuickTerminalGroup) -> Void
    let onNamedTmux: (UUID) -> Void

    @State private var state: SessionState = .created
    @State private var commandStatus = "Starting"
    @State private var isGroupDropTargeted = false
    @State private var tabWidths: [UUID: CGFloat] = [:]
    @AppStorage("apexterm.terminal.smartPasteProtectionEnabled") private var smartPasteProtectionEnabled = true
    @AppStorage("apexterm.terminal.multilinePasteConfirmationEnabled") private var multilinePasteConfirmationEnabled = false
    @AppStorage("apexterm.terminal.autoCopyCommandOutputEnabled") private var autoCopyCommandOutputEnabled = false
    @AppStorage("apexterm.font.terminal") private var terminalFontSize = 13.0

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                tabBar
                Divider()
                terminalContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .dropDestination(for: TerminalDragPayload.self) { values, location in
                guard let payload = values.first,
                      payload.kind == .quickTerminalTab else { return false }
                let region = TerminalDropRegion.resolve(
                    location: location,
                    size: proxy.size
                )
                model.moveTab(
                    id: payload.id,
                    to: group.id,
                    placement: region.quickTerminalPlacement
                )
                return true
            } isTargeted: { targeted in
                isGroupDropTargeted = targeted
            }
            .overlay {
                if isGroupDropTargeted {
                    QuickTerminalDropGuide()
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 1)
                    .stroke(
                        model.selectedGroupID == group.id
                            ? Color.accentColor.opacity(0.55)
                            : Color.clear,
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(group.tabs) { tab in
                        tabButton(tab)
                    }
                }
            }

            Divider().frame(height: 20)

            Menu {
                Button("New Local Shell") {
                    model.addLocalTab(to: group.id)
                }
                Button("Open Named tmux Session…") {
                    onNamedTmux(group.id)
                }
                Divider()
                Button("Rename Group…") {
                    onRenameGroup(group)
                }
                Button(isPinned ? "Unpin Window" : "Pin Window Above Others") {
                    isPinned.toggle()
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 32, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("New terminal tab")

            Menu {
                Button("Rename Group…") {
                    onRenameGroup(group)
                }
                Button("New Local Shell") {
                    model.addLocalTab(to: group.id)
                }
                Button("Open Named tmux Session…") {
                    onNamedTmux(group.id)
                }
                Divider()
                Button(isPinned ? "Unpin Window" : "Pin Window Above Others") {
                    isPinned.toggle()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .frame(height: 31)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func tabButton(_ tab: QuickTerminalTab) -> some View {
        HStack(spacing: 0) {
            Button {
                model.select(tabID: tab.id, in: group.id)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "terminal")
                        .font(.caption)
                    Text(tab.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.leading, 9)
                .padding(.trailing, 5)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .frame(width: 22, height: 30)
            }
            .buttonStyle(.plain)
        }
        .background(
            group.selectedTabID == tab.id
                ? Color.accentColor.opacity(0.14)
                : Color.clear
        )
        .contextMenu {
            Button("Rename…") { onRenameTab(tab) }
            Button("Close") { model.closeTab(id: tab.id) }
            Divider()
            Button("New Local Shell") { model.addLocalTab(to: group.id) }
            Button("Open Named tmux Session…") { onNamedTmux(group.id) }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { tabWidths[tab.id] = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        tabWidths[tab.id] = width
                    }
            }
        }
        .draggable(TerminalDragPayload(kind: .quickTerminalTab, id: tab.id))
        .dropDestination(for: TerminalDragPayload.self) { values, location in
            guard let payload = values.first,
                  payload.kind == .quickTerminalTab,
                  payload.id != tab.id else { return false }
            let width = tabWidths[tab.id] ?? 0
            model.reorderTab(
                id: payload.id,
                relativeTo: tab.id,
                after: width > 0 && location.x >= width / 2
            )
            return true
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let tab = model.selectedTab(in: group.id) {
            TerminalPaneView(
                session: TerminalSessionSnapshot(
                    id: tab.sessionID,
                    kind: tab.kind,
                    workingDirectory: tab.workingDirectory,
                    appearance: .persisted,
                    remoteProfile: nil,
                    fontSize: terminalFontSize,
                    commandBlocksEnabled: false,
                    smartPasteProtectionEnabled: smartPasteProtectionEnabled,
                    multilinePasteConfirmationEnabled: multilinePasteConfirmationEnabled
                ),
                isActive: true,
                onTitleChange: { _ in },
                onDirectoryChange: { _ in },
                onStateChange: { state = $0 },
                onSemanticEvents: { events in
                    guard let event = events.last else { return }
                    commandStatus = switch event {
                    case .promptStarted: "Ready"
                    case .commandInputStarted: "Typing"
                    case .commandCaptured: "Running"
                    case .commandExecuted: "Running"
                    case let .commandFinished(code):
                        code.map { $0 == 0 ? "Done" : "Exit \($0)" } ?? "Done"
                    }
                },
                onPromptReadinessChange: { _ in },
                onCommandCaptured: { record in
                    guard autoCopyCommandOutputEnabled, !record.output.isEmpty else { return }
                    ClipboardWriter.copy(record.output)
                    AutoCopyToastPresenter.shared.showOutputCopied()
                },
                onActivate: {}
            )
            .id(tab.sessionID)
            .accessibilityLabel("Quick Terminal \(tab.title), \(commandStatus)")
        } else {
            ContentUnavailableView(
                "No Terminal Tab",
                systemImage: "terminal",
                description: Text("Use + to create a local shell or named tmux session.")
            )
        }
    }
}

private struct QuickTerminalDropGuide: View {
    var body: some View {
        GeometryReader { proxy in
            let sideWidth = max(70, proxy.size.width * 0.22)
            let sideHeight = max(60, proxy.size.height * 0.22)

            ZStack {
                guide("ADD TAB", emphasized: false)
                    .padding(.horizontal, sideWidth)
                    .padding(.vertical, sideHeight)

                HStack {
                    guide("LEFT", emphasized: true).frame(width: sideWidth)
                    Spacer()
                    guide("RIGHT", emphasized: true).frame(width: sideWidth)
                }

                VStack {
                    guide("TOP", emphasized: true).frame(height: sideHeight)
                    Spacer()
                    guide("BOTTOM", emphasized: true).frame(height: sideHeight)
                }
            }
            .padding(8)
            .background(.black.opacity(0.24))
        }
    }

    private func guide(_ label: String, emphasized: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(emphasized ? 0.20 : 0.12))
            .overlay {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        Color.accentColor.opacity(0.75),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5])
                    )
            }
    }
}

private extension TerminalDropRegion {
    var quickTerminalPlacement: QuickTerminalDropPlacement {
        switch self {
        case .center: .center
        case .left: .left
        case .right: .right
        case .top: .top
        case .bottom: .bottom
        }
    }
}
