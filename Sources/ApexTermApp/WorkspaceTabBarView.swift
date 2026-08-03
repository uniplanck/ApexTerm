import ApexTermCore
import AppKit
import SwiftUI

struct WorkspaceTabBarPresentationSnapshot: Equatable {
    let availableWidth: CGFloat
    let isCompactMode: Bool
    let usesIconOnlyTabs: Bool
    let showsSeparators: Bool
    let tabCount: Int
    let iconTabCount: Int
    let labelTabCount: Int
    let separatorCount: Int
}

@MainActor
final class WorkspaceTabBarPresentationProbe {
    static let shared = WorkspaceTabBarPresentationProbe()

    private(set) var snapshot: WorkspaceTabBarPresentationSnapshot?

    private init() {}

    func record(
        availableWidth: CGFloat,
        isCompactMode: Bool,
        separatorsEnabled: Bool,
        tabCount: Int
    ) {
        let presentation = TabBarPresentationPolicy(
            availableWidth: Double(availableWidth),
            separatorsEnabled: separatorsEnabled
        )
        snapshot = WorkspaceTabBarPresentationSnapshot(
            availableWidth: availableWidth,
            isCompactMode: isCompactMode,
            usesIconOnlyTabs: presentation.usesIconOnlyTabs,
            showsSeparators: presentation.showsSeparators,
            tabCount: tabCount,
            iconTabCount: presentation.usesIconOnlyTabs ? tabCount : 0,
            labelTabCount: presentation.usesIconOnlyTabs ? 0 : tabCount,
            separatorCount: presentation.showsSeparators ? max(0, tabCount - 1) : 0
        )
    }
}

struct WorkspaceTabBarView: View {
    @ObservedObject var model: AppModel
    let onOpenNamedTmux: () -> Void
    let onRenameWorkspace: (Workspace) -> Void

    @State private var tabWidths: [UUID: CGFloat] = [:]
    @State private var dropIndicator: MainTabDropIndicator?
    @State private var hoverActivationTask: Task<Void, Never>?
    @State private var availableWidth: CGFloat = .greatestFiniteMagnitude

