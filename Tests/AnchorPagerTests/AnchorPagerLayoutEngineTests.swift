import CoreGraphics
import XCTest
@testable import AnchorPager

final class AnchorPagerLayoutEngineTests: XCTestCase {
    func testAutomaticHeightUsesMeasuredHeightClampedByMinAndMax() {
        let output = AnchorPagerLayoutEngine().layout(
            for: input(
                measuredHeaderHeight: 120,
                headerHeightMode: .automatic(min: 40, max: 96)
            )
        )

        XCTAssertEqual(output.resolvedHeaderHeight.expanded, 96)
        XCTAssertEqual(output.resolvedHeaderHeight.collapsed, 40)
        XCTAssertEqual(output.resolvedHeaderHeight.collapsibleDistance, 56)
    }

    func testFixedHeightUsesMaxAsExpandedAndMinAsCollapsed() {
        let output = AnchorPagerLayoutEngine().layout(
            for: input(
                measuredHeaderHeight: 12,
                headerHeightMode: .fixed(max: 88, min: 24)
            )
        )

        XCTAssertEqual(output.resolvedHeaderHeight.expanded, 88)
        XCTAssertEqual(output.resolvedHeaderHeight.collapsed, 24)
        XCTAssertEqual(output.resolvedHeaderHeight.collapsibleDistance, 64)
    }

    func testRangedHeightClampsMeasuredHeight() {
        let shortOutput = AnchorPagerLayoutEngine().layout(
            for: input(
                measuredHeaderHeight: 20,
                headerHeightMode: .ranged(min: 64, max: 120)
            )
        )
        let tallOutput = AnchorPagerLayoutEngine().layout(
            for: input(
                measuredHeaderHeight: 160,
                headerHeightMode: .ranged(min: 64, max: 120)
            )
        )

        XCTAssertEqual(shortOutput.resolvedHeaderHeight.expanded, 64)
        XCTAssertEqual(shortOutput.resolvedHeaderHeight.collapsed, 64)
        XCTAssertEqual(tallOutput.resolvedHeaderHeight.expanded, 120)
        XCTAssertEqual(tallOutput.resolvedHeaderHeight.collapsed, 64)
    }

    func testInsideSafeAreaPlacesHeaderBelowTopObstruction() {
        let output = AnchorPagerLayoutEngine().layout(
            for: input(
                headerTopBehavior: .insideSafeArea,
                topObstructionHeight: 44
            )
        )

        XCTAssertEqual(output.headerFrame.minY, 44)
        XCTAssertEqual(output.headerFrame.height, 100)
        XCTAssertEqual(output.barFrame.minY, output.headerFrame.maxY)
    }

    func testExtendsUnderTopSafeAreaPlacesHeaderAtBoundsTop() {
        let output = AnchorPagerLayoutEngine().layout(
            for: input(
                headerTopBehavior: .extendsUnderTopSafeArea,
                topObstructionHeight: 44
            )
        )

        XCTAssertEqual(output.headerFrame.minY, 0)
        XCTAssertEqual(output.headerFrame.height, 144)
        XCTAssertEqual(output.barFrame.minY, 144)
        XCTAssertEqual(output.barFrame.minY, output.headerFrame.maxY)
    }

    func testTopBehaviorsKeepSameBarBaseline() {
        let inside = AnchorPagerLayoutEngine().layout(
            for: input(
                measuredHeaderHeight: 100,
                headerHeightMode: .fixed(max: 100, min: 20),
                headerTopBehavior: .insideSafeArea,
                topObstructionHeight: 44,
                contentOffsetY: 30
            )
        )
        let extended = AnchorPagerLayoutEngine().layout(
            for: input(
                measuredHeaderHeight: 100,
                headerHeightMode: .fixed(max: 100, min: 20),
                headerTopBehavior: .extendsUnderTopSafeArea,
                topObstructionHeight: 44,
                contentOffsetY: 30
            )
        )

        XCTAssertEqual(inside.barFrame.minY, extended.barFrame.minY)
        XCTAssertEqual(inside.headerFrame.height, 70)
        XCTAssertEqual(extended.headerFrame.height, 114)
        XCTAssertEqual(inside.resolvedHeaderHeight.collapsibleDistance, 80)
        XCTAssertEqual(extended.resolvedHeaderHeight.collapsibleDistance, 80)
    }

    func testPagingFrameMovesWithHeaderButKeepsCollapsedViewportHeight() {
        let engine = AnchorPagerLayoutEngine()
        let expanded = engine.layout(
            for: input(
                headerHeightMode: .fixed(max: 100, min: 20),
                topObstructionHeight: 44,
                contentOffsetY: 0
            )
        )
        let collapsed = engine.layout(
            for: input(
                headerHeightMode: .fixed(max: 100, min: 20),
                topObstructionHeight: 44,
                contentOffsetY: 80
            )
        )

        XCTAssertEqual(expanded.pagingFrame.minY, 144)
        XCTAssertEqual(collapsed.pagingFrame.minY, 64)
        XCTAssertEqual(expanded.pagingFrame.height, 576)
        XCTAssertEqual(collapsed.pagingFrame.height, 576)
        XCTAssertEqual(expanded.pagingFrame.maxY, 720)
        XCTAssertEqual(collapsed.pagingFrame.maxY, 640)
    }

