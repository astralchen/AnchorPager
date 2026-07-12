# v0.4 Child 生命周期与缓存实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 AnchorPager 的全量页面预加载改为 PageStateStore 驱动的按需加载、稳定页面身份、可选相邻缓存、offset snapshot 和安全 reload generation。

**Architecture:** `AnchorPagerViewController` 继续编排 public lifecycle 和 selection，`AnchorPagerPagingAdapter` 只通过 internal provider 按 index 取页，`AnchorPagerPageStateStore` 独占 weak live identity、retention reasons、fallback host、scroll target 和 snapshot。Pageboy/UIKit 继续执行普通页面 containment/appearance，managed inset 仍由既有 coordinator 单独拥有。

**Tech Stack:** Swift 6、UIKit、Swift Package Manager、XCTest、Tabman 4.0.1、Pageboy 5.0.2、iOS 14+

**Current Status:** 主体实现与原验收已完成；后续审查发现的空数据 reload terminal、public reload 重入和 appearance cancel 缺口已按 repair plan 修复。2026-07-12 新鲜完整验收通过；最终独立复审通过前不启动 v0.5。

## Global Constraints

- 所有 UIKit、data source、delegate、page state 和 coordinator 操作保持 `@MainActor`。
- Tabman/Pageboy 类型只允许出现在 `Sources/AnchorPager/Paging/` internal adapter 层。
- 普通横向业务页面不得由 AnchorPager 重复 `addChild`；只有 fallback host contain 无 scroll child。
- Tabman `automaticallyAdjustsChildInsets` 必须在 `viewDidLoad` 前保持 `false`。
- 不新增 public API；只激活 `AnchorPagerPagingConfiguration.keepsAdjacentPagesLoaded` 的既有语义。
- snapshot 只保存 `childDistanceFromTop`，不保存 managed/external inset 或手工 appearance 状态。
- 每项行为严格执行 RED → GREEN → REFACTOR，未观察到预期失败前不得写对应生产代码。
- 高频布局和滚动路径不得遍历总 page count，也不得逐帧输出普通日志。
- 优先复用已启动的 `iPhone 17` simulator，不执行无必要的 boot/shutdown。

---

## 文件结构

### 新增

- `Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift`：页面 generation、weak identity、retention、fallback、snapshot 和 inset 接管编排。
- `Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift`：Store 的 identity、缓存、offset、reload、冲突和日志测试。

### 修改

- `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`：数组 data source 改为 weak provider，转发 reload terminal。
- `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：移除全量页面数组/scroll 数组/fallback 字典，接入 Store 和 generation。
- `Sources/AnchorPager/Children/AnchorPagerPageScrollHostViewController.swift`：保持 fallback containment，并让重复 content 清理幂等。
- `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`：更新 `keepsAdjacentPagesLoaded` DocC 为 v0.4 实际语义。
- `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`：验证 provider、page count、reload callback 和无强缓存。
- `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：把全量预加载断言改为懒加载、缓存、selection 和 generation 断言。
- `Tests/AnchorPagerTests/AnchorPagerChildViewControllerStoreTests.swift`：移除旧独立 Store 主路径测试，保留 fallback containment 测试。
- `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：补充切页 offset/appearance/reload 可见行为。
- `README.md`、`docs/architecture.md`、`docs/task-list.md`：记录已实现语义、限制和验收证据。
- `AGENTS.md`：登记本实施计划。

---

### Task 1: PagingAdapter 改为按 index provider

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor protocol AnchorPagerPageProviding: AnyObject { func pageViewController(at index: Int) -> UIViewController? }`
  - `weak var pageProvider: AnchorPagerPageProviding?`
  - `func reload(titles: [String], pageCount: Int, selectedIndex: Int)`
  - `pagingAdapter(_:didReloadAt:)` delegate terminal event
- Consumes: 现有 Pageboy data source、selection callback 和 Tabman bar API。

- [x] **Step 1: 写 provider RED 测试**

