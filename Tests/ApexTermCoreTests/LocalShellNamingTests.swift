import XCTest
@testable import ApexTermCore

final class LocalShellNamingTests: XCTestCase {
    func testTitleUsesTwoDigitMinimum() {
        XCTAssertEqual(LocalShellNaming.title(number: 1), "Local Shell (01)")
        XCTAssertEqual(LocalShellNaming.title(number: 12), "Local Shell (12)")
        XCTAssertEqual(LocalShellNaming.title(number: 123), "Local Shell (123)")
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
                "Local Shell (01)",
                "Local Shell (03)",
                "Build",
                "Local Shell (02)",
                "Local Shell (04)"
            ]
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
