import ApexTermCore
import Darwin
import Foundation

@main
enum GagCLI {
    static func main() {
        do {
            let code = try run(arguments: Array(CommandLine.arguments.dropFirst()))
            Foundation.exit(code)
        } catch let error as CLIError {
            if !error.message.isEmpty {
                fputs("gag: \(error.message)\n", stderr)
            }
            Foundation.exit(error.exitCode)
        } catch {
            fputs("gag: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String]) throws -> Int32 {
        let configuration = CLIConfiguration.load()
        guard let command = arguments.first else {
            printUsage()
            return 0
        }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "run":
            return try runTask(arguments: rest, configuration: configuration)
        case "tui":
            return try runTUI(arguments: rest, configuration: configuration)
        case "status":
            return try showStatus(arguments: rest, configuration: configuration)
        case "watch":
            return try watchJob(arguments: rest, configuration: configuration)
        case "list", "ls":
            return try listJobs(arguments: rest, configuration: configuration)
        case "result":
            return try showResult(arguments: rest, configuration: configuration)
        case "open":
            return try openChat(arguments: rest, configuration: configuration)
        case "cancel":
            return try cancelJob(arguments: rest, configuration: configuration)
        case "resume":
            return try resumeJob(arguments: rest, configuration: configuration)
        case "doctor":
            return try doctor(arguments: rest, configuration: configuration)
        case "version", "--version", "-v":
            print("gag 0.1.0")
            return 0
        case "help", "--help", "-h":
            printUsage()
            return 0
        default:
            throw CLIError.usage("unknown command: \(command)")
        }
    }

    private static func runTask(
        arguments: [String],
        configuration: CLIConfiguration
    ) throws -> Int32 {
        let options = try RunOptions.parse(arguments)
        let targets = options.target.targets
        let reporter = AgentRailReporter(socketURL: configuration.automationSocketURL)
        var started: [TargetedJob] = []

        for target in targets {
            let client = GagJobClient(
                backend: GagBackend(target: target, configuration: configuration)
            )
            let jobID = try client.start(options: options)
            let job = try client.show(jobID: jobID).job
            reporter.report(target: target, job: job)
            started.append(TargetedJob(target: target, job: job))
            if !options.json {
                print("started \(GagJobReference(target: target, jobID: job.id).serialized) — \(job.title)")
                fflush(stdout)
            }
        }

        if options.noWait {
            if options.json { printJSON(started) }
            return 0
        }

        let completed = try monitor(
            jobs: started,
            configuration: configuration,
            timeoutSeconds: options.timeoutSeconds + 90,
            reporter: reporter,
            quiet: options.json
        )

        if options.json {
            printJSON(completed)
        } else {
            for item in completed {
                printResult(item)
            }
        }

        if completed.contains(where: { $0.job.status == .waitingApproval }) {
            return 3
        }
        if completed.contains(where: {
            $0.job.status == .failed || $0.job.status == .cancelled || $0.job.status == .interrupted
        }) {
            return 2
        }
        return 0
    }

    private static func runTUI(
        arguments: [String],
        configuration: CLIConfiguration
    ) throws -> Int32 {
        guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else {
            throw CLIError.usage("tui requires an interactive terminal")
        }
        var tuiOptions = try TUIOptions.parse(arguments)
        let renderer = GagTUIRenderer()
        renderer.renderWelcome(target: tuiOptions.target)

        if tuiOptions.prompt.isEmpty {
            renderer.printPromptLabel("Instruction")
            tuiOptions.prompt = (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !tuiOptions.prompt.isEmpty else {
            renderer.clear()
            throw CLIError.usage("tui requires an instruction")
        }

        if !tuiOptions.targetWasExplicit {
            renderer.renderTargetChoice()
            let selection = (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch selection.lowercased() {
            case "2", "gae": tuiOptions.target = .gae
            case "3", "both": tuiOptions.target = .both
            default: tuiOptions.target = .local
            }
        }
        if !tuiOptions.performanceWasExplicit {
            renderer.renderPerformanceChoice()
            let selection = (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch selection.lowercased() {
            case "1", "fastest", "fast", "instant", "gpt-5-5-instant":
                tuiOptions.performance = .fastest
            default:
                tuiOptions.performance = .high
            }
        }

        var runOptions = RunOptions()
        runOptions.target = tuiOptions.target
        runOptions.prompt = tuiOptions.prompt
        runOptions.title = "ApexTerm TUI: " + String(
            tuiOptions.prompt.replacingOccurrences(of: "\n", with: " ").prefix(64)
        )
        runOptions.expectedMarker = tuiOptions.expectedMarker
        runOptions.timeoutSeconds = tuiOptions.timeoutSeconds
        runOptions.writingKernel = tuiOptions.writingKernel
        runOptions.performance = tuiOptions.performance
        runOptions.keepTab = tuiOptions.keepTab

        let reporter = AgentRailReporter(socketURL: configuration.automationSocketURL)
        var latest: [String: TargetedJob] = [:]
        for target in runOptions.target.targets {
            let client = GagJobClient(
                backend: GagBackend(target: target, configuration: configuration)
            )
            let jobID = try client.start(options: runOptions)
            let job = try client.show(jobID: jobID).job
            reporter.report(target: target, job: job)
            let item = TargetedJob(target: target, job: job)
            latest[GagJobReference(target: target, jobID: job.id).serialized] = item
        }

        let deadline = Date().addingTimeInterval(TimeInterval(runOptions.timeoutSeconds + 90))
        var consecutiveFailures: [String: Int] = [:]
        while Date() < deadline {
            let values = latest.values.sorted { $0.target.rawValue < $1.target.rawValue }
            renderer.renderDashboard(prompt: runOptions.prompt, jobs: values)
            let active = values.filter {
                !$0.job.status.isTerminal
                    && $0.job.status != .waitingApproval
                    && $0.job.status != .interrupted
            }
            if active.isEmpty { break }

            for item in active {
                let key = GagJobReference(target: item.target, jobID: item.job.id).serialized
                do {
                    let refreshed = try GagJobClient(
                        backend: GagBackend(target: item.target, configuration: configuration)
                    ).show(jobID: item.job.id).job
                    latest[key] = TargetedJob(target: item.target, job: refreshed)
                    reporter.report(target: item.target, job: refreshed)
                    consecutiveFailures[key] = 0
                } catch {
                    let failures = (consecutiveFailures[key] ?? 0) + 1
                    consecutiveFailures[key] = failures
                    if failures >= 3 {
                        renderer.clear()
                        throw CLIError.runtime(
                            "lost \(item.target.displayName) job status after 3 attempts: \(error.localizedDescription)"
                        )
                    }
                }
            }
            Thread.sleep(forTimeInterval: configuration.pollIntervalSeconds)
        }

        let completed = latest.values.sorted { $0.target.rawValue < $1.target.rawValue }
        let unfinished = completed.filter {
            !$0.job.status.isTerminal
                && $0.job.status != .waitingApproval
                && $0.job.status != .interrupted
        }
        if !unfinished.isEmpty {
            renderer.renderDashboard(prompt: runOptions.prompt, jobs: completed)
            renderer.printFooter("Timeout. Jobs continue in background. Press Return to leave the dashboard.")
        } else {
            renderer.renderFinished(prompt: runOptions.prompt, jobs: completed)
            renderer.printFooter("Press Return to close the dashboard and print the full response.")
        }
        if ProcessInfo.processInfo.environment["GAG_TUI_NO_PAUSE"] != "1" {
            _ = readLine()
        }
        renderer.clear()
        for item in completed {
            printResult(item)
        }

        if !unfinished.isEmpty { return 124 }
        if completed.contains(where: { $0.job.status == .waitingApproval }) { return 3 }
        if completed.contains(where: {
            $0.job.status == .failed || $0.job.status == .cancelled || $0.job.status == .interrupted
        }) { return 2 }
        return 0
    }

    private static func showStatus(
        arguments: [String],
        configuration: CLIConfiguration
    ) throws -> Int32 {
        let parsed = try ReferenceOptions.parse(arguments, command: "status")
        let client = GagJobClient(
            backend: GagBackend(target: parsed.reference.target, configuration: configuration)
        )
        let envelope = try client.show(jobID: parsed.reference.jobID)
        AgentRailReporter(socketURL: configuration.automationSocketURL)
            .report(target: parsed.reference.target, job: envelope.job)
        if parsed.json {
            printJSON(TargetedJobEnvelope(target: parsed.reference.target, envelope: envelope))
        } else {
            printJobLine(target: parsed.reference.target, job: envelope.job)
            for event in envelope.events ?? [] {
                print("\(event.timestamp) \(event.level.padding(toLength: 7, withPad: " ", startingAt: 0)) \(event.message)")
            }
        }
        return envelope.job.status == .failed ? 2 : 0
    }

    private static func watchJob(
        arguments: [String],
        configuration: CLIConfiguration
    ) throws -> Int32 {
        let options = try WatchOptions.parse(
            arguments,
            defaultInterval: configuration.pollIntervalSeconds
        )
        let client = GagJobClient(
            backend: GagBackend(
                target: options.reference.target,
                configuration: configuration
            )
        )
        let reporter = AgentRailReporter(
            socketURL: configuration.automationSocketURL
        )
        let deadline = options.timeoutSeconds.map {
            Date().addingTimeInterval($0)
        }
        var previous: GagJobRecord?
        var consecutiveFailures = 0

        while deadline.map({ Date() < $0 }) ?? true {
            do {
                let job = try client.show(jobID: options.reference.jobID).job
                consecutiveFailures = 0
                if job != previous {
                    reporter.report(target: options.reference.target, job: job)
                    let targeted = TargetedJob(
                        target: options.reference.target,
                        job: job
                    )
                    if options.jsonLines {
                        printJSONLine(targeted)
                    } else {
                        printJobLine(
                            target: options.reference.target,
                            job: job
                        )
                    }
                    fflush(stdout)
                    previous = job
                }

                if job.status.isTerminal
                    || job.status == .waitingApproval
                    || job.status == .interrupted {
                    if job.status == .waitingApproval { return 3 }
                    if job.status == .failed
                        || job.status == .cancelled
                        || job.status == .interrupted {
                        return 2
                    }
                    return 0
                }
            } catch {
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    throw CLIError.runtime(
                        "lost job status after 3 attempts: \(error.localizedDescription)"
                    )
                }
            }
            Thread.sleep(forTimeInterval: options.intervalSeconds)
        }

        return 124
    }

    private static func listJobs(
        arguments: [String],
        configuration: CLIConfiguration
    ) throws -> Int32 {
        let options = try ListOptions.parse(arguments)
        var result: [TargetedJob] = []
        for target in options.target.targets {
            let client = GagJobClient(
                backend: GagBackend(target: target, configuration: configuration)
            )
            let jobs = try client.list()
                .filter { options.allPresets || $0.preset == "chatgpt-task" }
            result.append(contentsOf: jobs.map { TargetedJob(target: target, job: $0) })
        }
        result.sort { $0.job.updatedAt > $1.job.updatedAt }
        if options.json {
            printJSON(result)
        } else if result.isEmpty {
            print("No GAG/GAE ChatGPT jobs found.")
        } else {
            for item in result {
                printJobLine(target: item.target, job: item.job)
            }
        }
        return 0
    }

    private static func showResult(
        arguments: [String],
        configuration: CLIConfiguration
    ) throws -> Int32 {
        let parsed = try ReferenceOptions.parse(arguments, command: "result")
        let client = GagJobClient(
            backend: GagBackend(target: parsed.reference.target, configuration: configuration)
        )
        let job = try client.show(jobID: parsed.reference.jobID).job
        AgentRailReporter(socketURL: configuration.automationSocketURL)
            .report(target: parsed.reference.target, job: job)
        if parsed.json {
            printJSON(TargetedJob(target: parsed.reference.target, job: job))
        } else {
            printResult(TargetedJob(target: parsed.reference.target, job: job))
        }
        return job.status == .succeeded ? 0 : 2
    }

    private static func openChat(
        arguments: [String],
        configuration: CLIConfiguration
    ) throws -> Int32 {
        let parsed = try ReferenceOptions.parse(arguments, command: "open")
        let client = GagJobClient(
            backend: GagBackend(target: parsed.reference.target, configuration: configuration)
        )
        let job = try client.show(jobID: parsed.reference.jobID).job
        guard let rawURL = job.state?.conversationUrl,
              let url = URL(string: rawURL),
              url.scheme == "https",
              url.host == "chatgpt.com" || url.host == "www.chatgpt.com" else {
            throw CLIError.runtime("ChatGPT conversation URL is not available yet")
        }
        let result = try GagChatLinkLauncher.open(url: url)
        print("\(result == .focused ? "Focused" : "Opened") Chat: \(url.absoluteString)")
        return 0
    }

    private static func cancelJob(
        arguments: [String],
        configuration: CLIConfiguration
    ) throws -> Int32 {
        let parsed = try ReferenceOptions.parse(arguments, command: "cancel")
        let client = GagJobClient(
            backend: GagBackend(target: parsed.reference.target, configuration: configuration)
        )
        let job = try client.cancel(jobID: parsed.reference.jobID)
        AgentRailReporter(socketURL: configuration.automationSocketURL)
            .report(target: parsed.reference.target, job: job)
        if parsed.json {
            printJSON(TargetedJob(target: parsed.reference.target, job: job))
        } else {
            printJobLine(target: parsed.reference.target, job: job)
        }
        return 0
    }

    private static func resumeJob(
        arguments: [String],
        configuration: CLIConfiguration
    ) throws -> Int32 {
        let parsed = try ResumeOptions.parse(arguments)
        let client = GagJobClient(
            backend: GagBackend(target: parsed.reference.target, configuration: configuration)
        )
        let resumed = try client.resume(jobID: parsed.reference.jobID)
        let reporter = AgentRailReporter(socketURL: configuration.automationSocketURL)
        reporter.report(target: parsed.reference.target, job: resumed)
        if parsed.noWait {
            if parsed.json {
                printJSON(TargetedJob(target: parsed.reference.target, job: resumed))
            } else {
                printJobLine(target: parsed.reference.target, job: resumed)
            }
            return 0
        }
        let completed = try monitor(
            jobs: [TargetedJob(target: parsed.reference.target, job: resumed)],
            configuration: configuration,
            timeoutSeconds: parsed.timeoutSeconds,
            reporter: reporter,
            quiet: parsed.json
        )
        if parsed.json {
            printJSON(completed)
        } else if let result = completed.first {
            printResult(result)
        }
        return completed.first?.job.status == .succeeded ? 0 : 2
    }

    private static func doctor(
        arguments: [String],
        configuration: CLIConfiguration
    ) throws -> Int32 {
        let options = try DoctorOptions.parse(arguments)
        var targets: [DoctorTargetResult] = []
        for target in options.target.targets {
            let backend = GagBackend(target: target, configuration: configuration)
            do {
                _ = try GagJobClient(backend: backend).list()
                let computer = try backend.execute(
                    arguments: ["computer", "doctor", "--json"],
                    timeoutSeconds: 20
                )
                let readiness = BrowserReadiness.parse(computer.standardOutput)
                targets.append(
                    DoctorTargetResult(
                        target: target,
                        backendAvailable: true,
                        computerUseEnabled: readiness.enabled,
                        browserReady: readiness.browserReady,
                        detail: readiness.missing.isEmpty
                            ? "Job store and browser diagnostics available"
                            : readiness.missing.joined(separator: "; ")
                    )
                )
            } catch {
                targets.append(
                    DoctorTargetResult(
                        target: target,
                        backendAvailable: false,
                        computerUseEnabled: false,
                        browserReady: false,
                        detail: error.localizedDescription
                    )
                )
            }
        }

        let apexTermConnected: Bool = {
            let request = AutomationRequest(clientID: "gag", action: .readStatus)
            guard let response = try? UnixAutomationClient.send(
                request,
                to: configuration.automationSocketURL
            ) else { return false }
            return response.status == .accepted
        }()
        let report = DoctorReport(apexTermConnected: apexTermConnected, targets: targets)
        if options.json {
            printJSON(report)
        } else {
            print("ApexTerm Agent Rail: \(apexTermConnected ? "connected" : "not connected")")
            for item in targets {
                print(
                    "\(item.target.displayName): backend=\(item.backendAvailable ? "ready" : "unavailable") "
                    + "computer=\(item.computerUseEnabled ? "enabled" : "disabled") "
                    + "browser=\(item.browserReady ? "ready" : "not-ready") — \(item.detail)"
                )
            }
        }
        return targets.allSatisfy { $0.backendAvailable && $0.computerUseEnabled && $0.browserReady } ? 0 : 2
    }

    private static func monitor(
        jobs: [TargetedJob],
        configuration: CLIConfiguration,
        timeoutSeconds: Int,
        reporter: AgentRailReporter,
        quiet: Bool
    ) throws -> [TargetedJob] {
        var latest = Dictionary(uniqueKeysWithValues: jobs.map {
            (GagJobReference(target: $0.target, jobID: $0.job.id).serialized, $0)
        })
        var lastFingerprint: [String: String] = [:]
        var consecutiveFailures: [String: Int] = [:]
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while Date() < deadline {
            var pending = false
            for key in latest.keys.sorted() {
                guard let item = latest[key] else { continue }
                if item.job.status.isTerminal
                    || item.job.status == .waitingApproval
                    || item.job.status == .interrupted {
                    continue
                }
                pending = true
                let client = GagJobClient(
                    backend: GagBackend(target: item.target, configuration: configuration)
                )
                do {
                    let refreshed = try client.show(jobID: item.job.id).job
                    latest[key] = TargetedJob(target: item.target, job: refreshed)
                    consecutiveFailures[key] = 0
                    reporter.report(target: item.target, job: refreshed)
                    let fingerprint = "\(refreshed.status.rawValue):\(refreshed.progress):\(refreshed.currentStep)"
                    if lastFingerprint[key] != fingerprint {
                        lastFingerprint[key] = fingerprint
                        if !quiet { printJobLine(target: item.target, job: refreshed, toStandardError: true) }
                    }
                } catch {
                    let failures = (consecutiveFailures[key] ?? 0) + 1
                    consecutiveFailures[key] = failures
                    if failures >= 3 {
                        throw CLIError.runtime(
                            "lost \(item.target.displayName) job status after 3 attempts: \(error.localizedDescription)"
                        )
                    }
                }
            }
            if !pending { break }
            Thread.sleep(forTimeInterval: configuration.pollIntervalSeconds)
        }

        let values = latest.values.sorted {
            if $0.target == $1.target { return $0.job.createdAt < $1.job.createdAt }
            return $0.target.rawValue < $1.target.rawValue
        }
        let unfinished = values.filter {
            !$0.job.status.isTerminal
                && $0.job.status != .waitingApproval
                && $0.job.status != .interrupted
        }
        if !unfinished.isEmpty {
            let references = unfinished.map {
                GagJobReference(target: $0.target, jobID: $0.job.id).serialized
            }.joined(separator: ", ")
            throw CLIError.timeout("timed out while waiting; jobs continue in background: \(references)")
        }
        return values
    }

    private static func printResult(_ item: TargetedJob) {
        printJobLine(target: item.target, job: item.job)
        if let text = item.job.state?.responseText, !text.isEmpty {
            print("\n--- \(item.target.displayName) response ---")
            print(text)
        }
        let requestedPerformance = item.job.state?.requestedPerformance
            ?? item.job.input?.performance
            ?? .high
        print("\nRequested performance: \(requestedPerformance.displayName) (\(requestedPerformance.rawValue))")
        if let model = item.job.state?.selectedModelLabel
            ?? item.job.state?.selectedModel
            ?? item.job.state?.requestedModel {
            print("Selected model: \(model)")
        }
        if let cost = item.job.state?.apiCostEstimate {
            if cost.isRegistered {
                print("API換算推定: \(formatYenRange(cost.jpy, cost.maxJpy)) — \(cost.pricingLabel ?? cost.pricingModel ?? "registered")")
            } else {
                print("API換算推定: 単価未登録 — \(cost.selectedModel ?? cost.requestedModel ?? "unknown model")")
            }
        }
        if let url = item.job.state?.conversationUrl {
            print("Conversation: \(url)")
        }
        if let error = item.job.error, !error.isEmpty {
            print("Error: \(error)")
        }
        if item.job.status == .waitingApproval {
            print("Approval required. Complete the local browser approval, then run:")
            print("  gag resume \(GagJobReference(target: item.target, jobID: item.job.id).serialized)")
        }
    }

    private static func printJobLine(
        target: GagTarget,
        job: GagJobRecord,
        toStandardError: Bool = false
    ) {
        let metrics = GagRuntimeMetrics.calculate(target: target, job: job)
        let reference = metrics.reference
        let progress = String(format: "%3d%%", max(0, min(100, job.progress)))
        let eta = metrics.estimatedRemainingSeconds.map { " · ETA 約\(formatDuration($0))" } ?? ""
        let tokens = metrics.tokens.total > 0 ? " · Token推定 \(formatTokenCount(metrics.tokens.total))" : ""
        let performance = " · \(metrics.requestedPerformance.compactName)→\(metrics.selectedModelLabel ?? metrics.selectedModel ?? "未確定")"
        let line = "\(reference) \(job.status.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)) "
            + "\(progress) — \(job.currentStep)\(eta)\(tokens)\(performance)"
        if toStandardError {
            fputs(line + "\n", stderr)
        } else {
            print(line)
        }
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value < 60 { return "\(value)秒" }
        let minutes = value / 60
        let remainder = value % 60
        if minutes < 60 { return remainder == 0 ? "\(minutes)分" : "\(minutes)分\(remainder)秒" }
        let hours = minutes / 60
        return "\(hours)時間\(minutes % 60)分"
    }

    private static func formatTokenCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return String(value)
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        print(text)
    }

    private static func printJSONLine<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        print(text)
    }

    private static func printUsage() {
        print(
            """
            ApexTerm GAG CLI

            Usage:
              gag run [--target local|gae|both] [--prompt TEXT] [options] [TEXT...]
              gag tui [--target local|gae|both] [--timeout-seconds 5...600] [TEXT...]
              gag status [--target local|gae] JOB_OR_TARGET/JOB [--json]
              gag watch [--target local|gae] JOB_OR_TARGET/JOB [--json-lines]
              gag list [--target local|gae|both] [--all-presets] [--json]
              gag result [--target local|gae] JOB_OR_TARGET/JOB [--json]
              gag open [--target local|gae] JOB_OR_TARGET/JOB
              gag cancel [--target local|gae] JOB_OR_TARGET/JOB [--json]
              gag resume [--target local|gae] JOB_OR_TARGET/JOB [--no-wait] [--json]
              gag doctor [--target local|gae|both] [--json]

            Run options:
              --title TEXT
              --url CHATGPT_URL
              --expect MARKER
              --timeout-seconds 5...600
              --writing-kernel auto|on|off
              --performance fastest|high  (default: high)
              --keep-tab
              --no-wait
              --json

            Examples:
              gag run "このプロジェクトを分析して"
              gag tui
              gag tui --target gae "EC2側を確認して"
              gag run --target both --expect DONE "短く比較して。末尾にDONE"
              gag list --target both
              gag watch local/job_abc123 --json-lines
              gag result gae/job_abc123
              gag open local/job_abc123
            """
        )
    }
}

private struct CLIConfiguration {
    var localRoot: String
    var localNode: String
    var localCLI: String
    var gaeHost: String
    var gaeRoot: String
    var gaeNode: String
    var gaeCLI: String
    var sshExecutable: String
    var pollIntervalSeconds: TimeInterval
    var automationSocketURL: URL

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> CLIConfiguration {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let localRoot = environment["GAG_LOCAL_ROOT"]
            ?? URL(fileURLWithPath: home).appendingPathComponent("MyWorkspace2/GPT-Agent").path
        let localNode = environment["GAG_LOCAL_NODE"]
            ?? firstExecutable([
                URL(fileURLWithPath: home).appendingPathComponent(".local/bin/node").path,
                "/opt/homebrew/bin/node",
                "/usr/local/bin/node",
                "/usr/bin/node"
            ])
            ?? URL(fileURLWithPath: home).appendingPathComponent(".local/bin/node").path
        let socketPath = environment["APEXTERM_AUTOMATION_SOCKET"]
            .map { NSString(string: $0).expandingTildeInPath }
        return CLIConfiguration(
            localRoot: localRoot,
            localNode: localNode,
            localCLI: environment["GAG_LOCAL_CLI"]
                ?? URL(fileURLWithPath: localRoot).appendingPathComponent("dist/cli.js").path,
            gaeHost: environment["GAG_GAE_HOST"] ?? "ubuntu@remote-host",
            gaeRoot: environment["GAG_GAE_ROOT"] ?? "/opt/gpt-agent",
            gaeNode: environment["GAG_GAE_NODE"] ?? "/usr/bin/node",
            gaeCLI: environment["GAG_GAE_CLI"] ?? "/opt/gpt-agent/dist/cli.js",
            sshExecutable: environment["GAG_SSH"] ?? "/usr/bin/ssh",
            pollIntervalSeconds: max(
                0.25,
                min(10, Double(environment["GAG_POLL_INTERVAL"] ?? "1") ?? 1)
            ),
            automationSocketURL: socketPath.map(URL.init(fileURLWithPath:))
                ?? ApexTermPaths.automationSocketURL()
        )
    }

    private static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }
}

private struct GagBackend {
    var target: GagTarget
    var configuration: CLIConfiguration