在 `AnchorPagerPagingAdapterTests` 增加 recording provider，并把旧数组测试替换为：

```swift
@MainActor
func testAdapterRequestsPagesByIndexWithoutOwningControllerArray() {
    let adapter = AnchorPagerPagingAdapter()
    let first = UIViewController()
    let provider = RecordingPageProvider(pages: [0: first])
    adapter.pageProvider = provider

    adapter.reload(titles: ["First", "Second"], pageCount: 2, selectedIndex: 1)

    XCTAssertEqual(adapter.numberOfViewControllers(in: adapter), 2)
    XCTAssertTrue(adapter.viewController(for: adapter, at: 0) === first)
    XCTAssertNil(adapter.viewController(for: adapter, at: 1))
    XCTAssertEqual(provider.requestedIndexes, [0, 1])
}

@MainActor
private final class RecordingPageProvider: AnchorPagerPageProviding {
    var pages: [Int: UIViewController]
    var requestedIndexes: [Int] = []

    init(pages: [Int: UIViewController]) {
        self.pages = pages
    }

    func pageViewController(at index: Int) -> UIViewController? {
        requestedIndexes.append(index)
        return pages[index]
    }
}
```

- [x] **Step 2: 运行测试并确认预期失败**

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

Expected: 编译失败，提示 `AnchorPagerPageProviding`、`pageProvider` 或新 `reload` 签名不存在。

- [x] **Step 3: 实现最小 provider 边界**

在 adapter 文件定义：

```swift
@MainActor
protocol AnchorPagerPageProviding: AnyObject {
    func pageViewController(at index: Int) -> UIViewController?
}
```

把 `viewControllers` 替换为：

```swift
weak var pageProvider: AnchorPagerPageProviding?
private var pageCount = 0
```

并把 reload/data source 改为：

```swift
func reload(titles: [String], pageCount: Int, selectedIndex: Int) {
    self.titles = titles
    self.pageCount = max(0, pageCount)
    defaultSelectedIndex = (0..<self.pageCount).contains(selectedIndex) ? selectedIndex : 0
    committedSelectedIndex = defaultSelectedIndex
    pendingPageboySelectionIndex = nil
    pendingProgrammaticSelection = nil
    dataSource = self
    if isViewLoaded {
        reloadData()
    }
    AnchorPagerLogger.log(.info, category: .paging, event: "paging.reload")
}

func numberOfViewControllers(in pageboyViewController: PageboyViewController) -> Int {
    pageCount
}

func viewController(
    for pageboyViewController: PageboyViewController,
    at index: PageboyViewController.PageIndex
) -> UIViewController? {
    guard (0..<pageCount).contains(index) else { return nil }
    return pageProvider?.pageViewController(at: index)
}
```

所有 `setSelectedIndex`/default page 范围判断统一改为 `0..<pageCount`。

- [x] **Step 4: 增加 reload terminal RED 测试**

测试：

```swift
adapter.pageboyViewController(adapter, didReloadWith: first, currentPageIndex: 0)
XCTAssertTrue(delegate.events.contains(.didReload(0)))
```

- [x] **Step 5: 运行 reload terminal 测试并确认失败**

Run 同 Step 2。

Expected: delegate 没有 `didReload` event 或 adapter 没有转发回调。

- [x] **Step 6: 实现 reload terminal 转发**

扩展 delegate：

```swift
func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, didReloadAt index: Int)
```

adapter override 必须先调用 super，再转发 internal index，不把 Pageboy 类型传出 adapter 文件。

- [x] **Step 7: 运行 adapter 全量测试**

Run 同 Step 2。

Expected: `AnchorPagerPagingAdapterTests` 全部通过；现有 selection、bar height 和日志测试无回归。

- [x] **Step 8: 提交 adapter 边界**

```bash
git add Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift
git commit -m "重构分页适配器为按需页面提供器"
```

---

### Task 2: PageStateStore 页面身份、按需准备和 fallback

