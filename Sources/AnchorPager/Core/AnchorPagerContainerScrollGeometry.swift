import CoreGraphics

struct AnchorPagerContainerScrollGeometry: Equatable {
    static let zero = AnchorPagerContainerScrollGeometry(
        topInset: 0,
        collapsibleDistance: 0
    )

    let topInset: CGFloat
    let collapsibleDistance: CGFloat

    init(topInset: CGFloat, collapsibleDistance: CGFloat) {
        self.topInset = Self.nonNegativeFinite(topInset)
        self.collapsibleDistance = Self.nonNegativeFinite(collapsibleDistance)
    }

    static func topInset(
        for behavior: AnchorPagerHeaderTopBehavior,
        topObstructionHeight: CGFloat
    ) -> CGFloat {
        switch behavior {
        case .insideSafeArea:
            nonNegativeFinite(topObstructionHeight)
        case .extendsUnderTopSafeArea:
            0
        }
    }

    var expandedRawOffset: CGFloat { -topInset }
    var collapsedRawOffset: CGFloat { collapsibleDistance - topInset }

    func logicalOffset(forRawOffset rawOffset: CGFloat) -> CGFloat {
        guard rawOffset.isFinite else { return 0 }
        return rawOffset + topInset
    }

    func rawOffset(forLogicalOffset logicalOffset: CGFloat) -> CGFloat {
        guard logicalOffset.isFinite else { return expandedRawOffset }
        return logicalOffset - topInset
    }

    func clampedLogicalOffset(_ logicalOffset: CGFloat) -> CGFloat {
        min(collapsibleDistance, max(0, logicalOffset.isFinite ? logicalOffset : 0))
    }

    func topOverflow(forRawOffset rawOffset: CGFloat) -> CGFloat {
        max(0, -logicalOffset(forRawOffset: rawOffset))
    }

    func bottomOverflow(forRawOffset rawOffset: CGFloat) -> CGFloat {
        max(0, logicalOffset(forRawOffset: rawOffset) - collapsibleDistance)
    }

    func scrollRangeHeight(viewportHeight: CGFloat) -> CGFloat {
        max(0, Self.nonNegativeFinite(viewportHeight) + collapsibleDistance - topInset)
    }

    private static func nonNegativeFinite(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}
