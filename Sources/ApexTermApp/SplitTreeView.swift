import ApexTermCore
import AppKit
import SwiftUI

@MainActor
private final class FixedWidthTranscriptModeButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 30, height: 20)
    }
}

private struct NativeColumnAddTabButton: NSViewRepresentable {
    let accessibilityIdentifier: String
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: NSImage(
                systemSymbolName: "plus",
                accessibilityDescription: "New terminal tab in this column"
            ) ?? NSImage(),
            target: context.coordinator,
            action: #selector(Coordinator.performAction(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        button.setAccessibilityLabel("New terminal tab in this column")
        button.toolTip = "New terminal tab in this column"
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryPushIn)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: @MainActor () -> Void

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        @objc func performAction(_ sender: NSButton) {
            action()
        }
    }
}

private struct NativeRatioSplitView: NSViewRepresentable {
    let isVertical: Bool
    let ratio: CGFloat
    let layoutKey: String
    let first: AnyView
    let second: AnyView

    func makeNSView(context: Context) -> RatioSplitContainerView {
        let view = RatioSplitContainerView(frame: .zero)
        view.configure(
            isVertical: isVertical,
            ratio: ratio,
            layoutKey: layoutKey,
            first: first,
            second: second
        )
        return view
    }

    func updateNSView(_ nsView: RatioSplitContainerView, context: Context) {
        nsView.configure(
            isVertical: isVertical,
            ratio: ratio,
            layoutKey: layoutKey,
            first: first,
            second: second
        )
    }

    @MainActor
    final class RatioSplitContainerView: NSView, NSSplitViewDelegate {
        private let splitView = NSSplitView(frame: .zero)
        private let firstHost = NSHostingView(rootView: AnyView(EmptyView()))
        private let secondHost = NSHostingView(rootView: AnyView(EmptyView()))
        private var requestedRatio: CGFloat = 0.5
        private var requestedKey = ""
        private var appliedKey: String?
        private var applyScheduled = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            splitView.dividerStyle = .thin
            splitView.delegate = self
            splitView.addSubview(firstHost)
            splitView.addSubview(secondHost)
            addSubview(splitView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(
            isVertical: Bool,
            ratio: CGFloat,
            layoutKey: String,
            first: AnyView,
            second: AnyView
        ) {
            firstHost.rootView = first
            secondHost.rootView = second
            requestedRatio = min(0.95, max(0.05, ratio))
            if splitView.isVertical != isVertical {
                splitView.isVertical = isVertical
                appliedKey = nil
            }
            if requestedKey != layoutKey {
                requestedKey = layoutKey
                appliedKey = nil
            }
            needsLayout = true
            splitView.needsLayout = true
            scheduleApply()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleApply()
        }

        override func layout() {
            super.layout()
            splitView.frame = bounds
            splitView.adjustSubviews()
            applyRatioIfNeeded()
        }

        private func scheduleApply() {
            guard window != nil,
                  appliedKey != requestedKey,
                  !applyScheduled else {
                return
            }
            applyScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applyScheduled = false
                self.needsLayout = true
                self.layoutSubtreeIfNeeded()
                self.applyRatioIfNeeded()
            }
        }

        private func applyRatioIfNeeded() {
            guard appliedKey != requestedKey,
                  splitView.subviews.count >= 2 else {
                return
            }
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            guard total > splitView.dividerThickness else {
                scheduleApply()
                return
            }
            splitView.setPosition(total * requestedRatio, ofDividerAt: 0)
            appliedKey = requestedKey
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainSplitPosition proposedPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let minimum: CGFloat = splitView.isVertical ? 120 : 100
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            let maximum = max(minimum, total - minimum - splitView.dividerThickness)
            return min(maximum, max(minimum, proposedPosition))
        }
    }
}

private struct CommandTranscriptModeCycleButton: NSViewRepresentable {
    @Binding var mode: CommandTranscriptMode