    func execute(arguments: [String], timeoutSeconds: TimeInterval = 30) throws -> ProcessResult {
        switch target {
        case .local:
            guard FileManager.default.isExecutableFile(atPath: configuration.localNode) else {
                throw CLIError.runtime("local node executable not found: \(configuration.localNode)")
            }
            guard FileManager.default.fileExists(atPath: configuration.localCLI) else {
                throw CLIError.runtime("local GAG CLI not found: \(configuration.localCLI)")
            }
            var environment = ProcessInfo.processInfo.environment
            if environment["DEVSPACE_WORKSPACE_ROOT"] == nil {
                environment["DEVSPACE_WORKSPACE_ROOT"] = FileManager.default.currentDirectoryPath
            }
            environment["DEVSPACE_BROWSER_BACKGROUND_MODE"] =
                environment["GAG_LOCAL_BROWSER_MODE"] ?? "background-window"
            return try ProcessRunner.run(
                executable: configuration.localNode,
                arguments: [configuration.localCLI] + arguments,
                environment: environment,
                currentDirectory: FileManager.default.currentDirectoryPath,
                timeoutSeconds: timeoutSeconds
            )

        case .gae:
            guard FileManager.default.isExecutableFile(atPath: configuration.sshExecutable) else {
                throw CLIError.runtime("ssh executable not found: \(configuration.sshExecutable)")
            }
            let remoteParts = [
                "cd",
                GagJobCodec.shellQuote(configuration.gaeRoot),
                "&&",
                "env",
                GagJobCodec.shellQuote("DEVSPACE_WORKSPACE_ROOT=\(configuration.gaeRoot)"),
                GagJobCodec.shellQuote(configuration.gaeNode),
                GagJobCodec.shellQuote(configuration.gaeCLI)
            ] + arguments.map(GagJobCodec.shellQuote)
            let remoteCommand = remoteParts.joined(separator: " ")
            return try ProcessRunner.run(
                executable: configuration.sshExecutable,
                arguments: [
                    "-n",
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=8",
                    "-o", "ServerAliveInterval=15",
                    "-o", "ServerAliveCountMax=2",
                    configuration.gaeHost,
                    remoteCommand
                ],
                environment: ProcessInfo.processInfo.environment,
                currentDirectory: FileManager.default.currentDirectoryPath,
                timeoutSeconds: timeoutSeconds
            )
        }
    }
}

private struct GagJobClient {
    var backend: GagBackend

