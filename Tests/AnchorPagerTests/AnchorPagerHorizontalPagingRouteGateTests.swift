import UIKit
import XCTest
@testable import AnchorPager

final class AnchorPagerHorizontalPagingRouteGateTests: XCTestCase {
    @MainActor
    func testInteriorBusinessScrollMakesGateBeginWithoutChangingDelegates() {
        let paging = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let business = UIScrollView(frame: paging.bounds)
        business.contentSize = CGSize(width: 900, height: 700)
        business.contentOffset.x = 120
        paging.addSubview(business)
        let originalScrollDelegate = business.delegate
        let originalPanDelegate = business.panGestureRecognizer.delegate
        let gate = AnchorPagerHorizontalPagingRouteGate(
            pagingScrollView: paging,
            pagingPan: paging.panGestureRecognizer,
            hitTest: { _, _ in business },
            velocity: { _, _ in CGPoint(x: -400, y: 0) }
        )
        paging.addGestureRecognizer(gate)

        XCTAssertTrue(gate.gestureRecognizerShouldBegin(gate))
        XCTAssertTrue(business.delegate === originalScrollDelegate)
        XCTAssertTrue(business.panGestureRecognizer.delegate === originalPanDelegate)
        XCTAssertFalse(gate.cancelsTouchesInView)
    }

    @MainActor
    func testBoundaryMakesGateFailAndNestedOuterCandidateCanStillConsume() {
        let paging = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let outer = UIScrollView(frame: paging.bounds)
        outer.contentSize = CGSize(width: 600, height: 700)
        outer.contentOffset.x = 80
        let inner = UIScrollView(frame: outer.bounds)
        inner.contentSize = CGSize(width: 900, height: 700)
        inner.contentOffset.x = 510
        paging.addSubview(outer)
        outer.addSubview(inner)
        let gate = AnchorPagerHorizontalPagingRouteGate(
            pagingScrollView: paging,
            pagingPan: paging.panGestureRecognizer,
            hitTest: { _, _ in inner },
            velocity: { _, _ in CGPoint(x: -400, y: 0) }
        )
        paging.addGestureRecognizer(gate)

        XCTAssertTrue(gate.gestureRecognizerShouldBegin(gate))

        outer.contentOffset.x = 210
        XCTAssertFalse(gate.gestureRecognizerShouldBegin(gate))
    }

    @MainActor
    func testGateOnlyAllowsSimultaneousRecognitionWithNonPagingRecognizer() {
        let paging = UIScrollView()
        let business = UIScrollView()
        let gate = AnchorPagerHorizontalPagingRouteGate(
            pagingScrollView: paging,
            pagingPan: paging.panGestureRecognizer
        )

        XCTAssertTrue(
            gate.gestureRecognizer(
                gate,
                shouldRecognizeSimultaneouslyWith: business.panGestureRecognizer
            )
        )
        XCTAssertFalse(
            gate.gestureRecognizer(
                gate,
                shouldRecognizeSimultaneouslyWith: paging.panGestureRecognizer
            )
        )
    }

    func testSourceOnlyAssignsItsOwnDelegateAndUsesNoPrivateOrMutatingEscapeHatches() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/AnchorPager/Gesture/AnchorPagerHorizontalPagingRouteGate.swift"
            ),
            encoding: .utf8
        )

        XCTAssertEqual(source.components(separatedBy: "delegate = self").count - 1, 1)
        XCTAssertFalse(source.contains(".delegate ="))
        XCTAssertFalse(source.contains("setValue("))
        XCTAssertFalse(source.contains("value(forKey:"))
        XCTAssertFalse(source.contains("_UI"))
        XCTAssertFalse(source.contains("contentOffset ="))
        XCTAssertFalse(source.contains("isScrollEnabled ="))
        XCTAssertFalse(source.contains(".bounces ="))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
