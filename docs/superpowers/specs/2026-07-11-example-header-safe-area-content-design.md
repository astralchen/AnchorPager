# ExampleHeaderView 安全区内容布局设计

## 背景

示例工程的 `ExampleHeaderView` 当前把标题栈四边约束到 `layoutMarginsGuide`。虽然 UIKit 默认会让布局边距
受 safe area 影响，但该关系是间接的，无法清晰表达示例希望展示的语义：Header 背景可以按
`AnchorPagerHeaderTopBehavior` 延伸到顶部系统区域，文字内容始终位于安全区域内。

本变更只调整示例 Header 的内部内容约束，不修改 AnchorPager 的 Header 外框、automatic 高度测量、滚动
范围或顶部行为切换语义。

## 关系梳理

相关布局分为两层：

1. `AnchorPagerViewController` 根据顶部行为决定 Header 外框是否覆盖顶部 obstruction。
2. `ExampleHeaderView` 决定蓝色背景范围内标题和副标题的内容位置。

`.extendsUnderTopSafeArea` 只应扩展第一层的背景外框，不应把第二层的文字移入状态栏或导航栏区域。
`.insideSafeArea` 下 Header 外框本身已经位于安全区域内，内部 safe area 与 bounds 重合。

Header 的 automatic fitting 继续由中立测量事务执行。在中立位置测量时，Header 自身顶部 safe area 为零，
因此把文字约束到 `safeAreaLayoutGuide` 不会把顶部 obstruction 重复计入纯内容高度；最终展示到顶部时，
safe area 只负责移动内容，不改变框架保存的纯内容高度语义。

## 设计决策

`ExampleHeaderView` 保持蓝色背景覆盖自身完整 bounds，并采用以下内容约束：

- 左右继续约束到 `layoutMarginsGuide`，保留系统横向布局边距。
- 上下改为约束到 `safeAreaLayoutGuide`，分别保留 20 pt 内边距。
- 标题与副标题的字号、间距、文案和 Dynamic Type 行为不变。

两种顶部行为统一满足：

```text
stackView.minY >= headerView.safeAreaLayoutGuide.layoutFrame.minY + 20
stackView.maxY <= headerView.safeAreaLayoutGuide.layoutFrame.maxY - 20
```

不通过修改 `additionalSafeAreaInsets`、关闭 safe-area propagation、硬编码设备顶部高度或给框架添加示例专用
分支实现该效果。

## 影响范围

- Public API：无变化。
- 框架内部分层、paging adapter、containment、child lifecycle、scroll discovery、inset ownership：无变化。
- gesture、overscroll、日志：无变化；本次没有新增框架状态事件，不增加日志。
- 示例工程：仅调整 `ExampleHeaderView` 的内部 Auto Layout 约束。
- 文档：登记本设计与对应实施计划。

## 测试与验收

采用测试先行：

1. 示例单元测试在真实 window/safe area 布局中验证两种顶部行为下标题内容不越过安全区域，同时确认
   `.extendsUnderTopSafeArea` 的 Header 外框仍从容器顶部开始。
2. 示例 UI 测试验证运行时切换顶部行为后，Header 标题仍位于导航栏下方并可见。
3. 复用已经启动的 iPhone 17 模拟器运行示例测试，避免不必要的模拟器冷启动。
4. 运行示例 generic simulator build 与 `git diff --check`。

## 回归风险

主要风险是 safe area 参与 automatic fitting 后重复增加 Header 高度。测试必须同时检查内容安全区位置和切换后的
Header/bar 几何基线，确保只改变内部内容位置，没有改变框架 Header 高度模型、分段栏位置或回弹行为。

## 实施记录

