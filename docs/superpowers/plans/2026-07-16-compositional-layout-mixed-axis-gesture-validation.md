# Compositional Layout 页面级横向分页策略 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 AnchorPager 增加按页面声明的交互式横向分页开关，让横向业务页与 Compositional Layout 混合轴页都关闭 Pageboy 横向拖拽、保留 Tabman bar/API 切页，并完成真实纵向、业务横向、正交横向、reload 与 lifecycle 验收。

**Architecture:** `AnchorPagerViewControllerDataSource` 通过带默认实现的逐页 Bool 提供策略；`AnchorPagerViewController` 把策略作为 reload metadata 采集，`AnchorPagerPagingHostViewController` 是唯一 committed policy owner，`AnchorPagerPagingAdapter` 只执行 Pageboy 自有 `isScrollEnabled` 开关。Interaction、Scroll、Overscroll、PageStateStore、业务 scroll/pan delegate 与 bounce ownership 均不增加新 owner。

**Tech Stack:** Swift 6.2、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、Tabman 4.0.1、Pageboy 5.0.2、`UICollectionViewCompositionalLayout`、XCTest/XCUITest、Xcode 26.6、iPhone 17 Pro / iOS 26.5 Simulator。

## Global Constraints

- 设计基线固定为 `docs/superpowers/specs/2026-07-16-compositional-layout-mixed-axis-gesture-validation-design.md`，二次修订确认提交为 `9408bc7`。
- 按用户要求继续在当前 `codex/v0-7-interaction-state` 分支工作，不创建 worktree。
- Public API 只新增 `pagerViewController(_:allowsInteractiveHorizontalPagingAt:) -> Bool`，并由 protocol extension 默认返回 `true`。
- `false` 只关闭 committed page 的 Pageboy 交互式横向拖拽；Tabman bar 和 `setSelectedIndex(_:animated:)` 必须继续可用。
- Example 的 index 4、index 5 固定返回 `false`；index 0...3 保持默认 `true`，不得依赖 index 4 位于分页末端掩盖手势竞争。
- 策略必须与 page count/title 使用同一 reload transaction token；不得从 page controller、scroll target、业务 view hierarchy 或 recognizer 推断。
- PagingHost 独占 committed policy、reload 与 selection transaction；Adapter 不保存策略 queue/generation，InteractionCoordinator 不保存 index/policy。
- Adapter 只设置 Pageboy 自有 `PageboyViewController.isScrollEnabled`；不得设置业务 child 的 scroll delegate、pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。
- 不增加 `pagingPan -> childPan` relation、hit-test guard、方向锁、recognizer reset、私有层级 discovery、KVC/private selector、异步 delay 或手工横向 offset 驱动。
- 根 `UICollectionView` 仍是组合布局页唯一 `anchorPagerScrollView`；orthogonal 内部 scroll 不进入 discovery、inset、snapshot、binding、overscroll 或 synthetic deceleration。
- Pageboy containment、selection semantic/completion/executor-ready、Store generation、appearance lifecycle、managed inset、纵向 handoff 与 interactive-pop relation 保持现有契约。
- 新 committed policy 状态使用固定 paging 日志，重复相同值不输出，高频 pan/layout handler 不逐帧记录。
- 每个任务严格执行 RED → 最小 GREEN → 聚焦回归 → 自审 → `git diff --check` → 中文单一主题提交。

---

## 当前执行检查点与证据

Task 1–5 已按原计划完成并提交：

```text
b2e6935 建立逐页横向分页策略元数据
c4dcf66 封装 Pageboy 交互分页开关
6dcd5bb 原子提交分页交互策略
db83bf3 按选择终态切换分页策略
77a04dd 接入组合布局页面级分页策略
```

Task 6 起点仅 `AnchorPagerExampleUITests.swift` 保留预期未提交改动。已确认的后续证据为：

1. Example target-level unit GREEN 为 18/18；Swift Testing 的 method-level `-only-testing` 会运行 0 tests，后续必须使用 target-level selector。
2. `/private/tmp/AnchorPagerTask6OrthogonalGreen-20260716-1520.xcresult` 中组合布局正交左右拖动通过。
3. `/private/tmp/AnchorPagerTask6PagePolicyGreen-20260716-1525.xcresult` 中原 index 5 页面级契约通过。
4. `/private/tmp/AnchorPagerTask6PagePolicyRegression-20260716-1527.xcresult` 为 4 pass、2 fail；horizontal-only 与 interactive-pop 需分别隔离复验。
5. `/private/tmp/AnchorPagerTask6HorizontalDiagnostic-20260716.xcresult` 精确证明 index 4 业务区域拖动提交了 index 5，终态为 `page=compositional`，而全部纵向 presentation 为零。

因此 Task 6 起按二次修订规格继续：先以单元 RED 让 index 4、index 5 都返回 `false`，再迁移真实 UI 契约；不得回退已经通过的 Framework Public/Host/Adapter 实现。

最终执行记录：Task 1–9 已全部完成，生产代码 HEAD `db4b9bc`。Framework 439/439、Example 70/70（19 单元 + 51 UI）与 generic Simulator build 全部通过，0 fail、0 skip、0 error/warning/analyzer warning；运行时问题关键字零命中，fresh-pass 终态 Critical 0、Important 0、Minor 0。上述“当前仅 UI 文件未提交”为 Task 6 起点快照，最终工作区已收口。

## 文件与职责

重点修改：

```text
Sources/AnchorPager/Public/AnchorPagerProtocols.swift
  - 定义带默认实现的逐页交互式横向分页策略。

Sources/AnchorPager/Public/AnchorPagerViewController.swift
  - 在 reload metadata transaction 中采集策略并传给 PagingHost。

Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift
  - 保存 active/latest reload payload 与唯一 committed policy snapshot；在 matching terminal 应用。

Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift
  - 封装 Pageboy 自有 isScrollEnabled 写入与幂等日志。

Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
  - 覆盖默认 API、metadata 顺序、reload 重入与 ViewController 集成。

Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift
  - 覆盖 acknowledged reload、stale terminal、selection commit/cancel 与 explicit selection。

Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift
  - 覆盖 Pageboy 开关、程序化选择、surface replacement 和业务 ownership 隔离。

Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift
  - 覆盖新固定日志事件与隐私边界。

Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift
  - 组合布局混合轴页面、正交进度 probe 与显示帧 sampler。

Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift
  - 第六页装配，对 index 4、index 5 返回 false，并修正横向业务页显式导航提示。

Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift
  - 覆盖第六页结构、策略、probe 与 sampler lifecycle。

Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
  - 覆盖纵向 handoff、业务/正交双向拖拽、非正交禁用、bar/API、index 3→4 target terminal 与 reload。
```

---

### Task 1：建立 Public 策略与 generation-aware metadata 采集

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerProtocols.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Consumes: 现有 `AnchorPagerViewControllerDataSource`、`ReloadSnapshot`、`reloadTransactionIdentifier` 与 Host reload request identifier。
- Produces: `pagerViewController(_:allowsInteractiveHorizontalPagingAt:) -> Bool`、`ReloadSnapshot.interactiveHorizontalPagingPermissions: [Bool]`、Host reload 参数 `interactiveHorizontalPagingPermissions: [Bool]?`。

