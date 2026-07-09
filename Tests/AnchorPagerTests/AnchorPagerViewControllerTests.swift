import UIKit
import XCTest
@testable import AnchorPager

final class AnchorPagerViewControllerTests: XCTestCase {
    @MainActor
    func testDefaultStateHasNoEffectiveSelection() {
        let pager = AnchorPagerViewController()

        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertNil(pager.effectiveSelectedIndex)
        XCTAssertTrue(pager.verticalScrollView === pager.verticalScrollView)
    }

    @MainActor
    func testReloadDataKeepsEmptyPageSelectionAtZero() {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 0)
        pager.dataSource = dataSource

        pager.reloadData()

        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertNil(pager.effectiveSelectedIndex)
    }

    @MainActor
    func testSetSelectedIndexCommitsValidSelectionAndNotifiesDelegate() {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 3)
        let delegate = StubDelegate()
        pager.dataSource = dataSource
        pager.delegate = delegate
        pager.reloadData()

        pager.setSelectedIndex(2, animated: false)

        XCTAssertEqual(pager.selectedIndex, 2)
        XCTAssertEqual(pager.effectiveSelectedIndex, 2)
        XCTAssertEqual(delegate.selectedIndexes, [2])
    }

    @MainActor
    func testSetSelectedIndexOutOfRangeIsNoOp() {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 2)
        pager.dataSource = dataSource
        pager.reloadData()
        pager.setSelectedIndex(1, animated: false)

        AnchorPagerAssertions.$isEnabled.withValue(false) {
            pager.setSelectedIndex(4, animated: false)
        }

        XCTAssertEqual(pager.selectedIndex, 1)
        XCTAssertEqual(pager.effectiveSelectedIndex, 1)
    }

    @MainActor
    func testReloadDataClampsSelectionWhenPageCountShrinks() {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 4)
        pager.dataSource = dataSource
        pager.reloadData()
        pager.setSelectedIndex(3, animated: false)

        dataSource.count = 2
        pager.reloadData()

        XCTAssertEqual(pager.selectedIndex, 1)
        XCTAssertEqual(pager.effectiveSelectedIndex, 1)
    }

    @MainActor
    func testReloadDataInstallsVisibleHeaderAndPagingAdapter() {
        let pager = AnchorPagerViewController()
        let headerView = UIView()
        headerView.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let first = ScrollChildViewController()
        let second = ScrollChildViewController()
        let dataSource = StubDataSource(
            count: 2,
            titles: ["First", "Second"],
            viewControllers: [first, second],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()

        pager.reloadData()

        XCTAssertTrue(headerView.isDescendant(of: pager.view))

        let adapter = pager.children.compactMap { $0 as? AnchorPagerPagingAdapter }.first
        guard let adapter else {
            XCTFail("reloadData 应安装分页 adapter。")
            return
        }
        XCTAssertTrue(adapter.parent === pager)
        XCTAssertTrue(adapter.view.isDescendant(of: pager.view))
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 2)
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === first)
        XCTAssertTrue(adapter.viewController(for: adapter, at: 1) === second)
    }

    @MainActor
    func testReloadDataWrapsChildWithoutScrollViewInFallbackHost() {
        let pager = AnchorPagerViewController()
        let plainChild = UIViewController()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [plainChild]
        )
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()

        pager.reloadData()

        guard let adapter = pager.children.compactMap({ $0 as? AnchorPagerPagingAdapter }).first else {
            XCTFail("reloadData 应安装分页 adapter。")
            return
        }

        let page = adapter.viewController(for: adapter, at: 0)
        let fallbackHost = page as? AnchorPagerPageScrollHostViewController
        XCTAssertNotNil(fallbackHost, "无 UIScrollView child 应由内部 fallback scroll host 承载。")

        fallbackHost?.loadViewIfNeeded()
        XCTAssertTrue(plainChild.parent === fallbackHost)
    }

    @MainActor
    func testReloadDataKeepsScrollViewChildUnwrapped() {
        let pager = AnchorPagerViewController()
        let scrollChild = ScrollChildViewController()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [scrollChild]
        )
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()

        pager.reloadData()

        guard let adapter = pager.children.compactMap({ $0 as? AnchorPagerPagingAdapter }).first else {
            XCTFail("reloadData 应安装分页 adapter。")
            return
        }

        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === scrollChild)
    }

    @MainActor
    func testReloadDataRemovesStaleFallbackChildAndWritesChildrenLog() {
        let pager = AnchorPagerViewController()
        let stalePlainChild = UIViewController()
        let replacementPlainChild = UIViewController()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [stalePlainChild]
        )
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()

        guard let adapter = pager.children.compactMap({ $0 as? AnchorPagerPagingAdapter }).first,
              let staleFallbackHost = adapter.viewController(
                for: adapter,
                at: 0
              ) as? AnchorPagerPageScrollHostViewController else {
            XCTFail("无 UIScrollView child 应由内部 fallback scroll host 承载。")
            return
        }
        staleFallbackHost.loadViewIfNeeded()
        XCTAssertTrue(stalePlainChild.parent === staleFallbackHost)

        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        dataSource.viewControllers = [replacementPlainChild]
        pager.reloadData()

        XCTAssertNil(stalePlainChild.parent)
        XCTAssertNil(stalePlainChild.view.superview)
        XCTAssertTrue(events.contains(.init(category: .children, level: .info, event: "reloadData.child.remove")))
    }

    @MainActor
    func testReloadDataAndSelectionWriteLifecycleAndPagingLogs() {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 2)
        pager.dataSource = dataSource
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        pager.reloadData()
        pager.setSelectedIndex(1, animated: false)

        XCTAssertTrue(events.contains(.init(category: .lifecycle, level: .info, event: "reloadData.begin")))
        XCTAssertTrue(events.contains(.init(category: .lifecycle, level: .info, event: "reloadData.end")))
        XCTAssertTrue(events.contains(.init(category: .paging, level: .info, event: "setSelectedIndex.request")))
        XCTAssertTrue(events.contains(.init(category: .paging, level: .info, event: "setSelectedIndex.commit")))
    }

    @MainActor
    func testOutOfRangeSelectionWritesPagingLog() {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 1)
        pager.dataSource = dataSource
        pager.reloadData()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        AnchorPagerAssertions.$isEnabled.withValue(false) {
            pager.setSelectedIndex(3, animated: false)
        }

        XCTAssertTrue(events.contains(.init(category: .paging, level: .debug, event: "setSelectedIndex.outOfRange")))
    }

    @MainActor
    func testConfigurationDefaultsMatchV01Baseline() {
        let configuration = AnchorPagerConfiguration.default

        XCTAssertEqual(configuration.header.heightMode, .automatic(min: 0, max: nil))
        XCTAssertEqual(configuration.header.topBehavior, .insideSafeArea)
        XCTAssertEqual(configuration.bar.height, 48)
        XCTAssertEqual(configuration.topOverscrollHandlingMode, .none)
    }
}

