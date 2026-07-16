# AnchorPager v0.7 交互、选择事务与跨 owner 惯性设计

**日期：** 2026-07-15

**状态：** Task 0–15、横向-only 纵向目标回归与 Compositional Layout 页面级分页专项均已完成；v0.7 Ready

**适用范围：** v0.7 interaction state、快速选择请求、Tabman bar 点击、Pageboy 横向 pan、纵向跨 owner 惯性、reload/layout/尺寸仲裁、系统返回优先级和业务横向手势可行性边界

## 背景

v0.5 已完成 container/current child 的单根手指纵向连续 handoff，v0.6 已完成 stable/native boundary 分离和三种顶部 owner 路由。当前代码仍保留以下明确边界：

1. `AnchorPagerScrollCoordinator` 在 pan 结束时只收敛稳定 offset，不把剩余 velocity 从 container 合成到 child，也不反向合成。
2. API 程序化选择由 `AnchorPagerPagingAdapter` 保存 pending 状态；`AnchorPagerPagingHostViewController` 只用 adapter readiness 串行 reload，并没有真正拥有 selection request。
3. Tabman bar 点击走 `TabmanViewController.bar(_:didRequestScrollTo:)` 的默认实现，直接调用 Pageboy，不进入 Adapter 的程序化 completion 状态。
4. 当前没有统一的 interaction state 来仲裁纵向拖拽、横向分页、程序化分页、顶部回弹、Header layout reload 和尺寸过渡。
5. Pageboy 内部 paging `UIScrollView.delegate` 由 Pageboy 自己持有；AnchorPager 不能通过替换 delegate 获取横向手势生命周期。

本设计以本地锁定源码为第三方契约基线：

- Tabman `4.0.1`，revision `030dd80277bb36c9a832f232ff85af1b436cabd8`
- Pageboy `5.0.2`，revision `293e7860ac0eafabd7301cad5fe69bdabde56102`

## 源码审查结论

### 连续非动画请求窗口

Pageboy `_scrollToPage` 先检查 tracking、decelerating、page position 和 `isScrollingAnimated`，随后把真实 `UIPageViewController.setViewControllers` 更新排到下一轮主队列。外层 admission 不检查内部 `isUpdatingViewControllers`，而内部 updater 在该标志为 true 时直接返回且不调用 completion。

因此，同一主线程调用栈内连续两次 `animated: false` 时可能出现：第二次 `scrollToPage` 返回 true，但内部更新没有执行，也没有 semantic terminal 或 completion。当前 Adapter 会在调用前把 pending programmatic selection 替换为第二笔，最终导致 selection 与 reload readiness 永久悬空。

该行为视为 Pageboy 5.0.2 的调用方串行契约，AnchorPager 不修改第三方源码，也不并发调用 Pageboy。

### 动画 completion 不等于 executor ready

Pageboy 5.0.2 的动画完成顺序是：

1. `UIPageViewController.setViewControllers` completion 先把 `isUpdatingViewControllers` 设为 false。
2. Pageboy 更新 `currentPosition/currentIndex` 并发送 semantic did-select。
3. Pageboy 调用接入方传入的 programmatic completion。
4. programmatic completion 返回后，Pageboy 才把 `isScrollingAnimated` 设为 false；其 `didSet` 通过 Pageboy 自身的 open `isUserInteractionEnabled` 属性恢复内部 paging scroll view 交互。

因此，Host 不能在动画 completion 调用栈内立即启动 latest selection；此时 Pageboy 外层 admission 仍会因 `isScrollingAnimated == true` 拒绝。v0.7 必须把 programmatic completion acknowledgement 与 Pageboy executor-ready acknowledgement 分开。

非动画路径在 programmatic completion 前已经把 `isUpdatingViewControllers` 设为 false，且 `isScrollingAnimated` 始终为 false，因此 completion 可以同步视为 executor ready。动画路径由 Adapter 覆写继承自 Pageboy 的 open `isUserInteractionEnabled` 属性；只有在 matching completion 已 acknowledgement 后收到 `true`，才发布 executor ready。此时 Pageboy 的 `isScrollingAnimated` 存储值已经是 false，`isUpdatingViewControllers` 也已经是 false。该 hook 使用第三方公开覆写点，不依赖 UIKit KVO、timer、主队列 delay 或 Pageboy 私有属性。

### Tabman bar 请求入口

`TMBarView` 把按钮点击交给 `TMBarDelegate`；`TabmanViewController` 的 open 默认实现直接调用 `scrollToPage(..., completion: nil)`。`addBar` 会把 bar delegate 固定为 TabmanViewController 自身。因此 AnchorPager 必须在 `AnchorPagerPagingAdapter` 覆写 `bar(_:didRequestScrollTo:)`，不得从外部替换 bar delegate。

### 横向 paging surface

