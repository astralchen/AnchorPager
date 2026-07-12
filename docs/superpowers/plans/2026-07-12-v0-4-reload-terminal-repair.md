# v0.4 Reload Terminal 修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复非空到空 reload 的旧 Pageboy 内容残留，建立统一 page/empty terminal、public reload 重入保护，并补齐 v0.4 appearance cancel 和文档验收。

**Architecture:** viewport 长期 contain `AnchorPagerPagingHostViewController`，host 按空/非空状态 contain 或移除 `AnchorPagerPagingAdapter`，并向主控制器发送领域无关 reload terminal。移除前由 adapter 的集中 Pageboy 5.0.2 兼容 shim 通过第三方 public delete-last-page 先解除业务页面，再清理只剩 plumbing 的 UIKit containment。`AnchorPagerViewController.reloadData()` 使用 transaction token 采集局部数据快照，只有最新事务才能发布并开始 Store generation。

**Tech Stack:** Swift 6、UIKit、Swift Package Manager、XCTest、XCUITest、Tabman 4.0.1、Pageboy 5.0.2、iOS 14+

## Global Constraints

- 不新增或修改 public API。
- Tabman/Pageboy 类型继续只出现在 `Sources/AnchorPager/Paging/`。
- 普通业务页面 containment 和 appearance 继续只由 Pageboy/UIKit 执行。
- PagingHost 只管理 adapter containment，不管理页面 identity、snapshot 或 inset ownership。
- Store 只在 paging host 的 page/empty terminal 后提交 pending generation。
- 所有 data source、UIKit、paging host、Store 和 coordinator 操作保持 `@MainActor`。
- 不使用 timer、生产异步延迟、AnchorPager sentinel page、手工 appearance forwarding 或第三方 internal API；
  允许 Pageboy public delete-last-page 内部使用其零页 reset controller，但不得把它暴露为业务 page。
- Pageboy 5.0.2 空态 teardown 只能封装在 adapter 的单一兼容入口；依赖升级必须重审对应源码契约与回归测试。
- selection transaction 活跃时 Host 只保留 latest pending reload；由 did/cancel terminal 驱动继续，不使用 timer 或
  dispatch delay。
- 每项行为严格执行 RED → GREEN → REFACTOR。
- 复用当前 `iPhone 17` simulator，不执行无必要 boot/shutdown。

---

## 文件结构

### 新增

- `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`：稳定 viewport child、adapter containment 和 reload terminal 标准化。
- `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`：host 空/非空状态、containment、terminal 和转发测试。

### 修改

- `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`：保持非空 Pageboy reload，向 host 转发 page terminal。
- `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：contain host、消费 terminal、引入 reload transaction。
- `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：空 reload、重入、负 count 和现有 adapter 访问迁移。
- `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`：增加测试专用跨页面 appearance recorder。
- `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：增加真实交互取消验收。
- `README.md`、`docs/architecture.md`、`docs/task-list.md`、相关 spec/plan、`AGENTS.md`：同步真实状态与验收证据。

---

### Task 1: PagingHost 空/非空 terminal 与 containment

**Files:**
- Create: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`

**Interfaces:**
- Produces:

```swift
@MainActor
enum AnchorPagerPagingReloadTerminal: Equatable {
    case page(index: Int)
    case empty
}

@MainActor
protocol AnchorPagerPagingHostViewControllerDelegate: AnyObject {
    func pagingHost(_ host: AnchorPagerPagingHostViewController, didReload terminal: AnchorPagerPagingReloadTerminal)
    func pagingHost(_ host: AnchorPagerPagingHostViewController, willSelect index: Int, animated: Bool)
    func pagingHost(_ host: AnchorPagerPagingHostViewController, didSelect index: Int, animated: Bool)
    func pagingHost(_ host: AnchorPagerPagingHostViewController, didCancelSelectionAt index: Int, returningTo previousIndex: Int)
    func pagingHost(_ host: AnchorPagerPagingHostViewController, didUpdateBarInsets barInsets: UIEdgeInsets)
}
```

- Host API:

```swift
weak var pageProvider: AnchorPagerPageProviding?
weak var eventDelegate: AnchorPagerPagingHostViewControllerDelegate?
var activeAdapter: AnchorPagerPagingAdapter? { get }
func reload(titles: [String], pageCount: Int, selectedIndex: Int)
func setBarHeight(_ height: CGFloat?)
func setSelectedIndex(_ index: Int, animated: Bool) -> Bool
```

- [x] **Step 1: 写 PagingHost RED 测试**

覆盖：首次非空 reload 安装一个 adapter；连续非空 reload 复用实例；reload 空数据按标准 UIKit 顺序移除 adapter 并发送一次 `.empty`；空到空幂等；空到非空安装新 adapter；barInsets 在空状态回零。