- [ ] **Step 1：写默认兼容、显式策略与回调顺序 RED**

在 `AnchorPagerViewControllerTests` 新增：

```swift
@MainActor
func testInteractiveHorizontalPagingPolicyDefaultsToTrueAndIsCollectedByIndex() {
    let pager = AnchorPagerViewController()
    let legacy = LegacyPagingPolicyDataSource()
    XCTAssertTrue(
        legacy.pagerViewController(
            pager,
            allowsInteractiveHorizontalPagingAt: 0
        )
    )

    let dataSource = StubDataSource(
        count: 3,
        interactiveHorizontalPagingPermissions: [true, false, true]
    )
    pager.dataSource = dataSource
    pager.reloadData()

    XCTAssertEqual(dataSource.requestedInteractivePagingIndexes, [0, 1, 2])
}
```

为 `StubDataSource` 增加明确记录：

```swift
var interactiveHorizontalPagingPermissions: [Bool]
var requestedInteractivePagingIndexes: [Int] = []
var onInteractivePagingPermission: (() -> Void)?

init(
    count: Int,
    titles: [String]? = nil,
    viewControllers: [UIViewController]? = nil,
    headerContent: AnchorPagerHeaderContent = .view(UIView()),
    interactiveHorizontalPagingPermissions: [Bool]? = nil
) {
    self.count = count
    self.titles = titles ?? (0..<max(0, count)).map { "Page \($0)" }
    self.viewControllers = viewControllers
        ?? (0..<max(0, count)).map { _ in UIViewController() }
    self.headerContent = headerContent
    self.interactiveHorizontalPagingPermissions =
        interactiveHorizontalPagingPermissions
        ?? Array(repeating: true, count: max(0, count))
}

func pagerViewController(
    _ pagerViewController: AnchorPagerViewController,
    allowsInteractiveHorizontalPagingAt index: Int
) -> Bool {
    requestedInteractivePagingIndexes.append(index)
    let result = interactiveHorizontalPagingPermissions.indices.contains(index)
        ? interactiveHorizontalPagingPermissions[index]
        : true
    let hook = onInteractivePagingPermission
    onInteractivePagingPermission = nil
    hook?()
    return result
}

func resetCallbackRecords() {
    requestedViewControllerIndexes.removeAll()
    requestedTitleIndexes.removeAll()
    requestedInteractivePagingIndexes.removeAll()
    numberOfViewControllersCallCount = 0
    headerContentCallCount = 0
}
```

`LegacyPagingPolicyDataSource` 精确实现现有四个 required data source 方法，但不实现新方法，用来证明 protocol extension 保持源码兼容：

```swift
@MainActor
private final class LegacyPagingPolicyDataSource: AnchorPagerViewControllerDataSource {
    func numberOfViewControllers(
        in pagerViewController: AnchorPagerViewController
    ) -> Int {
        1
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        titleForViewControllerAt index: Int
    ) -> String {
        "Legacy"
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        viewControllerAt index: Int
    ) -> UIViewController {
        UIViewController()
    }

    func headerContent(
        in pagerViewController: AnchorPagerViewController
    ) -> AnchorPagerHeaderContent {
        .view(UIView())
    }
}
```

- [ ] **Step 2：写策略 callback 重入 RED**

```swift
@MainActor
func testReloadDataInteractivePagingPolicyCallbackReentryKeepsLatestSnapshot() throws {
    let pager = AnchorPagerViewController()
    let dataSource = StubDataSource(
        count: 2,
        titles: ["Outer 0", "Outer 1"],
        interactiveHorizontalPagingPermissions: [false, false]
    )
    pager.dataSource = dataSource
    pager.loadViewIfNeeded()
    dataSource.onInteractivePagingPermission = {
        dataSource.count = 1
        dataSource.titles = ["Latest"]
        dataSource.viewControllers = [UIViewController()]
        dataSource.interactiveHorizontalPagingPermissions = [true]
        pager.reloadData()
    }

    pager.reloadData()

    XCTAssertEqual(dataSource.requestedInteractivePagingIndexes, [0, 0])
    XCTAssertEqual(pager.effectiveSelectedIndex, 0)
}
```

- [ ] **Step 3：运行 RED**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testInteractiveHorizontalPagingPolicyDefaultsToTrueAndIsCollectedByIndex \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadDataInteractivePagingPolicyCallbackReentryKeepsLatestSnapshot test
```

预期：编译失败于新 data source 方法、Stub 初始化参数和 metadata 字段不存在。

- [ ] **Step 4：实现 Public 默认方法**

在 `AnchorPagerProtocols.swift` 增加：

```swift
public protocol AnchorPagerViewControllerDataSource: AnyObject {
    // 现有方法保持不变。
    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        allowsInteractiveHorizontalPagingAt index: Int
    ) -> Bool
}

public extension AnchorPagerViewControllerDataSource {
    /// 返回指定页面是否允许通过横向拖拽进行交互式分页。
    ///
    /// 返回 `false` 只关闭该页面的横向拖拽分页；分段栏和
    /// `setSelectedIndex(_:animated:)` 仍可切换页面。默认返回 `true`。
    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        allowsInteractiveHorizontalPagingAt index: Int
    ) -> Bool {
        true
    }
}
```

- [ ] **Step 5：把策略采集接入同一 reload token**

在 `ReloadSnapshot` 增加：

```swift
let interactiveHorizontalPagingPermissions: [Bool]
```

把 title 循环改为同 index 采集：

```swift
var resolvedTitles: [String] = []
var resolvedInteractiveHorizontalPagingPermissions: [Bool] = []
resolvedTitles.reserveCapacity(resolvedPageCount)
resolvedInteractiveHorizontalPagingPermissions.reserveCapacity(resolvedPageCount)
for index in 0..<resolvedPageCount {
    let title = reloadDataSource?.pagerViewController(
        self,
        titleForViewControllerAt: index
    ) ?? ""
    guard isCurrentReloadTransaction(transactionIdentifier) else { return }
    let allowsInteractivePaging = reloadDataSource?.pagerViewController(
        self,
        allowsInteractiveHorizontalPagingAt: index
    ) ?? true
    guard isCurrentReloadTransaction(transactionIdentifier) else { return }
    resolvedTitles.append(title)
    resolvedInteractiveHorizontalPagingPermissions.append(allowsInteractivePaging)
}
```

构造 snapshot 时保存数组，并在 `submitStagedReloadIfNeeded()` 传给 Host：

```swift
pagingHost.reload(
    requestIdentifier: snapshot.requestIdentifier,
    titles: snapshot.titles,
    pageCount: snapshot.pageCount,
    selectedIndex: snapshot.selectedIndex,
    interactiveHorizontalPagingPermissions:
        snapshot.interactiveHorizontalPagingPermissions
)
```

Host reload 签名增加可空数组参数，为现有 internal tests 保留默认参数；`ReloadRequest` 内部始终保存非可空数组：

```swift
private struct ReloadRequest {
    let identifier: AnchorPagerPagingReloadRequestIdentifier
    let titles: [String]
    let pageCount: Int
    let selectedIndex: Int
    let interactiveHorizontalPagingPermissions: [Bool]
}

