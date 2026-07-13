import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerOverscrollCoordinatorTests: XCTestCase {
    func testTopOwnerMatrix() {
        XCTAssertEqual(route(mode: .none, hasChild: true), .clampStableBoundary(.top))
        XCTAssertEqual(route(mode: .container, hasChild: true), .passThrough(.init(boundary: .top, owner: .container)))
        XCTAssertEqual(route(mode: .child, hasChild: true), .passThrough(.init(boundary: .top, owner: .child)))
        XCTAssertEqual(route(mode: .none, hasChild: false), .clampStableBoundary(.top))
        XCTAssertEqual(route(mode: .container, hasChild: false), .passThrough(.init(boundary: .top, owner: .container)))
        XCTAssertEqual(route(mode: .child, hasChild: false), .clampStableBoundary(.top))
    }

    func testBottomOwnerDependsOnlyOnChildAvailability() {
        let child = AnchorPagerOverscrollCoordinator(topMode: .none)
        XCTAssertEqual(
            child.begin(boundary: .bottom, hasChild: true),
            .passThrough(.init(boundary: .bottom, owner: .child))
        )
        let plain = AnchorPagerOverscrollCoordinator(topMode: .child)
        XCTAssertEqual(
            plain.begin(boundary: .bottom, hasChild: false),
            .passThrough(.init(boundary: .bottom, owner: .container))
        )
    }

    func testOwnerFinishesOnlyAfterVisibleOverflowReturnsToStableRange() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        _ = coordinator.begin(boundary: .top, hasChild: true)

        XCTAssertEqual(coordinator.observeActiveOverflow(0), .active)
        XCTAssertEqual(coordinator.observeActiveOverflow(8), .active)
        XCTAssertEqual(coordinator.observeActiveOverflow(0.4), .finished)
        XCTAssertNil(coordinator.activeOwner)
    }

    func testOverflowThresholdRequiresStrictlyMoreThanHalfPoint() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        _ = coordinator.begin(boundary: .top, hasChild: true)

        XCTAssertEqual(coordinator.observeActiveOverflow(0.5), .active)
        XCTAssertNotNil(coordinator.activeOwner)
        XCTAssertEqual(coordinator.observeActiveOverflow(0.5001), .active)
        XCTAssertNotNil(coordinator.activeOwner)
        XCTAssertEqual(coordinator.observeActiveOverflow(0.5), .finished)
        XCTAssertNil(coordinator.activeOwner)
    }

    func testChildWithoutTargetLogsUnavailableOnlyOncePerInteraction() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .child)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        _ = coordinator.begin(boundary: .top, hasChild: false)
        _ = coordinator.begin(boundary: .top, hasChild: false)

        XCTAssertEqual(events.filter { $0.event == "overscroll.owner.unavailable" }.count, 1)
    }

    func testModeChangeCancelsActiveOwner() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        _ = coordinator.begin(boundary: .top, hasChild: true)

        coordinator.updateTopMode(.child)

        XCTAssertNil(coordinator.activeOwner)
        XCTAssertEqual(coordinator.topMode, .child)
    }

    func testRepeatedBeginLogsBoundaryAndOwnerBeginOnlyOncePerInteraction() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        XCTAssertEqual(
            coordinator.begin(boundary: .top, hasChild: true),
            .passThrough(.init(boundary: .top, owner: .container))
        )
        XCTAssertEqual(
            coordinator.begin(boundary: .top, hasChild: true),
            .passThrough(.init(boundary: .top, owner: .container))
        )

        XCTAssertEqual(
            events.map(\.event),
            [
                "overscroll.boundary.top",
                "overscroll.owner.container.begin"
            ]
        )
    }

    func testUnpresentedTopOwnerFinishesBeforeRoutingBottomBoundary() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .child)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        _ = coordinator.begin(boundary: .top, hasChild: true)

        XCTAssertEqual(
            coordinator.begin(boundary: .bottom, hasChild: true),
            .passThrough(.init(boundary: .bottom, owner: .child))
        )
        XCTAssertEqual(
            coordinator.activeOwner,
            .init(boundary: .bottom, owner: .child)
        )
        XCTAssertEqual(
            events.map(\.event),
            [
                "overscroll.boundary.top",
                "overscroll.owner.child.begin",
                "overscroll.owner.finish",
                "overscroll.boundary.bottom",
                "overscroll.owner.child.begin"
            ]
        )
    }

    func testUnpresentedBottomOwnerFinishesBeforeRoutingTopBoundary() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        _ = coordinator.begin(boundary: .bottom, hasChild: false)

        XCTAssertEqual(
            coordinator.begin(boundary: .top, hasChild: false),
            .passThrough(.init(boundary: .top, owner: .container))
        )
        XCTAssertEqual(
            coordinator.activeOwner,
            .init(boundary: .top, owner: .container)
        )
        XCTAssertEqual(
            events.map(\.event),
            [
                "overscroll.boundary.bottom",
                "overscroll.owner.container.begin",
                "overscroll.owner.finish",
                "overscroll.boundary.top",
                "overscroll.owner.container.begin"
            ]
        )
    }

    func testPresentedOwnerKeepsBoundaryUntilOverflowReturnsToStableRange() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)

        _ = coordinator.begin(boundary: .top, hasChild: false)
        XCTAssertEqual(coordinator.observeActiveOverflow(8), .active)

        XCTAssertEqual(
            coordinator.begin(boundary: .bottom, hasChild: false),
            .passThrough(.init(boundary: .top, owner: .container))
        )
        XCTAssertEqual(
            coordinator.activeOwner,
            .init(boundary: .top, owner: .container)
        )

        XCTAssertEqual(coordinator.observeActiveOverflow(0.5), .finished)
        XCTAssertEqual(
            coordinator.begin(boundary: .bottom, hasChild: false),
            .passThrough(.init(boundary: .bottom, owner: .container))
        )
    }

    func testOwnerLifecycleAndModeChangeLogsOnceInRequiredOrder() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        _ = coordinator.begin(boundary: .top, hasChild: true)
        _ = coordinator.begin(boundary: .top, hasChild: true)
        coordinator.updateTopMode(.child)
        _ = coordinator.begin(boundary: .top, hasChild: true)
        XCTAssertEqual(coordinator.observeActiveOverflow(0.5001), .active)
        XCTAssertEqual(coordinator.observeActiveOverflow(0.5), .finished)

        let eventNames = events.map(\.event)
        XCTAssertEqual(
            eventNames,
            [
                "overscroll.boundary.top",
                "overscroll.owner.container.begin",
                "overscroll.owner.cancel",
                "overscroll.mode.changed",
                "overscroll.boundary.top",
                "overscroll.owner.child.begin",
                "overscroll.owner.finish"
            ]
        )
        XCTAssertEqual(eventNames.filter { $0 == "overscroll.owner.container.begin" }.count, 1)
        XCTAssertEqual(eventNames.filter { $0 == "overscroll.owner.child.begin" }.count, 1)
        XCTAssertEqual(eventNames.filter { $0 == "overscroll.owner.finish" }.count, 1)
        XCTAssertEqual(eventNames.filter { $0 == "overscroll.owner.cancel" }.count, 1)
        XCTAssertEqual(eventNames.filter { $0 == "overscroll.mode.changed" }.count, 1)
    }

    func testEndInteractionFinishesOwnerAndResetsBoundaryState() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        _ = coordinator.begin(boundary: .top, hasChild: true)

        XCTAssertTrue(coordinator.endInteraction())
        XCTAssertNil(coordinator.activeOwner)
        XCTAssertEqual(
            coordinator.begin(boundary: .top, hasChild: true),
            .passThrough(.init(boundary: .top, owner: .container))
        )
        XCTAssertEqual(
            events.map(\.event),
            [
                "overscroll.boundary.top",
                "overscroll.owner.container.begin",
                "overscroll.owner.finish",
                "overscroll.boundary.top",
                "overscroll.owner.container.begin"
            ]
        )
    }

    func testFinishUnpresentedActiveOwnerOnlyFinishesBeforeVisibleOverflow() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .child)

        _ = coordinator.begin(boundary: .top, hasChild: true)

        XCTAssertEqual(coordinator.finishUnpresentedActiveOwner(), .finished)
        XCTAssertNil(coordinator.activeOwner)

        _ = coordinator.begin(boundary: .top, hasChild: true)
        XCTAssertEqual(coordinator.observeActiveOverflow(0.5001), .active)

        XCTAssertEqual(coordinator.finishUnpresentedActiveOwner(), .presented)
        XCTAssertEqual(
            coordinator.activeOwner,
            .init(boundary: .top, owner: .child)
        )
    }

    func testFinishUnpresentedActiveOwnerReportsInactiveWithoutOwner() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)

        XCTAssertEqual(coordinator.finishUnpresentedActiveOwner(), .inactive)
    }

    func testReachedStableRangeResetsBoundaryAndUnavailableState() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .child)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        XCTAssertEqual(
            coordinator.begin(boundary: .top, hasChild: false),
            .clampStableBoundary(.top)
        )
        XCTAssertEqual(
            coordinator.begin(boundary: .top, hasChild: false),
            .clampStableBoundary(.top)
        )

        coordinator.reachedStableRange()

        XCTAssertEqual(
            coordinator.begin(boundary: .top, hasChild: false),
            .clampStableBoundary(.top)
        )
        XCTAssertEqual(
            events.map(\.event),
            [
                "overscroll.boundary.top",
                "overscroll.owner.unavailable",
                "overscroll.boundary.top",
                "overscroll.owner.unavailable"
            ]
        )
    }

    func testDirectCancelClearsActiveOwnerAndResetsBoundaryState() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        _ = coordinator.begin(boundary: .bottom, hasChild: false)
        XCTAssertEqual(coordinator.observeActiveOverflow(1), .active)

        XCTAssertTrue(coordinator.cancel())
        XCTAssertNil(coordinator.activeOwner)
        XCTAssertFalse(coordinator.cancel())
        XCTAssertEqual(
            coordinator.begin(boundary: .bottom, hasChild: false),
            .passThrough(.init(boundary: .bottom, owner: .container))
        )
        XCTAssertEqual(
            events.map(\.event),
            [
                "overscroll.boundary.bottom",
                "overscroll.owner.container.begin",
                "overscroll.owner.cancel",
                "overscroll.boundary.bottom",
                "overscroll.owner.container.begin"
            ]
        )
    }

    private func route(
        mode: AnchorPagerTopOverscrollHandlingMode,
        hasChild: Bool
    ) -> AnchorPagerOverscrollCoordinator.Route {
        AnchorPagerOverscrollCoordinator(topMode: mode)
            .begin(boundary: .top, hasChild: hasChild)
    }
}