Pageboy 的 `UIPageViewController` 和内部 scroll view 不是 public API，但实际 containment 在 Adapter 子树中可发现。AnchorPager 已在 page presentation 路径使用同一 containment 边界查找 `UIPageViewController.view`。v0.7 将集中建立一个可撤销的 paging surface observation：

1. 只在 Adapter 内查找真实 `UIPageViewController`、其 paging `UIScrollView` 和 pan gesture。
2. 只添加 target/action 和只读 observation，不设置 scroll delegate 或 pan delegate。
3. Adapter teardown、surface identity 变化和 deinit 时同步解绑。
4. 该内部缝隙后续可供 v0.8 把 paging scroll view 的 `scrollsToTop` 关闭，但 v0.7 不提前实现完整 scrollsToTop owner manager。

### Tabman 已有能力

Tabman 4.0.1 的默认 bar 已为 item 提供 `.button` trait，并在 selection state 变化时增删 `.selected` trait。Pageboy 5.0.2 已按 layout direction 归一化程序化方向和横向 position。v0.9 应验证并补齐集成缺口，不重新实现已有能力。

## 目标

1. 建立唯一 internal interaction state，处理 begin、重要 update、finish、cancel 和非法 transition。
2. 让 API、Tabman bar 和 Pageboy interactive swipe 进入同一套 Host selection transaction。
3. 支持一笔 active explicit selection 和一笔 latest pending explicit selection，旧 completion 不清除新意图。
4. 保持每个真实 Pageboy terminal 与 Store committed current、public `selectedIndex` 一致。
5. 把纵向剩余 velocity 在 container/child 边界进行双向合成，同时保持 ScrollCoordinator 是唯一协调期 offset writer。
6. 明确 reloadData、reloadHeaderLayout、尺寸变化和手势竞争的优先级。
7. 不扩大 Public API，不泄漏 Tabman/Pageboy 类型，不改变业务 child delegate、pan delegate、bounce 或 `isScrollEnabled`。

## 非目标

1. 不主动中断或强制重置 Pageboy 已接受的 transition。
2. 不修改 Tabman/Pageboy 源码，不依赖 private selector、KVC 或固定 UIKit 私有类名。
3. 不建立第二套 reload generation、page identity、cache window、snapshot 或 inset owner。
4. 不实现 refresh control、业务 overscroll 回调或顶部任务。
5. 不在 v0.7 实现尺寸变化后的最终 offset snapshot 恢复；v0.7 只提供 `transitioningSize` 仲裁生命周期，完整恢复属于 v0.8。
6. 不在 v0.7 实现完整 scrollsToTop owner manager。
7. 不为任意业务横向滚动新增 Public API 或条件式边界 handoff。

## 架构与唯一事实源

### AnchorPagerPagingHostViewController

Host 是唯一 selection request 仲裁者，负责：

1. 分配单调递增的 internal selection request identifier。
2. 同时保存至多一笔 active transaction 和一笔 latest pending explicit request。
3. 接收 public API 与 Tabman bar explicit request。
4. 在 Pageboy interactive will-select 到来时收编为 active interactive transaction。
5. 串行 selection 与已有 reload request，不复制 reload generation。
6. 只接受 active adapter、matching identifier、matching target 的 terminal/acknowledgement。

Host 不持有业务页面、Store、provider generation、scroll target 或 UIKit offset。

### AnchorPagerPagingAdapter

Adapter 是第三方执行与回调标准化边界，负责：

1. 接收 Host 已分配 identifier 的 explicit selection 并调用 Pageboy。
2. 覆写 Tabman bar 请求入口，把 index 交回 Host，不直接调用 `super` 的滚动实现。
3. 标准化 Pageboy will/did/cancel 和程序化 completion。
4. 为同一 executing request 附带 Host identifier；interactive will-select 请求 Host 同步分配 identifier。
5. 维护可撤销 paging surface/pan observation。

Adapter 不再拥有 explicit request queue，不决定 latest-wins，不提交 public selection，也不拥有 reload generation。

### AnchorPagerInteractionCoordinator

原路线中的 `AnchorPagerGestureCoordinator` 改名为 `AnchorPagerInteractionCoordinator`，因为它同时处理非手势事务。

Coordinator 只负责：

1. 维护唯一主交互状态。
2. 校验状态转换和优先级。
3. 告知 Host 当前能否开始/推进 selection 或 reload。
4. 告知 ViewController 当前应立即执行还是合并 Header layout request。
5. 记录 begin、重要边界 update、finish、cancel 和非法 transition 日志。

Coordinator 不写 contentOffset，不提交 selection，不持有 page、provider、Store 或 Tabman/Pageboy 类型。

### AnchorPagerGesturePriorityCoordinator

GesturePriorityCoordinator 只管理 AnchorPager 已验证的系统返回失败关系：

1. 弱持有 Pageboy paging pan 和 navigation interactive-pop gesture。
2. 只调用 UIKit public `require(toFail:)`，不设置任何 recognizer delegate。
3. Pageboy paging pan 对 interactive-pop gesture 建立失败依赖，使 leading-edge 系统返回优先。
4. Pageboy paging surface identity 改变时，只为新 paging pan 重新建立当前系统关系。

