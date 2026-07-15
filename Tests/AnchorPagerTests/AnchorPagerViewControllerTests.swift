import Pageboy
import Tabman
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
    func testInitialCommittedChildCoordinatesWithoutReplacingBusinessDelegate() {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 100, min: 0)
        let child = ScrollChildViewController()
        child.loadViewIfNeeded()
        let businessDelegate = VerticalOwnershipScrollDelegate()
        child.scrollView.delegate = businessDelegate
        child.scrollView.contentSize = CGSize(width: 320, height: 1_200)
        let pager = AnchorPagerViewController(configuration: configuration)
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [child],
            headerContent: .view(FixedFittingView(height: 100))
        )
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        setContainerLogicalOffset(50, in: pager)
        child.scrollView.contentOffset.y = -child.scrollView.contentInset.top + 20

        XCTAssertEqual(
            child.scrollView.contentOffset.y,
            -child.scrollView.contentInset.top,
            accuracy: 0.5
        )
        XCTAssertTrue(child.scrollView.delegate === businessDelegate)
    }

    @MainActor
    func testPublicVerticalScrollViewUsesInternalContainerWithoutLeakingItsType() {
        let pager = AnchorPagerViewController()

        XCTAssertTrue(pager.verticalScrollView is AnchorPagerContainerScrollView)
        XCTAssertTrue(
            pager.verticalScrollView.panGestureRecognizer.delegate
                === pager.verticalScrollView
        )
    }

    func testVerticalCoordinationSourcesNeverAssignBusinessOrPanDelegates() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift",
            "Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift",
            "Sources/AnchorPager/Gesture/AnchorPagerContainerScrollView.swift"
        ]

        for relativePath in relativePaths {
            let source = try String(
                contentsOf: packageRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            XCTAssertFalse(source.contains(".delegate ="), relativePath)
            XCTAssertFalse(source.contains("panGestureRecognizer.delegate ="), relativePath)
            XCTAssertFalse(source.contains("Task.detached"), relativePath)
            XCTAssertFalse(source.contains("nonisolated(unsafe)"), relativePath)
            XCTAssertFalse(source.contains("@unchecked Sendable"), relativePath)
        }

        let viewControllerSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/AnchorPager/Public/AnchorPagerViewController.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            viewControllerSource.contains(
                "verticalScrollView.delegate = verticalScrollDelegate"
            )
        )
        XCTAssertFalse(viewControllerSource.contains("panGestureRecognizer.delegate ="))
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
    func testReloadDataCountCallbackReentryKeepsLatestTransactionSnapshot() throws {
        let outerHeader = UIView()
        let latestHeader = UIView()
        let outerFirst = ScrollChildViewController()
        let outerSecond = ScrollChildViewController()
        let latestChild = ScrollChildViewController()
        let latestDataSource = StubDataSource(
            count: 1,
            titles: ["Latest"],
            viewControllers: [latestChild],
            headerContent: .view(latestHeader)
        )
        let dataSource = StubDataSource(
            count: 2,
            titles: ["Outer 0", "Outer 1"],
            viewControllers: [outerFirst, outerSecond],
            headerContent: .view(outerHeader)
        )
        let pager = AnchorPagerViewController()
        pager.dataSource = dataSource
        pager.reloadData()
        pager.setSelectedIndex(1, animated: false)
        XCTAssertEqual(pager.selectedIndex, 1)
        pager.loadViewIfNeeded()

        dataSource.resetCallbackRecords()
        dataSource.onNumberOfViewControllers = {
            pager.dataSource = latestDataSource
            pager.reloadData()
        }
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        pager.reloadData()

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 1)
        XCTAssertEqual(adapter.barItem(for: TMBarView.ButtonBar(), at: 0).title, "Latest")
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === latestChild)
        XCTAssertTrue(latestHeader.isDescendant(of: pager.view))
        XCTAssertFalse(outerHeader.isDescendant(of: pager.view))
        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertEqual(pager.effectiveSelectedIndex, 0)
        XCTAssertEqual(dataSource.numberOfViewControllersCallCount, 1)
        XCTAssertEqual(dataSource.headerContentCallCount, 0)
        XCTAssertEqual(dataSource.requestedTitleIndexes, [])
        XCTAssertEqual(latestDataSource.numberOfViewControllersCallCount, 1)
        XCTAssertEqual(latestDataSource.headerContentCallCount, 1)
        XCTAssertEqual(latestDataSource.requestedTitleIndexes, [0])
        XCTAssertEqual(events.filter { $0.event == "lifecycle.reloadData.cancelled" }.count, 1)
        XCTAssertEqual(events.filter { $0.event == "reloadData.begin" }.count, 1)
        XCTAssertEqual(events.filter { $0.event == "children.page.generation.begin" }.count, 1)
        XCTAssertEqual(events.filter { $0.event == "reloadData.end" }.count, 1)
    }

    @MainActor
    func testReloadDataHeaderCallbackReentryKeepsLatestTransactionSnapshot() throws {
        let outerHeader = UIView()
        let latestHeader = UIView()
        let latestChild = ScrollChildViewController()
        let dataSource = StubDataSource(
            count: 2,
            titles: ["Outer 0", "Outer 1"],
            viewControllers: [ScrollChildViewController(), ScrollChildViewController()],
            headerContent: .view(outerHeader)
        )
        let pager = AnchorPagerViewController()
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()

        dataSource.onHeaderContent = {
            dataSource.count = 1
            dataSource.titles = ["Latest"]
            dataSource.viewControllers = [latestChild]
            dataSource.headerContent = .view(latestHeader)
            pager.reloadData()
        }

        pager.reloadData()

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 1)
        XCTAssertEqual(adapter.barItem(for: TMBarView.ButtonBar(), at: 0).title, "Latest")
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === latestChild)
        XCTAssertTrue(latestHeader.isDescendant(of: pager.view))
        XCTAssertFalse(outerHeader.isDescendant(of: pager.view))
        XCTAssertEqual(dataSource.numberOfViewControllersCallCount, 2)
        XCTAssertEqual(dataSource.headerContentCallCount, 2)
        XCTAssertEqual(dataSource.requestedTitleIndexes, [0])
    }

    @MainActor
    func testReloadDataTitleCallbackReentryKeepsLatestTransactionSnapshot() throws {
        let outerHeader = UIView()
        let latestHeader = UIView()
        let latestChild = ScrollChildViewController()
        let dataSource = StubDataSource(
            count: 2,
            titles: ["Outer 0", "Outer 1"],
            viewControllers: [ScrollChildViewController(), ScrollChildViewController()],
            headerContent: .view(outerHeader)
        )
        let pager = AnchorPagerViewController()
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()

        dataSource.onTitle = {
            dataSource.count = 1
            dataSource.titles = ["Latest"]
            dataSource.viewControllers = [latestChild]
            dataSource.headerContent = .view(latestHeader)
            pager.reloadData()
        }

        pager.reloadData()

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 1)
        XCTAssertEqual(adapter.barItem(for: TMBarView.ButtonBar(), at: 0).title, "Latest")
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === latestChild)
        XCTAssertTrue(latestHeader.isDescendant(of: pager.view))
        XCTAssertFalse(outerHeader.isDescendant(of: pager.view))
        XCTAssertEqual(dataSource.numberOfViewControllersCallCount, 2)
        XCTAssertEqual(dataSource.headerContentCallCount, 2)
        XCTAssertEqual(dataSource.requestedTitleIndexes, [0, 0])
    }

    @MainActor
    func testReloadDataNegativeCountWritesSingleChildrenInvalidCountLog() {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: -1)
        pager.dataSource = dataSource
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        AnchorPagerAssertions.$isEnabled.withValue(false) {
            pager.reloadData()
        }

        XCTAssertEqual(
            events.filter { $0.event == "children.page.invalidCount" },
            [
                AnchorPagerLogger.Event(
                    category: .children,
                    level: .error,
                    event: "children.page.invalidCount"
                )
            ]
        )
        XCTAssertNil(pager.effectiveSelectedIndex)
    }

    @MainActor
    func testReloadDataNegativeCountHeaderReentryCancelsBeforePublishingInvalidCount() throws {
        let outerHeader = UIView()
        let latestHeader = UIView()
        let latestChild = ScrollChildViewController()
        let outerDataSource = StubDataSource(
            count: -1,
            titles: [],
            viewControllers: [],
            headerContent: .view(outerHeader)
        )
        let latestDataSource = StubDataSource(
            count: 1,
            titles: ["Latest"],
            viewControllers: [latestChild],
            headerContent: .view(latestHeader)
        )
        let pager = AnchorPagerViewController()
        pager.dataSource = outerDataSource
        pager.loadViewIfNeeded()
        outerDataSource.onHeaderContent = {
            pager.dataSource = latestDataSource
            pager.reloadData()
        }
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        pager.reloadData()

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 1)
        XCTAssertEqual(adapter.barItem(for: TMBarView.ButtonBar(), at: 0).title, "Latest")
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === latestChild)
        XCTAssertTrue(latestHeader.isDescendant(of: pager.view))
        XCTAssertFalse(outerHeader.isDescendant(of: pager.view))
        XCTAssertEqual(outerDataSource.numberOfViewControllersCallCount, 1)
        XCTAssertEqual(outerDataSource.headerContentCallCount, 1)
        XCTAssertEqual(outerDataSource.requestedTitleIndexes, [])
        XCTAssertEqual(latestDataSource.numberOfViewControllersCallCount, 1)
        XCTAssertEqual(latestDataSource.headerContentCallCount, 1)
        XCTAssertEqual(latestDataSource.requestedTitleIndexes, [0])
        XCTAssertFalse(events.contains { $0.event == "children.page.invalidCount" })
        XCTAssertEqual(events.filter { $0.event == "lifecycle.reloadData.cancelled" }.count, 1)
        XCTAssertEqual(events.filter { $0.event == "reloadData.begin" }.count, 1)
        XCTAssertEqual(events.filter { $0.event == "children.page.generation.begin" }.count, 1)
        XCTAssertEqual(events.filter { $0.event == "paging.reload" }.count, 1)
        XCTAssertEqual(events.filter { $0.event == "reloadData.end" }.count, 1)
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
    func testDeferredReloadKeepsCommittedPublicAndVisibleStoreStateUntilTerminal() throws {
        let oldHeader = UIView()
        let newHeader = UIView()
        let oldFirst = ScrollChildViewController()
        let oldSecond = ScrollChildViewController()
        let replacement = ScrollChildViewController()
        let dataSource = StubDataSource(
            count: 2,
            titles: ["Old 0", "Old 1"],
            viewControllers: [oldFirst, oldSecond],
            headerContent: .view(oldHeader)
        )
        let pager = AnchorPagerViewController()
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()
        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === oldFirst)

        pager.setSelectedIndex(1, animated: true)
        dataSource.count = 1
        dataSource.titles = ["Replacement"]
        dataSource.viewControllers = [replacement]
        dataSource.headerContent = .view(newHeader)
        pager.reloadData()

        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertEqual(pager.effectiveSelectedIndex, 0)
        XCTAssertTrue(oldHeader.isDescendant(of: pager.view))
        XCTAssertFalse(newHeader.isDescendant(of: pager.view))
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === oldFirst)

        adapter.pageboyViewController(
            adapter,
            didScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )
        adapter.finishProgrammaticTransition(
            requestIdentifier: 1,
            targetIndex: 1,
            finished: true
        )
        adapter.isUserInteractionEnabled = true
        let pagingHost = try XCTUnwrap(installedPagingHost(in: pager))
        pagingHost.pagingAdapter(
            adapter,
            didReloadAt: 0,
            terminalBarInsets: UIEdgeInsets(top: 44, left: 0, bottom: 0, right: 0),
            requestIdentifier: 2
        )

        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertEqual(pager.effectiveSelectedIndex, 0)
        XCTAssertTrue(newHeader.isDescendant(of: pager.view))
        XCTAssertFalse(oldHeader.isDescendant(of: pager.view))
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === replacement)
    }

    @MainActor
    func testDeferredLatestReloadDoesNotLetOldAdapterFetchPendingGeneration() throws {
        let oldFirst = ScrollChildViewController()
        let oldSecond = ScrollChildViewController()
        let firstReplacement = ScrollChildViewController()
        let latestReplacement = ScrollChildViewController()
        oldFirst.loadViewIfNeeded()
        oldFirst.scrollView.contentInsetAdjustmentBehavior = .always
        let dataSource = StubDataSource(
            count: 2,
            viewControllers: [oldFirst, oldSecond]
        )
        let pager = AnchorPagerViewController()
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()
        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === oldFirst)
        adapter.pageboyViewController(
            adapter,
            willScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        dataSource.count = 1
        dataSource.titles = ["First replacement"]
        dataSource.viewControllers = [firstReplacement]
        pager.reloadData()
        dataSource.titles = ["Latest replacement"]
        dataSource.viewControllers = [latestReplacement]
        pager.reloadData()
        dataSource.requestedViewControllerIndexes.removeAll()

        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === oldFirst)
        XCTAssertEqual(oldFirst.scrollView.contentInsetAdjustmentBehavior, .never)
        XCTAssertFalse(latestReplacement.isViewLoaded)
        XCTAssertEqual(dataSource.requestedViewControllerIndexes, [])

        adapter.pageboyViewController(
            adapter,
            didCancelScrollToPageAt: 1,
            returnToPageAt: 0
        )

        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === latestReplacement)
        XCTAssertFalse(adapter.viewController(for: adapter, at: 0) === firstReplacement)
        XCTAssertEqual(oldFirst.scrollView.contentInsetAdjustmentBehavior, .always)
    }

    @MainActor
    func testDeferredEmptyKeepsOldOwnershipUntilEmptyTerminal() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.bar.height = 56
        let oldFirst = ScrollChildViewController()
        let oldSecond = ScrollChildViewController()
        oldFirst.loadViewIfNeeded()
        oldFirst.scrollView.contentInset = UIEdgeInsets(top: 7, left: 0, bottom: 9, right: 0)
        oldFirst.scrollView.contentInsetAdjustmentBehavior = .always
        let dataSource = StubDataSource(
            count: 2,
            viewControllers: [oldFirst, oldSecond]
        )
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.dataSource = dataSource
        pager.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        pager.loadViewIfNeeded()
        pager.reloadData()
        let host = try XCTUnwrap(installedPagingHost(in: pager))
        let adapter = try XCTUnwrap(host.activeAdapter)
        _ = adapter.viewController(for: adapter, at: 0)
        host.pagingAdapter(
            adapter,
            didUpdateBarInsets: UIEdgeInsets(top: 56, left: 0, bottom: 0, right: 0)
        )
        pager.view.layoutIfNeeded()
        XCTAssertEqual(oldFirst.scrollView.contentInsetAdjustmentBehavior, .never)
        let committedManagedTop = oldFirst.scrollView.contentInset.top

        adapter.pageboyViewController(
            adapter,
            willScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )
        dataSource.count = 0
        dataSource.titles = []
        dataSource.viewControllers = []
        pager.reloadData()

        XCTAssertEqual(pager.effectiveSelectedIndex, 0)
        XCTAssertTrue(host.activeAdapter === adapter)
        XCTAssertEqual(oldFirst.scrollView.contentInset.top, committedManagedTop, accuracy: 0.5)
        XCTAssertEqual(oldFirst.scrollView.contentInsetAdjustmentBehavior, .never)

        adapter.pageboyViewController(
            adapter,
            didCancelScrollToPageAt: 1,
            returnToPageAt: 0
        )

        XCTAssertNil(pager.effectiveSelectedIndex)
        XCTAssertNil(host.activeAdapter)
        XCTAssertEqual(oldFirst.scrollView.contentInset.top, 7, accuracy: 0.5)
        XCTAssertEqual(oldFirst.scrollView.contentInsetAdjustmentBehavior, .always)
    }

    @MainActor
    func testSupersededActiveReloadTerminalAdvancesAndCommitsLatestRequest() throws {
        let oldHeader = UIView()
        let firstHeader = UIView()
        let latestHeader = UIView()
        let oldFirst = ScrollChildViewController()
        let oldSecond = ScrollChildViewController()
        let firstPage = ScrollChildViewController()
        let latestPage = ScrollChildViewController()
        let dataSource = StubDataSource(
            count: 2,
            viewControllers: [oldFirst, oldSecond],
            headerContent: .view(oldHeader)
        )
        var configuration = AnchorPagerConfiguration.default
        configuration.bar.height = 44
        let pager = AnchorPagerViewController(configuration: configuration)
        let delegate = StubDelegate()
        pager.dataSource = dataSource
        pager.delegate = delegate
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        pager.reloadData()
        window.layoutIfNeeded()
        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === oldFirst)
        XCTAssertEqual(adapter.barInsets.top, 44, accuracy: 0.5)
        XCTAssertEqual(oldFirst.scrollView.contentInset.top, 44, accuracy: 0.5)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        dataSource.count = 1
        dataSource.titles = ["First"]
        dataSource.viewControllers = [firstPage]
        dataSource.headerContent = .view(firstHeader)
        var observedCommittedStateWhileLatestWasPending = false
        dataSource.onViewController = {
            pager.configuration.bar.height = 60
            window.layoutIfNeeded()
            XCTAssertEqual(adapter.barInsets.top, 60, accuracy: 0.5)
            XCTAssertEqual(oldFirst.scrollView.contentInset.top, 44, accuracy: 0.5)

            dataSource.count = 1
            dataSource.titles = ["Latest"]
            dataSource.viewControllers = [latestPage]
            dataSource.headerContent = .view(latestHeader)
            pager.reloadData()

            observedCommittedStateWhileLatestWasPending = true
            XCTAssertEqual(pager.selectedIndex, 0)
            XCTAssertEqual(pager.effectiveSelectedIndex, 0)
            XCTAssertTrue(oldHeader.isDescendant(of: pager.view))
            XCTAssertFalse(firstHeader.isDescendant(of: pager.view))
            XCTAssertFalse(latestHeader.isDescendant(of: pager.view))
        }

        pager.reloadData()
        window.layoutIfNeeded()

        XCTAssertTrue(observedCommittedStateWhileLatestWasPending)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 1)
        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertEqual(pager.effectiveSelectedIndex, 0)
        XCTAssertFalse(oldHeader.isDescendant(of: pager.view))
        XCTAssertFalse(firstHeader.isDescendant(of: pager.view))
        XCTAssertTrue(latestHeader.isDescendant(of: pager.view))
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === latestPage)
        XCTAssertFalse(adapter.viewController(for: adapter, at: 0) === firstPage)
        XCTAssertEqual(adapter.barInsets.top, 60, accuracy: 0.5)
        XCTAssertEqual(latestPage.scrollView.contentInset.top, 60, accuracy: 0.5)
        XCTAssertEqual(delegate.layoutContexts.last?.barFrame.height ?? -1, 60, accuracy: 0.5)
        XCTAssertTrue(events.contains(
            .init(category: .paging, level: .debug, event: "paging.reload.stale")
        ))
        XCTAssertEqual(
            events.filter { $0.event == "paging.reload.begin" }.count,
            2
        )
        XCTAssertEqual(
            events.filter { $0.event == "paging.barInsetsChanged" }.count,
            1
        )
    }

    @MainActor
    func testPreloadReloadPublishesInitialMetadataWithoutLoadingPagingView() {
        let page = ScrollChildViewController()
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 1, viewControllers: [page])
        pager.dataSource = dataSource

        pager.reloadData()

        XCTAssertFalse(pager.isViewLoaded)
        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertEqual(pager.effectiveSelectedIndex, 0)
        XCTAssertEqual(dataSource.requestedViewControllerIndexes, [])
        XCTAssertFalse(page.isViewLoaded)
    }

    @MainActor
    func testPreloadSelectionUpdatesStagedRequestUsedAtFirstTerminal() throws {
        let pages = (0..<3).map { _ in ScrollChildViewController() }
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 3, viewControllers: pages)
        pager.dataSource = dataSource
        pager.reloadData()

        pager.setSelectedIndex(2, animated: false)

        XCTAssertFalse(pager.isViewLoaded)
        XCTAssertEqual(pager.selectedIndex, 2)
        XCTAssertEqual(pager.effectiveSelectedIndex, 2)
        XCTAssertEqual(dataSource.requestedViewControllerIndexes, [])

        pager.loadViewIfNeeded()

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertEqual(adapter.currentIndex, 2)
        XCTAssertEqual(pager.selectedIndex, 2)
        XCTAssertEqual(pager.effectiveSelectedIndex, 2)
    }

    @MainActor
    func testMultiplePreloadReloadsUseLatestSnapshotWithoutDuplicateProviderActivation() throws {
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 2)
        pager.dataSource = dataSource
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        pager.reloadData()
        dataSource.count = 3
        dataSource.titles = ["Latest 0", "Latest 1", "Latest 2"]
        dataSource.viewControllers = (0..<3).map { _ in ScrollChildViewController() }
        pager.reloadData()
        pager.setSelectedIndex(2, animated: false)
        let beginCountBeforeViewLoad = events.filter {
            $0.event == "children.page.generation.begin"
        }.count

        pager.loadViewIfNeeded()

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 3)
        XCTAssertEqual(adapter.currentIndex, 2)
        XCTAssertEqual(pager.selectedIndex, 2)
        XCTAssertEqual(
            events.filter { $0.event == "children.page.generation.begin" }.count,
            beginCountBeforeViewLoad
        )
    }

    @MainActor
    func testLayoutDelegateTerminalReentrantReloadPreservesLatestSnapshot() throws {
        let firstHeader = FixedFittingView(height: 40)
        let latestHeader = FixedFittingView(height: 100)
        let firstPage = ScrollChildViewController()
        let latestPage = ScrollChildViewController()
        let pager = AnchorPagerViewController()
        let dataSource = StubDataSource(count: 1)
        let delegate = StubDelegate()
        pager.dataSource = dataSource
        pager.delegate = delegate
        pager.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        pager.loadViewIfNeeded()
        pager.reloadData()

        dataSource.titles = ["First"]
        dataSource.viewControllers = [firstPage]
        dataSource.headerContent = .view(firstHeader)
        var observedFirstTerminal = false
        delegate.onLayout = { _ in
            guard !observedFirstTerminal else { return }
            observedFirstTerminal = true
            XCTAssertTrue(firstHeader.isDescendant(of: pager.view))
            XCTAssertFalse(latestHeader.isDescendant(of: pager.view))
            dataSource.titles = ["Latest"]
            dataSource.viewControllers = [latestPage]
            dataSource.headerContent = .view(latestHeader)
            pager.reloadData()
        }

        pager.reloadData()

        XCTAssertTrue(observedFirstTerminal)
        XCTAssertTrue(latestHeader.isDescendant(of: pager.view))
        XCTAssertFalse(firstHeader.isDescendant(of: pager.view))
        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === latestPage)
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

        let pagingHost = installedPagingHost(in: pager)
        let adapter = pagingHost?.activeAdapter
        guard let adapter else {
            XCTFail("reloadData 应安装分页 adapter。")
            return
        }
        XCTAssertTrue(pagingHost?.parent === pager)
        XCTAssertTrue(adapter.parent === pagingHost)
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
    func testAutomaticHeaderBootstrapNeverLaysOutConstrainedContentAtRequiredZeroHeight() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .automatic(min: 0, max: nil)
        let pager = AnchorPagerViewController(configuration: configuration)
        let header = ConstrainedLayoutRecordingHeaderView()
        let delegate = StubDelegate()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [UIViewController()],
            headerContent: .view(header)
        )
        pager.dataSource = dataSource
        pager.delegate = delegate
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()

        XCTAssertFalse(header.didLayoutAtRequiredZeroHeight)
        XCTAssertGreaterThan(
            try XCTUnwrap(delegate.layoutContexts.last).headerFrame.height,
            0
        )
    }

    @MainActor
    func testAutomaticHeaderBootstrapSeedsHostBeforeConstrainedContentAttachment() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .automatic(min: 0, max: nil)
        let pager = AnchorPagerViewController(configuration: configuration)
        let header = ConstrainedLayoutRecordingHeaderView()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [UIViewController()],
            headerContent: .view(header)
        )
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()

        XCTAssertGreaterThan(
            try XCTUnwrap(header.requiredHostHeightWhenAttached),
            0
        )
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
        setContainerLogicalOffset(30, in: pager)

        headerView.measuredHeight = 160
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)

        XCTAssertEqual(containerLogicalOffset(in: pager), 90, accuracy: 0.001)
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
        setContainerLogicalOffset(40, in: pager)

        headerView.measuredHeight = 180
        pager.reloadHeaderLayout(offsetAdjustment: .preserveCollapseProgress)

        XCTAssertEqual(containerLogicalOffset(in: pager), 80, accuracy: 0.001)
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
        setContainerLogicalOffset(40, in: pager)

        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        XCTAssertEqual(containerLogicalOffset(in: pager), 0, accuracy: 0.001)

        setContainerLogicalOffset(40, in: pager)
        pager.reloadHeaderLayout(offsetAdjustment: .resetToCollapsed)
        XCTAssertEqual(containerLogicalOffset(in: pager), 80, accuracy: 0.001)
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
        setContainerLogicalOffset(48, in: pager)
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
        let expectedHeight = pager.verticalScrollView.bounds.height
            + 120
            - pager.verticalScrollView.contentInset.top

        XCTAssertEqual(pager.verticalScrollView.contentSize.height, expectedHeight, accuracy: 0.5)

        setContainerLogicalOffset(60, in: pager)
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()

        XCTAssertEqual(pager.verticalScrollView.contentSize.height, expectedHeight, accuracy: 0.5)
    }

    @MainActor
    func testHeaderReturnsToSafeAreaAfterTopBehaviorSwitchAndBounce() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.topBehavior = .insideSafeArea
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

        setContainerLogicalOffset(60, in: pager)
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        pager.configuration.header.topBehavior = .extendsUnderTopSafeArea
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        pager.configuration.header.topBehavior = .insideSafeArea
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()

        pager.verticalScrollView.contentOffset.y = rawContainerOffset(
            forLogicalOffset: 0,
            in: pager
        ) - 24
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        setContainerLogicalOffset(0, in: pager)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()

        let finalFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
        let context = try XCTUnwrap(delegate.layoutContexts.last)

        XCTAssertEqual(finalFrame.minY, initialFrame.minY, accuracy: 0.5)
        XCTAssertEqual(finalFrame.minY, context.headerFrame.minY, accuracy: 0.5)
    }

    @MainActor
    func testAutomaticHeaderHeightStaysStableAcrossTopBehaviorSwitchAndBounceSettlement() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.topBehavior = .insideSafeArea
        let pager = AnchorPagerViewController(configuration: configuration)
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
        pager.verticalScrollView.contentOffset.y = rawContainerOffset(
            forLogicalOffset: 0,
            in: pager
        ) - 24
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        setContainerLogicalOffset(0, in: pager)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()
        let finalContext = try XCTUnwrap(delegate.layoutContexts.last)

        XCTAssertEqual(finalContext.headerFrame.height, initialContext.headerFrame.height, accuracy: 0.5)
        XCTAssertEqual(finalContext.barFrame.minY, initialContext.barFrame.minY, accuracy: 0.5)
    }

    @MainActor
    func testStableCollapseKeepsHeaderHostHeightAndMovesCanonicalContentSurface() throws {
        let fixture = try FixedHeaderPresentationFixture(
            expandedHeaderHeight: 100,
            collapsedHeaderHeight: 20
        )
        defer { fixture.window.isHidden = true }
        let expanded = fixture.capturePresentation()

        fixture.setLogicalOffset(30)
        fixture.layout()
        let partial = fixture.capturePresentation()

        fixture.setLogicalOffset(80)
        fixture.layout()
        let collapsed = fixture.capturePresentation()

        XCTAssertEqual(
            [expanded.headerHeight, partial.headerHeight, collapsed.headerHeight],
            [100, 100, 100]
        )
        XCTAssertEqual(
            [
                expanded.headerRootHeight,
                partial.headerRootHeight,
                collapsed.headerRootHeight
            ],
            [100, 100, 100]
        )
        XCTAssertEqual(partial.headerMinY, expanded.headerMinY - 30, accuracy: 0.5)
        XCTAssertEqual(collapsed.headerMinY, expanded.headerMinY - 80, accuracy: 0.5)
        XCTAssertEqual(partial.viewportTransform, .identity)
        XCTAssertEqual(collapsed.viewportTransform, .identity)
        XCTAssertEqual(partial.contentPresentationTransform.ty, -30, accuracy: 0.5)
        XCTAssertEqual(collapsed.contentPresentationTransform.ty, -80, accuracy: 0.5)
    }

    @MainActor
    func testCanonicalSurfaceSitsBetweenViewportAndBothHosts() throws {
        let fixture = try FixedHeaderPresentationFixture()
        defer { fixture.window.isHidden = true }

        XCTAssertTrue(fixture.headerHost.superview === fixture.contentPresentationView)
        XCTAssertTrue(fixture.pagingHostView.superview === fixture.contentPresentationView)
        XCTAssertTrue(fixture.contentPresentationView.superview === fixture.viewportView)
        XCTAssertTrue(fixture.viewportView.superview === fixture.pager.verticalScrollView)
        XCTAssertFalse(fixture.viewportView === fixture.pager.verticalScrollView)
    }

    @MainActor
    func testStableCollapseKeepsPagingViewportHeightAndPlainPagePhysicalBottom() throws {
        let fixture = try FixedHeaderPresentationFixture(usesPlainPage: true)
        defer { fixture.window.isHidden = true }
        let expanded = fixture.capturePresentation()

        fixture.setLogicalOffset(fixture.collapsibleDistance)
        fixture.layout()
        let collapsed = fixture.capturePresentation()

        XCTAssertEqual(collapsed.pagingHeight, expanded.pagingHeight, accuracy: 0.5)
        XCTAssertEqual(
            collapsed.plainPageFrame.maxY,
            fixture.pager.view.bounds.maxY,
            accuracy: 0.5
        )
    }

    @MainActor
    func testCanonicalPresentationSurfaceInstallationLogsOnce() throws {
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        let fixture = try FixedHeaderPresentationFixture()
        defer { fixture.window.isHidden = true }

        fixture.pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        fixture.layout()

        XCTAssertEqual(
            events.filter { $0.event == "layout.headerPresentationInstalled" }.count,
            1
        )
    }

    @MainActor
    func testInsideSafeAreaOwnsRealContainerTopInsetAndRawBoundaries() throws {
        let fixture = try FixedHeaderPresentationFixture(
            topBehavior: .insideSafeArea
        )
        defer { fixture.window.isHidden = true }
        let inset = fixture.pager.verticalScrollView.contentInset.top

        XCTAssertGreaterThan(inset, 0)
        XCTAssertEqual(inset, fixture.topObstructionHeight, accuracy: 0.5)
        XCTAssertEqual(
            fixture.pager.verticalScrollView.adjustedContentInset.top,
            inset,
            accuracy: 0.5
        )
        XCTAssertEqual(fixture.pager.verticalScrollView.contentInset.left, 0)
        XCTAssertEqual(fixture.pager.verticalScrollView.contentInset.bottom, 0)
        XCTAssertEqual(fixture.pager.verticalScrollView.contentInset.right, 0)
        XCTAssertEqual(fixture.expandedRawOffset, -inset, accuracy: 0.5)
        XCTAssertEqual(
            fixture.collapsedRawOffset,
            fixture.collapsibleDistance - inset,
            accuracy: 0.5
        )
    }

    @MainActor
    func testExtendsUnderTopSafeAreaOwnsZeroContainerTopInset() throws {
        let fixture = try FixedHeaderPresentationFixture(
            topBehavior: .extendsUnderTopSafeArea
        )
        defer { fixture.window.isHidden = true }

        XCTAssertEqual(
            fixture.pager.verticalScrollView.contentInset.top,
            0,
            accuracy: 0.001
        )
    }

    @MainActor
    func testContainerRangeIsViewportPlusCollapseMinusTopInset() throws {
        let fixture = try FixedHeaderPresentationFixture(
            topBehavior: .insideSafeArea
        )
        defer { fixture.window.isHidden = true }
        let expected = max(
            0,
            fixture.pager.verticalScrollView.bounds.height
                + fixture.collapsibleDistance
                - fixture.pager.verticalScrollView.contentInset.top
        )

        XCTAssertEqual(
            fixture.pager.verticalScrollView.contentSize.height,
            expected,
            accuracy: 0.5
        )
    }

    @MainActor
    func testSwitchingTopBehaviorPreservesLogicalOffsetAndBarPresentation() throws {
        let fixture = try FixedHeaderPresentationFixture(
            topBehavior: .insideSafeArea
        )
        defer { fixture.window.isHidden = true }
        fixture.setLogicalOffset(40)
        fixture.layout()
        let before = fixture.capturePresentation()

        fixture.setHeaderTopBehavior(.extendsUnderTopSafeArea)
        fixture.layout()
        let after = fixture.capturePresentation()

        XCTAssertEqual(after.logicalContainerOffset, 40, accuracy: 0.5)
        XCTAssertEqual(after.rawContainerOffset, 40, accuracy: 0.5)
        XCTAssertEqual(after.barMinY, before.barMinY, accuracy: 0.5)
    }

    @MainActor
    func testZeroCollapseDistanceHasSingleInsetAwareRawBoundary() throws {
        let fixture = try FixedHeaderPresentationFixture(
            topBehavior: .insideSafeArea,
            expandedHeaderHeight: 20,
            collapsedHeaderHeight: 20
        )
        defer { fixture.window.isHidden = true }
        let inset = fixture.pager.verticalScrollView.contentInset.top

        XCTAssertGreaterThan(inset, 0)
        XCTAssertEqual(fixture.collapsibleDistance, 0, accuracy: 0.001)
        XCTAssertEqual(fixture.expandedRawOffset, -inset, accuracy: 0.5)
        XCTAssertEqual(fixture.collapsedRawOffset, -inset, accuracy: 0.5)
        XCTAssertEqual(
            fixture.pager.verticalScrollView.contentSize.height,
            fixture.pager.verticalScrollView.bounds.height - inset,
            accuracy: 0.5
        )
    }

    @MainActor
    func testAdditionalSafeAreaChangePreservesLogicalOffsetAndCollapseProgress() throws {
        let fixture = try FixedHeaderPresentationFixture(
            topBehavior: .insideSafeArea
        )
        defer { fixture.window.isHidden = true }
        fixture.setLogicalOffset(40)
        fixture.layout()

        fixture.pager.additionalSafeAreaInsets.top = 24
        fixture.layout()
        let first = fixture.capturePresentation()

        fixture.pager.additionalSafeAreaInsets.top = 40
        fixture.layout()
        let second = fixture.capturePresentation()

        XCTAssertEqual(first.logicalContainerOffset, 40, accuracy: 0.5)
        XCTAssertEqual(second.logicalContainerOffset, 40, accuracy: 0.5)
        XCTAssertEqual(first.contentPresentationTransform.ty, -40, accuracy: 0.5)
        XCTAssertEqual(second.contentPresentationTransform.ty, -40, accuracy: 0.5)
        XCTAssertEqual(
            second.rawContainerOffset,
            40 - fixture.pager.verticalScrollView.contentInset.top,
            accuracy: 0.5
        )
    }

    @MainActor
    func testBoundsDrivenHeaderDistanceChangePreservesCollapseProgress() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .automatic(min: 0, max: nil)
        let pager = AnchorPagerViewController(configuration: configuration)
        let headerView = WidthSensitiveFittingView(
            compactHeight: 100,
            regularHeight: 140
        )
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [ScrollChildViewController()],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        pager.reloadData()
        window.layoutIfNeeded()
        pager.verticalScrollView.contentOffset.y = 50
            - pager.verticalScrollView.contentInset.top
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)

        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        pager.view.setNeedsLayout()
        window.layoutIfNeeded()

        XCTAssertEqual(
            pager.verticalScrollView.contentOffset.y
                + pager.verticalScrollView.contentInset.top,
            70,
            accuracy: 0.5
        )
    }

    @MainActor
    func testReloadHeaderLayoutStrategiesUseLogicalOffsetsWithContainerInset() throws {
        let cases: [(AnchorPagerHeaderOffsetAdjustment, CGFloat)] = [
            (.preserveVisualPosition, 80),
            (.preserveCollapseProgress, 60),
            (.resetToExpanded, 0),
            (.resetToCollapsed, 120)
        ]

        for (strategy, expectedLogicalOffset) in cases {
            var configuration = AnchorPagerConfiguration.default
            configuration.header.heightMode = .automatic(min: 20, max: nil)
            configuration.header.topBehavior = .insideSafeArea
            let pager = AnchorPagerViewController(configuration: configuration)
            let headerView = DynamicFittingView(height: 100)
            let dataSource = StubDataSource(
                count: 1,
                viewControllers: [ScrollChildViewController()],
                headerContent: .view(headerView)
            )
            pager.dataSource = dataSource
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = pager
            window.makeKeyAndVisible()
            pager.reloadData()
            window.layoutIfNeeded()
            XCTAssertGreaterThan(pager.verticalScrollView.contentInset.top, 0)
            pager.verticalScrollView.contentOffset.y = 40
                - pager.verticalScrollView.contentInset.top
            pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)

            headerView.measuredHeight = 140
            pager.reloadHeaderLayout(offsetAdjustment: strategy)
            window.layoutIfNeeded()

            XCTAssertEqual(
                pager.verticalScrollView.contentOffset.y
                    + pager.verticalScrollView.contentInset.top,
                expectedLogicalOffset,
                accuracy: 0.5,
                "strategy: \(strategy)"
            )
            window.isHidden = true
        }
    }

    @MainActor
    func testContainerTopInsetLogOnlyChangesWithResolvedInset() throws {
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        let fixture = try FixedHeaderPresentationFixture(
            topBehavior: .insideSafeArea
        )
        defer { fixture.window.isHidden = true }
        let initialCount = events.filter {
            $0.event == "inset.containerTopChanged"
        }.count
        XCTAssertGreaterThan(initialCount, 0)

        fixture.pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        fixture.layout()
        XCTAssertEqual(
            events.filter { $0.event == "inset.containerTopChanged" }.count,
            initialCount
        )

        fixture.setHeaderTopBehavior(.extendsUnderTopSafeArea)
        fixture.layout()
        XCTAssertEqual(
            events.filter { $0.event == "inset.containerTopChanged" }.count,
            initialCount + 1
        )

        fixture.pager.configuration.topOverscrollHandlingMode = .child
        fixture.layout()
        XCTAssertEqual(
            events.filter { $0.event == "inset.containerTopChanged" }.count,
            initialCount + 1
        )
    }

    @MainActor
    func testNegativeContainerOffsetTranslatesViewportAndLayoutContextWithoutChangingRange() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 120, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        let headerView = FixedFittingView(height: 120)
        let child = ScrollChildViewController()
        let delegate = StubDelegate()
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [child],
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
        let contentPresentationView = try XCTUnwrap(headerHostView.superview)
        let viewportView = try XCTUnwrap(contentPresentationView.superview)
        let initialFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
        let initialContext = try XCTUnwrap(delegate.layoutContexts.last)
        let initialChildFrameInWindow = child.view.convert(child.view.bounds, to: window)
        let initialContentSize = pager.verticalScrollView.contentSize
        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        let pageViewController = try XCTUnwrap(
            adapter.children.compactMap { $0 as? UIPageViewController }.first
        )

        pager.verticalScrollView.contentOffset.y = rawContainerOffset(
            forLogicalOffset: 0,
            in: pager
        ) - 24
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()
        let bouncedFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
        let bouncedContext = try XCTUnwrap(delegate.layoutContexts.last)

        XCTAssertEqual(bouncedFrame.minY, initialFrame.minY + 24, accuracy: 0.5)
        XCTAssertGreaterThan(viewportView.transform.ty, 0)
        XCTAssertEqual(contentPresentationView.transform, .identity)
        XCTAssertEqual(bouncedContext.headerFrame.minY, bouncedFrame.minY, accuracy: 0.5)
        XCTAssertEqual(
            bouncedContext.barFrame.minY,
            initialContext.barFrame.minY + 24,
            accuracy: 0.5
        )
        XCTAssertEqual(
            bouncedContext.contentFrame.minY,
            initialContext.contentFrame.minY + 24,
            accuracy: 0.5
        )
        XCTAssertEqual(pageViewController.view.transform, .identity)
        XCTAssertEqual(pager.verticalScrollView.contentSize, initialContentSize)
        XCTAssertTrue(delegate.collapseProgresses.isEmpty)

        setContainerLogicalOffset(0, in: pager)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()
        let restoredFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
        let restoredContext = try XCTUnwrap(delegate.layoutContexts.last)
        let restoredChildFrameInWindow = child.view.convert(child.view.bounds, to: window)

        XCTAssertEqual(restoredFrame.minY, initialFrame.minY, accuracy: 0.5)
        XCTAssertEqual(viewportView.transform, .identity)
        XCTAssertEqual(contentPresentationView.transform, .identity)
        XCTAssertEqual(restoredContext, initialContext)
        XCTAssertEqual(restoredChildFrameInWindow, initialChildFrameInWindow)
        XCTAssertGreaterThanOrEqual(restoredChildFrameInWindow.maxY, window.bounds.maxY - 1)
        XCTAssertEqual(pager.verticalScrollView.contentSize, initialContentSize)
    }

    @MainActor
    func testPlainBottomOverflowMovesOnlyPageSurfaceAndRestoresCanonicalChrome() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 100, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        let delegate = StubDelegate()
        let plainChild = UIViewController()
        let headerView = FixedFittingView(height: 100)
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [plainChild],
            headerContent: .view(headerView)
        )
        pager.delegate = delegate
        pager.dataSource = dataSource
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        let initialContentSize = pager.verticalScrollView.contentSize
        setContainerLogicalOffset(100, in: pager)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()
        let headerHostView = try XCTUnwrap(headerView.superview)
        let contentPresentationView = try XCTUnwrap(headerHostView.superview)
        let viewportView = try XCTUnwrap(contentPresentationView.superview)
        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        let pageViewController = try XCTUnwrap(
            adapter.children.compactMap { $0 as? UIPageViewController }.first
        )
        let collapsedContext = try XCTUnwrap(delegate.layoutContexts.last)
        let collapsedHeaderFrame = headerHostView.convert(
            headerHostView.bounds,
            to: pager.view
        )
        let collapsedPlainFrame = plainChild.view.convert(
            plainChild.view.bounds,
            to: pager.view
        )
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        pager.verticalScrollView.contentOffset.y = rawContainerOffset(
            forLogicalOffset: 124,
            in: pager
        )
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()

        let context = try XCTUnwrap(delegate.layoutContexts.last)
        let presentedPlainFrame = plainChild.view.convert(
            plainChild.view.bounds,
            to: pager.view
        )
        XCTAssertEqual(context.headerFrame, collapsedContext.headerFrame)
        XCTAssertEqual(context.barFrame, collapsedContext.barFrame)
        XCTAssertEqual(
            headerHostView.convert(headerHostView.bounds, to: pager.view),
            collapsedHeaderFrame
        )
        XCTAssertEqual(viewportView.transform, .identity)
        XCTAssertEqual(contentPresentationView.transform.ty, -100, accuracy: 0.5)
        XCTAssertEqual(pageViewController.view.transform.ty, -24, accuracy: 0.5)
        XCTAssertEqual(plainChild.view.transform, .identity)
        XCTAssertEqual(
            context.contentFrame.minY,
            collapsedContext.contentFrame.minY - 24,
            accuracy: 0.5
        )
        XCTAssertEqual(
            presentedPlainFrame.minY,
            collapsedPlainFrame.minY - 24,
            accuracy: 0.5
        )
        XCTAssertFalse(events.contains {
            $0.event == "paging.pagePresentation.unavailable"
        })
        XCTAssertEqual(pager.verticalScrollView.contentSize, initialContentSize)
        XCTAssertEqual(try XCTUnwrap(delegate.collapseProgresses.last), 1, accuracy: 0.001)

        setContainerLogicalOffset(100, in: pager)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()

        let restoredContext = try XCTUnwrap(delegate.layoutContexts.last)
        let restoredPlainFrame = plainChild.view.convert(
            plainChild.view.bounds,
            to: pager.view
        )
        XCTAssertEqual(restoredContext, collapsedContext)
        XCTAssertEqual(restoredPlainFrame, collapsedPlainFrame)
        XCTAssertEqual(viewportView.transform, .identity)
        XCTAssertEqual(contentPresentationView.transform.ty, -100, accuracy: 0.5)
        XCTAssertEqual(pageViewController.view.transform, .identity)
        XCTAssertEqual(plainChild.view.transform, .identity)
        XCTAssertEqual(pager.verticalScrollView.contentSize, initialContentSize)
    }

    @MainActor
    func testPlainBottomPresentationResetsBeforeSelection() throws {
        let fixture = try PlainBottomPresentationFixture(pageCount: 2)
        defer { fixture.window.isHidden = true }
        let surface = try fixture.presentBottomOverflow()
        XCTAssertEqual(surface.transform.ty, -24, accuracy: 0.5)

        fixture.pager.setSelectedIndex(1, animated: false)

        XCTAssertEqual(surface.transform, .identity)
    }

    @MainActor
    func testPlainBottomPresentationResetsBeforeReloadHeaderLayout() throws {
        let fixture = try PlainBottomPresentationFixture()
        defer { fixture.window.isHidden = true }
        let surface = try fixture.presentBottomOverflow()
        XCTAssertEqual(surface.transform.ty, -24, accuracy: 0.5)

        fixture.pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)

        XCTAssertEqual(surface.transform, .identity)
    }

    @MainActor
    func testPlainBottomPresentationResetsBeforeSizeTransition() throws {
        let fixture = try PlainBottomPresentationFixture()
        defer { fixture.window.isHidden = true }
        let surface = try fixture.presentBottomOverflow()
        XCTAssertEqual(surface.transform.ty, -24, accuracy: 0.5)

        fixture.pager.viewWillTransition(
            to: CGSize(width: 844, height: 390),
            with: ImmediateTransitionCoordinator()
        )

        XCTAssertEqual(surface.transform, .identity)
    }

    @MainActor
    func testPlainBottomPresentationResetsBeforeEmptyReload() throws {
        let fixture = try PlainBottomPresentationFixture()
        defer { fixture.window.isHidden = true }
        let surface = try fixture.presentBottomOverflow()
        XCTAssertEqual(surface.transform.ty, -24, accuracy: 0.5)

        fixture.dataSource.count = 0
        fixture.dataSource.titles = []
        fixture.dataSource.viewControllers = []
        fixture.pager.reloadData()

        XCTAssertEqual(surface.transform, .identity)
        XCTAssertNil(fixture.host.activeAdapter)
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

        setContainerLogicalOffset(60, in: pager)
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
    func testHeaderScrollingMovesPagingPresentationWithoutChangingCanonicalHostOrChildHeight() throws {
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

        let pagingHost = try XCTUnwrap(installedPagingHost(in: pager))
        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        let expandedAdapterHeight = adapter.view.bounds.height
        let expandedChildHeight = child.view.bounds.height
        let expandedCanonicalMinY = pagingHost.view.frame.minY
        let expandedPresentedMinY = pagingHost.view.convert(
            pagingHost.view.bounds,
            to: pager.view
        ).minY

        setContainerLogicalOffset(100, in: pager)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()

        XCTAssertEqual(pagingHost.view.frame.minY, expandedCanonicalMinY, accuracy: 0.5)
        XCTAssertLessThan(
            pagingHost.view.convert(pagingHost.view.bounds, to: pager.view).minY,
            expandedPresentedMinY
        )
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

        setContainerLogicalOffset(50, in: pager)
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
            0,
            accuracy: 0.5
        )
        XCTAssertEqual(adapter.view.bounds.height, fixedAdapterHeight, accuracy: 0.5)
        XCTAssertEqual(child.view.bounds.height, fixedChildHeight, accuracy: 0.5)
        XCTAssertFalse(events.contains { $0.event == "inset.ownership.update" })

        setContainerLogicalOffset(100, in: pager)
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
            0,
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
    func testReloadDataProvidesPlainChildDirectlyToPagingAdapter() throws {
        let pager = AnchorPagerViewController()
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
        let page = adapter.viewController(for: adapter, at: 0)

        XCTAssertTrue(page === plainChild)
        XCTAssertNotNil(plainChild.parent)
        XCTAssertFalse(plainChild.parent is AnchorPagerViewController)
        XCTAssertTrue(plainChild.view.window === window)
    }

    @MainActor
    func testPlainPageRootReachesPagerAndWindowBottomWithoutFrameworkInsets() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 80, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        let plainChild = UIViewController()
        plainChild.additionalSafeAreaInsets = UIEdgeInsets(top: 3, left: 0, bottom: 7, right: 0)
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [plainChild],
            headerContent: .view(FixedFittingView(height: 80))
        )
        pager.dataSource = dataSource
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [pager]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        pager.reloadData()
        window.layoutIfNeeded()
        let pageFrameInPager = plainChild.view.convert(plainChild.view.bounds, to: pager.view)
        let pageFrameInWindow = plainChild.view.convert(plainChild.view.bounds, to: window)

        XCTAssertGreaterThanOrEqual(pageFrameInPager.maxY, pager.view.bounds.maxY - 1)
        XCTAssertGreaterThanOrEqual(pageFrameInWindow.maxY, window.bounds.maxY - 1)
        XCTAssertEqual(plainChild.additionalSafeAreaInsets.top, 3, accuracy: 0.001)
        XCTAssertEqual(plainChild.additionalSafeAreaInsets.bottom, 7, accuracy: 0.001)
    }

    @MainActor
    func testCommittedPlainPageBindsNoChildPanAndContainerStillCollapses() throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 100, min: 0)
        let pager = AnchorPagerViewController(configuration: configuration)
        let dataSource = StubDataSource(count: 1, viewControllers: [UIViewController()])
        pager.dataSource = dataSource
        pager.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        pager.loadViewIfNeeded()
        pager.reloadData()
        pager.view.layoutIfNeeded()
        let container = try XCTUnwrap(
            pager.verticalScrollView as? AnchorPagerContainerScrollView
        )
        let unrelatedPan = UIPanGestureRecognizer()

        XCTAssertFalse(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: unrelatedPan
        ))

        setContainerLogicalOffset(60, in: pager)
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        XCTAssertEqual(containerLogicalOffset(in: pager), 60, accuracy: 0.5)
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

        guard let adapter = installedAdapter(in: pager) else {
            XCTFail("reloadData 应安装分页 adapter。")
            return
        }

        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === scrollChild)
    }

    @MainActor
    func testReloadDataFromScrollPageToEmptyRemovesPagingContentAndReleasesInsetOwnership() throws {
        let child = ScrollChildViewController()
        child.loadViewIfNeeded()
        child.scrollView.contentInsetAdjustmentBehavior = .always
        child.scrollView.contentInset = UIEdgeInsets(top: 7, left: 0, bottom: 11, right: 0)
        child.scrollView.automaticallyAdjustsScrollIndicatorInsets = true
        let dataSource = StubDataSource(count: 1, viewControllers: [child])
        let pager = AnchorPagerViewController()
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()

        let pagingHost = try XCTUnwrap(installedPagingHost(in: pager))
        try autoreleasepool {
            let adapter = try XCTUnwrap(pagingHost.activeAdapter)
            XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === child)
            XCTAssertNotNil(child.parent)
            XCTAssertEqual(child.scrollView.contentInsetAdjustmentBehavior, .never)
        }

        dataSource.count = 0
        dataSource.titles = []
        dataSource.viewControllers = []
        autoreleasepool {
            pager.reloadData()
        }

        XCTAssertNil(pager.effectiveSelectedIndex)
        XCTAssertNil(pagingHost.activeAdapter)
        XCTAssertNil(child.parent)
        XCTAssertNil(child.view.superview)
        XCTAssertEqual(child.scrollView.contentInsetAdjustmentBehavior, .always)
        XCTAssertTrue(child.scrollView.automaticallyAdjustsScrollIndicatorInsets)
        XCTAssertEqual(child.scrollView.contentInset.top, 7, accuracy: 0.5)
        XCTAssertEqual(child.scrollView.contentInset.bottom, 11, accuracy: 0.5)
    }

    @MainActor
    func testReloadDataFromPlainPageToEmptyRemovesPagingContainment() throws {
        let child = UIViewController()
        let dataSource = StubDataSource(count: 1, viewControllers: [child])
        let pager = AnchorPagerViewController()
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()

        let pagingHost = try XCTUnwrap(installedPagingHost(in: pager))
        try autoreleasepool {
            let adapter = try XCTUnwrap(pagingHost.activeAdapter)
            XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === child)
            XCTAssertNotNil(child.parent)
            XCTAssertFalse(child.parent is AnchorPagerViewController)
        }

        dataSource.count = 0
        dataSource.titles = []
        dataSource.viewControllers = []
        autoreleasepool {
            pager.reloadData()
        }

        XCTAssertNil(pager.effectiveSelectedIndex)
        XCTAssertNil(pagingHost.activeAdapter)
        XCTAssertNil(child.parent)
        XCTAssertNil(child.view.superview)
    }

    @MainActor
    func testReloadDataFromEmptyToNonEmptyInstallsAdapterUnderStablePagingHost() throws {
        let child = ScrollChildViewController()
        let dataSource = StubDataSource(count: 0, titles: [], viewControllers: [])
        let pager = AnchorPagerViewController()
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()

        let pagingHost = try XCTUnwrap(installedPagingHost(in: pager))
        XCTAssertTrue(pagingHost.parent === pager)
        XCTAssertNil(pagingHost.activeAdapter)

        dataSource.count = 1
        dataSource.titles = ["Page 0"]
        dataSource.viewControllers = [child]
        pager.reloadData()

        let adapter = try XCTUnwrap(pagingHost.activeAdapter)
        XCTAssertTrue(adapter.parent === pagingHost)
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === child)
        XCTAssertEqual(pager.effectiveSelectedIndex, 0)
    }

    @MainActor
    func testRepeatedEmptyReloadKeepsStablePagingHostWithoutAdapter() throws {
        let dataSource = StubDataSource(count: 0, titles: [], viewControllers: [])
        let pager = AnchorPagerViewController()
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()

        let pagingHost = try XCTUnwrap(installedPagingHost(in: pager))

        pager.reloadData()

        XCTAssertTrue(pagingHost.parent === pager)
        XCTAssertNil(pagingHost.activeAdapter)
        XCTAssertNil(pager.effectiveSelectedIndex)
    }

    @MainActor
    func testNonEmptyReloadReusesAdapterAndReplacesCommittedPageGeneration() throws {
        let oldChild = ScrollChildViewController()
        let replacementChild = ScrollChildViewController()
        let dataSource = StubDataSource(count: 1, viewControllers: [oldChild])
        let pager = AnchorPagerViewController()
        pager.dataSource = dataSource
        pager.loadViewIfNeeded()
        pager.reloadData()

        let pagingHost = try XCTUnwrap(installedPagingHost(in: pager))
        let adapter = try XCTUnwrap(pagingHost.activeAdapter)
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === oldChild)

        dataSource.viewControllers = [replacementChild]
        pager.reloadData()

        XCTAssertTrue(pagingHost.activeAdapter === adapter)
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === replacementChild)
        XCTAssertNil(oldChild.parent)
        XCTAssertNil(oldChild.view.superview)
        XCTAssertEqual(pager.effectiveSelectedIndex, 0)
    }

    @MainActor
    func testReloadDataReplacesStalePlainPageThroughPagingAdapter() throws {
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

        let adapter = try XCTUnwrap(installedAdapter(in: pager))
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === stalePlainChild)
        XCTAssertNotNil(stalePlainChild.parent)

        dataSource.viewControllers = [replacementPlainChild]
        pager.reloadData()

        XCTAssertNil(stalePlainChild.parent)
        XCTAssertNil(stalePlainChild.view.superview)
        XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === replacementPlainChild)
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
            guard installedAdapter(in: pager) != nil,
                  let pagingHost = installedPagingHost(in: pager) else {
                XCTFail("reloadData 应安装稳定 paging host 和分页 adapter。")
                return
            }
            pager.pagingHost(
                pagingHost,
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
    func testDeinitResetsPagePresentationSurface() throws {
        let dataSource = StubDataSource(
            count: 1,
            viewControllers: [UIViewController()]
        )
        weak var weakPager: AnchorPagerViewController?
        var pageSurface: UIView?

        try autoreleasepool {
            let pager = AnchorPagerViewController()
            weakPager = pager
            pager.dataSource = dataSource
            pager.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            pager.loadViewIfNeeded()
            pager.reloadData()
            pager.view.layoutIfNeeded()
            let pagingHost = try XCTUnwrap(installedPagingHost(in: pager))
            let adapter = try XCTUnwrap(pagingHost.activeAdapter)
            let pageViewController = try XCTUnwrap(
                adapter.children.compactMap { $0 as? UIPageViewController }.first
            )
            pageSurface = pageViewController.view

            XCTAssertTrue(pagingHost.setPagePresentationTranslationY(-24))
            XCTAssertEqual(try XCTUnwrap(pageSurface).transform.ty, -24, accuracy: 0.5)
        }

        XCTAssertNil(weakPager)
        XCTAssertEqual(try XCTUnwrap(pageSurface).transform, .identity)
    }

    @MainActor
    func testSharedExplicitScrollTargetUsesOriginalLaterPageWithNilBindingAndWritesLog() throws {
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
        XCTAssertTrue(pages.1 === second)
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
    func testConfigurationDefaultsUseExtendedHeaderTopBehavior() {
        let constructedHeader = AnchorPagerHeaderConfiguration()
        let defaultHeader = AnchorPagerHeaderConfiguration.default
        let constructedConfiguration = AnchorPagerConfiguration()
        let defaultConfiguration = AnchorPagerConfiguration.default
        let pager = AnchorPagerViewController()
        let explicitInside = AnchorPagerHeaderConfiguration(
            topBehavior: .insideSafeArea
        )

        XCTAssertEqual(constructedHeader.heightMode, .automatic(min: 0, max: nil))
        XCTAssertEqual(constructedHeader.topBehavior, .extendsUnderTopSafeArea)
        XCTAssertEqual(defaultHeader.topBehavior, .extendsUnderTopSafeArea)
        XCTAssertEqual(
            constructedConfiguration.header.topBehavior,
            .extendsUnderTopSafeArea
        )
        XCTAssertEqual(
            defaultConfiguration.header.topBehavior,
            .extendsUnderTopSafeArea
        )
        XCTAssertEqual(
            pager.configuration.header.topBehavior,
            .extendsUnderTopSafeArea
        )
        XCTAssertEqual(explicitInside.topBehavior, .insideSafeArea)
        XCTAssertNil(defaultConfiguration.bar.height)
        XCTAssertEqual(defaultConfiguration.topOverscrollHandlingMode, .container)
    }

    @MainActor
    func testRuntimeTopModeChangeCancelsContainerPresentationAndKeepsChildConfiguration() {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 100, min: 0)
        let child = ScrollChildViewController()
        child.loadViewIfNeeded()
        child.scrollView.bounces = false
        child.scrollView.alwaysBounceVertical = true
        let pager = AnchorPagerViewController(configuration: configuration)
        pager.dataSource = StubDataSource(
            count: 1,
            viewControllers: [child],
            headerContent: .view(FixedFittingView(height: 100))
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        pager.reloadData()
        window.layoutIfNeeded()
        pager.verticalScrollView.contentOffset.y = rawContainerOffset(
            forLogicalOffset: 0,
            in: pager
        ) - 20
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)

        pager.configuration.topOverscrollHandlingMode = .child
        window.layoutIfNeeded()

        XCTAssertEqual(containerLogicalOffset(in: pager), 0, accuracy: 0.5)
        XCTAssertFalse(child.scrollView.bounces)
        XCTAssertTrue(child.scrollView.alwaysBounceVertical)
    }

    @MainActor
    func testReloadDataSynchronouslyCancelsActiveContainerPresentationBeforeReadingDataSource() throws {
        let fixture = try TopOverscrollPresentationFixture()
        defer { fixture.window.isHidden = true }
        fixture.activateContainerPresentation()
        var observedCanonicalState = false
        fixture.dataSource.onNumberOfViewControllers = {
            fixture.assertCanonicalPresentationRestored()
            observedCanonicalState = true
        }

        fixture.pager.reloadData()

        XCTAssertTrue(observedCanonicalState)
        fixture.assertCanonicalPresentationRestored()
    }

    @MainActor
    func testReloadHeaderLayoutSynchronouslyCancelsActiveContainerPresentation() throws {
        let fixture = try TopOverscrollPresentationFixture()
        defer { fixture.window.isHidden = true }
        fixture.activateContainerPresentation()

        fixture.pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)

        fixture.assertCanonicalPresentationRestored()
    }

    @MainActor
    func testOnlyMatchingWillPerformReloadRequestSynchronouslyCancelsActiveContainerPresentation() throws {
        let fixture = try TopOverscrollPresentationFixture()
        defer { fixture.window.isHidden = true }
        let adapter = try XCTUnwrap(fixture.host.activeAdapter)
        adapter.pageboyViewController(
            adapter,
            willScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )
        fixture.replaceDataSourcePages(with: [ScrollChildViewController()])
        fixture.pager.reloadData()
        fixture.activateContainerPresentation()

        XCTAssertFalse(
            fixture.pager.pagingHost(
                fixture.host,
                willPerformReloadRequest: 999
            )
        )
        fixture.assertContainerPresentationIsActive()

        XCTAssertTrue(
            fixture.pager.pagingHost(
                fixture.host,
                willPerformReloadRequest: 2
            )
        )
        fixture.assertCanonicalPresentationRestored()
    }

    @MainActor
    func testWillSelectSynchronouslyCancelsActiveContainerPresentation() throws {
        let fixture = try TopOverscrollPresentationFixture()
        defer { fixture.window.isHidden = true }
        fixture.activateContainerPresentation()

        fixture.pager.pagingHost(fixture.host, willSelect: 1, animated: true)

        fixture.assertCanonicalPresentationRestored()
    }

    @MainActor
    func testSelectionCompletionWithoutWillSelectCancelsPlainBottomPresentation() throws {
        let fixture = try PlainBottomPresentationFixture(pageCount: 2)
        defer { fixture.window.isHidden = true }
        let surface = try fixture.presentBottomOverflow()
        XCTAssertEqual(surface.transform.ty, -24, accuracy: 0.5)

        fixture.pager.pagingHost(fixture.host, didSelect: 1, animated: false)

        XCTAssertEqual(surface.transform, .identity)
    }

    @MainActor
    func testViewWillTransitionSynchronouslyCancelsActiveContainerPresentation() throws {
        let fixture = try TopOverscrollPresentationFixture()
        defer { fixture.window.isHidden = true }
        fixture.activateContainerPresentation()

        fixture.pager.viewWillTransition(
            to: CGSize(width: 844, height: 390),
            with: ImmediateTransitionCoordinator()
        )

        fixture.assertCanonicalPresentationRestored()
    }

    @MainActor
    func testSafeAreaChangeCancelsActiveContainerPresentationWhenTopInsetStaysZero() throws {
        let fixture = try TopOverscrollPresentationFixture(
            topBehavior: .extendsUnderTopSafeArea
        )
        defer { fixture.window.isHidden = true }
        fixture.activateContainerPresentation()

        fixture.pager.additionalSafeAreaInsets.top = 100
        fixture.pager.viewSafeAreaInsetsDidChange()
        fixture.window.layoutIfNeeded()

        fixture.assertCanonicalPresentationRestored()
    }

    @MainActor
    func testBoundsChangeCancelsActiveContainerPresentationWhenDistanceIsUnchanged() throws {
        let fixture = try TopOverscrollPresentationFixture(
            topBehavior: .extendsUnderTopSafeArea
        )
        defer { fixture.window.isHidden = true }
        fixture.activateContainerPresentation()

        fixture.pager.view.bounds.size = CGSize(width: 430, height: 780)
        fixture.pager.viewDidLayoutSubviews()

        fixture.assertCanonicalPresentationRestored(checksHeaderFrame: false)
    }

    @MainActor
    func testReloadTerminalRebindsCommittedScrollOnlyAfterPendingGenerationCommits() throws {
        let fixture = try TopOverscrollPresentationFixture()
        defer { fixture.window.isHidden = true }
        let pendingPage = ScrollChildViewController()
        let oldFirst = try XCTUnwrap(fixture.pages.first)
        try fixture.activatePendingProvider(with: pendingPage)

        fixture.assertOnlyScrollViewIsBound(
            oldFirst.scrollView,
            insteadOf: pendingPage.scrollView
        )

        XCTAssertTrue(
            fixture.pager.pagingHost(
                fixture.host,
                didReload: .page(index: 0),
                finalBarInsets: .zero,
                requestIdentifier: 2
            )
        )

        fixture.assertOnlyScrollViewIsBound(
            pendingPage.scrollView,
            insteadOf: oldFirst.scrollView
        )
    }

    @MainActor
    func testSelectionTerminalRebindsCommittedGenerationInsteadOfPendingProvider() throws {
        let fixture = try TopOverscrollPresentationFixture()
        defer { fixture.window.isHidden = true }
        let pendingPage = ScrollChildViewController()
        let oldSecond = try XCTUnwrap(fixture.pages.dropFirst().first)
        try fixture.activatePendingProvider(with: pendingPage)

        fixture.pager.pagingHost(fixture.host, didSelect: 1, animated: true)

        fixture.assertOnlyScrollViewIsBound(
            oldSecond.scrollView,
            insteadOf: pendingPage.scrollView
        )
    }

    @MainActor
    func testSelectionCancelRebindsCommittedGenerationInsteadOfPendingProvider() throws {
        let fixture = try TopOverscrollPresentationFixture()
        defer { fixture.window.isHidden = true }
        let pendingPage = ScrollChildViewController()
        let oldFirst = try XCTUnwrap(fixture.pages.first)
        try fixture.activatePendingProvider(with: pendingPage)

        fixture.pager.pagingHost(
            fixture.host,
            didCancelSelectionAt: 1,
            returningTo: 0
        )

        fixture.assertOnlyScrollViewIsBound(
            oldFirst.scrollView,
            insteadOf: pendingPage.scrollView
        )
    }

    @MainActor
    private func rawContainerOffset(
        forLogicalOffset logicalOffset: CGFloat,
        in pager: AnchorPagerViewController
    ) -> CGFloat {
        logicalOffset - pager.verticalScrollView.contentInset.top
    }

    @MainActor
    private func containerLogicalOffset(
        in pager: AnchorPagerViewController
    ) -> CGFloat {
        pager.verticalScrollView.contentOffset.y
            + pager.verticalScrollView.contentInset.top
    }

    @MainActor
    private func setContainerLogicalOffset(
        _ logicalOffset: CGFloat,
        in pager: AnchorPagerViewController
    ) {
        pager.verticalScrollView.contentOffset.y = rawContainerOffset(
            forLogicalOffset: logicalOffset,
            in: pager
        )
    }

    @MainActor
    private func installedAdapter(in pager: AnchorPagerViewController) -> AnchorPagerPagingAdapter? {
        installedPagingHost(in: pager)?.activeAdapter
    }

    @MainActor
    private func installedPagingHost(
        in pager: AnchorPagerViewController
    ) -> AnchorPagerPagingHostViewController? {
        pager.children.compactMap { $0 as? AnchorPagerPagingHostViewController }.first
    }
}

