import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerInteractionCoordinatorTests: XCTestCase {
    func testVerticalStatesBeginUpdateFinishAndCancel() {
        let coordinator = AnchorPagerInteractionCoordinator()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(coordinator.isReadyForDeferredWorkDrain)
        XCTAssertTrue(coordinator.begin(.verticalDragging(identifier: 1)))
        XCTAssertEqual(coordinator.state, .verticalDragging(identifier: 1))
        XCTAssertTrue(coordinator.updateBoundary(to: .topOverscrolling(identifier: 1)))
        XCTAssertEqual(coordinator.state, .topOverscrolling(identifier: 1))
        XCTAssertTrue(coordinator.finish(.topOverscrolling(identifier: 1)))
        XCTAssertEqual(coordinator.state, .verticalDragging(identifier: 1))
        XCTAssertTrue(coordinator.begin(.verticalDecelerating(identifier: 1)))
        XCTAssertEqual(coordinator.state, .verticalDecelerating(identifier: 1))
        XCTAssertTrue(coordinator.finish(.verticalDecelerating(identifier: 1)))
        XCTAssertEqual(coordinator.state, .idle)

        XCTAssertTrue(coordinator.begin(.verticalDragging(identifier: 2)))
        XCTAssertTrue(coordinator.updateBoundary(to: .topOverscrolling(identifier: 2)))
        XCTAssertTrue(coordinator.cancel(.topOverscrolling(identifier: 2)))
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testPagingAndLayoutStatesRequireMatchingIdentifierToFinishOrCancel() {
        let states: [AnchorPagerInteractionState] = [
            .horizontalPaging(identifier: 11),
            .programmaticPaging(identifier: 12),
            .layoutReloading(identifier: 13),
        ]

        for state in states {
            let coordinator = AnchorPagerInteractionCoordinator()
            XCTAssertTrue(coordinator.begin(state))
            XCTAssertTrue(coordinator.begin(state))
            XCTAssertFalse(coordinator.finish(state.replacingIdentifierForTesting(with: 99)))
            XCTAssertEqual(coordinator.state, state)
            XCTAssertTrue(coordinator.cancel(state))
            XCTAssertEqual(coordinator.state, .idle)
        }
    }

    func testIllegalLowerPriorityBeginDoesNotReplaceActiveState() {
        let coordinator = AnchorPagerInteractionCoordinator()

        XCTAssertTrue(coordinator.begin(.programmaticPaging(identifier: 21)))
        XCTAssertFalse(coordinator.begin(.verticalDragging(identifier: 22)))
        XCTAssertEqual(coordinator.state, .programmaticPaging(identifier: 21))

        coordinator.beginSizeTransition(identifier: 23)
        XCTAssertEqual(coordinator.state, .transitioningSize(identifier: 23))
        XCTAssertFalse(coordinator.begin(.layoutReloading(identifier: 24)))
        XCTAssertEqual(coordinator.state, .transitioningSize(identifier: 23))
    }

    func testSizeTransitionSuspendsAndRestoresPagingOrLayoutState() {
        let resumableStates: [AnchorPagerInteractionState] = [
            .horizontalPaging(identifier: 31),
            .programmaticPaging(identifier: 32),
            .layoutReloading(identifier: 33),
        ]

        for state in resumableStates {
            let coordinator = AnchorPagerInteractionCoordinator()
            XCTAssertTrue(coordinator.begin(state))

            coordinator.beginSizeTransition(identifier: 40)
            XCTAssertEqual(coordinator.state, .transitioningSize(identifier: 40))
            XCTAssertFalse(coordinator.isReadyForDeferredWorkDrain)

            coordinator.finishSizeTransition(identifier: 40)
            XCTAssertEqual(coordinator.state, state)
            XCTAssertFalse(coordinator.isReadyForDeferredWorkDrain)
            XCTAssertTrue(coordinator.finish(state))
            XCTAssertEqual(coordinator.state, .idle)
        }
    }

    func testTerminalDuringSizeClearsSuspendedResumeAndBecomesDrainReadyOnce() {
        let coordinator = AnchorPagerInteractionCoordinator()
        XCTAssertTrue(coordinator.begin(.programmaticPaging(identifier: 51)))
        coordinator.beginSizeTransition(identifier: 52)

        XCTAssertTrue(coordinator.finish(.programmaticPaging(identifier: 51)))
        XCTAssertEqual(coordinator.state, .transitioningSize(identifier: 52))
        coordinator.finishSizeTransition(identifier: 52)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(coordinator.isReadyForDeferredWorkDrain)
        coordinator.finishSizeTransition(identifier: 52)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testSizeTransitionDoesNotResumeVerticalState() {
        let coordinator = AnchorPagerInteractionCoordinator()
        XCTAssertTrue(coordinator.begin(.verticalDragging(identifier: 61)))

        coordinator.beginSizeTransition(identifier: 62)
        coordinator.finishSizeTransition(identifier: 62)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(coordinator.isReadyForDeferredWorkDrain)
    }

    func testBoundaryUpdateRejectsWrongStateOrIdentifier() {
        let coordinator = AnchorPagerInteractionCoordinator()
        XCTAssertFalse(coordinator.begin(.topOverscrolling(identifier: 70)))
        XCTAssertFalse(coordinator.begin(.verticalDecelerating(identifier: 70)))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(coordinator.begin(.verticalDragging(identifier: 71)))

        XCTAssertFalse(coordinator.updateBoundary(to: .topOverscrolling(identifier: 72)))
        XCTAssertFalse(coordinator.updateBoundary(to: .horizontalPaging(identifier: 71)))
        XCTAssertEqual(coordinator.state, .verticalDragging(identifier: 71))
        XCTAssertTrue(coordinator.updateBoundary(to: .topOverscrolling(identifier: 71)))
        XCTAssertTrue(coordinator.updateBoundary(to: .topOverscrolling(identifier: 71)))
        XCTAssertEqual(coordinator.state, .topOverscrolling(identifier: 71))
    }

    func testLogsFixedEventNamesAndSuppressesRepeatedInvalidTransition() {
        let coordinator = AnchorPagerInteractionCoordinator()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        XCTAssertTrue(coordinator.begin(.verticalDragging(identifier: 801)))
        XCTAssertTrue(coordinator.begin(.verticalDragging(identifier: 801)))
        XCTAssertTrue(coordinator.updateBoundary(to: .topOverscrolling(identifier: 801)))
        XCTAssertTrue(coordinator.finish(.topOverscrolling(identifier: 801)))
        XCTAssertTrue(coordinator.cancel(.verticalDragging(identifier: 801)))
        XCTAssertFalse(coordinator.finish(.verticalDragging(identifier: 801)))
        XCTAssertFalse(coordinator.finish(.verticalDragging(identifier: 801)))

        XCTAssertEqual(
            events,
            [
                .init(category: .gesture, level: .info, event: "interaction.state.begin"),
                .init(
                    category: .gesture,
                    level: .debug,
                    event: "interaction.state.updateBoundary"
                ),
                .init(category: .gesture, level: .info, event: "interaction.state.finish"),
                .init(category: .gesture, level: .info, event: "interaction.state.cancel"),
                .init(
                    category: .gesture,
                    level: .debug,
                    event: "interaction.state.invalidTransition"
                ),
            ]
        )
        XCTAssertFalse(events.contains { event in
            event.event.contains("801") || event.event.contains("=")
        })
    }
}

private extension AnchorPagerInteractionState {
    func replacingIdentifierForTesting(with identifier: Int) -> Self {
        switch self {
        case .idle:
            return .idle
        case .verticalDragging:
            return .verticalDragging(identifier: identifier)
        case .verticalDecelerating:
            return .verticalDecelerating(identifier: identifier)
        case .horizontalPaging:
            return .horizontalPaging(identifier: identifier)
        case .programmaticPaging:
            return .programmaticPaging(identifier: identifier)
        case .topOverscrolling:
            return .topOverscrolling(identifier: identifier)
        case .layoutReloading:
            return .layoutReloading(identifier: identifier)
        case .transitioningSize:
            return .transitioningSize(identifier: identifier)
        }
    }
}