该 coordinator 不遍历、接管或安装任意业务 child 手势。真实 UIKit 验收已否定 `pagingPan -> childPan` 和附加 guard 两种自动方案；业务 scroll identity 不再进入该 coordinator。

### AnchorPagerScrollCoordinator

ScrollCoordinator 继续负责：

1. active 纵向协调期间的 container/child offset 写入。
2. stable range resolver、guarded update、boundary enforcement 和 binding。
3. 生成结构化 vertical dragging/decelerating/top overscroll 事件。
4. 运行跨 owner synthetic deceleration driver。

### AnchorPagerOverscrollCoordinator

OverscrollCoordinator 仍是唯一 boundary owner policy。Interaction Coordinator 的 `topOverscrolling` 只响应 OverscrollCoordinator 已确认的 begin/finish/cancel，不保存第二份 boundary/owner 状态。

### AnchorPagerViewController 与 AnchorPagerPageStateStore

ViewController 和 Store 仍是实际可见页面语义的唯一提交层：

1. matching did-select 后 Store 提交真实 current page，ViewController 提交 public `selectedIndex`。
2. matching cancel 后 Store 恢复 source retention/scroll binding，public selection 不变。
3. pending explicit request 不是 visible current，不能参与 layout、inset、scroll、scrollsToTop 或 lifecycle owner 查询。

## 内部类型

### Selection request

selection request 至少包含：

- `identifier`：Host 分配的单调递增内部标识。
- `targetIndex`：目标页。
- `animated`：是否动画。
- `source`：`api`、`bar` 或 `interactive`。

`api` 和 `bar` 是 explicit request，可进入 latest pending；`interactive` 由正在发生的 Pageboy 手势创建，不能排队伪造。

### Selection transaction

active transaction 额外记录：

- transition source index。
- semantic terminal：尚未到达、did-select 或 did-cancel。
- programmatic completion acknowledgement：是否仍等待。
- Pageboy executor-ready acknowledgement：是否仍等待。
- active adapter identity。

API 与 bar transaction 必须同时收到 semantic terminal、completion acknowledgement 和 executor-ready acknowledgement 才能释放 active 并推进 reload/latest pending。interactive transaction 只等待 did-select/did-cancel。

semantic did-select 到达时立即提交真实 current page；completion 与 executor-ready 只控制 transaction readiness，不重复发送 public didSelect。

若 programmatic completion 先暴露缺失 semantic callback：

1. `finished == true` 且 Adapter 真实 Pageboy current index 等于 target 时，Host 建立 matching recovery did-select，提交一次实际页面并记录 missing-semantic 日志。
2. `finished == false` 且 semantic terminal 仍为空时，Host 建立 matching did-cancel，返回 transaction source 并记录 missing-semantic 日志。
3. semantic terminal 已到达时，completion 只 acknowledgement，不重复 did-select/did-cancel。

executor-ready 规则：

1. 非动画 transaction 的 completion 同步 acknowledgement completion 与 executor ready。
2. 动画 transaction 的 completion 只 acknowledgement completion；Adapter 保留 matching ready request identifier。
3. Adapter 覆写的 Pageboy `isUserInteractionEnabled` 随后收到 `true` 时，发布 matching executor ready，并清除 ready identifier。
4. `false`、无 matching ready identifier、重复 `true` 或旧 identifier 都不能释放 active transaction。
5. teardown 必须以 structural cancel 清除 ready identifier；旧 Adapter 迟到 hook 不能释放新 Adapter 的 active transaction。

### Interaction state

状态集合保持：

- `idle`
- `verticalDragging`
- `verticalDecelerating`
- `horizontalPaging`
- `programmaticPaging`
- `topOverscrolling`
- `layoutReloading`
- `transitioningSize`

状态可以携带内部 request identifier 或纵向 interaction identifier，但这些值不得进入 Public API 或日志消息正文。

## Explicit selection 规则

### Admission

1. target 越界时保持既有 public no-op + Debug assertion。
2. 没有 active/pending，且 target 等于 committed selected index 时 no-op。
3. active 存在时，新 explicit request 替换 latest pending。
4. 新 target 与 active target 相同且没有不同 pending 时视为重复请求，不新增 pending。
5. 新 target 与 committed index 相同但 active target 不同，仍是有效 latest intent，表示 active 完成后返回 committed page。
6. 因此 ViewController 不再仅用 `selectedIndex == target` 提前返回；重复/no-op 统一由 Host 基于 active、pending 和 committed state 判断。

### Active + latest pending

用户已确认采用以下语义：

