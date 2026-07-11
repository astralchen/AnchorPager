# v0.3 固定分页视口与 Inset Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 optional bar height、collapsed-state fixed Tabman adapter、Tabman `barInsets` 几何回调和可逆 child managed inset ownership，使 v0.3 成为后续 page state 与纵向滚动协调的稳定基础。

**Architecture:** Header 继续位于 Tabman adapter 上方，adapter top 跟随 Header bottom，但 adapter height 固定为 Header 完全折叠时的 viewport 高度。Paging adapter 负责把 optional height 应用到实际 Tabman bar，并只通过 UIKit `UIEdgeInsets` 回报真实 `barInsets`；独立 `AnchorPagerManagedInsetCoordinator` 负责 weak ownership、external/managed inset 合成、offset distance 迁移与归还。

**Tech Stack:** Swift 6、UIKit、Swift Package Manager、XCTest、Swift Testing、Tabman 4.0.1、Pageboy 5.0.2、Xcode iOS Simulator UI tests、`os.Logger`

## Global Constraints

- Package name、Library product、Module name 均保持 `AnchorPager`。
- Minimum OS 保持 iOS 14，语言模式保持 Swift 6，UI stack 保持 UIKit。
- Tabman 4.0.1、Pageboy 5.0.2 只允许出现在 `Sources/AnchorPager/Paging/`，不得泄漏到 public API。
- 横向 page 的 UIKit containment 仍只由 Tabman/Pageboy adapter 执行；AnchorPager 不对同一 page controller 重复 `addChild`。
- UIKit、public API、data source、delegate 和 coordinator 状态保持 `@MainActor`；纯 LayoutEngine 不绑定 MainActor。
- `automaticallyAdjustsChildInsets` 必须在 paging adapter `viewDidLoad` 前设置为 `false`。
- bar 最终几何只读取 Tabman public `barInsets`；不访问 `topBarContainer`、`AutoInsetter`、`InsetStore` 或 Pageboy 内部 scroll view。
- 普通 Header 折叠热路径只移动 adapter top，不改变 adapter height 或 Pageboy child bounds。
- child managed top 只表达 Tabman bar obstruction，不包含 Header 或容器顶部 safe area。
- 外部 inset 必须保留；ownership 结束时只移除最后一次 managed 部分并恢复原始 adjustment behavior。
- 所有实现任务测试先行；每个任务完成后运行定向测试、`git diff --check` 和代码自审，再使用中文单主题提交。
- 用户可见布局、滚动、safe area、fallback 和示例行为必须有 UIKit 集成测试或 UI test。
- 不实现 v0.4 page cache/lifecycle state store，不实现 v0.5 container/child handoff，不提前实现 v0.6/v0.7。

---

## File Structure

### Create

- `Sources/AnchorPager/Children/AnchorPagerManagedInsetCoordinator.swift`
  - weak scroll ownership、managed/external inset 合成、offset distance 迁移、归还与 inset 日志。
- `Tests/AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests.swift`
  - coordinator 纯 UIKit 单元测试。

### Modify

- `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`
  - `AnchorPagerBarConfiguration.height: CGFloat?`，默认 nil。
- `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`
  - 增加 fixed `pagingFrame`，移除歧义 `ManagedInsetTarget`，barHeight 输入改为 resolved runtime height。
- `Sources/AnchorPager/Paging/AnchorPagerTabBarAdapter.swift`
  - 继续只创建默认 TMBar，不承担 inset 或容器布局。
- `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
  - 保存实际 bar、应用 optional height constraint、布局后回报 resolved `barInsets`。
- `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
  - 使用 resolved barInsets 生成 LayoutEngine input、应用 fixed paging height、管理 active scroll targets 和 inset ownership。
- `Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift`
  - fixed paging frame 纯计算测试。
- `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
  - optional/adaptive bar height、barInsets callback 和日志测试。
- `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
  - adapter/child bounds、真实 managed inset、fallback、reload 归还和容器集成测试。
- `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
  - 为真实 scroll/fallback 内容增加稳定 accessibility identifiers，默认使用自适应 bar。
- `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
  - 真实列表页和 fallback 页可见路径 UI test。
- `README.md`
  - optional bar height、Tabman bar inset、external inset 修改限制和 ownership 归还。
- `docs/architecture.md`
  - 把 v0.3 计划架构更新为真实完成状态，记录 current limitations。
- `docs/task-list.md`
  - 只勾选有实现和验证证据的 v0.3 项。
- `docs/superpowers/plans/2026-07-11-v0-3-fixed-paging-inset-ownership.md`
  - 每个任务完成后更新 checkbox、自审和验证记录。

---

### Task 1: LayoutEngine 固定 Paging Frame 契约

**Files:**
- Modify: `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Consumes: `AnchorPagerHeaderHeightMode`、`AnchorPagerHeaderTopBehavior`、container bounds/obstruction/contentOffset。
- Produces: `AnchorPagerLayoutEngine.Input.barHeight: CGFloat` 的语义固定为 runtime resolved height、`Output.pagingFrame: CGRect`；不再产生 `ManagedInsetTarget`。

- [x] **Step 1: 写 fixed paging frame 失败测试**

在 `AnchorPagerLayoutEngineTests` 增加：

```swift
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
```

把原 `testBottomObstructionDoesNotClipContentFrameAndPreservesManagedInsetTarget` 改为：

```swift
func testBottomObstructionDoesNotClipContentOrPagingFrame() {
    let output = AnchorPagerLayoutEngine().layout(
        for: input(bottomObstructionHeight: 83)
    )

    XCTAssertEqual(output.contentFrame.maxY, 640)
    XCTAssertEqual(output.pagingFrame.height, 640)
}
```

- [x] **Step 2: 运行 Task 1 RED**

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-layout-red -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests test
```

Expected: FAIL，核心错误为 `Output` 没有 `pagingFrame`，旧测试仍引用 `managedInsetTarget`。

- [x] **Step 3: 实现最小固定 frame 纯计算**

保留 input 的 `barHeight` 参数标签以避免无意义调用点改名，并在类型定义旁记录它表示 runtime
resolved bar height，不是 public 配置的先验值：

