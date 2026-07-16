import CoreGraphics
import XCTest
@testable import AnchorPager

final class AnchorPagerHorizontalScrollBoundaryResolverTests: XCTestCase {
    private typealias Geometry = AnchorPagerHorizontalScrollBoundaryResolver.Geometry

    func testInteriorCanConsumeBothPhysicalDirections() {
        let geometry = makeGeometry(offsetX: 100, maximumX: 300)
        XCTAssertEqual(resolve([geometry], velocityX: 400), .content)
        XCTAssertEqual(resolve([geometry], velocityX: -400), .content)
    }

    func testMinimumBoundaryPagesOutwardAndConsumesInward() {
        let geometry = makeGeometry(offsetX: 0, maximumX: 300)
        XCTAssertEqual(resolve([geometry], velocityX: 400), .pagingBoundary)
        XCTAssertEqual(resolve([geometry], velocityX: -400), .content)
    }

    func testMaximumBoundaryPagesOutwardAndConsumesInward() {
        let geometry = makeGeometry(offsetX: 300, maximumX: 300)
        XCTAssertEqual(resolve([geometry], velocityX: -400), .pagingBoundary)
        XCTAssertEqual(resolve([geometry], velocityX: 400), .content)
    }

    func testNativeBounceUsesPhysicalReturnDirection() {
        XCTAssertEqual(resolve([makeGeometry(offsetX: -12, maximumX: 300)], velocityX: 400), .pagingBoundary)
        XCTAssertEqual(resolve([makeGeometry(offsetX: -12, maximumX: 300)], velocityX: -400), .content)
        XCTAssertEqual(resolve([makeGeometry(offsetX: 312, maximumX: 300)], velocityX: -400), .pagingBoundary)
        XCTAssertEqual(resolve([makeGeometry(offsetX: 312, maximumX: 300)], velocityX: 400), .content)
    }

    func testAnyNestedCandidateCanKeepGestureInContent() {
        let innerAtMaximum = makeGeometry(offsetX: 300, maximumX: 300)
        let outerInterior = makeGeometry(offsetX: 40, maximumX: 100)
        XCTAssertEqual(resolve([innerAtMaximum, outerInterior], velocityX: -400), .content)
    }

    func testAdjustedInsetsAndHalfPointEpsilonDefineStableRange() {
        let geometry = Geometry(
            contentOffsetX: -9.6,
            contentSizeWidth: 500,
            boundsWidth: 300,
            adjustedInsetLeft: 10,
            adjustedInsetRight: 20
        )
        XCTAssertEqual(resolve([geometry], velocityX: 400), .pagingBoundary)
    }

    func testVerticalZeroAndInvalidGeometryDoNotBlockPaging() {
        let valid = makeGeometry(offsetX: 100, maximumX: 300)
        XCTAssertEqual(
            AnchorPagerHorizontalScrollBoundaryResolver.decision(
                for: [valid],
                velocity: CGPoint(x: 20, y: 200)
            ),
            .noCandidate
        )
        XCTAssertEqual(resolve([valid], velocityX: 0), .noCandidate)
        XCTAssertEqual(resolve([makeGeometry(offsetX: .nan, maximumX: 300)], velocityX: 400), .noCandidate)
    }

    private func resolve(_ geometries: [Geometry], velocityX: CGFloat) -> AnchorPagerHorizontalScrollBoundaryResolver.Decision {
        AnchorPagerHorizontalScrollBoundaryResolver.decision(
            for: geometries,
            velocity: CGPoint(x: velocityX, y: 0)
        )
    }

    private func makeGeometry(offsetX: CGFloat, maximumX: CGFloat) -> Geometry {
        Geometry(
            contentOffsetX: offsetX,
            contentSizeWidth: maximumX + 300,
            boundsWidth: 300,
            adjustedInsetLeft: 0,
            adjustedInsetRight: 0
        )
    }
}
