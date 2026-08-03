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

    func testRawSixelIsBlockedAtEverySplitPoint() {
        let sixel = Array("\u{001B}Pq~~~~\u{001B}\\".utf8)

        for split in 0...sixel.count {
            var filter = TerminalSixelSafetyFilter()
            let first = filter.feed(sixel[..<split])
            let second = filter.feed(sixel[split...])
            XCTAssertEqual(first + second, [], "split=\(split)")
            XCTAssertEqual(filter.blockedSixelCount, 1, "split=\(split)")
        }
    }

    func testTmuxSixelIsBlockedAtEverySplitPoint() {
        let sixel = Array(
            "\u{001B}Ptmux;\u{001B}\u{001B}P0;0q~~~~\u{001B}\u{001B}\\\u{001B}\\".utf8
        )

        for split in 0...sixel.count {
            var filter = TerminalSixelSafetyFilter()
            let first = filter.feed(sixel[..<split])
            let second = filter.feed(sixel[split...])
            XCTAssertEqual(first + second, [], "split=\(split)")
            XCTAssertEqual(filter.blockedSixelCount, 1, "split=\(split)")
        }
    }

    func testOrdinaryEscapeSequencesPassThrough() {
        var filter = TerminalSixelSafetyFilter()
        let bytes = Array("\u{001B}[31mred\u{001B}[0m".utf8)

        XCTAssertEqual(filter.feed(bytes[...]), bytes)
    }
}