    func start(options: RunOptions) throws -> String {
        var arguments = [
            "jobs", "start", "chatgpt-task",
            "--prompt", options.prompt,
            "--title", options.title,
            "--auto-submit",
            "--timeout-seconds", String(options.timeoutSeconds),
            "--writing-kernel", options.writingKernel,
            "--performance", options.performance.rawValue
        ]
        if let url = options.url { arguments += ["--url", url] }
        if let marker = options.expectedMarker { arguments += ["--expect", marker] }
        if options.keepTab { arguments.append("--keep-tab") }
        let result = try backend.execute(arguments: arguments, timeoutSeconds: 60)
        try result.requireSuccess(context: "start \(backend.target.displayName) job")
        guard let jobID = GagJobCodec.parseStartedJobID(result.standardOutput) else {
            throw CLIError.runtime(
                "\(backend.target.displayName) did not return a job ID: \(result.standardOutput.trimmedForError)"
            )
        }
        return jobID
    }

    func show(jobID: String) throws -> GagJobEnvelope {
        let result = try backend.execute(
            arguments: ["jobs", "show", jobID, "--events", "--json"],
            timeoutSeconds: 25
        )
        try result.requireSuccess(context: "read \(backend.target.displayName) job \(jobID)")
        do {
            return try GagJobCodec.decodeJobEnvelope(Data(result.standardOutput.utf8))
        } catch {
            throw CLIError.runtime(
                "invalid \(backend.target.displayName) job JSON: \(error.localizedDescription)"
            )
        }
    }

