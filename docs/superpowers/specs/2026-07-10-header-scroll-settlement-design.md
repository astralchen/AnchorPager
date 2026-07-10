# Header 主容器视口与滚动范围解耦设计

## 背景

AnchorPager v0.2 支持在运行时切换 `AnchorPagerHeaderTopBehavior`，示例工程通过
`.preserveVisualPosition` 在 `.insideSafeArea` 与
`.extendsUnderTopSafeArea` 之间迁移 Header 布局。

当前可稳定复现以下异常：

1. 默认以 `.insideSafeArea` 显示页面。
2. 切换到 `.extendsUnderTopSafeArea`。
3. 再切换回 `.insideSafeArea`。
4. 向下拖动主容器一小段距离后松手。
5. 等待回弹完全结束。
6. Header 顶部仍与安全区域顶部保留一段空白。

该空白是回弹结束后的稳定错误状态，不是 UIKit rubber-band 期间允许出现的瞬时位移。

## 全链路关系梳理

### 数据流

当前布局数据依次经过：

1. `AnchorPagerViewController` 读取 Header 测量高度、safe area、本地 bounds 和
   `verticalScrollView.contentOffset.y`。
2. `AnchorPagerLayoutEngine` 计算 resolved height、collapse offset/progress、Header/bar/content
   的可见 frame 和 managed inset target。
3. `AnchorPagerViewController` 把可见 frame 转换为 scroll content 坐标并写入 Auto Layout。
4. Auto Layout 通过 Header 与 paging adapter 的底部约束反向确定主滚动视图的 content size。
5. UIScrollView 根据 content size 决定合法 content offset 和回弹终点。

问题发生在第 3–5 步形成的闭环，不在 LayoutEngine 的 safe area 或高度计算中。

### 现有约束关系

`AnchorPagerLayoutContext` 使用 `AnchorPagerViewController.view` 的本地可见坐标，Header host
位于 `verticalScrollView.contentLayoutGuide` 所代表的 content 坐标系内。当前实现使用：

```swift
contentY = visibleY + verticalScrollView.contentOffset.y
```

并通过以下约束确定 content 高度：

```text
contentView.top
  → Header.top
  → Header.height
  → paging.top
  → paging.height
  → contentView.bottom
```

以 `.insideSafeArea`、展开高度 `H`、top obstruction `safeTop`、当前 offset `d` 为例：

```text
Header.top     = safeTop + d
Header.height  = H - d
paging.height  = bounds - safeTop - H + d

contentHeight
= (safeTop + d) + (H - d) + (bounds - safeTop - H + d)
= bounds + d
```

因此：

```text
maxContentOffset = contentHeight - bounds = d
```

当前 offset 参与 content size 计算，而 content size 又定义 offset 的合法范围。任何瞬时 `d` 都可能
被约束系统固化成新的合法终点；如果 UIScrollView 已回到最终 offset，但约束仍保留旧 `d`，就会出现
截图中的残余空白。

### 为什么顶部行为切换会暴露问题

`.preserveVisualPosition` 会读取并迁移当前 offset，同时 top behavior 切换会触发新的布局 pass。
切换不是根因，但增加了在回弹中读取瞬时 offset、重新写约束并改变 content size 的机会。

### 为什么“滚动结束后再布局”不是完整修复

终态 delegate 回调可以在部分路径中把约束重新对齐最终 offset，却不能消除
`offset → constraint → contentSize → offset` 的反馈环。它可能修复当前截图，但会给后续 Header 折叠、
程序化 offset、v0.5 child 协调和 v0.6 overscroll 留下多个任意稳定点，因此属于架构补丁，不采用。

## 职责边界

### LayoutEngine

`AnchorPagerLayoutEngine` 继续负责纯计算：

- resolved Header expanded/collapsed height
- collapse offset 和 progress
- Header、bar、content 的可见 frame
- managed inset target

其输入/输出继续使用 pager view 的可见坐标，不引入 UIKit layout guide 或第三方分页类型。

### AnchorPagerViewController

主控制器负责：

- 创建稳定且与 offset 无关的主滚动范围
- 把 LayoutEngine 的可见 frame 应用到固定 viewport
- 接收主容器 scroll delegate 回调
- 在程序化 offset 更新时防止回调重入污染布局状态
- 派发 layout context 与 collapse progress

### Header host

`AnchorPagerHeaderViewHost` 只承载 Header 内容、测量 Header，并管理 UIViewController containment。
它接收 viewport 内的 top/height 约束，不读取 content offset，不拥有滚动状态。