- [x] **Step 2: 运行测试并确认预期失败**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests test
```

Expected: 编译失败，提示 PagingHost/terminal 类型不存在。

- [x] **Step 3: 实现最小 PagingHost**

host `loadView` 使用透明 UIView。安装 adapter 时执行 `addChild`、约束四边、`didMove`；清理时执行
`willMove(nil)`、移除 view、`removeFromParent`。空 terminal 只能在 containment 清理和 barInsets 回零之后发送。

- [x] **Step 4: 转发 adapter selection/bar/page terminal**

Host conform `AnchorPagerPagingAdapterDelegate`。adapter `didReloadAt` 转为 `.page(index:)`；Host 不把 adapter
实例或 Tabman/Pageboy 类型传给上层。

- [x] **Step 5: 运行 Host 与 Adapter 测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

Expected: 两组测试全部通过，Public source scan 无回归。

- [x] **Step 6: 提交 Host 边界**

```bash
git add Sources/AnchorPager/Paging Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift
git commit -m "修复空分页 reload terminal"
```

---

### Task 2: 主控制器接入 Host 与空 generation 收敛

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Consumes Task 1 PagingHost API 和 `AnchorPagerPagingReloadTerminal`。
- `AnchorPagerViewController` conform `AnchorPagerPagingHostViewControllerDelegate`，不再直接 conform adapter delegate。

- [x] **Step 1: 写非空到空 RED 测试**

真实加载 scroll page 后把 data source count 改为 0 并 reload，断言：

```swift
XCTAssertNil(pager.effectiveSelectedIndex)
XCTAssertNil(pagingHost.activeAdapter)
XCTAssertNil(oldPage.parent)
XCTAssertEqual(oldScrollView.contentInsetAdjustmentBehavior, originalBehavior)
```

同时覆盖 fallback page 的业务 child `parent == nil`、view 已移除。

- [x] **Step 2: 运行测试并确认旧实现失败**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

Expected: 旧 adapter/page 仍存在，RED 失败。

- [x] **Step 3: 写 adapter teardown 兼容 RED 并实现集中 shim**

先在真实 Pageboy containment 中断言：旧 scroll/fallback page 的 `parent`/view superview 被同步清空，且清理过程
不发送 page/selection terminal。然后实现 adapter internal `prepareForRemoval()`：先清空自身 data source 状态，
再调用 Pageboy 5.0.2 public `deletePage`。completion 只记录同步完成；delete 整体返回并确认 public count 0/current
index nil 后，post-order 清理 adapter 剩余 direct-child plumbing。不得识别第三方类型、访问 third-party internal，
也不得手拆原业务 page。

- [x] **Step 4: Host 清理必须先执行 adapter teardown**

Host 只能在 `prepareForRemoval()` 返回后执行 adapter `willMove(nil)`、移除 view、`removeFromParent()`、barInsets
归零和 `.empty` terminal。测试在 terminal 快照中同时断言 active adapter、Host children、旧业务 page parent 均为空；
另以测试端 main-queue turns 验证 adapter/inner/reset placeholder 最终 weak 释放，生产代码不得等待析构。

- [x] **Step 5: selection 中 reload 使用 latest pending request**

Adapter 提供无副作用 reload-readiness，只依赖 will/did/cancel transaction 和 programmatic completion，不把
tracking/dragging/decelerating 当成额外 terminal；Host 在 readiness false 时暂存最新 titles/count/index，不调用
Pageboy。did/cancel semantic terminal 到达后，若有 pending reload，则不向上层提交旧 selection，立即执行最新
request；programmatic 路径继续等待 completion。覆盖 animated selection→empty、interactive cancel→empty、
selection→连续 empty/nonempty latest-wins，并断言没有 assertion、假 reload terminal、pending generation 提前提交
或物理滚动结束无回调造成的悬挂。pending 期间 `setSelectedIndex` 返回 false。

- [x] **Step 6: 把根布局 containment 改为稳定 Host**

用 `private let pagingHost = AnchorPagerPagingHostViewController()` 替换直接 adapter 属性。Header 下方约束对象改为
host view；`setBarHeight`、reload、selection 和 barInsets 均经 host 转发。

- [x] **Step 7: 消费 page/empty terminal**

统一实现：

```swift
func pagingHost(
    _ host: AnchorPagerPagingHostViewController,
    didReload terminal: AnchorPagerPagingReloadTerminal
) {
    guard let generation = pendingReloadGeneration else { return }
    pageStateStore.commitReload(generation: generation)
    pendingReloadGeneration = nil
    if case let .page(index) = terminal, (0..<pageCount).contains(index) {
        pageStateStore.didSelect(index, context: pageAccessContext)
    }
}
```

删除 `pageCount == 0` 直接 commit 特例。

- [x] **Step 8: 补空到非空、空到空和非空替换测试**

断言新 adapter 只在非空时存在，旧 adapter 已释放，现有非空 generation terminal 行为保持不变。

- [x] **Step 9: 迁移既有测试的 adapter 查找**

测试通过 `pagingHost.activeAdapter` 获取 adapter，不改变 production 可见性；不得重新让主控制器直接 contain adapter。

- [x] **Step 10: 运行 Adapter、Host、ViewController、Store 全量测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests test
```

