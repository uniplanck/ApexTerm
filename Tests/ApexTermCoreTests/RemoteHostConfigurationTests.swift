import Foundation
import XCTest
@testable import ApexTermCore

final class RemoteHostConfigurationTests: XCTestCase {
    func testHiddenAliasesAreExcludedAndOverridesReplaceBaseProfile() {
        let base = [
            SSHHostProfile(alias: "old", hostName: "old.example"),
            SSHHostProfile(alias: "prod", hostName: "prod.example", user: "ubuntu")
        ]
        let configuration = RemoteHostConfiguration(
            hiddenAliases: ["old"],
            customProfiles: [
                SSHHostProfile(alias: "prod", hostName: "10.0.0.4", user: "admin"),
                SSHHostProfile(alias: "custom", hostName: "custom.example")
            ]
        )

        XCTAssertEqual(
            configuration.visibleProfiles(baseProfiles: base).map(\.alias),
            ["custom", "prod"]
        )
        let prod = configuration.entries(baseProfiles: base).first {
            $0.profile.alias == "prod"
        }
        XCTAssertEqual(prod?.profile.hostName, "10.0.0.4")
        XCTAssertEqual(prod?.profile.user, "admin")
        XCTAssertEqual(prod?.isCustom, true)
    }

    func testConfigurationRoundTripsAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("remote-hosts.json")
        let expected = RemoteHostConfiguration(
            hiddenAliases: ["retired"],
            deletedAliases: ["removed"],
            customProfiles: [
                SSHHostProfile(
                    alias: "dev",
                    displayName: "Development Server",
                    hostName: "127.0.0.1"
                )
            ]
        )

        try RemoteHostConfigurationStore.save(expected, to: fileURL)

        XCTAssertEqual(
            try RemoteHostConfigurationStore.load(from: fileURL),
            expected
        )
    }

    func testDeletedAliasesDisappearFromSettingsAndVisibleProfiles() {
        let base = [
            SSHHostProfile(alias: "keep", hostName: "keep.example"),
            SSHHostProfile(alias: "remove", hostName: "remove.example")
        ]
        let configuration = RemoteHostConfiguration(deletedAliases: ["remove"])

        XCTAssertEqual(configuration.entries(baseProfiles: base).map(\.profile.alias), ["keep"])
        XCTAssertEqual(configuration.visibleProfiles(baseProfiles: base).map(\.alias), ["keep"])
    }

    func testLegacyConfigurationWithoutDeletedAliasesStillDecodes() throws {
        let legacy = Data(#"{"hiddenAliases":["old"],"customProfiles":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(RemoteHostConfiguration.self, from: legacy)

        XCTAssertEqual(decoded.hiddenAliases, ["old"])
        XCTAssertTrue(decoded.deletedAliases.isEmpty)
    }
}