func reload(
    requestIdentifier: AnchorPagerPagingReloadRequestIdentifier,
    titles: [String],
    pageCount: Int,
    selectedIndex: Int,
    interactiveHorizontalPagingPermissions: [Bool]? = nil
)
```

构造 request 前只解析缺省值，显式数组仍原样保留：

```swift
let resolvedPermissions = interactiveHorizontalPagingPermissions
    ?? Array(repeating: true, count: max(0, pageCount))
let request = ReloadRequest(
    identifier: requestIdentifier,
    titles: titles,
    pageCount: pageCount,
    selectedIndex: selectedIndex,
    interactiveHorizontalPagingPermissions: resolvedPermissions
)
```

Task 3 再收口显式数组的长度校验与 committed 应用。

- [ ] **Step 6：运行 GREEN 与相邻 reload 重入回归**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testInteractiveHorizontalPagingPolicyDefaultsToTrueAndIsCollectedByIndex \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadDataInteractivePagingPolicyCallbackReentryKeepsLatestSnapshot \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadDataTitleCallbackReentryKeepsLatestTransactionSnapshot \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadDataHeaderCallbackReentryKeepsLatestTransactionSnapshot test
```

预期：4/4 PASS；旧 transaction 的部分策略采集不发布。

- [ ] **Step 7：自审并提交**

检查新方法不含 Tabman/Pageboy 类型、默认值只有一处、策略采集不加载页面。运行 `git diff --check`。

```bash
git add Sources/AnchorPager/Public/AnchorPagerProtocols.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "建立逐页横向分页策略元数据"
```

---

### Task 2：封装 Adapter 的 Pageboy 交互分页开关与日志

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**
- Consumes: Pageboy 5.0.2 public `PageboyViewController.isScrollEnabled`。
- Produces: internal `setInteractiveHorizontalPagingEnabled(_:)`，固定日志 `paging.interactivePaging.enabled/disabled`。

- [ ] **Step 1：写 Adapter ownership 与幂等日志 RED**

```swift
func testInteractivePagingSwitchOnlyChangesPageboySurfaceAndLogsTransitions() throws {
    let adapter = AnchorPagerPagingAdapter()
    let page = ScrollPageViewController()
    reload(adapter, titles: ["Page"], viewControllers: [page], selectedIndex: 0)
    adapter.loadViewIfNeeded()
    let surface = try XCTUnwrap(adapter.pagingSurface)
    let businessScrollDelegate = page.scrollView.delegate
    let businessPanDelegate = page.scrollView.panGestureRecognizer.delegate
    var events: [AnchorPagerLogger.Event] = []
    AnchorPagerLogger.sink = { events.append($0) }
    defer { AnchorPagerLogger.sink = nil }

    adapter.setInteractiveHorizontalPagingEnabled(false)
    adapter.setInteractiveHorizontalPagingEnabled(false)

    XCTAssertFalse(adapter.isScrollEnabled)
    XCTAssertFalse(surface.scrollView.isScrollEnabled)
    XCTAssertTrue(page.scrollView.isScrollEnabled)
    XCTAssertTrue(page.scrollView.delegate === businessScrollDelegate)
    XCTAssertTrue(page.scrollView.panGestureRecognizer.delegate === businessPanDelegate)
    XCTAssertEqual(
        events.filter { $0.event == "paging.interactivePaging.disabled" }.count,
        1
    )

    adapter.setInteractiveHorizontalPagingEnabled(true)
    XCTAssertTrue(adapter.isScrollEnabled)
    XCTAssertTrue(surface.scrollView.isScrollEnabled)
    XCTAssertEqual(
        events.filter { $0.event == "paging.interactivePaging.enabled" }.count,
        1
    )
}
```

- [ ] **Step 2：写 disabled 状态程序化选择 RED**

```swift
func testProgrammaticSelectionStillExecutesWhileInteractivePagingIsDisabled() {
    let adapter = AnchorPagerPagingAdapter()
    reload(
        adapter,
        titles: ["A", "B"],
        viewControllers: [UIViewController(), UIViewController()],
        selectedIndex: 0
    )
    adapter.setInteractiveHorizontalPagingEnabled(false)
    let request = selectionRequest(
        identifier: 71,
        targetIndex: 1,
        animated: false
    )

    XCTAssertTrue(adapter.executeSelection(request, previousIndex: 0))
}
```

- [ ] **Step 3：运行 RED**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests/testInteractivePagingSwitchOnlyChangesPageboySurfaceAndLogsTransitions \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests/testProgrammaticSelectionStillExecutesWhileInteractivePagingIsDisabled test
```

预期：编译失败于 `setInteractiveHorizontalPagingEnabled` 不存在。

- [ ] **Step 4：实现最小 Adapter 入口**

```swift
func setInteractiveHorizontalPagingEnabled(_ isEnabled: Bool) {
    guard isScrollEnabled != isEnabled else { return }
    isScrollEnabled = isEnabled
    AnchorPagerLogger.log(
        .info,
        category: .paging,
        event: isEnabled
            ? "paging.interactivePaging.enabled"
            : "paging.interactivePaging.disabled"
    )
}
```

不得遍历 page subtree；Pageboy 在内部 page view controller 创建时会根据 stored `isScrollEnabled` 重放到 paging surface。

- [ ] **Step 5：在 Logger tests 固定事件隐私**

```swift
func testInteractivePagingLogsUseFixedPagingEventsWithoutPageMetadata() {
    let adapter = AnchorPagerPagingAdapter()
    var events: [AnchorPagerLogger.Event] = []
    AnchorPagerLogger.sink = { events.append($0) }
    defer { AnchorPagerLogger.sink = nil }

    adapter.setInteractiveHorizontalPagingEnabled(false)
    adapter.setInteractiveHorizontalPagingEnabled(true)

    XCTAssertEqual(
        events.map(\.event),
        ["paging.interactivePaging.disabled", "paging.interactivePaging.enabled"]
    )
    XCTAssertTrue(events.allSatisfy { $0.category == .paging })
}
```

- [ ] **Step 6：运行 GREEN、Adapter 全量和源码 ownership 扫描**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
rg -n '\.(delegate|bounces|alwaysBounceVertical)\s*=|scrollView\.isScrollEnabled\s*=' Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift
```

预期：Adapter + Logger 全部 PASS；源码只出现 Pageboy 继承属性 `isScrollEnabled = isEnabled`，不出现业务 page scroll 写入。

- [ ] **Step 7：自审并提交**

```bash
git diff --check
git add Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift
git commit -m "封装 Pageboy 交互分页开关"
```

---

### Task 3：让 PagingHost 原子提交 reload 策略

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `ReloadRequest.interactiveHorizontalPagingPermissions` 与 Task 2 Adapter 入口。
- Produces: Host 唯一 `committedInteractiveHorizontalPagingPermissions`，matching acknowledged reload 后的策略应用与 invalid metadata 降级。

- [ ] **Step 1：写 acknowledged reload、pending 与 stale terminal RED**

