# v0.4 Reload 代际原子性修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 deferred reload 从 metadata snapshot、Host start、provider generation 到 page/empty terminal 形成同一 request 事务，并隔离跨 generation 的 retention、snapshot 和 ownership 状态，为 v0.5 提供可信 committed current child/scroll target。

**Architecture:** PagingHost 用 internal request identifier 串行化 pending/active reload；ViewController 在 Host 真正开始 request 时只激活 provider generation，在匹配 terminal 时才发布 public visible snapshot。PageStateStore 把共享 live identity payload 与 generation-specific lease/snapshot 分开，provider 读取 pending、visible/selection/inset 读取 committed。

**Tech Stack:** Swift 6、UIKit、Swift Package Manager、XCTest、XCUITest、Tabman 4.0.1、Pageboy 5.0.2、iOS 14+

## Global Constraints

- 不新增或修改 public API。
- Tabman/Pageboy 类型继续只出现在 `Sources/AnchorPager/Paging/`。
- 普通业务 page containment 和 appearance 继续只由 Pageboy/UIKit 执行。
- Host 只管理 request 串行化、adapter containment 和标准 terminal，不管理 page identity、snapshot 或 ownership。
- Store 是 generation、page identity、retention、snapshot 和 ownership 策略的唯一 owner。
- deferred terminal 前 public、visible Store、旧 page 和 ownership 保持 committed 一致。
- 不使用 timer、dispatch delay、强制取消手势、AnchorPager sentinel、手工 appearance forwarding 或第三方 internal API。
- 保留 Pageboy 5.0.2 delete-last-page teardown 兼容边界及升级门禁。
- UIKit、data source、Host、Store 和 coordinator 状态保持 `@MainActor`。
- 每个任务严格执行 RED → GREEN → REFACTOR，并在独立复审清零 Critical/Important 后继续。
- 复用已启动的 `iPhone 17` simulator，不执行无必要 boot/shutdown。

---

## 文件结构

### 修改

- `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`：request identifier、pending/active 串行化、willPerform/terminal 关联。
- `Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift`：provider/visible generation 分离、live payload 与 generation state 隔离、committed current 入口。
- `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：staged ReloadSnapshot、provider activation、terminal public commit。
- `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`：request latest-wins、active 串行和 stale terminal。
- `Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift`：generation isolation、migration、ownership 和 committed current。
- `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：端到端 deferred 区间和 pre-load reload。
- `README.md`、`docs/architecture.md`、`docs/task-list.md`、roadmap、fixed-paging spec、v0.4 相关 spec/plan：真实状态和后续版本门禁。

---

### Task 1: PagingHost request identity 与串行 terminal

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`

**Interfaces:**
- Produces:

```swift
typealias AnchorPagerPagingReloadRequestIdentifier = Int

protocol AnchorPagerPagingHostViewControllerDelegate: AnyObject {
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willPerformReloadRequest identifier: AnchorPagerPagingReloadRequestIdentifier
    ) -> Bool
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    )
}
```

- Changes Host API to:

```swift
func reload(
    requestIdentifier: AnchorPagerPagingReloadRequestIdentifier,
    titles: [String],
    pageCount: Int,
    selectedIndex: Int
)
```

- [ ] **Step 1: 写 request identity RED 测试**

新增测试覆盖：

```swift
func testDeferredReloadOnlyStartsLatestRequestAfterSelectionTerminal()
func testActiveReloadSerializesNewerRequestUntilMatchingTerminal()
func testTerminalCarriesActiveRequestIdentifier()
func testRejectedWillPerformDoesNotCallAdapterOrEmitTerminal()
func testPendingOrActiveReloadRejectsProgrammaticSelection()
```

Recording delegate 记录 `.willPerform(id)`、`.reload(id, terminal)`；测试必须通过真实 `host.reload` 和 adapter
did/cancel/reload 回调驱动，不直接调用 ViewController。

- [ ] **Step 2: 运行 Host 测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests test
```

Expected: 编译失败或断言失败，现有 Host 没有 request identifier/active request，也会让 terminal 无法关联事务。

- [ ] **Step 3: 实现 pending/active request 状态**

```swift
private struct ReloadRequest {
    let identifier: AnchorPagerPagingReloadRequestIdentifier
    let titles: [String]
    let pageCount: Int
    let selectedIndex: Int
}

private var pendingReloadRequest: ReloadRequest?
private var activeReloadRequest: ReloadRequest?
```

