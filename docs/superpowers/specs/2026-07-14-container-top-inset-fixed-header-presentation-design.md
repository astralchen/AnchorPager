# 主容器顶部 Inset 与固定高度 Header Presentation 设计

**日期：** 2026-07-14

**状态：** 设计、TDD 实现与首轮全量验收已完成；最终实现者自审、fresh-pass 复审和最终 HEAD 全量复验待完成，v0.5/v0.6 Ready 继续关闭

**适用范围：** `AnchorPagerHeaderTopBehavior`、主容器顶部 inset、Header 固定高度呈现、正常折叠、bar 吸顶、纵向 handoff、双边界 bounce、运行时顶部行为切换与安全区变化。

## 背景与根因

当前实现采用“主容器 inset 恒为零、safe area 转换为 LayoutEngine obstruction”的坐标模型：

```text
container expanded raw offset = 0
container collapsed raw offset = collapsibleDistance
verticalScrollView.contentInset.top = 0
```

LayoutEngine 在稳定区间内固定 Header 顶边并持续缩小 Header host 高度；paging adapter 的 top 跟随缩小后的 Header bottom。该模型可以保持 bar baseline，但产生两个已经由用户确认需要修正的语义问题：

1. `.insideSafeArea` 与 `.extendsUnderTopSafeArea` 没有通过主容器真实顶部 inset 表达，`verticalScrollView` 的原生展开边界与配置语义不一致。
2. Header 业务 UIView/UIViewController 的根视图高度随折叠量持续缩小。业务内容约束、safe area 和布局回调因此处于变化中的小高度容器，而需求是保持完整 Header 高度，只让 Header 随正常折叠向上移动并由固定 viewport 裁剪。

只把 `.insideSafeArea` 的 `contentInset.top` 改为 safe area 高度并不能闭合问题。UIKit 的 raw offset 边界、content size、ScrollCoordinator canonical distance、OverscrollCoordinator boundary、LayoutContext 和运行时迁移都依赖同一坐标原点；若仍把 `0...collapsibleDistance` 当作 raw 稳定区间，inside 模式会额外多滚一个顶部 inset。

本设计把“主容器原生物理坐标”和“AnchorPager 逻辑折叠坐标”显式分离，并把正常折叠改为固定高度内容层的 presentation。

## 已确认语义

1. 保留 public `AnchorPagerHeaderTopBehavior` 及现有两个 case。
2. `AnchorPagerHeaderTopBehavior` 只决定 Header 顶部坐标系与主容器顶部 inset，不再决定 Header 是否在滚动热路径缩高。
3. `.insideSafeArea`：`verticalScrollView.contentInset.top` 等于当前本地顶部安全区遮挡。
4. `.extendsUnderTopSafeArea`：`verticalScrollView.contentInset.top == 0`。
5. Header 业务根视图在正常滚动中保持完整解析高度；正常折叠通过内部 presentation surface 向上移动，超出屏幕的部分由固定 viewport 裁剪。
6. 正常折叠量、非零 collapsed Header、bar 吸顶位置和 container/child handoff 保留；只有超出稳定边界的部分进入原生 bounce。
7. 主容器顶部 inset 与业务 child managed inset 是两套独立 ownership。顶部 safe area 不写入 child `contentInset.top`。

## 目标

1. 让两种 Header 顶部行为与 `verticalScrollView` 的真实 UIKit inset/offset 边界一致。
2. 统一所有稳定滚动、handoff、overscroll 与迁移路径使用逻辑 container offset，禁止各层自行重复加减 inset。
3. Header host 在滚动热路径保持固定高度；bar 与 paging viewport 继续正常折叠和吸顶。
4. 保留现有 container top、plain bottom page surface、真实 child top/bottom 三类原生 bounce owner 与可见 presentation 分层。
5. 顶部行为切换、安全区变化、Header 高度变化、reload、切页和尺寸变化不产生折叠量跳变或双 offset writer。
6. 不扩大 Public API，不改变 Tabman/Pageboy containment，不修改业务 child 的 delegate、pan delegate、滚动开关或 bounce 配置。

## 非目标

1. 不新增自定义 safe-area 数值或公开 container inset 配置。
2. 不改变 `AnchorPagerHeaderHeightMode` 对纯内容 expanded/collapsed height 的解析规则。
3. 不实现自定义 rubber-band 曲线、跨 owner velocity 合成或 v0.7 完整 interaction state。
4. 不把主容器顶部 inset 合并进 child managed inset coordinator。
5. 不恢复 plain page synthetic scroll wrapper，不直接修改业务 page 根 view transform。
6. 不通过异步 delay、重复 layout、强制 reset 或临时关闭 bounce 掩盖结构性坐标问题。