@MainActor
private final class FixedHeaderPresentationFixture {
    struct Snapshot {
        let headerHeight: CGFloat
        let headerMinY: CGFloat
        let pagingHeight: CGFloat
        let plainPageFrame: CGRect
        let viewportTransform: CGAffineTransform
        let contentPresentationTransform: CGAffineTransform
        let rawContainerOffset: CGFloat
        let logicalContainerOffset: CGFloat
        let barMinY: CGFloat
        let headerRootHeight: CGFloat
    }

    let pager: AnchorPagerViewController
    let dataSource: StubDataSource
    let window: UIWindow
    let headerView: FixedFittingView
    let headerHost: UIView
    let contentPresentationView: UIView
    let viewportView: UIView
    let pagingHostView: UIView
    let collapsibleDistance: CGFloat

    var topObstructionHeight: CGFloat {
        max(
            pager.view.safeAreaLayoutGuide.layoutFrame.minY - pager.view.bounds.minY,
            pager.view.safeAreaInsets.top,
            pager.additionalSafeAreaInsets.top
        )
    }

    var expandedRawOffset: CGFloat {
        -pager.verticalScrollView.contentInset.top
    }

    var collapsedRawOffset: CGFloat {
        collapsibleDistance - pager.verticalScrollView.contentInset.top
    }

