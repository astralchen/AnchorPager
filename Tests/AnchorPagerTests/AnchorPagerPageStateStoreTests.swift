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