## 方案比较

### 采用：真实 container inset + 逻辑 offset + 固定高度 canonical content surface

主容器保留 UIKit 原生 inset/bounce 物理；纯内部几何值统一完成 raw/logical 转换。固定 viewport 内新增 canonical content presentation surface，HeaderHost 与 PagingHost 按展开几何排列，正常折叠只移动该 surface。

该方案同时满足真实 inset、固定 Header 高度、固定 Pageboy viewport、bar 吸顶和现有 bounce presentation 分层。

### 不采用：保留 obstruction-only 坐标并只视觉补 safe area

该方案无法让 `verticalScrollView` 的展开边界、原生 bounce 和 `AnchorPagerHeaderTopBehavior` 语义一致，也会继续让外部调试看到 inside/extends 使用相同 raw offset 原点。

### 不采用：设置真实 inset但继续缩小 Header host

该方案只修正 offset 原点，没有解决用户确认的业务 Header 高度变化问题；safe-area 内容和约束仍会在滚动热路径进入越来越小的根视图。

### 不采用：逐帧移动 Header/Paging Auto Layout 约束

逐帧修改真实布局 frame 会让业务 Header safe area 和内部约束持续重算，并重新引入测量、约束与 paging bounds 反馈风险。正常折叠应只更新 AnchorPager 自有 presentation surface，不修改业务根 view transform。

## 坐标模型

定义：

```text
T = 当前本地顶部安全区遮挡，finite 且 >= 0
E = resolved expanded Header 纯内容高度
C = resolved collapsed Header 纯内容高度
D = collapsibleDistance = max(0, E - C)
H = verticalScrollView viewport height
I = containerTopInset
```

顶部行为决定：

```text
insideSafeArea:          I = T
extendsUnderTopSafeArea: I = 0
```

`verticalScrollView.contentInsetAdjustmentBehavior` 继续固定为 `.never`，因此框架拥有的 `contentInset.top` 与 `adjustedContentInset.top` 在没有外部非法改写时均为 `I`。

主容器 `contentInset.left/bottom/right` 继续由框架保持为 `0`；本设计不提供外部主容器 inset 合并语义。调用方不能把公开只读 scroll view 引用解释为 inset ownership 授权。

raw 与逻辑 offset 的唯一转换为：

```text
logicalOffsetY = rawContentOffsetY + I
rawContentOffsetY = logicalOffsetY - I
```

所有 LayoutEngine、ScrollCoordinator、OverscrollCoordinator 与结构性迁移判断必须消费逻辑 offset：

```text
expanded logical boundary  = 0
collapsed logical boundary = D
stable collapse offset     = clamp(logicalOffsetY, 0...D)
top overflow               = max(0, -logicalOffsetY)
bottom overflow            = max(0, logicalOffsetY - D)
```

对应 raw 边界：

```text
expanded raw boundary  = -I
collapsed raw boundary = D - I
```

不得在 ViewController、ScrollCoordinator 和 OverscrollCoordinator 中分别散落 `+ contentInset.top`。实现应建立单一纯值 container geometry/conversion 类型，由 ScrollCoordinator 保持唯一 UIKit offset 写入职责。

## 主容器 Scroll Range

UIKit 的纵向 raw 最大稳定 offset 由 content size、bounds 和 bottom inset 决定。为让 raw 稳定区间恰好从 `-I` 到 `D - I`，主容器内容高度必须为：

```text
scrollRangeHeight = max(0, H + D - I)
```

当 `D == 0` 时，inside 模式得到同一个 raw 展开/折叠边界 `-I`，不会凭空增加一段 safe-area 滚动距离。`alwaysBounceVertical` 继续允许边界原生 bounce。

`scrollRangeView` 仍只定义主容器原生物理范围，不承载 Header、bar 或页面可见布局；`viewportView` 继续绑定 `frameLayoutGuide` 并覆盖物理屏幕内容区域。

## 固定高度 Header 与 Presentation 分层

目标层级：

```text
AnchorPagerContainerScrollView
├─ scrollRangeView                         contentLayoutGuide，只有物理范围
└─ viewportView                            frameLayoutGuide，固定裁剪区域
   └─ canonicalContentPresentationView     正常折叠 presentation
      ├─ AnchorPagerHeaderViewHost          完整高度
      └─ AnchorPagerPagingHostViewController
          ├─ Tabman bar
          └─ Pageboy page surface
```