    func makeCoordinator() -> Coordinator {
        Coordinator(mode: $mode)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = FixedWidthTranscriptModeButton(
            title: mode.title,
            target: context.coordinator,
            action: #selector(Coordinator.cycleMode(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier("command-transcript-mode-button")
        button.setAccessibilityIdentifier("command-transcript-mode-button")
        button.setAccessibilityLabel("Cycle command transcript mode")
        button.bezelStyle = .roundRect
        button.controlSize = .small
        button.focusRingType = .none
        button.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        button.setButtonType(.momentaryPushIn)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.mode = $mode
        button.title = mode.title
        button.toolTip = "Command transcript: \(mode.title). Click for \(mode.next.title)."
    }

    @MainActor
    final class Coordinator: NSObject {
        var mode: Binding<CommandTranscriptMode>

        init(mode: Binding<CommandTranscriptMode>) {
            self.mode = mode
        }

        @objc func cycleMode(_ sender: NSButton) {
            mode.wrappedValue = mode.wrappedValue.next
        }
    }
}

struct SplitTreeView: View {
    let workspaceID: UUID
    let node: SplitNode
    @ObservedObject var model: AppModel
    @State private var activeDropRegion: TerminalDropRegion?
    @State private var terminalTabDropIndicator: TerminalTabDropIndicator?
    @State private var renameSessionID: UUID?
    @State private var renameDraft = ""
    @State private var livePaneHeights: [UUID: Double] = [:]
    @State private var livePanePreviewHeights: [UUID: Double] = [:]
    @State private var transcriptContentHeights: [UUID: Double] = [:]

    static func showsSelectionOutline(
        isSelected: Bool,
        isCompactMode: Bool
    ) -> Bool {
        isSelected && !isCompactMode
    }

