# AnchorPager v0.7 Interaction Selection Momentum Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 v0.7 的统一交互状态、Host 选择事务、Tabman bar 路由、Pageboy executor-ready、双向跨 owner 惯性和系统返回/业务横向手势优先级，同时保持现有 Public API、Pageboy containment、Store generation、纵向 offset 与 overscroll policy 所有权不变。

**Architecture:** `AnchorPagerPagingHostViewController` 独占 selection/reload request payload 与 active/latest-pending 事务；`AnchorPagerPagingAdapter` 只执行 Tabman/Pageboy、标准化 matching callback 并观察 paging surface；`AnchorPagerInteractionCoordinator` 只保存单一跨域状态。`AnchorPagerViewController` 作为装配层按“active Pageboy → size → reload → Header layout → selection”顺序触发 drain，但不接管 Host payload。`AnchorPagerScrollCoordinator` 继续是协调期唯一 offset writer，并通过纯衰减模型与 `CADisplayLink` driver 完成 container/child 双向剩余速度合成；`AnchorPagerOverscrollCoordinator` 仍是唯一 boundary policy owner。

**Tech Stack:** Swift 6.2、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、Tabman 4.0.1、Pageboy 5.0.2、XCTest/XCUITest、Xcode 26.6、iPhone 17 Pro / iOS 26.5 Simulator。

**当前状态：** 专项设计与 Pageboy executor-ready 补充契约已确认；用户已复核并授权实施。Task 0–9 已完成，下一步把 pan velocity 接入 ScrollCoordinator 并完成双向跨 owner 合成。

## Global Constraints

- 设计基线固定为 `docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md`，实施起点不早于设计补充提交 `7b28855`。
- Public API 不新增、删除或重命名 symbol；Tabman/Pageboy 类型只允许出现在 internal adapter/paging 层。
- ViewController/Store 只在 matching Pageboy semantic did-select 后提交真实 current/public `selectedIndex`；completion 和 executor-ready 只推进 transaction readiness。
- Host 是唯一 explicit selection request identifier、active/latest pending、reload request 串行 owner；Adapter 不保存第二套 queue，Interaction Coordinator 不保存 index/page/generation。
- 动画 selection 必须同时等待 semantic terminal、programmatic completion 与 Pageboy executor-ready；不得在 completion 调用栈内启动 latest request。
- Pageboy executor-ready 只使用 Adapter 对 Pageboy open `isUserInteractionEnabled` 的覆写点；不得使用 timer、dispatch delay、KVC、private selector 或 UIKit scroll view KVO 猜测 Pageboy 状态。
- 真实 Pageboy paging surface 只通过 Adapter containment 发现；不得按 UIKit 私有类名查找，不设置 Pageboy scroll delegate 或 pan delegate。
- 不设置业务 child 的 `UIScrollView.delegate`、内建 pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`，也不保存后恢复这些值。
- 纵向 simultaneous recognition 继续只由 `AnchorPagerContainerScrollView` 放行 committed container/current-child pair，不把 Pageboy pan 或无关 pan 加入该 pair。
- ScrollCoordinator 是协调期唯一 container/child offset writer；OverscrollCoordinator 不持有 UIKit/page/provider，不直接写 offset。
- pan ended 后同一个 driver 先作为原生减速时钟运行：边界前 ScrollCoordinator 只读取 sample velocity、不消费 delta；触达 handoff boundary 后才切为 synthetic delta 消费。这样不依赖业务 child scroll delegate 或 `isDecelerating` KVO，也不会创建第二套 finish lifecycle。
- 原生减速到达 handoff 边界后，旧 owner 的迟到 native callback 只能由 ScrollCoordinator 锁回边界；synthetic 阶段只推进 canonical total，driver 不能直接持有或写 UIScrollView。
- 生产惯性 driver 只使用一个 `CADisplayLink`；测试通过纯模型和可注入 driver 协议驱动相同 monitor/synthetic tick 消费路径，不增加第二套 timer。
- reload/layout/size/selection/identity 变化必须同步取消 synthetic deceleration；真实仍按下的 vertical pan 不通过切换 recognizer 或 scroll enabled 强制中断。
- v0.7 只建立 `transitioningSize` 仲裁，不实现 v0.8 的完整 selected/Header/child offset snapshot 恢复，也不实现 scrollsToTop owner manager。
- Tabman 已有 bar accessibility trait、Pageboy 已有 RTL normalization 留到 v0.9 做集成验证，本计划不重复实现。
- 高频 pan、KVO、scroll、display-link tick 不逐帧输出普通日志，只记录状态边界、owner/handoff、finish/cancel 与异常。
- 每个任务严格执行 RED → 最小 GREEN → 聚焦回归 → 自审 → `git diff --check` → 中文单一主题提交；没有测试证据不得勾选完成。
- 开始实现前使用 `superpowers:using-git-worktrees`；若当前不是 worktree，必须先获得用户同意再创建隔离 worktree。

---

## 文件与职责

新增文件：

```text
Sources/AnchorPager/Paging/AnchorPagerPagingSelectionRequest.swift
Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift
Sources/AnchorPager/Gesture/AnchorPagerInteractionState.swift
Sources/AnchorPager/Gesture/AnchorPagerInteractionCoordinator.swift
Sources/AnchorPager/Gesture/AnchorPagerGesturePriorityCoordinator.swift
Sources/AnchorPager/Core/AnchorPagerVerticalDecelerationDriver.swift
Tests/AnchorPagerTests/AnchorPagerPagingSelectionRequestTests.swift
Tests/AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests.swift
Tests/AnchorPagerTests/AnchorPagerInteractionCoordinatorTests.swift
Tests/AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests.swift
Tests/AnchorPagerTests/AnchorPagerVerticalDecelerationDriverTests.swift
```

重点修改：

```text
Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift
Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift
Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift
Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift
Sources/AnchorPager/Public/AnchorPagerViewController.swift
Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift
Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift
Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift
Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift
Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift
Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift
Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift
Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift
Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
README.md
docs/architecture.md
docs/task-list.md
docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md
docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md
AGENTS.md
```

---

### Task 0：封住 Pageboy 连续非动画假接受窗口

**Files:**
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`

**Interfaces:**
- 保留现有 `setSelectedIndex(_:animated:) -> Bool`，仅在已有 programmatic execution 未完成时同步拒绝第二次直接 Adapter 调用。
- 该 guard 是第三方 executor 安全边界；Task 2 改名为 identifier-aware execute 后继续保留。

- [x] **Step 1：用真实 Pageboy 写连续非动画 RED**

新增 `testSameCallStackNonanimatedRequestsRejectSecondBeforePageboyFalseAcceptanceWindow()`：加载三页真实 Adapter，在同一 MainActor 调用栈连续请求 `0 -> 1` 与 `0 -> 2`、均为 `animated: false`；断言第一笔为 true、第二笔必须为 false、第二笔不能替换第一笔 execution，第一笔 terminal 后 reload readiness 能恢复。