`viewportView` 保持屏幕固定裁剪层。`canonicalContentPresentationView` 使用展开态 canonical 几何，只应用正常折叠位移：

```text
canonicalContentTranslationY = -stableCollapseOffset
```

`canonicalContentPresentationView` 自身不裁剪，允许固定高度 PagingHost 在 Header 展开时向 viewport 底部外延；唯一屏幕裁剪边界仍是静止的 `viewportView`。不得把正常折叠 transform 施加到 `viewportView`，否则其裁剪底边会随折叠上移并再次破坏 plain page 的物理屏幕底边。

两种顶部行为的 Header 展开布局为：

```text
insideSafeArea:
    headerCanonicalMinY  = T
    headerCanonicalHeight = E

extendsUnderTopSafeArea:
    headerCanonicalMinY  = 0
    headerCanonicalHeight = T + E
```

正常折叠中 HeaderHost 高度保持上述完整高度，只随 canonical content surface 上移。Header 呈现底边和 bar baseline 在两种模式下都为：

```text
barBaselineY = T + E - stableCollapseOffset
```

完全折叠时：

```text
barBaselineY = T + C
```

因此 `C == 0` 时 bar 吸附到顶部安全区边界；`C > 0` 时保留 collapsed Header，并让 bar 吸附到其下方。顶部行为切换不会改变 bar baseline，只改变 Header 背景是否覆盖顶部系统区域。

PagingHost 继续使用完全折叠态的固定最大 viewport 高度。它在 canonical surface 内位于展开 Header 下方，并随同一 presentation 上移；普通折叠不得改变 Pageboy child bounds。

业务 Header UIView/UIViewController 根 view 继续四边约束到 HeaderHost。AnchorPager 不直接修改业务 Header 根 view 的 transform；只修改自有 canonical presentation surface。业务 Header 的正式 measurement、identity cache、bootstrap seed 与 UIViewController containment 顺序保持不变。

## Bounce Presentation 组合

正常折叠与边界 overflow 使用不同 presentation 层：

1. **稳定折叠：** `canonicalContentPresentationView` 上移 `stableCollapseOffset`。
2. **container 顶部 owner：** `viewportView` 额外下移 `topOverflow`，Header/bar/page 共同使用 UIKit 原生顶部 bounce。
3. **plain page container 底部 owner：** viewport 与 chrome 保持 collapsed canonical；只有 Paging adapter 内 Pageboy 页面 surface 上移 `bottomOverflow`。
4. **真实 child 顶部/底部 owner：** container presentation 保持 canonical，只有业务 child `UIScrollView` 产生原生内容回弹。
5. **`.none` 或不可用 `.child` 顶部 owner：** 非 owner 通过现有 guarded stable write 回到逻辑 expanded boundary，对应 raw offset `-I`。

presentation 合成不得把 overflow 写入 LayoutEngine canonical output、scroll range、PageState snapshot、managed inset 或 Header measurement cache。

## ScrollCoordinator 与 OverscrollCoordinator

ScrollCoordinator 继续是协调期 raw `contentOffset` 的唯一写入者，但其 resolver 输入/输出改为逻辑 container distance：

```text
containerLogicalDistance = clamp(rawOffset + I, 0...D)
canonicalTotal = containerLogicalDistance + childDistanceFromTop
```

写入 container 时统一转换回 raw offset。child top offset、child maximum distance、managed inset 和 snapshot 语义不变。

OverscrollCoordinator 继续只管理 owner 策略与生命周期，不直接写 UIKit offset。其 container top/bottom boundary 必须接收逻辑 offset；三种顶部 mode 与 nil scroll target 矩阵保持现状。

active native boundary 期间如果发生顶部行为切换、安全区变化、Header layout reload、selection/reload terminal、尺寸变化或释放，先同步 cancel AnchorPager 自有 owner/presentation，再迁移稳定逻辑状态；不得把旧 raw overflow 按新 inset 直接解释。

## 结构性迁移

### 顶部行为切换

切换前保存稳定逻辑折叠量，切换后使用新 inset 还原 raw offset：

```text
preservedLogical = clamp(oldRawOffset + oldInset, 0...oldDistance)
newRawOffset = migratedLogical - newInset
```

`migratedLogical` 继续遵守调用路径选定的 Header offset adjustment 语义。仅切换 top behavior 且高度范围未变时，它等于 `preservedLogical`。