    func list() throws -> [GagJobRecord] {
        let result = try backend.execute(
            arguments: ["jobs", "list", "--all", "--json"],
            timeoutSeconds: 25
        )
        try result.requireSuccess(context: "list \(backend.target.displayName) jobs")
        do {
            return try GagJobCodec.decodeJobList(Data(result.standardOutput.utf8)).jobs
        } catch {
            throw CLIError.runtime(
                "invalid \(backend.target.displayName) job-list JSON: \(error.localizedDescription)"
            )
        }
    }

    func cancel(jobID: String) throws -> GagJobRecord {
        let result = try backend.execute(
            arguments: ["jobs", "cancel", jobID],
            timeoutSeconds: 25
        )
        try result.requireSuccess(context: "cancel \(backend.target.displayName) job \(jobID)")
        return try show(jobID: jobID).job
    }

    func resume(jobID: String) throws -> GagJobRecord {
        let result = try backend.execute(
            arguments: ["jobs", "resume", jobID],
            timeoutSeconds: 25
        )
        try result.requireSuccess(context: "resume \(backend.target.displayName) job \(jobID)")
        return try show(jobID: jobID).job
    }
}

private struct ProcessResult {
    var standardOutput: String
    var standardError: String
    var exitCode: Int32

    func requireSuccess(context: String) throws {
        guard exitCode == 0 else {
            let detail = standardError.trimmedForError.isEmpty
                ? standardOutput.trimmedForError
                : standardError.trimmedForError
            throw CLIError.runtime("\(context) failed (exit \(exitCode)): \(detail)")
        }
    }
}

private enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String,
        timeoutSeconds: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = DataCollector()
        let errorCollector = DataCollector()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outputCollector.append(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errorCollector.append(data) }
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw CLIError.runtime("failed to launch \(executable): \(error.localizedDescription)")
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
            process.waitUntilExit()
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw CLIError.timeout("process timed out after \(Int(timeoutSeconds)) seconds: \(executable)")
        }
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
        return ProcessResult(
            standardOutput: outputCollector.string,
            standardError: errorCollector.string,
            exitCode: process.terminationStatus
        )
    }
}

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct AgentRailReporter {
    var socketURL: URL

    func report(target: GagTarget, job: GagJobRecord) {
        let metrics = GagRuntimeMetrics.calculate(target: target, job: job)
        let message = job.error?.isEmpty == false ? job.error : job.currentStep
        let report = AgentRunReport(
            runID: GagJobCodec.stableRunID(target: target, jobID: job.id),
            provider: target.displayName,
            label: job.title,
            workingDirectory: job.workspaceRoot,
            state: job.status.agentRunState,
            progress: metrics.progress,
            message: message,
            estimatedCompletionAt: metrics.estimatedCompletionAt,
            estimatedInputTokens: metrics.tokens.input,
            estimatedOutputTokens: metrics.tokens.output,
            requestedPerformance: metrics.requestedPerformance,
            selectedModel: metrics.selectedModel,
            selectedModelLabel: metrics.selectedModelLabel,
            apiCostEstimate: metrics.apiCostEstimate,
            conversationURL: metrics.conversationURL,
            jobReference: metrics.reference
        )
        let request = AutomationRequest(
            clientID: "gag",
            action: .reportAgentRun(report: report)
        )
        _ = try? UnixAutomationClient.send(request, to: socketURL)
    }
}

