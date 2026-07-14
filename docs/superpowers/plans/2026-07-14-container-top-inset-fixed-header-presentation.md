# 主容器顶部 Inset 与固定高度 Header Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `.insideSafeArea` 使用主容器真实顶部 safe-area inset、`.extendsUnderTopSafeArea` 使用零 top inset，同时保持业务 Header 完整高度，通过独立 canonical presentation surface 完成正常折叠、bar 吸顶和既有双边界回弹。

**Architecture:** 新增纯 `AnchorPagerContainerScrollGeometry` 统一 raw/logical offset、稳定边界、overflow 与 scroll range；LayoutEngine 只消费逻辑 offset 并输出固定高度 Header 的实际呈现 frame。ScrollCoordinator 保持唯一协调期 offset writer，ViewController 在固定 viewport 内新增不裁剪的 canonical content surface，正常折叠移动该 surface、container top 移动 viewport、plain bottom 只移动 Pageboy page surface。

**Tech Stack:** Swift 6.2、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、Tabman 4.0.1、Pageboy 5.0.2、XCTest/XCUITest、Xcode 26.6、iPhone 17 Pro / iOS 26.5 Simulator。

## Global Constraints

- 设计基线固定为 `docs/superpowers/specs/2026-07-14-container-top-inset-fixed-header-presentation-design.md`，实施起点不早于设计提交 `7885d9e`。
- Public API 不新增或删除 symbol；只修订 `AnchorPagerHeaderTopBehavior`、`verticalScrollView` 与 `AnchorPagerLayoutContext.headerFrame` 的 DocC 行为说明。
- `verticalScrollView.contentInsetAdjustmentBehavior` 始终为 `.never`；container left/bottom/right inset 为 `0`，inside top inset 为本地顶部 obstruction，extends top inset 为 `0`。
- child managed top 继续只等于 Tabman bar obstruction，不包含 Header、container top inset 或 safe area。
- `AnchorPagerScrollCoordinator` 保持协调期唯一 offset writer；`AnchorPagerOverscrollCoordinator` 不持有 UIKit/page/provider，也不直接写 offset。
- 不设置业务 child `UIScrollView.delegate`、内建 pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。
- 不恢复 synthetic scroll wrapper，不改变 Pageboy page containment，不直接修改业务 page 或业务 Header 根 view transform。
- Header UIViewController 保持标准 containment；automatic measurement、identity cache、preinstall bootstrap seed 与正式 measurement 日志边界不变。
- 固定 `viewportView` 是唯一屏幕裁剪边界；normal collapse 不得变换该 viewport，plain bottom 不得移动 Header/bar。
- 高频 pan、KVO、scroll delegate 与 layout 热路径不逐帧输出普通日志。
- 每个实现任务严格执行 RED → 最小 GREEN → 聚焦回归 → 自审 → `git diff --check` → 中文单一主题提交。

---

## 文件与职责

- Create `Sources/AnchorPager/Core/AnchorPagerContainerScrollGeometry.swift`：container top inset、raw/logical 双向转换、稳定边界、overflow 和 scroll range 的唯一纯计算来源。
- Create `Tests/AnchorPagerTests/AnchorPagerContainerScrollGeometryTests.swift`：纯坐标、退化距离、非有限输入和 range 公式。
- Modify `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`：只消费逻辑 offset，输出固定高度 Header/固定 paging viewport 的实际呈现 frame。
- Modify `Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift`：固定 Header 高度、bar baseline、child bottom obstruction 和 offset adjustment。
- Modify `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`：所有 container boundary/read/write 迁移到 `AnchorPagerContainerScrollGeometry`。
- Modify `Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift`：带 top inset 的 handoff、顶部三模式、plain/child bottom、geometry migration 与日志回归。
- Modify `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：canonical content surface、真实 container inset、结构性逻辑 offset 迁移、LayoutContext 和日志装配。
- Modify `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`：顶部行为 DocC。
- Modify `Sources/AnchorPager/Public/AnchorPagerLayoutContext.swift`：固定高度 Header 与三层 presentation 后的实际 frame DocC。
- Modify `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：真实 inset、固定 Header height、safe-area/behavior migration、Pageboy/plain/measurement/lifecycle 集成回归。
- Modify `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`：序列化 container inset 与 Header 几何探针。
- Modify `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`：使用 inset-aware boundary 采样，并记录固定 Header presentation。
- Modify `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`：探针序列化、reset 与菜单切换单元测试。
- Modify `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：inside/extends inset、固定 Header height、bar 吸顶和全部边界 owner 真实手势验收。
- Modify `AGENTS.md`、`README.md`、`docs/requirements.md`、`docs/architecture.md`、`docs/task-list.md`、roadmap、相关 specs/plans：同步最终行为、验收证据和 Ready 门禁。

---

### Task 1：建立主容器纯坐标模型

**Files:**
- Create: `Sources/AnchorPager/Core/AnchorPagerContainerScrollGeometry.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerContainerScrollGeometryTests.swift`

**Interfaces:**
- Produces: `AnchorPagerContainerScrollGeometry.init(topInset:collapsibleDistance:)`。
- Produces: `topInset(for:topObstructionHeight:)`、`logicalOffset(forRawOffset:)`、`rawOffset(forLogicalOffset:)`、`clampedLogicalOffset(_:)`。
- Produces: `expandedRawOffset`、`collapsedRawOffset`、`topOverflow(forRawOffset:)`、`bottomOverflow(forRawOffset:)`、`scrollRangeHeight(viewportHeight:)`。
- Consumes: `AnchorPagerHeaderTopBehavior`；不 import UIKit，不读写 `UIScrollView`。

- [x] **Step 1：先写纯坐标失败测试**

创建 `AnchorPagerContainerScrollGeometryTests.swift`：

```swift
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
```

- [x] **Step 2：运行 RED，确认只因新类型不存在而失败**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerContainerScrollGeometryTests test
```

预期：编译失败并明确缺少 `AnchorPagerContainerScrollGeometry`；不得出现依赖解析或其他测试失败。

- [x] **Step 3：实现最小纯坐标类型**

创建 `AnchorPagerContainerScrollGeometry.swift`：

```swift
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
```