    private let page: UIViewController

    init(
        topBehavior: AnchorPagerHeaderTopBehavior = .insideSafeArea,
        expandedHeaderHeight: CGFloat = 100,
        collapsedHeaderHeight: CGFloat = 20,
        usesPlainPage: Bool = false
    ) throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(
            max: expandedHeaderHeight,
            min: collapsedHeaderHeight
        )
        configuration.header.topBehavior = topBehavior
        collapsibleDistance = max(0, expandedHeaderHeight - collapsedHeaderHeight)
        headerView = FixedFittingView(height: expandedHeaderHeight)
        page = usesPlainPage ? UIViewController() : ScrollChildViewController()
        pager = AnchorPagerViewController(configuration: configuration)
        dataSource = StubDataSource(
            count: 1,
            viewControllers: [page],
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        pager.reloadData()
        window.layoutIfNeeded()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        window.layoutIfNeeded()

        headerHost = try XCTUnwrap(headerView.superview)
        contentPresentationView = try XCTUnwrap(headerHost.superview)
        viewportView = try XCTUnwrap(contentPresentationView.superview)
        let pagingHost = try XCTUnwrap(
            pager.children.compactMap {
                $0 as? AnchorPagerPagingHostViewController
            }.first
        )
        pagingHostView = pagingHost.view
    }

