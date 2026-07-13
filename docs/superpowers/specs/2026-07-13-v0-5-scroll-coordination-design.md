# v0.5 纵向滚动协调与代理所有权设计

> 2026-07-13 修订：本文关于 fallback 页作为 child scroll owner 或 simultaneous pair 的描述已被 `2026-07-13-plain-page-direct-containment-design.md` 取代。无 scroll 当前页的 committed page 非 nil、scroll target 为 nil，纵向手势只由 container 消费。
>
> 2026-07-13 第二次修订：本文的“临时 container 顶部 bounce”与 active pan 全程关闭 child `bounces` 的规则已被 `2026-07-13-boundary-bounce-ownership-design.md` 取代。新设计分离 stable range 与 native boundary pass-through，并按现有 public mode 路由正式顶部 owner。

**日期：** 2026-07-13

**状态：** Ready；Task 1–7、无滚动页直接 containment 与边界 owner 修订已实现，前三轮复审问题均已修复；第四次整分支独立复审 Critical 0、Important 0，两个 Minor 已在最终状态提交中修复

**适用范围：** v0.5 `AnchorPagerScrollCoordinator`、当前 container/current child 连续纵向 handoff、最小 simultaneous recognition、stable/native boundary 分离和真实手势验收

**依赖基线：** v0.4 committed current page/scroll target、request-aware reload/selection terminal、固定 Pageboy viewport、managed inset ownership 和 `childDistanceFromTop` snapshot 已完成并通过最终复审。

## 背景

v0.3–v0.4 已固定分页几何、child inset ownership、页面身份、缓存窗口和 reload generation，但现有 v0.5 描述仍有四个不能直接进入实现的问题：

1. “私有 delegate proxy”没有说明如何保留业务 child 已有的 `UIScrollViewDelegate`。
2. container 与 child 的 pan recognizer 都只有一个 delegate，不能直接覆盖 child 的 gesture delegate。
3. 同时识别后两个 scroll view 都会收到同一手势，不能依赖 UIKit callback 顺序猜测剩余 delta。
4. 完全展开后的继续下拉属于 v0.6，但 v0.5 必须先给出不会产生双 bounce owner 的临时终态。
5. simulator RED/GREEN 验证确认：给任意 `UIScrollView` 的内建 `panGestureRecognizer.delegate` 赋值都会抛出 `NSInvalidArgumentException`，错误为“UIScrollView's built-in pan gesture recognizer must have its scroll view as its delegate.”；因此 container pan forwarding proxy 同样不可实施。

本设计只固定 v0.5 的内部契约和实施边界，不实现代码，不扩大 public API。

## 目标

1. 任何时刻都不设置业务 child 的 `UIScrollView.delegate`，包括临时替换、forwarding proxy、解绑后恢复、测试注入或缓存原 delegate。
2. 不替换业务 child 的 `panGestureRecognizer.delegate`。
3. 由 AnchorPager 自有 `UIScrollView` 子类实现 simultaneous recognition，不设置 container 或 child 的内建 pan delegate。
4. 使用同一 pan 起点和 translation 计算总纵向距离，不依赖 container/child callback 先后顺序。
5. 保持“container 未完全折叠时 child 在顶部；child 离开顶部时 container 完全折叠”的唯一 owner 不变量。
6. 完全展开后的额外下拉在 v0.5 临时只允许 container 原生 bounce，child 保持顶部；v0.6 再按 public mode 接管。
7. 只绑定 Store committed current/empty 事实，并在 matching reload、selection complete 或 selection cancel terminal 后同步重绑定。
8. 通过单元、UIKit 集成和 Example UI test 验证真实连续手势，不以直接写 contentOffset 代替全部验收。

## 非目标

