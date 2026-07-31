import Foundation

public enum TmuxEndpoint: Hashable, Codable, Identifiable, Sendable {
    case localApexTerm(serverName: String)
    case remote(alias: String)

    public var id: String {
        switch self {
        case let .localApexTerm(serverName):
            "local-apexterm:\(serverName)"
        case let .remote(alias):
            "remote:\(alias)"
        }
    }

    public var remoteAlias: String? {
        guard case let .remote(alias) = self else { return nil }
        return alias
    }
}

public struct TmuxSessionDescriptor: Hashable, Identifiable, Sendable {
    public var id: String { "\(endpoint.id):\(name)" }
    public var endpoint: TmuxEndpoint
    public var name: String
    public var windowCount: Int
    public var attachedClientCount: Int
    public var createdAt: Date?

    public init(
        endpoint: TmuxEndpoint,
        name: String,
        windowCount: Int,
        attachedClientCount: Int,
        createdAt: Date?
    ) {
        self.endpoint = endpoint
        self.name = name
        self.windowCount = windowCount
        self.attachedClientCount = attachedClientCount
        self.createdAt = createdAt
    }
}

public enum TmuxSessionListParser {
    public static func parse(
        _ output: String,
        endpoint: TmuxEndpoint
    ) -> [TmuxSessionDescriptor] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }
                let fields = line.components(separatedBy: "|#|")
                guard !fields.isEmpty else { return nil }
                let name = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let windows = fields.indices.contains(1) ? Int(fields[1]) ?? 0 : 0
                let attached = fields.indices.contains(2) ? Int(fields[2]) ?? 0 : 0
                let createdAt = fields.indices.contains(3)
                    ? TimeInterval(fields[3]).map(Date.init(timeIntervalSince1970:))
                    : nil
                return TmuxSessionDescriptor(
                    endpoint: endpoint,
                    name: name,
                    windowCount: windows,
                    attachedClientCount: attached,
                    createdAt: createdAt
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

public enum TmuxLaunchPlanBuilder {
    public static let listFormat = "#{session_name}|#|#{session_windows}|#|#{session_attached}|#|#{session_created}"

    public static func listLocalApexTerm(
        executable: String,
        serverName: String
    ) -> ProcessLaunchPlan {
        ProcessLaunchPlan(
            executable: executable,
            arguments: ["-L", serverName, "list-sessions", "-F", listFormat]
        )
    }

    public static func killLocalApexTerm(
        executable: String,
        serverName: String,
        sessionName: String
    ) -> ProcessLaunchPlan {
        ProcessLaunchPlan(
            executable: executable,
            arguments: ["-L", serverName, "kill-session", "-t", sessionName]
        )
    }

    public static func listRemote(
        profile: SSHHostProfile,
        executable: String = "/usr/bin/ssh"
    ) -> ProcessLaunchPlan {
        RemoteLaunchPlanBuilder.ssh(
            profile: profile,
            remoteCommand: [remoteCommand(["tmux", "list-sessions", "-F", listFormat])],
            executable: executable,
            forceTTY: false,
            batchMode: true
        )
    }

    public static func killRemote(
        profile: SSHHostProfile,
        sessionName: String,
        executable: String = "/usr/bin/ssh"
    ) -> ProcessLaunchPlan {
        RemoteLaunchPlanBuilder.ssh(
            profile: profile,
            remoteCommand: [remoteCommand(["tmux", "kill-session", "-t", sessionName])],
            executable: executable,
            forceTTY: false,
            batchMode: true
        )
    }

    private static func remoteCommand(_ arguments: [String]) -> String {
        arguments.map(shellQuote).joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
