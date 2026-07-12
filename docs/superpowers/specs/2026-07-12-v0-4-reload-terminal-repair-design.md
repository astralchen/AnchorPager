# v0.4 Reload Terminal 与生命周期验收修复设计

**日期：** 2026-07-12

**状态：** 实施中；已按 Pageboy 5.0.2 实际 teardown 能力修订

**适用范围：** v0.4 合并前修复，并为 v0.5 的 current child/scroll owner 提供可信空页状态

## 背景与根因

v0.4 审查确认，现有非空 reload 通过 Pageboy `didReloadWith` 提交 pending generation，但空数据路径在
`AnchorPagerViewController` 内直接提交。Pageboy 5.0.2 的 `reloadData()` 在 page count 为 `0` 时会在
取得 default page 后直接返回：它既不会调用 `didReloadWith`，也不会清空内部现有
`UIPageViewController` 内容。

因此非空页面 reload 为零页时可能出现：

1. public `effectiveSelectedIndex` 已为 `nil`；
2. Store 已释放旧 generation 的 inset ownership 和 fallback content；
3. 旧 Pageboy 页面仍在可见层级；
4. v0.5 无法从 public selection、Store 和实际可见页面得到同一个 current owner。

根因不是 Store commit 本身，而是当前 paging adapter 边界没有定义“空结果 terminal”，主控制器在第三方
reload 没有完成时猜测了安全点。

审查同时发现三个相邻缺口：public `reloadData()` 的 count/title/Header 回调缺少重入事务保护；appearance
UI 验收只覆盖完成切页，没有覆盖取消；public 负 page count 在进入 Store 前被归零，承诺的 children 日志
在真实入口不可达。

## 目标

1. 非空、空数据 reload 都必须由 paging 层发出明确 terminal，主控制器不得自行猜测提交时机。
2. 空 terminal 发出前，旧 Tabman/Pageboy adapter 必须已经真实退出 UIKit containment。
3. 保持一个稳定 paging host，使 Header 几何和后续 v0.5 不依赖可替换 adapter 实例。
4. 所有 public data source reload 回调使用同一 transaction token，旧重入调用不得覆盖新调用。
5. 保留 PageStateStore 的 generation、identity、retention、snapshot 和 ownership 职责，不把第三方重置逻辑写入 Store。
6. 补齐交互取消的 UIKit appearance 顺序与 public selection/cache 收敛验收。
7. 修正文档状态、负 count 日志和实施计划证据。

## 非目标

1. 不实现 v0.5 container/child 纵向 handoff。
2. 不实现 v0.6 top overscroll owner。
3. 不实现 v0.7 完整 interaction state 或快速请求队列。
4. 不访问 Pageboy/Tabman internal API，不复制第三方源码。
5. 不新增或修改 AnchorPager public API。

## 方案比较

### 方案一：稳定 Paging Host + 可替换 Adapter + 集中兼容清理（采用）

在 viewport 中长期 contain 一个 internal paging host；host 内部 contain 当前
`AnchorPagerPagingAdapter`。普通非空 reload 继续复用 adapter；reload 到空数据时，host 先要求 adapter 通过
Pageboy 自身的 public delete-last-page 更新进入正式零页状态，确认旧业务页已退出第三方 containment 后，再清理
只剩第三方 plumbing 的 adapter 子树并标准移除旧 adapter、自身进入空状态、发送 `.empty` terminal。下一次非空
reload 创建新 adapter。

优点：真实清理第三方 containment；不伪造页面数量；不直接访问第三方 internal API；v0.5 面向稳定 host。
代价：新增一层 internal containment；需要把 barInsets、selection 和 reload 回调统一转发；还必须维护一个只针对
锁定版本 Pageboy 5.0.2 的集中兼容点及升级门禁。

### 方案二：内部 Sentinel Page（不采用）

公开 count 为零时向 Pageboy 报告一个内部空白页面，以换取 `didReloadWith`。

问题：形成“公开零页、Pageboy 一页”的双计数；需要隐藏 bar、屏蔽 selection、处理 indicator 和
appearance；会把空状态复杂度扩散到 v0.5–v0.8。

### 方案三：隐藏旧 Adapter 并直接 Commit（不采用）

只隐藏旧 adapter view 或清空 bar，然后直接提交 Store。

问题：旧 Pageboy containment、appearance 和资源仍然存在，public/Store/实际层级依旧不一致。

## 架构

```text
AnchorPager viewport
├─ Header
└─ AnchorPagerPagingHostViewController（稳定）
   └─ AnchorPagerPagingAdapter?（非空状态存在，空状态为 nil）
      ├─ Tabman bar
      └─ Pageboy child
```