- `ExampleHeaderView` 标题栈左右继续使用 `layoutMarginsGuide`，上下已改为 `safeAreaLayoutGuide`，常量保持 20 pt。
- 蓝色背景仍覆盖 Header 完整 bounds；AnchorPager Header 外框、分段栏基线、automatic 中立测量和 viewport bounce 未修改。
- 同进程测试覆盖两种顶部行为下标题栈相对 Header safe area 的上下 20 pt 间距，并确认 extends 外框仍从容器 `minY == 0` 开始。
- UI 测试覆盖 inside → extends 切换后标题始终位于导航栏底部下方 20 pt。
- TDD RED 中同进程测试和 UI 测试都记录到旧 `layoutMarginsGuide` 额外引入 8 pt；最小约束修改后两个目标路径均 GREEN。
- 最终验收使用同一台 Booted iPhone 17：框架测试 83/83、示例测试 13/13 通过，generic iOS Simulator build 和 `git diff --check` 通过。
- 最终自审确认未修改框架 Public API、Header 外框、第三方 adapter、containment/lifecycle、scroll/inset、overscroll、日志或并发边界。

## Follow-up：文本组顶部对齐与固定间距

### 问题关系

标题栈虽然设置了 `spacing = 8`，但其 top 和 bottom 都以等式约束到 Header safe area。最终 Header 的 safe area
高度大于标题栈 intrinsic height 时，`UIStackView.distribution == .fill` 会把多余高度分配给 arranged label，
导致文字视觉间距大于 8 pt。该现象是示例内部内容约束造成的，不是 AnchorPager Header 高度、safe area 计算或
viewport bounce 改变。

### 设计决策

文本组采用顶部对齐：

```text
stackView.top == safeArea.top + 20
stackView.bottom <= safeArea.bottom - 20
stackView.spacing == 8
```

左右约束继续使用 `layoutMarginsGuide`。bottom 使用 `lessThanOrEqualTo` 后，标题栈保持 intrinsic height，Header
多余高度全部留在副标题下方；安全区不足时仍要求至少保留 20 pt 底部空间。不得通过额外 spacer、UILabel 高优先级
hugging、固定 Header 高度或修改框架布局掩盖问题。

### 行为与边界

- inside 和 extends 两种顶部行为下，标题栈顶部保持 safe area 下方 20 pt。
- 标题与副标题的相邻 frame 间距保持 8 pt；Dynamic Type 和副标题换行继续由 intrinsic content size 驱动。
- 负主容器 offset 只整体平移 viewport，不改变标题栈内部 frame 或 8 pt 间距。
- 蓝色背景、Header 外框、分段栏基线、automatic 中立测量、scroll range 和 bounce 语义不变。

### 测试与验收

采用测试先行：先把现有同进程测试扩展为验证标题/副标题 frame 间距和 bottom 不越过 safe area，并模拟负 offset
确认内部间距不变；再增加真实 UI 断言，覆盖 inside → extends 后两段文本仍相邻 8 pt。最小实现只把 bottom 等式
约束改为 `lessThanOrEqualTo`，随后运行完整框架测试、完整示例测试、generic iOS Simulator build 和
`git diff --check`。

### Follow-up 实施记录

- 标题栈 bottom 已从 safe area 等式改为 `lessThanOrEqualTo`；top 继续等于 safe area 下方 20 pt，左右继续使用 layout margins。
- TDD RED 在 extends 模式模拟 `contentOffset.y = -24` 后记录到副标题高度从 18 pt 拉伸到 42 pt，差值 24 pt；使用 0.5 pt frame 容差后仍稳定失败。
- 真实 UI 测试在静止状态修复前已经满足 8 pt；由于同步 XCUITest 无法在拖拽调用返回前读取“手指仍按住”的 frame，中间态使用同进程 UIKit 负 offset 测试作为稳定替代验证。
- 最小修改后示例单元测试 4/4、目标 UI 测试 1/1 通过；负 offset 不再改变标题或副标题本地 frame，文本间距保持 8 pt。
- 框架 Header 外框、safe area 计算、automatic 测量、scroll range、viewport bounce 和日志均未修改。
- 最终验收继续复用 Booted iPhone 17：框架测试 83/83、示例测试 13/13、generic iOS Simulator build 和 `git diff --check` 全部通过。
- 最终自审确认没有 Public API、第三方 adapter、containment/lifecycle、并发、scroll/inset、gesture/overscroll、日志或资源边界变化。
