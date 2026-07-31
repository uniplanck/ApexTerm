import ApexTermCore
import AppKit
import SwiftUI

struct UniversalSearchView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var scope: UniversalSearchScope = .all
    @State private var results: [UniversalSearchItem] = []
    @State private var snapshot: UniversalSearchSnapshot?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var snapshotLoadCount = 0
    @State private var isRunningProbe = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            scopeBar
            Divider()
            searchContent
        }
        .frame(minWidth: 680, idealWidth: 820, minHeight: 500, idealHeight: 620)
        .accessibilityIdentifier("universal-search-view")
        .onAppear {
            searchFocused = true
            scheduleSearch(immediate: true, refreshSnapshot: true)
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onChange(of: query) { _, _ in
            guard !isRunningProbe else { return }
            scheduleSearch()
        }
        .onChange(of: scope) { _, _ in
            guard !isRunningProbe else { return }
            scheduleSearch(immediate: true)
        }
        .task {
            await runProbeIfRequested()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField(
                "Search workspaces, terminals, commands, and agents",
                text: $query
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($searchFocused)
            .accessibilityIdentifier("universal-search-field")
            .onSubmit {
                guard let first = results.first else { return }
                activate(first)
            }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching")
            } else {
                Text("\(results.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(results.count) results")
            }

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("universal-search-close")
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
    }

    private var scopeBar: some View {
        HStack(spacing: 12) {
            Picker("Search scope", selection: $scope) {
                ForEach(UniversalSearchScope.allCases, id: \.self) { value in
                    Text(scopeTitle(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)
            .accessibilityIdentifier("universal-search-scope")

            Spacer()

            Text("Return opens the first result")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
    }

    @ViewBuilder
    private var searchContent: some View {
        if isSearching && results.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching ApexTerm…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Nothing to search yet",
                    systemImage: "sparkle.magnifyingglass",
                    description: Text(
                        "Workspaces, command history, and agent activity will appear here."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(results) { item in
                        UniversalSearchRow(item: item) {
                            activate(item)
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    private func scheduleSearch(
        immediate: Bool = false,
        refreshSnapshot: Bool = false
    ) {
        searchTask?.cancel()
        let requestID = UUID()
        self.requestID = requestID
        isSearching = true
        let query = self.query
        let scope = self.scope

        searchTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }

            let resolvedSnapshot: UniversalSearchSnapshot
            if refreshSnapshot || snapshot == nil {
                let loadedSnapshot = await model.universalSearchSnapshot()
                guard !Task.isCancelled else { return }
                snapshot = loadedSnapshot
                snapshotLoadCount += 1
                resolvedSnapshot = loadedSnapshot
            } else if let snapshot {
                resolvedSnapshot = snapshot
            } else {
                return
            }

            let resolved = await Task.detached(priority: .userInitiated) {
                UniversalSearchEngine().search(
                    query,
                    in: resolvedSnapshot,
                    scope: scope,
                    limit: 100
                )
            }.value
            guard !Task.isCancelled, self.requestID == requestID else { return }

            results = resolved
            isSearching = false
        }
    }

    @MainActor
    private func runProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_UNIVERSAL_SEARCH_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        isRunningProbe = true
        defer { isRunningProbe = false }

        var rootProbeReady = false
        for _ in 0..<400 {
            let rootResult = try? String(
                contentsOfFile: outputPath,
                encoding: .utf8
            )
            rootProbeReady = rootResult?.contains("root_probe_ready=1") == true
            if rootProbeReady { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard rootProbeReady else {
            appendProbeResult(
                [
                    "root_probe_ready=0",
                    "probe_complete=1"
                ],
                to: outputPath
            )
            return
        }

        for _ in 0..<300 {
            if snapshot != nil, !isSearching { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        guard var probeSnapshot = snapshot else {
            appendProbeResult(
                [
                    "snapshot_loaded=0",
                    "probe_complete=1"
                ],
                to: outputPath
            )
            return
        }

        probeSnapshot.agentEvents.removeAll {
            $0.reference == "probe/universal-search"
        }
        probeSnapshot.agentEvents.append(
            UniversalAgentEvent(
                id: UUID(),
                reference: "probe/universal-search",
                title: "Universal Search Agent Event",
                status: "waitingApproval",
                summary: "Universal Search probe event",
                updatedAt: Date(),
                conversationURL: nil
            )
        )
        snapshot = probeSnapshot

        let all = await probeSearch("", scope: .all)
        let workspace = await probeSearch(
            "Universal Search Workspace",
            scope: .all
        )
        let session = await probeSearch(
            "Universal Search Session",
            scope: .all
        )
        let command = await probeSearch(
            "universal-search-command",
            scope: .all,
            immediate: false
        )
        let agentChat = await probeSearch("Agent Chat", scope: .all)
        let agentEvent = await probeSearch(
            "Universal Search Agent Event",
            scope: .all
        )
        let workspaceScope = await probeSearch("", scope: .workspaces)
        let commandScope = await probeSearch("", scope: .commands)
        let agentScope = await probeSearch("", scope: .agents)
        let empty = await probeSearch(
            "__universal_search_no_match__",
            scope: .all
        )

        let allKinds = Set(all.results.map(\.kind))
        let searchCompleted = [
            all.completed,
            workspace.completed,
            session.completed,
            command.completed,
            agentChat.completed,
            agentEvent.completed,
            workspaceScope.completed,
            commandScope.completed,
            agentScope.completed,
            empty.completed
        ].allSatisfy { $0 }
        let loadingObserved = [
            all.loadingObserved,
            workspace.loadingObserved,
            session.loadingObserved,
            command.loadingObserved,
            agentChat.loadingObserved,
            agentEvent.loadingObserved,
            workspaceScope.loadingObserved,
            commandScope.loadingObserved,
            agentScope.loadingObserved,
            empty.loadingObserved
        ].contains(true)
        let workspaceScopePassed = workspaceScope.results.allSatisfy {
            $0.kind == .workspace || $0.kind == .session
        }
        let commandScopePassed = !commandScope.results.isEmpty
            && commandScope.results.allSatisfy { $0.kind == .command }
        let agentScopePassed = !agentScope.results.isEmpty
            && agentScope.results.allSatisfy {
                $0.kind == .agentChat || $0.kind == .agentEvent
            }
        let commandItem = command.results.first { $0.kind == .command }

        let preflightLines = [
            "view_presented=1",
            "field_focused=\(searchFocused ? 1 : 0)",
            "snapshot_loaded=1",
            "snapshot_reused=\(snapshotLoadCount == 1 ? 1 : 0)",
            "loading_state=\(loadingObserved ? 1 : 0)",
            "search_completed=\(searchCompleted ? 1 : 0)",
            "all_kinds=\(Set(UniversalSearchItemKind.allCases).isSubset(of: allKinds) ? 1 : 0)",
            "workspace_result=\(workspace.results.first?.kind == .workspace ? 1 : 0)",
            "session_result=\(session.results.first?.kind == .session ? 1 : 0)",
            "command_result=\(commandItem == nil ? 0 : 1)",
            "agent_chat_result=\(agentChat.results.contains { $0.kind == .agentChat } ? 1 : 0)",
            "agent_event_result=\(agentEvent.results.first?.kind == .agentEvent ? 1 : 0)",
            "workspace_scope=\(workspaceScopePassed ? 1 : 0)",
            "command_scope=\(commandScopePassed ? 1 : 0)",
            "agent_scope=\(agentScopePassed ? 1 : 0)",
            "empty_state=\(empty.results.isEmpty ? 1 : 0)",
            "focus_state=\(searchFocused ? 1 : 0)"
        ]

        guard let commandItem,
              case let .command(_, expectedSessionID) = commandItem.target else {
            appendProbeResult(
                preflightLines + [
                    "universal_dismissed=0",
                    "command_history_presented=0",
                    "command_history_view=0",
                    "command_history_query=0",
                    "command_history_session=0",
                    "context_cleared_after_dismiss=0",
                    "probe_complete=1"
                ],
                to: outputPath
            )
            return
        }

        let expectedQuery = commandItem.title
        Task { @MainActor in
            var historyViewPresented = false
            for _ in 0..<300 {
                historyViewPresented = findAccessibilityView(
                    identifier: "command-history-search-view"
                ) != nil
                if model.isCommandHistorySearchPresented,
                   historyViewPresented {
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }

            let universalDismissed = !model.isUniversalSearchPresented
            let historyPresented = model.isCommandHistorySearchPresented
            let queryPassed = model.commandHistorySearchInitialQuery == expectedQuery
            let sessionPassed = model.commandHistorySearchSessionID == expectedSessionID

            model.isCommandHistorySearchPresented = false
            for _ in 0..<200 {
                if !model.isCommandHistorySearchPresented,
                   model.commandHistorySearchInitialQuery.isEmpty,
                   model.commandHistorySearchSessionID == nil {
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            let contextCleared = model.commandHistorySearchInitialQuery.isEmpty
                && model.commandHistorySearchSessionID == nil

            appendProbeResult(
                preflightLines + [
                    "universal_dismissed=\(universalDismissed ? 1 : 0)",
                    "command_history_presented=\(historyPresented ? 1 : 0)",
                    "command_history_view=\(historyViewPresented ? 1 : 0)",
                    "command_history_query=\(queryPassed ? 1 : 0)",
                    "command_history_session=\(sessionPassed ? 1 : 0)",
                    "context_cleared_after_dismiss=\(contextCleared ? 1 : 0)",
                    "probe_complete=1"
                ],
                to: outputPath
            )
        }
        activate(commandItem)
    }

    @MainActor
    private func probeSearch(
        _ value: String,
        scope: UniversalSearchScope,
        immediate: Bool = true
    ) async -> (
        results: [UniversalSearchItem],
        loadingObserved: Bool,
        completed: Bool
    ) {
        query = value
        self.scope = scope
        scheduleSearch(immediate: immediate)
        let loadingObserved = isSearching
        for _ in 0..<300 {
            if !isSearching {
                return (results, loadingObserved, true)
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return (results, loadingObserved, false)
    }

    @MainActor
    private func findAccessibilityView(identifier: String) -> NSView? {
        for window in NSApp.windows {
            guard let contentView = window.contentView else { continue }
            if let match = findAccessibilityView(
                identifier: identifier,
                in: contentView
            ) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func findAccessibilityView(
        identifier: String,
        in view: NSView
    ) -> NSView? {
        if view.identifier?.rawValue == identifier
            || view.accessibilityIdentifier() == identifier {
            return view
        }
        for subview in view.subviews {
            if let match = findAccessibilityView(
                identifier: identifier,
                in: subview
            ) {
                return match
            }
        }
        return nil
    }

    private func appendProbeResult(_ lines: [String], to path: String) {
        var existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        if !existing.isEmpty, !existing.hasSuffix("\n") {
            existing += "\n"
        }
        existing += lines.joined(separator: "\n") + "\n"
        try? Data(existing.utf8).write(
            to: URL(fileURLWithPath: path),
            options: [.atomic]
        )
    }

    private func activate(_ item: UniversalSearchItem) {
        searchTask?.cancel()
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            model.activateUniversalSearchItem(item)
        }
    }

    private func scopeTitle(_ scope: UniversalSearchScope) -> String {
        switch scope {
        case .all: "All"
        case .workspaces: "Workspaces"
        case .commands: "Commands"
        case .agents: "Agents"
        }
    }
}

private struct UniversalSearchRow: View {
    let item: UniversalSearchItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 13.5, weight: .medium))
                            .lineLimit(2)
                        Text(item.kind.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }

                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 12)

                if let timestamp = item.timestamp {
                    Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.trailing)
                }

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isHovered
                            ? Color.accentColor.opacity(0.10)
                            : Color(nsColor: .controlBackgroundColor)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(item.kind.title): \(item.title)")
        .accessibilityHint("Open this result")
    }

    private var iconName: String {
        switch item.kind {
        case .workspace: "square.stack.3d.up"
        case .session: "terminal"
        case .command: "chevron.left.forwardslash.chevron.right"
        case .agentChat: "bubble.left.and.bubble.right"
        case .agentEvent: "bolt.horizontal.circle"
        }
    }
}