1. `A -> B` 已 active 时收到 `C`，保存 `C` 为 latest pending。
2. 随后收到 `D`，`D` 替换 `C`。
3. 不主动取消 Pageboy 的 `A -> B`。
4. `B` 的真实 terminal 仍提交 Store/public selection，保证实际 UIKit 页面与公开状态一致。
5. `B` 的 completion acknowledgement 到达后只更新 transaction；非动画 `B` 可同时 acknowledgement executor ready。
6. 只有 semantic terminal、completion acknowledgement 和 executor-ready acknowledgement 全部满足后才释放 active；若 `D` 仍有效，直接启动 `B -> D`。动画 `B` 不得在 completion 调用栈内启动 `D`。
7. `B` 的旧 completion/ready 只能 acknowledgement `B` 的 identifier，不能清除或覆盖 `D`。
8. 非相邻 `B -> D` 使用 Pageboy 单次 source/target transition，不逐页执行中间 index。

如果当前处于 `verticalDragging` 或 `topOverscrolling`，explicit request 只进入 pending，不中断仍按下的真实 pan；回到 idle 后再开始。若当前只是 `verticalDecelerating`，explicit request 同步取消 synthetic deceleration 后可以开始。这样不通过 toggle recognizer 或 `isScrollEnabled` 强行终止业务触摸。

### Pageboy rejection

Host 只有在没有 active Pageboy execution 时才调用 Adapter。若 Pageboy 仍返回 false：

1. Adapter 返回 rejected-before-start terminal，并清理自身 executing context。
2. Host 只结束 matching active，不提交 selection。
3. Host 记录拒绝日志并继续评估 latest pending 或 reload。
4. 不使用 timer、dispatch delay、强制 reload 或 gesture reset 猜测第三方状态。

## Interactive selection 规则

1. Adapter 的 Pageboy will-select 没有 executing identifier 时，Host 创建 `interactive` active transaction并同步返回 identifier。
2. did-select 提交真实 current；did-cancel 恢复 source，不提交 public selection。
3. duplicate will 使用同一 identifier，不创建新 transaction。
4. did-select 缺少 will 时，以 active adapter 的真实 Pageboy current index 为门禁建立 recovery interactive transaction，记录 missing-will 日志并提交实际页面，避免 Store/public 与 UIKit 脱节。
5. cancel 缺少 active transaction 时没有新的真实页面，记录 stale/missing 日志后忽略。
6. 程序化 active 期间理论上 Pageboy 已关闭交互；若收到冲突 interactive will，不创建第二笔 active，只记录非法第三方回调。

## Tabman bar 规则

1. Adapter 覆写 `bar(_:didRequestScrollTo:)`，不调用 super。
2. bar 请求与 API 请求共用 Host admission、active/latest pending 和 request identifier。
3. bar 默认使用动画，Reduce Motion 的动画降级仍属于 v0.9，不在 v0.7提前建立第二份配置。
4. bar 本身不乐观提交 selection；indicator 继续由 Tabman 消费 Pageboy position/did-select 更新。

## Interaction state 转换

### 基本规则

1. 同一时刻只有一个主 interaction state。
2. specialized coordinator 的真实状态仍由 specialized coordinator 拥有；Interaction Coordinator 只保存跨域仲裁状态。
3. 重复 begin/update/finish/cancel 必须幂等或记录一次非法 transition，不能触发重复 terminal。

### 优先级

从高到低：

1. `transitioningSize`
2. 已开始的结构性 `layoutReloading`
3. `programmaticPaging` / `horizontalPaging`
4. `topOverscrolling`
5. `verticalDecelerating`
6. `verticalDragging`
7. `idle`

UIKit 已经决定真实 recognizer winner 时，Interaction Coordinator 不通过修改 delegate 或切换业务 `isScrollEnabled` 推翻 UIKit；它只接受第一个合法 begin，并让竞争路径 cancel/ignore。

### 垂直状态

1. container 或 committed child pan began：`idle -> verticalDragging`。
2. OverscrollCoordinator 确认 top begin：`verticalDragging -> topOverscrolling`。
3. top finish 回到同一根仍 active 的 pan：`topOverscrolling -> verticalDragging`。
4. pan ended 且存在原生或 synthetic 惯性：进入 `verticalDecelerating`；否则回 `idle`。
5. 新 pan、selection、reload、layout 或尺寸变化会同步 cancel synthetic deceleration。

### 横向与程序化状态

1. Pageboy interactive will-select：`idle -> horizontalPaging`。
2. Host 开始 API/bar request：`idle -> programmaticPaging`。
3. matching terminal + 该 transaction 要求的全部 acknowledgement 完成后回 `idle`，然后 drain latest pending/reload/layout。
4. did/cancel 可以先于 completion；此时 transaction 仍 active，状态保持 `programmaticPaging`。

### 尺寸状态

1. `viewWillTransition` 或等价结构性尺寸过渡进入 `transitioningSize`，暂停 Host queue draining并取消 active boundary/synthetic deceleration。
2. 已由 Pageboy 接受的 selection 不伪造 cancel，matching callback 仍由 Host 收敛。
3. 尺寸过渡结束后，若 selection transaction 仍 active，恢复对应 paging state；否则回 `idle` 并 drain。
4. v0.8 在该生命周期上增加 selected/Header/child offset snapshot 恢复，不创建另一套 size state。