- [x] **Step 2：运行 RED**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests/testSameCallStackNonanimatedRequestsRejectSecondBeforePageboyFalseAcceptanceWindow test
```

预期：当前实现第二笔错误返回 true，或第一笔完成后仍因第二笔悬空而 busy；失败必须精确落在该 Pageboy 5.0.2 窗口。

- [x] **Step 3：最小实现 executor busy guard**

在任何 `pendingProgrammaticSelection` 写入之前检查现有 programmatic semantic/completion 状态；busy 时记录 `paging.selection.reject` 并返回 false，不调用 `scrollToPage`、不覆盖第一笔 context。

- [x] **Step 4：运行聚焦 Adapter 回归**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

预期：全部 Adapter tests 通过，连续动画拒绝、reload readiness、empty teardown 与 appearance tests 无回归。

- [x] **Step 5：自审与提交**

检查没有修改 Pageboy 源码、没有异步 delay、没有扩大 Public API；运行 `git diff --check`。

```bash
git add Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift
git commit -m "封住 Pageboy 连续选择窗口"
```

---

### Task 1：建立 selection request 与 transaction 值语义

**Files:**
- Create: `Sources/AnchorPager/Paging/AnchorPagerPagingSelectionRequest.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPagingSelectionRequestTests.swift`

**Interfaces:**

```swift
typealias AnchorPagerPagingSelectionRequestIdentifier = Int

enum AnchorPagerPagingSelectionSource: Equatable {
    case api
    case bar
    case interactive
}

struct AnchorPagerPagingSelectionRequest: Equatable {
    let identifier: AnchorPagerPagingSelectionRequestIdentifier
    let targetIndex: Int
    let animated: Bool
    let source: AnchorPagerPagingSelectionSource
}

enum AnchorPagerPagingSelectionSemanticTerminal: Equatable {
    case selected(index: Int)
    case cancelled(index: Int, previousIndex: Int)
}

struct AnchorPagerPagingSelectionTransaction: Equatable {
    let request: AnchorPagerPagingSelectionRequest
    let previousIndex: Int
    let adapterIdentifier: ObjectIdentifier
    var semanticTerminal: AnchorPagerPagingSelectionSemanticTerminal?
    var didAcknowledgeCompletion: Bool
    var didAcknowledgeExecutorReady: Bool

    var isReadyToFinish: Bool { get }
}
```

- [x] **Step 1：写纯值语义 RED**

覆盖：interactive transaction 只需 semantic terminal；非动画 explicit completion 同时确认 completion/ready；动画 explicit 必须三项齐全；stale identifier、target mismatch、adapter identity mismatch 不改变 transaction；同 target duplicate 与 latest replacement admission 结果可区分。`interactive` 只能由 Host 的 interactive-begin 入口创建，不能通过 explicit enqueue 排队。

- [x] **Step 2：运行 RED**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingSelectionRequestTests test
```

预期：编译失败，缺少 selection request/transaction 类型。

- [x] **Step 3：实现最小值类型与 matching helper**

所有类型保持 internal、`Equatable`、无 UIKit page/provider/offset；`ObjectIdentifier` 只用于 active adapter identity，不进入日志正文。

- [x] **Step 4：运行 GREEN、自审并提交**

```bash
git add Sources/AnchorPager/Paging/AnchorPagerPagingSelectionRequest.swift Tests/AnchorPagerTests/AnchorPagerPagingSelectionRequestTests.swift
git commit -m "建立分页选择事务值语义"
```

---

### Task 2：把 Adapter 收口为 identifier-aware Pageboy executor

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

计划复核补充：Adapter delegate 与执行入口是 Paging 层的同步编译契约，改为 identifier-aware 后必须在本任务同步迁移 Host 调用点，并调整依赖旧 completion/readiness 顺序的 Host/ViewController 测试。这里仅建立 Host identifier 分配与签名桥接；一笔 active + 一笔 latest pending 的 admission、matching terminal 和 drain 所有权仍完整留在 Task 3，不在 Adapter 建立第二套队列。

**Interfaces:**

将 Adapter delegate 标准化为 matching request callback：

```swift
func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    didRequestBarSelectionAt index: Int
)
func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    didBeginInteractiveSelectionAt index: Int,
    animated: Bool
) -> AnchorPagerPagingSelectionRequestIdentifier?
func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    willSelect index: Int,
    animated: Bool,
    requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
)
func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    didSelect index: Int,
    animated: Bool,
    requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
)
func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    didCancelSelectionAt index: Int,
    returningTo previousIndex: Int,
    requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
)
func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    didComplete requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
    finished: Bool,
    currentIndex: Int?
)
func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    executorDidBecomeReadyFor requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
)
```

Adapter 执行入口改为：

```swift
@discardableResult
func executeSelection(
    _ request: AnchorPagerPagingSelectionRequest,
    previousIndex: Int
) -> Bool
```

- [x] **Step 1：写 Adapter callback provenance RED**

覆盖：execute 时保存唯一 matching identifier；will/did/cancel/completion 全部携带同一 identifier；没有 executing context 的 interactive will 同步向 Host 申请 identifier；duplicate will 复用 identifier；旧 completion 不清除新 context；target mismatch 只记录 stale 日志。

- [x] **Step 2：写 Tabman bar 旁路 RED**

直接调用 `adapter.bar(_:didRequestScrollTo:)`，断言只收到 `didRequestBarSelectionAt`，未调用 `super`、未直接改变 Pageboy current index、未创建无 identifier execution。

- [x] **Step 3：写 executor-ready 顺序 RED**

真实动画 request completion 到达时只发送 completion acknowledgement；在 Adapter 继承的 `isUserInteractionEnabled` 恢复为 true 前不发送 ready；恢复 true 后只发送一次 matching ready。false、重复 true、无 matching identifier、teardown 后迟到 true 均无效。

- [x] **Step 4：运行 RED**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

预期：因新 delegate/execute/bar/ready 契约缺失而失败。

- [x] **Step 5：实现最小 Adapter executor**

删除 Adapter 的 explicit queue/latest-wins 职责，只保留一笔 `ExecutingSelection`；覆写 `bar(_:didRequestScrollTo:)` 且不调用 super；覆写 Pageboy open `isUserInteractionEnabled`，只在 matching animated completion 已到达后发布 ready。非动画 completion 同步发布 completion + ready，不等待属性 hook。

- [x] **Step 6：保留 reload/teardown 兼容点**

`prepareForRemoval()` 先 structural-cancel executing/ready context，再使用现有 Pageboy 5.0.2 delete-last-page shim；不改变 post-order containment teardown、bar inset terminal 和 appearance suppression。

- [x] **Step 7：运行 Adapter 全量、自审并提交**

```bash
git add Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift docs/architecture.md docs/task-list.md docs/superpowers/plans/2026-07-15-v0-7-interaction-selection-momentum.md
git commit -m "收口 Pageboy 选择执行边界"
```

验收记录：RED 首先因新 delegate、`executeSelection` 与 executor-ready 契约缺失而编译失败；GREEN 后 Adapter/Host 聚焦测试通过，Framework 全量 335/335、0 fail、0 skip，结果包为 `/private/tmp/AnchorPagerV07Task2FrameworkFinal-20260715-1606.xcresult`。自审确认 Public API、Pageboy containment、reload/teardown、appearance suppression、业务 child delegate/pan/bounce/inset ownership 均未改变；Adapter 只保留一笔第三方 execution，Host active/latest queue 仍未提前实现。

---

### Task 3：让 PagingHost 拥有 active + latest pending selection

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`

**Interfaces:**

```swift
@discardableResult
func enqueueSelection(
    index: Int,
    animated: Bool,
    source: AnchorPagerPagingSelectionSource
) -> Bool

