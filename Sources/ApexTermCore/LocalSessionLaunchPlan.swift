import Foundation

public struct LocalSessionLaunchPlanBuilder: Sendable {
    public var tmuxExecutable: String?
    public var shellExecutable: String
    public var tmuxServerName: String
    public var tmuxConfigurationPath: String

    public init(
        tmuxExecutable: String?,
        shellExecutable: String,
        tmuxServerName: String = "apexterm",
        tmuxConfigurationPath: String = "/dev/null"
    ) {
        self.tmuxExecutable = tmuxExecutable
        self.shellExecutable = shellExecutable
        self.tmuxServerName = tmuxServerName
        self.tmuxConfigurationPath = tmuxConfigurationPath
    }

    public func build(
        sessionID: UUID,
        workingDirectory: String?,
        explicitSessionName: String? = nil,
        tmuxEnvironment: [String: String] = [:]
    ) -> ProcessLaunchPlan {
        guard let tmuxExecutable, !tmuxExecutable.isEmpty else {
            return ProcessLaunchPlan(
                executable: shellExecutable,
                arguments: ["-l"]
            )
        }

        var arguments = [
            "-u",
            "-L", tmuxServerName,
            "-f", tmuxConfigurationPath,
            "new-session",
            "-A",
            "-D"
        ]
        for (key, value) in tmuxEnvironment.sorted(by: { $0.key < $1.key }) {
            arguments += ["-e", "\(key)=\(value)"]
        }
        arguments += [
            "-s",
            normalizedSessionName(explicitSessionName) ?? sessionName(for: sessionID)
        ]
        if let workingDirectory, !workingDirectory.isEmpty {
            arguments += ["-c", workingDirectory]
        }
        arguments += [shellExecutable, "-l"]

        return ProcessLaunchPlan(
            executable: tmuxExecutable,
            arguments: arguments
        )
    }

    public func sessionName(for sessionID: UUID) -> String {
        "apexterm-" + sessionID.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    public func normalizedSessionName(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || "-_".contains($0) }
        return normalized.isEmpty ? nil : String(normalized.prefix(80))
    }
}

public enum LocalToolDiscovery {
    public static func firstExecutable(
        named name: String,
        searchPaths: [String] = defaultSearchPaths
    ) -> String? {
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(name)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static let defaultSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]
}
