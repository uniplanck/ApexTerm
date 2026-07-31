import ApexTermCore
import Darwin
import Foundation
import SwiftTerm

struct BenchmarkMeasurement: Codable {
    let name: String
    let iterations: Int
    let elapsedMilliseconds: Double
    let operationsPerSecond: Double
    let metrics: [String: Double]?
    let detail: String
}

struct BenchmarkReport: Codable {
    let generatedAt: Date
    let operatingSystem: String
    let architecture: String
    let measurements: [BenchmarkMeasurement]
}

private final class PTYLatencyProbe: TerminalDelegate, LocalProcessDelegate, @unchecked Sendable {
    private(set) var terminal: Terminal!
    private(set) var process: LocalProcess!
    private let stateLock = NSLock()
    private var pendingStart: UInt64?
    private var pendingSemaphore: DispatchSemaphore?
    private var lastLatencyMilliseconds: Double?

    init(queue: DispatchQueue) {
        terminal = Terminal(delegate: self)
        process = LocalProcess(delegate: self, dispatchQueue: queue)
    }

    func arm() -> DispatchSemaphore {
        let semaphore = DispatchSemaphore(value: 0)
        stateLock.lock()
        pendingStart = DispatchTime.now().uptimeNanoseconds
        pendingSemaphore = semaphore
        lastLatencyMilliseconds = nil
        stateLock.unlock()
        return semaphore
    }

    func consumeLatency() -> Double? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let latency = lastLatencyMilliseconds
        lastLatencyMilliseconds = nil
        return latency
    }

    func send(_ text: String) {
        process.send(data: Array(text.utf8)[...])
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {}

    func dataReceived(slice: ArraySlice<UInt8>) {
        stateLock.lock()
        if !slice.isEmpty,
           let start = pendingStart,
           let semaphore = pendingSemaphore {
            lastLatencyMilliseconds = Double(
                DispatchTime.now().uptimeNanoseconds - start
            ) / 1_000_000
            pendingStart = nil
            pendingSemaphore = nil
            stateLock.unlock()
            semaphore.signal()
        } else {
            stateLock.unlock()
        }
        terminal.feed(buffer: slice)
    }

    func send(source: Terminal, data: ArraySlice<UInt8>) {
        process.send(data: data)
    }

    func getWindowSize() -> winsize {
        winsize(
            ws_row: UInt16(terminal.rows),
            ws_col: UInt16(terminal.cols),
            ws_xpixel: 16,
            ws_ypixel: 16
        )
    }

    func mouseModeChanged(source: Terminal) {}
    func hostCurrentDirectoryUpdated(source: Terminal) {}
    func colorChanged(source: Terminal, idx: Int) {}

    func createImageFromBitmap(
        source: Terminal,
        bytes: inout [UInt8],
        width: Int,
        height: Int
    ) {}
}

