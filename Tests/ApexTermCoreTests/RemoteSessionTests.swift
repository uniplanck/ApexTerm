import XCTest
@testable import ApexTermCore

final class RemoteSessionTests: XCTestCase {
    func testSSHConfigParsesConcreteHostsAndSkipsWildcards() {
        let config = """
        Host *
          ServerAliveInterval 30

        Host production prod
          HostName 203.0.113.10
          User ubuntu
          Port 2222
          IdentityFile ~/.ssh/prod_ed25519

        Host dev-*
          User dev
        """

        let profiles = SSHConfigParser.parse(config)

        XCTAssertEqual(profiles.map(\.alias), ["production", "prod"])
        XCTAssertEqual(profiles[0].hostName, "203.0.113.10")
        XCTAssertEqual(profiles[0].user, "ubuntu")
        XCTAssertEqual(profiles[0].port, 2222)
        XCTAssertEqual(profiles[0].identityFile, "~/.ssh/prod_ed25519")
    }

    func testSSHCommandImportParsesIdentityUserAndHost() throws {
        let profile = try SSHCommandParser.parse(
            "ssh -i /Users/example/Keys/remote-host.pem ubuntu@203.0.113.10",
            alias: "Ubuntu"
        )

        XCTAssertEqual(profile.alias, "Ubuntu")
        XCTAssertEqual(profile.hostName, "203.0.113.10")
        XCTAssertEqual(profile.user, "ubuntu")
        XCTAssertEqual(
            profile.identityFile,
            "/Users/example/Keys/remote-host.pem"
        )
        XCTAssertEqual(profile.destination, "ubuntu@203.0.113.10")
    }

    func testSSHCommandImportSupportsQuotedIdentityAndPort() throws {
        let profile = try SSHCommandParser.parse(
            "ssh -p 2222 -i '~/.ssh/My Key.pem' admin@example.test"
        )

        XCTAssertEqual(profile.alias, "example.test")
        XCTAssertEqual(profile.port, 2222)
        XCTAssertEqual(profile.identityFile, "~/.ssh/My Key.pem")
        XCTAssertEqual(profile.destination, "admin@example.test")
    }

    func testTmuxLaunchPlanUsesArgumentArrayInsteadOfShellConcatenation() {
        let profile = SSHHostProfile(
            alias: "prod",
            port: 2222,
            identityFile: "~/.ssh/prod_ed25519"
        )

        let plan = RemoteLaunchPlanBuilder.tmuxAttach(
            profile: profile,
            sessionName: "agent-main"
        )

        XCTAssertEqual(plan.executable, "/usr/bin/ssh")
        XCTAssertEqual(plan.arguments.suffix(6), ["prod", "tmux", "new-session", "-A", "-s", "agent-main"])
        XCTAssertTrue(plan.arguments.contains("-tt"))
        XCTAssertTrue(plan.arguments.contains("-p"))
        XCTAssertTrue(plan.arguments.contains("ServerAliveInterval=15"))
        XCTAssertFalse(plan.arguments.joined(separator: " ").contains(";"))
    }

    func testGitTransportHostsAreNotOfferedAsInteractiveShells() {
        XCTAssertFalse(
            SSHHostProfile(
                alias: "github-home",
                hostName: "github.com",
                user: "git"
            ).isInteractiveShellCandidate
        )
        XCTAssertFalse(
            SSHHostProfile(
                alias: "gitlab-work",
                hostName: "altssh.gitlab.com",
                user: "git"
            ).isInteractiveShellCandidate
        )
        XCTAssertTrue(
            SSHHostProfile(
                alias: "hermes-control",
                hostName: "18.208.200.129",
                user: "ubuntu"
            ).isInteractiveShellCandidate
        )
    }

    func testPlainSSHForcesInteractiveTTY() {
        let plan = RemoteLaunchPlanBuilder.ssh(
            profile: SSHHostProfile(alias: "hermes-control")
        )
        XCTAssertTrue(plan.arguments.contains("-tt"))
        XCTAssertFalse(plan.arguments.contains("BatchMode=yes"))
        XCTAssertEqual(plan.arguments.last, "hermes-control")
    }

    func testPlainSSHUsesConfiguredUserAndHostInsteadOfAlias() {
        let plan = RemoteLaunchPlanBuilder.ssh(
            profile: SSHHostProfile(
                alias: "Ubuntu",
                hostName: "100.66.201.64",
                user: "ubuntu",
                identityFile: "~/Downloads/key.pem"
            )
        )

        XCTAssertEqual(plan.arguments.last, "ubuntu@100.66.201.64")
        XCTAssertTrue(plan.arguments.contains(NSString(string: "~/Downloads/key.pem").expandingTildeInPath))
    }

    func testRemoteStateMachineConnectAttachAndRecover() {
        var machine = RemoteSessionStateMachine(maximumReconnectAttempts: 3)

        XCTAssertEqual(machine.handle(.connectRequested), .connecting(attempt: 1))
        XCTAssertEqual(machine.handle(.transportConnected), .transportReady)
        XCTAssertEqual(machine.handle(.attachRequested), .attaching)
        XCTAssertEqual(machine.handle(.sessionAttached), .attached)
        XCTAssertEqual(machine.handle(.transportLost), .reconnecting(attempt: 1))
        XCTAssertEqual(machine.handle(.retry), .reconnecting(attempt: 2))
        XCTAssertEqual(machine.handle(.transportConnected), .transportReady)
    }

    func testRemoteStateMachineStopsAfterBoundedRetries() {
        var machine = RemoteSessionStateMachine(
            state: .reconnecting(attempt: 2),
            maximumReconnectAttempts: 2
        )

        XCTAssertEqual(
            machine.handle(.retry),
            .failed(reason: "Reconnect attempts exhausted")
        )
    }
}
