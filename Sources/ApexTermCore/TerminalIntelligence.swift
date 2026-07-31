import Foundation

public struct SmartPasteAssessment: Equatable, Sendable {
    public var requiresConfirmation: Bool
    public var lineCount: Int
    public var riskDecision: RiskDecision
    public var reason: String?

    public init(
        requiresConfirmation: Bool,
        lineCount: Int,
        riskDecision: RiskDecision,
        reason: String? = nil
    ) {
        self.requiresConfirmation = requiresConfirmation
        self.lineCount = lineCount
        self.riskDecision = riskDecision
        self.reason = reason
    }
}

public struct SmartPastePolicy: Sendable {
    public var multilineThreshold: Int
    public var maximumPreviewCharacters: Int
    public var riskEngine: CommandRiskEngine

    public init(
        multilineThreshold: Int = 2,
        maximumPreviewCharacters: Int = 1_200,
        riskEngine: CommandRiskEngine = CommandRiskEngine()
    ) {
        self.multilineThreshold = max(2, multilineThreshold)
        self.maximumPreviewCharacters = max(120, maximumPreviewCharacters)
        self.riskEngine = riskEngine
    }

    public func assess(
        _ text: String,
        confirmMultiline: Bool = true
    ) -> SmartPasteAssessment {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        let lineCount = max(1, lines.count)
        let decision = riskEngine.evaluate(normalized)
        let hasExecutableTrailingNewline = normalized.hasSuffix("\n")
        let isMultiline = lineCount >= multilineThreshold
        let requiresConfirmation = (confirmMultiline && isMultiline)
            || hasExecutableTrailingNewline
            || decision.level != .allow

        let reason: String?
        if decision.level != .allow {
            reason = decision.explanation
        } else if hasExecutableTrailingNewline {
            reason = "末尾に改行が含まれるため、貼り付け直後に実行される可能性があります。"
        } else if confirmMultiline && isMultiline {
            reason = "複数行の貼り付けです。内容を確認してから端末へ送信します。"
        } else {
            reason = nil
        }

        return SmartPasteAssessment(
            requiresConfirmation: requiresConfirmation,
            lineCount: lineCount,
            riskDecision: decision,
            reason: reason
        )
    }

    public func preview(_ text: String) -> String {
        guard text.count > maximumPreviewCharacters else { return text }
        let prefixCount = maximumPreviewCharacters * 3 / 4
        let suffixCount = maximumPreviewCharacters - prefixCount
        return String(text.prefix(prefixCount))
            + "\n… \(text.count - maximumPreviewCharacters)文字省略 …\n"
            + String(text.suffix(suffixCount))
    }
}

public enum TerminalPastePayload {
    private static let bracketedPasteStart: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
    private static let bracketedPasteEnd: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]

    public static func bytes(for text: String, bracketed: Bool) -> [UInt8] {
        let body = Array(text.utf8)
        guard bracketed else { return body }
        return bracketedPasteStart + body + bracketedPasteEnd
    }
}

public struct TerminalQuickFixSuggestion: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var command: String
    public var confidence: Double

    public init(
        id: String,
        title: String,
        detail: String,
        command: String,
        confidence: Double
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.command = command
        self.confidence = min(1, max(0, confidence))
    }
}

public struct TerminalQuickFixEngine: Sendable {
    public init() {}