## Reload 与 Header layout 仲裁

### 统一 drain 顺序

安全点的待处理事务严格按以下顺序推进：

1. 等待已经交给 Pageboy 的 active selection matching terminal 与全部 required acknowledgement。
2. 等待正在进行的 `transitioningSize` 结束。
3. 执行 latest reload request；reload terminal 未提交前不执行后续项。
4. 执行 latest Header layout request。
5. 启动仍属于当前 committed generation 的 latest pending selection。
6. 没有待处理事务时进入 `idle`。

reload 到来会丢弃旧 generation pending selection，因此第 5 项只可能消费 reload 后重新产生或始终未被 reload 取代的请求。

### reloadData

1. public reload transaction 和 Store generation 规则保持现状。
2. 非 idle 纵向 pan/overscroll 或 size transition 期间，Host 只保存 latest reload，不调用 Adapter reload。
3. reload 到来时丢弃尚未开始的 latest pending selection，因为 target 属于旧 metadata/generation。
4. active selection 继续等待真实 semantic terminal/acknowledgement；Host 保存 latest reload request。
5. selection 释放后先执行 latest reload，不先启动旧 generation 的 pending selection。
6. reload pending/active 时新 selection no-op 并记录 reload-pending 日志。
7. matching reload terminal 后再由 ViewController/Store 发布新 committed generation。

### reloadHeaderLayout

1. `idle` 时同步执行现有四种 offset adjustment。
2. 非 idle 时只保存一笔 latest layout request；后到请求替换前一笔，包括 adjustment policy。
3. 回到 idle 后，结构性优先执行合并后的 layout，再开始 selection pending。
4. layout 执行前同步取消 boundary presentation/synthetic deceleration，仍通过既有 geometry transaction 写 raw/logical offset。
5. 不使用异步 delay 或重复 layout pass。

## 跨 owner 惯性合成

### 设计原则

1. 当前 owner 在自身稳定范围内优先保留 UIKit 原生减速。
2. 只有原生 owner 到达 container/child handoff 边界且仍有同向剩余 velocity 时，才启动 synthetic handoff。
3. synthetic handoff 只推进 canonical total，再由现有 resolver 分配 container/child。
4. 非 owner 始终由 guarded writer 锁在边界，不允许双 owner。
5. synthetic phase 中，除 ScrollCoordinator guarded writer 之外的原生 offset 回调都不能成为第二个写入源：进入 synthetic 时先以 guarded、非动画写入把目标 owner 锁回法定 handoff boundary，终止其因 simultaneous recognition 产生的竞争原生减速，再由 canonical overflow 写出目标位置；旧 native owner 锁回 handoff boundary，目标 owner 的迟到原生回调按当前 synthetic canonical total 恢复完整稳定 pair。该路径不得 reset gesture 或修改业务 delegate、pan delegate、`isScrollEnabled`、`bounces`、`alwaysBounceVertical`。

### 输入

pan ended 时记录：

- interaction identifier。
- 初始纵向 velocity。
- monotonic start time。
- 当前 canonical total。
- 当前 owner 和方向。
- 当前 scroll view 的 `decelerationRate.rawValue`。

Child binding 和 container pan target 都必须上报 velocity；不占用任何 scroll/pan delegate。

手指 velocity 转换为 canonical velocity 时使用 `canonicalVelocity = -panVelocityY`：向上 fling 为正，向下 fling 为负。deceleration rate 记为 `d`，只接受 `0 < d < 1`；否则不启动 synthetic handoff并记录一次 cancel。

### Driver

新增 internal `AnchorPagerVerticalDecelerationDriver`：

1. 生产路径固定使用 `CADisplayLink`，在 MainActor 上运行。
2. 按 elapsed time 和只读 deceleration rate 计算当前剩余 velocity。
3. 每 tick 产生 canonical total delta，不直接持有或写 UIScrollView。
4. ScrollCoordinator 消费 delta，通过 existing guarded resolver 写 container/child。
5. velocity 小于统一 epsilon、达到不可穿越边界、identity 变化或 interaction cancel 时同步停止。

纯计算使用 UIScrollView deceleration rate 的毫秒衰减模型：

```text
v(t) = v0 * d^(1000 * t)
delta(t0, t1) = v0 * (d^(1000 * t0) - d^(1000 * t1)) / (-1000 * ln(d))
```

其中 `t` 使用秒，`v` 使用 pt/s。剩余速度绝对值不大于 `5 pt/s` 时 finish；stable/boundary geometry 仍使用现有 `0.5 pt` presentation epsilon。衰减计算和 tick integration 拆成接收固定 elapsed time 的纯计算类型；单测直接驱动纯计算，不给生产 driver 增加第二套 timer 或测试专用 UIKit 路径。