    func testExtendsUnderTopSafeAreaCoversTopObstructionWhenHeaderIsShorter() {
        let output = AnchorPagerLayoutEngine().layout(
            for: input(
                measuredHeaderHeight: 108,
                headerHeightMode: .fixed(max: 108, min: 0),
                headerTopBehavior: .extendsUnderTopSafeArea,
                topObstructionHeight: 116
            )
        )

        XCTAssertEqual(output.resolvedHeaderHeight.expanded, 108)
        XCTAssertEqual(output.headerFrame.minY, 0)
        XCTAssertEqual(output.headerFrame.height, 224)
        XCTAssertEqual(output.barFrame.minY, output.headerFrame.maxY)
        XCTAssertEqual(output.contentFrame.maxY, 640)
    }

    func testExtendsUnderTopSafeAreaMaintainsTopObstructionCoverageWhileCollapsed() {
        let output = AnchorPagerLayoutEngine().layout(
            for: input(
                measuredHeaderHeight: 160,
                headerHeightMode: .fixed(max: 160, min: 0),
                headerTopBehavior: .extendsUnderTopSafeArea,
                topObstructionHeight: 116,
                contentOffsetY: 80
            )
        )

        XCTAssertEqual(output.collapseOffset, 80)
        XCTAssertEqual(output.collapseProgress, 0.5)
        XCTAssertEqual(output.headerFrame.minY, 0)
        XCTAssertEqual(output.headerFrame.height, 196)
        XCTAssertEqual(output.barFrame.minY, output.headerFrame.maxY)
    }

    func testBottomObstructionDoesNotClipContentOrPagingFrame() {
        let output = AnchorPagerLayoutEngine().layout(
            for: input(
                bottomObstructionHeight: 83
            )
        )

        XCTAssertEqual(output.contentFrame.maxY, 640)
        XCTAssertEqual(output.contentFrame.height, 492)
        XCTAssertEqual(output.pagingFrame.height, 640)
    }

    func testOffsetAdjustmentStrategiesReturnExpectedContentOffset() {
        let engine = AnchorPagerLayoutEngine()
        let old = engine.layout(
            for: input(
                measuredHeaderHeight: 100,
                headerHeightMode: .fixed(max: 100, min: 20),
                contentOffsetY: 30
            )
        )
        let new = engine.layout(
            for: input(
                measuredHeaderHeight: 160,
                headerHeightMode: .fixed(max: 160, min: 20),
                contentOffsetY: 30
            )
        )

        XCTAssertEqual(
            engine.adjustedContentOffsetY(
                current: 30,
                old: old,
                new: new,
                strategy: .preserveVisualPosition
            ),
            90
        )
        XCTAssertEqual(
            engine.adjustedContentOffsetY(
                current: 30,
                old: old,
                new: new,
                strategy: .preserveCollapseProgress
            ),
            52.5
        )
        XCTAssertEqual(
            engine.adjustedContentOffsetY(
                current: 30,
                old: old,
                new: new,
                strategy: .resetToExpanded
            ),
            0
        )
        XCTAssertEqual(
            engine.adjustedContentOffsetY(
                current: 30,
                old: old,
                new: new,
                strategy: .resetToCollapsed
            ),
            140
        )
    }

    private func input(
        bounds: CGRect = CGRect(x: 0, y: 0, width: 320, height: 640),
        measuredHeaderHeight: CGFloat = 100,
        headerHeightMode: AnchorPagerHeaderHeightMode = .fixed(max: 100, min: 0),
        headerTopBehavior: AnchorPagerHeaderTopBehavior = .insideSafeArea,
        // 输入值表示 Tabman 完成布局后的真实 bar 高度。
        barHeight: CGFloat = 48,
        topObstructionHeight: CGFloat = 0,
        bottomObstructionHeight: CGFloat = 0,
        contentOffsetY: CGFloat = 0
    ) -> AnchorPagerLayoutEngine.Input {
        AnchorPagerLayoutEngine.Input(
            bounds: bounds,
            measuredHeaderHeight: measuredHeaderHeight,
            headerHeightMode: headerHeightMode,
            headerTopBehavior: headerTopBehavior,
            barHeight: barHeight,
            topObstructionHeight: topObstructionHeight,
            bottomObstructionHeight: bottomObstructionHeight,
            contentOffsetY: contentOffsetY
        )
    }
}
