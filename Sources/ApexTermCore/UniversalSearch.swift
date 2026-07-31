import Foundation

public enum UniversalSearchScope: String, CaseIterable, Codable, Hashable, Sendable {
    case all
    case workspaces
    case commands
    case agents
}

public enum UniversalSearchItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case workspace
    case session
    case command
    case agentChat
    case agentEvent

    public var title: String {
        switch self {
        case .workspace: "Workspace"
        case .session: "Terminal"
        case .command: "Command"
        case .agentChat: "Agent Chat"
        case .agentEvent: "Agent Event"
        }
    }
}

public enum UniversalSearchTarget: Codable, Equatable, Sendable {
    case workspace(UUID)
    case session(UUID)
    case command(recordID: UUID, sessionID: UUID)
    case agentChat(UUID)
    case agentJob(reference: String, conversationURL: URL?)
}

public struct UniversalSearchItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: UniversalSearchItemKind
    public var title: String
    public var subtitle: String
    public var detail: String?
    public var timestamp: Date?
    public var target: UniversalSearchTarget
    public var score: Int

    public init(
        id: String,
        kind: UniversalSearchItemKind,
        title: String,
        subtitle: String,
        detail: String? = nil,
        timestamp: Date? = nil,
        target: UniversalSearchTarget,
        score: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.timestamp = timestamp
        self.target = target
        self.score = score
    }
}

public struct UniversalAgentEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var reference: String
    public var title: String
    public var status: String
    public var summary: String
    public var updatedAt: Date?
    public var conversationURL: URL?

    public init(
        id: UUID,
        reference: String,
        title: String,
        status: String,
        summary: String,
        updatedAt: Date? = nil,
        conversationURL: URL? = nil
    ) {
        self.id = id
        self.reference = reference
        self.title = title
        self.status = status
        self.summary = summary
        self.updatedAt = updatedAt
        self.conversationURL = conversationURL
    }
}

public struct UniversalSearchSnapshot: Sendable {
    public var workspaces: [Workspace]
    public var sessions: [TerminalSession]
    public var commands: [CommandExecutionRecord]
    public var agentChats: [AgentChatTab]
    public var agentEvents: [UniversalAgentEvent]

    public init(
        workspaces: [Workspace],
        sessions: [TerminalSession],
        commands: [CommandExecutionRecord],
        agentChats: [AgentChatTab],
        agentEvents: [UniversalAgentEvent] = []
    ) {
        self.workspaces = workspaces
        self.sessions = sessions
        self.commands = commands
        self.agentChats = agentChats
        self.agentEvents = agentEvents
    }
}

public struct UniversalSearchEngine: Sendable {
    public init() {}

