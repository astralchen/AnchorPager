# 纵向边界 Bounce 与顶部 Owner 路由设计

**日期：** 2026-07-13

**状态：** Tasks 1–6 已实现；初次独立复审的 3 个 Important 与再次整分支复审剩余的 1 个 Important、1 个 Minor 均已修复并完成新鲜验收；修复后的再次独立复审待执行，不标记 v0.5/v0.6 Ready

**适用范围：** v0.5 可见 bounce 修复、v0.6 `topOverscrollHandlingMode` 正式启用、无滚动页双边界回弹、真实 child 顶部/底部回弹所有权。

## 背景与根因

v0.5 已建立 container/current child 的连续纵向 handoff，并删除无滚动页 synthetic scroll wrapper。但真实模拟器验收发现：`verticalScrollView.alwaysBounceVertical` 虽为 `true`，可见回弹仍会被协调层抵消。

根因不是 UIKit 没有产生 bounce，而是稳定位置协调与边界 presentation 的职责没有分开：

1. `AnchorPagerScrollPositionResolver` 把 canonical total 强制 clamp 到稳定区间。
2. `AnchorPagerScrollCoordinator.handlePan(.changed)` 在同一手势中把原生越界 offset 立即写回稳定位置。
3. `containerDidScroll()` 与 `updateGeometry()` 会再次触发 settle，底部越界尤其会被同步夹回 collapsed offset。
4. `viewportView` 只实现顶部负 offset 的正向 translation，没有实现 container 底部越界的对称负向 translation。
5. 现有 Example UI test 只记录“是否瞬间观察到负 offset”，没有证明 Header/bar/page 曾产生肉眼可见位移，因此测试通过不能证明 bounce 视觉成立。

同时，v0.5 临时把所有顶部下拉交给 container，尚未读取已经公开的 `AnchorPagerTopOverscrollHandlingMode`。用户现已确认：真实 scroll child 的顶部 owner 必须可由外部选择，底部 owner 则由页面是否存在真实 scroll target 决定。

## 目标

1. 稳定区间继续保持“container 先折叠、child 后滚动；child 先归顶、container 后展开”的唯一位置不变量。
2. 越过顶部或底部边界后，停止稳定位置 clamp，让选定的原生 `UIScrollView` 处理 rubber-band、减速和回弹。
3. 无滚动页不创建替代 scroll view；其可见顶部/底部 bounce 都只能由外层 container 表达。
4. 正式启用现有 `.none`、`.container`、`.child` 顶部模式，不新增 public 类型。
5. 默认顶部模式改为 `.container`，为普通接入提供稳定一致的整体回弹。
6. 真实 scroll child 的底部 bounce 始终由 child 表达，Header 和分段栏保持吸顶。
7. AnchorPager 不设置业务 child 的 `UIScrollView.delegate` 或 pan delegate，不切换 `isScrollEnabled`，也不修改业务 child 的 `bounces` 或 `alwaysBounceVertical`。
8. 用真实可见位移而非瞬时 offset flag 验收 bounce。

## 非目标

1. 不提供下拉刷新控件、刷新任务生命周期或业务事件回调。
2. 不实现 v0.7 完整 interaction state、横向返回手势优先级或跨 owner velocity 合成。
3. 不改变 Pageboy containment、page identity、reload generation、managed inset 或 snapshot ownership。
4. 不向 public API 暴露 internal owner、boundary phase、handoff 或 coordinator 类型。
5. 不手工实现弹簧动画或自定义 rubber-band 曲线。

## 方案比较

### 采用：稳定区间协调 + 原生边界 pass-through + 独立顶部路由

ScrollCoordinator 只分配稳定区间内的 canonical distance。进入选定 owner 的边界后，不再把越界 offset 写回 clamp 值；UIKit 原生 scroll view 继续产生 rubber-band 和回弹。顶部 mode 与 owner 进入/退出由独立 `AnchorPagerOverscrollCoordinator` 决定，ScrollCoordinator 仍是 guarded offset 的唯一执行入口。

