@testable import ApexTermApp
import ApexTermCore
import AppKit
import Darwin
import SwiftTerm
import XCTest

private final class ObservedPTYTerminal: TerminalDelegate, LocalProcessDelegate, @unchecked Sendable {
    private(set) var terminal: Terminal!
    private(set) var process: LocalProcess!
    var onBytes: ((ArraySlice<UInt8>) -> Void)?

    init(queue: DispatchQueue) {
        terminal = Terminal(delegate: self)
        process = LocalProcess(delegate: self, dispatchQueue: queue)
    }

    func send(_ text: String) {
        process.send(data: Array(text.utf8)[...])
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {}

    func dataReceived(slice: ArraySlice<UInt8>) {
        onBytes?(slice)
        terminal.feed(buffer: slice)
    }

    func send(source: Terminal, data: ArraySlice<UInt8>) {
        process.send(data: data)
    }

    func getWindowSize() -> winsize {
        winsize(
            ws_row: UInt16(terminal.rows),
            ws_col: UInt16(terminal.cols),
            ws_xpixel: 16,
            ws_ypixel: 16
        )
    }

    func mouseModeChanged(source: Terminal) {}
    func hostCurrentDirectoryUpdated(source: Terminal) {}
    func colorChanged(source: Terminal, idx: Int) {}

    func createImageFromBitmap(
        source: Terminal,
        bytes: inout [UInt8],
        width: Int,
        height: Int
    ) {}
}

private final class ProcessTerminationObserver: NSObject, LocalProcessTerminalViewDelegate {
    var onTermination: (() -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onTermination?()
    }
}

final class PTYRoundTripTests: XCTestCase {
    func testRealPTYReturnsInputToTerminal() {
        let queue = DispatchQueue(label: "app.apexterm.tests.pty")
        let terminal = ObservedPTYTerminal(queue: queue)
        let output = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var received = false

        terminal.onBytes = { bytes in
            guard bytes.contains(UInt8(ascii: "x")) else { return }
            lock.lock()
            let shouldSignal = !received
            received = true
            lock.unlock()
            if shouldSignal {
                output.signal()
            }
        }
        terminal.process.startProcess(
            executable: "/bin/cat",
            args: [],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )
        defer { terminal.process.terminate() }

        Thread.sleep(forTimeInterval: 0.03)
        terminal.send("x")

        XCTAssertEqual(output.wait(timeout: .now() + 1), .success)
        lock.lock()
        let didReceive = received
        lock.unlock()
        XCTAssertTrue(didReceive)
    }

    @MainActor
    func testPromptStartRestoresControlCAfterKittyModeWasLeftEnabled() throws {
        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        terminal.terminal.feed(text: "\u{001B}[=1;1u")
        for _ in 0..<16 {
            terminal.terminal.feed(text: "\u{001B}[>8u")
        }
        XCTAssertFalse(terminal.terminal.keyboardEnhancementFlags.isEmpty)

        terminal.handleSemanticEvent(.promptStarted)

        XCTAssertTrue(terminal.terminal.keyboardEnhancementFlags.isEmpty)

        let observer = ProcessTerminationObserver()
        let interrupted = expectation(description: "foreground PTY process interrupted")
        observer.onTermination = {
            interrupted.fulfill()
        }
        terminal.processDelegate = observer
        terminal.startProcess(
            executable: "/bin/cat",
            args: [],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )
        defer {
            if terminal.process.running {
                terminal.terminate()
            }
        }

        Thread.sleep(forTimeInterval: 0.05)
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .control,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: "c",
                charactersIgnoringModifiers: "c",
                isARepeat: false,
                keyCode: 8
            )
        )

        terminal.keyDown(with: event)

