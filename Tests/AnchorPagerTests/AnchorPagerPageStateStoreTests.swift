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
        weak let weakFirst = first
        weak let weakCurrent = current
        weak let weakLast = last
        store.beginReload(
            generation: 1,
            pageCount: 3,
            selectedIndex: 1,
            keepsAdjacentPagesLoaded: false
        )

        _ = store.pageViewController(at: 0, context: .testZero) { first }
        _ = store.pageViewController(at: 1, context: .testZero) { current }
        _ = store.pageViewController(at: 2, context: .testZero) { last }
        first = nil
        current = nil
        last = nil

        XCTAssertNil(weakFirst)
        XCTAssertNotNil(weakCurrent)
        XCTAssertNil(weakLast)
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

    func testReleasedPageIsRecreatedAndRestoresItsSavedDistance() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
        var source: PageStateScrollViewController? = PageStateScrollViewController()
        let target = PageStateScrollViewController()
        weak let weakSource = source
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
        _ = store.pageViewController(at: 0, context: context) { source }
        _ = store.pageViewController(at: 1, context: context) { target }
        source?.scrollView.contentOffset.y = -(source?.scrollView.contentInset.top ?? 0) + 120
        store.willSelect(from: 0, to: 1, context: context)
        store.didSelect(1, context: context)
        source = nil
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