    func setLogicalOffset(_ logicalOffset: CGFloat) {
        pager.verticalScrollView.contentOffset.y = logicalOffset
            - pager.verticalScrollView.contentInset.top
    }

    func setHeaderTopBehavior(_ behavior: AnchorPagerHeaderTopBehavior) {
        pager.configuration.header.topBehavior = behavior
    }

    func layout() {
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()
    }

    func capturePresentation() -> Snapshot {
        Snapshot(
            headerHeight: headerHost.bounds.height,
            headerMinY: headerHost.convert(headerHost.bounds, to: pager.view).minY,
            pagingHeight: pagingHostView.bounds.height,
            plainPageFrame: page.view.convert(page.view.bounds, to: pager.view),
            viewportTransform: viewportView.transform,
            contentPresentationTransform: contentPresentationView.transform,
            rawContainerOffset: pager.verticalScrollView.contentOffset.y,
            logicalContainerOffset: pager.verticalScrollView.contentOffset.y
                + pager.verticalScrollView.contentInset.top,
            barMinY: pagingHostView.convert(pagingHostView.bounds, to: pager.view).minY,
            headerRootHeight: headerView.bounds.height
        )
    }
}

@MainActor
private final class PlainBottomPresentationFixture {
    let pager: AnchorPagerViewController
    let dataSource: StubDataSource
    let window: UIWindow
    let host: AnchorPagerPagingHostViewController

