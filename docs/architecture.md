# AnchorPager 架构说明

本文档面向维护者，记录当前 v0.2 Header 与布局稳定阶段的架构边界和已固定的基础契约。

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

`AnchorPagerAssertions` 是内部断言门面，不操作 UIKit 状态，因此不绑定 MainActor。测试需要临时关闭断言时通过 `@TaskLocal` 的 `isEnabled` 覆盖当前调用上下文，避免共享可变全局状态，也避免使用 `nonisolated(unsafe)` 压制 Swift 6 并发检查。

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

负数或非有限测量会触发内部断言，并在 `layout` category 记录 `header.measure.invalid` 事件，运行时降级为 `0`。`AnchorPagerViewController` 会在主容器内安装 Header host，并把测量后的 Header 高度交给 LayoutEngine 解析。

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
- 容器级 managed inset target

`AnchorPagerViewController` 负责把 UIKit safe area 转为本地遮挡。top obstruction 取 `safeAreaLayoutGuide.layoutFrame.minY - view.bounds.minY`、`view.safeAreaInsets.top` 和 `additionalSafeAreaInsets.top` 的非负最大值；bottom obstruction 取 `view.bounds.maxY - safeAreaLayoutGuide.layoutFrame.maxY`、`view.safeAreaInsets.bottom` 和 `additionalSafeAreaInsets.bottom` 的非负最大值。这个策略覆盖 root、navigation controller、tab bar controller、toolbar 和未入 window 的 additional safe area 测试路径。

AnchorPager 自有主容器 `verticalScrollView` 的 `contentInsetAdjustmentBehavior` 固定为 `.never`。safe area、navigation bar、tab bar 和 toolbar 遮挡已经被转换为 LayoutEngine 的本地 obstruction；如果继续使用 UIKit 自动 content inset，Header 实际 frame 会比 `AnchorPagerLayoutContext.headerFrame` 多叠一层 top inset。这个约束只属于主容器，不代表 v0.3 的 child managed inset 写入已完成。

`insideSafeArea` 会让 Header frame 从顶部 obstruction 下方开始。`extendsUnderTopSafeArea` 会让 Header frame 从 bounds 顶部开始；当当前 Header 内容高度小于顶部 obstruction 时，LayoutEngine 会将 Header 可视 frame 高度提升到顶部 obstruction 高度，并保持 `barFrame.minY == headerFrame.maxY`。`AnchorPagerLayoutContext.headerFrame.height` 表示布局后的可视 frame 高度，可能大于 `AnchorPagerHeaderHeightMode` 解析出的当前 Header 内容高度。paging adapter 的 top spacing 和高度跟随 engine 输出，使实际分段栏/页面区域与 layout context 保持一致。content frame 默认延伸到容器 `bounds.maxY`，在全屏容器中即物理屏幕最底部；bottom obstruction 不裁剪横向区域，只进入 `managedInsetTarget.bottom`，供 v0.3 的 child inset ownership 使用。

v0.2 只计算 managed inset target 并记录日志，不写入外部 child scroll view 的 managed content inset；完整 inset ownership 在 v0.3 实现。AnchorPager 自有主容器和内部 fallback scroll host 会禁用 UIKit 自动 content inset，避免系统 inset 与 LayoutEngine 的本地遮挡计算重复作用。

## 主容器可视装配

`AnchorPagerViewController.reloadData()` 会从 data source 收集 Header、标题和 child view controller，并在 view loaded 后安装：

- `verticalScrollView`：主容器纵向滚动入口
- Header host：承载 `.view` 或 `.viewController` Header
- `AnchorPagerPagingAdapter`：内部 Tabman/Pageboy adapter，负责分段栏、横向分页内容和 page containment 执行

主容器只持有内部 adapter，不向 Public API 暴露 Tabman/Pageboy 类型。当前装配提供基础可视路径，并已通过 UI test 验证分段栏点击、横向滑动和 public API 程序化切页。完整 page state store、scroll inset ownership 和纵向嵌套滚动协调将在后续版本推进。

v0.2 会在基础布局更新和 `reloadHeaderLayout()` 时发送 `AnchorPagerLayoutContext`。当前 context 覆盖有效 selectedIndex、Header frame、bar frame 和内容 frame，用于调试和接入验证。

