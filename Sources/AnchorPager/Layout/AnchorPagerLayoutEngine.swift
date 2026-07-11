import CoreGraphics

struct AnchorPagerLayoutEngine {
    struct Input: Equatable {
        var bounds: CGRect
        var measuredHeaderHeight: CGFloat
        var headerHeightMode: AnchorPagerHeaderHeightMode
        var headerTopBehavior: AnchorPagerHeaderTopBehavior
        var barHeight: CGFloat
        var topObstructionHeight: CGFloat
        var bottomObstructionHeight: CGFloat
        var contentOffsetY: CGFloat
    }

    struct ResolvedHeaderHeight: Equatable {
        var expanded: CGFloat
        var collapsed: CGFloat

        var collapsibleDistance: CGFloat {
            Swift.max(0, expanded - collapsed)
        }
    }

    struct Output: Equatable {
        var resolvedHeaderHeight: ResolvedHeaderHeight
        var collapseOffset: CGFloat
        var collapseProgress: CGFloat
        var headerFrame: CGRect
        var barFrame: CGRect
        var contentFrame: CGRect
        var pagingFrame: CGRect
    }

    func layout(for input: Input) -> Output {
        let bounds = input.bounds
        let topObstructionHeight = nonNegativeFinite(input.topObstructionHeight)
        // 该值表示分页 adapter 完成布局后的真实 bar 高度，而不是配置先验值。
        let barHeight = nonNegativeFinite(input.barHeight)
        let resolvedHeaderHeight = resolvedHeaderHeight(
            measuredHeaderHeight: input.measuredHeaderHeight,
            mode: input.headerHeightMode
        )
        let collapsibleDistance = resolvedHeaderHeight.collapsibleDistance
        let collapseOffset = clamped(
            nonNegativeFinite(input.contentOffsetY),
            lowerBound: 0,
            upperBound: collapsibleDistance
        )
        let collapseProgress = collapsibleDistance > 0
            ? collapseOffset / collapsibleDistance
            : 0
        let visibleContentHeight = Swift.max(
            resolvedHeaderHeight.collapsed,
            resolvedHeaderHeight.expanded - collapseOffset
        )
        let topPinY = bounds.minY + topObstructionHeight
        let headerY: CGFloat
        let headerFrameHeight: CGFloat
        switch input.headerTopBehavior {
        case .insideSafeArea:
            headerY = topPinY
            headerFrameHeight = visibleContentHeight
        case .extendsUnderTopSafeArea:
            headerY = bounds.minY
            headerFrameHeight = topObstructionHeight + visibleContentHeight
        }

        let headerFrame = CGRect(
            x: bounds.minX,
            y: headerY,
            width: bounds.width,
            height: headerFrameHeight
        )
        let barY = topPinY + visibleContentHeight
        let barFrame = CGRect(
            x: bounds.minX,
            y: barY,
            width: bounds.width,
            height: barHeight
        )
        let contentY = barFrame.maxY
        let contentFrame = CGRect(
            x: bounds.minX,
            y: contentY,
            width: bounds.width,
            height: Swift.max(0, bounds.maxY - contentY)
        )
        let collapsedAdapterTop = topPinY + resolvedHeaderHeight.collapsed
        let pagingFrame = CGRect(
            x: bounds.minX,
            y: barY,
            width: bounds.width,
            height: Swift.max(0, bounds.maxY - collapsedAdapterTop)
        )

        return Output(
            resolvedHeaderHeight: resolvedHeaderHeight,
            collapseOffset: collapseOffset,
            collapseProgress: collapseProgress,
            headerFrame: headerFrame,
            barFrame: barFrame,
            contentFrame: contentFrame,
            pagingFrame: pagingFrame
        )
    }

    func adjustedContentOffsetY(
        current: CGFloat,
        old: Output?,
        new: Output,
        strategy: AnchorPagerHeaderOffsetAdjustment
    ) -> CGFloat {
        switch strategy {
        case .preserveVisualPosition:
            guard let old else {
                return clamped(
                    nonNegativeFinite(current),
                    lowerBound: 0,
                    upperBound: new.resolvedHeaderHeight.collapsibleDistance
                )
            }
            let oldVisibleHeaderHeight = Swift.max(
                old.resolvedHeaderHeight.collapsed,
                old.resolvedHeaderHeight.expanded - old.collapseOffset
            )
            return clamped(
                new.resolvedHeaderHeight.expanded - oldVisibleHeaderHeight,
                lowerBound: 0,
                upperBound: new.resolvedHeaderHeight.collapsibleDistance
            )
        case .preserveCollapseProgress:
            guard let old else {
                return clamped(
                    nonNegativeFinite(current),
                    lowerBound: 0,
                    upperBound: new.resolvedHeaderHeight.collapsibleDistance
                )
            }
            return clamped(
                new.resolvedHeaderHeight.collapsibleDistance * old.collapseProgress,
                lowerBound: 0,
                upperBound: new.resolvedHeaderHeight.collapsibleDistance
            )
        case .resetToExpanded:
            return 0
        case .resetToCollapsed:
            return new.resolvedHeaderHeight.collapsibleDistance
        }
    }

    private func resolvedHeaderHeight(
        measuredHeaderHeight: CGFloat,
        mode: AnchorPagerHeaderHeightMode
    ) -> ResolvedHeaderHeight {
        let measuredHeaderHeight = nonNegativeFinite(measuredHeaderHeight)

        switch mode {
        case let .automatic(min, max):
            let collapsed = nonNegativeFinite(min)
            let upperBound = max.map { Swift.max(collapsed, nonNegativeFinite($0)) }
            let measuredExpanded = Swift.max(collapsed, measuredHeaderHeight)
            let expanded = upperBound.map {
                Swift.min($0, measuredExpanded)
            } ?? measuredExpanded
            return ResolvedHeaderHeight(expanded: expanded, collapsed: collapsed)
        case let .fixed(max, min):
            let collapsed = nonNegativeFinite(min)
            let expanded = Swift.max(collapsed, nonNegativeFinite(max))
            return ResolvedHeaderHeight(expanded: expanded, collapsed: collapsed)
        case let .ranged(min, max):
            let collapsed = nonNegativeFinite(min)
            let upperBound = Swift.max(collapsed, nonNegativeFinite(max))
            let expanded = clamped(
                measuredHeaderHeight,
                lowerBound: collapsed,
                upperBound: upperBound
            )
            return ResolvedHeaderHeight(expanded: expanded, collapsed: collapsed)
        }
    }

    private func nonNegativeFinite(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return Swift.max(0, value)
    }

    private func clamped(
        _ value: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        Swift.min(upperBound, Swift.max(lowerBound, value))
    }
}