`reload` 在 active request 或 adapter selection busy 时只覆盖 pending；`performReload` 先调用 `willPerform`，接受后
设置 active，再调用 adapter reload/empty teardown。page/empty terminal 只能使用 active ID。

- [ ] **Step 4: terminal 后推进 latest pending**

统一 terminal helper：

```swift
private func finishActiveReload(with terminal: AnchorPagerPagingReloadTerminal) {
    guard let request = activeReloadRequest else { return }
    eventDelegate?.pagingHost(
        self,
        didReload: terminal,
        requestIdentifier: request.identifier
    )
    activeReloadRequest = nil
    _ = performPendingReloadIfNeeded()
}
```

如果 delegate 拒绝 willPerform，记录 `paging.reload.stale`，不调用 Pageboy、不发 terminal；若仍有更新 pending，继续
尝试最新 request。不得递归无限重试同一 rejected request。

- [ ] **Step 5: 运行 Adapter + Host 回归**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests test
```

- [ ] **Step 6: 提交 Host request 边界**

```bash
git add Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift \
  Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift
git commit -m "串行化分页 reload request terminal"
```

---

### Task 2: PageStateStore generation-specific lease 与 committed current

**Files:**
- Modify: `Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift`

**Interfaces:**
- Produces internal committed-current accessors:

```swift
var committedCurrentIndex: Int? { get }
var committedCurrentPageViewController: UIViewController? { get }
var committedCurrentScrollView: UIScrollView? { get }
```

- Provider path continues through `pageViewController(at:context:originalProvider:)`.
- Selection/inset/query paths consume visible generation (`committed ?? pending`).

- [ ] **Step 1: 写 provider/visible generation RED 测试**

```swift
func testPendingProviderGenerationDoesNotReplaceCommittedVisibleCurrentBeforeCommit()
func testCommittedCurrentAccessorsIgnorePendingGeneration()
func testPendingCancelLeavesCommittedManagedInsetAndRetentionUnchanged()
```

构造 committed generation 1 后 begin generation 2；让 provider 请求 generation 2 页面，同时断言 current page/scroll、
retention reasons、inset adjustment behavior 和 ownership 仍来自 generation 1。

- [ ] **Step 2: 写 migration 可变状态隔离 RED 测试**

分别覆盖 scroll page 和 fallback page：

```swift
func testMovedScrollPageMigrationDoesNotMutateCommittedLeaseBeforeTerminal()
func testMovedFallbackMigrationDoesNotRemoveCommittedContentBeforeTerminal()
func testSameIndexMigrationSharesLiveIdentityButNotGenerationState()
```

旧 current controller 从 generation 1 index 0 移到 generation 2 非 current index 1；terminal 前旧 state identifier、
retention、offset、managed inset、fallback parent/content必须保持。新旧 generation state identifier 必须不同。

- [ ] **Step 3: 运行 Store 测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests test
```

Expected: 现有 `activeGeneration = pending ?? committed` 和共享 `PageState` 使 visible/current 或 retention 断言失败。

- [ ] **Step 4: 拆分 live payload 与 generation state**

```swift
private final class PageIdentityPayload {
    weak var originalViewController: UIViewController?
    weak var actualPageViewController: UIViewController?
    weak var scrollView: UIScrollView?
    weak var fallbackHost: AnchorPagerPageScrollHostViewController?
    var originalViewControllerIdentifier: ObjectIdentifier?
    var claimedScrollViewIdentifier: ObjectIdentifier?
    var hasLoadedBefore = false
}

private final class GenerationPageState {
    let identity: PageIdentityPayload
    var retainedPage: UIViewController?
    var retentionReasons: Set<RetentionReason> = []
    var childDistanceFromTop: CGFloat

    init(identity: PageIdentityPayload, childDistanceFromTop: CGFloat = 0) {
        self.identity = identity
        self.childDistanceFromTop = childDistanceFromTop
    }
}
```

`GenerationState.pages` 改为 `[Int: GenerationPageState]`。migration 创建新的 generation state：同 index 复制
distance，移动 index 使用 0；只共享 payload。

- [ ] **Step 5: 分离 provider/visible/committed generation**

```swift
private var providerGeneration: GenerationState? {
    pendingGeneration ?? committedGeneration
}

private var visibleGeneration: GenerationState? {
    committedGeneration ?? pendingGeneration
}
```

