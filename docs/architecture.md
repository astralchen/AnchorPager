# AnchorPager 架构说明

本文档面向维护者，记录当前 page generation、固定分页 viewport、纵向 handoff、边界 bounce 与顶部 owner 路由的架构边界。2026-07-14 plain bottom 页面/chrome 分层、Header identity cache、正式中立测量、真实内容附着前 bootstrap seed，以及主容器真实 top inset/固定高度 Header presentation 均已完成实现、最终全量验收和 fresh-pass；v0.5 Task 7 与 v0.6 当前为 Ready。

## Container Top Inset 与固定高度 Header

最终设计与验收记录见 `docs/superpowers/specs/2026-07-14-container-top-inset-fixed-header-presentation-design.md`。旧的“container top inset 恒为零、raw 稳定区间固定为 `0...collapsibleDistance`、折叠热路径缩小 Header host”契约已被取代，不得在后续版本恢复。

当前架构保留 `contentInsetAdjustmentBehavior = .never`，但由 `AnchorPagerHeaderTopBehavior` 独立拥有主容器 top inset：inside 等于本地顶部安全区遮挡，extends 为零。所有纵向协调统一使用 `logicalOffset = rawOffset + containerTopInset`；固定 viewport 内的 canonical content presentation surface 让 HeaderHost 保持完整高度，并让 Header 与 PagingHost 正常上移。container top 移动共享 viewport，plain bottom 只移动 Pageboy 页面 surface，真实 child bounce 仍由业务 child 表达。

Example Header 的内部布局不属于框架 presentation owner。真实 container top 回弹期间，框架继续整体移动共享 viewport；Example 标题栈使用 `top >= safeArea.top + 20` 与 `bottom == safeArea.bottom - 20`，让动态顶部 safe area 只作为安全下限、底部 guide 作为稳定局部位置锚点，避免 safe-area top 变化抵消 Header 的可见位移。该约束不改变通用 Header API、高度测量或接入方对自身 Header 内容布局的所有权。

## 技术基线

- Minimum toolchain：Swift 6.2
- Language mode：Swift 6（`swiftLanguageModes: [.v6]`）
- Minimum OS：iOS 14

tools version 负责 SwiftPM/编译器最低工具链门禁，`.v6` 只选择 Swift 6 language mode；两者不能混为一谈。

2026-07-15 当前验收使用 Apple Swift 6.3.3、Xcode 26.6、iPhone 17 Pro / iOS 26.5：`swift package resolve` 通过；Example Header 专项生产代码 HEAD `1f7e3f4` 对应 Framework 322/322，Example 41/41（11 单元 + 30 UI），全部 0 fail、0 skip；generic Simulator build 成功。三份最终结果均为 0 error、0 warning、0 analyzer warning，UIKit `LayoutConstraints` 查询无冲突。

## 模块划分

```text
Sources/AnchorPager/
  Public/      Public API、配置、协议、UIViewController scroll 接入扩展
  Core/        纵向位置解析、滚动协调、主容器 delegate 与内部断言
  Layout/      Header、bar、content frame 和 offset 策略的纯计算层
  Header/      Header UIView/UIViewController 基础承载与测量
  Children/    Page state、scroll identity 与 retention ownership
  Paging/      Tabman/Pageboy internal adapter 和横向 page containment 执行层
  Overscroll/  顶部/底部 boundary owner policy 与生命周期
  Gesture/     跨纵向、分页、layout 和尺寸事务的 interaction state
  Logging/     AnchorPagerLogger
```

`AnchorPagerViewController` 是唯一 public 容器入口。UIKit 状态更新、data source、delegate 和 UI coordinator 均保持 MainActor 语义。日志、断言和纯位置计算不因测试或调用便利整体绑定 MainActor。

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

`AnchorPagerHeaderConfiguration` 的默认 `topBehavior` 为 `.extendsUnderTopSafeArea`。该默认只由 Header 配置初始化器定义；`AnchorPagerHeaderConfiguration.default`、`AnchorPagerConfiguration.default`、Pager 无参数初始化和 Example 均沿同一构造链继承，不保存第二份默认事实。显式 `.insideSafeArea` 仍是完整支持的运行时模式。

该默认迁移的生产代码 HEAD 为 `3bdcfb6`。2026-07-15 全量验收为 Framework 322/322、Example 41/41（11 单元 + 30 UI）及 generic Simulator build 全部通过；静态扫描确认没有新增几何/owner 分支、第三方 Public 泄漏或业务 child delegate/pan/bounce 写入，fresh-pass `97e8fc2...f4d9f41` 为 Critical 0、Important 0、Minor 0。

可见状态下的程序化切页采用确认后提交语义：`AnchorPagerViewController` 只在内部 adapter 收到 Pageboy/Tabman 的真实 semantic callback 后更新 public `selectedIndex` 并通知 delegate；取消或回弹不会提前提交。v0.7 Task 3 已由 Host 独占一笔 active transaction 与一笔 latest pending explicit request，API、bar 与 interactive source 共用 Host 单调 identifier。Adapter 的 will/did/cancel/completion/ready 回调必须匹配 adapter identity、identifier 和 target；真实中间 did-select 立即提交 Store/public selection，但 explicit active 仍等 semantic、completion 与 executor-ready 全部到达后才释放并直达 latest target。Adapter 只保存一笔第三方 execution，不能成为第二套 public selection 状态。

## Tabman/Pageboy 边界

