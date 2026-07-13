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
    func testSingleUpwardDragCollapsesHeaderThenContinuesIntoLongChild() throws {
        let app = launchLongPage()
        let stateProbe = scrollCoordinationStateProbe(in: app)

        drag(in: app, from: 0.78, to: 0.18)

        let state = waitForScrollState(from: stateProbe) {
            $0.page == "long" && $0.collapse >= 0.99 && $0.distance > 1
        }
        XCTAssertNotNil(state)
    }

    @MainActor
    func testSingleDownwardDragReturnsLongChildThenExpandsHeader() throws {
        let app = launchLongPage()
        let stateProbe = scrollCoordinationStateProbe(in: app)
        drag(in: app, from: 0.78, to: 0.18)
        let scrolled = waitForScrollState(from: stateProbe) {
            $0.collapse >= 0.99 && $0.distance > 1
        }
        let initialDistance = try XCTUnwrap(scrolled?.distance)

        drag(in: app, from: 0.22, to: 0.82)

        let returned = waitForScrollState(from: stateProbe) {
            $0.distance < initialDistance && $0.collapse < 0.99
        }
        XCTAssertNotNil(returned)
    }

    @MainActor
    func testShortAndPlainPagesRemainStableAcrossVerticalDrag() throws {
        let app = XCUIApplication()
        app.launch()
        let stateProbe = scrollCoordinationStateProbe(in: app)

        drag(in: app, from: 0.76, to: 0.24)
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "short" && $0.distance == 0
        })

        app.descendants(matching: .any)["无滚动页"].tap()
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "plain" && !$0.hasScrollTarget && $0.distance == 0
        })
        drag(in: app, from: 0.76, to: 0.24)
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "plain" && !$0.hasScrollTarget && $0.distance == 0
        })
    }

    @MainActor
    func testPlainPageRootReachesPhysicalBottomAndUsesContainerOnlyPan() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "3"]
        app.launch()
        let root = app.otherElements["plain-page-root"]
        let stateProbe = scrollCoordinationStateProbe(in: app)
        XCTAssertTrue(root.waitForExistence(timeout: 3))
        let initialFrame = root.frame

        XCTAssertGreaterThanOrEqual(initialFrame.maxY, app.frame.maxY - 1)
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "plain" && !$0.hasScrollTarget && $0.distance == 0
        })

        drag(in: app, from: 0.76, to: 0.24)

        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "plain" && !$0.hasScrollTarget
                && $0.collapse >= 0.99 && $0.distance == 0
        })
        let collapsedFrame = root.frame
        XCTAssertGreaterThanOrEqual(collapsedFrame.maxY, app.frame.maxY - 1)
        XCTAssertEqual(collapsedFrame.height, initialFrame.height, accuracy: 1)

        drag(in: app, from: 0.76, to: 0.24)
        XCTAssertEqual(root.frame, collapsedFrame)
    }

    @MainActor
    func testExpandedTopPullShowsVisibleContainerPresentationAndSettles() throws {
        let app = launchLongPage()
        let probe = scrollCoordinationStateProbe(in: app)

        drag(in: app, from: 0.30, to: 0.72)

        let state = try XCTUnwrap(waitForScrollState(from: probe) {
            $0.containerTopMax > 1 && abs($0.containerCurrent) < 0.5
        })
        XCTAssertEqual(state.mode, "container")
        XCTAssertEqual(state.distance, 0, accuracy: 0.5)
    }

    @MainActor
    func testPlainBottomPullShowsVisibleContainerPresentationAndSettles() throws {
        let app = launchPlainPage()
        let probe = scrollCoordinationStateProbe(in: app)
        drag(in: app, from: 0.76, to: 0.24)
        XCTAssertNotNil(waitForScrollState(from: probe) {
            $0.collapse >= 0.99
        })
        probe.tap()

        drag(in: app, from: 0.76, to: 0.24)

        let state = try XCTUnwrap(waitForScrollState(from: probe) {
            $0.containerBottomMax > 1 && abs($0.containerCurrent) < 0.5
        })
        XCTAssertFalse(state.hasScrollTarget)
        XCTAssertEqual(state.distance, 0, accuracy: 0.5)
    }

    @MainActor
    private func launchPlainPage() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "3"]
        app.launch()
        XCTAssertTrue(app.staticTexts["plain-page-content"].waitForExistence(timeout: 3))
        return app
    }

    @MainActor
    func testSwitchingPagesRebindsVerticalOwnerWithoutJump() throws {
        let app = launchLongPage()
        let stateProbe = scrollCoordinationStateProbe(in: app)
        drag(in: app, from: 0.78, to: 0.18)
        let longState = try XCTUnwrap(waitForScrollState(from: stateProbe) {
            $0.page == "long" && $0.collapse >= 0.99 && $0.distance > 1
        })

        app.descendants(matching: .any)["短页"].tap()
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "short" && $0.distance == 0 && $0.collapse >= 0.99
        })

        app.descendants(matching: .any)["长页"].tap()
        let restored = waitForScrollState(from: stateProbe) {
            $0.page == "long" && abs($0.distance - longState.distance) < 2 && $0.collapse >= 0.99
        }
        XCTAssertNotNil(restored)
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
    func testAdaptiveBarKeepsRealScrollAndPlainPagesVisible() throws {
        let app = XCUIApplication()
        app.launch()

        let firstRow = app.staticTexts["scroll-page-first-row"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 3))

        app.descendants(matching: .any)["无滚动页"].tap()
        XCTAssertTrue(app.staticTexts["plain-page-content"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLongPageBottomStaysAboveTabBarAfterNestedScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "2"]
        app.launch()

        let lastRow = app.staticTexts["长页 - 30"]
        let tabBar = app.tabBars.firstMatch
        let stateProbe = scrollCoordinationStateProbe(in: app)
        XCTAssertTrue(lastRow.waitForExistence(timeout: 3))
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))

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
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "long" && $0.collapse >= 0.99 && $0.distance > 0
        })
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
        let stateProbe = scrollCoordinationStateProbe(in: app)
        drag(in: app, from: 0.24, to: 0.76)
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "short" && $0.collapse <= 0.01 && $0.distance == 0
        })
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
    func testCancelledInteractivePagingKeepsAppearanceAndSelectionConsistent() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--anchorPagerInitialIndex", "2",
            "--anchorPagerAppearanceRecorder"
        ]
        app.launch()

        let longPage = app.staticTexts["长页 - 1"]
        let appearanceEvents = app.buttons["page-appearance-events"]
        XCTAssertTrue(longPage.waitForExistence(timeout: 3))
        XCTAssertTrue(appearanceEvents.waitForExistence(timeout: 3))

        XCTAssertTrue(appearanceEvents.isHittable)
        appearanceEvents.tap()
        XCTAssertEqual((appearanceEvents.value as? String) ?? "", "")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.62))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.62))
        start.press(
            forDuration: 0.2,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )

        let cancelSettled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let events = (appearanceEvents.value as? String)?.split(separator: "|").map(String.init) ?? []
                return events.contains("long.viewDidAppear")
                    && events.contains("short.viewDidDisappear")
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [cancelSettled], timeout: 3), .completed)

        let cancelledEvents = appearanceEventSequence(from: appearanceEvents)
        XCTAssertEqual(
            cancelledEvents.filter { $0 == "long.viewDidAppear" }.count,
            1,
            "取消事件：\(cancelledEvents)"
        )
        XCTAssertEqual(
            cancelledEvents.filter { $0 == "short.viewDidDisappear" }.count,
            1,
            "取消事件：\(cancelledEvents)"
        )
        XCTAssertFalse(cancelledEvents.contains("short.viewDidAppear"))
        XCTAssertFalse(cancelledEvents.contains("long.viewDidDisappear"))
        XCTAssertTrue(longPage.exists)
        XCTAssertTrue(app.frame.intersects(longPage.frame))

        app.descendants(matching: .any)["短页"].tap()
        XCTAssertTrue(app.staticTexts["短页 - 1"].waitForExistence(timeout: 3))

        let completedEvents = appearanceEventSequence(from: appearanceEvents)
        XCTAssertEqual(completedEvents.filter { $0 == "long.viewDidAppear" }.count, 1)
        XCTAssertEqual(completedEvents.filter { $0 == "long.viewDidDisappear" }.count, 1)
        XCTAssertEqual(completedEvents.filter { $0 == "short.viewDidAppear" }.count, 1)
        XCTAssertEqual(completedEvents.filter { $0 == "short.viewDidDisappear" }.count, 1)
    }

    @MainActor
    private func pushAnchorPagerExample(in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["AnchorPager"].waitForExistence(timeout: 3))
        app.navigationBars["AnchorPager"].buttons["打开 AnchorPager"].tap()
        XCTAssertTrue(app.navigationBars["AnchorPager"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["AnchorPager Example"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func appearanceEventSequence(from element: XCUIElement) -> [String] {
        ((element.value as? String) ?? "")
            .split(separator: "|")
            .map(String.init)
    }

    @MainActor
    private func launchLongPage() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "2"]
        app.launch()
        XCTAssertTrue(app.staticTexts["长页 - 1"].waitForExistence(timeout: 3))
        return app
    }

    @MainActor
    private func scrollCoordinationStateProbe(in app: XCUIApplication) -> XCUIElement {
        let probe = app.buttons["scroll-coordination-state"]
        XCTAssertTrue(probe.waitForExistence(timeout: 3))
        return probe
    }

    @MainActor
    private func drag(in app: XCUIApplication, from startY: CGFloat, to endY: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(
            forDuration: 0.12,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.05
        )
    }

    @MainActor
    private func waitForScrollState(
        from probe: XCUIElement,
        matching predicate: @escaping (ScrollCoordinationState) -> Bool
    ) -> ScrollCoordinationState? {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let state = ScrollCoordinationState(value: probe.value as? String) else {
                    return false
                }
                return predicate(state)
            },
            object: nil
        )
        guard XCTWaiter.wait(for: [expectation], timeout: 3) == .completed else {
            return nil
        }
        return ScrollCoordinationState(value: probe.value as? String)
    }
}

