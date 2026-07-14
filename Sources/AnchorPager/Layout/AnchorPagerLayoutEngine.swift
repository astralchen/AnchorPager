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
        var logicalContentOffsetY: CGFloat
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
        var childBottomObstruction: CGFloat
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
            nonNegativeFinite(input.logicalContentOffsetY),
            lowerBound: 0,
            upperBound: collapsibleDistance
        )
        let collapseProgress = collapsibleDistance > 0
            ? collapseOffset / collapsibleDistance
            : 0
        let topPinY = bounds.minY + topObstructionHeight
        let headerFrame: CGRect
        switch input.headerTopBehavior {
        case .insideSafeArea:
            headerFrame = CGRect(
                x: bounds.minX,
                y: topPinY - collapseOffset,
                width: bounds.width,
                height: resolvedHeaderHeight.expanded
            )
        case .extendsUnderTopSafeArea:
            headerFrame = CGRect(
                x: bounds.minX,
                y: bounds.minY - collapseOffset,
                width: bounds.width,
                height: topObstructionHeight + resolvedHeaderHeight.expanded
            )
        }
        let barY = topPinY + resolvedHeaderHeight.expanded - collapseOffset
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
        let safeVisibleMaxY = bounds.maxY - nonNegativeFinite(input.bottomObstructionHeight)
        let childBottomObstruction = nonNegativeFinite(pagingFrame.maxY - safeVisibleMaxY)

        return Output(
            resolvedHeaderHeight: resolvedHeaderHeight,
            collapseOffset: collapseOffset,
            collapseProgress: collapseProgress,
            headerFrame: headerFrame,
            barFrame: barFrame,
            contentFrame: contentFrame,
            pagingFrame: pagingFrame,
            childBottomObstruction: childBottomObstruction
        )
    }

    func adjustedLogicalOffsetY(
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

    func resolvedHeaderHeight(
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
