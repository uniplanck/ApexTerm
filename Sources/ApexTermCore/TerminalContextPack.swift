import Foundation

public enum TerminalContextPackBuilder {
    public static let defaultMaximumOutputCharacters = 12_000

    public static func markdown(
        record: CommandExecutionRecord,
        sessionTitle: String,
        workingDirectory: String?,
        maximumOutputCharacters: Int = defaultMaximumOutputCharacters,
        redactor: DiagnosticRedactor = DiagnosticRedactor()
    ) -> String {
        let duration = max(0, record.finishedAt.timeIntervalSince(record.startedAt))
        let command = redactor.redact(record.command)
        let directory = redactor.redact(workingDirectory ?? "(unknown)")
        let title = redactor.redact(sessionTitle)
        let outputTail = boundedTail(
            record.output,
            maximumCharacters: maximumOutputCharacters
        )
        let output = redactor.redact(outputTail.isEmpty ? "(no output)" : outputTail)

        return """
        # ApexTerm Context Pack

        - Session: \(title)
        - Working directory: \(directory)
        - Exit code: \(record.exitCode)
        - Duration: \(String(format: "%.2f", duration))s

        ## Command

        ````zsh
        \(escapeFence(command))
        ````

        ## Output tail

        ````text
        \(escapeFence(output))
        ````
        """
    }

    public static func agentPrompt(
        record: CommandExecutionRecord,
        sessionTitle: String,
        workingDirectory: String?,
        maximumOutputCharacters: Int = defaultMaximumOutputCharacters,
        redactor: DiagnosticRedactor = DiagnosticRedactor()
    ) -> String {
        let context = markdown(
            record: record,
            sessionTitle: sessionTitle,
            workingDirectory: workingDirectory,
            maximumOutputCharacters: maximumOutputCharacters,
            redactor: redactor
        )
        return """
        Diagnose this terminal failure from the evidence below.

        Return:
        1. The most likely root cause.
        2. The smallest safe correction.
        3. A copy-paste verification command.
        4. Any assumption that still needs confirmation.

        Do not execute commands, deploy, push, delete files, or mutate external systems. Prepare the fix for review only.

        \(context)
        """
    }

    private static func boundedTail(
        _ value: String,
        maximumCharacters: Int
    ) -> String {
        let limit = max(200, maximumCharacters)
        guard value.count > limit else { return value }
        return "… [truncated to the last \(limit) characters]\n" + String(value.suffix(limit))
    }

    private static func escapeFence(_ value: String) -> String {
        value.replacingOccurrences(of: "````", with: "``` `")
    }
}