```swift
var barHeight: CGFloat
```

Output 调整为：

```swift
struct Output: Equatable {
    var resolvedHeaderHeight: ResolvedHeaderHeight
    var collapseOffset: CGFloat
    var collapseProgress: CGFloat
    var headerFrame: CGRect
    var barFrame: CGRect
    var contentFrame: CGRect
    var pagingFrame: CGRect
}
```

在 `layout(for:)` 计算：

```swift
let resolvedBarHeight = nonNegativeFinite(input.barHeight)
let collapsedAdapterTop = topPinY + resolvedHeaderHeight.collapsed
let pagingFrame = CGRect(
    x: bounds.minX,
    y: barY,
    width: bounds.width,
    height: Swift.max(0, bounds.maxY - collapsedAdapterTop)
)
```

`barFrame.height` 使用 `resolvedBarHeight`，删除 `ManagedInsetTarget` 及其 output。bottom obstruction 仍作为已验证环境输入保留，v0.3 coordinator 在 UIKit 层消费。

同步删除 ViewController 的 `lastLoggedManagedInsetTarget` 和 `inset.managedTargetChanged` 旧日志分支。
把 `testSafeAreaBoundsAndManagedInsetChangesWriteLogs` 重命名为
`testSafeAreaAndBoundsChangesWriteLayoutLogs`，删除对旧 managed target 事件的正/负断言；safe area 和
bounds 日志断言保持不变。新的真实 inset 日志从 Task 3 coordinator 开始覆盖。

- [x] **Step 4: 更新全部 LayoutEngine helper 参数名并运行 GREEN**

测试 helper 继续使用 `barHeight` 标签；增加注释说明传入的是已解析的 runtime bar height。

Run: Task 1 RED 的同一命令。

Expected: PASS，`AnchorPagerLayoutEngineTests` 全部通过。

- [x] **Step 5: 自审并提交 Task 1**

检查纯计算层不 import UIKit、不绑定 MainActor；paging frame height 不依赖 contentOffset、bar height 或 bottom obstruction；不新增日志。

```bash
git diff --check
git add Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "固定分页适配器布局范围"
```

---

### Task 2: Optional Bar Height 与 Tabman BarInsets 回调

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`

**Interfaces:**
- Consumes: internal optional height request `CGFloat?`；public 配置在 Task 4 一次性切换并接入。
- Produces: `AnchorPagerPagingAdapter.setBarHeight(_ height: CGFloat?)`；delegate 新增 `pagingAdapter(_:didUpdateBarInsets:)`。

- [x] **Step 1: 写 optional API 和真实 bar 布局失败测试**

在 paging adapter tests 增加 window-backed helper 和测试：

```swift
@MainActor
func testExplicitBarHeightConstrainsActualTabmanBarAndReportsInsets() throws {
    let adapter = AnchorPagerPagingAdapter()
    let delegate = RecordingPagingDelegate()
    adapter.eventDelegate = delegate
    adapter.setBarHeight(64)
    adapter.reload(
        titles: ["First"],
        viewControllers: [UIViewController()],
        selectedIndex: 0
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = adapter
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    window.layoutIfNeeded()
    adapter.view.setNeedsLayout()
    adapter.view.layoutIfNeeded()

    XCTAssertEqual(adapter.barInsets.top, 64, accuracy: 0.5)
    XCTAssertTrue(delegate.barInsets.contains { abs($0.top - 64) < 0.5 })
}

@MainActor
func testNilBarHeightUsesAdaptiveTabmanHeight() {
    let adapter = AnchorPagerPagingAdapter()
    adapter.setBarHeight(nil)
    adapter.reload(
        titles: ["First"],
        viewControllers: [UIViewController()],
        selectedIndex: 0
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = adapter
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    window.layoutIfNeeded()
    adapter.view.layoutIfNeeded()

    XCTAssertGreaterThan(adapter.barInsets.top, 0)
}

@MainActor
func testInvalidBarHeightFallsBackToZeroAndWritesPagingLog() {
    let adapter = AnchorPagerPagingAdapter()
    var events: [AnchorPagerLogger.Event] = []
    AnchorPagerLogger.sink = { events.append($0) }
    defer { AnchorPagerLogger.sink = nil }

    AnchorPagerAssertions.$isEnabled.withValue(false) {
        adapter.setBarHeight(.nan)
    }

    XCTAssertTrue(events.contains(
        .init(category: .paging, level: .debug, event: "paging.barHeightInvalid")
    ))
}
```

`RecordingPagingDelegate` 增加：

```swift
var barInsets: [UIEdgeInsets] = []

func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    didUpdateBarInsets barInsets: UIEdgeInsets
) {
    self.barInsets.append(barInsets)
}
```

- [x] **Step 2: 运行 Task 2 RED**

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-bar-red -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

Expected: FAIL，核心错误为 adapter 缺少 `setBarHeight` 和 barInsets delegate。

- [x] **Step 3: 保存实际 bar 并实现 idempotent height constraint**

在 adapter 保存：

```swift
private var installedBar: TMBar?
private var barHeightConstraint: NSLayoutConstraint?
private var requestedBarHeight: CGFloat?
private var lastReportedBarInsets: UIEdgeInsets?
```

提供：

```swift
func setBarHeight(_ height: CGFloat?) {
    let resolvedHeight: CGFloat?
    if let height, (!height.isFinite || height < 0) {
        AnchorPagerAssertions.failure("AnchorPager bar height must be finite and nonnegative.")
        AnchorPagerLogger.log(.debug, category: .paging, event: "paging.barHeightInvalid")
        resolvedHeight = 0
    } else {
        resolvedHeight = height
    }

    guard requestedBarHeight != resolvedHeight else { return }
    requestedBarHeight = resolvedHeight
    updateBarHeightConstraintIfNeeded()
}
```

`installBarIfNeeded()` 创建 bar 后保存实例，并由 `updateBarHeightConstraintIfNeeded()` 在 nil 时 deactivate，非 nil 时创建/更新 `heightAnchor` constraint。

- [x] **Step 4: 布局后回报 public barInsets**

delegate protocol 增加：

```swift
func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    didUpdateBarInsets barInsets: UIEdgeInsets
)
```

为该新增 callback 提供 internal 默认 no-op，使 Task 2 不要求尚未接入 bar geometry 的
`AnchorPagerViewController` 提前实现：

```swift
extension AnchorPagerPagingAdapterDelegate {
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {}
}
```

adapter override：

```swift
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    let resolvedInsets = sanitizedBarInsets(barInsets)
    guard lastReportedBarInsets != resolvedInsets else { return }
    lastReportedBarInsets = resolvedInsets
    AnchorPagerLogger.log(.debug, category: .paging, event: "paging.barInsetsChanged")
    eventDelegate?.pagingAdapter(self, didUpdateBarInsets: resolvedInsets)
}
```

`sanitizedBarInsets` 把负数或非有限分量降级为 0，不输出业务数据。

- [x] **Step 5: 运行 Task 2 GREEN 和完整 adapter tests**

Run: Task 2 RED 的同一命令。

Expected: PASS。

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-bar-green -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

Expected: `AnchorPagerPagingAdapterTests` 全部通过，日志测试包含 `paging.barInsetsChanged` 和 invalid height。

- [x] **Step 6: 自审并提交 Task 2**

检查 Tabman/Pageboy 仍只在 Paging 层；bar constraint 在 nil/value 切换时不重复创建；delegate 不返回 TMBar；本任务不提前修改 public API。

```bash
git diff --check
git add Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift
git commit -m "支持分段栏自适应高度"
```

---

### Task 3: Managed Inset Coordinator 单元契约

**Files:**
- Create: `Sources/AnchorPager/Children/AnchorPagerManagedInsetCoordinator.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests.swift`

**Interfaces:**
- Consumes: managed `UIEdgeInsets` target 和 `UIScrollView`。
- Produces: `AnchorPagerManagedInsetCoordinator.Target`、`apply(_:to:)`、`release(_:)`、`releaseAll()`。

- [x] **Step 1: 写 coordinator 失败测试**

创建测试文件，至少包含：

```swift
@MainActor
final class AnchorPagerManagedInsetCoordinatorTests: XCTestCase {
    func testApplyPreservesExternalInsetsAndMigratesDistanceFromTop() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let scrollView = UIScrollView()
        scrollView.contentInset = UIEdgeInsets(top: 10, left: 3, bottom: 7, right: 4)
        scrollView.scrollIndicatorInsets = UIEdgeInsets(top: 2, left: 1, bottom: 5, right: 6)
        scrollView.contentOffset.y = -10

