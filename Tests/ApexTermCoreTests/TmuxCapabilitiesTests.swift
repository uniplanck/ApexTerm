import XCTest
@testable import ApexTermCore

final class TmuxCapabilitiesTests: XCTestCase {
    func testVersionParserHandlesReleaseSuffix() throws {
        let version = try XCTUnwrap(TmuxVersion(versionOutput: "tmux 3.6a\n"))

        XCTAssertEqual(version.major, 3)
        XCTAssertEqual(version.minor, 6)
        XCTAssertEqual(version.suffix, "a")
    }

    func testCapabilitiesFollowTmuxFeatureIntroductionVersions() throws {
        let version31 = try XCTUnwrap(TmuxVersion(versionOutput: "tmux 3.1c"))
        let version32 = try XCTUnwrap(TmuxVersion(versionOutput: "tmux 3.2"))
        let version33 = try XCTUnwrap(TmuxVersion(versionOutput: "tmux 3.3a"))
        let version35 = try XCTUnwrap(TmuxVersion(versionOutput: "tmux 3.5"))

        XCTAssertEqual(
            TmuxCapabilities(version: version31),
            TmuxCapabilities(
                supportsTerminalFeatures: false,
                supportsExtendedKeys: false,
                supportsAllowPassthrough: false,
                supportsExtendedKeysFormat: false
            )
        )
        XCTAssertTrue(TmuxCapabilities(version: version32).supportsTerminalFeatures)
        XCTAssertTrue(TmuxCapabilities(version: version32).supportsExtendedKeys)
        XCTAssertFalse(TmuxCapabilities(version: version32).supportsAllowPassthrough)
        XCTAssertTrue(TmuxCapabilities(version: version33).supportsAllowPassthrough)
        XCTAssertFalse(TmuxCapabilities(version: version33).supportsExtendedKeysFormat)
        XCTAssertTrue(TmuxCapabilities(version: version35).supportsExtendedKeysFormat)
    }

    func testGeneratedConfigurationAvoidsUnsupportedOptions() {
        let legacy = ShellIntegrationInstaller.tmuxConfiguration(
            capabilities: TmuxCapabilities(
                supportsTerminalFeatures: false,
                supportsExtendedKeys: false,
                supportsAllowPassthrough: false,
                supportsExtendedKeysFormat: false
            )
        )

        XCTAssertTrue(legacy.contains("terminal-overrides"))
        XCTAssertFalse(legacy.contains("terminal-features"))
        XCTAssertFalse(legacy.contains("extended-keys on"))
        XCTAssertFalse(legacy.contains("allow-passthrough"))
    }

    func testGeneratedConfigurationEnablesModernInputCapabilities() {
        let modern = ShellIntegrationInstaller.tmuxConfiguration(
            capabilities: TmuxCapabilities(version: TmuxVersion(major: 3, minor: 6))
        )

        XCTAssertTrue(modern.contains("terminal-features"))
        XCTAssertTrue(modern.contains("RGB:extkeys"))
        XCTAssertTrue(modern.contains("set-option -s extended-keys on"))
        XCTAssertTrue(modern.contains("set-option -s extended-keys-format csi-u"))
        XCTAssertTrue(modern.contains("set-option -g allow-passthrough on"))
    }

    func testRuntimeProbeReadsInstalledTmuxWhenAvailable() throws {
        guard let executable = LocalToolDiscovery.firstExecutable(named: "tmux") else {
            throw XCTSkip("tmux is not installed")
        }

        XCTAssertNotNil(TmuxRuntimeProbe.capabilities(executable: executable))
    }
}
