import Pageboy
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
    func testVerticalContainerHidesScrollIndicators() {
        let pager = AnchorPagerViewController()
        pager.loadViewIfNeeded()

        XCTAssertFalse(pager.verticalScrollView.showsVerticalScrollIndicator)
        XCTAssertFalse(pager.verticalScrollView.showsHorizontalScrollIndicator)
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
    func testReloadDataRequestsOnlyVisiblePageWindowInsteadOfAllPages() {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(
            count: 100,
            viewControllers: (0..<100).map { _ in ScrollChildViewController() }
        )
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        dataSource.requestedViewControllerIndexes.removeAll()

        pager.reloadData()

        XCTAssertLessThanOrEqual(dataSource.requestedViewControllerIndexes.count, 2)
        XCTAssertFalse(dataSource.requestedViewControllerIndexes.contains(99))
    }

    @MainActor
    func testRepeatedAdapterRequestReusesLivePageWithoutCallingDataSourceAgain() throws {
        let child = ScrollChildViewController()
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 1, viewControllers: [child])
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()
        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        let requestCount = dataSource.requestedViewControllerIndexes.count

        let first = adapter.viewController(for: adapter, at: 0)
        let second = adapter.viewController(for: adapter, at: 0)

        XCTAssertTrue(first === child)
        XCTAssertTrue(second === child)
        XCTAssertEqual(dataSource.requestedViewControllerIndexes.count, requestCount)
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
    func testVisibleSetSelectedIndexWaitsForAdapterConfirmationBeforeCommitting() throws {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(
            count: 3,
            viewControllers: [
                ScrollChildViewController(),
                ScrollChildViewController(),
                ScrollChildViewController()
            ]
        )
        let delegate = StubDelegate()
        pager.dataSource = dataSource
        pager.delegate = delegate
        pager.loadViewIfNeeded()
        pager.reloadData()

        pager.setSelectedIndex(2, animated: true)

        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertEqual(pager.effectiveSelectedIndex, 0)
        XCTAssertEqual(delegate.selectedIndexes, [])

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        adapter.pageboyViewController(
            adapter,
            didScrollToPageAt: 2,
            direction: .forward,
            animated: true
        )

        XCTAssertEqual(pager.selectedIndex, 2)
        XCTAssertEqual(pager.effectiveSelectedIndex, 2)
        XCTAssertEqual(delegate.selectedIndexes, [2])
    }

    @MainActor
    func testVisibleSetSelectedIndexCancelDoesNotNotifyDelegate() throws {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(
            count: 2,
            viewControllers: [
                ScrollChildViewController(),
                ScrollChildViewController()
            ]
        )
        let delegate = StubDelegate()
        pager.dataSource = dataSource
        pager.delegate = delegate
        pager.loadViewIfNeeded()
        pager.reloadData()

        pager.setSelectedIndex(1, animated: true)

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        adapter.pageboyViewController(adapter, didCancelScrollToPageAt: 1, returnToPageAt: 0)

        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertEqual(pager.effectiveSelectedIndex, 0)
        XCTAssertEqual(delegate.selectedIndexes, [])
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
    func testReloadHeaderLayoutSendsLayoutContext() throws {
        let pager = AnchorPagerViewController()
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let headerView = FixedFittingView(height: 72)
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        let delegate = StubDelegate()
        pager.dataSource = dataSource
        pager.delegate = delegate
        pager.loadViewIfNeeded()
        pager.reloadData()

        delegate.layoutContexts.removeAll()
        pager.reloadHeaderLayout()
        pager.view.layoutIfNeeded()

        let context = try XCTUnwrap(delegate.layoutContexts.last)
        XCTAssertEqual(context.selectedIndex, 0)
        XCTAssertEqual(context.headerFrame.height, 72)
        XCTAssertGreaterThan(context.contentFrame.height, 0)
    }

    @MainActor
    func testReloadHeaderLayoutPreservesVisualPositionWhenHeaderHeightChanges() {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .automatic(min: 0, max: nil)
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let headerView = DynamicFittingView(height: 100)
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()
        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 30)

        headerView.measuredHeight = 160
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)

        XCTAssertEqual(pager.verticalScrollView.contentOffset.y, 90, accuracy: 0.001)
    }

    @MainActor
    func testReloadHeaderLayoutPreservesCollapseProgressWhenHeaderHeightChanges() {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .automatic(min: 20, max: nil)
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let headerView = DynamicFittingView(height: 100)
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()
        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 40)

        headerView.measuredHeight = 180
        pager.reloadHeaderLayout(offsetAdjustment: .preserveCollapseProgress)

        XCTAssertEqual(pager.verticalScrollView.contentOffset.y, 80, accuracy: 0.001)
    }

    @MainActor
    func testReloadHeaderLayoutCanResetToExpandedAndCollapsed() {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .automatic(min: 20, max: nil)
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let headerView = DynamicFittingView(height: 100)
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()
        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 40)

        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        XCTAssertEqual(pager.verticalScrollView.contentOffset.y, 0, accuracy: 0.001)

        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 40)
        pager.reloadHeaderLayout(offsetAdjustment: .resetToCollapsed)
        XCTAssertEqual(pager.verticalScrollView.contentOffset.y, 80, accuracy: 0.001)
    }

    @MainActor
    func testRuntimeHeaderFrameChangeUpdatesLayoutContext() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .automatic(min: 0, max: nil)
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let headerView = DynamicFittingView(height: 72)
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        let delegate = StubDelegate()
        pager.dataSource = dataSource
        pager.delegate = delegate
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()

        delegate.layoutContexts.removeAll()
        headerView.measuredHeight = 120
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)

        let context = try XCTUnwrap(delegate.layoutContexts.last)
        XCTAssertEqual(context.headerFrame.height, 120)
        XCTAssertEqual(context.barFrame.minY, 120)
    }

    @MainActor
    func testInsideSafeAreaUsesAdditionalSafeAreaInsetsTop() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 80, min: 0)
        configuration.header.topBehavior = .insideSafeArea
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        pager.additionalSafeAreaInsets = UIEdgeInsets(top: 24, left: 0, bottom: 0, right: 0)
        let delegate = StubDelegate()
        pager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 80))
        )
        pager.delegate = delegate
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()

        delegate.layoutContexts.removeAll()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)

        let context = try XCTUnwrap(delegate.layoutContexts.last)
        XCTAssertEqual(context.headerFrame.minY, 24)
        XCTAssertEqual(context.barFrame.minY, 104)
    }

    @MainActor
    func testExtendsUnderTopSafeAreaKeepsHeaderAtBoundsTopAndPinsBar() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 10, min: 0)
        configuration.header.topBehavior = .extendsUnderTopSafeArea
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        pager.additionalSafeAreaInsets = UIEdgeInsets(top: 24, left: 0, bottom: 0, right: 0)
        let delegate = StubDelegate()
        pager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 10))
        )
        pager.delegate = delegate
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()

        delegate.layoutContexts.removeAll()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)

        let context = try XCTUnwrap(delegate.layoutContexts.last)
        XCTAssertEqual(context.headerFrame.minY, 0)
        XCTAssertEqual(context.headerFrame.height, 34)
        XCTAssertEqual(context.barFrame.minY, context.headerFrame.maxY)
    }

    @MainActor
    func testBottomObstructionDoesNotClipContentFrame() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 80, min: 0)
        configuration.bar.height = 48
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        pager.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        let delegate = StubDelegate()
        pager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 80))
        )
        pager.delegate = delegate
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()

        delegate.layoutContexts.removeAll()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)

        let context = try XCTUnwrap(delegate.layoutContexts.last)
        XCTAssertEqual(context.contentFrame.minY, context.barFrame.maxY)
        XCTAssertEqual(context.contentFrame.maxY, 640)
        XCTAssertEqual(context.contentFrame.height, 640 - context.contentFrame.minY)
    }

    @MainActor
    func testNavigationBarVisibilityChangesTopObstruction() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 80, min: 0)
        configuration.header.topBehavior = .insideSafeArea
        let pager = AnchorPagerViewController(configuration: configuration)
        let delegate = StubDelegate()
        pager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 80))
        )
        pager.delegate = delegate
        let navigationController = UINavigationController(rootViewController: pager)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        delegate.layoutContexts.removeAll()
        navigationController.setNavigationBarHidden(false, animated: false)
        window.layoutIfNeeded()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        let visibleContext = try XCTUnwrap(delegate.layoutContexts.last)

        delegate.layoutContexts.removeAll()
        navigationController.setNavigationBarHidden(true, animated: false)
        window.layoutIfNeeded()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        let hiddenContext = try XCTUnwrap(delegate.layoutContexts.last)

        XCTAssertGreaterThan(visibleContext.headerFrame.minY, hiddenContext.headerFrame.minY)
    }

    @MainActor
    func testNavigationBarDoesNotDoubleApplyTopInsetToHeaderFrame() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 80, min: 0)
        configuration.header.topBehavior = .insideSafeArea
        let pager = AnchorPagerViewController(configuration: configuration)
        let headerView = FixedFittingView(height: 80)
        let delegate = StubDelegate()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        pager.delegate = delegate
        let navigationController = UINavigationController(rootViewController: pager)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        delegate.layoutContexts.removeAll()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        window.layoutIfNeeded()

        let context = try XCTUnwrap(delegate.layoutContexts.last)
        let headerHostView = try XCTUnwrap(headerView.superview)
        let actualHeaderFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)

        XCTAssertEqual(pager.verticalScrollView.contentInsetAdjustmentBehavior, .never)
        XCTAssertEqual(actualHeaderFrame.minY, context.headerFrame.minY, accuracy: 0.5)
        XCTAssertEqual(actualHeaderFrame.height, context.headerFrame.height, accuracy: 0.5)
    }

    @MainActor
    func testHeaderActualFrameMatchesLayoutContextWhenContentOffsetIsPreserved() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 120, min: 0)
        configuration.header.topBehavior = .insideSafeArea
        let pager = AnchorPagerViewController(configuration: configuration)
        let headerView = FixedFittingView(height: 120)
        let delegate = StubDelegate()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        pager.delegate = delegate
        let navigationController = UINavigationController(rootViewController: pager)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        delegate.layoutContexts.removeAll()
        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 48)
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()

        let context = try XCTUnwrap(delegate.layoutContexts.last)
        let headerHostView = try XCTUnwrap(headerView.superview)
        let actualHeaderFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)

        XCTAssertEqual(actualHeaderFrame.minY, context.headerFrame.minY, accuracy: 0.5)
        XCTAssertEqual(actualHeaderFrame.height, context.headerFrame.height, accuracy: 0.5)
    }

    @MainActor
    func testContainerScrollRangeDoesNotDependOnCurrentContentOffset() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 120, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 120))
        )
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        let expectedHeight = pager.verticalScrollView.bounds.height + 120

        XCTAssertEqual(pager.verticalScrollView.contentSize.height, expectedHeight, accuracy: 0.5)

        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 60)
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()

        XCTAssertEqual(pager.verticalScrollView.contentSize.height, expectedHeight, accuracy: 0.5)
    }

    @MainActor
    func testHeaderReturnsToSafeAreaAfterTopBehaviorSwitchAndBounce() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 120, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        let headerView = FixedFittingView(height: 120)
        let delegate = StubDelegate()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        pager.delegate = delegate
        let navigationController = UINavigationController(rootViewController: pager)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        window.layoutIfNeeded()
        let headerHostView = try XCTUnwrap(headerView.superview)
        let initialFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)

        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 60)
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        pager.configuration.header.topBehavior = .extendsUnderTopSafeArea
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        pager.configuration.header.topBehavior = .insideSafeArea
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()

        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: -24)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        pager.verticalScrollView.contentOffset = .zero
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()

        let finalFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
        let context = try XCTUnwrap(delegate.layoutContexts.last)

        XCTAssertEqual(finalFrame.minY, initialFrame.minY, accuracy: 0.5)
        XCTAssertEqual(finalFrame.minY, context.headerFrame.minY, accuracy: 0.5)
    }

    @MainActor
    func testAutomaticHeaderHeightStaysStableAcrossTopBehaviorSwitchAndBounceSettlement() throws {
        let pager = AnchorPagerViewController()
        let headerView = SafeAreaSensitiveHeaderView(contentHeight: 80)
        let delegate = StubDelegate()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        pager.delegate = delegate
        let navigationController = UINavigationController(rootViewController: pager)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        window.layoutIfNeeded()
        let initialContext = try XCTUnwrap(delegate.layoutContexts.last)

        pager.configuration.header.topBehavior = .extendsUnderTopSafeArea
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()
        let extendedContext = try XCTUnwrap(delegate.layoutContexts.last)

        XCTAssertEqual(extendedContext.barFrame.minY, initialContext.barFrame.minY, accuracy: 0.5)

        pager.configuration.header.topBehavior = .insideSafeArea
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()
        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: -24)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        pager.verticalScrollView.contentOffset = .zero
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()
        let finalContext = try XCTUnwrap(delegate.layoutContexts.last)

        XCTAssertEqual(finalContext.headerFrame.height, initialContext.headerFrame.height, accuracy: 0.5)
        XCTAssertEqual(finalContext.barFrame.minY, initialContext.barFrame.minY, accuracy: 0.5)
    }

    @MainActor
    func testNegativeContainerOffsetTranslatesViewportAndLayoutContextWithoutChangingRange() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 120, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        let headerView = FixedFittingView(height: 120)
        let delegate = StubDelegate()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        pager.delegate = delegate
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        window.layoutIfNeeded()
        let headerHostView = try XCTUnwrap(headerView.superview)
        let initialFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
        let initialContentSize = pager.verticalScrollView.contentSize

        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: -24)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()
        let bouncedFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
        let bouncedContext = try XCTUnwrap(delegate.layoutContexts.last)

        XCTAssertEqual(bouncedFrame.minY, initialFrame.minY + 24, accuracy: 0.5)
        XCTAssertEqual(bouncedContext.headerFrame.minY, bouncedFrame.minY, accuracy: 0.5)
        XCTAssertEqual(pager.verticalScrollView.contentSize, initialContentSize)
        XCTAssertTrue(delegate.collapseProgresses.isEmpty)

        pager.verticalScrollView.contentOffset = .zero
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()
        let restoredFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
        let restoredContext = try XCTUnwrap(delegate.layoutContexts.last)

        XCTAssertEqual(restoredFrame.minY, initialFrame.minY, accuracy: 0.5)
        XCTAssertEqual(restoredContext.headerFrame.minY, initialFrame.minY, accuracy: 0.5)
        XCTAssertEqual(pager.verticalScrollView.contentSize, initialContentSize)
    }

    @MainActor
    func testContainerScrollingUpdatesCollapseProgressWithoutHotPathLogs() {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 120, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        let delegate = StubDelegate()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 120))
        )
        pager.dataSource = dataSource
        pager.delegate = delegate
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()

        XCTAssertTrue(delegate.collapseProgresses.isEmpty)

        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 60)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        pager.view.layoutIfNeeded()

        XCTAssertNotNil(pager.verticalScrollView.delegate)
        XCTAssertFalse(pager.verticalScrollView.delegate === pager)
        XCTAssertEqual(delegate.collapseProgresses, [0.5])
        XCTAssertFalse(events.contains { $0.event == "header.measure" })
        XCTAssertFalse(events.contains { $0.event == "layout.headerFrameChanged" })
        XCTAssertFalse(events.contains { $0.event == "layout.barFrameChanged" })
        XCTAssertFalse(events.contains { $0.event == "inset.managedTargetChanged" })
    }

    @MainActor
    func testHeaderScrollingMovesAdapterWithoutChangingAdapterOrChildHeight() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 120, min: 20)
        configuration.bar.height = 56
        let pager = AnchorPagerViewController(configuration: configuration)
        let child = ScrollChildViewController()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [child],
            headerContent: .view(FixedFittingView(height: 120))
        )
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        pager.reloadData()
        window.layoutIfNeeded()

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        let expandedAdapterHeight = adapter.view.bounds.height
        let expandedChildHeight = child.view.bounds.height
        let expandedMinY = adapter.view.frame.minY

        pager.verticalScrollView.contentOffset.y = 100
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()

        XCTAssertLessThan(adapter.view.frame.minY, expandedMinY)
        XCTAssertEqual(adapter.view.bounds.height, expandedAdapterHeight, accuracy: 0.5)
        XCTAssertEqual(child.view.bounds.height, expandedChildHeight, accuracy: 0.5)
    }

    @MainActor
    func testManagedTopUsesTabmanBarOnlyAndPreservesExternalInsets() {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 120, min: 20)
        configuration.bar.height = 56
        let pager = AnchorPagerViewController(configuration: configuration)
        let child = ScrollChildViewController()
        child.loadViewIfNeeded()
        child.scrollView.contentInset = UIEdgeInsets(top: 7, left: 3, bottom: 11, right: 4)
        child.scrollView.contentOffset.y = -7
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [child],
            headerContent: .view(FixedFittingView(height: 120))
        )
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        pager.view.layoutIfNeeded()

        XCTAssertEqual(child.scrollView.contentInset.top, 63, accuracy: 0.5)
        XCTAssertEqual(child.scrollView.contentInset.left, 3, accuracy: 0.001)
        XCTAssertEqual(child.scrollView.contentInset.right, 4, accuracy: 0.001)
        XCTAssertEqual(child.scrollView.contentOffset.y, -63, accuracy: 0.5)
    }

    @MainActor
    func testManagedScrollIndicatorInsetsUseChildLocalBottomObstruction() {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 120, min: 20)
        configuration.bar.height = 56
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.additionalSafeAreaInsets.bottom = 23
        let child = ScrollChildViewController()
        child.loadViewIfNeeded()
        child.scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: 2,
            left: 1,
            bottom: 5,
            right: 3
        )
        child.scrollView.automaticallyAdjustsScrollIndicatorInsets = true
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [child],
            headerContent: .view(FixedFittingView(height: 120))
        )
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()

        XCTAssertEqual(
            child.scrollView.verticalScrollIndicatorInsets.top,
            58,
            accuracy: 0.5
        )
        XCTAssertEqual(
            child.scrollView.verticalScrollIndicatorInsets.bottom,
            5 + pager.view.safeAreaInsets.bottom + 100,
            accuracy: 0.5
        )
        XCTAssertEqual(child.scrollView.verticalScrollIndicatorInsets.left, 1, accuracy: 0.001)
        XCTAssertEqual(child.scrollView.verticalScrollIndicatorInsets.right, 3, accuracy: 0.001)
        XCTAssertFalse(child.scrollView.automaticallyAdjustsScrollIndicatorInsets)
    }

    @MainActor
    func testManagedBottomConvergesWhileContainerCollapses() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 120, min: 20)
        configuration.bar.height = 56
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.additionalSafeAreaInsets.bottom = 23
        let child = ScrollChildViewController()
        child.loadViewIfNeeded()
        child.scrollView.contentInset.bottom = 11
        child.scrollView.verticalScrollIndicatorInsets.bottom = 5
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [child],
            headerContent: .view(FixedFittingView(height: 120))
        )
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        let fixedAdapterHeight = adapter.view.bounds.height
        let fixedChildHeight = child.view.bounds.height
        let safeBottom = pager.view.safeAreaInsets.bottom
        XCTAssertEqual(child.scrollView.contentInset.bottom, 11 + safeBottom + 100, accuracy: 0.5)
        XCTAssertEqual(
            child.scrollView.verticalScrollIndicatorInsets.bottom,
            5 + safeBottom + 100,
            accuracy: 0.5
        )

        child.scrollView.contentOffset.y = -child.scrollView.contentInset.top + 37
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        pager.verticalScrollView.contentOffset.y = 50
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()

        XCTAssertEqual(child.scrollView.contentInset.bottom, 11 + safeBottom + 50, accuracy: 0.5)
        XCTAssertEqual(
            child.scrollView.verticalScrollIndicatorInsets.bottom,
            5 + safeBottom + 50,
            accuracy: 0.5
        )
        XCTAssertEqual(
            child.scrollView.contentOffset.y + child.scrollView.contentInset.top,
            37,
            accuracy: 0.5
        )
        XCTAssertEqual(adapter.view.bounds.height, fixedAdapterHeight, accuracy: 0.5)
        XCTAssertEqual(child.view.bounds.height, fixedChildHeight, accuracy: 0.5)
        XCTAssertFalse(events.contains { $0.event == "inset.ownership.update" })

        pager.verticalScrollView.contentOffset.y = 100
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()

        XCTAssertEqual(child.scrollView.contentInset.bottom, 11 + safeBottom, accuracy: 0.5)
        XCTAssertEqual(
            child.scrollView.verticalScrollIndicatorInsets.bottom,
            5 + safeBottom,
            accuracy: 0.5
        )
        XCTAssertEqual(
            child.scrollView.contentOffset.y + child.scrollView.contentInset.top,
            37,
            accuracy: 0.5
        )
        XCTAssertEqual(adapter.view.bounds.height, fixedAdapterHeight, accuracy: 0.5)
        XCTAssertEqual(child.view.bounds.height, fixedChildHeight, accuracy: 0.5)
        XCTAssertFalse(events.contains { $0.event == "inset.ownership.update" })
    }

    @MainActor
    func testTabBarObstructionDoesNotClipContentFrame() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 80, min: 0)
        let tabPager = AnchorPagerViewController(configuration: configuration)
        let tabDelegate = StubDelegate()
        tabPager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 80))
        )
        tabPager.delegate = tabDelegate
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [tabPager]
        let tabWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        tabWindow.rootViewController = tabBarController
        tabWindow.makeKeyAndVisible()
        defer { tabWindow.isHidden = true }

        tabPager.reloadData()
        tabWindow.layoutIfNeeded()
        tabDelegate.layoutContexts.removeAll()
        tabPager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        let tabContext = try XCTUnwrap(tabDelegate.layoutContexts.last)

        let plainPager = AnchorPagerViewController(configuration: configuration)
        let plainDelegate = StubDelegate()
        plainPager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 80))
        )
        plainPager.delegate = plainDelegate
        let plainWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        plainWindow.rootViewController = plainPager
        plainWindow.makeKeyAndVisible()
        defer { plainWindow.isHidden = true }

        plainPager.reloadData()
        plainWindow.layoutIfNeeded()
        plainDelegate.layoutContexts.removeAll()
        plainPager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        let plainContext = try XCTUnwrap(plainDelegate.layoutContexts.last)

        XCTAssertEqual(tabContext.contentFrame.maxY, tabPager.view.bounds.maxY, accuracy: 0.5)
        XCTAssertEqual(tabContext.contentFrame.height, plainContext.contentFrame.height, accuracy: 0.5)
    }

    @MainActor
    func testNavigationToolbarObstructionDoesNotClipContentFrame() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 80, min: 0)
        let toolbarPager = AnchorPagerViewController(configuration: configuration)
        let toolbarDelegate = StubDelegate()
        toolbarPager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 80))
        )
        toolbarPager.delegate = toolbarDelegate
        toolbarPager.toolbarItems = [UIBarButtonItem(barButtonSystemItem: .done, target: nil, action: nil)]
        let toolbarNavigationController = UINavigationController(rootViewController: toolbarPager)
        toolbarNavigationController.setToolbarHidden(false, animated: false)
        let toolbarWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        toolbarWindow.rootViewController = toolbarNavigationController
        toolbarWindow.makeKeyAndVisible()
        defer { toolbarWindow.isHidden = true }

        toolbarPager.reloadData()
        toolbarWindow.layoutIfNeeded()
        toolbarDelegate.layoutContexts.removeAll()
        toolbarPager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        let toolbarContext = try XCTUnwrap(toolbarDelegate.layoutContexts.last)

        let plainPager = AnchorPagerViewController(configuration: configuration)
        let plainDelegate = StubDelegate()
        plainPager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 80))
        )
        plainPager.delegate = plainDelegate
        let plainNavigationController = UINavigationController(rootViewController: plainPager)
        plainNavigationController.setToolbarHidden(true, animated: false)
        let plainWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        plainWindow.rootViewController = plainNavigationController
        plainWindow.makeKeyAndVisible()
        defer { plainWindow.isHidden = true }

        plainPager.reloadData()
        plainWindow.layoutIfNeeded()
        plainDelegate.layoutContexts.removeAll()
        plainPager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        let plainContext = try XCTUnwrap(plainDelegate.layoutContexts.last)

        XCTAssertEqual(toolbarContext.contentFrame.maxY, toolbarPager.view.bounds.maxY, accuracy: 0.5)
        XCTAssertEqual(toolbarContext.contentFrame.height, plainContext.contentFrame.height, accuracy: 0.5)
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
    func testFallbackPageHostKeepsPlainChildAboveBottomObstruction() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 80, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        let plainChild = UIViewController()
        plainChild.view.backgroundColor = .systemBlue
        let delegate = StubDelegate()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [plainChild],
            headerContent: .view(FixedFittingView(height: 80))
        )
        pager.dataSource = dataSource
        pager.delegate = delegate
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [pager]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        delegate.layoutContexts.removeAll()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        window.layoutIfNeeded()

        _ = try XCTUnwrap(delegate.layoutContexts.last)
        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        let fallbackHost = try XCTUnwrap(
            adapter.viewController(for: adapter, at: 0) as? AnchorPagerPageScrollHostViewController
        )
        fallbackHost.loadViewIfNeeded()
        window.layoutIfNeeded()

        let childFrame = plainChild.view.convert(plainChild.view.bounds, to: pager.view)
        XCTAssertEqual(fallbackHost.scrollView.contentInsetAdjustmentBehavior, .never)
        XCTAssertEqual(
            fallbackHost.scrollView.adjustedContentInset.bottom,
            pager.view.safeAreaInsets.bottom + 80,
            accuracy: 0.5
        )
        XCTAssertEqual(
            childFrame.maxY,
            pager.view.safeAreaLayoutGuide.layoutFrame.maxY,
            accuracy: 4
        )
    }

    @MainActor
    func testFallbackHostUsesBarAndBottomManagedInsets() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.bar.height = 56
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.additionalSafeAreaInsets.bottom = 23
        let plainChild = UIViewController()
        let dataSource = StubDataSource(count: 1, viewControllers: [plainChild])
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        let fallbackHost = try XCTUnwrap(
            adapter.viewController(for: adapter, at: 0) as? AnchorPagerPageScrollHostViewController
        )
        XCTAssertEqual(fallbackHost.scrollView.contentInset.top, adapter.barInsets.top, accuracy: 0.5)
        XCTAssertEqual(
            fallbackHost.scrollView.contentInset.bottom,
            pager.view.safeAreaInsets.bottom,
            accuracy: 0.5
        )
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
    func testReloadReleasesStaleInsetOwnershipAndManagesReplacement() {
        var configuration = AnchorPagerConfiguration.default
        configuration.bar.height = 56
        let oldChild = ScrollChildViewController()
        let replacementChild = ScrollChildViewController()
        oldChild.loadViewIfNeeded()
        oldChild.scrollView.contentInsetAdjustmentBehavior = .always
        oldChild.scrollView.contentInset = UIEdgeInsets(top: 7, left: 3, bottom: 11, right: 4)
        oldChild.scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: 2,
            left: 1,
            bottom: 5,
            right: 3
        )
        oldChild.scrollView.automaticallyAdjustsScrollIndicatorInsets = true
        oldChild.scrollView.contentOffset.y = -7
        let dataSource = StubDataSource(count: 1, viewControllers: [oldChild])
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        XCTAssertEqual(oldChild.scrollView.contentInset.top, 63, accuracy: 0.5)

        dataSource.viewControllers = [replacementChild]
        pager.reloadData()
        window.layoutIfNeeded()

        XCTAssertEqual(oldChild.scrollView.contentInset.top, 7, accuracy: 0.5)
        XCTAssertEqual(oldChild.scrollView.contentInset.bottom, 11, accuracy: 0.5)
        XCTAssertEqual(oldChild.scrollView.contentInsetAdjustmentBehavior, .always)
        XCTAssertEqual(
            oldChild.scrollView.verticalScrollIndicatorInsets,
            UIEdgeInsets(top: 2, left: 1, bottom: 5, right: 3)
        )
        XCTAssertTrue(oldChild.scrollView.automaticallyAdjustsScrollIndicatorInsets)
        XCTAssertEqual(replacementChild.scrollView.contentInset.top, 56, accuracy: 0.5)
        XCTAssertEqual(replacementChild.scrollView.contentInsetAdjustmentBehavior, .never)
        XCTAssertFalse(replacementChild.scrollView.automaticallyAdjustsScrollIndicatorInsets)
    }

    @MainActor
    func testRepeatedStructuralLayoutDoesNotRewriteManagedInsets() {
        var configuration = AnchorPagerConfiguration.default
        configuration.bar.height = 56
        let child = ScrollChildViewController()
        let pager = AnchorPagerViewController(configuration: configuration)
        let dataSource = StubDataSource(count: 1, viewControllers: [child])
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        pager.reloadData()
        window.layoutIfNeeded()

        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()

        XCTAssertFalse(events.contains(.init(category: .inset, level: .debug, event: "inset.ownership.update")))
    }

    @MainActor
    func testDeinitReleasesInsetOwnership() {
        var configuration = AnchorPagerConfiguration.default
        configuration.bar.height = 56
        let child = ScrollChildViewController()
        child.loadViewIfNeeded()
        child.scrollView.contentInsetAdjustmentBehavior = .always
        child.scrollView.contentInset.top = 7
        child.scrollView.contentOffset.y = -7
        let dataSource = StubDataSource(count: 1, viewControllers: [child])
        weak var weakPager: AnchorPagerViewController?
        autoreleasepool {
            let pager = AnchorPagerViewController(configuration: configuration)
            weakPager = pager
            pager.dataSource = dataSource
            pager.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            pager.loadViewIfNeeded()
            pager.reloadData()
            pager.view.layoutIfNeeded()
            guard let adapter = installedAdapter(in: pager) else {
                XCTFail("reloadData 应安装分页 adapter。")
                return
            }
            pager.pagingAdapter(
                adapter,
                didUpdateBarInsets: UIEdgeInsets(top: 56, left: 0, bottom: 0, right: 0)
            )
            pager.view.layoutIfNeeded()
            XCTAssertEqual(child.scrollView.contentInset.top, 63, accuracy: 0.5)
        }

        XCTAssertNil(weakPager)
        XCTAssertEqual(child.scrollView.contentInset.top, 7, accuracy: 0.5)
        XCTAssertEqual(child.scrollView.contentInsetAdjustmentBehavior, .always)
    }

    @MainActor
    func testSharedExplicitScrollTargetFallsBackForLaterPageAndWritesLog() throws {
        let sharedScrollView = UIScrollView()
        let first = ExplicitScrollChildViewController(scrollView: sharedScrollView)
        let second = ExplicitScrollChildViewController(scrollView: sharedScrollView)
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 2, viewControllers: [first, second])
        pager.dataSource = dataSource
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        pager.loadViewIfNeeded()

        AnchorPagerAssertions.$isEnabled.withValue(false) {
            pager.reloadData()
        }

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        let pages = AnchorPagerAssertions.$isEnabled.withValue(false) {
            (
                adapter.viewController(for: adapter, at: 0),
                adapter.viewController(for: adapter, at: 1)
            )
        }
        XCTAssertTrue(pages.0 === first)
        XCTAssertTrue(
            pages.1 is AnchorPagerPageScrollHostViewController
        )
        XCTAssertTrue(events.contains(.init(category: .inset, level: .debug, event: "inset.targetCollision")))
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
    func testHeaderAndBarFrameChangesWriteLayoutLogs() {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 72, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        pager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 72))
        )
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()

        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        pager.configuration.header.heightMode = .fixed(max: 120, min: 0)
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)

        XCTAssertTrue(events.contains(.init(category: .layout, level: .debug, event: "layout.headerHeightResolved")))
        XCTAssertTrue(events.contains(.init(category: .layout, level: .debug, event: "layout.headerFrameChanged")))
        XCTAssertTrue(events.contains(.init(category: .layout, level: .debug, event: "layout.barFrameChanged")))

        events.removeAll()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)

        XCTAssertFalse(events.contains(.init(category: .layout, level: .debug, event: "layout.headerHeightResolved")))
        XCTAssertFalse(events.contains(.init(category: .layout, level: .debug, event: "layout.headerFrameChanged")))
        XCTAssertFalse(events.contains(.init(category: .layout, level: .debug, event: "layout.barFrameChanged")))
    }

    @MainActor
    func testSafeAreaAndBoundsChangesWriteLayoutLogs() {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 80, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        pager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(FixedFittingView(height: 80))
        )
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()

        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        pager.additionalSafeAreaInsets = UIEdgeInsets(top: 24, left: 0, bottom: 34, right: 0)
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)

        XCTAssertTrue(events.contains(.init(category: .layout, level: .info, event: "layout.safeAreaChanged")))

        events.removeAll()
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 700)
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)

        XCTAssertTrue(events.contains(.init(category: .layout, level: .info, event: "layout.boundsChanged")))

        events.removeAll()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)

        XCTAssertFalse(events.contains(.init(category: .layout, level: .info, event: "layout.safeAreaChanged")))
        XCTAssertFalse(events.contains(.init(category: .layout, level: .info, event: "layout.boundsChanged")))
    }

    @MainActor
    func testConfigurationDefaultsMatchV01Baseline() {
        let configuration = AnchorPagerConfiguration.default

        XCTAssertEqual(configuration.header.heightMode, .automatic(min: 0, max: nil))
        XCTAssertEqual(configuration.header.topBehavior, .insideSafeArea)
        XCTAssertNil(configuration.bar.height)
        XCTAssertEqual(configuration.topOverscrollHandlingMode, .none)
    }

    @MainActor
    private func installedAdapter(in pager: AnchorPagerViewController) -> AnchorPagerPagingAdapter? {
        pager.children.compactMap { $0 as? AnchorPagerPagingAdapter }.first
    }
}

