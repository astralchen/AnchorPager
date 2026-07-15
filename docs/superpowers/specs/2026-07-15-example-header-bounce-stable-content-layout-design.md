# Example Header 顶部回弹内容稳定布局设计

**日期：** 2026-07-15

**状态：** 已确认，待实施与验收

**实施计划：** `docs/superpowers/plans/2026-07-15-example-header-bounce-stable-content-layout.md`

**适用范围：** Example `ExampleHeaderView` 安全区内容约束、默认
`.extendsUnderTopSafeArea`、container 顶部原生回弹、Header 内部文字局部位置与相关自动化验证。

## 背景与可见证据

默认 Header 顶部行为迁移为 `.extendsUnderTopSafeArea` 后，用户在真实 container 下拉中观察到：
Header 外框高度保持不变并随 viewport 下移，但标题和副标题相对 Header 顶部的距离持续减小。

两张相同尺寸的真实截图提供了直接证据：

1. 未下拉时蓝色 Header 底部约为 `y = 625`；超过顶部安全区后约为 `y = 968`。
2. Header 整体下移约 `343 px`，高度仍约为 `625 px`。
3. 标题像素范围在两张图中都约为 `y = 424...481`，副标题都约为 `y = 520...556`。
4. 因此文字几乎固定在屏幕坐标，而相对 Header 顶部的距离减少约 `343 px`。

这不是 Header 缩高，也不是 viewport 裁剪；它是 Header 内部安全区约束在 presentation 位移期间重新求解。

## 根因与数据流

container 顶部 owner 的既有正确数据流是：

```text
verticalScrollView 原生 top overflow
  → viewportView 整体向下 presentation
  → Header / bar / page 一起下移
```

`ExampleHeaderView` 原约束为：

```text
stackView.top == safeArea.top + 20
stackView.bottom <= safeArea.bottom - 20
```

当 Header 随 viewport 穿过顶端系统遮挡时，UIKit 会重新传播 Header 局部
`safeAreaLayoutGuide`。动态 `safeArea.top` 的反向变化通过顶部等式直接写入标题栈局部位置，抵消了
viewport 的可见下移。框架的 Header frame、高度、raw/logical container offset、LayoutContext 与
overscroll owner 均保持正确；错误职责只位于 Example 内容布局。

现有同进程测试只设置 `contentOffset.y = -24` 并同步布局，没有跨越完整顶部遮挡，也没有覆盖真实手势多帧
safe-area 传播。因此它能验证 label 不拉伸，却不能证明大幅回弹时内容局部位置稳定。

## 已确认语义

1. container 顶部回弹继续移动完整 viewport；Header、bar 和 page 使用同一 UIKit 原生位移。
2. Header 外框和业务根视图高度在回弹期间保持固定。
3. Example 标题栈在 Header 本地坐标中的 frame 保持固定，不用动态顶部 safe area 抵消 viewport 位移。
4. 标题与副标题继续使用 intrinsic/fitting 高度，视觉间距保持 `8 pt`。
5. 静止状态下标题栈仍位于 Header 安全区域内，上下至少保留 `20 pt`。
6. 本次不改变 AnchorPager 对任意业务 Header 内部安全区布局的通用策略；接入方仍拥有自身内容约束。

## 方案比较

### 采用：底部稳定锚点与顶部安全下限

正式保留用户已验证的 Example 约束：

```swift
stackView.topAnchor.constraint(
    greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor,
    constant: 20
)
stackView.bottomAnchor.constraint(
    equalTo: safeAreaLayoutGuide.bottomAnchor,
    constant: -20
)
```

左右约束继续使用 `layoutMarginsGuide`。

`bottom == safeArea.bottom - 20` 成为标题栈唯一垂直位置锚点；顶部约束只表达安全下限。顶部回弹时
`safeArea.top` 可以减小而不再推动标题栈。当前 Example 使用 automatic Header，中立 compressed fitting
会解析最小内容高度，因此静止状态仍同时得到顶部和底部约 `20 pt`；回弹期间 Header 高度与底部安全区稳定，
标题栈局部 frame 也保持稳定。

### 不采用：框架冻结业务 Header 的 safe area

这会让 AnchorPager 侵入任意业务 Header 的内部布局语义，并需要处理顶部行为切换、旋转、
`additionalSafeAreaInsets` 和 UIViewController Header；它会扩大框架职责，不能为 Example 单点表现采用。

### 不采用：Example 缓存 canonical 顶部 safe-area 数值

缓存顶部 inset 后再维护自定义 top constraint 可以保留顶部对齐，但会引入第二份 safe-area 状态，并需要在
顶部行为切换、窗口变化、导航栏变化和 Header 重新测量时同步更新。相比无状态 Auto Layout 约束更脆弱。

### 不采用：`insetsLayoutMarginsFromSafeArea = false`

当前垂直约束直接引用 `safeAreaLayoutGuide`，该属性不会改变 safe-area guide；若改用不受 safe area 影响的
layout margins，静止 `.extendsUnderTopSafeArea` 下文字又可能进入顶部系统遮挡区域。

## 布局边界

1. 本方案固定的是 Example 当前 automatic Header 的内容局部位置，不新增通用 Header 对齐配置。
2. 当 Header 高度大于 compressed fitting 最小高度时，标题栈采用底部对齐，多余高度位于标题栈上方；这是本次
   正式接受的 Example 语义。
3. Dynamic Type 或副标题换行后，automatic fitting 继续扩展 Header 纯内容高度，不允许压缩 label 或改变 `8 pt`
   间距。