### 安全区或 bounds 变化

取消 active boundary，保存 collapse progress/逻辑位置，更新 `T`、`I`、scroll range、canonical Header 几何与 PagingHost 结构性布局，再恢复逻辑位置并转换 raw offset。inside 模式的 raw offset 会随 safe area delta 改变，但用户可见折叠量不得跳变。

### Header 高度变化

`reloadHeaderLayout(offsetAdjustment:)` 继续在纯内容 `E/C/D` 上应用四种公开策略。策略结果是新的逻辑 offset；最后一步才使用当前 `I` 转换成 raw offset。`preserveVisualPosition` 的“可见 Header”仍指顶部吸附基线到 bar 之间的逻辑可见纯内容量 `E - stableCollapseOffset`，不等于固定 Header 根视图的 `bounds.height`，也不按业务根视图与物理 viewport 的交集计算。这样可以在 Header 高度变化时保持 bar/paging 视觉位置，并让只切换 top behavior 且 `E/C/D` 不变时继续保留同一逻辑折叠量。

### reload、切页与 empty terminal

Store generation、selection terminal、committed current binding、child snapshot 和 Pageboy containment 不变。container 逻辑位置属于 ViewController/ScrollCoordinator，不进入 PageState；terminal 后按 committed state 使用当前 inset 幂等 reconcile。

## Public API 与 LayoutContext

Public symbol 不增删：

```swift
public enum AnchorPagerHeaderTopBehavior: Sendable, Equatable {
    case insideSafeArea
    case extendsUnderTopSafeArea
}
```

DocC 需要明确：

1. 该类型控制主容器顶部坐标/inset 与 Header 背景是否延伸到顶部系统区域。
2. 它不控制 Header 在折叠过程中缩高；Header 完整高度由 `AnchorPagerHeaderHeightMode` 解析。

`AnchorPagerLayoutContext` 的 frame 继续表示 pager view 本地实际 presentation 坐标：

1. 正常折叠时 `headerFrame.height` 保持完整高度，`minY` 随折叠向上移动；`headerFrame.maxY == barFrame.minY` 保持成立。
2. container top bounce 时 Header/bar/content 再加入同量正向 viewport presentation。
3. plain bottom 时 Header/bar 保持 collapsed canonical，只有 content frame 加入页面 surface 负向位移。
4. child owner bounce 时三者保持 container canonical。

这是既有 public 结构的行为语义修正，不新增字段，也不暴露 internal clip/presentation surface。

## Inset Ownership

主容器与 child inset ownership 必须严格分离：

```text
container contentInset.top = I
child managed contentInset.top = resolved Tabman bar obstruction
```

Header 高度、container 顶部 inset 和顶部 safe area 仍不得进入 child managed top。ManagedInsetCoordinator 不持有或恢复主容器 inset；主容器 inset 由 AnchorPagerViewController 的结构性布局事务独立拥有。

`verticalScrollView` public 静态类型继续是 `UIScrollView`，但 delegate、adjustment behavior 和框架拥有的 inset 不允许调用方替换。横纵 indicator 保持隐藏。

## 日志

新增或明确结构性事件：

```text
inset.containerTopChanged
layout.headerPresentationInstalled
```

`inset.containerTopChanged` 只在解析后的 container top inset 实际变化时记录，不输出数值。`layout.headerPresentationInstalled` 只在固定高度 canonical presentation 层完成安装或重建时记录；普通 pan/offset/layout 热路径不重复输出。

既有 `layout.headerFrameChanged`、`layout.barFrameChanged`、scroll/overscroll owner 与 boundary 日志继续使用状态变化/受控采样策略，不逐帧记录 raw/logical offset。

## 影响范围

- **Public API：** 无 symbol 变化；修订 `AnchorPagerHeaderTopBehavior` 与 `AnchorPagerLayoutContext.headerFrame` 行为说明。
- **内部分层：** 新增纯 container geometry/conversion 和固定高度 canonical content presentation surface；ScrollCoordinator 保持唯一 offset writer。
- **Header：** root 高度在滚动热路径固定；measurement/bootstrap/containment 保持。
- **Paging adapter：** 继续固定 Pageboy viewport 高度；正常折叠改由共同 presentation surface 移动，plain bottom page surface 保持独立。
- **Child lifecycle/Store：** generation、cache、snapshot、terminal 和 appearance 不变。
- **Scroll discovery/inset：** child discovery 与 managed inset 不变；新增 container-only top inset ownership。
- **Gesture/overscroll：** simultaneous pair、顶部 mode、native boundary owner 不变；所有 container boundary 改读逻辑 offset。
- **示例：** 继续用统一菜单切换 Header top behavior；新增固定 Header 高度、raw 边界和无跳变探针。
- **文档：** requirements、architecture、task-list、README、roadmap、DocC 及冲突旧规格同步修订。

