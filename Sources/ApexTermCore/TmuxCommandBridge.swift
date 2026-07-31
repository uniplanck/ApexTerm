import Foundation

public struct TmuxCommandResult: Codable, Equatable, Sendable {
    public var output: String
    public var exitCode: Int

    public init(output: String, exitCode: Int) {
        self.output = output
        self.exitCode = exitCode
    }
}

public enum TmuxCommandBridgeError: Error, Equatable {
    case tmuxUnavailable
    case sessionUnavailable
    case commandContainsNewline
    case timeout
    case malformedResult
    case processFailed(String)
}

public struct TmuxCommandBridge: Sendable {
    public var tmuxExecutable: String
    public var serverName: String

    public init(
        tmuxExecutable: String? = LocalToolDiscovery.firstExecutable(named: "tmux"),
        serverName: String = ApexTermPaths.tmuxServerName()
    ) throws {
        guard let tmuxExecutable else {
            throw TmuxCommandBridgeError.tmuxUnavailable
        }
        self.tmuxExecutable = tmuxExecutable
        self.serverName = serverName
    }

    public func runCommand(
        sessionID: UUID,
        command: String,
        explicitSessionName: String? = nil,
        timeout: TimeInterval = 15
    ) throws -> TmuxCommandResult {
        guard !command.contains("\n"), !command.contains("\r") else {
            throw TmuxCommandBridgeError.commandContainsNewline
        }

        let builder = LocalSessionLaunchPlanBuilder(
            tmuxExecutable: tmuxExecutable,
            shellExecutable: "/bin/zsh"
        )
        let sessionName = builder.normalizedSessionName(explicitSessionName)
            ?? builder.sessionName(for: sessionID)

        guard try runTmux(["has-session", "-t", sessionName]).status == 0 else {
            throw TmuxCommandBridgeError.sessionUnavailable
        }

        let token = String(
            UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        )
        let startMarker = "AS\(token)"
        let endMarker = "AE\(token)"

        let deadline = Date().addingTimeInterval(timeout)
        try sendLiteral("echo \(startMarker)", to: sessionName)
        try sendEnter(to: sessionName)

        var markerCapture = ""
        while Date() < deadline {
            markerCapture = try capturePane(sessionName)
            if markerCapture.components(separatedBy: .newlines).contains(startMarker) {
                break
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        guard markerCapture.components(separatedBy: .newlines).contains(startMarker) else {
            throw TmuxCommandBridgeError.timeout
        }
        let promptPrefix = promptPrefixBeforeMarker(
            in: markerCapture,
            marker: startMarker
        )

        try sendLiteral(command, to: sessionName)
        Thread.sleep(forTimeInterval: 0.08)
        let echoedCommandLines = linesAfterLastMarker(
            in: try capturePane(sessionName),
            marker: startMarker
        )

        try sendEnter(to: sessionName)
        try sendLiteral("echo \(endMarker):$?", to: sessionName)
        try sendEnter(to: sessionName)

        while Date() < deadline {
            let capture = try capturePane(sessionName)
            if let result = parse(
                capture,
                command: command,
                startMarker: startMarker,
                endMarker: endMarker,
                echoedCommandLines: echoedCommandLines,
                promptPrefix: promptPrefix
            ) {
                return result
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw TmuxCommandBridgeError.timeout
    }

    private func sendLiteral(_ text: String, to sessionName: String) throws {
        let result = try runTmux(["send-keys", "-t", sessionName, "-l", "--", text])
        guard result.status == 0 else {
            throw TmuxCommandBridgeError.processFailed(result.stderr)
        }
    }

    private func sendEnter(to sessionName: String) throws {
        let result = try runTmux(["send-keys", "-t", sessionName, "Enter"])
        guard result.status == 0 else {
            throw TmuxCommandBridgeError.processFailed(result.stderr)
        }
    }

    private func capturePane(_ sessionName: String) throws -> String {
        let capture = try runTmux([
            "capture-pane", "-p", "-J", "-S", "-2000", "-t", sessionName
        ])
        guard capture.status == 0 else {
            throw TmuxCommandBridgeError.processFailed(capture.stderr)
        }
        return capture.stdout
    }

    private func linesAfterLastMarker(in text: String, marker: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        guard let markerIndex = lines.lastIndex(of: marker), markerIndex + 1 < lines.count else {
            return []
        }
        var result = Array(lines[(markerIndex + 1)...])
        while result.last?.isEmpty == true { result.removeLast() }
        return result
    }

    private func promptPrefixBeforeMarker(in text: String, marker: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        guard let markerIndex = lines.lastIndex(of: marker), markerIndex > 0 else {
            return nil
        }
        let commandLine = lines[markerIndex - 1]
        let suffix = "echo \(marker)"
        guard commandLine.hasSuffix(suffix) else { return nil }
        return String(commandLine.dropLast(suffix.count))
            .trimmingCharacters(in: .whitespaces)
    }

    private func parse(
        _ text: String,
        command: String,
        startMarker: String,
        endMarker: String,
        echoedCommandLines: [String],
        promptPrefix: String?
    ) -> TmuxCommandResult? {
        let lines = text.components(separatedBy: .newlines)
        guard let startIndex = lines.lastIndex(of: startMarker) else { return nil }
        guard let endIndex = lines[(startIndex + 1)...].firstIndex(where: {
            $0.hasPrefix(endMarker + ":")
        }) else {
            return nil
        }

        let exitText = lines[endIndex].dropFirst(endMarker.count + 1)
        guard let exitCode = Int(exitText.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        var outputLines = Array(lines[(startIndex + 1)..<endIndex])
        if !echoedCommandLines.isEmpty,
           outputLines.count >= echoedCommandLines.count,
           Array(outputLines.prefix(echoedCommandLines.count)) == echoedCommandLines {
            outputLines.removeFirst(echoedCommandLines.count)
        } else if let first = outputLines.first, first.contains(command) {
            outputLines.removeFirst()
        }
        if let markerCommandIndex = outputLines.firstIndex(where: {
            $0.contains("echo \(endMarker)")
        }) {
            var removalStart = markerCommandIndex
            if markerCommandIndex > 0 {
                let candidate = outputLines[markerCommandIndex - 1]
                    .trimmingCharacters(in: .whitespaces)
                let isKnownPromptOnlyLine = ["%", "$", "#", "❯", "➜"].contains(candidate)
                if isKnownPromptOnlyLine || candidate == promptPrefix {
                    removalStart -= 1
                }
            }
            outputLines.removeSubrange(removalStart...)
        }
        while outputLines.first?.isEmpty == true { outputLines.removeFirst() }
        while outputLines.last?.isEmpty == true { outputLines.removeLast() }

        return TmuxCommandResult(
            output: outputLines.joined(separator: "\n"),
            exitCode: exitCode
        )
    }

    private func runTmux(_ arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxExecutable)
        process.arguments = ["-L", serverName] + arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(
                data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            stderr: String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        )
    }

    private struct ProcessResult {
        var status: Int32
        var stdout: String
        var stderr: String
    }
}
