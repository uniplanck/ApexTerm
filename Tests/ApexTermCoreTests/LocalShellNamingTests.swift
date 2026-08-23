import XCTest
@testable import ApexTermCore

final class LocalShellNamingTests: XCTestCase {
    func testTitleUsesCompactTwoDigitMinimum() {
        XCTAssertEqual(LocalShellNaming.title(number: 1), "01")
        XCTAssertEqual(LocalShellNaming.title(number: 12), "12")
        XCTAssertEqual(LocalShellNaming.title(number: 123), "123")
    }

    func testNextAvailableNumberReusesFirstGap() {
        XCTAssertEqual(
            LocalShellNaming.nextAvailableNumber(
                in: ["Local Shell (01)", "Local Shell (03)", "Custom"]
            ),
            2
        )
    }

    func testNormalizationNumbersPlainAndDuplicateAutomaticTitles() {
        XCTAssertEqual(
            LocalShellNaming.normalizedAutomaticTitles([
                "Local Shell",
                "Local Shell",
                "Build",
                "Local Shell (02)",
                "Local Shell (02)"
            ]),
            [
                "01",
                "03",
                "Build",
                "02",
                "04"
            ]
        )
    }

    func testLegacyAndCompactAutomaticTitlesShareNumberSpace() {
        XCTAssertEqual(LocalShellNaming.automaticNumber(in: "01"), 1)
        XCTAssertEqual(LocalShellNaming.automaticNumber(in: "Local Shell (02)"), 2)
        XCTAssertEqual(
            LocalShellNaming.nextAvailableNumber(in: ["01", "Local Shell (02)", "04"]),
            3
        )
    }

    func testCustomTitlesRemainUnchanged() {
        XCTAssertEqual(
            LocalShellNaming.normalizedAutomaticTitles([
                "API",
                "Local Shell - staging",
                "Local Shell (abc)"
            ]),
            [
                "API",
                "Local Shell - staging",
                "Local Shell (abc)"
            ]
        )
    }
}