    public func suggestions(for record: CommandExecutionRecord) -> [TerminalQuickFixSuggestion] {
        guard record.exitCode != 0 else { return [] }
        let output = String(record.output.prefix(120_000))
        var suggestions: [TerminalQuickFixSuggestion] = []

        if let command = firstMatch(
            pattern: #"git push --set-upstream origin [A-Za-z0-9._/\-]+"#,
            in: output
        ) {
            suggestions.append(
                TerminalQuickFixSuggestion(
                    id: "git.set-upstream",
                    title: "upstreamを設定",
                    detail: "Gitが提示したpushコマンドを入力します",
                    command: command,
                    confidence: 0.99
                )
            )
        }

        if let port = firstCapture(
            pattern: #"(?:EADDRINUSE|address already in use|port)[^0-9]{0,20}([0-9]{2,5})"#,
            in: output
        ) {
            suggestions.append(
                TerminalQuickFixSuggestion(
                    id: "port.inspect.\(port)",
                    title: "ポート\(port)の使用元を確認",
                    detail: "LISTEN中のプロセスを表示します",
                    command: "lsof -nP -iTCP:\(port) -sTCP:LISTEN",
                    confidence: 0.94
                )
            )
        }

        if let suggestion = firstCapture(
            pattern: #"The most similar command is\s+\n?\s*([A-Za-z0-9._-]+)"#,
            in: output
        ), record.command.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("git ") {
            suggestions.append(
                TerminalQuickFixSuggestion(
                    id: "git.similar.\(suggestion)",
                    title: "git \(suggestion)を入力",
                    detail: "Gitが提案した類似サブコマンドです",
                    command: "git \(suggestion)",
                    confidence: 0.91
                )
            )
        }

        if output.localizedCaseInsensitiveContains("command not found"),
           let missing = firstCapture(
                pattern: #"(?:command not found:|command not found\s*[: ]\s*)([A-Za-z0-9._+\-]+)"#,
                in: output
           ) {
            suggestions.append(
                TerminalQuickFixSuggestion(
                    id: "command.lookup.\(missing)",
                    title: "\(missing)の場所を確認",
                    detail: "PATH上に実行ファイルがあるか確認します",
                    command: "command -v \(shellQuote(missing)) || which \(shellQuote(missing))",
                    confidence: 0.82
                )
            )
        }

        if output.localizedCaseInsensitiveContains("permission denied"),
           let path = firstCapture(
                pattern: #"permission denied(?::|\s)+([^\n]+)"#,
                in: output
           )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            suggestions.append(
                TerminalQuickFixSuggestion(
                    id: "permission.inspect",
                    title: "権限を確認",
                    detail: "対象の所有者とパーミッションを表示します",
                    command: "ls -ld \(shellQuote(path))",
                    confidence: 0.70
                )
            )
        }

        var seen: Set<String> = []
        return suggestions
            .filter { seen.insert($0.command).inserted }
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)
            .map { $0 }
    }

    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else { return nil }
        return String(text[matchRange])
    }

    private func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum TerminalDetectedItemKind: String, Equatable, Sendable {
    case url
    case fileLine
    case gitHash
}

public struct TerminalDetectedItem: Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: TerminalDetectedItemKind
    public var value: String
    public var displayValue: String
    public var line: Int?

    public init(
        id: String,
        kind: TerminalDetectedItemKind,
        value: String,
        displayValue: String,
        line: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.displayValue = displayValue
        self.line = line
    }
}

public struct TerminalOutputDetector: Sendable {
    public init() {}

    public func detect(in output: String, limit: Int = 6) -> [TerminalDetectedItem] {
        let bounded = String(output.prefix(160_000))
        var candidates: [(offset: Int, item: TerminalDetectedItem)] = []
        candidates.append(contentsOf: matches(
            pattern: #"https?://[^\s<>()\[\]{}\"']+"#,
            text: bounded
        ) { value, offset, _ in
            let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            return TerminalDetectedItem(
                id: "url:\(offset):\(cleaned)",
                kind: .url,
                value: cleaned,
                displayValue: cleaned
            )
        })
        candidates.append(contentsOf: matches(
            pattern: #"(?<![A-Za-z0-9])((?:\.?\.?/|~/|/)?[A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)*\.[A-Za-z0-9]+):(\d{1,7})"#,
            text: bounded
        ) { value, offset, match in
            guard match.numberOfRanges > 2,
                  let pathRange = Range(match.range(at: 1), in: bounded),
                  let lineRange = Range(match.range(at: 2), in: bounded),
                  let line = Int(bounded[lineRange]) else { return nil }
            let path = String(bounded[pathRange])
            return TerminalDetectedItem(
                id: "file:\(offset):\(path):\(line)",
                kind: .fileLine,
                value: path,
                displayValue: value,
                line: line
            )
        })
        candidates.append(contentsOf: matches(
            pattern: #"(?<![0-9a-f])([0-9a-f]{7,40})(?![0-9a-f])"#,
            text: bounded,
            options: [.caseInsensitive]
        ) { value, offset, _ in
            TerminalDetectedItem(
                id: "hash:\(offset):\(value)",
                kind: .gitHash,
                value: value,
                displayValue: value
            )
        })

        var seen: Set<String> = []
        return candidates
            .sorted { $0.offset < $1.offset }
            .map(\.item)
            .filter { seen.insert("\($0.kind.rawValue):\($0.value)").inserted }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private func matches(
        pattern: String,
        text: String,
        options: NSRegularExpression.Options = [],
        transform: (String, Int, NSTextCheckingResult) -> TerminalDetectedItem?
    ) -> [(offset: Int, item: TerminalDetectedItem)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text),
                  let item = transform(String(text[matchRange]), match.range.location, match) else {
                return nil
            }
            return (match.range.location, item)
        }
    }
}