@discardableResult
func performPendingSelectionIfPossible() -> Bool
```

Host 新增单调 `nextSelectionRequestIdentifier`、`activeSelectionTransaction`、`pendingExplicitSelectionRequest` 和 committed index；testing 只读状态可返回值快照，不能暴露到 Public API。

- [x] **Step 1：写 Host admission RED**

覆盖：无 active 时开始 API；active 时 C 入 pending、D 替换 C；重复 active target 不建 pending；active B 时请求 committed A 是有效 pending；越界/reload pending 拒绝；bar 与 API 使用同一 identifier 递增序列。

- [x] **Step 2：写 matching terminal RED**

覆盖：did-select 立即转发 ViewController/Store 一次，但 active 直到 completion/ready 才释放；cancel 不提交 selection；duplicate/stale/out-of-order identifier、target、adapter identity 均不释放 active；completion missing semantic 按 Adapter current index recovery。

- [x] **Step 3：写真实中间页提交 RED**

模拟 `A -> B` active、D pending；B semantic terminal 必须先转发 `.didSelect(B)`，三项确认齐全后才直接执行 `B -> D`，不逐页经过 C，不允许 B 的旧 callback 清除 D。

- [x] **Step 4：运行 RED**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests test
```

- [x] **Step 5：实现 Host queue 与 identifier matching**

Host 创建 request 后才调用 `executeSelection`；Adapter false 形成 rejected-before-start，不提交 Store，结束 matching active 后继续评估最新请求。Host 不持有 page controller、provider generation、scroll target 或 offset。

- [x] **Step 6：运行 Host + Adapter 聚焦回归**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

- [x] **Step 7：自审并提交**

```bash
git add Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift docs/architecture.md docs/task-list.md docs/superpowers/plans/2026-07-15-v0-7-interaction-selection-momentum.md
git commit -m "统一分页选择请求所有权"
```

验收记录：RED 因缺少 `enqueueSelection`、active/latest 与 committed index 快照而编译失败。GREEN 覆盖 API/bar 共用单调 identifier、active + latest replacement、committed 返回意图、interactive duplicate/cancel、matching semantic/completion/ready、out-of-order ready、missing semantic select/cancel recovery、旧 adapter/identifier/target 隔离，以及真实非动画 Pageboy updater 的中间页先提交/最新目标后启动。Host + Adapter 联合回归 64/64、0 fail、0 skip，结果包为 `/private/tmp/AnchorPagerV07Task3HostAdapterFinal-20260715-1720.xcresult`；Framework 全量 342/342、0 fail、0 skip，结果包为 `/private/tmp/AnchorPagerV07Task3FrameworkFull-20260715-1728.xcresult`。自审确认 Host 未持有 page controller、provider generation、scroll target 或 offset；Adapter queue、Public API、containment、appearance 与业务 child ownership 均未改变。selection/reload 交叉的 pending generation 丢弃和统一优先 drain 仍留在 Task 4。

---

### Task 4：统一 selection 与 reload terminal 串行

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Verify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Modify: `docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md`

计划复核补充：Task 2 已用 `testNonanimatedCompletionPublishesReadySynchronouslyAndTeardownClearsLateHook()` 固定 Adapter teardown 清除晚到 ready hook，本任务复用并联合运行该门禁，不重复修改 Adapter 测试；新增 Host 真实 custom transition 集成测试固定动画 completion → interaction hook → latest start 顺序。

- [x] **Step 1：写 selection/reload 交叉 RED**

覆盖：active selection + latest reload；reload 到来丢弃旧 generation pending selection；selection 三项确认前 reload 不开始；release 后 reload 优先于 selection；reload pending/active 时新 API/bar selection no-op；empty teardown 对 active transaction 发 matching structural cancel；旧 Adapter 迟到 terminal 不影响新 Adapter。

- [x] **Step 2：写 executor-ready 真实集成 RED**

在真实 Adapter/Host 中启动 animated B，排队 D；手动到达 B semantic 与 completion 后断言 D 未启动；Pageboy interaction hook 恢复 true 后 D 才启动。另测 nonanimated B completion 可同步 ready，但仍不得在第一笔未进入真实 updater 前并发调用 Pageboy。

- [x] **Step 3：实现统一 reload-first drain**

移除 did/cancel callback 中“先 perform reload、再丢弃真实 semantic”的旧逻辑；matching semantic 必须先提交真实 B，transaction 完整释放后才开始 pending reload。reload request payload 与 generation acknowledgement 保持现有 identifier 契约。

- [x] **Step 4：运行聚焦回归**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

- [x] **Step 5：自审并提交**

```bash
git add Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift docs/architecture.md docs/task-list.md docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md docs/superpowers/plans/2026-07-15-v0-7-interaction-selection-momentum.md
git commit -m "串行分页选择与重载终态"
```

验收记录：selection/reload RED 同时暴露旧 generation pending selection 未清除和 empty shim 后 Host transaction 悬挂；GREEN 后 reload 到来同步丢弃未开始 selection，matching semantic 始终先提交，active 收齐 required acknowledgement 后优先启动 latest reload。真实 Pageboy public custom transition 验证动画 B 的 semantic 先到，只有真实 completion 令 interaction hook 恢复后才启动 D；真实非动画 updater 门禁继续验证 completion 同步 ready 不会在第一笔 updater 前并发执行。空态 shim 成功且 Adapter 已 ready、Host 仍缺 semantic 时只发送一次 matching structural cancel，旧 Adapter terminal/ready 不影响新 Adapter。Host + Adapter 66/66、Framework 344/344，均 0 fail、0 skip；结果包分别为 `/private/tmp/AnchorPagerV07Task4HostAdapterFinal-20260715-1830.xcresult` 与 `/private/tmp/AnchorPagerV07Task4FrameworkFinal-20260715-1832.xcresult`。自审确认 reload payload/generation acknowledgement、Public API、containment、appearance、Store 和业务 child ownership 均未改变。

---

### Task 5：建立单一 Interaction State 与状态转换

**Files:**
- Create: `Sources/AnchorPager/Gesture/AnchorPagerInteractionState.swift`
- Create: `Sources/AnchorPager/Gesture/AnchorPagerInteractionCoordinator.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerInteractionCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**

```swift
enum AnchorPagerInteractionState: Equatable {
    case idle
    case verticalDragging(identifier: Int)
    case verticalDecelerating(identifier: Int)
    case horizontalPaging(identifier: Int)
    case programmaticPaging(identifier: Int)
    case topOverscrolling(identifier: Int)
    case layoutReloading(identifier: Int)
    case transitioningSize(identifier: Int)
}

@MainActor
final class AnchorPagerInteractionCoordinator {
    private(set) var state: AnchorPagerInteractionState
    var isReadyForDeferredWorkDrain: Bool { get }

