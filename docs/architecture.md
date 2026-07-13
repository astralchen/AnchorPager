# AnchorPager 架构说明

本文档面向维护者，记录当前 v0.4 Child 生命周期、缓存与 reload 代际原子性阶段的架构边界和已固定契约。Task 1–3 实现、聚焦复审、Swift 6.2.4 完整验收及最终独立复审均已完成；v0.4 Ready，v0.5 实施中，Task 1–4 已完成，Task 5 尚未开始。

## 技术基线

- Minimum toolchain：Swift 6.2
- Language mode：Swift 6（`swiftLanguageModes: [.v6]`）
- Minimum OS：iOS 14

tools version 负责 SwiftPM/编译器最低工具链门禁，`.v6` 只选择 Swift 6 language mode；两者不能混为一谈。

2026-07-12 generation atomicity 完整验收严格串行复用 iPhone 17：resolve 1.34 秒；Framework 193 项、0 fail、0 skip，墙钟 53.81 秒；Example generic build 15.71 秒；Example 5 项单元 + 16 项 UI、0 fail、0 skip，墙钟 277.97 秒。warning 仅为 Pageboy/Tabman `PrivacyInfo.xcprivacy` unhandled resource 提示。

## 模块划分

```text
Sources/AnchorPager/
  Public/      Public API、配置、协议、UIViewController scroll 接入扩展
  Core/        内部断言和非 UI 基础设施
  Layout/      Header、bar、content frame 和 offset 策略的纯计算层
  Header/      Header UIView/UIViewController 基础承载与测量
  Children/    Page state/fallback page scroll host
  Paging/      Tabman/Pageboy internal adapter 和横向 page containment 执行层
  Logging/     AnchorPagerLogger
```

`AnchorPagerViewController` 是唯一 public 容器入口。UIKit 状态更新、data source、delegate 和内部 coordinator 均保持 MainActor 语义。非 UI 基础设施不因测试或调用便利整体绑定 MainActor。

## Core 基础设施

`AnchorPagerAssertions` 是内部断言门面，不操作 UIKit 状态，因此不绑定 MainActor。测试需要临时关闭断言时通过 `@TaskLocal` 的 `isEnabled` 覆盖当前调用上下文，避免共享可变全局状态，也避免使用 `nonisolated(unsafe)` 压制 Swift 6 language mode 并发检查。

## Public API 契约

Public API 保持领域无关，命名参考 UIKit。当前公开类型包括：

- `AnchorPagerViewController`
- `AnchorPagerViewControllerDataSource`
- `AnchorPagerViewControllerDelegate`
- `AnchorPagerHeaderContent`
- `AnchorPagerConfiguration`
- `AnchorPagerHeaderConfiguration`
- `AnchorPagerBarConfiguration`
- `AnchorPagerPagingConfiguration`
- `AnchorPagerHeaderHeightMode`
- `AnchorPagerHeaderTopBehavior`
- `AnchorPagerHeaderOffsetAdjustment`
- `AnchorPagerTopOverscrollHandlingMode`
- `AnchorPagerLayoutContext`

空页时 `selectedIndex` 保持 `0`，`effectiveSelectedIndex` 为 `nil`。`setSelectedIndex(_:animated:)` 越界时 no-op，Debug 下通过内部断言路径报告。

可见状态下的程序化切页采用确认后提交语义：`AnchorPagerViewController` 只在内部 adapter 收到 Pageboy/Tabman 的完成回调后更新 public `selectedIndex` 并通知 delegate；取消或回弹不会提前提交。若 Pageboy 当前忙碌导致 adapter 拒绝新的程序化请求，v0.1 不做请求排队，public 状态保持旧值，并写入 rejected 日志。adapter 会保留已被接受但尚未完成的上一笔请求，避免后续被拒绝的请求清掉正在进行的 transition。

## Tabman/Pageboy 边界

Tabman 和 Pageboy 只允许出现在 `Sources/AnchorPager/Paging/`。当前验证版本：