```swift
func testReloadAppliesInteractivePagingPolicyOnlyAfterAcknowledgedTerminal() throws {
    let host = makeHost()
    let delegate = RecordingRequestPagingHostDelegate()
    host.eventDelegate = delegate
    host.reload(
        requestIdentifier: 1,
        titles: ["A", "B"],
        pageCount: 2,
        selectedIndex: 0,
        interactiveHorizontalPagingPermissions: [true, false]
    )
    let adapter = try XCTUnwrap(host.activeAdapter)
    XCTAssertTrue(adapter.isScrollEnabled)

    host.setDeferredWorkExecutionSuspended(true)
    host.reload(
        requestIdentifier: 2,
        titles: ["A", "B"],
        pageCount: 2,
        selectedIndex: 1,
        interactiveHorizontalPagingPermissions: [true, false]
    )
    XCTAssertTrue(adapter.isScrollEnabled)

    host.setDeferredWorkExecutionSuspended(false)
    XCTAssertTrue(host.performPendingReloadIfPossible())
    XCTAssertFalse(adapter.isScrollEnabled)

    host.pagingAdapter(
        adapter,
        didReloadAt: 0,
        terminalBarInsets: .zero,
        requestIdentifier: 1
    )
    XCTAssertFalse(adapter.isScrollEnabled)
}
```

新增 rejected acknowledgement 用例：

```swift
func testRejectedReloadTerminalDoesNotPublishInteractivePagingPolicy() throws {
    let host = makeHost()
    let delegate = RecordingRequestPagingHostDelegate()
    host.eventDelegate = delegate
    host.reload(
        requestIdentifier: 1,
        titles: ["A"],
        pageCount: 1,
        selectedIndex: 0,
        interactiveHorizontalPagingPermissions: [true]
    )
    let adapter = try XCTUnwrap(host.activeAdapter)
    delegate.terminalAcknowledgements[2] = false

    host.reload(
        requestIdentifier: 2,
        titles: ["A"],
        pageCount: 1,
        selectedIndex: 0,
        interactiveHorizontalPagingPermissions: [false]
    )

    XCTAssertTrue(adapter.isScrollEnabled)

    host.reload(
        requestIdentifier: 3,
        titles: ["A"],
        pageCount: 1,
        selectedIndex: 0,
        interactiveHorizontalPagingPermissions: [false]
    )
    XCTAssertFalse(adapter.isScrollEnabled)
}
```

同时固定 empty teardown 与 Adapter replacement：

```swift
func testEmptyReloadClearsInteractivePolicyBeforeReplacementAdapter() throws {
    let host = makeHost()
    host.reload(
        requestIdentifier: 1,
        titles: ["A"],
        pageCount: 1,
        selectedIndex: 0,
        interactiveHorizontalPagingPermissions: [false]
    )
    let oldAdapter = try XCTUnwrap(host.activeAdapter)
    XCTAssertFalse(oldAdapter.isScrollEnabled)

    host.reload(
        requestIdentifier: 2,
        titles: [],
        pageCount: 0,
        selectedIndex: 0,
        interactiveHorizontalPagingPermissions: []
    )
    XCTAssertNil(host.activeAdapter)

    host.reload(
        requestIdentifier: 3,
        titles: ["Replacement"],
        pageCount: 1,
        selectedIndex: 0
    )
    XCTAssertTrue(try XCTUnwrap(host.activeAdapter).isScrollEnabled)
}
```

- [ ] **Step 2：写 invalid metadata RED**

```swift
func testInvalidInteractivePagingMetadataFailsClosedAndLogsOnce() throws {
    let host = makeHost()
    var events: [AnchorPagerLogger.Event] = []
    AnchorPagerLogger.sink = { events.append($0) }
    defer { AnchorPagerLogger.sink = nil }

    AnchorPagerAssertions.$isEnabled.withValue(false) {
        host.reload(
            requestIdentifier: 7,
            titles: ["A", "B"],
            pageCount: 2,
            selectedIndex: 0,
            interactiveHorizontalPagingPermissions: [true]
        )
    }

    XCTAssertFalse(try XCTUnwrap(host.activeAdapter).isScrollEnabled)
    XCTAssertEqual(
        events.filter { $0.event == "paging.interactivePaging.invalidMetadata" }.count,
        1
    )
}
```

- [ ] **Step 3：运行 RED**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests/testReloadAppliesInteractivePagingPolicyOnlyAfterAcknowledgedTerminal \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests/testRejectedReloadTerminalDoesNotPublishInteractivePagingPolicy \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests/testEmptyReloadClearsInteractivePolicyBeforeReplacementAdapter \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests/testInvalidInteractivePagingMetadataFailsClosedAndLogsOnce test
```

预期：策略仍未被 Host committed/apply，两个测试失败。

- [ ] **Step 4：实现长度校验和 committed snapshot**

在 Host 增加：

```swift
private var committedInteractiveHorizontalPagingPermissions: [Bool] = []

private func resolvedInteractiveHorizontalPagingPermissions(
    _ permissions: [Bool],
    pageCount: Int
) -> [Bool] {
    guard permissions.count == max(0, pageCount) else {
        AnchorPagerAssertions.failure(
            "AnchorPager interactive paging metadata must match page count."
        )
        AnchorPagerLogger.log(
            .error,
            category: .paging,
            event: "paging.interactivePaging.invalidMetadata"
        )
        return Array(repeating: false, count: max(0, pageCount))
    }
    return permissions
}
```

在构造 `ReloadRequest` 时只调用一次该函数。`finishActiveReload` 的 `didCommitTerminal == true` 分支中：

```swift
committedInteractiveHorizontalPagingPermissions =
    request.interactiveHorizontalPagingPermissions
switch terminal {
case let .page(index):
    committedSelectionIndex = index
    committedSelectionPageCount = request.pageCount
    applyCommittedInteractivePagingPolicy(to: activeAdapter, at: index)
case .empty:
    committedSelectionIndex = nil
    committedSelectionPageCount = 0
    committedInteractiveHorizontalPagingPermissions = []
}
```

增加唯一应用 helper：

```swift
private func applyCommittedInteractivePagingPolicy(
    to adapter: AnchorPagerPagingAdapter?,
    at index: Int
) {
    guard let adapter else { return }
    guard committedInteractiveHorizontalPagingPermissions.indices.contains(index) else {
        adapter.setInteractiveHorizontalPagingEnabled(false)
        return
    }
    adapter.setInteractiveHorizontalPagingEnabled(
        committedInteractiveHorizontalPagingPermissions[index]
    )
}
```

- [ ] **Step 5：运行 GREEN 与 reload terminal 全量回归**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests test
```

预期：Host tests 全部 PASS；empty teardown、latest reload、bar baseline 与 terminal acknowledgement 无回归。

- [ ] **Step 6：自审并提交**

确认 pending/stale/rejected terminal 零策略写入，empty 清空，Adapter replacement 通过 matching reload terminal 重放。

```bash
git diff --check
git add Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift
git commit -m "原子提交分页交互策略"
```

---