    @discardableResult func begin(_ state: AnchorPagerInteractionState) -> Bool
    @discardableResult func updateBoundary(to state: AnchorPagerInteractionState) -> Bool
    @discardableResult func finish(_ state: AnchorPagerInteractionState) -> Bool
    @discardableResult func cancel(_ state: AnchorPagerInteractionState) -> Bool
    func beginSizeTransition(identifier: Int)
    func finishSizeTransition(identifier: Int)
}
```

实现可使用 internal suspended state 保存 size preemption 前的 programmatic/horizontal/layout transaction；不得把 suspended page/index/provider 存入 coordinator。

- [x] **Step 1：写全部状态 RED**

逐一覆盖 idle、verticalDragging、verticalDecelerating、horizontalPaging、programmaticPaging、topOverscrolling、layoutReloading、transitioningSize 的 begin/update/finish/cancel；matching identifier 才能结束；duplicate 幂等；非法低优先级 begin 不覆盖高优先级状态。

- [x] **Step 2：写 size suspension RED**

programmatic/horizontal/layout active 时 size begin 进入 transitioningSize；原 transaction 在 size 内 terminal 时清除 suspended resume；size finish 后恢复仍 active 的 paging，否则 idle 并发出一次 drain-ready。

- [x] **Step 3：写日志 RED**

通过注入 sink 精确验证 `interaction.state.begin/updateBoundary/finish/cancel/invalidTransition`；identifier、index、velocity、geometry 不得进入 event 名或消息正文；重复非法 callback 不刷屏。

- [x] **Step 4：运行 RED/GREEN**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerInteractionCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
```

- [x] **Step 5：自审并提交**

```bash
git add Sources/AnchorPager/Gesture/AnchorPagerInteractionState.swift Sources/AnchorPager/Gesture/AnchorPagerInteractionCoordinator.swift Tests/AnchorPagerTests/AnchorPagerInteractionCoordinatorTests.swift Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift docs/architecture.md docs/task-list.md docs/superpowers/plans/2026-07-15-v0-7-interaction-selection-momentum.md
git commit -m "建立统一交互状态机"
```

验收记录：RED 因 `AnchorPagerInteractionState` 与 `AnchorPagerInteractionCoordinator` 缺失而编译失败。GREEN 覆盖八种 state、matching identifier、vertical drag/top/deceleration 边界、paging/layout begin/finish/cancel、重复幂等、低优先级非法 begin、size 抢占与 programmatic/horizontal/layout suspended resume、size 内 terminal 清除 resume，以及最近一次非法转换日志去重。Interaction + Logger 聚焦 15/15、Framework 全量 353/353，均 0 fail、0 skip；结果包分别为 `/private/tmp/AnchorPagerV07Task5InteractionFinal-20260715-1912.xcresult` 与 `/private/tmp/AnchorPagerV07Task5FrameworkFull-20260715-1915.xcresult`。自审确认 state 是纯 `Sendable` 值类型，Coordinator 仅保存 state/suspended state/非法转换去重键，不持有 UIKit、page、provider、Store、index payload、geometry 或 offset；日志只有固定事件名且不含 identifier。Host/ViewController/Scroll 装配仍留在 Task 6。

---

### Task 6：装配 reload/layout/selection/size 的统一 drain

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Ownership:**
- Host 保存 reload 与 selection payload。
- ViewController 只保存 `PendingHeaderLayoutRequest(offsetAdjustment:)`。
- Interaction Coordinator 只保存状态。
- ViewController 的 `drainDeferredWorkIfPossible()` 仅按顺序调用 owner，不复制 payload：active Pageboy/size 阻塞 → Host reload → Header layout → Host selection → idle。

- [x] **Step 1：写 latest Header layout RED**

verticalDragging/topOverscrolling/transitioningSize 期间连续请求不同 adjustment，只保存最后一笔；回 idle 后只执行一次最后策略。verticalDecelerating 时同步取消 synthetic 状态后执行。现有四种 offset adjustment 结果不变。`configuration.didSet` 的 Header 配置变化也走同一 layout admission；配置值立即更新，但 geometry/presentation transaction 不得绕开非 idle 仲裁。

- [x] **Step 2：写 deferred reload RED**

真实 pan/top overscroll 期间 `reloadData()` 仍同步采集最新 metadata snapshot，但不取消仍按下的手势、不调用 Adapter reload；idle 后只执行 latest Host reload。更新旧 `testReloadDataSynchronouslyCancelsActiveContainerPresentationBeforeReadingDataSource`，使其区分“采集 metadata”与 matching `willPerformReloadRequest` 的 canonical reset。

- [x] **Step 3：写 size transition RED**

使用可控 `UIViewControllerTransitionCoordinator`：size begin 同步取消 boundary/synthetic presentation并暂停 drain；active Pageboy transaction 不伪造 cancel；transition completion 后恢复 transaction 或执行 reload/layout/selection 顺序。

- [x] **Step 4：写选择 no-op 迁移 RED**

移除 ViewController 的 `selectedIndex == target` 过早返回；没有 active 时 Host 对 committed target no-op，active B 时请求 committed A 进入 latest pending 并在 B terminal 后返回 A。

- [x] **Step 5：实现装配与重入 guard**

`drainDeferredWorkIfPossible()` 使用同步重入 guard；Host/Interaction terminal 只请求 drain，不直接跨层执行 Header layout。layout begin/finish 必须成对，finish callback 内的新请求进入下一轮 drain，不递归重复提交。

- [x] **Step 6：运行 ViewController/Host 回归**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests test
```

- [x] **Step 7：自审并提交**

```bash
git add Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "统一交互事务排空顺序"
```

验收记录：RED 因 Host 缺少 deferred execution suspension/显式 drain 入口、ViewController 缺少 Interaction admission 与 pending Header layout owner 而编译失败。GREEN 覆盖 vertical dragging/top overscrolling/vertical decelerating/transitioning size 的 latest Header adjustment、Header 配置即时更新但 geometry 延后、layout callback 重入下一轮、reload metadata 同步采集但 matching Adapter reload 延后、连续 reload latest-wins、size 内 active Pageboy 不伪造 terminal、reload→layout 与 layout→selection 两条合法优先路径，以及 active B 时请求 committed A 仍进入 Host latest pending。自审追加的 pending-only selection RED 精确证明同目标会错误换 identifier、返回 committed 不会撤销旧 pending；GREEN 后改为同目标去重、不同目标 latest 替换、committed 目标撤销未启动 pending。Host + ViewController 聚焦 146/146、0 fail、0 skip，结果包为 `/private/tmp/AnchorPagerV07Task6HostViewControllerFinal-20260715-1733.xcresult`；Framework 全量 364/364、0 fail、0 skip，结果包为 `/private/tmp/AnchorPagerV07Task6FrameworkFull-20260715-1735.xcresult`。全量初跑的 Public 源码隔离扫描发现 internal 属性调用名含 `Pageboy`，已改为领域内 `hasActivePagingTransaction` 并完成聚焦/全量复验。自审确认 Host 仍独占 reload/selection payload，ViewController 只保存 Header layout payload，Interaction Coordinator 只保存 state；reload pending/active 继续拒绝跨 generation selection；未修改 Public API、Pageboy containment、Store generation、业务 child delegate/pan/bounce/isScrollEnabled 或纵向 offset owner。真实 vertical/paging/boundary lifecycle 接线仍留在 Task 11。

---

### Task 7：建立可撤销 Pageboy paging surface/pan observation

**Files:**
- Create: `Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`

**Interfaces:**

```swift
@MainActor
final class AnchorPagerPagingSurfaceObservation: NSObject {
    struct Surface {
        let pageViewController: UIPageViewController
        let scrollView: UIScrollView
        let panGestureRecognizer: UIPanGestureRecognizer
    }

