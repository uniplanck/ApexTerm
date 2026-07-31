import ApexTermCore
import Foundation

enum DirectTerminalAutomationCompletion: Sendable {
    case record(CommandExecutionRecord)
    case failure(String)
}

final class DirectTerminalAutomationRequest: @unchecked Sendable {
    let id = UUID()
    let sessionID: UUID
    let command: String

    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var completion: DirectTerminalAutomationCompletion?

    init(sessionID: UUID, command: String) {
        self.sessionID = sessionID
        self.command = command
    }

    func finish(_ value: DirectTerminalAutomationCompletion) {
        lock.lock()
        guard completion == nil else {
            lock.unlock()
            return
        }
        completion = value
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> DirectTerminalAutomationCompletion? {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return completion
    }
}