page provider 使用 provider；selection、managed inset、现有查询使用 visible。committed-current accessors严格只读
`committedGeneration`，没有 committed 时返回 nil。

- [ ] **Step 6: 让 ownership release 发生在 commit 边界**

pending reconcile 可以更新 pending reason/strong lease，但共享 payload 不归还 committed ownership。pending cancel 和
old generation release 使用 actual page/scroll/fallback identity preservation，不使用 generation state 对象地址。

commit 顺序：

```text
pending -> committed
release old generation leases, preserving shared payload
force reconcile new committed ownership
cleanup old unique fallback/scroll ownership
```

删除只为共享可变 state 回滚服务的 `migratedPreviousDistances`。

- [ ] **Step 7: 运行 Store + inset/fallback 回归**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests \
  -only-testing:AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerPageScrollHostViewControllerTests test
```

- [ ] **Step 8: 提交 generation state 隔离**

```bash
git add Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift \
  Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift
git commit -m "隔离页面代际 retention 与 ownership"
```

---

### Task 3: ViewController staged snapshot 与 terminal public commit

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Consumes Task 1 Host request identifier/willPerform/terminal APIs.
- Consumes Task 2 Store provider generation and committed-current accessors.
- Produces private `ReloadSnapshot` and request lifecycle helpers.

- [ ] **Step 1: 写 deferred 端到端 RED 测试**

```swift
func testDeferredReloadKeepsCommittedPublicAndVisibleStoreStateUntilTerminal()
func testDeferredLatestReloadDoesNotLetOldAdapterFetchPendingGeneration()
func testDeferredEmptyKeepsOldOwnershipUntilEmptyTerminal()
func testFirstTerminalCannotCommitSupersedingSnapshot()
```

使用真实 ViewController + Host + Adapter + Store 路径：programmatic selection 保持 busy，调用多次 reload；terminal 前
断言旧 effective selection、Header、actual page、scroll target、inset ownership和 provider identity均不变。

- [ ] **Step 2: 写 pre-load RED 回归**

```swift
func testPreloadReloadPublishesInitialMetadataWithoutLoadingPagingView()
func testPreloadSelectionUpdatesStagedRequestUsedAtFirstTerminal()
```

保持现有行为：view 未加载时 reloadData 后 public selection 可读，`setSelectedIndex` 可更新；不得因此加载 Host/adapter
view。view load 后首个 Host request 使用最终 selected index。

- [ ] **Step 3: 运行 ViewController 测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

- [ ] **Step 4: 实现 ReloadSnapshot staging**

```swift
private struct ReloadSnapshot {
    let requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    let pageCount: Int
    var selectedIndex: Int
    let titles: [String]
    let headerContent: AnchorPagerHeaderContent?
    var providerGenerationIsActive: Bool
}

private var nextReloadRequestIdentifier = 0
private var stagedReloadSnapshot: ReloadSnapshot?
private var activeReloadRequestIdentifier: AnchorPagerPagingReloadRequestIdentifier?
```

metadata callback transaction 完成后只创建 latest snapshot。view 已加载时 enqueue Host；未加载且没有 committed visible
state时走 initial fast path，发布 metadata并 begin provider generation，但不加载 view。

- [ ] **Step 5: 实现 willPerform provider activation**

```swift
func pagingHost(
    _ host: AnchorPagerPagingHostViewController,
    willPerformReloadRequest identifier: AnchorPagerPagingReloadRequestIdentifier
) -> Bool {
    guard var snapshot = stagedReloadSnapshot,
          snapshot.requestIdentifier == identifier else { return false }
    if !snapshot.providerGenerationIsActive {
        pageStateStore.beginReload(...)
        snapshot.providerGenerationIsActive = true
        stagedReloadSnapshot = snapshot
    }
    activeReloadRequestIdentifier = identifier
    return true
}
```

该阶段不写 `pageCount/selectedIndex/currentHeaderContent/currentTitles`，不安装 Header，不通知 public delegate。

- [ ] **Step 6: 实现匹配 terminal 原子 commit**

terminal 必须同时匹配 active ID 和 staged snapshot。顺序：Store commit → publish snapshot fields → page terminal index
收敛 Store committed current → 安装 Header/更新布局 → 清 active/staged。empty 保持 selectedIndex 0/effective nil。

迟到或不匹配 terminal 记录 `paging.reload.stale` 并 no-op，不能提交 latest snapshot。

- [ ] **Step 7: 更新 pre-load selection 与 viewDidLoad submit**

view 未加载时 `setSelectedIndex` 同步更新 initial snapshot selected index 和 pending provider current；`viewDidLoad` 安装已
发布 Header后 enqueue snapshot request。不得创建第二个 request ID或重复 begin generation。

- [ ] **Step 8: 运行端到端组合回归**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

- [ ] **Step 9: 提交端到端 staged reload**

```bash
git add Sources/AnchorPager/Public/AnchorPagerViewController.swift \
  Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "原子提交 reload public 与 provider 代际"