**Files:**
- Create: `Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift`
- Modify: `Sources/AnchorPager/Children/AnchorPagerManagedInsetCoordinator.swift`

**Interfaces:**
- Consumes:
  - `AnchorPagerManagedInsetCoordinator.Target`
  - `UIViewController.anchorPagerScrollView` / `anchorPagerDefaultScrollView`
  - `AnchorPagerPageScrollHostViewController`
- Produces:

```swift
@MainActor
final class AnchorPagerPageStateStore {
    struct AccessContext {
        var managedInsetTarget: AnchorPagerManagedInsetCoordinator.Target
        var containerIsCollapsed: Bool
    }

    init(managedInsetCoordinator: AnchorPagerManagedInsetCoordinator)
    func beginReload(
        generation: Int,
        pageCount: Int,
        selectedIndex: Int,
        keepsAdjacentPagesLoaded: Bool
    )
    func pageViewController(
        at index: Int,
        context: AccessContext,
        originalProvider: () -> UIViewController?
    ) -> UIViewController?
    func commitReload(generation: Int)
    func releaseAll()
}
```

同时给 internal target 增加确定的零值：

```swift
static let zero = Target(content: .zero, indicators: .zero)
```

- [x] **Step 1: 写同 index 稳定身份 RED 测试**

```swift
@MainActor
func testRepeatedAccessReturnsSameLivePageAndCallsProviderOnce() {
    let coordinator = AnchorPagerManagedInsetCoordinator()
    let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
    let child = ScrollPageViewController()
    var providerCalls = 0
    store.beginReload(generation: 1, pageCount: 2, selectedIndex: 0, keepsAdjacentPagesLoaded: false)

    let first = store.pageViewController(at: 0, context: .zero) {
        providerCalls += 1
        return child
    }
    let second = store.pageViewController(at: 0, context: .zero) {
        providerCalls += 1
        return UIViewController()
    }

    XCTAssertTrue(first === child)
    XCTAssertTrue(second === child)
    XCTAssertEqual(providerCalls, 1)
}
```

测试 helper 的 `.zero` 明确定义为 content/indicator `.zero` 且 `containerIsCollapsed == false`。

- [x] **Step 2: 运行 Store 测试确认失败**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests test
```

Expected: 编译失败，提示 Store 类型不存在。

- [x] **Step 3: 实现最小 generation 和 weak PageState**

文件内建立 private reference state：

```swift
private final class PageState {
    let index: Int
    weak var originalViewController: UIViewController?
    weak var actualPageViewController: UIViewController?
    weak var scrollView: UIScrollView?
    weak var fallbackHost: AnchorPagerPageScrollHostViewController?
    var retainedPage: UIViewController?
    var retentionReasons: Set<RetentionReason> = []
    var childDistanceFromTop: CGFloat = 0

    init(index: Int) {
        self.index = index
    }
}
```

Store 同时保存 committed/pending generation；`pageViewController` 只访问 pending（存在时）或 committed。
首次 current page 自动获得 `.current` reason，weak actual 存活时直接复用。

- [x] **Step 4: 写 scroll discovery/fallback RED 测试**

覆盖：

```swift
XCTAssertTrue(scrollPageResult === scrollChild)
XCTAssertTrue(store.scrollView(at: 0) === scrollChild.scrollView)
XCTAssertTrue(plainPageResult is AnchorPagerPageScrollHostViewController)
XCTAssertTrue(plainChild.parent === plainPageResult)
```

并验证请求单页时其他 index 的 provider 未执行、view 未加载。

- [x] **Step 5: 实现页面准备和 ownership**

`prepare` 顺序固定为：加载 original view、显式 scroll 优先、确定性 default lookup、collision 检查、fallback。
新增 internal 只读访问器供测试和 ViewController 集成：

```swift
func scrollView(at index: Int) -> UIScrollView?
func livePageViewController(at index: Int) -> UIViewController?
```

为 resolved scroll 应用 context target；fallback host 同时调用 `setManagedContentInsets`。同一请求幂等复用
ownership，不创建第二个 host。

- [x] **Step 6: 写共享 scroll 和 data source 缺失 RED 测试**

测试同一 generation 两个业务控制器声明同一 explicit scroll：后请求页降级 fallback，并捕获
`inset.targetCollision`。provider 返回 nil 时返回稳定 internal blank page，并捕获
`children.page.dataSourceMissing`。

- [x] **Step 7: 运行新增测试并确认预期失败**

Run Store-only command。

Expected: 共享 scroll 尚未降级或 nil provider 仍返回 nil。

- [x] **Step 8: 实现共享 scroll 与空白页降级**

generation state 使用 `Set<ObjectIdentifier>` 登记已声明的 scroll target；冲突时尝试非冲突 default
lookup，否则创建 fallback。nil provider 创建并按 index 弱复用 internal blank page，写稳定 children 日志。

- [x] **Step 9: 运行 Store 与现有 inset/fallback 测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests -only-testing:AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests -only-testing:AnchorPagerTests/AnchorPagerChildViewControllerStoreTests test
```