- [x] **Step 4：运行 GREEN 与纯计算相邻回归**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerContainerScrollGeometryTests -only-testing:AnchorPagerTests/AnchorPagerScrollPositionResolverTests test
git diff --check
```

预期：两个测试类全部通过；新文件不 import UIKit、没有 actor/unsafe 标记。

- [x] **Step 5：自审并提交 Task 1**

自审确认 top inset 只有一个解析入口，raw/logical 转换互逆，`D == 0` 时 expanded/collapsed raw boundary 相同，range 公式为 `H + D - I`。

```bash
git add Sources/AnchorPager/Core/AnchorPagerContainerScrollGeometry.swift Tests/AnchorPagerTests/AnchorPagerContainerScrollGeometryTests.swift
git commit -m "新增主容器逻辑滚动几何"
```

---

### Task 2：让 LayoutEngine 输出固定高度 Header 几何

**Files:**
- Modify: `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift`

**Interfaces:**
- Consumes: `Input.logicalContentOffsetY`，不再接收 raw `contentOffsetY`。
- Produces: `resolvedHeaderHeight(measuredHeaderHeight:mode:)` 供 ViewController 构造 container geometry。
- Produces: 固定高度 `headerFrame`、实际呈现 `barFrame/contentFrame/pagingFrame` 与逻辑 `collapseOffset`。
- Produces: `adjustedLogicalOffsetY(current:old:new:strategy:)`。

- [ ] **Step 1：先把 LayoutEngine 测试改为固定高度契约**

将测试 helper 参数改名为 `logicalContentOffsetY`，并新增/修改以下断言：

```swift
func testTopBehaviorsKeepFixedHeaderHeightAndSameBarBaselineWhileCollapsed() {
    let inside = AnchorPagerLayoutEngine().layout(
        for: input(
            measuredHeaderHeight: 100,
            headerHeightMode: .fixed(max: 100, min: 20),
            headerTopBehavior: .insideSafeArea,
            topObstructionHeight: 44,
            logicalContentOffsetY: 30
        )
    )
    let extended = AnchorPagerLayoutEngine().layout(
        for: input(
            measuredHeaderHeight: 100,
            headerHeightMode: .fixed(max: 100, min: 20),
            headerTopBehavior: .extendsUnderTopSafeArea,
            topObstructionHeight: 44,
            logicalContentOffsetY: 30
        )
    )

    XCTAssertEqual(inside.headerFrame, CGRect(x: 0, y: 14, width: 320, height: 100))
    XCTAssertEqual(extended.headerFrame, CGRect(x: 0, y: -30, width: 320, height: 144))
    XCTAssertEqual(inside.barFrame.minY, 114)
    XCTAssertEqual(extended.barFrame.minY, 114)
    XCTAssertEqual(inside.headerFrame.maxY, inside.barFrame.minY)
    XCTAssertEqual(extended.headerFrame.maxY, extended.barFrame.minY)
}

func testHeaderHeightRemainsConstantAcrossExpandedPartialAndCollapsedOffsets() {
    let engine = AnchorPagerLayoutEngine()
    let outputs = [0, 30, 80].map {
        engine.layout(for: input(
            headerHeightMode: .fixed(max: 100, min: 20),
            topObstructionHeight: 44,
            logicalContentOffsetY: CGFloat($0)
        ))
    }

    XCTAssertEqual(outputs.map(\.headerFrame.height), [100, 100, 100])
    XCTAssertEqual(outputs.map(\.headerFrame.minY), [44, 14, -36])
    XCTAssertEqual(outputs.map(\.barFrame.minY), [144, 114, 64])
}
```

更新 extends collapsed 测试：`logicalContentOffsetY == 80` 时 `headerFrame.minY == -80`、`headerFrame.height == topObstruction + expanded == 276`、`barFrame.minY == 196`。保留 paging height、child bottom obstruction、纯内容 height mode 与四种 offset adjustment 测试。

- [ ] **Step 2：运行 RED，证明旧实现仍在缩高**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests/testTopBehaviorsKeepFixedHeaderHeightAndSameBarBaselineWhileCollapsed -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests/testHeaderHeightRemainsConstantAcrossExpandedPartialAndCollapsedOffsets test
```

预期：旧实现分别得到 inside height `70`、extends height `114`，固定高度断言失败。

- [ ] **Step 3：把 LayoutEngine 输入和 frame 计算改为逻辑 offset**

把 `Input.contentOffsetY` 重命名为 `logicalContentOffsetY`，将 height 解析方法从 `private` 改为 module internal，并用以下 frame 计算替换 `visibleContentHeight` 分支：

```swift
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
```

保留：

```swift
let collapsedAdapterTop = topPinY + resolvedHeaderHeight.collapsed
let pagingFrame = CGRect(
    x: bounds.minX,
    y: barY,
    width: bounds.width,
    height: max(0, bounds.maxY - collapsedAdapterTop)
)
```

把 `adjustedContentOffsetY` 重命名为 `adjustedLogicalOffsetY`；函数内部继续只在 `0...new.collapsibleDistance` 计算，不加减 container inset。`.preserveVisualPosition` 继续保持逻辑可见纯内容量 `E - collapseOffset`，从而保持 bar/paging baseline；不得改用固定业务根 view 与物理 viewport 的交集高度。

