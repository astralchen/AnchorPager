# Header 单一沉浸式模型、稳定测量与 Bounce 设计

## 背景

AnchorPager v0.2 当前公开 `AnchorPagerHeaderTopBehavior`，允许在
`.insideSafeArea` 与 `.extendsUnderTopSafeArea` 之间切换。主容器上一轮将
Header/paging viewport 与 UIScrollView scroll range 解耦，修复了
`contentOffset → constraint → contentSize → contentOffset` 反馈闭环，但随后暴露两个新问题：

1. 从 inside 切到 extends、再切回 inside 后，下拉并松手会让 automatic Header 高度增大；
   Header 顶部位置正确，但蓝色 Header、分段栏和内容起点整体向下扩张。
2. `viewportView` 固定到 `frameLayoutGuide` 后，负 `contentOffset` 仍存在，但 Header、分段栏和页面
   不再随 UIScrollView rubber-band 产生可见 bounce。

用户最终确认不再保留两套顶部行为，直接移除 `AnchorPagerHeaderTopBehavior`，统一使用单一沉浸式模型：

- Header 外框从容器物理顶部开始布局。
- Header 内容自行通过 `safeAreaLayoutGuide`、`layoutMarginsGuide` 或其他 UIKit 约束决定是否避让。
- 框架不强制修改接入方 Header 内容约束，也不提供顶部行为切换状态。

本设计是 Public API 和布局语义的架构修订，不通过关闭 bounce、强制 reset offset、异步延迟或重复终态
layout 补丁掩盖问题。

## 文档优先级

本设计已经用户确认。凡涉及 `AnchorPagerHeaderTopBehavior`、Header 顶部几何、automatic Header 测量、
主容器负 offset presentation 或 bounce 的内容，本设计取代以下文档中的旧方案：

- `docs/requirements.md` 当前双 top behavior 契约
- `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md` 的 v0.2 双行为范围
- `docs/superpowers/specs/2026-07-10-header-scroll-settlement-design.md` 中固定 viewport 不产生可见 bounce 的假设
- `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md` 和
  `docs/superpowers/plans/2026-07-10-header-scroll-viewport.md` 的相关历史实施步骤

这些旧记录在实现阶段保留为历史证据，但必须明确标注已被本设计取代，不能继续作为当前实现契约。

## 根因与关系梳理

### 当前 Header 高度数据流

当前数据依次经过：

1. `AnchorPagerHeaderViewHost` 在已安装的 Header view 上调用 `systemLayoutSizeFitting`。
2. `AnchorPagerViewController` 把测量结果作为 `measuredHeaderHeight` 交给 LayoutEngine。
3. LayoutEngine 根据 height mode、top behavior、top obstruction 和 offset 生成 Header/bar/content frame。
4. 主控制器把 frame 写入固定 viewport 的 Header/paging 约束。
5. 后续 `viewDidLayoutSubviews`、safe area 变化或显式 `reloadHeaderLayout` 可能再次测量已经处于新几何中的
   Header view。

### 高度增大的直接原因

示例 Header 使用 `layoutMarginsGuide` 布局内容。UIView 默认会让 layout margins 受 safe area 影响：

- Header 位于 top obstruction 下方时，Header 自身的顶部 safe area 接近 `0`。
- Header 位于物理顶部时，Header 自身会收到顶部 safe area，内部 layout margins 随之增大。

当前测量直接发生在展示中的 Header view 上，因此测量结果会混入 Header 当前展示位置带来的 safe area。
随后 LayoutEngine 又把该结果当成纯 Header 内容高度，导致 top obstruction 同时进入“展示外框”和
“可折叠内容高度”。当布局在不同顶部环境之间切换或回弹触发后续结构布局时，污染后的测量值会成为新的
expanded height，表现为 Header 高度增大。

### Bounce 消失的直接原因

上一轮架构把：

```text
viewportView.edges = verticalScrollView.frameLayoutGuide.edges
```

因此 UIScrollView 的负 `contentOffset` 只作用于 `contentLayoutGuide` 下的 `scrollRangeView`。Header 和
paging 位于固定 viewport，不跟随 scroll content 移动。`alwaysBounceVertical` 虽然仍为 `true`，用户看到的
内容却没有 presentation 位移，所以视觉 bounce 消失。

