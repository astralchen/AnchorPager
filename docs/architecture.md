# AnchorPager 架构说明

本文档面向维护者，记录当前 v0.1 可视分页核心阶段的架构边界和已固定的基础契约。

## 模块划分

```text
Sources/AnchorPager/
  Public/      Public API、配置、协议、UIViewController scroll 接入扩展
  Core/        内部断言和非 UI 基础设施
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

`AnchorPagerViewController` 现在会在主容器内安装 Header host，并把测量后的 Header 高度接入纵向内容布局。完整 header 折叠、safe area 和 runtime frame 恢复在后续版本实现。

## 主容器可视装配

`AnchorPagerViewController.reloadData()` 会从 data source 收集 Header、标题和 child view controller，并在 view loaded 后安装：

- `verticalScrollView`：主容器纵向滚动入口
- Header host：承载 `.view` 或 `.viewController` Header
- `AnchorPagerPagingAdapter`：内部 Tabman/Pageboy adapter，负责分段栏、横向分页内容和 page containment 执行

主容器只持有内部 adapter，不向 Public API 暴露 Tabman/Pageboy 类型。当前装配提供基础可视路径，并已通过 UI test 验证分段栏点击、横向滑动和 public API 程序化切页。完整 page state store、scroll inset ownership 和纵向嵌套滚动协调将在后续版本推进。

v0.1 会在基础布局更新和 `reloadHeaderLayout()` 时发送 `AnchorPagerLayoutContext`。当前 context 覆盖有效 selectedIndex、Header frame、基础 bar frame 和内容 frame，用于调试和早期接入验证。`reloadHeaderLayout(offsetAdjustment:)` 在 v0.1 只做重新测量和 context 通知；`.preserveVisualPosition`、`.preserveCollapseProgress`、`.resetToExpanded`、`.resetToCollapsed` 的完整 offset 迁移语义仍属于 v0.2 布局稳定版。

## Child Lifecycle

横向 page containment 的执行层是 Tabman/Pageboy adapter。AnchorPager 的职责是维护 page lifecycle 策略和对外语义，而不是在主容器中重复 `addChild` 每个横向 page。后续 v0.4 的 child lifecycle 工作应围绕 page identity、cache window、offset snapshot、reload 清理、重复 view controller 策略和 selection commit/cancel 展开。

`AnchorPagerChildViewControllerStore` 是 v0.1 保留的独立基础 containment 工具，不接入横向分页主路径。后续 v0.4 可以将其重定位或替换为 page state store；如果继续保留，也只能用于 AnchorPager 自有 wrapper 场景，不能与 Tabman/Pageboy 对同一个 page view controller 形成双重 containment。

`AnchorPagerPageScrollHostViewController` 为无 scroll view child 提供内部 fallback scroll host。fallback host 会把普通 child view 约束到 scroll view content layout guide，并保证内容高度至少覆盖可视 viewport，避免无固有高度的普通 child 在示例工程中不可见。`AnchorPagerViewController.reloadData()` 会清理不再使用的旧 fallback host content，并记录 `children` 日志。完整 page cache window、Tabman 驱动的 appearance lifecycle 语义和 offset snapshot 将在后续版本实现。

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

## Known Limitations

当前 v0.1 已完成可视分页核心路径，仍不包含后续版本能力：

- Header 折叠/展开布局引擎
- Header top safe area 视觉迁移完整实现
- managed inset ownership
- 完整 page cache window 和 Tabman 驱动的 appearance lifecycle 语义
- 纵向嵌套滚动协调
- 顶部 overscroll owner
- 手势状态机
- 状态栏点击顶滚 owner
- 尺寸变化恢复
- `AnchorPagerConfiguration` 中 `topOverscrollHandlingMode`、`header.topBehavior`、`paging.keepsAdjacentPagesLoaded` 等后续版本配置项只保留 public skeleton 和默认值，完整行为按版本路线推进