- [ ] **Step 4：运行 LayoutEngine 完整 GREEN**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests test
git diff --check
```

预期：LayoutEngine 全部通过；paging height 在三个折叠位置相同，child bottom obstruction仍从 `D + bottom` 收敛到 `bottom`。

- [ ] **Step 5：自审并提交 Task 2**

自审确认 `headerFrame.height` 不再依赖 collapseOffset、两种 top behavior 的 bar baseline 相同、top obstruction 不进入 `D`、offset adjustment 返回逻辑值。

```bash
git add Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift
git commit -m "固定 Header 布局几何"
```

---

### Task 3：把 ScrollCoordinator 全面迁移到逻辑 Container Offset

**Files:**
- Modify: `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AnchorPagerContainerScrollGeometry`。
- Replaces: `updateGeometry(collapsibleDistance:)`。
- Produces: `updateGeometry(_:targetLogicalOffset:)`；`Position.containerOffset` 始终表示逻辑 container distance。
- Preserves: child KVO/pan binding、simultaneous recognition、top mode matrix、native boundary pass-through 与业务 bounce 配置。

- [ ] **Step 1：增加带 top inset 的协调 RED**

扩展测试 `Fixture`：

```swift
init(
    collapsedOffset: CGFloat = 100,
    childMaximumDistance: CGFloat = 500,
    topInset: CGFloat = 0
) {
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
    coordinator = AnchorPagerScrollCoordinator(containerScrollView: container)
    coordinator.updateGeometry(
        AnchorPagerContainerScrollGeometry(
            topInset: topInset,
            collapsibleDistance: collapsedOffset
        )
    )
    coordinator.bindCommittedChild(child)
}
```

新增：

```swift
func testInsetGeometryUsesLogicalOffsetsForHandoffAndBoundaries() {
    let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500, topInset: 44)

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
        AnchorPagerContainerScrollGeometry(topInset: 0, collapsibleDistance: 100),
        targetLogicalOffset: 40
    )

    XCTAssertEqual(fixture.container.contentOffset.y, 40, accuracy: 0.001)
    XCTAssertEqual(fixture.child.contentOffset.y, -fixture.child.contentInset.top, accuracy: 0.001)
}
```

- [ ] **Step 2：运行 RED，确认失败来自 raw offset 假设**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests/testInsetGeometryUsesLogicalOffsetsForHandoffAndBoundaries -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests/testChildTopModePinsContainerToInsetExpandedBoundary -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests/testGeometryMigrationWritesRawOffsetForPreservedLogicalDistance test
```

预期：接口编译失败或旧 coordinator 把 raw `-44/56` 当作逻辑 `0/56`，目标断言失败。

- [ ] **Step 3：替换 coordinator geometry 状态与结构性更新入口**

删除 `private var collapsibleDistance`，新增：

```swift
private var containerGeometry: AnchorPagerContainerScrollGeometry = .zero

func updateGeometry(
    _ geometry: AnchorPagerContainerScrollGeometry,
    targetLogicalOffset: CGFloat? = nil
) {
    let previous = currentStablePosition()
    if containerGeometry != geometry {
        overscrollCoordinator.cancel()
    }
    containerGeometry = geometry

    guard let targetLogicalOffset else {
        settleStableOffsets()
        return
    }

    let containerTarget = geometry.clampedLogicalOffset(targetLogicalOffset)
    let childTarget = containerTarget >= geometry.collapsibleDistance - epsilon
        ? previous.childDistance
        : 0
    apply(.init(containerOffset: containerTarget, childDistance: childTarget))
}
```

`handlePan`、resolver、maximum stable total、transition logs 全部使用 `containerGeometry.collapsibleDistance`。

- [ ] **Step 4：集中替换 raw read/write 与边界判断**

用以下实现替换对应 helper：

```swift
func currentStablePosition() -> AnchorPagerScrollPositionResolver.Position {
    let container = containerGeometry.clampedLogicalOffset(
        containerGeometry.logicalOffset(
            forRawOffset: containerScrollView.contentOffset.y
        )
    )
    let childDistance = committedChildScrollView.map {
        min(
            max(0, $0.contentOffset.y + $0.contentInset.top),
            childMaximumDistance
        )
    } ?? 0
    return .init(containerOffset: container, childDistance: childDistance)
}

func writeContainerBoundary(_ logicalTarget: CGFloat) {
    let rawTarget = containerGeometry.rawOffset(forLogicalOffset: logicalTarget)
    guard abs(containerScrollView.contentOffset.y - rawTarget) > epsilon else { return }
    isApplyingGuardedOffsets = true
    defer { isApplyingGuardedOffsets = false }
    containerScrollView.contentOffset.y = rawTarget
}
```

在 `apply(_:)` 的 `writeContainer` closure 中把 `position.containerOffset` 转成 raw target。`activeOverflowDistance` 的 container 两支改为：

```swift
case (.top, .container):
    return containerGeometry.topOverflow(
        forRawOffset: containerScrollView.contentOffset.y
    )
case (.bottom, .container):
    return containerGeometry.bottomOverflow(
        forRawOffset: containerScrollView.contentOffset.y
    )
```

`handleObservedBoundaryIfNeeded()` 先计算：

```swift
let containerLogicalOffset = containerGeometry.logicalOffset(
    forRawOffset: containerScrollView.contentOffset.y
)
```

然后用 `< -boundaryEpsilon`、`>= D - boundaryEpsilon`、`> D + boundaryEpsilon` 判断。`childDidChange` 也只比较 `containerLogicalOffset < D - epsilon`。所有 top stable write 使用逻辑 `0`，所有 bottom stable write 使用逻辑 `D`。

- [ ] **Step 5：运行 ScrollCoordinator 完整 GREEN**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests -only-testing:AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests -only-testing:AnchorPagerTests/AnchorPagerContainerScrollViewTests test
git diff --check
```

预期：旧 topInset=0 全量行为保持，新增 topInset=44 三项通过；owner/boundary/handoff 日志计数不增加，业务 bounce 属性测试继续通过。

- [ ] **Step 6：静态审查并提交 Task 3**

```bash
rg -n "containerScrollView\.contentOffset\.y" Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift
```

逐项确认每个命中都通过 `containerGeometry` 转换或仅执行已经转换好的 raw 写入；不得再直接把 raw 与 `0`/`D` 比较。

```bash
git add Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift
git commit -m "迁移纵向协调到逻辑 offset"
```

---

### Task 4：安装固定 Header Canonical Presentation Surface

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Adds internal hierarchy: `viewportView -> contentPresentationView -> headerHostView/pagingHostView`。
- Preserves: `viewportView` 作为屏幕裁剪与 container top bounce surface。
- Preserves: `AnchorPagerPagingHostViewController.setPagePresentationTranslationY(_:)` 作为 plain bottom 唯一 page-only surface。
- Prohibits: 直接修改业务 Header 根 view、业务 page 根 view或 Pageboy containment。

- [ ] **Step 1：先写层级、固定高度与 presentation owner 的失败测试**

在 `AnchorPagerViewControllerTests.swift` 增加私有 `FixedHeaderPresentationFixture`。其 initializer 接收 `topBehavior`、expanded/collapsed height 和 plain/scroll child 类型；从 `headerView.superview` 取得 HeaderHost、从 HeaderHost 的父视图取得 `contentPresentationView`、再从其父视图取得 `viewportView`，不增加 production test hook 或 public API。fixture 提供 `setLogicalOffset(_:)`（内部执行 `logical - contentInset.top`）、`layout()`、`capturePresentation()` 和 `collapsibleDistance`。snapshot 固定包含 Header/paging/plain page frame、viewport/canonical transform。

先增加/修订以下集成断言：

```swift
func testStableCollapseKeepsHeaderHostHeightAndMovesCanonicalContentSurface() throws {
    let fixture = try FixedHeaderPresentationFixture(
        expandedHeaderHeight: 100,
        collapsedHeaderHeight: 20
    )
    let expanded = fixture.capturePresentation()

    fixture.setLogicalOffset(30)
    fixture.layout()
    let partial = fixture.capturePresentation()

    fixture.setLogicalOffset(80)
    fixture.layout()
    let collapsed = fixture.capturePresentation()

    XCTAssertEqual([expanded.headerHeight, partial.headerHeight, collapsed.headerHeight], [100, 100, 100])
    XCTAssertEqual(partial.headerMinY, expanded.headerMinY - 30, accuracy: 0.5)
    XCTAssertEqual(collapsed.headerMinY, expanded.headerMinY - 80, accuracy: 0.5)
    XCTAssertEqual(partial.viewportTransform, .identity)
    XCTAssertEqual(collapsed.viewportTransform, .identity)
}