```

---

### Task 4: 后续版本架构审查、文档与完整验收

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- Modify: `docs/superpowers/specs/2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md`
- Modify: `docs/superpowers/specs/2026-07-12-v0-4-child-lifecycle-cache-design.md`
- Modify: `docs/superpowers/specs/2026-07-12-v0-4-reload-terminal-repair-design.md`
- Modify: `docs/superpowers/specs/2026-07-12-v0-4-generation-atomicity-repair-design.md`
- Modify: `docs/superpowers/plans/2026-07-12-v0-4-generation-atomicity-repair.md`

**Interfaces:**
- Documents Task 1–3 final contracts.
- Produces v0.5–v0.9 reviewed entry constraints; does not implement later versions.

- [ ] **Step 1: 审查 v0.5 任务边界**

逐项确认 v0.5 `AnchorPagerScrollCoordinator`：

- 只读 Store committed current page/scroll target；空态为 nil。
- 不缓存 adapter、不读取 provider pending、不复制 page identity/cache/generation。
- reload/selection terminal 后重新绑定 current child。
- 纵向 handoff 和最小 simultaneous recognition留在 v0.5；不提前实现 v0.7 完整 interaction state。

- [ ] **Step 2: 审查 v0.6–v0.9 架构依赖**

- v0.6/v0.8 只消费 committed current/empty owner。
- v0.7 扩展 Host 标准 request/selection transaction，不建立第二套 generation owner。
- v0.9 accessibility/RTL 不读取 provider pending。
- Pageboy 升级门禁覆盖 teardown、request terminal、appearance 和 provider activation。

若任务列表存在重复 owner 或错误依赖，先更新设计和 task-list，不实现后续代码。

- [ ] **Step 3: 同步 v0.4 真实状态和测试证据**

更新架构、README、task-list、roadmap 和相关 spec/plan；只有 Task 1–3 独立复审通过后才恢复 v0.4 完成状态。
记录最终复审曾发现的两个 Important 及对应 RED/GREEN，不引用 `/private/tmp` 作为仓库资产。

- [ ] **Step 4: 运行完整验收**

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test
```

记录 tests 数量、fail/skip、耗时和 Pageboy/Tabman privacy warnings；复用模拟器。

- [ ] **Step 5: 最终自审与独立复审**

自审 public API、第三方边界、containment/appearance、request identity、provider/visible generation、migration、
ownership、pre-load、MainActor、日志、测试和文档。独立复审比较 `e5447a5` 或本修复设计前基线到 HEAD；
Critical/Important 必须清零。

- [ ] **Step 6: 提交验收文档**

```bash
git add README.md docs AGENTS.md
git commit -m "完成 v0.4 reload 代际原子性修复验收"
```

---

## 实施检查点

1. Task 1 后复审 Host 是否只拥有 request 串行和 adapter containment。
2. Task 2 后复审 pending migration 是否完全不修改 committed lease/snapshot/ownership。
3. Task 3 后复审 deferred 区间 public、visible Store、old page/provider identity 是否一致。
4. Task 4 后完整验收和独立复审通过，才开放 v0.5。

## 计划自审

- Spec coverage：两个最终复审 Important 分别由 Task 1/3 和 Task 2 覆盖；v0.5 committed current 由 Task 2/4 覆盖。
- Type consistency：Host request identifier 从 Task 1 产出，Task 3 原样消费；Store committed-current 从 Task 2 产出，Task 3/4 原样消费。
- Scope：不实现 v0.5+；后续版本只做任务和架构审查。
- 占位符扫描：未发现未决项、空白步骤或模糊的后续补充描述。
