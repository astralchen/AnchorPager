# v0.4 Reload 代际原子性与 PageState 隔离修复设计

**日期：** 2026-07-12

**状态：** 已确认，待实施计划

**适用范围：** v0.4 最终复审发现的 deferred reload 代际不一致、跨 generation 可变 PageState 共享，以及 v0.5 committed current child/scroll target 启动门禁

**技术基线：** 最低工具链 Swift 6.2、语言模式 Swift 6、最低系统版本 iOS 14；不以并发 unsafe 标记规避工具链诊断。

## 背景与根因

v0.4 reload terminal 修复已经建立稳定 PagingHost、page/empty terminal、Pageboy 5.0.2 空态 teardown、
latest-wins pending reload 和 public data source 重入保护。完整自动化验收通过，但最终独立复审发现两个仍会破坏
唯一 owner 的代际问题。

### deferred reload 只延迟了第三方调用

selection transaction 活跃时，PagingHost 会暂存最新 reload request，旧 adapter/page 继续可见；但
`AnchorPagerViewController.reloadData()` 已立即发布新 `pageCount`、`selectedIndex`、Header、titles，并让 Store
建立 pending generation。Store 又使用 `pending ?? committed` 作为通用 active generation。

因此 deferred 区间同时存在：

1. 旧 adapter 和旧 page 仍是实际可见内容；
2. public selection 和 Header 已属于新代际；
3. page provider、inset 更新和 current scroll 查询优先读取尚未交给 Pageboy 的 pending generation；
4. 旧 adapter 若再次请求 page，可能混入新 generation identity。

根因是 reload request 没有从 metadata snapshot、Host start、provider activation 到 terminal commit 形成一个带标识的
端到端事务。

### migration 共享可变 PageState

Store 当前把 committed generation 的同一个 `PageState` 实例直接放入 pending generation。pending retention
reconciliation 会改写共享的 `retentionReasons`、`retainedPage`、`childDistanceFromTop`，甚至归还 inset ownership。
这会在 Pageboy terminal 前修改仍可见的 committed generation。

根因是页面 live identity 和 generation-specific lease/snapshot 被放在同一个可变对象里。

## 目标

1. deferred reload 返回后，public 状态、旧可见 page、Store visible current 和 ownership 保持同一 committed 事实。
2. Host 真正开始第三方 reload 前才激活 provider generation；Pageboy terminal 前不得发布新 public visible state。
3. Host request、will-perform 和 page/empty terminal 使用同一个 internal request identifier，迟到 terminal 不能提交新事务。
4. page provider 可以读取正在执行 reload 的 pending generation；selection、layout、inset 和 v0.5 current 查询只读取 committed-visible generation。
5. generation 之间可以复用 live controller/fallback/scroll identity，但不得共享 retention、strong lease、snapshot 或 transition 状态。
6. ownership 转移只在 terminal commit 时完成；取消 pending generation 不改变 committed ownership。
7. 提供 v0.5 可依赖的 committed current child/scroll target internal 入口。
8. 不新增或修改 public API，不泄漏 Tabman/Pageboy 类型。

## 非目标

1. 不实现 v0.5 纵向 container/child handoff。
2. 不实现 v0.6 overscroll owner、v0.7 完整 interaction state、v0.8 scrollsToTop 或尺寸恢复。
3. 不改变 Pageboy 5.0.2 teardown shim。
4. 不引入 timer、dispatch delay、强制取消手势或第三方 internal API。
5. 不以每次重建所有业务 controller 规避 generation migration。

## 方案比较

### 方案 A：Host request ID + staged public snapshot + generation-specific lease（采用）

ViewController 保存最新 metadata snapshot；Host 保存最新轻量 paging request。Host 真正执行时用 request ID 通知
ViewController 激活 provider generation；Pageboy terminal 带回同一 ID，ViewController 再原子提交 Store 和 public
visible state。Store 把 live identity payload 与 generation-specific state 分开。

优点：端到端时序可证明；保持现有懒加载和 identity 复用；为 v0.5 提供可信 committed current。
代价：需要调整 Host delegate 契约、ViewController reload 编排和 Store 内部状态结构。

### 方案 B：reloadData 强制结束当前 selection 后立即 reload（不采用）