    init(pageCount: Int = 1) throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 100, min: 0)
        pager = AnchorPagerViewController(configuration: configuration)
        let pages = (0..<pageCount).map { _ in UIViewController() }
        dataSource = StubDataSource(
            count: pageCount,
            viewControllers: pages,
            headerContent: .view(FixedFittingView(height: 100))
        )
        pager.dataSource = dataSource
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        pager.reloadData()
        window.layoutIfNeeded()
        host = try XCTUnwrap(
            pager.children.compactMap {
                $0 as? AnchorPagerPagingHostViewController
            }.first
        )
    }

    func presentBottomOverflow() throws -> UIView {
        let topInset = pager.verticalScrollView.contentInset.top
        pager.verticalScrollView.contentOffset.y = 100 - topInset
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()
        pager.verticalScrollView.contentOffset.y = 124 - topInset
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        window.layoutIfNeeded()
        let adapter = try XCTUnwrap(host.activeAdapter)
        let pageViewController = try XCTUnwrap(
            adapter.children.compactMap { $0 as? UIPageViewController }.first
        )
        return pageViewController.view
    }
}

@MainActor
private final class TopOverscrollPresentationFixture {
    let pager: AnchorPagerViewController
    let dataSource: StubDataSource
    let pages: [ScrollChildViewController]
    let headerView: FixedFittingView
    let window: UIWindow
    let host: AnchorPagerPagingHostViewController

