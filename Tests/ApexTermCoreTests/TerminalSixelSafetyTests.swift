import XCTest
@testable import ApexTermCore

final class TerminalSixelSafetyTests: XCTestCase {
    func testBlocksRawSixelWithParameters() {
        var filter = TerminalSixelSafetyFilter()
        let sixel = "\u{001B}P0;1;0q#0;2;100;0;0~\u{001B}\\"
        let bytes = Array(("before" + sixel + "after").utf8)

        XCTAssertEqual(String(decoding: filter.feed(bytes[...]), as: UTF8.self), "beforeafter")
        XCTAssertEqual(filter.blockedSixelCount, 1)
    }

    func testBlocksTmuxWrappedSixel() {
        var filter = TerminalSixelSafetyFilter()
        let sixel = "\u{001B}Ptmux;\u{001B}\u{001B}Pq~~~~\u{001B}\u{001B}\\\u{001B}\\"
        let bytes = Array(("a" + sixel + "b").utf8)

        XCTAssertEqual(String(decoding: filter.feed(bytes[...]), as: UTF8.self), "ab")
        XCTAssertEqual(filter.blockedSixelCount, 1)
    }

    func testNonSixelDCSPassesThroughUnchanged() {
        var filter = TerminalSixelSafetyFilter()
        let dcs = Array("\u{001B}P1$r0m\u{001B}\\".utf8)

        XCTAssertEqual(filter.feed(dcs[...]), dcs)
        XCTAssertEqual(filter.blockedSixelCount, 0)
    }

    func testNonSixelC1DCSPassesThroughUnchanged() {
        var filter = TerminalSixelSafetyFilter()
        let dcs = [UInt8(0x90)] + Array("1$r0m".utf8) + [0x9C]

        XCTAssertEqual(filter.feed(dcs[...]), dcs)
        XCTAssertEqual(filter.blockedSixelCount, 0)
    }

    func testRawSixelIsBlockedAtEverySplitPoint() {
        assertBlockedAtEverySplit(
            Array("\u{001B}Pq~~~~\u{001B}\\".utf8)
        )
    }

    func testC1SixelIsBlockedAtEverySplitPoint() {
        assertBlockedAtEverySplit(
            [0x90] + Array("0;0q~~~~".utf8) + [0x9C]
        )
    }

    func testTmuxSixelIsBlockedAtEverySplitPoint() {
        assertBlockedAtEverySplit(
            Array("\u{001B}Ptmux;\u{001B}\u{001B}P0;0q~~~~\u{001B}\u{001B}\\\u{001B}\\".utf8)
        )
    }

    func testTmuxC1SixelIsBlockedAtEverySplitPoint() {
        assertBlockedAtEverySplit(
            Array("\u{001B}Ptmux;".utf8)
                + [0x90]
                + Array("0;0q~~~~".utf8)
                + [0x9C]
                + Array("\u{001B}\\".utf8)
        )
    }

    func testBlockedSixelEndedByBareEscapePreservesFollowingCSI() {
        var filter = TerminalSixelSafetyFilter()
        let input = Array("\u{001B}Pq~~~~\u{001B}[31mred".utf8)
        let expected = Array("\u{001B}[31mred".utf8)

        XCTAssertEqual(filter.feed(input[...]), expected)
        XCTAssertEqual(filter.blockedSixelCount, 1)
    }

    func testOrdinaryEscapeSequencesPassThrough() {
        var filter = TerminalSixelSafetyFilter()
        let bytes = Array("\u{001B}[31mred\u{001B}[0m".utf8)

        XCTAssertEqual(filter.feed(bytes[...]), bytes)
    }

    func testSixelIsBlockedByteByByteIncludingC1OuterTmux() {
        let sequences = [
            Array("\u{001B}P0;0q~~~~\u{001B}\\".utf8),
            [0x90] + Array("0;0q~~~~".utf8) + [0x9C],
            [0x90] + Array("tmux;".utf8) + [0x90]
                + Array("0;0q~~~~".utf8) + [0x9C]
                + Array("\u{001B}\\".utf8)
        ]

        for sequence in sequences {
            var filter = TerminalSixelSafetyFilter()
            var output: [UInt8] = []
            for index in sequence.indices {
                output += filter.feed(sequence[index...index])
            }
            XCTAssertEqual(output, [])
            XCTAssertEqual(filter.blockedSixelCount, 1)
        }
    }

    func testValidUTF8ContinuationByteIsNotMistakenForC1DCS() {
        var filter = TerminalSixelSafetyFilter()
        let sequence = Array("А0;0q~~~~\u{001B}\\".utf8)
        var output: [UInt8] = []

        for index in sequence.indices {
            output += filter.feed(sequence[index...index])
        }

        XCTAssertEqual(output, sequence)
        XCTAssertEqual(filter.blockedSixelCount, 0)
    }

    private func assertBlockedAtEverySplit(
        _ sequence: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for split in 0...sequence.count {
            var filter = TerminalSixelSafetyFilter()
            let first = filter.feed(sequence[..<split])
            let second = filter.feed(sequence[split...])
            XCTAssertEqual(first + second, [], "split=\(split)", file: file, line: line)
            XCTAssertEqual(
                filter.blockedSixelCount,
                1,
                "split=\(split)",
                file: file,
                line: line
            )
        }
    }
}
