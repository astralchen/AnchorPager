import UIKit
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerPagingHostViewControllerTests: XCTestCase {
    func testFirstNonemptyReloadInstallsAdapterUsingStandardContainment() throws {
        let host = makeHost()

        host.reload(titles: ["First"], pageCount: 1, selectedIndex: 0)

        let adapter = try XCTUnwrap(host.activeAdapter)
        XCTAssertTrue(adapter.parent === host)
        XCTAssertTrue(adapter.view.superview === host.view)
        XCTAssertEqual(host.children.count, 1)
        XCTAssertTrue(host.children.first === adapter)
    }

    func testConsecutiveNonemptyReloadsReuseAdapter() throws {
        let host = makeHost()
        host.reload(titles: ["First"], pageCount: 1, selectedIndex: 0)
        let firstAdapter = try XCTUnwrap(host.activeAdapter)

        host.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 1)

        XCTAssertTrue(host.activeAdapter === firstAdapter)
        XCTAssertEqual(host.children.count, 1)
    }

    func testNonemptyReloadEmitsOnePageTerminalWithoutSelectionCallbacks() {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate

        host.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 1)

        XCTAssertEqual(delegate.events, [.reload(.page(index: 1))])
    }

    func testConsecutiveNonemptyReloadsEachEmitOnePageTerminalWithoutSelectionCallbacks() {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate

        host.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        XCTAssertEqual(delegate.events, [.reload(.page(index: 0))])

        delegate.events.removeAll()
        delegate.terminalSnapshots.removeAll()
        host.reload(titles: ["First", "Second", "Third"], pageCount: 3, selectedIndex: 2)

        XCTAssertEqual(delegate.events, [.reload(.page(index: 2))])
    }

    func testReloadingEmptyRemovesAdapterAndResetsBarBeforeEmptyTerminal() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["First"], pageCount: 1, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        host.pagingAdapter(
            adapter,
            didUpdateBarInsets: UIEdgeInsets(top: 44, left: 0, bottom: 0, right: 0)
        )
        delegate.events.removeAll()
        delegate.terminalSnapshots.removeAll()

        host.reload(titles: [], pageCount: 0, selectedIndex: 0)

        XCTAssertNil(host.activeAdapter)
        XCTAssertNil(adapter.parent)
        XCTAssertNil(adapter.view.superview)
        XCTAssertTrue(host.children.isEmpty)
        XCTAssertEqual(delegate.events, [.barInsets(.zero), .reload(.empty)])
        XCTAssertEqual(delegate.terminalSnapshots.count, 1)
        XCTAssertFalse(delegate.terminalSnapshots[0].hasActiveAdapter)
        XCTAssertEqual(delegate.terminalSnapshots[0].childCount, 0)
    }

    func testEmptyTerminalIsSentAfterPageboyBusinessPageContainmentIsCleared() async throws {
        let page = UIViewController()
        let provider = FixedHostPageProvider(page: page)
        let host = AnchorPagerPagingHostViewController()
        host.pageProvider = provider
        let delegate = RecordingPagingHostDelegate()
        delegate.observedPage = page
        host.eventDelegate = delegate
        host.reload(titles: ["Page"], pageCount: 1, selectedIndex: 0)
        weak var oldAdapter = host.activeAdapter
        weak var oldInnerPageboyContainer = host.activeAdapter?.children.first
        weak var resetPlaceholder: UIViewController?
        XCTAssertNotNil(page.parent)
        XCTAssertNotNil(page.view.superview)
        delegate.events.removeAll()
        delegate.terminalSnapshots.removeAll()

        autoreleasepool {
            host.reload(titles: [], pageCount: 0, selectedIndex: 0)
            resetPlaceholder = (oldInnerPageboyContainer as? UIPageViewController)?
                .viewControllers?
                .first
            XCTAssertNotNil(resetPlaceholder)
        }

        XCTAssertEqual(delegate.events, [.reload(.empty)])
        let terminalSnapshot = try XCTUnwrap(delegate.terminalSnapshots.first)
        XCTAssertFalse(terminalSnapshot.hasActiveAdapter)
        XCTAssertEqual(terminalSnapshot.childCount, 0)
        XCTAssertFalse(terminalSnapshot.observedPageHasParent)
        XCTAssertFalse(terminalSnapshot.observedPageHasSuperview)
        XCTAssertNil(page.parent)
        XCTAssertNil(page.view.superview)

        let releaseExpectation = expectation(description: "Pageboy terminal objects release")
        func inspectAfterMainTurns(_ remainingTurns: Int) {
            guard remainingTurns > 0 else {
                XCTAssertNil(oldAdapter)
                XCTAssertNil(oldInnerPageboyContainer)
                XCTAssertNil(resetPlaceholder)
                releaseExpectation.fulfill()
                return
            }
            DispatchQueue.main.async {
                inspectAfterMainTurns(remainingTurns - 1)
            }
        }
        inspectAfterMainTurns(3)
        await fulfillment(of: [releaseExpectation], timeout: 1)
    }

    func testRepeatedEmptyReloadIsContainmentIdempotentAndStillSendsTerminalPerReload() {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate

        host.reload(titles: [], pageCount: 0, selectedIndex: 0)
        host.reload(titles: [], pageCount: 0, selectedIndex: 0)

        XCTAssertNil(host.activeAdapter)
        XCTAssertTrue(host.children.isEmpty)
        XCTAssertEqual(delegate.events, [.reload(.empty), .reload(.empty)])
    }

    func testEmptyToNonemptyReloadInstallsNewAdapter() throws {
        let host = makeHost()
        host.reload(titles: ["First"], pageCount: 1, selectedIndex: 0)
        let oldAdapter = try XCTUnwrap(host.activeAdapter)

        host.reload(titles: [], pageCount: 0, selectedIndex: 0)
        XCTAssertNil(oldAdapter.parent)

        host.reload(titles: ["Replacement"], pageCount: 1, selectedIndex: 0)

        let newAdapter = try XCTUnwrap(host.activeAdapter)
        XCTAssertFalse(newAdapter === oldAdapter)
        XCTAssertTrue(newAdapter.parent === host)
        XCTAssertTrue(newAdapter.view.superview === host.view)
    }

    func testAdapterEventsAreForwardedAsHostEvents() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        delegate.terminalSnapshots.removeAll()

        host.pagingAdapter(adapter, willSelect: 1, animated: true)
        host.pagingAdapter(adapter, didSelect: 1, animated: true)
        host.pagingAdapter(adapter, didCancelSelectionAt: 1, returningTo: 0)
        host.pagingAdapter(adapter, didReloadAt: 1)

        XCTAssertEqual(
            delegate.events,
            [.willSelect(1, true), .didSelect(1, true), .didCancel(1, 0), .reload(.page(index: 1))]
        )
    }

    func testPageProviderAndSelectionAreForwardedOnlyWhileAdapterIsActive() throws {
        let host = AnchorPagerPagingHostViewController()
        let provider = RecordingHostPageProvider()
        host.pageProvider = provider

        XCTAssertFalse(host.setSelectedIndex(0, animated: false))

        host.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)

        XCTAssertTrue(adapter.pageProvider === provider)
        XCTAssertTrue(host.setSelectedIndex(1, animated: false))

        let emptyHost = AnchorPagerPagingHostViewController()
        XCTAssertFalse(emptyHost.setSelectedIndex(0, animated: false))
    }

    func testAnimatedSelectionDefersEmptyReloadUntilSelectionTerminal() throws {
        let host = AnchorPagerPagingHostViewController()
        let provider = RecordingHostPageProvider()
        host.pageProvider = provider
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        var logEvents: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { logEvents.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        host.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        delegate.terminalSnapshots.removeAll()
        adapter.pageboyViewController(
            adapter,
            willScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        host.reload(titles: [], pageCount: 0, selectedIndex: 0)

        XCTAssertTrue(host.activeAdapter === adapter)
        XCTAssertTrue(adapter.parent === host)
        XCTAssertEqual(host.children.count, 1)
        XCTAssertFalse(delegate.events.contains(.reload(.empty)))
        XCTAssertTrue(delegate.terminalSnapshots.isEmpty)
        XCTAssertFalse(host.setSelectedIndex(0, animated: false))
        XCTAssertTrue(logEvents.contains(
            .init(category: .paging, level: .debug, event: "paging.reload.deferred")
        ))
        XCTAssertFalse(logEvents.contains { $0.event == "paging.adapter.remove.rejected" })

        adapter.pageboyViewController(
            adapter,
            didScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        XCTAssertNil(host.activeAdapter)
        XCTAssertTrue(host.children.isEmpty)
        XCTAssertTrue(delegate.events.contains(.reload(.empty)))
        XCTAssertFalse(delegate.events.contains(.didSelect(1, true)))
    }

    func testLatestNonemptyReloadWinsWhileSelectionIsPending() throws {
        let host = AnchorPagerPagingHostViewController()
        let provider = RecordingHostPageProvider()
        host.pageProvider = provider
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        delegate.terminalSnapshots.removeAll()
        adapter.pageboyViewController(
            adapter,
            willScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        host.reload(titles: [], pageCount: 0, selectedIndex: 0)
        host.reload(titles: ["Replacement"], pageCount: 1, selectedIndex: 0)

        adapter.pageboyViewController(
            adapter,
            didScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        XCTAssertTrue(host.activeAdapter === adapter)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 1)
        XCTAssertTrue(delegate.events.contains(.reload(.page(index: 0))))
        XCTAssertFalse(delegate.events.contains(.reload(.empty)))
        XCTAssertFalse(delegate.events.contains(.didSelect(1, true)))
    }

    func testRejectedSecondProgrammaticSelectionKeepsFirstCompletionBusyUntilReloadCanAdvance() throws {
        let host = AnchorPagerPagingHostViewController()
        let provider = RecordingHostPageProvider()
        host.pageProvider = provider
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["First", "Second", "Third"], pageCount: 3, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        XCTAssertTrue(host.setSelectedIndex(1, animated: true))
        XCTAssertFalse(host.setSelectedIndex(2, animated: true))
        delegate.events.removeAll()
        delegate.terminalSnapshots.removeAll()

        host.reload(titles: ["Replacement"], pageCount: 1, selectedIndex: 0)
        adapter.pageboyViewController(
            adapter,
            didScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        XCTAssertTrue(host.activeAdapter === adapter)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 3)
        XCTAssertFalse(delegate.events.contains(.reload(.page(index: 0))))
        XCTAssertFalse(delegate.events.contains(.didSelect(1, true)))

        adapter.finishProgrammaticTransition(at: 1, finished: true)

        XCTAssertTrue(host.activeAdapter === adapter)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 1)
    }

    func testLatestEmptyReloadWinsAfterInteractiveCancel() throws {
        let host = AnchorPagerPagingHostViewController()
        let provider = RecordingHostPageProvider()
        host.pageProvider = provider
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        delegate.terminalSnapshots.removeAll()
        adapter.pageboyViewController(
            adapter,
            willScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        host.reload(titles: ["Replacement"], pageCount: 1, selectedIndex: 0)
        host.reload(titles: [], pageCount: 0, selectedIndex: 0)
        adapter.pageboyViewController(
            adapter,
            didCancelScrollToPageAt: 1,
            returnToPageAt: 0
        )

        XCTAssertNil(host.activeAdapter)
        XCTAssertTrue(host.children.isEmpty)
        XCTAssertTrue(delegate.events.contains(.reload(.empty)))
        XCTAssertFalse(delegate.events.contains(.reload(.page(index: 0))))
        XCTAssertFalse(delegate.events.contains(.didCancel(1, 0)))
    }

    func testInstallRemoveAndEmptyReloadWriteStableLogs() {
        let host = makeHost()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        host.reload(titles: ["First"], pageCount: 1, selectedIndex: 0)
        host.reload(titles: [], pageCount: 0, selectedIndex: 0)

        XCTAssertTrue(events.contains(
            .init(category: .lifecycle, level: .debug, event: "paging.adapter.install")
        ))
        XCTAssertTrue(events.contains(
            .init(category: .lifecycle, level: .debug, event: "paging.adapter.remove")
        ))
        XCTAssertTrue(events.contains(
            .init(category: .paging, level: .info, event: "paging.reload.empty")
        ))
    }

    private func makeHost() -> AnchorPagerPagingHostViewController {
        let host = AnchorPagerPagingHostViewController()
        host.pageProvider = RecordingHostPageProvider.shared
        return host
    }
}

@MainActor
private final class RecordingHostPageProvider: AnchorPagerPageProviding {
    static let shared = RecordingHostPageProvider()

    func pageViewController(at index: Int) -> UIViewController? {
        UIViewController()
    }
}

@MainActor
private final class FixedHostPageProvider: AnchorPagerPageProviding {
    let page: UIViewController

    init(page: UIViewController) {
        self.page = page
    }

    func pageViewController(at index: Int) -> UIViewController? {
        index == 0 ? page : nil
    }
}

@MainActor
private final class RecordingPagingHostDelegate: AnchorPagerPagingHostViewControllerDelegate {
    enum Event: Equatable {
        case reload(AnchorPagerPagingReloadTerminal)
        case willSelect(Int, Bool)
        case didSelect(Int, Bool)
        case didCancel(Int, Int)
        case barInsets(UIEdgeInsets)
    }

    struct TerminalSnapshot {
        let hasActiveAdapter: Bool
        let childCount: Int
        let observedPageHasParent: Bool
        let observedPageHasSuperview: Bool
    }

    var events: [Event] = []
    var terminalSnapshots: [TerminalSnapshot] = []
    weak var observedPage: UIViewController?

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal
    ) {
        let event = Event.reload(terminal)
        events.append(event)
        terminalSnapshots.append(
            TerminalSnapshot(
                hasActiveAdapter: host.activeAdapter != nil,
                childCount: host.children.count,
                observedPageHasParent: observedPage?.parent != nil,
                observedPageHasSuperview: observedPage?.viewIfLoaded?.superview != nil
            )
        )
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willSelect index: Int,
        animated: Bool
    ) {
        let event = Event.willSelect(index, animated)
        events.append(event)
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didSelect index: Int,
        animated: Bool
    ) {
        let event = Event.didSelect(index, animated)
        events.append(event)
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    ) {
        let event = Event.didCancel(index, previousIndex)
        events.append(event)
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {
        let event = Event.barInsets(barInsets)
        events.append(event)
    }
}