Tabman 和 Pageboy 只允许出现在 `Sources/AnchorPager/Paging/`。当前验证版本：

- Tabman `4.0.1`
- Pageboy `5.0.2`

`AnchorPagerPagingAdapter` 继承 `TabmanViewController`，实现 Pageboy data source 和 Tabman bar data source。adapter 初始化时将 `automaticallyAdjustsChildInsets` 设为 `false`，避免 Tabman 自动 child inset 与 AnchorPager 后续 managed inset 策略冲突。

横向 page 的实际 UIKit containment 由 Tabman/Pageboy 在 adapter 内执行。AnchorPager 不对同一个 page view controller 再次 `addChild`，避免 UIKit 双重 containment。AnchorPager 负责 page identity、selection commit/cancel、reload 清理、scroll discovery、真实 scroll target 的 inset ownership 和对外状态语义；adapter 负责把 Tabman/Pageboy 回调标准化后交回 AnchorPager。无滚动 original page 同样直接交给 Pageboy，Store 只记录 nil scroll target，不建立 wrapper containment。

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

负数或非有限测量会触发内部断言，并在 `layout` category 记录 `header.measure.invalid` 事件，运行时降级为 `0`。结构性布局会先清除 viewport/page presentation，把 Header host 临时放到顶部遮挡下方，并使用当前 Header 身份最近一次有效纯内容高度建立中立测量几何。HeaderHost 在 UIView/UIViewController 内容身份替换时使旧测量缓存失效；identity 确实变化后，Host 先对 incoming view 执行不发布状态的 compressed fitting，通过同步 nonescaping 回调创建或更新唯一 required host height constraint，再执行 `addSubview` 和四边约束激活。UIViewController Header 先 `addChild`，再 load/measure view、写 seed、附着并 `didMove`；同 identity no-op 不重复 fitting 或清空 cache。正式 fitting 仍是唯一更新测量缓存和 canonical output 的入口，bootstrap/临时几何不更新 layout context、progress、range 或状态日志缓存。

Header host 只负责 Header 内容和 containment。它可以接收内部 top offset 约束更新，但不计算 safe area、折叠进度、bar frame 或 child inset。

## LayoutEngine 与 Safe Area

`AnchorPagerLayoutEngine` 是 internal 纯计算类型，只 import `CoreGraphics`，不操作 UIKit 对象，也不绑定 MainActor。输入包括：

- 容器 bounds
- Header measured height
- `AnchorPagerHeaderHeightMode`
- `AnchorPagerHeaderTopBehavior`
- bar height
- 本地 top/bottom obstruction
- 当前归一化后的逻辑 container offset

输出包括：

- resolved Header expanded/collapsed height
- collapse offset 和 collapse progress
- Header frame
- bar frame
- content frame
- collapsed-state fixed paging frame
- child 本地底部遮挡

`AnchorPagerViewController` 负责把 UIKit safe area 转为本地遮挡。top obstruction 取 `safeAreaLayoutGuide.layoutFrame.minY - view.bounds.minY`、`view.safeAreaInsets.top` 和 `additionalSafeAreaInsets.top` 的非负最大值；bottom obstruction 取 `view.bounds.maxY - safeAreaLayoutGuide.layoutFrame.maxY`、`view.safeAreaInsets.bottom` 和 `additionalSafeAreaInsets.bottom` 的非负最大值。这个策略覆盖 root、navigation controller、tab bar controller、toolbar 和未入 window 的 additional safe area 测试路径。

AnchorPager 自有主容器 `verticalScrollView` 的 `contentInsetAdjustmentBehavior` 固定为 `.never`，横纵 scroll indicator 均隐藏，delegate 与 `contentInset` 由 AnchorPager 独占。默认 `.extendsUnderTopSafeArea` 的 top inset 为 `0`；显式 `.insideSafeArea` 的 top inset 等于本地顶部 obstruction，left/bottom/right 始终为 `0`。主容器 scroll range 只表示 Header 折叠距离，不代表页面内容进度；当前真实 child scroll view 是唯一用户可见 indicator owner，无滚动页没有 indicator owner。真实 child scroll view 由独立 managed inset coordinator 接管，不与主容器复用同一份 inset。

主容器 raw 与逻辑坐标由唯一纯 `AnchorPagerContainerScrollGeometry` 转换。设 top inset 为 `I`、纯内容可折叠距离为 `D`、viewport 高度为 `H`：`logical = raw + I`、`raw = logical - I`，展开/折叠 raw 边界分别为 `-I` 与 `D-I`，`scrollRangeView` 高度为 `H + D - I`。ScrollCoordinator 的稳定区间、boundary、handoff 和写入全部使用同一 geometry；LayoutEngine 只消费 `0...D` 逻辑 offset，不读取 raw offset。

主容器使用三个职责分离的内部层：`scrollRangeView` 约束到 `contentLayoutGuide`，只定义上述 `contentSize`；固定且裁剪的 `viewportView` 约束到 `frameLayoutGuide`，作为唯一屏幕裁剪边界；不裁剪的 `contentPresentationView` 位于 viewport 内，承载 Header host 和 paging adapter。Header/paging 可见约束不会参与 scroll range 反算，正常折叠只把 `contentPresentationView` 上移逻辑 collapse offset，不移动 viewport，也不直接修改业务 Header 根 view transform。container overflow 物理仍来自 `verticalScrollView`，但 presentation 分层：共享 chrome 的 `viewportTranslationY = topOverflow`，adapter 页面 surface 的 `pageSurfaceTranslationY = -plainBottomOverflow`，页面最终可见总位移为两者之和。顶部越界使 Header/bar/page 整体下移；plain bottom 越界只使 Pageboy 页面 surface 上移，Header/bar 保持 canonical。两类位移都由 UIKit 自身 bounce 动画驱动恢复，且不进入 Auto Layout、scroll range、managed inset、snapshot 或 generation。