- Tabman `4.0.1`
- Pageboy `5.0.2`

`AnchorPagerPagingAdapter` 继承 `TabmanViewController`，实现 Pageboy data source 和 Tabman bar data source。adapter 初始化时将 `automaticallyAdjustsChildInsets` 设为 `false`，避免 Tabman 自动 child inset 与 AnchorPager 后续 managed inset 策略冲突。

横向 page 的实际 UIKit containment 由 Tabman/Pageboy 在 adapter 内执行。AnchorPager 不对同一个 page view controller 再次 `addChild`，避免 UIKit 双重 containment。AnchorPager 负责 page identity、selection commit/cancel、reload 清理、scroll discovery、fallback host、inset ownership 和对外状态语义；adapter 负责把 Tabman/Pageboy 回调标准化后交回 AnchorPager。

Public API source scan 测试会检查 `Sources/AnchorPager/Public/` 不包含 `Tabman` 或 `Pageboy`。

## Header 承载

`AnchorPagerHeaderViewHost` 负责 Header 内容承载：

- `.view(UIView)`：添加到 host view 内并约束到四边。
- `.viewController(UIViewController)`：使用 `addChild`、添加 view、`didMove(toParent:)`；移除时使用 `willMove(toParent: nil)`、移除 view、`removeFromParent()`。

重复安装同一个 Header view 或同一个 Header view controller 时，host 会直接 no-op，不触发 remove/re-add，也不会重复执行 UIKit containment。这是 v0.1 对动态 reload 的稳定性约束，后续 Header runtime frame 变化也必须保持该语义。

当前测量顺序为：

1. Header view controller 的 `preferredContentSize.height`
2. Header view 的 Auto Layout fitting size
3. Header view 当前 `bounds.height`
4. Header view `intrinsicContentSize.height`
5. 无有效结果时为 `0`

负数或非有限测量会触发内部断言，并在 `layout` category 记录 `header.measure.invalid` 事件，运行时降级为 `0`。结构性布局会先清除 viewport presentation transform，把 Header host 临时放到顶部遮挡下方，并使用最近一次有效纯内容高度建立中立测量几何；首次没有缓存时使用 `0`。同步 layout 后再执行 fitting，避免最终 top behavior、safe area/layout margins 或 bounce translation 被重复计入内容高度。临时几何不更新 layout context、progress、range 或状态日志缓存。

Header host 只负责 Header 内容和 containment。它可以接收内部 top offset 约束更新，但不计算 safe area、折叠进度、bar frame 或 child inset。

## LayoutEngine 与 Safe Area

`AnchorPagerLayoutEngine` 是 internal 纯计算类型，只 import `CoreGraphics`，不操作 UIKit 对象，也不绑定 MainActor。输入包括：

- 容器 bounds
- Header measured height
- `AnchorPagerHeaderHeightMode`
- `AnchorPagerHeaderTopBehavior`
- bar height
- 本地 top/bottom obstruction
- 当前 `verticalScrollView.contentOffset.y`

输出包括：

- resolved Header expanded/collapsed height
- collapse offset 和 collapse progress
- Header frame
- bar frame
- content frame
- collapsed-state fixed paging frame
- child 本地底部遮挡

`AnchorPagerViewController` 负责把 UIKit safe area 转为本地遮挡。top obstruction 取 `safeAreaLayoutGuide.layoutFrame.minY - view.bounds.minY`、`view.safeAreaInsets.top` 和 `additionalSafeAreaInsets.top` 的非负最大值；bottom obstruction 取 `view.bounds.maxY - safeAreaLayoutGuide.layoutFrame.maxY`、`view.safeAreaInsets.bottom` 和 `additionalSafeAreaInsets.bottom` 的非负最大值。这个策略覆盖 root、navigation controller、tab bar controller、toolbar 和未入 window 的 additional safe area 测试路径。

