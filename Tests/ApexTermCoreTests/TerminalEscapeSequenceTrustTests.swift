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

    func testLocalDefaultHandlesC1AndLeadingZeroClipboardCommands() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .localDefault)
        let write = [UInt8(0x9D)] + Array("00052;c;SGVsbG8=".utf8) + [0x9C]
        let read = [UInt8(0x9D)] + Array("052;c;?".utf8) + [0x9C]

        XCTAssertEqual(filter.feed(write[...]), write)
        XCTAssertEqual(filter.feed(read[...]), [])
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

        XCTAssertEqual(filter.feed(Array(sequence.utf8)[...]), Array(sequence.utf8))
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

    func testSwiftTermNumericPrefixJunkCannotBypassRemotePolicy() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
        let sequence = Array("\u{001B}]00052junk;c;SGVsbG8=\u{0007}".utf8)

        XCTAssertEqual(filter.feed(sequence[...]), [])
        XCTAssertEqual(filter.blockedOSC52Count, 1)
    }

    func testBlockedOSCEndedByBareEscapePreservesFollowingCSI() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
        let input = Array("\u{001B}]52;c;SGVsbG8=\u{001B}[31mred".utf8)
        let expected = Array("\u{001B}[31mred".utf8)

        XCTAssertEqual(filter.feed(input[...]), expected)
        XCTAssertEqual(filter.blockedOSC52Count, 1)
    }

    func testUnterminatedNumericCandidateIsBoundedAndDiscarded() {
        var filter = TerminalEscapeSequenceTrustFilter(
            policy: .remoteDefault,
            maximumOSC52Bytes: 1_024
        )
        let first = Array(("safe\u{001B}]" + String(repeating: "0", count: 1_500)).utf8)
        let second = Array("\u{0007}tail".utf8)

        XCTAssertEqual(String(decoding: filter.feed(first[...]), as: UTF8.self), "safe")
        XCTAssertEqual(String(decoding: filter.feed(second[...]), as: UTF8.self), "tail")
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
        assertBlockedAtEverySplit(
            Array("\u{001B}]52;c;SGVsbG8=\u{0007}".utf8)
        )
    }

    func testRemoteLeadingZeroSequenceIsBlockedAtEverySplitPoint() {
        assertBlockedAtEverySplit(
            Array("\u{001B}]00052;c;SGVsbG8=\u{001B}\\".utf8)
        )
    }

    func testRemoteC1SequenceIsBlockedAtEverySplitPoint() {
        assertBlockedAtEverySplit(
            [0x9D] + Array("052;c;SGVsbG8=".utf8) + [0x9C]
        )
    }

    func testRemoteTmuxSequenceIsBlockedAtEverySplitPoint() {
        assertBlockedAtEverySplit(
            Array("\u{001B}Ptmux;\u{001B}\u{001B}]52;c;SGVsbG8=\u{0007}\u{001B}\\".utf8)
        )
    }

    func testRemoteTmuxC1SequenceIsBlockedAtEverySplitPoint() {
        assertBlockedAtEverySplit(
            Array("\u{001B}Ptmux;".utf8)
                + [0x9D]
                + Array("00052;c;SGVsbG8=".utf8)
                + [0x9C]
                + Array("\u{001B}\\".utf8)
        )
    }

    func testMalformedTargetWithoutSeparatorDoesNotConsumeLaterText() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
        let sequence = Array("\u{001B}]52junk\u{0007}later;text".utf8)

        XCTAssertEqual(filter.feed(sequence[...]), sequence)
        XCTAssertEqual(filter.blockedOSC52Count, 0)
    }

    func testNonTargetLeadingZeroOSCPassesThroughUnchanged() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
        let sequence = Array("\u{001B}]0008;;https://example.test\u{0007}".utf8)

        XCTAssertEqual(filter.feed(sequence[...]), sequence)
        XCTAssertEqual(filter.blockedOSC52Count, 0)
    }

    func testNonClipboardEscapeSequencesPassThroughUnchanged() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
        let bytes = Array("\u{001B}[31mred\u{001B}[0m\n".utf8)

        XCTAssertEqual(filter.feed(bytes[...]), bytes)
    }

    func testRemoteTargetsAreBlockedByteByByteIncludingC1OuterTmux() {
        let sequences = [
            Array("\u{001B}]00052;c;SGVsbG8=\u{0007}".utf8),
            [0x9D] + Array("052;c;SGVsbG8=".utf8) + [0x9C],
            [0x90] + Array("tmux;".utf8) + [0x9D]
                + Array("00052;c;SGVsbG8=".utf8) + [0x9C]
                + Array("\u{001B}\\".utf8)
        ]

        for sequence in sequences {
            var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
            var output: [UInt8] = []
            for index in sequence.indices {
                output += filter.feed(sequence[index...index])
            }
            XCTAssertEqual(output, [])
            XCTAssertEqual(filter.blockedOSC52Count, 1)
        }
    }

    func testValidUTF8ContinuationByteIsNotMistakenForC1OSC() {
        var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
        let sequence = Array("Н52;c;SGVsbG8=\u{0007}".utf8)
        var output: [UInt8] = []

        for index in sequence.indices {
            output += filter.feed(sequence[index...index])
        }

        XCTAssertEqual(output, sequence)
        XCTAssertEqual(filter.blockedOSC52Count, 0)
    }

    private func assertBlockedAtEverySplit(
        _ sequence: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for split in 0...sequence.count {
            var filter = TerminalEscapeSequenceTrustFilter(policy: .remoteDefault)
            let first = filter.feed(sequence[..<split])
            let second = filter.feed(sequence[split...])
            XCTAssertEqual(first + second, [], "split=\(split)", file: file, line: line)
            XCTAssertEqual(
                filter.blockedOSC52Count,
                1,
                "split=\(split)",
                file: file,
                line: line
            )
        }
    }
}
