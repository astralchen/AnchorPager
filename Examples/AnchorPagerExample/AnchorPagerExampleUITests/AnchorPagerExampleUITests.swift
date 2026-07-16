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
    func testPlainContainerTopBounceIsVisible() throws {
        let app = launchPage(index: 3, mode: "container")
        let probe = scrollCoordinationStateProbe(in: app)
        XCTAssertNotNil(waitForScrollState(from: probe) {
            $0.headerContentTop > 1 && $0.headerContentTopDeltaMax < 0.5
        })
        probe.tap()

        drag(in: app, from: 0.30, to: 0.72)

        let state = try XCTUnwrap(waitForScrollState(from: probe) {
            $0.containerTopMax > 1 && abs($0.containerCurrent) < 0.5
        })
        XCTAssertFalse(state.hasScrollTarget)
        XCTAssertEqual(state.mode, "container")
        XCTAssertEqual(state.childTopMax, 0, accuracy: 0.5)
        XCTAssertGreaterThan(state.containerTopMax, 1)
        XCTAssertLessThan(state.headerHeightDeltaMax, 0.5)
        XCTAssertLessThan(state.headerContentTopDeltaMax, 0.5)
    }

    @MainActor
    func testPlainContainerBottomBounceIsVisible() throws {
        let app = launchPage(index: 3, mode: "none")
        let probe = scrollCoordinationStateProbe(in: app)
        let root = app.otherElements["plain-page-root"]
        XCTAssertTrue(root.waitForExistence(timeout: 3))
        drag(in: app, from: 0.76, to: 0.24)
        XCTAssertNotNil(waitForScrollState(from: probe) {
            $0.collapse >= 0.99
        })
        probe.tap()

        drag(in: app, from: 0.76, to: 0.24)

        let state = try XCTUnwrap(waitForScrollState(from: probe) {
            $0.containerBottomMax > 1
                && $0.barMax < 0.5
                && abs($0.containerCurrent) < 0.5
                && abs($0.barCurrent) < 0.5
        })
        XCTAssertFalse(state.hasScrollTarget)
        XCTAssertGreaterThanOrEqual(root.frame.maxY, app.frame.maxY - 1)
    }

    @MainActor
    func testRealChildContainerTopBounceIsVisible() throws {
        let app = launchPage(index: 2, mode: "container")
        let probe = scrollCoordinationStateProbe(in: app)

        drag(in: app, from: 0.30, to: 0.72)

        let state = try XCTUnwrap(waitForScrollState(from: probe) {
            $0.containerTopMax > 1
                && abs($0.containerCurrent) < 0.5
                && abs($0.childTopCurrent) < 0.5
        })
        XCTAssertEqual(state.mode, "container")
        XCTAssertLessThan(state.childTopMax, 0.5)
        XCTAssertEqual(state.distance, 0, accuracy: 0.5)
    }

    @MainActor
    func testRealChildTopBounceUsesChildMode() throws {
        let app = launchPage(index: 2, mode: "child")
        let probe = scrollCoordinationStateProbe(in: app)

        drag(in: app, from: 0.30, to: 0.72)

        let state = try XCTUnwrap(waitForScrollState(from: probe) {
            $0.childTopMax > 1
                && abs($0.childTopCurrent) < 0.5
                && abs($0.containerCurrent) < 0.5
        })
        XCTAssertEqual(state.mode, "child")
        XCTAssertLessThan(state.containerTopMax, 0.5)
    }

    @MainActor
    func testNoneModeHasNoVisibleTopOwner() throws {
        let app = launchPage(index: 2, mode: "none")
        let probe = scrollCoordinationStateProbe(in: app)
        probe.tap()

        drag(in: app, from: 0.30, to: 0.72)

        let state = try XCTUnwrap(waitForScrollState(from: probe) {
            abs($0.containerCurrent) < 0.5 && abs($0.childTopCurrent) < 0.5
        })
        XCTAssertEqual(state.mode, "none")
        XCTAssertLessThan(state.containerTopMax, 0.5)
        XCTAssertLessThan(state.childTopMax, 0.5)
        XCTAssertEqual(state.distance, 0, accuracy: 0.5)
    }

    @MainActor
    func testRealChildBottomBounceUsesChild() throws {
        let app = launchPage(index: 2, mode: "container")
        let probe = scrollCoordinationStateProbe(in: app)
        let lastRow = app.staticTexts["长页 - 30"]
        for _ in 0..<6 where !lastRow.isHittable {
            drag(in: app, from: 0.76, to: 0.24)
        }
        XCTAssertTrue(lastRow.isHittable)
        probe.tap()

        drag(in: app, from: 0.76, to: 0.24)

        let state = try XCTUnwrap(waitForScrollState(from: probe) {
            $0.childBottomMax > 1
                && abs($0.childBottomCurrent) < 0.5
                && abs($0.containerCurrent) < 0.5
        })
        XCTAssertLessThan(state.containerBottomMax, 0.5)
        XCTAssertLessThan(state.barMax, 0.5)
        XCTAssertGreaterThanOrEqual(state.collapse, 0.99)
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
                && $0.mode == "container" && $0.hasZeroPresentationMetrics
        })

        app.descendants(matching: .any)["长页"].tap()
        let restored = waitForScrollState(from: stateProbe) {
            $0.page == "long" && abs($0.distance - longState.distance) < 2
                && $0.collapse >= 0.99 && $0.mode == "container"
                && $0.hasScrollTarget && $0.hasZeroPresentationMetrics
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
        let probe = scrollCoordinationStateProbe(in: app)

        XCTAssertNotNil(waitForScrollState(from: probe) {
            $0.containerTopInset < 0.5 && $0.headerHeight > 1
        })
        openSettingsSubmenu(named: "Header 顶部行为", in: app)
        let safeAreaAction = app.buttons["安全区内"]
        let extendedAction = app.buttons["延伸到顶部"]
        XCTAssertTrue(safeAreaAction.waitForExistence(timeout: 3))
        XCTAssertTrue(extendedAction.waitForExistence(timeout: 3))
        XCTAssertTrue(extendedAction.isSelected)
        safeAreaAction.tap()

        openSettingsSubmenu(named: "Header 顶部行为", in: app)
        XCTAssertTrue(app.buttons["安全区内"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["安全区内"].isSelected)
        XCTAssertNotNil(waitForScrollState(from: probe) {
            $0.containerTopInset > 1
        })
    }

    @MainActor
    func testInsideSafeAreaUsesTopInsetAndKeepsHeaderHeightDuringCollapse() throws {
        let app = XCUIApplication()
        app.launch()
        selectHeaderTopBehavior(named: "安全区内", in: app)
        let probe = scrollCoordinationStateProbe(in: app)
        XCTAssertNotNil(waitForScrollState(from: probe) {
            $0.containerTopInset > 1 && $0.headerHeight > 1
        })
        probe.tap()

        drag(in: app, from: 0.62, to: 0.50)

        let state = try XCTUnwrap(waitForScrollState(from: probe) {
            $0.containerTopInset > 1
                && $0.headerCollapse > 1
                && $0.headerHeightDeltaMax < 0.5
        })
        XCTAssertGreaterThan(state.headerHeight, 1)
        XCTAssertLessThan(state.headerHeightDeltaMax, 0.5)
    }

    @MainActor
    func testExtendsUnderTopSafeAreaUsesZeroTopInsetAndPreservesBarPosition() throws {
        let app = XCUIApplication()
        app.launch()
        selectHeaderTopBehavior(named: "安全区内", in: app)
        let probe = scrollCoordinationStateProbe(in: app)
        let barItem = app.descendants(matching: .any)["短页"]
        XCTAssertTrue(barItem.waitForExistence(timeout: 3))
        drag(in: app, from: 0.62, to: 0.50)
        XCTAssertNotNil(waitForScrollState(from: probe) {
            $0.containerTopInset > 1 && $0.headerCollapse > 1
        })
        let beforeBarMinY = barItem.frame.minY

        selectHeaderTopBehavior(named: "延伸到顶部", in: app)

        let state = try XCTUnwrap(waitForScrollState(from: probe) {
            $0.containerTopInset < 0.5
                && abs($0.barCurrent) < 0.5
        })
        XCTAssertEqual(barItem.frame.minY, beforeBarMinY, accuracy: 1)
        XCTAssertLessThan(state.headerHeightDeltaMax, 0.5)
    }

    @MainActor
    func testUnifiedSettingsMenuSwitchesTopOverscrollMode() throws {
        let app = XCUIApplication()
        app.launch()
        let probe = scrollCoordinationStateProbe(in: app)
        XCTAssertNotNil(waitForScrollState(from: probe) {
            $0.mode == "container" && $0.hasZeroPresentationMetrics
        })

        openSettingsSubmenu(named: "顶部回弹模式", in: app)
        let childAction = app.buttons["子页面"]
        XCTAssertTrue(childAction.waitForExistence(timeout: 3))
        childAction.tap()

        XCTAssertNotNil(waitForScrollState(from: probe) {
            $0.mode == "child" && $0.hasZeroPresentationMetrics
        })
    }

    @MainActor
    func testHeaderContentKeepsTwentyPointTopSafeAreaPaddingWhenSwitchingBehaviors() throws {
        let app = XCUIApplication()
        app.launch()

        let navigationBar = app.navigationBars["AnchorPager"]
        let title = app.staticTexts["AnchorPager Example"]
        let subtitle = app.staticTexts["Header UIView、显式 scroll view、无 scroll view child"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(subtitle.waitForExistence(timeout: 3))
        XCTAssertEqual(title.frame.minY, navigationBar.frame.maxY + 20, accuracy: 1)
        XCTAssertEqual(subtitle.frame.minY - title.frame.maxY, 8, accuracy: 1)
        XCTAssertLessThanOrEqual(title.frame.height, 44)

        selectHeaderTopBehavior(named: "安全区内", in: app)

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

        selectHeaderTopBehavior(named: "安全区内", in: app)
        selectHeaderTopBehavior(named: "延伸到顶部", in: app)

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
    func testHorizontalBusinessRegionDoesNotDriveVerticalContainer() throws {
        let app = launchPage(index: 4, mode: "container")
        let stateProbe = scrollCoordinationStateProbe(in: app)
        let horizontalScrollView = app.scrollViews["horizontal-business-scroll"]
        let ownershipProbe = app.otherElements["horizontal-business-probe"]
        let firstCard = app.staticTexts["横向业务内容 1"]

        XCTAssertTrue(horizontalScrollView.waitForExistence(timeout: 3))
        XCTAssertTrue(ownershipProbe.waitForExistence(timeout: 3))
        XCTAssertTrue(firstCard.waitForExistence(timeout: 3))
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "horizontal"
                && !$0.hasScrollTarget
                && $0.collapse < 0.01
                && abs($0.headerCollapse) < 0.5
        })
        stateProbe.tap()
        let initialFirstCardMinX = firstCard.frame.minX

        let start = horizontalScrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.82, dy: 0.45)
        )
        let end = horizontalScrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.18, dy: 0.55)
        )
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.05
        )

        let state = try XCTUnwrap(waitForScrollState(from: stateProbe) {
            $0.page == "horizontal"
                && !$0.hasScrollTarget
                && $0.collapse < 0.01
                && abs($0.headerCollapse) < 0.5
                && $0.hasZeroPresentationMetrics
        }, "probe：\(String(describing: stateProbe.value))")
        XCTAssertFalse(state.hasScrollTarget)
        XCTAssertLessThan(state.collapse, 0.01)
        XCTAssertLessThan(abs(state.headerCollapse), 0.5)
        XCTAssertTrue(state.hasZeroPresentationMetrics)
        XCTAssertLessThan(
            firstCard.frame.minX,
            initialFirstCardMinX - 20,
            "业务横向内容必须产生真实位移"
        )
        XCTAssertEqual(
            ownershipProbe.value as? String,
            "scrollDelegate=1;panDelegate=1;bounces=1;alwaysBounceVertical=0;isScrollEnabled=1;horizontalRange=1"
        )
    }

    @MainActor
    func testCompositionalVerticalRegionHandsOffToCollectionView() throws {
        let app = launchPage(index: 5, mode: "container")
        let stateProbe = scrollCoordinationStateProbe(in: app)
        let compositionalProbe = compositionalScrollProbe(in: app)
        let verticalCard = app.cells["compositional-vertical-card-1"]

        XCTAssertTrue(verticalCard.waitForExistence(timeout: 3))
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "compositional"
                && $0.hasScrollTarget
                && $0.collapse < 0.01
        })
        reset(trace: stateProbe)

        let start = verticalCard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)
        )
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)
        )
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.05
        )

        let state = try XCTUnwrap(waitForScrollState(from: stateProbe, timeout: 5) {
            $0.page == "compositional"
                && $0.hasScrollTarget
                && $0.collapse >= 0.99
                && $0.distance > 0.5
                && $0.containerToChild
                && $0.invariantMax <= 0.5
        })
        let compositional = try XCTUnwrap(
            CompositionalScrollState(value: compositionalProbe.value as? String)
        )

        XCTAssertEqual(state.page, "compositional")
        XCTAssertTrue(state.hasScrollTarget)
        XCTAssertGreaterThan(state.distance, 0.5)
        XCTAssertTrue(compositional.hasStableOwnership)
        XCTAssertTrue(compositional.hasVerticalRange)
    }

    @MainActor
    func testCompositionalOrthogonalRegionOwnsHorizontalDrag() throws {
        let app = launchPage(index: 5, mode: "container")
        let stateProbe = scrollCoordinationStateProbe(in: app)
        let compositionalProbe = compositionalScrollProbe(in: app)
        let trace = selectionTraceProbe(in: app)
        let firstCard = app.cells["compositional-horizontal-card-1"]
        let secondCard = app.cells["compositional-horizontal-card-2"]

        XCTAssertTrue(firstCard.waitForExistence(timeout: 3))
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "compositional"
                && $0.hasScrollTarget
                && $0.collapse < 0.01
        })
        reset(trace: stateProbe)
        reset(trace: compositionalProbe)
        reset(trace: trace)
        let initialFirstFrame = firstCard.frame
        let initialSecondFrame = secondCard.frame

        let leftStart = firstCard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.82, dy: 0.45)
        )
        let leftEnd = firstCard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.18, dy: 0.55)
        )
        leftStart.press(
            forDuration: 0.1,
            thenDragTo: leftEnd,
            withVelocity: .slow,
            thenHoldForDuration: 0.05
        )

        let movedForwardCandidate = waitForCompositionalState(
            from: compositionalProbe,
            timeout: 5
        ) {
            $0.maximumHorizontalOffset > 30
                && $0.currentHorizontalOffset > 20
        }
        XCTAssertNotNil(
            movedForwardCandidate,
            "组合横向进度未建立；probe=\(String(describing: compositionalProbe.value));"
                + "state=\(String(describing: stateProbe.value));"
                + "selection=\(String(describing: trace.value));"
                + "firstFrame=\(initialFirstFrame)->\(firstCard.frame);"
                + "secondFrame=\(initialSecondFrame)->\(secondCard.frame)"
        )
        let movedForward = try XCTUnwrap(movedForwardCandidate)
        let forwardOffset = movedForward.currentHorizontalOffset
        let forwardScrollState = try XCTUnwrap(waitForScrollState(
            from: stateProbe,
            timeout: 5
        ) {
            $0.page == "compositional"
                && $0.hasScrollTarget
                && $0.collapse < 0.01
                && abs($0.headerCollapse) < 0.5
                && $0.distance < 0.5
                && $0.hasZeroPresentationMetrics
        })

        XCTAssertEqual(selectionEventSequence(from: trace), [])
        XCTAssertTrue(forwardScrollState.hasZeroPresentationMetrics)

        let visibleCard = try XCTUnwrap(
            hittableCompositionalHorizontalCards(in: app).first
        )
        let rightStart = visibleCard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.18, dy: 0.55)
        )
        let rightEnd = visibleCard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.82, dy: 0.45)
        )
        rightStart.press(
            forDuration: 0.1,
            thenDragTo: rightEnd,
            withVelocity: .slow,
            thenHoldForDuration: 0.05
        )

        let movedBackward = try XCTUnwrap(waitForCompositionalState(
            from: compositionalProbe,
            timeout: 5
        ) {
            $0.currentHorizontalOffset < forwardOffset - 20
        })
        let backwardScrollState = try XCTUnwrap(waitForScrollState(
            from: stateProbe,
            timeout: 5
        ) {
            $0.page == "compositional"
                && $0.hasScrollTarget
                && $0.collapse < 0.01
                && abs($0.headerCollapse) < 0.5
                && $0.distance < 0.5
                && $0.hasZeroPresentationMetrics
        })

        XCTAssertLessThan(movedBackward.currentHorizontalOffset, forwardOffset - 20)
        XCTAssertEqual(backwardScrollState.page, "compositional")
        XCTAssertEqual(selectionEventSequence(from: trace), [])
    }

    @MainActor
    func testCompositionalPageDisablesNonOrthogonalSwipeButKeepsBarSelection() throws {
        let app = launchPage(index: 5, mode: "container")
        let stateProbe = scrollCoordinationStateProbe(in: app)
        let trace = selectionTraceProbe(in: app)
        let verticalCard = app.cells["compositional-vertical-card-1"]

        XCTAssertTrue(verticalCard.waitForExistence(timeout: 3))
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "compositional" && $0.hasScrollTarget
        })
        reset(trace: trace)

        let start = verticalCard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.18, dy: 0.52)
        )
        let end = verticalCard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.82, dy: 0.48)
        )
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.05
        )

        let stateAfterSwipe = try XCTUnwrap(waitForScrollState(from: stateProbe) {
            $0.page == "compositional" && $0.hasScrollTarget
        })
        XCTAssertEqual(stateAfterSwipe.page, "compositional")
        XCTAssertEqual(selectionEventSequence(from: trace), [])

        app.descendants(matching: .any)["横向业务页"].tap()
        XCTAssertTrue(
            app.scrollViews["horizontal-business-scroll"].waitForExistence(timeout: 5)
        )
        XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [4]), [4])
    }

    @MainActor
    func testCompositionalPageKeepsPublicSelectionAvailable() throws {
        let app = launchInteractionPage(
            initialIndex: 5,
            rapidTargets: "4",
            recordsAppearance: true
        )
        let trace = selectionTraceProbe(in: app)
        reset(trace: trace)

        rapidSelectionTrigger(in: app).tap()

        XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [4]), [4])
        XCTAssertTrue(
            app.scrollViews["horizontal-business-scroll"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testEnabledPageCanSwipeIntoDisabledHorizontalPageThenBarToCompositional() throws {
        let app = launchPage(index: 3, mode: "container")
        let stateProbe = scrollCoordinationStateProbe(in: app)
        let trace = selectionTraceProbe(in: app)
        reset(trace: trace)
        let pageStart = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.82, dy: 0.78)
        )
        let pageEnd = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.18, dy: 0.78)
        )
        pageStart.press(forDuration: 0.1, thenDragTo: pageEnd)

        let horizontalScrollView = app.scrollViews["horizontal-business-scroll"]
        XCTAssertTrue(horizontalScrollView.waitForExistence(timeout: 5))
        XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [4]), [4])
        XCTAssertNotNil(waitForScrollState(from: stateProbe, timeout: 5) {
            $0.page == "horizontal"
                && !$0.hasScrollTarget
                && $0.hasZeroPresentationMetrics
        })

        let firstCard = app.staticTexts["横向业务内容 1"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 3))
        let initialMinX = firstCard.frame.minX
        let businessStart = horizontalScrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.82, dy: 0.45)
        )
        let businessEnd = horizontalScrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.18, dy: 0.55)
        )
        businessStart.press(
            forDuration: 0.1,
            thenDragTo: businessEnd,
            withVelocity: .slow,
            thenHoldForDuration: 0.05
        )

        XCTAssertLessThan(firstCard.frame.minX, initialMinX - 20)
        XCTAssertEqual(selectionEventSequence(from: trace), [4])
        XCTAssertNotNil(waitForScrollState(from: stateProbe, timeout: 5) {
            $0.page == "horizontal"
                && !$0.hasScrollTarget
                && $0.hasZeroPresentationMetrics
        })

        let compositionalItem = app.descendants(matching: .any)["组合布局页"]
        XCTAssertTrue(compositionalItem.waitForExistence(timeout: 3))
        compositionalItem.tap()

        let card = app.cells["compositional-horizontal-card-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [4, 5]), [4, 5])

        let compositionalProbe = compositionalScrollProbe(in: app)
        reset(trace: compositionalProbe)
        let cardStart = card.coordinate(
            withNormalizedOffset: CGVector(dx: 0.82, dy: 0.48)
        )
        let cardEnd = card.coordinate(
            withNormalizedOffset: CGVector(dx: 0.18, dy: 0.52)
        )
        cardStart.press(
            forDuration: 0.1,
            thenDragTo: cardEnd,
            withVelocity: .slow,
            thenHoldForDuration: 0.05
        )

        XCTAssertNotNil(waitForCompositionalState(
            from: compositionalProbe,
            timeout: 5
        ) {
            $0.maximumHorizontalOffset > 20
        })
        XCTAssertEqual(selectionEventSequence(from: trace), [4, 5])
    }

    @MainActor
    func testCompositionalReloadRebindsRootVerticalTarget() throws {
        let app = launchPage(index: 5, mode: "container")
        let stateProbe = scrollCoordinationStateProbe(in: app)
        let generationOne = app.staticTexts["page-generation-1-compositional"]

        XCTAssertTrue(generationOne.waitForExistence(timeout: 3))
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "compositional" && $0.hasScrollTarget
        })

        let reload = app.navigationBars.buttons["重新加载页面"]
        XCTAssertTrue(reload.waitForExistence(timeout: 3))
        reload.tap()

        let generationTwo = app.staticTexts["page-generation-2-compositional"]
        XCTAssertTrue(generationTwo.waitForExistence(timeout: 5))
        XCTAssertFalse(generationOne.exists)
        XCTAssertNotNil(waitForScrollState(from: stateProbe, timeout: 5) {
            $0.page == "compositional"
                && $0.hasScrollTarget
                && $0.hasZeroPresentationMetrics
        })

        let compositionalProbe = compositionalScrollProbe(in: app)
        let card = app.cells["compositional-horizontal-card-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        reset(trace: compositionalProbe)
        let start = card.coordinate(
            withNormalizedOffset: CGVector(dx: 0.82, dy: 0.48)
        )
        let end = card.coordinate(
            withNormalizedOffset: CGVector(dx: 0.18, dy: 0.52)
        )
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.05
        )

        XCTAssertNotNil(waitForCompositionalState(
            from: compositionalProbe,
            timeout: 5
        ) {
            $0.maximumHorizontalOffset > 20
                && $0.hasStableOwnership
                && $0.hasVerticalRange
        })
    }

    @MainActor
    func testRapidPublicSelectionsCommitRealIntermediateThenLatestTarget() throws {
        let app = launchInteractionPage(
            initialIndex: 1,
            rapidTargets: "2,3,0",
            recordsAppearance: true
        )
        let trace = selectionTraceProbe(in: app)
        let appearance = appearanceEventsProbe(in: app)
        let trigger = rapidSelectionTrigger(in: app)
        reset(trace: trace)
        reset(trace: appearance)

        trigger.tap()

        XCTAssertTrue(app.staticTexts["page-generation-1-empty"].waitForExistence(timeout: 5))
        let committed = waitForSelectionTrace(from: trace, matching: [2, 0])
        XCTAssertEqual(
            committed,
            [2, 0],
            "实际 trace：\(selectionEventSequence(from: trace))"
        )
        let events = appearanceEventSequence(from: appearance)
        XCTAssertTrue(events.contains("long.viewDidAppear"), "事件：\(events)")
        XCTAssertTrue(events.contains("long.viewDidDisappear"), "事件：\(events)")
        XCTAssertTrue(events.contains("empty.viewDidAppear"), "事件：\(events)")
        XCTAssertFalse(events.contains("plain.viewDidAppear"), "事件：\(events)")
    }

    @MainActor
    func testRapidBarSelectionsUseLatestPendingWithoutHanging() throws {
        let app = launchInteractionPage(
            initialIndex: 1,
            rapidBarTargets: "2,3,0",
            recordsAppearance: true
        )
        let trace = selectionTraceProbe(in: app)
        let appearance = appearanceEventsProbe(in: app)
        reset(trace: trace)
        reset(trace: appearance)

        rapidSelectionTrigger(in: app).tap()

        XCTAssertTrue(app.staticTexts["page-generation-1-empty"].waitForExistence(timeout: 5))
        let committed = waitForSelectionTrace(from: trace, matching: [2, 0])
        XCTAssertEqual(
            committed,
            [2, 0],
            "实际 trace：\(selectionEventSequence(from: trace))"
        )
        let events = appearanceEventSequence(from: appearance)
        XCTAssertTrue(events.contains("long.viewDidAppear"), "事件：\(events)")
        XCTAssertTrue(events.contains("long.viewDidDisappear"), "事件：\(events)")
        XCTAssertTrue(events.contains("empty.viewDidAppear"), "事件：\(events)")
        XCTAssertFalse(events.contains("plain.viewDidAppear"), "事件：\(events)")
    }

    @MainActor
    func testMixedAPIAndBarSelectionsShareOneLatestPendingQueue() throws {
        let app = launchInteractionPage(
            initialIndex: 1,
            rapidTargets: "2",
            rapidBarTargets: "3,0",
            recordsAppearance: true
        )
        let trace = selectionTraceProbe(in: app)
        let appearance = appearanceEventsProbe(in: app)
        reset(trace: trace)
        reset(trace: appearance)

        rapidSelectionTrigger(in: app).tap()

        XCTAssertTrue(app.staticTexts["page-generation-1-empty"].waitForExistence(timeout: 5))
        let committed = waitForSelectionTrace(from: trace, matching: [2, 0])
        XCTAssertEqual(
            committed,
            [2, 0],
            "实际 trace：\(selectionEventSequence(from: trace))"
        )
        let events = appearanceEventSequence(from: appearance)
        XCTAssertTrue(events.contains("long.viewDidAppear"), "事件：\(events)")
        XCTAssertTrue(events.contains("long.viewDidDisappear"), "事件：\(events)")
        XCTAssertTrue(events.contains("empty.viewDidAppear"), "事件：\(events)")
        XCTAssertFalse(events.contains("plain.viewDidAppear"), "事件：\(events)")
    }

    @MainActor
    func testNonadjacentSelectionUsesSingleSourceTargetTransition() throws {
        let app = launchInteractionPage(
            initialIndex: 1,
            rapidTargets: "4",
            recordsAppearance: true
        )
        let trace = selectionTraceProbe(in: app)
        let appearance = appearanceEventsProbe(in: app)
        reset(trace: trace)
        reset(trace: appearance)

        rapidSelectionTrigger(in: app).tap()

        XCTAssertTrue(app.staticTexts["横向业务内容 1"].waitForExistence(timeout: 5))
        XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [4]), [4])
        let events = appearanceEventSequence(from: appearance)
        XCTAssertEqual(events.filter { $0 == "short.viewDidDisappear" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "horizontal.viewDidAppear" }.count, 1)
        XCTAssertFalse(events.contains("long.viewDidAppear"), "事件：\(events)")
        XCTAssertFalse(events.contains("plain.viewDidAppear"), "事件：\(events)")
    }

    @MainActor
    func testCompletedInteractivePagingAcceptsImmediateExplicitRequest() throws {
        let app = launchInteractionPage(
            initialIndex: 1,
            rapidTargets: "3",
            recordsAppearance: true
        )
        let trace = selectionTraceProbe(in: app)
        let appearance = appearanceEventsProbe(in: app)
        reset(trace: trace)
        reset(trace: appearance)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.62))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.62))
        start.press(forDuration: 0.1, thenDragTo: end)
        rapidSelectionTrigger(in: app).tap()

        XCTAssertTrue(app.staticTexts["plain-page-content"].waitForExistence(timeout: 5))
        XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [2, 3]), [2, 3])
        let events = appearanceEventSequence(from: appearance)
        XCTAssertEqual(events.filter { $0 == "long.viewDidAppear" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "long.viewDidDisappear" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "plain.viewDidAppear" }.count, 1)
    }

    @MainActor
    func testTrackedScrollReloadAndLayoutWaitForInteractionTerminal() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--anchorPagerInitialIndex", "2",
            "--anchorPagerTopOverscrollMode", "container",
            "--anchorPagerTrackedScrollCompetition", "reload-layout"
        ]
        app.launch()
        let oldGeneration = app.staticTexts["page-generation-1-long"]
        let probe = scrollCoordinationStateProbe(in: app)
        let competition = app.otherElements["tracked-competition-trace"]
        XCTAssertTrue(oldGeneration.waitForExistence(timeout: 3))
        XCTAssertTrue(competition.waitForExistence(timeout: 3))

        drag(in: app, from: 0.76, to: 0.24)

        XCTAssertEqual(
            (competition.value as? String) ?? "",
            "triggered=1;tracking=1;oldVisibleAfterPublic=1"
        )
        XCTAssertTrue(app.staticTexts["page-generation-2-long"].waitForExistence(timeout: 5))
        XCTAssertFalse(oldGeneration.exists)
        let settled = waitForScrollState(from: probe) {
            $0.page == "long" && $0.hasScrollTarget
                && $0.hasZeroPresentationMetrics
        }
        XCTAssertNotNil(settled, "实际 probe：\((probe.value as? String) ?? "nil")")
    }

    @MainActor
    func testSizeTransitionKeepsLatestSelectionAndSingleTerminal() throws {
        let app = launchInteractionPage(
            initialIndex: 1,
            sizeTransitionTargets: "4,3",
            recordsAppearance: true
        )
        let trace = selectionTraceProbe(in: app)
        let appearance = appearanceEventsProbe(in: app)
        let stateProbe = scrollCoordinationStateProbe(in: app)
        reset(trace: trace)
        reset(trace: appearance)
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }

        XCUIDevice.shared.orientation = .landscapeLeft

        XCTAssertTrue(app.staticTexts["plain-page-content"].waitForExistence(timeout: 5))
        XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [3]), [3])
        let events = appearanceEventSequence(from: appearance)
        XCTAssertEqual(events.filter { $0 == "short.viewDidDisappear" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "plain.viewDidAppear" }.count, 1)
        XCTAssertFalse(events.contains("horizontal.viewDidAppear"), "事件：\(events)")
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "plain" && !$0.hasScrollTarget
                && $0.hasZeroPresentationMetrics
        })
    }

    @MainActor
    func testFastUpwardFlingHandsRemainingVelocityFromContainerToChild() throws {
        let app = launchLongPage()
        let probe = scrollCoordinationStateProbe(in: app)
        probe.tap()

        fastDrag(
            in: app,
            from: CGVector(dx: 0.5, dy: 0.72),
            to: CGVector(dx: 0.5, dy: 0.64)
        )

        let state = try XCTUnwrap(waitForScrollState(from: probe, timeout: 5) {
            $0.page == "long" && $0.containerToChild
                && $0.collapse >= 0.99 && $0.distance > 1
        })
        XCTAssertGreaterThan(state.samples, 2)
        let probeValue = (probe.value as? String) ?? "nil"
        XCTAssertLessThanOrEqual(state.reversalMax, 0.5, "probe：\(probeValue)")
        XCTAssertLessThanOrEqual(state.invariantMax, 0.5, "probe：\(probeValue)")
        XCTAssertEqual(
            state.canonical,
            state.headerCollapse + state.distance,
            accuracy: 1
        )
        XCTAssertTrue(state.hasZeroPresentationMetrics)
    }

    @MainActor
    func testFastDownwardFlingHandsRemainingVelocityFromChildToContainer() throws {
        let app = launchPage(index: 2, mode: "none")
        let probe = scrollCoordinationStateProbe(in: app)
        drag(in: app, from: 0.76, to: 0.34)
        XCTAssertNotNil(waitForScrollState(from: probe, timeout: 5) {
            $0.collapse >= 0.99 && $0.distance > 10 && $0.distance < 350
        })
        probe.tap()

        fastDrag(
            in: app,
            from: CGVector(dx: 0.5, dy: 0.18),
            to: CGVector(dx: 0.5, dy: 0.86)
        )

        let state = try XCTUnwrap(waitForScrollState(from: probe, timeout: 5) {
            $0.page == "long" && $0.childToContainer
                && $0.distance < 0.5 && $0.collapse < 0.99
        }, "probe：\((probe.value as? String) ?? "nil")")
        let terminalProbeValue = (probe.value as? String) ?? "nil"
        XCTAssertGreaterThan(state.samples, 2)
        XCTAssertLessThanOrEqual(
            state.reversalMax,
            0.5,
            "probe：\(terminalProbeValue)"
        )
        XCTAssertLessThanOrEqual(
            state.invariantMax,
            0.5,
            "probe：\(terminalProbeValue)"
        )
        XCTAssertEqual(
            state.canonical,
            state.headerCollapse + state.distance,
            accuracy: 1
        )
        XCTAssertTrue(
            state.hasZeroPresentationMetrics,
            "probe：\((probe.value as? String) ?? "nil")"
        )
    }

    @MainActor
    func testShortDownwardFlingCompletesChildToContainerAfterFingerRelease() throws {
        let app = launchPage(index: 2, mode: "none")
        let probe = scrollCoordinationStateProbe(in: app)
        drag(in: app, from: 0.76, to: 0.34)
        let startOffset = CGVector(dx: 0.5, dy: 0.46)
        let endOffset = CGVector(dx: 0.5, dy: 0.54)
        let fingerTravel = app.frame.height * abs(endOffset.dy - startOffset.dy)
        let initialState = try XCTUnwrap(waitForStableScrollState(from: probe, timeout: 5) {
            $0.collapse >= 0.99
                && $0.distance > fingerTravel + 20
                && $0.distance < 350
        }, "probe：\((probe.value as? String) ?? "nil")")
        XCTAssertGreaterThan(initialState.distance, fingerTravel + 20)
        probe.tap()

        fastDrag(in: app, from: startOffset, to: endOffset)

        let state = try XCTUnwrap(waitForScrollState(from: probe, timeout: 5) {
            $0.page == "long" && $0.childToContainer
                && $0.distance < 0.5 && $0.collapse < 0.99
        }, "probe：\((probe.value as? String) ?? "nil")")
        let terminalProbeValue = (probe.value as? String) ?? "nil"
        XCTAssertGreaterThan(state.samples, 2)
        XCTAssertLessThanOrEqual(
            state.invariantMax,
            0.5,
            "probe：\(terminalProbeValue)"
        )
        XCTAssertEqual(
            state.canonical,
            state.headerCollapse + state.distance,
            accuracy: 1
        )
        XCTAssertTrue(state.hasZeroPresentationMetrics, "probe：\(terminalProbeValue)")
    }

    @MainActor
    func testPlainPageFlingNeverCreatesSyntheticChildOwner() throws {
        let app = launchPage(index: 3, mode: "none")
        let probe = scrollCoordinationStateProbe(in: app)
        probe.tap()

        fastDrag(
            in: app,
            from: CGVector(dx: 0.5, dy: 0.82),
            to: CGVector(dx: 0.5, dy: 0.16)
        )

        let state = try XCTUnwrap(waitForScrollState(from: probe, timeout: 5) {
            $0.page == "plain" && !$0.hasScrollTarget
                && $0.collapse >= 0.99 && $0.samples > 2
        })
        XCTAssertEqual(state.distance, 0, accuracy: 0.5)
        XCTAssertFalse(state.containerToChild)
        XCTAssertFalse(state.childToContainer)
        XCTAssertLessThanOrEqual(state.invariantMax, 0.5)
        XCTAssertLessThan(state.childTopMax, 0.5)
        XCTAssertLessThan(state.childBottomMax, 0.5)
    }

    @MainActor
    func testTopModesAndBottomBoundariesDoNotCrossContaminateMomentumOwner() throws {
        for mode in ["none", "container", "child"] {
            let app = launchPage(index: 2, mode: mode)
            let probe = scrollCoordinationStateProbe(in: app)
            probe.tap()
            fastDrag(
                in: app,
                from: CGVector(dx: 0.5, dy: 0.34),
                to: CGVector(dx: 0.5, dy: 0.76)
            )
            let state = try XCTUnwrap(waitForScrollState(from: probe, timeout: 5) {
                switch mode {
                case "none":
                    $0.containerTopMax < 0.5 && $0.childTopMax < 0.5
                case "container":
                    $0.containerTopMax > 1 && $0.childTopMax < 0.5
                default:
                    $0.childTopMax > 1 && $0.containerTopMax < 0.5
                }
            }, "mode=\(mode);probe=\((probe.value as? String) ?? "nil")")
            XCTAssertFalse(state.containerToChild)
            XCTAssertFalse(state.childToContainer)
            XCTAssertLessThanOrEqual(state.invariantMax, 0.5)
            app.terminate()
        }

        let realChildApp = launchPage(index: 2, mode: "container")
        let realChildProbe = scrollCoordinationStateProbe(in: realChildApp)
        let lastRow = realChildApp.staticTexts["长页 - 30"]
        for _ in 0..<6 where !lastRow.isHittable {
            drag(in: realChildApp, from: 0.76, to: 0.24)
        }
        XCTAssertTrue(lastRow.isHittable)
        realChildProbe.tap()
        fastDrag(
            in: realChildApp,
            from: CGVector(dx: 0.5, dy: 0.78),
            to: CGVector(dx: 0.5, dy: 0.20)
        )
        let childBottom = try XCTUnwrap(waitForScrollState(
            from: realChildProbe,
            timeout: 5
        ) {
            $0.childBottomMax > 1 && $0.containerBottomMax < 0.5
        })
        XCTAssertLessThan(childBottom.barMax, 0.5)
        realChildApp.terminate()

        let plainApp = launchPage(index: 3, mode: "none")
        let plainProbe = scrollCoordinationStateProbe(in: plainApp)
        drag(in: plainApp, from: 0.76, to: 0.24)
        XCTAssertNotNil(waitForScrollState(from: plainProbe) { $0.collapse >= 0.99 })
        plainProbe.tap()
        fastDrag(
            in: plainApp,
            from: CGVector(dx: 0.5, dy: 0.78),
            to: CGVector(dx: 0.5, dy: 0.20)
        )
        let plainBottom = try XCTUnwrap(waitForScrollState(
            from: plainProbe,
            timeout: 5
        ) {
            $0.containerBottomMax > 1 && $0.childBottomMax < 0.5
        })
        XCTAssertLessThan(plainBottom.barMax, 0.5)
    }

    @MainActor
    func testLeadingEdgeInteractivePopWinsOverPageboyPaging() throws {
        let app = XCUIApplication()
        app.launch()

        for pageTitle in ["无内容页", "长页"] {
            pushAnchorPagerExample(in: app)
            app.descendants(matching: .any)[pageTitle].tap()
            let trace = selectionTraceProbe(in: app)
            reset(trace: trace)

            leadingEdgeDrag(in: app, targetX: 0.16)

            XCTAssertFalse(app.tabBars.buttons["AnchorPager"].exists)
            XCTAssertEqual(selectionEventSequence(from: trace), [])

            leadingEdgeDrag(in: app, targetX: 0.88)

            XCTAssertTrue(app.tabBars.buttons["AnchorPager"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testDiagonalGestureProducesOneLegalInteractionTerminal() throws {
        let app = launchInteractionPage(initialIndex: 2)
        let trace = selectionTraceProbe(in: app)
        let probe = scrollCoordinationStateProbe(in: app)
        reset(trace: trace)
        probe.tap()

        fastDrag(
            in: app,
            from: CGVector(dx: 0.72, dy: 0.82),
            to: CGVector(dx: 0.34, dy: 0.16)
        )
        let vertical = try XCTUnwrap(waitForScrollState(from: probe, timeout: 5) {
            $0.page == "long" && ($0.collapse > 0.1 || $0.distance > 1)
        })
        XCTAssertEqual(selectionEventSequence(from: trace), [])
        XCTAssertLessThanOrEqual(vertical.invariantMax, 0.5)

        probe.tap()
        fastDrag(
            in: app,
            from: CGVector(dx: 0.86, dy: 0.64),
            to: CGVector(dx: 0.14, dy: 0.48)
        )
        XCTAssertTrue(app.staticTexts["plain-page-content"].waitForExistence(timeout: 5))
        XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [3]), [3])
        XCTAssertNotNil(waitForScrollState(from: probe, timeout: 5) {
            $0.page == "plain" && !$0.hasScrollTarget
                && $0.invariantMax <= 0.5 && $0.hasZeroPresentationMetrics
        })
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
        let app = launchPage(index: 2, mode: "container")
        let stateProbe = scrollCoordinationStateProbe(in: app)
        let oldGeneration = app.staticTexts["page-generation-1-long"]
        XCTAssertTrue(oldGeneration.waitForExistence(timeout: 3))

        let reloadButton = app.navigationBars["AnchorPager"].buttons["重新加载页面"]
        XCTAssertTrue(reloadButton.waitForExistence(timeout: 3))
        reloadButton.tap()

        XCTAssertTrue(app.staticTexts["page-generation-2-long"].waitForExistence(timeout: 3))
        XCTAssertFalse(oldGeneration.exists)
        XCTAssertTrue(app.staticTexts["长页 - 1"].exists)
        XCTAssertNotNil(waitForScrollState(from: stateProbe) {
            $0.page == "long" && $0.mode == "container" && $0.hasScrollTarget
                && $0.hasZeroPresentationMetrics
        })
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
        let selectionTrace = selectionTraceProbe(in: app)
        XCTAssertTrue(longPage.waitForExistence(timeout: 3))
        XCTAssertTrue(appearanceEvents.waitForExistence(timeout: 3))

        XCTAssertTrue(appearanceEvents.isHittable)
        appearanceEvents.tap()
        reset(trace: selectionTrace)
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
        XCTAssertEqual(selectionEventSequence(from: selectionTrace), [])
        XCTAssertTrue(longPage.exists)
        XCTAssertTrue(app.frame.intersects(longPage.frame))

        app.descendants(matching: .any)["短页"].tap()
        XCTAssertTrue(app.staticTexts["短页 - 1"].waitForExistence(timeout: 3))
        XCTAssertEqual(waitForSelectionTrace(from: selectionTrace, matching: [1]), [1])

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
    private func openSettingsSubmenu(named title: String, in app: XCUIApplication) {
        let settingsButton = app.navigationBars["AnchorPager"].buttons["示例设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()

        let submenu = app.buttons[title]
        XCTAssertTrue(submenu.waitForExistence(timeout: 3))
        submenu.tap()
    }

    @MainActor
    private func selectHeaderTopBehavior(
        named title: String,
        in app: XCUIApplication
    ) {
        openSettingsSubmenu(named: "Header 顶部行为", in: app)
        let action = app.buttons[title]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        action.tap()
    }

    @MainActor
    private func appearanceEventSequence(from element: XCUIElement) -> [String] {
        ((element.value as? String) ?? "")
            .split(separator: "|")
            .map(String.init)
    }

    @MainActor
    private func selectionEventSequence(from element: XCUIElement) -> [Int] {
        ((element.value as? String) ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
    }

    @MainActor
    private func waitForSelectionTrace(
        from probe: XCUIElement,
        matching expected: [Int]
    ) -> [Int]? {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                self.selectionEventSequence(from: probe) == expected
            },
            object: nil
        )
        guard XCTWaiter.wait(for: [expectation], timeout: 5) == .completed else {
            return nil
        }
        return selectionEventSequence(from: probe)
    }

    @MainActor
    private func reset(trace: XCUIElement) {
        XCTAssertTrue(trace.waitForExistence(timeout: 3))
        XCTAssertTrue(trace.isHittable)
        trace.tap()
    }

    @MainActor
    private func selectionTraceProbe(in app: XCUIApplication) -> XCUIElement {
        let probe = app.buttons["selection-event-trace"]
        XCTAssertTrue(probe.waitForExistence(timeout: 3))
        return probe
    }

    @MainActor
    private func appearanceEventsProbe(in app: XCUIApplication) -> XCUIElement {
        let probe = app.buttons["page-appearance-events"]
        XCTAssertTrue(probe.waitForExistence(timeout: 3))
        return probe
    }

    @MainActor
    private func rapidSelectionTrigger(in app: XCUIApplication) -> XCUIElement {
        let trigger = app.buttons["rapid-selection-trigger"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 3))
        XCTAssertTrue(trigger.isEnabled)
        return trigger
    }

    @MainActor
    private func launchInteractionPage(
        initialIndex: Int,
        rapidTargets: String? = nil,
        rapidBarTargets: String? = nil,
        sizeTransitionTargets: String? = nil,
        recordsAppearance: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--anchorPagerInitialIndex", "\(initialIndex)"]
        if let rapidTargets {
            app.launchArguments += [
                "--anchorPagerRapidSelectionTargets", rapidTargets
            ]
        }
        if let rapidBarTargets {
            app.launchArguments += [
                "--anchorPagerRapidBarSelectionTargets", rapidBarTargets
            ]
        }
        if let sizeTransitionTargets {
            app.launchArguments += [
                "--anchorPagerSizeTransitionSelectionTargets",
                sizeTransitionTargets
            ]
        }
        if recordsAppearance {
            app.launchArguments.append("--anchorPagerAppearanceRecorder")
        }
        app.launch()
        XCTAssertTrue(selectionTraceProbe(in: app).exists)
        return app
    }

    @MainActor
    private func launchLongPage() -> XCUIApplication {
        launchPage(index: 2, mode: "container")
    }

    @MainActor
    private func launchPage(index: Int, mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--anchorPagerInitialIndex", "\(index)",
            "--anchorPagerTopOverscrollMode", mode
        ]
        app.launch()
        XCTAssertTrue(scrollCoordinationStateProbe(in: app).exists)
        return app
    }

    @MainActor
    private func scrollCoordinationStateProbe(in app: XCUIApplication) -> XCUIElement {
        let probe = app.buttons["scroll-coordination-state"]
        XCTAssertTrue(probe.waitForExistence(timeout: 3))
        return probe
    }

    @MainActor
    private func compositionalScrollProbe(in app: XCUIApplication) -> XCUIElement {
        let probe = app.buttons["compositional-scroll-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 3))
        return probe
    }

    @MainActor
    private func hittableCompositionalHorizontalCards(
        in app: XCUIApplication
    ) -> [XCUIElement] {
        app.cells.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "compositional-horizontal-card-"
            )
        ).allElementsBoundByIndex.filter(\.isHittable)
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
    private func fastDrag(
        in app: XCUIApplication,
        from startOffset: CGVector,
        to endOffset: CGVector
    ) {
        let start = app.coordinate(withNormalizedOffset: startOffset)
        let end = app.coordinate(withNormalizedOffset: endOffset)
        start.press(
            forDuration: 0.05,
            thenDragTo: end,
            withVelocity: .fast,
            thenHoldForDuration: 0.02
        )
    }

    @MainActor
    private func leadingEdgeDrag(in app: XCUIApplication, targetX: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.62))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: targetX, dy: 0.62))
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: targetX > 0.5 ? .fast : .slow,
            thenHoldForDuration: 0.05
        )
    }

    @MainActor
    private func waitForScrollState(
        from probe: XCUIElement,
        timeout: TimeInterval = 3,
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
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            return nil
        }
        return ScrollCoordinationState(value: probe.value as? String)
    }

    @MainActor
    private func waitForCompositionalState(
        from probe: XCUIElement,
        timeout: TimeInterval,
        matching predicate: @escaping (CompositionalScrollState) -> Bool
    ) -> CompositionalScrollState? {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let state = CompositionalScrollState(
                    value: probe.value as? String
                ) else {
                    return false
                }
                return predicate(state)
            },
            object: nil
        )
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            return nil
        }
        return CompositionalScrollState(value: probe.value as? String)
    }

    @MainActor
    private func waitForStableScrollState(
        from probe: XCUIElement,
        timeout: TimeInterval,
        matching predicate: (ScrollCoordinationState) -> Bool
    ) -> ScrollCoordinationState? {
        let deadline = Date().addingTimeInterval(timeout)
        var previousCanonical: CGFloat?
        var stableSince: Date?

        while Date() < deadline {
            guard let state = ScrollCoordinationState(value: probe.value as? String),
                  predicate(state) else {
                previousCanonical = nil
                stableSince = nil
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                continue
            }

            if let previousCanonical,
               abs(state.canonical - previousCanonical) <= 0.25 {
                let now = Date()
                if let stableSince,
                   now.timeIntervalSince(stableSince) >= 0.3 {
                    return state
                }
                if stableSince == nil {
                    stableSince = now
                }
            } else {
                stableSince = nil
            }
            previousCanonical = state.canonical
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }

}

