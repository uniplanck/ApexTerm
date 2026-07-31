import Foundation
import XCTest
@testable import ApexTermCore

final class ApexTermPathsTests: XCTestCase {
    func testSupportDirectoryOverrideIsSharedByDerivedPaths() {
        let environment = ["APEXTERM_SUPPORT_DIRECTORY": "~/ApexTerm Test"]
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("ApexTerm Test", isDirectory: true)

        XCTAssertEqual(
            ApexTermPaths.supportDirectory(environment: environment).standardizedFileURL,
            expected.standardizedFileURL
        )
        XCTAssertEqual(
            ApexTermPaths.shellIntegrationDirectory(environment: environment)
                .standardizedFileURL,
            expected.appendingPathComponent("shell-integration", isDirectory: true)
                .standardizedFileURL
        )
        XCTAssertEqual(
            ApexTermPaths.automationSocketURL(environment: environment)
                .standardizedFileURL,
            expected
                .appendingPathComponent("runtime", isDirectory: true)
                .appendingPathComponent("apexterm.sock")
                .standardizedFileURL
        )
    }

    func testBlankOverrideFallsBackToApplicationSupport() {
        let result = ApexTermPaths.supportDirectory(
            environment: ["APEXTERM_SUPPORT_DIRECTORY": "   "]
        )

        XCTAssertEqual(result.lastPathComponent, "ApexTerm")
        XCTAssertTrue(result.path.contains("Application Support"))
    }
}
