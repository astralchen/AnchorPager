import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerContainerScrollViewTests: XCTestCase {
    func testOnlyCommittedContainerChildPairRecognizesSimultaneously() {
        let container = AnchorPagerContainerScrollView()
        let child = UIScrollView()
        let unrelated = UIPanGestureRecognizer()
        container.bindCurrentChildPan(child.panGestureRecognizer)

        XCTAssertTrue(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: child.panGestureRecognizer
        ))
        XCTAssertFalse(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: unrelated
        ))
        XCTAssertFalse(container.gestureRecognizer(
            child.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: unrelated
        ))
    }

    func testRebindRejectsOldChildAndNilRemovesPair() {
        let container = AnchorPagerContainerScrollView()
        let oldChild = UIScrollView()
        let currentChild = UIScrollView()
        container.bindCurrentChildPan(oldChild.panGestureRecognizer)
        container.bindCurrentChildPan(currentChild.panGestureRecognizer)

        XCTAssertFalse(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: oldChild.panGestureRecognizer
        ))
        XCTAssertTrue(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: currentChild.panGestureRecognizer
        ))
        container.bindCurrentChildPan(nil)
        XCTAssertFalse(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: currentChild.panGestureRecognizer
        ))
    }

    func testBindingNeverChangesContainerOrChildPanDelegateIdentity() {
        let container = AnchorPagerContainerScrollView()
        let child = UIScrollView()
        let originalContainerDelegate = container.panGestureRecognizer.delegate
        let originalChildDelegate = child.panGestureRecognizer.delegate

        container.bindCurrentChildPan(child.panGestureRecognizer)
        container.bindCurrentChildPan(nil)

        XCTAssertTrue(container.panGestureRecognizer.delegate === originalContainerDelegate)
        XCTAssertTrue(child.panGestureRecognizer.delegate === originalChildDelegate)
    }

    func testUIKitPanDelegateDispatchesToContainerSubclassMethod() {
        let container = AnchorPagerContainerScrollView()
        let child = UIScrollView()
        container.bindCurrentChildPan(child.panGestureRecognizer)

        XCTAssertTrue(container.panGestureRecognizer.delegate === container)
        XCTAssertEqual(
            container.panGestureRecognizer.delegate?.gestureRecognizer?(
                container.panGestureRecognizer,
                shouldRecognizeSimultaneouslyWith: child.panGestureRecognizer
            ),
            true
        )
    }

    func testBindingLogsEnabledOnlyForNewNonNilPair() {
        let container = AnchorPagerContainerScrollView()
        let child = UIScrollView()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        container.bindCurrentChildPan(child.panGestureRecognizer)
        container.bindCurrentChildPan(child.panGestureRecognizer)
        container.bindCurrentChildPan(nil)

        XCTAssertEqual(
            events.filter { $0.event == "gesture.simultaneous.enabled" }.count,
            1
        )
    }
}