## TDD 与验收设计

### 纯几何 RED

1. inside/extends 的 `I`、raw/logical 双向转换与 `0...D` 稳定边界。
2. `scrollRangeHeight == H + D - I`，覆盖 `D == 0`、`D < I`、非零 collapsed height 和非有限输入降级。
3. 两种 top behavior 在相同逻辑折叠量下 bar baseline 一致。
4. Header frame 高度固定、minY 上移、maxY 始终等于 bar minY。
5. top behavior/safe area/高度范围迁移保持逻辑 offset 或指定 progress。

### UIKit/Framework RED

1. inside 模式真实 `contentInset.top == safeArea.top`，展开 raw offset 为 `-safeArea.top`，折叠 raw offset为 `D - safeArea.top`。
2. extends 模式 top inset 和展开 raw offset为 `0`，折叠 raw offset为 `D`。
3. 部分折叠与完全折叠期间业务 Header 根 view bounds 高度不变，HeaderHost 不发生滚动热路径 required height 修改。
4. canonical content surface 上移而固定 viewport/物理屏幕底边不移动；Pageboy child bounds 保持固定。
5. top behavior 双向切换、safe area 变化、旋转和 `reloadHeaderLayout` 后无 bar/page 跳变，raw offset 按新 inset 迁移。
6. container top、plain bottom、真实 child top/bottom presentation 与既有 owner 矩阵全部回归。
7. 无滚动页 scroll target 仍为 nil；不产生 wrapper、managed inset 或 snapshot。
8. Header UIViewController containment、automatic bootstrap seed、内部 safe-area 内容约束和零约束告警回归。
9. 新日志只在结构变化时产生，重复 layout/pan 不刷屏。
10. 源码扫描继续确认不写业务 child scroll/pan delegate、`isScrollEnabled`、`bounces`、`alwaysBounceVertical` 或业务 page root transform。

### Example 真实 UI RED

1. 菜单切换 inside/extends 后，探针分别报告 container top inset 为 safe-area top/0。
2. 同一 Header 在展开、部分折叠和吸顶状态下本地高度保持不变，frame minY 向上移动。
3. 两种模式下 bar 到达相同吸顶基线；切换时 bar/page 不跳动。
4. inside 模式顶部 container bounce、三种顶部 mode、真实 child 双边界和 plain page 双边界继续有可见且排他的 owner 证据。
5. plain root 继续到达物理屏幕底部，plain bottom 只移动页面 surface，bar 不越过吸顶基线。
6. 真实启动和滚动期间无 `Unable to simultaneously satisfy constraints`。

