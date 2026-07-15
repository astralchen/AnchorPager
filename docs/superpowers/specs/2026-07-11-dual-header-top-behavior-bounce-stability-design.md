# Header 双顶部行为、稳定测量与可见回弹设计

> 后续修订：本文记录 v0.2 Header/bounce 稳定契约。本文中的 `managedInsetTarget.top`
> 保持 v0.2 容器级总预留输出，仅用于当时布局与日志回归，不得在 v0.3 直接写入 child。
> v0.3 起 child managed top 只表达 Tabman bar 的局部 obstruction，详细设计见
> `2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md`。
> 2026-07-14 修订：首次没有缓存时使用 required `height == 0` 建立中立布局会与非空 Header 内部约束冲突；当前 bootstrap measurement 规则以
> `2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement-design.md` 为准。

## 背景

AnchorPager v0.2 支持在运行时切换 `AnchorPagerHeaderTopBehavior`：

- `.insideSafeArea`
- `.extendsUnderTopSafeArea`

主容器上一轮将 Header/paging viewport 与 UIScrollView scroll range 解耦，消除了
`contentOffset → 约束 → contentSize → contentOffset` 反馈闭环，但引入了两个回归：

1. `insideSafeArea → extendsUnderTopSafeArea → insideSafeArea` 后，主容器仍可产生负
   `contentOffset`，但 Header、分段栏和页面没有可见 rubber-band 位移。
2. 使用 `layoutMarginsGuide` 或 safe area 的 automatic Header 在切换后下拉并回弹，后续结构布局会把
   顶部遮挡计入 fitting height，导致 Header、分段栏和内容起点整体向下扩张。

本设计保留两个 public 顶部行为，修正其共同几何语义、automatic 测量环境和固定 viewport 的可见
bounce。不得通过关闭 bounce、强制 reset offset、异步延迟、终态重复 layout 或示例专用分支掩盖问题。

## 文档优先级

凡涉及双顶部行为切换、automatic Header 测量、Header/paging viewport 或主容器可见 bounce，本设计
取代已删除的 `2026-07-11-immersive-header-measurement-bounce-design.md` 单一沉浸式方案。

以下文档继续提供基础契约，但与本设计冲突的旧几何或 bounce 描述以本设计为准：

- `docs/requirements.md`
- `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- `docs/superpowers/specs/2026-07-10-header-scroll-settlement-design.md`
- `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- `docs/superpowers/plans/2026-07-10-header-scroll-viewport.md`

## 根因与完整关系

### 当前布局数据流

1. `AnchorPagerHeaderViewHost` 对已经安装并显示的 Header view 调用
   `systemLayoutSizeFitting`。
2. `AnchorPagerViewController` 把结果作为 `measuredHeaderHeight` 传给 LayoutEngine。
3. LayoutEngine 根据 height mode、top behavior、top obstruction 和 offset 生成 Header/bar/content frame。
4. 主控制器把 frame 写入固定于 `frameLayoutGuide` 的 `viewportView`。
5. 独立的 `scrollRangeView` 通过 `contentLayoutGuide` 定义稳定 content size。

### automatic 高度污染

示例 Header 的内容约束到 `layoutMarginsGuide`。UIView 默认让 layout margins 受自身 safe area 影响。
Header 位于容器物理顶部时，自身顶部 safe area 会进入 fitting 计算；如果下一次结构布局直接测量当前
展示位置，top obstruction 会被误当成 Header 内容高度。

污染后的测量结果又成为新的 expanded height，形成：

```text
展示位置的 safe area
  → systemLayoutSizeFitting
  → measuredHeaderHeight
  → Header 约束高度
  → 下一次展示与测量环境
```

这不是 LayoutEngine 高度 clamp 的问题，而是测量值在进入纯计算层之前已经带入了展示环境。

### 可见 bounce 消失

当前约束为：

```text
viewportView.edges = verticalScrollView.frameLayoutGuide.edges
```

因此负 `contentOffset` 只移动 `contentLayoutGuide` 下的 `scrollRangeView`。Header 和 paging 位于固定
viewport，不随 scroll content 产生 presentation 位移。`alwaysBounceVertical` 仍为 `true`，但用户看不到
rubber-band。

### 现有测试漏检

现有同进程回归使用固定返回高度的测试 view，无法暴露 safe-area-sensitive fitting。现有 UI test 只比较
Header 标题最终 `minY`，没有比较分段栏最终 `minY`、Header 高度，也没有覆盖负 offset 期间的实际 frame。

## 设计决策

### 保留 Public API

继续保留：

- `AnchorPagerHeaderTopBehavior`
- `AnchorPagerHeaderConfiguration.topBehavior`
- `.insideSafeArea`
- `.extendsUnderTopSafeArea`

不新增模式、兼容字段或业务回调。

