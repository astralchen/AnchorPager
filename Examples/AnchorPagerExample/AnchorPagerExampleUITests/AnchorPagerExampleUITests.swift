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
        XCTAssertTrue(app.tabBars.buttons["AnchorPager"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["AnchorPager Example"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testNavigationIconPushesAnchorPagerAndHidesTabBar() throws {
        let app = XCUIApplication()
        app.launch()

        pushAnchorPagerExample(in: app)

        XCTAssertTrue(app.staticTexts["AnchorPager Example"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.buttons["AnchorPager"].exists)
    }

    @MainActor
    func testHeaderTopBehaviorMenuSwitchesVisibleConfiguration() throws {
        let app = XCUIApplication()
        app.launch()

        let behaviorButton = app.navigationBars["AnchorPager"].buttons["Header 顶部行为"]
        XCTAssertTrue(behaviorButton.waitForExistence(timeout: 3))
        XCTAssertEqual(behaviorButton.value as? String, "安全区内")

        behaviorButton.tap()

        let extendedAction = app.buttons["延伸到顶部"]
        XCTAssertTrue(extendedAction.waitForExistence(timeout: 3))
        extendedAction.tap()

        XCTAssertEqual(behaviorButton.value as? String, "延伸到顶部")
    }

    @MainActor
    func testLaunchShowsHeaderTabBarAndSelectedPageContent() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["AnchorPager Example"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["无内容页"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["短页"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["长页"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["无滚动页"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["短页 - 1"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTappingTabBarSelectsPageContent() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["短页 - 1"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["长页"].tap()

        XCTAssertTrue(app.staticTexts["长页 - 1"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testHorizontalSwipeSelectsNextPageContent() throws {
        let app = XCUIApplication()
        app.launch()

        let currentPageRow = app.staticTexts["短页 - 1"]
        XCTAssertTrue(currentPageRow.waitForExistence(timeout: 3))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.62))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.62))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(app.staticTexts["长页 - 1"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchArgumentSelectsPageThroughPublicAPI() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "3"]
        app.launch()

        XCTAssertTrue(app.staticTexts["无滚动页"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func pushAnchorPagerExample(in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["AnchorPager"].waitForExistence(timeout: 3))
        app.navigationBars["AnchorPager"].buttons["打开 AnchorPager"].tap()
        XCTAssertTrue(app.navigationBars["AnchorPager"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["AnchorPager Example"].waitForExistence(timeout: 3))
    }
}