### 当前顶部行为抽象的问题

现有 `.extendsUnderTopSafeArea` 使用：

```text
visibleHeaderHeight = max(rawHeaderContentHeight, topObstruction)
```

这无法准确表达“外框从物理顶部开始，内容通过 safe area 避让”的沉浸式语义。正确模型需要明确区分：

- 纯 Header 内容高度
- 顶部 obstruction/underlay 高度
- Header 最终可见外框高度
- 内容可折叠距离

删除 `AnchorPagerHeaderTopBehavior` 后，框架只保留一个模型，避免两套环境、运行时迁移和测量语义继续互相
污染。

## 最终设计决策

### Public API 收缩

直接删除，不保留 deprecated 兼容层：

- `AnchorPagerHeaderTopBehavior`
- `AnchorPagerHeaderConfiguration.topBehavior`
- `AnchorPagerHeaderConfiguration.init(..., topBehavior:)` 参数

新的 Header 配置只保留高度模式：

```swift
public struct AnchorPagerHeaderConfiguration: Sendable, Equatable {
    public var heightMode: AnchorPagerHeaderHeightMode

    public init(
        heightMode: AnchorPagerHeaderHeightMode = .automatic(min: 0, max: nil)
    )
}
```

这是有意的破坏性变更。AnchorPager 尚未进入 v1.0 API 冻结阶段，不保留一个已确认会增加错误状态和维护
成本的兼容抽象。

### 单一沉浸式几何

LayoutEngine 中 resolved height 始终只表示纯内容高度：

```text
expandedContentHeight
collapsedContentHeight
collapsibleDistance = expandedContentHeight - collapsedContentHeight
```

当前 offset 对纯内容高度执行折叠：

```text
visibleContentHeight = max(collapsedContentHeight, expandedContentHeight - collapseOffset)
```

最终可见几何固定为：

```text
headerFrame.minY  = bounds.minY
headerFrame.height = topObstruction + visibleContentHeight
barFrame.minY = headerFrame.maxY
contentFrame.minY = barFrame.maxY
```

因此：

- Header 外框始终从容器物理顶部开始。
- Header view 在最终展示状态会收到 UIKit 计算出的顶部 safe area。
- 使用 safe area/layout margins 的 Header 内容会自动避让。
- 忽略 safe area 的 Header 内容可以有意绘制到顶部系统区域。
- top obstruction 不进入 `collapsibleDistance`，不会产生没有视觉变化的额外滚动距离。
- `managedInsetTarget.top` 继续等于
  `topObstruction + expandedContentHeight + barHeight`。

### 中立测量几何

automatic Header 的测量必须与最终展示位置解耦。结构性布局使用以下两阶段事务：

1. 读取新的 bounds 和 top/bottom obstruction。
2. 使用上次有效内容高度；首次没有缓存时使用 `0` 作为 provisional seed。
3. 临时把 Header host 放到 `bounds.minY + topObstruction`，高度使用 seed content height。
4. 同步执行一次内部 layout，使 Header view 的顶部 safe area 在测量时归零。
5. 调用 `AnchorPagerHeaderViewHost.measure(in:)`，得到纯内容高度。
6. 使用纯内容高度和当前 offset 生成最终沉浸式 LayoutEngine output。
7. 按 offset adjustment 迁移 offset，再应用最终 Header/bar/paging 几何和 scroll range。

provisional 约束只用于同一布局事务内的测量环境，不更新：

- `lastLayoutOutput`
- `AnchorPagerLayoutContext`
- collapse progress delegate
- 结构日志缓存
- scroll range

最终约束在当前 run loop 提交前覆盖 provisional 约束，不产生用户可见闪动。

Header UIViewController 的 `preferredContentSize.height` 继续视为纯内容高度。无效测量继续使用现有断言、错误
日志和降级规则。

### 结构路径与滚动热路径

执行中立测量的结构路径：

- 初次加载和 `reloadData()`
- `reloadHeaderLayout(offsetAdjustment:)`
- `viewDidLayoutSubviews()`
- `viewSafeAreaInsetsDidChange()`
- 后续尺寸变化恢复入口

滚动热路径继续复用 `lastMeasuredHeaderHeight`：

