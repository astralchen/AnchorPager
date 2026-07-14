import CoreGraphics
import XCTest
@testable import AnchorPager

final class AnchorPagerContainerScrollGeometryTests: XCTestCase {
    func testInsideAndExtendsResolveDifferentTopInsets() {
        XCTAssertEqual(
            AnchorPagerContainerScrollGeometry.topInset(
                for: .insideSafeArea,
                topObstructionHeight: 44
            ),
            44
        )
        XCTAssertEqual(
            AnchorPagerContainerScrollGeometry.topInset(
                for: .extendsUnderTopSafeArea,
                topObstructionHeight: 44
            ),
            0
        )
    }

    func testRawLogicalConversionAndStableBoundariesIncludeTopInset() {
        let geometry = AnchorPagerContainerScrollGeometry(
            topInset: 44,
            collapsibleDistance: 100
        )

        XCTAssertEqual(geometry.expandedRawOffset, -44)
        XCTAssertEqual(geometry.collapsedRawOffset, 56)
        XCTAssertEqual(geometry.logicalOffset(forRawOffset: -44), 0)
        XCTAssertEqual(geometry.logicalOffset(forRawOffset: 56), 100)
        XCTAssertEqual(geometry.rawOffset(forLogicalOffset: 40), -4)
        XCTAssertEqual(geometry.clampedLogicalOffset(-12), 0)
        XCTAssertEqual(geometry.clampedLogicalOffset(112), 100)
    }

    func testOverflowAndScrollRangeUseLogicalBoundaries() {
        let geometry = AnchorPagerContainerScrollGeometry(
            topInset: 44,
            collapsibleDistance: 100
        )

        XCTAssertEqual(geometry.topOverflow(forRawOffset: -68), 24)
        XCTAssertEqual(geometry.bottomOverflow(forRawOffset: 80), 24)
        XCTAssertEqual(geometry.scrollRangeHeight(viewportHeight: 640), 696)
    }

    func testZeroDistanceKeepsSingleRawBoundaryAndFiniteFallbacks() {
        let geometry = AnchorPagerContainerScrollGeometry(
            topInset: 44,
            collapsibleDistance: 0
        )

        XCTAssertEqual(geometry.expandedRawOffset, -44)
        XCTAssertEqual(geometry.collapsedRawOffset, -44)
        XCTAssertEqual(geometry.scrollRangeHeight(viewportHeight: 640), 596)
        XCTAssertEqual(geometry.logicalOffset(forRawOffset: .nan), 0)
        XCTAssertEqual(geometry.rawOffset(forLogicalOffset: .infinity), -44)
    }

    func testDistanceSmallerThanInsetStillProducesOrderedRawBoundaries() {
        let geometry = AnchorPagerContainerScrollGeometry(
            topInset: 44,
            collapsibleDistance: 20
        )

        XCTAssertEqual(geometry.expandedRawOffset, -44)
        XCTAssertEqual(geometry.collapsedRawOffset, -24)
        XCTAssertEqual(geometry.scrollRangeHeight(viewportHeight: 640), 616)
    }
}
