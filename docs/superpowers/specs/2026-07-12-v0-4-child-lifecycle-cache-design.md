# v0.4 Child 生命周期与缓存设计

**日期：** 2026-07-12

**状态：** 已确认设计，尚未实现

**适用版本：** v0.4，并作为 v0.5 纵向滚动协调的 page state 基础

## 背景

v0.3 已完成固定分页 viewport、Tabman bar 几何回报和 child inset ownership，但
`AnchorPagerViewController.reloadData()` 仍会一次性向 data source 请求全部页面并加载每个 child view，
`AnchorPagerPagingAdapter` 也通过 `[UIViewController]` 强持有全部页面。这种装配方式无法实现真正的
按需加载、缓存窗口和卸载后 offset 恢复，并会让页面数量直接放大 reload 和滚动布局成本。

当前 `AnchorPagerChildViewControllerStore` 是 v0.1 的独立 containment 工具，不是横向分页主路径的
page lifecycle owner。继续在其上叠加缓存会与 Tabman/Pageboy 的实际 containment 职责冲突。

v0.4 必须把页面身份、按需创建、缓存保留、reload generation、fallback host 和 offset snapshot
收敛到一个 page policy owner，同时继续让 Pageboy/UIKit 执行横向页面的 containment 和 appearance。

## 目标

1. `reloadData()` 只同步页面数量、标题和 Header，不再请求或加载全部页面控制器。
2. 页面控制器只在 Pageboy 按 index 请求时由 data source 创建或取得。
3. 同一 generation、同一 index 在控制器仍存活时始终返回同一实例。
4. AnchorPager 默认只强保留当前页和进行中的切页 source/target；配置开启时额外保留当前页相邻页面。
5. 安全淘汰页面时保存 `childDistanceFromTop`，页面重新创建后恢复内容位置。
6. reload 期间旧页面保持稳定可见，待 Pageboy 确认新 generation 已装配后再释放旧状态。
7. 不对交给 Pageboy 的业务页面执行第二套 containment 或手工 appearance forwarding。
8. 把动态 inset 更新限制在当前策略所需页面，不让热路径复杂度随总页面数增长。
9. 保持 v0.5 页面切换时“container 未折叠则目标页归顶、完全折叠则恢复目标 offset”的契约。

## 非目标

1. v0.4 不实现 container/child 的纵向 handoff；该职责属于 v0.5。
2. v0.4 不实现顶部 overscroll owner；该职责属于 v0.6。
3. v0.4 不实现完整横向/返回手势 interaction state；该职责属于 v0.7。
4. 不承诺在 AnchorPager 释放强引用后业务控制器立即 `deinit`，因为 Pageboy/UIKit 可能暂时持有相邻页。
5. 不新增通用 LRU、容量数字或自定义 eviction policy；v0.4 只实现 current、transition 和可选 adjacent 窗口。
6. 不把 Tabman、Pageboy 或内部 retention reason 暴露到 public API。

## Tabman/Pageboy 源码结论

当前锁定版本为 Tabman 4.0.1、Pageboy 5.0.2。源码确认如下：

1. Pageboy 的 `fetchViewController(at:)` 每次都直接调用
   `PageboyViewControllerDataSource.viewController(for:at:)`，没有强控制器缓存。
2. 内部 `UIPageViewController` 请求 before/after 页面时会重复调用 `fetchViewController(at:)`。
3. Pageboy 的 `IndexedObjectMap` 只弱引用控制器，用于从实例反查 index，不构成页面缓存。
4. Tabman 在 `willScrollToPageAt` 中还会再次向 data source 请求目标控制器，以更新 child inset。
   即使 AnchorPager 已关闭 Tabman auto inset，这次 data source 请求仍会发生。
5. Pageboy 内部创建并 contain `UIPageViewController`；具体横向 page containment 和 UIKit appearance
   由该层执行。
6. Pageboy 提供 `willScrollToPageAt`、`didScrollToPageAt`、`didCancelScrollToPageAt` 和
   `didReloadWith`，足以驱动 transition pin、commit/cancel 和 reload generation 收敛。
7. Tabman 的 `automaticallyAdjustsChildInsets` 必须在 `viewDidLoad` 前关闭；当前 adapter 已满足该条件。