### Paging adapter

Tabman/Pageboy adapter 继续只负责横向分页、bar、indicator、selection 事件和横向 page containment。
它被放置在固定 viewport 中，但不参与主滚动范围计算。

### 后续 ScrollCoordinator

本次只建立主容器自身的稳定滚动几何和基础 Header 可见更新。v0.5 的
`AnchorPagerScrollCoordinator` 仍负责：

- 主容器与当前 child scroll view 的 offset 转移
- Header 展开/折叠优先级
- child top boundary
- owner 切换
- 复杂 guarded contentOffset update

本次 delegate 入口和重入保护应允许 v0.5 迁移到 coordinator 或内部 delegate proxy，不改变
Public API。

## 方案比较

### 方案一：固定 viewport 与独立 scroll range

在 `verticalScrollView` 中建立两个互不反向约束的内部层：

1. `scrollRangeView` 约束到 `contentLayoutGuide`，只负责定义 content size。
2. `viewportView` 约束到 `frameLayoutGuide`，只负责承载 Header 和 paging 可视内容。

`scrollRangeView.height` 固定为：

```text
viewportHeight + resolvedHeaderHeight.collapsibleDistance
```

这个值只依赖容器尺寸和 Header 高度范围，不依赖当前 offset。Header 和 paging 使用 LayoutEngine 的
可见 frame 直接布局在 viewport 中，不再执行 `visibleY + contentOffset` 转换。

这是本设计采用的方案。

### 方案二：仅在滚动结束时重新收敛

改动较小，但没有消除 offset/contentSize 反馈闭环，属于症状修复，不采用。

### 方案三：关闭主容器 bounce

只能封闭当前手势入口，程序化 offset 和其他布局 pass 仍可触发相同闭环，不采用。

## 视图与约束结构

目标结构：

```text
AnchorPagerViewController.view
└── verticalScrollView
    ├── scrollRangeView
    │   ├── edges = contentLayoutGuide
    │   ├── width = frameLayoutGuide.width
    │   └── height = frameLayoutGuide.height + collapsibleDistance
    └── viewportView
        ├── edges = frameLayoutGuide
        ├── clipsToBounds = true
        ├── headerViewHost.view
        └── pagingAdapter.view
```

Header host：

- leading/trailing 约束到 `viewportView`
- top 直接使用 `layoutOutput.headerFrame.minY`
- height 使用 `layoutOutput.headerFrame.height`

Paging adapter：

- leading/trailing 约束到 `viewportView`
- top 保持相对 Header bottom 的 gap：
  `barFrame.minY - headerFrame.maxY`
- height 使用 `barFrame.height + contentFrame.height`
- 不再约束到 `scrollRangeView` 或 `contentLayoutGuide`

因此 Header/paging 的可见布局不会参与 content size 反算，scroll range 也不会因 offset 改变。

## 滚动更新设计

### 结构性布局

以下路径继续执行完整测量和环境计算：

- 初次加载与 `reloadData()`
- `reloadHeaderLayout(offsetAdjustment:)`
- `viewDidLayoutSubviews()`
- `viewSafeAreaInsetsDidChange()`

完整布局会缓存最近一次有效 Header 测量高度，计算 LayoutEngine output，更新 scroll range，并应用
viewport 约束。

### 滚动热路径

`scrollViewDidScroll(_:)` 只处理 AnchorPager 自有 `verticalScrollView`：

1. 复用缓存的 Header 测量高度。
2. 读取当前 bounds、obstruction 和 content offset。
3. 调用 LayoutEngine 计算可见 output。
4. 更新 Header top/height、paging top/height。
5. 更新 layout context 和 collapse progress。
6. 不重新测量 Header。
7. 不修改 scroll range，除非结构性输入已经变化并由完整布局处理。
8. 不输出逐帧普通日志。

### 重入保护

`reloadHeaderLayout(offsetAdjustment:)` 可能主动调用 `setContentOffset`，该调用可能同步触发
`scrollViewDidScroll`。主控制器使用 MainActor 隔离的内部布尔状态保护当前布局应用：

```swift
private var isApplyingLayout = false
```

完整布局开始时设为 `true`，结束时通过 `defer` 恢复。滚动回调在该状态下直接返回，由发起方继续完成
同一次 output 应用。不得使用 `nonisolated(unsafe)`、`@unchecked Sendable` 或异步 Task 绕过重入。

## Delegate 与对外状态