该方案保留 UIKit 原生物理效果，且不会把 v0.6 mode 判断、日志和 owner 生命周期永久塞进 v0.5 的位置分配器。

### 不采用：扩展 resolver 并手工写弹性距离

把 `rawTotal` 映射为自定义 top/bottom overflow 可以产生确定性位移，但需要复制 UIKit rubber-band 阻尼、速度和回弹曲线，还会与原生 deceleration 形成第二套物理状态。

### 不采用：只切换 `bounces` 或恢复 synthetic scroll wrapper

`bounces` 是双向布尔值，无法单独表达“顶部禁用、底部允许”；只切换该属性不能处理同一手势跨稳定边界的剩余 delta。恢复 wrapper 则会重新引入虚假 owner、错误尺寸、inset、snapshot 和双重 containment 风险。

## Public API 契约

继续使用已有类型：

```swift
public enum AnchorPagerTopOverscrollHandlingMode: Sendable, Equatable {
    case none
    case container
    case child
}
```

`AnchorPagerConfiguration` 的默认值从 `.none` 改为 `.container`。这是默认用户可见行为调整，但不新增或删除 public symbol。

运行时修改 `configuration.topOverscrollHandlingMode` 必须同步取消当前 top owner，再按当前 committed page/scroll target 建立新策略；不得等待下一次 reload 或切页。取消只清理 AnchorPager 自己的 owner/边界状态和 container presentation，不写业务 child 的回弹属性。

## 所有权矩阵

| 当前页 | 顶部模式 | Header 完全展开后的顶部 bounce | 最底部继续上推 |
| --- | --- | --- | --- |
| 真实 scroll child | `.none` | 无 owner，不产生顶部可见 bounce | child 按自身配置处理原生 bottom bounce |
| 真实 scroll child | `.container` | container，整个 Header/bar/page viewport 下移 | child 按自身配置处理原生 bottom bounce |
| 真实 scroll child | `.child` | child 按自身配置处理原生 top bounce，Header/bar 保持展开位置 | child 按自身配置处理原生 bottom bounce |
| 无滚动页 | `.none` | 无 owner，不产生顶部 bounce | container 原生 bottom bounce |
| 无滚动页 | `.container` | container 原生 top bounce | container 原生 bottom bounce |
| 无滚动页 | `.child` | child owner 不可用，不静默切换 container，不产生顶部 bounce | container 原生 bottom bounce |

`.child` 遇到 nil scroll target 时记录一次 owner unavailable 状态，不创建替代 scroll view。默认 `.container` 保证普通无滚动页具备用户已确认的双边界回弹；显式 `.child` 则保持 case 语义严格，不做隐式 fallback。

`.child` 只改变边界路由，不承诺替业务 scroll view 开启 UIKit 回弹能力。如果业务 child 设置了 `bounces = false`，或短内容没有设置 `alwaysBounceVertical = true`，AnchorPager 必须尊重该配置，此时 child owner 可以成立但不会产生原生可见 bounce。真实 child 的底部同理。

## JXPagingView 手势处理验证

本设计在用户确认前对照检查了 JXPagingView 当前 `master` 源码（提交 `8aa5663720ebfab0c4df41cfca04b113f832c5b2`），结论如下：

1. 普通 `JXPagingView` 在 Header 未折叠时把列表 offset 重置到顶部，并让主容器承担顶部下拉；Header 折叠后固定主容器并交给列表滚动。这验证了“稳定区间由 offset gate 决定 owner”。
2. `JXPagingListRefreshView` 关闭主容器 bounce，Header 展开后不再重置列表的负 offset，让业务列表自行处理下拉刷新。这验证了 `.container`/`.child` 应是边界路由差异，而不是第二套 handoff。
3. 主容器与列表 pan 默认允许 simultaneous recognition；列表通过自身 `scrollViewDidScroll` callback 把变化通知框架，JXPagingView 不替换业务列表 delegate。
4. JXPagingView 核心不临时修改业务列表的 `bounces` 或 `alwaysBounceVertical`；短内容回弹能力由业务列表或刷新组件配置。
5. JXPagingView 要求每个列表提供 `listScrollView()`，没有覆盖 nil scroll target。AnchorPager 的 plain page direct containment 与 container 双边界 bounce 仍是独立职责。

