@testable import ApexTermApp
import Foundation
import XCTest

final class AutoCopyToastPresenterTests: XCTestCase {
    func testToastPreferencesUseProminentTwoSecondDefaults() {
        let suiteName = "AutoCopyToastPresenterTests.defaults.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let presentation = AutoCopyToastPreferences.current(defaults: defaults)

        XCTAssertEqual(presentation.scale, 1.45, accuracy: 0.001)
        XCTAssertEqual(presentation.duration, 2.0, accuracy: 0.001)
        XCTAssertEqual(presentation.transparency, 0.10, accuracy: 0.001)
        XCTAssertEqual(presentation.visibleAlpha, 0.90, accuracy: 0.001)
    }

    func testToastPreferencesReadStoredValuesAndClampUnsafeValues() {
        let suiteName = "AutoCopyToastPresenterTests.custom.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(1.25, forKey: AutoCopyToastPreferences.scaleKey)
        defaults.set(3.5, forKey: AutoCopyToastPreferences.durationKey)
        defaults.set(0.35, forKey: AutoCopyToastPreferences.transparencyKey)

        var presentation = AutoCopyToastPreferences.current(defaults: defaults)
        XCTAssertEqual(presentation.scale, 1.25, accuracy: 0.001)
        XCTAssertEqual(presentation.duration, 3.5, accuracy: 0.001)
        XCTAssertEqual(presentation.transparency, 0.35, accuracy: 0.001)
        XCTAssertEqual(presentation.visibleAlpha, 0.65, accuracy: 0.001)

        defaults.set(99.0, forKey: AutoCopyToastPreferences.scaleKey)
        defaults.set(-10.0, forKey: AutoCopyToastPreferences.durationKey)
        defaults.set(9.0, forKey: AutoCopyToastPreferences.transparencyKey)

        presentation = AutoCopyToastPreferences.current(defaults: defaults)
        XCTAssertEqual(presentation.scale, AutoCopyToastPreferences.scaleRange.upperBound)
        XCTAssertEqual(presentation.duration, AutoCopyToastPreferences.durationRange.lowerBound)
        XCTAssertEqual(
            presentation.transparency,
            AutoCopyToastPreferences.transparencyRange.upperBound
        )
    }
}
