import Foundation

public struct ScheduledTerminalCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var command: String
    public var scheduledAt: Date
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        command: String,
        scheduledAt: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scheduledAt = scheduledAt
        self.createdAt = createdAt
    }

    public var isValid: Bool {
        !command.isEmpty && command.utf8.count <= 64 * 1_024
    }
}

public enum ScheduledTerminalCommandPolicy {
    public static func normalizedFireDate(
        requested: Date,
        now: Date = Date()
    ) -> Date {
        max(requested, now)
    }

    public static func shouldSend(
        sessionKind: SessionKind,
        processRunning: Bool,
        shellPromptReady: Bool,
        remoteInteractiveCommandActive: Bool
    ) -> Bool {
        guard processRunning else { return false }
        _ = sessionKind
        _ = remoteInteractiveCommandActive
        return shellPromptReady
    }
}
