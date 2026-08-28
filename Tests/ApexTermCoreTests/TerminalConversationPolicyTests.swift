import ApexTermCore
import XCTest

final class TerminalConversationPolicyTests: XCTestCase {
    func testRemoteSessionDefaultsToExWithoutOverwritingExplicitOverride() {
        XCTAssertEqual(
            TerminalConversationPolicy.resolvesTranscriptMode(
                baseMode: .off,
                sessionKind: .ssh(host: "gae"),
                remoteInteractiveCommandActive: false
            ),
            .ex
        )
        XCTAssertEqual(
            TerminalConversationPolicy.resolvesTranscriptMode(
                baseMode: .off,
                sessionKind: .ssh(host: "gae"),
                remoteInteractiveCommandActive: false,
                userOverride: .on
            ),
            .on
        )
        XCTAssertEqual(
            TerminalConversationPolicy.resolvesTranscriptMode(
                baseMode: .off,
                sessionKind: .ssh(host: "gae"),
                remoteInteractiveCommandActive: false,
                userOverride: .conversation
            ),
            .conversation
        )
    }

    func testTypedRemoteCommandsActivateExForLocalSession() {
        for command in [
            "ssh ubuntu@example.com",
            "sudo /usr/bin/ssh -i key ubuntu@example.com",
            "tailscale ssh ubuntu@gae",
            "aws ssm start-session --target i-123",
            "aws ec2-instance-connect ssh --instance-id i-123",
            "gcloud compute ssh instance-1",
            "mosh user@example.com"
        ] {
            XCTAssertTrue(
                TerminalConversationPolicy.commandStartsRemoteInteractiveSession(command),
                command
            )
        }

        XCTAssertFalse(
            TerminalConversationPolicy.commandStartsRemoteInteractiveSession(
                "printf 'ssh ubuntu@example.com\\n'"
            )
        )
        XCTAssertFalse(
            TerminalConversationPolicy.commandStartsRemoteInteractiveSession(
                "scp file ubuntu@example.com:/tmp/"
            )
        )
    }

    func testComposerRequiresIntegratedLocalPrompt() {
        XCTAssertTrue(
            TerminalConversationPolicy.supportsComposer(
                sessionKind: .local,
                shellPromptReady: true,
                remoteInteractiveCommandActive: false
            )
        )
        XCTAssertFalse(
            TerminalConversationPolicy.supportsComposer(
                sessionKind: .local,
                shellPromptReady: false,
                remoteInteractiveCommandActive: false
            )
        )
        XCTAssertTrue(
            TerminalConversationPolicy.supportsComposer(
                sessionKind: .local,
                shellPromptReady: true,
                remoteInteractiveCommandActive: true
            )
        )
        XCTAssertTrue(
            TerminalConversationPolicy.supportsComposer(
                sessionKind: .tmux(host: "gae", session: "main"),
                shellPromptReady: true,
                remoteInteractiveCommandActive: false
            )
        )
    }
}