AnchorPager 自有主容器 `verticalScrollView` 的 `contentInsetAdjustmentBehavior` 固定为 `.never`，横纵 scroll indicator 均隐藏。主容器 scroll range 只表示 Header 折叠距离，不代表页面内容进度；当前 child/fallback scroll view 是唯一用户可见 indicator owner。safe area、navigation bar、tab bar 和 toolbar 遮挡已经被转换为 LayoutEngine 的本地 obstruction；如果继续使用 UIKit 自动 content inset，Header 实际 frame 会比 `AnchorPagerLayoutContext.headerFrame` 多叠一层 top inset。child scroll view 由独立 managed inset coordinator 接管，不与主容器复用同一份 inset。

主容器使用两个互不反向约束的内部层：`scrollRangeView` 约束到 `contentLayoutGuide`，高度固定为 viewport 高度加纯内容可折叠距离，只负责定义 `contentSize`；`viewportView` 约束到 `frameLayoutGuide`，只承载 Header host 和 paging adapter。Header/paging 的可见约束不会参与 scroll range 反算，当前 `contentOffset` 也不会改变 `contentSize`。负 offset 时，私有 delegate proxy 把 `max(0, -contentOffset.y)` 应用为整个 viewport 的 presentation translation，由 UIKit 自身 bounce 动画驱动恢复；transform 不参与 Auto Layout 或 range 计算。`verticalScrollView.delegate` 由内部私有 proxy 管理，调用方不得替换。

LayoutEngine 的 resolved expanded/collapsed height 始终表示纯内容高度，top obstruction 不进入 collapsible distance。`insideSafeArea` 让 Header frame 从顶部 obstruction 下方开始，高度为当前可见内容高度；`extendsUnderTopSafeArea` 让 Header frame 从 bounds 顶部开始，高度为顶部 obstruction 加当前可见内容高度。两种模式统一使用 `bounds.minY + topObstruction + visibleContentHeight` 作为 bar baseline，因此切换只改变 Header 外框是否延伸，不移动分段栏和 child 内容基线。

paging adapter 的 top 跟随当前 Header bottom，但 `pagingFrame.height` 固定为 Header 完全折叠时的最大 viewport 高度。滚动热路径只改变 adapter top，Pageboy child bounds 保持稳定；bottom obstruction 不裁剪横向区域，而由 child managed bottom inset 表达。LayoutEngine 用 `max(0, pagingFrame.maxY - safeVisibleMaxY)` 输出 child 本地底部遮挡：展开态包含 adapter 被 viewport 裁剪的尾部，完全折叠态收敛为根容器 bottom obstruction。LayoutEngine 不再输出历史容器级 managed inset target。

## 主容器可视装配

`AnchorPagerViewController.reloadData()` 会从 data source 同步 Header、标题和页面数量，并在 view loaded 后安装：

- `verticalScrollView`：主容器纵向滚动入口
- Header host：承载 `.view` 或 `.viewController` Header
- `AnchorPagerPagingHostViewController`：稳定 viewport child，在非空状态内含 `AnchorPagerPagingAdapter`，空状态不含 adapter
- `AnchorPagerPagingAdapter`：内部 Tabman/Pageboy adapter，负责分段栏、横向分页内容和 page containment 执行

主容器只持有稳定 internal host，不向 Public API 暴露 Tabman/Pageboy 类型。页面控制器由 `AnchorPagerPageStateStore` 在 adapter 按 index 请求时按需提供，不在 reload 时全量预加载。当前装配已通过 UI test 验证分段栏点击、横向滑动、public API 程序化切页、真实 scroll/fallback 页面、空/非空 reload 代际替换、滚动位置恢复和完成/取消的标准 UIKit appearance 回调。完整纵向嵌套滚动协调将在 v0.5 推进。

### Reload terminal 与稳定 Paging Host