@MainActor
private final class StubDataSource: AnchorPagerViewControllerDataSource {
    var count: Int
    var titles: [String]
    var viewControllers: [UIViewController]
    var headerContent: AnchorPagerHeaderContent
    var requestedViewControllerIndexes: [Int] = []

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
        requestedViewControllerIndexes.append(index)
        return viewControllers.indices.contains(index) ? viewControllers[index] : UIViewController()
    }

    func headerContent(in pagerViewController: AnchorPagerViewController) -> AnchorPagerHeaderContent {
        headerContent
    }
}

@MainActor
private final class StubDelegate: AnchorPagerViewControllerDelegate {
    var selectedIndexes: [Int] = []
    var collapseProgresses: [CGFloat] = []
    var layoutContexts: [AnchorPagerLayoutContext] = []

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didSelectViewControllerAt index: Int
    ) {
        selectedIndexes.append(index)
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateHeaderCollapseProgress progress: CGFloat
    ) {
        collapseProgresses.append(progress)
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateLayout context: AnchorPagerLayoutContext
    ) {
        layoutContexts.append(context)
    }
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

@MainActor
private final class ExplicitScrollChildViewController: UIViewController {
    private let explicitScrollView: UIScrollView

    init(scrollView: UIScrollView) {
        explicitScrollView = scrollView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func loadView() {
        view = UIView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        anchorPagerScrollView = explicitScrollView
    }
}

private final class FixedFittingView: UIView {
    private let measuredHeight: CGFloat

    init(height: CGFloat) {
        self.measuredHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        CGSize(width: targetSize.width, height: measuredHeight)
    }
}

private final class DynamicFittingView: UIView {
    var measuredHeight: CGFloat

    init(height: CGFloat) {
        self.measuredHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        CGSize(width: targetSize.width, height: measuredHeight)
    }
}

private final class SafeAreaSensitiveHeaderView: UIView {
    let contentView = UIView()

    init(contentHeight: CGFloat) {
        super.init(frame: .zero)
        directionalLayoutMargins = .zero
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            contentView.heightAnchor.constraint(equalToConstant: contentHeight)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }
}
