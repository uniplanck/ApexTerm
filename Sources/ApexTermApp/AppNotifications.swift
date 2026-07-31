import Foundation

struct TerminalInputRequest: Sendable {
    let sessionID: UUID
    let text: String
    let execute: Bool
}

extension Notification.Name {
    static let apexTermFindRequested = Notification.Name(
        "app.apexterm.terminal.find-requested"
    )
    static let apexTermQuickTerminalRequested = Notification.Name(
        "app.apexterm.quick-terminal.requested"
    )
    static let apexTermInputRequested = Notification.Name(
        "app.apexterm.terminal.input-requested"
    )
}
