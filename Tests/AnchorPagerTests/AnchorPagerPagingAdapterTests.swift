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