### 双向 handoff

1. container 向上减速到 fully collapsed 时，把同向剩余 velocity 交给 child。
2. child 向下减速到 child top 时，把同向剩余 velocity 交给 container 展开 Header。
3. 到达顶部/底部 stable range 后是否进入 native boundary owner，继续由 OverscrollCoordinator 根据 mode 和真实 scroll target 决定。
4. plain page 没有 child scroll target，不创建 child synthetic owner；其纵向惯性只由 container 表达。

## 横向、返回与业务手势优先级

1. Adapter 暴露的 internal Pageboy pan 只用于 observation 和 failure relation，不泄漏 Public API。
2. `pagingPan.require(toFail: interactivePopGestureRecognizer)` 让 navigation controller 的 interactive pop gesture 在 leading edge 优先于 Pageboy paging pan；该保证至少覆盖第一页，且不设置系统 recognizer delegate。
3. 真实 UI 证明 `pagingPan.require(toFail: childPan)` 会与 UIKit 同向嵌套 scroll 的层级仲裁形成依赖环，Pageboy 仍获胜；无论关系在 committed 后或 child containment 前安装，结果均相同，因此不得安装该关系。
4. 真实 UI 也证明附加 internal guard 无法在不接管既有 recognizer delegate、不重置手势、不依赖私有层级且不阻塞页面其他区域的前提下稳定改变 winner。v0.7 因此不声明任意业务横向 child 优先于 Pageboy，也不保留无效 guard。
5. UIKit public API 不能安全表达“只在业务横向 scroll 命中区域或边界内由 child 消费、其他区域交给 Pageboy”的动态关系。若未来支持，必须先形成显式接入契约与独立设计；不得通过遍历业务 view tree、替换 delegate、强制 reset、写 offset 或私有 API 隐式实现。
6. container/current child 的纵向 simultaneous pair 继续只由 `AnchorPagerContainerScrollView` 放行；Pageboy pan 和无关 pan 不加入该 pair。
7. 已声明的真实优先级必须用导航栈、第一页、非第一页和普通纵向 child 的 UIKit/UI 测试固定，不能只用直接调用 delegate 方法代替；业务横向 child 用例作为不支持结论的证据保留在计划验收记录，不作为已交付能力。

## Task 15 fresh-pass 修复契约

1. Pageboy 真实 `didSelect` 缺失对应 `willSelect` 时，Adapter 不能只记录日志并丢弃 terminal。只有 active adapter 的公开 `currentIndex` 已等于 callback index、index 仍在当前 page 范围、没有其他 execution 且该 index 不等于 Adapter committed index 时，才允许建立一笔 recovery interactive execution；它必须先经 Host 正常 admission 获取 identifier，再同栈补发 internal `willSelect` 语义并转发 matching `didSelect`。admission 拒绝、真实 current 不匹配、重复 committed 或已有冲突 execution 时保持 stale，不猜测提交。
2. active overscroll boundary 不启动 synthetic deceleration。顶部 `.container/.child` 与底部原生 owner 都先按既有 boundary lifecycle 完成回稳；v0.7 driver 只从 stable range 的 container/current child owner 启动，避免产生 Interaction Coordinator 不允许的 `topOverscrolling -> verticalDecelerating` 或 boundary/synthetic 双 owner。
3. 新 pan 替换旧 synthetic deceleration 或仍等待原生回稳的 boundary recovery interaction 时，必须显式标记为 replacement cancel。ViewController 仍同步取消旧 vertical state，但该 cancel 不请求 deferred drain；紧随其后的新 `beganDragging` 建立后继续保持 Host suspended，延迟 reload/layout/selection 只能在新 pan matching terminal 后排空。其他结构性 cancel 继续按既有策略请求 drain。
4. 真实 child→container 惯性 UI 必须证明 handoff 发生在手指离开后：释放前 child distance 要大于测试手指的物理位移并保留安全余量，再用短距离高速 flick 触发。若禁用 synthetic handoff，该用例必须无法同时满足 child 回顶和 Header 展开；不得只用“曾出现 child→container”而允许拖拽阶段先跨界。

## 日志

新增事件只记录状态与边界，不包含 index、velocity、geometry、业务标题或 view hierarchy：

- `interaction.state.begin`
- `interaction.state.updateBoundary`
- `interaction.state.finish`
- `interaction.state.cancel`
- `interaction.state.invalidTransition`
- `paging.selection.enqueue`
- `paging.selection.replacePending`
- `paging.selection.start`
- `paging.selection.reject`
- `paging.selection.staleTerminal`
- `paging.selection.executorReady`
- `paging.selection.structuralCancel`
- `scroll.deceleration.begin`
- `scroll.deceleration.handoff`
- `scroll.deceleration.finish`
- `scroll.deceleration.cancel`

changed/tick 热路径不逐帧记录普通日志。所有新关键日志必须通过可注入 sink 测试。