### Task 4：把 selection terminal 与 explicit selection 接入 committed 策略

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`

**Interfaces:**
- Consumes: Host matching selection transaction 与 committed policy snapshot。
- Produces: did-select/recovery 先应用 target policy、cancel 保持 source、disabled source 仍允许 API/bar transaction。

- [ ] **Step 1：写 enabled→disabled commit ordering RED**

为 `RecordingPagingHostDelegate` 增加 `onDidSelect` 内读取 `host.activeAdapter?.isScrollEnabled`，并新增：

```swift
func testInteractiveDidSelectAppliesTargetPolicyBeforeForwardingPublicCommit() throws {
    let host = makeHost()
    let delegate = RecordingPagingHostDelegate()
    host.eventDelegate = delegate
    host.reload(
        requestIdentifier: 1,
        titles: ["A", "B"],
        pageCount: 2,
        selectedIndex: 0,
        interactiveHorizontalPagingPermissions: [true, false]
    )
    let adapter = try XCTUnwrap(host.activeAdapter)
    var observedPolicyDuringCommit: Bool?
    delegate.onDidSelect = { host, _, _ in
        observedPolicyDuringCommit = host.activeAdapter?.isScrollEnabled
    }
    let identifier = try XCTUnwrap(host.pagingAdapter(
        adapter,
        didBeginInteractiveSelectionAt: 1,
        animated: true
    ))
    host.pagingAdapter(
        adapter,
        didSelect: 1,
        animated: true,
        requestIdentifier: identifier
    )

    XCTAssertEqual(observedPolicyDuringCommit, false)
    XCTAssertFalse(adapter.isScrollEnabled)
}
```

- [ ] **Step 2：写 cancel、missing-semantic 和 explicit exit RED**

```swift
func testInteractiveCancelKeepsCommittedSourcePagingPolicy() throws {
    let host = makeHost()
    host.reload(
        requestIdentifier: 1,
        titles: ["A", "B"],
        pageCount: 2,
        selectedIndex: 0,
        interactiveHorizontalPagingPermissions: [true, false]
    )
    let adapter = try XCTUnwrap(host.activeAdapter)
    let identifier = try XCTUnwrap(host.pagingAdapter(
        adapter,
        didBeginInteractiveSelectionAt: 1,
        animated: true
    ))
    host.pagingAdapter(
        adapter,
        didCancelSelectionAt: 1,
        returningTo: 0,
        requestIdentifier: identifier
    )
    XCTAssertTrue(adapter.isScrollEnabled)
}

func testMissingSemanticRecoveryAppliesCommittedTargetPagingPolicy() throws {
    let host = makeHost()
    host.reload(
        requestIdentifier: 1,
        titles: ["A", "B"],
        pageCount: 2,
        selectedIndex: 0,
        interactiveHorizontalPagingPermissions: [true, false]
    )
    let adapter = try XCTUnwrap(host.activeAdapter)

    adapter.handleDidSelect(at: 1, animated: true, reportedCurrentIndex: 1)

    XCTAssertFalse(adapter.isScrollEnabled)
}

func testDisabledPageStillAllowsAPIAndBarSelections() throws {
    let apiHost = makeHost()
    apiHost.reload(
        requestIdentifier: 1,
        titles: ["A", "B"],
        pageCount: 2,
        selectedIndex: 1,
        interactiveHorizontalPagingPermissions: [true, false]
    )
    let apiAdapter = try XCTUnwrap(apiHost.activeAdapter)
    XCTAssertFalse(apiAdapter.isScrollEnabled)
    XCTAssertTrue(apiHost.setSelectedIndex(0, animated: false))
    let apiIdentifier = try XCTUnwrap(
        apiHost.activeSelectionRequestForTesting?.identifier
    )
    apiHost.pagingAdapter(
        apiAdapter,
        didComplete: apiIdentifier,
        finished: true,
        currentIndex: 0
    )
    XCTAssertTrue(apiAdapter.isScrollEnabled)
    apiHost.pagingAdapter(
        apiAdapter,
        executorDidBecomeReadyFor: apiIdentifier
    )
    XCTAssertNil(apiHost.activeSelectionRequestForTesting)

    let barHost = makeHost()
    barHost.reload(
        requestIdentifier: 2,
        titles: ["A", "B"],
        pageCount: 2,
        selectedIndex: 1,
        interactiveHorizontalPagingPermissions: [true, false]
    )
    let barAdapter = try XCTUnwrap(barHost.activeAdapter)
    barHost.pagingAdapter(barAdapter, didRequestBarSelectionAt: 0)
    let barRequest = try XCTUnwrap(barHost.activeSelectionRequestForTesting)
    XCTAssertEqual(barRequest.targetIndex, 0)
    barHost.pagingAdapter(
        barAdapter,
        didComplete: barRequest.identifier,
        finished: true,
        currentIndex: 0
    )
    XCTAssertTrue(barAdapter.isScrollEnabled)
    barHost.pagingAdapter(
        barAdapter,
        executorDidBecomeReadyFor: barRequest.identifier
    )
    XCTAssertNil(barHost.activeSelectionRequestForTesting)
}
```

- [ ] **Step 3：运行 RED**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests/testInteractiveDidSelectAppliesTargetPolicyBeforeForwardingPublicCommit \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests/testInteractiveCancelKeepsCommittedSourcePagingPolicy \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests/testMissingSemanticRecoveryAppliesCommittedTargetPagingPolicy \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests/testDisabledPageStillAllowsAPIAndBarSelections test
```

预期：reload policy 已可应用，但 selection terminal 尚未切换 target policy，至少前三项失败。

- [ ] **Step 4：统一 selection commit helper**

在 Host 增加：

```swift
private func commitSelection(
    _ index: Int,
    on adapter: AnchorPagerPagingAdapter
) {
    committedSelectionIndex = index
    applyCommittedInteractivePagingPolicy(to: adapter, at: index)
}
```

matching did-select 中替换直接 index 写入：

```swift
activeSelectionTransaction = transaction
commitSelection(index, on: adapter)
eventDelegate?.pagingHost(self, didSelect: index, animated: animated)
finishActiveSelectionIfReady()
```

`forwardRecoveredSelectionTerminal` 增加 `adapter` 参数，并在 `.selected(index:)` 走同一 helper；`.cancelled` 不调用 helper，不修改 committed policy。

- [ ] **Step 5：运行 GREEN 与 selection/reload 相邻回归**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

预期：Host + Adapter 全部 PASS；semantic/completion/executor-ready、active/latest、reload-first 与 structural cancel 顺序不变。

- [ ] **Step 6：自审并提交**

```bash
git diff --check
git add Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift
git commit -m "按选择终态切换分页策略"
```

---

### Task 5：让 Example 第六页声明 false 并完成单元契约

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Verify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift`

**Interfaces:**
- Consumes: Task 1 Public data source 方法。
- Produces: 首轮 index 5 为 `false`、index 0...4 为默认 `true`；根 CollectionView 仍是唯一纵向 target。Task 6 根据二次修订规格继续把 index 4 改为 `false`。

- [ ] **Step 1：收紧 Example 策略 RED**

在 `compositionalPageIsSixthAndUsesRootCollectionAsVerticalTarget()` 增加：

```swift
#expect(
    pager.dataSource?.pagerViewController(
        pager,
        allowsInteractiveHorizontalPagingAt: 5
    ) == false
)
for index in 0..<5 {
    #expect(
        pager.dataSource?.pagerViewController(
            pager,
            allowsInteractiveHorizontalPagingAt: index
        ) == true
    )
}
```

- [ ] **Step 2：运行 RED**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests test
```

