import XCTest
@testable import ApexTermCore

final class TerminalInlineImageSafetyTests: XCTestCase {
    func testLocalPolicyAllowsBoundedInlineImage() {
        var filter = TerminalInlineImageSafetyFilter(policy: .localDefault)
        let sequence = "\u{001B}]1337;File=inline=1:SGVsbG8=\u{0007}"

        XCTAssertEqual(filter.feed(Array(sequence.utf8)[...]), Array(sequence.utf8))
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
        let sequence = Array("\u{001B}]1337;File=inline=1:SGVsbG8=\u{0007}".utf8)

        for split in 0...sequence.count {
            var filter = TerminalInlineImageSafetyFilter(policy: .remoteDefault)
            let first = filter.feed(sequence[..<split])
            let second = filter.feed(sequence[split...])
            XCTAssertEqual(first + second, [], "split=\(split)")
            XCTAssertEqual(filter.blockedInlineImageCount, 1, "split=\(split)")
        }
    }

    func testOtherOSC1337CommandsPassThrough() {
        var filter = TerminalInlineImageSafetyFilter(policy: .remoteDefault)
        let sequence = Array("\u{001B}]1337;SetMark\u{0007}".utf8)

        XCTAssertEqual(filter.feed(sequence[...]), sequence)
    }
}