        coordinator.apply(
            .init(
                content: UIEdgeInsets(top: 48, left: 0, bottom: 34, right: 0),
                indicators: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
            ),
            to: scrollView
        )

        XCTAssertEqual(scrollView.contentInset, UIEdgeInsets(top: 58, left: 3, bottom: 41, right: 4))
        XCTAssertEqual(scrollView.scrollIndicatorInsets, UIEdgeInsets(top: 2, left: 1, bottom: 39, right: 6))
        XCTAssertEqual(scrollView.contentOffset.y, -58, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentInsetAdjustmentBehavior, .never)
    }

    func testReleaseRemovesOnlyManagedInsetsAndRestoresBehavior() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let scrollView = UIScrollView()
        scrollView.contentInsetAdjustmentBehavior = .always
        scrollView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 7, right: 0)
        scrollView.contentOffset.y = -10
        let target = AnchorPagerManagedInsetCoordinator.Target(
            content: UIEdgeInsets(top: 48, left: 0, bottom: 34, right: 0),
            indicators: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        )

        coordinator.apply(target, to: scrollView)
        scrollView.contentInset.bottom += 5
        coordinator.release(scrollView)

        XCTAssertEqual(scrollView.contentInset.top, 10, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentInset.bottom, 12, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentOffset.y, -10, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentInsetAdjustmentBehavior, .always)
    }

    func testRepeatedTargetSkipsWritesAndWritesSkipLog() {
        let coordinator = AnchorPagerManagedInsetCoordinator()
        let scrollView = UIScrollView()
        let target = AnchorPagerManagedInsetCoordinator.Target(
            content: UIEdgeInsets(top: 48, left: 0, bottom: 0, right: 0),
            indicators: .zero
        )
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        coordinator.apply(target, to: scrollView)
        events.removeAll()
        coordinator.apply(target, to: scrollView)

        XCTAssertEqual(events, [.init(category: .inset, level: .debug, event: "inset.ownership.skip")])
    }
}
```

增加 weak record 测试：

```swift
func testCoordinatorDoesNotRetainManagedScrollView() {
    let coordinator = AnchorPagerManagedInsetCoordinator()
    weak var weakScrollView: UIScrollView?

    autoreleasepool {
        let scrollView = UIScrollView()
        weakScrollView = scrollView
        coordinator.apply(
            .init(
                content: UIEdgeInsets(top: 48, left: 0, bottom: 0, right: 0),
                indicators: .zero
            ),
            to: scrollView
        )
    }

    XCTAssertNil(weakScrollView)
    coordinator.releaseAll()
}
```

- [x] **Step 2: 运行 Task 3 RED**

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-inset-red -only-testing:AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests test
```

Expected: FAIL，核心错误为找不到 `AnchorPagerManagedInsetCoordinator`。

- [x] **Step 3: 实现 weak ownership record 和 Target**

核心结构：

```swift
@MainActor
final class AnchorPagerManagedInsetCoordinator {
    struct Target: Equatable {
        var content: UIEdgeInsets
        var indicators: UIEdgeInsets
    }

    private final class Record {
        weak var scrollView: UIScrollView?
        let originalAdjustmentBehavior: UIScrollView.ContentInsetAdjustmentBehavior
        var lastManagedContent: UIEdgeInsets = .zero
        var lastManagedIndicators: UIEdgeInsets = .zero

        init(scrollView: UIScrollView) {
            self.scrollView = scrollView
            self.originalAdjustmentBehavior = scrollView.contentInsetAdjustmentBehavior
        }
    }

    private var records: [ObjectIdentifier: Record] = [:]
}
```