LayoutEngine 的 resolved expanded/collapsed height 始终表示纯内容高度，top obstruction 不进入 collapsible distance。`insideSafeArea` 让 Header frame 从顶部 obstruction 下方开始，高度固定为完整 expanded content height；`extendsUnderTopSafeArea` 让 Header frame 从 bounds 顶部开始，高度固定为 top obstruction 加完整 expanded content height。正常折叠只减小 frame 的 `minY`，不改变高度；两种模式统一使用 `bounds.minY + topObstruction + expandedHeight - collapseOffset` 作为 bar baseline，因此切换只改变 Header 外框是否延伸，不移动分段栏和 child 内容基线。

paging adapter 的 top 跟随当前 Header bottom，但 `pagingFrame.height` 固定为 Header 完全折叠时的最大 viewport 高度。滚动热路径只改变 adapter top，Pageboy child bounds 保持稳定；bottom obstruction 不裁剪横向区域，而由 child managed bottom inset 表达。LayoutEngine 用 `max(0, pagingFrame.maxY - safeVisibleMaxY)` 输出 child 本地底部遮挡：展开态包含 adapter 被 viewport 裁剪的尾部，完全折叠态收敛为根容器 bottom obstruction。LayoutEngine 不再输出历史容器级 managed inset target。

## 主容器可视装配

`AnchorPagerViewController.reloadData()` 会从 data source 同步 Header、标题和页面数量，并在 view loaded 后安装：

- `verticalScrollView`：主容器纵向滚动入口
- Header host：承载 `.view` 或 `.viewController` Header
- `AnchorPagerPagingHostViewController`：稳定 viewport child，在非空状态内含 `AnchorPagerPagingAdapter`，空状态不含 adapter
- `AnchorPagerPagingAdapter`：内部 Tabman/Pageboy adapter，负责分段栏、横向分页内容和 page containment 执行

主容器只持有稳定 internal host，不向 Public API 暴露 Tabman/Pageboy 类型。页面控制器由 `AnchorPagerPageStateStore` 在 adapter 按 index 请求时按需提供，不在 reload 时全量预加载。当前装配已通过 UI test 验证分段栏点击、横向滑动、public API 程序化切页、真实 scroll/无滚动页面、空/非空 reload 代际替换、滚动位置恢复和完成/取消的标准 UIKit appearance 回调。v0.5 纵向嵌套滚动协调及 2026-07-14 专项修复已完成全量验收与最终复审。

### Reload terminal 与稳定 Paging Host

`AnchorPagerPagingHostViewController` 是 Header 下方布局约束的长期 owner。当前实现管理 reload request 串行、adapter containment 和事件转发，并通过 Adapter readiness 等待 selection terminal。每笔 reload request 都带 internal identifier；Host 同时最多有一个 active request 和一个 latest pending request，只有 matching adapter callback 才能形成 `.page(index:)`/`.empty` terminal。selection 活跃时，pending reload 由 adapter did/cancel 语义 terminal（程序化路径还要等 Pageboy completion）推进，不使用 timer 或主队列 delay 猜测第三方完成时机。terminal 通知期间的重入和旧 request 迟到 callback 不能结束新 active request。

v0.7 Task 2–4 已实现 selection request 的 Host 单调 identifier、active/latest admission、source 路由、matching transaction、reload-first drain 和 Adapter 单 execution 边界；Tabman bar 请求只回到 Host，不再由 Adapter 旁路调用 Pageboy。Pageboy 5.0.2 的动画 completion 早于内部 `isScrollingAnimated` 清零，因此 Adapter 只在 completion 后通过 Pageboy 的 open `isUserInteractionEnabled` 覆写点发布一次 matching executor-ready；非动画 completion 同步 acknowledgement completion 与 ready。completion 缺少 semantic 时，Host 只按 matching Adapter current index 恢复 did-select，或在 `finished == false` 时恢复 cancel；旧 adapter、identifier、target 和乱序 ready 均不释放 active。reload 到来同步丢弃尚未开始的旧 generation selection；matching semantic 先提交，active 释放后优先执行 latest reload。只有 empty Pageboy shim 已成功且 Adapter 已 ready、Host 仍缺 semantic 时，Host 才发送一次 `paging.selection.structuralCancel` 并清理 matching transaction；不借用新 generation callback。完整契约见 `docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md`。

Pageboy 5.0.2 的空 count `reloadData()` 会早退，不清空旧 `UIPageViewController` 业务页。adapter 因此在唯一 `prepareForRemoval()` 兼容点内使用 Pageboy public delete-last-page，同步验证 `pageCount == 0` 和 `currentIndex == nil`，再 post-order 清理只剩的第三方 plumbing。host 之后以标准 UIKit 顺序移除 adapter，并把 `.zero` 作为该 request 的 staged final bar inset 随 `.empty` terminal 发送。ViewController 只有实际提交 matching snapshot 才 acknowledgement；Host 仅在 ack 为 true 时更新 committed bar baseline，superseded terminal 保留旧 baseline，并推进 latest pending。该 shim 只对锁定的 Pageboy 5.0.2 验证；任何 Pageboy 升级都必须先重审 teardown、request provenance/terminal、appearance、provider activation 和 bar acknowledgement，并通过对应回归门禁。