- 不调用 Header fitting measurement
- 不修改 scroll range
- 不执行 provisional layout
- 不输出逐帧普通日志

### 可见 Bounce

保留现有 `scrollRangeView`/`viewportView` 解耦结构。scroll range 仍只由：

```text
viewportHeight + collapsibleDistance
```

决定，不读取当前 offset。

负 offset 的可见 bounce 使用 presentation translation：

```text
overscrollTranslationY = max(0, -verticalScrollView.contentOffset.y)
viewportView.transform = translationY(overscrollTranslationY)
```

规则：

- `contentOffset.y >= 0` 时 transform 为 identity，LayoutEngine 负责 Header 折叠。
- `contentOffset.y < 0` 时 collapse offset/progress clamp 为 `0`，Header 保持展开模型；Header、bar、paging
  作为整个 viewport 一起下移。
- UIKit 回弹把 offset 动画恢复到 `0` 时，delegate 逐帧把 transform 恢复到 identity。
- transform 不参与 Auto Layout 和 `contentSize` 计算，不会重新引入旧反馈闭环。
- 不关闭 `alwaysBounceVertical`，不手工实现弹簧动画。

### Layout Context 语义

`AnchorPagerLayoutContext` 继续表示 pager view 本地的实际可见坐标。

- LayoutEngine output 保持 canonical geometry，不包含临时 bounce translation。
- 生成 public layout context 时，把 `overscrollTranslationY` 同步加到 Header/bar/content frame。
- 实际 Header host frame、paging adapter frame 与 layout context 在负 offset 和回弹结束后都必须一致。
- collapse progress 基于 canonical content collapse，负 offset 时保持 `0`。

`lastLayoutOutput` 保存 canonical output，避免瞬时 presentation translation 污染
`reloadHeaderLayout(offsetAdjustment:)` 的状态迁移。

## 视图职责

### AnchorPagerHeaderViewHost

继续只负责：

- Header UIView/UIViewController 承载
- 标准 UIViewController containment
- Header 内容 fitting measurement
- Header top/height 约束入口

它不读取 offset、不计算 obstruction、不修改接入方 Header 的 safe area、layout margins 或内部约束。

### AnchorPagerViewController

负责：

- 创建中立测量几何
- 调用 Header host 测量
- 调用 LayoutEngine 生成单一沉浸式 output
- 维护稳定 scroll range
- 应用 viewport canonical 约束和 bounce transform
- 派发 presentation-aware layout context 与 collapse progress

### AnchorPagerLayoutEngine

继续是纯计算类型，只处理：

- content height mode 解析
- content collapse offset/progress
- 单一沉浸式 Header/bar/content canonical frame
- managed inset target

它不引入 UIKit safe area guide、transform、measurement 或第三方分页类型。

### Paging adapter 与后续版本

Tabman/Pageboy adapter 只跟随 viewport，selection、indicator、horizontal containment 和 adapter API 不变。

本次不提前实现：

- v0.3 child managed inset ownership
- v0.4 page lifecycle/cache window
- v0.5 child scroll owner/handoff
- v0.6 overscroll mode/owner
- v0.7 interaction state machine

当前负 offset presentation 只恢复主容器自身的 UIKit bounce，不定义 top overscroll owner 或业务事件。

## 方案比较

### 方案一：单一沉浸式模型 + 中立测量 + viewport translation

优点：

- 消除顶部行为状态和迁移分支。
- 纯内容高度与 safe area underlay 分离。
- 保留稳定 scroll range，同时恢复可见 bounce。
- 允许 Header 内容按标准 UIKit safe area 自主布局。
- 为 v0.5/v0.6 保留稳定 canonical/presentation 边界。

代价：

- Public API 有意收缩。
- 结构性测量增加一次同步 provisional layout。

采用本方案。

### 方案二：保留顶部行为并缓存每种模式的测量值

可以减少往返污染，但仍保留两套状态、缓存失效和运行时迁移；首次加载、动态内容、safe area 变化和
Dynamic Type 都需要额外一致性规则。不采用。

### 方案三：把 viewport 放回 scroll content

可以恢复原生 bounce，但会重新引入 Header/paging 约束参与 content size 反算的问题。不采用。

### 方案四：只修改示例 Header 或关闭 safe-area-adjusted margins