    var onSurfaceChanged: ((Surface?) -> Void)?
    var onPanStateChanged: ((UIGestureRecognizer.State) -> Void)?

    func refresh(in rootViewController: UIViewController)
    func invalidate()
}
```

- [x] **Step 1：写 containment discovery RED**

只通过 `UIPageViewController` containment 和其 UIScrollView 子树识别 surface；不匹配私有类名。重复 refresh 同 identity 不重复 target；identity replacement 先解绑旧 pan；invalidate/deinit 幂等。

- [x] **Step 2：写 delegate ownership RED**

保存 Pageboy scroll/pan delegate identity，refresh、pan callback、replacement、invalidate 全程不变；源码扫描禁止 `.delegate =`、`isScrollEnabled =`、bounce 写入。

- [x] **Step 3：实现观察并装配 Adapter**

Adapter 在 `viewDidLoad`、`viewDidLayoutSubviews`、reload terminal 和 teardown 后刷新/清理 observation；只向 Host/ViewController 暴露 internal pan identity 和生命周期事件，不泄漏 Public API。

- [x] **Step 4：运行聚焦测试**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

- [x] **Step 5：自审并提交**

```bash
git add Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift Tests/AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests.swift Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift
git commit -m "观察 Pageboy 分页手势表面"
```

验收记录：首轮 RED 因 `AnchorPagerPagingSurfaceObservation`、Adapter surface identity 与 pan lifecycle delegate 入口缺失而编译失败；生命周期日志补充 RED 精确失败于缺少固定 `paging.surface.bind/unbind`。GREEN 仅通过公开 `UIPageViewController` containment 与最浅层 `UIScrollView` 子树发现 paging surface，同 identity refresh 幂等，replacement 先 remove 旧 target 再 add 新 target，invalidate/deinit 幂等；全程不设置 scroll/pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。Adapter 在 view load/layout、reload terminal 与 teardown 刷新或清理，并只经 internal delegate 发布 surface identity/pan state。Observation + Adapter 最终聚焦 40/40、0 fail、0 skip，结果包 `/private/tmp/AnchorPagerV07Task7AdapterFinal-20260715-1820.xcresult`；Framework 全量 372/372、0 fail、0 skip，结果包 `/private/tmp/AnchorPagerV07Task7FrameworkFinal-20260715-1821.xcresult`；两份 xcresult 均为 0 error、0 warning、0 analyzer warning。自审确认 Public API、Tabman/Pageboy containment、Host/Store generation、业务 child delegate/pan/bounce/isScrollEnabled、纵向 simultaneous recognition、offset writer 与 overscroll policy owner 均未改变；真实 paging lifecycle 仲裁留在 Task 11。

---

### Task 8：安装 system/page/current-child 手势失败关系

**Files:**
- Create: `Sources/AnchorPager/Gesture/AnchorPagerGesturePriorityCoordinator.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**

```swift
@MainActor
final class AnchorPagerGesturePriorityCoordinator {
    typealias FailureInstaller = (UIGestureRecognizer, UIGestureRecognizer) -> Void

    init(failureInstaller: @escaping FailureInstaller = { gesture, required in
        gesture.require(toFail: required)
    })

    func bindPagingPan(_ pan: UIPanGestureRecognizer?)
    func bindInteractivePopGesture(_ gesture: UIGestureRecognizer?)
    func bindCommittedScrollView(_ scrollView: UIScrollView?)
    func refresh()
    func invalidate()
}
```

- [x] **Step 1：写 failure matrix RED**

验证 `pagingPan -> interactivePop`；只有 committed scroll view 水平范围满足 `contentSize.width + adjustedContentInset.left + adjustedContentInset.right > bounds.width + 0.5` 时安装 `pagingPan -> childPan`；plain nil、普通纵向 child、不相关 cached page 不安装。

- [x] **Step 2：写 delegate/configuration RED**

绑定与 refresh 不改变 system/Pageboy/child recognizer delegate，不改变业务 scroll delegate、isScrollEnabled、bounce。注入 `FailureInstaller` 记录 public relation，不用 KVC/private introspection。

- [x] **Step 3：实现单调 relation 与 identity guard**

UIKit 没有 removal API；同一 pair 只安装一次，paging surface identity 改变后为新 pan 重建当前关系。旧 page pan 离开命中层级后不参与新触摸。若同一 committed child 在同一 paging surface 生命周期内从水平可滚动态缩为不可滚，已安装 relation 只能保留到 surface replacement；把该 UIKit 限制写入 architecture known limitations，不新增 Public API 模拟动态移除。

- [x] **Step 4：装配 navigation/current committed identity**

ViewController 在 paging surface change、`viewDidAppear`/navigation 变化、matching reload/selection/cancel terminal 和 committed scroll identity 变化时 refresh；只消费 Store committed current scroll view。

- [x] **Step 5：运行聚焦测试**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

- [x] **Step 6：自审并提交**

```bash
git add Sources/AnchorPager/Gesture/AnchorPagerGesturePriorityCoordinator.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift docs/architecture.md
git commit -m "明确横向与系统手势优先级"
```

验收记录：RED 因 `AnchorPagerGesturePriorityCoordinator` 与 ViewController 装配入口缺失而编译失败。GREEN 使用可注入 `FailureInstaller` 固定 `pagingPan -> interactivePop` 与仅 committed current 具备真实水平范围时的 `pagingPan -> childPan`；plain nil、普通纵向 current、不相关 cached page 均不安装。关系记录弱持有双方 identity，同一 pair 单调去重；paging surface replacement 为新 pan 建立当前有效关系，已安装 pair 不用 KVC/private API 模拟删除。delegate/configuration 源码隔离和运行时 identity 均覆盖，空 reload 清空当前 paging/committed binding，matching reload/selection/cancel terminal 只重绑 Store committed identity。两条 ViewController 初跑失败经 xcresult 定位为测试 weak data source 临时对象已释放，修正夹具后生产逻辑无需变化。Coordinator + ViewController 最终聚焦 118/118、0 fail、0 skip，结果包 `/private/tmp/AnchorPagerV07Task8FocusedFinal-20260715-1832.xcresult`；Framework 全量 380/380、0 fail、0 skip，结果包 `/private/tmp/AnchorPagerV07Task8FrameworkFinal-20260715-1833.xcresult`；两份 xcresult 均为 0 error、0 warning、0 analyzer warning。自审确认未扩大 Public API，未改变 Tabman/Pageboy containment、Host/Store generation、纵向 simultaneous pair、业务 child delegate/pan/bounce/isScrollEnabled、offset writer 或 overscroll policy owner；真实导航栈/横向 child UI 验收留在 Task 13。

---

### Task 9：实现纯衰减模型与 CADisplayLink driver

**Files:**
- Create: `Sources/AnchorPager/Core/AnchorPagerVerticalDecelerationDriver.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerVerticalDecelerationDriverTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**

```swift
struct AnchorPagerVerticalDecelerationModel {
    struct Sample: Equatable {
        let delta: CGFloat
        let velocity: CGFloat
        let isFinished: Bool
    }

    static func sample(
        initialVelocity: CGFloat,
        decelerationRate: CGFloat,
        fromElapsedTime: TimeInterval,
        toElapsedTime: TimeInterval,
        velocityEpsilon: CGFloat = 5
    ) -> Sample?
}