Public `reloadData()` 在第一个 data source 回调前预留 transaction identifier，count、Header 和每个 title 回调后都验证 token。发生重入时只有最新事务能形成 staged snapshot；过期事务零写入。已有 committed visible generation 时，staged snapshot 在 matching terminal 前不发布 public metadata/Header，也不改变 visible Store 或 ownership；Host `willPerform` 才激活 provider generation。首次 view 未加载且没有 committed visible generation 时允许预发布初始 metadata并幂等激活 provider，但不会提前加载 Host/adapter view。

Store 将可跨 generation 复用的 live UIKit page/optional scroll identity payload 与每代独立的 retention reasons、strong lease、`childDistanceFromTop` snapshot 和 ownership lease 分开。Pageboy provider 读取 `pending ?? committed`，selection、layout、inset 和现有可见查询读取 `committed ?? pending`；提供给后续版本的 committed-current 入口严格只读 committed generation，没有 committed 或 empty 时返回 nil。commit 在释放旧代最后 strong lease 前建立强 `CleanupPlan`，然后发布新 committed、释放旧 lease、强制收敛新 ownership，再用 plan 归还旧代真实 scroll ownership；页面 containment 的 teardown 始终由 Pageboy 执行。

基础布局更新和 `reloadHeaderLayout()` 会发送 `AnchorPagerLayoutContext`。当前 context 覆盖有效 selectedIndex、Header frame、bar frame 和内容 frame，所有 frame 都是 pager 本地最终可见坐标，用于调试和接入验证。

`AnchorPagerLayoutContext` 中的 frame 使用 `AnchorPagerViewController.view` 的本地最终可见坐标。LayoutEngine output 和 `lastLayoutOutput` 保存由逻辑 collapse offset 得出的稳定几何；normal collapse 的位置已经包含在 output 中，container top 时三个 frame再加入相同正向位移，plain bottom 时 Header/bar frame 保持稳定折叠位置、只有 content frame 加入负向页面位移。`scrollViewDidScroll` 复用最近一次有效纯内容测量，只更新 canonical output、分层 presentation、layout context 和 collapse progress；它不重新测量 Header、不修改 scroll range，也不输出逐帧普通日志。v0.5 已完成 committed current child 的连续双向 handoff、逻辑稳定区间 offset 分配与原生边界 owner 路由；v0.7 仅在本专项 fresh-pass 完成并恢复 Ready 后扩展跨 owner 惯性合成和完整 interaction state。

`reloadHeaderLayout(offsetAdjustment:)` 会重新测量 Header，并按策略迁移 `verticalScrollView.contentOffset.y`：

- `.preserveVisualPosition`：尽量保持旧的可见 Header 高度。
- `.preserveCollapseProgress`：保持旧折叠进度。
- `.resetToExpanded`：回到展开位置。
- `.resetToCollapsed`：移动到当前折叠上限。

普通 `viewDidLayoutSubviews` 和 `viewSafeAreaInsetsDidChange` 会在 top inset 或折叠距离变化时通过结构性 geometry 事务迁移 raw offset，以保持同一逻辑折叠量或 collapse progress；无结构变化时不写 offset。`reloadHeaderLayout(offsetAdjustment:)` 的四种公开策略同样先解析目标逻辑 offset，最后才按当前 inset 转换为 raw offset。active boundary 会在迁移前同步取消，避免把旧 overflow 按新原点解释。

## v0.3 固定分页与后续滚动边界

以下固定分页与 inset ownership 已在 v0.3 实现，并由 v0.5 纵向 owner/handoff 直接消费。

当前层级为：

```text
固定 viewport（唯一屏幕裁剪边界）
└─ canonical content presentation（正常折叠整体上移）
   ├─ 固定完整高度 Header
   └─ Tabman adapter（top = Header.bottom，固定最大高度）
      ├─ Tabman bar
      └─ Pageboy child surface（plain bottom 独立位移）
```

Tabman adapter 的 top 继续跟随 Header bottom，但高度固定为 Header 完全折叠时的
最大 viewport 高度。Header 折叠滚动只移动 AnchorPager 自有 canonical content presentation；展开时
adapter 底部超出 viewport 的部分由固定 `viewportView` 裁剪。这样业务 Header 高度和 Pageboy child
bounds 都不在滚动热路径反复变化。

`AnchorPagerBarConfiguration.height` 为 `CGFloat?`，默认 nil 表示使用 Tabman bar 自适应高度，
显式值由 internal adapter 约束到实际 bar。最终 bar geometry 使用 Tabman public `barInsets.top`，
而不是把配置值当作第二份事实。

child managed top 只等于 Tabman adapter 内部实际覆盖 Pageboy child 的 bar obstruction，不包含
Header 或容器顶部 safe area。managed bottom 和 indicator bottom 等于 adapter 当前底端到 pager
安全可见底端的 child 局部遮挡；container 折叠时该派生值幂等更新，但 adapter/Pageboy child bounds
保持固定。
AnchorPager 使用弱引用差量 ownership record 合成 external/managed inset，并在 ownership 结束时
只移除最后一次 managed 部分、恢复原始 `contentInsetAdjustmentBehavior`。