实现 private inset add/subtract、finite sanitization、distance-from-top 迁移和 guarded equality。apply 首次记录 `inset.ownership.begin`，变化记录 update，相同记录 skip；release 记录 end。

- [x] **Step 4: 实现 apply/release/releaseAll**

`apply` 顺序固定为：清理 dead records、计算旧 top distance、分离 external、设置 `.never`、写新 insets、迁移 offset、更新 last managed。

`release` 使用相同 distance 算法把 managed target 迁移到 zero，然后恢复 original behavior 并移除 record。`releaseAll()` 对 live records 逐一归还，不在迭代字典时修改原字典。

- [x] **Step 5: 运行 Task 3 GREEN**

Run: Task 3 RED 的同一命令。

Expected: 全部 coordinator tests 通过。

- [x] **Step 6: 自审并提交 Task 3**

检查 coordinator 为 MainActor、record 弱持有 scroll、没有 Tabman/Pageboy、没有 `nonisolated(unsafe)`、日志不包含几何值、重复 target 不写 UIKit 属性。

```bash
git diff --check
git add Sources/AnchorPager/Children/AnchorPagerManagedInsetCoordinator.swift Tests/AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests.swift
git commit -m "实现子页面插入量所有权"
```

---

### Task 4: ViewController、Fallback 与 Fixed Adapter 集成

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Sources/AnchorPager/Children/AnchorPagerPageScrollHostViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Consumes: Task 1 `Output.pagingFrame`、Task 2 `didUpdateBarInsets`、Task 3 inset coordinator。
- Produces: active page scroll target 列表、resolved bar geometry、真实 managed top/bottom、reload/deinit ownership 归还。

- [x] **Step 1: 写固定 adapter 和真实 managed inset 失败测试**

先把默认配置断言改为：

```swift
XCTAssertNil(configuration.bar.height)
```

增加：

```swift
@MainActor
func testHeaderScrollingMovesAdapterWithoutChangingAdapterOrChildHeight() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 120, min: 20)
    configuration.bar.height = 56
    let pager = AnchorPagerViewController(configuration: configuration)
    let child = ScrollChildViewController()
    let dataSource = StubDataSource(
        count: 1,
        viewControllers: [child],
        headerContent: .view(FixedFittingView(height: 120))
    )
    pager.dataSource = dataSource
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = pager
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    pager.reloadData()
    window.layoutIfNeeded()

    let adapter = try XCTUnwrap(installedAdapter(in: pager))
    let expandedAdapterHeight = adapter.view.bounds.height
    let expandedChildHeight = child.view.bounds.height
    let expandedMinY = adapter.view.frame.minY

    pager.verticalScrollView.contentOffset.y = 100
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
    window.layoutIfNeeded()

    XCTAssertLessThan(adapter.view.frame.minY, expandedMinY)
    XCTAssertEqual(adapter.view.bounds.height, expandedAdapterHeight, accuracy: 0.5)
    XCTAssertEqual(child.view.bounds.height, expandedChildHeight, accuracy: 0.5)
}
```

增加真实 inset 测试：

```swift
@MainActor
func testManagedTopUsesTabmanBarOnlyAndPreservesExternalInsets() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 120, min: 20)
    configuration.bar.height = 56
    let pager = AnchorPagerViewController(configuration: configuration)
    let child = ScrollChildViewController()
    child.loadViewIfNeeded()
    child.scrollView.contentInset = UIEdgeInsets(top: 7, left: 3, bottom: 11, right: 4)
    child.scrollView.contentOffset.y = -7
    let dataSource = StubDataSource(
        count: 1,
        viewControllers: [child],
        headerContent: .view(FixedFittingView(height: 120))
    )
    pager.dataSource = dataSource
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = pager
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    pager.reloadData()
    window.layoutIfNeeded()
    pager.view.layoutIfNeeded()

    XCTAssertEqual(child.scrollView.contentInset.top, 63, accuracy: 0.5)
    XCTAssertEqual(child.scrollView.contentInset.left, 3, accuracy: 0.001)
    XCTAssertEqual(child.scrollView.contentInset.right, 4, accuracy: 0.001)
    XCTAssertEqual(child.scrollView.contentOffset.y, -63, accuracy: 0.5)
}
```

该断言证明 managed top 为 56，而不是 Header 120 + bar 56。

- [x] **Step 2: 写 reload 归还和 fallback 失败测试**

增加 reload 归还测试：

```swift
@MainActor
func testReloadReleasesStaleInsetOwnershipAndManagesReplacement() {
    var configuration = AnchorPagerConfiguration.default
    configuration.bar.height = 56
    let pager = AnchorPagerViewController(configuration: configuration)
    let oldChild = ScrollChildViewController()
    let replacement = ScrollChildViewController()
    oldChild.loadViewIfNeeded()
    replacement.loadViewIfNeeded()
    oldChild.scrollView.contentInsetAdjustmentBehavior = .always
    oldChild.scrollView.contentInset = UIEdgeInsets(top: 7, left: 0, bottom: 11, right: 0)
    oldChild.scrollView.contentOffset.y = -7
    let dataSource = StubDataSource(count: 1, viewControllers: [oldChild])
    pager.dataSource = dataSource
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = pager
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    pager.reloadData()
    window.layoutIfNeeded()
    XCTAssertEqual(oldChild.scrollView.contentInset.top, 63, accuracy: 0.5)

    dataSource.viewControllers = [replacement]
    pager.reloadData()
    window.layoutIfNeeded()

    XCTAssertEqual(oldChild.scrollView.contentInset.top, 7, accuracy: 0.001)
    XCTAssertEqual(oldChild.scrollView.contentInset.bottom, 11, accuracy: 0.001)
    XCTAssertEqual(oldChild.scrollView.contentInsetAdjustmentBehavior, .always)
    XCTAssertEqual(replacement.scrollView.contentInset.top, 56, accuracy: 0.5)
    XCTAssertEqual(replacement.scrollView.contentInsetAdjustmentBehavior, .never)
}
```

扩展现有 fallback test；测试先设置 `pager.additionalSafeAreaInsets.bottom = 23`。由于 UIKit 会把
设备自身 safe area 与 additional safe area 合成，断言应使用容器最终解析到的本地底部遮挡：

