import UIKit
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerManagedInsetCoordinatorTests: XCTestCase {
    func testApplyPreservesExternalInsetsAndMigratesDistanceFromTop() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let scrollView = UIScrollView()
        scrollView.contentInset = UIEdgeInsets(top: 10, left: 3, bottom: 7, right: 4)
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: 2,
            left: 1,
            bottom: 5,
            right: 6
        )
        scrollView.contentOffset.y = -10

        coordinator.apply(
            .init(
                content: UIEdgeInsets(top: 48, left: 0, bottom: 34, right: 0),
                indicators: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
            ),
            to: scrollView
        )

        XCTAssertEqual(
            scrollView.contentInset,
            UIEdgeInsets(top: 58, left: 3, bottom: 41, right: 4)
        )
        XCTAssertEqual(
            scrollView.verticalScrollIndicatorInsets,
            UIEdgeInsets(top: 2, left: 1, bottom: 39, right: 6)
        )
        XCTAssertEqual(scrollView.contentOffset.y, -58, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentInsetAdjustmentBehavior, .never)
    }

    func testUpdatePreservesRuntimeExternalDelta() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let scrollView = UIScrollView()
        scrollView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 7, right: 0)
        scrollView.contentOffset.y = -10

        coordinator.apply(
            .init(
                content: UIEdgeInsets(top: 48, left: 0, bottom: 34, right: 0),
                indicators: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
            ),
            to: scrollView
        )
        scrollView.contentInset.bottom += 5

        coordinator.apply(
            .init(
                content: UIEdgeInsets(top: 56, left: 0, bottom: 20, right: 0),
                indicators: UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
            ),
            to: scrollView
        )

        XCTAssertEqual(scrollView.contentInset.top, 66, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentInset.bottom, 32, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentOffset.y, -66, accuracy: 0.001)
    }

    func testReleaseRemovesOnlyManagedInsetsAndRestoresBehavior() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let scrollView = UIScrollView()
        scrollView.contentInsetAdjustmentBehavior = .always
        scrollView.automaticallyAdjustsScrollIndicatorInsets = true
        scrollView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 7, right: 0)
        scrollView.contentOffset.y = -10
        let target = AnchorPagerManagedInsetCoordinator.Target(
            content: UIEdgeInsets(top: 48, left: 0, bottom: 34, right: 0),
            indicators: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        )

        coordinator.apply(target, to: scrollView)
        XCTAssertFalse(scrollView.automaticallyAdjustsScrollIndicatorInsets)
        scrollView.contentInset.bottom += 5
        coordinator.release(scrollView)

        XCTAssertEqual(scrollView.contentInset.top, 10, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentInset.bottom, 12, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentOffset.y, -10, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentInsetAdjustmentBehavior, .always)
        XCTAssertTrue(scrollView.automaticallyAdjustsScrollIndicatorInsets)
    }

    func testRepeatedTargetReclaimsAutomaticIndicatorAdjustment() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let scrollView = UIScrollView()
        let target = AnchorPagerManagedInsetCoordinator.Target(
            content: UIEdgeInsets(top: 48, left: 0, bottom: 34, right: 0),
            indicators: UIEdgeInsets(top: 48, left: 0, bottom: 34, right: 0)
        )

        coordinator.apply(target, to: scrollView)
        scrollView.automaticallyAdjustsScrollIndicatorInsets = true
        coordinator.apply(target, to: scrollView)

        XCTAssertFalse(scrollView.automaticallyAdjustsScrollIndicatorInsets)
    }

    func testRepeatedTargetSkipsWritesAndWritesSkipLog() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let scrollView = UIScrollView()
        let target = AnchorPagerManagedInsetCoordinator.Target(
            content: UIEdgeInsets(top: 48, left: 0, bottom: 0, right: 0),
            indicators: .zero
        )
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        coordinator.apply(target, to: scrollView)
        events.removeAll()
        coordinator.apply(target, to: scrollView)

        XCTAssertEqual(
            events,
            [.init(category: .inset, level: .debug, event: "inset.ownership.skip")]
        )
    }

    func testCoordinatorDoesNotRetainManagedScrollView() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        weak var weakScrollView: UIScrollView?

        autoreleasepool {
            let scrollView = UIScrollView()
            weakScrollView = scrollView
            coordinator.apply(
                .init(
                    content: UIEdgeInsets(top: 48, left: 0, bottom: 0, right: 0),
                    indicators: .zero
                ),
                to: scrollView
            )
        }

        XCTAssertNil(weakScrollView)
        coordinator.releaseAll()
    }
}