`verticalScrollView` 是 AnchorPager 创建和管理的主容器滚动视图，内部 delegate 由框架持有。现有
Public API 没有承诺调用方拥有该 delegate；README、DocC 和 architecture 需明确调用方不得替换。

滚动 output 应用后：

- `didUpdateHeaderCollapseProgress` 只在 progress 实际变化时调用。
- `didUpdateLayout` 只在 `AnchorPagerLayoutContext` 实际变化时调用。
- selection delegate、reloadData 和 Tabman/Pageboy 回调语义不变。

## Gesture 与 Overscroll 边界

本次不实现主容器与 child 的手势 owner 仲裁。`topOverscrollHandlingMode` 默认仍为 `.none`。

负 offset 时 LayoutEngine 将 collapse offset clamp 为 `0`，viewport 中的 Header 保持展开 frame；
scroll indicator 仍可表现 UIKit bounce，但不会再通过 content 坐标把 Header 永久推离安全区域。v0.6
如需 `.container` 或 `.child` 的额外视觉/事件语义，应在独立 overscroll coordinator 中实现。

## 影响范围

### Public API

不新增或删除 public 类型、属性和方法，不改变 top behavior、height mode 或 offset adjustment 枚举语义。
补充 `verticalScrollView.delegate` 由框架管理的文档说明。

### 内部分层

修改 `AnchorPagerViewController` 的内部视图结构和布局应用路径。LayoutEngine 保持纯计算；Header、
Paging、Children、Logging 的职责不扩大。

### UIKit containment 与 lifecycle

Header view controller 继续由 Header host 标准 containment。Paging adapter 仍只被主控制器添加一次，
横向 page containment 仍由 Tabman/Pageboy 执行。移动内部承载父 view 不得引起重复 add/remove child。

### Scroll discovery 与 inset ownership

不改变 child scroll discovery，不写入外部 child contentInset，不提前实现 v0.3 managed inset ownership。
主容器和 fallback host 继续使用 `.never` content inset adjustment。

### Paging adapter

只改变 adapter view 的内部父 view/约束，不修改 adapter API、selection commit/cancel、bar 数据源或
Pageboy containment。

### 并发与资源

UIScrollViewDelegate 和 UIKit 布局都保持 MainActor。新增 delegate 为 weak UIKit 引用，不新增 KVO、
Notification、Task、display link 或 closure observer，不产生额外清理资源。

### 日志

结构性布局继续复用现有：

- `layout.headerHeightResolved`
- `layout.headerFrameChanged`
- `layout.barFrameChanged`
- `layout.safeAreaChanged`
- `layout.boundsChanged`
- `inset.managedTargetChanged`

`scrollViewDidScroll` 不调用结构性日志方法，避免逐帧噪声。本次不新增关键日志事件；collapse progress
和 layout context 已提供可测试状态输出，Header 完全展开/折叠等边界日志继续留给 v0.5。

## 架构停机条件

实施过程中出现以下任一情况，必须停止编码、向用户报告并先修订本设计：

1. `scrollRangeView.height` 仍需读取当前 content offset 才能维持布局。
2. Header/paging 的 viewport 约束仍会参与 UIScrollView content size 反算。
3. 修复要求修改 Tabman/Pageboy adapter 的 containment 职责。
4. 修复要求提前接管 child contentInset 或 child scroll owner。
5. 滚动更新必须依赖未定义的 v0.5/v0.6 状态才能保证正确。
6. 新测试暴露 public API、生命周期、selection 或 safe area 契约与现有文档不一致。
7. 连续三次最小修复尝试失败或每次修复都在不同共享状态产生新问题。

不得通过关闭 bounce、强制 reset offset、额外异步延迟或重复 layout pass 绕过上述问题。

## 测试设计

### 纯几何与滚动范围测试

新增断言：

1. expanded、部分折叠、collapsed 三个 offset 下，content size 高度保持
   `bounds.height + collapsibleDistance`。
2. content size 不随当前 offset 变化。
3. Header 实际 frame 与 LayoutEngine/layout context 一致。
4. paging 可见底部继续等于 `contentFrame.maxY`。

### 问题回归集成测试

完整覆盖：

1. 在导航控制器中安装 pager。
2. 记录 `.insideSafeArea` 初始 Header frame。
3. 切换到 `.extendsUnderTopSafeArea`。
4. 再切换回 `.insideSafeArea`。
5. 模拟负 offset 与回弹到 `0` 的滚动回调。
6. 断言回弹结束后的 Header 顶部等于初始顶部和当前 top obstruction。
7. 断言不存在残余 offset 空白。