```swift
XCTAssertEqual(fallbackHost.scrollView.contentInset.top, adapter.barInsets.top, accuracy: 0.5)
XCTAssertEqual(
    fallbackHost.scrollView.contentInset.bottom,
    pager.view.safeAreaInsets.bottom,
    accuracy: 0.5
)
```

增加重复 apply 日志测试，结构性 layout 重跑不得重复 `inset.ownership.update`。

- [x] **Step 3: 运行 Task 4 RED**

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-controller-red -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

Expected: FAIL，adapter height 随 offset 变化，child inset 未写入，reload 未归还 ownership。

- [x] **Step 4: 接入 resolved barInsets 和 fixed paging frame**

先切换 public 配置：

```swift
public struct AnchorPagerBarConfiguration: Sendable, Equatable {
    public var height: CGFloat?

    public static let `default` = AnchorPagerBarConfiguration()

    public init(height: CGFloat? = nil) {
        self.height = height
    }
}
```

同步中文 DocC：nil 为 Tabman 自适应，非 nil 为显式高度策略。

ViewController 新增：

```swift
private let managedInsetCoordinator = AnchorPagerManagedInsetCoordinator()
private var resolvedBarInsets: UIEdgeInsets = .zero
private var activePageScrollViews: [UIScrollView] = []
```

`makeLayoutOutput` 使用：

```swift
barHeight: resolvedBarInsets.top
```

`applyLayoutOutput` 改为：

```swift
pagingTopConstraint?.constant = Swift.max(
    0,
    output.pagingFrame.minY - output.headerFrame.maxY
)
pagingHeightConstraint?.constant = output.pagingFrame.height
```

Task 1 已删除 ViewController 的旧 `lastLoggedManagedInsetTarget` 和 `inset.managedTargetChanged` 布局日志；本步骤不得重新引入。

- [x] **Step 5: 实现 barInsets delegate 收敛**

在 adapter delegate extension 增加：

```swift
func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    didUpdateBarInsets barInsets: UIEdgeInsets
) {
    guard resolvedBarInsets != barInsets else { return }
    resolvedBarInsets = barInsets
    view.setNeedsLayout()
    if !isApplyingLayout {
        updateVisibleLayout()
    }
}
```

在结构性布局开始前调用 `pagingAdapter.setBarHeight(configuration.bar.height)`。若 callback 发生在当前布局事务中，只缓存并请求下一次 layout，不递归进入。

- [x] **Step 6: 准备 active scroll targets 并处理冲突**

reloadData 期间为每个 page 解析一次 target，保存与 `currentViewControllers` 同索引的 active scroll 列表：

```swift
private struct PreparedPage {
    let viewController: UIViewController
    let scrollView: UIScrollView
}

private func fallbackPageHost(
    for childViewController: UIViewController,
    activeFallbackHostIdentifiers: inout Set<ObjectIdentifier>
) -> AnchorPagerPageScrollHostViewController {
    let childIdentifier = ObjectIdentifier(childViewController)
    activeFallbackHostIdentifiers.insert(childIdentifier)
    if let existingHost = fallbackPageHosts[childIdentifier] {
        return existingHost
    }

    let host = AnchorPagerPageScrollHostViewController(
        contentViewController: childViewController
    )
    fallbackPageHosts[childIdentifier] = host
    return host
}

private func preparePage(
    for childViewController: UIViewController,
    claimedScrollViews: inout Set<ObjectIdentifier>,
    activeFallbackHostIdentifiers: inout Set<ObjectIdentifier>
) -> PreparedPage {
    childViewController.loadViewIfNeeded()

    if let resolved = childViewController.anchorPagerScrollView,
       claimedScrollViews.insert(ObjectIdentifier(resolved)).inserted {
        return PreparedPage(viewController: childViewController, scrollView: resolved)
    }

    if childViewController.anchorPagerScrollView != nil {
        AnchorPagerAssertions.failure("AnchorPager pages must not share a scroll view.")
        AnchorPagerLogger.log(.debug, category: .inset, event: "inset.targetCollision")
        if let defaultScrollView = childViewController.anchorPagerDefaultScrollView,
           claimedScrollViews.insert(ObjectIdentifier(defaultScrollView)).inserted {
            return PreparedPage(
                viewController: childViewController,
                scrollView: defaultScrollView
            )
        }
    }

    let fallbackHost = fallbackPageHost(
        for: childViewController,
        activeFallbackHostIdentifiers: &activeFallbackHostIdentifiers
    )
    fallbackHost.loadViewIfNeeded()
    claimedScrollViews.insert(ObjectIdentifier(fallbackHost.scrollView))
    return PreparedPage(
        viewController: fallbackHost,
        scrollView: fallbackHost.scrollView
    )
}
```

测试关闭 assertion 后构造两个 page 声明同一显式 scroll view，断言第二个 page 使用 default lookup 或 fallback，并收到 `inset.targetCollision`。

在 fallback host `loadViewIfNeeded()` 后读取其 `scrollView`；不得让 managed coordinator 重新执行 view hierarchy discovery。

- [x] **Step 7: 应用和归还 ownership**

结构性 layout 获得 barInsets 和 local bottom obstruction 后构造：

```swift
let target = AnchorPagerManagedInsetCoordinator.Target(
    content: UIEdgeInsets(
        top: resolvedBarInsets.top,
        left: 0,
        bottom: environment.obstruction.bottom,
        right: 0
    ),
    indicators: UIEdgeInsets(
        top: 0,
        left: 0,
        bottom: environment.obstruction.bottom,
        right: 0
    )
)
```

只对 target 变化或 active scroll 集合变化调用 coordinator。reload 时在 Tabman 完成新页面装配后 release stale scroll views。ViewController 释放路径固定为：

```swift
deinit {
    MainActor.assumeIsolated {
        managedInsetCoordinator.releaseAll()
    }
    AnchorPagerLogger.log(.info, category: .lifecycle, event: "deinit")
}
```