问题：Pageboy 没有满足当前约束的 public 强制完成/取消 API；手工拆 transition 会破坏 appearance 和 selection
terminal，也会把 v0.7 interaction 职责提前塞入 v0.4。

### 方案 C：每个 generation 全量重建页面（不采用）

问题：破坏同 controller identity、fallback containment、offset snapshot 和按需缓存语义；还可能在旧 Pageboy page
仍 contained 时创建第二套 page，不能解决唯一 owner。

## 架构

```text
public reloadData
  └─ collect ReloadSnapshot（latest transaction）
       └─ PagingHost.enqueue(requestID, titles, count, selectedIndex)
            ├─ busy：只保存 latest request；旧 committed 事实不变
            └─ ready：willPerform(requestID)
                 ├─ Store.beginProviderGeneration(requestID)
                 └─ Pageboy reload / empty teardown
                      └─ terminal(requestID)
                           ├─ Store.commitProviderGeneration(requestID)
                           ├─ publish public metadata/Header/selection
                           └─ expose committed current child/scroll target
```

### ReloadSnapshot

`AnchorPagerViewController` 增加 private MainActor snapshot，只保存一次 data source transaction 的完整结果：

```swift
private struct ReloadSnapshot {
    let requestIdentifier: Int
    let pageCount: Int
    let selectedIndex: Int
    let titles: [String]
    let headerContent: AnchorPagerHeaderContent?
}
```

ViewController 最多保存 latest staged snapshot 和当前 activated request ID。snapshot 不进入 public API，也不传给
Store；Host 只接收 paging 所需的 request ID、titles、count 和 selected index。

### PagingHost request lifecycle

Host 的 `ReloadRequest` 增加 request identifier，并区分：

```text
pending request：selection/reload transaction 阻塞期间保存的 latest request
active request：已调用 willPerform、等待 page/empty terminal 的唯一 request
```

规则：

1. active request 存在时，新的 reload 只能覆盖 pending request，不能并行调用 Pageboy。
2. Host 开始 request 前调用 internal delegate `willPerform requestIdentifier`；delegate 返回 false 时不得调用 Pageboy。
3. adapter `didReloadAt` 和 empty terminal 必须映射到 active request identifier。
4. terminal 先发送给 ViewController，再清理 active request；随后尝试执行 latest pending request。
5. pending/active request 存在时程序化 selection 返回 false。
6. 旧 selection did/cancel 只用于解除 readiness；存在 pending reload 时不提交旧 public selection。
7. 不使用 timer；推进只来自 did/cancel、programmatic completion 或 reload terminal。
8. request-aware ViewController 接入完成后，删除 Host/Adapter 的无 request identifier reload 与 terminal 兼容桥；
   internal 层只保留一条带 request identifier 的 reload/terminal 契约，避免双 terminal 语义长期并存。
9. active reload 期间产生的 bar insets（包括 empty 的 `.zero`）属于该 request 的 staged geometry，不得先通过
   `didUpdateBarInsets` 写入旧 committed scroll；Host 必须在 matching terminal 中携带最终 bar insets，非 reload 期间的
   bar insets 变化才允许即时发布。

### ViewController 激活与提交

#### 已有可见 committed generation

1. `reloadData()` 只采集并保存 latest snapshot，然后 enqueue Host request。
2. Host deferred 时，`pageCount`、`selectedIndex`、`effectiveSelectedIndex`、Header 和当前 Store visible state 均保持旧值。
3. Host `willPerform` 到达且 request ID 等于 latest snapshot 时，Store 创建 provider generation；public state仍不发布。
4. Pageboy 在 reload 中请求 page 时只从 provider generation 取值。
5. 匹配的 page/empty terminal 到达后，Store commit provider generation；随后一次性发布 snapshot 的 public fields 与
   terminal bar insets、安装 Header、更新布局并按 terminal index 收敛 committed current。empty terminal 的 bar insets
   必须为 `.zero`，旧 committed scroll 在 terminal 进入前保持原 inset/ownership。
6. 不匹配、迟到或已被 supersede 的 request 不得 commit。

#### view 尚未加载且没有 committed visible generation

为保持既有 UIKit 风格调用语义，首次 pre-load `reloadData()` 可以立即发布 snapshot 的 public metadata，并建立尚未
commit 的 provider generation，因为此时不存在旧可见 page/owner。`setSelectedIndex` 在 view load 前可更新该 snapshot
和 provider current index。

