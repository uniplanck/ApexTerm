import Foundation

public enum CommandTimelineKind: String, Codable, CaseIterable, Hashable, Sendable {
    case command
    case agent

    public var title: String {
        switch self {
        case .command: "Command"
        case .agent: "Agent"
        }
    }
}

public enum CommandTimelineFilter: String, Codable, CaseIterable, Hashable, Sendable {
    case all
    case commands
    case agents
    case failures
}

public enum CommandTimelineExportPrivacy: String, Codable, CaseIterable, Hashable, Sendable {
    case metadataOnly
    case redacted
    case full

    public var title: String {
        switch self {
        case .metadataOnly: "Metadata only"
        case .redacted: "Redacted"
        case .full: "Full content"
        }
    }
}

public enum CommandTimelineTarget: Codable, Equatable, Sendable {
    case command(recordID: UUID, sessionID: UUID)
    case agentJob(reference: String, conversationURL: URL?)
}

public struct CommandTimelineEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: CommandTimelineKind
    public var title: String
    public var subtitle: String
    public var detail: String
    public var status: String
    public var timestamp: Date
    public var sessionID: UUID?
    public var target: CommandTimelineTarget
    public var isFailure: Bool

    public init(
        id: String,
        kind: CommandTimelineKind,
        title: String,
        subtitle: String,
        detail: String,
        status: String,
        timestamp: Date,
        sessionID: UUID? = nil,
        target: CommandTimelineTarget,
        isFailure: Bool
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.status = status
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.target = target
        self.isFailure = isFailure
    }
}

public struct CommandTimelineSnapshot: Sendable {
    public var commands: [CommandExecutionRecord]
    public var agentEvents: [UniversalAgentEvent]
    public var sessionTitles: [UUID: String]

    public init(
        commands: [CommandExecutionRecord],
        agentEvents: [UniversalAgentEvent],
        sessionTitles: [UUID: String] = [:]
    ) {
        self.commands = commands
        self.agentEvents = agentEvents
        self.sessionTitles = sessionTitles
    }
}

public struct CommandTimelineEngine: Sendable {
    public init() {}

    public func entries(
        in snapshot: CommandTimelineSnapshot,
        query: String = "",
        filter: CommandTimelineFilter = .all,
        sessionID: UUID? = nil,
        limit: Int = 1_000
    ) -> [CommandTimelineEntry] {
        let normalizedQuery = normalize(query)
        var result: [CommandTimelineEntry] = []

        if filter != .agents {
            result.append(contentsOf: snapshot.commands.compactMap { record in
                guard sessionID == nil || record.sessionID == sessionID else { return nil }
                let title = record.command.isEmpty ? "(empty command)" : record.command
                let entry = CommandTimelineEntry(
                    id: "command:\(record.id.uuidString)",
                    kind: .command,
                    title: title,
                    subtitle: "\(snapshot.sessionTitles[record.sessionID] ?? "Terminal") · exit \(record.exitCode)",
                    detail: record.output,
                    status: record.exitCode == 0 ? "succeeded" : "failed",
                    timestamp: record.finishedAt,
                    sessionID: record.sessionID,
                    target: .command(recordID: record.id, sessionID: record.sessionID),
                    isFailure: record.exitCode != 0
                )
                return matches(entry, query: normalizedQuery, filter: filter) ? entry : nil
            })
        }

        if filter != .commands, sessionID == nil {
            result.append(contentsOf: snapshot.agentEvents.compactMap { event in
                let failure = Self.failureAgentStatuses.contains(event.status.lowercased())
                let entry = CommandTimelineEntry(
                    id: "agent:\(event.id.uuidString)",
                    kind: .agent,
                    title: event.title,
                    subtitle: "\(event.status) · \(event.reference)",
                    detail: event.summary,
                    status: event.status,
                    timestamp: event.updatedAt ?? .distantPast,
                    target: .agentJob(reference: event.reference, conversationURL: event.conversationURL),
                    isFailure: failure
                )
                return matches(entry, query: normalizedQuery, filter: filter) ? entry : nil
            })
        }

        return result
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
                return lhs.id < rhs.id
            }
            .prefix(max(1, min(limit, 10_000)))
            .map { $0 }
    }

    private func matches(
        _ entry: CommandTimelineEntry,
        query: String,
        filter: CommandTimelineFilter
    ) -> Bool {
        if filter == .failures, !entry.isFailure { return false }
        guard !query.isEmpty else { return true }
        return normalize("\(entry.title) \(entry.subtitle) \(entry.detail) \(entry.status)").contains(query)
    }

    private func normalize(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let failureAgentStatuses: Set<String> = [
        "failed", "cancelled", "interrupted"
    ]
}

public struct CommandTimelineExporter: Sendable {
    public init() {}

    public func markdown(
        entries: [CommandTimelineEntry],
        privacy: CommandTimelineExportPrivacy = .redacted,
        generatedAt: Date = Date(),
        redactor: DiagnosticRedactor = DiagnosticRedactor()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "# ApexTerm Command Timeline",
            "",
            "Generated: \(formatter.string(from: generatedAt))",
            "Privacy: \(privacy.rawValue)",
            "Entries: \(entries.count)",
            ""
        ]

        for entry in entries {
            let visibleTitle: String
            let visibleSubtitle: String
            let visibleDetail: String
            switch privacy {
            case .metadataOnly:
                visibleTitle = entry.kind == .command ? "Command content omitted" : "Agent event content omitted"
                visibleSubtitle = "\(entry.kind.title) · \(entry.status)"
                visibleDetail = ""
            case .redacted:
                visibleTitle = redactor.redact(entry.title)
                visibleSubtitle = redactor.redact(entry.subtitle)
                visibleDetail = redactor.redact(bounded(entry.detail))
            case .full:
                visibleTitle = entry.title
                visibleSubtitle = entry.subtitle
                visibleDetail = bounded(entry.detail)
            }

            lines.append("## \(visibleTitle)")
            lines.append("")
            lines.append("- Time: \(formatter.string(from: entry.timestamp))")
            lines.append("- Kind: \(entry.kind.rawValue)")
            lines.append("- Status: \(entry.status)")
            lines.append("- Context: \(visibleSubtitle)")
            if !visibleDetail.isEmpty {
                lines.append("")
                lines.append(contentsOf: visibleDetail.split(
                    separator: "\n",
                    omittingEmptySubsequences: false
                ).map { "    \($0)" })
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func bounded(_ text: String, maximumCharacters: Int = 20_000) -> String {
        guard text.count > maximumCharacters else { return text }
        return String(text.prefix(maximumCharacters)) + "\n… [truncated]"
    }
}