@MainActor
protocol AnchorPagerVerticalDecelerationDriving: AnyObject {
    var onTick: ((AnchorPagerVerticalDecelerationModel.Sample) -> Void)? { get set }
    var onCancel: (() -> Void)? { get set }
    func start(initialVelocity: CGFloat, decelerationRate: CGFloat, elapsedTime: TimeInterval)
    func cancel()
}

@MainActor
final class AnchorPagerVerticalDecelerationDriver: AnchorPagerVerticalDecelerationDriving {
    // 唯一生产 CADisplayLink driver
}
```

- [x] **Step 1：写纯数学 RED**

固定 `v0 = 1000 pt/s`、`d = 0.998`、`t = 0.1s`，断言 velocity 约 `818.567`、delta 约 `90.626`；负 velocity 保持符号；分段积分等于整段；绝对速度不大于 5 时 finish；非有限值、`d <= 0`、`d >= 1`、倒退时间返回 nil。

- [x] **Step 2：写 driver 生命周期 RED**

start replacement 只保留最新 identity；cancel 幂等并释放 display link/target；deinit 无残留；tick 热路径不写普通日志，begin/finish/cancel 各一次。

- [x] **Step 3：运行 RED/GREEN**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerVerticalDecelerationDriverTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
```

- [x] **Step 4：自审并提交**

确认纯模型不 import UIKit；driver 不持有 UIScrollView/page/provider；只在 MainActor 操作 CADisplayLink。

```bash
git add Sources/AnchorPager/Core/AnchorPagerVerticalDecelerationDriver.swift Tests/AnchorPagerTests/AnchorPagerVerticalDecelerationDriverTests.swift Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift
git commit -m "实现纵向惯性衰减驱动"
```

验收记录：RED 因 `AnchorPagerVerticalDecelerationModel`、`AnchorPagerVerticalDecelerationDriving`、display-link 抽象与生产 driver 缺失而编译失败。GREEN 的纯模型对 `v0 = 1000`、`d = 0.998`、`t = 0.1s` 得到 velocity `818.567`、delta `90.626`，覆盖负号保持、分段积分等于整段、`5 pt/s` finish，以及非有限值、非法 rate、倒退时间拒绝。Driver 使用唯一 `CADisplayLink` 和弱 owner target proxy；start replacement 只保留最新 run，cancel 幂等，finish 不发送 cancel callback，deinit 同步 invalidate，tick 无普通日志，begin/finish/cancel 各只记录固定事件。测试仅注入 display-link 生命周期和单调时钟，不创建第二套 timer。Driver + Logger 最终聚焦 15/15、0 fail、0 skip，结果包 `/private/tmp/AnchorPagerV07Task9FocusedFinal-20260715-1840.xcresult`；Framework 全量 388/388、0 fail、0 skip，结果包 `/private/tmp/AnchorPagerV07Task9FrameworkFinal-20260715-1841.xcresult`；两份 xcresult 均为 0 error、0 warning、0 analyzer warning。自审与源码隔离确认模型不 import UIKit，driver 不持有 UIScrollView、UIViewController、page/provider，不使用 Timer、delay、并发 unsafe 标记，也不直接写任何 offset；ScrollCoordinator 消费仍留在 Task 10。

---

### Task 10：把 pan velocity 接入 ScrollCoordinator 并双向合成

**Files:**
- Modify: `Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift`
- Modify: `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift`

**Interfaces:**

Child binding 的 pan callback 扩为：

```swift
onPan: (
    UIGestureRecognizer.State,
    CGFloat, // translationY
    CGFloat  // velocityY
) -> Void
```

ScrollCoordinator 增加 internal driver factory、vertical interaction identifier 和明确 cancel：

```swift
func cancelSyntheticDeceleration()

func handlePan(
    source: AnchorPagerVerticalPanSource,
    state: UIGestureRecognizer.State,
    translationY: CGFloat,
    velocityY: CGFloat
)
```

- [x] **Step 1：写 velocity capture 与原生监控阶段 RED**

container/child pan ended 都传入 `velocity(in:)`；canonical velocity 等于 `-panVelocityY`；deceleration rate 只读取 ended 时 current owner scroll view 的 `decelerationRate.rawValue`；只接受当前 owner 的 ended 样本；同一 interaction 的另一 recognizer ended 不重复启动 context；binding token stale 不启动 driver。有效样本立即启动唯一 driver 进入 monitor-native phase，tick 在触边前不得写 container/child offset；模型速度低于阈值且未触边时结束 `verticalDecelerating`。

- [x] **Step 2：写 container-to-child RED**

container 在部分折叠位置以向上 velocity 结束，driver 先 monitor；原生 callback 到 fully collapsed 后，用同一 driver 当前 sample 的剩余速度切换为 synthetic phase，只消费边界之后的 delta。container 固定 collapsed、child distance 单调增加，无 delta 丢失/反跳，不创建第二个 driver。

- [x] **Step 3：写 child-to-container RED**

child 在正 distance 以向下 velocity 结束，driver 先 monitor；原生 callback 到 child top 后切换同一 driver 为 synthetic phase。child 固定 top、container logical offset 单调下降，Header 展开；到 expanded stable boundary 停止，不创建 plain child owner。

- [x] **Step 4：写 native callback 竞争 RED**

synthetic handoff 期间旧 owner 的迟到 native offset/bounce callback 被 guarded writer 锁回 handoff boundary，不触发第二个 overscroll owner、不覆盖 driver canonical total；driver 始终是唯一 synthetic writer。

- [x] **Step 5：写取消矩阵 RED**

新 pan、selection、reload、Header layout、size、geometry、committed child identity、mode change、teardown/deinit、无效 rate、反向/低速、不可穿越边界都同步 cancel；每次只记录一次 `scroll.deceleration.cancel`。

- [x] **Step 6：运行 RED/GREEN**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerChildScrollBindingTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests test
```

- [x] **Step 7：运行 boundary/ownership 相邻回归**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerOverscrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerContainerScrollViewTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollPositionResolverTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests test
```

- [x] **Step 8：自审并提交**

```bash
git add Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift
git commit -m "合成纵向跨所有者惯性"
```

验收记录：RED 首先证明 child binding 未传 velocity、ScrollCoordinator 未区分 pan source/current owner，且缺少 monitor-native/synthetic context。GREEN 后 container/child ended 都以 `-velocityY` 形成 canonical velocity，只读取 ended 时 current owner rate；同一 interaction 只启动一个 driver，stale binding、非 owner、非法 rate、反向/低速和不可穿越边界均被拒绝。driver 在 native 触边前只累计模型 delta、零 offset 写入；触边后仅消费边界外 overflow，双向 handoff 均使用同一 driver，旧 owner 晚到 callback 只锁回自身边界，稳定端点停止且不创建 overscroll owner。取消矩阵覆盖新 pan、geometry/contentSize、committed identity、mode、boundary 与 invalidate；上层 selection/reload/Header/size 通过既有结构入口触发这些同步取消点，Task 11 再接入 matching interaction lifecycle。自审追加的 stale-driver RED 证明旧 tick 曾会误取消替换事务，修复后 interaction identifier 不匹配时静默丢弃。最终聚焦 71/71、boundary/ownership 相邻回归 86/86、Framework 全量 399/399，均 0 fail、0 skip；结果包分别为 `/private/tmp/AnchorPagerV07Task10FocusedFinal-20260715-1910.xcresult`、`/private/tmp/AnchorPagerV07Task10BoundaryFinal-20260715-1920.xcresult` 与 `/private/tmp/AnchorPagerV07Task10FrameworkFinal-20260715-1922.xcresult`，全量结果为 0 error、0 warning、0 analyzer warning。自审确认未扩大 Public API，未改变 Tabman/Pageboy containment、Host/Store generation、业务 child delegate/pan delegate/bounce/isScrollEnabled、现有 simultaneous pair 或 Overscroll policy ownership；ScrollCoordinator 仍是唯一 synthetic offset writer。