### 纯内容高度模型

LayoutEngine 的 `ResolvedHeaderHeight` 始终表示不包含 top obstruction 的纯内容高度：

```text
expandedContentHeight
collapsedContentHeight
collapsibleDistance = expandedContentHeight - collapsedContentHeight
```

当前 offset 只折叠内容部分：

```text
visibleContentHeight = max(collapsedContentHeight,
                           expandedContentHeight - collapseOffset)
```

top obstruction 不进入 `collapsibleDistance`，避免切换行为或安全区变化产生没有对应内容折叠的额外滚动距离。

### 双顶部行为的统一基线

`.insideSafeArea`：

```text
headerFrame.minY = bounds.minY + topObstruction
headerFrame.height = visibleContentHeight
```

`.extendsUnderTopSafeArea`：

```text
headerFrame.minY = bounds.minY
headerFrame.height = topObstruction + visibleContentHeight
```

两种模式统一满足：

```text
barFrame.minY = bounds.minY + topObstruction + visibleContentHeight
```

因此切换只改变 Header 外框是否延伸到顶部系统区域，不改变分段栏和 child 内容的可见基线。使用 safe area
或 layout margins 的 Header 内容会自动避让；有意忽略 safe area 的内容可绘制到顶部系统区域。

作为 v0.2 容器级历史输出，`managedInsetTarget.top` 继续等于：

```text
topObstruction + expandedContentHeight + barHeight
```

### 中立测量事务

结构性布局必须在与最终 top behavior 无关的中立位置测量 Header：

1. 获取当前 bounds 和本地 top/bottom obstruction。
2. 临时清除 viewport presentation transform。
3. 临时把 Header host 放到 `bounds.minY + topObstruction`。
4. 历史实现使用最近一次有效纯内容高度，首次没有缓存时使用 `0`；该首次 zero-height 规则已被 2026-07-14 bootstrap seed 修订废止。
5. 同步执行内部 layout，使 Header 自身顶部 safe area 在测量时归零。
6. 调用 Header host fitting measurement，得到纯内容高度。
7. 使用纯内容高度、当前 top behavior 和 offset 生成 canonical output。
8. 按 offset adjustment 迁移 offset，并应用最终 canonical 约束和 presentation transform。

临时测量状态不得更新：

- `lastLayoutOutput`
- `AnchorPagerLayoutContext`
- collapse progress delegate
- scroll range
- frame/inset 状态日志缓存

Header UIViewController 的 `preferredContentSize.height` 继续视为纯内容高度。中立测量不得 remove/re-add Header
view，不得破坏 Header view controller containment。

### 结构路径与滚动热路径

执行中立测量的结构路径：

- 初次加载与 `reloadData()`
- `reloadHeaderLayout(offsetAdjustment:)`
- `viewDidLayoutSubviews()`
- `viewSafeAreaInsetsDidChange()`
- 后续尺寸变化恢复入口

滚动热路径继续复用 `lastMeasuredHeaderHeight`：

- 不执行 fitting measurement
- 不修改 scroll range
- 不执行中立测量事务
- 不逐帧输出普通 layout/inset 日志

### 固定 range 与可见 presentation bounce

保留 `scrollRangeView`/`viewportView` 解耦：

```text
scrollRangeHeight = viewportHeight + collapsibleDistance
```

range 不读取当前 offset。负 offset 的可见 bounce 只使用 viewport transform：

```text
overscrollTranslationY = max(0, -verticalScrollView.contentOffset.y)
viewportView.transform = translationY(overscrollTranslationY)
```

规则：

- `contentOffset.y >= 0` 时 transform 为 identity，LayoutEngine 负责内容折叠。
- `contentOffset.y < 0` 时 collapse offset/progress clamp 为 `0`，整个 Header/bar/page viewport 下移。
- UIKit 自身的 bounce 动画驱动 offset 回到 `0`，delegate 逐帧恢复 transform。
- transform 不参与 Auto Layout、content size 或 scroll range 计算。
- 不手工实现弹簧动画，不关闭 `alwaysBounceVertical`。

### Canonical 与 presentation 坐标

LayoutEngine output 和 `lastLayoutOutput` 保存 canonical geometry，不包含 overscroll translation。

`AnchorPagerLayoutContext` 表示 pager view 本地的实际可见坐标；生成 context 时，将同一个
`overscrollTranslationY` 加到 Header/bar/content frame。负 offset 期间实际 view frame 与 layout context
必须一致，offset 回到 `0` 后二者都恢复 canonical geometry。

`reloadHeaderLayout(offsetAdjustment:)` 只能读取 canonical output，不能把瞬时 bounce translation 当成
Header 内容高度或折叠状态。

## 职责边界

### AnchorPagerHeaderViewHost

继续只负责：