func testCanonicalSurfaceSitsBetweenViewportAndBothHosts() throws {
    let fixture = try FixedHeaderPresentationFixture()

    XCTAssertTrue(fixture.headerHost.superview === fixture.contentPresentationView)
    XCTAssertTrue(fixture.pagingHostView.superview === fixture.contentPresentationView)
    XCTAssertTrue(fixture.contentPresentationView.superview === fixture.viewportView)
}

func testStableCollapseKeepsPagingViewportHeightAndPlainPagePhysicalBottom() throws {
    let fixture = try FixedHeaderPresentationFixture(usesPlainPage: true)
    let expanded = fixture.capturePresentation()

    fixture.setLogicalOffset(fixture.collapsibleDistance)
    fixture.layout()
    let collapsed = fixture.capturePresentation()

    XCTAssertEqual(collapsed.pagingHeight, expanded.pagingHeight, accuracy: 0.5)
    XCTAssertEqual(collapsed.plainPageFrame.maxY, fixture.pager.view.bounds.maxY, accuracy: 0.5)
}
```

同时更新既有 `testNegativeContainerOffsetTranslatesViewportAndLayoutContextWithoutChangingRange` 与 `testPlainBottomOverflowMovesOnlyPageSurfaceAndRestoresCanonicalChrome`：顶部 container owner 只断言 `viewportView.transform.ty > 0`；plain bottom 只断言 Pageboy page surface 上移，并严格断言 viewport、canonical content surface、Header/bar 均不动。

- [ ] **Step 2：运行 RED，确认旧层级和缩高行为失败**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testStableCollapseKeepsHeaderHostHeightAndMovesCanonicalContentSurface -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testCanonicalSurfaceSitsBetweenViewportAndBothHosts -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testStableCollapseKeepsPagingViewportHeightAndPlainPagePhysicalBottom test
```

预期：旧实现没有中间 surface，Header host 随 collapse 缩高，测试失败。

- [ ] **Step 3：建立 canonical surface 和 expanded canonical constraints**

在 `AnchorPagerViewController` 增加：

```swift
private let contentPresentationView = UIView()
```

安装顺序固定为：

```swift
viewportView.addSubview(contentPresentationView)
contentPresentationView.translatesAutoresizingMaskIntoConstraints = false
contentPresentationView.clipsToBounds = false
NSLayoutConstraint.activate([
    contentPresentationView.topAnchor.constraint(equalTo: viewportView.topAnchor),
    contentPresentationView.leadingAnchor.constraint(equalTo: viewportView.leadingAnchor),
    contentPresentationView.trailingAnchor.constraint(equalTo: viewportView.trailingAnchor),
    contentPresentationView.bottomAnchor.constraint(equalTo: viewportView.bottomAnchor),
])
```

把 Header host 与 Paging host 的父视图从 `viewportView` 改为 `contentPresentationView`。constraints 始终表达 expanded canonical geometry：Header host 顶部/高度是完整展开尺寸，Paging host 从 Header host 底部开始且高度固定；normal collapse 只由 `contentPresentationView.transform` 表达。

安装完成只记录一次低频日志：

```swift
AnchorPagerLogger.log(
    .info,
    category: .layout,
    event: "layout.headerPresentationInstalled"
)
```

- [ ] **Step 4：分离 normal collapse、top bounce 与 plain bottom 三个 surface**

在本任务先以 `topInset == 0` 的临时 geometry 接通固定呈现，Task 5 再接真实 inset：

```swift
let geometry = AnchorPagerContainerScrollGeometry(
    topInset: 0,
    collapsibleDistance: output.resolvedHeaderHeight.collapsibleDistance
)
let presentation = containerPresentation(for: output, geometry: geometry)

viewportView.transform = CGAffineTransform(
    translationX: 0,
    y: presentation.chromeTranslationY
)
contentPresentationView.transform = CGAffineTransform(
    translationX: 0,
    y: -output.collapseOffset
)
pagingHost.setPagePresentationTranslationY(
    presentation.pageSurfaceTranslationY
)
```

把 `containerPresentation(for:)` 临时改为 `containerPresentation(for:geometry:)`：top overflow 使用 `geometry.topOverflow(forRawOffset:)`，bottom overflow 使用 `geometry.bottomOverflow(forRawOffset:)`；只有 committed plain page 把 bottom overflow 转成负的 `pageSurfaceTranslationY`。Task 5 接入持久 `containerGeometry` 后删除临时参数，不能保留第二份 boundary 公式。

应用 canonical constraints 时，把 LayoutEngine 的实际呈现 frame 还原成 expanded local coordinates：

```swift
headerViewHost.setTopOffset(output.headerFrame.minY + output.collapseOffset)
headerHeightConstraint.constant = output.headerFrame.height
pagingTopConstraint.constant = 0
pagingHeightConstraint.constant = output.pagingFrame.height
```

上述四项只允许在 `updatesScrollRange == true` 的结构性 layout 中写入；`updateVisibleLayoutForScrolling()` 的热路径只更新 `contentPresentationView.transform`、边界 presentation、LayoutContext 和 collapse delegate。这样 HeaderHost 的 required height 不会在普通滚动中反复赋值，即使目标常量相同也不写。

