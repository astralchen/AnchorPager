# 纵向边界 Bounce 与顶部 Owner 路由 Implementation Plan

> **代理执行要求：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务实施本计划；所有步骤使用复选框跟踪。

**目标：** 在不修改业务 child 回弹配置、不接管业务 delegate 的前提下，修复 container/child 原生边界回弹，启用 `.none/.container/.child` 顶部路由，并用实际可见 presentation 完成 v0.5/v0.6 验收。

**架构：** `AnchorPagerScrollCoordinator` 继续是唯一 offset 写入者，只协调稳定区间并约束非 owner；`AnchorPagerOverscrollCoordinator` 只管理顶部 mode、边界 owner 和 begin/finish/cancel 状态，不直接写 UIKit。原生 owner 越界时停止 canonical clamp；container top 通过共享 viewport 呈现，plain bottom 保留 container 物理但只移动 Pageboy 页面 surface，child 越界按业务 scroll view 自身配置呈现。

**技术栈：** Swift 6.2、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、Tabman 4.0.1、Pageboy 5.0.2、XCTest/XCUITest、Xcode 26.3。

**当前状态：** 已完成；2026-07-13 历史 Tasks 1–7 与复审完成，2026-07-14 plain bottom 页面/chrome presentation 修订、完整重新验收和整分支 fresh-pass 复审已在生产代码 HEAD `c37e829` 收口，v0.5/v0.6 当前为 Ready。

> 2026-07-14 修订：本文后续 `topOverflow - bottomOverflow`、对称 viewport transform 和“整个 viewport 上移”代码/步骤只保留为历史实施记录，不得再次执行；最新 page/chrome 分层契约以同日专项设计和后续新计划为准。

## Global Constraints

- Package name、Library product 和 Module name 均为 `AnchorPager`。
- Minimum toolchain 为 Swift 6.2，Language mode 为 Swift 6，Minimum OS 为 iOS 14。
- 横向分页继续由 Tabman 4.0.1 与 Pageboy 5.0.2 执行；第三方类型不得进入 public API。
- AnchorPager 任何时刻都不得设置业务 child 的 `UIScrollView.delegate`、任一内建 pan delegate 或 `isScrollEnabled`。
- AnchorPager 不得保存、修改或恢复业务 child 的 `bounces` 与 `alwaysBounceVertical`。
- 无滚动页 original controller 继续直接由 Pageboy containment，scroll target 保持 nil，不创建 synthetic scroll wrapper。
- `AnchorPagerScrollCoordinator` 是 container/child offset 的唯一框架写入入口；`AnchorPagerOverscrollCoordinator` 只能返回策略和状态。
- Overscroll 只消费 Store committed current page/optional scroll target，不读取 pending provider、Host、Adapter 或 generation payload。
- LayoutEngine output、contentSize、managed inset、snapshot 与 collapse progress 只保存 canonical stable state；presentation overflow 不进入这些模型。
- 高频 pan/KVO/scroll callback 不逐帧输出普通日志，只记录 mode、owner、boundary phase 和异常状态变化。
- 每个任务遵循 RED → 最小 GREEN → 聚焦回归 → 自审 → 中文提交；v0.5 native boundary 验收先于 v0.6 mode Ready。

---

## 文件结构与职责

- `Sources/AnchorPager/Overscroll/AnchorPagerOverscrollCoordinator.swift`：新增；只管理边界 owner 路由、active 生命周期、阈值和 overscroll 状态日志。
- `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`：修改；稳定区间 handoff、边界 pass-through、非 owner guarded write、唯一 offset writer。
- `Sources/AnchorPager/Core/AnchorPagerScrollPositionResolver.swift`：修改；增加有限值校验后的未夹紧 canonical total 计算，稳定位置输出语义不变。
- `Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift`：修改；删除 bounce 租约，只保留 observation 与 pan target。
- `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`：修改；默认顶部模式改为 `.container`，DocC 明确 child 原生配置所有权。
- `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：历史修改；装配 mode、取消路径和当时的 container presentation，当前分层修订由 2026-07-14 新计划接管。
- `Tests/AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests.swift`：新增；纯 owner 矩阵、阈值、日志与 cancel 测试。
- `Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift`：修改；native pass-through、非 owner clamp、零范围方向和配置保持测试。
- `Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift`：修改；业务 bounce 配置不变与静态禁止项测试。
- `Tests/AnchorPagerTests/AnchorPagerScrollPositionResolverTests.swift`：修改；未夹紧 canonical total 有限值测试。
- `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：修改；顶部/底部 presentation、运行时 mode、reload/selection cancel 与几何恢复测试。
- `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`：修改；记录实际 container presentation 和 child overflow 的 current/max 距离。
- `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`：修改；mode 菜单、launch argument、探针和测试重置入口。
- `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`：修改；状态序列化和 mode 菜单测试。
- `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：修改；六类真实 coordinate drag 验收。
- `README.md`、`docs/requirements.md`、`docs/architecture.md`、`docs/task-list.md`、相关 specs/plans、`AGENTS.md`：修改；同步最终契约、状态与验收证据。

---

### Task 1：删除业务 Child Bounce 租约

**Files:**
- Modify: `Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift`
- Modify: `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift`

**Interfaces:**
- Consumes: 现有 `AnchorPagerChildScrollBinding` KVO/pan target 与 `AnchorPagerScrollCoordinator.bindCommittedChild(_:)`。
- Produces: 只读 binding；删除 `setAllowsNativeBounce(_:)`，业务 `bounces`/`alwaysBounceVertical` 全生命周期保持原值。

- [x] **Step 1：写业务 bounce 配置保持的失败测试**

在 `AnchorPagerChildScrollBindingTests` 新增：

```swift
func testBindingNeverChangesBusinessBounceConfiguration() {
    let scrollView = UIScrollView()
    scrollView.bounces = false
    scrollView.alwaysBounceVertical = true
    let binding = makeBinding(scrollView: scrollView)

    scrollView.contentOffset.y = 20
    scrollView.contentSize.height = 900

    XCTAssertFalse(scrollView.bounces)
    XCTAssertTrue(scrollView.alwaysBounceVertical)

    binding.invalidate()

    XCTAssertFalse(scrollView.bounces)
    XCTAssertTrue(scrollView.alwaysBounceVertical)
}

