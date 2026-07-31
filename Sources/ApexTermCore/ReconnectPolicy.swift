import Foundation

public struct ReconnectPolicy: Codable, Equatable, Sendable {
    public var maximumAttempts: Int
    public var initialDelaySeconds: Double
    public var maximumDelaySeconds: Double
    public var multiplier: Double

    public init(
        maximumAttempts: Int = 5,
        initialDelaySeconds: Double = 0.5,
        maximumDelaySeconds: Double = 8,
        multiplier: Double = 2
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.initialDelaySeconds = max(0, initialDelaySeconds)
        self.maximumDelaySeconds = max(self.initialDelaySeconds, maximumDelaySeconds)
        self.multiplier = max(1, multiplier)
    }

    public func delaySeconds(forAttempt attempt: Int) -> Double? {
        guard attempt >= 1, attempt <= maximumAttempts else { return nil }
        let exponent = Double(attempt - 1)
        return min(
            maximumDelaySeconds,
            initialDelaySeconds * pow(multiplier, exponent)
        )
    }

    public func nextAttempt(after attempt: Int) -> Int? {
        let next = attempt + 1
        return next <= maximumAttempts ? next : nil
    }
}

public actor ReconnectAttemptTracker {
    private let policy: ReconnectPolicy
    private var attemptsBySession: [UUID: Int] = [:]

    public init(policy: ReconnectPolicy = ReconnectPolicy()) {
        self.policy = policy
    }

    public func begin(sessionID: UUID) -> (attempt: Int, delaySeconds: Double)? {
        let attempt = (attemptsBySession[sessionID] ?? 0) + 1
        guard let delay = policy.delaySeconds(forAttempt: attempt) else {
            return nil
        }
        attemptsBySession[sessionID] = attempt
        return (attempt, delay)
    }

    public func reset(sessionID: UUID) {
        attemptsBySession[sessionID] = nil
    }

    public func attempts(sessionID: UUID) -> Int {
        attemptsBySession[sessionID] ?? 0
    }
}