v0.5 的稳定状态要求 container 未完全折叠时当前 child 位于顶部，child 离开顶部时 container完全折叠。同一 pan 的连续交接允许当前 container 与当前 child 进行受限纵向 simultaneous recognition。AnchorPager 不替换业务 child 的 scroll delegate 或 pan gesture delegate，也不设置 container 的内建 pan delegate；child offset/contentSize 通过可撤销 observation 读取，simultaneous decision 只由自有 container `UIScrollView` 子类放行当前 committed child pair。拖拽位移从固定 pan 起点计算 canonical total 后再分配到 container/child，不依赖两个 scroll callback 的先后顺序。v0.7 在此基础上增加统一 interaction state、系统返回失败关系和跨 owner 惯性；任意业务横向 child 与 Pageboy 的自动优先级不属于当前已交付能力。

`AnchorPagerScrollCoordinator` 是纵向协调期唯一 offset writer；managed inset 迁移、page snapshot 恢复和显式 Header layout adjustment 是各自结构性事务的既有 writer，不与 active pan 竞争。`AnchorPagerOverscrollCoordinator` 是纯 owner 策略状态机，不持有 UIKit、page、Store 或 provider。stable range 内由 resolver 分配 canonical position；native boundary active 时只固定非 owner，container delegate、child KVO、pan target 和相同/变化 geometry 回调都不得反向夹紧原生 owner。顶部 `.none` 收敛稳定边界，`.container` 选择自有容器，`.child` 只选择真实 committed child；底部始终按“真实 child → child、无滚动页 → container”路由。

active owner 只有在实际 overflow 超过可见阈值后才成为已呈现 owner。若业务 child 的原生 bounce 配置让 owner 已创建但始终未呈现，而同一 pan 反向回到 stable range，ScrollCoordinator 会同步结束该未呈现 owner并立即重新应用 resolver，避免把反向 delta 丢到 pan end。零稳定区间允许 pan 从 top overflow 直接进入 bottom overflow，反向亦然：纯 Overscroll policy 会在 boundary 改变且旧 owner 从未呈现时同步 finish 旧 owner，再路由新 boundary；同 boundary 保持不变，已呈现 owner 即使收到不同 boundary 请求也仍等待真实 overflow 回稳。两条 finish 路径互斥，不重复发出生命周期日志。child KVO 观察到顶部负 offset 时，只有 container 已展开到 epsilon 内才允许进入 top owner；Header 部分折叠时始终保持 canonical container offset、把 child 钉回顶部且不创建 owner，这一门禁不依赖 container/child 回调顺序。

### v0.7 Interaction State

`AnchorPagerInteractionState` 是只携带 internal identifier 的纯 `Sendable` 值类型，包含 idle、vertical dragging/decelerating、horizontal/programmatic paging、top overscrolling、layout reloading 和 transitioning size。`AnchorPagerInteractionCoordinator` 由 MainActor 隔离，只保存当前 state、size 抢占时可恢复的 programmatic/horizontal/layout state，以及最近一次非法转换去重键；不保存 UIKit、page、provider、Store、selection/reload payload、geometry 或 offset。

vertical dragging 只能以 matching identifier 进入 top overscrolling 或 vertical decelerating；top natural finish 回到同一 dragging，structural cancel 回 idle。size 可以抢占任意状态，但只恢复仍 active 的 paging/layout state；这些 transaction 在 size 内先 terminal 时会清除 suspended resume，size finish 后回 idle。重复 begin/update 幂等，旧 identifier、低优先级覆盖和重复 terminal 不修改 state；连续相同非法转换只记录一次固定 `interaction.state.invalidTransition`。

v0.7 Task 6 已完成 Host/ViewController 的统一排空装配。Host 仍是 reload 与 selection payload 的唯一 owner；ViewController 只保存一笔 latest `PendingHeaderLayoutRequest`，Interaction Coordinator 只保存状态。Host terminal/executor-ready 通过 internal drain handler 请求容器排空，不直接调用 Header layout；容器使用同步重入 guard，严格按 active Pageboy → transitioning size → Host reload → Header layout → Host selection 推进。reload pending/active 继续拒绝新 selection，避免 target 跨 metadata/generation；交互暂停产生 pending-only selection 时，同目标去重、不同目标 latest 替换、请求 committed 目标则撤销尚未启动的 pending。Header layout 回调内产生的新请求进入下一轮 drain。尺寸开始同步恢复 canonical boundary/page presentation 并暂停排空，但不伪造 active Pageboy selection cancel；尺寸完成后若 Pageboy 仍 active 则恢复 matching paging state，否则从最高优先待处理事务恢复。Task 11 已把真实 lifecycle 结构化接入该排空入口，测试 admission hook 与 `isReadyForDeferredWorkDrain` 均不持有 payload。

v0.7 Task 7 已在 Paging adapter 内建立可撤销的 Pageboy paging surface observation。观察器只从 adapter 的公开 UIKit containment 中按最近层级寻找 `UIPageViewController`，再从其 view 子树选择最浅层 `UIScrollView`；不依赖 UIKit 私有类名。它只向分页 pan 安装 target-action，不读取或写入 Pageboy scroll/pan delegate、`isScrollEnabled` 或 bounce 配置；相同 identity 的重复 refresh 幂等，identity replacement 先解绑旧 pan，reload terminal/layout 时刷新，adapter teardown 与观察器析构时同步清理。Adapter 只向 internal delegate 暴露 surface identity 与 pan state，Public API、Pageboy containment 和业务 child ownership 均未改变。surface bind/unbind 仅记录固定 `paging.surface.bind/unbind`，pan 热路径不输出普通日志；Task 8 在该 identity 基础上安装公开 failure relation。Task 11 以 Host matching interactive will/semantic terminal 作为 horizontal interaction 真值，不从原始 pan state 建立第二套 selection transaction。