Expected: 全部通过。

- [x] **Step 10: 提交 PageStateStore 基础**

```bash
git add Sources/AnchorPager/Children Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift
git commit -m "实现页面状态按需加载基础"
```

---

### Task 3: Retention reasons、offset snapshot 与切页事务

**Files:**
- Modify: `Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift`

**Interfaces:**
- Adds:

```swift
func willSelect(from sourceIndex: Int, to targetIndex: Int, context: AccessContext)
func didSelect(_ index: Int, context: AccessContext)
func didCancelSelection(at targetIndex: Int, returningTo sourceIndex: Int, context: AccessContext)
func setKeepsAdjacentPagesLoaded(_ keepsAdjacentPagesLoaded: Bool)
func updateManagedInsets(_ target: AnchorPagerManagedInsetCoordinator.Target, logsChanges: Bool)
```

- [x] **Step 1: 写默认/current/adjacent retention RED 测试**

使用 weak probes 验证：

```swift
store.beginReload(generation: 1, pageCount: 3, selectedIndex: 1, keepsAdjacentPagesLoaded: false)
// 请求 0/1/2 后释放外部强引用：只有 index 1 由 AnchorPager Store 保留。

store.setKeepsAdjacentPagesLoaded(true)
// 已 live 的 0/2 增加 configuredAdjacent；配置本身不请求未创建页。
```

为测试提供：

```swift
func retentionReasons(at index: Int) -> Set<RetentionReason>
```

该接口保持 internal，`RetentionReason` 也保持 internal。

- [x] **Step 2: 运行并确认 retention 测试失败**

Run Store-only command。

Expected: 缺少 retention API 或非 current 页面被错误强持有。

- [x] **Step 3: 实现 reason reconciliation**

reason 定义：

```swift
enum RetentionReason: Hashable {
    case current
    case transitionSource
    case transitionTarget
    case configuredAdjacent
}
```

只对已存在 PageState 计算相邻 reason；`retainedPage` 仅在 reason set 非空时指向 actual page。
reason 清空前保存 snapshot、归还 ownership，然后清除 `retainedPage`，保留 weak identity。

- [x] **Step 4: 写 transition pin/commit/cancel RED 测试**

分别断言：

```swift
store.willSelect(from: 0, to: 1, context: context)
XCTAssertEqual(store.retentionReasons(at: 0), [.current, .transitionSource])
XCTAssertTrue(store.retentionReasons(at: 1).contains(.transitionTarget))

store.didSelect(1, context: context)
XCTAssertEqual(store.retentionReasons(at: 1), [.current])

store.didCancelSelection(at: 1, returningTo: 0, context: context)
XCTAssertEqual(store.retentionReasons(at: 0), [.current])
```

- [x] **Step 5: 写 offset 恢复/归顶 RED 测试**

创建带 top inset 的 scroll page，设置：

```swift
scrollView.contentOffset.y = -scrollView.contentInset.top + 120
```