        wait(for: [interrupted], timeout: 2)
    }

    @MainActor
    func testControlCKeyInterruptsForegroundPTYProcess() throws {
        let terminal = LocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        let observer = ProcessTerminationObserver()
        let interrupted = expectation(description: "foreground PTY process interrupted")
        observer.onTermination = {
            interrupted.fulfill()
        }
        terminal.processDelegate = observer
        terminal.startProcess(
            executable: "/bin/cat",
            args: [],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )
        defer {
            if terminal.process.running {
                terminal.terminate()
            }
        }

        Thread.sleep(forTimeInterval: 0.05)
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .control,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: "c",
                charactersIgnoringModifiers: "c",
                isARepeat: false,
                keyCode: 8
            )
        )

        terminal.keyDown(with: event)

        wait(for: [interrupted], timeout: 2)
    }

    @MainActor
    func testControlCRecoversInteractiveShellWhenPTYISIGWasDisabled() async throws {
        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        terminal.setLocalControlCRecoveryEnabled(true)
        var output = ""
        terminal.onHostData = { bytes in
            output += String(decoding: bytes, as: UTF8.self)
        }
        terminal.startProcess(
            executable: "/bin/zsh",
            args: ["-df"],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )
        defer {
            if terminal.process.running {
                terminal.terminateSession(scope: .processGroup)
            }
        }
        try await Task.sleep(for: .milliseconds(100))

        terminal.send(
            source: terminal,
            data: Array("stty -isig; sleep 30\n".utf8)[...]
        )
        let foregroundStarted = await waitUntilAsync(timeout: 2) {
            LocalTerminalProcessSession(rootPID: terminal.process.shellPid)?
                .foregroundJobProcessGroup() != nil
        }
        XCTAssertTrue(foregroundStarted)

        let controlC = try controlKeyEvent(character: "c", keyCode: 8)
        terminal.handleApexKeyDown(controlC)
        terminal.keyDown(with: controlC)

        let foregroundReleased = await waitUntilAsync(timeout: 3) {
            LocalTerminalProcessSession(rootPID: terminal.process.shellPid)?
                .foregroundJobProcessGroup() == nil
        }
        XCTAssertTrue(foregroundReleased, "foreground job did not release the PTY")
        terminal.send(
            source: terminal,
            data: Array("printf '__CTRL_C_SHELL_RECOVERED__\\n'; stty isig\n".utf8)[...]
        )
        let shellRecovered = await waitUntilAsync(timeout: 3) {
            output.contains("__CTRL_C_SHELL_RECOVERED__")
        }
        XCTAssertTrue(shellRecovered, "output=\(output)")
        XCTAssertTrue(terminal.process.running)
    }

    @MainActor
    func testRemoteTrustPolicyBlocksOSC52ClipboardAccess() {
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let original {
                pasteboard.setString(original, forType: .string)
            }
        }

        pasteboard.clearContents()
        pasteboard.setString("sentinel", forType: .string)
        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        let writeSequence = Array("\u{001B}]52;c;SGVsbG8=\u{0007}".utf8)
        let c1WriteSequence = [UInt8(0x9D)]
            + Array("00052;c;V29ybGQ=".utf8)
            + [0x9C]

        terminal.configureTrustPolicy(.remoteDefault)
        terminal.dataReceived(slice: writeSequence[...])
        terminal.dataReceived(slice: c1WriteSequence[...])
        XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")

        terminal.configureTrustPolicy(.localDefault)
        terminal.dataReceived(slice: writeSequence[...])
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello")
    }

    @MainActor
    func testProgrammaticInputIsRejectedUntilSessionIsAttached() {
        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        let received = expectation(description: "allowed programmatic input reached PTY")
        var output = ""
        var didFulfill = false
        terminal.onHostData = { bytes in
            output += String(decoding: bytes, as: UTF8.self)
            if output.contains("allowed-input"), !didFulfill {
                didFulfill = true
                received.fulfill()
            }
        }
        terminal.startProcess(
            executable: "/bin/cat",
            args: [],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )
        defer {
            if terminal.process.running {
                terminal.terminateSession(scope: .processOnly)
            }
        }
        Thread.sleep(forTimeInterval: 0.05)

        let request = TerminalInputRequest(
            sessionID: UUID(),
            text: "allowed-input\n",
            execute: false
        )
        terminal.setProgrammaticInputEnabled(false)
        XCTAssertFalse(terminal.handleProgrammaticInput(request))

        terminal.setProgrammaticInputEnabled(true)
        XCTAssertTrue(terminal.handleProgrammaticInput(request))
        wait(for: [received], timeout: 2)
        XCTAssertFalse(output.contains("blocked-input"))
    }

    @MainActor
    func testProcessExitRecoveryClearsInputModesAcrossBothBuffers() {
        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        terminal.terminal.feed(text: "\u{001B}[=1;1u")
        terminal.terminal.feed(text: "\u{001B}[?1049h")
        terminal.terminal.feed(text: "\u{001B}[>8u")
        terminal.terminal.feed(text: "\u{001B}[?1000h\u{001B}[?2004h")

        XCTAssertTrue(terminal.terminal.isCurrentBufferAlternate)
        XCTAssertFalse(terminal.terminal.keyboardEnhancementFlags.isEmpty)
        XCTAssertNotEqual(terminal.terminal.mouseMode, .off)
        XCTAssertTrue(terminal.terminal.bracketedPasteMode)

        terminal.recoverTerminalModesAfterProcessExit()

        XCTAssertFalse(terminal.terminal.isCurrentBufferAlternate)
        XCTAssertTrue(terminal.terminal.keyboardEnhancementFlags.isEmpty)
        XCTAssertEqual(terminal.terminal.mouseMode, .off)
        XCTAssertFalse(terminal.terminal.bracketedPasteMode)

        terminal.terminal.feed(text: "\u{001B}[?1049h")
        XCTAssertTrue(terminal.terminal.keyboardEnhancementFlags.isEmpty)
        terminal.terminal.feed(text: "\u{001B}[?1049l")
    }

    @MainActor
    func testSixelIsRemovedBeforeHostObserversAndSwiftTerm() {
        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        var observed = ""
        terminal.onHostData = { bytes in
            observed += String(decoding: bytes, as: UTF8.self)
        }
        let sixel = "\u{001B}P0;0q~~~~\u{001B}\\"
        let bytes = Array(("before" + sixel + "after").utf8)

        terminal.dataReceived(slice: bytes[...])

        XCTAssertEqual(observed, "beforeafter")
        let buffer = String(
            decoding: terminal.terminal.getBufferAsData(kind: .active),
            as: UTF8.self
        )
        XCTAssertTrue(buffer.contains("beforeafter"))
        XCTAssertFalse(buffer.contains("~~~~"))
    }

    @MainActor
    func testRemoteKittyGraphicsIsRemovedBeforeHostObserversAndSwiftTerm() {
        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        var observed: [UInt8] = []
        terminal.onHostData = { bytes in
            observed.append(contentsOf: bytes)
        }
        terminal.configureInlineImageSafetyPolicy(.remoteDefault)
        let kitty = [UInt8(0x9F), 0x47]
            + Array("a=T,f=100;SGVsbG8=".utf8)
            + [0x9C]
        let bytes = Array("before".utf8) + kitty + Array("after".utf8)

        terminal.dataReceived(slice: bytes[...])

        XCTAssertEqual(String(decoding: observed, as: UTF8.self), "beforeafter")
        let buffer = String(
            decoding: terminal.terminal.getBufferAsData(kind: .active),
            as: UTF8.self
        )
        XCTAssertTrue(buffer.contains("beforeafter"))
        XCTAssertFalse(buffer.contains("SGVsbG8="))
    }

    @MainActor
    func testResourceBudgetCapsKittyImageCachePerPane() {
        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )

        terminal.configureResourceBudget()

        XCTAssertEqual(
            terminal.terminal.options.kittyImageCacheLimitBytes,
            64 * 1_024 * 1_024
        )
        XCTAssertFalse(terminal.terminal.options.enableSixelReported)
    }

    @MainActor
    func testPTYWindowSizeTracksTerminalResize() {
        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        let resized = expectation(description: "PTY reported resized dimensions")
        var output = ""
        var didSignalResize = false
        terminal.onHostData = { bytes in
            output += String(decoding: bytes, as: UTF8.self)
            if output.contains("__PTY_SIZE__37 101"), !didSignalResize {
                didSignalResize = true
                resized.fulfill()
            }
        }
        terminal.startProcess(
            executable: "/bin/zsh",
            args: ["-df"],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )
        defer {
            if terminal.process.running {
                terminal.terminateSession(scope: .processGroup)
            }
        }
        Thread.sleep(forTimeInterval: 0.1)

        terminal.terminal.resize(cols: 101, rows: 37)
        terminal.sizeChanged(source: terminal, newCols: 101, newRows: 37)
        terminal.send(
            source: terminal,
            data: Array("printf '__PTY_SIZE__'; stty size\n".utf8)[...]
        )

        wait(for: [resized], timeout: 2)
        XCTAssertTrue(output.contains("__PTY_SIZE__37 101"), "output=\(output)")
    }

    @MainActor
    func testControlZForegroundResumeAndControlBackslash() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let startedURL = directory.appendingPathComponent("started")
        let shellRegainedURL = directory.appendingPathComponent("shell-regained")
        let continuedURL = directory.appendingPathComponent("continued")
        let quitURL = directory.appendingPathComponent("quit")
        let finishedURL = directory.appendingPathComponent("finished")

        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        terminal.startProcess(
            executable: "/bin/zsh",
            args: ["-df"],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )
        defer {
            if terminal.process.running {
                terminal.terminateSession(scope: .processGroup)
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
        terminal.send(
            source: terminal,
            data: Array("stty -echo\n".utf8)[...]
        )
        Thread.sleep(forTimeInterval: 0.1)
        let jobCommand =
            "/bin/sh -c 'trap \"touch \(continuedURL.path)\" CONT; "
                + "trap \"touch \(quitURL.path); exit 131\" QUIT; "
                + "touch \(startedURL.path); while :; do sleep 1; done'; "
                + "touch \(finishedURL.path)\n"
        terminal.send(
            source: terminal,
            data: Array(jobCommand.utf8)[...]
        )
        XCTAssertTrue(waitUntil(timeout: 2) {
            FileManager.default.fileExists(atPath: startedURL.path)
        })

        terminal.keyDown(with: try controlKeyEvent(character: "z", keyCode: 6))
        Thread.sleep(forTimeInterval: 0.15)
        terminal.send(
            source: terminal,
            data: Array("touch \(shellRegainedURL.path)\n".utf8)[...]
        )
        XCTAssertTrue(waitUntil(timeout: 2) {
            FileManager.default.fileExists(atPath: shellRegainedURL.path)
        })

        terminal.send(source: terminal, data: Array("fg\n".utf8)[...])
        XCTAssertTrue(waitUntil(timeout: 3) {
            FileManager.default.fileExists(atPath: continuedURL.path)
        })
        terminal.keyDown(with: try controlKeyEvent(character: "\\", keyCode: 42))

        XCTAssertTrue(waitUntil(timeout: 5) {
            FileManager.default.fileExists(atPath: quitURL.path)
                && FileManager.default.fileExists(atPath: finishedURL.path)
        })
        XCTAssertTrue(terminal.process.running)
    }

    @MainActor
    func testLocalSessionShutdownTerminatesSeparateJobProcessGroup() throws {
        let pidURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("apexterm-child-\(UUID().uuidString).pid")
        var childPID: pid_t = 0

        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        defer {
            if terminal.process.running {
                terminal.terminateSession(scope: .processGroup)
            }
            if childPID > 0 {
                _ = Darwin.kill(childPID, SIGKILL)
            }
            try? FileManager.default.removeItem(at: pidURL)
        }
        terminal.startProcess(
            executable: "/bin/zsh",
            args: ["-df"],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )
        Thread.sleep(forTimeInterval: 0.1)
        terminal.send(
            source: terminal,
            data: Array("stty -echo\n".utf8)[...]
        )
        Thread.sleep(forTimeInterval: 0.1)
        let command =
            "/bin/sh -c 'trap \"\" HUP; exec sleep 30' & child=$!; "
                + "group=$(ps -o pgid= -p $child | tr -d ' '); "
                + "printf '%s %s' $child $group > '\(pidURL.path)'; wait\n"
        terminal.send(
            source: terminal,
            data: Array(command.utf8)[...]
        )

        XCTAssertTrue(waitUntil(timeout: 2) {
            FileManager.default.fileExists(atPath: pidURL.path)
        })
        let values = try String(contentsOf: pidURL, encoding: .utf8)
            .split(separator: " ")
        XCTAssertEqual(values.count, 2)
        childPID = try XCTUnwrap(pid_t(values[0]))
        let childProcessGroup = try XCTUnwrap(pid_t(values[1]))
        let shellProcessGroup = Darwin.getpgid(terminal.process.shellPid)
        XCTAssertGreaterThan(childProcessGroup, 0)
        XCTAssertNotEqual(childProcessGroup, shellProcessGroup)
        XCTAssertEqual(Darwin.kill(childPID, 0), 0)

        terminal.terminateSession(scope: .processGroup)

        XCTAssertTrue(waitUntil(timeout: 3) {
            Darwin.kill(childPID, 0) == -1 && errno == ESRCH
        })
    }

    private func controlKeyEvent(
        character: String,
        keyCode: UInt16
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .control,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    @MainActor
    private func waitUntilAsync(
        timeout: TimeInterval,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return condition()
    }
}