func testBindingSourceDoesNotStoreOrAssignBounceConfiguration() throws {
    let testURL = URL(fileURLWithPath: #filePath)
    let packageRoot = testURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = packageRoot.appendingPathComponent(
        "Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift"
    )
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let normalized = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")

    XCTAssertFalse(normalized.contains("originalBounces"))
    XCTAssertFalse(normalized.contains(".bounces ="))
    XCTAssertFalse(normalized.contains(".alwaysBounceVertical ="))
}
```

把 coordinator 中两个租约测试替换为：

```swift
func testBindingPanAndInvalidateKeepBusinessBounceConfiguration() {
    let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
    fixture.child.bounces = false
    fixture.child.alwaysBounceVertical = true
    fixture.coordinator.bindCommittedChild(nil)
    fixture.coordinator.bindCommittedChild(fixture.child)

    fixture.coordinator.handlePan(state: .began, translationY: 0)
    fixture.coordinator.handlePan(state: .changed, translationY: -150)
    fixture.coordinator.handlePan(state: .ended, translationY: -150)
    fixture.coordinator.invalidate()

    XCTAssertFalse(fixture.child.bounces)
    XCTAssertTrue(fixture.child.alwaysBounceVertical)
}
```

- [x] **Step 2：运行 RED**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerChildScrollBindingTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests test
```

Expected: `testBindingSourceDoesNotStoreOrAssignBounceConfiguration` 失败，源码仍包含 `originalBounces` 和 `.bounces =`。

- [x] **Step 3：删除租约实现**

`AnchorPagerChildScrollBinding` 删除：

```swift
private let originalBounces: Bool
```

删除 init 中：

```swift
self.originalBounces = scrollView.bounces
```

删除 `invalidate()` 中的 bounce 恢复，只保留 pan target 移除：

```swift
if let scrollView {
    scrollView.panGestureRecognizer.removeTarget(
        self,
        action: #selector(handlePan(_:))
    )
}
```

完整删除：

```swift
func setAllowsNativeBounce(_ allowsNativeBounce: Bool) {
    guard isValid, let scrollView else { return }
    scrollView.bounces = allowsNativeBounce && originalBounces
}
```

`AnchorPagerScrollCoordinator` 删除 `isContainerPanActive`、所有 `setAllowsNativeBounce` 调用、`updateChildBounceLease()` 及 invalidate 中对应复位。pan 开始/结束只保留 canonical 手势状态：

```swift
case .began:
    gestureStartTotal = currentCanonicalTotal()
    gestureStartTranslationY = translationY
case .ended, .cancelled, .failed:
    gestureStartTotal = nil
    settleStableOffsets()
```

- [x] **Step 4：运行 GREEN 与静态门禁**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerChildScrollBindingTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests test
rg -n 'originalBounces|setAllowsNativeBounce|\.bounces\s*=|\.alwaysBounceVertical\s*=' \
  Sources/AnchorPager/Children Sources/AnchorPager/Core
```

Expected: 聚焦测试全部通过；`rg` 在 Binding/ScrollCoordinator 中无匹配。

- [x] **Step 5：自审并提交**

确认 observation/pan target cleanup、delegate identity、MainActor 和资源日志不变；随后：

```bash
git diff --check
git add Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift \
  Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift \
  Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift \
  Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift
git commit -m "移除业务滚动回弹租约"
```

---

### Task 2：建立纯 Overscroll Owner 策略状态机

**Files:**
- Create: `Sources/AnchorPager/Overscroll/AnchorPagerOverscrollCoordinator.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AnchorPagerTopOverscrollHandlingMode`、当前页是否存在 committed child scroll target。
- Produces: `Boundary`、`Owner`、`ActiveOwner`、`Route`、`begin(boundary:hasChild:)`、`observeActiveOverflow(_:)`、`endInteraction()`、`updateTopMode(_:)`、`cancel()`。

- [x] **Step 1：写 owner 矩阵与生命周期 RED 测试**

新增测试文件，核心测试固定为：

```swift
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerOverscrollCoordinatorTests: XCTestCase {
    func testTopOwnerMatrix() {
        XCTAssertEqual(route(mode: .none, hasChild: true), .clampStableBoundary(.top))
        XCTAssertEqual(route(mode: .container, hasChild: true), .passThrough(.init(boundary: .top, owner: .container)))
        XCTAssertEqual(route(mode: .child, hasChild: true), .passThrough(.init(boundary: .top, owner: .child)))
        XCTAssertEqual(route(mode: .none, hasChild: false), .clampStableBoundary(.top))
        XCTAssertEqual(route(mode: .container, hasChild: false), .passThrough(.init(boundary: .top, owner: .container)))
        XCTAssertEqual(route(mode: .child, hasChild: false), .clampStableBoundary(.top))
    }

    func testBottomOwnerDependsOnlyOnChildAvailability() {
        let child = AnchorPagerOverscrollCoordinator(topMode: .none)
        XCTAssertEqual(
            child.begin(boundary: .bottom, hasChild: true),
            .passThrough(.init(boundary: .bottom, owner: .child))
        )
        let plain = AnchorPagerOverscrollCoordinator(topMode: .child)
        XCTAssertEqual(
            plain.begin(boundary: .bottom, hasChild: false),
            .passThrough(.init(boundary: .bottom, owner: .container))
        )
    }

    func testOwnerFinishesOnlyAfterVisibleOverflowReturnsToStableRange() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        _ = coordinator.begin(boundary: .top, hasChild: true)

        XCTAssertEqual(coordinator.observeActiveOverflow(0), .active)
        XCTAssertEqual(coordinator.observeActiveOverflow(8), .active)
        XCTAssertEqual(coordinator.observeActiveOverflow(0.4), .finished)
        XCTAssertNil(coordinator.activeOwner)
    }

    func testChildWithoutTargetLogsUnavailableOnlyOncePerInteraction() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .child)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        _ = coordinator.begin(boundary: .top, hasChild: false)
        _ = coordinator.begin(boundary: .top, hasChild: false)

        XCTAssertEqual(events.filter { $0.event == "overscroll.owner.unavailable" }.count, 1)
    }

    func testModeChangeCancelsActiveOwner() {
        let coordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        _ = coordinator.begin(boundary: .top, hasChild: true)

        coordinator.updateTopMode(.child)

        XCTAssertNil(coordinator.activeOwner)
        XCTAssertEqual(coordinator.topMode, .child)
    }

    private func route(
        mode: AnchorPagerTopOverscrollHandlingMode,
        hasChild: Bool
    ) -> AnchorPagerOverscrollCoordinator.Route {
        AnchorPagerOverscrollCoordinator(topMode: mode)
            .begin(boundary: .top, hasChild: hasChild)
    }
}
```

- [x] **Step 2：运行 RED**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests test
```

Expected: 编译失败，`AnchorPagerOverscrollCoordinator` 不存在。

- [x] **Step 3：实现纯策略状态机**

新增文件，使用以下完整接口和状态规则：

```swift
import CoreGraphics

@MainActor
final class AnchorPagerOverscrollCoordinator {
    enum Boundary: Equatable {
        case top
        case bottom
    }

    enum Owner: Equatable {
        case container
        case child
    }

    struct ActiveOwner: Equatable {
        let boundary: Boundary
        let owner: Owner
    }

    enum Route: Equatable {
        case clampStableBoundary(Boundary)
        case passThrough(ActiveOwner)
    }

    enum ObservationResult: Equatable {
        case inactive
        case active
        case finished
    }

    private(set) var topMode: AnchorPagerTopOverscrollHandlingMode
    private(set) var activeOwner: ActiveOwner?
    private var activeHasPresentedOverflow = false
    private var requestedBoundary: Boundary?
    private var didLogUnavailable = false
    private let epsilon: CGFloat = 0.5

    init(topMode: AnchorPagerTopOverscrollHandlingMode) {
        self.topMode = topMode
    }

    func updateTopMode(_ mode: AnchorPagerTopOverscrollHandlingMode) {
        guard topMode != mode else { return }
        cancel()
        topMode = mode
        AnchorPagerLogger.log(.info, category: .overscroll, event: "overscroll.mode.changed")
    }

    func begin(boundary: Boundary, hasChild: Bool) -> Route {
        if let activeOwner {
            return .passThrough(activeOwner)
        }
        if requestedBoundary != boundary {
            requestedBoundary = boundary
            AnchorPagerLogger.log(
                .info,
                category: .overscroll,
                event: boundary == .top
                    ? "overscroll.boundary.top"
                    : "overscroll.boundary.bottom"
            )
        }

        let owner: Owner?
        switch boundary {
        case .top:
            switch topMode {
            case .none:
                owner = nil
            case .container:
                owner = .container
            case .child:
                owner = hasChild ? .child : nil
                if !hasChild, !didLogUnavailable {
                    didLogUnavailable = true
                    AnchorPagerLogger.log(
                        .info,
                        category: .overscroll,
                        event: "overscroll.owner.unavailable"
                    )
                }
            }
        case .bottom:
            owner = hasChild ? .child : .container
        }

        guard let owner else {
            return .clampStableBoundary(boundary)
        }
        let active = ActiveOwner(boundary: boundary, owner: owner)
        activeOwner = active
        activeHasPresentedOverflow = false
        AnchorPagerLogger.log(
            .info,
            category: .overscroll,
            event: owner == .container
                ? "overscroll.owner.container.begin"
                : "overscroll.owner.child.begin"
        )
        return .passThrough(active)
    }

    func observeActiveOverflow(_ distance: CGFloat) -> ObservationResult {
        guard activeOwner != nil else { return .inactive }
        let overflow = distance.isFinite ? max(0, distance) : 0
        if overflow > epsilon {
            activeHasPresentedOverflow = true
            return .active
        }
        guard activeHasPresentedOverflow else { return .active }
        finish()
        return .finished
    }

    func endInteraction() -> Bool {
        requestedBoundary = nil
        didLogUnavailable = false
        guard activeOwner != nil, !activeHasPresentedOverflow else { return false }
        finish()
        return true
    }

    func reachedStableRange() {
        guard activeOwner == nil else { return }
        requestedBoundary = nil
        didLogUnavailable = false
    }

    @discardableResult
    func cancel() -> Bool {
        requestedBoundary = nil
        didLogUnavailable = false
        activeHasPresentedOverflow = false
        guard activeOwner != nil else { return false }
        activeOwner = nil
        AnchorPagerLogger.log(.info, category: .overscroll, event: "overscroll.owner.cancel")
        return true
    }

    private func finish() {
        activeOwner = nil
        activeHasPresentedOverflow = false
        requestedBoundary = nil
        didLogUnavailable = false
        AnchorPagerLogger.log(.info, category: .overscroll, event: "overscroll.owner.finish")
    }
}
```