`viewDidLoad` 后才向 Host 提交 request；Host `willPerform` 对已经激活的同 ID 幂等，terminal 后正式 commit。
后续 pre-load reload 仍是 latest-wins，并安全取消旧 pending provider generation。

### Store generation 角色

Store 明确区分：

```text
providerGeneration = pendingGeneration ?? committedGeneration
visibleGeneration  = committedGeneration ?? pendingGeneration
committedGeneration = v0.5 唯一可消费的 current 事实
```

用途：

- `pageViewController(at:)` 使用 provider generation；Pageboy 正在执行新 reload 时必须能取得新页面。
- selection、managed inset update、retention 查询、snapshot 查询和现有 current scroll/page 查询使用 visible generation。
- 只有没有 committed generation 的首次 pre-load/initial load 才允许 visible fallback 到 pending。
- 新增 internal committed-current 查询，至少提供 committed current index、actual page 和 scroll view；返回 weak/live
  结果，不扩大 public API，也不转移 Store ownership。

## Page identity 与 generation-specific state

### Shared live identity payload

generation 之间允许共享一个 internal live identity payload：

```text
weak originalViewController
weak actualPageViewController
weak childScrollView
weak fallbackHost
original controller identifier
claimed scroll identifier
hasLoadedBefore
```

payload 只描述 live identity，不保存 current/transition/cache reason、strong page lease 或 offset snapshot。

### GenerationPageState

每个 generation/index 拥有独立状态：

```text
identity payload
retentionReasons
retainedPage
childDistanceFromTop
```

迁移规则：

1. 同 controller 在新 generation 同 index：新建 GenerationPageState，共享 payload，复制 committed distance。
2. 同 controller 移到新 index：共享 payload，但新 generation distance 初始化为 0；committed distance 不变。
3. pending retention reconciliation 只能改 pending state。
4. pending 取消时只释放 pending lease；共享 payload 的 fallback content、managed inset 和 committed lease保持不变。
5. terminal commit 时先把 pending 变成 committed；在释放旧 generation 最后一个 strong lease 前，必须强捕获旧代
   unique fallback/scroll cleanup snapshot。共享 payload 不重复拆 containment，unique 资源清理不得依赖 weak identity 或析构副作用。

## Ownership 与 snapshot 提交

1. pending page 创建可以对它实际使用的 scroll view 应用当前 managed inset target，但不得因为 pending reason 为空而
   归还 committed generation 仍使用的 ownership。
2. pending reconcile 只计算 reason 和 strong lease，不执行会影响共享 committed payload 的 ownership release。
3. containment identity preservation 与 generation-specific managed inset ownership lease 必须分离判断；identity 被新代共享
   不代表旧代 ownership lease 可以保留，pending cancel/commit 都必须分别收敛 containment 与 ownership。
4. commit 必须按以下顺序执行：

   ```text
   pending -> committed
   强捕获旧 generation unique fallback/scroll cleanup snapshot
   release old generation strong leases
   force reconcile new committed ownership
   使用 cleanup snapshot 清理旧代 unique fallback/scroll 资源
   ```

   cleanup snapshot 至少强持有完成 fallback containment removal 与 scroll ownership release 所需的对象，直到清理结束；
   不得在最后 strong lease 释放后再从 weak payload 猜测资源是否仍存活。
5. commit 后对新 committed generation 强制执行一次 ownership reconciliation：
   - 新 committed retained state 保持 ownership；
   - 无 reason 的 state 保存自己的 snapshot并归还 ownership；
   - 旧 generation 独有 payload 归还 ownership并清理 fallback content；
   - 新旧共享 payload 不重复 release/remove。
6. pending cancel 使用 actual page/scroll/fallback identity 判断 containment preservation，但 ownership lease 必须按 generation
   独立判断，不能再使用 GenerationPageState 对象地址或仅凭 identity 相同保留旧 ownership。
7. committed scroll/fallback 的 offset、inset adjustment behavior 和 retained current 在 terminal 前不得改变。

## Header、bar 与布局顺序