Swift 6 将 `deinit` 按 nonisolated 上下文检查；这里依赖 UIKit 生命周期必须位于主线程的约束，
用 `MainActor.assumeIsolated` 同步归还。不得使用 `nonisolated(unsafe)`、异步 Task、延迟归还或
unchecked Sendable 绕过释放顺序。

- [x] **Step 8: 运行 Task 4 GREEN 和回归测试**

Run: Task 4 RED 的同一命令。

Expected: `AnchorPagerViewControllerTests` 全部通过。

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-core-green test
```

Expected: package 全部测试通过；旧 v0.2 Header/bounce/layout tests 无回归。

- [x] **Step 9: 自审并提交 Task 4**

重点检查：Tabman/Pageboy containment 未改；scroll discovery 只在 reload 安全点发生；fallback containment 顺序不变；热路径不写 inset/不改变 paging height；bar callback 幂等；stale ownership 可释放；日志不逐帧输出。

```bash
git diff --check
git add Sources/AnchorPager/Public/AnchorPagerConfiguration.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Sources/AnchorPager/Children/AnchorPagerPageScrollHostViewController.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "接入子页面插入量管理"
```

Task 4 验证记录：

- RED：控制器测试 41 项中 6 项按预期失败，覆盖默认高度、固定 viewport、managed inset、reload 与 target collision；修正两处 weak data source 测试夹具后进入实现。
- GREEN：`AnchorPagerViewControllerTests` 原 41 项全部通过；新增 deinit ownership 用例单独通过。
- 回归：package 全量 99 项先得到 98 项通过，唯一失败为 Public DocC 出现第三方库名称；修正后对应架构守卫测试通过，最终全量将在 Task 6 再执行一次。
- 自审：Public API 仅把 `bar.height` 改为可选 `CGFloat?`，未泄漏第三方类型；Tabman/Pageboy containment 未改；scroll discovery 只发生在 reload；stale/deinit ownership 均同步归还；滚动热路径不写 inset、不改变 adapter 高度；fallback containment 顺序保持不变。

---

### Task 5: 示例可视路径与接入文档

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`

**Interfaces:**
- Consumes: v0.3 public optional bar height 和真实 managed inset 行为。
- Produces: 可重复 UI 验收入口、接入限制说明和真实版本状态。

- [x] **Step 1: 写真实列表/fallback UI 失败测试**

给示例内容增加稳定 identifier 的测试期望：

```swift
@MainActor
func testAdaptiveBarKeepsRealScrollAndFallbackPagesVisible() throws {
    let app = XCUIApplication()
    app.launch()

    let firstRow = app.staticTexts["scroll-page-first-row"]
    XCTAssertTrue(firstRow.waitForExistence(timeout: 3))

    app.descendants(matching: .any)["无滚动页"].tap()
    XCTAssertTrue(app.staticTexts["plain-page-content"].waitForExistence(timeout: 3))
}
```

- [x] **Step 2: 运行 Task 5 UI RED**

Run:

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-v03-ui-red -parallel-testing-enabled NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testAdaptiveBarKeepsRealScrollAndFallbackPagesVisible test
```

Expected: FAIL，示例内容还没有两个 accessibility identifier。

- [x] **Step 3: 增加示例 identifiers 并保持默认 adaptive bar**

第一条真实 scroll row：

```swift
if row == 0 {
    label.accessibilityIdentifier = "scroll-page-first-row"
}
```

plain page 内容 label：

```swift
label.accessibilityIdentifier = "plain-page-content"
```

示例不设置 `configuration.bar.height`，用于持续覆盖默认 nil/Tabman adaptive 路径。

- [x] **Step 4: 更新 README 和 architecture**

README 增加：

```swift
var configuration = AnchorPagerConfiguration.default
configuration.bar.height = nil // 默认：使用 Tabman bar 自适应高度
configuration.bar.height = 56  // 可选：显式覆盖
```

明确：child managed top 只等于实际 Tabman bar obstruction；Header/safe area 由 adapter frame 处理；调用方修改外部 inset 时应基于当前总 inset增量修改；页面移除后 AnchorPager 归还 managed 部分和 adjustment behavior。

architecture 把“v0.3 已批准后续架构”更新为已实现状态，记录 fixed adapter、public `barInsets`、weak ownership、fallback 统一规则和 v0.4/v0.5 remaining limitations。

task-list 只勾选 Task 1–5 已有代码和测试证据的条目。

- [x] **Step 5: 运行示例 build 和完整 UI tests**

Run:

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild-v03 build
```

Expected: BUILD SUCCEEDED。

Run:

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-v03-ui -parallel-testing-enabled NO test
```

Expected: 示例单元测试和 UI tests 全部通过。

- [x] **Step 6: 自审并提交 Task 5**

检查示例没有依赖 internal API；README 没有提前宣称 v0.4/v0.5；UI test 同时覆盖真实 scroll 和 fallback；文档记录 optional default 的 public API 变化。

```bash
git diff --check
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift README.md docs/architecture.md docs/task-list.md
git commit -m "补充插入量示例与接入文档"
```

Task 5 验证记录：

- UI RED：新增用例因缺少 `scroll-page-first-row` 与 `plain-page-content` 按预期失败。
- UI GREEN：补充 identifier 后目标用例通过，示例保持默认 nil/adaptive bar。
- 示例 build：generic iOS Simulator build 通过。
- 完整示例测试：复用 `iPhone 17 Pro` 与 `.build/example-xcodebuild-v03-ui`，全部单元测试和 UI tests 通过，测试阶段约 163 秒。
- 自审：示例未引用 internal API；README/architecture 已更新为 v0.3 真实状态；UI test 同时覆盖真实 scroll 与 fallback；v0.4/v0.5 能力仍保留为限制。

---

### Task 6: v0.3 最终验收与计划记录

**Files:**
- Modify: `docs/superpowers/plans/2026-07-11-v0-3-fixed-paging-inset-ownership.md`
- Modify: `docs/task-list.md`（仅在最终证据成立时补充验收状态）

**Interfaces:**
- Consumes: Task 1–5 的代码、测试、文档和提交。
- Produces: 可复核验证记录、自审结论和 v0.3 完成状态。

- [x] **Step 1: 运行静态与依赖验证**

```bash
git diff --check
swift package resolve
```

Expected: 两者 exit 0，依赖仍解析为 Tabman 4.0.1、Pageboy 5.0.2。

- [x] **Step 2: 运行 package 完整测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-final -parallel-testing-enabled NO -enableCodeCoverage NO test
```

