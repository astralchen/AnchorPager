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

        host.reload(titles: [], pageCount: 0, selectedIndex: 0)
        XCTAssertFalse(host.setSelectedIndex(0, animated: false))
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
    }

    var events: [Event] = []
    var terminalSnapshots: [TerminalSnapshot] = []

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal
    ) {
        events.append(.reload(terminal))
        terminalSnapshots.append(
            TerminalSnapshot(
                hasActiveAdapter: host.activeAdapter != nil,
                childCount: host.children.count
            )
        )
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willSelect index: Int,
        animated: Bool
    ) {
        events.append(.willSelect(index, animated))
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didSelect index: Int,
        animated: Bool
    ) {
        events.append(.didSelect(index, animated))
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    ) {
        events.append(.didCancel(index, previousIndex))
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {
        events.append(.barInsets(barInsets))
    }
}