### AnchorPagerPagingHostViewController

新增 internal MainActor 类型，位于 `Sources/AnchorPager/Paging/`。职责：

1. 标准 contain/remove `AnchorPagerPagingAdapter`；
2. 保存弱 `pageProvider` 和 `eventDelegate`，并在创建 adapter 时重新连接；
3. 转发 barInsets、will/did/cancel selection；
4. 把 reload terminal 标准化为：

```swift
enum AnchorPagerPagingReloadTerminal: Equatable {
    case page(index: Int)
    case empty
}
```

5. 非空 reload 复用当前 adapter；若当前为空则先创建并安装 adapter；
6. 空 reload 先移除旧 adapter，再把 barInsets 收敛为 `.zero`，最后同步发送 `.empty`；
7. host 不持有业务页面、不决定 generation、不管理 inset 或 snapshot。

Host 还维护一个 latest-wins 的 internal pending reload request，只保存 titles、page count 和 selected index，不保存
Store generation。当 adapter 正在用户/程序化 selection transaction 中时，Pageboy 5.0.2 不能安全执行
`reloadData()` 或 delete-last-page；Host 不调用第三方更新，而是暂存最新 reload。selection 的 did/cancel terminal
到达后，Host 丢弃该旧 selection 对上层的提交事件并立即执行最新 pending reload。后续 reload 覆盖先前 pending
request；pending 期间程序化 selection 返回拒绝。不得用 timer、主队列 delay 或猜测动画时长推进 pending reload。

host view 是 Header 下方固定分页 viewport 的约束对象。adapter 替换不会改变 AnchorPager 根布局约束。

### AnchorPagerPagingAdapter

adapter 继续是唯一 Tabman/Pageboy 类型边界。它只处理非空 reload；host 不会对空状态调用 Pageboy
`reloadData()`。adapter 的 `didReloadWith` 继续产生 `.page(index:)` 所需事件。

adapter 普通 reload 必须保持现有可见页直到 Pageboy terminal；不得为了统一路径而每次重建 adapter。

#### Pageboy 5.0.2 空态 teardown 兼容点

实施测试确认，仅把 adapter 从 PagingHost 移除，并不会同步拆除 adapter 内部 Pageboy 的
`UIPageViewController` containment；旧业务页仍可能以 `Pageboy.PatchedPageViewController` 为 parent。因此
“外层 remove adapter 等于内部页面已清空”的原假设不成立。

Pageboy 5.0.2 没有正式的 public `clearPages`/`detach` API。其 public `reloadData()` 在 count 为零时早退，
不能用于 teardown。源码和真实 UIKit 测试确认，public `deletePage(at:then:completion:)` 的 delete-last-page 路径
会把 Pageboy 的 `pageCount` 置为 `0`、`currentIndex` 置为 `nil`，并由 Pageboy 自己以内部 reset
`UIViewController` 替换旧业务页。这个 reset controller 是 Pageboy 在零页更新过程中的 plumbing，不由
AnchorPager 创建、不向 data source 报告、不形成公开或稳定的 sentinel page。

因此 adapter 提供唯一 internal `prepareForRemoval()` 兼容入口：

1. 记录旧 Pageboy page count/selected index，再把 adapter 的 data source count、titles 和 pending selection
   状态收敛为空；
2. 若 view 已加载且旧 count 非零，调用 Pageboy public `deletePage` 删除当前页；completion 只记录删除完成，
   不在 completion 内提前拆层级；
3. `deletePage` 整体返回后，必须同步确认 completion 已执行、public `pageCount == 0`、`currentIndex == nil`；
   任一条件不成立都不得发送 `.empty`；
4. 此时旧业务页已经由 Pageboy 解除 parent/view hierarchy。adapter 才能对自身剩余 direct-child plumbing 子树
   执行 post-order 标准 UIKit teardown；不得识别第三方类型、访问 internal 属性或递归触碰原业务页；
5. 方法返回后，PagingHost 移除 adapter、归零 barInsets 并发送 `.empty`。

adapter 同时提供只读 internal reload readiness。它只能由 adapter 已有的 pending will/did/cancel transaction、
pending programmatic selection 和 programmatic completion 计算；preflight 为 false 时不得先修改 count、titles、
selection 或 Pageboy 状态。Host 必须先做 preflight，再决定立即 reload 或暂存 latest pending request，不能通过调用
`prepareForRemoval()` 的失败副作用判断是否繁忙。