Expected: 全部测试通过、0 failures。

- [x] **Step 3: 运行示例 build 与完整测试**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild-v03-final build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-v03-final-ui -parallel-testing-enabled NO -enableCodeCoverage NO test
```

Expected: build 成功；示例单元/UI tests 全部通过。

- [x] **Step 4: 执行源码与架构自审**

逐项记录：

1. Public API 只有 `CGFloat?` 变化，没有 Tabman/Pageboy 类型泄漏。
2. Tabman/Pageboy import 和类型引用只出现在 Paging 层；其他 internal 层仅允许用注释记录 containment 边界。
3. adapter containment、Header containment、fallback containment 顺序未破坏。
4. Pageboy child bounds 在 Header 折叠热路径稳定。
5. inset coordinator weak ownership、external 合成、归还和 offset 迁移闭环成立。
6. reload/deinit 不遗留 adjustment behavior 或 managed inset。
7. bar/inset 日志有 sink 测试且热路径不逐帧输出。
8. v0.4 page state 和 v0.5 handoff 没有被提前实现。
9. README、architecture、requirements、task-list、spec、plan 状态一致。

- [x] **Step 5: 更新计划 Self-review / Verification Record**

在本文末尾追加实际命令、测试数量、失败修复记录和自审结果。只有完整验证通过后才在 task-list 标记 v0.3 完成。

- [x] **Step 6: 提交最终验收记录**

```bash
git diff --check
git add docs/superpowers/plans/2026-07-11-v0-3-fixed-paging-inset-ownership.md docs/task-list.md
git commit -m "记录 v0.3 固定分页视口验收"
```

---

### Task 7: v0.3 Scroll Indicator Ownership 修复

**Files:**
- Modify: `Sources/AnchorPager/Children/AnchorPagerManagedInsetCoordinator.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `README.md`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md`

**Interfaces:**
- Consumes: `resolvedBarInsets.top`、`LayoutEnvironment.obstruction.bottom`、`AnchorPagerManagedInsetCoordinator.Target.indicators`。
- Produces: indicator top/bottom 单一 owner、`automaticallyAdjustsScrollIndicatorInsets` 同步接管与归还；不扩大 Public API。

- [ ] **Step 1: 写 indicator top 和自动调整所有权失败测试**

在 coordinator 测试中确认接管期间关闭、release 后恢复 UIKit 自动 indicator 调整：

```swift
scrollView.automaticallyAdjustsScrollIndicatorInsets = true
coordinator.apply(target, to: scrollView)
XCTAssertFalse(scrollView.automaticallyAdjustsScrollIndicatorInsets)
coordinator.release(scrollView)
XCTAssertTrue(scrollView.automaticallyAdjustsScrollIndicatorInsets)
```

在真实 window 的 ViewController 测试中给 child 设置 external indicator top/bottom，并断言：

```swift
XCTAssertEqual(child.scrollView.verticalScrollIndicatorInsets.top, 2 + 56, accuracy: 0.5)
XCTAssertEqual(
    child.scrollView.verticalScrollIndicatorInsets.bottom,
    5 + pager.view.safeAreaInsets.bottom,
    accuracy: 0.5
)
XCTAssertFalse(child.scrollView.automaticallyAdjustsScrollIndicatorInsets)
```

reload 替换页面后，旧 child 必须恢复 external indicator insets 和原始自动调整状态。

- [ ] **Step 2: 运行 Task 7 RED**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-indicator -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testManagedScrollIndicatorInsetsUseBarAndBottomObstruction -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadReleasesStaleInsetOwnershipAndManagesReplacement test
```

Expected: FAIL；当前 indicator top 仍为 external top，且 `automaticallyAdjustsScrollIndicatorInsets` 仍为 true。

- [ ] **Step 3: 实现 indicator 完整 ownership**

Coordinator record 增加：

```swift
let originalAutomaticallyAdjustsScrollIndicatorInsets: Bool
```

`apply` 的幂等条件同时检查自动 indicator 调整已关闭；写入 managed insets 前设置：

```swift
scrollView.contentInsetAdjustmentBehavior = .never
scrollView.automaticallyAdjustsScrollIndicatorInsets = false
```

`release` 在移除最后一次 managed indicator inset 后恢复原值。ViewController target 改为：

```swift
indicators: UIEdgeInsets(
    top: resolvedBarInsets.top,
    left: 0,
    bottom: environment.obstruction.bottom,
    right: 0
)
```

- [ ] **Step 4: 运行 Task 7 GREEN 与 package 回归**

先运行 Step 2 同一命令，Expected: PASS。再运行：

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-indicator -parallel-testing-enabled NO -enableCodeCoverage NO test
```

Expected: package 全部测试通过、0 failures。

- [ ] **Step 5: 运行示例可视回归**

UIKit 没有稳定 public API 暴露 indicator 私有 view frame，XCUITest 也不保证把滚动指示器作为 accessibility element；因此以真实 window 集成测试验证决定实际轨道的 top/bottom property 和自动调整 owner，再运行现有示例 UI 流程作为可视回归：

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-v03-indicator -parallel-testing-enabled NO -enableCodeCoverage NO test
```

Expected: 示例单元/UI tests 全部通过。

- [ ] **Step 6: 自审、更新状态并提交**

检查 indicator top 不越过 bar bottom、bottom 不重复 safe area、external indicator insets 保留、reload/deinit 恢复自动状态、滚动热路径不写 inset、Public API 和 containment 均未变化。验证完成后勾选 task-list 两项修复状态并追加真实命令记录。

```bash
git diff --check
git add Sources/AnchorPager/Children/AnchorPagerManagedInsetCoordinator.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift README.md docs/requirements.md docs/architecture.md docs/task-list.md docs/superpowers/specs/2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md docs/superpowers/plans/2026-07-11-v0-3-fixed-paging-inset-ownership.md
git commit -m "修复滚动指示器安全区避让"
```