这些事实决定 PagingAdapter 不能直接把 public data source 当作无状态 factory。AnchorPager 必须在
Pageboy data source 前建立稳定的页面身份层。

## 架构

```text
AnchorPagerViewController
├─ PageStateStore
│  ├─ generation + index 页面身份
│  ├─ weak live identity
│  ├─ current / transition / adjacent 强保留
│  ├─ scroll discovery / fallback host
│  └─ childDistanceFromTop snapshot
├─ AnchorPagerPagingAdapter
│  └─ 仅按 index 向 PageStateStore 请求实际 page
└─ AnchorPagerManagedInsetCoordinator
   └─ 仅管理仍存活且需要接管的 scroll view
```

### AnchorPagerViewController

`AnchorPagerViewController` 继续是 page lifecycle 策略和对外 selection 语义的唯一 owner。它负责：

- 创建和切换 generation；
- 把 page count、titles、default index 交给 adapter；
- 根据 adapter 的 will/did/cancel/reload 回调更新 retention reasons；
- 把当前 container 状态传给 Store，用于 offset 恢复或归顶；
- 在控制器释放时同步归还所有 inset ownership。

它不保存全量 `[UIViewController]`，也不对横向业务页面调用 `addChild`。

### PageStateStore

`PageStateStore` 是 MainActor internal 类型，是唯一页面策略 owner。每个状态使用以下稳定键：

```text
PageKey = generation + index
```

单个 `PageState` 至少保存：

```text
PageKey
weak originalViewController
weak actualPageViewController
weak childScrollView
weak fallbackHost
strong retainedPage（仅 retentionReasons 非空时）
retentionReasons
childDistanceFromTop
```

其中：

- `originalViewController` 是 public data source 返回的业务控制器；
- 普通 scroll page 的 `actualPageViewController` 与 original 相同；
- 无 scroll view 页面由 fallback host 作为 actual page，fallback host 标准 contain original；
- Store dictionary 可以长期保留轻量 PageState 和 offset snapshot，但弱引用不得阻止页面释放；
- `strong retainedPage` 是 AnchorPager 缓存窗口的唯一强页面引用。

Store 不直接计算 inset，不修改 container offset，也不执行 Pageboy containment。

### AnchorPagerPagingAdapter

PagingAdapter 从“强持有页面数组”改成轻量 provider：

- 保存 page count、titles 和 default index；
- `viewController(for:at:)` 转发给 PageStateStore；
- 转发 will/did/cancel/reload 事件；
- 保留现有 selection 去重和 programmatic completion 防乱序逻辑；
- 不持有业务页面数组，不决定缓存策略。

adapter 使用 internal 协议或闭包连接 Store，协议只包含 UIKit/Swift 类型，不向 public API 泄漏
Tabman/Pageboy。

### AnchorPagerChildViewControllerStore

现有 `AnchorPagerChildViewControllerStore` 不再承担横向分页相关职责。v0.4 将其删除或重定位；
fallback host 自己只管理其内部业务 child 的标准 containment。不得为普通 Pageboy page 保留第二条
containment 路径。

## 页面请求与身份

### 首次请求

Pageboy 请求 index 时按以下顺序执行：

1. 校验 index 位于当前 generation 的 page count 内。
2. 查询 PageState 的 weak actual page；仍存活则直接返回同一实例。
3. weak page 已释放时，调用 public data source 的 `viewControllerAt index`。
4. 校验该业务控制器没有在同一 generation 被其他 index 使用。
5. 执行 scroll discovery；没有有效 scroll view 时创建 fallback host。
6. 为实际 scroll view 建立 managed inset ownership，应用当前 bar top 和 child local bottom。
7. 根据 container 状态恢复 `childDistanceFromTop` 或归到顶部。
8. 根据当前 retention reasons 决定是否写入 `strong retainedPage`。
9. 返回 actual page 给 Pageboy。

创建过程只加载当前被请求页面的 view。`reloadData()` 不对所有页面调用 `loadViewIfNeeded()`。

### 重复请求

Pageboy 和 Tabman 可能在一次切页中多次请求同一 index。只要 weak actual page 仍存活，Store 必须返回
同一实例，并幂等刷新所需 inset/offset；不得再次调用 public data source，也不得创建第二个 fallback
host。

### 释放后重新创建

