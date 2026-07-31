import Foundation
import XCTest
@testable import ApexTermCore

final class LocalSessionLaunchPlanTests: XCTestCase {
    func testTmuxPlanUsesStableSessionIdentityAndWorkingDirectory() {
        let sessionID = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        let builder = LocalSessionLaunchPlanBuilder(
            tmuxExecutable: "/opt/homebrew/bin/tmux",
            shellExecutable: "/bin/zsh"
        )

        let plan = builder.build(
            sessionID: sessionID,
            workingDirectory: "/tmp/project"
        )

        XCTAssertEqual(plan.executable, "/opt/homebrew/bin/tmux")
        XCTAssertEqual(
            plan.arguments,
            [
                "-u",
                "-L", "apexterm",
                "-f", "/dev/null",
                "new-session",
                "-A",
                "-D",
                "-s",
                "apexterm-123456781234123412341234567890ab",
                "-c",
                "/tmp/project",
                "/bin/zsh",
                "-l"
            ]
        )
    }

    func testTmuxPlanPassesOnlyProvidedSessionEnvironmentAndConfiguration() {
        let builder = LocalSessionLaunchPlanBuilder(
            tmuxExecutable: "/opt/homebrew/bin/tmux",
            shellExecutable: "/bin/zsh",
            tmuxServerName: "apexterm-v2",
            tmuxConfigurationPath: "/tmp/apexterm/tmux.conf"
        )

        let plan = builder.build(
            sessionID: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            workingDirectory: nil,
            tmuxEnvironment: [
                "ZDOTDIR": "/tmp/apexterm/shell-integration",
                "APEXTERM_SHELL_INTEGRATION": "1"
            ]
        )

        XCTAssertEqual(plan.arguments.prefix(7), [
            "-u",
            "-L", "apexterm-v2",
            "-f", "/tmp/apexterm/tmux.conf",
            "new-session",
            "-A"
        ])
        XCTAssertTrue(plan.arguments.contains("APEXTERM_SHELL_INTEGRATION=1"))
        XCTAssertTrue(plan.arguments.contains("ZDOTDIR=/tmp/apexterm/shell-integration"))
        XCTAssertFalse(plan.arguments.contains(where: { $0.contains("HOME=") }))
    }

    func testExplicitTmuxNameIsSanitizedAndPassedAsOneArgument() {
        let builder = LocalSessionLaunchPlanBuilder(
            tmuxExecutable: "/opt/homebrew/bin/tmux",
            shellExecutable: "/bin/zsh"
        )

        let plan = builder.build(
            sessionID: UUID(),
            workingDirectory: nil,
            explicitSessionName: "  client work; rm -rf /  "
        )

        XCTAssertEqual(builder.normalizedSessionName("  client work; rm -rf /  "), "client-work-rm--rf-")
        XCTAssertEqual(plan.arguments[plan.arguments.firstIndex(of: "-s")! + 1], "client-work-rm--rf-")
        XCTAssertFalse(plan.arguments.contains("client work; rm -rf /"))
    }

    func testMissingTmuxFallsBackToDirectLoginShell() {
        let plan = LocalSessionLaunchPlanBuilder(
            tmuxExecutable: nil,
            shellExecutable: "/bin/zsh"
        ).build(
            sessionID: UUID(),
            workingDirectory: "/tmp"
        )

        XCTAssertEqual(plan.executable, "/bin/zsh")
        XCTAssertEqual(plan.arguments, ["-l"])
    }

    func testExecutableDiscoveryFindsOnlyExecutableFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tool = directory.appendingPathComponent("tool")
        try Data("#!/bin/sh\n".utf8).write(to: tool)

        XCTAssertNil(
            LocalToolDiscovery.firstExecutable(
                named: "tool",
                searchPaths: [directory.path]
            )
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: tool.path
        )
        XCTAssertEqual(
            LocalToolDiscovery.firstExecutable(
                named: "tool",
                searchPaths: [directory.path]
            ),
            tool.path
        )
    }
}
