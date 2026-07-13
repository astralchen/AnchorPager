import XCTest
@testable import AnchorPager

final class AnchorPagerScrollPositionResolverTests: XCTestCase {
    func testUnclampedDesiredTotalPreservesTopAndBottomOverflow() {
        let top = AnchorPagerScrollPositionResolver.Input(
            gestureStartTotal: 0,
            gestureStartTranslationY: 0,
            currentTranslationY: 24,
            containerCollapsedOffset: 100,
            childMaximumDistance: 500,
            fallback: .init(containerOffset: 0, childDistance: 0)
        )
        let bottom = AnchorPagerScrollPositionResolver.Input(
            gestureStartTotal: 600,
            gestureStartTranslationY: 0,
            currentTranslationY: -24,
            containerCollapsedOffset: 100,
            childMaximumDistance: 500,
            fallback: .init(containerOffset: 100, childDistance: 500)
        )

        XCTAssertEqual(AnchorPagerScrollPositionResolver.unclampedDesiredTotal(top), -24)
        XCTAssertEqual(AnchorPagerScrollPositionResolver.unclampedDesiredTotal(bottom), 624)
    }

    func testUpwardTranslationDistributesAcrossContainerAndChildWithoutDroppingDelta() {
        let result = AnchorPagerScrollPositionResolver.resolve(.init(
            gestureStartTotal: 80,
            gestureStartTranslationY: 0,
            currentTranslationY: -70,
            containerCollapsedOffset: 100,
            childMaximumDistance: 500,
            fallback: .init(containerOffset: 80, childDistance: 0)
        ))

        XCTAssertEqual(result, .init(containerOffset: 100, childDistance: 50))
    }

    func testDownwardTranslationConsumesChildBeforeExpandingContainer() {
        let result = AnchorPagerScrollPositionResolver.resolve(.init(
            gestureStartTotal: 180,
            gestureStartTranslationY: 0,
            currentTranslationY: 130,
            containerCollapsedOffset: 100,
            childMaximumDistance: 500,
            fallback: .init(containerOffset: 100, childDistance: 80)
        ))

        XCTAssertEqual(result, .init(containerOffset: 50, childDistance: 0))
    }

    func testShortChildClampsDistanceToZero() {
        let result = AnchorPagerScrollPositionResolver.resolve(.init(
            gestureStartTotal: 100,
            gestureStartTranslationY: 0,
            currentTranslationY: -90,
            containerCollapsedOffset: 100,
            childMaximumDistance: 0,
            fallback: .init(containerOffset: 100, childDistance: 0)
        ))

        XCTAssertEqual(result, .init(containerOffset: 100, childDistance: 0))
    }

    func testNonFiniteInputReturnsStableFallback() {
        let fallback = AnchorPagerScrollPositionResolver.Position(
            containerOffset: 40,
            childDistance: 0
        )
        let result = AnchorPagerScrollPositionResolver.resolve(.init(
            gestureStartTotal: .nan,
            gestureStartTranslationY: 0,
            currentTranslationY: 0,
            containerCollapsedOffset: 100,
            childMaximumDistance: 500,
            fallback: fallback
        ))

        XCTAssertEqual(result, fallback)
    }

    func testChildMaximumDistanceIncludesContentInsets() {
        XCTAssertEqual(
            AnchorPagerScrollPositionResolver.childMaximumDistance(
                contentSizeHeight: 900,
                boundsHeight: 600,
                contentInsetTop: 50,
                contentInsetBottom: 30
            ),
            380
        )
    }
}