1. 不实现 v0.6 的 `.none`、`.container`、`.child` overscroll mode 路由、阈值或事件 owner。
2. 不实现 v0.7 的完整 interaction state、横向/返回手势优先级或跨 owner 惯性转移。
3. 不替换 Tabman/Pageboy 的横向 containment、selection transaction 或 appearance lifecycle。
4. 不把 owner、handoff、generation、container 子类或 observation 暴露到 public API。
5. 不通过切换任一 scroll view 的 `isScrollEnabled` 完成交接。

## 方案选择

### 采用：container UIScrollView 子类 + child KVO/target-action + canonical distance

AnchorPager 已明确拥有 `verticalScrollView.delegate`，因此现有 container scroll delegate 可继续转发到 ScrollCoordinator。`verticalScrollView` 的运行时实例改为 internal `AnchorPagerContainerScrollView`，公开属性的静态类型仍为 `UIScrollView`。child 侧只使用可撤销的 `NSKeyValueObservation` 观察 `contentOffset`/`contentSize`，并向 child pan 添加 target-action 观察 state 和 translation；代码路径中禁止对 child `UIScrollView.delegate` 赋值或保存/恢复其值。

`AnchorPagerContainerScrollView` 自身实现 `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`，只放行自己的 pan 与 weak committed current child pan 这一精确 pair。它不读取或写入任何 recognizer 的 delegate，rebind 只更新 weak child pan。child pan delegate 与 UIKit 管理的 container pan delegate 始终保持原值。

每次拖拽从固定起点计算 canonical total distance，再分配给 container 和 child，避免两个原生 scroll callback 对同一 delta 重复消费。

### 不采用：替换 child scroll delegate

业务 child 可能依赖 UITableView/UICollectionView 或自定义 `UIScrollViewDelegate`。即使做 forwarding，也无法可靠处理接入方在运行中替换 delegate 的语义，且会把业务代理生命周期纳入 AnchorPager ownership。

### 不采用：切换 `isScrollEnabled` 或在边界重建 pan

该方案会中断正在进行的 gesture、丢失 velocity，并使同一根手指无法连续跨越 container/child 边界。

### 参考验证：JXPagingView

以 JXPagingView `8aa5663720ebfab0c4df41cfca04b113f832c5b2` 为只读参考完成以下验证，不复制源码、不新增依赖：

1. `JXPagingMainTableView` 通过 `UITableView` 子类自身实现 `UIGestureRecognizerDelegate` simultaneous 方法，没有替换内建 pan delegate，证明 container 子类入口符合 UIKit 实际约束。
2. 普通模式由业务列表在自身 `scrollViewDidScroll` 中回调框架，Smooth 模式使用 KVO 观察 child `contentOffset`/`contentSize`；两者都不要求框架替换业务 child scroll delegate。
3. JXPagingView 默认放行任意 pan pair，并在主容器拖动时切换自有横向容器 `isScrollEnabled`。AnchorPager 不沿用这两点：前者收紧为 committed current 精确 pair，后者会干扰 Tabman/Pageboy 且违反连续手势约束。
4. Smooth 模式把 Header/inset 分散到 child scroll view，和 AnchorPager 固定 Pageboy viewport、独立 Header host、managed inset ownership 不同，因此只验证手势入口与 observation 模式，不迁移其布局架构。

## 组件与所有权

### AnchorPagerScrollCoordinator

MainActor internal 类型，只负责：

- 当前 container/current child 的纵向位置不变量；
- pan 起点、translation 和 canonical total distance；
- guarded contentOffset 写入；
- 当前 committed child 的 observation/target-action 绑定与解绑；
- owner/阈值变化日志。

它不持有 Host、Adapter、provider、page identity、generation state、cache reason 或 snapshot。

### AnchorPagerVerticalScrollDelegate

现有 `VerticalScrollDelegate` 从 ViewController 私有嵌套类型重定位为单一职责 internal 类型。它仍是 `verticalScrollView.delegate` 的唯一 owner，将 container `scrollViewDidScroll` 和 drag/deceleration 边界转给 ViewController/ScrollCoordinator；Public API 仍只读暴露 `UIScrollView`。