    var body: some View {
        Group {
            switch node {
            case let .pane(sessionID):
                terminalColumn(
                    TerminalColumn(
                        id: sessionID,
                        sessionIDs: [sessionID],
                        selectedSessionID: sessionID
                    )
                )
            case let .column(column):
                terminalColumn(column)
            case let .split(axis, ratio, first, second):
                splitView(axis: axis, ratio: ratio, first: first, second: second)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(
            "Rename Tab",
            isPresented: Binding(
                get: { renameSessionID != nil },
                set: { presented in
                    if !presented { renameSessionID = nil }
                }
            )
        ) {
            TextField("Tab name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renameSessionID {
                    model.renameSession(id: renameSessionID, to: renameDraft)
                }
            }
        }
    }

    @ViewBuilder
    private func terminalColumn(_ column: TerminalColumn) -> some View {
        let resolvedSessionID = model.session(id: column.selectedSessionID) != nil
            ? column.selectedSessionID
            : column.sessionIDs.first(where: { model.session(id: $0) != nil })
        let isFocused = model.selectedSessionID.map(column.sessionIDs.contains) ?? false

        if let resolvedSessionID {
            VStack(spacing: 0) {
                terminalColumnHeader(
                    column: column,
                    selectedSessionID: resolvedSessionID,
                    isFocused: isFocused
                )
                Divider()
                pane(
                    sessionID: resolvedSessionID,
                    showsHeader: false,
                    allowsSelfEdgeDrop: column.sessionIDs.count > 1
                )
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay {
                if Self.showsSelectionOutline(
                    isSelected: isFocused,
                    isCompactMode: model.isCompactMode
                ) {
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityIdentifier("terminal-column-\(column.id.uuidString)")
        } else {
            ContentUnavailableView(
                "Missing Terminal Tabs",
                systemImage: "exclamationmark.triangle",
                description: Text("This column references unavailable terminal sessions.")
            )
        }
    }

    private func terminalColumnHeader(
        column: TerminalColumn,
        selectedSessionID: UUID,
        isFocused: Bool
    ) -> some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(column.sessionIDs, id: \.self) { sessionID in
                        if let session = model.session(id: sessionID) {
                            terminalColumnTab(
                                session: session,
                                isSelected: sessionID == selectedSessionID,
                                isColumnFocused: isFocused
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 31)
            }

            if isFocused {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Text(model.commandStatus(sessionID: selectedSessionID) ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        commandPresetMenu(sessionID: selectedSessionID)
                        CommandTranscriptModeCycleButton(mode: $model.commandTranscriptMode)
                            .frame(width: 30, height: 20)
                        columnAddButton(anchorSessionID: selectedSessionID)
                    }
                    HStack(spacing: 4) {
                        CommandTranscriptModeCycleButton(mode: $model.commandTranscriptMode)
                            .frame(width: 30, height: 20)
                        columnAddButton(anchorSessionID: selectedSessionID)
                    }
                    columnAddButton(anchorSessionID: selectedSessionID)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 5)
            }
        }
        .frame(height: 32)
        .background(
            isFocused
                ? Color.accentColor.opacity(0.07)
                : Color(nsColor: .controlBackgroundColor)
        )
    }

    private func terminalColumnTab(
        session: TerminalSession,
        isSelected: Bool,
        isColumnFocused: Bool
    ) -> some View {
        let tabWidth: CGFloat = if session.kind == .local
            && LocalShellNaming.isAutomaticTitle(session.title) {
            80
        } else {
            168
        }

        return HStack(spacing: 6) {
            Image(systemName: "circle.grid.2x2")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
            Circle()
                .fill(statusColor(for: session.state))
                .frame(width: 7, height: 7)
            Text(session.title)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            Button {
                model.closeSession(id: session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Close terminal tab")
        }
        .padding(.horizontal, 8)
        .frame(width: tabWidth, height: 28)
        .contentShape(Rectangle())
        .background(
            isSelected
                ? Color.accentColor.opacity(isColumnFocused ? 0.16 : 0.10)
                : Color.clear
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(isColumnFocused ? 0.7 : 0.35), lineWidth: 1)
            }
        }
        .overlay {
            if let indicator = terminalTabDropIndicator,
               indicator.targetSessionID == session.id {
                HStack(spacing: 0) {
                    if indicator.after { Spacer(minLength: 0) }
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                    if !indicator.after { Spacer(minLength: 0) }
                }
                .padding(.vertical, 3)
                .allowsHitTesting(false)
            }
        }
        .onTapGesture {
            model.selectSession(session.id)
        }
        .onTapGesture(count: 2) {
            renameSessionID = session.id
            renameDraft = session.title
        }
        .onDrag {
            model.selectSession(session.id)
            return TerminalDragPayload(kind: .workspacePane, id: session.id).itemProvider()
        }
        .onDrop(
            of: [.apexTermTerminalTab],
            delegate: TerminalTabDropDelegate(
                targetSessionID: session.id,
                width: tabWidth,
                indicator: $terminalTabDropIndicator
            ) { payload, targetSessionID, after in
                guard let sourceSessionID = payload.workspacePaneSessionID else { return }
                withAnimation(.snappy(duration: 0.18)) {
                    if let workspace = model.workspaces.first(where: { $0.id == workspaceID }),
                       let sourceColumn = SplitTreeOperations.column(
                           containing: sourceSessionID,
                           in: workspace.layout
                       ),
                       let targetColumn = SplitTreeOperations.column(
                           containing: targetSessionID,
                           in: workspace.layout
                       ),
                       sourceColumn.id == targetColumn.id {
                        model.reorderTerminalTab(
                            sourceSessionID: sourceSessionID,
                            relativeTo: targetSessionID,
                            after: after
                        )
                    } else {
                        model.dropWorkspacePane(
                            sourceSessionID: sourceSessionID,
                            ontoWorkspace: workspaceID,
                            targetSessionID: targetSessionID,
                            region: .center
                        )
                    }
                }
            }
        )
        .background {
            NativeTerminalTabProbe(sessionID: session.id)
                .allowsHitTesting(false)
        }
        .help("Drag to reorder, move into another column, or drop on a column edge")
        .accessibilityIdentifier("terminal-column-tab-\(session.id.uuidString)")
    }

    private func columnAddButton(anchorSessionID: UUID) -> some View {
        NativeColumnAddTabButton(
            accessibilityIdentifier: "terminal-column-add-tab-\(anchorSessionID.uuidString)"
        ) {
            model.addTerminalTab(toColumnContaining: anchorSessionID)
        }
        .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private func pane(
        sessionID: UUID,
        showsHeader: Bool = true,
        allowsSelfEdgeDrop: Bool = false
    ) -> some View {
        if let session = model.session(id: sessionID) {
            GeometryReader { proxy in
                let transcriptMode = model.commandTranscriptMode
                let recentCommands = model.recentCommands(
                    sessionID: session.id,
                    limit: transcriptMode.recordLimit
                )
                let showsTranscript = transcriptMode.showsTranscript
                    && !recentCommands.isEmpty
                let minimumLivePaneHeight: CGFloat = 76
                let maximumLivePaneHeight = max(
                    minimumLivePaneHeight,
                    min(420, proxy.size.height * 0.65)
                )
                let storedLivePaneHeight = livePaneHeights[session.id]
                    ?? persistedLivePaneHeight(for: session.id)
                let resolvedLivePaneHeight = min(
                    max(CGFloat(storedLivePaneHeight), minimumLivePaneHeight),
                    maximumLivePaneHeight
                )
                let previewLivePaneHeight = livePanePreviewHeights[session.id].map { height in
                    min(max(CGFloat(height), minimumLivePaneHeight), maximumLivePaneHeight)
                }
                let manualLivePaneHeight = previewLivePaneHeight ?? resolvedLivePaneHeight
                let paneHeaderTopInset: CGFloat = showsHeader && model.isCompactMode ? 5 : 0
                let transcriptLayout = CommandTranscriptLayoutPolicy.resolve(
                    mode: transcriptMode,
                    showsTranscript: showsTranscript,
                    containerHeight: Double(proxy.size.height),
                    measuredContentHeight: transcriptContentHeights[session.id] ?? 86,
                    preferredLivePaneHeight: Double(manualLivePaneHeight),
                    minimumLivePaneHeight: Double(minimumLivePaneHeight),
                    maximumLivePaneHeight: Double(maximumLivePaneHeight),
                    headerHeight: showsHeader ? Double(26 + paneHeaderTopInset) : 0,
                    resizeHandleHeight: 12
                )
                let resolvedTranscriptHeight = CGFloat(transcriptLayout.transcriptHeight)
                let effectiveLivePaneHeight = CGFloat(transcriptLayout.livePaneHeight)

                ZStack {
                    VStack(spacing: 0) {
                        if showsHeader {
                            ZStack {
                            HStack(spacing: 7) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Circle()
                                    .fill(statusColor(for: session.state))
                                    .frame(width: 7, height: 7)
                                Text(session.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(model.commandStatus(sessionID: session.id) ?? kindLabel(session.kind))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)

                                commandPresetMenu(sessionID: session.id)

                                CommandTranscriptModeCycleButton(
                                    mode: $model.commandTranscriptMode
                                )
                                .frame(width: 30, height: 20)
                                .padding(.trailing, 2)
                                .help("Command transcript: \(transcriptMode.title). Click to cycle.")
                            }
                            .padding(.horizontal, 9)

                            NativePaneDragHandle(
                                sessionID: sessionID,
                                title: session.title,
                                onSelect: {
                                    model.selectSession(sessionID)
                                },
                                onRename: {
                                    renameSessionID = session.id
                                    renameDraft = session.title
                                }
                            )
                            .id(sessionID)
                            .padding(.trailing, 90)
                        }
                        .frame(height: 25)
                        .padding(.top, paneHeaderTopInset)
                        .contentShape(Rectangle())
                        .background(
                            sessionID == model.selectedSessionID
                                ? Color.accentColor.opacity(0.14)
                                : Color(nsColor: .controlBackgroundColor)
                        )
                        .help("Drag into another column, then choose top, bottom, left, right, or whole")

                            Divider()
                        }

                        if showsTranscript {
                            TerminalCommandTranscript(
                                records: recentCommands,
                                appearance: model.terminalAppearance,
                                fontSize: model.terminalFontSize,
                                collapsedCommandIDs: model.collapsedCommandIDs,
                                onToggleCollapsed: model.toggleCommandCollapsed,
                                onInsertCommand: { command in
                                    model.requestTerminalInput(
                                        command,
                                        sessionID: session.id
                                    )
                                },
                                onContentHeightChange: { height in
                                    let value = Double(height)
                                    guard abs((transcriptContentHeights[session.id] ?? 0) - value) > 0.5 else {
                                        return
                                    }
                                    if transcriptMode == .ex {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            transcriptContentHeights[session.id] = value
                                        }
                                    } else {
                                        transcriptContentHeights[session.id] = value
                                    }
                                }
                            )
                            .frame(height: resolvedTranscriptHeight)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    model.selectSession(session.id)
                                }
                            )

                            if transcriptLayout.showsResizeHandle {
                                TerminalLivePaneResizeHandle(
                                    sessionID: session.id,
                                    currentHeight: effectiveLivePaneHeight,
                                    minimumHeight: minimumLivePaneHeight,
                                    maximumHeight: maximumLivePaneHeight,
                                    onResizeChanged: { height in
                                        let value = Double(height)
                                        if let previous = livePanePreviewHeights[session.id],
                                           abs(previous - value) < 0.75 {
                                            return
                                        }
                                        var transaction = Transaction()
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            livePanePreviewHeights[session.id] = value
                                        }
                                    },
                                    onResizeEnded: { height in
                                        let value = Double(height)
                                        var transaction = Transaction()
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            livePaneHeights[session.id] = value
                                            livePanePreviewHeights.removeValue(forKey: session.id)
                                        }
                                        UserDefaults.standard.set(
                                            value,
                                            forKey: livePaneHeightKey(for: session.id)
                                        )
                                    }
                                )
                                .frame(height: 12)
                            }
                        }

                        TerminalPaneView(
                            session: TerminalSessionSnapshot(
                                id: session.id,
                                kind: session.kind,
                                workingDirectory: session.workingDirectory,
                                appearance: model.terminalAppearance,
                                remoteProfile: remoteProfile(for: session.kind),
                                fontSize: model.terminalFontSize,
                                commandBlocksEnabled: model.terminalCommandBlocksEnabled,
                                smartPasteProtectionEnabled: model.smartPasteProtectionEnabled,
                                multilinePasteConfirmationEnabled: model.multilinePasteConfirmationEnabled
                            ),
                            onTitleChange: { title in
                                model.updateTerminalTitle(title, sessionID: session.id)
                            },
                            onDirectoryChange: { directory in
                                model.updateCurrentDirectory(directory, sessionID: session.id)
                            },
                            onStateChange: { state in
                                model.updateSessionState(state, sessionID: session.id)
                            },
                            onSemanticEvents: { events in
                                Task { @MainActor in
                                    model.recordSemanticEvents(events, sessionID: session.id)
                                }
                            },
                            onCommandCaptured: { record in
                                model.recordCommandExecution(record)
                            },
                            onActivate: {
                                model.selectSession(session.id)
                            }
                        )
                        .frame(
                            minHeight: showsTranscript ? effectiveLivePaneHeight : 0,
                            idealHeight: showsTranscript ? effectiveLivePaneHeight : nil,
                            maxHeight: showsTranscript ? effectiveLivePaneHeight : .infinity
                        )
                        .layoutPriority(showsTranscript ? 0 : 1)
                        .id(session.id)
                    }

                    NativePaneDropTarget(
                        targetSessionID: sessionID,
                        allowsSelfEdgeDrop: allowsSelfEdgeDrop,
                        onRegionChange: { region in
                            activeDropRegion = region
                        },
                        onDrop: { payload, region in
                            guard let sourceSessionID = payload.workspacePaneSessionID else {
                                return
                            }
                            withAnimation(.snappy(duration: 0.22)) {
                                model.dropWorkspacePane(
                                    sourceSessionID: sourceSessionID,
                                    ontoWorkspace: workspaceID,
                                    targetSessionID: sessionID,
                                    region: region
                                )
                            }
                        }
                    )
                    .zIndex(10)

                    if let activeDropRegion {
                        WorkspaceDropPreview(activeRegion: activeDropRegion)
                            .allowsHitTesting(false)
                            .zIndex(20)
                    }

                    if let previewLivePaneHeight {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.9))
                            .frame(height: 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, previewLivePaneHeight)
                            .allowsHitTesting(false)
                            .zIndex(30)
                    }
                }
                .overlay {
                    if Self.showsSelectionOutline(
                        isSelected: showsHeader && sessionID == model.selectedSessionID,
                        isCompactMode: model.isCompactMode
                    ) {
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(
                    of: [.apexTermTerminalTab],
                    delegate: WorkspacePaneDropDelegate(
                        size: proxy.size,
                        region: $activeDropRegion
                    ) { payload, region in
                        withAnimation(.snappy(duration: 0.22)) {
                            if let source = payload.mainTabReference {
                                model.dropMainTab(
                                    source,
                                    ontoWorkspace: workspaceID,
                                    targetSessionID: sessionID,
                                    region: region
                                )
                            } else if let sourceSessionID = payload.workspacePaneSessionID {
                                model.dropWorkspacePane(
                                    sourceSessionID: sourceSessionID,
                                    ontoWorkspace: workspaceID,
                                    targetSessionID: sessionID,
                                    region: region
                                )
                            }
                        }
                    }
                )
            }
        } else {
            ContentUnavailableView(
                "Missing Session",
                systemImage: "exclamationmark.triangle",
                description: Text("The workspace references an unavailable session.")
            )
        }
    }

    private func commandPresetMenu(sessionID: UUID) -> some View {
        Menu {
            if model.commandPresets.isEmpty {
                Button("定型コマンドを設定…") {
                    model.settingsTab = .commands
                    model.isSettingsPresented = true
                }
            } else {
                ForEach(model.commandPresets) { preset in
                    Button {
                        model.executeCommandPreset(preset, sessionID: sessionID)
                    } label: {
                        Text(preset.name)
                    }
                    .help(preset.command)
                }

                Divider()

                Button("定型コマンドを管理…") {
                    model.settingsTab = .commands
                    model.isSettingsPresented = true
                }
            }
        } label: {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("定型コマンドを送信")
        .accessibilityLabel("定型コマンドを送信")
    }

    private func splitView(
        axis: SplitNode.SplitAxis,
        ratio: Double,
        first: SplitNode,
        second: SplitNode
    ) -> some View {
        let clampedRatio = min(max(ratio, 0.05), 0.95)
        let layoutKey = splitLayoutKey(
            axis: axis,
            ratio: clampedRatio,
            first: first,
            second: second
        )
        let firstView = AnyView(
            SplitTreeView(workspaceID: workspaceID, node: first, model: model)
                .frame(
                    minWidth: axis == .vertical ? 120 : nil,
                    minHeight: axis == .horizontal ? 100 : nil
                )
        )
        let secondView = AnyView(
            SplitTreeView(workspaceID: workspaceID, node: second, model: model)
                .frame(
                    minWidth: axis == .vertical ? 120 : nil,
                    minHeight: axis == .horizontal ? 100 : nil
                )
        )
        return NativeRatioSplitView(
            isVertical: axis == .vertical,
            ratio: CGFloat(clampedRatio),
            layoutKey: layoutKey,
            first: firstView,
            second: secondView
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func splitLayoutKey(
        axis: SplitNode.SplitAxis,
        ratio: Double,
        first: SplitNode,
        second: SplitNode
    ) -> String {
        let axisKey = axis == .vertical ? "v" : "h"
        let firstIDs = SplitTreeOperations.sessionIDs(in: first)
            .map(\.uuidString)
            .joined(separator: ",")
        let secondIDs = SplitTreeOperations.sessionIDs(in: second)
            .map(\.uuidString)
            .joined(separator: ",")
        return "\(axisKey):\(ratio):\(SplitTreeOperations.columnCount(in: first)):\(firstIDs)|\(SplitTreeOperations.columnCount(in: second)):\(secondIDs)"
    }

    private func livePaneHeightKey(for sessionID: UUID) -> String {
        "apexterm.terminal.livePaneHeight.\(sessionID.uuidString)"
    }

    private func persistedLivePaneHeight(for sessionID: UUID) -> Double {
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: livePaneHeightKey(for: sessionID)) as? Double {
            return value
        }
        if let legacyValue = defaults.object(
            forKey: "apexterm.terminal.livePaneHeight"
        ) as? Double {
            return legacyValue
        }
        return 92
    }

    private func remoteProfile(for kind: SessionKind) -> SSHHostProfile? {
        switch kind {
        case .local, .localTmux:
            nil
        case let .ssh(host), let .tmux(host, _):
            model.remoteProfile(alias: host)
        }
    }

    private func kindLabel(_ kind: SessionKind) -> String {
        switch kind {
        case .local:
            "LOCAL"
        case .localTmux:
            "TMUX"
        case .ssh:
            "SSH"
        case .tmux:
            "TMUX"
        }
    }

    private func statusColor(for state: SessionState) -> Color {
        switch state {
        case .attached:
            .green
        case .starting, .reconnecting:
            .orange
        case .failed, .exited:
            .red
        case .created, .detached:
            .secondary
        }
    }
}

private struct TerminalLivePaneResizeHandle: NSViewRepresentable {
    let sessionID: UUID
    let currentHeight: CGFloat
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let onResizeChanged: (CGFloat) -> Void
    let onResizeEnded: (CGFloat) -> Void

    func makeNSView(context: Context) -> TerminalLivePaneResizeHandleView {
        let view = TerminalLivePaneResizeHandleView(frame: .zero)
        configure(view)
        return view
    }

    func updateNSView(
        _ nsView: TerminalLivePaneResizeHandleView,
        context: Context
    ) {
        configure(nsView)
    }

    private func configure(_ view: TerminalLivePaneResizeHandleView) {
        view.configure(
            sessionID: sessionID,
            currentHeight: currentHeight,
            minimumHeight: minimumHeight,
            maximumHeight: maximumHeight,
            onResizeChanged: onResizeChanged,
            onResizeEnded: onResizeEnded
        )
    }
}

@MainActor
private final class TerminalLivePaneResizeHandleView: NSView {
    private var sessionID = UUID()
    private var currentHeight: CGFloat = 92
    private var minimumHeight: CGFloat = 76
    private var maximumHeight: CGFloat = 420
    private var onResizeChanged: (CGFloat) -> Void = { _ in }
    private var onResizeEnded: (CGFloat) -> Void = { _ in }
    private var dragStartHeight: CGFloat?
    private var dragStartMouseY: CGFloat?
    private var pendingResizeHeight: CGFloat?
    private var resizeUpdateScheduled = false
    private var lastReportedHeight: CGFloat?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isDragging = false
    private var probeEvents: [String] = []
    private let probeFileURL = ProcessInfo.processInfo.environment[
        "APEXTERM_LIVE_PANE_RESIZE_PROBE_FILE"
    ].flatMap { value in
        value.isEmpty ? nil : URL(fileURLWithPath: value)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Resize live terminal area")
        setAccessibilityHelp("Drag vertically to resize the live terminal area")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 12)
    }

    func configure(
        sessionID: UUID,
        currentHeight: CGFloat,
        minimumHeight: CGFloat,
        maximumHeight: CGFloat,
        onResizeChanged: @escaping (CGFloat) -> Void,
        onResizeEnded: @escaping (CGFloat) -> Void
    ) {
        self.sessionID = sessionID
        if !isDragging {
            self.currentHeight = currentHeight
        }
        self.minimumHeight = minimumHeight
        self.maximumHeight = maximumHeight
        self.onResizeChanged = onResizeChanged
        self.onResizeEnded = onResizeEnded
        setAccessibilityIdentifier(
            "live-terminal-resize-handle-\(sessionID.uuidString)"
        )
        setAccessibilityValue("\(Int(currentHeight.rounded())) points")
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        if probeFileURL != nil {
            DispatchQueue.main.async { [weak self] in
                self?.recordProbe()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        recordProbe()
    }

    override func layout() {
        super.layout()
        recordProbe()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
        NSCursor.resizeUpDown.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
        if !isDragging {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStartHeight = currentHeight
        dragStartMouseY = NSEvent.mouseLocation.y
        isDragging = true
        needsDisplay = true
        recordProbe(event: "down")
        NSCursor.resizeUpDown.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartHeight, let dragStartMouseY else { return }
        let delta = NSEvent.mouseLocation.y - dragStartMouseY
        let height = clamped(dragStartHeight + delta)
        scheduleResizeUpdate(height)
        recordProbe(event: "drag:\(Int(height.rounded()))")
        NSCursor.resizeUpDown.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStartHeight, let dragStartMouseY else { return }
        let delta = NSEvent.mouseLocation.y - dragStartMouseY
        let finalHeight = clamped(dragStartHeight + delta)
        self.dragStartHeight = nil
        self.dragStartMouseY = nil
        pendingResizeHeight = nil
        isDragging = false
        currentHeight = finalHeight
        lastReportedHeight = finalHeight
        needsDisplay = true
        onResizeEnded(finalHeight)
        recordProbe(event: "up:\(Int(finalHeight.rounded()))")
        if isHovering {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1).fill()

        let opacity: CGFloat = isHovering || isDragging ? 0.72 : 0.45
        NSColor.secondaryLabelColor.withAlphaComponent(opacity).setFill()
        let capsuleRect = NSRect(
            x: max(0, bounds.midX - 19),
            y: bounds.midY - 1,
            width: min(38, bounds.width),
            height: 2
        )
        NSBezierPath(roundedRect: capsuleRect, xRadius: 1, yRadius: 1).fill()
    }

    private func clamped(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximumHeight)
    }

    private func scheduleResizeUpdate(_ height: CGFloat) {
        if let lastReportedHeight, abs(lastReportedHeight - height) < 0.75 {
            return
        }
        pendingResizeHeight = height
        guard !resizeUpdateScheduled else { return }
        resizeUpdateScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 / 30.0)) { [weak self] in
            guard let self else { return }
            self.resizeUpdateScheduled = false
            guard self.isDragging, let pending = self.pendingResizeHeight else { return }
            self.pendingResizeHeight = nil
            self.lastReportedHeight = pending
            self.onResizeChanged(pending)
        }
    }

    private func recordProbe(event: String? = nil) {
        guard let probeFileURL, let window else { return }
        if let event {
            probeEvents.append(event)
            if probeEvents.count > 40 {
                probeEvents.removeFirst(probeEvents.count - 40)
            }
        }

        let windowRect = convert(bounds, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(screenRect) })
            ?? NSScreen.main
        guard let screen else { return }

        let payload: [String: Any] = [
            "sessionID": sessionID.uuidString,
            "currentHeight": currentHeight,
            "frame": [
                "x": screenRect.minX,
                "y": screen.frame.maxY - screenRect.maxY,
                "width": screenRect.width,
                "height": screenRect.height
            ],
            "events": probeEvents
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: probeFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: probeFileURL, options: .atomic)
    }
}