`measureHeaderHeight`、reload/selection cancel 和 `deinit` 都必须把 `viewportView`、`contentPresentationView` 与 Pageboy page surface 恢复为 identity/zero；不得依赖父视图释放隐式清理。

- [ ] **Step 5：运行 ViewController presentation GREEN 与日志回归**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testStableCollapseKeepsHeaderHostHeightAndMovesCanonicalContentSurface -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testCanonicalSurfaceSitsBetweenViewportAndBothHosts -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testStableCollapseKeepsPagingViewportHeightAndPlainPagePhysicalBottom -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testNegativeContainerOffsetTranslatesViewportAndLayoutContextWithoutChangingRange -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testPlainBottomOverflowMovesOnlyPageSurfaceAndRestoresCanonicalChrome -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
git diff --check
```

预期：normal collapse 的 viewport transform 始终 identity；顶部 container bounce、plain bottom page-only bounce 和固定 paging height 同时通过；安装日志只出现一次。

- [ ] **Step 6：自审并提交 Task 4**

重点检查 Header UIViewController containment、Pageboy containment、host 父子层级、reload/deinit 清理和日志频率；确认没有业务根 view transform。

```bash
git add Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "增加固定 Header 内容呈现层"
```

---

### Task 5：接入真实 Container Top Inset 与结构性坐标迁移

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerLayoutContext.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Adds private state: `containerGeometry`、`hasAppliedContainerGeometry`、`lastLoggedContainerTopInset`。
- Consumes: LayoutEngine 的 resolved Header geometry、当前 safe-area obstruction、`AnchorPagerHeaderTopBehavior`。
- Produces: `verticalScrollView.contentInset.top`、raw/logical migration、`LayoutContext.headerFrame` 的最终可见坐标。
- Preserves: `AnchorPagerHeaderTopBehavior` public enum cases；不新增 public symbol。

- [ ] **Step 1：先写真实 inset、range 和迁移失败测试**

在测试 fixture 增加统一 helper，替换所有把 raw `0...D` 当作稳定区间的命名用例：

```swift
private func rawContainerOffset(
    forLogicalOffset logicalOffset: CGFloat,
    in pager: AnchorPagerViewController
) -> CGFloat {
    logicalOffset - pager.verticalScrollView.contentInset.top
}

private func setContainerLogicalOffset(
    _ logicalOffset: CGFloat,
    in pager: AnchorPagerViewController
) {
    pager.verticalScrollView.contentOffset.y = rawContainerOffset(
        forLogicalOffset: logicalOffset,
        in: pager
    )
}
```

新增测试矩阵：

```swift
func testInsideSafeAreaOwnsRealContainerTopInsetAndRawBoundaries() {
    let fixture = makeWindowFixture(topBehavior: .insideSafeArea)
    let inset = fixture.pager.verticalScrollView.contentInset.top

    XCTAssertGreaterThan(inset, 0)
    XCTAssertEqual(inset, fixture.topObstructionHeight, accuracy: 0.5)
    XCTAssertEqual(fixture.pager.verticalScrollView.adjustedContentInset.top, inset, accuracy: 0.5)
    XCTAssertEqual(fixture.pager.verticalScrollView.contentInset.left, 0)
    XCTAssertEqual(fixture.pager.verticalScrollView.contentInset.bottom, 0)
    XCTAssertEqual(fixture.pager.verticalScrollView.contentInset.right, 0)
    XCTAssertEqual(fixture.expandedRawOffset, -inset, accuracy: 0.5)
    XCTAssertEqual(fixture.collapsedRawOffset, fixture.collapsibleDistance - inset, accuracy: 0.5)
}

func testExtendsUnderTopSafeAreaOwnsZeroContainerTopInset() {
    let fixture = makeWindowFixture(topBehavior: .extendsUnderTopSafeArea)
    XCTAssertEqual(fixture.pager.verticalScrollView.contentInset.top, 0, accuracy: 0.001)
}

func testContainerRangeIsViewportPlusCollapseMinusTopInset() {
    let fixture = makeWindowFixture(topBehavior: .insideSafeArea)
    let expected = max(
        0,
        fixture.pager.verticalScrollView.bounds.height
            + fixture.collapsibleDistance
            - fixture.pager.verticalScrollView.contentInset.top
    )
    XCTAssertEqual(fixture.pager.verticalScrollView.contentSize.height, expected, accuracy: 0.5)
}

func testSwitchingTopBehaviorPreservesLogicalOffsetAndBarPresentation() {
    let fixture = makeWindowFixture(topBehavior: .insideSafeArea)
    fixture.setContainerLogicalOffset(40)
    let before = fixture.capturePresentation()

    fixture.setHeaderTopBehavior(.extendsUnderTopSafeArea)
    fixture.layout()
    let after = fixture.capturePresentation()

    XCTAssertEqual(after.logicalContainerOffset, 40, accuracy: 0.5)
    XCTAssertEqual(after.rawContainerOffset, 40, accuracy: 0.5)
    XCTAssertEqual(after.barMinY, before.barMinY, accuracy: 0.5)
}
```

再覆盖：`D == 0` 时 raw 单边界、`additionalSafeAreaInsets.top` 从 24 变 40 保留逻辑 progress、bounds/旋转改变保留 collapse progress、四种 `reloadHeaderLayout` strategy 都先在逻辑域计算再转 raw、container inset 日志仅在值变化时记录。固定高度测试同时断言 HeaderHost 与业务 Header 根 view 的 `bounds.height` 在 expanded/partial/collapsed 三态均不变。

把以下既有回归明确纳入本任务的完整 ViewController suite，不删除或放宽断言：`testReloadDataProvidesPlainChildDirectlyToPagingAdapter`、`testPlainPageRootReachesPagerAndWindowBottomWithoutFrameworkInsets`、`testCommittedPlainPageBindsNoChildPanAndContainerStillCollapses`、两个 automatic bootstrap 测试、Header UIViewController containment 测试、managed inset 幂等测试、selection/reload/size transition presentation cancel 测试。它们共同证明无滚动页仍为 nil scroll target、没有 wrapper，Header/Pageboy containment、bootstrap measurement、child inset 与 terminal 清理没有被新 container inset 侵入。

- [ ] **Step 2：运行 RED，确认旧实现 top inset 始终为零**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testInsideSafeAreaOwnsRealContainerTopInsetAndRawBoundaries -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testExtendsUnderTopSafeAreaOwnsZeroContainerTopInset -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testContainerRangeIsViewportPlusCollapseMinusTopInset -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testSwitchingTopBehaviorPreservesLogicalOffsetAndBarPresentation test
```