### AnchorPagerContainerScrollView

仅作为 `verticalScrollView` 的 private runtime instance：

1. 继承 `UIScrollView`，显式声明 `UIGestureRecognizerDelegate` 并实现 `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`；显式声明是 Swift 6 下让 UIKit optional protocol dispatch 命中子类实现的必要条件。
2. 仅当识别对恰好是自己的 pan 与当前 committed child pan 时返回 `true`；任意横向 pager pan、旧 child pan、非 pan 或无绑定均返回 `false`。
3. `bindCurrentChildPan(_:)` 只 weak 保存 child pan，相同实例重绑幂等，nil 同步解除 pair。
4. 不给 container/child pan delegate 赋值，不保存、转发或恢复 recognizer delegate。
5. Public API 继续是 `public let verticalScrollView: UIScrollView`，第三方类型和内部子类均不泄漏。

### Child observation

每次 committed-current rebind 建立一组 binding resource：

- weak child scroll view；
- `contentOffset` observation；
- `contentSize` observation；
- child pan target-action；
- binding token，用于拒绝旧 observation 的迟到事件。

解绑顺序为先失效 token，再移除 pan target，最后 invalidate observations。旧 child、空态、reload replacement 和 controller deinit 都必须同步走相同 teardown。

## 坐标与 canonical distance

定义：

```text
containerExpandedOffset = 0
containerCollapsedOffset = collapsibleDistance
childTopOffset = -child.contentInset.top
childDistanceFromTop = max(0, child.contentOffset.y - childTopOffset)
canonicalTotal = clamp(containerOffset, 0...containerCollapsedOffset)
               + childDistanceFromTop
```

pan `.began` 时捕获：

```text
gestureStartTotal
gestureStartTranslationY
```

pan `.changed` 时只从 container pan 的 translation 计算：

```text
upwardDelta = gestureStartTranslationY - currentTranslationY
desiredTotal = max(0, gestureStartTotal + upwardDelta)
desiredContainer = min(desiredTotal, containerCollapsedOffset)
desiredChildDistance = max(0, desiredTotal - containerCollapsedOffset)
```

child 最大可见距离使用当前 `contentSize`、`bounds` 和 managed/external inset 计算并 clamp；短内容页得到 `0`。`contentSize` 变化只更新上限并幂等 settle，不改写 managed inset target。

container/child 原生 callback 只作为“需要 settle”的触发，不作为 delta 来源。无论 callback 缺失、重复或乱序，同一个 pan translation 都产生同一个 desired pair。

## Guarded update

ScrollCoordinator 使用同步 scoped guard 包围主动 contentOffset 写入：

1. 进入 guard 前计算完整 container/child 目标对。
2. 先锁定非 owner，再写 owner，避免中间状态同时违反两个不变量。
3. observation 或 container scroll delegate 在 guard 内重入时只记录一次 skip 状态，不递归 settle。
4. 仅当目标与当前值差异超过统一 epsilon 时写入。
5. guard 退出后复验稳定不变量；失败时执行一次同步幂等收敛，不使用 Task、dispatch delay 或重复 layout 掩盖问题。

## 向上与向下交接

### 向上

1. `desiredTotal < collapsedOffset`：container 消费，child 固定 `childTopOffset`。
2. `desiredTotal == collapsedOffset`：container 固定 collapsed，child 仍在顶部。
3. `desiredTotal > collapsedOffset`：container 固定 collapsed，剩余距离进入 child。

### 向下

1. childDistance 大于 0：先减少 childDistance，container 固定 collapsed。
2. childDistance 到 0 后：剩余距离展开 container，child固定顶部。
3. container 到 0 后：Header 完全展开。

### v0.5 顶部下拉临时规则

v0.5 不读取 `topOverscrollHandlingMode`。Header 完全展开后继续下拉时：

