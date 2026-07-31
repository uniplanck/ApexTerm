import ApexTermCore
import Foundation

protocol AgentTransport: Sendable {
    func start(
        prompt: String,
        target: GagTarget,
        performance: GagPerformance,
        title: String,
        conversationURL: URL?
    ) async throws -> GagTargetedJob

    func updates(
        reference: String,
        initial: GagTargetedJob?
    ) -> AsyncThrowingStream<GagTargetedJob, Error>

    func cancel(reference: String) async throws -> GagTargetedJob
}

struct GagCLIAgentTransport: AgentTransport {
    private let client: AgentChatCLIClient
    private let fallbackPollInterval: Duration
    private let maximumConsecutiveFailures: Int

    init(
        client: AgentChatCLIClient = AgentChatCLIClient(),
        fallbackPollInterval: Duration = .seconds(1),
        maximumConsecutiveFailures: Int = 3
    ) {
        self.client = client
        self.fallbackPollInterval = fallbackPollInterval
        self.maximumConsecutiveFailures = maximumConsecutiveFailures
    }

    func start(
        prompt: String,
        target: GagTarget,
        performance: GagPerformance,
        title: String,
        conversationURL: URL?
    ) async throws -> GagTargetedJob {
        try await client.start(
            prompt: prompt,
            target: target,
            performance: performance,
            title: title,
            conversationURL: conversationURL
        )
    }

    func updates(
        reference: String,
        initial: GagTargetedJob?
    ) -> AsyncThrowingStream<GagTargetedJob, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var latest = initial
                if let initial {
                    continuation.yield(initial)
                    if Self.isFinished(initial) {
                        continuation.finish()
                        return
                    }
                }

                do {
                    for try await update in client.watch(reference: reference) {
                        guard !Task.isCancelled else { return }
                        if update != latest {
                            latest = update
                            continuation.yield(update)
                        }
                        if Self.isFinished(update) {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    do {
                        try await pollFallback(
                            reference: reference,
                            latest: latest,
                            continuation: continuation
                        )
                    } catch is CancellationError {
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func cancel(reference: String) async throws -> GagTargetedJob {
        try await client.cancel(reference: reference)
    }

    private func pollFallback(
        reference: String,
        latest: GagTargetedJob?,
        continuation: AsyncThrowingStream<GagTargetedJob, Error>.Continuation
    ) async throws {
        var latest = latest
        var consecutiveFailures = 0

        while !Task.isCancelled {
            do {
                let update = try await client.status(reference: reference)
                consecutiveFailures = 0
                if update != latest {
                    latest = update
                    continuation.yield(update)
                }
                if Self.isFinished(update) {
                    continuation.finish()
                    return
                }
                try await Task.sleep(for: fallbackPollInterval)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                consecutiveFailures += 1
                guard consecutiveFailures < maximumConsecutiveFailures else {
                    throw AgentChatRuntimeError.commandFailed(
                        "進捗取得に\(maximumConsecutiveFailures)回失敗しました: \(error.localizedDescription)"
                    )
                }
                try await Task.sleep(for: fallbackPollInterval)
            }
        }
    }

    private static func isFinished(_ update: GagTargetedJob) -> Bool {
        update.job.status.isTerminal
            || update.job.status == .waitingApproval
            || update.job.status == .interrupted
    }
}
