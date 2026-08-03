import XCTest
@testable import ApexTermCore

final class TerminalInlineImageSafetyTests: XCTestCase {
    func testLocalPolicyAllowsBoundedInlineImage() {
        var filter = TerminalInlineImageSafetyFilter(policy: .localDefault)
        let sequence = "\u{001B}]1337;File=inline=1:SGVsbG8=\u{0007}"

        XCTAssertEqual(filter.feed(Array(sequence.utf8)[...]), Array(sequence.utf8))
        XCTAssertEqual(filter.blockedInlineImageCount, 0)
    }

    func testLocalPolicyAllowsC1LeadingZeroInlineImage() {
        var filter = TerminalInlineImageSafetyFilter(policy: .localDefault)
        let sequence = [UInt8(0x9D)]
            + Array("001337;File=inline=1:SGVsbG8=".utf8)
            + [0x9C]

        XCTAssertEqual(filter.feed(sequence[...]), sequence)
        XCTAssertEqual(filter.blockedInlineImageCount, 0)
    }

    func testRemotePolicyBlocksRawAndTmuxInlineImages() {
        var filter = TerminalInlineImageSafetyFilter(policy: .remoteDefault)
        let raw = "\u{001B}]1337;File=inline=1:SGVsbG8=\u{0007}"
        let tmux = "\u{001B}Ptmux;\u{001B}\u{001B}]1337;File=inline=1:SGVsbG8=\u{0007}\u{001B}\\"
        let bytes = Array(("a" + raw + "b" + tmux + "c").utf8)

        XCTAssertEqual(String(decoding: filter.feed(bytes[...]), as: UTF8.self), "abc")
        XCTAssertEqual(filter.blockedInlineImageCount, 2)
    }

    func testSwiftTermNumericPrefixJunkCannotBypassRemotePolicy() {
        var filter = TerminalInlineImageSafetyFilter(policy: .remoteDefault)
        let sequence = Array(
            "\u{001B}]001337junk;File=inline=1:SGVsbG8=\u{0007}".utf8
        )

        XCTAssertEqual(filter.feed(sequence[...]), [])
        XCTAssertEqual(filter.blockedInlineImageCount, 1)
    }

    func testBlockedImageEndedByBareEscapePreservesFollowingCSI() {
        var filter = TerminalInlineImageSafetyFilter(policy: .remoteDefault)
        let input = Array(
            "\u{001B}]1337;File=inline=1:SGVsbG8=\u{001B}[31mred".utf8
        )
        let expected = Array("\u{001B}[31mred".utf8)

        XCTAssertEqual(filter.feed(input[...]), expected)
        XCTAssertEqual(filter.blockedInlineImageCount, 1)
    }

    func testLargeBoundedImageFedByteByByteRemainsLinearAndExact() {
        var filter = TerminalInlineImageSafetyFilter(
            policy: TerminalInlineImageSafetyPolicy(
                access: .bounded(maximumSequenceBytes: 64 * 1_024)
            )
        )
        let sequence = Array(
            ("\u{001B}]1337;File=inline=1:"
                + String(repeating: "A", count: 32 * 1_024)
                + "\u{0007}").utf8
        )
        var output: [UInt8] = []

        for index in sequence.indices {
            output += filter.feed(sequence[index...index])
        }

        XCTAssertEqual(output, sequence)
        XCTAssertEqual(filter.blockedInlineImageCount, 0)
    }

    func testUnterminatedNumericCandidateIsBoundedAndDiscarded() {
        var filter = TerminalInlineImageSafetyFilter(
            policy: TerminalInlineImageSafetyPolicy(
                access: .bounded(maximumSequenceBytes: 1_024)
            )
        )
        let first = Array(("safe\u{001B}]" + String(repeating: "0", count: 1_500)).utf8)
        let second = Array("\u{0007}tail".utf8)

        XCTAssertEqual(String(decoding: filter.feed(first[...]), as: UTF8.self), "safe")
        XCTAssertEqual(String(decoding: filter.feed(second[...]), as: UTF8.self), "tail")
        XCTAssertEqual(filter.blockedInlineImageCount, 1)
    }

