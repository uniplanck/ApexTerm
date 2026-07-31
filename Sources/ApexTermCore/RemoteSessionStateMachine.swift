import Foundation

public enum RemoteSessionState: Equatable, Sendable {
    case idle
    case connecting(attempt: Int)
    case transportReady
    case attaching
    case attached
    case detached
    case reconnecting(attempt: Int)
    case failed(reason: String)
    case exited(code: Int32?)
}

public enum RemoteSessionEvent: Equatable, Sendable {
    case connectRequested
    case transportConnected
    case attachRequested
    case sessionAttached
    case userDetached
    case transportLost
    case retry
    case retryExhausted(reason: String)
    case processExited(code: Int32?)
    case reset
}

public struct RemoteSessionStateMachine: Equatable, Sendable {
    public private(set) var state: RemoteSessionState
    public let maximumReconnectAttempts: Int

    public init(
        state: RemoteSessionState = .idle,
        maximumReconnectAttempts: Int = 5
    ) {
        self.state = state
        self.maximumReconnectAttempts = max(1, maximumReconnectAttempts)
    }

    @discardableResult
    public mutating func handle(_ event: RemoteSessionEvent) -> RemoteSessionState {
        switch (state, event) {
        case (_, .reset):
            state = .idle

        case (.idle, .connectRequested), (.detached, .connectRequested), (.failed, .connectRequested):
            state = .connecting(attempt: 1)

        case (.connecting, .transportConnected), (.reconnecting, .transportConnected):
            state = .transportReady

        case (.transportReady, .attachRequested):
            state = .attaching

        case (.attaching, .sessionAttached):
            state = .attached

        case (.attached, .userDetached), (.attaching, .userDetached), (.transportReady, .userDetached):
            state = .detached

        case (.attached, .transportLost), (.attaching, .transportLost), (.transportReady, .transportLost):
            state = .reconnecting(attempt: 1)

        case let (.connecting(attempt), .transportLost), let (.reconnecting(attempt), .transportLost):
            state = nextReconnectState(after: attempt)

        case let (.connecting(attempt), .retry), let (.reconnecting(attempt), .retry):
            state = nextReconnectState(after: attempt)

        case (_, let .retryExhausted(reason)):
            state = .failed(reason: reason)

        case (_, let .processExited(code)):
            state = .exited(code: code)

        default:
            break
        }
        return state
    }

    private func nextReconnectState(after attempt: Int) -> RemoteSessionState {
        let nextAttempt = attempt + 1
        guard nextAttempt <= maximumReconnectAttempts else {
            return .failed(reason: "Reconnect attempts exhausted")
        }
        return .reconnecting(attempt: nextAttempt)
    }
}