离开窗口后断言 snapshot 为 120。重新创建并：

- `containerIsCollapsed == true`：offset 恢复为新 top + 120；
- `containerIsCollapsed == false`：offset 回到新 top，snapshot 更新为 0。

`childDistanceFromTop(at:)` 作为 internal 测试 accessor。

- [x] **Step 6: 实现 snapshot 和目标页 offset 策略**

统一 helper：

```swift
private func childDistanceFromTop(in scrollView: UIScrollView) -> CGFloat {
    max(0, scrollView.contentOffset.y + scrollView.contentInset.top)
}

private func applySnapshot(_ state: PageState, context: AccessContext) {
    guard let scrollView = state.scrollView else { return }
    let distance = context.containerIsCollapsed ? state.childDistanceFromTop : 0
    state.childDistanceFromTop = distance
    scrollView.contentOffset.y = -scrollView.contentInset.top + distance
}
```

普通非当前 Pageboy prefetch 只建立页面和 inset，不清零 snapshot；只在 initial current、willSelect target、
didSelect terminal 时调用 `applySnapshot`。

- [x] **Step 7: 写 active-window inset 复杂度测试**

创建大量轻量 PageState，但只让 current/transition/adjacent live；通过 injectable test hook 或 internal
`lastManagedUpdateCount` 断言一次 `updateManagedInsets` 的访问数不超过 active window，不等于 pageCount。

- [x] **Step 8: 运行 Store 全量测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests test
```

Expected: Store 全量测试通过。

- [x] **Step 9: 提交缓存窗口与 offset**

```bash
git add Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift
git commit -m "实现页面缓存窗口与偏移快照"
```

---

### Task 4: Reload generation、重复 identity 与安全清理

**Files:**
- Modify: `Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift`
- Modify: `Sources/AnchorPager/Children/AnchorPagerPageScrollHostViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift`

**Interfaces:**
- Uses Task 2 `beginReload`/`commitReload`。
- Adds internal diagnostic accessors only where behavior cannot otherwise be observed:

```swift
var committedGenerationIdentifier: Int? { get }
var pendingGenerationIdentifier: Int? { get }
```

- [x] **Step 1: 写 didReload 前后释放 RED 测试**

```swift
store.beginReload(generation: 1, pageCount: 1, selectedIndex: 0, keepsAdjacentPagesLoaded: false)
var oldChild: UIViewController? = UIViewController()
weak var oldWeak = oldChild
_ = store.pageViewController(at: 0, context: .zero) { oldChild }
store.commitReload(generation: 1)

store.beginReload(generation: 2, pageCount: 1, selectedIndex: 0, keepsAdjacentPagesLoaded: false)
let newChild = UIViewController()
_ = store.pageViewController(at: 0, context: .zero) { newChild }
oldChild = nil
XCTAssertNotNil(oldWeak)

