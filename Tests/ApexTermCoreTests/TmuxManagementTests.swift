import XCTest
@testable import ApexTermCore

final class TmuxManagementTests: XCTestCase {
    func testSessionListParserReadsNameCountsAndCreationDate() {
        let endpoint = TmuxEndpoint.remote(alias: "ubuntu")
        let sessions = TmuxSessionListParser.parse(
            "main|#|3|#|1|#|1785040000\nworker|#|1|#|0|#|1785041000\n",
            endpoint: endpoint
        )

        XCTAssertEqual(sessions.map(\.name), ["main", "worker"])
        XCTAssertEqual(sessions[0].windowCount, 3)
        XCTAssertEqual(sessions[0].attachedClientCount, 1)
        XCTAssertEqual(sessions[0].endpoint, endpoint)
        XCTAssertNotNil(sessions[0].createdAt)
    }

    func testLocalPlansSelectApexTermServerAndKeepNameAsOneArgument() {
        let list = TmuxLaunchPlanBuilder.listLocalApexTerm(
            executable: "/opt/homebrew/bin/tmux",
            serverName: "apexterm-test"
        )
        let kill = TmuxLaunchPlanBuilder.killLocalApexTerm(
            executable: "/opt/homebrew/bin/tmux",
            serverName: "apexterm-test",
            sessionName: "agent main"
        )

        XCTAssertEqual(
            list.arguments,
            ["-L", "apexterm-test", "list-sessions", "-F", TmuxLaunchPlanBuilder.listFormat]
        )
        XCTAssertEqual(
            kill.arguments,
            ["-L", "apexterm-test", "kill-session", "-t", "agent main"]
        )
    }

    func testRemoteManagementUsesNonInteractiveSSHAndProfileDestination() {
        let profile = SSHHostProfile(
            alias: "ubuntu-prod",
            displayName: "Production Ubuntu",
            hostName: "100.66.201.64",
            user: "ubuntu",
            identityFile: "~/Downloads/key.pem"
        )
        let list = TmuxLaunchPlanBuilder.listRemote(profile: profile)
        let kill = TmuxLaunchPlanBuilder.killRemote(
            profile: profile,
            sessionName: "main"
        )

        XCTAssertTrue(list.arguments.contains("-T"))
        XCTAssertFalse(list.arguments.contains("-tt"))
        XCTAssertTrue(list.arguments.contains("BatchMode=yes"))
        XCTAssertTrue(list.arguments.contains("NumberOfPasswordPrompts=0"))
        XCTAssertTrue(list.arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(list.arguments.contains("ubuntu@100.66.201.64"))
        XCTAssertEqual(kill.arguments.last, "'tmux' 'kill-session' '-t' 'main'")
        XCTAssertTrue(list.arguments.last?.contains("#{session_name}") == true)
        XCTAssertEqual(profile.displayTitle, "Production Ubuntu")
    }

    func testLegacyProfileWithoutDisplayNameStillDecodes() throws {
        let data = Data(#"{"alias":"legacy","hostName":"example.test"}"#.utf8)
        let profile = try JSONDecoder().decode(SSHHostProfile.self, from: data)

        XCTAssertNil(profile.displayName)
        XCTAssertEqual(profile.displayTitle, "legacy")
    }
}
