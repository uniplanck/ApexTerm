import ApexTermCore
import AppKit
import SwiftUI

struct CommandTimelineView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot = CommandTimelineSnapshot(
        commands: [],
        agentEvents: []
    )
    @State private var query = ""
    @State private var filter: CommandTimelineFilter = .all
    @State private var selectedSessionOnly = false
    @State private var exportPrivacy: CommandTimelineExportPrivacy = .redacted
    @State private var selectedEntryID: String?
    @State private var isLoading = true
    @State private var exportMessage: String?
    @FocusState private var searchFocused: Bool

    private let engine = CommandTimelineEngine()
    private let exporter = CommandTimelineExporter()

    private var entries: [CommandTimelineEntry] {
        engine.entries(
            in: snapshot,
            query: query,
            filter: filter,
            sessionID: selectedSessionOnly ? model.selectedSessionID : nil
        )
    }

    private var selectedEntry: CommandTimelineEntry? {
        if let selectedEntryID,
           let selected = entries.first(where: { $0.id == selectedEntryID }) {
            return selected
        }
        return entries.first
    }

    private var groups: [(day: Date, entries: [CommandTimelineEntry])] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: entries) {
            calendar.startOfDay(for: $0.timestamp)
        }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day, default: []])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            content
            if let exportMessage {
                Divider()
                Text(exportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
            }
        }
        .frame(minWidth: 940, minHeight: 620)
        .background(CommandTimelineProbeView(identifier: "command-timeline-view"))
        .accessibilityIdentifier("command-timeline-view")
        .task {
            await loadSnapshot()
            await runProbeIfRequested()
        }
        .onChange(of: entries.map(\.id)) { _, ids in
            if let selectedEntryID, ids.contains(selectedEntryID) { return }
            self.selectedEntryID = ids.first
        }
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField("Search commands and Agent events", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .accessibilityIdentifier("command-timeline-search-field")
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("\(entries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Close") { dismiss() }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("Filter", selection: $filter) {
                Text("All").tag(CommandTimelineFilter.all)
                Text("Commands").tag(CommandTimelineFilter.commands)
                Text("Agents").tag(CommandTimelineFilter.agents)
                Text("Failures").tag(CommandTimelineFilter.failures)
            }
            .pickerStyle(.segmented)
            .frame(width: 390)
            .accessibilityIdentifier("command-timeline-filter")

            Toggle("Selected terminal only", isOn: $selectedSessionOnly)
                .toggleStyle(.checkbox)
                .disabled(model.selectedSessionID == nil)
                .accessibilityIdentifier("command-timeline-session-toggle")

            Spacer()

            Picker("Export privacy", selection: $exportPrivacy) {
                ForEach(CommandTimelineExportPrivacy.allCases, id: \.self) { privacy in
                    Text(privacy.title).tag(privacy)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)
            .accessibilityIdentifier("command-timeline-export-privacy")

            Button {
                copyExport()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(entries.isEmpty)

            Button {
                saveExport()
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .disabled(entries.isEmpty)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading command and Agent events…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("command-timeline-loading")
        } else if entries.isEmpty {
            ContentUnavailableView(
                "No timeline entries",
                systemImage: "clock.badge.questionmark",
                description: Text(query.isEmpty
                    ? "Run a command or Agent job to create timeline history."
                    : "No command or Agent event matches this search.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("command-timeline-empty")
        } else {
            HSplitView {
                timelineList
                    .frame(minWidth: 420, idealWidth: 520)
                detailView
                    .frame(minWidth: 360, idealWidth: 460)
            }
        }
    }

    private var timelineList: some View {
        List(selection: $selectedEntryID) {
            ForEach(groups, id: \.day) { group in
                Section(group.day.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(group.entries) { entry in
                        timelineRow(entry)
                            .tag(entry.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .background(CommandTimelineProbeView(identifier: "command-timeline-list"))
        .accessibilityIdentifier("command-timeline-list")
    }

    private func timelineRow(_ entry: CommandTimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: entry))
                .foregroundStyle(entry.isFailure ? Color.red : Color.secondary)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 12.5, weight: .medium, design: entry.kind == .command ? .monospaced : .default))
                    .lineLimit(2)
                Text(entry.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("command-timeline-entry-\(entry.id)")
    }

    @ViewBuilder
    private var detailView: some View {
        if let entry = selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: entry))
                            .font(.title2)
                            .foregroundStyle(entry.isFailure ? Color.red : Color.accentColor)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.title)
                                .font(.headline)
                                .textSelection(.enabled)
                            Text(entry.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text(entry.timestamp.formatted(date: .complete, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button("Open") {
                            model.activateCommandTimelineEntry(entry)
                        }
                        .keyboardShortcut(.defaultAction)

                        Button("Copy entry") {
                            let text = exporter.markdown(
                                entries: [entry],
                                privacy: exportPrivacy
                            )
                            ClipboardWriter.copy(text)
                            exportMessage = "Copied 1 entry using \(exportPrivacy.title.lowercased()) privacy."
                        }
                    }

                    Divider()

                    if entry.detail.isEmpty {
                        Text("No captured detail")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(entry.detail)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if exportPrivacy == .full {
                        Label(
                            "Full export can include secrets, tokens, private paths, and raw command output.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                .padding(18)
            }
            .background(CommandTimelineProbeView(identifier: "command-timeline-detail"))
            .accessibilityIdentifier("command-timeline-detail")
        } else {
            ContentUnavailableView("Select an entry", systemImage: "cursorarrow.click")
        }
    }

    private func loadSnapshot() async {
        isLoading = true
        snapshot = await model.commandTimelineSnapshot()
        selectedEntryID = entries.first?.id
        isLoading = false
    }

    private func copyExport() {
        let text = exporter.markdown(entries: entries, privacy: exportPrivacy)
        ClipboardWriter.copy(text)
        exportMessage = "Copied \(entries.count) entries using \(exportPrivacy.title.lowercased()) privacy."
    }

    private func saveExport() {
        let panel = NSSavePanel()
        panel.title = "Export Command Timeline"
        panel.nameFieldStringValue = "ApexTerm-Command-Timeline.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = exporter.markdown(entries: entries, privacy: exportPrivacy)
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Saved \(entries.count) entries to \(url.lastPathComponent)."
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func runProbeIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["APEXTERM_COMMAND_TIMELINE_PROBE_FILE"],
              !outputPath.isEmpty else {
            return
        }

        var rootProbeReady = false
        for _ in 0..<400 {
            let rootResult = try? String(contentsOfFile: outputPath, encoding: .utf8)
            rootProbeReady = rootResult?.contains("root_probe_ready=1") == true
            if rootProbeReady { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard rootProbeReady else {
            appendProbeResult(["root_probe_ready=0", "probe_complete=1"], to: outputPath)
            return
        }

        var probeSnapshot = snapshot
        probeSnapshot.agentEvents.removeAll { $0.reference.hasPrefix("probe/command-timeline") }
        probeSnapshot.agentEvents.append(contentsOf: [
            UniversalAgentEvent(
                id: UUID(),
                reference: "probe/command-timeline-running",
                title: "Timeline Agent Running",
                status: "running",
                summary: "Agent timeline detail",
                updatedAt: Date().addingTimeInterval(1)
            ),
            UniversalAgentEvent(
                id: UUID(),
                reference: "probe/command-timeline-failed",
                title: "Timeline Agent Failed",
                status: "failed",
                summary: "TOKEN=timeline-agent-secret",
                updatedAt: Date().addingTimeInterval(2)
            )
        ])
        snapshot = probeSnapshot
        try? await Task.sleep(for: .milliseconds(80))

        let all = engine.entries(in: probeSnapshot)
        let commands = engine.entries(in: probeSnapshot, filter: .commands)
        let agents = engine.entries(in: probeSnapshot, filter: .agents)
        let failures = engine.entries(in: probeSnapshot, filter: .failures)
        let search = engine.entries(in: probeSnapshot, query: "timeline-failure-command")
        let selectedSession = engine.entries(
            in: probeSnapshot,
            sessionID: model.selectedSessionID
        )
        let redacted = exporter.markdown(entries: all, privacy: .redacted)
        let metadata = exporter.markdown(entries: all, privacy: .metadataOnly)
        let full = exporter.markdown(entries: all, privacy: .full)
        let commandEntry = commands.first { $0.title.contains("timeline-failure-command") }
        let viewPresented = findAccessibilityView(identifier: "command-timeline-view") != nil
        let listPresented = findAccessibilityView(identifier: "command-timeline-list") != nil
        let detailPresented = findAccessibilityView(identifier: "command-timeline-detail") != nil

        let preflight = [
            "view_presented=\(viewPresented ? 1 : 0)",
            "field_focused=\(searchFocused ? 1 : 0)",
            "snapshot_loaded=\(!probeSnapshot.commands.isEmpty ? 1 : 0)",
            "all_kinds=\(Set(all.map(\.kind)) == Set(CommandTimelineKind.allCases) ? 1 : 0)",
            "command_filter=\(!commands.isEmpty && commands.allSatisfy { $0.kind == .command } ? 1 : 0)",
            "agent_filter=\(!agents.isEmpty && agents.allSatisfy { $0.kind == .agent } ? 1 : 0)",
            "failure_filter=\(failures.count >= 2 && failures.allSatisfy(\.isFailure) ? 1 : 0)",
            "search_result=\(search.count == 1 && search.first?.kind == .command ? 1 : 0)",
            "selected_session=\(!selectedSession.isEmpty && selectedSession.allSatisfy { $0.kind == .command && $0.sessionID == model.selectedSessionID } ? 1 : 0)",
            "list_presented=\(listPresented ? 1 : 0)",
            "detail_presented=\(detailPresented ? 1 : 0)",
            "redacted_export=\(!redacted.contains("timeline-secret") && redacted.contains("<redacted>") ? 1 : 0)",
            "metadata_export=\(!metadata.contains("timeline-failure-command") && metadata.contains("Command content omitted") ? 1 : 0)",
            "full_export=\(full.contains("timeline-secret-token") && full.contains("timeline-agent-secret") ? 1 : 0)"
        ]

        guard let commandEntry else {
            appendProbeResult(
                preflight + [
                    "timeline_dismissed=0",
                    "command_history_presented=0",
                    "command_history_view=0",
                    "command_history_query=0",
                    "command_history_session=0",
                    "probe_complete=1"
                ],
                to: outputPath
            )
            return
        }

        appendProbeResult(preflight, to: outputPath)
        Task { @MainActor in
            model.activateCommandTimelineEntry(commandEntry)
            var historyViewPresented = false
            for _ in 0..<300 {
                historyViewPresented = findAccessibilityView(
                    identifier: "command-history-search-view"
                ) != nil
                if model.isCommandHistorySearchPresented, historyViewPresented { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            let timelineDismissed = !model.isCommandTimelinePresented
            let historyPresented = model.isCommandHistorySearchPresented
            let queryPassed = model.commandHistorySearchInitialQuery.contains("timeline-failure-command")
            let sessionPassed = model.commandHistorySearchSessionID == model.selectedSessionID
            model.isCommandHistorySearchPresented = false
            appendProbeResult(
                [
                    "timeline_dismissed=\(timelineDismissed ? 1 : 0)",
                    "command_history_presented=\(historyPresented ? 1 : 0)",
                    "command_history_view=\(historyViewPresented ? 1 : 0)",
                    "command_history_query=\(queryPassed ? 1 : 0)",
                    "command_history_session=\(sessionPassed ? 1 : 0)",
                    "probe_complete=1"
                ],
                to: outputPath
            )
        }
    }

    @MainActor
    private func findAccessibilityView(identifier: String) -> NSView? {
        for window in NSApp.windows {
            guard let contentView = window.contentView else { continue }
            if let match = findAccessibilityView(identifier: identifier, in: contentView) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func findAccessibilityView(identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier
            || view.accessibilityIdentifier() == identifier {
            return view
        }
        for subview in view.subviews {
            if let match = findAccessibilityView(identifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }

    private func appendProbeResult(_ lines: [String], to path: String) {
        var existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        if !existing.isEmpty, !existing.hasSuffix("\n") { existing += "\n" }
        existing += lines.joined(separator: "\n") + "\n"
        try? Data(existing.utf8).write(
            to: URL(fileURLWithPath: path),
            options: [.atomic]
        )
    }

    private func icon(for entry: CommandTimelineEntry) -> String {
        switch entry.kind {
        case .command:
            entry.isFailure ? "terminal.fill" : "terminal"
        case .agent:
            entry.isFailure ? "exclamationmark.bubble.fill" : "bubble.left.and.text.bubble.right"
        }
    }
}

private struct CommandTimelineProbeView: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityElement(true)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