预期：inside inset/range/raw boundary 失败；extends 的零 inset 保持通过。

- [ ] **Step 3：建立 ViewController geometry 状态和解析入口**

新增：

```swift
private var containerGeometry: AnchorPagerContainerScrollGeometry = .zero
private var hasAppliedContainerGeometry = false
private var lastLoggedContainerTopInset: CGFloat?
```

新增私有解析函数，只使用当前正式 measurement/environment：

```swift
private func resolvedContainerGeometry(
    measuredHeaderHeight: CGFloat,
    environment: LayoutEnvironment
) -> AnchorPagerContainerScrollGeometry {
    let resolved = layoutEngine.resolvedHeaderHeight(
        measuredHeaderHeight: measuredHeaderHeight,
        mode: configuration.header.heightMode
    )
    return AnchorPagerContainerScrollGeometry(
        topInset: AnchorPagerContainerScrollGeometry.topInset(
            for: configuration.header.topBehavior,
            topObstructionHeight: environment.obstruction.top
        ),
        collapsibleDistance: resolved.collapsibleDistance
    )
}
```

`makeLayoutOutput` 改为显式接收 `logicalContentOffsetY`，不得从 `verticalScrollView.contentOffset.y` 隐式读取 raw 值。

- [ ] **Step 4：在一次 layout transaction 中迁移 geometry 与逻辑位置**

`updateVisibleLayout` 的固定顺序为：

1. 完成 Header measurement，取旧 geometry 下的 `previousLogicalOffset`；首次 layout 固定为 `0`。
2. 计算 `nextGeometry` 和 provisional output。
3. 若存在显式 reload strategy，调用 `adjustedLogicalOffsetY`；若只有 `D` 结构性变化，按旧 collapse progress 映射到新 `D`；否则 clamp 旧逻辑值。
4. geometry 变化先 `cancelBoundaryHandling()`，再设置真实 inset/range，并通过 ScrollCoordinator 写入目标 raw offset。
5. 用最终逻辑 offset 再生成 output，一次性应用 canonical constraints 与 presentation。

实现唯一装配入口：

```swift
private func applyContainerGeometry(
    _ geometry: AnchorPagerContainerScrollGeometry,
    targetLogicalOffset: CGFloat
) {
    verticalScrollView.contentInset = UIEdgeInsets(
        top: geometry.topInset,
        left: 0,
        bottom: 0,
        right: 0
    )

    containerGeometry = geometry
    hasAppliedContainerGeometry = true
    scrollCoordinator?.updateGeometry(
        geometry,
        targetLogicalOffset: targetLogicalOffset
    )
}
```

如 coordinator 尚未创建，fallback 也只用 `geometry.rawOffset(forLogicalOffset:)` 写一次 raw。仅当 top inset 真正变化时记录 `inset.containerTopChanged`，日志 payload 不包含业务数据。

- [ ] **Step 5：把所有 ViewController 边界与 range 消费迁到 geometry**

`applyLayoutOutput` 使用：

```swift
let rangeHeight = containerGeometry.scrollRangeHeight(
    viewportHeight: environment.bounds.height
)
scrollRangeHeightConstraint.constant = rangeHeight - environment.bounds.height
```

`updateVisibleLayoutForScrolling` 先把 raw 转成 logical 再调用 LayoutEngine。`containerPresentation` 使用 `topOverflow(forRawOffset:)`/`bottomOverflow(forRawOffset:)`。把 `layoutOutputByApplyingContentOffset` 重命名为 `layoutOutputByApplyingLogicalOffset`，整个函数不再处理 inset。

`configuration.didSet` 仅在 `oldValue.header != configuration.header` 时取消活动 boundary owner，再执行结构性迁移；单独改变 overscroll mode 或 paging cache 不能重置折叠位置。`viewSafeAreaInsetsDidChange`、bounds change、`reloadHeaderLayout`、`reloadData` 与 selection commit 都复用同一 transaction，不增加异步 delay、重复 layout 或强制 reset。

更新 `AnchorPagerHeaderTopBehavior`、`verticalScrollView` 与 `AnchorPagerLayoutContext.headerFrame` DocC：inside/extends 分别拥有真实 top inset/零 inset；调用方不得写 container inset；child managed inset ownership 不变；LayoutContext frame 是 pager 本地最终 presentation 坐标且 Header 高度在正常折叠中固定。

- [ ] **Step 6：更新 overscroll fixture 的 inset-aware 边界**

顶部 fixture 以：

```swift
let expandedRawOffset = -pager.verticalScrollView.contentInset.top
pager.verticalScrollView.contentOffset.y = expandedRawOffset - overflow
```

表示顶部回弹；canonical stable offset 恢复到 `expandedRawOffset`。plain bottom fixture 以 `rawContainerOffset(forLogicalOffset: D)` 和 `D + overflow` 表示稳定/回弹，不再硬编码 raw `100/124`。层级查找改为 Header host 的 `superview?.superview` 是 viewport，且严格区分 canonical surface。

