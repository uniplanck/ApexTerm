import CoreGraphics
import XCTest
@testable import ApexTermCore

final class TerminalDropRegionTests: XCTestCase {
    func testCenterAndAllEdgesResolveDeterministically() {
        let size = CGSize(width: 1_000, height: 600)

        XCTAssertEqual(TerminalDropRegion.resolve(location: CGPoint(x: 500, y: 300), size: size), .center)
        XCTAssertEqual(TerminalDropRegion.resolve(location: CGPoint(x: 10, y: 300), size: size), .left)
        XCTAssertEqual(TerminalDropRegion.resolve(location: CGPoint(x: 990, y: 300), size: size), .right)
        XCTAssertEqual(TerminalDropRegion.resolve(location: CGPoint(x: 500, y: 10), size: size), .top)
        XCTAssertEqual(TerminalDropRegion.resolve(location: CGPoint(x: 500, y: 590), size: size), .bottom)
    }

    func testClosestEdgeWinsAtCornersAndInvalidSizesFallBackToCenter() {
        let size = CGSize(width: 500, height: 300)

        XCTAssertEqual(TerminalDropRegion.resolve(location: CGPoint(x: 5, y: 40), size: size), .left)
        XCTAssertEqual(TerminalDropRegion.resolve(location: CGPoint(x: 250, y: 150), size: .zero), .center)
    }

    func testPreviewFramesMatchFinalWholeAndSplitFootprints() {
        let size = CGSize(width: 1_000, height: 600)
        let whole = TerminalDropRegion.center.previewFrame(in: size, inset: 10)
        let left = TerminalDropRegion.left.previewFrame(in: size, inset: 10)
        let right = TerminalDropRegion.right.previewFrame(in: size, inset: 10)
        let top = TerminalDropRegion.top.previewFrame(in: size, inset: 10)
        let bottom = TerminalDropRegion.bottom.previewFrame(in: size, inset: 10)

        XCTAssertEqual(whole, CGRect(x: 10, y: 10, width: 980, height: 580))
        XCTAssertEqual(left, CGRect(x: 10, y: 10, width: 490, height: 580))
        XCTAssertEqual(right, CGRect(x: 500, y: 10, width: 490, height: 580))
        XCTAssertEqual(top, CGRect(x: 10, y: 10, width: 980, height: 290))
        XCTAssertEqual(bottom, CGRect(x: 10, y: 300, width: 980, height: 290))
    }

    func testPreviewFrameClampsUnsafeInputs() {
        XCTAssertEqual(TerminalDropRegion.center.previewFrame(in: .zero), .zero)

        let frame = TerminalDropRegion.left.previewFrame(
            in: CGSize(width: 100, height: 80),
            inset: 1_000,
            splitFraction: 0.99
        )
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertLessThan(frame.width, 100)
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertLessThanOrEqual(frame.maxX, 100)
    }
}