private struct CompositionalScrollState {
    let scrollDelegateIsStable: Bool
    let panDelegateIsStable: Bool
    let bounces: Bool
    let alwaysBounceVertical: Bool
    let isScrollEnabled: Bool
    let hasVerticalRange: Bool
    let currentHorizontalOffset: CGFloat
    let maximumHorizontalOffset: CGFloat
    let leadingHorizontalItem: Int

    var hasStableOwnership: Bool {
        scrollDelegateIsStable
            && panDelegateIsStable
            && bounces
            && alwaysBounceVertical
            && isScrollEnabled
    }

    init?(value: String?) {
        let fields = Dictionary(
            uniqueKeysWithValues: (value ?? "")
                .split(separator: ";")
                .compactMap { component -> (String, String)? in
                    let parts = component
                        .split(separator: "=", maxSplits: 1)
                        .map(String.init)
                    guard parts.count == 2 else { return nil }
                    return (parts[0], parts[1])
                }
        )
        guard let scrollDelegate = fields["scrollDelegate"],
              let panDelegate = fields["panDelegate"],
              let bounces = fields["bounces"],
              let alwaysBounceVertical = fields["alwaysBounceVertical"],
              let isScrollEnabled = fields["isScrollEnabled"],
              let verticalRange = fields["verticalRange"],
              let horizontalCurrentValue = fields["horizontalCurrent"],
              let horizontalCurrent = Double(horizontalCurrentValue),
              let horizontalMaxValue = fields["horizontalMax"],
              let horizontalMax = Double(horizontalMaxValue),
              let leadingValue = fields["leading"],
              let leading = Int(leadingValue) else {
            return nil
        }
        scrollDelegateIsStable = scrollDelegate == "1"
        panDelegateIsStable = panDelegate == "1"
        self.bounces = bounces == "1"
        self.alwaysBounceVertical = alwaysBounceVertical == "1"
        self.isScrollEnabled = isScrollEnabled == "1"
        hasVerticalRange = verticalRange == "1"
        currentHorizontalOffset = CGFloat(horizontalCurrent)
        maximumHorizontalOffset = CGFloat(horizontalMax)
        leadingHorizontalItem = leading
    }
}