public struct TerminalCommandInsights: Equatable, Sendable {
    public var quickFixes: [TerminalQuickFixSuggestion]
    public var detectedItems: [TerminalDetectedItem]
    public var outputPreview: TerminalOutputPresentation

    public init(
        quickFixes: [TerminalQuickFixSuggestion],
        detectedItems: [TerminalDetectedItem],
        outputPreview: TerminalOutputPresentation
    ) {
        self.quickFixes = quickFixes
        self.detectedItems = detectedItems
        self.outputPreview = outputPreview
    }
}

public final class TerminalInsightCache: @unchecked Sendable {
    public static let shared = TerminalInsightCache()

    private let lock = NSLock()
    private let maximumCount: Int
    private var values: [UUID: TerminalCommandInsights] = [:]
    private var order: [UUID] = []

    public init(maximumCount: Int = 300) {
        self.maximumCount = max(20, maximumCount)
    }

    public func insights(for record: CommandExecutionRecord) -> TerminalCommandInsights {
        lock.lock()
        if let cached = values[record.id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let computed = TerminalCommandInsights(
            quickFixes: TerminalQuickFixEngine().suggestions(for: record),
            detectedItems: TerminalOutputDetector().detect(in: record.output, limit: 4),
            outputPreview: TerminalOutputPresentation.preview(record.output)
        )

        lock.lock()
        if values[record.id] == nil {
            values[record.id] = computed
            order.append(record.id)
            if order.count > maximumCount {
                let overflow = order.count - maximumCount
                let evicted = Array(order.prefix(overflow))
                order.removeFirst(overflow)
                for id in evicted {
                    values.removeValue(forKey: id)
                }
            }
        }
        let result = values[record.id] ?? computed
        lock.unlock()
        return result
    }

    public func removeAll() {
        lock.lock()
        values.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

public struct TerminalOutputPresentation: Equatable, Sendable {
    public var text: String
    public var omittedCharacterCount: Int
    public var isTruncated: Bool { omittedCharacterCount > 0 }

    public init(text: String, omittedCharacterCount: Int) {
        self.text = text
        self.omittedCharacterCount = max(0, omittedCharacterCount)
    }

    public static func preview(
        _ output: String,
        maximumCharacters: Int = 30_000
    ) -> TerminalOutputPresentation {
        let maximum = max(2_000, maximumCharacters)
        guard output.count > maximum else {
            return TerminalOutputPresentation(text: output, omittedCharacterCount: 0)
        }
        let headCount = maximum * 4 / 5
        let tailCount = maximum - headCount
        let omitted = output.count - maximum
        let text = String(output.prefix(headCount))
            + "\n\n… \(omitted)文字を表示省略（コピー内容には全出力を保持） …\n\n"
            + String(output.suffix(tailCount))
        return TerminalOutputPresentation(text: text, omittedCharacterCount: omitted)
    }
}
