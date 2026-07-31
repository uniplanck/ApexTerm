import Foundation

public struct DiagnosticRedactor: Sendable {
    public var privatePaths: [String]
    public var homeDirectory: String?

    public init(
        privatePaths: [String] = [],
        homeDirectory: String? = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.privatePaths = privatePaths
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        self.homeDirectory = homeDirectory
    }

    public func redact(_ input: String) -> String {
        var output = input

        for path in privatePaths {
            output = output.replacingOccurrences(
                of: path,
                with: "<private-path>",
                options: [.caseInsensitive]
            )
        }
        if let homeDirectory, !homeDirectory.isEmpty {
            output = output.replacingOccurrences(
                of: homeDirectory,
                with: "~",
                options: [.caseInsensitive]
            )
        }

        let replacements: [(String, String)] = [
            (
                #"(?i)(authorization\s*:\s*bearer\s+)[A-Za-z0-9._~+/=-]+"#,
                "$1<redacted>"
            ),
            (
                #"(?i)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY)[A-Z0-9_]*)=([^\s]+)"#,
                "$1=<redacted>"
            ),
            (
                #"(?i)(--(?:token|secret|password|api-key)\s+)([^\s]+)"#,
                "$1<redacted>"
            ),
            (#"\bsk-[A-Za-z0-9_-]{10,}\b"#, "<redacted-openai-key>"),
            (#"\bgh[pousr]_[A-Za-z0-9]{20,}\b"#, "<redacted-github-token>"),
            (#"\bAKIA[A-Z0-9]{16}\b"#, "<redacted-aws-key>")
        ]

        for (pattern, replacement) in replacements {
            output = output.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return output
    }

    public func redactedEnvironment(
        _ environment: [String: String]
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: environment.map { key, value in
            if Self.isSensitiveEnvironmentKey(key) {
                return (key, "<redacted>")
            }
            return (key, redact(value))
        })
    }

    public static func isSensitiveEnvironmentKey(_ key: String) -> Bool {
        let normalized = key.uppercased()
        let fragments = [
            "TOKEN",
            "SECRET",
            "PASSWORD",
            "PASSWD",
            "API_KEY",
            "PRIVATE_KEY",
            "CREDENTIAL",
            "AUTHORIZATION",
            "COOKIE"
        ]
        return fragments.contains { normalized.contains($0) }
    }
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var appVersion: String
    public var operatingSystem: String
    public var architecture: String
    public var renderer: String
    public var workspaceCount: Int
    public var sessionCount: Int
    public var activeAgentCount: Int
    public var automationSocketEnabled: Bool
    public var notes: [String]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        appVersion: String,
        operatingSystem: String,
        architecture: String,
        renderer: String,
        workspaceCount: Int,
        sessionCount: Int,
        activeAgentCount: Int,
        automationSocketEnabled: Bool,
        notes: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.renderer = renderer
        self.workspaceCount = workspaceCount
        self.sessionCount = sessionCount
        self.activeAgentCount = activeAgentCount
        self.automationSocketEnabled = automationSocketEnabled
        self.notes = notes
    }

    public func redacted(using redactor: DiagnosticRedactor) -> DiagnosticReport {
        var copy = self
        copy.notes = notes.map(redactor.redact)
        return copy
    }
}