readiness 不使用 Pageboy public `isTracking`、`isDragging` 或 `isDecelerating` 作为额外 terminal。Pageboy 5.0.2
会在 `scrollViewDidScroll` 的 tracking/decelerating 阶段更新 current index 并发出 didSelect，同时滚动结束不再向
外部提供可覆写或 delegate 化的 ready 事件；若继续等待物理 flag，pending reload 会永久悬挂。AnchorPager 以
Pageboy 自己的 didSelect/didCancel 作为交互 selection 的权威语义 terminal；programmatic 路径额外等待 public
scroll completion closure，避免 Pageboy did 早于 completion。真实 UIPageViewController 完成/取消交互必须在
appearance cancel 验收中覆盖，不能只手工调用 delegate。

UIKit/Pageboy 对已移除 adapter、inner page controller 和 reset placeholder 的析构允许延迟到后续 main run-loop；
`.empty` 的同步契约是“业务 page parent/view、Host children 和 active adapter 已为空”，不是所有 UIKit 对象已经
同步 `deinit`。测试必须在 terminal 快照中验证同步 containment，在若干 main-queue turns 后用 weak 引用验证对象
最终释放；生产实现不得为释放或 terminal 添加 timer、dispatch delay 或下一轮队列等待。

该流程依赖 Pageboy 5.0.2 delete-last-page 的实际顺序，必须视为受控兼容 shim：只能存在于
`Sources/AnchorPager/Paging/`。任何 Pageboy 升级都必须重审 `deletePage`、零页 `performUpdates` 和
`reloadData()` 源码，并重新运行 containment、appearance、事件静默和延迟释放测试；若上游提供正式
clear/detach API，应立即替换 shim。不得把这个机制泄漏到 public API、Store 或主控制器。

### AnchorPagerViewController

主控制器只 contain paging host，不直接 contain adapter。它：

1. 在 host terminal 到达前保持 pending generation；
2. 收到 `.page(index:)` 后 commit，并按 index 收敛 Store current；
3. 收到 `.empty` 后 commit，保持 `selectedIndex == 0`、`effectiveSelectedIndex == nil`；
4. 不再包含 `pageCount == 0` 的直接 Store commit 特例。

## Reload Transaction

`reloadData()` 在第一次调用 public data source 前递增 transaction identifier：

```text
reserve transaction
  ↓
read count into local snapshot
  ↓ validate transaction
read Header into local snapshot
  ↓ validate transaction
read titles into local snapshot（每次回调后验证）
  ↓
atomically publish pageCount/titles/Header/selectedIndex
  ↓
begin Store generation
  ↓
PagingHost reload
```

任何 data source 回调重入 `reloadData()` 时，内层会取得更新的 identifier；外层在当前回调返回后发现 token
失效并立即退出，不能发布部分旧快照，也不能开始旧 generation。

页面 provider 闭包中的重入继续使用 Store 已有 generation 二次校验；两层保护分别覆盖“reload 元数据采集”
和“按需页面创建”。

## Empty Reload 顺序

非空到空的顺序固定为：

1. ViewController 原子发布空元数据并建立 pending generation；
2. PagingHost 调用旧 adapter 的 `prepareForRemoval()`；
3. adapter 通过 Pageboy public delete-last-page 同步进入 count 0/current index nil，并由 Pageboy 自己解除旧业务
   page containment；
4. adapter 在 delete 整体返回后清理剩余第三方 plumbing containment；
5. PagingHost 对已清空 adapter 调用 `willMove(toParent: nil)`；
6. 移除 adapter view并调用 `removeFromParent()`；
7. host 清空 adapter 引用并报告 barInsets `.zero`；
8. host 发送 `.empty` terminal；
9. ViewController commit pending generation；
10. Store 归还旧 ownership、清理旧 fallback 和 snapshot；
11. public 空页状态与实际可见层级同时成立；UIKit 对已移除 plumbing 对象可在后续 run-loop 自然析构。

空到空重复 reload 仍发送当前 transaction 的 `.empty` terminal，但不重复 containment removal。空到非空先创建
adapter、安装 containment，再执行普通非空 reload，只有 Pageboy `didReloadWith` 后才 commit。

### Selection 中 reload 顺序

若 animated/programmatic/interactive selection 尚未 terminal 时收到 reload：

1. ViewController 可以建立新的 pending Store generation，但旧 committed generation 继续持有实际页面和 ownership；
2. Host 发现 adapter 仍有 selection transaction 或 programmatic completion，只保存最新 reload request，不调用
   Pageboy reload/delete；
