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

    func testSelectionEventsAreForwardedAndReloadWithoutActiveRequestIsIgnored() throws {
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
            [.willSelect(1, true), .didSelect(1, true), .didCancel(1, 0)]
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

    func testDeferredReloadOnlyStartsLatestRequestAfterSelectionTerminal() throws {
        let host = makeHost()
        let delegate = RecordingRequestPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(requestIdentifier: 1, titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        adapter.pageboyViewController(
            adapter,
            willScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        host.reload(requestIdentifier: 2, titles: [], pageCount: 0, selectedIndex: 0)
        host.reload(requestIdentifier: 3, titles: ["Latest"], pageCount: 1, selectedIndex: 0)

        XCTAssertTrue(delegate.events.isEmpty)
        adapter.pageboyViewController(
            adapter,
            didScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        XCTAssertEqual(
            delegate.events,
            [.willPerform(3), .reload(3, .page(index: 0))]
        )
    }

    func testActiveReloadSerializesNewerRequestUntilMatchingTerminal() throws {
        let provider = ControllableHostPageProvider()
        let host = AnchorPagerPagingHostViewController()
        host.pageProvider = provider
        let delegate = RecordingRequestPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(requestIdentifier: 1, titles: ["First"], pageCount: 1, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        provider.providesPages = false

        host.reload(
            requestIdentifier: 2,
            titles: ["First", "Second"],
            pageCount: 2,
            selectedIndex: 0
        )
        host.reload(
            requestIdentifier: 3,
            titles: ["First", "Second", "Third"],
            pageCount: 3,
            selectedIndex: 2
        )

        XCTAssertEqual(delegate.events, [.willPerform(2)])
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 2)
        host.pagingAdapter(adapter, didReloadAt: 0, requestIdentifier: 2)

        XCTAssertEqual(
            delegate.events,
            [.willPerform(2), .reload(2, .page(index: 0)), .willPerform(3)]
        )
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 3)
        host.pagingAdapter(adapter, didReloadAt: 2, requestIdentifier: 3)

        XCTAssertEqual(
            delegate.events,
            [
                .willPerform(2),
                .reload(2, .page(index: 0)),
                .willPerform(3),
                .reload(3, .page(index: 2)),
            ]
        )
    }

    func testTerminalCarriesActiveRequestIdentifier() {
        let host = makeHost()
        let delegate = RecordingRequestPagingHostDelegate()
        host.eventDelegate = delegate

        host.reload(requestIdentifier: 42, titles: ["First"], pageCount: 1, selectedIndex: 0)
        host.reload(requestIdentifier: 43, titles: [], pageCount: 0, selectedIndex: 0)

        XCTAssertEqual(
            delegate.events,
            [
                .willPerform(42),
                .reload(42, .page(index: 0)),
                .willPerform(43),
                .reload(43, .empty),
            ]
        )
    }

    func testReloadTerminalSynchronousReentryDoesNotEmitDuplicateTerminal() {
        let host = makeHost()
        let delegate = RecordingRequestPagingHostDelegate()
        host.eventDelegate = delegate
        delegate.onReload = { host, requestIdentifier, terminal in
            guard case let .page(index) = terminal,
                  let adapter = host.activeAdapter else { return }
            host.pagingAdapter(
                adapter,
                didReloadAt: index,
                requestIdentifier: requestIdentifier
            )
        }

        host.reload(requestIdentifier: 51, titles: ["First"], pageCount: 1, selectedIndex: 0)

        XCTAssertEqual(delegate.events, [.willPerform(51), .reload(51, .page(index: 0))])
    }

    func testLateOldReloadCallbackDoesNotFinishNewActiveRequest() throws {
        let provider = ControllableHostPageProvider()
        let host = AnchorPagerPagingHostViewController()
        host.pageProvider = provider
        let delegate = RecordingRequestPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(requestIdentifier: 61, titles: ["First"], pageCount: 1, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        provider.providesPages = false

        host.reload(
            requestIdentifier: 62,
            titles: ["First", "Second"],
            pageCount: 2,
            selectedIndex: 0
        )
        host.reload(
            requestIdentifier: 63,
            titles: ["Replacement"],
            pageCount: 1,
            selectedIndex: 0
        )
        host.pagingAdapter(adapter, didReloadAt: 0, requestIdentifier: 62)
        adapter.pageboyViewController(
            adapter,
            didReloadWith: UIViewController(),
            currentPageIndex: 0
        )
        host.pagingAdapter(adapter, didReloadAt: 0, requestIdentifier: 62)

        XCTAssertEqual(
            delegate.events,
            [.willPerform(62), .reload(62, .page(index: 0)), .willPerform(63)]
        )
        XCTAssertFalse(host.setSelectedIndex(0, animated: false))

        host.pagingAdapter(adapter, didReloadAt: 0, requestIdentifier: 63)

        XCTAssertEqual(
            delegate.events,
            [
                .willPerform(62),
                .reload(62, .page(index: 0)),
                .willPerform(63),
                .reload(63, .page(index: 0)),
            ]
        )
    }

    func testRejectedWillPerformDoesNotCallAdapterOrEmitTerminal() throws {
        let host = makeHost()
        let delegate = RecordingRequestPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(requestIdentifier: 1, titles: ["First"], pageCount: 1, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        delegate.rejectedRequestIdentifiers = [2]
        var logEvents: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { logEvents.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        host.reload(
            requestIdentifier: 2,
            titles: ["First", "Second"],
            pageCount: 2,
            selectedIndex: 1
        )

        XCTAssertEqual(delegate.events, [.willPerform(2)])
        XCTAssertTrue(host.activeAdapter === adapter)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 1)
        XCTAssertTrue(logEvents.contains(
            .init(category: .paging, level: .debug, event: "paging.reload.stale")
        ))
    }

    func testPendingOrActiveReloadRejectsProgrammaticSelection() throws {
        let pendingHost = makeHost()
        pendingHost.reload(requestIdentifier: 1, titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        let pendingAdapter = try XCTUnwrap(pendingHost.activeAdapter)
        pendingAdapter.pageboyViewController(
            pendingAdapter,
            willScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )
        pendingHost.reload(requestIdentifier: 2, titles: ["Replacement"], pageCount: 1, selectedIndex: 0)

        XCTAssertFalse(pendingHost.setSelectedIndex(0, animated: false))

        let provider = ControllableHostPageProvider()
        let activeHost = AnchorPagerPagingHostViewController()
        activeHost.pageProvider = provider
        activeHost.reload(requestIdentifier: 3, titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        provider.providesPages = false
        activeHost.reload(requestIdentifier: 4, titles: ["Replacement"], pageCount: 1, selectedIndex: 0)

        XCTAssertFalse(activeHost.setSelectedIndex(0, animated: false))
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
private final class ControllableHostPageProvider: AnchorPagerPageProviding {
    var providesPages = true

    func pageViewController(at index: Int) -> UIViewController? {
        providesPages ? UIViewController() : nil
    }
}

@MainActor
private final class RecordingRequestPagingHostDelegate: AnchorPagerPagingHostViewControllerDelegate {
    enum Event: Equatable {
        case willPerform(AnchorPagerPagingReloadRequestIdentifier)
        case reload(
            AnchorPagerPagingReloadRequestIdentifier,
            AnchorPagerPagingReloadTerminal
        )
    }

    var events: [Event] = []
    var rejectedRequestIdentifiers: Set<AnchorPagerPagingReloadRequestIdentifier> = []
    var onReload: ((
        AnchorPagerPagingHostViewController,
        AnchorPagerPagingReloadRequestIdentifier,
        AnchorPagerPagingReloadTerminal
    ) -> Void)?

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willPerformReloadRequest identifier: AnchorPagerPagingReloadRequestIdentifier
    ) -> Bool {
        events.append(.willPerform(identifier))
        return !rejectedRequestIdentifiers.contains(identifier)
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    ) {
        events.append(.reload(requestIdentifier, terminal))
        onReload?(host, requestIdentifier, terminal)
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willSelect index: Int,
        animated: Bool
    ) {}

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didSelect index: Int,
        animated: Bool
    ) {}

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    ) {}

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {}
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