1. child 始终固定 `childTopOffset`，不得产生 child 顶部 bounce。
2. 只保留 `verticalScrollView` 已有的原生负 offset/presentation translation，container 是唯一临时 bounce owner。
3. 负 offset 不进入 canonicalTotal，也不保存到 PageState snapshot。
4. 手势回弹到 0 后重新进入普通 canonical distance 分配。

真实 simulator pan 验收补充确认：仅靠 child `contentOffset` KVO 不能满足第 1 条。UIKit 可以先把原生负 offset 发布给业务 `UIScrollViewDelegate`，再触发框架 KVO 收敛；最终 offset 虽然回到顶部，业务层仍已观察到一次瞬态 child bounce。因此 v0.5 增加以下内部 bounce 租约：

1. committed child 位于顶部，或 container pan 正在进行时，ScrollCoordinator 临时把该 child 的 `bounces` 设为 `false`，从源头阻止 UIKit 发布负 offset。
2. container pan 结束且 child 已离开顶部后，恢复绑定开始时记录的业务 `bounces` 值；这样不长期取消 child 自身的底部 bounce。
3. committed binding 切换、空态解绑或 coordinator 失效时，必须同步恢复旧 child 的原始 `bounces` 值。
4. 该租约不得修改 child 的 `delegate`、pan delegate、`isScrollEnabled`、content inset 或 page state；它只闭合 v0.5 已声明的唯一顶部 bounce owner。
5. 如果业务在绑定期间自行修改 `bounces`，v0.5 仍以绑定开始时的值作为解绑恢复值；动态业务配置协商不在本版本范围内。

该规则只用于让 v0.5 独立可交付。v0.6 必须替换这一临时路由，并根据 `.none`、`.container`、`.child` 选择正式 overscroll owner；不能建立第二套纵向 handoff。

## Drag 结束与减速边界

v0.5 保证手指仍按下时的连续 delta 交接。drag 结束后：

1. 当前稳定 owner 可以继续 UIKit 原生减速。
2. 非 owner 在任何 offset callback 中继续被锁定到边界。
3. v0.5 不把 container 的剩余减速 velocity 合成到 child，也不反向合成。
4. 跨 owner 惯性转移和统一 `verticalDecelerating` interaction state 属于 v0.7。

该限制必须写入 README known limitations，并有测试证明不会出现双 owner 或边界跳动。

## Committed current 绑定时序

ScrollCoordinator 只通过 ViewController 读取 Store 的：

```swift
committedCurrentPageViewController
committedCurrentScrollView
```

同步重绑定发生在：

1. matching reload page/empty terminal 完成 Store commit、terminal index 收敛和可见布局后；
2. selection `didSelect` 完成 Store current 提交后；
3. selection cancel 完成 Store source 恢复后；
4. committed current scroll target 释放并在安全同步点重新解析后；
5. controller teardown 时绑定到 nil。

rebind 使用同一个 `reconcileCommittedScrollBinding()` 入口。pending provider generation、willSelect target、staged reload snapshot 和空态猜测均不能调用该入口产生新 owner。相同 child 重绑必须幂等，不重复 observation 或 pan target。

## 结构性布局与 inset

1. LayoutEngine 继续是 collapsible distance 和 fixed paging frame 的唯一几何来源。
2. ManagedInsetCoordinator 继续是 child inset 的唯一写入 owner。
3. ScrollCoordinator 只消费 resolved collapsible distance、child inset 后的 top offset 和 content bounds，不写 managed inset。
4. bar/inset 结构性变化先由既有流程保持 childDistance，再把新边界交给 ScrollCoordinator settle。
5. Header 普通滚动热路径不改变 adapter height 或 Pageboy child bounds。

## 异常与降级