当某页没有 retention reason，Pageboy/UIKit 也不再持有它时，weak page 会变为 nil。后续再次请求该
index 时允许重新调用 public data source，并允许返回新的控制器实例。新实例继承该 index 保存的
`childDistanceFromTop`，但不继承旧控制器的 external content inset。

### 重复控制器策略

同一 generation 内，同一个业务 `UIViewController` 实例只能对应一个 index。若 data source 把同一实例
返回给不同 index：

- Debug：触发内部 assertion；
- Release：目标 index 使用内部空白 page，记录稳定诊断事件；
- 不把重复实例包装成两个 fallback host 来掩盖 identity 冲突。

相邻 generation 在同一 index 返回同一业务控制器属于状态迁移：转移原 PageState、fallback host、
ownership 和 snapshot，不建立重复 containment。若同一业务控制器在新 generation 移动到不同 index，
则按新 page identity 处理：原子转移仍存活的 actual page、fallback containment 和 ownership 到新 key，
旧 key 立即退出可请求集合；offset snapshot 按新 index 重置为 `0`，不沿用旧 index 的位置。该迁移不属于
同一 generation 的重复控制器冲突，也不能让同一实例同时存在于两个 active key。

## 缓存窗口与保留原因

每个页面的强保留由 reason set 决定：

```text
current
transitionSource
transitionTarget
configuredAdjacent
```

规则如下：

1. `keepsAdjacentPagesLoaded == false`：AnchorPager 强保留 current，以及进行中 transition 的 source/target。
2. `keepsAdjacentPagesLoaded == true`：在上述基础上强保留 current index 的 `-1`、`+1` 有效页面。
3. 相邻保留只作用于已经按需创建的页面；配置开启不主动实例化尚未被 Pageboy 请求的邻页。
4. 切页开始时先 pin source/target，再允许旧窗口收缩。
5. commit 后 target 成为 current，移除 transition reasons，并重算相邻 reason。
6. cancel 后 source 恢复 current，移除 target 的 transition reason，并恢复原相邻窗口。
7. 多个 reason 可以同时存在；只有 reason set 为空时才释放 Store 的强引用。
8. Pageboy/UIKit 的临时强引用不是 AnchorPager cache window 的一部分。

因此 `keepsAdjacentPagesLoaded == false` 的准确语义是“AnchorPager 不额外强保留相邻页”，不是
“相邻页回调后立即 deinit”。

## Offset Snapshot 与 Inset Ownership

Store 只保存内容相对顶部的距离：

```text
childTopOffset = -contentInset.top
childDistanceFromTop = max(0, contentOffset.y - childTopOffset)
```

不保存以下派生或外部状态：

- managed top/bottom inset；
- scroll indicator inset；
- 调用方 external content inset；
- `contentInsetAdjustmentBehavior`；
- `automaticallyAdjustsScrollIndicatorInsets`。

这些值继续由 `AnchorPagerManagedInsetCoordinator` 的 ownership record 管理和归还。页面安全淘汰时：

1. 保存 `childDistanceFromTop`；
2. 归还该 scroll view 的 inset ownership；
3. 清除 Store 强引用，保留 weak live identity；
4. 若 Pageboy 仍持有页面，再次请求时返回同一 live instance，并重新建立 ownership；
5. weak identity 变为 nil 后才允许创建新页面。

container 折叠引起 managed bottom 逐帧变化时，只更新 current 和当前 transition/缓存策略需要的 live
scroll views，不扫描总 page count。非当前 weak live page 在成为 transition target 或再次被请求时，
先收敛到最新 inset target，再参与显示。

## 页面切换

### 开始

adapter 收到 Pageboy `willScrollToPageAt` 后：

1. source 增加 `transitionSource`；
2. target 增加 `transitionTarget`；
3. 确保 target 已按当前几何完成 inset ownership；
4. 按 container 折叠状态准备 target offset。

### 完成

adapter 收到 `didScrollToPageAt` 后：

1. target 提交为 current；
2. AnchorPager 更新 `selectedIndex` 并发送一次 public delegate 回调；
3. 移除 transition reasons；
4. 重算 configuredAdjacent；
5. 安全淘汰离开窗口的页面。

### 取消

adapter 收到 `didCancelScrollToPageAt` 后：

