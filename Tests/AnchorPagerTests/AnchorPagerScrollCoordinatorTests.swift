import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerScrollCoordinatorTests: XCTestCase {
    func testNoneModeClampsContainerAndChildAtExpandedBoundary() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.updateTopOverscrollHandlingMode(.none)
        fixture.container.contentOffset.y = -20
        fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

        fixture.coordinator.containerDidScroll()

        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
    }

    func testChildModeKeepsContainerExpandedAndPassesThroughChildTop() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.updateTopOverscrollHandlingMode(.child)
        fixture.container.contentOffset.y = -20
        fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

        fixture.coordinator.handleChildChangeForTesting(
            token: fixture.coordinator.bindingTokenForTesting
        )

        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top - 12,
            accuracy: 0.001
        )
    }

    func testChildModeWithNilTargetClampsWithoutFallback() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.bindCommittedChild(nil)
        fixture.coordinator.updateTopOverscrollHandlingMode(.child)
        fixture.container.contentOffset.y = -20

        fixture.coordinator.containerDidScroll()

        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
    }

    func testModesNeverChangeBusinessBounceConfiguration() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 0)
        fixture.child.bounces = false
        fixture.child.alwaysBounceVertical = false

        for mode in [
            AnchorPagerTopOverscrollHandlingMode.none,
            .container,
            .child
        ] {
            fixture.coordinator.updateTopOverscrollHandlingMode(mode)
            fixture.coordinator.handlePan(state: .began, translationY: 0)
            fixture.coordinator.handlePan(state: .changed, translationY: 40)
            fixture.coordinator.handlePan(state: .cancelled, translationY: 40)
            XCTAssertFalse(fixture.child.bounces)
            XCTAssertFalse(fixture.child.alwaysBounceVertical)
        }
    }

    func testBindingPanAndInvalidateKeepBusinessBounceConfiguration() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.child.bounces = false
        fixture.child.alwaysBounceVertical = true
        fixture.coordinator.bindCommittedChild(nil)
        fixture.coordinator.bindCommittedChild(fixture.child)

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)
        fixture.coordinator.handlePan(state: .ended, translationY: -150)
        fixture.coordinator.invalidate()

        XCTAssertFalse(fixture.child.bounces)
        XCTAssertTrue(fixture.child.alwaysBounceVertical)
    }

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

    func testDefaultContainerTopPassThroughKeepsNegativeContainerAndPinsChild() {
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

    func testContainerTopPassThroughDoesNotInvokeOwnerOffsetSetter() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = -24
        fixture.coordinator.containerDidScroll()
        let ownerSetterInvoked = expectation(description: "owner setter 不应被调用")
        ownerSetterInvoked.isInverted = true
        let observation = fixture.container.observe(\.contentOffset, options: [.new]) { _, _ in
            ownerSetterInvoked.fulfill()
        }

        fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

        wait(for: [ownerSetterInvoked], timeout: 0.01)
        XCTAssertEqual(fixture.container.contentOffset.y, -24, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .container)
        )
        observation.invalidate()
    }

    func testZeroStableRangeDownwardPanSelectsOnlyTopBoundary() {
        let fixture = Fixture(collapsedOffset: 0, childMaximumDistance: 0)

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 24)

        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .container)
        )
    }

    func testZeroStableRangeUpwardPanSelectsOnlyBottomBoundary() {
        let fixture = Fixture(collapsedOffset: 0, childMaximumDistance: 0)

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -24)

        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .bottom, owner: .child)
        )
    }

    func testZeroStableRangeSwitchesFromUnpresentedChildTopToBottomWithoutStableCallback() {
        let fixture = Fixture(collapsedOffset: 0, childMaximumDistance: 0)
        fixture.coordinator.updateTopOverscrollHandlingMode(.child)
        fixture.child.bounces = false

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 24)
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .child)
        )

        fixture.coordinator.handlePan(state: .changed, translationY: -24)

        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .bottom, owner: .child)
        )
        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertFalse(fixture.child.bounces)
    }

    func testZeroStableRangeSwitchesFromUnpresentedChildBottomToContainerTopWithoutStableCallback() {
        let fixture = Fixture(collapsedOffset: 0, childMaximumDistance: 0)
        fixture.child.bounces = true
        fixture.child.alwaysBounceVertical = false

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -24)
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .bottom, owner: .child)
        )

        fixture.coordinator.handlePan(state: .changed, translationY: 24)

        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .container)
        )
        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertTrue(fixture.child.bounces)
        XCTAssertFalse(fixture.child.alwaysBounceVertical)
    }

    func testCancelBoundaryHandlingClearsOwnerAndSettlesStableOffsets() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = -24
        fixture.coordinator.containerDidScroll()

        fixture.coordinator.cancelBoundaryHandling()

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
    }

    func testEndInteractionWithoutVisibleOverflowFinishesOwner() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 1)
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .container)
        )

        fixture.coordinator.handlePan(state: .ended, translationY: 1)

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
    }

    func testUnpresentedChildTopOwnerReversesIntoStableRangeWhenBounceIsDisabled() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.updateTopOverscrollHandlingMode(.child)
        fixture.child.bounces = false

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 24)
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .child)
        )

        fixture.coordinator.handlePan(state: .changed, translationY: -30)

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 30, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertFalse(fixture.child.bounces)
    }

    func testUnpresentedShortChildTopOwnerReversesWithoutAlwaysBounceVertical() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 0)
        fixture.coordinator.updateTopOverscrollHandlingMode(.child)
        fixture.child.alwaysBounceVertical = false

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 24)
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .child)
        )

        fixture.coordinator.handlePan(state: .changed, translationY: -30)

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 30, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertFalse(fixture.child.alwaysBounceVertical)
    }

    func testUnpresentedRealChildBottomOwnerReversesWithoutDroppingDelta() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 100
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 500
        fixture.child.bounces = false

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -24)
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .bottom, owner: .child)
        )

        fixture.coordinator.handlePan(state: .changed, translationY: 30)

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y + fixture.child.contentInset.top,
            470,
            accuracy: 0.001
        )
        XCTAssertFalse(fixture.child.bounces)
    }

    func testPresentedChildTopOwnerObserverFinishPreservesRawTotalBeforePanCallback() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.updateTopOverscrollHandlingMode(.child)
        fixture.child.bounces = true
        fixture.child.alwaysBounceVertical = true
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 24)
        fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .child)
        )

        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 6

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 6, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertEqual(
            fixture.container.contentOffset.y
                + fixture.child.contentOffset.y
                + fixture.child.contentInset.top,
            6,
            accuracy: 0.001
        )

        fixture.coordinator.handlePan(state: .changed, translationY: -6)

        XCTAssertEqual(fixture.container.contentOffset.y, 6, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertEqual(
            events.filter { $0.event == "overscroll.owner.finish" }.count,
            1
        )
        XCTAssertTrue(fixture.child.bounces)
        XCTAssertTrue(fixture.child.alwaysBounceVertical)
    }

    func testPresentedChildTopOwnerPanFirstThenObserverFinishPreservesRawTotal() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.updateTopOverscrollHandlingMode(.child)
        fixture.child.bounces = true
        fixture.child.alwaysBounceVertical = true
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 24)
        fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

        fixture.coordinator.handlePan(state: .changed, translationY: -6)
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .child)
        )
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 6

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 6, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertEqual(
            fixture.container.contentOffset.y
                + fixture.child.contentOffset.y
                + fixture.child.contentInset.top,
            6,
            accuracy: 0.001
        )
        XCTAssertEqual(
            events.filter { $0.event == "overscroll.owner.finish" }.count,
            1
        )
        XCTAssertTrue(fixture.child.bounces)
        XCTAssertTrue(fixture.child.alwaysBounceVertical)
    }

    func testPanAppliesCurrentResolverInputImmediatelyWhenPresentedOwnerFinishes() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.child.bounces = false
        fixture.child.alwaysBounceVertical = true
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 24)
        fixture.container.contentOffset.y = -12
        fixture.coordinator.containerDidScroll()
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .container)
        )

        fixture.container.contentOffset.y = 6
        fixture.coordinator.handlePan(state: .changed, translationY: -6)

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 6, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertEqual(
            events.filter { $0.event == "overscroll.owner.finish" }.count,
            1
        )
        XCTAssertFalse(fixture.child.bounces)
        XCTAssertTrue(fixture.child.alwaysBounceVertical)
    }

    func testObservedContainerTopFinishKeepsExpandedStablePosition() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = -12
        fixture.coordinator.containerDidScroll()

        fixture.container.contentOffset.y = 0
        fixture.coordinator.containerDidScroll()

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
    }

    func testObservedChildBottomFinishKeepsCollapsedMaximumStablePosition() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 100
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 524

        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 500

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y + fixture.child.contentInset.top,
            500,
            accuracy: 0.001
        )
    }

    func testObservedPlainContainerBottomFinishKeepsCollapsedStablePosition() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.bindCommittedChild(nil)
        fixture.container.contentOffset.y = 124
        fixture.coordinator.containerDidScroll()

        fixture.container.contentOffset.y = 100
        fixture.coordinator.containerDidScroll()

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
    }

    func testChangedGeometryCancelsActiveBoundaryAndSettlesStableOffsets() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = -24
        fixture.coordinator.containerDidScroll()

        fixture.coordinator.updateGeometry(
            AnchorPagerContainerScrollGeometry(
                topInset: 0,
                collapsibleDistance: 120
            )
        )

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
    }

    func testInsetGeometryUsesLogicalOffsetsForHandoffAndBoundaries() {
        let fixture = Fixture(
            collapsedOffset: 100,
            childMaximumDistance: 500,
            topInset: 44
        )

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)
        XCTAssertEqual(fixture.container.contentOffset.y, 56, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y + fixture.child.contentInset.top,
            50,
            accuracy: 0.001
        )

        fixture.container.contentOffset.y = -68
        fixture.coordinator.containerDidScroll()
        XCTAssertEqual(fixture.container.contentOffset.y, -68, accuracy: 0.001)

        fixture.coordinator.cancelBoundaryHandling()
        XCTAssertEqual(fixture.container.contentOffset.y, -44, accuracy: 0.001)
    }

    func testChildTopModePinsContainerToInsetExpandedBoundary() {
        let fixture = Fixture(topInset: 44)
        fixture.coordinator.updateTopOverscrollHandlingMode(.child)
        fixture.container.contentOffset.y = -68
        fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

        fixture.coordinator.containerDidScroll()

        XCTAssertEqual(fixture.container.contentOffset.y, -44, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top - 12,
            accuracy: 0.001
        )
    }

    func testGeometryMigrationWritesRawOffsetForPreservedLogicalDistance() {
        let fixture = Fixture(topInset: 44)
        fixture.container.contentOffset.y = -4

        fixture.coordinator.updateGeometry(
            AnchorPagerContainerScrollGeometry(
                topInset: 0,
                collapsibleDistance: 100
            ),
            targetLogicalOffset: 40
        )

        XCTAssertEqual(fixture.container.contentOffset.y, 40, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
    }

    func testInsetOnlyGeometryMigrationDoesNotRepeatStableBoundaryLogs() {
        let fixture = Fixture(topInset: 44)
        fixture.container.contentOffset.y = 56
        fixture.coordinator.containerDidScroll()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.coordinator.updateGeometry(
            AnchorPagerContainerScrollGeometry(
                topInset: 0,
                collapsibleDistance: 100
            ),
            targetLogicalOffset: 100
        )

        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertFalse(events.contains { $0.event == "scroll.boundary.collapsed" })
        XCTAssertFalse(events.contains { $0.event == "scroll.boundary.expanded" })
    }

    func testChangedCommittedChildCancelsActiveBoundaryAndSettlesReplacement() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let replacement = fixture.makeChild(maximumDistance: 300)
        fixture.container.contentOffset.y = -24
        fixture.coordinator.containerDidScroll()

        fixture.coordinator.bindCommittedChild(replacement)

        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertEqual(
            replacement.contentOffset.y,
            -replacement.contentInset.top,
            accuracy: 0.001
        )
    }

    func testActiveBoundaryGuardedChildCorrectionDoesNotReenterSettlement() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = -24
        fixture.coordinator.containerDidScroll()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

        XCTAssertEqual(
            events.filter { $0.event.hasPrefix("scroll.offset.guard.") }.count,
            0
        )
        XCTAssertEqual(
            fixture.coordinator.activeBoundaryForTesting,
            .init(boundary: .top, owner: .container)
        )
        XCTAssertEqual(fixture.container.contentOffset.y, -24, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
    }

    func testRepeatedBoundaryCorrectionsDoNotEmitPerFrameGuardLogs() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.container.contentOffset.y = 112
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 524
        for _ in 0..<3 {
            fixture.container.contentOffset.y = 112
            fixture.coordinator.handleChildChangeForTesting(
                token: fixture.coordinator.bindingTokenForTesting
            )
        }

        XCTAssertEqual(
            events.filter { $0.event == "overscroll.boundary.bottom" }.count,
            1
        )
        XCTAssertEqual(
            events.filter { $0.event == "overscroll.owner.child.begin" }.count,
            1
        )
        XCTAssertEqual(
            events.filter { $0.event.hasPrefix("scroll.offset.guard.") }.count,
            0
        )
    }

    func testRepeatedTopNonOwnerCorrectionsDoNotEmitPerFrameGuardLogs() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.container.contentOffset.y = -24
        fixture.coordinator.containerDidScroll()
        for _ in 0..<3 {
            fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12
        }

        XCTAssertEqual(
            events.filter { $0.event == "overscroll.boundary.top" }.count,
            1
        )
        XCTAssertEqual(
            events.filter { $0.event == "overscroll.owner.container.begin" }.count,
            1
        )
        XCTAssertEqual(
            events.filter { $0.event.hasPrefix("scroll.offset.guard.") }.count,
            0
        )
    }

    func testPlainBottomPassThroughKeepsContainerOverflow() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.bindCommittedChild(nil)
        fixture.container.contentOffset.y = 124

        fixture.coordinator.containerDidScroll()

        XCTAssertEqual(fixture.container.contentOffset.y, 124, accuracy: 0.001)
    }

    func testRealChildBottomPassThroughKeepsChildOverflowAndPinsContainer() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 112
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 524

        fixture.coordinator.handleChildChangeForTesting(
            token: fixture.coordinator.bindingTokenForTesting
        )

        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y + fixture.child.contentInset.top,
            524,
            accuracy: 0.001
        )
    }

    func testShortChildOffsetWhileContainerExpandedDoesNotBecomeBottomOwner() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 0)

        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 37

        XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertEqual(
            fixture.child.contentOffset.y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )
        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
    }

    func testPartiallyCollapsedContainerRejectsObservedChildTopOverflowInEveryMode() {
        for mode in [
            AnchorPagerTopOverscrollHandlingMode.none,
            .container,
            .child
        ] {
            let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
            fixture.coordinator.updateTopOverscrollHandlingMode(mode)
            fixture.container.contentOffset.y = 40

            fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

            XCTAssertEqual(fixture.container.contentOffset.y, 40, accuracy: 0.001)
            XCTAssertEqual(
                fixture.child.contentOffset.y,
                -fixture.child.contentInset.top,
                accuracy: 0.001
            )
            XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
        }
    }

    func testPartiallyCollapsedChildTopCorrectionIsIndependentOfCallbackOrder() {
        for mode in [
            AnchorPagerTopOverscrollHandlingMode.none,
            .container,
            .child
        ] {
            let containerFirst = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
            containerFirst.coordinator.updateTopOverscrollHandlingMode(mode)
            containerFirst.container.contentOffset.y = 40
            containerFirst.coordinator.containerDidScroll()
            containerFirst.child.contentOffset.y = -containerFirst.child.contentInset.top - 12

            XCTAssertEqual(containerFirst.container.contentOffset.y, 40, accuracy: 0.001)
            XCTAssertEqual(
                containerFirst.child.contentOffset.y,
                -containerFirst.child.contentInset.top,
                accuracy: 0.001
            )
            XCTAssertNil(containerFirst.coordinator.activeBoundaryForTesting)

            let childFirst = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
            childFirst.coordinator.updateTopOverscrollHandlingMode(mode)
            childFirst.container.contentOffset.y = 40
            childFirst.child.contentOffset.y = -childFirst.child.contentInset.top - 12
            childFirst.coordinator.containerDidScroll()

            XCTAssertEqual(childFirst.container.contentOffset.y, 40, accuracy: 0.001)
            XCTAssertEqual(
                childFirst.child.contentOffset.y,
                -childFirst.child.contentInset.top,
                accuracy: 0.001
            )
            XCTAssertNil(childFirst.coordinator.activeBoundaryForTesting)
        }
    }

    func testActiveNativeBoundaryIsNotClampedByGeometryRefresh() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = -24
        fixture.coordinator.containerDidScroll()

        fixture.coordinator.updateGeometry(
            AnchorPagerContainerScrollGeometry(
                topInset: 0,
                collapsibleDistance: 100
            )
        )

        XCTAssertEqual(fixture.container.contentOffset.y, -24, accuracy: 0.001)
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

    func testGuardedWritesDoNotReenterOrEmitPerFrameGuardLogs() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)

        XCTAssertEqual(
            events.filter { $0.event.hasPrefix("scroll.offset.guard.") }.count,
            0
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

    func testEndedSampleStartsNativeMonitorWithCurrentOwnerRateWithoutWritingOffsets() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.decelerationRate = .normal
        fixture.container.contentOffset.y = 40

        fixture.coordinator.handlePan(
            source: .container,
            state: .began,
            translationY: 0,
            velocityY: 0
        )
        fixture.coordinator.handlePan(
            source: .container,
            state: .ended,
            translationY: 0,
            velocityY: -1_000
        )
        let driver = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)

        XCTAssertEqual(driver.starts.count, 1)
        XCTAssertEqual(driver.starts[0].initialVelocity, 1_000)
        XCTAssertEqual(
            driver.starts[0].decelerationRate,
            fixture.container.decelerationRate.rawValue
        )
        XCTAssertEqual(
            fixture.coordinator.decelerationPhaseForTesting,
            .monitoringNative
        )

        driver.emit(.init(delta: 12, velocity: 900, isFinished: false))

        XCTAssertEqual(fixture.container.contentOffset.y, 40, accuracy: 0.001)
        XCTAssertEqual(fixture.childDistance, 0, accuracy: 0.001)
    }

    func testOnlyCurrentOwnerAndMatchingBindingCanStartOncePerInteraction() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let token = fixture.coordinator.bindingTokenForTesting

        fixture.coordinator.handlePan(
            source: .container,
            state: .began,
            translationY: 0,
            velocityY: 0
        )
        fixture.coordinator.handlePan(
            source: .child(token: token),
            state: .began,
            translationY: 0,
            velocityY: 0
        )
        fixture.coordinator.handlePan(
            source: .child(token: token),
            state: .ended,
            translationY: 0,
            velocityY: -1_000
        )
        XCTAssertTrue(fixture.decelerationDrivers.drivers.isEmpty)

        fixture.coordinator.handlePan(
            source: .container,
            state: .ended,
            translationY: 0,
            velocityY: -1_000
        )
        fixture.coordinator.handlePan(
            source: .child(token: token),
            state: .ended,
            translationY: 0,
            velocityY: -1_000
        )

        XCTAssertEqual(fixture.decelerationDrivers.drivers.count, 1)

        fixture.coordinator.handlePan(
            source: .child(token: token - 1),
            state: .ended,
            translationY: 0,
            velocityY: -1_000
        )
        XCTAssertEqual(fixture.decelerationDrivers.drivers.count, 1)
    }

    func testContainerToChildDecelerationConsumesOnlyModelOverflowPastBoundary() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 80
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let driver = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)

        driver.emit(.init(delta: 15, velocity: 900, isFinished: false))
        XCTAssertEqual(fixture.container.contentOffset.y, 80, accuracy: 0.001)
        XCTAssertEqual(fixture.childDistance, 0, accuracy: 0.001)

        fixture.container.contentOffset.y = 100
        fixture.coordinator.containerDidScroll()
        driver.emit(.init(delta: 10, velocity: 800, isFinished: false))

        XCTAssertEqual(
            fixture.coordinator.decelerationPhaseForTesting,
            .synthetic
        )
        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertEqual(fixture.childDistance, 5, accuracy: 0.001)

        driver.emit(.init(delta: 10, velocity: 700, isFinished: false))
        XCTAssertEqual(fixture.childDistance, 15, accuracy: 0.001)
        XCTAssertEqual(fixture.decelerationDrivers.drivers.count, 1)

        fixture.container.contentOffset.y = 90
        fixture.coordinator.containerDidScroll()

        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertEqual(fixture.childDistance, 15, accuracy: 0.001)
        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
    }

    func testSyntheticContainerToChildRejectsLateNativeTargetChildWrite() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let child = try XCTUnwrap(fixture.child as? RecordingScrollView)
        fixture.container.contentOffset.y = 80
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let driver = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)

        driver.emit(.init(delta: 15, velocity: 900, isFinished: false))
        fixture.container.contentOffset.y = 100
        fixture.coordinator.containerDidScroll()
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 3
        driver.emit(.init(delta: 10, velocity: 800, isFinished: false))
        XCTAssertEqual(fixture.childDistance, 5, accuracy: 0.001)
        XCTAssertEqual(child.nonanimatedContentOffsetWriteCount, 1)
        XCTAssertEqual(
            try XCTUnwrap(child.lastNonanimatedContentOffset).y,
            -fixture.child.contentInset.top,
            accuracy: 0.001
        )

        fixture.child.contentOffset.y = -fixture.child.contentInset.top

        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertEqual(fixture.childDistance, 5, accuracy: 0.001)
        XCTAssertEqual(fixture.coordinator.decelerationPhaseForTesting, .synthetic)
        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
    }

    func testChildToContainerDecelerationConsumesOnlyModelOverflowPastBoundary() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 100
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 50
        XCTAssertEqual(fixture.coordinator.owner, .child)
        let token = fixture.coordinator.bindingTokenForTesting
        fixture.child.decelerationRate = .fast
        fixture.startDeceleration(
            source: .child(token: token),
            velocityY: 1_000
        )
        let driver = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)
        XCTAssertEqual(
            driver.starts[0].decelerationRate,
            fixture.child.decelerationRate.rawValue
        )

        driver.emit(.init(delta: -30, velocity: -900, isFinished: false))
        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertEqual(fixture.childDistance, 50, accuracy: 0.001)

        fixture.child.contentOffset.y = -fixture.child.contentInset.top
        driver.emit(.init(delta: -30, velocity: -800, isFinished: false))

        XCTAssertEqual(
            fixture.coordinator.decelerationPhaseForTesting,
            .synthetic
        )
        XCTAssertEqual(fixture.childDistance, 0, accuracy: 0.001)
        XCTAssertEqual(fixture.container.contentOffset.y, 90, accuracy: 0.001)

        driver.emit(.init(delta: -20, velocity: -700, isFinished: false))
        XCTAssertEqual(fixture.container.contentOffset.y, 70, accuracy: 0.001)

        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 10
        XCTAssertEqual(fixture.childDistance, 0, accuracy: 0.001)
        XCTAssertEqual(fixture.container.contentOffset.y, 70, accuracy: 0.001)
        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
    }

    func testSyntheticChildToContainerRejectsLateNativeTargetContainerWrite() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 100
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 50
        let token = fixture.coordinator.bindingTokenForTesting
        fixture.startDeceleration(
            source: .child(token: token),
            velocityY: 1_000
        )
        let driver = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)

        driver.emit(.init(delta: -30, velocity: -900, isFinished: false))
        fixture.child.contentOffset.y = -fixture.child.contentInset.top
        driver.emit(.init(delta: -30, velocity: -800, isFinished: false))
        XCTAssertEqual(fixture.container.contentOffset.y, 90, accuracy: 0.001)

        fixture.container.contentOffset.y = 100
        fixture.coordinator.containerDidScroll()

        XCTAssertEqual(fixture.container.contentOffset.y, 90, accuracy: 0.001)
        XCTAssertEqual(fixture.childDistance, 0, accuracy: 0.001)
        XCTAssertEqual(fixture.coordinator.decelerationPhaseForTesting, .synthetic)
        XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
    }

    func testMonitorFinishesBelowVelocityThresholdWithoutWritingOffsets() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 40
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let driver = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)

        driver.emit(.init(delta: 8, velocity: 5, isFinished: true))

        XCTAssertNil(fixture.coordinator.decelerationPhaseForTesting)
        XCTAssertEqual(fixture.container.contentOffset.y, 40, accuracy: 0.001)
        XCTAssertEqual(fixture.childDistance, 0, accuracy: 0.001)
        XCTAssertEqual(driver.cancelCount, 0)
    }

    func testNewPanAndStructuralChangesCancelSyntheticDecelerationOnce() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 40
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let firstDriver = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)

        fixture.coordinator.handlePan(
            source: .container,
            state: .began,
            translationY: 0,
            velocityY: 0
        )
        fixture.coordinator.cancelSyntheticDeceleration()
        XCTAssertEqual(firstDriver.cancelCount, 1)

        fixture.coordinator.handlePan(
            source: .container,
            state: .cancelled,
            translationY: 0,
            velocityY: 0
        )
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let geometryDriver = try XCTUnwrap(fixture.decelerationDrivers.drivers.last)
        fixture.coordinator.updateGeometry(
            .init(topInset: 0, collapsibleDistance: 120)
        )
        XCTAssertEqual(geometryDriver.cancelCount, 1)

        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let identityDriver = try XCTUnwrap(fixture.decelerationDrivers.drivers.last)
        fixture.coordinator.bindCommittedChild(
            fixture.makeChild(maximumDistance: 300)
        )
        XCTAssertEqual(identityDriver.cancelCount, 1)

        fixture.container.contentOffset.y = 40
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let modeDriver = try XCTUnwrap(fixture.decelerationDrivers.drivers.last)
        fixture.coordinator.updateTopOverscrollHandlingMode(.none)
        XCTAssertEqual(modeDriver.cancelCount, 1)

        fixture.container.contentOffset.y = 40
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let boundaryDriver = try XCTUnwrap(fixture.decelerationDrivers.drivers.last)
        fixture.coordinator.cancelBoundaryHandling()
        XCTAssertEqual(boundaryDriver.cancelCount, 1)

        fixture.container.contentOffset.y = 40
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let invalidationDriver = try XCTUnwrap(
            fixture.decelerationDrivers.drivers.last
        )
        fixture.coordinator.invalidate()
        XCTAssertEqual(invalidationDriver.cancelCount, 1)
    }

    func testChildContentGeometryChangeCancelsActiveDeceleration() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 40
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let driver = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)

        fixture.child.contentSize.height += 20

        XCTAssertEqual(driver.cancelCount, 1)
        XCTAssertNil(fixture.coordinator.decelerationPhaseForTesting)
    }

    func testSyntheticDecelerationStopsAtStableEndpointWithoutOverscrollOwner() throws {
        let upward = Fixture(collapsedOffset: 100, childMaximumDistance: 20)
        upward.container.contentOffset.y = 90
        upward.startDeceleration(source: .container, velocityY: -1_000)
        let upwardDriver = try XCTUnwrap(upward.decelerationDrivers.drivers.first)
        upwardDriver.emit(.init(delta: 15, velocity: 900, isFinished: false))
        upward.container.contentOffset.y = 100
        upward.coordinator.containerDidScroll()
        upwardDriver.emit(.init(delta: 20, velocity: 800, isFinished: false))

        XCTAssertEqual(upward.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertEqual(upward.childDistance, 20, accuracy: 0.001)
        XCTAssertEqual(upwardDriver.cancelCount, 1)
        XCTAssertNil(upward.coordinator.activeBoundaryForTesting)

        let downward = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        downward.container.contentOffset.y = 100
        downward.child.contentOffset.y = -downward.child.contentInset.top + 10
        let token = downward.coordinator.bindingTokenForTesting
        downward.startDeceleration(
            source: .child(token: token),
            velocityY: 1_000
        )
        let downwardDriver = try XCTUnwrap(
            downward.decelerationDrivers.drivers.first
        )
        downwardDriver.emit(.init(delta: -15, velocity: -900, isFinished: false))
        downward.child.contentOffset.y = -downward.child.contentInset.top
        downwardDriver.emit(.init(delta: -100, velocity: -800, isFinished: false))

        XCTAssertEqual(downward.container.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertEqual(downward.childDistance, 0, accuracy: 0.001)
        XCTAssertEqual(downwardDriver.cancelCount, 1)
        XCTAssertNil(downward.coordinator.activeBoundaryForTesting)
    }

    func testStaleCancelledDriverTickCannotCancelReplacementInteraction() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 40
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let staleDriver = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)
        fixture.coordinator.cancelSyntheticDeceleration()

        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let currentDriver = try XCTUnwrap(fixture.decelerationDrivers.drivers.last)
        staleDriver.emitIgnoringCancellation(
            .init(delta: 20, velocity: 800, isFinished: false)
        )

        XCTAssertEqual(
            fixture.coordinator.decelerationPhaseForTesting,
            .monitoringNative
        )
        XCTAssertEqual(currentDriver.cancelCount, 0)
        currentDriver.emit(.init(delta: 10, velocity: 700, isFinished: false))
        XCTAssertEqual(fixture.container.contentOffset.y, 40, accuracy: 0.001)
    }

    func testInvalidReverseLowSpeedAndUntraversableSamplesDoNotStartDriver() {
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        let invalidRate = Fixture(
            collapsedOffset: 100,
            childMaximumDistance: 500,
            decelerationRateProvider: { _ in 1 }
        )
        invalidRate.container.contentOffset.y = 40
        invalidRate.startDeceleration(source: .container, velocityY: -1_000)

        let reverse = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        reverse.container.contentOffset.y = 40
        reverse.startDeceleration(source: .container, velocityY: 1_000)

        let lowSpeed = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        lowSpeed.container.contentOffset.y = 40
        lowSpeed.startDeceleration(source: .container, velocityY: -5)

        let plain = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        plain.coordinator.bindCommittedChild(nil)
        plain.container.contentOffset.y = 40
        plain.startDeceleration(source: .container, velocityY: -1_000)

        XCTAssertTrue(invalidRate.decelerationDrivers.drivers.isEmpty)
        XCTAssertTrue(reverse.decelerationDrivers.drivers.isEmpty)
        XCTAssertTrue(lowSpeed.decelerationDrivers.drivers.isEmpty)
        XCTAssertTrue(plain.decelerationDrivers.drivers.isEmpty)
        XCTAssertEqual(
            events.filter { $0.event == "scroll.deceleration.cancel" }.count,
            4
        )
    }

    func testStructuredInteractionEventsFollowDragTopBoundaryAndStableFinish() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let delegate = RecordingScrollInteractionDelegate()
        fixture.coordinator.interactionDelegate = delegate

        fixture.coordinator.handlePan(
            source: .container,
            state: .began,
            translationY: 0,
            velocityY: 0
        )
        fixture.container.contentOffset.y = -20
        fixture.coordinator.containerDidScroll()
        fixture.container.contentOffset.y = 0
        fixture.coordinator.containerDidScroll()
        fixture.coordinator.handlePan(
            source: .container,
            state: .ended,
            translationY: 20,
            velocityY: 0
        )

        XCTAssertEqual(delegate.events, [
            .beganDragging(identifier: 1),
            .enteredTopOverscroll(identifier: 1),
            .leftTopOverscroll(identifier: 1),
            .finishedDragging(identifier: 1),
        ])
    }

    func testUnpresentedTopBoundaryStillReturnsInteractionToDragging() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let delegate = RecordingScrollInteractionDelegate()
        fixture.coordinator.interactionDelegate = delegate

        fixture.coordinator.handlePan(
            source: .container,
            state: .began,
            translationY: 0,
            velocityY: 0
        )
        fixture.coordinator.handlePan(
            source: .container,
            state: .changed,
            translationY: 20,
            velocityY: 0
        )
        fixture.coordinator.handlePan(
            source: .container,
            state: .changed,
            translationY: 0,
            velocityY: 0
        )
        fixture.coordinator.handlePan(
            source: .container,
            state: .ended,
            translationY: 0,
            velocityY: 0
        )

        XCTAssertEqual(delegate.events, [
            .beganDragging(identifier: 1),
            .enteredTopOverscroll(identifier: 1),
            .leftTopOverscroll(identifier: 1),
            .finishedDragging(identifier: 1),
        ])
    }

    func testStructuredInteractionEventsKeepDecelerationIdentifierUntilFinish() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let delegate = RecordingScrollInteractionDelegate()
        fixture.coordinator.interactionDelegate = delegate
        fixture.container.contentOffset.y = 40

        fixture.startDeceleration(source: .container, velocityY: -1_000)
        let driver = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)

        XCTAssertEqual(delegate.events, [
            .beganDragging(identifier: 1),
            .beganDecelerating(identifier: 1),
        ])

        driver.emit(.init(delta: 1, velocity: 4, isFinished: true))

        XCTAssertEqual(delegate.events.last, .finishedDecelerating(identifier: 1))
    }

    func testNewPanCancelsOldDecelerationBeforeBeginningNewInteraction() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let delegate = RecordingScrollInteractionDelegate()
        fixture.coordinator.interactionDelegate = delegate
        fixture.container.contentOffset.y = 40
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        _ = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)

        fixture.coordinator.handlePan(
            source: .container,
            state: .began,
            translationY: 0,
            velocityY: 0
        )

        XCTAssertEqual(Array(delegate.events.suffix(2)), [
            .cancelled(identifier: 1),
            .beganDragging(identifier: 2),
        ])
    }

    func testCommittedIdentityChangeCancelsMatchingDecelerationInteraction() throws {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let delegate = RecordingScrollInteractionDelegate()
        fixture.coordinator.interactionDelegate = delegate
        fixture.container.contentOffset.y = 40
        fixture.startDeceleration(source: .container, velocityY: -1_000)
        _ = try XCTUnwrap(fixture.decelerationDrivers.drivers.first)

        fixture.coordinator.bindCommittedChild(
            fixture.makeChild(maximumDistance: 300)
        )

        XCTAssertEqual(delegate.events.last, .cancelled(identifier: 1))
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
    let decelerationDrivers: RecordingDecelerationDriverFactory

    init(
        collapsedOffset: CGFloat = 100,
        childMaximumDistance: CGFloat = 500,
        topInset: CGFloat = 0,
        decelerationRateProvider: AnchorPagerScrollCoordinator.DecelerationRateProvider? = nil
    ) {
        let decelerationDrivers = RecordingDecelerationDriverFactory()
        self.decelerationDrivers = decelerationDrivers
        child = RecordingScrollView()
        container.bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        container.contentInset.top = topInset
        container.contentOffset.y = -topInset
        child.bounds = CGRect(x: 0, y: 0, width: 320, height: 600)
        child.contentInset = UIEdgeInsets(top: 50, left: 0, bottom: 0, right: 0)
        child.contentSize = CGSize(
            width: 320,
            height: 600 + childMaximumDistance - child.contentInset.top
        )
        child.contentOffset.y = -child.contentInset.top
        coordinator = AnchorPagerScrollCoordinator(
            containerScrollView: container,
            decelerationDriverFactory: {
                decelerationDrivers.makeDriver()
            },
            decelerationRateProvider: decelerationRateProvider
                ?? { $0.decelerationRate.rawValue }
        )
        coordinator.updateGeometry(
            AnchorPagerContainerScrollGeometry(
                topInset: topInset,
                collapsibleDistance: collapsedOffset
            )
        )
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

    var childDistance: CGFloat {
        child.contentOffset.y + child.contentInset.top
    }

    func startDeceleration(
        source: AnchorPagerVerticalPanSource,
        velocityY: CGFloat
    ) {
        coordinator.handlePan(
            source: source,
            state: .began,
            translationY: 0,
            velocityY: 0
        )
        coordinator.handlePan(
            source: source,
            state: .ended,
            translationY: 0,
            velocityY: velocityY
        )
    }
}

@MainActor
private final class RecordingScrollView: UIScrollView {
    private(set) var nonanimatedContentOffsetWriteCount = 0
    private(set) var lastNonanimatedContentOffset: CGPoint?

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if !animated {
            nonanimatedContentOffsetWriteCount += 1
            lastNonanimatedContentOffset = contentOffset
        }
        super.setContentOffset(contentOffset, animated: animated)
    }
}