v0.7 Task 12 只扩展示例验收面：既有 empty/short/long/plain index 保持不变，第五页上半区域提供真实业务 horizontal `UIScrollView`，下半区域保留 Pageboy 命中面；隐藏 probe 只序列化业务 scroll/pan delegate identity 稳定性与 scroll configuration。selection probe 只记录公开 `didSelect`，连续选择与 tracked-scroll 竞争入口也只调用公开 API。纵向 probe 在既有可见页 `CADisplayLink` 采样链路上记录 canonical total、最大方向反跳、最大 stable invariant 偏差和双向 handoff，不建立第二个 timer，也不改变框架 Public API 或所有权边界。

v0.7 Task 13 以 launch-argument gated 的 Example harness 验收真实事务竞争。public selection trigger 在同一调用栈连续调用 `setSelectedIndex`；bar trigger 只遍历 Example 已安装的 UIKit view，向匹配 accessibility label 的实际 `UIControl` 发送其既有 `.touchUpInside` action，不导入或强转 Tabman 类型。selection probe 仅记录公开 `didSelect`，并与真实页面和 appearance 序列交叉验证。tracked-scroll 入口只从业务 child `scrollViewDidScroll` 的 `isTracking == true` 分支调用公开 reload/layout；同步 probe 证明调用返回时旧页面仍可见，matching interaction terminal 后才提交新 Example 代际。size 入口在真实 `viewWillTransition` 内发出连续公开选择，只有 latest 请求在 size terminal 后执行，不伪造被替换目标的 appearance。所有入口在正常启动时均不存在，不进入框架 Public API 或生产 transaction owner。

v0.7 Task 8/14 最终由 `AnchorPagerGesturePriorityCoordinator` 只安装 system/page 的公开 failure relation：Pageboy paging pan 对 navigation interactive-pop gesture 建立失败依赖，Coordinator 弱持有双方 identity、同一 pair 单调去重，并在 paging surface replacement 后为新 pan 建立关系。它只调用 `require(toFail:)`，不设置 system/Pageboy/业务 recognizer delegate，也不持有业务 scroll identity。真实 UI 证明候选 `pagingPan -> childPan` 在 containment 前后都会与同向嵌套 scroll 的 UIKit 层级仲裁形成失败环，Pageboy 仍获胜；业务子树 guard、共同祖先 hit-region guard 和 simultaneous/non-preventing guard 同样不能在不接管既有 delegate、不 reset 手势、不依赖私有层级且不阻塞页面其他区域的约束下稳定改变 winner。生产代码因此不保留 child relation 或 guard。若未来支持业务横向 child 优先，必须先设计显式接入契约，不得通过遍历业务树、写 offset、修改 `isScrollEnabled`/bounce 或私有 API 隐式实现。

v0.7 Task 9 已建立不依赖 UIKit 的 `AnchorPagerVerticalDecelerationModel` 和唯一生产 `CADisplayLink` driver。纯模型按 UIScrollView 毫秒衰减公式计算任意两个 elapsed time 之间的 delta、剩余 velocity 与 `5 pt/s` finish 阈值，拒绝非有限值、越界 rate 和倒退时间；正负 velocity 使用同一公式并保持符号。Driver 只持有模型输入、单调时钟、display-link target proxy 和 lifecycle closure，不持有或写 UIScrollView/page/provider；target proxy 弱持有 driver，replacement/cancel/finish/deinit 均同步 invalidate。测试只注入 display-link 生命周期和时钟，不增加第二套 timer。tick 热路径不记录普通日志，只在 run begin/finish/cancel 输出固定事件；真实 owner 监控、handoff delta 消费和取消矩阵由 Task 10 接入 ScrollCoordinator。

v0.7 Task 10/14 已把 container 与 committed child 的 pan velocity 接入现有 `AnchorPagerScrollCoordinator`，不新增 delegate 或第二套纵向 handoff。ended 时只接受 current owner 对应的 recognizer，以 `-velocityY` 作为 canonical velocity，并读取该 owner 当时的 `decelerationRate.rawValue`；同一 vertical interaction 最多启动一个 context，stale binding token、反向/低速、非法 rate 与不可穿越边界均不启动合成。唯一 driver 先进入 monitor-native phase，只累积纯模型 delta，不写 container/child offset；native owner 到达交接边界后，同一 driver 仅消费投影总量越过边界的 overflow，再由 Resolver 写入接收 owner。切入 synthetic 时先以 guarded、非动画边界写入停止接收 owner 的竞争原生减速；之后旧 native owner 的迟到 callback 锁回旧边界，接收 owner 的迟到 callback 则恢复 driver 当前 canonical stable pair，两者都不输出伪 position transition 或覆盖 driver canonical total。到稳定端点同步停止且不创建 overscroll owner。新 pan、结构性 geometry/identity/mode/boundary/invalidate 以及上层 selection/reload/Header/size 入口会同步取消 context；interaction identifier 隔离迟到 tick，旧 driver 不能取消替换后的事务。Offset writer 仍只有 ScrollCoordinator，OverscrollCoordinator 仍只管理 owner 策略。

