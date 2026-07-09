# AnchorPager 架构说明

本文档面向维护者，记录当前 v0.1 可视分页核心阶段的架构边界和已固定的基础契约。

## 模块划分

```text
Sources/AnchorPager/
  Public/      Public API、配置、协议、UIViewController scroll 接入扩展
  Core/        内部断言和非 UI 基础设施
  Header/      Header UIView/UIViewController 基础承载与测量
  Children/    Child containment store 和 fallback page scroll host
  Paging/      Tabman/Pageboy internal adapter
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

## Tabman/Pageboy 边界

Tabman 和 Pageboy 只允许出现在 `Sources/AnchorPager/Paging/`。当前验证版本：

- Tabman `4.0.1`
- Pageboy `5.0.2`

`AnchorPagerPagingAdapter` 继承 `TabmanViewController`，实现 Pageboy data source 和 Tabman bar data source。adapter 初始化时将 `automaticallyAdjustsChildInsets` 设为 `false`，避免 Tabman 自动 child inset 与 AnchorPager 后续 managed inset 策略冲突。

Public API source scan 测试会检查 `Sources/AnchorPager/Public/` 不包含 `Tabman` 或 `Pageboy`。

## Header 承载

`AnchorPagerHeaderViewHost` 负责 Header 内容承载：

- `.view(UIView)`：添加到 host view 内并约束到四边。
- `.viewController(UIViewController)`：使用 `addChild`、添加 view、`didMove(toParent:)`；移除时使用 `willMove(toParent: nil)`、移除 view、`removeFromParent()`。

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
- `AnchorPagerPagingAdapter`：内部 Tabman/Pageboy adapter，负责分段栏和横向分页内容

主容器只持有内部 adapter，不向 Public API 暴露 Tabman/Pageboy 类型。当前装配提供基础可视路径和 `setSelectedIndex(_:animated:)` 到 adapter 的转发；完整 child cache window、scroll inset ownership、点击/横滑切页 UI 验收和纵向嵌套滚动协调仍继续按 v0.1/v0.3 节奏推进。

## Child Lifecycle

`AnchorPagerChildViewControllerStore` 负责基础 child containment：

- 安装时调用 `addChild`、添加 child view、`didMove(toParent:)`
- 清理时调用 `willMove(toParent: nil)`、移除 view、`removeFromParent()`

`AnchorPagerPageScrollHostViewController` 为无 scroll view child 提供内部 fallback scroll host。完整 cache window、appearance lifecycle 转发、offset snapshot 和 reloadData 与 adapter 状态同步将在后续版本实现。

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

## 日志策略

日志门面为 `AnchorPagerLogger`，底层使用 `os.Logger`，subsystem 为 `com.anchorpager.AnchorPager`。`AnchorPagerLogger.log` 不绑定 MainActor，内部非 UIKit 路径可以从非主线程记录诊断事件。测试用 sink 单独由 MainActor 隔离：主线程日志同步投递 sink，非主线程日志会把 sink 投递回 MainActor。

category 覆盖：

`lifecycle`、`layout`、`header`、`paging`、`children`、`scroll`、`inset`、`overscroll`、`gesture`、`accessibility`、`resource`

日志测试通过内部可注入 sink 验证，不依赖人工查看控制台。日志消息只使用稳定事件名，不记录业务数据、用户内容或完整 view 层级。

## Known Limitations

当前 v0.1 尚未完成：

- 示例工程已验证基础 Header、分段栏和当前页面内容可见；分段栏点击切页和横向滑动切页仍需补充 UI 验收
- Header 折叠/展开布局引擎
- managed inset ownership
- 完整 child cache window 和 appearance lifecycle 转发
- 纵向嵌套滚动协调
- 顶部 overscroll owner
- 手势状态机
- 状态栏点击顶滚 owner
- 尺寸变化恢复
