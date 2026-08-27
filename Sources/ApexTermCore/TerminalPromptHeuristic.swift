import Foundation

public enum TerminalPromptHeuristic {
    public static func looksLikePromptLine(_ line: String) -> Bool {
        let normalized = stripCommonANSICodes(from: line)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= 300,
              let suffix = normalized.last,
              "%$#❯➜>".contains(suffix) else {
            return false
        }

        return normalized.hasPrefix("(")
            || normalized.contains("@")
            || normalized.contains("~")
            || normalized.contains("/")
            || normalized.contains(":")
            || normalized.count <= 3
    }

    public static func isPromptReady(bufferText: String) -> Bool {
        let lines = bufferText.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        for line in lines.reversed().prefix(8) {
            let value = String(line)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { continue }
            return looksLikePromptLine(value)
        }
        return false
    }

    private static func stripCommonANSICodes(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\u001B\[[0-?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }
}