v0.7 Task 11 已通过 internal delegate 把 specialized coordinator 的真实 lifecycle 接入 `AnchorPagerInteractionCoordinator`。ScrollCoordinator 只发同一 vertical identifier 的 dragging、top enter/leave、decelerating、finish/cancel 事件；top owner 只有经 OverscrollCoordinator 确认后才更新 state，可见与未呈现回稳都成对离开，driver 自然阈值/稳定端点发 finish，结构性 identity/geometry/new-pan 取消发 matching cancel；top mode identity 未变化时为 no-op，不因其他配置变化取消真实 drag。PagingHost 在 explicit execution 或 matching interactive will 真正获准时开始 programmatic/horizontal state；interactive semantic terminal 和 explicit semantic + completion + executor-ready 全部满足后才 finish，adapter reject/structural teardown 才 cancel。Reload 由 Host 单独包围 `layoutReloading` lifecycle，`willPerformReloadRequest` 继续只负责 provider generation lease。ViewController 是唯一映射与 drain 点：drag/top 期间 reload/layout/selection 只保留既有 latest payload，vertical deceleration 先取消 driver 再 drain，paging/layout/size 按既定优先级串行；尺寸入口先建立 `transitioningSize` 并暂停 Host，再取消 boundary/driver，取消事件不能抢先排空 pending；size 内 paging terminal 只清 suspended state，若 transaction 仍 active 则尺寸完成后恢复 matching paging state。Interaction Coordinator 不持有 UIKit、page、provider、Store、payload、geometry 或 offset，Scroll/Host 也不互调对方的 specialized API。

已呈现 `.top/.child` owner 从负 overflow 回到 stable range 时，边界 enforcement 只返回 finish 结果和原 owner，不再递归进入通用 stable settle。若当前回调携带 container pan resolver input，ScrollCoordinator 同轮立即应用该 input；若只有 child KVO，则先保存原始总量 `containerBoundary(0) + rawChildDistance`，再交给同一 Resolver 按 container-first 分配。例如 child 从 `-12` 越过顶部到 `+6` 时最终位置为 `container = 6, child = top`，不会跳成 `container = collapsed, child = 6`。`.top/.container`、真实 child bottom 和无滚动页 container bottom 的 observer finish 仍沿用原稳定化语义；整个流程保持 ScrollCoordinator 唯一 offset writer，不依赖 KVO/pan 回调先后顺序。

container top 使用 `topOverflow` 变换共享 viewport；plain bottom 保留 container 作为原生物理 owner，但只通过 Paging adapter 变换 `UIPageViewController.view` 页面 surface。不得变换业务 page 根 view，也不得在页面 surface 不可用时退化为移动 Header/bar。LayoutEngine output、scroll range、managed inset、snapshot 与 generation 都保持 canonical；`AnchorPagerLayoutContext` 报告分层后的实际可见 frame。顶部 mode 切换、selection will-select、matching Host will-perform、实际 Header layout transaction、尺寸过渡、committed child rebind 和 deinit 都同步取消 active boundary并恢复 page surface identity。`reloadData()` 在非 idle 阶段只同步采集并替换 Host latest metadata payload，不提前取消仍 active 的手势/presentation；只有 matching reload 真正开始时才执行 canonical reset。

Binding 只保留不占用 delegate 的 contentOffset/contentSize observation 与 pan target，永远不保存、修改或恢复业务 child 的 `bounces`、`alwaysBounceVertical`、scroll delegate、pan delegate 或 `isScrollEnabled`。`.child` 顶部及真实 child bottom 是否出现原生回弹取决于业务 scroll view 自身配置；短内容由业务方决定是否启用 `alwaysBounceVertical`。

由于 AnchorPager 不接管业务 delegate，也不修改业务 bounce 属性，UIKit 可能先向业务 delegate 发布瞬时非 owner 越界，然后内部 observation 才执行 guarded stable-boundary write。框架契约是非 owner 不形成持续可见 presentation、稳定位置正确且只有选定 owner 保留原生越界，不再承诺业务 delegate 从未观察到瞬时负 offset。Example 因此只在 `CADisplayLink` 显示帧采样当前 child 的 presentation offset；业务 delegate 回调只标记待采样，采样器在 page `viewWillAppear` 启动、`viewDidDisappear` 与析构时同步清理，避免把同一 run loop 内已修正的原始回调误记为可见 UI。

## Child Lifecycle

横向 page containment 的执行层是 Tabman/Pageboy adapter。AnchorPager 的职责是维护 page lifecycle 策略和对外语义，而不是在主容器中重复 `addChild` 每个横向 page。`AnchorPagerPagingAdapter` 通过弱 `AnchorPagerPageProviding` 按 index 请求页面，不持有业务页面数组；`AnchorPagerPageStateStore` 以 reload generation + index 管理 weak live page identity、optional scroll identity、current/transition/可选 adjacent 强保留和真实 scroll target 的 `childDistanceFromTop` snapshot。

Store 同时维护 committed generation 和至多一个 provider pending generation。已有可见内容时，`reloadData()` 只 staged snapshot；Host matching `willPerform` 才建立 pending provider generation。非空由 matching Pageboy callback 形成 `.page` terminal，空态由 paging host 完成真实 teardown 后形成 `.empty` terminal；ViewController ack 后才一起提交 Store、public metadata/Header、terminal index 与 bar inset。新的 reload 抢占尚未提交的 snapshot/provider 时只取消 pending generation-specific lease/snapshot，不修改旧 committed state 或 ownership。负 page count 在最新 metadata transaction 采集时断言、记录 `children.page.invalidCount` 并降级为零；同一 generation 内 data source 若把同一个控制器实例用于多个 index，后一个 index 会断言、记录日志并使用内部空白 direct page，避免 Pageboy containment 身份冲突。