store.commitReload(generation: 2)
XCTAssertNil(oldWeak)
```

旧 fallback content 也必须在 generation 2 commit 后从 parent 移除。

- [x] **Step 2: 实现 pending/committed 双 generation**

`beginReload` 不立即释放 committed generation；新请求只进入 pending。`commitReload` 必须：

1. 校验 callback generation 等于 pending id；
2. 把 pending 设为 committed；
3. 保存并归还旧 generation ownership；
4. 对旧 fallback host 调用幂等 content removal；
5. 清理旧 state/snapshot；
6. 记录 generation commit。

重复/过期 commit 只记录诊断，不破坏当前 generation。

- [x] **Step 3: 写同 index migration 与 index 移动 RED 测试**

同 index 返回相同业务 controller：actual/fallback/ownership/snapshot 迁移且 provider 不产生第二个 host。
移动到不同 index：live actual 原子转移，旧 key 退出可请求集合，新 snapshot 为 0。

- [x] **Step 4: 写 duplicate controller RED 测试**

同 generation 的两个 index 返回同一业务实例：在
`AnchorPagerAssertions.$isEnabled.withValue(false)` 下，第二页是 internal blank page，事件包含：

```swift
.init(category: .children, level: .debug, event: "children.page.duplicateController")
```

Expected: 旧实现错误复用同一业务控制器，测试失败。

- [x] **Step 5: 实现 duplicate controller 降级**

按 original controller 的 `ObjectIdentifier` 建立 generation 内唯一索引；不得用两个 fallback host
掩盖冲突。

- [x] **Step 6: 写过期请求/重入 generation RED 测试**

provider 闭包中调用 `beginReload(generation: 3, ...)`，generation 2 的创建结果不得提交；刚建立的
ownership 必须归还。

- [x] **Step 7: 实现请求 generation 二次校验**

使用请求开始时捕获的 generation id，在 provider 返回后再次校验；失效结果不写入 pending/committed
state，并归还刚建立的 ownership/fallback content。

- [x] **Step 8: 写 generation 与降级日志测试**

验证 begin/commit/cancel、duplicate、dataSourceMissing 使用设计文档中的稳定事件名，不输出业务标题或
controller class。

- [x] **Step 9: 运行 Store/fallback/inset 测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests -only-testing:AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests -only-testing:AnchorPagerTests/AnchorPagerChildViewControllerStoreTests test
```

Expected: 全部通过。

- [x] **Step 10: 提交 reload generation**

```bash
git add Sources/AnchorPager/Children Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift Tests/AnchorPagerTests/AnchorPagerChildViewControllerStoreTests.swift
git commit -m "实现页面重载代际与身份冲突处理"
```

---

### Task 5: 集成 AnchorPagerViewController 懒加载与切页

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Delete: `Sources/AnchorPager/Children/AnchorPagerChildViewControllerStore.swift`
- Delete: `Tests/AnchorPagerTests/AnchorPagerChildViewControllerStoreTests.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPageScrollHostViewControllerTests.swift`（迁移并保留 fallback host containment、可见高度和日志测试）
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- `AnchorPagerViewController` conforms to `AnchorPagerPageProviding`。
- Consumes Store Task 2–4 API and adapter Task 1 callbacks。

- [x] **Step 1: 写 reload 不全量加载 RED 测试**

扩展 StubDataSource：

```swift
var requestedViewControllerIndexes: [Int] = []
var loadViewCounts: [Int: Int] = [:]
```

测试 100 页 reload：

```swift
pager.reloadData()
XCTAssertLessThanOrEqual(dataSource.requestedViewControllerIndexes.count, 2)
XCTAssertFalse(dataSource.requestedViewControllerIndexes.contains(99))
```

允许 Pageboy/UIKit 按需预取当前相邻页，因此不把请求数硬编码为仅 1；必须断言远端页面未请求、未加载。

- [x] **Step 2: 运行 ViewController 测试确认旧实现失败**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

Expected: 旧实现请求全部 100 页，RED 断言失败。

- [x] **Step 3: 用 Store 替换全量数组和 fallback 字典**

删除：

```swift
currentViewControllers
activePageScrollViews
fallbackPageHosts
lastManagedScrollViewIdentifiers
PreparedPage
preparePage(...)
fallbackPageHost(...)
removeStaleFallbackPageHosts(...)
```

新增：

```swift
private lazy var pageStateStore = AnchorPagerPageStateStore(
    managedInsetCoordinator: managedInsetCoordinator
)
private var reloadGeneration = 0
private var pendingReloadGeneration: Int?
private var currentManagedInsetTarget: AnchorPagerManagedInsetCoordinator.Target = .zero
```

`reloadData()` 只请求 count/titles/Header，递增 generation，调用 Store `beginReload`，然后调用：

```swift
pagingAdapter.reload(
    titles: currentTitles,
    pageCount: pageCount,
    selectedIndex: selectedIndex
)
```

- [x] **Step 4: 实现 AnchorPagerPageProviding**