- [x] **Step 4：运行 GREEN 与日志回归**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
```

Expected: 全部通过；重复 begin 不产生逐帧重复 boundary/unavailable 日志。

- [x] **Step 5：自审并提交**

确认新 coordinator 不 import UIKit、不持有 scroll view/page/provider、不写 offset。随后：

```bash
git diff --check
git add Sources/AnchorPager/Overscroll/AnchorPagerOverscrollCoordinator.swift \
  Tests/AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests.swift
git commit -m "建立纵向边界所有权策略"
```

---

### Task 3：分离 Stable Range 与 Native Boundary Pass-through

**Files:**
- Modify: `Sources/AnchorPager/Core/AnchorPagerScrollPositionResolver.swift`
- Modify: `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerScrollPositionResolverTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 2 的 `AnchorPagerOverscrollCoordinator`。
- Produces: `AnchorPagerScrollPositionResolver.unclampedDesiredTotal(_:) -> CGFloat?`；ScrollCoordinator 的 top/bottom owner pass-through、非 owner guarded clamp、`cancelBoundaryHandling()`。

- [x] **Step 1：写未夹紧 total 和四类边界 RED 测试**

Resolver 新增：

```swift
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
```

Coordinator 新增：

```swift
func testDefaultContainerTopPassThroughKeepsNegativeContainerAndPinsChild() {
    let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
    fixture.container.contentOffset.y = -24
    fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

    fixture.coordinator.containerDidScroll()

    XCTAssertEqual(fixture.container.contentOffset.y, -24, accuracy: 0.001)
    XCTAssertEqual(fixture.child.contentOffset.y, -fixture.child.contentInset.top, accuracy: 0.001)
}

func testPlainBottomPassThroughKeepsContainerOverflow() {
    let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
    fixture.coordinator.bindCommittedChild(nil)
    fixture.container.contentOffset.y = 124

    fixture.coordinator.containerDidScroll()

    XCTAssertEqual(fixture.container.contentOffset.y, 124, accuracy: 0.001)
}

func testRealChildBottomPassThroughKeepsChildOverflowAndPinsContainer() {
    let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
    fixture.container.contentOffset.y = 112
    fixture.child.contentOffset.y = -fixture.child.contentInset.top + 524

    fixture.coordinator.handleChildChangeForTesting(
        token: fixture.coordinator.bindingTokenForTesting
    )

    XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
    XCTAssertEqual(
        fixture.child.contentOffset.y + fixture.child.contentInset.top,
        524,
        accuracy: 0.001
    )
}

func testActiveNativeBoundaryIsNotClampedByGeometryRefresh() {
    let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
    fixture.container.contentOffset.y = -24
    fixture.coordinator.containerDidScroll()

    fixture.coordinator.updateGeometry(collapsibleDistance: 100)

    XCTAssertEqual(fixture.container.contentOffset.y, -24, accuracy: 0.001)
}
```

- [x] **Step 2：运行 RED**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerScrollPositionResolverTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests test
```

Expected: resolver API 缺失；plain bottom 和 child bottom 被现有 settle clamp。

- [x] **Step 3：增加未夹紧 canonical total**

在 resolver 增加：

```swift
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
```

把 `resolve(_:)` 的 desired total 改为复用该方法并继续夹紧稳定区间：

```swift
guard let rawDesiredTotal = unclampedDesiredTotal(input) else {
    return input.fallback
}
let desiredTotal = min(
    max(0, rawDesiredTotal),
    collapsedOffset + maximumChildDistance
)
```

- [x] **Step 4：接入边界策略但暂时固定顶部 `.container`**

ScrollCoordinator 新增 property，并在现有 initializer 中固定 v0.5 临时 `.container`：

```swift
private let overscrollCoordinator: AnchorPagerOverscrollCoordinator
private var boundaryEpsilon: CGFloat { 0.5 }

var activeBoundaryForTesting: AnchorPagerOverscrollCoordinator.ActiveOwner? {
    overscrollCoordinator.activeOwner
}

func cancelBoundaryHandling() {
    let didCancel = overscrollCoordinator.cancel()
    if didCancel {
        apply(currentStablePosition())
    }
}
```

```swift
init(containerScrollView: AnchorPagerContainerScrollView) {
    self.containerScrollView = containerScrollView
    self.overscrollCoordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
    containerScrollView.panGestureRecognizer.addTarget(
        self,
        action: #selector(handleContainerPan(_:))
    )
}
```

`handlePan(.changed)` 先判断未夹紧 total：

```swift
let input = AnchorPagerScrollPositionResolver.Input(
    gestureStartTotal: gestureStartTotal,
    gestureStartTranslationY: gestureStartTranslationY,
    currentTranslationY: translationY,
    containerCollapsedOffset: collapsibleDistance,
    childMaximumDistance: childMaximumDistance,
    fallback: currentStablePosition()
)
guard let desiredTotal = AnchorPagerScrollPositionResolver
    .unclampedDesiredTotal(input) else {
    apply(AnchorPagerScrollPositionResolver.resolve(input))
    return
}
let maximumStableTotal = collapsibleDistance + childMaximumDistance
if desiredTotal < -boundaryEpsilon {
    beginBoundary(.top)
} else if desiredTotal > maximumStableTotal + boundaryEpsilon {
    beginBoundary(.bottom)
} else if overscrollCoordinator.activeOwner == nil {
    overscrollCoordinator.reachedStableRange()
    apply(AnchorPagerScrollPositionResolver.resolve(input))
} else {
    enforceAndObserveActiveBoundary()
}
```

新增完整边界辅助方法：

```swift
func beginBoundary(_ boundary: AnchorPagerOverscrollCoordinator.Boundary) {
    let route = overscrollCoordinator.begin(
        boundary: boundary,
        hasChild: committedChildScrollView != nil
    )
    switch route {
    case let .clampStableBoundary(boundary):
        switch boundary {
        case .top:
            apply(.init(containerOffset: 0, childDistance: 0))
        case .bottom:
            apply(.init(
                containerOffset: collapsibleDistance,
                childDistance: childMaximumDistance
            ))
        }
    case .passThrough:
        enforceAndObserveActiveBoundary()
    }
}

func enforceAndObserveActiveBoundary() {
    guard let active = overscrollCoordinator.activeOwner else { return }
    switch (active.boundary, active.owner) {
    case (.top, .container):
        pinChildToTop()
    case (.top, .child):
        writeContainerBoundary(0)
    case (.bottom, .child):
        writeContainerBoundary(collapsibleDistance)
    case (.bottom, .container):
        break
    }

    let result = overscrollCoordinator.observeActiveOverflow(
        activeOverflowDistance(active)
    )
    if result == .finished {
        settleStableOffsets()
    }
}