---

## Self-review Record

- Task 1：`AnchorPagerLayoutEngine` 仍为只 import CoreGraphics 的纯计算类型；`pagingFrame.height` 只依赖 bounds、top obstruction 和 collapsed Header height，不依赖 contentOffset、bar height 或 bottom obstruction。旧容器级 managed target 与未落地的 target 日志已移除，Header、Tabman/Pageboy containment、selection 和 scroll discovery 未改变。
- Task 2：optional height 只作为 internal adapter 请求，尚未提前修改 public configuration；实际 TMBar 仍由 Paging 层创建和持有。nil 不安装高度约束，非 nil 复用单一 constraint；公开 `barInsets` 只在 sanitized value 变化时通过 UIKit `UIEdgeInsets` 回调，未向 Public/Layout 层泄漏 TMBar 或 Pageboy 类型。invalid height 和 barInsets 变化均有 sink 测试。
- Task 3：`AnchorPagerManagedInsetCoordinator` 与 nested Record 均为 MainActor；record 弱持有 UIScrollView，不阻止页面资源释放。apply/update/release 使用“current - previous managed + new managed”合成 external inset，并按 distance-from-top 迁移 offset；release 恢复原 adjustment behavior。日志只记录 begin/update/skip/end 稳定事件，没有几何或业务数据。
- Task 4：Public `bar.height` 已切换为 `CGFloat?` 且默认 nil；ViewController 使用 runtime `barInsets.top` 驱动 LayoutEngine 和 managed top。reload 先完成新页面装配再归还 stale ownership，deinit 通过主线程隔离断言同步 `releaseAll()`；fallback 内容高度扣除 managed top/bottom。Tabman/Pageboy page containment 未改。
- Task 5：示例保持默认 adaptive bar，真实 scroll/fallback 页面均有稳定 UI identifier 和可见性测试。README、architecture、requirements 与 task-list 已同步 v0.3 真实状态；requirements 中遗留的默认 48 契约在最终自审中修正为默认自适应。
- 最终源码自审：Public API 只有 optional `CGFloat?` 语义变化；第三方 import/类型只存在于 Paging；Header、adapter、fallback containment 顺序未破坏；fixed paging、weak ownership、external 合成、offset 迁移、reload/deinit 归还均有测试。v0.4 page state 与 v0.5 handoff 未提前实现。
- 计划覆盖 spec 中 v0.3 的 optional bar height、fixed adapter、barInsets callback、managed inset ownership、fallback、日志、文档和 UI test；v0.4/v0.5 只保留接口兼容边界，没有提前实现。
- Task 1 的 `barHeight` runtime 语义/`pagingFrame`、Task 2 的 `setBarHeight`/`didUpdateBarInsets`、Task 3 的 `Target`/apply/release 与 Task 4 的消费名称保持一致。
- 每个实现任务都有明确 RED、GREEN、定向命令、自审和中文提交；最终任务包含 package、example build 和 UI tests。
- 计划没有未决占位符；异常值、重复回调、target 冲突、ownership 释放和外部 inset 限制均有明确策略。

## Verification Record

- 计划编写阶段：`git diff --check` 通过。
- Task 1 RED：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-layout-red -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests test` 失败，核心错误为 `AnchorPagerLayoutEngine.Output` 没有 `pagingFrame`，符合测试先行预期。
- Task 1 GREEN：同一 LayoutEngine 定向测试命令通过。
- Task 1 回归：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-layout-green -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test` 通过。
- Task 2 RED：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-bar-red -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test` 失败，核心错误为 `AnchorPagerPagingAdapter` 没有 `setBarHeight`，符合测试先行预期。
- Task 2 GREEN：同一定向 PagingAdapter 测试命令通过。
- Task 2 日志 RED：移除 `paging.barInsetsChanged` 发射后，定向 `testExplicitBarHeightConstrainsActualTabmanBarAndReportsInsets` 失败；恢复最小日志实现后同一测试通过。
- Task 2 回归：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-bar-green -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test` 通过。
- Task 3 RED：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-inset-red -only-testing:AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests test` 失败，核心错误为找不到 `AnchorPagerManagedInsetCoordinator`，符合测试先行预期。
- Task 3 初次 GREEN：同一命令通过，但编译器报告 nested Record 读取 MainActor UIKit 属性的隔离警告。
- Task 3 最终 GREEN：显式标记 nested Record 为 MainActor 后，`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v03-inset-green -only-testing:AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests test` 通过且不再出现该 Swift 6 actor warning。
- Task 4 RED：`AnchorPagerViewControllerTests` 41 项中 6 项按预期失败，覆盖默认高度、fixed viewport、managed inset、reload 与 scroll target collision。
- Task 4 GREEN：原 41 项控制器测试全部通过；新增 deinit ownership 用例单独通过。首次 package 回归 99 项中 98 项通过，唯一失败为 Public DocC 出现第三方名称；修正后架构守卫定向测试通过。
- Task 5 UI RED：新增真实 scroll/fallback 可见性用例因缺少两个 identifier 按预期失败。
- Task 5 UI GREEN：目标用例通过；示例 generic build 通过；完整示例测试 14 项通过、0 failures，测试阶段约 163 秒。
- 最终静态验证：`git diff --check` 通过。`swift package resolve` 沙箱内首次因用户级 Clang module cache 不可写失败，按授权在沙箱外重跑后通过；`Package.resolved` 保持 Tabman 4.0.1、Pageboy 5.0.2。
- 最终 package：复用已启动的 `iPhone 17 Pro` 和 `.build/xcodebuild-v03-controller-red` 执行完整测试，99 项通过、0 failures、0 skipped，测试阶段约 35 秒。
- 最终示例证据：复用 Task 5 当前提交的 `.build/example-xcodebuild-v03-ui`；generic build 成功，完整示例单元/UI tests 14 项通过、0 failures、0 skipped。
- 最终文档审查：AGENTS 必读索引、README、architecture、requirements、task-list、spec 和 plan 已统一 optional bar height、fixed paging frame、managed inset ownership 与后续版本限制。