1. committed child 为 nil：解绑 observations，container 独立滚动，child owner 为 nil。
2. child 在手势中释放：binding token 失效，停止 child 写入并收敛 container；不从 provider pending 猜测替代页。
3. child delegate 或 child pan delegate 变化：不干预，因为 AnchorPager 从未拥有它们。
4. container 或 child 内建 pan delegate：AnchorPager 永不替换；若 UIKit 不再以 container scroll view 自身进行 simultaneous 查询，真实手势 UI test 必须失败并阻止版本完成，不能用运行时 delegate 覆盖降级。
5. contentOffset/contentSize 非有限：断言并记录 scroll 诊断，当前事件降级为最近一次稳定 pair。
6. observation 重入或旧 token 回调：忽略且不输出逐帧普通日志。

## 日志

新增稳定事件：

```text
scroll.binding.begin
scroll.binding.end
scroll.binding.stale
scroll.owner.container
scroll.owner.child
scroll.handoff.containerToChild
scroll.handoff.childToContainer
scroll.boundary.expanded
scroll.boundary.collapsed
scroll.boundary.childTop
scroll.offset.guard.apply
scroll.offset.guard.skip
gesture.simultaneous.enabled
resource.scrollObservation.release
```

事件不携带页面标题、controller 类型、offset 数值或 view hierarchy。owner、boundary、binding 状态只有变化时记录；pan changed、KVO 和 layout 热路径不得逐帧输出普通日志。

## 测试策略

### 纯协调单元测试

把 canonical total 分配提取为不操作 UIKit 的 internal 纯计算：

1. 向上跨 collapsed boundary 不丢 delta。
2. 向下跨 child top boundary 不丢 delta。
3. 短内容 child 的 distance clamp 为 0。
4. 非有限输入降级到稳定 pair。
5. callback 顺序排列不改变相同 translation 的结果。

### UIKit 集成测试

1. child 已有 scroll delegate 在绑定、滚动、切页、reload 和解绑后保持同一实例并继续收到回调；源码检查同时断言生产代码不存在 child `delegate` 赋值路径。
2. child pan delegate 始终保持原实例。
3. container scroll view 子类只放行当前 committed child pair，且 container/child pan delegate identity 始终不变。
4. selection complete/cancel、nonempty/empty reload 后绑定与 committed current 一致。
5. guarded update 不递归，旧 observation token 不修改新绑定。
6. contentSize、bar inset 和 Header layout 变化后不震荡。
7. controller 释放后 observations、pan target 和 weak child pair 同步清理。

### Example UI test

必须使用真实 simulator drag，不以直接赋值 contentOffset 替代：

1. 长列表向上一次连续 drag：Header 先折叠，剩余位移继续滚动 child。
2. 已滚动 child 向下一次连续 drag：child 先回顶部，剩余位移展开 Header。
3. 短内容页和 fallback 页保持稳定，不出现双 bounce 或跳动。
4. Header 完全展开后继续下拉：只有 container 可见 bounce，child 保持顶部。
5. 部分折叠与完全折叠状态切页，目标页遵守 snapshot/归顶规则。
6. UI test 同时断言 Header/bar/page 可见几何和可访问标识，失败时使用稳定日志事件定位。

如果 XCTest 无法直接读两个 scroll offset，使用示例内部测试状态标签表达 collapse state 与 child distance 区间；该标签只存在于 Example target，不进入框架 public API。

## 文档与版本门禁

1. 本设计登记到 `AGENTS.md` 必读文档。
2. v0.5 实施前必须创建并登记对应详细计划。
3. 计划必须按 TDD 拆分纯计算、代理/observation、coordinator、ViewController 集成、日志、Example UI test、文档和完整验收。
4. v0.5 未通过真实 pan UI test、完整框架测试、Example build/test、自审和独立复审前，不得标记完成或开放 v0.6。
5. 本设计与旧固定分页设计冲突时，以本设计的 v0.5 代理所有权、delta、bounce 和测试契约为准。

## 影响范围

