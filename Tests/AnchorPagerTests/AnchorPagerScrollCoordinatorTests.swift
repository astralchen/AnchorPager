import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerScrollCoordinatorTests: XCTestCase {
    func testUpwardPanCollapsesContainerThenScrollsChild() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)

        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y + fixture.child.contentInset.top,
            50,
            accuracy: 0.001
        )
    }

    func testDownwardPanReturnsChildThenExpandsContainer() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 100
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 80

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 130)

        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertEqual(fixture.container.contentOffset.y, 50, accuracy: 0.001)
    }

    func testExpandedTopBouncePinsChildAndKeepsContainerNegativeOffset() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = -24
        fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

        fixture.coordinator.containerDidScroll()

        XCTAssertEqual(fixture.container.contentOffset.y, -24, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
    }

    func testSameChildRebindIsIdempotentAndOldChildStopsAffectingReplacement() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let replacement = fixture.makeChild(maximumDistance: 300)

        fixture.coordinator.bindCommittedChild(fixture.child)
        fixture.coordinator.bindCommittedChild(replacement)
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 90

        XCTAssertEqual(
            replacement.contentOffset.y,
            -replacement.contentInset.top,
            accuracy: 0.001
        )
    }

    func testEmptyCommitBindsNilAndLeavesContainerSafe() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.bindCommittedChild(nil)
        fixture.container.contentOffset.y = 60

        fixture.coordinator.containerDidScroll()

        XCTAssertEqual(fixture.container.contentOffset.y, 60, accuracy: 0.001)
    }

    func testGuardedWritesDoNotReenter() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)

        XCTAssertEqual(events.filter { $0.event == "scroll.offset.guard.apply" }.count, 1)
        XCTAssertLessThanOrEqual(
            events.filter { $0.event == "scroll.offset.guard.skip" }.count,
            2
        )
    }

    func testRepeatedChangedDoesNotRepeatOwnerOrBoundaryLogs() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)

        XCTAssertEqual(events.filter { $0.event == "scroll.owner.child" }.count, 1)
        XCTAssertEqual(events.filter { $0.event == "scroll.boundary.collapsed" }.count, 1)
    }

    func testOldBindingTokenCannotModifyReplacementChild() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let oldToken = fixture.coordinator.bindingTokenForTesting
        let replacement = fixture.makeChild(maximumDistance: 300)
        fixture.coordinator.bindCommittedChild(replacement)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.coordinator.handleChildChangeForTesting(token: oldToken)

        XCTAssertEqual(
            replacement.contentOffset.y,
            -replacement.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertEqual(events.filter { $0.event == "scroll.binding.stale" }.count, 1)
    }

    func testContainerToChildAndChildToContainerEmitOneHandoffEach() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)
        fixture.coordinator.handlePan(state: .ended, translationY: -150)
        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 100)

        XCTAssertEqual(
            events.filter { $0.event == "scroll.handoff.containerToChild" }.count,
            1
        )
        XCTAssertEqual(
            events.filter { $0.event == "scroll.handoff.childToContainer" }.count,
            1
        )
    }

    func testInvalidateEmitsOneBindingAndResourceReleaseEvent() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.coordinator.invalidate()
        fixture.coordinator.invalidate()

        XCTAssertEqual(events.filter { $0.event == "scroll.binding.end" }.count, 1)
        XCTAssertEqual(
            events.filter { $0.event == "resource.scrollObservation.release" }.count,
            1
        )
    }
}

@MainActor
private final class Fixture {
    let container = AnchorPagerContainerScrollView()
    let child: UIScrollView
    let coordinator: AnchorPagerScrollCoordinator

    init(collapsedOffset: CGFloat, childMaximumDistance: CGFloat) {
        child = UIScrollView()
        container.bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        child.bounds = CGRect(x: 0, y: 0, width: 320, height: 600)
        child.contentInset = UIEdgeInsets(top: 50, left: 0, bottom: 0, right: 0)
        child.contentSize = CGSize(width: 320, height: 550 + childMaximumDistance)
        child.contentOffset.y = -child.contentInset.top
        coordinator = AnchorPagerScrollCoordinator(containerScrollView: container)
        coordinator.updateGeometry(collapsibleDistance: collapsedOffset)
        coordinator.bindCommittedChild(child)
    }

    func makeChild(maximumDistance: CGFloat) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.bounds = child.bounds
        scrollView.contentInset = child.contentInset
        scrollView.contentSize = CGSize(width: 320, height: 550 + maximumDistance)
        scrollView.contentOffset.y = -scrollView.contentInset.top
        return scrollView
    }
}
