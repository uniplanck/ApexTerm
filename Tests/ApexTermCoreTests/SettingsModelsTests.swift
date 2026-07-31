import Foundation
import XCTest
@testable import ApexTermCore

final class SettingsModelsTests: XCTestCase {
    func testDefaultSettingsExposeStableProfilesAndKeybindings() {
        let document = ApexSettingsDocument(
            activeProfileID: ApexSettingsDocument.defaultProfileID,
            profiles: [ApexSettingsDocument.defaultProfile]
        )

        XCTAssertEqual(document.activeProfile.id, ApexSettingsDocument.defaultProfileID)
        XCTAssertEqual(document.activeProfile.name, "Default")
        XCTAssertNil(document.general.interfaceAppearance)
        XCTAssertNil(document.general.accentColorHex)
        XCTAssertEqual(
            document.keybinding(for: "search.universal")?.chord.displayName,
            "⌘K"
        )
        XCTAssertEqual(
            document.keybinding(for: "workspace.new")?.chord.displayName,
            "⇧⌘N"
        )
        XCTAssertEqual(
            document.keybinding(for: "terminal.quick")?.chord.displayName,
            "⌃`"
        )
        XCTAssertEqual(
            document.keybinding(for: "history.timeline")?.chord.displayName,
            "⇧⌘Y"
        )
        XCTAssertEqual(
            document.keybinding(for: "pane.select.1")?.chord.displayName,
            "⌃⌥1"
        )
        XCTAssertEqual(
            document.keybinding(for: "pane.select.4")?.chord.displayName,
            "⌃⌥4"
        )
        XCTAssertEqual(
            document.keybinding(for: "tab.next")?.chord.displayName,
            "⌃⇥"
        )
        XCTAssertEqual(
            document.keybinding(for: "tab.previous")?.chord.displayName,
            "⌃⇧⇥"
        )
        XCTAssertEqual(
            document.keybinding(for: "tab.select.1")?.chord.displayName,
            "⌘1"
        )
        XCTAssertEqual(
            document.keybinding(for: "terminal.latestOutput.copy")?.chord.displayName,
            "⌥⌘C"
        )
        XCTAssertEqual(
            document.keybinding(for: "terminal.transcript.cycle")?.chord.displayName,
            "⌥⌘T"
        )
        XCTAssertEqual(
            document.keybinding(for: "history.toggle")?.chord.displayName,
            "⌃⌘H"
        )
        XCTAssertEqual(
            Set(document.keybindings.map(\.id)).count,
            document.keybindings.count
        )
        XCTAssertEqual(
            Set(document.keybindings.filter(\.isEnabled).map {
                "\($0.scope.rawValue):\($0.chord.displayName)"
            }).count,
            document.keybindings.filter(\.isEnabled).count
        )
    }

    func testSettingsNormalizationDropsDuplicateProfilesAndEnabledChords() {
        let profileID = UUID()
        let duplicateChord = ApexKeyChord(
            key: "p",
            modifiers: [.command, .shift]
        )
        let document = ApexSettingsDocument(
            activeProfileID: UUID(),
            profiles: [
                ApexTerminalProfile(
                    id: profileID,
                    name: "One",
                    terminalFontSize: 99,
                    sidebarFontSize: 1,
                    inputColorHex: "#111111",
                    outputColorHex: "#EEEEEE"
                ),
                ApexTerminalProfile(
                    id: profileID,
                    name: "Duplicate",
                    inputColorHex: "#222222",
                    outputColorHex: "#DDDDDD"
                )
            ],
            keybindings: [
                ApexKeybinding(
                    actionID: "command.palette",
                    chord: duplicateChord
                ),
                ApexKeybinding(
                    actionID: "history.search",
                    chord: duplicateChord
                ),
                ApexKeybinding(
                    actionID: "disabled.duplicate",
                    chord: duplicateChord,
                    isEnabled: false
                )
            ]
        )

        XCTAssertEqual(document.profiles.count, 1)
        XCTAssertEqual(document.activeProfileID, profileID)
        XCTAssertEqual(document.activeProfile.terminalFontSize, 24)
        XCTAssertEqual(document.activeProfile.sidebarFontSize, 9)
        XCTAssertEqual(document.keybindings.count, 2)
        XCTAssertEqual(document.keybindings.filter(\.isEnabled).count, 1)
    }