## 错误与清理

1. stale identifier、旧 adapter callback 和 target mismatch 不修改 active/pending，只记录一次诊断日志。
2. reload/teardown/deinit 同步取消 pending selection、paging surface observation、synthetic driver 和 interaction state。
3. matching active programmatic transaction 在 teardown 前仍优先等待第三方 terminal；若结构性 teardown 已通过现有 Pageboy 5.0.2 shim 完成，则由 Host 发送明确 structural cancel，不借用新 generation callback。
4. 不用 timer 伪造 Pageboy terminal，不用 `Task`、dispatch delay、toggle gesture enabled 或重复 layout 掩盖缺失回调。
5. 所有 cleanup 幂等，不重复发送 didSelect/didCancel、interaction finish/cancel 或资源释放日志。

## 文件职责规划

新增或重点修改：

- `Sources/AnchorPager/Gesture/AnchorPagerInteractionState.swift`：状态和值语义。
- `Sources/AnchorPager/Gesture/AnchorPagerInteractionCoordinator.swift`：跨域转换、优先级和延迟仲裁。
- `Sources/AnchorPager/Gesture/AnchorPagerGesturePriorityCoordinator.swift`：system/page/current child 的 public failure relation。
- `Sources/AnchorPager/Paging/AnchorPagerPagingSelectionRequest.swift`：selection identifier、source、request/transaction 值类型。
- `Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift`：Pageboy surface/pan 的可撤销内部观察。
- `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`：active/latest pending selection 与 reload 串行。
- `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`：Host request 执行、bar override、matching callback。
- `Sources/AnchorPager/Core/AnchorPagerVerticalDecelerationDriver.swift`：纯衰减计算和 display-link driver。
- `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`：velocity input、driver 消费和 interaction 事件。
- `Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift`：pan velocity 上报。
- `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：装配 Interaction Coordinator，移除过早 selection no-op，仲裁 reload/layout/size。

不把所有状态和 coordinator 合并进 ViewController 或 Adapter 大文件。

## TDD 与验收

### Selection 单元/集成测试

1. 同一调用栈连续两个 `animated: false` 不会让第二笔假接受后悬空。
2. active + latest pending，第三笔替换第二笔 pending。
3. active completion/executor-ready 不清除 newer pending。
4. 非动画 completion 可以同步 executor-ready；动画 completion 返回前不得启动 latest target。
5. Pageboy interaction hook 恢复为 `true` 后，matching executor-ready 才启动 latest target。
6. active target 完成后真实中间页提交，再直接启动 latest target。
7. active 期间请求 committed source index 能排队返回 source。
8. API、bar 使用相同 identifier/admission；Adapter bar override 不调用 Tabman 默认滚动路径。
9. interactive did/cancel、missing will recovery、duplicate/stale/out-of-order callback。
10. selection active + latest reload、reload pending + selection、teardown structural cancel。
11. Pageboy 真实 Adapter/Host 集成测试，不只使用 fake adapter 返回值。

### Interaction 测试

1. 每个状态 begin/update/finish/cancel。
2. 非法或重复 transition 幂等并记录日志。
3. selection、vertical pan、top overscroll、layout、size 的优先级矩阵。
4. latest Header layout policy 合并并在 idle 执行。
5. size preemption 后恢复 active paging 或 idle。

### Velocity 测试

1. 衰减纯计算在固定时间步下确定可重复。
2. container-to-child 与 child-to-container 剩余 velocity 同向、单调衰减。
3. 低于阈值、反向、无 child、identity 变化和新手势取消。
4. handoff 全程保持 container/child stable invariant 和唯一 offset writer。
5. 顶部三种 mode、真实 child bottom、plain page bottom 不发生 owner 交叉污染。

### UIKit/UI 测试

1. 真实连续 API request 与连续 bar 点击。
2. 横向 paging 完成/取消和 public selection。
3. 快速纵向 fling 跨完整 Header/child 边界，显示帧无停顿、反跳或双 owner。
4. 系统 leading-edge pop 不被 Pageboy 吞掉。
5. 业务横向 scroll 自动优先方案的真实 winner 可行性；若不成立，必须撤回候选关系并固定不支持边界。
6. 横向/纵向竞争、reload/layout/size 期间真实手势。
7. 业务 child scroll delegate、pan delegate、bounce 和 `isScrollEnabled` 身份/值全程不变。

### 全量门禁

每个任务完成后先运行聚焦测试和自审；版本完成后至少运行：

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=<available simulator>' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
```

同时检查 xcresult 的 error、warning、analyzer warning、skip、UIKit 运行时约束冲突和资源释放日志。