@main
enum ApexTermBench {
    static func main() async throws {
        var measurements: [BenchmarkMeasurement] = []
        measurements.append(benchmarkRiskEngine())
        measurements.append(benchmarkSplitTree())
        measurements.append(benchmarkCommandHistoryPersistence())
        measurements.append(benchmarkShellIntegrationRouting())
        measurements.append(try benchmarkPTYRoundTrip())
        measurements.append(benchmarkTerminalParser())
        measurements.append(benchmarkLargeScrollbackMemory())
        measurements.append(try await benchmarkWorkspacePersistence())

        let report = BenchmarkReport(
            generatedAt: Date(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture(),
            measurements: measurements
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let outputURL = URL(fileURLWithPath: "benchmark-report.json")
        try data.write(to: outputURL, options: [.atomic])

        for measurement in measurements {
            let extraMetrics = measurement.metrics?
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(String(format: "%.3f", $0.value))" }
                .joined(separator: ", ")
            let suffix = extraMetrics.map { " [\($0)]" } ?? ""
            print(
                "\(measurement.name): "
                    + String(
                        format: "%.3f ms, %.0f ops/s",
                        measurement.elapsedMilliseconds,
                        measurement.operationsPerSecond
                    )
                    + suffix
                    + " — \(measurement.detail)"
            )
        }

        let failures = performanceGateFailures(measurements)
        if !failures.isEmpty {
            for failure in failures {
                fputs("PERFORMANCE_GATE_FAILURE: \(failure)\n", stderr)
            }
            print("PERFORMANCE_GATE=FAIL")
            print("Report: \(outputURL.path)")
            Foundation.exit(3)
        }
        print("PERFORMANCE_GATE=PASS")
        print("Report: \(outputURL.path)")
    }

    private static func performanceGateFailures(
        _ measurements: [BenchmarkMeasurement]
    ) -> [String] {
        var failures: [String] = []
        let byName = Dictionary(uniqueKeysWithValues: measurements.map { ($0.name, $0) })

        if let p95 = byName["pty-input-to-output-latency"]?.metrics?["p95_ms"],
           p95 > 8 {
            failures.append("PTY p95 \(p95) ms exceeds 8 ms")
        }

        if let measurement = byName["workspace-save-load"] {
            let average = measurement.elapsedMilliseconds / Double(measurement.iterations)
            if average > 25 {
                failures.append("Workspace save/load average \(average) ms exceeds 25 ms")
            }
        }

        if let measurement = byName["large-scrollback-memory"],
           let growth = measurement.metrics?["rss_growth_mb"],
           growth > 64 {
            failures.append("Large scrollback RSS growth \(growth) MB exceeds 64 MB")
        }

        if let measurement = byName["terminal-parser-throughput"],
           let processed = measurement.metrics?["processed_mb"] {
            let seconds = measurement.elapsedMilliseconds / 1_000
            let throughput = seconds > 0 ? processed / seconds : 0
            if throughput < 10 {
                failures.append("Parser throughput \(throughput) MB/s is below 10 MB/s")
            }
        }

        if let measurement = byName["split-tree-mutation"],
           measurement.elapsedMilliseconds > 25 {
            failures.append("64-pane split mutation exceeds 25 ms")
        }

        return failures
    }

    private static func benchmarkRiskEngine() -> BenchmarkMeasurement {
        let engine = CommandRiskEngine()
        let commands = [
            "git status",
            "swift test",
            "npm run deploy",
            "git push origin main --force",
            "sudo rm -rf /",
            "wrangler d1 execute app --remote --command 'DELETE FROM users'"
        ]
        let iterations = 50_000
        var checksum = 0
        let start = DispatchTime.now().uptimeNanoseconds
        for index in 0..<iterations {
            checksum += engine.evaluate(commands[index % commands.count]).level.rawValue
        }
        let elapsed = milliseconds(since: start)
        precondition(checksum > 0)
        return measurement(
            name: "command-risk-evaluation",
            iterations: iterations,
            elapsedMilliseconds: elapsed,
            detail: "Six-rule mixed command workload"
        )
    }

    private static func benchmarkSplitTree() -> BenchmarkMeasurement {
        let rootID = UUID()
        var tree = SplitNode.pane(sessionID: rootID)
        var selectedID = rootID
        let iterations = SplitTreeOperations.maximumPaneCount - 1
        let start = DispatchTime.now().uptimeNanoseconds
        for index in 0..<iterations {
            let newID = UUID()
            tree = SplitTreeOperations.split(
                sessionID: selectedID,
                newSessionID: newID,
                axis: index.isMultiple(of: 2) ? .vertical : .horizontal,
                in: tree
            )
            selectedID = newID
        }
        let elapsed = milliseconds(since: start)
        precondition(SplitTreeOperations.sessionIDs(in: tree).count == iterations + 1)
        return measurement(
            name: "split-tree-mutation",
            iterations: iterations,
            elapsedMilliseconds: elapsed,
            detail: "Nested insertion up to the supported 64-pane workspace limit"
        )
    }

    private static func benchmarkPTYRoundTrip() throws -> BenchmarkMeasurement {
        let callbackQueue = DispatchQueue(
            label: "app.apexterm.bench.pty",
            qos: .userInteractive
        )
        let terminal = PTYLatencyProbe(queue: callbackQueue)
        terminal.process.startProcess(
            executable: "/bin/cat",
            args: [],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )
        defer { terminal.process.terminate() }
        Thread.sleep(forTimeInterval: 0.05)

        for _ in 0..<20 {
            let semaphore = terminal.arm()
            terminal.send("x")
            guard semaphore.wait(timeout: .now() + 1) == .success else {
                throw NSError(
                    domain: "ApexTermBench",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "PTY warm-up timed out"]
                )
            }
            _ = terminal.consumeLatency()
        }

        let iterations = 500
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        let totalStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            let semaphore = terminal.arm()
            terminal.send("x")
            guard semaphore.wait(timeout: .now() + 1) == .success,
                  let latency = terminal.consumeLatency() else {
                throw NSError(
                    domain: "ApexTermBench",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "PTY round-trip timed out"]
                )
            }
            samples.append(latency)
        }
        let elapsed = milliseconds(since: totalStart)
        let sorted = samples.sorted()
        let p50 = percentile(0.50, in: sorted)
        let p95 = percentile(0.95, in: sorted)
        let p99 = percentile(0.99, in: sorted)