### 完整门禁

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=<available simulator>' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=<available simulator>' -parallel-testing-enabled NO test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
```

实现后还必须执行运行时约束日志检查、静态禁止项扫描、代码自审和独立 fresh-pass 复审。Critical/Important 清零前不得恢复 v0.5 Task 7 与 v0.6 Ready，也不得进入 v0.7。

## 冲突与取代关系

本设计在下列范围取代旧契约：

1. `2026-07-10-header-scroll-settlement-design.md` 和 `2026-07-11-dual-header-top-behavior-bounce-stability-design.md` 中“主容器 raw 稳定区间固定为 `0...D`”及“Header host 高度随可见高度缩小”的部分。
2. `2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md` 中“主容器 top inset 恒为零”和“adapter top 通过缩小 Header frame 移动”的部分；child inset ownership 与固定 Pageboy viewport 继续有效。
3. `2026-07-13-v0-5-scroll-coordination-design.md` 与 `2026-07-13-boundary-bounce-ownership-design.md` 中直接把 raw container offset 当作逻辑 `0...D` 的公式；delegate、gesture、owner 与 native boundary pass-through 继续有效。
4. `2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement-design.md` 的 page/chrome presentation 和 bootstrap measurement 继续有效，并与本设计的 canonical content surface 组合。

## 设计自审与首轮实施验收

1. **Public API：** 没有新增、删除或重命名 symbol；`AnchorPagerHeaderTopBehavior` 与 `AnchorPagerLayoutContext` 只修订行为语义，未泄漏 Tabman/Pageboy 或 internal owner 词汇。
2. **坐标闭环：** raw/logical 双向转换、expanded/collapsed boundary 与 `H + D - I` scroll range 使用同一 `I`；inside/extends 不再存在第二份 offset 原点。
3. **分层职责：** ScrollCoordinator 保持唯一 offset writer，OverscrollCoordinator 只管理策略；固定 viewport、canonical content、共享 top bounce 和 Pageboy page-only bottom surface 没有形成双 transform owner。
4. **UIKit 边界：** Header UIViewController containment、Pageboy page containment、Store generation/cache/snapshot 和 child managed inset 保持原 owner；不要求修改业务 child delegate、pan delegate、滚动开关或 bounce 配置。
5. **回归覆盖：** 纯几何、UIKit、真实 UI、运行时约束、日志、完整构建测试均已执行；最终 fresh-pass 仍是恢复 Ready 的独立门禁。
6. **文档状态：** AGENTS、requirements、architecture、task-list、README 与 roadmap 已同步首轮实施和验收事实，同时继续关闭 v0.5/v0.6 Ready。
7. **实现范围：** `AnchorPagerContainerScrollGeometry` 统一 raw/logical、稳定边界、overflow 与 range；LayoutEngine 改为固定 Header 高度；ScrollCoordinator 所有 container 读写迁移到 geometry；ViewController 新增 canonical content presentation 并独占主容器 top inset；Example 新增 inset/Header 几何探针和真实手势 UI。
8. **实现提交：** `feffaf6`、`4f5cb26`、`cea399a`、`33132c5`、`65cc9b7`、`1847aac`；验收 HEAD `ce09f2b` 只额外消除两条测试弱引用编译警告。
9. **Framework 首轮全量：** `/private/tmp/AnchorPagerContainerTopInsetFrameworkFullClean-20260714.xcresult`，318/318、0 fail、0 skip、0 error、0 warning、0 analyzer warning。
10. **Example 首轮全量：** `/private/tmp/AnchorPagerContainerTopInsetExampleFull-20260714.xcresult`，41/41（11 单元 + 30 UI）、0 fail、0 skip、0 error、0 warning、0 analyzer warning；`/private/tmp/AnchorPagerContainerTopInsetExampleBuild-20260714.xcresult` generic Simulator build 成功且诊断全零。
11. **运行时约束：** 新 Header 真实手势 UI 单独通过，`/private/tmp/AnchorPagerContainerTopInsetRuntime-20260714.log` 对 `Unable to simultaneously satisfy constraints` 与 `UIViewAlertForUnsatisfiableConstraints` 均为零命中。Xcode 宿主会输出 LLDB version store 环境提示，但未进入 xcresult error/warning。
12. **当前门禁：** 上述证据只表示 Task 7 首轮验收通过；Task 8 必须对 `7885d9e...HEAD` 做 fresh-pass、清零 Critical/Important 并使用最终 HEAD 重跑三项正式门禁后，才能恢复 Ready。
13. **基础与静态门禁：** `swift package resolve`、`git diff --check` 通过；Public 目录 Tabman/Pageboy 零命中，生产代码的 delegate/bounce 写入只命中 AnchorPager 自有 `verticalScrollView`，synthetic/wrapper 与业务 transform 仅命中禁止或被取代的历史说明。
14. **Task 7 自审：** Public API 未扩大；Header/Pageboy containment、generation/cache/snapshot、child managed inset 和业务 child delegate/pan/bounce ownership 未改变；新日志均为低频状态事件且有测试；长期文档没有提前恢复 Ready。未发现阻塞 Task 8 的问题。

## 完成定义

1. 主容器真实 inset、raw/logical offset、content range 和所有边界 owner 使用同一坐标契约。
2. Header 业务根视图在稳定滚动和 bounce 期间保持完整布局高度，正常折叠只由 AnchorPager 自有 presentation surface 表达。
3. bar 吸顶、Pageboy 固定 viewport、plain bottom page-only presentation 和真实 child 原生 bounce 均保持。
4. 顶部行为切换、安全区/尺寸/Header 高度变化、reload/selection terminal 与释放清理无跳变或残留 transform。
5. Public API 不扩大，Tabman/Pageboy 不泄漏，业务 child 配置与 containment 边界不变。
6. TDD、完整 Framework/Example/UI/generic build、日志、静态扫描、`git diff --check`、自审与独立复审均有新鲜证据。
