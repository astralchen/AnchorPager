import Foundation
import Pageboy
import Tabman
import UIKit
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerPagingAdapterTests: XCTestCase {
    private var retainedPageProvider: RecordingPageProvider?

    @MainActor
    func testAdapterDisablesTabmanAutomaticChildInsetsBeforeViewDidLoad() {
        let adapter = AnchorPagerPagingAdapter()

        XCTAssertFalse(adapter.automaticallyAdjustsChildInsets)
    }

    @MainActor
    func testExplicitBarHeightConstrainsActualTabmanBarAndReportsInsets() {
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        adapter.setBarHeight(64)
        reload(
            adapter,
            titles: ["First"],
            viewControllers: [UIViewController()],
            selectedIndex: 0
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = adapter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        window.layoutIfNeeded()
        adapter.view.setNeedsLayout()
        adapter.view.layoutIfNeeded()

        XCTAssertEqual(adapter.barInsets.top, 64, accuracy: 0.5)
        XCTAssertTrue(delegate.barInsets.contains { abs($0.top - 64) < 0.5 })
        XCTAssertTrue(events.contains(
            .init(category: .paging, level: .debug, event: "paging.barInsetsChanged")
        ))
    }

    @MainActor
    func testReloadSettlesBarInsetsBeforeForwardingTerminal() {
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        adapter.setBarHeight(44)
        reload(
            adapter,
            titles: ["First"],
            viewControllers: [UIViewController()],
            selectedIndex: 0
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = adapter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        adapter.view.layoutIfNeeded()
        delegate.callbackOrder.removeAll()

        adapter.setBarHeight(64)
        adapter.reload(
            requestIdentifier: 42,
            titles: ["Replacement"],
            pageCount: 1,
            selectedIndex: 0
        )

        XCTAssertEqual(delegate.callbackOrder.count, 2)
        if case let .barInsets(insets) = delegate.callbackOrder[0] {
            XCTAssertEqual(insets.top, 64, accuracy: 0.5)
        } else {
            XCTFail("reload terminal 前应先完成 bar inset settlement。")
        }
        if case let .didReload(index, insets) = delegate.callbackOrder[1] {
            XCTAssertEqual(index, 0)
            XCTAssertEqual(insets.top, 64, accuracy: 0.5)
        } else {
            XCTFail("reload terminal 应携带直接采样的 bar inset。")
        }

        delegate.callbackOrder.removeAll()
        adapter.reload(
            requestIdentifier: 43,
            titles: ["Latest"],
            pageCount: 1,
            selectedIndex: 0
        )

        XCTAssertEqual(delegate.callbackOrder.count, 1)
        if case let .didReload(index, insets) = delegate.callbackOrder[0] {
            XCTAssertEqual(index, 0)
            XCTAssertEqual(insets.top, 64, accuracy: 0.5)
        } else {
            XCTFail("相同几何没有普通回调时，terminal 仍应显式携带 bar inset。")
        }
    }

    @MainActor
    func testNilBarHeightUsesAdaptiveTabmanHeight() {
        let adapter = AnchorPagerPagingAdapter()
        adapter.setBarHeight(nil)
        reload(
            adapter,
            titles: ["First"],
            viewControllers: [UIViewController()],
            selectedIndex: 0
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = adapter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        window.layoutIfNeeded()
        adapter.view.layoutIfNeeded()

        XCTAssertGreaterThan(adapter.barInsets.top, 0)
    }

    @MainActor
    func testInvalidBarHeightFallsBackToZeroAndWritesPagingLog() {
        let adapter = AnchorPagerPagingAdapter()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        AnchorPagerAssertions.$isEnabled.withValue(false) {
            adapter.setBarHeight(.nan)
        }

        XCTAssertTrue(events.contains(
            .init(category: .paging, level: .debug, event: "paging.barHeightInvalid")
        ))
    }

    @MainActor
    func testPagePresentationMovesPageboySurfaceWithoutMovingBarAndCanReset() throws {
        let page = UIViewController()
        let adapter = AnchorPagerPagingAdapter()
        adapter.setBarHeight(44)
        reload(
            adapter,
            titles: ["Plain"],
            viewControllers: [page],
            selectedIndex: 0
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = adapter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        let pageViewController = try XCTUnwrap(
            adapter.children.compactMap { $0 as? UIPageViewController }.first
        )
        let barView = try XCTUnwrap(adapter.bars.first)
        let barFrame = barView.frame
        let barTransform = barView.transform

        XCTAssertTrue(adapter.setPagePresentationTranslationY(-24))
        XCTAssertEqual(pageViewController.view.transform.ty, -24, accuracy: 0.001)
        XCTAssertEqual(barView.frame, barFrame)
        XCTAssertEqual(barView.transform, barTransform)

        XCTAssertTrue(adapter.setPagePresentationTranslationY(0))
        XCTAssertEqual(pageViewController.view.transform, .identity)
    }

    @MainActor
    func testAdapterSuppliesTitlesAndViewControllersToTabmanAndPageboy() {
        let adapter = AnchorPagerPagingAdapter()
        let first = UIViewController()
        let second = UIViewController()

        reload(
            adapter,
            titles: ["First", "Second"],
            viewControllers: [first, second],
            selectedIndex: 1
        )

        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 2)
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === first)
        XCTAssertTrue(adapter.viewController(for: adapter, at: 1) === second)
        XCTAssertNil(adapter.viewController(for: adapter, at: 2))

        if case let .at(index)? = adapter.defaultPage(for: adapter) {
            XCTAssertEqual(index, 1)
        } else {
            XCTFail("默认页面应指向传入的 selectedIndex。")
        }

        let item = adapter.barItem(for: TMBarView.ButtonBar(), at: 0)
        XCTAssertEqual(item.title, "First")
    }

    @MainActor
    func testAdapterRequestsPagesByIndexWithoutOwningControllerArray() {
        let adapter = AnchorPagerPagingAdapter()
        let first = UIViewController()
        let provider = RecordingPageProvider(pages: [0: first])
        adapter.pageProvider = provider

        adapter.reload(
            requestIdentifier: 1,
            titles: ["First", "Second"],
            pageCount: 2,
            selectedIndex: 1
        )

        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 2)
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === first)
        XCTAssertNil(adapter.viewController(for: adapter, at: 1))
        XCTAssertEqual(Array(provider.requestedIndexes.suffix(2)), [0, 1])
    }

    @MainActor
    func testAdapterForwardsSelectionEventsAndIgnoresUnidentifiedReloadCallback() {
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        reload(
            adapter,
            titles: ["First", "Second"],
            viewControllers: [UIViewController(), UIViewController()],
            selectedIndex: 0
        )

        adapter.pageboyViewController(adapter, willScrollToPageAt: 1, direction: .forward, animated: true)
        adapter.pageboyViewController(adapter, didScrollToPageAt: 1, direction: .forward, animated: true)
        adapter.pageboyViewController(adapter, didCancelScrollToPageAt: 1, returnToPageAt: 0)
        let current = adapter.viewController(for: adapter, at: 0)!
        adapter.pageboyViewController(adapter, didReloadWith: current, currentPageIndex: 0)

        XCTAssertEqual(
            delegate.events,
            [.willSelect(1, true), .didSelect(1, true), .didCancel(1, 0)]
        )
    }

    @MainActor
    func testSetSelectedIndexReturnsRequestStatusAndWaitsForTerminalCallback() {
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        adapter.loadViewIfNeeded()
        reload(
            adapter,
            titles: ["First", "Second"],
            viewControllers: [UIViewController(), UIViewController()],
            selectedIndex: 0
        )
        let didAcceptRequest = adapter.setSelectedIndex(1, animated: true)

        XCTAssertTrue(didAcceptRequest)
        XCTAssertFalse(delegate.events.contains(.didSelect(1, true)))
        adapter.pageboyViewController(adapter, didScrollToPageAt: 1, direction: .forward, animated: true)

        XCTAssertTrue(delegate.events.contains(.didSelect(1, true)))
    }

    @MainActor
    func testSetSelectedIndexOutOfRangeReturnsFalseAndWritesLog() {
        let adapter = AnchorPagerPagingAdapter()
        reload(
            adapter,
            titles: ["First"],
            viewControllers: [UIViewController()],
            selectedIndex: 0
        )
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        let didAcceptRequest = adapter.setSelectedIndex(4, animated: false)

        XCTAssertFalse(didAcceptRequest)
        XCTAssertTrue(events.contains(.init(category: .paging, level: .debug, event: "paging.setSelectedIndex.outOfRange")))
    }

    @MainActor
    func testRejectedSecondSelectionKeepsFirstPendingSelection() {
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        adapter.loadViewIfNeeded()
        reload(
            adapter,
            titles: ["First", "Second", "Third"],
            viewControllers: [UIViewController(), UIViewController(), UIViewController()],
            selectedIndex: 0
        )
        let didAcceptFirstRequest = adapter.setSelectedIndex(1, animated: true)
        let didAcceptSecondRequest = adapter.setSelectedIndex(2, animated: true)

        XCTAssertTrue(didAcceptFirstRequest)
        XCTAssertFalse(didAcceptSecondRequest)
        adapter.pageboyViewController(adapter, didScrollToPageAt: 1, direction: .forward, animated: true)

        XCTAssertTrue(delegate.events.contains(.didSelect(1, true)))
        XCTAssertFalse(delegate.events.contains(.didSelect(2, true)))
    }

    @MainActor
    func testAdapterLogsMissingDuplicateAndOutOfOrderPageboyCallbacks() {
        let adapter = AnchorPagerPagingAdapter()
        reload(
            adapter,
            titles: ["First", "Second"],
            viewControllers: [UIViewController(), UIViewController()],
            selectedIndex: 0
        )
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        adapter.pageboyViewController(adapter, didScrollToPageAt: 1, direction: .forward, animated: true)
        adapter.pageboyViewController(adapter, willScrollToPageAt: 1, direction: .forward, animated: true)
        adapter.pageboyViewController(adapter, willScrollToPageAt: 1, direction: .forward, animated: true)
        adapter.pageboyViewController(adapter, didCancelScrollToPageAt: 0, returnToPageAt: 1)

        XCTAssertTrue(events.contains(.init(category: .paging, level: .debug, event: "paging.callback.missingWillSelect")))
        XCTAssertTrue(events.contains(.init(category: .paging, level: .debug, event: "paging.callback.duplicateWillSelect")))
        XCTAssertTrue(events.contains(.init(category: .paging, level: .debug, event: "paging.callback.outOfOrder")))
    }

    @MainActor
    func testPrepareForRemovalSynchronouslyClearsScrollPageWithoutPagingEvents() {
        let page = ScrollPageViewController()
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        reload(adapter, titles: ["Page"], viewControllers: [page], selectedIndex: 0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = adapter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        XCTAssertNotNil(page.parent)
        XCTAssertNotNil(page.view.superview)
        delegate.events.removeAll()

        let didCompleteSynchronously = adapter.prepareForRemoval()

        XCTAssertTrue(didCompleteSynchronously)
        XCTAssertNil(page.parent)
        XCTAssertNil(page.view.superview)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 0)
        XCTAssertNil(adapter.defaultPage(for: adapter))
        XCTAssertEqual(delegate.events, [])
    }

    @MainActor
    func testPrepareForRemovalSynchronouslyClearsPlainPageWithoutPagingEvents() {
        let plainPage = UIViewController()
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        reload(
            adapter,
            titles: ["Plain"],
            viewControllers: [plainPage],
            selectedIndex: 0
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = adapter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        XCTAssertNotNil(plainPage.parent)
        XCTAssertNotNil(plainPage.view.superview)
        delegate.events.removeAll()

        let didCompleteSynchronously = adapter.prepareForRemoval()

        XCTAssertTrue(didCompleteSynchronously)
        XCTAssertNil(plainPage.parent)
        XCTAssertNil(plainPage.view.superview)
        XCTAssertEqual(delegate.events, [])
    }

    @MainActor
    func testPrepareForRemovalResetsPagePresentationBeforeContainmentTeardown() throws {
        let plainPage = UIViewController()
        let adapter = AnchorPagerPagingAdapter()
        reload(
            adapter,
            titles: ["Plain"],
            viewControllers: [plainPage],
            selectedIndex: 0
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = adapter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let pageViewController = try XCTUnwrap(
            adapter.children.compactMap { $0 as? UIPageViewController }.first
        )

        XCTAssertTrue(adapter.setPagePresentationTranslationY(-24))
        XCTAssertEqual(pageViewController.view.transform.ty, -24, accuracy: 0.001)

        XCTAssertTrue(adapter.prepareForRemoval())

        XCTAssertEqual(pageViewController.view.transform, .identity)
    }

    @MainActor
    func testDeleteBasedPrepareForRemovalClearsSelectedPageFromMultiplePagesSynchronously() {
        let first = UIViewController()
        let second = UIViewController()
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        reload(
            adapter,
            titles: ["First", "Second"],
            viewControllers: [first, second],
            selectedIndex: 1
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = adapter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        XCTAssertTrue(adapter.currentViewController === second)
        XCTAssertNotNil(second.parent)
        delegate.events.removeAll()

        let didCompleteSynchronously = adapter.prepareForRemoval()

        XCTAssertTrue(didCompleteSynchronously)
        XCTAssertEqual(adapter.pageCount, 0)
        XCTAssertNil(adapter.currentIndex)
        XCTAssertNil(second.parent)
        XCTAssertNil(second.view.superview)
        XCTAssertEqual(delegate.events, [])
    }

    @MainActor
    func testDeleteBasedPrepareForRemovalIsRepeatableAndSilent() {
        let page = UIViewController()
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        reload(adapter, titles: ["Page"], viewControllers: [page], selectedIndex: 0)
        adapter.loadViewIfNeeded()
        delegate.events.removeAll()

        let firstDidCompleteSynchronously = adapter.prepareForRemoval()
        let secondDidCompleteSynchronously = adapter.prepareForRemoval()

        XCTAssertTrue(firstDidCompleteSynchronously)
        XCTAssertTrue(secondDidCompleteSynchronously)
        XCTAssertEqual(adapter.pageCount, 0)
        XCTAssertNil(adapter.currentIndex)
        XCTAssertNil(page.parent)
        XCTAssertNil(page.view.superview)
        XCTAssertEqual(delegate.events, [])
    }

    @MainActor
    func testReloadReadinessTracksSelectionWithoutMutatingPagingState() {
        let first = UIViewController()
        let second = UIViewController()
        let adapter = AnchorPagerPagingAdapter()
        reload(
            adapter,
            titles: ["First", "Second"],
            viewControllers: [first, second],
            selectedIndex: 0
        )
        adapter.loadViewIfNeeded()
        XCTAssertTrue(adapter.isReadyForReload)

        adapter.pageboyViewController(
            adapter,
            willScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        XCTAssertFalse(adapter.isReadyForReload)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 2)
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === first)

        adapter.pageboyViewController(
            adapter,
            didCancelScrollToPageAt: 1,
            returnToPageAt: 0
        )

        XCTAssertTrue(adapter.isReadyForReload)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 2)
    }

    func testProgrammaticDidRemainsBusyUntilScrollCompletion() {
        let adapter = AnchorPagerPagingAdapter()
        adapter.loadViewIfNeeded()
        reload(
            adapter,
            titles: ["First", "Second"],
            viewControllers: [UIViewController(), UIViewController()],
            selectedIndex: 0
        )
        XCTAssertTrue(adapter.setSelectedIndex(1, animated: true))

        adapter.pageboyViewController(
            adapter,
            didScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        XCTAssertFalse(adapter.isReadyForReload)

        adapter.finishProgrammaticTransition(at: 1, finished: true)

        XCTAssertTrue(adapter.isReadyForReload)
    }

    func testReloadReadinessUsesSemanticTransactionStateOnly() throws {
        let sourceURL = try packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("AnchorPager")
            .appendingPathComponent("Paging")
            .appendingPathComponent("AnchorPagerPagingAdapter.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let readiness = try XCTUnwrap(
            source.components(separatedBy: "var isReadyForReload: Bool {").dropFirst().first?
                .components(separatedBy: "\n    }").first
        )

        XCTAssertFalse(readiness.contains("isTracking"))
        XCTAssertFalse(readiness.contains("isDragging"))
        XCTAssertFalse(readiness.contains("isDecelerating"))
    }

    @MainActor
    func testDeleteThenPostOrderTeardownClearsRemainingPageboyContainment() {
        let page = UIViewController()
        let adapter = AnchorPagerPagingAdapter()
        reload(adapter, titles: ["Page"], viewControllers: [page], selectedIndex: 0)
        adapter.loadViewIfNeeded()
        XCTAssertEqual(adapter.children.count, 1)
        XCTAssertFalse(adapter.children.first === page)
        XCTAssertTrue(adapter.children.first?.children.contains(page) == true)
        let didCompleteSynchronously = adapter.prepareForRemoval()

        XCTAssertTrue(didCompleteSynchronously)
        XCTAssertNil(page.parent)
        XCTAssertNil(page.view.superview)
        XCTAssertTrue(adapter.children.isEmpty)
    }

    @MainActor
    func testPostOrderRemovalDoesNotDuplicateBusinessPageAppearanceCallbacks() {
        let page = AppearanceRecordingPageViewController()
        let adapter = AnchorPagerPagingAdapter()
        reload(adapter, titles: ["Page"], viewControllers: [page], selectedIndex: 0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = adapter
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer { window.isHidden = true }
        page.events.removeAll()

        let didCompleteSynchronously = adapter.prepareForRemoval()

        XCTAssertTrue(didCompleteSynchronously)
        XCTAssertLessThanOrEqual(page.events.filter { $0 == .willDisappear }.count, 1)
        XCTAssertLessThanOrEqual(page.events.filter { $0 == .didDisappear }.count, 1)
        XCTAssertFalse(page.events.contains(.willAppear))
        XCTAssertFalse(page.events.contains(.didAppear))
    }

    func testPublicSourcesDoNotReferenceTabmanOrPageboy() throws {
        let publicDirectory = try packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("AnchorPager")
            .appendingPathComponent("Public")
        let swiftFiles = try FileManager.default.swiftFiles(in: publicDirectory)

        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.contains("Tabman"), "\(file.path) 不应引用 Tabman")
            XCTAssertFalse(contents.contains("Pageboy"), "\(file.path) 不应引用 Pageboy")
        }
    }

    func testPublicDocCUsesUserFacingTopOverscrollTerms() throws {
        let publicDirectory = try packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("AnchorPager")
            .appendingPathComponent("Public")
        let swiftFiles = try FileManager.default.swiftFiles(in: publicDirectory)
        let docComments = try swiftFiles.flatMap { file in
            try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("///") }
        }
        let normalizedDocC = docComments.joined(separator: "\n")
        let internalTerms = try NSRegularExpression(
            pattern: #"(?i)\b(owner|handoff|pin(?:\s+anchor)?)\b"#
        )
        let fullRange = NSRange(
            normalizedDocC.startIndex..<normalizedDocC.endIndex,
            in: normalizedDocC
        )

        XCTAssertNil(
            internalTerms.firstMatch(in: normalizedDocC, range: fullRange),
            "Public DocC 不得暴露内部状态机术语。"
        )

        let configurationSource = try String(
            contentsOf: publicDirectory.appendingPathComponent(
                "AnchorPagerConfiguration.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            configurationSource.contains(
                "/// 收敛到稳定边界，不提供可见的顶部 overscroll。"
            )
        )
        XCTAssertTrue(
            configurationSource.contains(
                "/// 由当前真实 child 滚动视图按自身原生配置处理顶部 overscroll。"
            )
        )
        XCTAssertTrue(
            configurationSource.contains(
                "/// 当前页面的 scroll target 为 nil 时，该模式不可用，且不会回退到 container。"
            )
        )
    }

    private func packageRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let packageFile = current.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageFile.path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func reload(
        _ adapter: AnchorPagerPagingAdapter,
        titles: [String],
        viewControllers: [UIViewController],
        selectedIndex: Int
    ) {
        let provider = RecordingPageProvider(
            pages: Dictionary(
                uniqueKeysWithValues: viewControllers.enumerated().map { ($0.offset, $0.element) }
            )
        )
        retainedPageProvider = provider
        adapter.pageProvider = provider
        adapter.reload(
            requestIdentifier: 1,
            titles: titles,
            pageCount: viewControllers.count,
            selectedIndex: selectedIndex
        )
    }
}