    private let headerHostView: UIView
    private let contentPresentationView: UIView
    private let viewportView: UIView
    private let canonicalHeaderFrame: CGRect
    private let overflowDistance: CGFloat = 24

    init(
        topBehavior: AnchorPagerHeaderTopBehavior = .insideSafeArea
    ) throws {
        var configuration = AnchorPagerConfiguration.default
        configuration.header.heightMode = .fixed(max: 100, min: 0)
        configuration.header.topBehavior = topBehavior
        pages = [ScrollChildViewController(), ScrollChildViewController()]
        for page in pages {
            page.loadViewIfNeeded()
            page.scrollView.contentSize = CGSize(width: 390, height: 1_600)
        }
        headerView = FixedFittingView(height: 100)
        pager = AnchorPagerViewController(configuration: configuration)
        dataSource = StubDataSource(
            count: pages.count,
            viewControllers: pages,
            headerContent: .view(headerView)
        )
        pager.dataSource = dataSource
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = pager
        window.makeKeyAndVisible()
        pager.reloadData()
        window.layoutIfNeeded()
        pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        window.layoutIfNeeded()

        host = try XCTUnwrap(
            pager.children.compactMap {
                $0 as? AnchorPagerPagingHostViewController
            }.first
        )
        let adapter = try XCTUnwrap(host.activeAdapter)
        for index in pages.indices {
            _ = adapter.viewController(for: adapter, at: index)
        }
        headerHostView = try XCTUnwrap(headerView.superview)
        contentPresentationView = try XCTUnwrap(headerHostView.superview)
        viewportView = try XCTUnwrap(contentPresentationView.superview)
        canonicalHeaderFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
    }