只能隐藏当前示例现象，会改变接入方 Header 内容语义，也无法修复其他使用 safe area 的 Header 和 bounce
回归。不采用。

## 影响范围

### Public API

- 删除 `AnchorPagerHeaderTopBehavior`。
- 删除 `AnchorPagerHeaderConfiguration.topBehavior` 和对应 initializer 参数。
- 不新增替代 public 开关。
- `AnchorPagerHeaderHeightMode`、`AnchorPagerHeaderOffsetAdjustment` 和 layout context 类型保留。

### 内部分层

- LayoutEngine 从双 top behavior 分支收敛为单一沉浸式公式。
- ViewController 增加中立测量事务和 presentation translation。
- Header host、Paging、Children、Logging 职责不扩大。

### UIKit containment 与 lifecycle

- Header UIViewController 的 add/remove/didMove/willMove 顺序不变。
- Header 内容不因测量被 remove/re-add 或换父 view。
- Paging adapter 仍只由主控制器 addChild 一次。
- 横向 page containment 仍由 Tabman/Pageboy 执行。

### Scroll discovery 与 inset ownership

- 不改变 child scroll discovery。
- 不写入外部 child contentInset。
- 主容器和 fallback host 继续使用 `.never` automatic inset adjustment。
- managed inset target 继续保留给 v0.3。

### Gesture 与 overscroll

- 只恢复主容器负 offset 的视觉 rubber-band。
- 不定义 overscroll owner、阈值、事件或业务回调。
- 后续 coordinator 可以消费 canonical offset/presentation translation，不需要推翻 scroll range。

### 并发与资源

- 所有 UIKit 操作继续由 MainActor 隔离。
- 不新增 KVO、Notification、Task、display link 或 closure observer。
- transform 由现有私有 UIScrollViewDelegate proxy 驱动，不新增 retain cycle。

### 日志

- 结构性最终 output 继续使用现有 layout/inset 状态变化日志。
- provisional measurement 不写 frame/inset 状态日志。
- 滚动 transform 不逐帧写普通日志。
- 本次不新增关键日志事件；v0.5/v0.6 再记录 owner 和阈值事件。

### 示例工程

- 删除 Header 顶部行为菜单、按钮状态和相关单元/UI 测试。
- 保留导航 push 按钮。
- 示例 Header 继续使用 layout margins，作为内容通过 safe area 避让的真实样例。
- 新增单一沉浸式 Header 初始几何、重复布局稳定性和回弹后高度稳定 UI 回归。

### 文档

实施时同步更新：

- `README.md`
- `docs/requirements.md`
- `docs/architecture.md`
- `docs/task-list.md`
- `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- `docs/superpowers/specs/2026-07-10-header-scroll-settlement-design.md`
- `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- `docs/superpowers/plans/2026-07-10-header-scroll-viewport.md`
- 本设计与对应实施计划

历史文档中的双行为方案必须明确标为已废止，不能保留为当前推荐方案。

## 测试设计

### Public API 与编译契约

1. Public source scan 不再出现 `AnchorPagerHeaderTopBehavior` 或 `topBehavior`。
2. `AnchorPagerHeaderConfiguration` 只通过 height mode 初始化和比较。
3. 示例工程不引用被删除类型或属性。

### LayoutEngine 纯计算

1. Header `minY == bounds.minY`。
2. Header height 等于 `topObstruction + visibleContentHeight`。
3. bar 紧跟 Header bottom。
4. collapsible distance 不包含 top obstruction。
5. offset 从 expanded 到 collapsed 只减少内容部分高度。
6. managed inset target 保持 `topObstruction + expandedContentHeight + barHeight`。

### 中立测量集成测试

使用真实 Auto Layout Header，内部内容约束到 `layoutMarginsGuide`，不 override fitting measurement：

1. 在 UINavigationController 中记录纯内容测量和最终沉浸式 frame。
2. 重复 `viewDidLayoutSubviews`/`reloadHeaderLayout` 后内容高度不增加。
3. navigation bar 或 safe area 变化时，最终 Header frame 只按 obstruction 差值变化。
4. obstruction 恢复后 Header frame 恢复初始值。
5. Header view/controller 不被 remove/re-add。

### Bounce 与范围测试

