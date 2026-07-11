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
