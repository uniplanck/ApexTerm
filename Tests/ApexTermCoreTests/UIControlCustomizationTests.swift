import XCTest
@testable import ApexTermCore

final class UIControlCustomizationTests: XCTestCase {
    func testDefaultsExposeEveryMainToolbarControlExactlyOnce() {
        let customization = UIControlCustomization()
        XCTAssertEqual(Set(customization.mainToolbarOrder), Set(UIControlID.controls(in: .mainToolbar)))
        XCTAssertEqual(customization.mainToolbarOrder.count, UIControlID.controls(in: .mainToolbar).count)
        XCTAssertTrue(UIControlID.allCases.allSatisfy(customization.isVisible))
    }

    func testVisibilityCanBeHiddenAndRestored() {
        var customization = UIControlCustomization()
        customization.setVisible(false, for: .quickTerminal)
        XCTAssertFalse(customization.isVisible(.quickTerminal))
        customization.setVisible(true, for: .quickTerminal)
        XCTAssertTrue(customization.isVisible(.quickTerminal))
    }

    func testRetiredToolbarChromeIsNotAvailableOnMainSurface() {
        XCTAssertFalse(UIControlID.toggleLeftSidebar.isMainToolbarSurfaceAvailable)
        XCTAssertFalse(UIControlID.toggleRightSidebar.isMainToolbarSurfaceAvailable)
        XCTAssertFalse(UIControlID.splitVertical.isMainToolbarSurfaceAvailable)
        XCTAssertFalse(UIControlID.splitHorizontal.isMainToolbarSurfaceAvailable)
        XCTAssertFalse(UIControlID.toggleCommandHistory.isMainToolbarSurfaceAvailable)
        XCTAssertFalse(UIControlID.toolbarPinWindow.isMainToolbarSurfaceAvailable)
        XCTAssertTrue(UIControlID.commandPalette.isMainToolbarSurfaceAvailable)
        XCTAssertTrue(UIControlID.controls(in: .tabBar).contains(.remoteHostLaunch))
    }

    func testTabSeparatorsAreVisibleByDefaultAndConfigurable() {
        var customization = UIControlCustomization()

        XCTAssertTrue(UIControlID.controls(in: .tabBar).contains(.tabSeparators))
        XCTAssertTrue(customization.isVisible(.tabSeparators))

        customization.setVisible(false, for: .tabSeparators)
        XCTAssertFalse(customization.isVisible(.tabSeparators))
    }

    func testToolbarOrderNormalizesDuplicatesAndMissingControls() {
        let customization = UIControlCustomization(
            mainToolbarOrder: [.findTerminal, .findTerminal, .commandPalette]
        )
        XCTAssertEqual(customization.mainToolbarOrder.first, .findTerminal)
        XCTAssertEqual(customization.mainToolbarOrder.dropFirst().first, .commandPalette)
        XCTAssertEqual(Set(customization.mainToolbarOrder), Set(UIControlID.controls(in: .mainToolbar)))
    }

    func testToolbarControlCanMoveBeforeAnotherControl() {
        var customization = UIControlCustomization()
        customization.moveMainToolbarControl(.toggleRightSidebar, before: .commandPalette)
        XCTAssertEqual(customization.mainToolbarOrder[1], .toggleRightSidebar)
        XCTAssertEqual(customization.mainToolbarOrder[2], .commandPalette)
    }

    func testResetRestoresToolbarOrderAndVisibilityOnlyForToolbar() {
        var customization = UIControlCustomization()
        customization.setVisible(false, for: .quickTerminal)
        customization.setVisible(false, for: .sidebarSettings)
        customization.moveMainToolbarControl(.toggleRightSidebar, before: .commandPalette)

        customization.resetMainToolbar()

        XCTAssertEqual(customization.mainToolbarOrder, UIControlCustomization.defaultMainToolbarOrder)
        XCTAssertTrue(customization.isVisible(.quickTerminal))
        XCTAssertFalse(customization.isVisible(.sidebarSettings))
    }
}