func activeOverflowDistance(
    _ active: AnchorPagerOverscrollCoordinator.ActiveOwner
) -> CGFloat {
    switch (active.boundary, active.owner) {
    case (.top, .container):
        return max(0, -containerScrollView.contentOffset.y)
    case (.top, .child):
        let distance = (committedChildScrollView?.contentOffset.y ?? childTopOffset)
            - childTopOffset
        return max(0, -distance)
    case (.bottom, .child):
        let distance = (committedChildScrollView?.contentOffset.y ?? childTopOffset)
            - childTopOffset
        return max(0, distance - childMaximumDistance)
    case (.bottom, .container):
        return max(0, containerScrollView.contentOffset.y - collapsibleDistance)
    }
}

func writeContainerBoundary(_ target: CGFloat) {
    guard abs(containerScrollView.contentOffset.y - target) > epsilon else { return }
    isApplyingGuardedOffsets = true
    containerScrollView.contentOffset.y = target
    isApplyingGuardedOffsets = false
    AnchorPagerLogger.log(.debug, category: .scroll, event: "scroll.offset.guard.apply")
}
```

`containerDidScroll()` 与 `childDidChange(token:)` 在 stable settle 前调用以下统一观察入口：

```swift
func handleObservedBoundaryIfNeeded() -> Bool {
    let childDistance = committedChildScrollView.map {
        $0.contentOffset.y + $0.contentInset.top
    }
    if overscrollCoordinator.activeOwner == nil {
        if containerScrollView.contentOffset.y < -boundaryEpsilon
            || (childDistance ?? 0) < -boundaryEpsilon {
            beginBoundary(.top)
        } else if let childDistance,
                  childDistance > childMaximumDistance + boundaryEpsilon {
            beginBoundary(.bottom)
        } else if committedChildScrollView == nil,
                  containerScrollView.contentOffset.y
                    > collapsibleDistance + boundaryEpsilon {
            beginBoundary(.bottom)
        }
    }
    guard overscrollCoordinator.activeOwner != nil else { return false }
    enforceAndObserveActiveBoundary()
    return true
}
```

`containerDidScroll()` 在 guarded reentry 检查后先执行：

```swift
if handleObservedBoundaryIfNeeded() {
    return
}
settleStableOffsets()
```

`childDidChange(token:)` 在 token/guard 检查后先执行同一方法；返回 `true` 时不进入原 stable settle。`settleStableOffsets()` 开头增加 active 检查，并删除旧的 `containerScrollView.contentOffset.y < 0` 特判，使取消后的 settle 可以真正回到 stable range：

```swift
if overscrollCoordinator.activeOwner != nil {
    enforceAndObserveActiveBoundary()
    return
}
```

pan 结束时：

```swift
gestureStartTotal = nil
if overscrollCoordinator.endInteraction() {
    settleStableOffsets()
} else if overscrollCoordinator.activeOwner == nil {
    settleStableOffsets()
}
```

`bindCommittedChild`、`invalidate` 和 collapsible distance 真实变化时先 `overscrollCoordinator.cancel()`；相同 geometry 的滚动热路径不得 cancel。`updateGeometry` 固定为先比较规范化后的距离，变化时 cancel，写入新值后 stable settle：

```swift
func updateGeometry(collapsibleDistance: CGFloat) {
    let next = max(0, collapsibleDistance.isFinite ? collapsibleDistance : 0)
    if abs(self.collapsibleDistance - next) > epsilon {
        overscrollCoordinator.cancel()
    }
    self.collapsibleDistance = next
    settleStableOffsets()
}
```

- [x] **Step 5：运行 GREEN、组合回归与属性静态扫描**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerScrollPositionResolverTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerChildScrollBindingTests test
rg -n 'scrollView\.delegate\s*=|panGestureRecognizer\.delegate\s*=|\.bounces\s*=|\.alwaysBounceVertical\s*=|\.isScrollEnabled\s*=' \
  Sources/AnchorPager/Core Sources/AnchorPager/Children Sources/AnchorPager/Overscroll
```

Expected: 聚焦测试全部通过；扫描不命中业务 child 写入路径。

- [x] **Step 6：自审并提交 v0.5 native boundary 核心**

重点确认 active owner 时 geometry/KVO/delegate 不 clamp、zero range 按拖动方向只进入一个边界、ScrollCoordinator 仍是唯一 writer。随后：

```bash
git diff --check
git add Sources/AnchorPager/Core/AnchorPagerScrollPositionResolver.swift \
  Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift \
  Tests/AnchorPagerTests/AnchorPagerScrollPositionResolverTests.swift \
  Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift
git commit -m "分离稳定滚动与原生边界回弹"
```

---

### Task 4：实现对称 Container Presentation 并完成 v0.5 可见验收

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: Task 3 默认 container top、plain bottom native pass-through。
- Produces: `containerOverscrollTranslationY(for:)` 对称 presentation；Example current/max 可见距离探针；默认 container 的真实 drag 证据。

- [x] **Step 1：写 UIKit 对称几何 RED 测试**

在 ViewController tests 新增：

```swift
func testPlainBottomOverflowTranslatesViewportUpWithoutChangingCanonicalRange() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 100, min: 0)
    let pager = AnchorPagerViewController(configuration: configuration)
    let delegate = StubDelegate()
    pager.delegate = delegate
    pager.dataSource = StubDataSource(
        count: 1,
        viewControllers: [UIViewController()],
        headerContent: .view(FixedFittingView(height: 100))
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = pager
    window.makeKeyAndVisible()
    pager.reloadData()
    window.layoutIfNeeded()
    let initialContentSize = pager.verticalScrollView.contentSize
    pager.verticalScrollView.contentOffset.y = 100
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
    window.layoutIfNeeded()
    let collapsedContext = try XCTUnwrap(delegate.layoutContexts.last)

    pager.verticalScrollView.contentOffset.y = 124
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
    window.layoutIfNeeded()

    let context = try XCTUnwrap(delegate.layoutContexts.last)
    XCTAssertEqual(
        context.headerFrame.minY,
        collapsedContext.headerFrame.minY - 24,
        accuracy: 0.5
    )
    XCTAssertEqual(pager.verticalScrollView.contentSize, initialContentSize)
    XCTAssertEqual(try XCTUnwrap(delegate.collapseProgresses.last), 1, accuracy: 0.001)
}
```

保留并扩展已有顶部负 offset 测试，断言回弹恢复后 transform、context 和物理底边回到 canonical 值。

- [x] **Step 2：运行 RED**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testPlainBottomOverflowTranslatesViewportUpWithoutChangingCanonicalRange test
```

Expected: Header/context 没有向上平移 24 pt；当前实现只处理顶部负 offset。

- [x] **Step 3：实现对称 translation**

把 `applyLayoutOutput` 改为：

```swift
let translationY = containerOverscrollTranslationY(for: output)
viewportView.transform = CGAffineTransform(translationX: 0, y: translationY)
```

用以下方法替换旧 `overscrollTranslationY`：

```swift
private func containerOverscrollTranslationY(
    for output: AnchorPagerLayoutEngine.Output
) -> CGFloat {
    let offset = verticalScrollView.contentOffset.y
    let collapsed = output.resolvedHeaderHeight.collapsibleDistance
    let topOverflow = max(0, -offset)
    let bottomOverflow = max(0, offset - collapsed)
    return topOverflow - bottomOverflow
}
```

LayoutEngine input、scroll range、managed inset 和 collapse progress 不使用该 translation。

- [x] **Step 4：把 Example 探针从 boolean 改为 current/max 距离**

`ExampleScrollCoordinationState` 使用以下字段和序列化键：

```swift
struct ExampleScrollCoordinationState: Equatable {
    var page: String
    var hasScrollTarget: Bool
    var topMode: String
    var collapseProgress: CGFloat
    var childDistance: CGFloat
    var containerPresentation: CGFloat
    var maximumContainerTopPresentation: CGFloat
    var maximumContainerBottomPresentation: CGFloat
    var childTopOverflow: CGFloat
    var maximumChildTopOverflow: CGFloat
    var childBottomOverflow: CGFloat
    var maximumChildBottomOverflow: CGFloat