- [ ] **Step 7：运行 ViewController 完整 GREEN 与禁止项扫描**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests -only-testing:AnchorPagerTests/AnchorPagerHeaderViewHostTests -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests test
rg -n "\.delegate\s*=|panGestureRecognizer\.delegate\s*=|isScrollEnabled\s*=|\.bounces\s*=|alwaysBounceVertical\s*=" Sources/AnchorPager
rg -n "contentOffset\.y\s*[<>]=?\s*(0|collapsibleDistance)|contentOffset\.y\s*-\s*collapsibleDistance" Sources/AnchorPager
git diff --check
```

预期：ViewController 集成测试全过；静态扫描没有业务 child 禁止写入；raw offset 不再直接与逻辑稳定边界比较。

- [ ] **Step 8：自审并提交 Task 5**

重点复核 safe-area/bounds/config/reload 结构性迁移、LayoutContext 最终可见 frame、Header measurement cache、child inset ownership、selection/reload/deinit 终态和日志去重。

```bash
git add Sources/AnchorPager/Public/AnchorPagerViewController.swift Sources/AnchorPager/Public/AnchorPagerConfiguration.swift Sources/AnchorPager/Public/AnchorPagerLayoutContext.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "接入主容器安全区 inset"
```

---

### Task 6：扩展 Example 探针与真实 UI 验收

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Adds test-only probe fields: `containerTopInset`、`headerHeight`、`maximumHeaderHeightDelta`、`headerCollapseTranslation`。
- Replaces Example raw-top assumption with inset-aware expanded/maximum raw boundaries。
- Preserves: 统一齿轮菜单、Header top behavior 菜单和 top overscroll mode 菜单。

- [ ] **Step 1：先扩展 probe 序列化 RED**

在 `ExampleScrollCoordinationState` 增加：

```swift
var containerTopInset: CGFloat = 0
var headerHeight: CGFloat = 0
var maximumHeaderHeightDelta: CGFloat = 0
var headerCollapseTranslation: CGFloat = 0
```

序列化稳定 key 固定为：

```text
containerTopInset
headerHeight
headerHeightDeltaMax
headerCollapse
```

先更新 `AnchorPagerExampleTests` 的完整 probe 字符串、record/reset 测试，使其因生产字段不存在而失败。reset 必须把本次 interaction 的最大高度差和 collapse translation 清零，不清除当前菜单选择。

- [ ] **Step 2：运行 Example unit RED**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerExampleTests test
```

预期：新字段/记录接口缺失导致编译或断言失败。

- [ ] **Step 3：实现 inset-aware boundary 与 Header 几何采样**

Example container boundary 统一改为：

```swift
let expandedRawOffset = -scrollView.contentInset.top
let maximumRawOffset = max(
    expandedRawOffset,
    scrollView.contentSize.height
        - scrollView.bounds.height
        + scrollView.contentInset.bottom
)
let topOverflow = max(0, expandedRawOffset - scrollView.contentOffset.y)
let bottomOverflow = max(0, scrollView.contentOffset.y - maximumRawOffset)
```

每次低频探针采样写入 `containerTopInset`。在 expanded stable 状态记录 Header baseline height/minY；正常折叠期间记录当前 `headerHeight`、`maximumHeaderHeightDelta = max(old, abs(currentHeight - baselineHeight))`、`headerCollapseTranslation = max(0, baselineMinY - currentMinY)`。顶部行为切换、reload 与页面 generation reset 时重建 baseline，避免跨结构比较。

- [ ] **Step 4：增加真实菜单与手势 UI RED/GREEN**

UI parser 增加四个字段，并新增：

```swift
func testInsideSafeAreaUsesTopInsetAndKeepsHeaderHeightDuringCollapse()
func testExtendsUnderTopSafeAreaUsesZeroTopInsetAndPreservesBarPosition()
```

inside 用真实上推手势进入 partial collapse，断言：

```swift
XCTAssertGreaterThan(state.containerTopInset, 1)
XCTAssertGreaterThan(state.headerCollapseTranslation, 1)
XCTAssertLessThan(state.maximumHeaderHeightDelta, 0.5)
```

通过齿轮菜单切换 extends 后断言 `containerTopInset < 0.5`，同一逻辑折叠位置的 bar current/presentation 差小于 `1`。随后完整运行既有 `.none/.container/.child` 顶部、plain bottom、真实 child bottom、切页/reload/cancel 菜单 UI，确认 owner 排他和业务 bounce 配置不变。

- [ ] **Step 5：运行 Example unit、聚焦 UI 与完整 UI**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerExampleTests test
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testInsideSafeAreaUsesTopInsetAndKeepsHeaderHeightDuringCollapse -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testExtendsUnderTopSafeAreaUsesZeroTopInsetAndPreservesBarPosition test
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleUITests test
git diff --check
```

预期：Header height delta 上限小于 `0.5pt`；inside/extends inset 与菜单选中态一致；全部既有真实 pan UI 通过。

- [ ] **Step 6：自审并提交 Task 6**

自审确认 probe 只用于 Example/测试、不进入 Framework public API；采样不逐帧写 os.Logger；菜单切换调用现有 public API，未加入测试专用生产分支。

```bash
git add Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "扩展示例 Header 几何验收"
```

---

### Task 7：完成全量回归并同步长期文档

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- Modify: `docs/superpowers/specs/2026-07-14-container-top-inset-fixed-header-presentation-design.md`
- Modify: `docs/superpowers/plans/2026-07-13-v0-5-scroll-coordination.md`
- Modify: `docs/superpowers/plans/2026-07-13-boundary-bounce-ownership.md`

- [ ] **Step 1：在修改完成状态文档前运行 Framework 全量**

```bash
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -resultBundlePath /private/tmp/AnchorPagerContainerTopInsetFrameworkFull-20260714.xcresult test
```

记录总数、失败、skip、error/warning/analyzer warning；任一非零不得继续把状态写成完成。

- [ ] **Step 2：运行 Example 全量与 generic Simulator build**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -resultBundlePath /private/tmp/AnchorPagerContainerTopInsetExampleFull-20260714.xcresult test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -resultBundlePath /private/tmp/AnchorPagerContainerTopInsetExampleBuild-20260714.xcresult build
```

使用 `xcrun xcresulttool get test-results summary --path <xcresult>` 记录真实统计；用 `xcodebuild` 输出与 xcresult issue summary 双重确认没有 warning/analyzer warning。

