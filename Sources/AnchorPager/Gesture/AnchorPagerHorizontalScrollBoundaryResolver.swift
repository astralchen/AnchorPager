import CoreGraphics

struct AnchorPagerHorizontalScrollBoundaryResolver {
    struct Geometry: Equatable {
        let contentOffsetX: CGFloat
        let contentSizeWidth: CGFloat
        let boundsWidth: CGFloat
        let adjustedInsetLeft: CGFloat
        let adjustedInsetRight: CGFloat
    }

    enum Decision: Equatable {
        case content
        case pagingBoundary
        case noCandidate
    }

    static func decision(
        for geometries: [Geometry],
        velocity: CGPoint,
        epsilon: CGFloat = 0.5
    ) -> Decision {
        guard velocity.x.isFinite,
              velocity.y.isFinite,
              abs(velocity.x) > abs(velocity.y),
              abs(velocity.x) > epsilon else {
            return .noCandidate
        }

        let ranges = geometries.compactMap { geometry -> (CGFloat, CGFloat, CGFloat)? in
            guard geometry.contentOffsetX.isFinite,
                  geometry.contentSizeWidth.isFinite,
                  geometry.boundsWidth.isFinite,
                  geometry.adjustedInsetLeft.isFinite,
                  geometry.adjustedInsetRight.isFinite,
                  geometry.boundsWidth > 0 else {
                return nil
            }
            let minimumX = -geometry.adjustedInsetLeft
            let maximumX = max(
                minimumX,
                geometry.contentSizeWidth
                    - geometry.boundsWidth
                    + geometry.adjustedInsetRight
            )
            guard maximumX - minimumX > epsilon else { return nil }
            return (geometry.contentOffsetX, minimumX, maximumX)
        }
        guard !ranges.isEmpty else { return .noCandidate }

        let canConsume = ranges.contains { range in
            let (offsetX, minimumX, maximumX) = range
            if velocity.x > 0 {
                return offsetX > minimumX + epsilon
            }
            return offsetX < maximumX - epsilon
        }
        return canConsume ? .content : .pagingBoundary
    }
}