@MainActor
private final class StubDataSource: AnchorPagerViewControllerDataSource {
    var count: Int
    var titles: [String]
    var viewControllers: [UIViewController]
    var headerContent: AnchorPagerHeaderContent

    init(
        count: Int,
        titles: [String]? = nil,
        viewControllers: [UIViewController]? = nil,
        headerContent: AnchorPagerHeaderContent = .view(UIView())
    ) {
        self.count = count
        self.titles = titles ?? (0..<max(0, count)).map { "Page \($0)" }
        self.viewControllers = viewControllers ?? (0..<max(0, count)).map { _ in UIViewController() }
        self.headerContent = headerContent
    }

    func numberOfViewControllers(in pagerViewController: AnchorPagerViewController) -> Int {
        count
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        titleForViewControllerAt index: Int
    ) -> String {
        titles.indices.contains(index) ? titles[index] : "Page \(index)"
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        viewControllerAt index: Int
    ) -> UIViewController {
        viewControllers.indices.contains(index) ? viewControllers[index] : UIViewController()
    }

    func headerContent(in pagerViewController: AnchorPagerViewController) -> AnchorPagerHeaderContent {
        headerContent
    }
}

@MainActor
private final class StubDelegate: AnchorPagerViewControllerDelegate {
    var selectedIndexes: [Int] = []

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didSelectViewControllerAt index: Int
    ) {
        selectedIndexes.append(index)
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateHeaderCollapseProgress progress: CGFloat
    ) {}

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateLayout context: AnchorPagerLayoutContext
    ) {}
}

@MainActor
private final class ScrollChildViewController: UIViewController {
    let scrollView = UIScrollView()

    override func loadView() {
        view = UIView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        anchorPagerScrollView = scrollView
    }
}