参考源码：

- [JXPagingView 稳定区间 offset gate](https://github.com/pujiaxin33/JXPagingView/blob/master/Sources/JXPagingView/JXPagingView.swift#L203-L238)
- [JXPagingListRefreshView 顶部 child owner](https://github.com/pujiaxin33/JXPagingView/blob/master/Sources/JXPagingView/JXPagingListRefreshView.swift#L14-L86)
- [JXPagingMainTableView simultaneous recognition](https://github.com/pujiaxin33/JXPagingView/blob/master/Sources/JXPagingView/JXPagingMainTableView.swift#L16-L25)
- [JXPagingViewListViewDelegate callback 契约](https://github.com/pujiaxin33/JXPagingView/blob/master/Sources/JXPagingView/JXPagingListContainerView.swift#L19-L36)

AnchorPager 采用其“simultaneous recognition + 稳定边界 offset gate + 原生 owner”原则，但不复制下列实现：不要求业务方转发 callback，而继续使用不占用 delegate 的内部 observation；不切换横向 Pageboy scroll 或业务 child 的 `isScrollEnabled`；不要求 plain page 伪造 `UIScrollView`。

## 组件与职责

### AnchorPagerOverscrollCoordinator

新增 MainActor internal 类型，位于 `Sources/AnchorPager/Overscroll/`，只负责：

- 消费当前 `topOverscrollHandlingMode`；
- 消费 Store committed current page 与 optional scroll target；
- 根据 Header 是否完全展开选择 top owner；
- 管理 top owner begin/update/finish/cancel 与 unavailable；
- 输出 container/child 顶部 pass-through 策略；
- 输出非 owner 的稳定边界 clamp 策略；
- 记录 overscroll 状态变化日志。

它不持有 PagingHost、Adapter、provider、generation 或页面数组，不直接写 managed inset、page snapshot 或 UIKit containment。

### AnchorPagerScrollCoordinator

继续负责稳定区间 handoff、pan translation、canonical total 与 guarded offset 写入。新增边界职责仅限：

1. 在 stable range 内继续使用 resolver。
2. 当 OverscrollCoordinator 指定的顶部 owner已经进入原生越界时，不再写回顶部 clamp。
3. 当真实 child 到达底部并继续上推时，不再把 child offset 写回 maximum distance。
4. 无滚动页没有 child binding，container 在顶部/底部有效 owner 边界直接走原生 pass-through。
5. owner 回弹重新进入稳定区间后，再执行一次幂等 settle。

ScrollCoordinator 不复制 mode 状态机，不输出顶部业务语义日志。

### AnchorPagerChildScrollBinding

Binding 只保留不占用 delegate 的 `contentOffset`/`contentSize` observation 和 pan target，用于把业务 child 的原生变化通知 ScrollCoordinator。它不保存、修改或恢复 `bounces`、`alwaysBounceVertical`、scroll delegate、pan delegate、`isScrollEnabled`、inset 或 scroll indicator。

顶部非 owner 约束只通过 ScrollCoordinator 的 guarded stable-boundary write 完成：

- `.container`：container 允许顶部原生越界，child 观察到越界后归到其 top stable position。
- `.none`：container 和 child 都归到 top stable position。
- `.child`：container 归到 expanded stable position，child 越界不被写回。
- 真实 child bottom：container 归到 collapsed stable position，child 越界不被写回。

由于 AnchorPager 不占用业务 delegate，也不修改业务 bounce 属性，不能承诺业务 delegate 永远看不到 UIKit 在同一 run loop 内产生的瞬时非 owner 越界回调；契约是非 owner 不形成持续可见 presentation、稳定位置最终正确且只有选定 owner 保留原生越界。测试不得重新以“业务 delegate 从未收到负 offset”作为 owner 正确性的必要条件。

### AnchorPagerViewController

负责装配 mode、committed binding、collapsible distance 和 presentation translation。结构性配置变化通过现有 `configuration.didSet` 同步 reconcile。

## 坐标与可见 Presentation

稳定位置仍定义为：

```text
containerStable = clamp(containerOffset, 0...collapsibleDistance)
childStable = clamp(childDistanceFromTop, 0...childMaximumDistance)
```

container owner 的可见 overflow：

```text
containerTopOverflow = max(0, -containerOffset)
containerBottomOverflow = max(0, containerOffset - collapsibleDistance)
viewportTranslationY = containerTopOverflow - containerBottomOverflow
```

规则：

1. container 顶部 owner 时整个 Header/bar/page viewport 下移。
2. 无滚动页 container 底部 owner 时整个 viewport 上移。
3. child 顶部或底部 owner 时 viewport transform 保持 canonical，只有 child 内容原生回弹。
4. LayoutEngine output、scroll range 和 snapshot 始终只保存 canonical 状态，overflow 不参与 contentSize 或折叠进度。
5. `AnchorPagerLayoutContext` 继续表示实际可见坐标，container presentation bounce 时加入相同 translation。

## 手势与状态流

1. pan 开始时捕获 stable canonical total 和当前有效 top mode。
2. stable range 内按原有 container/child 顺序分配 delta。
3. 向下到达 expanded boundary 后，按 mode 进入 `.none`、container 或 child 顶部策略。
4. 向上到达最大稳定距离后，真实 scroll 页进入 child bottom pass-through；无滚动页进入 container bottom pass-through。
5. active owner 的原生 offset 在边界外时，container delegate、child observation、pan target 和结构性 geometry 更新都不得同步 clamp。
6. UIKit 回弹重新进入 stable range 后 finish owner并幂等 settle。
7. selection/reload/layout reload/尺寸变化/模式切换期间取消 active owner，清除 AnchorPager 自有边界/presentation 状态，再按 committed state 重建；不读取 pending provider、不修改业务 scroll 配置。

边界进入使用统一 presentation epsilon `0.5 pt`：越界距离大于 epsilon 才发布 begin；回到 stable range 内且误差不大于 epsilon 时 finish。collapsible distance 或 child maximum distance 为 0 的退化场景按 pan 方向判定：向下只进入 top policy，向上只进入 bottom policy，不能同时建立两个 owner。若零稳定区间的连续 pan callback 从 top overflow 直接跳到 bottom overflow，或从 bottom 直接跳到 top，且旧 active owner 从未形成可见 overflow，纯 Overscroll policy 必须先同步 finish 旧 owner 再路由新 boundary；同 boundary 保持，已呈现 owner 请求不同 boundary 时仍保持到真实 overflow 回稳。

## 日志

新增或正式启用以下稳定事件：

```text
overscroll.mode.changed
overscroll.owner.container.begin
overscroll.owner.child.begin
overscroll.owner.finish
overscroll.owner.cancel
overscroll.owner.unavailable
overscroll.boundary.top
overscroll.boundary.bottom
```

只在 mode、owner 或 boundary phase 变化时记录；pan changed、offset KVO 和 presentation transform 热路径不得逐帧输出普通日志。日志不包含 controller 类型、页面标题、offset 数值或 view hierarchy。

## 测试策略

### 纯策略与协调测试

1. 六种“页面类型 × 顶部 mode”矩阵得到唯一 top owner。
2. `.child` + nil scroll target 返回 unavailable，不 fallback、不创建 scroll。
3. stable range 行为与现有 resolver 完全一致。
4. container/child 顶部或底部 native pass-through 时不执行 clamp write。
5. owner 回到 stable range 后只 settle 一次。
6. 模式切换、切页、reload、empty 和 invalidate 清除 active owner，但业务 `bounces` 与 `alwaysBounceVertical` 始终保持调用方原值。
7. `.child` 顶部与真实 child bottom 均尊重 `bounces == false`；短内容是否 bounce 由业务 `alwaysBounceVertical` 决定。
8. `.container`/`.none` 允许 UIKit 先产生瞬时 child 越界回调，但非 owner 必须通过 guarded write 在同一协调周期回到 stable boundary，不形成持续可见双 owner。
9. zero collapsible/zero child maximum 场景按方向只建立一个 owner。

### UIKit 几何测试

1. container 顶部负 offset 使 Header/bar/content frame 与 layout context 同步下移。
2. 无滚动页 container 底部 overflow 使三者同步上移，contentSize/range 不变。
3. child top/bottom bounce 不改变 Header/bar canonical frame。
4. 回弹结束后 transform、layout context、collapse progress 和 root physical-bottom 几何恢复。
5. framework 源码扫描确认没有业务 child `UIScrollView.delegate` 或 pan delegate 赋值。

### Example 真实手势 UI 测试

Example 为顶部 mode 提供 `.none/.container/.child` 切换入口，并扩展测试探针记录实际 `AnchorPagerLayoutContext` presentation 位移和 child 可见 offset 区间，而不是只记录“曾出现负 offset”。

真实 coordinate drag 必须覆盖：

1. 无滚动页 `.container` 顶部下拉可见下移并恢复。
2. 无滚动页折叠后继续上推可见上移并恢复。
3. 真实 scroll 页 `.container` 顶部只形成 viewport 可见 presentation，child 不形成持续可见顶部 presentation。
4. 真实 scroll 页 `.child` 顶部只移动 child 内容，Header/bar 不动。
5. `.none` 顶部不产生 container 或 child presentation 位移。
6. 真实 scroll 页到底后由 child bottom bounce，Header/bar 保持吸顶。
7. 模式切换、横向切页和 reload 期间 active bounce 被取消且无跳动。

XCUITest 若无法稳定读取手指按下中的 frame，Example target 必须通过同进程 layout delegate/offset observation 保存本次手势最大 presentation distance，并在回弹后同时报告 stable zero；不得以单一 boolean offset flag 代替视觉证据。

## 实施顺序与版本门禁

详细实施步骤见 `docs/superpowers/plans/2026-07-13-boundary-bounce-ownership.md`。

本设计跨越 v0.5 修复与 v0.6 顶部 mode，实施必须保持顺序：

1. 先提取通用 boundary pass-through 与对称 container presentation，修复无滚动页和现有默认 container 的可见 bounce；回归通过后才能完成 v0.5 Task 7 最终复审。
2. 再新增 OverscrollCoordinator，启用 `.none/.container/.child` 和 owner 日志；不得把 mode 分支临时堆进 ScrollCoordinator。
3. v0.6 的 mode 矩阵、owner 互斥、真实 UI 与完整验收通过后，才标记 v0.6 Ready。

两个阶段可以属于同一实施计划，但必须有独立 RED/GREEN、提交和自审记录；不得先勾选 v0.6 再补 v0.5 验收。

## 影响范围

1. **Public API：** 类型不变；默认 mode 从 `.none` 调整为 `.container`，正式启用运行时语义。
2. **内部分层：** 新增 OverscrollCoordinator；ScrollCoordinator 保留唯一 offset 写入职责；Binding 只负责只读 observation/pan target。
3. **Containment/lifecycle：** Pageboy 唯一 page containment 不变；只新增同步 owner cancel/自有 presentation 清理路径。
4. **Scroll discovery：** 只消费 committed optional scroll target；nil 与 empty 必须区分。
5. **Inset ownership：** 不修改 managed inset 计算或写入 owner。
6. **Paging/reload：** matching terminal 后 rebind；pending generation 不参与 owner。
7. **Gesture：** 不设置 container/child pan delegate，不切换 `isScrollEnabled`。
8. **日志：** 增加 overscroll 状态事件，无热路径数值日志。
9. **示例/测试：** 增加 mode UI、双边界真实 drag 和最大可见 presentation 探针。
10. **文档：** 同步 README、requirements、architecture、task-list、v0.5/v0.6 规格与实施记录。

## 架构停机条件

出现以下任一情况必须停止实现并修订设计：

1. 需要设置业务 child `UIScrollView.delegate` 或任一内建 pan delegate。
2. 需要修改业务 child 的 `bounces`、`alwaysBounceVertical`、`isScrollEnabled`，或恢复 synthetic scroll wrapper、修改 Pageboy child containment、缩短 plain root viewport。
3. OverscrollCoordinator 与 ScrollCoordinator 同时成为同一 offset 的独立写入 owner。
4. presentation overflow 进入 LayoutEngine canonical output、contentSize、managed inset 或 snapshot。
5. `.none/.container/.child` 需要读取 pending provider 或猜测未提交页面。
6. `.container`/`.none` 必须依赖修改业务 bounce 属性才能避免持续可见双 owner。
7. 连续三次最小实现尝试仍在不同共享状态产生新问题。

## 自审结论

1. 已明确稳定位置协调、顶部 owner 路由、原生边界物理和 presentation transform 四层职责，没有形成双 offset writer。
2. 所有页面类型、顶部模式和底部 owner 均有唯一结果；`.child` + nil 的不可用语义明确。
3. child delegate/pan delegate 禁止项、Pageboy containment、Store committed/pending、managed inset 和 snapshot 边界均保持不变。
4. 默认行为、运行时配置、业务 bounce 属性保留、日志和 UI 视觉证据均已固定，没有 TODO、TBD 或未选方案。
5. 实施顺序先完成 v0.5 修复/验收，再正式提交 v0.6 mode，符合版本门禁。

## 实施者验收记录（2026-07-13）

- 实现提交链：`cff0e55`、`8805892`、`27390b4`、`f9fd570`、`687733a`、`c20e259`、`344317d`、`10f1799`、`a4f7c3f`、`47abcd6`。
- Apple Swift 6.3.3；`swift package resolve` 提升缓存权限后 exit 0。
- Framework xcresult：264 项通过，0 fail、0 skip、0 warning。
- Example xcresult：36 项通过，其中 9 项单元测试、27 项 UI 测试，0 fail、0 skip、0 warning。
- Example generic iOS Simulator build：成功，0 error、0 warning、0 analyzer warning。
- 实现者十项自审未发现阻塞性代码缺陷；该初始验收随后进入独立复审并发现下述 3 个 Important。本规格以修复记录后的“再次独立复审待执行”为最新门禁，不宣告 Ready。

## 初次独立复审修复记录（2026-07-13）

初次独立复审发现 3 个 Important，修复提交为 `f81ca1e`：

1. active owner 已创建但因业务 `bounces = false` 或短内容未启用 `alwaysBounceVertical` 而从未产生实际 overflow 时，同一 pan 反向进入 stable range 会同步结束该未呈现 owner，并立即应用 resolver；已呈现 owner 仍等待实际 overflow 回稳。
2. child contentOffset KVO 只有在 container expanded epsilon 内才允许路由 child top；Header 部分折叠时三种顶部 mode 均保留 canonical container、把 child 钉回顶部且不创建 owner，结果不依赖 container/child 回调顺序。container 自身负 overflow 仍按 mode 路由。
3. Example 的 child delegate 不再直接累计可见最大 offset，只标记待采样；`CADisplayLink` 在显示帧读取实际 presentation，随 page appearance 启停并在析构同步失效。`.none` UI 直接断言 `childTopMax < 0.5`，不放宽阈值、不使用 sleep、框架异步复位或 internal owner。

随后再次整分支复审发现零稳定区间可以从一侧 overflow 直接跳到相反侧、不会经过 stable callback；旧 `begin` 会无条件返回旧 active owner。`5b80893` 将“不同 boundary 且旧 owner 未呈现时同步 finish 并继续新 route”收口在纯 Overscroll policy，同 boundary 和已呈现 owner 语义保持不变；architecture 同步补齐 top/bottom 对称公式与当前 v0.5/v0.7 职责。

最新新鲜验收：Apple Swift 6.3.3；Framework 276 项、Example 37 项（10 单元 + 27 UI），0 fail、0 skip；generic iOS Simulator build 成功；三份 xcresult 均为 0 error、0 warning、0 analyzer warning。修复后的再次独立复审待执行；在其确认 Critical/Important 清零前，本规格不宣告 Ready。