    var accessibilityValue: String {
        [
            "page=\(page)",
            "hasScrollTarget=\(hasScrollTarget ? 1 : 0)",
            "mode=\(topMode)",
            "collapse=\(formatted(collapseProgress))",
            "distance=\(formatted(childDistance))",
            "containerCurrent=\(formatted(containerPresentation))",
            "containerTopMax=\(formatted(maximumContainerTopPresentation))",
            "containerBottomMax=\(formatted(maximumContainerBottomPresentation))",
            "childTopCurrent=\(formatted(childTopOverflow))",
            "childTopMax=\(formatted(maximumChildTopOverflow))",
            "childBottomCurrent=\(formatted(childBottomOverflow))",
            "childBottomMax=\(formatted(maximumChildBottomOverflow))"
        ].joined(separator: ";")
    }

    mutating func resetPresentationMetrics() {
        containerPresentation = 0
        maximumContainerTopPresentation = 0
        maximumContainerBottomPresentation = 0
        childTopOverflow = 0
        maximumChildTopOverflow = 0
        childBottomOverflow = 0
        maximumChildBottomOverflow = 0
    }
}
```

Example controller 增加 canonical context 基线：

```swift
private var expandedHeaderBaselineY: CGFloat?
private var collapsedHeaderBaselineY: CGFloat?

private func recordContainerPresentation(_ context: AnchorPagerLayoutContext) {
    let scrollView = pagerViewController.verticalScrollView
    let maximumOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
    let topOverflow = max(0, -scrollView.contentOffset.y)
    let bottomOverflow = max(0, scrollView.contentOffset.y - maximumOffset)
    let isStable = topOverflow <= 0.5 && bottomOverflow <= 0.5

    if isStable {
        scrollCoordinationState.containerPresentation = 0
        if scrollCoordinationState.collapseProgress <= 0.01 {
            expandedHeaderBaselineY = context.headerFrame.minY
        }
        if scrollCoordinationState.collapseProgress >= 0.99 {
            collapsedHeaderBaselineY = context.headerFrame.minY
        }
    } else if topOverflow > 0.5, let baseline = expandedHeaderBaselineY {
        let presentation = context.headerFrame.minY - baseline
        scrollCoordinationState.containerPresentation = presentation
        scrollCoordinationState.maximumContainerTopPresentation = max(
            scrollCoordinationState.maximumContainerTopPresentation,
            presentation
        )
    } else if bottomOverflow > 0.5, let baseline = collapsedHeaderBaselineY {
        let presentation = context.headerFrame.minY - baseline
        scrollCoordinationState.containerPresentation = presentation
        scrollCoordinationState.maximumContainerBottomPresentation = max(
            scrollCoordinationState.maximumContainerBottomPresentation,
            -presentation
        )
    }
    updateScrollCoordinationStateControl()
}
```

Delegate 固定调用：

```swift
func pagerViewController(
    _ pagerViewController: AnchorPagerViewController,
    didUpdateLayout context: AnchorPagerLayoutContext
) {
    recordContainerPresentation(context)
}
```

业务页面自己的 `scrollViewDidScroll` 使用以下计算，并把 current/max 通过 closure 回报：

```swift
let distance = scrollView.contentOffset.y + scrollView.contentInset.top
let maximumDistance = max(
    0,
    scrollView.contentSize.height
        + scrollView.contentInset.top
        + scrollView.contentInset.bottom
        - scrollView.bounds.height
)
let topOverflow = max(0, -distance)
let bottomOverflow = max(0, distance - maximumDistance)
onScrollStateChange(pageIdentifier, distance, topOverflow, bottomOverflow)
```

Example controller 收到回调后固定更新：

```swift
scrollCoordinationState.childDistance = max(0, distance)
scrollCoordinationState.childTopOverflow = topOverflow
scrollCoordinationState.maximumChildTopOverflow = max(
    scrollCoordinationState.maximumChildTopOverflow,
    topOverflow
)
scrollCoordinationState.childBottomOverflow = bottomOverflow
scrollCoordinationState.maximumChildBottomOverflow = max(
    scrollCoordinationState.maximumChildBottomOverflow,
    bottomOverflow
)
```

状态按钮增加 `touchUpInside` target，只调用 `resetPresentationMetrics()` 并刷新 accessibility value，不改变框架状态。

- [x] **Step 5：更新默认 container 真实 UI 测试**

替换旧 boolean bounce 测试，新增：

```swift
func testExpandedTopPullShowsVisibleContainerPresentationAndSettles() throws {
    let app = launchLongPage()
    let probe = scrollCoordinationStateProbe(in: app)

    drag(in: app, from: 0.30, to: 0.72)

    let state = try XCTUnwrap(waitForScrollState(from: probe) {
        $0.containerTopMax > 1 && abs($0.containerCurrent) < 0.5
    })
    XCTAssertEqual(state.mode, "container")
    XCTAssertEqual(state.distance, 0, accuracy: 0.5)
}

func testPlainBottomPullShowsVisibleContainerPresentationAndSettles() throws {
    let app = launchPlainPage()
    let probe = scrollCoordinationStateProbe(in: app)
    drag(in: app, from: 0.76, to: 0.24)
    XCTAssertNotNil(waitForScrollState(from: probe) { $0.collapse >= 0.99 })
    probe.tap()

    drag(in: app, from: 0.76, to: 0.24)

    let state = try XCTUnwrap(waitForScrollState(from: probe) {
        $0.containerBottomMax > 1 && abs($0.containerCurrent) < 0.5
    })
    XCTAssertFalse(state.hasScrollTarget)
    XCTAssertEqual(state.distance, 0, accuracy: 0.5)
}
```

`ScrollCoordinationState` parser 同步解析全部新键。旧 `childBounce == false` 断言删除，因为该值来自业务 delegate 的瞬时 callback，不再代表可见 owner。

- [x] **Step 6：运行 v0.5 framework/Example 聚焦 GREEN**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testExpandedTopPullShowsVisibleContainerPresentationAndSettles \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainBottomPullShowsVisibleContainerPresentationAndSettles test
```

Expected: framework 聚焦集和两个真实 drag 均通过；探针证明 max presentation > 1 pt 且回弹后 current < 0.5 pt。

- [x] **Step 7：自审并提交 v0.5 可见 bounce 修复**

确认 plain root 仍到物理底边、presentation 不进入 contentSize/range/snapshot、UI test 不再使用瞬时 boolean。随后：

```bash
git diff --check
git add Sources/AnchorPager/Public/AnchorPagerViewController.swift \
  Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift \
  Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift \
  Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift \
  Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift \
  Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "修复纵向边界可见回弹"
```

---

### Task 5：正式启用三种顶部模式与同步取消路径

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`
- Modify: `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 2/3 的 route 与 pass-through。
- Produces: 默认 `.container`；`updateTopOverscrollHandlingMode(_:)`；configuration/reload/selection/layout/rotation 同步 cancel。

- [x] **Step 1：写 mode integration 与属性保持 RED 测试**

新增 coordinator 测试：