private enum TargetSelection: String {
    case local
    case gae
    case both

    var targets: [GagTarget] {
        switch self {
        case .local: [.local]
        case .gae: [.gae]
        case .both: [.local, .gae]
        }
    }

    static func parse(_ value: String) throws -> TargetSelection {
        let normalized = value == "gag" ? "local" : value
        guard let result = TargetSelection(rawValue: normalized) else {
            throw CLIError.usage("--target must be local, gae, or both")
        }
        return result
    }
}

private struct RunOptions {
    var target: TargetSelection = .local
    var prompt = ""
    var title = ""
    var url: String?
    var expectedMarker: String?
    var timeoutSeconds = 600
    var writingKernel = "auto"
    var performance: GagPerformance = .high
    var keepTab = false
    var noWait = false
    var json = false

    static func parse(_ arguments: [String]) throws -> RunOptions {
        var options = RunOptions()
        var positional: [String] = []
        var explicitPrompt: String?
        var index = 0
        var positionalOnly = false
        while index < arguments.count {
            let argument = arguments[index]
            if positionalOnly {
                positional.append(argument)
                index += 1
                continue
            }
            switch argument {
            case "--":
                positionalOnly = true
                index += 1
            case "--target":
                options.target = try TargetSelection.parse(try value(after: index, in: arguments, option: argument))
                index += 2
            case "--prompt", "-p":
                explicitPrompt = try value(after: index, in: arguments, option: argument)
                index += 2
            case "--title":
                options.title = try value(after: index, in: arguments, option: argument)
                index += 2
            case "--url":
                options.url = try value(after: index, in: arguments, option: argument)
                index += 2
            case "--expect":
                options.expectedMarker = try value(after: index, in: arguments, option: argument)
                index += 2
            case "--timeout-seconds":
                let raw = try value(after: index, in: arguments, option: argument)
                guard let timeout = Int(raw), (5...600).contains(timeout) else {
                    throw CLIError.usage("--timeout-seconds must be 5...600")
                }
                options.timeoutSeconds = timeout
                index += 2
            case "--writing-kernel":
                let mode = try value(after: index, in: arguments, option: argument)
                guard ["auto", "on", "off"].contains(mode) else {
                    throw CLIError.usage("--writing-kernel must be auto, on, or off")
                }
                options.writingKernel = mode
                index += 2
            case "--performance":
                let raw = try value(after: index, in: arguments, option: argument)
                guard let performance = GagPerformance.parse(raw) else {
                    throw CLIError.usage("--performance must be fastest or high")
                }
                options.performance = performance
                index += 2
            case "--keep-tab":
                options.keepTab = true
                index += 1
            case "--no-wait":
                options.noWait = true
                index += 1
            case "--json":
                options.json = true
                index += 1
            default:
                if argument.hasPrefix("-") {
                    throw CLIError.usage("unknown run option: \(argument)")
                }
                positional.append(argument)
                index += 1
            }
        }

        let combined = ([explicitPrompt].compactMap { $0 } + positional).joined(separator: " ")
        let stdinPrompt: String
        if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           isatty(STDIN_FILENO) == 0 {
            stdinPrompt = String(
                data: FileHandle.standardInput.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        } else {
            stdinPrompt = ""
        }
        options.prompt = (combined.isEmpty ? stdinPrompt : combined)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !options.prompt.isEmpty else {
            throw CLIError.usage("run requires a prompt argument, --prompt, or stdin")
        }
        if options.title.isEmpty {
            let singleLine = options.prompt
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            options.title = "ApexTerm: \(String(singleLine.prefix(72)))"
        }
        return options
    }
}

private struct ReferenceOptions {
    var reference: GagJobReference
    var json: Bool

