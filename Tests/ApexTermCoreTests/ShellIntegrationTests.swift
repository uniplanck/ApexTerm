import XCTest
@testable import ApexTermCore

final class ShellIntegrationTests: XCTestCase {
    func testParsesCompleteOSC133LifecycleWithBellTerminators() {
        var parser = ShellIntegrationParser()
        let text = "\u{001B}]133;A\u{0007}"
            + "\u{001B}]133;B\u{0007}"
            + "\u{001B}]133;E;printf hello\u{0007}"
            + "\u{001B}]133;C\u{0007}"
            + "\u{001B}]133;D;0\u{0007}"

        let events = parser.feed(Array(text.utf8)[...])

        XCTAssertEqual(
            events,
            [
                .promptStarted,
                .commandInputStarted,
                .commandCaptured(command: "printf hello"),
                .commandExecuted,
                .commandFinished(exitCode: 0)
            ]
        )
    }

    func testParsesStringTerminatorAndExitFailure() {
        var parser = ShellIntegrationParser()
        let text = "\u{001B}]133;D;127\u{001B}\\"

        XCTAssertEqual(
            parser.feed(Array(text.utf8)[...]),
            [.commandFinished(exitCode: 127)]
        )
    }

    func testFragmentedSequenceIsRetainedAcrossFeeds() {
        var parser = ShellIntegrationParser()
        let first = Array("noise\u{001B}]13".utf8)
        let second = Array("3;C\u{0007}".utf8)

        XCTAssertEqual(parser.feed(first[...]), [])
        XCTAssertEqual(parser.feed(second[...]), [.commandExecuted])
    }

    func testUnknownMarkerIsIgnored() {
        var parser = ShellIntegrationParser()
        let text = "\u{001B}]133;Z;value\u{0007}"

        XCTAssertEqual(parser.feed(Array(text.utf8)[...]), [])
    }

    func testStreamParserFastPathAcceptsOrdinaryANSIAndRejectsMarkerPrefixes() {
        var parser = ShellIntegrationStreamParser()
        let ordinary = Array("\u{001B}[31mred\u{001B}[0m\n".utf8)
        let completeMarker = Array("before\u{001B}]133;A\u{0007}".utf8)
        let fragmentedMarker = Array("before\u{001B}]13".utf8)

        XCTAssertTrue(parser.canBypass(ordinary[...]))
        XCTAssertFalse(parser.canBypass(completeMarker[...]))
        XCTAssertFalse(parser.canBypass(fragmentedMarker[...]))

        _ = parser.feed(fragmentedMarker[...])
        XCTAssertFalse(parser.canBypass(Array("3;A\u{0007}".utf8)[...]))
    }

    func testStreamParserPreservesDataAndMarkerOrderAcrossFragments() {
        var parser = ShellIntegrationStreamParser()
        let first = Array("before\u{001B}]133;E;echo".utf8)
        let second = Array(" hello\u{0007}after".utf8)

        XCTAssertEqual(parser.feed(first[...]), [.data(Array("before".utf8))])
        XCTAssertEqual(
            parser.feed(second[...]),
            [
                .marker(
                    raw: Array("\u{001B}]133;E;echo hello\u{0007}".utf8),
                    event: .commandCaptured(command: "echo hello")
                ),
                .data(Array("after".utf8))
            ]
        )
    }

    func testTmuxPassthroughMarkerIsParsedAsOneMarkerWithoutLeakingWrapperData() {
        var parser = ShellIntegrationStreamParser()
        let marker = "\u{001B}Ptmux;\u{001B}\u{001B}]133;E;printf hello\u{0007}\u{001B}\\"
        let bytes = Array(("before" + marker + "after").utf8)

        XCTAssertEqual(
            parser.feed(bytes[...]),
            [
                .data(Array("before".utf8)),
                .marker(
                    raw: Array(marker.utf8),
                    event: .commandCaptured(command: "printf hello")
                ),
                .data(Array("after".utf8))
            ]
        )
    }

    func testFragmentedTmuxPassthroughMarkerRetainsOuterTerminator() {
        var parser = ShellIntegrationStreamParser()
        let first = Array("\u{001B}Ptmux;\u{001B}\u{001B}]133;D;0\u{0007}\u{001B}".utf8)
        let second = Array("\\tail".utf8)

        XCTAssertEqual(parser.feed(first[...]), [])
        XCTAssertEqual(
            parser.feed(second[...]),
            [
                .marker(
                    raw: Array("\u{001B}Ptmux;\u{001B}\u{001B}]133;D;0\u{0007}\u{001B}\\".utf8),
                    event: .commandFinished(exitCode: 0)
                ),
                .data(Array("tail".utf8))
            ]
        )
    }

    func testTerminalTextSanitizerRemovesANSIAndNormalizesCarriageReturns() {
        let text = "\u{001B}[31mred\u{001B}[0m\rprogress\u{0008}!\n"
            + "\u{001B}(Bplain\n   "
        let bytes = Array(text.utf8)

        XCTAssertEqual(
            TerminalTextSanitizer.plainText(from: bytes),
            "red\nprogres!\nplain"
        )
    }

    func testBoundaryIndexStoresNoCommandText() async {
        let index = CommandBoundaryIndex(maximumEventsPerSession: 100)
        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 100)

        await index.append(
            [
                .commandCaptured(command: "secret command"),
                .commandExecuted,
                .commandFinished(exitCode: 1)
            ],
            sessionID: sessionID,
            timestamp: timestamp
        )
        let events = await index.events(sessionID: sessionID)

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.map(\.kind), [.commandCaptured, .executed, .finished])
        XCTAssertEqual(events.last?.exitCode, 1)
        XCTAssertEqual(events.map(\.timestamp), [timestamp, timestamp, timestamp])
    }

    func testBoundaryIndexTrimsOldEvents() async {
        let index = CommandBoundaryIndex(maximumEventsPerSession: 100)
        let sessionID = UUID()

        for _ in 0..<110 {
            await index.append([.promptStarted], sessionID: sessionID)
        }

        let events = await index.events(sessionID: sessionID)
        XCTAssertEqual(events.count, 100)
    }
}