1. previous index 保持 current；
2. 不提交 public selection；
3. 移除 source/target transition reasons；
4. 恢复 source 对应的相邻窗口；
5. target 若不再被策略保留则进入安全淘汰。

### Container 状态规则

该规则在 v0.4 固化 page state 语义，并由 v0.5 的 ScrollCoordinator 继续使用：

- container 完全折叠时切页：container 保持折叠，目标页恢复自己的 `childDistanceFromTop`；
- container 尚未完全折叠时切页：container 位置不变，目标页归到顶部，并把该页 snapshot 更新为 `0`；
- 不暂存被清零的旧距离等待 Header 后续折叠时突然恢复；
- 不为了恢复目标页 offset 强制折叠 Header。

## Reload Generation

每次 `reloadData()` 创建一个递增 generation。收敛顺序如下：

1. 记录当前 generation、current 和进行中的 transition 状态。
2. 向 data source 请求新 page count；负数在 Debug assertion，Release 按 `0` 处理并记录日志。
3. 请求新 generation 的 titles 和 Header，不请求全部 page controllers。
4. 修正 default selected index：空数据无 effective selection；越界时夹到最后一个有效 index。
5. adapter 切换 page count/titles/default index 并调用 Pageboy reload。
6. Pageboy 按需请求新 default page；Store 在此时创建、复用或迁移页面状态。
7. 在 adapter 收到 `didReloadWith currentViewController` 后，确认新 generation 已装配。
8. 应用最新 bar/local-bottom inset，并按 container 状态恢复新 current offset。
9. 归还旧 generation 剩余 ownership，清理旧 fallback content、强引用和 snapshot。
10. 提交新 effective selection，并结束 reload 日志事务。

旧 generation 在第 7 步前保持 source/target 强引用和 ownership，避免仍可见页面在 reload 中间态跳动。
不使用异步延迟或 timer 猜测 Pageboy 何时完成。

若 reload 回调缺失或乱序，Store 保持旧 generation pin，不提前破坏可见页面；后续有效 terminal callback、
下一次 reload 或明确 selection 收敛点会先清理过期事务并记录异常日志。

## Appearance 与 Containment

1. 普通业务页面直接交给 Pageboy，AnchorPager 不重复 `addChild`。
2. fallback host 是 AnchorPager 自有 wrapper，只对其内部无 scroll 业务控制器执行一次标准 containment。
3. Store 增删强引用不是 appearance 事件，不调用 `beginAppearanceTransition` 或
   `endAppearanceTransition`。
4. 页面实际出现、消失、交互取消的 appearance 顺序由 `UIPageViewController`/UIKit 驱动。
5. AnchorPager 只记录 Pageboy will/did/cancel 作为缓存和 selection 事务输入，不伪造业务页面
   `viewWillAppear`/`viewDidDisappear`。

测试通过观察业务测试控制器的 UIKit 回调验证顺序和次数，但实现不依赖这些回调反推 selection。

## 配置变化

`AnchorPagerPagingConfiguration.keepsAdjacentPagesLoaded` 已是 public API，v0.4 只激活其既有语义，
不新增 API：

- 默认 `false`；
- 运行时从 false 改为 true 时，只给已经 live 的相邻页增加强保留，不主动创建；
- 从 true 改为 false 时移除 `configuredAdjacent`，但保留 current/transition reasons；
- 配置变化后统一执行一次 retention reconciliation。

## 错误处理

1. **data source 已释放：** 页面请求返回内部空白 page，记录 `children.page.dataSourceMissing`，不崩溃。
2. **index 越界：** 返回 nil 给 Pageboy，记录 debug 诊断；public 越界 selection 继续沿用现有 assertion/no-op。
3. **负 page count：** Debug assertion，Release 归零，记录 `children.page.invalidCount`。
4. **重复业务控制器：** Debug assertion，Release 使用空白 page，记录
   `children.page.duplicateController`。
5. **共享 scroll view：** 沿用 v0.3 collision 规则；尝试非冲突默认目标，否则降级 fallback host。
6. **回调重复或乱序：** 通过 generation 和 selection transaction id 幂等忽略，记录 paging 诊断；
   不使用 timer、强制 layout 或重复 reload 掩盖。