测试必须在实现前失败，失败证据应体现 content size 随 offset 变化或 Header 顶部残留过期补偿。

### 滚动状态测试

新增断言：

1. 主容器安装后内部 delegate 已配置。
2. scroll callback 使用缓存测量，不重复产生 `header.measure` 日志。
3. 主动 setContentOffset 期间的回调被重入保护拦截，最终 output 仍正确。
4. collapse progress 只在值变化时通知。
5. 滚动热路径不产生逐帧 layout/inset 普通日志。

### 现有相邻路径回归

继续覆盖：

- 四种 offset adjustment
- 两种 top behavior
- navigation/tab/toolbar/additionalSafeAreaInsets
- Header UIView/UIViewController containment
- fallback host 底部
- 分段栏点击、横向滑动、API 切页
- selection commit/cancel
- public surface 不泄漏 Tabman/Pageboy

### 示例 UI 回归

优先增加相对 frame 测试：记录初始 Header frame，完成两次菜单切换和下拉回弹，等待稳定后断言 Header
顶部回到初始位置。相对比较避免依赖不同模拟器的绝对系统 bar 高度。

如果 XCUITest 无法稳定识别回弹结束时刻，则使用同进程 UIKit 精确几何测试作为替代自动化验证，
并在实施计划与验收记录写明原因；现有菜单 UI test 继续覆盖真实菜单交互。

## 文档同步

实现前先更新本设计和实施计划。实现完成后同步：

- `README.md`
- `docs/architecture.md`
- `docs/task-list.md`
- `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- 本设计的验证与自审结论

文档必须明确 viewport/scroll range 边界、内部 delegate 所有权、滚动热路径日志策略和 v0.5 非目标。

## 验证命令

至少运行：

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test
```

## 完成标准

1. 回归测试先失败后通过。
2. content size 与当前 offset 解耦。
3. 回弹结束后 Header 实际 frame、layout context 和 safe area 一致。
4. Header/paging viewport 约束不参与 scroll range 反算。
5. 滚动热路径不重复测量 Header，不产生逐帧普通日志。
6. 不扩大 Public API，不泄漏 Tabman/Pageboy 类型。
7. Header/page containment、selection、scroll discovery 和 inset ownership 行为不变。
8. 核心测试、示例测试、示例 build 和 `git diff --check` 通过。
9. README、architecture、task-list、v0.2 计划和本设计同步更新。

## 实施记录

- 主容器已使用 `scrollRangeView` 约束 `contentLayoutGuide`，range 高度仅为 viewport 高度加 Header 可折叠距离。
- Header host 与 paging adapter 已移入约束到 `frameLayoutGuide` 的 `viewportView`，不再参与 `contentSize` 反算。
- `visibleY + contentOffset.y` 约束补偿已移除，LayoutEngine 可见坐标直接应用于 viewport。
- 主容器使用私有 weak-owner delegate proxy，未让 public `AnchorPagerViewController` 声明 `UIScrollViewDelegate` conformance。
- 滚动回调复用缓存 Header 测量，只更新可见 output、layout context 和变化后的 collapse progress，不修改 range、不写逐帧普通日志。
- TDD RED：3 个目标测试、3 个失败；失败值分别证明 range 缺失、60pt 残余空白和 progress 未派发。
- TDD GREEN：3 个目标测试通过；`AnchorPagerViewControllerTests` 33 个通过、0 失败。
- Public API 自审追加 RED/GREEN：直接 self-conformance 时 `delegate === pager` 断言失败，改用私有 proxy 后通过。
- Delegate 语义自审追加 RED/GREEN：初次布局错误通知 progress `0` 的断言先失败，改为仅比较既有 output 后通过。
- 示例 UI 回归 `testHeaderReturnsAfterTopBehaviorSwitchAndPullDown` 已通过。
- 完整核心测试 80 个、示例测试 11 个，均 0 失败；示例 generic build、SwiftPM resolve 和 `git diff --check` 通过。
- 最终自审确认未扩大 Public API 或泄漏 Tabman/Pageboy 类型，Header/page containment 与 lifecycle 未变，child scroll/inset/gesture/overscroll 职责未提前实现。私有 delegate proxy 不形成 retain cycle；滚动后强制下一次 `layoutIfNeeded()` 的测试仍未出现 Header 重新测量或普通布局日志。
- 现有依赖会提示 Tabman/Pageboy 的 `PrivacyInfo.xcprivacy` 为 unhandled resource；该上游提示不是本次变更引入，不影响构建和测试结果。
