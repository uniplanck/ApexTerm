import XCTest
@testable import ApexTermCore

final class TerminalEscapeSequenceTrustTests: XCTestCase {
    func testLocalDefaultAllowsClipboardWriteAndBlocksRead() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .localDefault)
        let write = "\u{001B}]52;c;SGVsbG8=\u{0007}"
        let read = "\u{001B}]52;c;?\u{0007}"
        let input = Array(("before" + write + read + "after").utf8)

        let output = filter.feed(input[...])

        XCTAssertEqual(String(decoding: output, as: UTF8.self), "before" + write + "after")
        XCTAssertEqual(filter.blockedOSC52Count, 1)
    }

    func testRemoteDefaultBlocksFragmentedClipboardSequence() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
        let first = Array("before\u{001B}]52;c".utf8)
        let second = Array(";SGVsbG8=\u{0007}after".utf8)

        XCTAssertEqual(String(decoding: filter.feed(first[...]), as: UTF8.self), "before")
        XCTAssertEqual(String(decoding: filter.feed(second[...]), as: UTF8.self), "after")
        XCTAssertEqual(filter.blockedOSC52Count, 1)
    }

    func testReadWritePolicyPreservesStringTerminatedQuery() {
        var filter = TerminalEscapeSequenceTrustFilter(
            policy: TerminalEscapeSequenceTrustPolicy(clipboardAccess: .readWrite)
        )
        let sequence = "\u{001B}]52;c;?\u{001B}\\"

        XCTAssertEqual(
            filter.feed(Array(sequence.utf8)[...]),
            Array(sequence.utf8)
        )
        XCTAssertEqual(filter.blockedOSC52Count, 0)
    }

    func testRemoteDefaultRemovesTmuxPassthroughEnvelope() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
        let sequence = "\u{001B}Ptmux;\u{001B}\u{001B}]52;c;SGVsbG8=\u{0007}\u{001B}\\"
        let bytes = Array(("left" + sequence + "right").utf8)

        XCTAssertEqual(
            String(decoding: filter.feed(bytes[...]), as: UTF8.self),
            "leftright"
        )
        XCTAssertEqual(filter.blockedOSC52Count, 1)
    }

    func testOversizedSequenceIsDiscardedUntilItsTerminator() {
        var filter = TerminalEscapeSequenceTrustFilter(
            policy: TerminalEscapeSequenceTrustPolicy(clipboardAccess: .readWrite),
            maximumOSC52Bytes: 1_024
        )
        let first = Array(("safe\u{001B}]52;c;" + String(repeating: "A", count: 1_500)).utf8)
        let second = Array("\u{0007}tail".utf8)

        XCTAssertEqual(String(decoding: filter.feed(first[...]), as: UTF8.self), "safe")
        XCTAssertEqual(String(decoding: filter.feed(second[...]), as: UTF8.self), "tail")
        XCTAssertEqual(filter.blockedOSC52Count, 1)
    }

    func testRemoteRawSequenceIsBlockedAtEverySplitPoint() {
        let sequence = Array("\u{001B}]52;c;SGVsbG8=\u{0007}".utf8)

        for split in 0...sequence.count {
            var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
            let first = filter.feed(sequence[..<split])
            let second = filter.feed(sequence[split...])
            XCTAssertEqual(first + second, [], "split=\(split)")
            XCTAssertEqual(filter.blockedOSC52Count, 1, "split=\(split)")
        }
    }

    func testRemoteTmuxSequenceIsBlockedAtEverySplitPoint() {
        let sequence = Array(
            "\u{001B}Ptmux;\u{001B}\u{001B}]52;c;SGVsbG8=\u{0007}\u{001B}\\".utf8
        )

        for split in 0...sequence.count {
            var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
            let first = filter.feed(sequence[..<split])
            let second = filter.feed(sequence[split...])
            XCTAssertEqual(first + second, [], "split=\(split)")
            XCTAssertEqual(filter.blockedOSC52Count, 1, "split=\(split)")
        }
    }

    func testNonClipboardEscapeSequencesPassThroughUnchanged() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
        let bytes = Array("\u{001B}[31mred\u{001B}[0m\n".utf8)

        XCTAssertEqual(filter.feed(bytes[...]), bytes)
    }
}