    static func parse(_ arguments: [String], command: String) throws -> ReferenceOptions {
        var target: GagTarget = .local
        var json = false
        var referenceValue: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--target":
                let value = try value(after: index, in: arguments, option: "--target")
                guard value != "both",
                      let parsed = GagTarget(rawValue: value == "gag" ? "local" : value) else {
                    throw CLIError.usage("--target must be local or gae for \(command)")
                }
                target = parsed
                index += 2
            case "--json":
                json = true
                index += 1
            default:
                if referenceValue != nil {
                    throw CLIError.usage("\(command) accepts one job reference")
                }
                referenceValue = arguments[index]
                index += 1
            }
        }
        guard let referenceValue,
              let reference = GagJobReference.parse(referenceValue, defaultTarget: target) else {
            throw CLIError.usage("\(command) requires JOB_ID or local|gae/JOB_ID")
        }
        return ReferenceOptions(reference: reference, json: json)
    }
}

private struct WatchOptions {
    var reference: GagJobReference
    var intervalSeconds: TimeInterval
    var timeoutSeconds: TimeInterval?
    var jsonLines: Bool

    static func parse(
        _ arguments: [String],
        defaultInterval: TimeInterval
    ) throws -> WatchOptions {
        var filtered: [String] = []
        var intervalSeconds = defaultInterval
        var timeoutSeconds: TimeInterval?
        var jsonLines = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--json-lines", "--json":
                jsonLines = true
                index += 1
            case "--interval-seconds":
                let raw = try value(
                    after: index,
                    in: arguments,
                    option: "--interval-seconds"
                )
                guard let interval = Double(raw),
                      (0.25...10).contains(interval) else {
                    throw CLIError.usage(
                        "--interval-seconds must be 0.25...10"
                    )
                }
                intervalSeconds = interval
                index += 2
            case "--timeout-seconds":
                let raw = try value(
                    after: index,
                    in: arguments,
                    option: "--timeout-seconds"
                )
                guard let timeout = Double(raw),
                      (5...86_400).contains(timeout) else {
                    throw CLIError.usage(
                        "--timeout-seconds must be 5...86400"
                    )
                }
                timeoutSeconds = timeout
                index += 2
            default:
                filtered.append(arguments[index])
                index += 1
            }
        }

        let parsed = try ReferenceOptions.parse(filtered, command: "watch")
        return WatchOptions(
            reference: parsed.reference,
            intervalSeconds: intervalSeconds,
            timeoutSeconds: timeoutSeconds,
            jsonLines: jsonLines || parsed.json
        )
    }
}

private struct ResumeOptions {
    var reference: GagJobReference
    var noWait = false
    var json = false
    var timeoutSeconds = 690

    static func parse(_ arguments: [String]) throws -> ResumeOptions {
        var filtered: [String] = []
        var noWait = false
        var json = false
        var timeoutSeconds = 690
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--no-wait":
                noWait = true
                index += 1
            case "--json":
                json = true
                index += 1
            case "--timeout-seconds":
                let raw = try value(after: index, in: arguments, option: "--timeout-seconds")
                guard let timeout = Int(raw), (5...690).contains(timeout) else {
                    throw CLIError.usage("--timeout-seconds must be 5...690")
                }
                timeoutSeconds = timeout
                index += 2
            default:
                filtered.append(arguments[index])
                index += 1
            }
        }
        let parsed = try ReferenceOptions.parse(filtered, command: "resume")
        return ResumeOptions(
            reference: parsed.reference,
            noWait: noWait,
            json: json || parsed.json,
            timeoutSeconds: timeoutSeconds
        )
    }
}

private struct ListOptions {
    var target: TargetSelection = .local
    var allPresets = false
    var json = false

    static func parse(_ arguments: [String]) throws -> ListOptions {
        var options = ListOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--target":
                options.target = try TargetSelection.parse(
                    try value(after: index, in: arguments, option: "--target")
                )
                index += 2
            case "--all-presets":
                options.allPresets = true
                index += 1
            case "--json":
                options.json = true
                index += 1
            default:
                throw CLIError.usage("unknown list option: \(arguments[index])")
            }
        }
        return options
    }
}

private struct DoctorOptions {
    var target: TargetSelection = .both
    var json = false

    static func parse(_ arguments: [String]) throws -> DoctorOptions {
        var options = DoctorOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--target":
                options.target = try TargetSelection.parse(
                    try value(after: index, in: arguments, option: "--target")
                )
                index += 2
            case "--json":
                options.json = true
                index += 1
            default:
                throw CLIError.usage("unknown doctor option: \(arguments[index])")
            }
        }
        return options
    }
}

private struct TUIOptions {
    var target: TargetSelection = .local
    var targetWasExplicit = false
    var prompt = ""
    var timeoutSeconds = 600
    var writingKernel = "auto"
    var performance: GagPerformance = .high
    var performanceWasExplicit = false
    var expectedMarker: String?
    var keepTab = true

    static func parse(_ arguments: [String]) throws -> TUIOptions {
        var options = TUIOptions()
        var positional: [String] = []
        var index = 0
        var positionalOnly = false
        while index < arguments.count {
            let argument = arguments[index]
            if positionalOnly {
                positional.append(argument)
                index += 1
                continue
            }
            switch argument {
            case "--":
                positionalOnly = true
                index += 1
            case "--target":
                options.target = try TargetSelection.parse(
                    try value(after: index, in: arguments, option: argument)
                )
                options.targetWasExplicit = true
                index += 2
            case "--timeout-seconds":
                let raw = try value(after: index, in: arguments, option: argument)
                guard let timeout = Int(raw), (5...600).contains(timeout) else {
                    throw CLIError.usage("--timeout-seconds must be 5...600")
                }
                options.timeoutSeconds = timeout
                index += 2
            case "--writing-kernel":
                let mode = try value(after: index, in: arguments, option: argument)
                guard ["auto", "on", "off"].contains(mode) else {
                    throw CLIError.usage("--writing-kernel must be auto, on, or off")
                }
                options.writingKernel = mode
                index += 2
            case "--performance":
                let raw = try value(after: index, in: arguments, option: argument)
                guard let performance = GagPerformance.parse(raw) else {
                    throw CLIError.usage("--performance must be fastest or high")
                }
                options.performance = performance
                options.performanceWasExplicit = true
                index += 2
            case "--expect":
                options.expectedMarker = try value(after: index, in: arguments, option: argument)
                index += 2
            case "--close-tab":
                options.keepTab = false
                index += 1
            default:
                if argument.hasPrefix("-") {
                    throw CLIError.usage("unknown tui option: \(argument)")
                }
                positional.append(argument)
                index += 1
            }
        }
        options.prompt = positional.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return options
    }
}