`AnchorPagerPagingHostViewController` 是 Header 下方布局约束的长期 owner，只管理 request/selection transaction 串行、adapter containment 和事件转发，不管理业务页身份、snapshot 或 inset。每笔 reload request 都带 internal identifier；Host 同时最多有一个 active request 和一个 latest pending request，只有 matching adapter callback 才能形成 `.page(index:)`/`.empty` terminal。selection 事务活跃时，pending 由 adapter did/cancel 语义 terminal（程序化路径还要等 public completion）推进，不使用 timer 或主队列 delay 猜测第三方完成时机。terminal 通知期间的重入和旧 request 迟到 callback 不能结束新 active request。

Pageboy 5.0.2 的空 count `reloadData()` 会早退，不清空旧 `UIPageViewController` 业务页。adapter 因此在唯一 `prepareForRemoval()` 兼容点内使用 Pageboy public delete-last-page，同步验证 `pageCount == 0` 和 `currentIndex == nil`，再 post-order 清理只剩的第三方 plumbing。host 之后以标准 UIKit 顺序移除 adapter，并把 `.zero` 作为该 request 的 staged final bar inset 随 `.empty` terminal 发送。ViewController 只有实际提交 matching snapshot 才 acknowledgement；Host 仅在 ack 为 true 时更新 committed bar baseline，superseded terminal 保留旧 baseline，并推进 latest pending。该 shim 只对锁定的 Pageboy 5.0.2 验证；任何 Pageboy 升级都必须先重审 teardown、request provenance/terminal、appearance、provider activation 和 bar acknowledgement，并通过对应回归门禁。

Public `reloadData()` 在第一个 data source 回调前预留 transaction identifier，count、Header 和每个 title 回调后都验证 token。发生重入时只有最新事务能形成 staged snapshot；过期事务零写入。已有 committed visible generation 时，staged snapshot 在 matching terminal 前不发布 public metadata/Header，也不改变 visible Store 或 ownership；Host `willPerform` 才激活 provider generation。首次 view 未加载且没有 committed visible generation 时允许预发布初始 metadata并幂等激活 provider，但不会提前加载 Host/adapter view。

Store 将可跨 generation 复用的 live UIKit identity payload 与每代独立的 retention reasons、strong lease、`childDistanceFromTop` snapshot 和 ownership lease 分开。Pageboy provider 读取 `pending ?? committed`，selection、layout、inset 和现有可见查询读取 `committed ?? pending`；提供给后续版本的 committed-current 入口严格只读 committed generation，没有 committed 或 empty 时返回 nil。commit 在释放旧代最后 strong lease 前建立强 `CleanupPlan`，然后发布新 committed、释放旧 lease、强制收敛新 ownership，再用 plan 清理旧代 unique fallback/scroll，避免依赖 weak identity 或析构副作用。

v0.2 会在基础布局更新和 `reloadHeaderLayout()` 时发送 `AnchorPagerLayoutContext`。当前 context 覆盖有效 selectedIndex、Header frame、bar frame 和内容 frame，用于调试和接入验证。

`AnchorPagerLayoutContext` 中的 frame 使用 `AnchorPagerViewController.view` 的本地实际可见坐标。LayoutEngine output 和 `lastLayoutOutput` 保持 canonical geometry；负 offset 期间生成 context 时同步加入 viewport presentation translation，使实际 Header/paging frame 与 context 对齐。`scrollViewDidScroll` 复用最近一次有效纯内容测量，只更新 canonical output、presentation transform、layout context 和 collapse progress；它不重新测量 Header、不修改 scroll range，也不输出逐帧普通日志。完整 child scroll owner 与 offset 转移仍属于 v0.5。

`reloadHeaderLayout(offsetAdjustment:)` 会重新测量 Header，并按策略迁移 `verticalScrollView.contentOffset.y`：

- `.preserveVisualPosition`：尽量保持旧的可见 Header 高度。
- `.preserveCollapseProgress`：保持旧折叠进度。
- `.resetToExpanded`：回到展开位置。
- `.resetToCollapsed`：移动到当前折叠上限。