@MainActor
private final class ScrollPageViewController: UIViewController {
    let scrollView = UIScrollView()

    override func loadView() {
        view = scrollView
    }
}

@MainActor
private final class AppearanceRecordingPageViewController: UIViewController {
    enum Event: Equatable {
        case willAppear
        case didAppear
        case willDisappear
        case didDisappear
    }

    var events: [Event] = []

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        events.append(.willAppear)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        events.append(.didAppear)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        events.append(.willDisappear)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        events.append(.didDisappear)
    }
}

@MainActor
private final class RecordingPageProvider: AnchorPagerPageProviding {
    var pages: [Int: UIViewController]
    var requestedIndexes: [Int] = []

    init(pages: [Int: UIViewController]) {
        self.pages = pages
    }

    func pageViewController(at index: Int) -> UIViewController? {
        requestedIndexes.append(index)
        return pages[index]
    }
}

@MainActor
private final class RecordingPagingDelegate: AnchorPagerPagingAdapterDelegate {
    enum Event: Equatable {
        case willSelect(Int, Bool)
        case didSelect(Int, Bool)
        case didCancel(Int, Int)
        case didReload(Int)
    }

    enum Callback: Equatable {
        case barInsets(UIEdgeInsets)
        case didReload(Int, UIEdgeInsets)
    }

    var events: [Event] = []
    var barInsets: [UIEdgeInsets] = []
    var callbackOrder: [Callback] = []

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {
        self.barInsets.append(barInsets)
        callbackOrder.append(.barInsets(barInsets))
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        willSelect index: Int,
        animated: Bool
    ) {
        let event = Event.willSelect(index, animated)
        events.append(event)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didSelect index: Int,
        animated: Bool
    ) {
        let event = Event.didSelect(index, animated)
        events.append(event)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    ) {
        let event = Event.didCancel(index, previousIndex)
        events.append(event)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didReloadAt index: Int,
        terminalBarInsets: UIEdgeInsets,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    ) {
        let event = Event.didReload(index)
        events.append(event)
        callbackOrder.append(.didReload(index, terminalBarInsets))
    }
}

private extension FileManager {
    func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true && url.pathExtension == "swift" ? url : nil
        }
    }
}
