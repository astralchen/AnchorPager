# Header 默认延伸到顶部安全区域外设计

**日期：** 2026-07-14

**状态：** 实现与聚焦 RED/GREEN 已完成；全量验收、自审和 fresh-pass 待完成

**适用范围：** `AnchorPagerHeaderConfiguration` 默认值、`AnchorPagerConfiguration.default`、`AnchorPagerViewController` 无参数配置、Example 初始顶部行为、默认配置测试与接入文档。

## 背景

当前 `AnchorPagerHeaderConfiguration.init` 把 `topBehavior` 的默认参数设为
`.insideSafeArea`。`AnchorPagerHeaderConfiguration.default`、
`AnchorPagerConfiguration.default`、`AnchorPagerViewController()` 和 Example 又依次复用这条默认构造链，
因此默认 Header 背景从顶部安全区域下方开始。

用户已确认把默认顶部行为调整为 `.extendsUnderTopSafeArea`。默认 Header 背景应覆盖顶部系统区域，
主容器默认 `contentInset.top` 应为 `0`；需要安全区域内背景的接入方继续显式设置
`.insideSafeArea`。

本变更只调整默认选择，不改变两种 case 的现有几何语义。固定高度 Header、canonical content
presentation、固定 viewport 裁剪、bar 吸顶、plain bottom page surface 和真实 child bounce 均沿用
已经在生产代码 HEAD `424a0a3` 完成验收的架构。

## 现有默认值数据流

当前默认构造链只有一个应当修改的源头：

```text
AnchorPagerHeaderConfiguration.init(topBehavior: 默认值)
└─ AnchorPagerHeaderConfiguration.default
   └─ AnchorPagerConfiguration.init(header: .default)
      └─ AnchorPagerConfiguration.default
         ├─ AnchorPagerViewController.init(configuration: .default)
         └─ ExamplePagerViewController.initialConfiguration()
```

`AnchorPagerHeaderConfiguration.default` 和 `AnchorPagerConfiguration.default` 都通过无参数初始化生成，
不应分别覆盖 `topBehavior`，否则会形成多份默认事实。

## 方案比较

### 采用：修改 Header 初始化器的默认参数

```swift
public init(
    heightMode: AnchorPagerHeaderHeightMode = .automatic(min: 0, max: nil),
    topBehavior: AnchorPagerHeaderTopBehavior = .extendsUnderTopSafeArea
)
```

优点：无参数初始化、两级 `.default`、Pager 默认配置与 Example 初始配置自动保持一致；默认值仍只有
一个来源。该方案不增加 public symbol，不引入迁移字段或内部条件分支。

### 不采用：只修改 `AnchorPagerHeaderConfiguration.default`

这会让 `AnchorPagerHeaderConfiguration()` 与 `.default` 产生不同结果，破坏 UIKit 风格的默认构造直觉，
也会给测试和文档留下两份默认契约。

### 不采用：只修改 Example

这只能改变示例初始画面，框架的无参数配置仍为 `.insideSafeArea`，不符合用户确认的 Public API 默认语义。

## Public API 与兼容性

Public 类型、属性、方法和枚举 case 均不增删，也不重命名：

```swift
public enum AnchorPagerHeaderTopBehavior: Sendable, Equatable {
    case insideSafeArea
    case extendsUnderTopSafeArea
}
```

变更是源码兼容但用户可见的默认行为调整：省略 `topBehavior` 的调用方重新编译后会从
`.insideSafeArea` 切换到 `.extendsUnderTopSafeArea`。依赖旧视觉行为的调用方必须显式写出：

```swift
configuration.header.topBehavior = .insideSafeArea
```

`AnchorPagerHeaderHeightMode` 默认值、bar 自适应高度、paging cache 和顶部 overscroll 默认
`.container` 均不改变。

## 布局与滚动语义

新默认直接复用现有 `.extendsUnderTopSafeArea` 契约：

```text
containerTopInset = 0
expanded raw container offset = 0
collapsed raw container offset = collapsibleDistance
header canonical minY = bounds.minY
header canonical height = topObstruction + expandedContentHeight
```