---

### Task 11：把 vertical/paging/boundary 事件接入 Interaction Coordinator

**Files:**
- Modify: `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`
- Modify: `Sources/AnchorPager/Gesture/AnchorPagerInteractionState.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

- [x] **Step 1：写纵向状态事件 RED**

container/current child began → verticalDragging；top pass-through begin → topOverscrolling；回稳定范围 → 同一 pan verticalDragging；ended 启动 monitor/synthetic driver context → verticalDecelerating，否则 idle；driver 速度阈值 finish、cancel/fail/identity change 形成 matching finish/cancel。不得依赖业务 child `scrollViewDidEndDecelerating` 或 `isDecelerating` KVO。

- [x] **Step 2：写 paging 状态 RED**

Host explicit start → programmaticPaging；Pageboy interactive will → horizontalPaging；semantic did/cancel 与 required acknowledgements 全部到达才 finish；size 中 terminal 清 suspended paging；冲突 interactive will 不建立第二 active。

- [x] **Step 3：写跨域优先级 RED**

verticalDragging/topOverscrolling 时 selection/reload/layout 只排队；verticalDecelerating 时 selection/reload/layout 先同步 cancel driver 再 drain；programmatic/horizontal paging 阻塞结构性 reload/layout；size 最高优先。

- [x] **Step 4：实现结构化 delegate 装配**

ScrollCoordinator/Host 只向 ViewController 发送 internal interaction lifecycle；ViewController 转交 Interaction Coordinator 并请求统一 drain。任何 coordinator 都不直接调用另一个 specialized coordinator 的 offset/page API。

- [x] **Step 5：运行集成回归**

```bash
xcodebuild -quiet -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerTests/AnchorPagerInteractionCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

- [x] **Step 6：所有权源码扫描、自审并提交**

确认 v0.7 新文件没有业务 `.delegate =`、`.isScrollEnabled =`、`.bounces =`、`.alwaysBounceVertical =`，Public 目录没有 Tabman/Pageboy import。

```bash
git add Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift Sources/AnchorPager/Gesture/AnchorPagerInteractionState.swift Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "装配跨域交互生命周期"
```

验收记录：RED 因 vertical/paging 结构化 event 与 delegate 边界缺失而编译失败。首轮 GREEN 暴露把 reload interaction begin 混入 `willPerformReloadRequest` 会破坏该回调既有 provider-generation lease 职责；修复后由 Host 单独发 reload begin/finish/cancel，`willPerform` 恢复只管理 matching generation。ScrollCoordinator 以同一 identifier 发出 drag、top enter/leave、deceleration 与 matching terminal；自审补充的未呈现 top 回稳 RED 修复了 Overscroll owner 已 finish 但 interaction 仍停在 top 的缺口。第二轮自审 RED 又证明 top mode 未变化时取消真实 drag、以及 size state 建立前的 Scroll cancel 可能抢先 drain pending；GREEN 后 same-mode 为 no-op，尺寸入口先建立最高优先 state、暂停 Host，再取消 boundary/driver。PagingHost 只在真实 explicit execution/interactive admission 后 begin，interactive semantic 或 explicit semantic + completion + executor-ready 全部满足后 finish，结构 teardown/adapter reject 才 cancel。ViewController 统一映射事件、暂停 Host execution，并保持 active Pageboy 跨 size 时恢复 matching paging state；vertical deceleration 的 selection/reload/Header/size 路径先同步取消 driver 再按 reload → Header → selection 排空。最终聚焦 Interaction/Scroll/Host/ViewController 226/226、Framework 全量 413/413，均 0 fail、0 skip；结果包分别为 `/private/tmp/AnchorPagerV07Task11FocusedFinal3-20260715-2052.xcresult` 与 `/private/tmp/AnchorPagerV07Task11FrameworkFinal2-20260715-2055.xcresult`，两份均为 0 error、0 warning、0 analyzer warning。新增行扫描对业务 `.delegate =`、`.isScrollEnabled =`、`.bounces =`、`.alwaysBounceVertical =` 零命中，Public 目录 Tabman/Pageboy 零命中。自审确认 Interaction Coordinator 不持有 payload/UIKit/offset，Host 继续独占 reload/selection transaction，Store/provider generation、Pageboy containment、业务 child ownership 与 Scroll/Overscroll writer/policy 边界未改变。

---

### Task 12：扩展示例探针与横向业务页面

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`

**Scope:**
- 在现有四页之后追加“横向页”，不改变 empty/short/long/plain 的既有 index。
- 横向页上半区域是真实业务 horizontal UIScrollView，下半区域保留 Pageboy 页面滑动命中区；其业务 scroll/pan delegate identity 和 scroll configuration 可由隐藏 accessibility probe 报告。
- 新增 selection event probe，记录 public didSelect 序列；launch argument 可在首个 visible terminal 后连续发出 API targets，不能调用 internal API。
- 扩充纵向 probe：记录 canonical total、方向反转最大值、stable invariant violation、container→child/child→container handoff 是否出现、采样数；只序列化数值，不输出 view hierarchy 或业务内容。

- [ ] **Step 1：先写 Example unit RED**

覆盖新 probe serialization/reset、selection trace、横向页在第五页、业务 delegate/configuration baseline、momentum sample 的单调/反向/owner-conflict 计算。interaction UI test control 只在 launch argument 开启后安装，其 action 在同一调用栈调用公开 `setSelectedIndex`；reload/layout 竞争入口由真实 child `scrollViewDidScroll` 且 `isTracking == true` 时一次性触发公开 API，不使用 timer。

- [ ] **Step 2：运行 RED**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests test
```

- [ ] **Step 3：最小实现示例与探针**

复用现有可见页 CADisplayLink sampler，不创建第二个滚动采样 timer；隐藏 probe 不遮挡业务点击，不改变框架 Public API。

- [ ] **Step 4：运行 Example unit GREEN 与 generic build**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests test
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' build
```

- [ ] **Step 5：自审并提交**

```bash
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift
git commit -m "扩展示例交互验收探针"
```

---

### Task 13：真实选择、reload/layout/size UI 验收

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`（仅测试装配缺口）

- [ ] **Step 1：写快速 API 与 bar RED**

新增 UI tests：

```text
testRapidPublicSelectionsCommitRealIntermediateThenLatestTarget()
testRapidBarSelectionsUseLatestPendingWithoutHanging()
testMixedAPIAndBarSelectionsShareOneLatestPendingQueue()
testNonadjacentSelectionUsesSingleSourceTargetTransition()
```

断言 public selection trace、真实页面内容、appearance count 一致，无第二笔悬空。