    func testSettingsStoreRoundTripAndPermissions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("settings.json")
        let store = ApexSettingsStore(fileURL: fileURL)
        let profile = ApexTerminalProfile(
            name: "Operations",
            shellExecutable: "/bin/zsh",
            defaultWorkingDirectory: "/tmp/ops",
            inputColorHex: "#ABCDEF",
            outputColorHex: "#123456",
            environment: ["TERM": "xterm-256color"]
        )
        let document = ApexSettingsDocument(
            activeProfileID: profile.id,
            profiles: [profile],
            general: ApexGeneralSettings(
                languageCode: "ja",
                interfaceAppearance: .dark,
                accentColorHex: "#FF3366",
                compactMode: true,
                autoCollapseLineThreshold: 320
            )
        )

        try await store.save(document)
        let loaded = try await store.load(defaults: document)

        XCTAssertEqual(loaded, document)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testLegacyGeneralSettingsDecodeWithoutAppearanceFields() throws {
        let data = Data(
            """
            {
              "languageCode": "en",
              "compactMode": false,
              "pinMainWindow": false,
              "collapseLeftSidebar": false,
              "collapseRightSidebar": false,
              "showCommandHistory": true,
              "confirmMultilinePaste": false,
              "autoCopyCommandOutput": false,
              "autoCollapseLargeOutputs": true,
              "autoCollapseLineThreshold": 160
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(ApexGeneralSettings.self, from: data)

        XCTAssertNil(settings.interfaceAppearance)
        XCTAssertNil(settings.accentColorHex)
    }

    func testMissingSettingsFileReturnsProvidedDefaults() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing-settings.json")
        let defaults = ApexSettingsDocument(
            activeProfileID: ApexSettingsDocument.defaultProfileID,
            profiles: [ApexSettingsDocument.defaultProfile]
        )
        let store = ApexSettingsStore(fileURL: fileURL)

        let loaded = try await store.load(defaults: defaults)
        XCTAssertEqual(loaded, defaults)
    }

    func testFutureSettingsSchemaIsRejectedWithoutQuarantine() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("settings.json")
        let store = ApexSettingsStore(fileURL: fileURL)
        let document = ApexSettingsDocument(
            schemaVersion: ApexSettingsDocument.currentSchemaVersion + 1,
            activeProfileID: ApexSettingsDocument.defaultProfileID,
            profiles: [ApexSettingsDocument.defaultProfile]
        )
        try await store.save(document)

        do {
            _ = try await store.load(defaults: document)
            XCTFail("Expected unsupported settings schema")
        } catch let ApexSettingsStoreError.unsupportedSchema(found, supported) {
            XCTAssertEqual(found, ApexSettingsDocument.currentSchemaVersion + 1)
            XCTAssertEqual(supported, ApexSettingsDocument.currentSchemaVersion)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    func testCorruptSettingsFileIsQuarantined() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent("settings.json")
        try Data("invalid-json".utf8).write(to: fileURL)
        let defaults = ApexSettingsDocument(
            activeProfileID: ApexSettingsDocument.defaultProfileID,
            profiles: [ApexSettingsDocument.defaultProfile]
        )
        let store = ApexSettingsStore(fileURL: fileURL)

        do {
            _ = try await store.load(defaults: defaults)
            XCTFail("Expected corrupt settings file")
        } catch let ApexSettingsStoreError.corruptFile(quarantinedAt) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedAt.path))
        }
    }
}