    func activateContainerPresentation(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        pager.verticalScrollView.contentOffset.y = expandedRawOffset - overflowDistance
        pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
        assertContainerPresentationIsActive(file: file, line: line)
    }

    func assertContainerPresentationIsActive(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            pager.verticalScrollView.contentOffset.y,
            expandedRawOffset - overflowDistance,
            accuracy: 0.5,
            file: file,
            line: line
        )
        XCTAssertEqual(
            viewportView.transform.ty,
            overflowDistance,
            accuracy: 0.5,
            file: file,
            line: line
        )
        XCTAssertEqual(
            contentPresentationView.transform,
            .identity,
            file: file,
            line: line
        )
    }

    func assertCanonicalPresentationRestored(
        checksHeaderFrame: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            pager.verticalScrollView.contentOffset.y,
            expandedRawOffset,
            accuracy: 0.5,
            file: file,
            line: line
        )
        XCTAssertEqual(viewportView.transform.a, 1, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(viewportView.transform.b, 0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(viewportView.transform.c, 0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(viewportView.transform.d, 1, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(viewportView.transform.tx, 0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(viewportView.transform.ty, 0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(
            contentPresentationView.transform,
            .identity,
            file: file,
            line: line
        )
        if checksHeaderFrame {
            XCTAssertEqual(
                currentHeaderFrame.minY,
                canonicalHeaderFrame.minY,
                accuracy: 0.5,
                file: file,
                line: line
            )
        }
    }

    func replaceDataSourcePages(with replacements: [ScrollChildViewController]) {
        for replacement in replacements {
            replacement.loadViewIfNeeded()
            replacement.scrollView.contentSize = CGSize(width: 390, height: 1_600)
        }
        dataSource.count = replacements.count
        dataSource.titles = replacements.indices.map { "Replacement \($0)" }
        dataSource.viewControllers = replacements
    }

    func activatePendingProvider(with pendingPage: ScrollChildViewController) throws {
        let adapter = try XCTUnwrap(host.activeAdapter)
        adapter.pageboyViewController(
            adapter,
            willScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )
        replaceDataSourcePages(with: [pendingPage])
        pager.reloadData()
        XCTAssertTrue(
            pager.pagingHost(host, willPerformReloadRequest: 2),
            "测试前置条件要求激活匹配的 pending provider generation。"
        )
        XCTAssertTrue(pager.pageViewController(at: 0) === pendingPage)
    }

    func assertOnlyScrollViewIsBound(
        _ expected: UIScrollView,
        insteadOf other: UIScrollView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        pager.verticalScrollView.contentOffset.y = expandedRawOffset
        let expectedTop = -expected.contentInset.top
        expected.contentOffset.y = expectedTop + 20
        XCTAssertEqual(
            expected.contentOffset.y,
            expectedTop,
            accuracy: 0.5,
            file: file,
            line: line
        )

        let otherTop = -other.contentInset.top
        other.contentOffset.y = otherTop + 20
        XCTAssertEqual(
            other.contentOffset.y,
            otherTop + 20,
            accuracy: 0.5,
            file: file,
            line: line
        )
        other.contentOffset.y = otherTop
    }

    private var currentHeaderFrame: CGRect {
        headerHostView.convert(headerHostView.bounds, to: pager.view)
    }

    private var expandedRawOffset: CGFloat {
        -pager.verticalScrollView.contentInset.top
    }
}

@MainActor
private final class ImmediateTransitionCoordinator: NSObject,
    UIViewControllerTransitionCoordinator {
    let isAnimated = false
    let presentationStyle: UIModalPresentationStyle = .none
    let initiallyInteractive = false
    let isInterruptible = false
    let isInteractive = false
    let isCancelled = false
    let transitionDuration: TimeInterval = 0
    let percentComplete: CGFloat = 1
    let completionVelocity: CGFloat = 1
    let completionCurve: UIView.AnimationCurve = .linear
    let containerView = UIView()
    let targetTransform = CGAffineTransform.identity

    func viewController(
        forKey key: UITransitionContextViewControllerKey
    ) -> UIViewController? {
        nil
    }

    func view(forKey key: UITransitionContextViewKey) -> UIView? {
        nil
    }

    func animate(
        alongsideTransition animation: (
            (any UIViewControllerTransitionCoordinatorContext) -> Void
        )?,
        completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?
    ) -> Bool {
        animation?(self)
        completion?(self)
        return true
    }

    func animateAlongsideTransition(
        in view: UIView?,
        animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
        completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?
    ) -> Bool {
        animation?(self)
        completion?(self)
        return true
    }

    func notifyWhenInteractionEnds(
        _ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void
    ) {
        handler(self)
    }

    func notifyWhenInteractionChanges(
        _ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void
    ) {
        handler(self)
    }
}

@MainActor
private final class StubDataSource: AnchorPagerViewControllerDataSource {
    var count: Int
    var titles: [String]
    var viewControllers: [UIViewController]
    var headerContent: AnchorPagerHeaderContent
    var requestedViewControllerIndexes: [Int] = []
    var requestedTitleIndexes: [Int] = []
    var numberOfViewControllersCallCount = 0
    var headerContentCallCount = 0
    var onNumberOfViewControllers: (() -> Void)?
    var onTitle: (() -> Void)?
    var onHeaderContent: (() -> Void)?
    var onViewController: (() -> Void)?

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
        numberOfViewControllersCallCount += 1
        let result = count
        let hook = onNumberOfViewControllers
        onNumberOfViewControllers = nil
        hook?()
        return result
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        titleForViewControllerAt index: Int
    ) -> String {
        requestedTitleIndexes.append(index)
        let result = titles.indices.contains(index) ? titles[index] : "Page \(index)"
        let hook = onTitle
        onTitle = nil
        hook?()
        return result
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        viewControllerAt index: Int
    ) -> UIViewController {
        requestedViewControllerIndexes.append(index)
        let result = viewControllers.indices.contains(index) ? viewControllers[index] : UIViewController()
        let hook = onViewController
        onViewController = nil
        hook?()
        return result
    }

    func headerContent(in pagerViewController: AnchorPagerViewController) -> AnchorPagerHeaderContent {
        headerContentCallCount += 1
        let result = headerContent
        let hook = onHeaderContent
        onHeaderContent = nil
        hook?()
        return result
    }

    func resetCallbackRecords() {
        requestedViewControllerIndexes.removeAll()
        requestedTitleIndexes.removeAll()
        numberOfViewControllersCallCount = 0
        headerContentCallCount = 0
    }
}

@MainActor
private final class StubDelegate: AnchorPagerViewControllerDelegate {
    var selectedIndexes: [Int] = []
    var collapseProgresses: [CGFloat] = []
    var layoutContexts: [AnchorPagerLayoutContext] = []
    var onLayout: ((AnchorPagerLayoutContext) -> Void)?

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
        onLayout?(context)
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

private final class WidthSensitiveFittingView: UIView {
    private let compactHeight: CGFloat
    private let regularHeight: CGFloat

    init(compactHeight: CGFloat, regularHeight: CGFloat) {
        self.compactHeight = compactHeight
        self.regularHeight = regularHeight
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        CGSize(
            width: targetSize.width,
            height: targetSize.width >= 500 ? regularHeight : compactHeight
        )
    }
}

private final class ConstrainedLayoutRecordingHeaderView: UIView {
    private(set) var didLayoutAtRequiredZeroHeight = false
    private(set) var requiredHostHeightWhenAttached: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            contentView.bottomAnchor.constraint(
                lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor,
                constant: -20
            ),
            contentView.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard let hostView = superview else { return }
        requiredHostHeightWhenAttached = hostView.constraints.first { constraint in
            constraint.isActive
                && constraint.priority == .required
                && (constraint.firstItem as? UIView) === hostView
                && constraint.firstAttribute == .height
                && constraint.secondItem == nil
        }?.constant
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if window != nil, bounds.width > 1, bounds.height <= 0.5 {
            didLayoutAtRequiredZeroHeight = true
        }
    }
}

@MainActor
private final class VerticalOwnershipScrollDelegate: NSObject, UIScrollViewDelegate {}

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