预期：18 tests 中组合布局策略断言失败，index 5 仍继承默认 `true`。Swift Testing method-level selector 在当前工具链运行 0 tests，因此固定使用 target-level selector。

- [ ] **Step 3：实现 Example data source 策略**

```swift
func pagerViewController(
    _ pagerViewController: AnchorPagerViewController,
    allowsInteractiveHorizontalPagingAt index: Int
) -> Bool {
    index != 5
}
```

不得把策略写入 `ExampleCompositionalPageViewController`，也不得修改其 root collection/pan/bounce 配置。

- [ ] **Step 4：运行 Example unit GREEN 与 Framework Public 回归**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests test
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests test
```

预期：Example unit 全部 PASS；Framework ViewController/Host 回归全部 PASS。

- [ ] **Step 5：自审并提交 Example 页面与结构测试**

检查新页面文件的 layout handler weak capture、root target、appearance callback、display link invalidate 和 accessibility probe；确认 Xcode filesystem-synchronized group 自动纳入文件。

```bash
git diff --check
git add Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift
git commit -m "接入组合布局页面级分页策略"
```

---

### Task 6：让横向业务页与组合布局页统一声明 false

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: Task 1 的 `pagerViewController(_:allowsInteractiveHorizontalPagingAt:) -> Bool` 与 Task 4 的 matching target terminal 策略切换。
- Produces: index 4、index 5 为 `false`，index 0...3 为 `true`；横向业务页不再依赖 Pageboy 末端边界，页面提示不再承诺不可用的区域分页手势。

- [ ] **Step 1：写双页面策略、提示和业务横向位移 RED**

在 `horizontalBusinessPageIsFifthAndKeepsDelegateConfiguration()` 增加：

```swift
#expect(
    pager.dataSource?.pagerViewController(
        pager,
        allowsInteractiveHorizontalPagingAt: 4
    ) == false
)
let navigationRegion = try #require(
    firstSubview(in: page.view, as: UIView.self) {
        $0.accessibilityIdentifier == "horizontal-explicit-navigation-region"
    }
)
let navigationLabel = try #require(
    firstSubview(in: navigationRegion, as: UILabel.self) { _ in true }
)
#expect(navigationLabel.text == "使用上方分段栏切换页面")
```

把组合布局策略循环收紧为：

```swift
for index in 0..<6 {
    let expected = index != 4 && index != 5
    #expect(
        pager.dataSource?.pagerViewController(
            pager,
            allowsInteractiveHorizontalPagingAt: index
        ) == expected
    )
}
```

在 `testHorizontalBusinessRegionDoesNotDriveVerticalContainer()` 的真实 drag 前后记录首卡 frame：

```swift
let firstCard = app.staticTexts["横向业务内容 1"]
XCTAssertTrue(firstCard.waitForExistence(timeout: 3))
let initialFirstCardMinX = firstCard.frame.minX
// 保留现有 horizontalScrollView coordinate drag
XCTAssertLessThan(
    firstCard.frame.minX,
    initialFirstCardMinX - 20,
    "业务横向内容必须产生真实位移"
)
```

- [ ] **Step 2：运行 target-level Example unit RED**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests test
```

预期：18 tests 中策略/提示测试 FAIL；index 4 当前仍为 `true`，旧 identifier/提示仍存在。不得使用 Swift Testing method-level selector，因为该工具链会得到 0 tests。

- [ ] **Step 3：实现双页面策略与准确提示**

```swift
func pagerViewController(
    _ pagerViewController: AnchorPagerViewController,
    allowsInteractiveHorizontalPagingAt index: Int
) -> Bool {
    index != 4 && index != 5
}
```

把横向页下半区域改为显式导航说明：

```swift
region.accessibilityIdentifier = "horizontal-explicit-navigation-region"
region.accessibilityLabel = "显式页面切换说明"
// ...
label.text = "使用上方分段栏切换页面"
```

不得修改横向业务 `UIScrollView` 的 delegate、pan delegate、bounce、`isScrollEnabled` 或 nil 纵向 target 契约。

- [ ] **Step 4：运行 Example unit GREEN 与 Framework 策略回归**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests test
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests test
```

预期：Example unit 18/18 PASS；Framework ViewController/Host 全部 PASS。

- [ ] **Step 5：隔离运行横向业务真实 UI GREEN**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -enableCodeCoverage NO \
  -resultBundlePath /private/tmp/AnchorPagerTask6HorizontalBusinessGreen-20260716.xcresult \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalBusinessRegionDoesNotDriveVerticalContainer test
```

预期：1/1 PASS；页面保持 horizontal、业务卡片横向位移超过 20 pt、nil scroll target 与所有纵向 presentation 保持零。

- [ ] **Step 6：自审并提交 Example 策略**

检查 index 4、index 5 的 `false` 只来自 data source metadata，不写入页面 controller 或手势热路径；旧 `horizontal-pageboy-hit-region` 与旧提示全文零命中。

```bash
git diff --check
rg -n 'horizontal-pageboy-hit-region|在此区域左右滑动切换页面' Examples/AnchorPagerExample
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift
git commit -m "统一横向业务页面分页策略"
```

---

### Task 7：固定真实 UI 的 target terminal、bar 与 API 契约

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: index 3 `true`、index 4/5 `false`、`compositional-scroll-probe`、`scroll-coordination-state`、`selection-event-trace`、真实 Tabman item 与 public rapid selection trigger。
- Produces: enabled index 3→disabled index 4 的 matching terminal、index 4 业务横向 winner、index 4→5 bar terminal、index 5 orthogonal winner与 API 离页证据。

- [ ] **Step 1：保留组合布局正交、非正交与 API 契约**

保留已通过的 `testCompositionalOrthogonalRegionOwnsHorizontalDrag()` 和 `testCompositionalPageDisablesNonOrthogonalSwipeButKeepsBarSelection()`。把 `testCompositionalPageKeepsPublicSelectionAndIncomingSwipeAvailable()` 拆为只验证 API 的 `testCompositionalPageKeepsPublicSelectionAvailable()`：

```swift
let app = launchInteractionPage(
    initialIndex: 5,
    rapidTargets: "4",
    recordsAppearance: true
)
let trace = selectionTraceProbe(in: app)
reset(trace: trace)
rapidSelectionTrigger(in: app).tap()
XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [4]), [4])
XCTAssertTrue(
    app.scrollViews["horizontal-business-scroll"].waitForExistence(timeout: 5)
)
```

- [ ] **Step 2：新增 index 3→4 target terminal 与 index 4→5 bar 测试**

新增 `testEnabledPageCanSwipeIntoDisabledHorizontalPageThenBarToCompositional()`：