private struct GagTUIRenderer {
    private let colorEnabled = ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    func clear() {
        write("\u{001B}[2J\u{001B}[H")
    }

    func renderWelcome(target: TargetSelection) {
        clear()
        let width = contentWidth
        print(topBorder(width: width))
        print(boxLine("✦  APEX GAG · AGENT STUDIO  ♡", width: width, style: .pink))
        print(boxLine("Natural-language control for GAG / GAE", width: width, style: .muted))
        print(boxLine("Target  \(targetBadge(target))", width: width, style: .plain))
        print(separator(width: width))
        print(boxLine("Tell the agent what to do. Multi-byte Japanese input is supported.", width: width, style: .muted))
        print(bottomBorder(width: width))
        print("")
    }

    func printPromptLabel(_ label: String) {
        print("\(paint("✦", .pink)) \(paint(label, .bold))  › ", terminator: "")
        fflush(stdout)
    }

    func renderTargetChoice() {
        print("")
        print("\(paint("Target", .bold))  \(paint("1", .pink)) GAG   \(paint("2", .cyan)) GAE   \(paint("3", .purple)) BOTH")
        print("Choose [1] › ", terminator: "")
        fflush(stdout)
    }

    func renderPerformanceChoice() {
        print("")
        print("\(paint("応答性能", .bold))  \(paint("1", .pink)) 最速   \(paint("2", .purple)) 高い")
        print("Choose [2] › ", terminator: "")
        fflush(stdout)
    }

    func renderDashboard(prompt: String, jobs: [TargetedJob]) {
        clear()
        let width = contentWidth
        print(topBorder(width: width))
        print(boxLine("✦  APEX GAG · LIVE RUN  ♡", width: width, style: .pink))
        print(boxLine(fit(prompt.replacingOccurrences(of: "\n", with: " "), width: width - 4), width: width, style: .muted))
        print(bottomBorder(width: width))
        print("")
        for item in jobs {
            renderJobCard(item, width: width)
            print("")
        }
        print(paint("  Live data · ETA and tokens are estimates · Ctrl+C leaves the job running", .muted))
        fflush(stdout)
    }

    func renderFinished(prompt: String, jobs: [TargetedJob]) {
        renderDashboard(prompt: prompt, jobs: jobs)
        let success = jobs.allSatisfy { $0.job.status == .succeeded }
        print("")
        print(
            success
                ? paint("  ✦ Done! The agent brought your result back. ♡", .green)
                : paint("  ✦ Run finished with an action or error state.", .yellow)
        )
    }

    func printFooter(_ text: String) {
        print("")
        print(paint("  \(text)", .muted))
        print("  › ", terminator: "")
        fflush(stdout)
    }

    private func renderJobCard(_ item: TargetedJob, width: Int) {
        let metrics = GagRuntimeMetrics.calculate(target: item.target, job: item.job)
        let inner = max(40, width - 2)
        let status = statusMark(item.job.status)
        print("╭" + String(repeating: "─", count: inner) + "╮")
        print(boxLine("\(status)  \(item.target.displayName)  ·  \(item.job.status.rawValue)", width: width, style: .bold))
        print(boxLine(fit(item.job.currentStep, width: inner - 3), width: width, style: .plain))

        let barWidth = max(12, min(36, inner - 22))
        let filled = min(barWidth, max(0, Int((metrics.progress * Double(barWidth)).rounded())))
        let bar = String(repeating: "━", count: filled) + String(repeating: "─", count: barWidth - filled)
        let progressText = String(format: "%3d%%", Int(metrics.progress * 100))
        print(boxLine("\(paint(bar, .purple))  \(progressText)", width: width, style: .plain))

        let elapsed = formatDuration(metrics.elapsedSeconds)
        let eta = metrics.estimatedRemainingSeconds.map { "約\(formatDuration($0))" } ?? "waiting"
        let complete = metrics.estimatedCompletionAt?.formatted(date: .omitted, time: .shortened) ?? "—"
        print(boxLine("Elapsed \(elapsed)   ETA \(eta)   Complete \(complete)", width: width, style: .muted))
        print(boxLine(
            "Token推定  Input ~\(formatTokens(metrics.tokens.input))   Output ~\(formatTokens(metrics.tokens.output))   Total ~\(formatTokens(metrics.tokens.total))",
            width: width,
            style: .muted
        ))
        print(boxLine(
            "応答性能  要求 \(metrics.requestedPerformance.displayName)   実モデル \(metrics.selectedModelLabel ?? metrics.selectedModel ?? "選択中")",
            width: width,
            style: .cyan
        ))
        if let cost = metrics.apiCostEstimate {
            let value = cost.isRegistered
                ? "API換算  \(formatYenRange(cost.jpy, cost.maxJpy))   \(cost.pricingLabel ?? cost.pricingModel ?? "registered")"
                : "API換算  単価未登録   \(cost.selectedModel ?? cost.requestedModel ?? "unknown model")"
            print(boxLine(value, width: width, style: cost.isRegistered ? .muted : .yellow))
        }
        print(boxLine(metrics.reference, width: width, style: .muted))
        if let url = metrics.conversationURL {
            print(boxLine("Chat  \(hyperlink(url: url, label: "Open running Chat ↗"))", width: width, style: .cyan))
            print(boxLine("Command  gag open \(metrics.reference)", width: width, style: .muted))
        }
        print("╰" + String(repeating: "─", count: inner) + "╯")
    }

    private var contentWidth: Int {
        max(58, min(104, terminalWidth - 4))
    }

    private var terminalWidth: Int {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        return 88
    }

    private func topBorder(width: Int) -> String {
        "╭" + String(repeating: "─", count: max(1, width - 2)) + "╮"
    }

    private func bottomBorder(width: Int) -> String {
        "╰" + String(repeating: "─", count: max(1, width - 2)) + "╯"
    }

    private func separator(width: Int) -> String {
        "├" + String(repeating: "─", count: max(1, width - 2)) + "┤"
    }

    private func boxLine(_ value: String, width: Int, style: TUIColor) -> String {
        let inner = max(1, width - 4)
        let clipped = fit(value, width: inner)
        let padding = max(0, inner - stripANSI(clipped).count)
        return "│ " + paint(clipped, style) + String(repeating: " ", count: padding) + " │"
    }

    private func targetBadge(_ target: TargetSelection) -> String {
        switch target {
        case .local: paint("● GAG", .pink)
        case .gae: paint("● GAE", .cyan)
        case .both: paint("● GAG + GAE", .purple)
        }
    }