普通 `viewDidLayoutSubviews` 和 `viewSafeAreaInsetsDidChange` 布局更新不会主动迁移 content offset，避免系统布局 pass 改变用户当前滚动位置。

## v0.3 固定分页与后续滚动边界

以下固定分页与 inset ownership 已在 v0.3 实现；纵向 owner/handoff 仍属于 v0.5。

层级保持：

```text
AnchorPager viewport
├─ Header
└─ Tabman adapter（top = Header.bottom）
   ├─ Tabman bar
   └─ Pageboy child
```

Tabman adapter 的 top 继续跟随 Header bottom，但高度固定为 Header 完全折叠时的
最大 viewport 高度。Header 折叠滚动只移动 adapter；展开时 adapter 底部超出 viewport 的部分由
`viewportView` 裁剪。这样 Pageboy child bounds 不在滚动热路径反复变化。

`AnchorPagerBarConfiguration.height` 为 `CGFloat?`，默认 nil 表示使用 Tabman bar 自适应高度，
显式值由 internal adapter 约束到实际 bar。最终 bar geometry 使用 Tabman public `barInsets.top`，
而不是把配置值当作第二份事实。

child managed top 只等于 Tabman adapter 内部实际覆盖 Pageboy child 的 bar obstruction，不包含
Header 或容器顶部 safe area。managed bottom 和 indicator bottom 等于 adapter 当前底端到 pager
安全可见底端的 child 局部遮挡；container 折叠时该派生值幂等更新，但 adapter/Pageboy child bounds
保持固定。
AnchorPager 使用弱引用差量 ownership record 合成 external/managed inset，并在 ownership 结束时
只移除最后一次 managed 部分、恢复原始 `contentInsetAdjustmentBehavior`。

v0.5 的稳定状态要求 container 未完全折叠时当前 child 位于顶部，child 离开顶部时 container
完全折叠。同一 pan 的连续交接允许当前 container 与当前 child 进行受限纵向 simultaneous
recognition。AnchorPager 不替换业务 child 的 scroll delegate 或 pan gesture delegate，也不设置 container 的内建
pan delegate；child offset/contentSize 通过可撤销 observation 读取，simultaneous decision 只由自有 container
`UIScrollView` 子类放行当前 committed child pair。拖拽位移从固定 pan 起点计算 canonical total 后再分配到 container/child，不依赖两个
scroll callback 的先后顺序。完整横向、返回手势、跨 owner 惯性转移和 interaction state 仍属于 v0.7。

v0.5 尚未实现正式 overscroll mode。Header 完全展开后的额外下拉临时只保留 container 原生 bounce，
child 固定顶部，避免同时出现两个 bounce owner；v0.6 再使用同一纵向 binding 按 `.none`、`.container`、
`.child` 路由正式 owner，不重复建立 handoff。

## Child Lifecycle

横向 page containment 的执行层是 Tabman/Pageboy adapter。AnchorPager 的职责是维护 page lifecycle 策略和对外语义，而不是在主容器中重复 `addChild` 每个横向 page。`AnchorPagerPagingAdapter` 通过弱 `AnchorPagerPageProviding` 按 index 请求页面，不持有业务页面数组；`AnchorPagerPageStateStore` 以 reload generation + index 管理 weak live identity、current/transition/可选 adjacent 强保留、fallback host、scroll target 和 `childDistanceFromTop` snapshot。

Store 同时维护 committed generation 和至多一个 provider pending generation。已有可见内容时，`reloadData()` 只 staged snapshot；Host matching `willPerform` 才建立 pending provider generation。非空由 matching Pageboy callback 形成 `.page` terminal，空态由 paging host 完成真实 teardown 后形成 `.empty` terminal；ViewController ack 后才一起提交 Store、public metadata/Header、terminal index 与 bar inset。新的 reload 抢占尚未提交的 snapshot/provider 时只取消 pending generation-specific lease/snapshot，不修改旧 committed state 或 ownership。负 page count 在最新 metadata transaction 采集时断言、记录 `children.page.invalidCount` 并降级为零；同一 generation 内 data source 若把同一个控制器实例用于多个 index，后一个 index 会断言、记录日志并使用空白 fallback 页面，避免 Pageboy containment 身份冲突。