        return measurement(
            name: "pty-input-to-output-latency",
            iterations: iterations,
            elapsedMilliseconds: elapsed,
            metrics: [
                "p50_ms": p50,
                "p95_ms": p95,
                "p99_ms": p99
            ],
            detail: "Real forkpty input to first returned output byte using /bin/cat"
        )
    }

    private static func benchmarkTerminalParser() -> BenchmarkMeasurement {
        let asciiLine = "\u{001B}[38;5;45mApexTerm output 0123456789\u{001B}[0m\r"
        let unicodeLine = "\u{001B}[38;2;120;180;255mApexTerm 日本語 🚀\u{001B}[0m\r"
        let group = String(repeating: asciiLine, count: 19) + unicodeLine
        let payload = Array(repeating: group, count: 1_000).joined()
        let bytes = Array(payload.utf8)
        let iterations = 10
        let sampleCount = 3

        func runSample(
            bytes: [UInt8],
            iterations: Int
        ) -> (wallMilliseconds: Double, cpuMilliseconds: Double) {
            let terminal = HeadlessTerminal(
                options: TerminalOptions(scrollback: 0)
            ) { _ in }
            let wallStart = DispatchTime.now().uptimeNanoseconds
            let cpuStart = processCPUMilliseconds()
            for _ in 0..<iterations {
                terminal.terminal.feed(buffer: bytes[...])
            }
            let cpuElapsed = max(0.001, processCPUMilliseconds() - cpuStart)
            return (
                wallMilliseconds: milliseconds(since: wallStart),
                cpuMilliseconds: cpuElapsed
            )
        }

        _ = runSample(bytes: bytes, iterations: iterations)
        let samples = (0..<sampleCount).map { _ in
            runSample(bytes: bytes, iterations: iterations)
        }
        let wallSamples = samples.map(\.wallMilliseconds).sorted()
        let cpuSamples = samples.map(\.cpuMilliseconds).sorted()
        let medianWallElapsed = wallSamples[wallSamples.count / 2]
        let medianCPUElapsed = cpuSamples[cpuSamples.count / 2]
        let megabytes = Double(bytes.count * iterations) / 1_000_000

        let unicodeStressBytes = Array(
            Array(repeating: unicodeLine, count: 5_000).joined().utf8
        )
        _ = runSample(bytes: unicodeStressBytes, iterations: 2)
        let unicodeStress = runSample(bytes: unicodeStressBytes, iterations: 4)
        let unicodeStressMegabytes = Double(unicodeStressBytes.count * 4) / 1_000_000
        let unicodeStressThroughput = unicodeStressMegabytes
            / max(unicodeStress.cpuMilliseconds / 1_000, 0.001)

        return measurement(
            name: "terminal-parser-throughput",
            iterations: iterations,
            elapsedMilliseconds: medianCPUElapsed,
            metrics: [
                "processed_mb": megabytes,
                "sample_count": Double(sampleCount),
                "cpu_median_ms": medianCPUElapsed,
                "cpu_min_ms": cpuSamples.first ?? medianCPUElapsed,
                "cpu_max_ms": cpuSamples.last ?? medianCPUElapsed,
                "wall_median_ms": medianWallElapsed,
                "wall_min_ms": wallSamples.first ?? medianWallElapsed,
                "wall_max_ms": wallSamples.last ?? medianWallElapsed,
                "unicode_stress_mb_s": unicodeStressThroughput
            ],
            detail: String(
                format: "%.2f MB parser-focused payload (95%% ASCII, 5%% Unicode) with scrollback disabled, CPU-time median of %d samples after warmup; wall median %.3f ms",
                megabytes,
                sampleCount,
                medianWallElapsed
            )
        )
    }

    private static func benchmarkLargeScrollbackMemory() -> BenchmarkMeasurement {
        let scrollbackLimit = 10_000
        let terminal = HeadlessTerminal(
            options: TerminalOptions(
                cols: 120,
                rows: 40,
                scrollback: scrollbackLimit
            )
        ) { _ in }
        let line = String(repeating: "ApexTerm 日本語 0123456789 ", count: 4) + "\r\n"
        let linesPerChunk = 1_000
        let chunk = Array(Array(repeating: line, count: linesPerChunk).joined().utf8)
        let chunkCount = 250
        let totalBytes = chunk.count * chunkCount
        let rssBefore = residentMemoryBytes()
        let start = DispatchTime.now().uptimeNanoseconds

        for _ in 0..<chunkCount {
            terminal.terminal.feed(buffer: chunk[...])
        }

        let elapsed = milliseconds(since: start)
        let rssAfter = residentMemoryBytes()
        let rssGrowth = rssAfter >= rssBefore ? rssAfter - rssBefore : 0

        return measurement(
            name: "large-scrollback-memory",
            iterations: chunkCount * linesPerChunk,
            elapsedMilliseconds: elapsed,
            metrics: [
                "input_mb": Double(totalBytes) / 1_000_000,
                "rss_growth_mb": Double(rssGrowth) / 1_000_000,
                "configured_scrollback_lines": Double(scrollbackLimit)
            ],
            detail: "Bounded 10,000-line scrollback under 250,000 lines of ANSI/Unicode output"
        )
    }

    private static func benchmarkShellIntegrationRouting() -> BenchmarkMeasurement {
        let line = "\u{001B}[38;5;45mApexTerm output 0123456789\u{001B}[0m\r\n"
        let bytes = Array(Array(repeating: line, count: 64).joined().utf8)
        let iterations = 10_000

        var baselineParser = ShellIntegrationStreamParser()
        var baselineChecksum = 0
        let baselineStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            baselineChecksum += baselineParser.feed(bytes[...]).count
        }
        let baselineElapsed = milliseconds(since: baselineStart)

        let fastParser = ShellIntegrationStreamParser()
        var fastChecksum = 0
        let fastStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            if fastParser.canBypass(bytes[...]) {
                fastChecksum += 1
            }
        }
        let fastElapsed = milliseconds(since: fastStart)
        precondition(baselineChecksum == iterations && fastChecksum == iterations)

        return measurement(
            name: "shell-integration-routing",
            iterations: iterations,
            elapsedMilliseconds: fastElapsed,
            metrics: [
                "baseline_segmenting_ms": baselineElapsed,
                "zero_copy_fast_path_ms": fastElapsed,
                "speedup_x": baselineElapsed / max(fastElapsed, 0.001),
                "payload_kb": Double(bytes.count) / 1_000
            ],
            detail: "Ordinary ANSI PTY chunks bypass OSC 133 segmentation and data-array allocation"
        )
    }

    private static func benchmarkCommandHistoryPersistence() -> BenchmarkMeasurement {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApexTermHistoryBench-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let syncURL = root.appendingPathComponent("sync.json")
        let deferredURL = root.appendingPathComponent("deferred.json")
        let syncRecorder = CommandHistoryRecorder(fileURL: syncURL, maximumCount: 200)
        let deferredRecorder = CommandHistoryRecorder(fileURL: deferredURL, maximumCount: 200)
        let output = String(repeating: "ApexTerm output 日本語 0123456789 ", count: 64)
        let records = (0..<200).map { index in
            CommandExecutionRecord(
                sessionID: UUID(),
                command: "benchmark-command-\(index)",
                output: output,
                exitCode: index.isMultiple(of: 17) ? 1 : 0,
                startedAt: Date(timeIntervalSince1970: Double(index)),
                finishedAt: Date(timeIntervalSince1970: Double(index) + 0.1)
            )
        }

        let syncStart = DispatchTime.now().uptimeNanoseconds
        for record in records {
            syncRecorder.append(record)
        }
        let syncElapsed = milliseconds(since: syncStart)

        let deferredStart = DispatchTime.now().uptimeNanoseconds
        for record in records {
            deferredRecorder.appendDeferred(record)
        }
        let enqueueElapsed = milliseconds(since: deferredStart)
        deferredRecorder.flush()
        let totalElapsed = milliseconds(since: deferredStart)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: deferredURL.path)[.size] as? NSNumber)?
            .doubleValue ?? 0

        return measurement(
            name: "command-history-ui-append",
            iterations: records.count,
            elapsedMilliseconds: enqueueElapsed,
            metrics: [
                "sync_total_ms": syncElapsed,
                "deferred_enqueue_ms": enqueueElapsed,
                "deferred_flush_total_ms": totalElapsed,
                "ui_path_speedup_x": syncElapsed / max(enqueueElapsed, 0.001),
                "persisted_kb": fileSize / 1_000
            ],
            detail: "200 bounded history records; deferred enqueue represents the UI-path cost"
        )
    }

    private static func benchmarkWorkspacePersistence() async throws -> BenchmarkMeasurement {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApexTermBench-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(fileURL: directory.appendingPathComponent("workspaces.json"))

        let sessions = (0..<64).map { index in
            TerminalSession(title: "Session \(index)", workingDirectory: "/tmp/project-\(index)")
        }
        let workspaces = sessions.map { session in
            Workspace(
                name: session.title,
                rootDirectory: session.workingDirectory,
                layout: .pane(sessionID: session.id)
            )
        }
        let document = WorkspaceDocument(workspaces: workspaces, sessions: sessions)
        let iterations = 100
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            try await store.save(document)
            _ = try await store.load()
        }
        let elapsed = milliseconds(since: start)
        return measurement(
            name: "workspace-save-load",
            iterations: iterations,
            elapsedMilliseconds: elapsed,
            detail: "64 workspaces and 64 sessions per round trip"
        )
    }

    private static func measurement(
        name: String,
        iterations: Int,
        elapsedMilliseconds: Double,
        metrics: [String: Double]? = nil,
        detail: String
    ) -> BenchmarkMeasurement {
        let seconds = elapsedMilliseconds / 1_000
        return BenchmarkMeasurement(
            name: name,
            iterations: iterations,
            elapsedMilliseconds: elapsedMilliseconds,
            operationsPerSecond: seconds > 0 ? Double(iterations) / seconds : 0,
            metrics: metrics,
            detail: detail
        )
    }

    private static func percentile(_ percentile: Double, in sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = percentile * Double(sorted.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        guard lower != upper else { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size
                / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }

    private static func processCPUMilliseconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = Double(usage.ru_utime.tv_sec) * 1_000
            + Double(usage.ru_utime.tv_usec) / 1_000
        let system = Double(usage.ru_stime.tv_sec) * 1_000
            + Double(usage.ru_stime.tv_usec) / 1_000
        return user + system
    }

    private static func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