- [x] **Step 11: 提交主控制器空状态闭环**

```bash
git add Sources/AnchorPager/Paging Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests
git commit -m "接入稳定分页 Host 空状态"
```

---

### Task 3: Public reload transaction 与负 count 日志

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Adds internal state only:

```swift
private var reloadTransactionIdentifier = 0
```

- [x] **Step 1: 扩展测试 StubDataSource 的重入 hook**

为 count/title/Header 回调分别提供一次性 closure，并记录调用次数。hook 执行后必须清空自身，避免递归。

- [x] **Step 2: 写 count/title/Header 重入 RED 测试**

每个测试让外层回调中修改数据源并重入 `reloadData()`；断言内层最新 count/titles/Header/generation 获胜，
外层不再触发旧页面 provider 或覆盖 public selection。

- [x] **Step 3: 运行并确认旧调用覆盖新调用**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

- [x] **Step 4: 实现局部快照和 token 校验**

transaction 在第一次 data source 回调前递增；count/Header/每个 title 回调后执行：

```swift
guard transaction == reloadTransactionIdentifier else {
    AnchorPagerLogger.log(.debug, category: .lifecycle, event: "lifecycle.reloadData.cancelled")
    return
}
```

所有实例状态只在完整快照采集后一次性发布。

- [x] **Step 5: 补 public 负 count 日志 RED/GREEN**

从 `pager.reloadData()` 进入负 count，关闭测试断言后捕获
`children.page.invalidCount`；主控制器记录后把 `0` 交给 Store，避免重复日志。

- [x] **Step 6: 运行 ViewController 和日志测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
```

- [x] **Step 7: 提交 reload transaction**

```bash
git add Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "保护 reloadData 数据源重入"
```

---

### Task 4: Appearance cancel 真实交互验收

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Example-only `ExampleAppearanceRecorder` 记录 `<page>.<callback>` 稳定事件。
- 通过 accessibility identifier `page-appearance-events` 暴露 recorder 当前序列；不增加框架 API。

- [x] **Step 1: 写交互取消 UI RED 测试**

启动长页后清空 recorder，执行小于完成阈值的水平拖动并释放。断言长页仍可见、短页没有 `didAppear`、事件序列
终止于 source 恢复；随后正常点击短页可完成。

- [x] **Step 2: 运行并确认缺少 recorder/断言失败**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCancelledInteractivePagingKeepsAppearanceAndSelectionConsistent test
```

- [x] **Step 3: 增加 Example-only recorder**

四个标准生命周期 override 只在调用 `super` 后追加 recorder；不得调用或模拟 appearance transition。测试观测点保持
可访问但不参与框架布局和状态决策。

- [x] **Step 4: 调整取消手势并验证稳定性**

同一模拟器连续运行目标测试至少三次。若 XCUI 无法稳定制造取消，改为真实 Pageboy/UIPageViewController 同进程
UIKit 集成测试，并在 plan 验收记录原因；不得直接调用 adapter delegate 代替交互。

- [x] **Step 5: 运行 v0.4 四项既有 UI + 新取消测试**

Expected: offset restore/reset、reload generation、完成 appearance、取消 appearance 全部通过。

- [x] **Step 6: 提交 appearance cancel 验收**

```bash
git add Examples/AnchorPagerExample
git commit -m "补充分页取消生命周期验收"
```

---

### Task 5: 文档、完整验证与独立复审

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md`
- Modify: `docs/superpowers/specs/2026-07-12-v0-4-child-lifecycle-cache-design.md`
- Modify: `docs/superpowers/specs/2026-07-12-v0-4-reload-terminal-repair-design.md`
- Modify: `docs/superpowers/plans/2026-07-12-v0-4-reload-terminal-repair.md`

- [x] **Step 1: 更新真实架构和限制**

记录稳定 paging host、page/empty terminal、reload transaction、空状态语义和 v0.5 只能依赖 host/Store 的边界。

- [x] **Step 2: 更新任务与计划证据**

只勾选实际通过的任务；记录 RED/GREEN、测试数量、耗时、第三方 privacy warning 和自审结论。

- [x] **Step 3: 运行完整验收**

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test
```

- [x] **Step 4: 最终自审**

检查 public API、第三方边界、双重 containment、appearance、空状态、generation、ownership、重入、MainActor、日志、
测试、示例、文档和工作区解释。

- [ ] **Step 5: 独立代码复审**

