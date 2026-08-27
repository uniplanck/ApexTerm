import ApexTermCore
import XCTest

final class ScheduledTerminalCommandTests: XCTestCase {
    func testCommandValidationAndFireDateNormalization() {
        let sessionID = UUID()
        let command = ScheduledTerminalCommand(
            sessionID: sessionID,
            command: "  printf hello  ",
            scheduledAt: Date(timeIntervalSince1970: 10)
        )
        XCTAssertEqual(command.command, "printf hello")
        XCTAssertTrue(command.isValid)

        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(
            ScheduledTerminalCommandPolicy.normalizedFireDate(
                requested: Date(timeIntervalSince1970: 90),
                now: now
            ),
            now
        )
    }

    func testScheduledCommandsRequireRunningProcessAndReadyPrompt() {
        XCTAssertFalse(
            ScheduledTerminalCommandPolicy.shouldSend(
                sessionKind: .local,
                processRunning: true,
                shellPromptReady: false,
                remoteInteractiveCommandActive: false
            )
        )
        XCTAssertTrue(
            ScheduledTerminalCommandPolicy.shouldSend(
                sessionKind: .local,
                processRunning: true,
                shellPromptReady: true,
                remoteInteractiveCommandActive: false
            )
        )
        XCTAssertFalse(
            ScheduledTerminalCommandPolicy.shouldSend(
                sessionKind: .ssh(host: "gae"),
                processRunning: true,
                shellPromptReady: false,
                remoteInteractiveCommandActive: false
            )
        )
        XCTAssertTrue(
            ScheduledTerminalCommandPolicy.shouldSend(
                sessionKind: .ssh(host: "gae"),
                processRunning: true,
                shellPromptReady: true,
                remoteInteractiveCommandActive: false
            )
        )
        XCTAssertFalse(
            ScheduledTerminalCommandPolicy.shouldSend(
                sessionKind: .ssh(host: "gae"),
                processRunning: false,
                shellPromptReady: true,
                remoteInteractiveCommandActive: false
            )
        )
    }
}
