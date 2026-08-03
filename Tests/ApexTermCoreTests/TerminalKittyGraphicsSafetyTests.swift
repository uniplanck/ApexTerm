import XCTest
@testable import ApexTermCore

final class TerminalKittyGraphicsSafetyTests: XCTestCase {
    func testLocalPolicyAllowsBoundedKittyGraphics() {
        var filter = TerminalKittyGraphicsSafetyFilter(policy: .localDefault)
        let sequence = Array("\u{001B}_Ga=T,f=100;SGVsbG8=\u{001B}\\".utf8)

        XCTAssertEqual(filter.feed(sequence[...]), sequence)
        XCTAssertEqual(filter.blockedKittyGraphicsCount, 0)
    }

    func testLocalPolicyAllowsBoundedC1KittyGraphics() {
        var filter = TerminalKittyGraphicsSafetyFilter(policy: .localDefault)
        let sequence = [UInt8(0x9F), 0x47]
            + Array("a=T,f=100;SGVsbG8=".utf8)
            + [0x9C]

        XCTAssertEqual(filter.feed(sequence[...]), sequence)
        XCTAssertEqual(filter.blockedKittyGraphicsCount, 0)
    }

    func testRemotePolicyBlocksRawAndTmuxKittyGraphics() {
        var filter = TerminalKittyGraphicsSafetyFilter(policy: .remoteDefault)
        let raw = Array("a\u{001B}_Ga=T;SGVsbG8=\u{001B}\\b".utf8)
        let tmux = Array("\u{001B}Ptmux;\u{001B}\u{001B}_Ga=T;SGVsbG8=\u{001B}\u{001B}\\\u{001B}\\c".utf8)

        let first = filter.feed(raw[...])
        let second = filter.feed(tmux[...])

        XCTAssertEqual(String(decoding: first + second, as: UTF8.self), "abc")
        XCTAssertEqual(filter.blockedKittyGraphicsCount, 2)
    }

    func testRemoteC1SequenceIsBlockedAtEverySplitPoint() {
        assertBlockedAtEverySplit(
            [0x9F, 0x47] + Array("a=T;SGVsbG8=".utf8) + [0x9C]
        )
    }

    func testRemoteTmuxC1SequenceIsBlockedAtEverySplitPoint() {
        assertBlockedAtEverySplit(
            Array("\u{001B}Ptmux;".utf8)
                + [0x9F, 0x47]
                + Array("a=T;SGVsbG8=".utf8)
                + [0x9C]
                + Array("\u{001B}\\".utf8)
        )
    }

    func testBlockedKittySequenceEndedByBareEscapePreservesFollowingCSI() {
        var filter = TerminalKittyGraphicsSafetyFilter(policy: .remoteDefault)
        let input = Array("\u{001B}_Ga=T;SGVsbG8=\u{001B}[31mred".utf8)
        let expected = Array("\u{001B}[31mred".utf8)

        XCTAssertEqual(filter.feed(input[...]), expected)
        XCTAssertEqual(filter.blockedKittyGraphicsCount, 1)
    }

    func testLargeBoundedSequenceFedByteByByteRemainsLinearAndExact() {
        var filter = TerminalKittyGraphicsSafetyFilter(
            policy: TerminalInlineImageSafetyPolicy(
                access: .bounded(maximumSequenceBytes: 64 * 1_024)
            )
        )
        let sequence = Array(
            ("\u{001B}_Ga=T;"
                + String(repeating: "A", count: 32 * 1_024)
                + "\u{001B}\\").utf8
        )
        var output: [UInt8] = []

        for index in sequence.indices {
            output += filter.feed(sequence[index...index])
        }

        XCTAssertEqual(output, sequence)
        XCTAssertEqual(filter.blockedKittyGraphicsCount, 0)
    }

    func testOversizedFragmentedSequenceIsDiscardedThroughTerminator() {
        var filter = TerminalKittyGraphicsSafetyFilter(
            policy: TerminalInlineImageSafetyPolicy(
                access: .bounded(maximumSequenceBytes: 1_024)
            )
        )
        let first = Array(
            ("safe\u{001B}_Ga=T;" + String(repeating: "A", count: 1_500)).utf8
        )
        let second = Array("\u{001B}\\tail".utf8)

        XCTAssertEqual(String(decoding: filter.feed(first[...]), as: UTF8.self), "safe")
        XCTAssertEqual(String(decoding: filter.feed(second[...]), as: UTF8.self), "tail")
        XCTAssertEqual(filter.blockedKittyGraphicsCount, 1)
    }

    func testNonKittyAPCPassesThroughUnchanged() {
        var filter = TerminalKittyGraphicsSafetyFilter(policy: .remoteDefault)
        let sequence = Array("\u{001B}_Xordinary\u{001B}\\".utf8)

        XCTAssertEqual(filter.feed(sequence[...]), sequence)
        XCTAssertEqual(filter.blockedKittyGraphicsCount, 0)
    }

    func testRemoteTargetsAreBlockedByteByByteIncludingC1OuterTmux() {
        let sequences = [
            Array("\u{001B}_Ga=T;SGVsbG8=\u{001B}\\".utf8),
            [0x9F, 0x47] + Array("a=T;SGVsbG8=".utf8) + [0x9C],
            [0x90] + Array("tmux;".utf8) + [0x9F, 0x47]
                + Array("a=T;SGVsbG8=".utf8) + [0x9C]
                + Array("\u{001B}\\".utf8)
        ]

        for sequence in sequences {
            var filter = TerminalKittyGraphicsSafetyFilter(policy: .remoteDefault)
            var output: [UInt8] = []
            for index in sequence.indices {
                output += filter.feed(sequence[index...index])
            }
            XCTAssertEqual(output, [])
            XCTAssertEqual(filter.blockedKittyGraphicsCount, 1)
        }
    }

    func testValidUTF8ContinuationByteIsNotMistakenForC1APC() {
        var filter = TerminalKittyGraphicsSafetyFilter(policy: .remoteDefault)
        let sequence = Array("ПGa=T;SGVsbG8=\u{001B}\\".utf8)
        var output: [UInt8] = []

        for index in sequence.indices {
            output += filter.feed(sequence[index...index])
        }

        XCTAssertEqual(output, sequence)
        XCTAssertEqual(filter.blockedKittyGraphicsCount, 0)
    }

    private func assertBlockedAtEverySplit(
        _ sequence: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for split in 0...sequence.count {
            var filter = TerminalKittyGraphicsSafetyFilter(policy: .remoteDefault)
            let first = filter.feed(sequence[..<split])
            let second = filter.feed(sequence[split...])
            XCTAssertEqual(first + second, [], "split=\(split)", file: file, line: line)
            XCTAssertEqual(
                filter.blockedKittyGraphicsCount,
                1,
                "split=\(split)",
                file: file,
                line: line
            )
        }
    }
}