- Header UIView/UIViewController 承载
- 标准 UIKit containment
- fitting measurement
- Header top/height 约束入口

它不读取 offset、不计算 safe area obstruction、不修改接入方 Header 的 safe area 或 layout margins。

### AnchorPagerLayoutEngine

继续为纯计算类型，负责：

- height mode 解析
- 纯内容折叠距离和 progress
- 双 top behavior canonical frame
- managed inset target

它不操作 UIKit view、transform、layout guide 或第三方分页类型。

### AnchorPagerViewController

负责：

- 中立测量事务
- 稳定 scroll range
- canonical 约束应用
- viewport presentation transform
- presentation-aware layout context
- guarded contentOffset 更新

### Paging、Children 与后续版本

Tabman/Pageboy adapter 的 selection、indicator 和横向 page containment 不变。本次不提前实现 child managed
inset、page cache/lifecycle、child scroll owner、overscroll owner 或 interaction state machine。

## 影响范围

### Public API

不新增、删除或重命名 public 类型、属性、方法。双 top behavior 语义通过文档澄清为“只改变 Header 外框
是否延伸，分段栏基线保持一致”。

### UIKit containment 与 lifecycle

Header view controller containment 和 paging adapter containment 不变。中立测量只改约束并同步 layout，
不换父 view、不重复 add/remove child。

### Scroll discovery 与 inset ownership

不改变 child scroll discovery，不写入外部 child contentInset。主容器和 fallback host 继续使用 `.never`
automatic inset adjustment。

### Gesture 与 overscroll

只恢复主容器自身负 offset 的 UIKit presentation bounce，不定义 overscroll owner、阈值、事件或业务回调。

### 并发与资源

所有 UIKit 操作继续由 MainActor 隔离。不新增 KVO、Notification、Task、display link 或 observer。现有 weak-owner
delegate proxy 继续使用，不产生 retain cycle。

### 日志

结构性最终 output 继续使用现有 layout/inset 状态变化日志。中立测量临时几何和滚动 transform 不逐帧写
普通日志。本次不新增关键业务事件，因此无需新增日志 category。

## 方案比较

### 方案一：中立测量 + 统一双模式基线 + viewport translation

优点：

- 保留现有 Public API。
- 纯内容高度与 safe area 展示环境解耦。
- 分段栏基线在两种 top behavior 间稳定。
- 保留稳定 range，同时恢复 UIKit 可见 bounce。
- canonical/presentation 边界可延续到 v0.5/v0.6。

代价：结构性布局增加一次同步中立 layout。

采用本方案。

### 方案二：按 top behavior 缓存不同测量高度

需要处理 Dynamic Type、safe area、bounds、内容变化和 Header reload 的缓存失效，仍保留环境污染和状态分叉，
不采用。

### 方案三：把 viewport 放回 contentLayoutGuide

可恢复原生 bounce，但会重新引入 offset/constraint/contentSize 反馈闭环，不采用。

## 测试设计

### LayoutEngine

1. 两种 top behavior 使用相同 bar baseline。
2. extends Header 高度等于 `topObstruction + visibleContentHeight`。
3. top obstruction 不进入 collapsible distance。
4. expanded、partial、collapsed 状态均保持上述关系。
5. v0.2 容器级 managed inset target 保持既有总预留语义；该断言不验证 v0.3 child inset。

### 中立测量集成测试

使用真实 Auto Layout Header，内容约束到 `layoutMarginsGuide`，不 override fitting measurement：

1. 记录 inside 初始 Header 和 bar frame。
2. 切到 extends，再切回 inside。
3. 模拟负 offset 与恢复 `0`。
4. 重复结构 layout/reload。
5. 断言最终 Header 高度、bar `minY`、纯内容高度与初始值一致。
6. 断言 Header view/controller 没有 remove/re-add。

### Bounce 与 range

1. 负 offset 时 Header、bar、paging 实际 frame 和 layout context 同步下移。
2. collapse progress 在负 offset 时保持 `0`。
3. offset 恢复 `0` 后 transform 为 identity，实际 frame/context 恢复 canonical geometry。
4. content size 始终为 viewport height 加纯内容 collapsible distance。
5. 滚动热路径不测量 Header、不修改 range、不写普通 layout/inset 日志。

### 示例 UI 回归

1. 保留 Header 顶部行为菜单和双向切换。
2. 记录初始分段栏 item `minY`。
3. 完成 inside → extends → inside 和真实下拉回弹。
4. 等待稳定后断言分段栏 `minY` 恢复初始值，覆盖截图中的高度增长。

XCUITest 不稳定采样手指仍按下时的中间 frame，因此实时 bounce 位移由同进程 UIKit 集成测试精确覆盖；
UI test 负责真实菜单、拖拽路径和回弹终态。

### 相邻回归

继续覆盖：