1. deferred 区间 Header 和 public metadata 保持 committed 版本。
2. Host 开始 Pageboy reload 时可更新 adapter titles/default index，但 Header 仍保持 committed。
3. terminal 到达后发布 Header snapshot并重新测量布局；barInsets 仍由 Host/adapter 标准回调更新。
4. initial pre-load 没有旧可见事实，可以在 view load 时安装已发布 Header。

## 错误处理与日志

新增或调整稳定事件：

- `paging.reload.deferred`：Host 保存/覆盖 pending request。
- `paging.reload.begin`：带 request 语义但日志不输出 identifier 数值。
- `paging.reload.stale`：Host/ViewController 拒绝不匹配 request。
- `children.page.generation.begin/commit/cancel`：继续表示 provider generation lifecycle。
- `lifecycle.reloadData.cancelled`：继续只表示 metadata callback transaction 被重入抢占。

任何 willPerform 拒绝、terminal ID 不匹配或 provider generation 缺失都不得猜测 commit；Debug assertion 配合无业务
数据日志。日志不输出标题、controller 类型、request ID 数值或 view hierarchy。

## 测试

### deferred reload 端到端 RED

1. programmatic selection 活跃时 reload 非空：reloadData 返回后 public selected/effective/Header、visible current page、
   scroll target、ownership 和旧 adapter provider identity仍属于 committed generation。
2. selection 活跃时连续 empty/nonempty reload：只保留最新 snapshot/request；旧 selection terminal 不提交，最新
   request terminal 后一次性切换 public/Store/页面。
3. active reload 未 terminal 时再次 reload：第二 request 不并行执行；迟到第一 terminal 不能提交第二 snapshot。
4. view 未加载 reload + setSelectedIndex：保持既有 public 语义；加载后 terminal commit 同一 request。

### Store generation isolation RED

1. begin pending generation 后，provider 读取 pending page，但 visible/committed current page 和 scroll 仍为旧 generation。
2. 旧 current scroll controller 在 pending 移到非 current index：terminal 前 committed retention、strong lease、offset、
   inset ownership不变；commit 后按新 index/reason 收敛。
3. fallback page 执行同样重排：terminal 前 fallback parent/content/inset 不变，commit 后无双 containment。
4. pending 被更新 request 取消：committed PageState、snapshot 和 ownership完全不变。
5. 相同 controller 同 index migration：两个 generation 的 state identifier 不同，live payload identity 相同。
6. 旧代 unique fallback/scroll 只由最后 strong lease 保活时，commit 必须先强捕获 cleanup snapshot；释放 lease 后仍按标准
   containment 顺序清理 fallback，并由 recording child 明确观察到 `willMove(toParent: nil)`，同时归还 scroll ownership。
   测试不得依赖 Debug 生命周期延长、weak payload 恰好存活或对象 `deinit` 的副作用。

### 回归与验收

- 现有 reload reentry、empty teardown、latest pending、programmatic 双请求、cache window、offset restore/reset、
  appearance complete/cancel 测试全部保留。
- Framework 全量、Example generic build、Example 全量 UI、`swift package resolve` 和 `git diff --check` 必须重跑。
- 最终独立复审必须清零 Critical/Important，才能恢复 v0.4 完成状态并开放 v0.5。

## 对后续版本的影响

1. v0.5 只能消费 Store 的 committed current page/scroll target 和 Host 标准 terminal；不得读取 provider pending。
2. v0.6 overscroll owner 与 v0.8 scrollsToTop 同样只能基于 committed/empty 事实。
3. v0.7 可以扩展 Host request/selection transaction，但不得建立第二套 generation owner。
4. v0.6–v0.9 路线无需重排；本修复是它们共同的代际一致性门禁。
5. Pageboy 升级仍必须重新验证 delete-last-page teardown、reload terminal 和 request 串行化。

## 完成定义

1. 两个最终复审 Important 都有先失败后通过的自动化测试。
2. deferred terminal 前 public、visible Store、旧 page 和 ownership保持 committed 一致。
3. generation migration 不共享可变 retention/snapshot/lease。
4. v0.5 committed current internal 入口存在并有单元测试。
5. public API 未变化，第三方类型不泄漏，生产代码无 timer/delay/internal API。
6. 文档状态和新鲜完整验收结果一致。
7. 最终独立复审没有 Critical/Important。