以下行为不变：

1. Header 业务根视图在滚动热路径保持完整解析高度。
2. 正常折叠仍只移动 AnchorPager 自有 `contentPresentationView`。
3. 固定 `viewportView` 继续作为屏幕裁剪边界；本变更不提供“不裁剪”模式。
4. bar baseline 仍为 `topObstruction + contentHeight - collapseOffset`，两种顶部行为一致。
5. 显式 `.insideSafeArea` 继续让主容器 top inset 等于本地顶部遮挡，并使用 raw 展开边界
   `-contentInset.top`。
6. ScrollCoordinator、OverscrollCoordinator、LayoutEngine 和 container geometry 不新增默认值分支，
   只消费最终配置。

因此该变更不会改变 Pageboy containment、child managed inset、scroll discovery、page lifecycle、
selection/reload terminal、gesture pair 或业务 child delegate/pan/bounce ownership。

## Example 行为

Example 继续从 `AnchorPagerConfiguration.default` 创建配置，不在示例层重复指定
`.extendsUnderTopSafeArea`。初次启动时：

1. “Header 顶部行为”菜单默认勾选“延伸到顶部”。
2. Header 蓝色背景覆盖顶部系统区域，文字仍由 `safeAreaLayoutGuide` 保持在安全区域内。
3. 菜单可以切换到“安全区内”，运行时迁移继续使用现有 `.preserveVisualPosition`。
4. 需要验证 `.insideSafeArea` 的 UI 测试必须在测试步骤中显式选择该模式，不得继续依赖旧默认。

改变默认值不会取消 Header 折叠时的物理屏幕边界裁剪，也不承诺蓝色背景的可见交集高度在折叠时保持不变。

## 日志与错误处理

本变更不新增状态机、异常输入或资源，因此不新增日志事件。既有
`inset.containerTopChanged` 和 `layout.headerFrameChanged` 状态变化语义保持不变。

默认 `.extendsUnderTopSafeArea` 的初次布局如果 top inset 从初始零值保持为零，不要求为了记录默认选择而
人为发出 `inset.containerTopChanged`。日志继续只反映真实状态变化。

## 测试设计

### Public 默认配置 RED/GREEN

实现前先修改或新增断言，使当前代码精确失败于旧 `.insideSafeArea` 默认值：

1. `AnchorPagerHeaderConfiguration().topBehavior == .extendsUnderTopSafeArea`。
2. `AnchorPagerHeaderConfiguration.default.topBehavior == .extendsUnderTopSafeArea`。
3. `AnchorPagerConfiguration().header.topBehavior == .extendsUnderTopSafeArea`。
4. `AnchorPagerConfiguration.default.header.topBehavior == .extendsUnderTopSafeArea`。
5. `AnchorPagerViewController().configuration.header.topBehavior == .extendsUnderTopSafeArea`。
6. 显式 `AnchorPagerHeaderConfiguration(topBehavior: .insideSafeArea)` 仍为 `.insideSafeArea`。

测试夹具中为了隔离具体几何而显式使用 `.insideSafeArea` 的默认参数不必机械改写；只有用于验证 Public
默认值的断言随本设计改变。

### UIKit 几何回归

1. 默认 Pager 在真实 window/safe area 中 `verticalScrollView.contentInset.top == 0`。
2. 默认 Header frame 从 pager bounds 顶部开始，并保持
   `barFrame.minY == headerFrame.maxY`。
3. 显式 `.insideSafeArea` 仍使用真实顶部 inset 和 `-inset` raw 展开边界。
4. 两种模式下 Header 固定高度、bar 基线、Pageboy child bounds 和顶部/底部 owner 矩阵继续通过现有回归。

### Example 单元与 UI