7. **页面创建过程中 data source 重入 reload：** 当前请求以捕获的 generation 校验；generation 已失效则
   丢弃新状态并归还刚建立的 ownership，不提交到新 generation。

内部空白 page 不包含业务信息，仅作为 Release 环境的结构安全降级。

## 日志

新增事件使用现有 `AnchorPagerLogger`，不记录标题、控制器类名或业务数据：

```text
children.page.load
children.page.reuse
children.page.recreate
children.page.retain
children.page.release
children.page.snapshot.save
children.page.snapshot.restore
children.page.snapshot.reset
children.page.generation.begin
children.page.generation.commit
children.page.generation.cancel
children.page.invalidCount
children.page.duplicateController
children.page.dataSourceMissing
```

高频路径只在 retention reason 集合、generation、snapshot 行为或异常发生变化时记录；container 每帧滚动
不得输出页面级普通日志。日志测试通过内部 sink 验证稳定事件名。

## 测试与验收

### 单元与集成测试

1. 首次 reload 只请求 count/titles/Header 和当前按需页，不加载全部 child view。
2. Pageboy/Tabman 重复请求同一 generation/index 时返回同一 live controller。
3. 页面弱释放后再次请求会调用 data source 创建新实例，并恢复 distance snapshot。
4. `keepsAdjacentPagesLoaded` false/true 的强保留窗口和运行时切换。
5. transition source/target pin、commit 和 cancel 后 reason reconciliation。
6. container 完全折叠时恢复目标 snapshot，未完全折叠时目标归顶并清零 snapshot。
7. reload generation 在 `didReloadWith` 前保留旧页，确认后释放旧页和 ownership。
8. 相邻 generation 同 index 同实例迁移，不重复 fallback containment。
9. 同 generation 重复 controller、负 count、data source 释放和越界请求降级。
10. 共享 scroll target 沿用 collision/fallback 语义。
11. fallback host 只执行一次标准 containment，淘汰和 reload 后可释放。
12. 动态 inset 更新访问集合大小与 active retention window 有关，不随 page count 线性增长。
13. 新增 children 日志事件和高频路径无噪声。

### UIKit 与 UI 测试

1. 分段栏点击、横向滑动和程序化切页仍能显示正确页面。
2. 交互切页完成与取消时，业务页面 UIKit appearance 回调顺序正确且不重复。
3. 长页滚动后切走、淘汰、切回，内容位置恢复。
4. Header 未完全折叠时切页，目标内容从顶部开始；完全折叠时恢复各页位置。
5. 无 scroll view fallback 页面切换、淘汰、重建后内容和 safe-area/inset 显示正确。
6. reloadData 替换页面时旧可见页无中间态跳动，确认后旧控制器可释放。

### 验收命令

实现阶段至少运行：

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=<available simulator>' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=<available simulator>' test
```

优先复用已启动 simulator，避免无意义重复启动。

## 影响范围

- **Public API：** 不新增类型；激活 `keepsAdjacentPagesLoaded` 已有配置语义并更新 DocC/README。
- **内部分层：** 新增 PageStateStore，PagingAdapter 改为 provider，移除或重定位旧 Child Store。
- **Containment/lifecycle：** Pageboy/UIKit 继续管理普通页面；fallback host 仅管理内部业务 child。
- **Scroll discovery：** 从 reload 全量发现改为页面首次按需请求时发现。
- **Inset ownership：** live page 建立、淘汰归还；snapshot 不复制 managed/external inset。
- **Paging adapter：** 不再强持有页面数组，新增 reload generation/transition 事件桥接。
- **Gesture/overscroll：** 不在 v0.4 实现，仅保持 v0.5–v0.7 边界。
- **日志：** 新增页面 load/reuse/retention/snapshot/generation/降级事件。
- **测试与示例：** 补充懒加载、释放、offset、appearance、fallback 和 reload UI 路径。
- **文档：** 更新 README、architecture、task-list 和 v0.4 实施计划。

## 后续版本边界

v0.5 的 ScrollCoordinator 只消费 PageStateStore 暴露的当前 page scroll target、
`childDistanceFromTop` 和 selection terminal 事件，不接管页面身份或缓存。v0.7 可以在 adapter 事件桥上
扩展完整 interaction state，但不得把 selection transaction 再复制到 Store。这样 page policy、纵向
owner 和交互仲裁保持单向依赖。