private struct ScrollCoordinationState {
    let page: String
    let hasScrollTarget: Bool
    let mode: String
    let collapse: CGFloat
    let distance: CGFloat
    let containerCurrent: CGFloat
    let containerTopMax: CGFloat
    let containerBottomMax: CGFloat
    let childTopCurrent: CGFloat
    let childTopMax: CGFloat
    let childBottomCurrent: CGFloat
    let childBottomMax: CGFloat

    init?(value: String?) {
        let fields = Dictionary(
            uniqueKeysWithValues: (value ?? "")
                .split(separator: ";")
                .compactMap { component -> (String, String)? in
                    let parts = component.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { return nil }
                    return (parts[0], parts[1])
                }
        )
        guard let page = fields["page"],
              let hasScrollTargetValue = fields["hasScrollTarget"],
              let mode = fields["mode"],
              let collapseValue = fields["collapse"],
              let collapse = Double(collapseValue),
              let distanceValue = fields["distance"],
              let distance = Double(distanceValue),
              let containerCurrentValue = fields["containerCurrent"],
              let containerCurrent = Double(containerCurrentValue),
              let containerTopMaxValue = fields["containerTopMax"],
              let containerTopMax = Double(containerTopMaxValue),
              let containerBottomMaxValue = fields["containerBottomMax"],
              let containerBottomMax = Double(containerBottomMaxValue),
              let childTopCurrentValue = fields["childTopCurrent"],
              let childTopCurrent = Double(childTopCurrentValue),
              let childTopMaxValue = fields["childTopMax"],
              let childTopMax = Double(childTopMaxValue),
              let childBottomCurrentValue = fields["childBottomCurrent"],
              let childBottomCurrent = Double(childBottomCurrentValue),
              let childBottomMaxValue = fields["childBottomMax"],
              let childBottomMax = Double(childBottomMaxValue) else {
            return nil
        }
        self.page = page
        self.hasScrollTarget = hasScrollTargetValue == "1"
        self.mode = mode
        self.collapse = CGFloat(collapse)
        self.distance = CGFloat(distance)
        self.containerCurrent = CGFloat(containerCurrent)
        self.containerTopMax = CGFloat(containerTopMax)
        self.containerBottomMax = CGFloat(containerBottomMax)
        self.childTopCurrent = CGFloat(childTopCurrent)
        self.childTopMax = CGFloat(childTopMax)
        self.childBottomCurrent = CGFloat(childBottomCurrent)
        self.childBottomMax = CGFloat(childBottomMax)
    }
}