@MainActor
private final class RecordingDecelerationDriverFactory {
    private(set) var drivers: [RecordingDecelerationDriver] = []

    func makeDriver() -> AnchorPagerVerticalDecelerationDriving {
        let driver = RecordingDecelerationDriver()
        drivers.append(driver)
        return driver
    }
}

@MainActor
private final class RecordingDecelerationDriver: AnchorPagerVerticalDecelerationDriving {
    struct Start: Equatable {
        let initialVelocity: CGFloat
        let decelerationRate: CGFloat
        let elapsedTime: TimeInterval
    }

    var onTick: ((AnchorPagerVerticalDecelerationModel.Sample) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var starts: [Start] = []
    private(set) var cancelCount = 0
    private var isRunning = false

    func start(
        initialVelocity: CGFloat,
        decelerationRate: CGFloat,
        elapsedTime: TimeInterval
    ) {
        starts.append(.init(
            initialVelocity: initialVelocity,
            decelerationRate: decelerationRate,
            elapsedTime: elapsedTime
        ))
        isRunning = true
    }

    func cancel() {
        guard isRunning else { return }
        isRunning = false
        cancelCount += 1
        onCancel?()
    }

    func emit(_ sample: AnchorPagerVerticalDecelerationModel.Sample) {
        guard isRunning else { return }
        onTick?(sample)
        if sample.isFinished {
            isRunning = false
        }
    }

    func emitIgnoringCancellation(
        _ sample: AnchorPagerVerticalDecelerationModel.Sample
    ) {
        onTick?(sample)
    }
}

@MainActor
private final class RecordingScrollInteractionDelegate:
    AnchorPagerScrollCoordinatorInteractionDelegate {
    private(set) var events: [AnchorPagerVerticalInteractionEvent] = []

    func scrollCoordinator(
        _ coordinator: AnchorPagerScrollCoordinator,
        didEmit event: AnchorPagerVerticalInteractionEvent
    ) {
        events.append(event)
    }
}