    public func search(
        _ query: String,
        in snapshot: UniversalSearchSnapshot,
        scope: UniversalSearchScope = .all,
        limit: Int = 80
    ) -> [UniversalSearchItem] {
        let normalizedQuery = normalize(query)
        let sessionTitles = Dictionary(
            uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0.title) }
        )
        var candidates: [Candidate] = []

        if scope == .all || scope == .workspaces {
            candidates.append(contentsOf: snapshot.workspaces.map { workspace in
                let repositories = workspace.context.repositories
                let repositoryText = repositories.map {
                    "\($0.name) \($0.path)"
                }.joined(separator: " ")
                let root = workspace.rootDirectory ?? repositories.first?.path ?? ""
                return Candidate(
                    item: UniversalSearchItem(
                        id: "workspace:\(workspace.id.uuidString)",
                        kind: .workspace,
                        title: workspace.name,
                        subtitle: root.isEmpty ? "Workspace" : root,
                        detail: repositories.isEmpty
                            ? nil
                            : "\(repositories.count) repositories",
                        timestamp: workspace.updatedAt,
                        target: .workspace(workspace.id)
                    ),
                    searchableText: "\(workspace.name) \(root) \(repositoryText)"
                )
            })

            candidates.append(contentsOf: snapshot.sessions.map { session in
                Candidate(
                    item: UniversalSearchItem(
                        id: "session:\(session.id.uuidString)",
                        kind: .session,
                        title: session.title,
                        subtitle: session.workingDirectory ?? sessionKindText(session.kind),
                        detail: sessionKindText(session.kind),
                        timestamp: session.lastAttachedAt ?? session.createdAt,
                        target: .session(session.id)
                    ),
                    searchableText: "\(session.title) \(session.workingDirectory ?? "") \(sessionKindText(session.kind))"
                )
            })
        }

        if scope == .all || scope == .commands {
            candidates.append(contentsOf: snapshot.commands.map { record in
                let command = record.command.isEmpty ? "(empty command)" : record.command
                let outputPreview = boundedPreview(record.output, maximum: 500)
                return Candidate(
                    item: UniversalSearchItem(
                        id: "command:\(record.id.uuidString)",
                        kind: .command,
                        title: command,
                        subtitle: "\(sessionTitles[record.sessionID] ?? "Terminal") · exit \(record.exitCode)",
                        detail: outputPreview.isEmpty ? nil : outputPreview,
                        timestamp: record.finishedAt,
                        target: .command(
                            recordID: record.id,
                            sessionID: record.sessionID
                        )
                    ),
                    searchableText: "\(record.command) \(record.output) \(sessionTitles[record.sessionID] ?? "") exit \(record.exitCode)"
                )
            })
        }

        if scope == .all || scope == .agents {
            candidates.append(contentsOf: snapshot.agentChats.map { tab in
                let lastMessage = tab.messages.last?.text ?? ""
                let state = tab.activeJob?.job.status.rawValue
                    ?? (tab.lastError == nil ? "idle" : "failed")
                return Candidate(
                    item: UniversalSearchItem(
                        id: "agent-chat:\(tab.id.uuidString)",
                        kind: .agentChat,
                        title: tab.title,
                        subtitle: "\(tab.target.rawValue) · \(state)",
                        detail: boundedPreview(lastMessage, maximum: 500),
                        timestamp: tab.updatedAt,
                        target: .agentChat(tab.id)
                    ),
                    searchableText: "\(tab.title) \(tab.target.rawValue) \(state) \(lastMessage) \(tab.lastError ?? "")"
                )
            })

            candidates.append(contentsOf: snapshot.agentEvents.map { event in
                Candidate(
                    item: UniversalSearchItem(
                        id: "agent-event:\(event.id.uuidString)",
                        kind: .agentEvent,
                        title: event.title,
                        subtitle: "\(event.status) · \(event.reference)",
                        detail: boundedPreview(event.summary, maximum: 500),
                        timestamp: event.updatedAt,
                        target: .agentJob(
                            reference: event.reference,
                            conversationURL: event.conversationURL
                        )
                    ),
                    searchableText: "\(event.title) \(event.status) \(event.reference) \(event.summary)"
                )
            })
        }

        let resolvedLimit = max(1, min(limit, 500))
        if normalizedQuery.isEmpty {
            return candidates
                .map(\.item)
                .sorted(by: defaultOrdering)
                .prefix(resolvedLimit)
                .map { $0 }
        }

        return candidates.compactMap { candidate in
            let score = matchScore(
                query: normalizedQuery,
                title: normalize(candidate.item.title),
                subtitle: normalize(candidate.item.subtitle),
                detail: normalize(candidate.item.detail ?? ""),
                searchableText: normalize(candidate.searchableText),
                kind: candidate.item.kind,
                timestamp: candidate.item.timestamp
            )
            guard score > 0 else { return nil }
            var item = candidate.item
            item.score = score
            return item
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return defaultOrdering(lhs, rhs)
        }
        .prefix(resolvedLimit)
        .map { $0 }
    }

    private func matchScore(
        query: String,
        title: String,
        subtitle: String,
        detail: String,
        searchableText: String,
        kind: UniversalSearchItemKind,
        timestamp: Date?
    ) -> Int {
        var score = 0
        if title == query { score += 1_000 }
        if title.hasPrefix(query) { score += 500 }
        if title.contains(query) { score += 260 }
        if subtitle.hasPrefix(query) { score += 140 }
        if subtitle.contains(query) { score += 90 }
        if detail.contains(query) { score += 45 }
        if searchableText.contains(query) { score += 25 }

        let tokens = query.split(separator: " ").map(String.init)
        if tokens.count > 1,
           tokens.allSatisfy({ searchableText.contains($0) }) {
            score += 120 + tokens.count * 10
        }

        guard score > 0 else { return 0 }

        switch kind {
        case .workspace: score += 18
        case .session: score += 14
        case .command: score += 10
        case .agentChat: score += 12
        case .agentEvent: score += 6
        }

        if let timestamp {
            let age = max(0, Date().timeIntervalSince(timestamp))
            if age < 60 * 60 { score += 16 }
            else if age < 24 * 60 * 60 { score += 10 }
            else if age < 7 * 24 * 60 * 60 { score += 4 }
        }
        return score
    }

    private func defaultOrdering(
        _ lhs: UniversalSearchItem,
        _ rhs: UniversalSearchItem
    ) -> Bool {
        let lhsDate = lhs.timestamp ?? .distantPast
        let rhsDate = rhs.timestamp ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        let lhsPriority = kindPriority(lhs.kind)
        let rhsPriority = kindPriority(rhs.kind)
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func kindPriority(_ kind: UniversalSearchItemKind) -> Int {
        switch kind {
        case .workspace: 0
        case .session: 1
        case .agentChat: 2
        case .command: 3
        case .agentEvent: 4
        }
    }

    private func sessionKindText(_ kind: SessionKind) -> String {
        switch kind {
        case .local:
            "Local shell"
        case let .localTmux(session):
            "Local tmux · \(session)"
        case let .ssh(host):
            "SSH · \(host)"
        case let .tmux(host, session):
            "tmux · \(host)/\(session)"
        }
    }

    private func normalize(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
    }

    private func boundedPreview(_ text: String, maximum: Int) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maximum else { return normalized }
        return String(normalized.prefix(maximum)) + "…"
    }

    private struct Candidate {
        var item: UniversalSearchItem
        var searchableText: String
    }
}