private struct ScrollCoordinationState {
    let page: String
    let hasScrollTarget: Bool
    let mode: String
    let collapse: CGFloat
    let containerTopInset: CGFloat
    let headerHeight: CGFloat
    let headerHeightDeltaMax: CGFloat
    let headerCollapse: CGFloat
    let distance: CGFloat
    let containerCurrent: CGFloat
    let containerTopMax: CGFloat
    let containerBottomMax: CGFloat
    let barCurrent: CGFloat
    let barMax: CGFloat
    let childTopCurrent: CGFloat
    let childTopMax: CGFloat
    let childBottomCurrent: CGFloat
    let childBottomMax: CGFloat
    let headerContentTop: CGFloat
    let headerContentTopDeltaMax: CGFloat
    let canonical: CGFloat
    let reversalMax: CGFloat
    let invariantMax: CGFloat
    let containerToChild: Bool
    let childToContainer: Bool
    let samples: Int

    var hasZeroPresentationMetrics: Bool {
        abs(containerCurrent) < 0.5
            && containerTopMax < 0.5
            && containerBottomMax < 0.5
            && abs(barCurrent) < 0.5
            && barMax < 0.5
            && abs(childTopCurrent) < 0.5
            && childTopMax < 0.5
            && abs(childBottomCurrent) < 0.5
            && childBottomMax < 0.5
            && headerContentTopDeltaMax < 0.5
    }

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
              let containerTopInsetValue = fields["containerTopInset"],
              let containerTopInset = Double(containerTopInsetValue),
              let headerHeightValue = fields["headerHeight"],
              let headerHeight = Double(headerHeightValue),
              let headerHeightDeltaMaxValue = fields["headerHeightDeltaMax"],
              let headerHeightDeltaMax = Double(headerHeightDeltaMaxValue),
              let headerCollapseValue = fields["headerCollapse"],
              let headerCollapse = Double(headerCollapseValue),
              let distanceValue = fields["distance"],
              let distance = Double(distanceValue),
              let containerCurrentValue = fields["containerCurrent"],
              let containerCurrent = Double(containerCurrentValue),
              let containerTopMaxValue = fields["containerTopMax"],
              let containerTopMax = Double(containerTopMaxValue),
              let containerBottomMaxValue = fields["containerBottomMax"],
              let containerBottomMax = Double(containerBottomMaxValue),
              let barCurrentValue = fields["barCurrent"],
              let barCurrent = Double(barCurrentValue),
              let barMaxValue = fields["barMax"],
              let barMax = Double(barMaxValue),
              let childTopCurrentValue = fields["childTopCurrent"],
              let childTopCurrent = Double(childTopCurrentValue),
              let childTopMaxValue = fields["childTopMax"],
              let childTopMax = Double(childTopMaxValue),
              let childBottomCurrentValue = fields["childBottomCurrent"],
              let childBottomCurrent = Double(childBottomCurrentValue),
              let childBottomMaxValue = fields["childBottomMax"],
              let childBottomMax = Double(childBottomMaxValue),
              let headerContentTopValue = fields["headerContentTop"],
              let headerContentTop = Double(headerContentTopValue),
              let headerContentTopDeltaMaxValue = fields["headerContentTopDeltaMax"],
              let headerContentTopDeltaMax = Double(headerContentTopDeltaMaxValue),
              let canonicalValue = fields["canonical"],
              let canonical = Double(canonicalValue),
              let reversalMaxValue = fields["reversalMax"],
              let reversalMax = Double(reversalMaxValue),
              let invariantMaxValue = fields["invariantMax"],
              let invariantMax = Double(invariantMaxValue),
              let containerToChildValue = fields["containerToChild"],
              let childToContainerValue = fields["childToContainer"],
              let samplesValue = fields["samples"],
              let samples = Int(samplesValue) else {
            return nil
        }
        self.page = page
        self.hasScrollTarget = hasScrollTargetValue == "1"
        self.mode = mode
        self.collapse = CGFloat(collapse)
        self.containerTopInset = CGFloat(containerTopInset)
        self.headerHeight = CGFloat(headerHeight)
        self.headerHeightDeltaMax = CGFloat(headerHeightDeltaMax)
        self.headerCollapse = CGFloat(headerCollapse)
        self.distance = CGFloat(distance)
        self.containerCurrent = CGFloat(containerCurrent)
        self.containerTopMax = CGFloat(containerTopMax)
        self.containerBottomMax = CGFloat(containerBottomMax)
        self.barCurrent = CGFloat(barCurrent)
        self.barMax = CGFloat(barMax)
        self.childTopCurrent = CGFloat(childTopCurrent)
        self.childTopMax = CGFloat(childTopMax)
        self.childBottomCurrent = CGFloat(childBottomCurrent)
        self.childBottomMax = CGFloat(childBottomMax)
        self.headerContentTop = CGFloat(headerContentTop)
        self.headerContentTopDeltaMax = CGFloat(headerContentTopDeltaMax)
        self.canonical = CGFloat(canonical)
        self.reversalMax = CGFloat(reversalMax)
        self.invariantMax = CGFloat(invariantMax)
        self.containerToChild = containerToChildValue == "1"
        self.childToContainer = childToContainerValue == "1"
        self.samples = samples
    }
}
