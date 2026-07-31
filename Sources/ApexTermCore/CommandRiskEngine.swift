import Foundation

public enum RiskLevel: Int, Codable, Comparable, Sendable {
    case allow = 0
    case warn = 1
    case requireApproval = 2

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct RiskDecision: Codable, Equatable, Sendable {
    public var level: RiskLevel
    public var ruleID: String?
    public var explanation: String?

    public init(level: RiskLevel, ruleID: String? = nil, explanation: String? = nil) {
        self.level = level
        self.ruleID = ruleID
        self.explanation = explanation
    }
}

public struct CommandRiskRule: Codable, Equatable, Sendable {
    public var id: String
    public var pattern: String
    public var level: RiskLevel
    public var explanation: String

    public init(id: String, pattern: String, level: RiskLevel, explanation: String) {
        self.id = id
        self.pattern = pattern
        self.level = level
        self.explanation = explanation
    }
}

public struct CommandRiskEngine: Sendable {
    public let rules: [CommandRiskRule]

    public init(rules: [CommandRiskRule] = CommandRiskEngine.defaultRules) {
        self.rules = rules
    }

    public func evaluate(_ command: String) -> RiskDecision {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return RiskDecision(level: .allow)
        }

        let matches = rules.filter { rule in
            normalized.range(
                of: rule.pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }

        guard let strongest = matches.max(by: { lhs, rhs in lhs.level < rhs.level }) else {
            return RiskDecision(level: .allow)
        }

        return RiskDecision(
            level: strongest.level,
            ruleID: strongest.id,
            explanation: strongest.explanation
        )
    }

    public static let defaultRules: [CommandRiskRule] = [
        CommandRiskRule(
            id: "filesystem.rm-root",
            pattern: #"(^|[;&|]\s*)(sudo\s+)?rm\s+(-[^\n]*r[^\n]*f|-[^\n]*f[^\n]*r)\s+(/|~)(\s|$)"#,
            level: .requireApproval,
            explanation: "ルートまたはホーム全体を再帰削除する可能性があります。"
        ),
        CommandRiskRule(
            id: "git.force-protected",
            pattern: #"git\s+push[^\n]*(--force(?!-with-lease)|-f)([^\n]*(main|master)|\s*$)"#,
            level: .requireApproval,
            explanation: "保護対象になりやすいブランチへのforce pushです。"
        ),
        CommandRiskRule(
            id: "database.remote-mutation",
            pattern: #"(wrangler\s+d1\s+execute[^\n]*--remote|psql[^\n]*(-c|--command)[^\n]*(drop|truncate|delete\s+from)|mysql[^\n]*(-e|--execute)[^\n]*(drop|truncate|delete\s+from))"#,
            level: .requireApproval,
            explanation: "リモートデータベースを破壊的に変更する可能性があります。"
        ),
        CommandRiskRule(
            id: "secret.display",
            pattern: #"(^|[;&|]\s*)(cat|less|more|head|tail)\s+[^\n]*(\.env|id_rsa|id_ed25519|credentials|secret)|security\s+find-[^\n]*-w"#,
            level: .requireApproval,
            explanation: "secretや秘密鍵を画面へ表示する可能性があります。"
        ),
        CommandRiskRule(
            id: "service.activation",
            pattern: #"(^|[;&|]\s*)(sudo\s+)?(systemctl\s+(enable|start)|launchctl\s+(load|bootstrap)|cron(tab)?\b)"#,
            level: .warn,
            explanation: "常駐サービスまたは定期実行を有効化する可能性があります。"
        ),
        CommandRiskRule(
            id: "production.deploy",
            pattern: #"(^|[;&|]\s*)(wrangler\s+deploy|vercel\s+--prod|firebase\s+deploy|npm\s+run\s+deploy)\b"#,
            level: .warn,
            explanation: "本番環境へ反映する可能性があります。"
        )
    ]
}