```swift
func pageViewController(at index: Int) -> UIViewController? {
    pageStateStore.pageViewController(
        at: index,
        context: pageAccessContext
    ) { [weak self] in
        guard let self, let dataSource = self.dataSource else { return nil }
        return dataSource.pagerViewController(self, viewControllerAt: index)
    }
}
```

`pageAccessContext` 使用 `lastManagedInsetTarget ?? .zero`，container collapsed 判定采用
`collapseOffset >= collapsibleDistance - 0.5`，零折叠距离视为 collapsed。

- [x] **Step 5: 集成 will/did/cancel/reload callbacks**

```swift
func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, willSelect index: Int, animated: Bool) {
    pageStateStore.willSelect(from: selectedIndex, to: index, context: pageAccessContext)
}

func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, didSelect index: Int, animated: Bool) {
    pageStateStore.didSelect(index, context: pageAccessContext)
    commitSelectedIndex(index, animated: animated)
}

func pagingAdapter(
    _ adapter: AnchorPagerPagingAdapter,
    didCancelSelectionAt index: Int,
    returningTo previousIndex: Int
) {
    pageStateStore.didCancelSelection(at: index, returningTo: previousIndex, context: pageAccessContext)
}

func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, didReloadAt index: Int) {
    guard let generation = pendingReloadGeneration else { return }
    pageStateStore.commitReload(generation: generation)
    pendingReloadGeneration = nil
}
```

- [x] **Step 6: 把布局 inset 更新改为 Store active window**

`applyManagedInsets` 只计算 target、缓存 target 并调用：

```swift
pageStateStore.updateManagedInsets(target, logsChanges: logsChanges)
```

不再 zip/遍历全量页面数组。配置变化时调用
`pageStateStore.setKeepsAdjacentPagesLoaded(configuration.paging.keepsAdjacentPagesLoaded)`。

- [x] **Step 7: 修复并扩展既有 ViewController 测试**

更新直接检查 adapter page 的测试，使其显式请求对应 index；补充：

- 相同 live index 不重复调用 data source；
- 完成/取消切页的 Store current 不变量；
- Header 未折叠时目标归顶、折叠时恢复 snapshot；
- reload callback 前旧 child 保留、callback 后释放；
- deinit 仍归还所有 live ownership；
- 100 页 container scroll 的 managed update count 受 active window 限制。

- [x] **Step 8: 运行 package 全量测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' test
git diff --check
```

Expected: package 全量测试 0 failure；无 Tabman/Pageboy public 泄漏。

- [x] **Step 9: 提交主控制器集成**

```bash
git add Sources/AnchorPager Tests/AnchorPagerTests
git commit -m "集成页面生命周期与懒加载缓存"
```

---

### Task 6: UI appearance、示例、日志与文档验收

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-12-v0-4-child-lifecycle-cache-design.md`

**Interfaces:**
- 不新增 public API。
- 示例只增加 accessibility identifiers / debug counters，不引入业务命名到框架。

- [x] **Step 1: 写 appearance/offset/reload UI RED 测试**

新增稳定 UI 路径：

1. 进入长页，滚动到可识别 cell；
2. 完全折叠 Header 后切走再切回，断言原 cell 位置恢复；
3. Header 未完全折叠时切页，断言目标页第一项可见；
4. 触发示例 reload，断言旧页面消失且新页面可交互；
5. 使用示例内 accessibility label 暴露 appearance 次数，断言完成/取消路径没有重复终态。