    private func statusMark(_ status: GagJobStatus) -> String {
        switch status {
        case .queued: paint("◌", .yellow)
        case .running: paint("●", .purple)
        case .succeeded: paint("✓", .green)
        case .failed: paint("×", .red)
        case .cancelling, .cancelled: paint("■", .muted)
        case .waitingApproval: paint("!", .yellow)
        case .interrupted: paint("◇", .yellow)
        }
    }

    private func fit(_ value: String, width: Int) -> String {
        guard width > 1 else { return "" }
        let clean = value.replacingOccurrences(of: "\r", with: " ")
        if stripANSI(clean).count <= width { return clean }
        return String(clean.prefix(max(1, width - 1))) + "…"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value < 60 { return "\(value)s" }
        if value < 3600 { return "\(value / 60)m\(value % 60)s" }
        return "\(value / 3600)h\((value % 3600) / 60)m"
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return String(value)
    }

    private func hyperlink(url: URL, label: String) -> String {
        "\u{001B}]8;;\(url.absoluteString)\u{0007}\(label)\u{001B}]8;;\u{0007}"
    }

    private func paint(_ value: String, _ color: TUIColor) -> String {
        guard colorEnabled, let code = color.code else { return value }
        return "\u{001B}[\(code)m\(value)\u{001B}[0m"
    }

    private func stripANSI(_ value: String) -> String {
        value.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*m|\u{001B}\\]8;;.*?\u{0007}",
            with: "",
            options: .regularExpression
        )
    }

    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    private enum TUIColor {
        case plain
        case muted
        case bold
        case pink
        case purple
        case cyan
        case green
        case yellow
        case red

        var code: String? {
            switch self {
            case .plain: nil
            case .muted: "38;5;245"
            case .bold: "1;38;5;255"
            case .pink: "1;38;5;213"
            case .purple: "1;38;5;141"
            case .cyan: "1;38;5;117"
            case .green: "1;38;5;120"
            case .yellow: "1;38;5;228"
            case .red: "1;38;5;203"
            }
        }
    }
}

private enum GagChatOpenResult {
    case focused
    case opened
}

private enum GagChatLinkLauncher {
    static func open(url: URL) throws -> GagChatOpenResult {
        let prefix = normalizedPrefix(url)
        let browsers = [
            (name: "Brave Browser", safari: false),
            (name: "Google Chrome", safari: false),
            (name: "Safari", safari: true)
        ]
        for browser in browsers {
            if focusExisting(appName: browser.name, urlPrefix: prefix, safari: browser.safari) {
                return .focused
            }
        }
        for browser in browsers {
            if openNewTab(appName: browser.name, url: url, safari: browser.safari) {
                return .opened
            }
        }
        let result = try ProcessRunner.run(
            executable: "/usr/bin/open",
            arguments: [url.absoluteString],
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: FileManager.default.currentDirectoryPath,
            timeoutSeconds: 15
        )
        try result.requireSuccess(context: "open ChatGPT conversation")
        return .opened
    }

    private static func openNewTab(appName: String, url: URL, safari: Bool) -> Bool {
        let app = escape(appName)
        let safeURL = escape(url.absoluteString)
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
        if application \"\(app)\" is running then
            tell application \"\(app)\"
        \(body)
            end tell
        end if
        return \"missing\"
        """
        guard let result = try? ProcessRunner.run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", script],
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: FileManager.default.currentDirectoryPath,
            timeoutSeconds: 5
        ), result.exitCode == 0 else {
            return false
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "opened"
    }

    private static func normalizedPrefix(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private static func focusExisting(appName: String, urlPrefix: String, safari: Bool) -> Bool {
        let app = escape(appName)
        let url = escape(urlPrefix)
        let body: String
        if safari {
            body = """
                repeat with w in windows
                    repeat with i from 1 to count of tabs of w
                        if URL of tab i of w starts with "\(url)" then
                            set current tab of w to tab i of w
                            set index of w to 1
                            activate
                            return "focused"
                        end if
                    end repeat
                end repeat
            """
        } else {
            body = """
                repeat with w in windows
                    repeat with i from 1 to count of tabs of w
                        if URL of tab i of w starts with "\(url)" then
                            set active tab index of w to i
                            set index of w to 1
                            activate
                            return "focused"
                        end if
                    end repeat
                end repeat
            """
        }
        let script = """
        if application "\(app)" is running then
            tell application "\(app)"
        \(body)
            end tell
        end if
        return "missing"
        """
        guard let result = try? ProcessRunner.run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", script],
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: FileManager.default.currentDirectoryPath,
            timeoutSeconds: 5
        ), result.exitCode == 0 else {
            return false
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "focused"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct BrowserReadiness {
    var enabled: Bool
    var browserReady: Bool
    var missing: [String]

    static func parse(_ text: String) -> BrowserReadiness {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return BrowserReadiness(enabled: false, browserReady: false, missing: ["invalid computer doctor JSON"])
        }
        let enabled = object["enabled"] as? Bool ?? false
        let browser = object["browser"] as? [String: Any]
        let browserReady = browser?["ready"] as? Bool ?? false
        let missing = object["missingRequirements"] as? [String] ?? []
        return BrowserReadiness(enabled: enabled, browserReady: browserReady, missing: missing)
    }
}

private struct TargetedJob: Codable {
    var target: GagTarget
    var job: GagJobRecord
}

private struct TargetedJobEnvelope: Codable {
    var target: GagTarget
    var envelope: GagJobEnvelope
}

private struct DoctorTargetResult: Codable {
    var target: GagTarget
    var backendAvailable: Bool
    var computerUseEnabled: Bool
    var browserReady: Bool
    var detail: String
}

private struct DoctorReport: Codable {
    var apexTermConnected: Bool
    var targets: [DoctorTargetResult]
}

private func formatYenRange(_ minimum: Double?, _ maximum: Double?) -> String {
    guard let minimum else { return "単価未登録" }
    let resolvedMaximum = maximum ?? minimum
    let format: (Double) -> String = { value in
        if value >= 100 { return String(format: "¥%.0f", value) }
        if value >= 10 { return String(format: "¥%.1f", value) }
        return String(format: "¥%.2f", value)
    }
    return abs(resolvedMaximum - minimum) < 0.005
        ? format(minimum)
        : "\(format(minimum))–\(format(resolvedMaximum))"
}

private struct CLIError: Error {
    var message: String
    var exitCode: Int32

    static func usage(_ message: String) -> CLIError {
        CLIError(message: message + "\nRun 'gag help' for usage.", exitCode: 64)
    }

    static func runtime(_ message: String) -> CLIError {
        CLIError(message: message, exitCode: 1)
    }

    static func timeout(_ message: String) -> CLIError {
        CLIError(message: message, exitCode: 124)
    }
}

private func value(after index: Int, in arguments: [String], option: String) throws -> String {
    guard arguments.indices.contains(index + 1) else {
        throw CLIError.usage("\(option) requires a value")
    }
    return arguments[index + 1]
}

private extension String {
    var trimmedForError: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(800))
    }
}
