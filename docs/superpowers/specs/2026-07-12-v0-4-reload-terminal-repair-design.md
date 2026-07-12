# v0.4 Reload Terminal 与生命周期验收修复设计

**日期：** 2026-07-12

**状态：** 待用户确认

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

### 方案一：稳定 Paging Host + 可替换 Adapter（采用）

在 viewport 中长期 contain 一个 internal paging host；host 内部 contain 当前
`AnchorPagerPagingAdapter`。普通非空 reload 继续复用 adapter；reload 到空数据时，host 标准移除旧 adapter，
自身进入空状态并发送 `.empty` terminal。下一次非空 reload 创建新 adapter。

优点：真实清理第三方 containment；不伪造页面数量；不依赖第三方 internal API；v0.5 面向稳定 host。
代价：新增一层 internal containment，并需要把 barInsets、selection 和 reload 回调统一转发。

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

host view 是 Header 下方固定分页 viewport 的约束对象。adapter 替换不会改变 AnchorPager 根布局约束。

### AnchorPagerPagingAdapter

adapter 继续是唯一 Tabman/Pageboy 类型边界。它只处理非空 reload；host 不会对空状态调用 Pageboy
`reloadData()`。adapter 的 `didReloadWith` 继续产生 `.page(index:)` 所需事件。

adapter 普通 reload 必须保持现有可见页直到 Pageboy terminal；不得为了统一路径而每次重建 adapter。

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
2. PagingHost 对旧 adapter 调用 `willMove(toParent: nil)`；
3. 移除 adapter view；
4. adapter `removeFromParent()`，由 UIKit 结束其 Pageboy containment；
5. host 清空 adapter 引用并报告 barInsets `.zero`；
6. host 发送 `.empty` terminal；
7. ViewController commit pending generation；
8. Store 归还旧 ownership、清理旧 fallback 和 snapshot；
9. public 空页状态与实际可见层级同时成立。

空到空重复 reload 仍发送当前 transaction 的 `.empty` terminal，但不重复 containment removal。空到非空先创建
adapter、安装 containment，再执行普通非空 reload，只有 Pageboy `didReloadWith` 后才 commit。

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
3. 空到非空：创建新 adapter，Pageboy terminal 后提交新 generation。
4. 空到空：幂等 terminal，无旧内容复现。
5. count/title/Header 回调分别重入 reload：新事务获胜，旧事务不发布。
6. public 负 count 路径发出 `children.page.invalidCount`。
7. 交互取消的 appearance 序列和 public selection/cache 收敛。

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

## 完成定义

1. 所有 RED 测试在旧实现上观察到目标失败，并在修复后转绿。
2. 非空、空、重入和取消路径都由自动化测试覆盖。
3. v0.4 设计、实施计划、task-list、architecture 和 README 状态一致。
4. 完整验证命令通过并记录实际数量、耗时和 warning。
5. 独立代码审查没有 Critical/Important 未解决项后，v0.4 才恢复“已实现并验收”。