    func testOversizedFragmentedImageIsDiscardedThroughTerminator() {
        var filter = TerminalInlineImageSafetyFilter(
            policy: TerminalInlineImageSafetyPolicy(
                access: .bounded(maximumSequenceBytes: 1_024)
            )
        )
        let first = Array(
            ("safe\u{001B}]1337;File=inline=1:" + String(repeating: "A", count: 1_500)).utf8
        )
        let second = Array("\u{0007}tail".utf8)

        XCTAssertEqual(String(decoding: filter.feed(first[...]), as: UTF8.self), "safe")
        XCTAssertEqual(String(decoding: filter.feed(second[...]), as: UTF8.self), "tail")
        XCTAssertEqual(filter.blockedInlineImageCount, 1)
    }

    func testEveryRawSequenceSplitPointIsHandled() {
        assertBlockedAtEverySplit(
            Array("\u{001B}]1337;File=inline=1:SGVsbG8=\u{0007}".utf8)
        )
    }

    func testEveryLeadingZeroC1SequenceSplitPointIsHandled() {
        assertBlockedAtEverySplit(
            [0x9D] + Array("01337;File=inline=1:SGVsbG8=".utf8) + [0x9C]
        )
    }

    func testEveryTmuxC1SequenceSplitPointIsHandled() {
        assertBlockedAtEverySplit(
            Array("\u{001B}Ptmux;".utf8)
                + [0x9D]
                + Array("001337;File=inline=1:SGVsbG8=".utf8)
                + [0x9C]
                + Array("\u{001B}\\".utf8)
        )
    }

    func testMalformedTargetWithoutSeparatorDoesNotConsumeLaterText() {
        var filter = TerminalInlineImageSafetyFilter(policy: .remoteDefault)
        let sequence = Array("\u{001B}]1337junk\u{0007}later;File=fake".utf8)

        XCTAssertEqual(filter.feed(sequence[...]), sequence)
        XCTAssertEqual(filter.blockedInlineImageCount, 0)
    }

    func testOtherOSC1337CommandsPassThrough() {
        var filter = TerminalInlineImageSafetyFilter(policy: .remoteDefault)
        let sequence = Array("\u{001B}]01337;SetMark\u{0007}".utf8)

        XCTAssertEqual(filter.feed(sequence[...]), sequence)
    }

    func testRemoteTargetsAreBlockedByteByByteIncludingC1OuterTmux() {
        let sequences = [
            Array("\u{001B}]001337;File=inline=1:SGVsbG8=\u{0007}".utf8),
            [0x9D] + Array("01337;File=inline=1:SGVsbG8=".utf8) + [0x9C],
            [0x90] + Array("tmux;".utf8) + [0x9D]
                + Array("001337;File=inline=1:SGVsbG8=".utf8) + [0x9C]
                + Array("\u{001B}\\".utf8)
        ]

        for sequence in sequences {
            var filter = TerminalInlineImageSafetyFilter(policy: .remoteDefault)
            var output: [UInt8] = []
            for index in sequence.indices {
                output += filter.feed(sequence[index...index])
            }
            XCTAssertEqual(output, [])
            XCTAssertEqual(filter.blockedInlineImageCount, 1)
        }
    }

    func testValidUTF8ContinuationByteIsNotMistakenForC1OSC() {
        var filter = TerminalInlineImageSafetyFilter(policy: .remoteDefault)
        let sequence = Array("Н01337;File=inline=1:SGVsbG8=\u{0007}".utf8)
        var output: [UInt8] = []

        for index in sequence.indices {
            output += filter.feed(sequence[index...index])
        }

        XCTAssertEqual(output, sequence)
        XCTAssertEqual(filter.blockedInlineImageCount, 0)
    }

    private func assertBlockedAtEverySplit(
        _ sequence: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for split in 0...sequence.count {
            var filter = TerminalInlineImageSafetyFilter(policy: .remoteDefault)
            let first = filter.feed(sequence[..<split])
            let second = filter.feed(sequence[split...])
            XCTAssertEqual(first + second, [], "split=\(split)", file: file, line: line)
            XCTAssertEqual(
                filter.blockedInlineImageCount,
                1,
                "split=\(split)",
                file: file,
                line: line
            )
        }
    }
}
