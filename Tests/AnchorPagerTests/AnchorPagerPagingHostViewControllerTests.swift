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

    func testSuspendedReloadKeepsOnlyLatestPayloadUntilExternalDrain() throws {
        let host = makeHost()
        let delegate = RecordingRequestPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(requestIdentifier: 1, titles: ["A", "B"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        host.setDeferredWorkExecutionSuspended(true)

        host.reload(requestIdentifier: 2, titles: ["Old"], pageCount: 1, selectedIndex: 0)
        host.reload(
            requestIdentifier: 3,
            titles: ["Latest A", "Latest B", "Latest C"],
            pageCount: 3,
            selectedIndex: 2
        )

        XCTAssertEqual(host.pendingReloadRequestIdentifierForTesting, 3)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 2)
        XCTAssertTrue(delegate.events.isEmpty)

        host.setDeferredWorkExecutionSuspended(false)
        XCTAssertTrue(host.performPendingReloadIfPossible())

        XCTAssertEqual(delegate.events, [.willPerform(3), .reload(3, .page(index: 2))])
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 3)
        XCTAssertNil(host.pendingReloadRequestIdentifierForTesting)
    }

    func testReloadAppliesInteractivePagingPolicyOnlyAfterAcknowledgedTerminal() throws {
        let host = makeHost()
        let delegate = RecordingRequestPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(
            requestIdentifier: 1,
            titles: ["A", "B"],
            pageCount: 2,
            selectedIndex: 0,
            interactiveHorizontalPagingPermissions: [true, false]
        )
        let adapter = try XCTUnwrap(host.activeAdapter)
        XCTAssertTrue(adapter.isScrollEnabled)

        host.setDeferredWorkExecutionSuspended(true)
        host.reload(
            requestIdentifier: 2,
            titles: ["A", "B"],
            pageCount: 2,
            selectedIndex: 1,
            interactiveHorizontalPagingPermissions: [true, false]
        )
        XCTAssertTrue(adapter.isScrollEnabled)

        host.setDeferredWorkExecutionSuspended(false)
        XCTAssertTrue(host.performPendingReloadIfPossible())
        XCTAssertFalse(adapter.isScrollEnabled)

        host.pagingAdapter(
            adapter,
            didReloadAt: 0,
            terminalBarInsets: .zero,
            requestIdentifier: 1
        )
        XCTAssertFalse(adapter.isScrollEnabled)
    }

    func testRejectedReloadTerminalDoesNotPublishInteractivePagingPolicy() throws {
        let host = makeHost()
        let delegate = RecordingRequestPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(
            requestIdentifier: 1,
            titles: ["A"],
            pageCount: 1,
            selectedIndex: 0,
            interactiveHorizontalPagingPermissions: [true]
        )
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.terminalAcknowledgements[2] = false

        host.reload(
            requestIdentifier: 2,
            titles: ["A"],
            pageCount: 1,
            selectedIndex: 0,
            interactiveHorizontalPagingPermissions: [false]
        )

        XCTAssertTrue(adapter.isScrollEnabled)

        host.reload(
            requestIdentifier: 3,
            titles: ["A"],
            pageCount: 1,
            selectedIndex: 0,
            interactiveHorizontalPagingPermissions: [false]
        )
        XCTAssertFalse(adapter.isScrollEnabled)
    }

    func testEmptyReloadClearsInteractivePolicyBeforeReplacementAdapter() throws {
        let host = makeHost()
        host.reload(
            requestIdentifier: 1,
            titles: ["A"],
            pageCount: 1,
            selectedIndex: 0,
            interactiveHorizontalPagingPermissions: [false]
        )
        let oldAdapter = try XCTUnwrap(host.activeAdapter)
        XCTAssertFalse(oldAdapter.isScrollEnabled)

        host.reload(
            requestIdentifier: 2,
            titles: [],
            pageCount: 0,
            selectedIndex: 0,
            interactiveHorizontalPagingPermissions: []
        )
        XCTAssertNil(host.activeAdapter)

        host.reload(
            requestIdentifier: 3,
            titles: ["Replacement"],
            pageCount: 1,
            selectedIndex: 0
        )
        XCTAssertTrue(try XCTUnwrap(host.activeAdapter).isScrollEnabled)
    }

    func testInvalidInteractivePagingMetadataFailsClosedAndLogsOnce() throws {
        let host = makeHost()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        AnchorPagerAssertions.$isEnabled.withValue(false) {
            host.reload(
                requestIdentifier: 7,
                titles: ["A", "B"],
                pageCount: 2,
                selectedIndex: 0,
                interactiveHorizontalPagingPermissions: [true]
            )
        }

        XCTAssertFalse(try XCTUnwrap(host.activeAdapter).isScrollEnabled)
        XCTAssertEqual(
            events.filter {
                $0.event == "paging.interactivePaging.invalidMetadata"
            }.count,
            1
        )
    }

    func testSuspendedSelectionKeepsLatestExplicitRequestUntilExternalDrain() throws {
        let host = makeHost()
        host.reload(titles: ["A", "B", "C"], pageCount: 3, selectedIndex: 0)
        host.setDeferredWorkExecutionSuspended(true)

        XCTAssertTrue(host.setSelectedIndex(1, animated: true))
        let firstIdentifier = host.pendingExplicitSelectionRequestForTesting?.identifier
        XCTAssertFalse(host.setSelectedIndex(1, animated: false))
        XCTAssertEqual(
            host.pendingExplicitSelectionRequestForTesting?.identifier,
            firstIdentifier
        )
        XCTAssertTrue(host.setSelectedIndex(0, animated: false))
        XCTAssertNil(host.pendingExplicitSelectionRequestForTesting)

        XCTAssertTrue(host.setSelectedIndex(1, animated: true))
        XCTAssertTrue(host.setSelectedIndex(2, animated: false))

        XCTAssertNil(host.activeSelectionRequestForTesting)
        XCTAssertEqual(host.pendingExplicitSelectionRequestForTesting?.targetIndex, 2)

        host.setDeferredWorkExecutionSuspended(false)
        XCTAssertTrue(host.performPendingSelectionIfPossible())

        XCTAssertEqual(host.activeSelectionRequestForTesting?.targetIndex, 2)
        XCTAssertNil(host.pendingExplicitSelectionRequestForTesting)
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
        XCTAssertEqual(delegate.events, [.reload(.empty)])
        XCTAssertEqual(Array(delegate.reloadFinalBarInsets.suffix(1)), [.zero])
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
        weak var oldAdapter: AnchorPagerPagingAdapter?
        oldAdapter = host.activeAdapter
        weak var oldInnerPageboyContainer: UIViewController?
        oldInnerPageboyContainer = host.activeAdapter?.children.first
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

        let requestIdentifier = try XCTUnwrap(host.pagingAdapter(
            adapter,
            didBeginInteractiveSelectionAt: 1,
            animated: true
        ))
        host.pagingAdapter(
            adapter,
            willSelect: 1,
            animated: true,
            requestIdentifier: requestIdentifier
        )
        host.pagingAdapter(
            adapter,
            didSelect: 1,
            animated: true,
            requestIdentifier: requestIdentifier
        )
        host.pagingAdapter(
            adapter,
            didCancelSelectionAt: 1,
            returningTo: 0,
            requestIdentifier: requestIdentifier
        )
        host.pagingAdapter(
            adapter,
            didReloadAt: 1,
            terminalBarInsets: UIEdgeInsets(top: 99, left: 0, bottom: 0, right: 0),
            requestIdentifier: 999
        )

        XCTAssertEqual(
            delegate.events,
            [.willSelect(1, true), .didSelect(1, true)]
        )
    }

    func testMissingWillSelectRecoveryCommitsThroughHostTransaction() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        delegate.interactionEvents.removeAll()

        adapter.handleDidSelect(
            at: 1,
            animated: true,
            reportedCurrentIndex: 1
        )

        XCTAssertEqual(delegate.events, [.willSelect(1, true), .didSelect(1, true)])
        XCTAssertEqual(host.committedSelectionIndexForTesting, 1)
        XCTAssertNil(host.activeSelectionRequestForTesting)
        XCTAssertEqual(delegate.interactionEvents.count, 2)
        guard case let .began(request) = delegate.interactionEvents.first else {
            return XCTFail("恢复事务必须先经过 Host admission。")
        }
        XCTAssertEqual(request.targetIndex, 1)
        XCTAssertEqual(delegate.interactionEvents.last, .finished(request))
    }

    func testMissingWillSelectRecoveryDoesNotBypassRejectedHostAdmission() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        delegate.acceptsInteractionBegin = false
        host.eventDelegate = delegate
        host.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        delegate.interactionEvents.removeAll()

        adapter.handleDidSelect(
            at: 1,
            animated: true,
            reportedCurrentIndex: 1
        )

        XCTAssertTrue(delegate.events.isEmpty)
        XCTAssertEqual(host.committedSelectionIndexForTesting, 0)
        XCTAssertNil(host.activeSelectionRequestForTesting)
        XCTAssertEqual(delegate.interactionEvents.count, 1)
        guard case let .began(request) = delegate.interactionEvents.first else {
            return XCTFail("恢复尝试必须经过可拒绝的 Host admission。")
        }
        XCTAssertEqual(request.targetIndex, 1)
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

    func testExplicitSelectionAdmissionKeepsOneActiveAndLatestPendingIntent() throws {
        let host = makeHost()
        host.reload(titles: ["A", "B", "C", "D"], pageCount: 4, selectedIndex: 0)
        var logEvents: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { logEvents.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        XCTAssertTrue(host.enqueueSelection(index: 1, animated: true, source: .api))
        XCTAssertEqual(host.activeSelectionRequestForTesting?.identifier, 1)
        XCTAssertEqual(host.activeSelectionRequestForTesting?.targetIndex, 1)
        XCTAssertNil(host.pendingExplicitSelectionRequestForTesting)

        XCTAssertFalse(host.enqueueSelection(index: 1, animated: false, source: .api))
        XCTAssertNil(host.pendingExplicitSelectionRequestForTesting)

        XCTAssertTrue(host.enqueueSelection(index: 2, animated: true, source: .bar))
        XCTAssertEqual(host.pendingExplicitSelectionRequestForTesting?.identifier, 2)
        XCTAssertEqual(host.pendingExplicitSelectionRequestForTesting?.targetIndex, 2)
        XCTAssertEqual(host.pendingExplicitSelectionRequestForTesting?.source, .bar)

        XCTAssertTrue(host.enqueueSelection(index: 3, animated: false, source: .api))
        XCTAssertEqual(host.pendingExplicitSelectionRequestForTesting?.identifier, 3)
        XCTAssertEqual(host.pendingExplicitSelectionRequestForTesting?.targetIndex, 3)

        XCTAssertTrue(host.enqueueSelection(index: 0, animated: true, source: .api))
        XCTAssertEqual(host.pendingExplicitSelectionRequestForTesting?.identifier, 4)
        XCTAssertEqual(host.pendingExplicitSelectionRequestForTesting?.targetIndex, 0)
        XCTAssertEqual(host.committedSelectionIndexForTesting, 0)
        XCTAssertFalse(host.enqueueSelection(index: 4, animated: true, source: .api))
        XCTAssertFalse(host.enqueueSelection(index: 2, animated: true, source: .interactive))

        XCTAssertTrue(logEvents.contains { $0.event == "paging.selection.start" })
        XCTAssertTrue(logEvents.contains { $0.event == "paging.selection.enqueue" })
        XCTAssertEqual(
            logEvents.filter { $0.event == "paging.selection.replacePending" }.count,
            2
        )
    }

    func testAPIAndBarSelectionsShareHostIdentifierSequence() throws {
        let host = makeHost()
        host.reload(titles: ["A", "B", "C"], pageCount: 3, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)

        XCTAssertTrue(host.setSelectedIndex(1, animated: true))
        host.pagingAdapter(adapter, didRequestBarSelectionAt: 2)

        XCTAssertEqual(host.activeSelectionRequestForTesting?.identifier, 1)
        XCTAssertEqual(host.activeSelectionRequestForTesting?.source, .api)
        XCTAssertEqual(host.pendingExplicitSelectionRequestForTesting?.identifier, 2)
        XCTAssertEqual(host.pendingExplicitSelectionRequestForTesting?.source, .bar)
    }

    func testMatchingSelectionTerminalCommitsOnceAndWaitsForAllAcknowledgements() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["A", "B", "C"], pageCount: 3, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        let staleAdapter = AnchorPagerPagingAdapter()
        delegate.events.removeAll()
        var logEvents: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { logEvents.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        XCTAssertTrue(host.enqueueSelection(index: 1, animated: true, source: .api))
        let identifier = try XCTUnwrap(host.activeSelectionRequestForTesting?.identifier)
        host.pagingAdapter(
            adapter,
            willSelect: 1,
            animated: true,
            requestIdentifier: identifier
        )
        host.pagingAdapter(
            adapter,
            willSelect: 1,
            animated: true,
            requestIdentifier: identifier
        )
        host.pagingAdapter(
            staleAdapter,
            didSelect: 1,
            animated: true,
            requestIdentifier: identifier
        )
        host.pagingAdapter(
            adapter,
            didSelect: 2,
            animated: true,
            requestIdentifier: identifier
        )
        host.pagingAdapter(
            adapter,
            didSelect: 1,
            animated: true,
            requestIdentifier: identifier
        )
        host.pagingAdapter(
            adapter,
            didSelect: 1,
            animated: true,
            requestIdentifier: identifier
        )

        XCTAssertEqual(delegate.events, [.willSelect(1, true), .didSelect(1, true)])
        XCTAssertEqual(host.committedSelectionIndexForTesting, 1)
        XCTAssertNotNil(host.activeSelectionRequestForTesting)

        host.pagingAdapter(adapter, executorDidBecomeReadyFor: identifier)
        XCTAssertNotNil(host.activeSelectionRequestForTesting)
        host.pagingAdapter(
            adapter,
            didComplete: identifier + 10,
            finished: true,
            currentIndex: 1
        )
        host.pagingAdapter(adapter, executorDidBecomeReadyFor: identifier + 10)
        XCTAssertNotNil(host.activeSelectionRequestForTesting)

        host.pagingAdapter(
            adapter,
            didComplete: identifier,
            finished: true,
            currentIndex: 1
        )
        XCTAssertNotNil(host.activeSelectionRequestForTesting)
        host.pagingAdapter(adapter, executorDidBecomeReadyFor: identifier)

        XCTAssertNil(host.activeSelectionRequestForTesting)
        XCTAssertEqual(delegate.events, [.willSelect(1, true), .didSelect(1, true)])
        XCTAssertGreaterThanOrEqual(
            logEvents.filter { $0.event == "paging.selection.staleTerminal" }.count,
            4
        )
    }

    func testProgrammaticInteractionFinishesOnlyAfterAllAcknowledgements() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["A", "B"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.interactionEvents.removeAll()

        XCTAssertTrue(host.enqueueSelection(index: 1, animated: true, source: .api))
        let request = try XCTUnwrap(host.activeSelectionRequestForTesting)
        XCTAssertEqual(delegate.interactionEvents, [.began(request)])

        host.pagingAdapter(
            adapter,
            didSelect: 1,
            animated: true,
            requestIdentifier: request.identifier
        )
        host.pagingAdapter(
            adapter,
            didComplete: request.identifier,
            finished: true,
            currentIndex: 1
        )
        XCTAssertEqual(delegate.interactionEvents, [.began(request)])

        host.pagingAdapter(adapter, executorDidBecomeReadyFor: request.identifier)

        XCTAssertEqual(delegate.interactionEvents, [.began(request), .finished(request)])
    }

    func testRejectedInteractiveInteractionDoesNotCreateHostTransaction() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["A", "B"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.acceptsInteractionBegin = false
        delegate.interactionEvents.removeAll()

        let identifier = host.pagingAdapter(
            adapter,
            didBeginInteractiveSelectionAt: 1,
            animated: true
        )

        XCTAssertNil(identifier)
        XCTAssertNil(host.activeSelectionRequestForTesting)
        XCTAssertEqual(delegate.interactionEvents.count, 1)
        guard case .began(let request) = delegate.interactionEvents[0] else {
            return XCTFail("应记录一次 interactive admission 尝试")
        }
        XCTAssertEqual(request.source, .interactive)
    }

    func testStructuralSelectionCancelEmitsMatchingInteractionCancel() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["A", "B"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        let identifier = try XCTUnwrap(host.pagingAdapter(
            adapter,
            didBeginInteractiveSelectionAt: 1,
            animated: true
        ))
        let request = try XCTUnwrap(host.activeSelectionRequestForTesting)
        XCTAssertEqual(request.identifier, identifier)
        XCTAssertEqual(request.source, .interactive)
        delegate.interactionEvents.removeAll()

        host.reload(
            titles: [],
            pageCount: 0,
            selectedIndex: 0
        )

        XCTAssertTrue(delegate.interactionEvents.contains(.cancelled(request)))
    }

    func testInteractiveSelectionUsesOneTransactionAndCancelDoesNotCommit() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["A", "B"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()

        let identifier = try XCTUnwrap(host.pagingAdapter(
            adapter,
            didBeginInteractiveSelectionAt: 1,
            animated: true
        ))
        XCTAssertEqual(identifier, 1)
        XCTAssertEqual(host.activeSelectionRequestForTesting?.source, .interactive)
        XCTAssertEqual(
            host.pagingAdapter(
                adapter,
                didBeginInteractiveSelectionAt: 1,
                animated: true
            ),
            identifier
        )
        host.pagingAdapter(
            adapter,
            willSelect: 1,
            animated: true,
            requestIdentifier: identifier
        )
        host.pagingAdapter(
            adapter,
            willSelect: 1,
            animated: true,
            requestIdentifier: identifier
        )
        host.pagingAdapter(
            adapter,
            didCancelSelectionAt: 1,
            returningTo: 0,
            requestIdentifier: identifier
        )

        XCTAssertNil(host.activeSelectionRequestForTesting)
        XCTAssertEqual(host.committedSelectionIndexForTesting, 0)
        XCTAssertEqual(delegate.events, [.willSelect(1, true), .didCancel(1, 0)])
        XCTAssertEqual(delegate.interactionEvents, [
            .began(.init(
                identifier: identifier,
                targetIndex: 1,
                animated: true,
                source: .interactive
            )),
            .finished(.init(
                identifier: identifier,
                targetIndex: 1,
                animated: true,
                source: .interactive
            )),
        ])
    }

    func testReloadInteractionWrapsProviderAndSemanticTerminal() {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate

        host.reload(
            requestIdentifier: 7,
            titles: ["A"],
            pageCount: 1,
            selectedIndex: 0
        )

        XCTAssertEqual(delegate.reloadInteractionEvents, [
            .began(7),
            .finished(7),
        ])
    }

    func testProgrammaticCompletionRecoversMissingSemanticTerminal() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["A", "B"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        var logEvents: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { logEvents.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        XCTAssertTrue(host.enqueueSelection(index: 1, animated: true, source: .api))
        let identifier = try XCTUnwrap(host.activeSelectionRequestForTesting?.identifier)
        host.pagingAdapter(
            adapter,
            didComplete: identifier,
            finished: true,
            currentIndex: 1
        )

        XCTAssertEqual(delegate.events, [.willSelect(1, true), .didSelect(1, true)])
        XCTAssertEqual(host.committedSelectionIndexForTesting, 1)
        XCTAssertNotNil(host.activeSelectionRequestForTesting)
        XCTAssertTrue(logEvents.contains { $0.event == "paging.selection.missingSemantic" })

        host.pagingAdapter(adapter, executorDidBecomeReadyFor: identifier)
        XCTAssertNil(host.activeSelectionRequestForTesting)
    }

    func testFailedProgrammaticCompletionRecoversMissingCancelTerminal() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["A", "B"], pageCount: 2, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()

        XCTAssertTrue(host.enqueueSelection(index: 1, animated: true, source: .api))
        let identifier = try XCTUnwrap(host.activeSelectionRequestForTesting?.identifier)
        host.pagingAdapter(
            adapter,
            didComplete: identifier,
            finished: false,
            currentIndex: 0
        )

        XCTAssertEqual(delegate.events, [.willSelect(1, true), .didCancel(1, 0)])
        XCTAssertEqual(host.committedSelectionIndexForTesting, 0)
        XCTAssertNotNil(host.activeSelectionRequestForTesting)

        host.pagingAdapter(adapter, executorDidBecomeReadyFor: identifier)
        XCTAssertNil(host.activeSelectionRequestForTesting)
    }

    func testRealIntermediateTerminalCommitsBeforeLatestSelectionStarts() async throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        host.reload(titles: ["A", "B", "C", "D"], pageCount: 4, selectedIndex: 0)
        _ = try XCTUnwrap(host.activeAdapter)
        host.view.layoutIfNeeded()
        delegate.events.removeAll()
        let intermediateTerminal = expectation(description: "真实中间页先提交")
        let latestSelectionStarted = expectation(description: "latest selection 后启动")
        var intermediateActiveIdentifier: Int?
        var intermediatePendingIdentifier: Int?
        var latestActiveIdentifier: Int?
        var latestActiveTarget: Int?
        var latestPendingIdentifier: Int?
        delegate.onDidSelect = { host, index, _ in
            guard index == 1 else { return }
            intermediateActiveIdentifier = host.activeSelectionRequestForTesting?.identifier
            intermediatePendingIdentifier =
                host.pendingExplicitSelectionRequestForTesting?.identifier
            intermediateTerminal.fulfill()
        }
        delegate.onWillSelect = { host, index, _ in
            guard index == 3 else { return }
            latestActiveIdentifier = host.activeSelectionRequestForTesting?.identifier
            latestActiveTarget = host.activeSelectionRequestForTesting?.targetIndex
            latestPendingIdentifier = host.pendingExplicitSelectionRequestForTesting?.identifier
            latestSelectionStarted.fulfill()
        }

        XCTAssertTrue(host.setSelectedIndex(1, animated: false))
        XCTAssertTrue(host.setSelectedIndex(3, animated: false))
        let firstIdentifier = try XCTUnwrap(host.activeSelectionRequestForTesting?.identifier)
        let latestIdentifier = try XCTUnwrap(
            host.pendingExplicitSelectionRequestForTesting?.identifier
        )

        await fulfillment(
            of: [intermediateTerminal, latestSelectionStarted],
            timeout: 2,
            enforceOrder: true
        )

        XCTAssertEqual(intermediateActiveIdentifier, firstIdentifier)
        XCTAssertEqual(intermediatePendingIdentifier, latestIdentifier)
        XCTAssertEqual(latestActiveIdentifier, latestIdentifier)
        XCTAssertEqual(latestActiveTarget, 3)
        XCTAssertNil(latestPendingIdentifier)
    }

    func testAnimatedExecutorReadyStartsLatestOnlyAfterRealPageboyCompletion() async throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        host.reload(titles: ["A", "B", "C", "D"], pageCount: 4, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        adapter.transition = .init(style: .fade, duration: 0.01)
        host.view.layoutIfNeeded()
        delegate.events.removeAll()
        let intermediateTerminal = expectation(description: "动画中间页 semantic terminal")
        let latestSelectionStarted = expectation(description: "executor ready 后启动 latest")
        var activeAtIntermediate: Int?
        var pendingAtIntermediate: Int?
        var activeAtLatestStart: Int?
        delegate.onDidSelect = { host, index, _ in
            guard index == 1 else { return }
            activeAtIntermediate = host.activeSelectionRequestForTesting?.identifier
            pendingAtIntermediate = host.pendingExplicitSelectionRequestForTesting?.identifier
            intermediateTerminal.fulfill()
        }
        delegate.onWillSelect = { host, index, _ in
            guard index == 3 else { return }
            activeAtLatestStart = host.activeSelectionRequestForTesting?.identifier
            latestSelectionStarted.fulfill()
        }

        XCTAssertTrue(host.setSelectedIndex(1, animated: true))
        XCTAssertTrue(host.setSelectedIndex(3, animated: true))
        let firstIdentifier = try XCTUnwrap(host.activeSelectionRequestForTesting?.identifier)
        let latestIdentifier = try XCTUnwrap(
            host.pendingExplicitSelectionRequestForTesting?.identifier
        )

        await fulfillment(
            of: [intermediateTerminal, latestSelectionStarted],
            timeout: 2,
            enforceOrder: true
        )

        XCTAssertEqual(activeAtIntermediate, firstIdentifier)
        XCTAssertEqual(pendingAtIntermediate, latestIdentifier)
        XCTAssertEqual(activeAtLatestStart, latestIdentifier)
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
        XCTAssertTrue(delegate.events.contains(.didSelect(1, true)))
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
        XCTAssertTrue(delegate.events.contains(.didSelect(1, true)))
    }

    func testQueuedSecondProgrammaticSelectionKeepsFirstCompletionBusyUntilReloadCanAdvance() throws {
        let host = AnchorPagerPagingHostViewController()
        let provider = RecordingHostPageProvider()
        host.pageProvider = provider
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["First", "Second", "Third"], pageCount: 3, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        XCTAssertTrue(host.setSelectedIndex(1, animated: true))
        XCTAssertTrue(host.setSelectedIndex(2, animated: true))
        delegate.events.removeAll()
        delegate.terminalSnapshots.removeAll()
        delegate.reloadWillPerformCount = 0
        var didSelectObserved = false
        var didSelectPrecededReload = false
        delegate.onDidSelect = { _, index, _ in
            if index == 1 {
                didSelectObserved = true
            }
        }
        delegate.onWillPerformReload = { _ in
            didSelectPrecededReload = didSelectObserved
        }

        host.reload(titles: ["Replacement"], pageCount: 1, selectedIndex: 0)
        XCTAssertNil(host.pendingExplicitSelectionRequestForTesting)
        XCTAssertFalse(host.setSelectedIndex(0, animated: false))
        host.pagingAdapter(adapter, didRequestBarSelectionAt: 0)
        XCTAssertNil(host.pendingExplicitSelectionRequestForTesting)
        adapter.pageboyViewController(
            adapter,
            didScrollToPageAt: 1,
            direction: .forward,
            animated: true
        )

        XCTAssertTrue(host.activeAdapter === adapter)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 3)
        XCTAssertFalse(delegate.events.contains(.reload(.page(index: 0))))
        XCTAssertTrue(delegate.events.contains(.didSelect(1, true)))

        adapter.finishProgrammaticTransition(
            requestIdentifier: 1,
            targetIndex: 1,
            finished: true
        )

        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 3)
        adapter.isUserInteractionEnabled = true

        XCTAssertTrue(host.activeAdapter === adapter)
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 1)
        XCTAssertNil(host.activeSelectionRequestForTesting)
        XCTAssertNil(host.pendingExplicitSelectionRequestForTesting)
        XCTAssertEqual(delegate.reloadWillPerformCount, 1)
        XCTAssertTrue(didSelectPrecededReload)
    }

    func testEmptyStructuralTeardownCancelsMatchingTransactionAndIsolatesOldAdapter() throws {
        let host = makeHost()
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(titles: ["A", "B"], pageCount: 2, selectedIndex: 0)
        let oldAdapter = try XCTUnwrap(host.activeAdapter)
        delegate.events.removeAll()
        var logEvents: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { logEvents.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        let identifier = try XCTUnwrap(host.pagingAdapter(
            oldAdapter,
            didBeginInteractiveSelectionAt: 1,
            animated: true
        ))
        XCTAssertNotNil(host.activeSelectionRequestForTesting)
        XCTAssertTrue(oldAdapter.isReadyForReload)

        host.reload(titles: [], pageCount: 0, selectedIndex: 0)

        XCTAssertNil(host.activeAdapter)
        XCTAssertNil(host.activeSelectionRequestForTesting)
        XCTAssertNil(host.pendingExplicitSelectionRequestForTesting)
        XCTAssertEqual(delegate.events, [.didCancel(1, 0), .reload(.empty)])
        XCTAssertTrue(logEvents.contains { $0.event == "paging.selection.structuralCancel" })

        host.reload(titles: ["Replacement"], pageCount: 1, selectedIndex: 0)
        let newAdapter = try XCTUnwrap(host.activeAdapter)
        XCTAssertFalse(newAdapter === oldAdapter)
        let eventCount = delegate.events.count
        host.pagingAdapter(
            oldAdapter,
            didSelect: 1,
            animated: true,
            requestIdentifier: identifier
        )
        host.pagingAdapter(oldAdapter, executorDidBecomeReadyFor: identifier)

        XCTAssertEqual(delegate.events.count, eventCount)
        XCTAssertNil(host.activeSelectionRequestForTesting)
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
        XCTAssertTrue(delegate.events.contains(.didCancel(1, 0)))
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
        host.pagingAdapter(
            adapter,
            didReloadAt: 0,
            terminalBarInsets: UIEdgeInsets(top: 60, left: 0, bottom: 0, right: 0),
            requestIdentifier: 2
        )

        XCTAssertEqual(
            delegate.events,
            [.willPerform(2), .reload(2, .page(index: 0)), .willPerform(3)]
        )
        XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 3)
        host.pagingAdapter(
            adapter,
            didReloadAt: 2,
            terminalBarInsets: UIEdgeInsets(top: 64, left: 0, bottom: 0, right: 0),
            requestIdentifier: 3
        )

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

    func testActiveReloadStagesBarInsetsUntilMatchingTerminal() throws {
        let provider = ControllableHostPageProvider()
        let host = AnchorPagerPagingHostViewController()
        host.pageProvider = provider
        let delegate = RecordingPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(requestIdentifier: 1, titles: ["First"], pageCount: 1, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        host.pagingAdapter(
            adapter,
            didUpdateBarInsets: UIEdgeInsets(top: 44, left: 0, bottom: 0, right: 0)
        )
        delegate.events.removeAll()
        provider.providesPages = false

        host.reload(requestIdentifier: 2, titles: ["Replacement"], pageCount: 1, selectedIndex: 0)
        host.pagingAdapter(
            adapter,
            didUpdateBarInsets: UIEdgeInsets(top: 60, left: 0, bottom: 0, right: 0)
        )

        XCTAssertTrue(delegate.events.isEmpty)
        host.pagingAdapter(
            adapter,
            didReloadAt: 0,
            terminalBarInsets: UIEdgeInsets(top: 64, left: 0, bottom: 0, right: 0),
            requestIdentifier: 2
        )
        XCTAssertEqual(delegate.events, [.reload(.page(index: 0))])
        XCTAssertEqual(
            Array(delegate.reloadFinalBarInsets.suffix(1)),
            [UIEdgeInsets(top: 64, left: 0, bottom: 0, right: 0)]
        )
    }

    func testRejectedEmptyTerminalDoesNotReplacePendingRequestBarBaseline() throws {
        let host = AnchorPagerPagingHostViewController()
        let provider = ControllableHostPageProvider()
        host.pageProvider = provider
        let delegate = RecordingRequestPagingHostDelegate()
        host.eventDelegate = delegate
        host.reload(requestIdentifier: 1, titles: ["Initial"], pageCount: 1, selectedIndex: 0)
        let adapter = try XCTUnwrap(host.activeAdapter)
        host.pagingAdapter(
            adapter,
            didUpdateBarInsets: UIEdgeInsets(top: 44, left: 0, bottom: 0, right: 0)
        )
        delegate.events.removeAll()
        delegate.terminalBarInsets.removeAll()
        delegate.terminalAcknowledgements[2] = false
        provider.providesPages = false
        delegate.onWillPerform = { host, identifier in
            guard identifier == 2 else { return }
            host.reload(
                requestIdentifier: 3,
                titles: ["Replacement"],
                pageCount: 1,
                selectedIndex: 0
            )
        }

        host.reload(requestIdentifier: 2, titles: [], pageCount: 0, selectedIndex: 0)

        let replacementAdapter = try XCTUnwrap(host.activeAdapter)
        host.pagingAdapter(
            replacementAdapter,
            didReloadAt: 0,
            terminalBarInsets: UIEdgeInsets(top: 44, left: 0, bottom: 0, right: 0),
            requestIdentifier: 3
        )

        XCTAssertEqual(
            delegate.events,
            [
                .willPerform(2),
                .reload(2, .empty),
                .willPerform(3),
                .reload(3, .page(index: 0)),
            ]
        )
        XCTAssertEqual(delegate.terminalBarInsets.count, 2)
        let firstTerminal = try XCTUnwrap(delegate.terminalBarInsets.first)
        let lastTerminal = try XCTUnwrap(delegate.terminalBarInsets.last)
        XCTAssertEqual(firstTerminal.0, 2)
        XCTAssertEqual(firstTerminal.1, .zero)
        XCTAssertEqual(lastTerminal.0, 3)
        XCTAssertEqual(
            lastTerminal.1,
            UIEdgeInsets(top: 44, left: 0, bottom: 0, right: 0)
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
                terminalBarInsets: UIEdgeInsets(top: 44, left: 0, bottom: 0, right: 0),
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
        host.pagingAdapter(
            adapter,
            didReloadAt: 0,
            terminalBarInsets: UIEdgeInsets(top: 60, left: 0, bottom: 0, right: 0),
            requestIdentifier: 62
        )
        adapter.pageboyViewController(
            adapter,
            didReloadWith: UIViewController(),
            currentPageIndex: 0
        )
        host.pagingAdapter(
            adapter,
            didReloadAt: 0,
            terminalBarInsets: UIEdgeInsets(top: 5, left: 0, bottom: 0, right: 0),
            requestIdentifier: 62
        )

        XCTAssertEqual(
            delegate.events,
            [.willPerform(62), .reload(62, .page(index: 0)), .willPerform(63)]
        )
        XCTAssertFalse(host.setSelectedIndex(0, animated: false))

        host.pagingAdapter(
            adapter,
            didReloadAt: 0,
            terminalBarInsets: UIEdgeInsets(top: 64, left: 0, bottom: 0, right: 0),
            requestIdentifier: 63
        )

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

    func testMissingPagePresentationSurfaceLogsOnceUntilStateRecovers() {
        let host = AnchorPagerPagingHostViewController()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        XCTAssertFalse(host.setPagePresentationTranslationY(-12))
        XCTAssertFalse(host.setPagePresentationTranslationY(-18))
        XCTAssertTrue(host.setPagePresentationTranslationY(0))
        XCTAssertFalse(host.setPagePresentationTranslationY(-12))

        XCTAssertEqual(
            events.filter { $0.event == "paging.pagePresentation.unavailable" }.count,
            2
        )
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
    var terminalAcknowledgements: [AnchorPagerPagingReloadRequestIdentifier: Bool] = [:]
    var terminalBarInsets: [(AnchorPagerPagingReloadRequestIdentifier, UIEdgeInsets)] = []
    var onWillPerform: ((
        AnchorPagerPagingHostViewController,
        AnchorPagerPagingReloadRequestIdentifier
    ) -> Void)?
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
        onWillPerform?(host, identifier)
        return !rejectedRequestIdentifiers.contains(identifier)
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal,
        finalBarInsets: UIEdgeInsets,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    ) -> Bool {
        events.append(.reload(requestIdentifier, terminal))
        terminalBarInsets.append((requestIdentifier, finalBarInsets))
        onReload?(host, requestIdentifier, terminal)
        return terminalAcknowledgements[requestIdentifier] ?? true
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
    enum ReloadInteractionEvent: Equatable {
        case began(AnchorPagerPagingReloadRequestIdentifier)
        case finished(AnchorPagerPagingReloadRequestIdentifier)
        case cancelled(AnchorPagerPagingReloadRequestIdentifier)
    }

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
    var interactionEvents: [AnchorPagerPagingInteractionEvent] = []
    var reloadInteractionEvents: [ReloadInteractionEvent] = []
    var acceptsInteractionBegin = true
    var terminalSnapshots: [TerminalSnapshot] = []
    var reloadFinalBarInsets: [UIEdgeInsets] = []
    var onWillSelect: ((AnchorPagerPagingHostViewController, Int, Bool) -> Void)?
    var onDidSelect: ((AnchorPagerPagingHostViewController, Int, Bool) -> Void)?
    var onWillPerformReload: ((AnchorPagerPagingHostViewController) -> Void)?
    var reloadWillPerformCount = 0
    weak var observedPage: UIViewController?

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        shouldBeginReloadInteraction identifier: AnchorPagerPagingReloadRequestIdentifier
    ) -> Bool {
        reloadInteractionEvents.append(.began(identifier))
        return true
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didFinishReloadInteraction identifier: AnchorPagerPagingReloadRequestIdentifier
    ) {
        reloadInteractionEvents.append(.finished(identifier))
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didCancelReloadInteraction identifier: AnchorPagerPagingReloadRequestIdentifier
    ) {
        reloadInteractionEvents.append(.cancelled(identifier))
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        shouldBeginInteractionFor request: AnchorPagerPagingSelectionRequest
    ) -> Bool {
        interactionEvents.append(.began(request))
        return acceptsInteractionBegin
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didFinishInteractionFor request: AnchorPagerPagingSelectionRequest
    ) {
        interactionEvents.append(.finished(request))
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didCancelInteractionFor request: AnchorPagerPagingSelectionRequest
    ) {
        interactionEvents.append(.cancelled(request))
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willPerformReloadRequest identifier: AnchorPagerPagingReloadRequestIdentifier
    ) -> Bool {
        reloadWillPerformCount += 1
        onWillPerformReload?(host)
        return true
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal,
        finalBarInsets: UIEdgeInsets,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    ) -> Bool {
        reloadFinalBarInsets.append(finalBarInsets)
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
        return true
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willSelect index: Int,
        animated: Bool
    ) {
        let event = Event.willSelect(index, animated)
        events.append(event)
        onWillSelect?(host, index, animated)
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didSelect index: Int,
        animated: Bool
    ) {
        let event = Event.didSelect(index, animated)
        events.append(event)
        onDidSelect?(host, index, animated)
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

@MainActor
private extension AnchorPagerPagingHostViewController {
    func reload(titles: [String], pageCount: Int, selectedIndex: Int) {
        reload(
            requestIdentifier: 0,
            titles: titles,
            pageCount: pageCount,
            selectedIndex: selectedIndex
        )
    }
}
