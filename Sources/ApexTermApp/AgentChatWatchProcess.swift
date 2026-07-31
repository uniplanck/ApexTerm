import ApexTermCore
import Darwin
import Foundation

final class AgentChatWatchProcess: @unchecked Sendable {
    private typealias Continuation = AsyncThrowingStream<GagTargetedJob, Error>.Continuation

    private let lock = NSLock()
    private var process: Process?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var continuation: Continuation?
    private var isFinished = false

    func stream(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) -> AsyncThrowingStream<GagTargetedJob, Error> {
        AsyncThrowingStream { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()

            continuation.onTermination = { [self] _ in
                cancel()
            }

            do {
                try start(
                    executable: executable,
                    arguments: arguments,
                    environment: environment
                )
            } catch {
                finish(throwing: error)
            }
        }
    }

    private func start(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputHandle.readabilityHandler = { [weak self] handle in
            self?.consumeOutput(handle.availableData)
        }
        errorHandle.readabilityHandler = { [weak self] handle in
            self?.consumeError(handle.availableData)
        }
        process.terminationHandler = { [weak self] process in
            self?.processDidTerminate(process)
        }

        lock.lock()
        self.process = process
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
        lock.unlock()

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            throw AgentChatRuntimeError.launchFailed(error.localizedDescription)
        }
    }

    private func consumeOutput(_ data: Data) {
        guard !data.isEmpty else { return }

        var lines: [Data] = []
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        outputBuffer.append(data)
        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer.prefix(upTo: newlineIndex)
            outputBuffer.removeSubrange(...newlineIndex)
            if !line.isEmpty {
                lines.append(Data(line))
            }
        }
        let continuation = self.continuation
        lock.unlock()

        for line in lines {
            do {
                let update = try JSONDecoder().decode(
                    GagTargetedJob.self,
                    from: line
                )
                continuation?.yield(update)
            } catch {
                cancel()
                finish(
                    throwing: AgentChatRuntimeError.invalidResponse(
                        "GAG watch returned invalid JSON: \(error.localizedDescription)"
                    )
                )
                return
            }
        }
    }

    private func consumeError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        if !isFinished {
            errorBuffer.append(data)
        }
        lock.unlock()
    }

    private func processDidTerminate(_ process: Process) {
        let outputHandle: FileHandle?
        let errorHandle: FileHandle?
        lock.lock()
        outputHandle = self.outputHandle
        errorHandle = self.errorHandle
        self.outputHandle = nil
        self.errorHandle = nil
        self.process = nil
        lock.unlock()

        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        if let outputHandle {
            consumeOutput(outputHandle.readDataToEndOfFile())
        }
        if let errorHandle {
            consumeError(errorHandle.readDataToEndOfFile())
        }
        flushTrailingOutput()

        switch process.terminationStatus {
        case 0, 2, 3:
            finish()
        default:
            let detail: String
            lock.lock()
            detail = String(data: errorBuffer, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            lock.unlock()
            finish(
                throwing: AgentChatRuntimeError.commandFailed(
                    detail.isEmpty
                        ? "gag watch exited with \(process.terminationStatus)"
                        : detail
                )
            )
        }
    }

    private func flushTrailingOutput() {
        let trailing: Data
        let continuation: Continuation?
        lock.lock()
        trailing = outputBuffer
        outputBuffer.removeAll(keepingCapacity: false)
        continuation = self.continuation
        lock.unlock()

        guard !trailing.isEmpty else { return }
        do {
            let update = try JSONDecoder().decode(
                GagTargetedJob.self,
                from: trailing
            )
            continuation?.yield(update)
        } catch {
            finish(
                throwing: AgentChatRuntimeError.invalidResponse(
                    "GAG watch returned incomplete JSON: \(error.localizedDescription)"
                )
            )
        }
    }

    private func finish(throwing error: Error? = nil) {
        let continuation: Continuation?
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
    }

    private func cancel() {
        let process: Process?
        lock.lock()
        process = self.process
        lock.unlock()

        guard let process, process.isRunning else {
            finish()
            return
        }
        process.terminate()
        let processID = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
            if process.isRunning {
                kill(processID, SIGKILL)
            }
        }
    }
}