1. content size 始终为 viewport height 加 content collapsible distance。
2. `contentOffset.y = -24` 时 Header、bar、paging 和 layout context 均向下移动 `24`。
3. collapse progress 在负 offset 时为 `0`。
4. offset 恢复 `0` 后 transform 为 identity，实际 frame 和 context 恢复 canonical geometry。
5. 滚动热路径不调用 `header.measure`，不修改 scroll range，不写普通 layout/inset 日志。

### Offset adjustment 与相邻路径

继续覆盖：

- `.preserveVisualPosition`
- `.preserveCollapseProgress`
- `.resetToExpanded`
- `.resetToCollapsed`
- automatic/fixed/ranged height
- navigation/tab/toolbar/additionalSafeAreaInsets
- Header UIView/UIViewController containment
- selection commit/cancel
- fallback host
- Public API 不泄漏 Tabman/Pageboy

### 示例 UI 回归

1. 首屏不存在 Header 顶部行为菜单。
2. Header 背景从容器物理顶部开始，Header 内容仍通过 safe area 显示在系统栏下方。
3. 记录初始分段栏 `minY`，下拉并等待回弹后再次比较，确认 Header 高度没有增加。
4. 现有分段栏点击、横滑、public API 切页、push/hidesBottomBar 测试继续通过。

XCUITest 难以稳定采样手指仍按下时的中间 frame，因此实时 bounce 位移由同进程 UIKit 集成测试精确覆盖；
UI test 覆盖真实下拉路径和回弹终态。

## 错误处理与边界

- 首次没有缓存高度时，provisional content height 使用 `0`；沉浸式 Header 仍至少覆盖 top obstruction。
- automatic measurement 为负数或非有限值时继续断言、记录 `header.measure.invalid` 并降级为 `0`。
- top obstruction 为非有限或负数时继续归零。
- Header 内容忽略 safe area 时允许绘制到系统区域，这是单一沉浸式 public 契约，不由框架修正。
- Header 内容使用 safe area/layout margins 时，框架不得把 safe area 再加入纯内容测量。
- transform 必须在 offset 回到非负时恢复 identity，避免复用旧 overscroll translation。

## 架构停机条件

实施过程中出现以下任一情况必须停止编码并先报告用户：

1. 纯内容测量仍依赖 Header 最终沉浸式 safe area。
2. 测量要求临时 remove/re-add Header view 或破坏 UIViewController containment。
3. bounce 要求把 Header/paging 重新约束到 `contentLayoutGuide`。
4. bounce transform 参与 content size 或 scroll range 计算。
5. 修复要求提前实现 child scroll owner、child inset 或 overscroll owner。
6. 删除 Public API 后仍存在内部双 top behavior 状态或兼容分支。
7. 连续三次最小实现尝试失败，或每次修复都在不同共享状态产生新问题。

不得通过示例专用处理、关闭 safe area margins、关闭 bounce、强制 reset offset、异步延迟或终态重复 layout
绕过上述条件。

## 验证命令

至少运行：

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test
```

Simulator 验证复用已启动设备和固定 DerivedData，除非没有可用 Booted 设备或必须执行一次独立 clean
验收，不主动 shutdown/reboot Simulator。

## 完成标准

1. `AnchorPagerHeaderTopBehavior` 和 `topBehavior` 从 Public API、示例和当前文档契约中删除。
2. Header 外框始终从容器物理顶部开始。
3. 使用 safe area/layout margins 的 Header 内容正确避让系统区域。
4. 纯内容测量不包含 top obstruction，重复结构布局不会增长 Header 高度。
5. Header frame 高度等于 top obstruction 加当前可见内容高度。
6. collapsible distance 和 scroll range 不包含 top obstruction 的额外死区。
7. 负 offset 时 Header、bar、paging 和 layout context 同步产生可见 bounce。
8. 回弹结束后 transform、实际 frame、layout context 和 Header 高度恢复稳定。
9. scroll range 继续与当前 offset 解耦。
10. 不扩大其他 Public API，不改变 containment、selection、scroll discovery 或 child inset ownership。
11. 核心测试、示例测试、示例 build、SwiftPM resolve 和 `git diff --check` 通过。
12. 所有长期文档、设计、计划、任务状态和验收记录同步更新。
