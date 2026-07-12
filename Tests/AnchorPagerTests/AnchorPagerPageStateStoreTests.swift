import UIKit
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerPageStateStoreTests: XCTestCase {
    func testRepeatedAccessReturnsSameLivePageAndCallsProviderOnce() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let child = PageStateScrollViewController()
        var providerCalls = 0
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        store.beginReload(
            generation: 1,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(content: .zero, indicators: .zero),
            containerIsCollapsed: false
        )

        let first = store.pageViewController(at: 0, context: context) {
            providerCalls += 1
            return child
        }
        let second = store.pageViewController(at: 0, context: context) {
            providerCalls += 1
            return UIViewController()
        }

        XCTAssertTrue(first === child)
        XCTAssertTrue(second === child)
        XCTAssertEqual(providerCalls, 1)
        XCTAssertTrue(events.contains(.init(
            category: .children,
            level: .info,
            event: "children.page.load"
        )))
        XCTAssertTrue(events.contains(.init(
            category: .children,
            level: .debug,
            event: "children.page.reuse"
        )))
    }

    func testScrollPageStaysUnwrappedAndReceivesManagedInsets() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let child = PageStateScrollViewController()
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(
                content: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0),
                indicators: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)
            ),
            containerIsCollapsed: false
        )

        let actual = store.pageViewController(at: 0, context: context) { child }

        XCTAssertTrue(actual === child)
        XCTAssertTrue(store.scrollView(at: 0) === child.scrollView)
        XCTAssertEqual(child.scrollView.contentInset.top, 20)
        XCTAssertEqual(child.scrollView.contentInset.bottom, 30)
    }

    func testPlainPageUsesSingleFallbackContainment() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let child = UIViewController()
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(content: .zero, indicators: .zero),
            containerIsCollapsed: false
        )

        let actual = store.pageViewController(at: 0, context: context) { child }
        actual?.loadViewIfNeeded()

        let fallbackHost = actual as? AnchorPagerPageScrollHostViewController
        XCTAssertNotNil(fallbackHost)
        XCTAssertTrue(child.parent === fallbackHost)
        XCTAssertTrue(store.scrollView(at: 0) === fallbackHost?.scrollView)
        XCTAssertEqual(fallbackHost?.children.count, 1)
    }

    func testSharedExplicitScrollTargetFallsBackForLaterPageAndWritesLog() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let sharedScrollView = UIScrollView()
        let first = PageStateExplicitScrollViewController(scrollView: sharedScrollView)
        let second = PageStateExplicitScrollViewController(scrollView: sharedScrollView)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        store.beginReload(
            generation: 1,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(content: .zero, indicators: .zero),
            containerIsCollapsed: false
        )

        let firstActual = store.pageViewController(at: 0, context: context) { first }
        let secondActual = AnchorPagerAssertions.$isEnabled.withValue(false) {
            store.pageViewController(at: 1, context: context) { second }
        }

        XCTAssertTrue(firstActual === first)
        XCTAssertTrue(secondActual is AnchorPagerPageScrollHostViewController)
        XCTAssertFalse(store.scrollView(at: 1) === sharedScrollView)
        XCTAssertTrue(events.contains(.init(
            category: .inset,
            level: .debug,
            event: "inset.targetCollision"
        )))
    }

    func testMissingPageProviderReturnsStableBlankPageAndWritesLog() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(content: .zero, indicators: .zero),
            containerIsCollapsed: false
        )

        let first = store.pageViewController(at: 0, context: context) { nil }
        let second = store.pageViewController(at: 0, context: context) {
            XCTFail("稳定空白页不应再次请求 data source。")
            return UIViewController()
        }

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
        XCTAssertNotNil(store.scrollView(at: 0))
        XCTAssertTrue(events.contains(.init(
            category: .children,
            level: .error,
            event: "children.page.dataSourceMissing"
        )))
    }

    func testDefaultRetentionKeepsOnlyCurrentPage() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        var first: PageStateScrollViewController? = PageStateScrollViewController()
        var current: PageStateScrollViewController? = PageStateScrollViewController()
        var last: PageStateScrollViewController? = PageStateScrollViewController()
        weak let weakCurrent = current
        store.beginReload(
            generation: 1,
            pageCount: 3,
            selectedIndex: 1,
            keepsAdjacentPagesLoaded: false
        )

        autoreleasepool {
            _ = store.pageViewController(at: 0, context: .testZero) { first }
            _ = store.pageViewController(at: 1, context: .testZero) { current }
            _ = store.pageViewController(at: 2, context: .testZero) { last }
        }
        first = nil
        current = nil
        last = nil

        XCTAssertFalse(store.isPageRetained(at: 0))
        XCTAssertNotNil(weakCurrent)
        XCTAssertTrue(store.isPageRetained(at: 1))
        XCTAssertFalse(store.isPageRetained(at: 2))
        XCTAssertEqual(store.retentionReasons(at: 1), [.current])
    }

    func testAdjacentRetentionOnlyKeepsAlreadyLoadedNeighborsAndCanBeDisabled() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        var first: PageStateScrollViewController? = PageStateScrollViewController()
        var current: PageStateScrollViewController? = PageStateScrollViewController()
        var last: PageStateScrollViewController? = PageStateScrollViewController()
        weak let weakFirst = first
        weak let weakCurrent = current
        weak let weakLast = last
        store.beginReload(
            generation: 1,
            pageCount: 100,
            selectedIndex: 1,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { first }
        _ = store.pageViewController(at: 1, context: .testZero) { current }
        _ = store.pageViewController(at: 2, context: .testZero) { last }

        store.setKeepsAdjacentPagesLoaded(true)
        first = nil
        current = nil
        last = nil

        XCTAssertNotNil(weakFirst)
        XCTAssertNotNil(weakCurrent)
        XCTAssertNotNil(weakLast)
        XCTAssertEqual(store.retentionReasons(at: 0), [.configuredAdjacent])
        XCTAssertEqual(store.retentionReasons(at: 2), [.configuredAdjacent])

        store.setKeepsAdjacentPagesLoaded(false)

        XCTAssertNotNil(weakCurrent)
        XCTAssertEqual(store.retentionReasons(at: 0), [])
        XCTAssertEqual(store.retentionReasons(at: 1), [.current])
        XCTAssertEqual(store.retentionReasons(at: 2), [])
    }

    func testTransitionPinsSourceAndTargetThenCommitsTarget() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let source = PageStateScrollViewController()
        let target = PageStateScrollViewController()
        store.beginReload(
            generation: 1,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { source }
        _ = store.pageViewController(at: 1, context: .testZero) { target }

        store.willSelect(from: 0, to: 1, context: .testZero)

        XCTAssertEqual(store.retentionReasons(at: 0), [.current, .transitionSource])
        XCTAssertEqual(store.retentionReasons(at: 1), [.transitionTarget])

        store.didSelect(1, context: .testZero)

        XCTAssertEqual(store.retentionReasons(at: 0), [])
        XCTAssertEqual(store.retentionReasons(at: 1), [.current])
    }

    func testCancelledTransitionRestoresSourceWindow() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let source = PageStateScrollViewController()
        let target = PageStateScrollViewController()
        store.beginReload(
            generation: 1,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { source }
        _ = store.pageViewController(at: 1, context: .testZero) { target }
        store.willSelect(from: 0, to: 1, context: .testZero)

        store.didCancelSelection(
            at: 1,
            returningTo: 0,
            context: .testZero
        )

        XCTAssertEqual(store.retentionReasons(at: 0), [.current])
        XCTAssertEqual(store.retentionReasons(at: 1), [])
    }

    func testCollapsedContainerRestoresSavedChildDistanceWhenSelectingPageAgain() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let source = PageStateScrollViewController()
        let target = PageStateScrollViewController()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        let expandedContext = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(
                content: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0),
                indicators: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)
            ),
            containerIsCollapsed: false
        )
        var collapsedContext = expandedContext
        collapsedContext.containerIsCollapsed = true
        store.beginReload(
            generation: 1,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: expandedContext) { source }
        _ = store.pageViewController(at: 1, context: expandedContext) { target }
        source.scrollView.contentOffset.y = -source.scrollView.contentInset.top + 120
        store.willSelect(from: 0, to: 1, context: collapsedContext)
        store.didSelect(1, context: collapsedContext)
        source.scrollView.contentOffset.y = -source.scrollView.contentInset.top

        store.willSelect(from: 1, to: 0, context: collapsedContext)

        XCTAssertEqual(store.childDistanceFromTop(at: 0), 120, accuracy: 0.5)
        XCTAssertEqual(
            source.scrollView.contentOffset.y + source.scrollView.contentInset.top,
            120,
            accuracy: 0.5
        )
        XCTAssertTrue(events.contains(.init(
            category: .children,
            level: .debug,
            event: "children.page.snapshot.save"
        )))
        XCTAssertTrue(events.contains(.init(
            category: .children,
            level: .debug,
            event: "children.page.snapshot.restore"
        )))
    }

    func testExpandedContainerResetsSavedChildDistanceWhenSelectingPageAgain() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let source = PageStateScrollViewController()
        let target = PageStateScrollViewController()
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(
                content: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0),
                indicators: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)
            ),
            containerIsCollapsed: false
        )
        store.beginReload(
            generation: 1,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: context) { source }
        _ = store.pageViewController(at: 1, context: context) { target }
        source.scrollView.contentOffset.y = -source.scrollView.contentInset.top + 120
        store.willSelect(from: 0, to: 1, context: context)
        store.didSelect(1, context: context)

        store.willSelect(from: 1, to: 0, context: context)

        XCTAssertEqual(store.childDistanceFromTop(at: 0), 0, accuracy: 0.5)
        XCTAssertEqual(
            source.scrollView.contentOffset.y,
            -source.scrollView.contentInset.top,
            accuracy: 0.5
        )
    }

    func testManagedInsetUpdatesOnlyVisitActiveRetentionWindow() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let pages = (0..<10).map { _ in PageStateScrollViewController() }
        store.beginReload(
            generation: 1,
            pageCount: 1_000,
            selectedIndex: 5,
            keepsAdjacentPagesLoaded: true
        )
        for (index, page) in pages.enumerated() {
            _ = store.pageViewController(at: index, context: .testZero) { page }
        }

        store.updateManagedInsets(
            .init(
                content: UIEdgeInsets(top: 12, left: 0, bottom: 34, right: 0),
                indicators: UIEdgeInsets(top: 12, left: 0, bottom: 34, right: 0)
            ),
            logsChanges: false
        )

        XCTAssertEqual(store.lastManagedUpdateCount, 3)
        XCTAssertEqual(pages[4].scrollView.contentInset.top, 12)
        XCTAssertEqual(pages[5].scrollView.contentInset.top, 12)
        XCTAssertEqual(pages[6].scrollView.contentInset.top, 12)
        XCTAssertEqual(pages[3].scrollView.contentInset.top, 0)
    }

    func testManagedInsetHotPathDoesNotWritePageLifecycleLogs() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let page = PageStateScrollViewController()
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { page }
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        for bottom in 0..<100 {
            store.updateManagedInsets(
                .init(
                    content: UIEdgeInsets(top: 10, left: 0, bottom: CGFloat(bottom), right: 0),
                    indicators: UIEdgeInsets(top: 10, left: 0, bottom: CGFloat(bottom), right: 0)
                ),
                logsChanges: false
            )
        }

        XCTAssertTrue(events.filter { $0.category == .children }.isEmpty)
    }

    func testReleasedPageIsRecreatedAndRestoresItsSavedDistance() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let target = PageStateScrollViewController()
        weak var weakSource: PageStateScrollViewController?
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(
                content: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0),
                indicators: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)
            ),
            containerIsCollapsed: true
        )
        autoreleasepool {
            let source = PageStateScrollViewController()
            weakSource = source
            store.beginReload(
                generation: 1,
                pageCount: 2,
                selectedIndex: 0,
                keepsAdjacentPagesLoaded: false
            )
            _ = store.pageViewController(at: 0, context: context) { source }
            _ = store.pageViewController(at: 1, context: context) { target }
            source.scrollView.contentOffset.y = -source.scrollView.contentInset.top + 120
            store.willSelect(from: 0, to: 1, context: context)
            store.didSelect(1, context: context)
        }
        XCTAssertNil(weakSource)
        let recreated = PageStateScrollViewController()
        var providerCalls = 0

        let actual = store.pageViewController(at: 0, context: context) {
            providerCalls += 1
            return recreated
        }
        store.willSelect(from: 1, to: 0, context: context)

        XCTAssertTrue(actual === recreated)
        XCTAssertEqual(providerCalls, 1)
        XCTAssertEqual(
            recreated.scrollView.contentOffset.y + recreated.scrollView.contentInset.top,
            120,
            accuracy: 0.5
        )
        for event in [
            "children.page.retain",
            "children.page.release",
            "children.page.snapshot.save",
            "children.page.snapshot.restore",
            "children.page.recreate"
        ] {
            XCTAssertTrue(events.contains(where: { $0.event == event }), "缺少日志：\(event)")
        }
    }

    func testCommittedGenerationStaysRetainedUntilPendingReloadCommits() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        weak var weakOldPage: PageStateScrollViewController?
        autoreleasepool {
            var oldPage: PageStateScrollViewController? = PageStateScrollViewController()
            weakOldPage = oldPage
            store.beginReload(
                generation: 1,
                pageCount: 1,
                selectedIndex: 0,
                keepsAdjacentPagesLoaded: false
            )
            var returnedOldPage = store.pageViewController(at: 0, context: .testZero) { oldPage }
            XCTAssertTrue(returnedOldPage === oldPage)
            store.commitReload(generation: 1)

            store.beginReload(
                generation: 2,
                pageCount: 1,
                selectedIndex: 0,
                keepsAdjacentPagesLoaded: false
            )
            let newPage = PageStateScrollViewController()
            _ = store.pageViewController(at: 0, context: .testZero) { newPage }
            oldPage = nil
            returnedOldPage = nil

            XCTAssertEqual(store.committedGenerationIdentifier, 1)
            XCTAssertEqual(store.pendingGenerationIdentifier, 2)
            XCTAssertNotNil(weakOldPage)

            store.commitReload(generation: 2)

            XCTAssertEqual(store.committedGenerationIdentifier, 2)
            XCTAssertNil(store.pendingGenerationIdentifier)
        }
        XCTAssertNil(weakOldPage)
    }

    func testPendingProviderGenerationDoesNotReplaceCommittedVisibleCurrentBeforeCommit() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let committedPage = PageStateScrollViewController()
        let pendingPage = PageStateScrollViewController()
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(
                content: UIEdgeInsets(top: 18, left: 0, bottom: 12, right: 0),
                indicators: UIEdgeInsets(top: 18, left: 0, bottom: 12, right: 0)
            ),
            containerIsCollapsed: false
        )
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: context) { committedPage }
        store.commitReload(generation: 1)

        store.beginReload(
            generation: 2,
            pageCount: 2,
            selectedIndex: 1,
            keepsAdjacentPagesLoaded: false
        )
        let providedPage = store.pageViewController(at: 1, context: context) { pendingPage }

        XCTAssertTrue(providedPage === pendingPage)
        XCTAssertTrue(store.livePageViewController(at: 0) === committedPage)
        XCTAssertNil(store.livePageViewController(at: 1))
        XCTAssertTrue(store.scrollView(at: 0) === committedPage.scrollView)
        XCTAssertEqual(store.retentionReasons(at: 0), [.current])
        XCTAssertEqual(committedPage.scrollView.contentInset.top, 18)
        XCTAssertEqual(committedPage.scrollView.contentInsetAdjustmentBehavior, .never)
    }

    func testCommittedCurrentAccessorsIgnorePendingGeneration() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let committedPage = PageStateScrollViewController()
        let pendingPage = PageStateScrollViewController()
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { committedPage }
        store.commitReload(generation: 1)

        store.beginReload(
            generation: 2,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { pendingPage }

        XCTAssertEqual(store.committedCurrentIndex, 0)
        XCTAssertTrue(store.committedCurrentPageViewController === committedPage)
        XCTAssertTrue(store.committedCurrentScrollView === committedPage.scrollView)

        store.beginReload(
            generation: 3,
            pageCount: 0,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        store.commitReload(generation: 3)

        XCTAssertNil(store.committedCurrentIndex)
        XCTAssertNil(store.committedCurrentPageViewController)
        XCTAssertNil(store.committedCurrentScrollView)
    }

    func testPendingCancelLeavesCommittedManagedInsetAndRetentionUnchanged() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let committedPage = PageStateScrollViewController()
        committedPage.loadViewIfNeeded()
        committedPage.scrollView.contentInset = UIEdgeInsets(top: 7, left: 0, bottom: 9, right: 0)
        committedPage.scrollView.contentInsetAdjustmentBehavior = .always
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(
                content: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0),
                indicators: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)
            ),
            containerIsCollapsed: false
        )
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: context) { committedPage }
        store.commitReload(generation: 1)

        store.beginReload(
            generation: 2,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: context) {
            PageStateScrollViewController()
        }
        _ = store.pageViewController(at: 1, context: context) { committedPage }
        store.beginReload(
            generation: 3,
            pageCount: 0,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )

        XCTAssertTrue(store.committedCurrentPageViewController === committedPage)
        XCTAssertEqual(store.retentionReasons(at: 0), [.current])
        XCTAssertTrue(store.isPageRetained(at: 0))
        XCTAssertEqual(committedPage.scrollView.contentInset.top, 27)
        XCTAssertEqual(committedPage.scrollView.contentInset.bottom, 39)
        XCTAssertEqual(committedPage.scrollView.contentInsetAdjustmentBehavior, .never)
    }

    func testMovedScrollPageMigrationDoesNotMutateCommittedLeaseBeforeTerminal() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let movedPage = PageStateScrollViewController()
        let oldNeighbor = PageStateScrollViewController()
        let newCurrent = PageStateScrollViewController()
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(
                content: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0),
                indicators: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)
            ),
            containerIsCollapsed: true
        )
        store.beginReload(
            generation: 1,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: context) { movedPage }
        _ = store.pageViewController(at: 1, context: context) { oldNeighbor }
        movedPage.scrollView.contentOffset.y = -movedPage.scrollView.contentInset.top + 90
        store.willSelect(from: 0, to: 1, context: context)
        store.didSelect(1, context: context)
        store.willSelect(from: 1, to: 0, context: context)
        store.didSelect(0, context: context)
        store.commitReload(generation: 1)
        let committedStateIdentifier = store.pageStateIdentifier(at: 0)

        store.beginReload(
            generation: 2,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: context) { newCurrent }
        let pendingActual = store.pageViewController(at: 1, context: context) { movedPage }

        XCTAssertTrue(pendingActual === movedPage)
        XCTAssertEqual(store.pageStateIdentifier(at: 0), committedStateIdentifier)
        XCTAssertEqual(store.retentionReasons(at: 0), [.current])
        XCTAssertTrue(store.isPageRetained(at: 0))
        XCTAssertEqual(store.childDistanceFromTop(at: 0), 90, accuracy: 0.5)
        XCTAssertEqual(movedPage.scrollView.contentInset.top, 20)
        XCTAssertEqual(movedPage.scrollView.contentInsetAdjustmentBehavior, .never)

        store.commitReload(generation: 2)

        XCTAssertTrue(store.livePageViewController(at: 1) === movedPage)
        XCTAssertNotEqual(store.pageStateIdentifier(at: 1), committedStateIdentifier)
        XCTAssertEqual(store.childDistanceFromTop(at: 1), 0, accuracy: 0.5)
    }

    func testMovedFallbackMigrationDoesNotRemoveCommittedContentBeforeTerminal() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let movedChild = UIViewController()
        let newCurrent = PageStateScrollViewController()
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(
                content: UIEdgeInsets(top: 16, left: 0, bottom: 24, right: 0),
                indicators: UIEdgeInsets(top: 16, left: 0, bottom: 24, right: 0)
            ),
            containerIsCollapsed: false
        )
        store.beginReload(
            generation: 1,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let committedActual = store.pageViewController(at: 0, context: context) { movedChild }
        store.commitReload(generation: 1)
        let committedStateIdentifier = store.pageStateIdentifier(at: 0)
        let committedHost = committedActual as? AnchorPagerPageScrollHostViewController

        store.beginReload(
            generation: 2,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: context) { newCurrent }
        let pendingActual = store.pageViewController(at: 1, context: context) { movedChild }

        XCTAssertTrue(pendingActual === committedHost)
        XCTAssertTrue(store.livePageViewController(at: 0) === committedHost)
        XCTAssertEqual(store.pageStateIdentifier(at: 0), committedStateIdentifier)
        XCTAssertTrue(movedChild.parent === committedHost)
        XCTAssertTrue(movedChild.view.superview === committedHost?.view)
        XCTAssertEqual(committedHost?.children.count, 1)
        XCTAssertEqual(committedHost?.scrollView.contentInset.top, 16)
        XCTAssertEqual(committedHost?.scrollView.contentInsetAdjustmentBehavior, .never)

        store.commitReload(generation: 2)

        XCTAssertTrue(store.livePageViewController(at: 1) === committedHost)
        XCTAssertNotEqual(store.pageStateIdentifier(at: 1), committedStateIdentifier)
        XCTAssertTrue(movedChild.parent === committedHost)
    }

    func testSameIndexMigrationSharesLiveIdentityButNotGenerationState() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let child = PageStateScrollViewController()
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let committedActual = store.pageViewController(at: 0, context: .testZero) { child }
        store.commitReload(generation: 1)
        let committedStateIdentifier = store.pageStateIdentifier(at: 0)

        store.beginReload(
            generation: 2,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let pendingActual = store.pageViewController(at: 0, context: .testZero) { child }

        XCTAssertTrue(pendingActual === committedActual)
        XCTAssertEqual(store.pageStateIdentifier(at: 0), committedStateIdentifier)

        store.commitReload(generation: 2)

        XCTAssertTrue(store.livePageViewController(at: 0) === committedActual)
        XCTAssertNotEqual(store.pageStateIdentifier(at: 0), committedStateIdentifier)
    }

    func testReloadCommitRemovesOldFallbackContainment() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let oldPage = UIViewController()
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { oldPage }
        store.commitReload(generation: 1)
        XCTAssertNotNil(oldPage.parent)

        store.beginReload(
            generation: 2,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { UIViewController() }
        XCTAssertNotNil(oldPage.parent)

        store.commitReload(generation: 2)

        XCTAssertNil(oldPage.parent)
        XCTAssertNil(oldPage.view.superview)
    }

    func testSameControllerAtSameIndexMigratesPageStateAndFallbackHost() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let child = UIViewController()
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let firstActual = store.pageViewController(at: 0, context: .testZero) { child }
        let firstStateIdentifier = store.pageStateIdentifier(at: 0)
        store.commitReload(generation: 1)

        store.beginReload(
            generation: 2,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let secondActual = store.pageViewController(at: 0, context: .testZero) { child }

        XCTAssertTrue(firstActual === secondActual)
        store.commitReload(generation: 2)

        XCTAssertNotEqual(store.pageStateIdentifier(at: 0), firstStateIdentifier)
        XCTAssertTrue(child.parent === secondActual)
        XCTAssertEqual(secondActual?.children.count, 1)
    }

    func testSameIndexMigrationCapturesCurrentScrollDistance() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let child = PageStateScrollViewController()
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { child }
        child.scrollView.contentOffset.y = 88
        store.commitReload(generation: 1)

        store.beginReload(
            generation: 2,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { child }

        XCTAssertEqual(store.childDistanceFromTop(at: 0), 0, accuracy: 0.5)

        store.commitReload(generation: 2)

        XCTAssertEqual(store.childDistanceFromTop(at: 0), 88, accuracy: 0.5)
    }

    func testControllerMovedToNewIndexMigratesStateAndResetsSnapshot() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let child = PageStateScrollViewController()
        store.beginReload(
            generation: 1,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: .testZero) { child }
        let originalStateIdentifier = store.pageStateIdentifier(at: 0)
        store.commitReload(generation: 1)

        store.beginReload(
            generation: 2,
            pageCount: 2,
            selectedIndex: 1,
            keepsAdjacentPagesLoaded: false
        )
        let actual = store.pageViewController(at: 1, context: .testZero) { child }

        XCTAssertTrue(actual === child)
        XCTAssertEqual(store.pageStateIdentifier(at: 0), originalStateIdentifier)

        store.commitReload(generation: 2)

        XCTAssertNotEqual(store.pageStateIdentifier(at: 1), originalStateIdentifier)
        XCTAssertEqual(store.childDistanceFromTop(at: 1), 0)
    }

    func testDuplicateControllerInOneGenerationUsesBlankFallbackAndWritesLog() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let duplicate = PageStateScrollViewController()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        store.beginReload(
            generation: 1,
            pageCount: 2,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )

        let first = store.pageViewController(at: 0, context: .testZero) { duplicate }
        let second = AnchorPagerAssertions.$isEnabled.withValue(false) {
            store.pageViewController(at: 1, context: .testZero) { duplicate }
        }

        XCTAssertTrue(first === duplicate)
        XCTAssertTrue(second is AnchorPagerPageScrollHostViewController)
        XCTAssertFalse(second?.children.contains(where: { $0 === duplicate }) ?? true)
        XCTAssertTrue(events.contains(.init(
            category: .children,
            level: .debug,
            event: "children.page.duplicateController"
        )))
    }

    func testProviderReentryDoesNotCommitStaleGenerationResult() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let stalePage = PageStateScrollViewController()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        store.beginReload(
            generation: 2,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )

        let actual = store.pageViewController(at: 0, context: .testZero) {
            store.beginReload(
                generation: 3,
                pageCount: 1,
                selectedIndex: 0,
                keepsAdjacentPagesLoaded: false
            )
            return stalePage
        }

        XCTAssertNil(actual)
        XCTAssertFalse(stalePage.isViewLoaded)
        XCTAssertEqual(store.pendingGenerationIdentifier, 3)
        XCTAssertNil(store.pageStateIdentifier(at: 0))
        XCTAssertTrue(events.contains(.init(
            category: .children,
            level: .debug,
            event: "children.page.generation.cancel"
        )))
    }

    func testSupersededPendingGenerationReleasesInsetOwnership() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        let page = PageStateScrollViewController()
        page.loadViewIfNeeded()
        page.scrollView.contentInset = UIEdgeInsets(top: 7, left: 0, bottom: 9, right: 0)
        page.scrollView.contentInsetAdjustmentBehavior = .always
        let context = AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: .init(
                content: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0),
                indicators: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)
            ),
            containerIsCollapsed: false
        )
        store.beginReload(
            generation: 1,
            pageCount: 1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        _ = store.pageViewController(at: 0, context: context) { page }
        XCTAssertEqual(page.scrollView.contentInset.top, 27)

        store.beginReload(
            generation: 2,
            pageCount: 0,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )

        XCTAssertEqual(page.scrollView.contentInset.top, 7)
        XCTAssertEqual(page.scrollView.contentInset.bottom, 9)
        XCTAssertEqual(page.scrollView.contentInsetAdjustmentBehavior, .always)
    }

    func testStaleCommitDoesNotChangePendingGenerationAndWritesCancelLog() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        store.beginReload(
            generation: 2,
            pageCount: 0,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )

        store.commitReload(generation: 1)

        XCTAssertEqual(store.pendingGenerationIdentifier, 2)
        XCTAssertNil(store.committedGenerationIdentifier)
        XCTAssertTrue(events.contains(.init(
            category: .children,
            level: .debug,
            event: "children.page.generation.cancel"
        )))
    }

    func testNegativePageCountBecomesEmptyGenerationAndWritesLog() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        var providerCalls = 0
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        store.beginReload(
            generation: 1,
            pageCount: -1,
            selectedIndex: 0,
            keepsAdjacentPagesLoaded: false
        )
        let page = store.pageViewController(at: 0, context: .testZero) {
            providerCalls += 1
            return UIViewController()
        }

        XCTAssertNil(page)
        XCTAssertEqual(providerCalls, 0)
        XCTAssertTrue(events.contains(.init(
            category: .children,
            level: .error,
            event: "children.page.invalidCount"
        )))
    }
}

private extension AnchorPagerPageStateStore.AccessContext {
    static var testZero: Self {
        .init(managedInsetTarget: .zero, containerIsCollapsed: false)
    }
}

@MainActor
private final class PageStateScrollViewController: UIViewController {
    let scrollView = UIScrollView()

    override func loadView() {
        let rootView = UIView()
        rootView.addSubview(scrollView)
        view = rootView
        anchorPagerScrollView = scrollView
    }
}

@MainActor
private final class PageStateExplicitScrollViewController: UIViewController {
    init(scrollView: UIScrollView) {
        super.init(nibName: nil, bundle: nil)
        anchorPagerScrollView = scrollView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 尚未实现")
    }

    override func loadView() {
        view = UIView()
    }
}
