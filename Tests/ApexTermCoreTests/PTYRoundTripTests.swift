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

        terminal.configureTrustPolicy(.remoteDefault)
        terminal.dataReceived(slice: writeSequence[...])
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
        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        let jobStarted = expectation(description: "foreground job started")
        let shellRegainedControl = expectation(description: "shell regained terminal after Control-Z")
        let jobContinued = expectation(description: "foreground job received SIGCONT")
        let jobReceivedQuit = expectation(description: "foreground job received SIGQUIT")
        let jobFinished = expectation(description: "shell continued after foreground job quit")
        var output = ""
        var didStart = false
        var didRegain = false
        var didContinue = false
        var didReceiveQuit = false
        var didFinish = false
        terminal.onHostData = { bytes in
            output += String(decoding: bytes, as: UTF8.self)
            if output.contains("__JOB_STARTED__"), !didStart {
                didStart = true
                jobStarted.fulfill()
            }
            if output.contains("__SHELL_REGAINED__"), !didRegain {
                didRegain = true
                shellRegainedControl.fulfill()
            }
            if output.contains("__JOB_CONTINUED__"), !didContinue {
                didContinue = true
                jobContinued.fulfill()
            }
            if output.contains("__JOB_QUIT__"), !didReceiveQuit {
                didReceiveQuit = true
                jobReceivedQuit.fulfill()
            }
            if output.contains("__AFTER_QUIT__"), !didFinish {
                didFinish = true
                jobFinished.fulfill()
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
        let jobCommand =
            "/bin/sh -c 'trap \"printf __JOB_CONTINUED__\\\\n\" CONT; "
                + "trap \"printf __JOB_QUIT__\\\\n; exit 131\" QUIT; "
                + "printf __JOB_STARTED__\\\\n; while :; do sleep 1; done'; "
                + "printf '__AFTER_QUIT__\\n'\n"
        terminal.send(
            source: terminal,
            data: Array(jobCommand.utf8)[...]
        )
        wait(for: [jobStarted], timeout: 2)

        terminal.keyDown(with: try controlKeyEvent(character: "z", keyCode: 6))
        Thread.sleep(forTimeInterval: 0.15)
        terminal.send(
            source: terminal,
            data: Array("printf '__SHELL_REGAINED__\\n'\n".utf8)[...]
        )
        wait(for: [shellRegainedControl], timeout: 2)

        terminal.send(source: terminal, data: Array("fg\n".utf8)[...])
        wait(for: [jobContinued], timeout: 3)
        terminal.keyDown(with: try controlKeyEvent(character: "\\", keyCode: 42))

        wait(for: [jobReceivedQuit, jobFinished], timeout: 5)
        XCTAssertTrue(terminal.process.running)
    }

    @MainActor
    func testLocalSessionShutdownTerminatesBackgroundProcessGroup() throws {
        let pidURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("apexterm-child-\(UUID().uuidString).pid")
        var childPID: pid_t = 0
        defer {
            if childPID > 0 {
                _ = Darwin.kill(childPID, SIGKILL)
            }
            try? FileManager.default.removeItem(at: pidURL)
        }

        let terminal = ApexLocalProcessTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480)
        )
        let command = "trap '' HUP; sleep 30 & printf '%s' $! > '\(pidURL.path)'; wait"
        terminal.startProcess(
            executable: "/bin/zsh",
            args: ["-lc", command],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )

        XCTAssertTrue(waitUntil(timeout: 2) {
            FileManager.default.fileExists(atPath: pidURL.path)
        })
        let text = try String(contentsOf: pidURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        childPID = try XCTUnwrap(pid_t(text))
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