同一 generation、同一 index 的实际页面仍存活时，Store 始终复用同一实例。默认只强保留 current 和 transition source/target；`keepsAdjacentPagesLoaded` 开启后额外保留已经加载过的当前页相邻页面，不主动预取。页面退出保留窗口时，Store 保存 `childDistanceFromTop`、归还 managed inset 并释放 AnchorPager 强引用。重新创建目标页面时，container 完全折叠则恢复 snapshot，尚未完全折叠则归顶。该规则为 v0.5 的唯一纵向 owner 不变量提供稳定页面状态基础。

旧 `AnchorPagerChildViewControllerStore` 已移除。普通横向业务页面只由 Pageboy/UIKit 执行 containment 和 appearance lifecycle；AnchorPager 不因缓存 retain/release 手工转发 appearance。

2026-07-13 无滚动页面修复已按 `docs/superpowers/specs/2026-07-13-plain-page-direct-containment-design.md` 完成：original page 直接由 Pageboy/UIKit containment；Store 保持 page 非 nil、scroll target 为 nil，不应用 managed inset、snapshot、child bounce 或 simultaneous pair。顶部 `.container` 和底部边界的原生物理都由外层 container 提供；2026-07-14 修订后，顶部仍整体移动 viewport，底部只移动 adapter 内 Pageboy 页面 surface，plain root identity、物理底边与 `.child` 不回退契约不变。

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

v0.4 由 PageStateStore 在页面第一次按需请求时加载该 child view，并且每个存活实例只解析一次 scroll target。目标修订后，若两个页面声明同一 scroll view，后出现的页面尝试非冲突默认目标，否则保留 original page 并把 scroll target 降级为 nil，同时记录 `inset.targetCollision`。scroll target claim 的生命周期与 generation/page state 一致，页面淘汰或 reload 清理时同步归还。

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
- `layout.headerPresentationInstalled`
- `inset.containerTopChanged`
- `inset.ownership.begin`
- `inset.ownership.update`
- `inset.ownership.end`
- `inset.ownership.skip`
- `inset.targetCollision`

这些事件只在对应状态变化时记录，不在无变化的 layout pass、`reloadHeaderLayout` 或滚动热路径中重复输出。`layout.headerPresentationInstalled` 只在 canonical content presentation 层安装时记录，`inset.containerTopChanged` 只在解析后的主容器 top inset 变化时记录。事件名不携带几何数值，避免泄漏用户界面内容或完整层级信息。

v0.4 页面状态事件包括 `children.page.load/reuse/recreate`、`children.page.retain/release`、`children.page.snapshot.save/restore/reset`、`children.page.generation.begin/commit/cancel`、`children.page.duplicateController` 和异常 data source/count 降级。缓存窗口或 snapshot 状态变化才会记录；单纯 managed inset 热路径不输出 children 日志。

v0.5/v0.6 的 scroll/overscroll 事件只记录 binding、owner/handoff、stable boundary 跨越，以及 overscroll boundary/owner/mode 的 begin、finish、cancel、unavailable。重复 container delegate、child KVO、pan changed 或 geometry update 不逐帧输出 guard/位移日志。

v0.7 Interaction state 事件为 `interaction.state.begin/updateBoundary/finish/cancel/invalidTransition`。事件名不携带 identifier、index、velocity 或 geometry；重复合法 callback 不重复记录，连续相同非法 callback 只记录一次。

## Known Limitations

Xcode 26.3 / Swift 6.2.4 的 x86_64 iPhone 17 Simulator 中，控制器改用 `isolated deinit` 会在 lifecycle
deinit 后稳定触发 allocator `pointer being freed was not allocated` 崩溃；恢复普通
`deinit + MainActor.assumeIsolated` 后同一资源析构测试通过。当前析构契约必须同步归还 Store 与 managed
inset ownership，不使用异步 Task、delay 或并发 unsafe 标记规避。后续 Xcode/Swift 升级只有在同一资源析构测试复验通过后，
才可重新评估 `isolated deinit`。

当前生产代码已实现固定分页 viewport、child inset ownership、按需 page state/cache window、reload generation、连续纵向 handoff、plain direct page、stable/native boundary 分离、三种顶部 owner 路由、plain bottom 分层 page presentation、Header 正式 measurement/内容附着前 bootstrap，以及主容器真实 top inset、逻辑 offset 与固定高度 Header presentation。2026-07-14 专项最终验收为 Framework 322/322、Example 41/41 和 generic Simulator build，0 fail、0 skip、0 error/warning/analyzer warning；fresh-pass 终态 Critical 0、Important 0、Minor 0，v0.5/v0.6 已恢复 Ready。仍不包含：

- v0.7 已完成系统返回、纵横竞争与双向跨 owner 惯性 UI 验收；任意业务横向 `UIScrollView` 自动优先于 Pageboy 当前不支持，原因与禁用方案见 v0.7 手势优先级章节
- v0.8 状态栏点击顶滚 owner 和尺寸变化后的滚动位置恢复
- refresh control、刷新任务或业务 overscroll 回调
- v0.8 `scrollsToTop` 消费者只读 committed current/empty owner；v0.7 按已确认设计把 selection request admission 收口到 Host 且不建立第二套 generation owner；v0.9 accessibility/RTL 不读取 provider pending