1. 统一设置菜单初始状态改为“延伸到顶部”勾选、“安全区内”未勾选。
2. 真实启动探针报告默认 container top inset 为 `0`，Header 背景延伸到顶部系统区域。
3. 菜单从默认 extends 切到 inside 后，勾选态、真实 top inset、Header 完整高度和 bar 基线正确。
4. 既有 inside 专项 UI 测试先显式选择“安全区内”，再执行折叠与回弹验收。
5. 真实启动与切换过程中不得出现 Auto Layout 约束冲突。

## 文档同步

实施时同步更新：

- Public DocC
- `README.md`
- `docs/requirements.md`
- `docs/architecture.md`
- `docs/task-list.md`
- `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- `AGENTS.md` 必读文档索引
- 本设计的实施、验收与自审状态

文档必须明确这是默认选择变化，不是 `.insideSafeArea` 删除，也不是裁剪策略变化。
旧规格中的历史实施步骤保持原貌；只有仍自称当前默认值的长期契约需要修订。

## 实施门禁

1. 先提交 Public 默认值 RED，再修改初始化器默认参数。
2. 只修改单一默认源，不在 ViewController、LayoutEngine 或 Example 添加重复默认分支。
3. 运行 Framework 相关全量测试、Example 单元/UI 全量测试与 generic Simulator build。
4. 捕获默认启动与 inside 切换路径运行时日志，确认没有 UIKit 约束冲突。
5. 执行 Public API/第三方类型/业务 child delegate、pan、bounce 配置静态扫描。
6. 完成代码自审和 fresh-pass；Critical/Important 清零后才能标记完成。

## 实施进度

生产实现与测试已在提交 `3bdcfb6` 完成。唯一生产变化是把 `AnchorPagerHeaderConfiguration.init` 的默认参数改为 `.extendsUnderTopSafeArea` 并同步 DocC；没有修改 LayoutEngine、container geometry、ScrollCoordinator、OverscrollCoordinator、paging adapter 或 child ownership。

TDD 证据：

1. Framework 新默认契约在实现前精确失败，实际值为旧 `.insideSafeArea`；Example 单元菜单状态和真实 UI 零 top inset 断言同样先失败。
2. 修改单一默认源后，Framework 精确默认契约 1/1 通过，Example 11 项单元测试与 5 项相关 UI 测试全部通过。
3. 控制器类回归暴露出 3 个隐式依赖旧默认值的 inside 专项测试；逐项补充显式 `.insideSafeArea` 前置条件后，`AnchorPagerViewControllerTests` 101/101 通过，生产几何逻辑未增加兼容分支。
4. `git diff --check` 与实现范围自审通过，`Examples/AnchorPagerExample.xcodeproj/project.pbxproj` 的用户改动未暂存、未提交。

全量 Framework、Example/generic build、运行时约束扫描、静态门禁和 fresh-pass 结果仍待最终验收，不在此阶段预填。

## 架构停机条件

出现以下任一情况必须停止实施并先修订设计：

1. 无参数初始化、`.default` 和 Pager 默认配置无法通过同一初始化器保持一致。
2. 改变默认值需要修改 LayoutEngine、ScrollCoordinator 或 OverscrollCoordinator 的几何/owner 逻辑。
3. Example 必须硬编码第二份 `.extendsUnderTopSafeArea` 才能表现新默认。
4. inside 专项回归要求削弱 safe-area、固定 Header 高度或 raw/logical offset 断言。
5. 修复要求改变 Pageboy containment、child inset ownership 或业务 child delegate/pan/bounce 配置。

## 完成定义

1. 单一初始化器默认值为 `.extendsUnderTopSafeArea`，所有默认构造链一致。
2. 显式 `.insideSafeArea` 行为与现有验收契约一致。
3. Example 初始菜单、背景、安全区内容和 container top inset 符合新默认。
4. Header 固定高度、viewport 裁剪、bar 吸顶、plain/真实 child bounce 和 Pageboy bounds 回归通过。
5. Public API 不扩大，Tabman/Pageboy 不泄漏，业务 child ownership 不改变。
6. TDD、Framework/Example/UI/generic build、运行时约束、静态扫描、`git diff --check`、自审与 fresh-pass 均有新鲜证据。
