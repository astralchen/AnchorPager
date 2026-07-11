import Foundation
import Pageboy
import Tabman
import UIKit
import XCTest
@testable import AnchorPager

final class AnchorPagerPagingAdapterTests: XCTestCase {
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
        adapter.reload(
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
    func testNilBarHeightUsesAdaptiveTabmanHeight() {
        let adapter = AnchorPagerPagingAdapter()
        adapter.setBarHeight(nil)
        adapter.reload(
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
    func testAdapterSuppliesTitlesAndViewControllersToTabmanAndPageboy() {
        let adapter = AnchorPagerPagingAdapter()
        let first = UIViewController()
        let second = UIViewController()

        adapter.reload(titles: ["First", "Second"], viewControllers: [first, second], selectedIndex: 1)

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
    func testAdapterForwardsPageboyEventsWithoutLeakingPageboyTypes() {
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        adapter.reload(
            titles: ["First", "Second"],
            viewControllers: [UIViewController(), UIViewController()],
            selectedIndex: 0
        )

        adapter.pageboyViewController(adapter, willScrollToPageAt: 1, direction: .forward, animated: true)
        adapter.pageboyViewController(adapter, didScrollToPageAt: 1, direction: .forward, animated: true)
        adapter.pageboyViewController(adapter, didCancelScrollToPageAt: 1, returnToPageAt: 0)

        XCTAssertEqual(delegate.events, [.willSelect(1, true), .didSelect(1, true), .didCancel(1, 0)])
    }

    @MainActor
    func testSetSelectedIndexReturnsRequestStatusAndWaitsForTerminalCallback() {
        let adapter = AnchorPagerPagingAdapter()
        let delegate = RecordingPagingDelegate()
        adapter.eventDelegate = delegate
        adapter.loadViewIfNeeded()
        adapter.reload(
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
        adapter.reload(
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
        adapter.reload(
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
        adapter.reload(
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
}

@MainActor
private final class RecordingPagingDelegate: AnchorPagerPagingAdapterDelegate {
    enum Event: Equatable {
        case willSelect(Int, Bool)
        case didSelect(Int, Bool)
        case didCancel(Int, Int)
    }

    var events: [Event] = []
    var barInsets: [UIEdgeInsets] = []

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {
        self.barInsets.append(barInsets)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        willSelect index: Int,
        animated: Bool
    ) {
        events.append(.willSelect(index, animated))
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didSelect index: Int,
        animated: Bool
    ) {
        events.append(.didSelect(index, animated))
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    ) {
        events.append(.didCancel(index, previousIndex))
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
