import AppKit
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
}
