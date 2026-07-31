import ApexTermCore
import AppKit
import SwiftUI

@MainActor
private final class TransientNoticePresentationProbe {
    static let shared = TransientNoticePresentationProbe()

    private(set) var message: String?

    private init() {}

    func record(_ message: String) {
        self.message = message
    }

    func clear() {
        message = nil
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isWorkspacePopoverPresented = false
    @State private var isAgentPopoverPresented = false
    @State private var mainWindow: NSWindow?
    @State private var isExternalFolderDropTargeted = false
    @State private var renameWorkspaceID: UUID?
    @State private var renameSessionID: UUID?
    @State private var renameDraft = ""
    @State private var tmuxDraft = ""
    @State private var isRenameMainWindowPresented = false
    @State private var isRenameWorkspacePresented = false
    @State private var isRenameSessionPresented = false
    @State private var isNamedTmuxPresented = false
    @State private var isMainWindowExpanded = false
    @State private var expandedWorkspaceIDs: Set<UUID> = []
    @State private var expandedRemoteHostAliases: Set<String> = []

    var body: some View {
        GeometryReader { proxy in
            let layout = ResponsiveLayoutPolicy(
                width: proxy.size.width,
                agentRailPreferred: model.isAgentRailVisible
            )

            HStack(spacing: 0) {
                if !model.isCompactMode && layout.showsWorkspaceSidebar {
                    workspaceSidebar
                        .frame(width: model.isWorkspaceSidebarCollapsed ? 40 : 210)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }

                terminalColumn(layout: layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                if !model.isCompactMode && layout.showsAgentRail {
                    Divider()
                    rightSidebar
                        .frame(width: model.isRightSidebarCollapsed ? 40 : 280)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.16), value: layout)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            model.openProjects(from: urls)
        } isTargeted: { targeted in
            isExternalFolderDropTargeted = targeted
        }
        .overlay {
            if isExternalFolderDropTargeted {
                ZStack {
                    Color.accentColor.opacity(0.10)
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 36, weight: .semibold))
                        Text("Drop Folder to Open as Project")
                            .font(.headline)
                        Text("The terminal starts with cd set to this folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                        .padding(6)
                )
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = model.transientNotice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3)
                    .padding(.bottom, model.isCompactMode ? 12 : 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("transient-notice")
                    .onAppear {
                        TransientNoticePresentationProbe.shared.record(notice)
                    }
                    .onDisappear {
                        TransientNoticePresentationProbe.shared.clear()
                    }
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: model.transientNotice)
        .background(
            WindowAccessor { window in
                window?.identifier = ApexTermWindowRole.main
                window?.contentMinSize = ApexTermWindowSizing.mainMinimumContentSize
                mainWindow = window
                WindowPinController.apply(pinned: model.isMainWindowPinned, to: window)
                syncCompactTitlebar(on: window)
            }
            .frame(width: 0, height: 0)
        )
        .onChange(of: model.isMainWindowPinned) { _, pinned in
            WindowPinController.apply(pinned: pinned, to: mainWindow)
        }
        .onChange(of: model.isCompactMode) { _, _ in
            syncCompactTitlebar(on: mainWindow)
        }
        .sheet(isPresented: $model.isCommandPalettePresented) {
            CommandPaletteView(model: model)
        }
        .sheet(isPresented: $model.isUniversalSearchPresented) {
            UniversalSearchView(model: model)
        }
        .sheet(isPresented: $model.isCommandTimelinePresented) {
            CommandTimelineView(model: model)
        }
        .sheet(isPresented: $model.isCommandHistorySearchPresented) {
            CommandHistorySearchView(model: model)
        }
        .sheet(isPresented: $model.isSettingsPresented) {
            AppSettingsView(model: model)
        }
        .sheet(isPresented: $model.isRemoteHostSettingsPresented) {
            RemoteHostSettingsView(model: model)
                .environment(\.locale, model.appLanguage.locale)
        }
        .sheet(isPresented: $model.isTmuxSessionManagerPresented) {
            TmuxSessionManagerView(model: model)
                .environment(\.locale, model.appLanguage.locale)
        }
        .alert("Rename Terminal Window", isPresented: $isRenameMainWindowPresented) {
            TextField("Window name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                model.renameMainWindow(to: renameDraft)
            }
        }
        .alert("Rename Workspace", isPresented: $isRenameWorkspacePresented) {
            TextField("Workspace name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renameWorkspaceID {
                    model.renameWorkspace(id: renameWorkspaceID, to: renameDraft)
                }
            }
        }
        .alert("Rename Terminal", isPresented: $isRenameSessionPresented) {
            TextField("Terminal name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renameSessionID {
                    model.renameSession(id: renameSessionID, to: renameDraft)
                }
            }
        }
        .alert("Open Named tmux Session", isPresented: $isNamedTmuxPresented) {
            TextField("Session name", text: $tmuxDraft)
            Button("Cancel", role: .cancel) {}
            Button("Open") {
                model.createNamedLocalTmuxWorkspace(name: tmuxDraft)
            }
        } message: {
            Text("Creates or attaches to a local tmux session as a new tab.")
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .apexTermQuickTerminalRequested
            )
        ) { _ in
            openWindow(id: "quick-terminal")
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .apexTermExternalFoldersRequested)
        ) { _ in
            _ = model.openProjects(from: ApexTermExternalOpenCoordinator.shared.drain())
        }
        .environment(\.locale, model.appLanguage.locale)
        .task {
            let pendingFolders = ApexTermExternalOpenCoordinator.shared.drain()
            if !pendingFolders.isEmpty {
                _ = model.openProjects(from: pendingFolders)
            }
            if ProcessInfo.processInfo.environment["APEXTERM_UI_DELETE_PROBE_ALIAS"] != nil {
                model.isRemoteHostSettingsPresented = true
            }
            if ProcessInfo.processInfo.environment["APEXTERM_QUICK_TERMINAL_PROBE_FILE"] != nil
                || ProcessInfo.processInfo.environment["APEXTERM_QUICK_ACTIVATION_PROBE_FILE"] != nil {
                openWindow(id: "quick-terminal")
            }
            await runUniversalSearchProbeIfRequested()
            await runCommandTimelineProbeIfRequested()
            await runFeatureProbeIfRequested()
            await runTmuxManagerProbeIfRequested()
            await runCopyProbeIfRequested()
            await runShortcutActionsProbeIfRequested()
            await runCommandBlockProbeIfRequested()
            await runLanguageProbeIfRequested()
            await runReadmeScreenshotSceneIfRequested()
            await runComposerAlignmentProbeIfRequested()
            await runTabLifecycleProbeIfRequested()
            await runCompactTitlebarProbeIfRequested()
            await runAgentChatE2EIfRequested()
        }
    }

    @MainActor
    private func syncCompactTitlebar(on window: NSWindow?) {
        CompactTitlebarToolbarController.shared.update(
            window: window,
            enabled: model.isCompactMode,
            contentRevision: compactTitlebarContentRevision,
            content: AnyView(workspaceTabBar)
        )
    }

    private var compactTitlebarContentRevision: String {
        let tabs = model.orderedMainTabs.map { item in
            switch item.kind {
            case .workspace:
                return "w:\(item.uuid.uuidString)"
            case .agentChat:
                return "a:\(item.uuid.uuidString)"
            }
        }.joined(separator: ",")
        return [
            tabs,
            "workspace:\(model.selectedWorkspaceID?.uuidString ?? "none")",
            "agent:\(model.selectedAgentChatID?.uuidString ?? "none")",
            "pinned:\(model.isMainWindowPinned ? 1 : 0)"
        ].joined(separator: "|")
    }

    private func terminalColumn(layout: ResponsiveLayoutPolicy) -> some View {
        VStack(spacing: 0) {
            if !model.isCompactMode {
                workspaceTabBar
                Divider()
            }
            if !model.isCompactMode && model.selectedAgentChatID == nil {
                terminalToolbar(layout: layout)
                Divider()
            }
            terminalCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !model.isCompactMode && model.selectedAgentChatID == nil {
                Divider()
                statusBar(compact: layout.mode == .compact)
            }
        }
    }

    private var workspaceTabBar: some View {
        WorkspaceTabBarView(
            model: model,
            onOpenNamedTmux: {
                tmuxDraft = ""
                isNamedTmuxPresented = true
            },
            onRenameWorkspace: beginRenameWorkspace
        )
    }

    @ViewBuilder
    private var workspaceSidebar: some View {
        if model.isWorkspaceSidebarCollapsed {
            compactWorkspaceRail
        } else {
            expandedWorkspaceSidebar
        }
    }

    private var expandedWorkspaceSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("APEXTERM")
                    .font(.system(size: max(9, model.sidebarFontSize - 1), weight: .bold))
                Spacer()
                if model.isUIControlVisible(.sidebarSettings) {
                    Button {
                        model.isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }

                if model.isUIControlVisible(.sidebarNewWorkspace) {
                    Button {
                        model.createWorkspace()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("New Workspace")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)

            Divider()

            List {
                Section("Terminal Windows") {
                    DisclosureGroup(isExpanded: $isMainWindowExpanded) {
                        ForEach(model.workspaces) { workspace in
                            workspaceSidebarItem(workspace)
                                .padding(.leading, 8)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "macwindow")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.mainWindowName)
                                    .lineLimit(1)
                                Text("\(model.workspaces.count) tab\(model.workspaces.count == 1 ? "" : "s")")
                                    .font(.system(size: max(8, model.sidebarFontSize - 2)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        mainWindowContextMenu()
                    }
                }

                if !model.sshProfiles.isEmpty {
                    Section("Remote Hosts") {
                        ForEach(model.sshProfiles) { profile in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedRemoteHostAliases.contains(profile.alias) },
                                    set: { expanded in
                                        if expanded {
                                            expandedRemoteHostAliases.insert(profile.alias)
                                        } else {
                                            expandedRemoteHostAliases.remove(profile.alias)
                                        }
                                    }
                                )
                            ) {
                                Button {
                                    model.createRemoteWorkspace(profile: profile)
                                    isWorkspacePopoverPresented = false
                                } label: {
                                    Label("Open SSH tab", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 10)

                                Button {
                                    model.createRemoteWorkspace(
                                        profile: profile,
                                        tmuxSession: "apexterm"
                                    )
                                    isWorkspacePopoverPresented = false
                                } label: {
                                    Label("Open with tmux", systemImage: "rectangle.stack")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 10)

                                Button {
                                    model.isTmuxSessionManagerPresented = true
                                } label: {
                                    Label("Manage tmux sessions", systemImage: "rectangle.stack")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 10)

                                Button {
                                    model.isRemoteHostSettingsPresented = true
                                } label: {
                                    Label("Edit connection", systemImage: "slider.horizontal.3")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 10)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "network")
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(profile.displayTitle)
                                            .lineLimit(1)
                                        Text(profile.destination)
                                            .font(.system(size: max(8, model.sidebarFontSize - 2)))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .contextMenu {
                                Button("Open SSH tab") {
                                    model.createRemoteWorkspace(profile: profile)
                                }
                                Button("Open with tmux") {
                                    model.createRemoteWorkspace(
                                        profile: profile,
                                        tmuxSession: "apexterm"
                                    )
                                }
                                Button("Manage tmux Sessions…") {
                                    model.isTmuxSessionManagerPresented = true
                                }
                                Divider()
                                Button("Remote Host Settings…") {
                                    model.isRemoteHostSettingsPresented = true
                                }
                                Button("Hide from ApexTerm", role: .destructive) {
                                    model.hideRemoteHost(alias: profile.alias)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 24)
            .font(.system(size: model.sidebarFontSize))
            .disclosureGroupStyle(ApexSidebarDisclosureGroupStyle(fontSize: model.sidebarFontSize))
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func workspaceSidebarItem(_ workspace: Workspace) -> some View {
        let sessionIDs = SplitTreeOperations.sessionIDs(in: workspace.layout)
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedWorkspaceIDs.contains(workspace.id) },
                set: { expanded in
                    if expanded {
                        expandedWorkspaceIDs.insert(workspace.id)
                    } else {
                        expandedWorkspaceIDs.remove(workspace.id)
                    }
                }
            )
        ) {
            ForEach(sessionIDs, id: \.self) { sessionID in
                if let session = model.session(id: sessionID) {
                    Button {
                        model.selectWorkspace(workspace)
                        model.selectSession(sessionID)
                    } label: {
                        Label(session.title, systemImage: "terminal")
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            beginRenameSession(session)
                        }
                    )
                    .contextMenu {
                        sessionContextMenu(session)
                    }
                }
            }
        } label: {
            workspaceSidebarLabel(workspace)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        model.selectWorkspace(workspace)
                        isWorkspacePopoverPresented = false
                    }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        beginRenameWorkspace(workspace)
                    }
                )
        }
        .contextMenu {
            workspaceContextMenu(workspace)
        }
        .listRowBackground(
            workspace.id == model.selectedWorkspaceID
                ? Color.accentColor.opacity(0.14)
                : Color.clear
        )
    }

    private func workspaceSidebarLabel(_ workspace: Workspace) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .lineLimit(1)
                Text(workspaceDetail(workspace))
                    .font(.system(size: max(8, model.sidebarFontSize - 2)))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var compactWorkspaceRail: some View {
        VStack(spacing: 6) {
            if model.isUIControlVisible(.expandLeftSidebar) {
                Button {
                    model.isWorkspaceSidebarCollapsed = false
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("Expand left sidebar")
                .padding(.top, 8)
            }

            Divider()

            ForEach(model.workspaces) { workspace in
                Button {
                    model.selectWorkspace(workspace)
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(
                            workspace.id == model.selectedWorkspaceID
                                ? Color.accentColor
                                : Color.secondary
                        )
                }
                .buttonStyle(.borderless)
                .help(workspace.name)
            }

            Spacer()

            if model.isUIControlVisible(.remoteHostSettings) {
                Button {
                    model.isRemoteHostSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Remote Host Settings")
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func terminalToolbar(layout: ResponsiveLayoutPolicy) -> some View {
        if layout.usesCompactToolbar {
            compactToolbar(layout: layout)
        } else {
            fullToolbar(layout: layout)
        }
    }

    private func compactToolbar(layout: ResponsiveLayoutPolicy) -> some View {
        HStack(spacing: 8) {
            if !layout.showsWorkspaceSidebar && model.isUIControlVisible(.compactWorkspaces) {
                Button {
                    isWorkspacePopoverPresented.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("Workspaces")
                .popover(isPresented: $isWorkspacePopoverPresented, arrowEdge: .bottom) {
                    workspaceSidebar
                        .frame(width: 280, height: 480)
                }
            }

            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(model.selectedSession?.title ?? model.terminalTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if model.isUIControlVisible(.compactFind) {
                Button {
                    model.requestFind()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Find in Terminal")
            }

            if model.isUIControlVisible(.compactHistorySearch) {
                Button {
                    model.isCommandHistorySearchPresented = true
                } label: {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
                .buttonStyle(.borderless)
                .help("Search Command History")
            }

            if model.isUIControlVisible(.compactOverflow) {
                Menu {
                Button("Command Palette") {
                    model.isCommandPalettePresented = true
                }
                Button("Quick Terminal") {
                    openWindow(id: "quick-terminal")
                }
                Button("Search Command History") {
                    model.isCommandHistorySearchPresented = true
                }
                Button("Copy Context Pack") {
                    model.copySelectedContextPack()
                }
                Button("Open Last Failure in Agent Chat") {
                    model.prepareLastFailureInAgentChat()
                }

                Divider()

                Button("Split Left / Right") {
                    model.splitSelected(axis: .vertical)
                }
                Button("Split Top / Bottom") {
                    model.splitSelected(axis: .horizontal)
                }
                Button("Close Selected Pane") {
                    model.closeSelectedSession()
                }
                Button(model.maximizedSessionID == nil ? "Maximize Selected Pane" : "Restore Pane Layout") {
                    model.toggleMaximizeSelectedPane()
                }
                Button("Next Pane") { model.selectAdjacentPane(offset: 1) }
                Button("Previous Pane") { model.selectAdjacentPane(offset: -1) }

                Divider()

                Button("Remote Host Settings") {
                    model.isRemoteHostSettingsPresented = true
                }
                Button(model.isWorkspaceSidebarCollapsed ? "Expand Left Sidebar" : "Collapse Left Sidebar") {
                    model.isWorkspaceSidebarCollapsed.toggle()
                }
                Button(model.isRightSidebarCollapsed ? "Expand Right Sidebar" : "Collapse Right Sidebar") {
                    model.isRightSidebarCollapsed.toggle()
                }
                Button(model.isCommandHistoryVisible ? "Hide Command History" : "Show Command History") {
                    model.isCommandHistoryVisible.toggle()
                }
                Button(model.isMainWindowPinned ? "Unpin Window" : "Pin Window Above Others") {
                    model.isMainWindowPinned.toggle()
                }
                Button("Agent Runs") {
                    isAgentPopoverPresented.toggle()
                }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .popover(isPresented: $isAgentPopoverPresented, arrowEdge: .bottom) {
                    rightSidebar
                        .frame(width: 320, height: 520)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
    }

    private func fullToolbar(layout: ResponsiveLayoutPolicy) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(model.selectedSession?.title ?? model.terminalTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)

            ForEach(model.visibleMainToolbarControls) { control in
                mainToolbarControl(control, layout: layout)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    @ViewBuilder
    private func mainToolbarControl(_ control: UIControlID, layout: ResponsiveLayoutPolicy) -> some View {
        switch control {
        case .toggleLeftSidebar:
            Button {
                model.isWorkspaceSidebarCollapsed.toggle()
            } label: {
                Image(systemName: model.isWorkspaceSidebarCollapsed ? "sidebar.left" : "sidebar.leading")
            }
            .buttonStyle(.borderless)
            .help(model.isWorkspaceSidebarCollapsed ? "Expand left sidebar" : "Collapse left sidebar")
        case .commandPalette:
            toolbarButton("command", help: "Command Palette") {
                model.isCommandPalettePresented = true
            }
        case .findTerminal:
            toolbarButton("magnifyingglass", help: "Find in Terminal") {
                model.requestFind()
            }
        case .quickTerminal:
            toolbarButton("macwindow.on.rectangle", help: "Quick Terminal") {
                openWindow(id: "quick-terminal")
            }
        case .historySearch:
            toolbarButton("clock.arrow.trianglehead.counterclockwise.rotate.90", help: "Search Command History") {
                model.isCommandHistorySearchPresented = true
            }
        case .copyContextPack:
            toolbarButton("doc.on.doc", help: "Copy a bounded, secret-redacted Context Pack") {
                model.copySelectedContextPack()
            }
        case .openFailureInAgent:
            toolbarButton("wrench.and.screwdriver", help: "Open the last failed command as an Agent Chat draft") {
                model.prepareLastFailureInAgentChat()
            }
        case .toggleCommandHistory:
            toolbarButton(model.isCommandHistoryVisible ? "clock.fill" : "clock", help: "Toggle command history") {
                model.isCommandHistoryVisible.toggle()
            }
        case .toolbarPinWindow:
            toolbarButton(model.isMainWindowPinned ? "pin.fill" : "pin", help: model.isMainWindowPinned ? "Unpin window" : "Keep window above others") {
                model.isMainWindowPinned.toggle()
            }
        case .splitVertical:
            toolbarButton("rectangle.split.2x1", help: "Split Left / Right") {
                model.splitSelected(axis: .vertical)
            }
        case .splitHorizontal:
            toolbarButton("rectangle.split.1x2", help: "Split Top / Bottom") {
                model.splitSelected(axis: .horizontal)
            }
        case .closePane:
            toolbarButton("xmark", help: "Close Selected Pane") {
                model.closeSelectedSession()
            }
        case .maximizePane:
            toolbarButton(
                model.maximizedSessionID == nil
                    ? "arrow.up.left.and.arrow.down.right"
                    : "arrow.down.right.and.arrow.up.left",
                help: model.maximizedSessionID == nil ? "Maximize Selected Pane" : "Restore Pane Layout"
            ) {
                model.toggleMaximizeSelectedPane()
            }
        case .toggleRightSidebar:
            Button {
                if layout.mode == .wide {
                    model.isRightSidebarCollapsed.toggle()
                } else {
                    isAgentPopoverPresented.toggle()
                }
            } label: {
                Image(systemName: model.isRightSidebarCollapsed ? "sidebar.right" : "sidebar.trailing")
            }
            .buttonStyle(.borderless)
            .help(layout.mode == .wide ? "Collapse or expand right sidebar" : "Show command history and agents")
            .popover(isPresented: $isAgentPopoverPresented, arrowEdge: .bottom) {
                rightSidebar
                    .frame(width: 320, height: 520)
            }
        default:
            EmptyView()
        }
    }

    private func toolbarButton(
        _ systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    @ViewBuilder
    private var terminalCanvas: some View {
        if let chatID = model.selectedAgentChatID {
            AgentChatView(model: model, tabID: chatID)
                .id(chatID)
        } else if let workspace = model.selectedWorkspace {
            SplitTreeView(
                workspaceID: workspace.id,
                node: visibleLayout(for: workspace),
                model: model
            )
        } else {
            ContentUnavailableView(
                "No Workspace",
                systemImage: "terminal",
                description: Text("Create or select a workspace.")
            )
        }
    }

    private func visibleLayout(for workspace: Workspace) -> SplitNode {
        guard let maximizedSessionID = model.maximizedSessionID,
              SplitTreeOperations.contains(
                sessionID: maximizedSessionID,
                in: workspace.layout
              ) else {
            return workspace.layout
        }
        return .pane(sessionID: maximizedSessionID)
    }

    private func statusBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            if !compact {
                Label("Metal", systemImage: "gauge.with.dots.needle.67percent")
                Label(model.automationStatus(), systemImage: "point.3.connected.trianglepath.dotted")
            }

            Label(sessionKindStatus, systemImage: "cpu")
                .lineLimit(1)

            if model.secureKeyboardEntryEnabled {
                Label("Secure Input", systemImage: "lock.fill")
                    .foregroundStyle(.orange)
            }

            if let message = model.persistenceMessage {
                Text(message)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(model.selectedSession?.workingDirectory ?? remoteStatus)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: compact ? 220 : .infinity, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, compact ? 8 : 12)
        .frame(height: 28)
    }

    @ViewBuilder
    private var rightSidebar: some View {
        if model.isRightSidebarCollapsed {
            VStack(spacing: 10) {
                if model.isUIControlVisible(.expandRightSidebar) {
                    Button {
                        model.isRightSidebarCollapsed = false
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Expand right sidebar")
                    .padding(.top, 10)
                }

                Divider()

                if model.isUIControlVisible(.rightRailHistory) {
                    Button {
                        model.isCommandHistoryVisible = true
                        model.isRightSidebarCollapsed = false
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "clock")
                            if !model.commandHistory.isEmpty {
                                Text("\(min(9, model.commandHistory.count))")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(2)
                                    .background(Color.accentColor, in: Circle())
                                    .foregroundStyle(.white)
                                    .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Command History")
                }

                if model.isUIControlVisible(.rightRailAgents) {
                    Button {
                        model.isRightSidebarCollapsed = false
                    } label: {
                        Image(systemName: "bolt.horizontal.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Agent Runs")
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        } else {
            VSplitView {
                if model.isCommandHistoryVisible {
                    CommandHistoryPanel(model: model)
                        .frame(minHeight: 150)
                }
                agentRail
                    .frame(minHeight: 150)
            }
            .environment(\.defaultMinListRowHeight, 24)
            .font(.system(size: model.sidebarFontSize))
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var agentRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AGENT RUNS")
                    .font(.system(size: max(9, model.sidebarFontSize - 2), weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.agentRuns.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)

            Divider()

            if model.agentRuns.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No Active Agents")
                        .font(.headline)
                    Text("外部Agent ProviderやCodexの実行状態がここに表示されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.agentRuns) { run in
                    agentRunRow(run)
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func agentRunRow(_ run: AgentRun) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(agentStateColor(run.state))
                        .frame(width: 7, height: 7)
                    Text(run.label)
                        .font(.system(size: model.sidebarFontSize, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(run.state.rawValue)
                        .font(.system(size: max(8, model.sidebarFontSize - 2)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let progress = run.progress {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .tint(.purple)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: max(8, model.sidebarFontSize - 2), weight: .semibold, design: .monospaced))
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                Text(run.lastEvent ?? run.provider)
                    .font(.system(size: max(9, model.sidebarFontSize - 1)))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        if let performance = run.requestedPerformance {
                            Label(performance.displayName, systemImage: "speedometer")
                        }
                        if let model = run.selectedModelLabel ?? run.selectedModel {
                            Label(model, systemImage: "brain.head.profile")
                                .lineLimit(1)
                        }
                        if let cost = run.apiCostEstimate {
                            Label(formatAgentCost(cost), systemImage: "yensign.circle")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if let performance = run.requestedPerformance {
                            Label("要求 \(performance.displayName)", systemImage: "speedometer")
                        }
                        if let model = run.selectedModelLabel ?? run.selectedModel {
                            Label("実 \(model)", systemImage: "brain.head.profile")
                                .lineLimit(1)
                        }
                        if let cost = run.apiCostEstimate {
                            Label(formatAgentCost(cost), systemImage: "yensign.circle")
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                HStack(spacing: 7) {
                    if let eta = run.estimatedCompletionAt,
                       ![AgentRunState.succeeded, .failed, .cancelled].contains(run.state) {
                        Label(
                            "約\(formatAgentDuration(eta.timeIntervalSince(context.date)))",
                            systemImage: "hourglass"
                        )
                    }
                    if let input = run.estimatedInputTokens {
                        let total = input + (run.estimatedOutputTokens ?? 0)
                        Label("~\(formatAgentTokens(total)) tok", systemImage: "number")
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                if let url = run.conversationURL {
                    Button {
                        ChatConversationOpener.open(url)
                    } label: {
                        Label("Open Chat", systemImage: "arrow.up.forward.app")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("既存のChatタブへ移動し、なければ開きます")
                }
            }
            .padding(.vertical, 5)
        }
    }

    private func agentStateColor(_ state: AgentRunState) -> Color {
        switch state {
        case .queued: .orange
        case .running: .purple
        case .waitingApproval: .yellow
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        case .disconnected: .orange
        }
    }

    private func formatAgentDuration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value < 60 { return "\(value)秒" }
        if value < 3600 { return "\(value / 60)分\(value % 60)秒" }
        return "\(value / 3600)時間\((value % 3600) / 60)分"
    }

    private func formatAgentTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return String(value)
    }

    private func formatAgentCost(_ estimate: GagAPICostEstimate) -> String {
        guard estimate.isRegistered, let minimum = estimate.jpy else { return "単価未登録" }
        let maximum = estimate.maxJpy ?? minimum
        if abs(maximum - minimum) < 0.005 {
            return String(format: "¥%.2f", minimum)
        }
        return String(format: "¥%.2f–%.2f", minimum, maximum)
    }

    @MainActor
    private func runCopyProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_UI_COPY_PROBE_FILE"],
              !outputPath.isEmpty,
              let record = model.commandHistory.first else {
            return
        }

        ClipboardWriter.copy(record.commandAndOutput)
        let allPassed = NSPasteboard.general.string(forType: .string) == record.commandAndOutput
        ClipboardWriter.copy(record.output)
        let outputPassed = NSPasteboard.general.string(forType: .string) == record.output
        ClipboardWriter.copy(record.command)
        let commandPassed = NSPasteboard.general.string(forType: .string) == record.command

        let result = [
            "copy_all=\(allPassed ? 1 : 0)",
            "copy_output=\(outputPassed ? 1 : 0)",
            "copy_command=\(commandPassed ? 1 : 0)"
        ].joined(separator: "\n") + "\n"
        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: outputPath),
            options: [.atomic]
        )
    }

    @MainActor
    private func runCommandBlockProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_COMMAND_BLOCK_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }
        let marker = environment["APEXTERM_SCROLL_PROBE_MARKER"]
            ?? "APT_SCROLL_PROBE_DONE"

        var targetRecord: CommandExecutionRecord?
        var actionButton: NSPopUpButton?
        var commandBlock: NSView?
        for _ in 0..<160 {
            if let record = model.commandHistory.first(where: { $0.output.contains(marker) }),
               let button = findView(
                    accessibilityIdentifier: "command-action-\(record.id.uuidString)"
               ) as? NSPopUpButton,
               let block = findView(
                    accessibilityIdentifier: "terminal-command-block-\(record.id.uuidString)"
               ) {
                targetRecord = record
                actionButton = button
                commandBlock = block
                break
            }
            try? await Task.sleep(for: .milliseconds(75))
        }

        guard let record = targetRecord,
              let button = actionButton,
              let commandBlock else {
            writeProbeResult(
                [
                    "button_found=0",
                    "button_enabled=0",
                    "button_hittable=0",
                    "menu_items=0",
                    "output_copy_action=0",
                    "toggle_action=0"
                ],
                to: outputPath
            )
            return
        }

        let inputItem = button.menu?.items.first(where: { $0.title == "入力をコピー" })
        let outputItem = button.menu?.items.first(where: { $0.title == "出力をコピー" })
        let combinedItem = button.menu?.items.first(where: { $0.title == "入力と出力をコピー" })
        let menuItemsPassed = inputItem?.isEnabled == !record.command.isEmpty
            && outputItem?.isEnabled == !record.output.isEmpty
            && combinedItem?.isEnabled == (!record.command.isEmpty || !record.output.isEmpty)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let actionSent: Bool
        if let outputItem, let action = outputItem.action {
            actionSent = NSApp.sendAction(action, to: outputItem.target, from: outputItem)
        } else {
            actionSent = false
        }
        let outputCopied = actionSent
            && pasteboard.string(forType: .string) == record.output

        let wasCollapsed = model.isCommandCollapsed(record.id)
        let toggleSent = commandBlock.accessibilityPerformPress()
        let togglePassed = toggleSent
            && model.isCommandCollapsed(record.id) != wasCollapsed
        if model.isCommandCollapsed(record.id) != wasCollapsed {
            model.toggleCommandCollapsed(record.id)
        }

        let center = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
        let localHit = button.hitTest(center)
        let hittable = localHit === button || localHit?.isDescendant(of: button) == true
        let visible = !button.visibleRect.isEmpty && !button.isHiddenOrHasHiddenAncestor

        let originalTranscriptMode = model.commandTranscriptMode
        let originalCollapsedState = model.isCommandCollapsed(record.id)
        let commandBlockIdentifier = "terminal-command-block-\(record.id.uuidString)"
        model.commandTranscriptMode = .on
        try? await Task.sleep(for: .milliseconds(120))

        let transcriptModeButton = findView(
            accessibilityIdentifier: "command-transcript-mode-button"
        ) as? NSButton
        let modeButtonCenter = transcriptModeButton.map {
            NSPoint(x: $0.bounds.midX, y: $0.bounds.midY)
        }
        let modeButtonHit = modeButtonCenter.flatMap { center in
            transcriptModeButton?.hitTest(center)
        }
        let modeButtonVisible = transcriptModeButton.map {
            !$0.visibleRect.isEmpty && !$0.isHiddenOrHasHiddenAncestor
        } ?? false
        let modeButtonHittable = transcriptModeButton.map { button in
            modeButtonHit === button || modeButtonHit?.isDescendant(of: button) == true
        } ?? false

        transcriptModeButton?.performClick(nil)
        try? await Task.sleep(for: .milliseconds(120))
        let modeButtonCyclesOff = model.commandTranscriptMode == .off
            && findView(accessibilityIdentifier: commandBlockIdentifier) == nil

        transcriptModeButton?.performClick(nil)
        var modeButtonCyclesEx = false
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(25))
            if model.commandTranscriptMode == .ex,
               findView(accessibilityIdentifier: commandBlockIdentifier) != nil,
               model.isCommandCollapsed(record.id) {
                modeButtonCyclesEx = true
                break
            }
        }

        transcriptModeButton?.performClick(nil)
        var modeButtonCyclesOn = false
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(25))
            if model.commandTranscriptMode == .on,
               findView(accessibilityIdentifier: commandBlockIdentifier) != nil {
                modeButtonCyclesOn = true
                break
            }
        }
        model.commandTranscriptMode = originalTranscriptMode
        if model.isCommandCollapsed(record.id) != originalCollapsedState {
            model.toggleCommandCollapsed(record.id)
        }

        writeProbeResult(
            [
                "button_found=1",
                "button_enabled=\(button.isEnabled ? 1 : 0)",
                "button_hittable=\((hittable && visible) ? 1 : 0)",
                "button_visible=\(visible ? 1 : 0)",
                "menu_items=\(menuItemsPassed ? 1 : 0)",
                "output_copy_action=\(outputCopied ? 1 : 0)",
                "toggle_action=\(togglePassed ? 1 : 0)",
                "transcript_mode_button_found=\(transcriptModeButton != nil ? 1 : 0)",
                "transcript_mode_button_enabled=\(transcriptModeButton?.isEnabled == true ? 1 : 0)",
                "transcript_mode_button_hittable=\((modeButtonHittable && modeButtonVisible) ? 1 : 0)",
                "mode_button_cycles_off=\(modeButtonCyclesOff ? 1 : 0)",
                "mode_button_cycles_ex=\(modeButtonCyclesEx ? 1 : 0)",
                "mode_button_cycles_on=\(modeButtonCyclesOn ? 1 : 0)"
            ],
            to: outputPath
        )
    }

    @MainActor
    private func findView(accessibilityIdentifier: String) -> NSView? {
        for window in NSApp.windows {
            guard let contentView = window.contentView else { continue }
            if let match = findView(
                accessibilityIdentifier: accessibilityIdentifier,
                in: contentView
            ) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func findView(
        accessibilityIdentifier: String,
        in view: NSView
    ) -> NSView? {
        if view.identifier?.rawValue == accessibilityIdentifier
            || view.accessibilityIdentifier() == accessibilityIdentifier {
            return view
        }
        for subview in view.subviews {
            if let match = findView(
                accessibilityIdentifier: accessibilityIdentifier,
                in: subview
            ) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func findMenuItem(
        keyEquivalent: String,
        modifierFlags expectedModifiers: NSEvent.ModifierFlags = [.command],
        in menu: NSMenu?
    ) -> NSMenuItem? {
        guard let menu else { return nil }
        let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        for item in menu.items {
            let modifiers = item.keyEquivalentModifierMask.intersection(relevantFlags)
            if item.keyEquivalent.lowercased() == keyEquivalent.lowercased(),
               modifiers == expectedModifiers {
                return item
            }
            if let match = findMenuItem(
                keyEquivalent: keyEquivalent,
                modifierFlags: expectedModifiers,
                in: item.submenu
            ) {
                return match
            }
        }
        return nil
    }

    private func writeProbeResult(_ lines: [String], to path: String) {
        let result = lines.joined(separator: "\n") + "\n"
        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: path),
            options: [.atomic]
        )
    }

    @MainActor
    private func runShortcutActionsProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_SHORTCUT_ACTIONS_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        for _ in 0..<100 {
            if mainWindow != nil, NSApp.mainMenu != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let window = mainWindow ?? NSApp.mainWindow,
              NSApp.mainMenu != nil else {
            writeProbeResult(["window_found=0"], to: outputPath)
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        while model.orderedMainTabs.count < 3 {
            model.createWorkspace()
        }
        let initialTabs = model.orderedMainTabs

        func selectedTab() -> MainTabReference? {
            if let selectedAgentChatID = model.selectedAgentChatID {
                return .agentChat(selectedAgentChatID)
            }
            if let selectedWorkspaceID = model.selectedWorkspaceID {
                return .workspace(selectedWorkspaceID)
            }
            return nil
        }

        func performShortcut(
            characters: String,
            charactersIgnoringModifiers: String? = nil,
            keyCode: UInt16,
            modifiers: NSEvent.ModifierFlags
        ) -> Bool {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
                isARepeat: false,
                keyCode: keyCode
            ) else {
                return false
            }
            return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
        }

        let defaultsConfigured = [
            "tab.next": "⌃⇥",
            "tab.previous": "⌃⇧⇥",
            "tab.select.1": "⌘1",
            "terminal.latestOutput.copy": "⌥⌘C",
            "terminal.transcript.cycle": "⌥⌘T",
            "history.toggle": "⌃⌘H",
            "sidebar.toggleLeft": "⌥⌘[",
            "sidebar.toggleRight": "⌥⌘]",
            "agent.new.local": "⇧⌘A",
            "pane.select.1": "⌃⌥1",
            "pane.select.4": "⌃⌥4"
        ].allSatisfy { actionID, displayName in
            model.keybindingChord(for: actionID)?.displayName == displayName
        }

        model.selectMainTab(initialTabs[0])
        let nextHandled = performShortcut(
            characters: "\t",
            keyCode: 48,
            modifiers: [.control]
        )
        try? await Task.sleep(for: .milliseconds(80))
        let nextSelected = selectedTab() == initialTabs[1]

        let previousMenuItem = findMenuItem(
            keyEquivalent: "\t",
            modifierFlags: [.control, .shift],
            in: NSApp.mainMenu
        )
        let previousHandled: Bool
        if let previousMenuItem,
           let action = previousMenuItem.action {
            previousHandled = NSApp.sendAction(
                action,
                to: previousMenuItem.target,
                from: previousMenuItem
            )
        } else {
            previousHandled = false
        }
        try? await Task.sleep(for: .milliseconds(80))
        let previousSelected = selectedTab() == initialTabs[0]

        let directHandled = performShortcut(
            characters: "3",
            keyCode: 20,
            modifiers: [.command]
        )
        try? await Task.sleep(for: .milliseconds(80))
        let directSelected = selectedTab() == initialTabs[2]

        guard let workspaceTab = initialTabs.first(where: { $0.kind == .workspace }) else {
            writeProbeResult(["workspace_tab_found=0"], to: outputPath)
            return
        }
        model.selectMainTab(workspaceTab)
        guard let sessionID = model.selectedSessionID else {
            writeProbeResult(["selected_session_found=0"], to: outputPath)
            return
        }

        model.splitSelected(axis: .vertical)
        model.splitSelected(axis: .horizontal)
        model.splitSelected(axis: .vertical)
        let paneIDs = model.selectedWorkspace.map {
            SplitTreeOperations.sessionIDs(in: $0.layout)
        } ?? []
        let paneFourHandled = performShortcut(
            characters: "4",
            keyCode: 21,
            modifiers: [.control, .option]
        )
        try? await Task.sleep(for: .milliseconds(80))
        let paneFourSelected = paneIDs.count >= 4
            && model.selectedSessionID == paneIDs[3]
        let paneTwoHandled = performShortcut(
            characters: "2",
            keyCode: 19,
            modifiers: [.control, .option]
        )
        try? await Task.sleep(for: .milliseconds(80))
        let paneTwoSelected = paneIDs.count >= 2
            && model.selectedSessionID == paneIDs[1]

        let marker = "APEXTERM_LATEST_OUTPUT_SHORTCUT_OK"
        let finishedAt = Date()
        let outputSessionID = model.selectedSessionID ?? sessionID
        model.recordCommandExecution(
            CommandExecutionRecord(
                sessionID: outputSessionID,
                command: "shortcut-output-probe",
                output: marker,
                exitCode: 0,
                startedAt: finishedAt.addingTimeInterval(-0.1),
                finishedAt: finishedAt
            )
        )
        NSPasteboard.general.clearContents()
        let copyHandled = performShortcut(
            characters: "c",
            keyCode: 8,
            modifiers: [.command, .option]
        )
        try? await Task.sleep(for: .milliseconds(120))
        let outputCopied = NSPasteboard.general.string(forType: .string) == marker
        let copyNoticeState = model.transientNotice == "コピーしました"
        var copyNoticeVisible = false
        for _ in 0..<20 {
            if TransientNoticePresentationProbe.shared.message == "コピーしました" {
                copyNoticeVisible = true
                break
            }
            try? await Task.sleep(for: .milliseconds(25))
        }

        model.commandTranscriptMode = .on
        let transcriptFirstHandled = performShortcut(
            characters: "t",
            keyCode: 17,
            modifiers: [.command, .option]
        )
        let transcriptOff = model.commandTranscriptMode == .off
        let transcriptSecondHandled = performShortcut(
            characters: "t",
            keyCode: 17,
            modifiers: [.command, .option]
        )
        let transcriptEx = model.commandTranscriptMode == .ex
        let transcriptThirdHandled = performShortcut(
            characters: "t",
            keyCode: 17,
            modifiers: [.command, .option]
        )
        let transcriptOn = model.commandTranscriptMode == .on

        model.isCommandHistoryVisible = false
        let historyHandled = performShortcut(
            characters: "h",
            keyCode: 4,
            modifiers: [.command, .control]
        )
        let historyToggled = model.isCommandHistoryVisible

        model.isWorkspaceSidebarCollapsed = false
        let leftSidebarHandled = performShortcut(
            characters: "[",
            keyCode: 33,
            modifiers: [.command, .option]
        )
        let leftSidebarToggled = model.isWorkspaceSidebarCollapsed

        model.isRightSidebarCollapsed = false
        let rightSidebarHandled = performShortcut(
            characters: "]",
            keyCode: 30,
            modifiers: [.command, .option]
        )
        let rightSidebarToggled = model.isRightSidebarCollapsed

        let agentCountBefore = model.agentChatTabs.count
        let newAgentHandled = performShortcut(
            characters: "a",
            keyCode: 0,
            modifiers: [.command, .shift]
        )
        try? await Task.sleep(for: .milliseconds(80))
        let newAgentCreated = model.agentChatTabs.count == agentCountBefore + 1
            && model.selectedAgentChatID != nil

        try? await Task.sleep(for: .seconds(1.7))
        let copyNoticeDismissed = model.transientNotice == nil

        writeProbeResult(
            [
                "window_found=1",
                "defaults_configured=\(defaultsConfigured ? 1 : 0)",
                "next_shortcut_handled=\(nextHandled ? 1 : 0)",
                "next_tab_selected=\(nextSelected ? 1 : 0)",
                "previous_shortcut_handled=\(previousHandled ? 1 : 0)",
                "previous_tab_selected=\(previousSelected ? 1 : 0)",
                "direct_shortcut_handled=\(directHandled ? 1 : 0)",
                "direct_tab_selected=\(directSelected ? 1 : 0)",
                "pane_four_shortcut_handled=\(paneFourHandled ? 1 : 0)",
                "pane_four_selected=\(paneFourSelected ? 1 : 0)",
                "pane_two_shortcut_handled=\(paneTwoHandled ? 1 : 0)",
                "pane_two_selected=\(paneTwoSelected ? 1 : 0)",
                "copy_shortcut_handled=\(copyHandled ? 1 : 0)",
                "latest_output_copied=\(outputCopied ? 1 : 0)",
                "copy_notice_state=\(copyNoticeState ? 1 : 0)",
                "copy_notice_visible=\(copyNoticeVisible ? 1 : 0)",
                "copy_notice_dismissed=\(copyNoticeDismissed ? 1 : 0)",
                "transcript_shortcuts_handled=\((transcriptFirstHandled && transcriptSecondHandled && transcriptThirdHandled) ? 1 : 0)",
                "transcript_cycle=\((transcriptOff && transcriptEx && transcriptOn) ? 1 : 0)",
                "history_shortcut_handled=\(historyHandled ? 1 : 0)",
                "history_toggled=\(historyToggled ? 1 : 0)",
                "left_sidebar_shortcut_handled=\(leftSidebarHandled ? 1 : 0)",
                "left_sidebar_toggled=\(leftSidebarToggled ? 1 : 0)",
                "right_sidebar_shortcut_handled=\(rightSidebarHandled ? 1 : 0)",
                "right_sidebar_toggled=\(rightSidebarToggled ? 1 : 0)",
                "new_agent_shortcut_handled=\(newAgentHandled ? 1 : 0)",
                "new_agent_created=\(newAgentCreated ? 1 : 0)"
            ],
            to: outputPath
        )
    }

    @MainActor
    private func runUniversalSearchProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_UNIVERSAL_SEARCH_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        for _ in 0..<100 {
            if mainWindow != nil, NSApp.mainMenu != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if model.selectedSessionID == nil {
            model.createWorkspace()
        }
        guard let workspace = model.selectedWorkspace,
              let sessionID = model.selectedSessionID else {
            writeProbeResult(
                [
                    "shortcut_configured=0",
                    "menu_shortcut=0",
                    "shortcut_handled=0",
                    "view_requested=0",
                    "root_probe_ready=1",
                    "probe_complete=1"
                ],
                to: outputPath
            )
            return
        }

        model.renameWorkspace(id: workspace.id, to: "Universal Search Workspace")
        model.renameSession(id: sessionID, to: "Universal Search Session")
        let finishedAt = Date()
        model.recordCommandExecution(
            CommandExecutionRecord(
                sessionID: sessionID,
                command: "universal-search-command",
                output: "Universal Search command output",
                exitCode: 0,
                startedAt: finishedAt.addingTimeInterval(-0.1),
                finishedAt: finishedAt
            )
        )
        model.createAgentChatTab(target: .local)
        try? await Task.sleep(for: .milliseconds(200))

        let configuredShortcut = model.keybindingChord(
            for: "search.universal"
        )?.displayName == "⌘K"
        var menuItem: NSMenuItem?
        for _ in 0..<100 {
            menuItem = findMenuItem(
                keyEquivalent: "k",
                in: NSApp.mainMenu
            )
            if menuItem != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let menuShortcut = menuItem != nil
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: mainWindow?.windowNumber ?? 0,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        )
        let shortcutHandled = event.map {
            NSApp.mainMenu?.performKeyEquivalent(with: $0) ?? false
        } ?? false

        for _ in 0..<300 {
            if model.isUniversalSearchPresented { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let viewRequested = model.isUniversalSearchPresented

        var lines = [
            "shortcut_configured=\(configuredShortcut ? 1 : 0)",
            "menu_shortcut=\(menuShortcut ? 1 : 0)",
            "shortcut_handled=\(shortcutHandled ? 1 : 0)",
            "view_requested=\(viewRequested ? 1 : 0)",
            "root_probe_ready=1"
        ]
        if !viewRequested {
            lines.append("probe_complete=1")
        }
        writeProbeResult(lines, to: outputPath)
    }

    @MainActor
    private func runCommandTimelineProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_COMMAND_TIMELINE_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        for _ in 0..<100 {
            if mainWindow != nil, NSApp.mainMenu != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if model.selectedSessionID == nil {
            model.createWorkspace()
        }
        guard let sessionID = model.selectedSessionID else {
            writeProbeResult(
                [
                    "shortcut_configured=0",
                    "menu_shortcut=0",
                    "shortcut_handled=0",
                    "view_requested=0",
                    "root_probe_ready=1",
                    "probe_complete=1"
                ],
                to: outputPath
            )
            return
        }

        let finishedAt = Date()
        model.recordCommandExecution(
            CommandExecutionRecord(
                sessionID: sessionID,
                command: "timeline-success-command",
                output: "timeline success output",
                exitCode: 0,
                startedAt: finishedAt.addingTimeInterval(-0.2),
                finishedAt: finishedAt.addingTimeInterval(-0.1)
            )
        )
        model.recordCommandExecution(
            CommandExecutionRecord(
                sessionID: sessionID,
                command: "timeline-failure-command --token timeline-secret-token",
                output: "TOKEN=timeline-secret-output",
                exitCode: 17,
                startedAt: finishedAt.addingTimeInterval(-0.1),
                finishedAt: finishedAt
            )
        )

        let configuredShortcut = model.keybindingChord(
            for: "history.timeline"
        )?.displayName == "⇧⌘Y"
        var menuItem: NSMenuItem?
        for _ in 0..<100 {
            menuItem = findMenuItem(
                keyEquivalent: "y",
                modifierFlags: [.command, .shift],
                in: NSApp.mainMenu
            )
            if menuItem != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let menuShortcut = menuItem != nil
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: mainWindow?.windowNumber ?? 0,
            context: nil,
            characters: "Y",
            charactersIgnoringModifiers: "y",
            isARepeat: false,
            keyCode: 16
        )
        let shortcutHandled = event.map {
            NSApp.mainMenu?.performKeyEquivalent(with: $0) ?? false
        } ?? false

        for _ in 0..<300 {
            if model.isCommandTimelinePresented { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let viewRequested = model.isCommandTimelinePresented
        var lines = [
            "shortcut_configured=\(configuredShortcut ? 1 : 0)",
            "menu_shortcut=\(menuShortcut ? 1 : 0)",
            "shortcut_handled=\(shortcutHandled ? 1 : 0)",
            "view_requested=\(viewRequested ? 1 : 0)",
            "root_probe_ready=1"
        ]
        if !viewRequested {
            lines.append("probe_complete=1")
        }
        writeProbeResult(lines, to: outputPath)
    }

    @MainActor
    private func runTmuxManagerProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_TMUX_MANAGER_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        let sessionName = "tmux-manager-probe"
        model.createNamedLocalTmuxWorkspace(name: sessionName)
        model.isTmuxSessionManagerPresented = true
        try? await Task.sleep(for: .milliseconds(650))
        model.refreshTmuxSessions()

        var descriptor: TmuxSessionDescriptor?
        for _ in 0..<80 {
            descriptor = model.tmuxEndpointStates
                .flatMap(\.sessions)
                .first { $0.name == sessionName }
            if descriptor != nil, !model.isTmuxRefreshing {
                break
            }
            try? await Task.sleep(for: .milliseconds(75))
        }

        let workspace = model.workspaces.first { $0.name == sessionName }
        let workspaceDetected = workspace.map(model.workspaceContainsTmux) ?? false
        let managerPresented = model.isTmuxSessionManagerPresented
        let listed = descriptor != nil

        if let descriptor {
            model.killTmuxSessions([descriptor])
            for _ in 0..<80 {
                if !model.isTmuxActionRunning && !model.isTmuxRefreshing {
                    break
                }
                try? await Task.sleep(for: .milliseconds(75))
            }
        }

        model.refreshTmuxSessions()
        for _ in 0..<80 {
            if !model.isTmuxRefreshing { break }
            try? await Task.sleep(for: .milliseconds(75))
        }
        let killed = !model.tmuxEndpointStates
            .flatMap(\.sessions)
            .contains { $0.name == sessionName }

        if let workspace {
            model.closeWorkspace(id: workspace.id)
        }
        model.isTmuxSessionManagerPresented = false

        writeProbeResult(
            [
                "manager_presented=\(managerPresented ? 1 : 0)",
                "local_session_listed=\(listed ? 1 : 0)",
                "workspace_tmux_detected=\(workspaceDetected ? 1 : 0)",
                "session_killed=\(killed ? 1 : 0)",
                "process_alive=1"
            ],
            to: outputPath
        )
    }

    @MainActor
    private func runFeatureProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_UI_FEATURE_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        let originalWindowName = model.mainWindowName
        let originalCompactMode = model.isCompactMode
        // Keep the legacy feature probe deterministic now that Compact Mode
        // moves the tab strip out of contentView and into the native titlebar.
        model.isCompactMode = false
        syncCompactTitlebar(on: mainWindow)
        let tabDropIntentPassed = MainTabDropIntent.resolve(
            locationX: 50,
            width: 100,
            allowsMerge: true
        ) == .merge
            && MainTabDropIntent.resolve(
                locationX: 10,
                width: 100,
                allowsMerge: true
            ) == .before
            && MainTabDropIntent.resolve(
                locationX: 90,
                width: 100,
                allowsMerge: true
            ) == .after

        let payloadID = UUID()
        let payloadRoundTrip = await withCheckedContinuation { continuation in
            TerminalDragPayload.load(
                from: TerminalDragPayload(kind: .workspacePane, id: payloadID).itemProvider()
            ) { payload in
                continuation.resume(returning: payload)
            }
        }
        let nativeDragPayloadPassed = payloadRoundTrip?.kind == .workspacePane
            && payloadRoundTrip?.id == payloadID

        let localSnapshot = TerminalSessionSnapshot(
            id: UUID(),
            kind: .local,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            appearance: model.terminalAppearance,
            remoteProfile: nil,
            fontSize: model.terminalFontSize,
            commandBlocksEnabled: true,
            smartPasteProtectionEnabled: model.smartPasteProtectionEnabled,
            multilinePasteConfirmationEnabled: model.multilinePasteConfirmationEnabled
        )
        let localLaunchPlan = localSnapshot.launchPlan
        let localShellWithoutTmuxPassed = URL(fileURLWithPath: localLaunchPlan.executable)
            .lastPathComponent != "tmux"
            && !localLaunchPlan.arguments.contains("new-session")
            && !localSnapshot.supportsReconnect

        var plusLeftClickPassed = false
        var plusRightClickMenuPassed = false
        for _ in 0..<20 {
            if let plusButton = findView(
                accessibilityIdentifier: "new-local-shell-button"
            ) as? NewTabNSButton {
                let countBeforePress = model.workspaces.count
                plusButton.performClick(nil)
                try? await Task.sleep(for: .milliseconds(75))
                plusLeftClickPassed = model.workspaces.count == countBeforePress + 1

                let menuTitles = plusButton.contextMenuProvider?()?
                    .items
                    .filter { !$0.isSeparatorItem }
                    .map(\.title) ?? []
                plusRightClickMenuPassed = menuTitles == [
                    "New Local Shell",
                    "Open Named tmux Session…",
                    "New Agent Chat — Local",
                    "New Agent Chat — Remote"
                ]
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        model.createWorkspace()
        model.createWorkspace()
        guard let dragged = model.workspaces.last,
              let reorderTarget = model.workspaces.first else {
            return
        }
        model.reorderWorkspace(draggedID: dragged.id, before: reorderTarget.id)
        let reorderPassed = model.workspaces.first?.id == dragged.id

        guard model.workspaces.count >= 2,
              let splitSource = model.workspaces.last,
              let splitTarget = model.workspaces.first,
              splitSource.id != splitTarget.id else {
            return
        }
        model.selectWorkspace(splitTarget)
        model.moveWorkspaceIntoSplit(
            draggedID: splitSource.id,
            targetID: splitTarget.id,
            axis: .vertical,
            newPaneFirst: false
        )
        let paneCount = model.workspaces.first(where: { $0.id == splitTarget.id })
            .map { SplitTreeOperations.paneCount(in: $0.layout) } ?? 0

        var nestedTreeDropPassed = false
        model.createWorkspace()
        if let nestedSource = model.selectedWorkspace,
           let sourceSessionID = SplitTreeOperations.sessionIDs(in: nestedSource.layout).first,
           let targetSessionID = model.workspaces.first(where: { $0.id == splitTarget.id })
            .flatMap({ SplitTreeOperations.sessionIDs(in: $0.layout).first }) {
            model.splitSession(id: sourceSessionID, axis: .horizontal)
            model.moveWorkspaceIntoSplit(
                draggedID: nestedSource.id,
                targetID: splitTarget.id,
                targetSessionID: targetSessionID,
                axis: .vertical,
                newPaneFirst: true
            )
            nestedTreeDropPassed = !model.workspaces.contains(where: { $0.id == nestedSource.id })
                && model.workspaces.first(where: { $0.id == splitTarget.id })
                    .map { SplitTreeOperations.paneCount(in: $0.layout) == 4 } == true
        }

        var tabMergeFourPanePassed = false
        model.createWorkspace()
        if let mergeTarget = model.selectedWorkspace,
           let mergeTargetSession = SplitTreeOperations.sessionIDs(in: mergeTarget.layout).first {
            model.splitSession(id: mergeTargetSession, axis: .vertical)
            model.createWorkspace()
            if let mergeSource = model.selectedWorkspace,
               let mergeSourceSession = SplitTreeOperations.sessionIDs(in: mergeSource.layout).first {
                model.splitSession(id: mergeSourceSession, axis: .vertical)
                model.mergeWorkspaceTabs(
                    draggedID: mergeSource.id,
                    targetID: mergeTarget.id,
                    axis: .vertical,
                    newPaneFirst: false
                )
                tabMergeFourPanePassed = !model.workspaces.contains(where: { $0.id == mergeSource.id })
                    && model.workspaces.first(where: { $0.id == mergeTarget.id })
                        .map { SplitTreeOperations.paneCount(in: $0.layout) == 4 } == true
            }
        }

        var paneHeaderMovePassed = false
        var paneWholeSwapPassed = false
        var paneMaximizePassed = false
        var paneNavigationPassed = false
        let paneDropPreviewSize = CGSize(width: 1_000, height: 600)
        let paneDropPreviewPassed = TerminalDropRegion.center
            .previewFrame(in: paneDropPreviewSize, inset: 10)
            == CGRect(x: 10, y: 10, width: 980, height: 580)
            && TerminalDropRegion.left
                .previewFrame(in: paneDropPreviewSize, inset: 10)
                == CGRect(x: 10, y: 10, width: 490, height: 580)
            && TerminalDropRegion.right
                .previewFrame(in: paneDropPreviewSize, inset: 10)
                == CGRect(x: 500, y: 10, width: 490, height: 580)
            && TerminalDropRegion.top
                .previewFrame(in: paneDropPreviewSize, inset: 10)
                == CGRect(x: 10, y: 10, width: 980, height: 290)
            && TerminalDropRegion.bottom
                .previewFrame(in: paneDropPreviewSize, inset: 10)
                == CGRect(x: 10, y: 300, width: 980, height: 290)
        model.createWorkspace()
        if let paneWorkspace = model.selectedWorkspace,
           let firstSessionID = SplitTreeOperations.sessionIDs(in: paneWorkspace.layout).first {
            model.splitSession(id: firstSessionID, axis: .vertical)
            if let secondSessionID = model.selectedSessionID {
                model.splitSession(id: secondSessionID, axis: .horizontal)
            }
            if let currentWorkspace = model.workspaces.first(where: { $0.id == paneWorkspace.id }) {
                let before = SplitTreeOperations.sessionIDs(in: currentWorkspace.layout)
                if let sourceSessionID = before.first,
                   let targetSessionID = before.last,
                   before.count == 3 {
                    model.dropWorkspacePane(
                        sourceSessionID: sourceSessionID,
                        ontoWorkspace: paneWorkspace.id,
                        targetSessionID: targetSessionID,
                        region: .right
                    )
                    if let movedWorkspace = model.workspaces.first(where: { $0.id == paneWorkspace.id }) {
                        let after = SplitTreeOperations.sessionIDs(in: movedWorkspace.layout)
                        paneHeaderMovePassed = after == Array(before.dropFirst()) + [sourceSessionID]
                        if after.count >= 2 {
                            model.dropWorkspacePane(
                                sourceSessionID: after[0],
                                ontoWorkspace: paneWorkspace.id,
                                targetSessionID: after[1],
                                region: .center
                            )
                            let swapped = model.workspaces
                                .first(where: { $0.id == paneWorkspace.id })
                                .map { SplitTreeOperations.sessionIDs(in: $0.layout) } ?? []
                            paneWholeSwapPassed = swapped.count == after.count
                                && swapped[0] == after[1]
                                && swapped[1] == after[0]

                            model.selectSession(swapped[0])
                            model.toggleMaximizeSelectedPane()
                            paneMaximizePassed = model.maximizedSessionID == swapped[0]
                            model.toggleMaximizeSelectedPane()
                            model.selectAdjacentPane(offset: 1)
                            paneNavigationPassed = model.selectedSessionID == swapped[1]
                        }
                    }
                }
            }
        }

        model.isCommandHistorySearchPresented = false
        model.performAction(id: "history.search")
        let historySearchActionPassed = model.isCommandHistorySearchPresented
        try? await Task.sleep(for: .milliseconds(250))
        let historySearchViewPassed = findView(
            accessibilityIdentifier: "command-history-search-view"
        ) != nil
        model.isCommandHistorySearchPresented = false

        let smartPastePassed = SmartPastePolicy()
            .assess("echo one\necho two\n")
            .requiresConfirmation

        let originalSecureInput = model.secureKeyboardEntryEnabled
        model.performAction(id: "terminal.secureInput.toggle")
        let secureInputActionPassed = model.secureKeyboardEntryEnabled != originalSecureInput
        model.performAction(id: "terminal.secureInput.toggle")

        let originalAutoCopy = model.autoCopyCommandOutputEnabled
        let originalClipboard = NSPasteboard.general.string(forType: .string)
        let autoCopyMarker = "APT_AUTO_COPY_\(UUID().uuidString)"
        model.autoCopyCommandOutputEnabled = true
        model.recordCommandExecution(
            CommandExecutionRecord(
                sessionID: model.selectedSessionID ?? UUID(),
                command: "apt-auto-copy-probe",
                output: autoCopyMarker,
                exitCode: 0,
                startedAt: Date(),
                finishedAt: Date()
            )
        )
        let autoCopyPassed = NSPasteboard.general.string(forType: .string) == autoCopyMarker
        model.autoCopyCommandOutputEnabled = originalAutoCopy
        NSPasteboard.general.clearContents()
        if let originalClipboard {
            NSPasteboard.general.setString(originalClipboard, forType: .string)
        }

        let originalAutoCollapse = model.autoCollapseLargeOutputsEnabled
        let originalAutoCollapseThreshold = model.autoCollapseLargeOutputLineThreshold
        model.autoCollapseLargeOutputsEnabled = true
        model.autoCollapseLargeOutputLineThreshold = 40
        let intelligenceRecord = CommandExecutionRecord(
            sessionID: model.selectedSessionID ?? UUID(),
            command: "apt-intelligence-probe",
            output: (1...50).map { "probe-line-\($0)" }.joined(separator: "\n"),
            exitCode: 1,
            startedAt: Date(),
            finishedAt: Date()
        )
        model.recordCommandExecution(intelligenceRecord)
        let autoCollapsePassed = model.isCommandCollapsed(intelligenceRecord.id)
        let historyFilterPassed = model.filteredCommandHistory(
            query: "intelligence-probe",
            failuresOnly: true
        ).contains { $0.id == intelligenceRecord.id }
        let insight = TerminalInsightCache.shared.insights(for: intelligenceRecord)
        let boundedOutputPassed = insight.outputPreview.text.count <= intelligenceRecord.output.count
        model.autoCollapseLargeOutputsEnabled = originalAutoCollapse
        model.autoCollapseLargeOutputLineThreshold = originalAutoCollapseThreshold

        var localShellInitialNumberPassed = false
        var localShellSequentialNumberPassed = false
        var localShellGapReusePassed = false
        var directWorkspaceRenamePassed = false
        var directTerminalRenamePassed = false
        model.createWorkspace()
        if let numberedWorkspace = model.selectedWorkspace,
           let firstSessionID = SplitTreeOperations.sessionIDs(
                in: numberedWorkspace.layout
           ).first {
            localShellInitialNumberPassed = model.session(id: firstSessionID)?.title
                == "Local Shell (01)"
            model.splitSession(id: firstSessionID, axis: .vertical)

            if let twoPaneWorkspace = model.workspaces.first(where: {
                $0.id == numberedWorkspace.id
            }) {
                let twoPaneIDs = SplitTreeOperations.sessionIDs(in: twoPaneWorkspace.layout)
                let twoPaneTitles = twoPaneIDs.compactMap { model.session(id: $0)?.title }
                localShellSequentialNumberPassed = Set(twoPaneTitles)
                    == Set(["Local Shell (01)", "Local Shell (02)"])

                if let secondSessionID = twoPaneIDs.first(where: {
                    model.session(id: $0)?.title == "Local Shell (02)"
                }) {
                    model.splitSession(id: secondSessionID, axis: .horizontal)
                    model.closeSession(id: secondSessionID)
                    model.splitSession(id: firstSessionID, axis: .vertical)
                }
            }

            if let gapWorkspace = model.workspaces.first(where: {
                $0.id == numberedWorkspace.id
            }) {
                let titles = SplitTreeOperations.sessionIDs(in: gapWorkspace.layout)
                    .compactMap { model.session(id: $0)?.title }
                localShellGapReusePassed = titles.count == 3
                    && titles.filter { $0 == "Local Shell (02)" }.count == 1
                    && Set(titles) == Set([
                        "Local Shell (01)",
                        "Local Shell (02)",
                        "Local Shell (03)"
                    ])
            }

            model.renameWorkspace(id: numberedWorkspace.id, to: "Renamed Main")
            model.renameSession(id: firstSessionID, to: "Renamed Local Shell")
            directWorkspaceRenamePassed = model.workspaces.contains {
                $0.id == numberedWorkspace.id && $0.name == "Renamed Main"
            }
            directTerminalRenamePassed = model.session(id: firstSessionID)?.title
                == "Renamed Local Shell"
            model.closeWorkspace(id: numberedWorkspace.id)
        }

        model.renameMainWindow(to: "Renamed Window")
        model.renameWorkspace(id: splitTarget.id, to: "renamed-tab")
        if let sessionID = SplitTreeOperations.sessionIDs(in: splitTarget.layout).first {
            model.renameSession(id: sessionID, to: "renamed-group")
        }
        let countBeforeClose = model.workspaces.count
        model.createWorkspace()
        if let closeCandidate = model.workspaces.last {
            model.closeWorkspace(id: closeCandidate.id)
        }
        let closeTabPassed = model.workspaces.count == countBeforeClose

        model.createNamedLocalTmuxWorkspace(name: "main-probe")
        let namedTmuxPassed = model.sessions.contains { session in
            if case let .localTmux(name) = session.kind { return name == "main-probe" }
            return false
        }
        let renameWindowPassed = model.mainWindowName == "Renamed Window"
        let renameTabPassed = model.workspaces.contains { $0.name == "renamed-tab" }
        let renameGroupPassed = model.sessions.contains { $0.title == "renamed-group" }

        model.createAgentChatTab(target: .gae)
        let agentChatID = model.selectedAgentChatID
        if let agentChatID {
            model.updateAgentChatDraft(id: agentChatID, value: "Agent Chat probe draft")
            model.setAgentChatPerformance(id: agentChatID, performance: .fastest)
            model.selectAgentChat(id: agentChatID)
        }
        let agentChatCreated = agentChatID != nil
            && model.agentChatTabs.contains(where: { $0.id == agentChatID && $0.target == .gae })
        let agentChatDraftPassed = agentChatID.flatMap { id in
            model.agentChatTabs.first(where: { $0.id == id })?.draft
        } == "Agent Chat probe draft"
        let agentChatSelected = model.selectedAgentChatID == agentChatID
        let agentChatPerformancePassed = agentChatID.flatMap { id in
            model.agentChatTabs.first(where: { $0.id == id })?.selectedPerformance
        } == .fastest
        var mixedTabOrderPassed = false
        if let agentChatID,
           let firstWorkspaceID = model.workspaces.first?.id {
            model.reorderMainTab(
                dragged: .agentChat(agentChatID),
                relativeTo: .workspace(firstWorkspaceID),
                after: false
            )
            mixedTabOrderPassed = model.orderedMainTabs.first == .agentChat(agentChatID)
        }

        model.isWorkspaceSidebarCollapsed = true
        model.isRightSidebarCollapsed = true
        model.isMainWindowPinned = true
        model.isCompactMode = true
        try? await Task.sleep(for: .milliseconds(250))
        let agentChatCompactPassed = model.isCompactMode
            && model.selectedAgentChatID == agentChatID
        if let namedWorkspace = model.workspaces.first(where: { $0.name == "main-probe" }) {
            model.selectWorkspace(namedWorkspace)
            try? await Task.sleep(for: .milliseconds(250))
        }

        let result = [
            "tab_reorder=\(reorderPassed ? 1 : 0)",
            "tab_drop_intent=\(tabDropIntentPassed ? 1 : 0)",
            "native_drag_payload=\(nativeDragPayloadPassed ? 1 : 0)",
            "local_shell_without_tmux=\(localShellWithoutTmuxPassed ? 1 : 0)",
            "plus_left_click_local=\(plusLeftClickPassed ? 1 : 0)",
            "plus_right_click_menu=\(plusRightClickMenuPassed ? 1 : 0)",
            "pane_header_move=\(paneHeaderMovePassed ? 1 : 0)",
            "pane_whole_swap=\(paneWholeSwapPassed ? 1 : 0)",
            "pane_drop_preview=\(paneDropPreviewPassed ? 1 : 0)",
            "pane_maximize=\(paneMaximizePassed ? 1 : 0)",
            "pane_navigation=\(paneNavigationPassed ? 1 : 0)",
            "history_search_action=\(historySearchActionPassed ? 1 : 0)",
            "history_search_view=\(historySearchViewPassed ? 1 : 0)",
            "history_filter=\(historyFilterPassed ? 1 : 0)",
            "smart_paste=\(smartPastePassed ? 1 : 0)",
            "secure_input_action=\(secureInputActionPassed ? 1 : 0)",
            "auto_copy_command_output=\(autoCopyPassed ? 1 : 0)",
            "auto_collapse_large_output=\(autoCollapsePassed ? 1 : 0)",
            "bounded_output_render=\(boundedOutputPassed ? 1 : 0)",
            "drop_split=\(paneCount == 2 ? 1 : 0)",
            "drop_nested_tree=\(nestedTreeDropPassed ? 1 : 0)",
            "tab_merge_four_panes=\(tabMergeFourPanePassed ? 1 : 0)",
            "mixed_tab_order=\(mixedTabOrderPassed ? 1 : 0)",
            "left_collapsed=\(model.isWorkspaceSidebarCollapsed ? 1 : 0)",
            "right_collapsed=\(model.isRightSidebarCollapsed ? 1 : 0)",
            "window_floating=\(mainWindow?.level == .floating ? 1 : 0)",
            "compact_mode=\(model.isCompactMode ? 1 : 0)",
            "rename_window=\(renameWindowPassed ? 1 : 0)",
            "rename_tab=\(renameTabPassed ? 1 : 0)",
            "rename_group=\(renameGroupPassed ? 1 : 0)",
            "local_shell_initial_number=\(localShellInitialNumberPassed ? 1 : 0)",
            "local_shell_sequential_number=\(localShellSequentialNumberPassed ? 1 : 0)",
            "local_shell_gap_reuse=\(localShellGapReusePassed ? 1 : 0)",
            "direct_workspace_rename=\(directWorkspaceRenamePassed ? 1 : 0)",
            "direct_terminal_rename=\(directTerminalRenamePassed ? 1 : 0)",
            "close_tab=\(closeTabPassed ? 1 : 0)",
            "named_tmux=\(namedTmuxPassed ? 1 : 0)",
            "agent_chat_created=\(agentChatCreated ? 1 : 0)",
            "agent_chat_target=\(model.agentChatTabs.first(where: { $0.id == agentChatID })?.target == .gae ? 1 : 0)",
            "agent_chat_draft=\(agentChatDraftPassed ? 1 : 0)",
            "agent_chat_selected=\(agentChatSelected ? 1 : 0)",
            "agent_chat_performance=\(agentChatPerformancePassed ? 1 : 0)",
            "agent_chat_compact=\(agentChatCompactPassed ? 1 : 0)"
        ].joined(separator: "\n") + "\n"
        model.renameMainWindow(to: originalWindowName)
        model.isCompactMode = originalCompactMode
        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: outputPath),
            options: [.atomic]
        )
    }

    @MainActor
    private func runComposerAlignmentProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_COMPOSER_ALIGNMENT_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        model.createAgentChatTab(target: .local)
        try? await Task.sleep(for: .milliseconds(500))

        var composer: AgentChatComposerContainerView?
        for _ in 0..<20 where composer == nil {
            composer = NSApp.windows
                .compactMap(\.contentView)
                .compactMap(findComposerView(in:))
                .first
            if composer == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        let result: String
        if let composer {
            let metrics = composer.alignmentMetrics()
            result = [
                "composer_found=1",
                "caret_placeholder_aligned=\(metrics.isAligned ? 1 : 0)",
                String(format: "delta_x=%.3f", Double(metrics.deltaX)),
                String(format: "delta_y=%.3f", Double(metrics.deltaY)),
                String(format: "editor_x=%.3f", Double(metrics.editorOrigin.x)),
                String(format: "editor_y=%.3f", Double(metrics.editorOrigin.y)),
                String(format: "placeholder_x=%.3f", Double(metrics.placeholderOrigin.x)),
                String(format: "placeholder_y=%.3f", Double(metrics.placeholderOrigin.y)),
            ].joined(separator: "\n") + "\n"
        } else {
            result = "composer_found=0\ncaret_placeholder_aligned=0\n"
        }

        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: outputPath),
            options: [.atomic]
        )
    }

    @MainActor
    private func findComposerView(in view: NSView) -> AgentChatComposerContainerView? {
        if let composer = view as? AgentChatComposerContainerView {
            return composer
        }
        for subview in view.subviews {
            if let composer = findComposerView(in: subview) {
                return composer
            }
        }
        return nil
    }

    @MainActor
    private func findComposerView(
        in view: NSView,
        tabID: UUID
    ) -> AgentChatComposerContainerView? {
        if let composer = view as? AgentChatComposerContainerView,
           composer.tabID == tabID {
            return composer
        }
        for subview in view.subviews {
            if let composer = findComposerView(in: subview, tabID: tabID) {
                return composer
            }
        }
        return nil
    }

    @MainActor
    private func runTabLifecycleProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_TAB_LIFECYCLE_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        let originalCompactMode = model.isCompactMode
        model.isCompactMode = false
        syncCompactTitlebar(on: mainWindow ?? NSApp.mainWindow)
        // If the app launched in Compact Mode, let AppKit finish removing the
        // native titlebar toolbar before starting responder stress cycles.
        try? await Task.sleep(for: .milliseconds(150))

        var terminalRuntimeRecovered = true
        var terminalFocusRecovered = true
        var removedRuntimeReleased = true
        var completedCloseCycles = 0

        // Repeatedly create and close the selected tab. Each close crosses the
        // SwiftUI/AppKit representable boundary that previously raced teardown
        // against first-responder recovery.
        for _ in 0..<20 {
            model.createWorkspace()
            try? await Task.sleep(for: .milliseconds(120))
            guard let closingWorkspace = model.selectedWorkspace else {
                terminalRuntimeRecovered = false
                break
            }
            let closingSessionIDs = SplitTreeOperations.sessionIDs(in: closingWorkspace.layout)
            model.closeWorkspace(id: closingWorkspace.id)

            var cycleRecovered = false
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(50))
                guard let selectedSessionID = model.selectedSessionID,
                      let container = TerminalPaneRuntimeStore.shared.container(for: selectedSessionID),
                      container.window != nil else {
                    continue
                }
                container.terminal.requestFocusWhenReady()
                try? await Task.sleep(for: .milliseconds(25))
                let focused = container.window?.firstResponder === container.terminal
                let running = container.terminal.process.running
                if focused && running {
                    cycleRecovered = true
                    break
                }
            }
            terminalRuntimeRecovered = terminalRuntimeRecovered && cycleRecovered
            terminalFocusRecovered = terminalFocusRecovered && cycleRecovered

            try? await Task.sleep(for: .milliseconds(80))
            let released = closingSessionIDs.allSatisfy {
                TerminalPaneRuntimeStore.shared.container(for: $0) == nil
            }
            removedRuntimeReleased = removedRuntimeReleased && released
            completedCloseCycles += 1
        }

        model.createAgentChatTab(target: .local)
        let firstChatID = model.selectedAgentChatID
        model.createAgentChatTab(target: .local)
        let secondChatID = model.selectedAgentChatID

        var composerFocusRecovered = false
        if let firstChatID, let secondChatID, firstChatID != secondChatID {
            model.selectAgentChat(id: firstChatID)
            try? await Task.sleep(for: .milliseconds(180))
            model.closeAgentChatTab(id: firstChatID)

            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(50))
                let inspectedWindow = mainWindow
                    ?? NSApp.windows.first {
                        $0.identifier == ApexTermWindowRole.main
                    }
                    ?? NSApp.mainWindow
                guard model.selectedAgentChatID == secondChatID,
                      let contentView = inspectedWindow?.contentView,
                      let composer = findComposerView(
                          in: contentView,
                          tabID: secondChatID
                      ),
                      composer.window != nil else {
                    continue
                }
                if composer.window?.firstResponder === composer.textView {
                    composerFocusRecovered = true
                    break
                }
            }
            model.closeAgentChatTab(id: secondChatID)
        }

        var terminalFocusAfterChatClose = false
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            guard model.selectedAgentChatID == nil,
                  let selectedSessionID = model.selectedSessionID,
                  let container = TerminalPaneRuntimeStore.shared.container(for: selectedSessionID),
                  container.window != nil else {
                continue
            }
            if container.window?.firstResponder === container.terminal {
                terminalFocusAfterChatClose = true
                break
            }
        }

        model.isCompactMode = originalCompactMode
        let result = [
            "close_cycles=\(completedCloseCycles)",
            "terminal_runtime_recovered=\(terminalRuntimeRecovered && completedCloseCycles == 20 ? 1 : 0)",
            "terminal_focus_recovered=\(terminalFocusRecovered && completedCloseCycles == 20 ? 1 : 0)",
            "removed_runtime_released=\(removedRuntimeReleased && completedCloseCycles == 20 ? 1 : 0)",
            "composer_focus_recovered=\(composerFocusRecovered ? 1 : 0)",
            "terminal_focus_after_chat_close=\(terminalFocusAfterChatClose ? 1 : 0)"
        ].joined(separator: "\n") + "\n"
        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: outputPath),
            options: [.atomic]
        )
    }

    @MainActor
    private func runCompactTitlebarProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_COMPACT_TITLEBAR_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        var resolvedWindow = mainWindow ?? NSApp.mainWindow
        for _ in 0..<40 where resolvedWindow == nil {
            try? await Task.sleep(for: .milliseconds(50))
            resolvedWindow = mainWindow
                ?? NSApp.mainWindow
                ?? NSApp.windows.first { $0.identifier == ApexTermWindowRole.main }
        }
        guard let window = resolvedWindow else {
            writeProbeResult(["window_found=0"], to: outputPath)
            return
        }
        window.makeKeyAndOrderFront(nil)

        let originalCompactMode = model.isCompactMode
        let originalNewTabVisibility = model.isUIControlVisible(.newTab)
        let originalTabSeparatorVisibility = model.isUIControlVisible(.tabSeparators)
        let originalContentSize = window.contentView?.bounds.size ?? NSSize(width: 900, height: 600)
        model.setUIControlVisible(.newTab, visible: true)
        model.isCompactMode = true
        syncCompactTitlebar(on: window)

        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            syncCompactTitlebar(on: window)
            if CompactTitlebarToolbarController.shared.isInstalled(on: window),
               CompactTitlebarToolbarController.shared.hostedViewContains(
                   identifier: NSUserInterfaceItemIdentifier("new-local-shell-button")
               ) {
                break
            }
        }

        let controller = CompactTitlebarToolbarController.shared
        let installed = controller.isInstalled(on: window)
        let toolbarIdentity = window.toolbar?.identifier == CompactTitlebarToolbarController.toolbarIdentifier
        let unifiedCompact = window.toolbarStyle == .unifiedCompact
        let titleHidden = window.titleVisibility == .hidden
        let titlebarHasNewTab = controller.hostedViewContains(
            identifier: NSUserInterfaceItemIdentifier("new-local-shell-button")
        )
        let titlebarAllowsWindowDrag = controller.hostedViewAllowsWindowDrag(
            identifier: CompactTitlebarDragRegion.identifier
        )
        let contentHasNewTab = window.contentView.map {
            findView(accessibilityIdentifier: "new-local-shell-button", in: $0) != nil
        } ?? false
        let compactPaneOutlineSuppressed = !SplitTreeView.showsSelectionOutline(
            isSelected: true,
            isCompactMode: true
        )
        let expandedPaneOutlinePreserved = SplitTreeView.showsSelectionOutline(
            isSelected: true,
            isCompactMode: false
        )

        func transcriptButtonMetrics() -> (
            found: Bool,
            width: CGFloat,
            rightInset: CGFloat,
            topInset: CGFloat
        ) {
            guard let contentView = window.contentView,
                  let button = findView(
                    accessibilityIdentifier: "command-transcript-mode-button"
                  ) as? NSButton else {
                return (false, 0, 0, 0)
            }
            let frameInContent = button.convert(button.bounds, to: contentView)
            let frameInWindow = button.convert(button.bounds, to: nil)
            let frameOnScreen = window.convertToScreen(frameInWindow)
            let contentOnScreen = window.convertToScreen(window.contentLayoutRect)
            return (
                true,
                button.bounds.width,
                max(0, contentView.bounds.maxX - frameInContent.maxX),
                max(0, contentOnScreen.maxY - frameOnScreen.maxY)
            )
        }

        let originalSelectedWorkspaceID = model.selectedWorkspaceID
        let originalSelectedAgentChatID = model.selectedAgentChatID
        let existingWorkspaceIDs = Set(model.workspaces.map(\.id))
        let existingAgentChatIDs = Set(model.agentChatTabs.map(\.id))

        let autoUpdateBaseline = controller.performanceSnapshot().contentUpdates
        model.createWorkspace()
        let autoProbeWorkspaceID = model.selectedWorkspaceID
        var titlebarAutoUpdated = false
        if let autoProbeWorkspaceID {
            let expectedRevisionFragment = autoProbeWorkspaceID.uuidString
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(25))
                let snapshot = controller.performanceSnapshot()
                if snapshot.contentUpdates > autoUpdateBaseline,
                   snapshot.contentRevision?.contains(expectedRevisionFragment) == true {
                    titlebarAutoUpdated = true
                    break
                }
            }
        }

        if model.workspaces.count < 2 {
            model.createWorkspace()
        }

        let layoutProbeWorkspaceID = model.workspaces[0].id
        if let layoutProbeWorkspace = model.workspaces.first(where: {
            $0.id == layoutProbeWorkspaceID
        }) {
            model.selectWorkspace(layoutProbeWorkspace)
        }
        let layoutProbeTabCount = model.orderedMainTabs.count

        model.setUIControlVisible(.tabSeparators, visible: false)
        window.setContentSize(
            NSSize(width: 360, height: max(220, originalContentSize.height))
        )
        syncCompactTitlebar(on: window)
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(25))
            if let snapshot = WorkspaceTabBarPresentationProbe.shared.snapshot,
               snapshot.usesIconOnlyTabs,
               snapshot.iconTabCount == layoutProbeTabCount,
               snapshot.separatorCount == max(0, layoutProbeTabCount - 1) {
                break
            }
        }
        let narrowSnapshot = WorkspaceTabBarPresentationProbe.shared.snapshot
        let narrowIconTabsRendered = narrowSnapshot?.usesIconOnlyTabs == true
            && narrowSnapshot?.iconTabCount == layoutProbeTabCount
            && narrowSnapshot?.labelTabCount == 0
        let narrowSeparatorForced = narrowSnapshot?.showsSeparators == true
            && narrowSnapshot?.separatorCount == max(0, layoutProbeTabCount - 1)
        let narrowTranscriptMetrics = transcriptButtonMetrics()

        window.setContentSize(
            NSSize(width: 760, height: max(220, originalContentSize.height))
        )
        syncCompactTitlebar(on: window)
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(25))
            if let snapshot = WorkspaceTabBarPresentationProbe.shared.snapshot,
               !snapshot.usesIconOnlyTabs,
               snapshot.labelTabCount == layoutProbeTabCount,
               snapshot.separatorCount == 0 {
                break
            }
        }
        let wideSnapshot = WorkspaceTabBarPresentationProbe.shared.snapshot
        let wideLabelsRendered = wideSnapshot?.usesIconOnlyTabs == false
            && wideSnapshot?.labelTabCount == layoutProbeTabCount
            && wideSnapshot?.iconTabCount == 0
        let wideSeparatorHiddenBySetting = wideSnapshot?.showsSeparators == false
            && wideSnapshot?.separatorCount == 0
        let wideTranscriptMetrics = transcriptButtonMetrics()
        let transcriptCycleButtonWidthBounded = narrowTranscriptMetrics.found
            && wideTranscriptMetrics.found
            && narrowTranscriptMetrics.width <= 34.5
            && wideTranscriptMetrics.width <= 34.5
        let transcriptCycleButtonRightInset = narrowTranscriptMetrics.rightInset >= 8
            && wideTranscriptMetrics.rightInset >= 8
        let compactPaneHeaderTopPadding = narrowTranscriptMetrics.topInset >= 4

        let performanceBefore = controller.performanceSnapshot()
        let probeWorkspaceIDs = Array(model.workspaces.prefix(2).map(\.id))
        let switchClock = ContinuousClock()
        let workspaceSwitchStartedAt = switchClock.now
        var completedWorkspaceSwitchCycles = 0
        if probeWorkspaceIDs.count == 2 {
            for index in 0..<40 {
                let workspaceID = probeWorkspaceIDs[index.isMultiple(of: 2) ? 0 : 1]
                guard let workspace = model.workspaces.first(where: {
                    $0.id == workspaceID
                }) else {
                    continue
                }
                model.selectWorkspace(workspace)
                await Task.yield()
                completedWorkspaceSwitchCycles += 1
            }
        }
        let workspaceSwitchDuration = workspaceSwitchStartedAt.duration(to: switchClock.now)
        let workspaceSwitchComponents = workspaceSwitchDuration.components
        let workspaceSwitchMilliseconds = workspaceSwitchComponents.seconds * 1_000
            + workspaceSwitchComponents.attoseconds / 1_000_000_000_000_000

        model.createAgentChatTab(target: .local)
        let firstProbeChatID = model.selectedAgentChatID
        model.createAgentChatTab(target: .local)
        let secondProbeChatID = model.selectedAgentChatID

        let agentSwitchStartedAt = switchClock.now
        var completedAgentSwitchCycles = 0
        if let firstProbeChatID, let secondProbeChatID {
            for index in 0..<40 {
                model.selectAgentChat(
                    id: index.isMultiple(of: 2)
                        ? firstProbeChatID
                        : secondProbeChatID
                )
                await Task.yield()
                completedAgentSwitchCycles += 1
            }
        }
        let agentSwitchDuration = agentSwitchStartedAt.duration(to: switchClock.now)
        let agentSwitchComponents = agentSwitchDuration.components
        let agentSwitchMilliseconds = agentSwitchComponents.seconds * 1_000
            + agentSwitchComponents.attoseconds / 1_000_000_000_000_000

        for _ in 0..<40 {
            if controller.performanceSnapshot().contentUpdates
                > performanceBefore.contentUpdates {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let performanceAfter = controller.performanceSnapshot()
        let titlebarHostReused = performanceAfter.hostingRootCreations
            == performanceBefore.hostingRootCreations
        let titlebarLayoutStable = performanceAfter.layoutResizes
            == performanceBefore.layoutResizes
        let titlebarContentUpdated = performanceAfter.contentUpdates
            > performanceBefore.contentUpdates
        let titlebarHostFillsContainer = performanceAfter.hostFillsContainer
        let titlebarHasNoVerticalGap = performanceAfter.containerFillsToolbarHostVertically

        for id in model.agentChatTabs.map(\.id)
            where !existingAgentChatIDs.contains(id) {
            model.closeAgentChatTab(id: id)
        }
        for id in model.workspaces.map(\.id)
            where !existingWorkspaceIDs.contains(id) {
            model.closeWorkspace(id: id)
        }
        if let originalSelectedAgentChatID,
           model.agentChatTabs.contains(where: { $0.id == originalSelectedAgentChatID }) {
            model.selectAgentChat(id: originalSelectedAgentChatID)
        } else if let originalSelectedWorkspaceID,
                  let originalWorkspace = model.workspaces.first(where: {
                      $0.id == originalSelectedWorkspaceID
                  }) {
            model.selectWorkspace(originalWorkspace)
        }
        syncCompactTitlebar(on: window)

        model.isCompactMode = false
        syncCompactTitlebar(on: window)
        try? await Task.sleep(for: .milliseconds(100))
        let removedWhenExpanded = !controller.isInstalled(on: window)
            && window.toolbar?.identifier != CompactTitlebarToolbarController.toolbarIdentifier
        let titleRestored = window.titleVisibility != .hidden

        model.setUIControlVisible(.tabSeparators, visible: false)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(25))
            if WorkspaceTabBarPresentationProbe.shared.snapshot?.showsSeparators == false {
                break
            }
        }
        let normalHiddenSnapshot = WorkspaceTabBarPresentationProbe.shared.snapshot
        let normalSeparatorHidden = normalHiddenSnapshot?.isCompactMode == false
            && normalHiddenSnapshot?.usesIconOnlyTabs == false
            && normalHiddenSnapshot?.showsSeparators == false
            && normalHiddenSnapshot?.separatorCount == 0

        model.setUIControlVisible(.tabSeparators, visible: true)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(25))
            if let snapshot = WorkspaceTabBarPresentationProbe.shared.snapshot,
               snapshot.showsSeparators,
               snapshot.separatorCount == max(0, snapshot.tabCount - 1) {
                break
            }
        }
        let normalShownSnapshot = WorkspaceTabBarPresentationProbe.shared.snapshot
        let normalSeparatorShown = normalShownSnapshot?.isCompactMode == false
            && normalShownSnapshot?.usesIconOnlyTabs == false
            && normalShownSnapshot?.showsSeparators == true
            && normalShownSnapshot?.separatorCount
                == max(0, (normalShownSnapshot?.tabCount ?? 0) - 1)

        model.setUIControlVisible(.newTab, visible: originalNewTabVisibility)
        model.setUIControlVisible(
            .tabSeparators,
            visible: originalTabSeparatorVisibility
        )
        window.setContentSize(originalContentSize)
        model.isCompactMode = originalCompactMode
        syncCompactTitlebar(on: window)

        writeProbeResult(
            [
                "window_found=1",
                "compact_toolbar_installed=\(installed ? 1 : 0)",
                "toolbar_identifier=\(toolbarIdentity ? 1 : 0)",
                "unified_compact_style=\(unifiedCompact ? 1 : 0)",
                "title_hidden=\(titleHidden ? 1 : 0)",
                "titlebar_new_tab=\(titlebarHasNewTab ? 1 : 0)",
                "titlebar_window_drag=\(titlebarAllowsWindowDrag ? 1 : 0)",
                "content_new_tab_removed=\(!contentHasNewTab ? 1 : 0)",
                "compact_pane_outline_suppressed=\(compactPaneOutlineSuppressed ? 1 : 0)",
                "expanded_pane_outline_preserved=\(expandedPaneOutlinePreserved ? 1 : 0)",
                "transcript_cycle_button_width_bounded=\(transcriptCycleButtonWidthBounded ? 1 : 0)",
                "transcript_cycle_button_right_inset=\(transcriptCycleButtonRightInset ? 1 : 0)",
                "compact_pane_header_top_padding=\(compactPaneHeaderTopPadding ? 1 : 0)",
                "narrow_transcript_button_width_pt=\(narrowTranscriptMetrics.width)",
                "wide_transcript_button_width_pt=\(wideTranscriptMetrics.width)",
                "narrow_transcript_button_right_inset_pt=\(narrowTranscriptMetrics.rightInset)",
                "wide_transcript_button_right_inset_pt=\(wideTranscriptMetrics.rightInset)",
                "compact_pane_header_top_inset_pt=\(narrowTranscriptMetrics.topInset)",
                "narrow_icon_tabs_rendered=\(narrowIconTabsRendered ? 1 : 0)",
                "narrow_separator_forced=\(narrowSeparatorForced ? 1 : 0)",
                "wide_labels_rendered=\(wideLabelsRendered ? 1 : 0)",
                "wide_separator_hidden_by_setting=\(wideSeparatorHiddenBySetting ? 1 : 0)",
                "normal_separator_hidden=\(normalSeparatorHidden ? 1 : 0)",
                "normal_separator_shown=\(normalSeparatorShown ? 1 : 0)",
                "titlebar_auto_updates=\(titlebarAutoUpdated ? 1 : 0)",
                "workspace_switch_cycles=\(completedWorkspaceSwitchCycles)",
                "workspace_switch_40_ms=\(workspaceSwitchMilliseconds)",
                "agent_switch_cycles=\(completedAgentSwitchCycles)",
                "agent_switch_40_ms=\(agentSwitchMilliseconds)",
                "titlebar_host_reused=\(titlebarHostReused ? 1 : 0)",
                "titlebar_layout_stable=\(titlebarLayoutStable ? 1 : 0)",
                "titlebar_content_updated=\(titlebarContentUpdated ? 1 : 0)",
                "titlebar_host_fills_container=\(titlebarHostFillsContainer ? 1 : 0)",
                "titlebar_vertical_gap_eliminated=\(titlebarHasNoVerticalGap ? 1 : 0)",
                "titlebar_geometry_available=\(performanceAfter.geometryAvailable ? 1 : 0)",
                "titlebar_content_bottom_gap_pt=\(performanceAfter.contentBottomGap)",
                "titlebar_content_top_gap_pt=\(performanceAfter.contentTopGap)",
                "titlebar_center_delta_from_traffic_lights_pt=\(performanceAfter.contentCenterDeltaFromTrafficLights)",
                "expanded_toolbar_removed=\(removedWhenExpanded ? 1 : 0)",
                "expanded_title_restored=\(titleRestored ? 1 : 0)"
            ],
            to: outputPath
        )
    }

    @MainActor
    private func runAgentChatE2EIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_AGENT_CHAT_E2E_FILE"],
              !outputPath.isEmpty else {
            return
        }

        let requestedTarget: GagTarget = environment["APEXTERM_AGENT_CHAT_E2E_TARGET"] == "local"
            ? .local
            : .gae
        let requestedPerformance = environment["APEXTERM_AGENT_CHAT_E2E_PERFORMANCE"]
            .flatMap(GagPerformance.parse)
            ?? .high
        model.createAgentChatTab(target: requestedTarget)
        guard let tabID = model.selectedAgentChatID else { return }
        model.setAgentChatPerformance(id: tabID, performance: requestedPerformance)
        model.updateAgentChatDraft(id: tabID, value: "Respond with exactly APEX_AGENT_CHAT_OK")
        model.sendAgentChat(id: tabID)

        let deadline = Date().addingTimeInterval(240)
        var observedProgress = false
        while Date() < deadline {
            guard let tab = model.agentChatTabs.first(where: { $0.id == tabID }) else { break }
            if (tab.metrics?.progress ?? 0) > 0 {
                observedProgress = true
            }
            if let job = tab.activeJob?.job,
               job.status.isTerminal || job.status == .waitingApproval || job.status == .interrupted {
                let responsePassed = tab.messages.contains {
                    $0.role == .assistant && $0.text.contains("APEX_AGENT_CHAT_OK")
                }
                let result = [
                    "agent_chat_job_started=1",
                    "agent_chat_progress=\(observedProgress ? 1 : 0)",
                    "agent_chat_succeeded=\(job.status == .succeeded ? 1 : 0)",
                    "agent_chat_response=\(responsePassed ? 1 : 0)",
                    "agent_chat_tokens=\((tab.metrics?.tokens.total ?? 0) > 0 ? 1 : 0)",
                    "agent_chat_requested_performance=\(tab.metrics?.requestedPerformance == requestedPerformance ? 1 : 0)",
                    "agent_chat_actual_model=\((tab.metrics?.selectedModel?.isEmpty == false || tab.metrics?.selectedModelLabel?.isEmpty == false) ? 1 : 0)",
                    "agent_chat_sol_model=\(([tab.metrics?.selectedModel, tab.metrics?.selectedModelLabel].compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains("sol")) ? 1 : 0)",
                    "agent_chat_cost=\(tab.metrics?.apiCostEstimate != nil ? 1 : 0)",
                    "agent_chat_url=\(tab.metrics?.conversationURL != nil ? 1 : 0)"
                ].joined(separator: "\n") + "\n"
                try? Data(result.utf8).write(
                    to: URL(fileURLWithPath: outputPath),
                    options: [.atomic]
                )
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }

        let timeoutResult = [
            "agent_chat_job_started=0",
            "agent_chat_progress=\(observedProgress ? 1 : 0)",
            "agent_chat_succeeded=0",
            "agent_chat_response=0",
            "agent_chat_tokens=0",
            "agent_chat_requested_performance=0",
            "agent_chat_actual_model=0",
            "agent_chat_sol_model=0",
            "agent_chat_cost=0",
            "agent_chat_url=0"
        ].joined(separator: "\n") + "\n"
        try? Data(timeoutResult.utf8).write(
            to: URL(fileURLWithPath: outputPath),
            options: [.atomic]
        )
    }

    @MainActor
    private func runReadmeScreenshotSceneIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let scene = environment["APEXTERM_README_SCREENSHOT_SCENE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !scene.isEmpty,
              let readyPath = environment["APEXTERM_README_SCREENSHOT_READY_FILE"],
              !readyPath.isEmpty else {
            return
        }

        for _ in 0..<120 {
            if mainWindow != nil { break }
            try? await Task.sleep(for: .milliseconds(25))
        }

        let screenshotAppearance = ApexInterfaceAppearance(
            rawValue: environment["APEXTERM_README_SCREENSHOT_APPEARANCE"] ?? "dark"
        ) ?? .dark
        model.interfaceAppearance = screenshotAppearance
        model.interfaceAccentColorHex = nil
        let appKitAppearance = NSAppearance(
            named: screenshotAppearance == .light ? .aqua : .darkAqua
        )
        NSApp.appearance = appKitAppearance
        mainWindow?.appearance = appKitAppearance
        model.languageCode = environment["APEXTERM_README_SCREENSHOT_LANGUAGE"] ?? "en"
        model.isMainWindowPinned = false
        model.isWorkspaceSidebarCollapsed = false
        model.isRightSidebarCollapsed = false
        model.isAgentRailVisible = true
        model.commandTranscriptMode = .on
        model.commandBlocksStartCollapsed = false

        while model.workspaces.count < 5 {
            model.createWorkspace()
        }
        let workspaceNames = ["Frontend", "API", "Tests", "Docs", "Deploy"]
        for (workspace, name) in zip(model.workspaces.prefix(workspaceNames.count), workspaceNames) {
            model.renameWorkspace(id: workspace.id, to: name)
        }

        guard let primary = model.workspaces.first else { return }
        model.selectWorkspace(primary)
        var sessionIDs = SplitTreeOperations.sessionIDs(in: primary.layout)
        if sessionIDs.count == 1, let first = sessionIDs.first {
            model.splitSession(id: first, axis: .vertical)
        }
        if let refreshed = model.workspaces.first(where: { $0.id == primary.id }) {
            sessionIDs = SplitTreeOperations.sessionIDs(in: refreshed.layout)
        }
        if sessionIDs.count == 2, let last = sessionIDs.last {
            model.splitSession(id: last, axis: .horizontal)
        }
        if let refreshed = model.workspaces.first(where: { $0.id == primary.id }) {
            sessionIDs = SplitTreeOperations.sessionIDs(in: refreshed.layout)
        }

        let paneNames = ["Web", "API", "Tests"]
        let commands = [
            ("npm run dev", "Local server ready at http://localhost:3000"),
            ("swift build --product ApexTerm", "Build complete! (0.82s)"),
            ("swift test", "Executed 177 tests, with 0 failures")
        ]
        let now = Date()
        for (index, sessionID) in sessionIDs.prefix(3).enumerated() {
            model.renameSession(id: sessionID, to: paneNames[index])
            model.recordCommandExecution(
                CommandExecutionRecord(
                    sessionID: sessionID,
                    command: commands[index].0,
                    output: commands[index].1,
                    exitCode: 0,
                    startedAt: now.addingTimeInterval(Double(index) - 4),
                    finishedAt: now.addingTimeInterval(Double(index) - 3.5)
                )
            )
        }
        if let firstSession = sessionIDs.first {
            model.selectSession(firstSession)
        }

        model.isCompactMode = scene == "compact"
        let contentSize = scene == "compact"
            ? CGSize(width: 760, height: 430)
            : CGSize(width: 1_180, height: 720)
        mainWindow?.setContentSize(contentSize)
        mainWindow?.center()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        switch scene {
        case "search":
            model.isUniversalSearchPresented = true
        case "timeline":
            model.isCommandTimelinePresented = true
        case "settings":
            model.isSettingsPresented = true
        default:
            break
        }

        try? await Task.sleep(for: .milliseconds(scene == "overview" ? 900 : 1_300))
        let screenshotWritten = environment["APEXTERM_README_SCREENSHOT_OUTPUT_FILE"]
            .map(writeReadmeScreenshot(to:)) ?? false
        let result = [
            "scene=\(scene)",
            "workspaces=\(model.workspaces.count)",
            "panes=\(sessionIDs.count)",
            "app_appearance=\(screenshotAppearance.rawValue)",
            "screenshot_written=\(screenshotWritten ? 1 : 0)",
            "ready=1"
        ].joined(separator: "\n") + "\n"
        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: readyPath),
            options: [.atomic]
        )
    }

    @MainActor
    private func writeReadmeScreenshot(to outputPath: String) -> Bool {
        guard !outputPath.isEmpty,
              let window = mainWindow?.attachedSheet ?? mainWindow,
              let contentView = window.contentView else {
            return false
        }

        contentView.layoutSubtreeIfNeeded()
        let bounds = contentView.bounds
        guard bounds.width > 0,
              bounds.height > 0,
              let sourceRep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return false
        }
        contentView.cacheDisplay(in: bounds, to: sourceRep)

        let sourceImage = NSImage(size: bounds.size)
        sourceImage.addRepresentation(sourceRep)
        let padding: CGFloat = 72
        let canvasSize = CGSize(
            width: bounds.width + padding * 2,
            height: bounds.height + padding * 2
        )
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()
        let appFrame = CGRect(
            x: padding,
            y: padding,
            width: bounds.width,
            height: bounds.height
        )
        let cornerRadius: CGFloat = 14
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -8)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(
            roundedRect: appFrame,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(
            roundedRect: appFrame,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).addClip()
        sourceImage.draw(
            in: appFrame,
            from: CGRect(origin: .zero, size: bounds.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
        let border = NSBezierPath(
            roundedRect: appFrame.insetBy(dx: -0.5, dy: -0.5),
            xRadius: cornerRadius + 0.5,
            yRadius: cornerRadius + 0.5
        )
        border.lineWidth = 1
        border.stroke()
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            let url = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private func runLanguageProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_LANGUAGE_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        let originalLanguage = model.languageCode
        model.isSettingsPresented = true
        let requestedCodes = ["en", "ja", "zh-Hans", "zh-Hant", "ko"]
        var immediateSwitchPassed = true
        for code in requestedCodes {
            model.languageCode = code
            try? await Task.sleep(for: .milliseconds(30))
            immediateSwitchPassed = immediateSwitchPassed
                && model.appLanguage.rawValue == code
                && model.appLanguage.locale.identifier.hasPrefix(code)
        }

        let japaneseBundle = Bundle.main.path(forResource: "ja", ofType: "lproj")
            .flatMap(Bundle.init(path:))
        let japaneseSettings = japaneseBundle?.localizedString(
            forKey: "Settings",
            value: nil,
            table: nil
        )
        let resourcesPresent = requestedCodes.allSatisfy { code in
            Bundle.main.path(forResource: code, ofType: "lproj") != nil
        }

        let result = [
            "settings_sheet=\(model.isSettingsPresented ? 1 : 0)",
            "language_switch=\(immediateSwitchPassed ? 1 : 0)",
            "language_resources=\(resourcesPresent ? 1 : 0)",
            "japanese_translation=\(japaneseSettings == "設定" ? 1 : 0)"
        ].joined(separator: "\n") + "\n"
        model.languageCode = originalLanguage
        try? Data(result.utf8).write(
            to: URL(fileURLWithPath: outputPath),
            options: [.atomic]
        )
    }

    @ViewBuilder
    private func mainWindowContextMenu() -> some View {
        Button("Rename Window…") {
            beginRenameMainWindow()
        }
        Divider()
        Button("New Local Shell") {
            model.createWorkspace()
        }
        Button("Open Named tmux Session…") {
            tmuxDraft = ""
            isNamedTmuxPresented = true
        }
        Divider()
        Button(model.isCompactMode ? "Exit Compact Mode" : "Enter Compact Mode") {
            model.isCompactMode.toggle()
        }
        Button(model.isMainWindowPinned ? "Unpin Main Window" : "Pin Main Window") {
            model.isMainWindowPinned.toggle()
        }
        Button(model.isWorkspaceSidebarCollapsed ? "Expand Left Sidebar" : "Collapse Left Sidebar") {
            model.isWorkspaceSidebarCollapsed.toggle()
        }
        Button(model.isRightSidebarCollapsed ? "Expand Right Sidebar" : "Collapse Right Sidebar") {
            model.isRightSidebarCollapsed.toggle()
        }
        Divider()
        Button("Settings…") {
            model.isSettingsPresented = true
        }
    }

    @ViewBuilder
    private func workspaceContextMenu(_ workspace: Workspace) -> some View {
        Button("Rename Workspace…") {
            beginRenameWorkspace(workspace)
        }
        Divider()
        Button("Move Tab Left") {
            model.moveMainTab(.workspace(workspace.id), offset: -1)
        }
        Button("Move Tab Right") {
            model.moveMainTab(.workspace(workspace.id), offset: 1)
        }
        Button("Close Tab") {
            model.closeWorkspace(id: workspace.id)
        }
        if model.workspaceContainsTmux(workspace) {
            Button("Close Tab and End tmux Session", role: .destructive) {
                model.closeWorkspaceAndKillTmux(id: workspace.id)
            }
        }
        Button("Close Other Tabs") {
            model.closeOtherWorkspaces(keeping: workspace.id)
        }
        Button("Close Tabs to the Right") {
            model.closeWorkspacesToRight(of: workspace.id)
        }
        if let sessionID = SplitTreeOperations.sessionIDs(in: workspace.layout).first {
            Divider()
            Button("Split Right") {
                model.splitSession(id: sessionID, axis: .vertical)
            }
            Button("Split Down") {
                model.splitSession(id: sessionID, axis: .horizontal)
            }
        }
        Divider()
        Button("New Local Shell") {
            model.createWorkspace()
        }
        Button("Open Named tmux Session…") {
            tmuxDraft = ""
            isNamedTmuxPresented = true
        }
        if let directory = workspace.rootDirectory {
            Divider()
            Button("Copy Working Directory") {
                ClipboardWriter.copy(directory)
            }
            Button("Reveal Working Directory in Finder") {
                revealInFinder(directory)
            }
        }
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: TerminalSession) -> some View {
        Button("Focus Terminal") {
            model.selectSession(session.id)
        }
        Button("Rename Terminal…") {
            beginRenameSession(session)
        }
        Divider()
        Button("Split Right") {
            model.splitSession(id: session.id, axis: .vertical)
        }
        Button("Split Down") {
            model.splitSession(id: session.id, axis: .horizontal)
        }
        Button("Close Terminal Group") {
            model.closeSession(id: session.id)
        }
        if case .localTmux = session.kind {
            Button("Close and End tmux Session", role: .destructive) {
                model.closeSessionAndKillTmux(id: session.id)
            }
        } else if case .tmux = session.kind {
            Button("Close and End tmux Session", role: .destructive) {
                model.closeSessionAndKillTmux(id: session.id)
            }
        }
        if let directory = session.workingDirectory {
            Divider()
            Button("Copy Working Directory") {
                ClipboardWriter.copy(directory)
            }
            Button("Reveal Working Directory in Finder") {
                revealInFinder(directory)
            }
        }
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: path)
        ])
    }

    private func beginRenameMainWindow() {
        renameDraft = model.mainWindowName
        isRenameMainWindowPresented = true
    }

    private func beginRenameWorkspace(_ workspace: Workspace) {
        renameWorkspaceID = workspace.id
        renameDraft = workspace.name
        isRenameWorkspacePresented = true
    }

    private func beginRenameSession(_ session: TerminalSession) {
        renameSessionID = session.id
        renameDraft = session.title
        isRenameSessionPresented = true
    }

    private func workspaceDetail(_ workspace: Workspace) -> String {
        let paneCount = SplitTreeOperations.sessionIDs(in: workspace.layout).count
        if let root = workspace.rootDirectory {
            return "\(URL(fileURLWithPath: root).lastPathComponent) · \(paneCount) pane\(paneCount == 1 ? "" : "s")"
        }
        return "\(paneCount) pane\(paneCount == 1 ? "" : "s")"
    }

    private var sessionKindStatus: String {
        guard let session = model.selectedSession else { return "No Session" }
        return switch session.kind {
        case .local: "Local PTY"
        case let .localTmux(session): "tmux:\(session)"
        case .ssh: "SSH"
        case .tmux: "SSH + tmux"
        }
    }

    private var remoteStatus: String {
        guard let session = model.selectedSession else { return "—" }
        return switch session.kind {
        case .local:
            "—"
        case let .localTmux(session):
            "local / tmux:\(session)"
        case let .ssh(host):
            host
        case let .tmux(host, session):
            "\(host) / tmux:\(session)"
        }
    }
}

private struct ApexSidebarDisclosureGroupStyle: DisclosureGroupStyle {
    let fontSize: Double

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: max(8, min(11, fontSize - 3)), weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 14, height: 24, alignment: .center)

                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, 20)
            }
        }
    }
}