4. 顶部约束仍为 required 下限；若未来把 Example 改为不足以容纳内容的 fixed/ranged 高度，必须单独设计
   overflow/compression 策略，不能降低当前安全约束优先级。
5. `.insideSafeArea` 与 `.extendsUnderTopSafeArea` 静止布局都必须满足标题栈不越过 safe area，上下至少 `20 pt`。

## 影响范围

- **Public API：** 无变化。
- **AnchorPager framework：** 无生产代码变化；Header、LayoutEngine、container geometry、ScrollCoordinator、
  OverscrollCoordinator 和日志均不修改。
- **UIKit containment / lifecycle：** Header UIView/UIViewController 与 Pageboy page containment 不变。
- **Paging / child / inset ownership：** 无变化；不修改业务 child delegate、pan delegate、bounce 或 inset。
- **Example：** 只正式保留 `ExampleHeaderView` 的纵向约束，并扩展测试探针。
- **日志：** 不新增框架日志；示例约束变化没有新的框架状态事件。
- **文档：** 本设计取代 `2026-07-11-example-header-safe-area-content-design.md` 中“顶部等式、底部上限、
  文本组顶部对齐”的当前约束，早期问题与实施记录保留为历史。

## TDD 与验收设计

### RED 证据

用户的两行约束修改已经存在于工作区，不能为了制造 RED 而回滚。实施计划应在隔离的临时 worktree 中基于当前
`HEAD` 应用新增测试，验证旧约束在跨越完整顶部遮挡时失败；主工作区保留用户修改，并用同一测试验证 GREEN。

RED 必须证明：

1. Header frame/根视图高度保持固定且 viewport 已产生明显正向 top presentation。
2. 旧约束下标题栈、标题或副标题相对 Header bounds 的局部 frame 发生变化。
3. 失败来自跨安全区回弹，不是页面选择、Header collapse、约束冲突或测试装配错误。

### Example 同进程测试

扩展现有 `headerContentUsesSafeAreaForVerticalPaddingInBothTopBehaviors()`：

1. 在 `.extendsUnderTopSafeArea` 展开态记录 Header bounds、标题栈、标题和副标题本地 frame。
2. 使用多个负 offset 逐步跨越完整本地顶部遮挡，并允许 UIKit 完成相邻 layout/run-loop 更新。
3. 每一步都断言 Header 高度不变、标题栈和两个 label 本地 frame 不变、标题与副标题间距仍为 `8 pt`。
4. 同时断言 LayoutContext Header/bar/content 产生同量 container top presentation，证明测试确实进入可见回弹。
5. 回稳后所有局部 frame、Header 高度和 presentation 恢复 canonical。
6. 两种顶部行为静止状态继续验证标题栈位于 safe area 内，上下至少 `20 pt`。

### 真实 UI 门禁

真实 XCUITest 的 drag API 在手指按住期间同步阻塞查询，不能直接读取中间帧。正式实现扩展 Example 已有
scroll coordination probe，在 `didUpdateLayout` 的真实显示帧中记录标题栈相对 Header 顶部距离及其最大变化量。
UI 测试执行超过顶部遮挡的真实下拉后，必须同时证明：

```text
maximumContainerTopPresentation > 1 pt
maximumHeaderContentTopDistanceDelta < 0.5 pt
maximumHeaderHeightDelta < 0.5 pt
```

这样测试不会只证明出现过负 offset，而会证明真实手势期间 Header 整体回弹、根视图不缩高、内部文字不漂移。

### 完整验收

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=<available simulator>' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=<available simulator>' -parallel-testing-enabled NO test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
```

还需检查三份 xcresult 的 error/warning/analyzer warning、运行时 Auto Layout 约束关键字、Public
Tabman/Pageboy 泄漏和业务 child delegate/pan/bounce 禁止项；完成后执行代码自审与 fresh-pass。

## 回归风险

1. **automatic measurement：** top 下限与 bottom 等式必须在 bootstrap seed 和正式中立 fitting 中得到稳定最小高度，
   不得恢复 required zero-height 冲突。
2. **Dynamic Type：** 标题栈必须保持 intrinsic height 和 `8 pt` 间距，不能因为 bottom 等式再次拉伸 label。
3. **safe-area 变化：** 静止 top behavior 切换、导航栏变化和旋转后内容仍在安全区内；只有 active bounce 期间允许
   顶部不等式从等号状态放宽。
4. **测试探针：** 只观察 Example 可见几何，不写 container/child offset，不成为第二个 presentation owner。
5. **文档冲突：** 旧“顶部对齐”契约必须明确被本设计取代，不能同时把两种约束关系都标成当前事实。

## 完成定义

1. Example 正式使用顶部安全下限与底部稳定等式。
2. 静止 inside/extends 都保持安全区上下至少 `20 pt`，标题/副标题 intrinsic 高度和 `8 pt` 间距不变。
3. 真实 container 顶部回弹跨越完整顶部遮挡时，Header 高度不变、文字相对 Header 顶部距离变化小于 `0.5 pt`。
4. Header/bar/page 仍整体使用 container 原生 top presentation，回稳后没有残留 transform 或状态。
5. Public API、framework、containment、paging、scroll/inset/overscroll/logging ownership 均不改变。
6. RED/GREEN、同进程测试、真实 UI、完整 Framework/Example、generic build、运行时约束、静态门禁、
   `git diff --check`、自审和 fresh-pass 都有新鲜证据。