同一 generation、同一 index 的实际页面仍存活时，Store 始终复用同一实例。默认只强保留 current 和 transition source/target；`keepsAdjacentPagesLoaded` 开启后额外保留已经加载过的当前页相邻页面，不主动预取。页面退出保留窗口时，Store 保存 `childDistanceFromTop`、归还 managed inset 并释放 AnchorPager 强引用。重新创建目标页面时，container 完全折叠则恢复 snapshot，尚未完全折叠则归顶。该规则为 v0.5 的唯一纵向 owner 不变量提供稳定页面状态基础。

旧 `AnchorPagerChildViewControllerStore` 已移除。普通横向业务页面只由 Pageboy/UIKit 执行 containment 和 appearance lifecycle；AnchorPager 不因缓存 retain/release 手工转发 appearance。

`AnchorPagerPageScrollHostViewController` 为无 scroll view child 提供内部 fallback scroll host。fallback host 使用与真实 scroll page 相同的 managed inset target，并把普通 child 的最小高度约束为扣除 managed top/bottom 后的可用 viewport，避免 inset 额外扩大内容高度。只有 fallback host 对其内部业务 child 执行 AnchorPager 自有 containment；普通页面的 appearance 完全由 Pageboy/UIKit 驱动。

## Scroll Discovery

`UIViewController+AnchorPager` 提供：

- `anchorPagerScrollView`
- `anchorPagerUsesDefaultScrollViewLookup`
- `anchorPagerDefaultScrollView`

默认查找启用。显式设置的 `anchorPagerScrollView` 优先。未显式设置时，从 `view` 开始按确定性深度优先顺序查找 `UIScrollView`。

默认查找会忽略：

- `isHidden == true`
- `alpha <= 0.01`
- `isUserInteractionEnabled == false`

查找不会跨 child view controller 边界：当前 view controller 的直接 child view controller 根 view 会作为边界被跳过。

v0.4 由 PageStateStore 在页面第一次按需请求时加载该 child view，并且每个存活实例只解析一次 scroll target。若两个页面声明同一 scroll view，后出现的页面尝试非冲突默认目标，否则降级到 fallback host，并记录 `inset.targetCollision`。scroll target claim 的生命周期与 generation/page state 一致，页面淘汰或 reload 清理时同步归还。

## Inset Ownership

`AnchorPagerManagedInsetCoordinator` 以弱引用 record 管理每个 active page scroll view。managed content top 与 indicator top 等于 adapter 通过 public `barInsets.top` 回报的实际 bar obstruction，不包含 Header 或顶部 safe area；managed content bottom 和 indicator bottom 等于 LayoutEngine 输出的 child 本地底部遮挡。

每次更新先用“当前总 inset - 上次 managed inset”分离 external，再叠加新 managed target，并按 `contentOffset.y + contentInset.top` 保存 distance-from-top。接管期间 content adjustment behavior 为 `.never`，同时关闭 UIKit 的自动 scroll indicator inset 调整，确保 top/bottom 只有一个 owner；页面退出 Store 保留窗口、reload 替换页面或控制器释放时，coordinator 只减去最后一次 managed 部分并恢复两项原始自动调整状态。相同 target 和 active scroll 集合不会重复写入；container 折叠热路径只更新 current/transition/已加载 adjacent 构成的有界集合，只在 bottom 实际变化时写入并抑制逐帧 inset/children 日志。Swift 6 language mode 下 controller 的普通 `deinit` 通过 `MainActor.assumeIsolated` 同步归还，具体约束见 v0.3 设计文档。

## 日志策略