最终验收记录：生产代码 HEAD `07a3443`；Framework 426/426，结果包 `/private/tmp/AnchorPagerV07FrameworkFinal2-20260716.xcresult`；Example 60/60（16 单元 + 44 UI），结果包 `/private/tmp/AnchorPagerV07ExampleFinal2-20260716.xcresult`；generic Simulator build 结果包 `/private/tmp/AnchorPagerV07ExampleBuildFinal2-20260716.xcresult`。全部 0 fail、0 skip、0 error、0 warning、0 analyzer warning；运行时约束、gesture cycle、appearance 与资源泄漏问题关键字零命中。fresh-pass 首轮 Critical 0、Important 4、Minor 1，四项 Important 与文档 Minor 完成 RED/GREEN；追踪复审发现的 boundary recovery 原子替换 Important 同样完成 RED/GREEN，终态 Critical 0、Important 0、Minor 0。v0.7 Ready。

## 文档迁移

实施过程中同步更新：

1. `docs/task-list.md`：补齐 selection Task 0、paging surface、velocity 和真实 UI 门禁。
2. `docs/architecture.md`：记录 Host/Adapter/Interaction/Scroll/Overscroll 唯一事实源。
3. `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`：删除“GestureCoordinator 统一拥有 selection commit/cancel”的旧表述和历史 fallback host 现行职责。
4. `README.md`：只有 velocity 合成与交互状态真实完成后才移除对应 known limitation。
5. `AGENTS.md`：登记本设计和后续实施计划，并只记录真实验收状态。

## 完成标准

v0.7 只有同时满足以下条件才可标记 Ready：

1. active/latest pending selection、bar 路由和 Pageboy matching terminal 已完成。
2. interaction state 全部状态和转换已实现并测试。
3. 双向跨 owner velocity 合成已通过真实 UI 验收。
4. 系统返回、Pageboy 与纵向手势优先级已通过真实导航栈测试；业务横向 child 自动优先级明确记录为当前不支持，生产代码不保留未通过真实 UI 的关系或 guard。
5. reload/layout/size 非 idle 策略没有 generation、selection 或 offset 双 owner。
6. Public API、Tabman/Pageboy containment、业务 child delegate/bounce 所有权不变。
7. Framework、Example、generic build、日志、warning/analyzer/runtime constraint 门禁全部通过。
8. 完成任务级自审、整分支 fresh-pass 和长期文档同步。

## 2026-07-16 横向-only 页面纵向目标修订

Task 12 的 Example 第五页把只承担横向业务内容的 `UIScrollView` 显式登记为 `anchorPagerScrollView`。这使它错误进入 managed inset、snapshot、ScrollCoordinator binding 和 container simultaneous pair，横向拖动的纵向分量因而可以带动 `verticalScrollView`。根因修复不增加全局方向锁，而是关闭该页默认 lookup、提交 nil 纵向 target，并明确 `anchorPagerScrollView` 只表示纵向协调目标。详细设计与计划见 `docs/superpowers/specs/2026-07-16-horizontal-only-page-vertical-scroll-target-design.md` 和 `docs/superpowers/plans/2026-07-16-horizontal-only-page-vertical-scroll-target.md`。

修复生产代码 HEAD `984a009`。Example unit 16/16、新真实横向手势 UI 1/1、相邻 UI 3/3、Framework 426/426、Example 全量 61/61（16 单元 + 45 UI）和 generic Simulator build 全部通过；0 fail、0 skip、0 error、0 warning、0 analyzer warning，运行时问题关键字零命中。fresh-pass 终态 Critical 0、Important 0、Minor 0；v0.7 恢复 Ready。

## 2026-07-16 Compositional Layout 页面级分页修订

追加第六页后，原第五页不再位于 Pageboy 末端，真实 UI 暴露出旧用例的边界依赖：业务横向区域拖动会提交第六页。根因方案新增 `pagerViewController(_:allowsInteractiveHorizontalPagingAt:)`，默认 `true`；策略与 reload metadata 同 generation 采集，由 PagingHost 唯一 committed snapshot 管理，Adapter 只执行 Pageboy 自有 `isScrollEnabled`。Example index 4、index 5 返回 `false`，业务横向内容到边界后不向 Pageboy 接力；index 3→4 验证 enabled-to-disabled terminal，index 4↔5 通过 bar/API 切换。详细设计与计划见 `docs/superpowers/specs/2026-07-16-compositional-layout-mixed-axis-gesture-validation-design.md` 和 `docs/superpowers/plans/2026-07-16-compositional-layout-mixed-axis-gesture-validation.md`。

生产代码 HEAD `db4b9bc`。Framework 439/439，结果包 `/private/tmp/AnchorPagerCompositionalPolicyFramework-20260716.xcresult`；Example 70/70（19 单元 + 51 UI），结果包 `/private/tmp/AnchorPagerCompositionalPolicyExample-20260716.xcresult`；generic Simulator build 结果包 `/private/tmp/AnchorPagerCompositionalPolicyBuild-20260716.xcresult`。全部 0 fail、0 skip、0 error、0 warning、0 analyzer warning，运行时问题关键字零命中；fresh-pass 终态 Critical 0、Important 0、Minor 0，v0.7 继续为 Ready。