比较修复前 commit `a4cef4c` 到修复 HEAD；Critical/Important 必须清零后才恢复 v0.4 完成状态。

- [x] **Step 6: 提交验收收尾**

```bash
git add README.md docs AGENTS.md
git commit -m "完成 v0.4 reload terminal 修复验收"
```

---

## Task 1–4 实施与复审证据

以下汇总来自各任务提交时的实施/独立复审回报和可核验中文 commit 链；原始 /private/tmp 报告不是仓库资产，现已清理，不能作为长期 transcript 复查。本轮 Task 5 的新鲜全量验收是最终可复现主证据。

- Task 1：RED 为 Host/terminal 类型不存在，focused 编译 exit 65；GREEN 初版 Host 8 项、Host + Adapter 20/20；双 terminal 复审修复后 22/22。对应提交包括 3039b0f、cf71ec8。
- Task 2：RED 的非空到空路径有 5 个断言暴露旧 adapter/page containment 残留；经 Pageboy 5.0.2 源码与真实 UIKit 实验，最终采用 delete-last-page、post-return guard 和 plumbing teardown。复审继续修复 readiness 与双请求 Important，最终 focused 112/112。对应提交包括 df4d4a1、6328069、8a835b1、7a90233。
- Task 3：RED 4 个用例、11 个断言覆盖 count/Header/title 重入覆盖和负 count 无日志；复审修复过期负 count 副作用后组合 102/102。对应提交 99d059a、e1bffcb。
- Task 4：RED 因缺少 page-appearance-events，目标 UI 1/1 按预期失败；optional recorder 复审修复后 Example 单元 5/5、取消测试连续 3/3（56.538 秒）、关键 UI 5/5（85.713 秒）。对应提交 1022077、6799891。
- Task 1–4 均有中文主题提交且任务独立复审结论为 Approved；Task 5 不替代最终整段 diff 的独立复审。

## Task 5 完整验收

- git diff --check：exit 0，0.201 秒。
- swift package resolve：sandbox 首次因用户 SwiftPM/clang cache 权限 exit 1；按权限规则提升后 exit 0，6.444 秒，依赖保持 Tabman 4.0.1 / Pageboy 5.0.2。
- 框架全量：iPhone 17、iOS 26.3.1，163 项通过，0 失败、0 跳过；xcresult 总区间 79.585 秒，测试执行 56.435 秒。
- Example generic simulator build：exit 0，15.465 秒。
- Example 全量（parallel NO）：21 项通过（5 项示例单元测试 + 16 项 UI 测试），0 失败、0 跳过；xcresult 总区间 287.116 秒，测试执行 276.938 秒。
- warning：框架测试目标有 2 条 weak local variable never mutated；Pageboy/Tabman 各自的 PrivacyInfo.xcprivacy 在框架测试、Example build/test 报 unhandled resource。均为测试或锁定第三方提示，没有框架/Example 生产源码 warning。

## Task 5 最终自审

1. Public API 未扩大，第三方类型仍只位于 Sources/AnchorPager/Paging/。
2. AnchorPager 只 contain 稳定 Host；Host 只 contain adapter；普通业务 page containment/appearance 仍由 Pageboy/UIKit 执行，fallback host 只 contain 自身普通 child。
3. empty terminal 晚于业务 page 与 adapter 同步退出 containment；UIKit plumbing 允许后续 main-run-loop 释放，不用 timer/delay 推进生产终态。
4. Host latest pending reload 与 adapter readiness 只使用 did/cancel/programmatic completion 语义状态；旧 selection 不提交新 generation。
5. reload transaction 覆盖 count、Header、每个 title 回调；过期事务不发布负 count 日志或部分元数据。
6. Store 继续独占 generation、page identity、retention、snapshot 和 ownership 清理；Host/adapter 不形成第二套状态 owner。
7. UIKit/data source/Store/adapter 均保持 MainActor；日志门面未整体绑定 MainActor，未新增不安全并发逃逸。
8. 日志、单元/集成/UI 测试、README、architecture、task-list、roadmap、原设计/计划与 repair 设计/计划已同步。
9. 工作区唯一无关项为用户已有未跟踪 .superpowers/，未读取、未修改、未提交。
10. v0.5 当前不可启动；必须等待最终独立复审清零 Critical/Important。之后只能依赖稳定 Host、Store committed current child/scroll target 和标准化 reload/selection terminal，不能缓存 adapter 或复制 identity/cache/generation。

## 实施检查点

1. Task 1 后审查 host 是否只管理 adapter containment。
2. Task 2 后审查空 terminal 是否晚于旧 adapter 实际移除、早于 Store 旧状态清理。
3. Task 3 后审查所有 public data source 回调均有 token 校验，且旧事务零写入。
4. Task 4 后审查框架没有新增 appearance forwarding。
5. Task 5 完整验收和独立复审通过后，才能合并或开始 v0.5。