3. 旧 selection did/cancel terminal 到达时，adapter 先完成自己的 pending selection 状态；
4. Host 若仍有 pending reload，不把这个过期 selection terminal 转发成 public selection commit；
5. Host 立即执行最新 pending reload：非空走正常 Pageboy reload，空态走 `prepareForRemoval()`；
6. 只有新的 `.page`/`.empty` reload terminal 才提交最新 Store generation；旧 transition retention 随旧 generation
   释放；
7. 若 terminal 永不到达，pending 保持，不用 timer 猜测。后续更新的 reload 只替换 pending request。

## 错误处理与日志

1. data source 返回负 count：主控制器 Debug assertion、Release 归零，并记录
   `children.page.invalidCount`；Store 接收已归零 count。
2. 过期 reload transaction：记录 `lifecycle.reloadData.cancelled`，不发布旧快照。
3. 空 reload：记录 `paging.reload.empty`；adapter 安装/移除分别记录稳定 paging/lifecycle 事件。
4. 非空 reload 缺少 Pageboy terminal：保持旧 committed generation；不得 timer 猜测。后续 reload 先取消旧 pending。
5. 所有日志不记录标题、控制器类名、页面内容或几何数值。

## Appearance Cancel 验收

Example target 增加仅用于测试的跨页面 appearance recorder，记录页面标识和四类标准 UIKit 回调；框架实现
不读取 recorder，也不调用 appearance transition。

UI 测试执行不足完成阈值的横向拖动并释放，验证：

1. source 页面最终仍可见，public page 内容未切换；
2. source/target 的 will/did appearance 序列没有重复 terminal；
3. target 没有错误 `didAppear`；
4. 随后的正常切页仍能完成；
5. Store 的 cancel 单元测试继续验证 source current 和 target retention 清理。

若 XCUI 的交互取消在目标 simulator 上不稳定，允许使用同进程 UIKit 集成测试作为替代，但必须记录原因，
并通过真实 Pageboy/UIPageViewController 交互路径验证，不能直接调用 AnchorPager adapter delegate 伪造 appearance。

## 测试

### RED 回归测试

1. 非空 scroll page reload 到空：旧 page view/adapter containment 消失，旧 ownership 在 terminal 后归还。
2. 非空 fallback reload 到空：旧业务 child 完整移除，host 为空。
3. adapter `prepareForRemoval()`：旧 scroll/fallback page 的 parent 和 view superview 同步清空，不发送
   page/selection terminal，零态 guard 成立，正常非空 reload 与用户/程序化 selection 不受影响；terminal 后若干
   main-queue turns 内 adapter/inner/reset placeholder 的 weak 引用归零。
4. animated/interactive selection 中 reload 空或非空：第三方更新延迟到 did/cancel semantic terminal；programmatic
   路径还必须等待 completion。latest request 获胜，旧 selection 不提前提交 pending generation，不触发 assertion、
   假 terminal 或物理滚动 flag 导致的永久悬挂。
5. 空到非空：创建新 adapter，Pageboy terminal 后提交新 generation。
6. 空到空：幂等 terminal，无旧内容复现。
7. count/title/Header 回调分别重入 reload：新事务获胜，旧事务不发布。
8. public 负 count 路径发出 `children.page.invalidCount`。
9. 交互取消及空态 teardown 的 appearance 序列和 public selection/cache 收敛。

### 完整验收

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test
```

继续复用已启动模拟器，不执行无必要 boot/shutdown。

## 对后续版本的影响

1. v0.5 只依赖稳定 paging host、Store current scroll target 和 selection terminal，不缓存 adapter 实例。
2. 空状态下没有 adapter/current child，ScrollCoordinator 只能让 container 成为纵向 owner。
3. v0.7 的完整 interaction state 继续在 host 的标准化事件上扩展，不把 Tabman/Pageboy 类型泄漏出去。
4. v0.8 的 scrollsToTop owner 在空状态关闭所有 managed scroll view。
5. Pageboy 依赖升级属于 paging adapter 兼容边界变更，必须先替换或重新验证空态 teardown shim，不能只依赖
   package resolve/build 通过。

## 完成定义

1. 所有 RED 测试在旧实现上观察到目标失败，并在修复后转绿。
2. 非空、空、重入和取消路径都由自动化测试覆盖。
3. v0.4 设计、实施计划、task-list、architecture 和 README 状态一致。
4. 完整验证命令通过并记录实际数量、耗时和 warning。
5. 独立代码审查没有 Critical/Important 未解决项后，v0.4 才恢复“已实现并验收”。
