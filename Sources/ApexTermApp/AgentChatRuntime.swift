import ApexTermCore
import AppKit
import Darwin
import Foundation

struct AgentChatCLIClient: Sendable {
    func start(
        prompt: String,
        target: GagTarget,
        performance: GagPerformance,
        title: String,
        conversationURL: URL? = nil
    ) async throws -> GagTargetedJob {
        var arguments = [
            "run",
            "--target", target.rawValue,
            "--performance", performance.rawValue,
            "--prompt", prompt,
            "--title", title,
            "--no-wait",
            "--json"
        ]
        if let conversationURL {
            arguments += ["--url", conversationURL.absoluteString]
        }
        let output = try await execute(
            arguments: arguments,
            timeoutSeconds: 75
        )
        let jobs = try JSONDecoder().decode([GagTargetedJob].self, from: output)
        guard let job = jobs.first else {
            throw AgentChatRuntimeError.invalidResponse("GAG did not return a job")
        }
        return job
    }

    func status(reference: String) async throws -> GagTargetedJob {
        let output = try await execute(
            arguments: ["status", reference, "--json"],
            timeoutSeconds: 45,
            acceptNonZeroOutput: true
        )
        let value = try JSONDecoder().decode(GagTargetedJobEnvelope.self, from: output)
        return GagTargetedJob(target: value.target, job: value.envelope.job)
    }

    func cancel(reference: String) async throws -> GagTargetedJob {
        let output = try await execute(
            arguments: ["cancel", reference, "--json"],
            timeoutSeconds: 45
        )
        return try JSONDecoder().decode(GagTargetedJob.self, from: output)
    }

    func watch(
        reference: String
    ) -> AsyncThrowingStream<GagTargetedJob, Error> {
        do {
            let executable = try Self.resolveExecutable()
            return AgentChatWatchProcess().stream(
                executable: executable,
                arguments: [
                    "watch",
                    reference,
                    "--json-lines",
                    "--interval-seconds",
                    "1"
                ],
                environment: ProcessInfo.processInfo.environment
            )
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    private func execute(
        arguments: [String],
        timeoutSeconds: TimeInterval,
        acceptNonZeroOutput: Bool = false
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let executable = try Self.resolveExecutable()
            return try AgentChatProcessRunner.run(
                executable: executable,
                arguments: arguments,
                timeoutSeconds: timeoutSeconds,
                acceptNonZeroOutput: acceptNonZeroOutput
            )
        }.value
    }

    private static func resolveExecutable() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [String] = []
        if let explicit = environment["GAG_CLI_PATH"], !explicit.isEmpty {
            candidates.append(explicit)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin/gag").path {
            candidates.append(bundled)
        }
        candidates.append(home.appendingPathComponent(".local/bin/gag").path)
        candidates.append(FileManager.default.currentDirectoryPath + "/.build/debug/gag")
        candidates.append(FileManager.default.currentDirectoryPath + "/.build/release/gag")
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw AgentChatRuntimeError.missingExecutable
        }
        return executable
    }
}

private enum AgentChatProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval,
        acceptNonZeroOutput: Bool = false
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let output = LockedDataCollector()
        let error = LockedDataCollector()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            output.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            error.append(handle.availableData)
        }
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw AgentChatRuntimeError.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.15)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        error.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        if process.terminationStatus != 0,
           acceptNonZeroOutput,
           !output.data.isEmpty {
            return output.data
        }
        guard process.terminationStatus == 0 else {
            let detail = String(data: error.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentChatRuntimeError.commandFailed(
                detail?.isEmpty == false ? detail! : "gag exited with \(process.terminationStatus)"
            )
        }
        return output.data
    }
}

private final class LockedDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

enum AgentChatRuntimeError: LocalizedError {
    case missingExecutable
    case launchFailed(String)
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "ApexTermのgag CLIが見つかりません"
        case let .launchFailed(detail):
            "gagを起動できませんでした: \(detail)"
        case let .commandFailed(detail):
            detail
        case let .invalidResponse(detail):
            detail
        }
    }
}

@MainActor
enum ChatConversationOpener {
    static func open(_ url: URL) {
        guard isAllowed(url) else { return }
        let match = conversationPrefix(url)
        let browsers = [
            ("com.brave.Browser", "Brave Browser", false),
            ("com.google.Chrome", "Google Chrome", false),
            ("com.apple.Safari", "Safari", true)
        ]
        for (bundleID, appName, safari) in browsers where isRunning(bundleID: bundleID) {
            if focusExistingTab(appName: appName, urlPrefix: match, safari: safari) {
                return
            }
        }
        for (bundleID, appName, safari) in browsers where isRunning(bundleID: bundleID) {
            if openNewTab(appName: appName, url: url, safari: safari) {
                return
            }
        }
        if let applicationURL = preferredRunningBrowserURL() {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: configuration
            )
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https"
            && (url.host == "chatgpt.com" || url.host == "www.chatgpt.com")
    }

    private static func conversationPrefix(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func preferredRunningBrowserURL() -> URL? {
        for bundleID in ["com.brave.Browser", "com.google.Chrome", "com.apple.Safari"] {
            guard isRunning(bundleID: bundleID),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                continue
            }
            return url
        }
        return nil
    }

    private static func openNewTab(appName: String, url: URL, safari: Bool) -> Bool {
        let safeURL = url.absoluteString.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let safeApp = appName.replacingOccurrences(of: "\"", with: "\\\"")
        let body = safari
            ? """
                if (count of windows) = 0 then make new document with properties {URL:\"\(safeURL)\"}
                if (count of windows) > 0 then
                    tell front window
                        set newTab to make new tab at end of tabs with properties {URL:\"\(safeURL)\"}
                        set current tab to newTab
                    end tell
                end if
                activate
                return \"opened\"
            """
            : """
                activate
                if (count of windows) = 0 then make new window
                tell front window
                    set newTab to make new tab with properties {URL:\"\(safeURL)\"}
                    set active tab index to (count of tabs)
                end tell
                return \"opened\"
            """
        let script = """
        tell application "\(safeApp)"
        \(body)
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        return error == nil && result.stringValue == "opened"
    }

    private static func focusExistingTab(appName: String, urlPrefix: String, safari: Bool) -> Bool {
        let safeURL = urlPrefix.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let safeApp = appName.replacingOccurrences(of: "\"", with: "\\\"")
        let script: String
        if safari {
            script = """
            tell application "\(safeApp)"
                repeat with w in windows
                    repeat with i from 1 to count of tabs of w
                        if URL of tab i of w starts with "\(safeURL)" then
                            set current tab of w to tab i of w
                            set index of w to 1
                            activate
                            return "focused"
                        end if
                    end repeat
                end repeat
            end tell
            return "missing"
            """
        } else {
            script = """
            tell application "\(safeApp)"
                repeat with w in windows
                    repeat with i from 1 to count of tabs of w
                        if URL of tab i of w starts with "\(safeURL)" then
                            set active tab index of w to i
                            set index of w to 1
                            activate
                            return "focused"
                        end if
                    end repeat
                end repeat
            end tell
            return "missing"
            """
        }
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        return error == nil && result.stringValue == "focused"
    }
}