1. **Public API：** 不变。
2. **内部分层：** 新增 ScrollCoordinator、container scroll view 子类、child observation resource；Store/Inset/Paging 职责不变。
3. **Containment/lifecycle：** 不改变 Pageboy/UIKit containment 或 appearance；新增 observation/target/weak pair 同步清理。
4. **Scroll discovery：** 只消费 committed current scroll target，不缓存 provider pending。
5. **Inset ownership：** 只读最终 inset，不复制 managed inset 写入。
6. **Gesture/overscroll：** v0.5 只实现最小纵向 pair和临时 container bounce；v0.6/v0.7 后续职责保持。
7. **日志：** 新增状态变化事件，无逐帧噪声。
8. **测试/示例：** 新增真实手势 UI 验收和 delegate 保留集成测试。

## 自审结论

1. child scroll delegate 和 child pan delegate ownership 已明确为接入方/UIKit 所有，AnchorPager 不替换。
2. simultaneous recognition 只通过 container scroll view 子类建立，不写入任何内建 pan delegate，并收紧为 committed current 精确 pair。
3. canonical total 使剩余 delta 与 callback 顺序解耦，不形成 offset/constraint/contentSize 反馈闭环。
4. v0.5 临时顶部 bounce owner 与 v0.6 正式 overscroll owner 边界明确。
5. committed current、Store、Inset、Paging、ScrollCoordinator 职责保持单向。
6. UI test、资源清理、日志和已知限制均有明确验收，不存在占位符或未选方案。

## 最终修订实施状态

本文中被页首修订说明取代的临时 bounce/业务 `bounces` 租约仅保留为历史决策记录，当前生产实现已删除。最终实现只绑定 committed current scroll target，Binding 使用 KVO 与 pan target-action，container 子类只放行 committed pair，ScrollCoordinator 分配 stable position 并约束非 owner，顶部与底部 native boundary 由同日边界 owner 规格统一收口。

2026-07-13 初始实现者完整验收为 Framework 264 项、Example 36 项、generic Simulator build 全部成功，0 fail、0 skip，xcresult 0 warning。其后初次独立复审发现 3 个 Important：未呈现 owner 反向回稳丢失 delta、Header 部分折叠时 child top KVO 错误创建顶部 owner，以及 `.none` 探针把 delegate/KVO 同轮瞬时 offset 误记为可见 presentation。`f81ca1e` 分别以“只同步结束从未呈现的 active owner 并重放 resolver”“child top 仅在 container expanded epsilon 内路由”“Example 使用显示帧采样并同步清理生命周期”修复。第二次整分支复审随后发现零稳定区间的 callback 可直接跨到相反 boundary；`5b80893` 在纯 Overscroll policy 内同步结束不同 boundary 的未呈现 owner并继续新 route，同 boundary 与已呈现 owner 保持不变。第三次整分支复审发现已呈现 `.top/.child` owner 由 child KVO 从 `-12` 越过到 `+6` 时，递归 stable settle 会把 raw total 6 错分配成 collapsed container + child 6；`128821f` 让 enforcement 显式返回 finish owner，pan 路径同轮应用当前 resolver input，observer-only `.top/.child` 以 `containerBoundary + rawChildDistance` 保留总量并交给同一 Resolver container-first 分配，其他 finish 语义保持不变。同期 requirements 的旧 guarded apply/skip 逐帧日志条款已改为只记录 owner/handoff/boundary 状态变化或受控采样。第四次整分支独立复审覆盖 `be2d783...13b3d95`，结论为 Critical 0、Important 0、Minor 2；README 旧验收摘要与 `.container` 顶部 UI 缺少 `childTopMax < 0.5` 严格排他断言两个 Minor 已在最终状态提交中修复。最终证据为生产代码 HEAD `128821f` 对应 Framework 283/283（`/private/tmp/AnchorPagerPresentedTopFrameworkFull-20260713-2258.xcresult`）、Example 37/37（10 单元 + 27 UI）和 generic Simulator build，全部 0 fail、0 skip、0 error/warning/analyzer warning；本规格标记 v0.5 Ready。
