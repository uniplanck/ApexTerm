import Foundation
import XCTest
@testable import ApexTermCore

final class ShellIntegrationInstallerTests: XCTestCase {
    func testPrepareCreatesPrivateWrapperFilesWithoutTouchingUserFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let wrapper = root.appendingPathComponent("wrapper", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try ShellIntegrationInstaller.prepare(at: wrapper)

        for name in [
            ".zshenv",
            ".zprofile",
            ".zshrc",
            ".zlogin",
            ".zlogout",
            "apexterm-integration.zsh",
            "tmux.conf"
        ] {
            let url = wrapper.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        }

        let tmuxConfiguration = try String(
            contentsOf: ShellIntegrationInstaller.tmuxConfigurationURL(at: wrapper),
            encoding: .utf8
        )
        XCTAssertTrue(tmuxConfiguration.contains("set-option -g mouse on"))
        XCTAssertTrue(tmuxConfiguration.contains("set-option -g history-limit 50000"))
        XCTAssertTrue(tmuxConfiguration.contains("set-option -g allow-passthrough on"))
    }

    func testEnvironmentPreservesBaseAndRedirectsZDOTDIR() {
        let wrapper = URL(fileURLWithPath: "/tmp/ApexTerm Wrapper")
        let environment = ShellIntegrationInstaller.environment(
            wrapperDirectory: wrapper,
            base: [
                "HOME": "/Users/tester",
                "PATH": "/opt/homebrew/bin:/usr/bin",
                "CUSTOM": "value"
            ]
        )
        let dictionary: [String: String] = Dictionary(
            uniqueKeysWithValues: environment.compactMap { entry -> (String, String)? in
                let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            }
        )

        XCTAssertEqual(dictionary["ZDOTDIR"], wrapper.path)
        XCTAssertEqual(dictionary["APEXTERM_ORIGINAL_ZDOTDIR"], "/Users/tester")
        XCTAssertEqual(dictionary["PATH"], "/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(dictionary["CUSTOM"], "value")
        XCTAssertEqual(dictionary["TERM_PROGRAM"], "ApexTerm")
        XCTAssertEqual(dictionary["TERM"], "xterm-256color")
    }

    func testPrepareIsIdempotent() throws {
        let wrapper = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: wrapper) }

        try ShellIntegrationInstaller.prepare(at: wrapper)
        let first = try Data(contentsOf: wrapper.appendingPathComponent(".zshrc"))
        try ShellIntegrationInstaller.prepare(at: wrapper)
        let second = try Data(contentsOf: wrapper.appendingPathComponent(".zshrc"))

        XCTAssertEqual(first, second)
    }

    func testInteractiveZshEmitsSemanticMarkersAndSourcesOriginalRC() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let wrapper = root.appendingPathComponent("wrapper", isDirectory: true)
        let original = root.appendingPathComponent("original", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try Data("PROMPT=''\nprint ORIGINAL_RC_LOADED\n".utf8).write(
            to: original.appendingPathComponent(".zshrc")
        )
        try ShellIntegrationInstaller.prepare(at: wrapper)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-i"]
        process.environment = [
            "HOME": root.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "ZDOTDIR": wrapper.path,
            "APEXTERM_ORIGINAL_ZDOTDIR": original.path,
            "TERM": "xterm-256color"
        ]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        try process.run()
        input.fileHandleForWriting.write(Data("print COMMAND_RAN\nexit\n".utf8))
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(text.contains("ORIGINAL_RC_LOADED"))
        XCTAssertTrue(text.contains("COMMAND_RAN"))
        XCTAssertTrue(text.contains("\u{001B}]133;A\u{0007}"))
        XCTAssertTrue(text.contains("\u{001B}]133;B\u{0007}"))
        XCTAssertTrue(text.contains("\u{001B}]133;E;print COMMAND_RAN\u{0007}"))
        XCTAssertTrue(text.contains("\u{001B}]133;C\u{0007}"))
        XCTAssertTrue(text.contains("\u{001B}]133;D;0\u{0007}"))

        let integration = try String(
            contentsOf: wrapper.appendingPathComponent("apexterm-integration.zsh"),
            encoding: .utf8
        )
        XCTAssertTrue(integration.contains("PROMPT_EOL_MARK=''"))
    }
}