- 四种 offset adjustment
- automatic/fixed/ranged height
- navigation/tab/toolbar/additionalSafeAreaInsets
- Header UIView/UIViewController containment
- fallback host
- selection commit/cancel
- Public API 不泄漏 Tabman/Pageboy

## 架构停机条件

出现以下任一情况必须停止编码并先修订设计：

1. 纯内容测量仍依赖最终 top behavior 或 Header 最终 safe area。
2. 中立测量要求 remove/re-add Header view 或破坏 containment。
3. 可见 bounce 要求把 Header/paging 重新约束到 `contentLayoutGuide`。
4. transform 参与 content size 或 range 计算。
5. 修复要求提前接管 child inset、child scroll owner 或 overscroll owner。
6. 两种 top behavior 的 bar baseline 无法保持一致。
7. 连续三次最小实现尝试失败，或每次在不同共享状态产生新问题。

## 文档同步

实现完成后同步：

- `README.md`
- `docs/requirements.md`
- `docs/architecture.md`
- `docs/task-list.md`
- `docs/superpowers/specs/2026-07-10-header-scroll-settlement-design.md`
- `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- `docs/superpowers/plans/2026-07-10-header-scroll-viewport.md`
- 本设计和对应实施计划
- `AGENTS.md` 必读文档/计划索引

## 验证命令

复用当前已启动的 iPhone 17 和固定 DerivedData，不主动 shutdown、reboot 或 clean：

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,id=<booted-device-id>' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,id=<booted-device-id>' -parallel-testing-enabled NO test
```

## 完成标准

1. 回归测试先按预期失败、实现后通过。
2. 双 top behavior Public API 保留。
3. automatic Header 纯内容高度不受当前展示 safe area 污染。
4. 两种 top behavior 的分段栏基线一致。
5. 负 offset 产生 Header/bar/page 可见 UIKit bounce。
6. range 与当前 offset 解耦。
7. 回弹后 Header 高度、bar 位置、实际 frame 和 layout context 恢复初始值。
8. 不改变 Header/page containment、selection、scroll discovery 和 child inset ownership。
9. 核心测试、示例测试、UI 回归、generic build、SwiftPM resolve 和 `git diff --check` 有新鲜证据。
10. 文档、实施记录和代码自审同步完成。

## 实施记录

- Public API 保留 `AnchorPagerHeaderTopBehavior` 和两个现有 case，没有新增兼容状态。
- LayoutEngine 已将 resolved height 固定为纯内容高度；extends frame 使用“顶部遮挡 + 可见内容高度”，两种模式共享 bar/content baseline。
- 结构性布局先清除 transform，把 Header host 放到顶部遮挡下方并同步 layout，再执行 fitting measurement；临时几何不更新 range、context、progress 或状态日志缓存。
- 固定 `scrollRangeView`/`viewportView` 架构继续保留；负 offset 只通过 viewport presentation translation 恢复可见 bounce。
- `lastLayoutOutput` 与结构日志保持 canonical geometry；`AnchorPagerLayoutContext` 在 bounce 期间包含实际 translation。
- TDD RED：LayoutEngine 10 个测试中 6 个预期几何失败；负 offset 同进程测试实际 Header `minY` 为 `62`、预期 `86`；强化后的真实示例 UI test 因分段栏无法返回初始 `minY` 超时失败。
- TDD GREEN：LayoutEngine 定向测试、两个 Task 2 目标测试、35 个控制器测试和真实示例 UI 回归均已通过。
- 最终完整核心测试 83/83、完整示例测试 11/11、generic build 和 SwiftPM resolve 已通过；命令、首次旧示例断言失败及最终自审记录在对应实施计划中。

## 2026-07-14 首次 Bootstrap Measurement 修订

后续用户启动日志证明：首次 automatic Header 没有 `lastMeasuredHeaderHeight` 时，旧步骤把 host required height 设为 `0` 再同步 layout；示例标题栈的 safe-area top/bottom 内容约束因此不可满足。该问题不改变“最终 top behavior 无关的中立位置测量”原则，只废止首次 required zero-height seed。

修订后的首次路径让测量缓存只属于当前 Header 内容身份，身份替换先使旧缓存失效，再对当前内容执行一次不发布状态的 compressed fitting，得到 finite、nonnegative bootstrap seed；随后以 seed 建立 required host height、同步中立 layout，再执行正式 fitting。只有正式结果更新测量缓存、canonical output 和既有日志；bootstrap 不更新 context、progress、range、inset 或 frame 日志。实现提交为 `dfabd6c`，完整验收与整分支 fresh-pass 复审已在生产代码 HEAD `c37e829` 通过；详细关系、RED/GREEN 和清理证据见 2026-07-14 专项设计，关联的 v0.5/v0.6 当前为 Ready。