```swift
func testNoneModeClampsContainerAndChildAtExpandedBoundary() {
    let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
    fixture.coordinator.updateTopOverscrollHandlingMode(.none)
    fixture.container.contentOffset.y = -20
    fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

    fixture.coordinator.containerDidScroll()

    XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
    XCTAssertEqual(fixture.child.contentOffset.y, -fixture.child.contentInset.top, accuracy: 0.001)
}

func testChildModeKeepsContainerExpandedAndPassesThroughChildTop() {
    let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
    fixture.coordinator.updateTopOverscrollHandlingMode(.child)
    fixture.container.contentOffset.y = -20
    fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12

    fixture.coordinator.handleChildChangeForTesting(
        token: fixture.coordinator.bindingTokenForTesting
    )

    XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
    XCTAssertEqual(fixture.child.contentOffset.y, -fixture.child.contentInset.top - 12, accuracy: 0.001)
}

func testChildModeWithNilTargetClampsWithoutFallback() {
    let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
    fixture.coordinator.bindCommittedChild(nil)
    fixture.coordinator.updateTopOverscrollHandlingMode(.child)
    fixture.container.contentOffset.y = -20

    fixture.coordinator.containerDidScroll()

    XCTAssertEqual(fixture.container.contentOffset.y, 0, accuracy: 0.001)
    XCTAssertNil(fixture.coordinator.activeBoundaryForTesting)
}

func testModesNeverChangeBusinessBounceConfiguration() {
    let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 0)
    fixture.child.bounces = false
    fixture.child.alwaysBounceVertical = false

    for mode in [
        AnchorPagerTopOverscrollHandlingMode.none,
        .container,
        .child
    ] {
        fixture.coordinator.updateTopOverscrollHandlingMode(mode)
        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 40)
        fixture.coordinator.handlePan(state: .cancelled, translationY: 40)
        XCTAssertFalse(fixture.child.bounces)
        XCTAssertFalse(fixture.child.alwaysBounceVertical)
    }
}
```

ViewController 默认测试把期望从 `.none` 改为 `.container`，再增加运行时 mode 更新取消 active presentation 的测试。

```swift
func testRuntimeTopModeChangeCancelsContainerPresentationAndKeepsChildConfiguration() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 100, min: 0)
    let child = ScrollChildViewController()
    child.loadViewIfNeeded()
    child.scrollView.bounces = false
    child.scrollView.alwaysBounceVertical = true
    let pager = AnchorPagerViewController(configuration: configuration)
    pager.dataSource = StubDataSource(
        count: 1,
        viewControllers: [child],
        headerContent: .view(FixedFittingView(height: 100))
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = pager
    window.makeKeyAndVisible()
    pager.reloadData()
    window.layoutIfNeeded()
    pager.verticalScrollView.contentOffset.y = -20
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)

    pager.configuration.topOverscrollHandlingMode = .child
    window.layoutIfNeeded()

    XCTAssertEqual(pager.verticalScrollView.contentOffset.y, 0, accuracy: 0.5)
    XCTAssertFalse(child.scrollView.bounces)
    XCTAssertTrue(child.scrollView.alwaysBounceVertical)
}
```

- [x] **Step 2：运行 RED**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testConfigurationDefaultsMatchV01Baseline test
```

Expected: update mode API 缺失；默认仍为 `.none`。

- [x] **Step 3：启用 public mode 与 coordinator 更新入口**

Configuration 默认参数改为：

```swift
topOverscrollHandlingMode: AnchorPagerTopOverscrollHandlingMode = .container
```

`.child` DocC 增加：

```swift
/// 由当前真实 child 滚动视图按自身原生配置处理顶部 overscroll。
///
/// AnchorPager 不修改 child 的 `bounces` 或 `alwaysBounceVertical`；
/// nil scroll target 时该 owner 不可用，也不会回退到 container。
case child
```

ScrollCoordinator initializer 与更新入口固定为：

```swift
init(
    containerScrollView: AnchorPagerContainerScrollView,
    topOverscrollHandlingMode: AnchorPagerTopOverscrollHandlingMode = .container
) {
    self.containerScrollView = containerScrollView
    self.overscrollCoordinator = AnchorPagerOverscrollCoordinator(
        topMode: topOverscrollHandlingMode
    )
    containerScrollView.panGestureRecognizer.addTarget(
        self,
        action: #selector(handleContainerPan(_:))
    )
}

func updateTopOverscrollHandlingMode(_ mode: AnchorPagerTopOverscrollHandlingMode) {
    let hadActiveOwner = overscrollCoordinator.activeOwner != nil
    overscrollCoordinator.updateTopMode(mode)
    if hadActiveOwner {
        settleStableOffsets()
    }
}
```

- [x] **Step 4：装配 configuration 与同步取消路径**

ViewController `configuration.didSet` 增加：

```swift
scrollCoordinator?.updateTopOverscrollHandlingMode(
    configuration.topOverscrollHandlingMode
)
```

安装时传入当前 mode：

```swift
scrollCoordinator = AnchorPagerScrollCoordinator(
    containerScrollView: container,
    topOverscrollHandlingMode: configuration.topOverscrollHandlingMode
)
```

以下入口在改变结构/committed owner 前同步调用：

```swift
scrollCoordinator?.cancelBoundaryHandling()
```

固定入口为：`reloadData()` 开始、`reloadHeaderLayout` 开始、`pagingHost(willPerformReloadRequest:)` matching request、`pagingHost(willSelect:)`、`viewWillTransition(to:with:)`。selection complete/cancel 和 reload terminal 再按 committed Store 绑定，不读取 pending provider。

- [x] **Step 5：运行 mode GREEN 与完整框架测试**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

Expected: 聚焦集与全部 framework tests 通过，0 failures、0 skips。

- [x] **Step 6：自审并提交 v0.6 mode 核心**

确认 public symbol 未增加、默认变化有 DocC、mode 只影响顶部、bottom owner 不受影响、cancel 不修改业务资源。随后：

```bash
git diff --check
git add Sources/AnchorPager/Public/AnchorPagerConfiguration.swift \
  Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift \
  Sources/AnchorPager/Public/AnchorPagerViewController.swift \
  Tests/AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests.swift \
  Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift \
  Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "启用顶部回弹所有权路由"
```

---

### Task 6：Example 模式入口与六类真实手势验收

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: Task 5 正式 public mode。
- Produces: “顶部回弹”菜单、`--anchorPagerTopOverscrollMode` launch argument、container/child current/max presentation 探针、六类 XCUITest。

- [x] **Step 1：写菜单和状态 RED 单元测试**

新增断言：

```swift
@Test func pagerNavigationShowsTopOverscrollMenuWithContainerSelected() {
    let viewController = ExamplePagerViewController()
    viewController.loadViewIfNeeded()

    let item = viewController.navigationItem.rightBarButtonItems?.first {
        $0.accessibilityLabel == "顶部回弹"
    }
    let actions = item?.menu?.children.compactMap { $0 as? UIAction } ?? []

    #expect(item?.accessibilityValue == "容器")
    #expect(actions.map(\.title) == ["关闭", "容器", "子页面"])
    #expect(actions.map(\.state) == [.off, .on, .off])
}
```

更新状态序列化期望，必须包含 `mode` 和七个 current/max presentation 数值键。

- [x] **Step 2：运行 RED**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests test
```

Expected: 找不到“顶部回弹”菜单；旧状态字符串字段不匹配。

- [x] **Step 3：实现菜单、launch argument 与业务 child 原生配置**

菜单映射固定为：

```swift
private func title(for mode: AnchorPagerTopOverscrollHandlingMode) -> String {
    switch mode {
    case .none: "关闭"
    case .container: "容器"
    case .child: "子页面"
    }
}
```

`--anchorPagerTopOverscrollMode none|container|child` 在安装 pager 前写入 configuration；菜单 action 直接更新 `pagerViewController.configuration.topOverscrollHandlingMode` 并重置探针。Example 业务 scroll page 显式设置：

```swift
scrollView.bounces = true
scrollView.alwaysBounceVertical = true
```

该设置属于业务 child，用于展示短内容 child mode；不得移入 framework。

- [x] **Step 4：实现六类真实 coordinate drag UI tests**

新增 launch helper：