Run:

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AnchorPagerExampleUITests test
```

Expected: 新测试因缺少标识或行为失败。

- [x] **Step 2: 最小化补充示例观测点**

只在 Example target 增加 identifier/label，不给 AnchorPager public API 增加调试字段。业务测试控制器用标准
`viewWillAppear`/`viewDidAppear`/`viewWillDisappear`/`viewDidDisappear` 累计并更新 accessibility value；
框架不得手工调用 appearance transition。

- [x] **Step 3: 运行 UI 测试并确认转绿**

Run 同 Step 1。

Expected: 新增 UI 流程全部通过。

- [x] **Step 4: 完成日志测试**

通过 `AnchorPagerLogger.sink` 验证 load/reuse/recreate/retain/release/snapshot/generation/降级事件；滚动
热路径测试断言没有逐帧 `children.page.*` 噪声。

- [x] **Step 5: 更新 DocC、README 和架构状态**

`keepsAdjacentPagesLoaded` DocC 明确：

```swift
/// 是否由 AnchorPager 额外强保留当前页两侧已经加载的页面。
///
/// Pageboy 或 UIKit 仍可能临时持有相邻页面，因此关闭时不保证页面立即释放。
```

README 记录按需创建、data source 可在释放后返回新实例、offset 恢复和相邻缓存限制。
`docs/architecture.md` 从“尚未实现”更新为真实装配；`docs/task-list.md` 只勾选有测试证据的 v0.4 项。
设计文档状态改为“已实现”仅在完整验收通过后执行。

- [x] **Step 6: 运行完整验收**

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: 所有命令 exit 0；记录测试数量、耗时和仅剩的第三方已知 warning。

- [x] **Step 7: 最终自审**

逐项检查并记录：

- public API 未扩大，Public 目录无 Tabman/Pageboy；
- 普通 page 没有 AnchorPager 重复 containment/appearance；
- fallback host containment 只有一条；
- Store weak identity 与 strong retention reason 一致；
- reload commit 前旧可见页稳定，commit 后 ownership/fallback 可释放；
- inset snapshot 没有复制 external/managed inset；
- container 热路径不随 page count 增长；
- Swift 6 MainActor 和 deinit 归还顺序无绕过；
- 日志、测试、示例和文档同步。

- [x] **Step 8: 提交 v0.4 收尾**

```bash
git add Sources/AnchorPager/Public/AnchorPagerConfiguration.swift Examples README.md docs Tests
git commit -m "完成 v0.4 页面生命周期与缓存验收"
```

---

## 实施顺序与检查点

1. Task 1 完成后审查 adapter 是否仍是唯一 Tabman/Pageboy 边界。
2. Task 2 完成后审查 Store 是否没有接管 container offset 或 Pageboy containment。
3. Task 3 完成后审查缓存关闭语义是否只是“不额外强保留”。
4. Task 4 完成后审查 generation commit 前后 ownership 和 fallback 的释放顺序。
5. Task 5 完成后运行 package 全量测试，确认旧 v0.3 inset/safe-area 行为无回归。
6. Task 6 完成后运行 Example UI 全量测试和完整自审，才允许标记 v0.4 完成。

## 修复后最终验收记录

- 原主体实现验收曾通过 129 项框架测试、4 项示例单元测试和 15 项 UI 测试；repair 新增 stable Host、empty terminal、重入和取消路径后，以 repair plan 的新鲜全量结果为最终证据。
- 2026-07-12 框架全量：163 项通过，0 失败、0 跳过；xcresult 总区间 79.585 秒，测试执行 56.435 秒。
- Example generic simulator build：exit 0，15.465 秒。
- Example 全量测试（parallel NO）：21 项通过，其中示例单元测试 5 项、UI 测试 16 项，0 失败、0 跳过；xcresult 总区间 287.116 秒，测试执行 276.938 秒。
- Swift package resolve 提升权限后 exit 0，6.444 秒；git diff --check exit 0。
- warning：框架编译有 2 条测试局部 weak variable 未变更提示；框架测试、Example build/test 均有 Pageboy/Tabman PrivacyInfo.xcprivacy unhandled resource 上游提示。没有 Swift 6、框架源码或 Example 源码 warning。
- 最终自审确认 public API 未扩大、Public 目录无 Tabman/Pageboy、普通业务页没有双重 containment 或手工 appearance、fallback host 只有一条 containment、Store generation/identity/snapshot/ownership 单向、MainActor/deinit 归还路径未绕过、日志与测试覆盖同步。v0.5 入口只允许消费稳定 Host、Store committed current child/scroll target 和标准化 terminal。
