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

    private func route(
        mode: AnchorPagerTopOverscrollHandlingMode,
        hasChild: Bool
    ) -> AnchorPagerOverscrollCoordinator.Route {
        AnchorPagerOverscrollCoordinator(topMode: mode)
            .begin(boundary: .top, hasChild: hasChild)
    }
}