```swift
let app = launchPage(index: 3, mode: "container")
let trace = selectionTraceProbe(in: app)
reset(trace: trace)
let pageStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.78))
let pageEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.78))
pageStart.press(forDuration: 0.1, thenDragTo: pageEnd)

let horizontalScrollView = app.scrollViews["horizontal-business-scroll"]
XCTAssertTrue(horizontalScrollView.waitForExistence(timeout: 5))
XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [4]), [4])

let firstCard = app.staticTexts["横向业务内容 1"]
let initialMinX = firstCard.frame.minX
let businessStart = horizontalScrollView.coordinate(
    withNormalizedOffset: CGVector(dx: 0.82, dy: 0.45)
)
let businessEnd = horizontalScrollView.coordinate(
    withNormalizedOffset: CGVector(dx: 0.18, dy: 0.55)
)
businessStart.press(forDuration: 0.1, thenDragTo: businessEnd)
XCTAssertLessThan(firstCard.frame.minX, initialMinX - 20)
XCTAssertEqual(selectionEventSequence(from: trace), [4])

app.descendants(matching: .any)["组合布局页"].tap()
let card = app.cells["compositional-horizontal-card-1"]
XCTAssertTrue(card.waitForExistence(timeout: 5))
XCTAssertEqual(waitForSelectionTrace(from: trace, matching: [4, 5]), [4, 5])

let compositionalProbe = compositionalScrollProbe(in: app)
reset(trace: compositionalProbe)
let cardStart = card.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.48))
let cardEnd = card.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.52))
cardStart.press(forDuration: 0.1, thenDragTo: cardEnd)
XCTAssertNotNil(waitForCompositionalState(from: compositionalProbe, timeout: 5) {
    $0.maximumHorizontalOffset > 20
})
XCTAssertEqual(selectionEventSequence(from: trace), [4, 5])
```

- [ ] **Step 3：先隔离复验 interactive-pop**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -enableCodeCoverage NO \
  -resultBundlePath /private/tmp/AnchorPagerTask7InteractivePopIsolation-20260716.xcresult \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testLeadingEdgeInteractivePopWinsOverPageboyPaging test
```

预期：1/1 PASS。若隔离仍失败，停止 Task 7 并以 xcresult activity/attachment 重新分型；不得把 batch 干扰假设写成产品修复。

- [ ] **Step 4：运行七项页面级与相邻手势回归**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -enableCodeCoverage NO \
  -resultBundlePath /private/tmp/AnchorPagerTask7PagePolicyRegression-20260716.xcresult \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalOrthogonalRegionOwnsHorizontalDrag \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalPageDisablesNonOrthogonalSwipeButKeepsBarSelection \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalPageKeepsPublicSelectionAvailable \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testEnabledPageCanSwipeIntoDisabledHorizontalPageThenBarToCompositional \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalSwipeSelectsNextPageContent \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalBusinessRegionDoesNotDriveVerticalContainer \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testLeadingEdgeInteractivePopWinsOverPageboyPaging test
```

预期：7/7 PASS；普通页面分页、horizontal-only nil target、业务横向位移与 interactive-pop 无回归。

- [ ] **Step 5：自审并提交 UI 契约**

确认所有横向位移来自真实 coordinate drag，测试未直接写 offset、未调用 Framework internal API；public trigger 只在 launch argument 开启时安装。

```bash
git diff --check
git add Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "验收双横向业务页面手势"
```

---

### Task 8：验收纵向 handoff、reload/rebind、appearance 与 sampler 资源

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift`（仅在 lifecycle RED 证明资源清理缺口时修改）

**Interfaces:**
- Consumes: 根 CollectionView committed target、page generation、matching reload policy、appearance callback 和现有 display-link sampler。
- Produces: 新 generation 继续 false、旧页面释放、纵向 handoff 与采样资源成对清理的证据。

- [ ] **Step 1：补组合页面 sampler lifecycle 回归**

```swift
@Test func compositionalPresentationSamplerFollowsVisiblePageLifecycle() throws {
    let owner = ExamplePagerViewController(arguments: [])
    owner.loadViewIfNeeded()
    let page = try #require(
        owner.pageForTesting(at: 5) as? ExampleCompositionalPageViewController
    )
    #expect(page.isScrollPresentationSamplingActive == false)

    page.beginAppearanceTransition(true, animated: false)
    page.endAppearanceTransition()
    #expect(page.isScrollPresentationSamplingActive)

    page.beginAppearanceTransition(false, animated: false)
    page.endAppearanceTransition()
    #expect(page.isScrollPresentationSamplingActive == false)
}
```

- [ ] **Step 2：使用 target-level selector 运行 lifecycle 回归**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests test
```

预期：新增后 19/19 PASS。现有实验实现已经具备成对 start/stop 时，该测试是先补齐遗漏的生命周期回归，不制造人为 RED；不得使用会运行 0 tests 的 Swift Testing method-level selector。

- [ ] **Step 3：仅在回归暴露缺口时固定 sampler 成对实现**

页面 lifecycle 保持以下唯一入口：

```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    startScrollPresentationSampling()
    onAppearance(identifier, "viewWillAppear")
}

override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    stopScrollPresentationSampling()
    onAppearance(identifier, "viewDidDisappear")
}

deinit {
    MainActor.assumeIsolated {
        displayLink?.invalidate()
        displayLink = nil
    }
}
```

`startScrollPresentationSampling()` 必须先判断 `displayLink == nil`，`stopScrollPresentationSampling()` 必须同步 invalidate 并清 nil。

- [ ] **Step 4：收紧 reload UI 策略与新 generation 正交能力**

保持 `testCompositionalReloadRebindsRootVerticalTarget()` 的 generation 1→2、旧元素消失、root target 与 presentation 断言；启动后取得并重置 trace：

```swift
let trace = selectionTraceProbe(in: app)
reset(trace: trace)
```

reload 后对新 card 左拖并要求：

```swift
XCTAssertNotNil(waitForCompositionalState(from: compositionalProbe, timeout: 5) {
    $0.maximumHorizontalOffset > 20
        && $0.hasStableOwnership
        && $0.hasVerticalRange
})
XCTAssertEqual(selectionEventSequence(from: trace), [])
```

- [ ] **Step 5：运行纵向/reload/appearance 聚焦回归**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -enableCodeCoverage NO \
  -resultBundlePath /private/tmp/AnchorPagerTask8LifecycleRegression-20260716.xcresult \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalVerticalRegionHandsOffToCollectionView \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalReloadRebindsRootVerticalTarget \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testReloadReplacesOldPageGenerationAndKeepsPageInteractive \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompletedPageSwitchProducesOneAdditionalDidAppear \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCancelledInteractivePagingKeepsAppearanceAndSelectionConsistent \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSwitchingPagesRebindsVerticalOwnerWithoutJump test
```

预期：6/6 PASS；无旧 handler 更新新 probe、appearance imbalance 或 owner jump。

- [ ] **Step 6：资源与 ownership 自审并提交**

检查：

```bash
git diff --check
rg -n 'CADisplayLink|invalidate|visibleItemsInvalidationHandler|\[weak self\]' Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift
rg -n '\.(delegate|isScrollEnabled|bounces|alwaysBounceVertical)\s*=' Sources/AnchorPager/Children Sources/AnchorPager/Gesture Sources/AnchorPager/Core Sources/AnchorPager/Paging
```

提交测试或 lifecycle 修复：

```bash
git add Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "验收组合布局重载与资源生命周期"
```

---

### Task 9：同步长期文档、完整门禁与 fresh-pass

**Files:**
- Modify: `README.md`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- Modify: `docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md`
- Modify: `docs/superpowers/specs/2026-07-16-compositional-layout-mixed-axis-gesture-validation-design.md`
- Modify: `docs/superpowers/plans/2026-07-15-v0-7-interaction-selection-momentum.md`
- Modify: `docs/superpowers/plans/2026-07-16-compositional-layout-mixed-axis-gesture-validation.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Task 1–8 的新鲜 RED/GREEN、commit、真实 UI 和日志证据。
- Produces: 长期 Public 契约、能力边界、最终测试统计、生产 HEAD 和复审结论。

