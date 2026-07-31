import Darwin
import Foundation
import XCTest
@testable import ApexTermCore

final class DiagnosticsTests: XCTestCase {
    func testRedactsCommonCredentialFormatsAndPrivatePaths() {
        let redactor = DiagnosticRedactor(
            privatePaths: ["/Users/tester/Secret Project"],
            homeDirectory: "/Users/tester"
        )
        let openAIKey = "sk-" + String(repeating: "a", count: 26)
        let githubToken = "ghp_" + String(repeating: "b", count: 30)
        let awsAccessKey = "AKIA" + String(repeating: "C", count: 16)
        let input = """
        path=/Users/tester/Secret Project/file.txt
        OPENAI_API_KEY=\(openAIKey)
        GITHUB_TOKEN=\(githubToken)
        Authorization: Bearer abc.def.ghi
        aws=\(awsAccessKey)
        command=tool --password hunter2
        home=/Users/tester/Documents
        """

        let output = redactor.redact(input)

        XCTAssertFalse(output.contains("Secret Project"))
        XCTAssertFalse(output.contains("hunter2"))
        XCTAssertFalse(output.contains("abc.def.ghi"))
        XCTAssertFalse(output.contains(openAIKey))
        XCTAssertFalse(output.contains(githubToken))
        XCTAssertFalse(output.contains(awsAccessKey))
        XCTAssertTrue(output.contains("<private-path>"))
        XCTAssertTrue(output.contains("home=~/Documents"))
    }

    func testSensitiveEnvironmentValuesAreNeverRetained() {
        let redactor = DiagnosticRedactor(homeDirectory: "/Users/tester")
        let environment = [
            "PATH": "/opt/homebrew/bin:/usr/bin",
            "HOME": "/Users/tester",
            "API_TOKEN": "actual-token",
            "DATABASE_PASSWORD": "actual-password",
            "SESSION_COOKIE": "actual-cookie"
        ]

        let output = redactor.redactedEnvironment(environment)

        XCTAssertEqual(output["PATH"], "/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(output["HOME"], "~")
        XCTAssertEqual(output["API_TOKEN"], "<redacted>")
        XCTAssertEqual(output["DATABASE_PASSWORD"], "<redacted>")
        XCTAssertEqual(output["SESSION_COOKIE"], "<redacted>")
    }

    func testDiagnosticReportContainsNoTerminalContentOrCommandHistoryFields() throws {
        let openAIKey = "sk-" + String(repeating: "a", count: 26)
        let report = DiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 100),
            appVersion: "0.1.0",
            operatingSystem: "macOS",
            architecture: "arm64",
            renderer: "Metal",
            workspaceCount: 2,
            sessionCount: 4,
            activeAgentCount: 1,
            automationSocketEnabled: true,
            notes: ["OPENAI_API_KEY=\(openAIKey)"]
        ).redacted(using: DiagnosticRedactor(homeDirectory: nil))

        let data = try JSONEncoder().encode(report)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.lowercased().contains("scrollback"))
        XCTAssertFalse(text.lowercased().contains("commandhistory"))
        XCTAssertFalse(text.contains(openAIKey))
        XCTAssertTrue(text.contains("redacted"))
    }

    func testPeerIdentityPolicyAcceptsOnlyConfiguredUIDs() {
        let policy = UnixPeerIdentityPolicy(allowedUserIDs: [1000, 1001])

        XCTAssertTrue(policy.permits(userID: 1000))
        XCTAssertTrue(policy.permits(userID: 1001))
        XCTAssertFalse(policy.permits(userID: 0))
        XCTAssertFalse(policy.permits(userID: 2000))
    }

    func testCurrentUserPolicyPermitsCurrentEffectiveUID() {
        XCTAssertTrue(
            UnixPeerIdentityPolicy.currentUserOnly.permits(
                userID: Darwin.geteuid()
            )
        )
    }
}