再单独捕获一次新 Header 真实手势 UI 的运行日志：

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testInsideSafeAreaUsesTopInsetAndKeepsHeaderHeightDuringCollapse test > /private/tmp/AnchorPagerContainerTopInsetRuntime-20260714.log 2>&1
rg -n "Unable to simultaneously satisfy constraints|UIViewAlertForUnsatisfiableConstraints" /private/tmp/AnchorPagerContainerTopInsetRuntime-20260714.log
```

第二条命令预期无输出并以未匹配状态结束；若有命中，专项验收失败，必须先新增约束回归测试并修复。

- [ ] **Step 3：同步行为文档但继续关闭 Ready 门禁**

文档必须明确：

- inside/extends 的 container top inset 分别为 obstruction/0，raw/logical 公式与 `H + D - I` range。
- Header 根 view 保持完整高度；canonical content surface 正常折叠，viewport 顶部 container bounce，Pageboy page surface plain bottom bounce。
- LayoutContext 使用最终可见坐标；child managed inset、delegate/bounce ownership 与 containment 均未变化。
- 已运行的精确命令、结果包、测试总数和当前生产 HEAD。
- Task 7 此时只能标为“实现与全量验收通过，待 fresh-pass”；v0.5/v0.6 Ready 仍关闭。

- [ ] **Step 4：运行静态门禁与文档一致性扫描**

```bash
rg -n "\.delegate\s*=|panGestureRecognizer\.delegate\s*=|isScrollEnabled\s*=|\.bounces\s*=|alwaysBounceVertical\s*=" Sources/AnchorPager
rg -n "Tabman|Pageboy" Sources/AnchorPager/Public
rg -n "synthetic|wrapper|业务.*transform|Header.*缩高" README.md docs AGENTS.md
rg -n -e 'TO''DO' -e 'TB''D' -e '待''定' -e '稍''后补' -e '暂''不处理' Sources Tests Examples README.md docs AGENTS.md
git diff --check
```

逐项人工解释允许的测试/文档命中；生产禁止项或状态矛盾必须修复并重跑受影响测试。

- [ ] **Step 5：自审并提交 Task 7**

```bash
git add AGENTS.md README.md docs/requirements.md docs/architecture.md docs/task-list.md docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md docs/superpowers/specs/2026-07-14-container-top-inset-fixed-header-presentation-design.md docs/superpowers/plans/2026-07-13-v0-5-scroll-coordination.md docs/superpowers/plans/2026-07-13-boundary-bounce-ownership.md
git commit -m "同步主容器 inset 文档与验收"
```

---

### Task 8：完成实现者自审和 Fresh-pass 复审

**Files:**
- Modify if findings require fixes: implementation/tests/docs touched by Tasks 1–7
- Modify after zero findings: `AGENTS.md`
- Modify after zero findings: `docs/task-list.md`
- Modify after zero findings: `docs/superpowers/specs/2026-07-14-container-top-inset-fixed-header-presentation-design.md`

- [ ] **Step 1：对完整实现范围做 fresh-pass 审查**

审查范围从设计基线到当前 HEAD：

```bash
git log --oneline 7885d9e..HEAD
git diff --stat 7885d9e...HEAD
git diff 7885d9e...HEAD -- Sources Tests Examples README.md docs AGENTS.md
```

逐项记录 Critical/Important/Minor：

1. public API 是否扩大、DocC 是否与行为一致、第三方类型是否泄漏。
2. Header/Pageboy containment、appearance、selection/reload generation、缓存与析构清理。
3. raw/logical 双向转换、`D == 0`、safe-area/bounds/top behavior/height mode 结构性迁移。
4. ScrollCoordinator 唯一 writer、OverscrollCoordinator owner-only、child delegate/pan/bounce 不写入。
5. normal/top/plain-bottom 三 surface 排他，LayoutContext 最终可见坐标。
6. 日志事件低频且有测试，Example probe/UI 覆盖完整，长期文档没有提前 Ready。

- [ ] **Step 2：任何发现都先补 RED，再做最小修复**

每个 Critical/Important/行为 Minor 必须：新增可复现测试 → 运行 RED → 最小修复 → 聚焦 GREEN → Framework/Example 相关全量复跑 → 中文单主题提交。不得只在文档中豁免，也不得用异步 delay、重复 layout、强制 reset 或扩大 public API 掩盖。

- [ ] **Step 3：用最终 HEAD 重跑全部门禁**

```bash
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -resultBundlePath /private/tmp/AnchorPagerContainerTopInsetFrameworkFinal-20260714.xcresult test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -resultBundlePath /private/tmp/AnchorPagerContainerTopInsetExampleFinal-20260714.xcresult test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -resultBundlePath /private/tmp/AnchorPagerContainerTopInsetExampleBuildFinal-20260714.xcresult build
git diff --check
```

- [ ] **Step 4：只在 Critical/Important 清零后恢复 Ready**

把最终生产 HEAD、测试统计、结果包、0 fail/skip/error/warning/analyzer warning 和复审结论写入 AGENTS、task-list 与专项设计状态。只有 fresh-pass Critical 0、Important 0 且所有门禁通过，才恢复 v0.5 Task 7 与 v0.6 Ready；否则明确保留未完成项，不进入 v0.7。

- [ ] **Step 5：提交最终复审状态**

```bash
git add AGENTS.md docs/task-list.md docs/superpowers/specs/2026-07-14-container-top-inset-fixed-header-presentation-design.md
git commit -m "完成固定 Header 专项复审"
```

---

## 计划自审门禁

- [x] 规格覆盖：逐条对照主容器 inset、raw/logical、固定 Header、三 surface、bar/paging、handoff、双边界、结构性迁移、measurement、containment、日志、Example/UI、文档和 Ready 门禁。
- [x] 占位扫描：`rg -n -e 'TO''DO' -e 'TB''D' -e '待''定' -e '稍''后' -e '类''似' -e '适''当' -e '视''情况' -e '<avail''able' docs/superpowers/plans/2026-07-14-container-top-inset-fixed-header-presentation.md` 无命中。
- [x] 类型一致性：全文统一使用 `AnchorPagerContainerScrollGeometry`、`logicalContentOffsetY`、`adjustedLogicalOffsetY`、`updateGeometry(_:targetLogicalOffset:)`、`contentPresentationView` 和四个 Example probe key。
- [x] 命令完整性：每个任务均包含 RED、GREEN、相邻回归、`git diff --check`、自审和中文提交。
- [x] 状态真实性：计划完成只代表可执行规格完成，不代表生产实现、测试或 v0.5/v0.6 Ready 已完成。

计划自审同时核对了仓库现有 `configuration.header.heightMode/topBehavior`、`LayoutEnvironment.obstruction.top`、HeaderHost/PagingHost 方法名和测试类名；已把 `.preserveVisualPosition` 澄清为保持 `E - collapseOffset` 与 bar/paging baseline。2026-07-14 本机可用 destination 已验证为 `iPhone 17 Pro / iOS 26.5`，工具链为 Xcode 26.6、Apple Swift 6.3.3；计划中的 Swift 6.2 表示 Package 最低技术基线。