`AnchorPagerLayoutContext` 中的 frame 使用 `AnchorPagerViewController.view` 的本地可见坐标，不是 `verticalScrollView` content 坐标。`AnchorPagerViewController` 将 Header host 写入 scroll content 约束时，会用当前 `verticalScrollView.contentOffset.y` 把可见 Y 坐标转换为 content Y 坐标，确保 `.preserveVisualPosition` 保留非零 offset 后，实际可见 Header frame 仍与 layout context 对齐。

`reloadHeaderLayout(offsetAdjustment:)` 会重新测量 Header，并按策略迁移 `verticalScrollView.contentOffset.y`：

- `.preserveVisualPosition`：尽量保持旧的可见 Header 高度。
- `.preserveCollapseProgress`：保持旧折叠进度。
- `.resetToExpanded`：回到展开位置。
- `.resetToCollapsed`：移动到当前折叠上限。

普通 `viewDidLayoutSubviews` 和 `viewSafeAreaInsetsDidChange` 布局更新不会主动迁移 content offset，避免系统布局 pass 改变用户当前滚动位置。

## Child Lifecycle

横向 page containment 的执行层是 Tabman/Pageboy adapter。AnchorPager 的职责是维护 page lifecycle 策略和对外语义，而不是在主容器中重复 `addChild` 每个横向 page。后续 v0.4 的 child lifecycle 工作应围绕 page identity、cache window、offset snapshot、reload 清理、重复 view controller 策略和 selection commit/cancel 展开。

`AnchorPagerChildViewControllerStore` 是 v0.1 保留的独立基础 containment 工具，不接入横向分页主路径。后续 v0.4 可以将其重定位或替换为 page state store；如果继续保留，也只能用于 AnchorPager 自有 wrapper 场景，不能与 Tabman/Pageboy 对同一个 page view controller 形成双重 containment。

`AnchorPagerPageScrollHostViewController` 为无 scroll view child 提供内部 fallback scroll host。fallback host 的 scroll view 使用 `.never` content inset adjustment，把普通 child view 约束到 scroll view content layout guide，并保证内容高度至少覆盖可视 viewport，避免无固有高度的普通 child 在示例工程中不可见或被 tab bar/safe area 自动 inset 抬高底部。`AnchorPagerViewController.reloadData()` 会清理不再使用的旧 fallback host content，并记录 `children` 日志。完整 page cache window、Tabman 驱动的 appearance lifecycle 语义和 offset snapshot 将在后续版本实现。

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

当前 v0.1 主容器在 `reloadData()` 收集页面时会加载 child view 以执行 scroll discovery 和 fallback host 判断。这样能保证示例和基础分页路径稳定，但不是最终的 page cache/window 策略；后续 v0.4 应把 scroll discovery 与 page state store、懒加载和 offset snapshot 统一，减少 reload 阶段的提前加载。

## 日志策略

日志门面为 `AnchorPagerLogger`，底层使用 `os.Logger`，subsystem 为 `com.anchorpager.AnchorPager`。`AnchorPagerLogger.log` 不绑定 MainActor，内部非 UIKit 路径可以从非主线程记录诊断事件。测试用 sink 单独由 MainActor 隔离：主线程日志同步投递 sink，非主线程日志会把 sink 投递回 MainActor。

category 覆盖：

`lifecycle`、`layout`、`header`、`paging`、`children`、`scroll`、`inset`、`overscroll`、`gesture`、`accessibility`、`resource`

日志测试通过内部可注入 sink 验证，不依赖人工查看控制台。日志消息只使用稳定事件名，不记录业务数据、用户内容或完整 view 层级。

v0.2 布局日志事件：

- `layout.headerHeightResolved`
- `layout.headerFrameChanged`
- `layout.barFrameChanged`
- `layout.safeAreaChanged`
- `layout.boundsChanged`
- `inset.managedTargetChanged`

这些事件只在对应状态变化时记录，不在无变化的 layout pass、`reloadHeaderLayout` 或滚动热路径中重复输出。事件名不携带几何数值，避免泄漏用户界面内容或完整层级信息。

## Known Limitations

当前 v0.2 已完成可视分页核心路径和 Header 布局稳定契约，仍不包含后续版本能力：

- child managed inset ownership 写入
- 完整 page cache window 和 Tabman 驱动的 appearance lifecycle 语义
- 纵向嵌套滚动协调
- 顶部 overscroll owner
- 手势状态机
- 状态栏点击顶滚 owner
- 尺寸变化恢复
- `AnchorPagerConfiguration` 中 `topOverscrollHandlingMode`、`paging.keepsAdjacentPagesLoaded` 等后续版本配置项只保留 public skeleton 和默认值，完整行为按版本路线推进
