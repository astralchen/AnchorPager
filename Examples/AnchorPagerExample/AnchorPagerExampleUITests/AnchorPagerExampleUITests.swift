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
    func testHeaderContentKeepsTwentyPointTopSafeAreaPaddingWhenSwitchingBehaviors() throws {
        let app = XCUIApplication()
        app.launch()

        let navigationBar = app.navigationBars["AnchorPager"]
        let title = app.staticTexts["AnchorPager Example"]
        let subtitle = app.staticTexts["Header UIView、显式 scroll view、无 scroll view child"]
        let behaviorButton = navigationBar.buttons["Header 顶部行为"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(subtitle.waitForExistence(timeout: 3))
        XCTAssertTrue(behaviorButton.waitForExistence(timeout: 3))
        XCTAssertEqual(title.frame.minY, navigationBar.frame.maxY + 20, accuracy: 1)
        XCTAssertEqual(subtitle.frame.minY - title.frame.maxY, 8, accuracy: 1)
        XCTAssertLessThanOrEqual(title.frame.height, 44)

        behaviorButton.tap()
        let extendedAction = app.buttons["延伸到顶部"]
        XCTAssertTrue(extendedAction.waitForExistence(timeout: 3))
        extendedAction.tap()

        XCTAssertEqual(title.frame.minY, navigationBar.frame.maxY + 20, accuracy: 1)
        XCTAssertEqual(subtitle.frame.minY - title.frame.maxY, 8, accuracy: 1)
        XCTAssertLessThanOrEqual(title.frame.height, 44)
    }

    @MainActor
    func testHeaderReturnsAfterTopBehaviorSwitchAndPullDown() throws {
        let app = XCUIApplication()
        app.launch()

        let tabItem = app.descendants(matching: .any)["短页"]
        XCTAssertTrue(tabItem.waitForExistence(timeout: 3))
        let initialMinY = tabItem.frame.minY
        let behaviorButton = app.navigationBars["AnchorPager"].buttons["Header 顶部行为"]

        behaviorButton.tap()
        XCTAssertTrue(app.buttons["延伸到顶部"].waitForExistence(timeout: 3))
        app.buttons["延伸到顶部"].tap()
        behaviorButton.tap()
        XCTAssertTrue(app.buttons["安全区内"].waitForExistence(timeout: 3))
        app.buttons["安全区内"].tap()

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56))
        start.press(forDuration: 0.1, thenDragTo: end)

        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                abs(tabItem.frame.minY - initialMinY) < 1
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 3), .completed)
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
    func testAdaptiveBarKeepsRealScrollAndFallbackPagesVisible() throws {
        let app = XCUIApplication()
        app.launch()

        let firstRow = app.staticTexts["scroll-page-first-row"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 3))

        app.descendants(matching: .any)["无滚动页"].tap()
        XCTAssertTrue(app.staticTexts["plain-page-content"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLongPageBottomStaysAboveTabBarWhileHeaderIsExpanded() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "2"]
        app.launch()

        let headerTitle = app.staticTexts["AnchorPager Example"]
        let lastRow = app.staticTexts["长页 - 30"]
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(headerTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(lastRow.waitForExistence(timeout: 3))
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
        let expandedHeaderMinY = headerTitle.frame.minY

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
        for _ in 0..<5 {
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        let bottomIsVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                lastRow.frame.maxY <= tabBar.frame.minY + 1
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [bottomIsVisible], timeout: 3), .completed)
        XCTAssertEqual(headerTitle.frame.minY, expandedHeaderMinY, accuracy: 1)
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
    func testCollapsedContainerRestoresLongPagePositionAfterSwitchingAway() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--anchorPagerInitialIndex", "2",
            "--anchorPagerInitialContainerCollapsed"
        ]
        app.launch()
        let row = app.staticTexts["长页 - 20"]
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        for _ in 0..<5 where !row.isHittable {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.isHittable)
        let savedMinY = row.frame.minY

        app.descendants(matching: .any)["短页"].tap()
        XCTAssertTrue(app.staticTexts["短页 - 1"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["长页"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.isHittable)
        XCTAssertEqual(row.frame.minY, savedMinY, accuracy: 2)
    }

    @MainActor
    func testExpandedContainerResetsPreviouslyScrolledTargetPageToTop() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "2"]
        app.launch()
        let twentiethRow = app.staticTexts["长页 - 20"]
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        for _ in 0..<5 where !twentiethRow.isHittable {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(twentiethRow.isHittable)

        app.descendants(matching: .any)["短页"].tap()
        XCTAssertTrue(app.staticTexts["短页 - 1"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["长页"].tap()

        XCTAssertTrue(app.staticTexts["长页 - 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["长页 - 1"].isHittable)
        XCTAssertFalse(twentiethRow.isHittable)
    }

    @MainActor
    func testReloadReplacesOldPageGenerationAndKeepsPageInteractive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "2"]
        app.launch()
        let oldGeneration = app.staticTexts["page-generation-1-long"]
        XCTAssertTrue(oldGeneration.waitForExistence(timeout: 3))

        let reloadButton = app.navigationBars["AnchorPager"].buttons["重新加载页面"]
        XCTAssertTrue(reloadButton.waitForExistence(timeout: 3))
        reloadButton.tap()

        XCTAssertTrue(app.staticTexts["page-generation-2-long"].waitForExistence(timeout: 3))
        XCTAssertFalse(oldGeneration.exists)
        XCTAssertTrue(app.staticTexts["长页 - 1"].exists)
    }

    @MainActor
    func testCompletedPageSwitchProducesOneAdditionalDidAppear() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "2"]
        app.launch()
        let appearance = app.staticTexts["page-appearance-long"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        XCTAssertTrue((appearance.value as? String)?.contains("didAppear=1") == true)

        app.descendants(matching: .any)["短页"].tap()
        XCTAssertTrue(app.staticTexts["短页 - 1"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["长页"].tap()

        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        XCTAssertTrue((appearance.value as? String)?.contains("didAppear=2") == true)
    }

    @MainActor
    private func pushAnchorPagerExample(in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["AnchorPager"].waitForExistence(timeout: 3))
        app.navigationBars["AnchorPager"].buttons["打开 AnchorPager"].tap()
        XCTAssertTrue(app.navigationBars["AnchorPager"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["AnchorPager Example"].waitForExistence(timeout: 3))
    }
}