    var body: some View {
        let tabs = model.orderedMainTabs
        let presentation = TabBarPresentationPolicy(
            availableWidth: Double(availableWidth),
            separatorsEnabled: model.isUIControlVisible(.tabSeparators)
        )

        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, item in
                        switch item.kind {
                        case .workspace:
                            if let workspace = model.workspaces.first(where: { $0.id == item.uuid }) {
                                workspaceTab(
                                    workspace,
                                    item: item,
                                    iconOnly: presentation.usesIconOnlyTabs
                                )
                            }
                        case .agentChat:
                            if let tab = model.agentChatTabs.first(where: { $0.id == item.uuid }) {
                                agentChatTab(
                                    tab,
                                    item: item,
                                    iconOnly: presentation.usesIconOnlyTabs
                                )
                            }
                        }

                        if presentation.showsSeparators && index < tabs.count - 1 {
                            tabSeparator(
                                after: item,
                                iconOnly: presentation.usesIconOnlyTabs
                            )
                        }
                    }
                }
            }

            if model.isCompactMode {
                CompactTitlebarDragRegion()
                    .frame(minWidth: 12, maxWidth: 12, maxHeight: .infinity)
            } else {
                Divider().frame(height: 20)
            }

            if model.isUIControlVisible(.newTab) {
                NewTabButton(
                    onCreateLocalShell: model.createWorkspace,
                    onOpenNamedTmux: onOpenNamedTmux,
                    onCreateLocalAgentChat: {
                        model.createAgentChatTab(target: .local)
                    },
                    onCreateRemoteAgentChat: {
                        model.createAgentChatTab(target: .gae)
                    }
                )
                .frame(width: 32, height: 32)

                remoteHostLaunchMenu
            }

            if model.isUIControlVisible(.tmuxManager) {
                Button {
                    model.isTmuxSessionManagerPresented = true
                } label: {
                    Image(systemName: "rectangle.stack")
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.plain)
                .help("tmuxセッション管理")
            }

            if model.isUIControlVisible(.tabBarPinWindow) {
                Button {
                    model.isMainWindowPinned.toggle()
                } label: {
                    Image(systemName: model.isMainWindowPinned ? "pin.fill" : "pin")
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.plain)
                .help(model.isMainWindowPinned ? "Unpin Main Window" : "Pin Main Window Above Others")
            }

            if model.isUIControlVisible(.compactMode) {
                Button {
                    model.isCompactMode.toggle()
                } label: {
                    Image(
                        systemName: model.isCompactMode
                            ? "arrow.up.left.and.arrow.down.right"
                            : "rectangle.compress.vertical"
                    )
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help(model.isCompactMode ? "Exit compact terminal mode" : "Compact terminal mode")
            }
        }
        .frame(
            minHeight: model.isCompactMode ? 0 : 34,
            maxHeight: model.isCompactMode ? .infinity : 34
        )
        .padding(.trailing, model.isCompactMode ? 8 : 0)
        .background(
            model.isCompactMode
                ? Color.clear
                : Color(nsColor: .controlBackgroundColor)
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            guard abs(availableWidth - width) > 0.5 else { return }
            availableWidth = width
            recordPresentation(
                width: width,
                tabCount: tabs.count,
                separatorsEnabled: model.isUIControlVisible(.tabSeparators)
            )
        }
        .onAppear {
            recordPresentation(
                width: availableWidth,
                tabCount: tabs.count,
                separatorsEnabled: model.isUIControlVisible(.tabSeparators)
            )
        }
        .onChange(of: model.isUIControlVisible(.tabSeparators)) { _, enabled in
            recordPresentation(
                width: availableWidth,
                tabCount: tabs.count,
                separatorsEnabled: enabled
            )
        }
        .onChange(of: tabs.map(\.id)) { _, identifiers in
            recordPresentation(
                width: availableWidth,
                tabCount: identifiers.count,
                separatorsEnabled: model.isUIControlVisible(.tabSeparators)
            )
        }
        .onDisappear {
            hoverActivationTask?.cancel()
            hoverActivationTask = nil
        }
    }

    private func recordPresentation(
        width: CGFloat,
        tabCount: Int,
        separatorsEnabled: Bool
    ) {
        WorkspaceTabBarPresentationProbe.shared.record(
            availableWidth: width,
            isCompactMode: model.isCompactMode,
            separatorsEnabled: separatorsEnabled,
            tabCount: tabCount
        )
    }

    @ViewBuilder
    private func workspaceTabLabel(
        _ workspace: Workspace,
        iconOnly: Bool
    ) -> some View {
        let isSelected = model.selectedAgentChatID == nil
            && workspace.id == model.selectedWorkspaceID

        if iconOnly {
            ZStack {
                Circle()
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.22)
                            : Color.primary.opacity(0.06)
                    )
                Circle()
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.85)
                            : Color.secondary.opacity(0.30),
                        lineWidth: 1
                    )
                Image(systemName: "terminal")
                    .font(.caption.weight(.semibold))
            }
            .frame(width: 26, height: 26)
            .accessibilityIdentifier("workspace-tab-icon-\(workspace.id.uuidString)")
            .help(workspace.name)
        } else {
            HStack(spacing: 7) {
                Image(systemName: "terminal")
                    .font(.caption)
                Text(workspace.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                let paneCount = SplitTreeOperations.paneCount(in: workspace.layout)
                if paneCount > 1 {
                    Text("\(paneCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, model.isCompactMode ? 9 : 12)
            .padding(.trailing, 6)
            .frame(height: model.isCompactMode ? 24 : 34)
            .accessibilityIdentifier("workspace-tab-label-\(workspace.id.uuidString)")
        }
    }

    @ViewBuilder
    private func agentChatTabLabel(
        _ tab: AgentChatTab,
        iconOnly: Bool
    ) -> some View {
        let isSelected = tab.id == model.selectedAgentChatID

        if iconOnly {
            ZStack {
                Circle()
                    .fill(
                        isSelected
                            ? Color.purple.opacity(0.22)
                            : Color.primary.opacity(0.06)
                    )
                Circle()
                    .stroke(
                        isSelected
                            ? Color.purple.opacity(0.85)
                            : Color.secondary.opacity(0.30),
                        lineWidth: 1
                    )
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .purple, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if tab.isRunning {
                    Circle()
                        .fill(.purple)
                        .frame(width: 5, height: 5)
                        .offset(x: 9, y: -9)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityIdentifier("agent-chat-tab-icon-\(tab.id.uuidString)")
            .help(tab.title)
        } else {
            HStack(spacing: 7) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .purple, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(tab.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                if tab.isRunning {
                    Circle()
                        .fill(.purple)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle()
                                .stroke(.purple.opacity(0.35), lineWidth: 3)
                                .scaleEffect(1.4)
                        )
                }
            }
            .padding(.leading, model.isCompactMode ? 9 : 12)
            .padding(.trailing, 6)
            .frame(height: model.isCompactMode ? 24 : 34)
            .accessibilityIdentifier("agent-chat-tab-label-\(tab.id.uuidString)")
        }
    }

    private func tabSeparator(
        after item: MainTabReference,
        iconOnly: Bool
    ) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(iconOnly ? 0.8 : 0.6))
            .frame(width: 1, height: iconOnly ? 18 : 22)
            .padding(.horizontal, iconOnly ? 3 : 0)
            .accessibilityElement()
            .accessibilityLabel("Tab separator")
            .accessibilityIdentifier("tab-separator-\(item.id)")
            .allowsHitTesting(false)
    }

    private var remoteHostLaunchMenu: some View {
        Menu {
            if model.sshProfiles.isEmpty {
                Button("Remote Host Settings…") {
                    model.isRemoteHostSettingsPresented = true
                }
            } else {
                Section("Open Remote Host") {
                    ForEach(model.sshProfiles) { profile in
                        Button {
                            model.createRemoteWorkspace(profile: profile)
                        } label: {
                            Label(profile.displayTitle, systemImage: "network")
                        }
                    }
                }

                Divider()

                Button("Remote Host Settings…") {
                    model.isRemoteHostSettingsPresented = true
                }
            }
        } label: {
            Image(systemName: "network")
                .frame(width: 30, height: 32)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.sshProfiles.isEmpty ? "Configure Remote Hosts" : "Open Remote Host")
        .accessibilityLabel("Open Remote Host")
    }

    private func workspaceTab(
        _ workspace: Workspace,
        item: MainTabReference,
        iconOnly: Bool
    ) -> some View {
        HStack(spacing: 0) {
            workspaceTabLabel(workspace, iconOnly: iconOnly)
            .contentShape(Rectangle())
            .onTapGesture {
                model.selectWorkspace(workspace)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(workspace.name) tab")
            .accessibilityIdentifier("workspace-tab-\(workspace.id.uuidString)")
            .accessibilityAddTraits(.isButton)

            if !iconOnly && model.isUIControlVisible(.tabCloseButtons) {
                Button {
                    model.closeWorkspace(id: workspace.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(
                            model.isCompactMode ? Color.secondary : Color.primary
                        )
                        .frame(
                            width: model.isCompactMode ? 20 : 22,
                            height: model.isCompactMode ? 24 : 34
                        )
                }
                .buttonStyle(.plain)
                .help("Close terminal tab")
                .contextMenu {
                    Button("Close Tab") {
                        model.closeWorkspace(id: workspace.id)
                    }
                    if model.workspaceContainsTmux(workspace) {
                        Button("Close Tab and End tmux Session", role: .destructive) {
                            model.closeWorkspaceAndKillTmux(id: workspace.id)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: model.isCompactMode ? .infinity : nil)
        .background {
            if iconOnly {
                Color.clear
            } else if model.isCompactMode {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        model.selectedAgentChatID == nil
                            && workspace.id == model.selectedWorkspaceID
                            ? Color.primary.opacity(0.10)
                            : Color.clear
                    )
            } else {
                Rectangle()
                    .fill(
                        workspace.id == model.selectedWorkspaceID
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear
                    )
            }
        }
        .padding(.vertical, model.isCompactMode || iconOnly ? 3 : 0)
        .padding(.horizontal, model.isCompactMode || iconOnly ? 1 : 0)
        .contextMenu {
            Button("Rename Workspace…") {
                onRenameWorkspace(workspace)
            }
            Divider()
            Button("Move Tab Left") {
                model.moveMainTab(item, offset: -1)
            }
            Button("Move Tab Right") {
                model.moveMainTab(item, offset: 1)
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
            Divider()
            if let sessionID = SplitTreeOperations.sessionIDs(in: workspace.layout).first {
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
            Button("Open Named tmux Session…", action: onOpenNamedTmux)
            if let directory = workspace.rootDirectory {
                Divider()
                Button("Copy Working Directory") {
                    ClipboardWriter.copy(directory)
                }
                Button("Reveal Working Directory in Finder") {
                    revealInFinder(directory)
                }
            }
            Divider()
            Button(model.isCompactMode ? "Exit Compact Mode" : "Enter Compact Mode") {
                model.isCompactMode.toggle()
            }
            Button(model.isMainWindowPinned ? "Unpin Main Window" : "Pin Main Window") {
                model.isMainWindowPinned.toggle()
            }
            Button("Settings…") {
                model.isSettingsPresented = true
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            guard tabWidths[workspace.id] != width else { return }
            tabWidths[workspace.id] = width
        }
        .overlay {
            insertionMarker(for: item)
        }
        .contentShape(Rectangle())
        .onDrag {
            TerminalDragPayload(kind: .workspace, id: workspace.id).itemProvider()
        }
        .onDrop(
            of: [.apexTermTerminalTab],
            delegate: MainTabDropDelegate(
                target: item,
                width: tabWidths[workspace.id] ?? 1,
                allowsMerge: true,
                indicator: $dropIndicator,
                onHover: scheduleHoverActivation,
                onExit: cancelHoverActivation,
                onPayload: handleDrop
            )
        )
    }

    private func agentChatTab(
        _ tab: AgentChatTab,
        item: MainTabReference,
        iconOnly: Bool
    ) -> some View {
        HStack(spacing: 0) {
            agentChatTabLabel(tab, iconOnly: iconOnly)
            .contentShape(Rectangle())
            .onTapGesture {
                model.selectAgentChat(id: tab.id)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tab.title) tab")
            .accessibilityIdentifier("agent-chat-tab-\(tab.id.uuidString)")
            .accessibilityAddTraits(.isButton)

            if !iconOnly && model.isUIControlVisible(.tabCloseButtons) {
                Button {
                    model.closeAgentChatTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(
                            model.isCompactMode ? Color.secondary : Color.primary
                        )
                        .frame(
                            width: model.isCompactMode ? 20 : 22,
                            height: model.isCompactMode ? 24 : 34
                        )
                }
                .buttonStyle(.plain)
                .help("Close Agent Chat")
            }
        }
        .frame(maxHeight: model.isCompactMode ? .infinity : nil)
        .background {
            if iconOnly {
                Color.clear
            } else if model.isCompactMode {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        tab.id == model.selectedAgentChatID
                            ? Color.primary.opacity(0.10)
                            : Color.clear
                    )
            } else {
                tab.id == model.selectedAgentChatID
                    ? LinearGradient(
                        colors: [
                            .pink.opacity(0.12),
                            .purple.opacity(0.13),
                            .cyan.opacity(0.1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    : LinearGradient(
                        colors: [.clear, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
            }
        }
        .padding(.vertical, model.isCompactMode || iconOnly ? 3 : 0)
        .padding(.horizontal, model.isCompactMode || iconOnly ? 1 : 0)
        .contextMenu {
            Button("New Agent Chat — Local") {
                model.createAgentChatTab(target: .local)
            }
            Button("New Agent Chat — Remote") {
                model.createAgentChatTab(target: .gae)
            }
            Divider()
            Button("Move Tab Left") {
                model.moveMainTab(item, offset: -1)
            }
            Button("Move Tab Right") {
                model.moveMainTab(item, offset: 1)
            }
            Divider()
            if tab.metrics?.conversationURL != nil {
                Button("Open running Chat") {
                    model.openAgentChatConversation(id: tab.id)
                }
            }
            if tab.isRunning {
                Button("Cancel Run", role: .destructive) {
                    model.cancelAgentChat(id: tab.id)
                }
            }
            Button("Close Agent Chat") {
                model.closeAgentChatTab(id: tab.id)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            guard tabWidths[tab.id] != width else { return }
            tabWidths[tab.id] = width
        }
        .overlay {
            insertionMarker(for: item)
        }
        .contentShape(Rectangle())
        .onDrag {
            TerminalDragPayload(kind: .agentChat, id: tab.id).itemProvider()
        }
        .onDrop(
            of: [.apexTermTerminalTab],
            delegate: MainTabDropDelegate(
                target: item,
                width: tabWidths[tab.id] ?? 1,
                allowsMerge: false,
                indicator: $dropIndicator,
                onHover: scheduleHoverActivation,
                onExit: cancelHoverActivation,
                onPayload: handleDrop
            )
        )
    }

    @ViewBuilder
    private func insertionMarker(for item: MainTabReference) -> some View {
        if let indicator = dropIndicator,
           indicator.target == item {
            switch indicator.intent {
            case .before, .after:
                HStack(spacing: 0) {
                    if indicator.intent == .after { Spacer(minLength: 0) }
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 3)
                        .shadow(color: Color.accentColor.opacity(0.5), radius: 3)
                    if indicator.intent == .before { Spacer(minLength: 0) }
                }
                .allowsHitTesting(false)
            case .merge:
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                    .overlay {
                        Image(systemName: "rectangle.split.2x1.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func handleDrop(
        _ payload: TerminalDragPayload,
        _ target: MainTabReference,
        _ intent: MainTabDropIntent
    ) {
        guard let source = payload.mainTabReference,
              source != target else { return }

        if intent == .merge,
           source.kind == .workspace,
           target.kind == .workspace {
            model.mergeWorkspaceTabs(
                draggedID: source.uuid,
                targetID: target.uuid,
                axis: .vertical,
                newPaneFirst: false
            )
            return
        }

        model.reorderMainTab(
            dragged: source,
            relativeTo: target,
            after: intent != .before
        )
    }

    private func scheduleHoverActivation(_ target: MainTabReference) {
        hoverActivationTask?.cancel()
        let selected = model.selectedAgentChatID.map(MainTabReference.agentChat)
            ?? model.selectedWorkspaceID.map(MainTabReference.workspace)
        guard selected != target else { return }
        hoverActivationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            model.selectMainTab(target)
        }
    }

    private func cancelHoverActivation() {
        hoverActivationTask?.cancel()
        hoverActivationTask = nil
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: path)
        ])
    }
}
