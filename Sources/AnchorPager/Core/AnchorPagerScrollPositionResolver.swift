import CoreGraphics

struct AnchorPagerScrollPositionResolver {
    struct Position: Equatable {
        var containerOffset: CGFloat
        var childDistance: CGFloat
    }

    struct Input {
        var gestureStartTotal: CGFloat
        var gestureStartTranslationY: CGFloat
        var currentTranslationY: CGFloat
        var containerCollapsedOffset: CGFloat
        var childMaximumDistance: CGFloat
        var fallback: Position
    }

    static func unclampedDesiredTotal(_ input: Input) -> CGFloat? {
        let values = [
            input.gestureStartTotal,
            input.gestureStartTranslationY,
            input.currentTranslationY,
            input.containerCollapsedOffset,
            input.childMaximumDistance
        ]
        guard values.allSatisfy(\.isFinite) else { return nil }

        let upwardDelta = input.gestureStartTranslationY - input.currentTranslationY
        return input.gestureStartTotal + upwardDelta
    }

    static func resolve(_ input: Input) -> Position {
        guard let rawDesiredTotal = unclampedDesiredTotal(input) else {
            return input.fallback
        }

        let collapsedOffset = max(0, input.containerCollapsedOffset)
        let maximumChildDistance = max(0, input.childMaximumDistance)
        let desiredTotal = min(
            max(0, rawDesiredTotal),
            collapsedOffset + maximumChildDistance
        )

        return Position(
            containerOffset: min(desiredTotal, collapsedOffset),
            childDistance: max(0, desiredTotal - collapsedOffset)
        )
    }

    static func childMaximumDistance(
        contentSizeHeight: CGFloat,
        boundsHeight: CGFloat,
        contentInsetTop: CGFloat,
        contentInsetBottom: CGFloat
    ) -> CGFloat {
        let values = [
            contentSizeHeight,
            boundsHeight,
            contentInsetTop,
            contentInsetBottom
        ]
        guard values.allSatisfy(\.isFinite) else { return 0 }

        return max(
            0,
            contentSizeHeight + contentInsetTop + contentInsetBottom - boundsHeight
        )
    }
}