```swift
private func launchPage(index: Int, mode: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
        "--anchorPagerInitialIndex", "\(index)",
        "--anchorPagerTopOverscrollMode", mode
    ]
    app.launch()
    XCTAssertTrue(scrollCoordinationStateProbe(in: app).exists)
    return app
}
```

六类测试使用以下完整断言：

```swift
func testPlainContainerTopBounceIsVisible() throws {
    let app = launchPage(index: 3, mode: "container")
    let probe = scrollCoordinationStateProbe(in: app)

    drag(in: app, from: 0.30, to: 0.72)

    let state = try XCTUnwrap(waitForScrollState(from: probe) {
        $0.containerTopMax > 1 && abs($0.containerCurrent) < 0.5
    })
    XCTAssertFalse(state.hasScrollTarget)
    XCTAssertEqual(state.mode, "container")
    XCTAssertEqual(state.childTopMax, 0, accuracy: 0.5)
}

func testPlainContainerBottomBounceIsVisible() throws {
    let app = launchPage(index: 3, mode: "none")
    let probe = scrollCoordinationStateProbe(in: app)
    let root = app.otherElements["plain-page-root"]
    XCTAssertTrue(root.waitForExistence(timeout: 3))
    drag(in: app, from: 0.76, to: 0.24)
    XCTAssertNotNil(waitForScrollState(from: probe) { $0.collapse >= 0.99 })
    probe.tap()

    drag(in: app, from: 0.76, to: 0.24)

    let state = try XCTUnwrap(waitForScrollState(from: probe) {
        $0.containerBottomMax > 1 && abs($0.containerCurrent) < 0.5
    })
    XCTAssertFalse(state.hasScrollTarget)
    XCTAssertGreaterThanOrEqual(root.frame.maxY, app.frame.maxY - 1)
}

func testRealChildContainerTopBounceIsVisible() throws {
    let app = launchPage(index: 2, mode: "container")
    let probe = scrollCoordinationStateProbe(in: app)

    drag(in: app, from: 0.30, to: 0.72)

    let state = try XCTUnwrap(waitForScrollState(from: probe) {
        $0.containerTopMax > 1
            && abs($0.containerCurrent) < 0.5
            && abs($0.childTopCurrent) < 0.5
    })
    XCTAssertEqual(state.mode, "container")
    XCTAssertEqual(state.distance, 0, accuracy: 0.5)
}

func testRealChildTopBounceUsesChildMode() throws {
    let app = launchPage(index: 2, mode: "child")
    let probe = scrollCoordinationStateProbe(in: app)

    drag(in: app, from: 0.30, to: 0.72)

    let state = try XCTUnwrap(waitForScrollState(from: probe) {
        $0.childTopMax > 1
            && abs($0.childTopCurrent) < 0.5
            && abs($0.containerCurrent) < 0.5
    })
    XCTAssertEqual(state.mode, "child")
    XCTAssertLessThan(state.containerTopMax, 0.5)
}

func testNoneModeHasNoVisibleTopOwner() throws {
    let app = launchPage(index: 2, mode: "none")
    let probe = scrollCoordinationStateProbe(in: app)
    probe.tap()

    drag(in: app, from: 0.30, to: 0.72)

    let state = try XCTUnwrap(waitForScrollState(from: probe) {
        abs($0.containerCurrent) < 0.5 && abs($0.childTopCurrent) < 0.5
    })
    XCTAssertEqual(state.mode, "none")
    XCTAssertLessThan(state.containerTopMax, 0.5)
    XCTAssertEqual(state.distance, 0, accuracy: 0.5)
}

func testRealChildBottomBounceUsesChild() throws {
    let app = launchPage(index: 2, mode: "container")
    let probe = scrollCoordinationStateProbe(in: app)
    let lastRow = app.staticTexts["长页 - 30"]
    for _ in 0..<6 where !lastRow.isHittable {
        drag(in: app, from: 0.76, to: 0.24)
    }
    XCTAssertTrue(lastRow.isHittable)
    probe.tap()

    drag(in: app, from: 0.76, to: 0.24)

    let state = try XCTUnwrap(waitForScrollState(from: probe) {
        $0.childBottomMax > 1
            && abs($0.childBottomCurrent) < 0.5
            && abs($0.containerCurrent) < 0.5
    })
    XCTAssertLessThan(state.containerBottomMax, 0.5)
    XCTAssertGreaterThanOrEqual(state.collapse, 0.99)
}
```

`ScrollCoordinationState` parser 新增并赋值这些字段：

```swift
let mode: String
let containerCurrent: CGFloat
let containerTopMax: CGFloat
let containerBottomMax: CGFloat
let childTopCurrent: CGFloat
let childTopMax: CGFloat
let childBottomCurrent: CGFloat
let childBottomMax: CGFloat
```

initializer 对 `mode` 和七个数值键逐项 guard；数值统一使用 `Double` 转 `CGFloat`。另外保留切页/reload 测试，断言 active metrics 归零、页面 owner 与 committed index 一致且无跳动。所有拖拽使用 `press(...thenDragTo:)` 与 predicate，不使用固定 sleep。

- [x] **Step 5：运行 Example 聚焦与全量测试**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainContainerTopBounceIsVisible \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainContainerBottomBounceIsVisible \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testRealChildContainerTopBounceIsVisible \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testRealChildTopBounceUsesChildMode \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testNoneModeHasNoVisibleTopOwner \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testRealChildBottomBounceUsesChild test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

Expected: 聚焦 6 类与 Example 全量全部通过，0 failures、0 skips。

- [x] **Step 6：自审并提交**

确认 Example child 自己拥有 delegate/bounce 配置，探针只读 public layout/自身 scroll offset，不伪造框架 owner。随后：

```bash
git diff --check
git add Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift \
  Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift \
  Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift \
  Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "验证顶部与底部真实回弹"
```

---

### Task 7：文档、全量验收与最终复审

**Files:**
- Modify: `README.md`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-13-boundary-bounce-ownership-design.md`
- Modify: `docs/superpowers/specs/2026-07-13-v0-5-scroll-coordination-design.md`
- Modify: `docs/superpowers/specs/2026-07-13-plain-page-direct-containment-design.md`
- Modify: `docs/superpowers/plans/2026-07-13-v0-5-scroll-coordination.md`
- Modify: `docs/superpowers/plans/2026-07-13-plain-page-direct-containment.md`
- Modify: `docs/superpowers/plans/2026-07-13-boundary-bounce-ownership.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Tasks 1–6 的实现、测试和提交记录。
- Produces: v0.5 Task 7 与 v0.6 状态、完整验收证据、自审结论和真实完成标记。

- [x] **Step 1：同步接入文档和版本状态**

README 必须明确：

- 默认 `.container`；`.child` 只路由到真实 committed child。
- 业务 child 自己决定 `bounces`/`alwaysBounceVertical`，AnchorPager 不修改。
- real child bottom 由 child、plain bottom 由 container。
- plain page direct containment、nil scroll target 和物理底边不变。
- framework 不设置业务 child scroll/pan delegate 或 `isScrollEnabled`。

task-list 只勾选真实通过的条目；v0.5 Task 7 与 v0.6 Ready 必须分别记录测试数量、0 fail/skip、复审结论和提交。

- [x] **Step 2：运行静态架构门禁**

```bash
rg -n 'scrollView\.delegate\s*=|panGestureRecognizer\.delegate\s*=' Sources/AnchorPager
rg -n '\.bounces\s*=|\.alwaysBounceVertical\s*=|\.isScrollEnabled\s*=' \
  Sources/AnchorPager/Children Sources/AnchorPager/Core Sources/AnchorPager/Overscroll
rg -n 'Tabman|Pageboy' Sources/AnchorPager/Public
rg -n 'AnchorPagerPageScrollHostViewController|fallback scroll host|synthetic scroll wrapper' \
  Sources Tests README.md docs/architecture.md docs/requirements.md
```

Expected:

- delegate 赋值只允许命中 AnchorPager 自有 `verticalScrollView.delegate = verticalScrollDelegate`。
- child/core/overscroll 不命中业务 bounce 与 `isScrollEnabled` 写入。
- Public 不命中 Tabman/Pageboy。
- Sources/Tests/现行接入文档不命中已删除 wrapper；历史 specs/plans 可保留带 superseded 说明的记录。

- [x] **Step 3：运行完整验收**

```bash
swift --version
swift package resolve
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' build
git diff --check
```

Expected: Swift 6.2 或更高；resolve、framework tests、Example 单元/UI tests 和 generic build 全部成功；0 failures、0 skips；无新增生产 warning。

- [x] **Step 4：执行代码自审**

逐项记录：

1. public API 只改变默认 mode，不泄漏第三方类型。
2. Pageboy 对 plain/scroll page 的唯一 containment 与 appearance complete/cancel 不变。
3. Store committed/pending、generation、cache、snapshot 和 managed inset ownership 不变。
4. ScrollCoordinator 是唯一 offset writer，OverscrollCoordinator 不持有 UIKit/page/provider。
5. child delegate/pan delegate/`isScrollEnabled`/`bounces`/`alwaysBounceVertical` 无框架写入。
6. stable range 与 native boundary 在 container delegate、child KVO、pan target、geometry update 中没有反向 clamp。
7. container top/bottom presentation 对称且不进入 canonical layout/range。
8. mode switch、selection、reload、layout reload、rotation 和 deinit cancel 幂等。
9. overscroll 日志只在状态变化时输出。
10. 真实 UI 使用实际 presentation distance，并保留 plain 物理底边证据。

- [x] **Step 5：执行初次独立复审门禁**

比较边界修复开始前提交 `be2d783` 到实现 HEAD。Critical/Important 必须清零；任何双 writer、业务属性写入、pending owner、synthetic wrapper、瞬时 flag 伪视觉证据或 UI 不稳定都先修复并重跑对应 RED/GREEN。

初次独立复审发现 3 个 Important：未呈现 owner 反向回稳未同步收敛、Header 部分折叠时 child KVO 错误触发 top owner、`.none` UI 探针记录原始 delegate/KVO 瞬时 offset。`f81ca1e` 已按 RED→GREEN 修复并完成聚焦与全量验收。

- [x] **Step 5b：执行修复后的再次独立复审门禁**

第四次整分支独立复审覆盖 `be2d783...13b3d95` 并重点比较 `b00d204...128821f`，尤其是 `5b80893...128821f`；结论为 Critical 0、Important 0、Minor 2。两个 Minor 已在最终状态提交中修复。

- [x] **Step 6：提交最终文档与验收记录**

```bash
git diff --check
git add README.md AGENTS.md docs
git commit -m "完成纵向边界回弹验收"
```

---

## Task 7 实现者验收记录（2026-07-13）

### 新鲜命令与结果

- `swift --version`：exit 0，Apple Swift 6.3.3，满足 Swift 6.2 最低工具链。
- `swift package resolve`：沙盒内因用户级 Clang/SwiftPM cache 权限 exit 1；按权限规则提升后同一命令 exit 0。
- `xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test`：提升 CoreSimulator 权限后 exit 0；xcresult 264 项、0 fail、0 skip、0 warning。
- `xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test`：exit 0；xcresult 36 项（9 单元 + 27 UI）、0 fail、0 skip、0 warning。
- `xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build`：exit 0；xcresult status succeeded、0 error、0 warning、0 analyzer warning。
- `git diff --check` 与文档修改后的静态门禁在提交前复验；最终结果记录在本次文档提交与实施者报告。

### 静态门禁与十项自审

1. Public API 仅把既有顶部 mode 默认值设为 `.container`，Public 无 Tabman/Pageboy。
2. Pageboy 继续对 plain/scroll page 执行唯一 containment 与 appearance complete/cancel；框架没有手工 appearance forwarding。
3. Store committed/pending、generation-specific retention/snapshot/managed inset ownership 未被边界实现复制或改写。
4. ScrollCoordinator 是 active handoff/boundary 的 offset writer；OverscrollCoordinator 只持有纯 owner 状态。managed inset、snapshot 和显式 Header layout adjustment 仅在各自结构性事务写 offset。
5. framework 未设置业务 child scroll/pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。
6. active native owner 在 container delegate、child KVO、pan target 和 geometry refresh 中均不被反向 clamp；对应 framework 回归通过。
7. 历史 container presentation 使用 `topOverflow - bottomOverflow`；2026-07-14 修订为 top 移动 chrome/page、plain bottom 只移动 page，且两者均不进入 canonical output、range、managed inset 或 snapshot。
8. mode switch、selection、reload、Header layout reload、rotation/rebind/deinit 的 cancel/cleanup 路径幂等且有测试。
9. overscroll 与 guard 日志只在状态变化时输出；重复热路径测试没有逐帧噪声。
10. Example 六类真实 drag 使用 current/max presentation distance；plain root 物理底边和 container-only pan 证据在本轮 36 项全量中通过。

### 最终门禁结论

- 初次独立复审的 3 个 Important、第二次整分支复审的零稳定区间 Important/架构文档 Minor，以及第三次整分支复审的已呈现 `.top/.child` 回稳 Important/requirements 日志 Minor 均已修复；`128821f` 显式返回 finish owner，按有无 pan input 分别重放当前 Resolver 或保留 observer raw total，其他 finish 路径保持原语义。
- 最新新鲜验收为 Framework 283 项、Example 37 项、generic build 全部成功，0 fail、0 skip，三份 xcresult 0 error/warning/analyzer warning。
- 第四次整分支独立复审已覆盖 `be2d783...13b3d95` 并重点比较 `b00d204...128821f`、尤其 `5b80893...128821f`；结论为 Critical 0、Important 0、Minor 2。README 旧验收摘要已更新，`testRealChildContainerTopBounceIsVisible` 已增加严格 `XCTAssertLessThan(state.childTopMax, 0.5)` 证明 `.container` 顶部 owner 排他。
- 最终证据：生产代码 HEAD `128821f` 对应 Framework 283/283 结果包 `/private/tmp/AnchorPagerPresentedTopFrameworkFull-20260713-2258.xcresult`；新增严格断言的目标 UI 1/1、Example 37/37（10 单元 + 27 UI）和 generic Simulator build 均通过，0 fail、0 skip、0 error/warning/analyzer warning。
- Step 5b/6 已完成；最终统一提交标题为 `完成纵向边界回弹验收`，v0.5 Task 7 与 v0.6 标记 Ready。

---

## 计划自审

- Spec coverage：Tasks 1–7 覆盖业务 bounce 配置保留、stable/native 分离、六种顶部矩阵、两种底部 owner、对称 presentation、cancel、日志、真实 UI 和文档状态。
- File boundaries：OverscrollCoordinator 只返回策略；ScrollCoordinator 唯一写 offset；Binding 只观察；ViewController 只装配 mode/cancel/presentation。
- Type consistency：Task 2 定义的 `Boundary`、`Owner`、`ActiveOwner`、`Route` 和生命周期 API 被 Tasks 3–5 原样消费；没有第二套 owner enum。
- TDD order：每个实现任务均先有精确 RED、预期失败原因、最小 GREEN、聚焦命令、自审和提交边界。
- Architecture gates：不设置业务 delegate/pan delegate/`isScrollEnabled`/bounce 属性，不恢复 wrapper，不读取 pending provider，不改变 Pageboy containment/inset/snapshot。
- UI evidence：container 使用 layout context 实际位移，child 使用业务 scroll 自身 overflow，所有场景同时验证 max presentation 与 settle 后 current，不以单一瞬时 boolean 代替视觉证据。
- Scope：不实现刷新控件、跨 owner velocity 合成、v0.7 完整 interaction state、scrollsToTop、旋转位置恢复或横向返回手势优先级。