日志门面为 `AnchorPagerLogger`，底层使用 `os.Logger`，subsystem 为 `com.anchorpager.AnchorPager`。`AnchorPagerLogger.log` 不绑定 MainActor，内部非 UIKit 路径可以从非主线程记录诊断事件。测试用 sink 单独由 MainActor 隔离：主线程日志同步投递 sink，非主线程日志会把 sink 投递回 MainActor。

category 覆盖：

`lifecycle`、`layout`、`header`、`paging`、`children`、`scroll`、`inset`、`overscroll`、`gesture`、`accessibility`、`resource`

日志测试通过内部可注入 sink 验证，不依赖人工查看控制台。日志消息只使用稳定事件名，不记录业务数据、用户内容或完整 view 层级。

v0.3 布局与 inset 事件：

- `layout.headerHeightResolved`
- `layout.headerFrameChanged`
- `layout.barFrameChanged`
- `layout.safeAreaChanged`
- `layout.boundsChanged`
- `inset.ownership.begin`
- `inset.ownership.update`
- `inset.ownership.end`
- `inset.ownership.skip`
- `inset.targetCollision`

这些事件只在对应状态变化时记录，不在无变化的 layout pass、`reloadHeaderLayout` 或滚动热路径中重复输出。事件名不携带几何数值，避免泄漏用户界面内容或完整层级信息。

v0.4 页面状态事件包括 `children.page.load/reuse/recreate`、`children.page.retain/release`、`children.page.snapshot.save/restore/reset`、`children.page.generation.begin/commit/cancel`、`children.page.duplicateController` 和异常 data source/count 降级。缓存窗口或 snapshot 状态变化才会记录；单纯 managed inset 热路径不输出 children 日志。

## Known Limitations

Xcode 26.3 / Swift 6.2.4 的 x86_64 iPhone 17 Simulator 中，控制器改用 `isolated deinit` 会在 lifecycle
deinit 后稳定触发 allocator `pointer being freed was not allocated` 崩溃；恢复普通
`deinit + MainActor.assumeIsolated` 后同一资源析构测试通过。当前析构契约必须同步归还 Store、fallback 与 managed
inset ownership，不使用异步 Task、delay 或并发 unsafe 标记规避。后续 Xcode/Swift 升级只有在同一资源析构测试复验通过后，
才可重新评估 `isolated deinit`。

当前 v0.4 已完成固定分页 viewport、child inset ownership、按需 page state/cache window、offset snapshot、reload generation、稳定 paging host、page/empty terminal 和 Pageboy/UIKit appearance lifecycle 边界，仍不包含后续版本能力：

- 纵向嵌套滚动协调
- 顶部 overscroll owner
- 手势状态机
- 状态栏点击顶滚 owner
- 尺寸变化恢复
- `AnchorPagerConfiguration.topOverscrollHandlingMode` 等后续版本配置项只保留 public skeleton 和默认值；`paging.keepsAdjacentPagesLoaded` 已在 v0.4 生效
- v0.4 Task 1–3 已完成 Host request/terminal 与 bar acknowledgement、Store payload/generation lease/CleanupPlan、ViewController staged public/provider/bar terminal 和 pre-load 路径；完整验收为框架 193 项、Example 5 项单元与 16 项 UI 测试全部通过，最终独立复审已清零 Critical/Important/Minor，v0.4 Ready 并开放 v0.5 设计与计划入口
- v0.5 实施中；专用设计已根据 UIKit 实测与 JXPagingView 参考验证修订为 child delegate 保留、container scroll view 子类 simultaneous recognition、canonical distance、临时 container bounce 和真实 pan UI 门禁。ScrollCoordinator 只能只读 Store committed current child/scroll target（empty 为 nil），在 reload/selection complete/cancel terminal 后重新绑定，不缓存 Host/adapter/provider、不读取 provider pending、不复制 page identity/cache/generation
- v0.6 overscroll 与 v0.8 scrollsToTop 只消费 committed current/empty owner；v0.7 只扩展 Host 现有单一 request/selection transaction；v0.9 accessibility/RTL 不读取 provider pending