- [x] **Step 1：同步长期文档的精确契约**

文档统一写明：

```text
allowsInteractiveHorizontalPagingAt 默认 true。
false 只关闭 committed page 的 Pageboy 横向拖拽。
Tabman bar/API 保持可用；从 enabled page 可拖入 disabled target。
disabled page 的非正交区域也不能横滑分页。
Example index 4、index 5 显式 false；index 3→4 验证 enabled-to-disabled terminal，index 4↔5 只使用 bar/API。
策略按 reload metadata generation 原子提交，由 PagingHost 独占 committed 状态。
Adapter 只写 Pageboy 自有 isScrollEnabled，不修改业务 child。
任意业务横向 UIScrollView 在默认 true 页面自动优先仍不支持。
```

只在完整门禁通过后把专项标记完成；先保留实际执行中的测试数量和结果包字段，运行后立即写入真实值，不预填数字。

- [x] **Step 2：运行静态门禁**

```bash
git diff --check
swift package resolve
rg -n 'import (Tabman|Pageboy)' Sources/AnchorPager/Public
rg -n 'orthogonal|compositional' Sources/AnchorPager
rg -n '\.(delegate|bounces|alwaysBounceVertical)\s*=' Sources/AnchorPager/Children Sources/AnchorPager/Gesture Sources/AnchorPager/Core Sources/AnchorPager/Paging
rg -n 'isScrollEnabled\s*=' Sources/AnchorPager
```

预期：Public 无第三方 import；Framework 不含 Example 业务命名；没有新增业务 child delegate/bounce 写入；`isScrollEnabled` 新增命中只允许出现在 Adapter 对 Pageboy 继承属性的封装入口。

- [x] **Step 3：运行 Framework 全量**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -resultBundlePath /private/tmp/AnchorPagerCompositionalPolicyFramework-20260716.xcresult test
```

预期：0 fail、0 skip。

- [x] **Step 4：运行 Example 全量与 generic build**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/AnchorPagerCompositionalPolicyExample-20260716.xcresult test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -resultBundlePath /private/tmp/AnchorPagerCompositionalPolicyBuild-20260716.xcresult build
```

预期：Example 0 fail、0 skip；generic Simulator build 成功。

- [x] **Step 5：检查 xcresult 与运行时诊断**

```bash
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerCompositionalPolicyFramework-20260716.xcresult
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerCompositionalPolicyExample-20260716.xcresult
xcrun xcresulttool get build-results --path /private/tmp/AnchorPagerCompositionalPolicyBuild-20260716.xcresult
```

记录 `testsCount/passedTests/failedTests/skippedTests/errorCount/warningCount/analyzerWarningCount`；导出诊断并检索 UIKit `LayoutConstraints`、gesture dependency cycle、appearance imbalance、KVO/observer、display-link/resource lifecycle 关键词，要求零命中。

- [x] **Step 6：执行任务级自审**

逐项检查：

1. Public 默认实现与 source compatibility；
2. reload callback 重入和 generation atomicity；
3. Host 唯一 committed policy 与 stale terminal 隔离；
4. Adapter 只写 Pageboy 自有开关；
5. selection semantic/completion/executor-ready 顺序；
6. bar/API、interactive-pop、horizontal-only nil target；
7. root vertical target、managed inset、snapshot、纵向 handoff；
8. appearance、display link、layout handler 与闭包释放；
9. 固定日志、隐私、测试和文档状态。

- [x] **Step 7：执行 fresh-pass**

从设计提交 `91a49f0`、原计划提交 `f318029`、首次修订规格提交 `f51c657` 与二次修订规格提交 `9408bc7` 起重读完整 diff。按 Critical/Important/Minor 记录；任何 Critical/Important 必须补 RED、修复并重跑受影响聚焦与全量门禁。用户已选择当前会话 inline execution，在当前会话本地完成复审。

- [x] **Step 8：写入真实验收结果并提交文档**

```bash
git diff --check
git add AGENTS.md README.md docs
git commit -m "完成组合布局页面级分页验收"
```

只有 Task 1–9、全量门禁和 fresh-pass 全部完成，才能把组合布局专项标记 Ready，并在 `AGENTS.md` 记录最终生产 HEAD。

最终验收记录：生产代码 HEAD `db4b9bc`；Framework 439/439，结果包 `/private/tmp/AnchorPagerCompositionalPolicyFramework-20260716.xcresult`；Example 70/70（19 单元 + 51 UI），结果包 `/private/tmp/AnchorPagerCompositionalPolicyExample-20260716.xcresult`；generic Simulator build 结果包 `/private/tmp/AnchorPagerCompositionalPolicyBuild-20260716.xcresult`。全部 0 fail、0 skip、0 error、0 warning、0 analyzer warning；运行时问题关键字零命中。fresh-pass 终态 Critical 0、Important 0、Minor 0，专项 Ready。

## 计划自审

1. **规格覆盖：** Task 1 覆盖 Public/default/metadata；Task 2 覆盖 Adapter/日志；Task 3 覆盖 reload atomicity；Task 4 覆盖 selection terminal；Task 5 覆盖第六页首轮装配；Task 6 覆盖 index 4/5 双策略与横向页提示；Task 7 覆盖 target terminal、业务/正交横向手势和 explicit selection；Task 8 覆盖纵向/reload/lifecycle；Task 9 覆盖长期文档、全量门禁和 fresh-pass。
2. **占位语句扫描：** 已按计划技能的禁用模式逐项检索，当前无命中；每个代码变更步骤都给出精确 symbol、代码和预期结果。
3. **类型一致性：** Public 方法统一为 `pagerViewController(_:allowsInteractiveHorizontalPagingAt:) -> Bool`；metadata 统一为 `interactiveHorizontalPagingPermissions: [Bool]`；Adapter 入口统一为 `setInteractiveHorizontalPagingEnabled(_:)`。
4. **所有权一致性：** ViewController 只采集，Host 只 committed，Adapter 只执行；Store/Interaction/Scroll/Overscroll、业务 delegate/pan/bounce 与 containment 不新增职责。
5. **TDD 顺序：** Framework 能力已按 RED/GREEN 完成；二次修订从 index 4 策略/提示 RED 开始，真实 UI 分别固定 index 3→4 terminal、index 4 业务位移、index 4→5 bar、index 5 orthogonal 与 reload/lifecycle。
6. **回归完整性：** 覆盖 reload 重入、stale/rejected terminal、missing semantic、active/latest、empty teardown、bar/API、enabled-to-disabled incoming swipe、interactive-pop、horizontal-only nil target、业务横向位移、纵向 handoff、appearance 与资源释放。
7. **提交边界：** Task 1–5 的既有中文提交保持不变；Task 6–9 各自单一中文主题提交，UI 文件在 Task 7 集中提交，不混入 Task 6 的策略提交。
