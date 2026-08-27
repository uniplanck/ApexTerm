import Foundation

public enum TerminalConversationPolicy {
    public static func resolvesTranscriptMode(
        baseMode: CommandTranscriptMode,
        sessionKind: SessionKind,
        remoteInteractiveCommandActive: Bool,
        userOverride: CommandTranscriptMode? = nil
    ) -> CommandTranscriptMode {
        if let userOverride {
            return userOverride
        }
        if sessionKind.isRemote || remoteInteractiveCommandActive {
            return .ex
        }
        return baseMode
    }

    public static func commandStartsRemoteInteractiveSession(_ command: String) -> Bool {
        let normalized = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        let patterns = [
            #"(?:^|[;&|]\s*)(?:sudo\s+)?(?:env\s+(?:[^\s=]+=[^\s]+\s+)*)?(?:/usr/bin/|/usr/local/bin/|/opt/homebrew/bin/)?ssh(?:\s|$)"#,
            #"(?:^|[;&|]\s*)(?:sudo\s+)?tailscale\s+ssh(?:\s|$)"#,
            #"(?:^|[;&|]\s*)(?:sudo\s+)?mosh(?:\s|$)"#,
            #"(?:^|[;&|]\s*)aws\s+ssm\s+start-session(?:\s|$)"#,
            #"(?:^|[;&|]\s*)aws\s+ec2-instance-connect\s+ssh(?:\s|$)"#,
            #"(?:^|[;&|]\s*)gcloud\s+compute\s+ssh(?:\s|$)"#
        ]

        return patterns.contains { pattern in
            normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }

    public static func supportsComposer(
        sessionKind: SessionKind,
        shellPromptReady: Bool,
        remoteInteractiveCommandActive: Bool
    ) -> Bool {
        // Dedicated SSH sessions and a local shell currently inside `ssh` do not
        // receive ApexTerm's OSC 133 integration. They become sendable only after
        // the rendered terminal buffer exposes a prompt through the bounded prompt
        // heuristic. The prompt signal, not the connection kind, is authoritative.
        _ = sessionKind
        _ = remoteInteractiveCommandActive
        return shellPromptReady
    }
}

public extension SessionKind {
    var isRemote: Bool {
        switch self {
        case .local, .localTmux:
            return false
        case .ssh, .tmux:
            return true
        }
    }
}
