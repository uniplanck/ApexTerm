@testable import ApexTermApp
import ApexTermCore
import XCTest

final class ApexTerminalOutputPipelineTests: XCTestCase {
    func testCommandCaptureUsesPTYBoundariesAndExcludesEarlierOutput() {
        let pipeline = ApexTerminalOutputPipeline()
        let command = "printf 'CURRENT_ONLY\\n'"
        let input = Array(
            (
                "startup warning that must not be captured\r\n"
                + "\u{001B}]133;B\u{0007}"
                + "(base) user@host ~ % \(command)\r\n"
                + "\u{001B}]133;E;\(command)\u{0007}"
                + "\u{001B}]133;C\u{0007}"
                + "CURRENT_ONLY\r\n"
                + "\u{001B}]133;D;0\u{0007}"
                + "\u{001B}]133;A\u{0007}"
            ).utf8
        )

        var forwarded: [UInt8] = []
        var completed: [ApexTerminalCompletedCommand] = []
        var semanticEvents: [ShellSemanticEvent] = []

        // Exercise fragmented marker and ordinary-output boundaries rather than
        // relying on one convenient PTY read shape.
        let cuts = [7, 31, 54, 89, 117, input.count]
        var start = 0
        for end in cuts where start < input.count {
            let upper = min(end, input.count)
            guard start < upper else { continue }
            let result = pipeline.process(input[start..<upper])
            forwarded.append(contentsOf: result.bytes)
            completed.append(contentsOf: result.signals.completedCommands)
            semanticEvents.append(contentsOf: result.signals.semanticEvents)
            start = upper
        }
        if start < input.count {
            let result = pipeline.process(input[start..<input.count])
            forwarded.append(contentsOf: result.bytes)
            completed.append(contentsOf: result.signals.completedCommands)
            semanticEvents.append(contentsOf: result.signals.semanticEvents)
        }

        XCTAssertEqual(forwarded, input)
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed[0].command, command)
        XCTAssertEqual(completed[0].exitCode, 0)
        XCTAssertFalse(completed[0].outputWasTruncated)

        let output = TerminalTextSanitizer.plainText(from: completed[0].output)
        XCTAssertEqual(output, "CURRENT_ONLY")
        XCTAssertFalse(output.contains("startup warning"))
        XCTAssertFalse(output.contains(command))
        XCTAssertEqual(
            semanticEvents,
            [
                .commandInputStarted,
                .commandCaptured(command: command),
                .commandExecuted,
                .commandFinished(exitCode: 0),
                .promptStarted
            ]
        )
    }
}
