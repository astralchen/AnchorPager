import XCTest

final class AnchorPagerExampleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsExampleTitle() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["AnchorPager"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchShowsHeaderTabBarAndSelectedPageContent() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["AnchorPager Example"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["短页"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["长页"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["无滚动"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["第二页 - 1"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTappingTabBarSelectsPageContent() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["第二页 - 1"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["短页"].tap()

        XCTAssertTrue(app.staticTexts["第一页 - 1"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testHorizontalSwipeSelectsNextPageContent() throws {
        let app = XCUIApplication()
        app.launch()

        let currentPageRow = app.staticTexts["第二页 - 1"]
        XCTAssertTrue(currentPageRow.waitForExistence(timeout: 3))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.62))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.62))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(app.staticTexts["无滚动页"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchArgumentSelectsPageThroughPublicAPI() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "2"]
        app.launch()

        XCTAssertTrue(app.staticTexts["无滚动页"].waitForExistence(timeout: 3))
    }
}
