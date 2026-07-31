import Foundation

public enum ApexTermPaths {
    public static func supportDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = environment["APEXTERM_SUPPORT_DIRECTORY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(
                fileURLWithPath: NSString(string: override).expandingTildeInPath,
                isDirectory: true
            )
        }

        return fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("ApexTerm", isDirectory: true)
    }

    public static func shellIntegrationDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        supportDirectory(environment: environment)
            .appendingPathComponent("shell-integration", isDirectory: true)
    }

    public static func automationSocketURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        supportDirectory(environment: environment)
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("apexterm.sock")
    }

    public static func tmuxServerName(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let explicit = environment["APEXTERM_TMUX_SERVER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return sanitizedTmuxName(explicit)
        }

        guard environment["APEXTERM_SUPPORT_DIRECTORY"] != nil else {
            return "apexterm-v2"
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in supportDirectory(environment: environment).path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "apexterm-v2-" + String(hash, radix: 16)
    }

    private static func sanitizedTmuxName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(scalars).prefix(80)
        return result.isEmpty ? "apexterm" : String(result)
    }
}