- [ ] **Step 2：写真实 interactive completion/cancel RED**

保留既有 cancel appearance 测试并增加完成/取消后立刻发新 explicit request；断言 Store/public/visible 页面一致，旧 callback 不覆盖新 intent。

- [ ] **Step 3：写 reload/layout/size 竞争 RED**

真实按住纵向 drag 时触发 public reload/layout 测试入口，断言触摸结束前不结构性切换；latest request 在 idle 执行。横向 paging/size transition 场景使用 Example 测试入口触发，断言不伪造 cancel、不重复 didSelect、不遗留 presentation。

- [ ] **Step 4：运行新增 UI tests 并修到 GREEN**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testRapidPublicSelectionsCommitRealIntermediateThenLatestTarget \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testRapidBarSelectionsUseLatestPendingWithoutHanging \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testMixedAPIAndBarSelectionsShareOneLatestPendingQueue \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testNonadjacentSelectionUsesSingleSourceTargetTransition test
```

- [ ] **Step 5：运行 paging/lifecycle 相邻 UI 回归**

至少包含 `testTappingTabBarSelectsPageContent`、`testHorizontalSwipeSelectsNextPageContent`、`testReloadReplacesOldPageGenerationAndKeepsPageInteractive`、`testCompletedPageSwitchProducesOneAdditionalDidAppear`、`testCancelledInteractivePagingKeepsAppearanceAndSelectionConsistent`。

- [ ] **Step 6：自审并提交**

```bash
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "验收分页选择与事务竞争"
```

---

### Task 14：真实惯性、系统返回与业务横向手势 UI 验收

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`（仅测试装配缺口）
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`（仅探针缺口）

- [ ] **Step 1：写双向惯性 RED**

新增：

```text
testFastUpwardFlingHandsRemainingVelocityFromContainerToChild()
testFastDownwardFlingHandsRemainingVelocityFromChildToContainer()
testPlainPageFlingNeverCreatesSyntheticChildOwner()
testTopModesAndBottomBoundariesDoNotCrossContaminateMomentumOwner()
```

以真实 `press(...thenDragTo:withVelocity:)` 触发，probe 断言跨过 handoff 两侧、canonical total 同向、最大反跳 ≤ 0.5pt、stable invariant violation ≤ 0.5pt、最终 owner/offset 合法、Header/bar/page presentation 无跳变。

- [ ] **Step 2：写系统返回 RED**

push 第二个 AnchorPager，在 leading edge 右滑；第一页和非第一页分别验证 interactive pop 优先，导航栈返回且 Pageboy selection trace 不变。

- [ ] **Step 3：写横向业务 scroll RED**

在“横向页”上半命中真实业务 scroll，断言业务 contentOffset.x 改变而 Pageboy 不切页；在下半页面区域横滑，断言 Pageboy 切页。前后读取 probe，确认业务 scroll delegate、pan delegate、isScrollEnabled、bounces、alwaysBounceVertical 身份/值不变。

- [ ] **Step 4：写横纵竞争 RED**

在长页做斜向快速手势，断言 UIKit 只形成一个合法主 interaction terminal；无 duplicate selection、无双 owner、无残留 synthetic driver。

- [ ] **Step 5：运行新增 UI tests 并修到 GREEN**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testFastUpwardFlingHandsRemainingVelocityFromContainerToChild \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testFastDownwardFlingHandsRemainingVelocityFromChildToContainer \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testLeadingEdgeInteractivePopWinsOverPageboyPaging \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalBusinessScrollWinsOnlyInsideItsHitRegion test
```

- [ ] **Step 6：运行全部 v0.5/v0.6 边界 UI 回归**

复跑单次上下 handoff、plain top/bottom、real child container/child/none top、real child bottom、页面切换 rebind、顶部行为与 Header 内容稳定测试。

- [ ] **Step 7：自审并提交**

```bash
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "验收惯性与横向手势优先级"
```

---

### Task 15：文档迁移、全量门禁与 fresh-pass

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- Modify: `docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md`
- Modify: `docs/superpowers/plans/2026-07-15-v0-7-interaction-selection-momentum.md`
- Modify: `AGENTS.md`

- [ ] **Step 1：同步长期文档但只写真实完成状态**

记录 Host/Adapter/Interaction/ViewController drain/Scroll/Overscroll 唯一事实源；README 仅在真实惯性完成后移除对应 known limitation；记录 failure relation 不能动态移除的 UIKit 限制；roadmap 删除旧 GestureCoordinator 提交 selection 的表述；task-list 逐项勾选真实完成项。

- [ ] **Step 2：运行静态门禁**

```bash
git diff --check
swift package resolve
rg -n 'import (Tabman|Pageboy)' Sources/AnchorPager/Public
rg -n '\.(delegate|isScrollEnabled|bounces|alwaysBounceVertical)\s*=' Sources/AnchorPager/Children Sources/AnchorPager/Gesture Sources/AnchorPager/Core Sources/AnchorPager/Paging
```

预期：Public 无第三方 import；业务 ownership 扫描只允许既有 container/Pageboy 自有配置，不得命中新业务 child 写入。

- [ ] **Step 3：运行 Framework 全量**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -resultBundlePath /private/tmp/AnchorPagerV07FrameworkFull-20260715.xcresult test
```

- [ ] **Step 4：运行 Example 全量与 generic build**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/AnchorPagerV07ExampleFull-20260715.xcresult test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -resultBundlePath /private/tmp/AnchorPagerV07ExampleBuild-20260715.xcresult build
```

- [ ] **Step 5：检查 xcresult 与运行时问题**

```bash
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerV07FrameworkFull-20260715.xcresult
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerV07ExampleFull-20260715.xcresult
```

记录真实 test count、0 fail、0 skip、0 error/warning/analyzer warning；检索 UIKit `LayoutConstraints`、gesture、appearance、resource release 相关 issue。任一异常都必须回到 `systematic-debugging`，补 RED 后修复。

- [ ] **Step 6：任务级自审**

逐项检查 Public API、Tabman/Pageboy containment、PageStateStore generation/cache、selection commit/cancel、reload terminal、child lifecycle/appearance、scroll discovery、managed inset、gesture delegates、bounce/configuration、MainActor、日志、Example 与文档。

- [ ] **Step 7：fresh-pass 独立复审**

使用 `superpowers:requesting-code-review` 从设计起点到当前 HEAD 重读完整 diff；在当前会话本地执行，除非用户明确要求 subagent。按 Critical/Important/Minor 记录发现；任何 Critical/Important 必须先补 RED、修复、重跑相邻与全量门禁，不得直接标记 Ready。

- [ ] **Step 8：生产 HEAD 最终复验**

fresh-pass 修复后使用新的 `Final` 结果包重跑 Framework、Example、generic build；文档记录最终生产 HEAD、测试统计、结果包、0 fail/skip/error/warning/analyzer warning 和复审结论。

- [ ] **Step 9：最终文档提交**

```bash
git add AGENTS.md README.md docs/architecture.md docs/task-list.md docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md docs/superpowers/plans/2026-07-15-v0-7-interaction-selection-momentum.md
git commit -m "完成 v0.7 全量验收与文档收口"
```

只有 Task 0–15、全量门禁和 fresh-pass 全部完成，才能把 v0.7 标记为 Ready 并进入 v0.8。
