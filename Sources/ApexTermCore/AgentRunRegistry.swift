import Foundation

public enum AgentRunEvent: Equatable, Sendable {
    case started(at: Date)
    case progress(value: Double, message: String?)
    case approvalRequested(message: String)
    case resumed(message: String?)
    case succeeded(message: String?)
    case failed(message: String)
    case cancelled(message: String?)
    case disconnected(message: String?)
}

public actor AgentRunRegistry {
    private var runs: [UUID: AgentRun] = [:]

    public init() {}

    @discardableResult
    public func register(
        provider: String,
        label: String,
        workingDirectory: String,
        sessionID: UUID? = nil
    ) -> AgentRun {
        let run = AgentRun(
            provider: provider,
            label: label,
            workingDirectory: workingDirectory,
            state: .queued,
            progress: 0,
            lastEvent: "Queued",
            sessionID: sessionID
        )
        runs[run.id] = run
        return run
    }

    @discardableResult
    public func handle(runID: UUID, event: AgentRunEvent, now: Date = Date()) -> AgentRun? {
        guard var run = runs[runID] else { return nil }

        switch event {
        case let .started(at):
            guard !isTerminal(run.state) else { return run }
            run.state = .running
            run.startedAt = at
            run.lastEvent = "Started"

        case let .progress(value, message):
            guard run.state == .running else { return run }
            run.progress = min(1, max(0, value))
            run.lastEvent = message ?? "Running"

        case let .approvalRequested(message):
            guard run.state == .running else { return run }
            run.state = .waitingApproval
            run.lastEvent = message

        case let .resumed(message):
            guard run.state == .waitingApproval || run.state == .disconnected else { return run }
            run.state = .running
            run.lastEvent = message ?? "Resumed"

        case let .succeeded(message):
            guard !isTerminal(run.state) else { return run }
            run.state = .succeeded
            run.progress = 1
            run.lastEvent = message ?? "Succeeded"

        case let .failed(message):
            guard !isTerminal(run.state) else { return run }
            run.state = .failed
            run.lastEvent = message

        case let .cancelled(message):
            guard !isTerminal(run.state) else { return run }
            run.state = .cancelled
            run.lastEvent = message ?? "Cancelled"

        case let .disconnected(message):
            guard !isTerminal(run.state) else { return run }
            run.state = .disconnected
            run.lastEvent = message ?? "Disconnected"
        }

        run.updatedAt = now
        runs[run.id] = run
        return run
    }

    @discardableResult
    public func apply(report: AgentRunReport) -> AgentRun? {
        if var existing = runs[report.runID] {
            guard !isTerminal(existing.state) || existing.state == report.state else {
                return existing
            }
            existing.provider = report.provider ?? existing.provider
            existing.label = report.label ?? existing.label
            existing.workingDirectory = report.workingDirectory ?? existing.workingDirectory
            existing.sessionID = report.sessionID ?? existing.sessionID
            existing.estimatedCompletionAt = report.estimatedCompletionAt ?? existing.estimatedCompletionAt
            existing.estimatedInputTokens = report.estimatedInputTokens ?? existing.estimatedInputTokens
            existing.estimatedOutputTokens = report.estimatedOutputTokens ?? existing.estimatedOutputTokens
            existing.requestedPerformance = report.requestedPerformance ?? existing.requestedPerformance
            existing.selectedModel = report.selectedModel ?? existing.selectedModel
            existing.selectedModelLabel = report.selectedModelLabel ?? existing.selectedModelLabel
            existing.apiCostEstimate = report.apiCostEstimate ?? existing.apiCostEstimate
            existing.conversationURL = report.conversationURL ?? existing.conversationURL
            existing.jobReference = report.jobReference ?? existing.jobReference
            existing.state = report.state
            if let progress = report.progress {
                existing.progress = min(1, max(0, progress))
            }
            if report.state == .succeeded {
                existing.progress = 1
            }
            existing.lastEvent = report.message ?? defaultMessage(for: report.state)
            if existing.startedAt == nil,
               report.state == .running || report.state == .waitingApproval {
                existing.startedAt = report.timestamp
            }
            existing.updatedAt = report.timestamp
            runs[existing.id] = existing
            return existing
        }

        guard let provider = report.provider?.trimmingCharacters(in: .whitespacesAndNewlines),
              !provider.isEmpty,
              let label = report.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              let workingDirectory = report.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workingDirectory.isEmpty else {
            return nil
        }

        let progress = report.state == .succeeded
            ? 1
            : report.progress.map { min(1, max(0, $0)) }
        let run = AgentRun(
            id: report.runID,
            provider: provider,
            label: label,
            workingDirectory: workingDirectory,
            state: report.state,
            progress: progress,
            lastEvent: report.message ?? defaultMessage(for: report.state),
            sessionID: report.sessionID,
            startedAt: report.state == .queued ? nil : report.timestamp,
            estimatedCompletionAt: report.estimatedCompletionAt,
            estimatedInputTokens: report.estimatedInputTokens,
            estimatedOutputTokens: report.estimatedOutputTokens,
            requestedPerformance: report.requestedPerformance,
            selectedModel: report.selectedModel,
            selectedModelLabel: report.selectedModelLabel,
            apiCostEstimate: report.apiCostEstimate,
            conversationURL: report.conversationURL,
            jobReference: report.jobReference,
            updatedAt: report.timestamp
        )
        runs[run.id] = run
        return run
    }

    public func run(id: UUID) -> AgentRun? {
        runs[id]
    }

    public func allRuns() -> [AgentRun] {
        runs.values.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    public func activeRuns() -> [AgentRun] {
        runs.values
            .filter { !isTerminal($0.state) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func removeTerminalRuns() {
        runs = runs.filter { !isTerminal($0.value.state) }
    }

    private func defaultMessage(for state: AgentRunState) -> String {
        switch state {
        case .queued: "Queued"
        case .running: "Running"
        case .waitingApproval: "Waiting for approval"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .disconnected: "Disconnected"
        }
    }

    private func isTerminal(_ state: AgentRunState) -> Bool {
        switch state {
        case .succeeded, .failed, .cancelled:
            true
        case .queued, .running, .waitingApproval, .disconnected:
            false
        }
    }
}
