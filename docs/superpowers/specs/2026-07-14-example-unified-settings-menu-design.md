# Example 统一设置菜单设计

**日期：** 2026-07-14

**状态：** 对话设计已确认，书面规格待用户复核

**适用范围：** Example 导航栏配置入口、`AnchorPagerHeaderTopBehavior` 与 `AnchorPagerTopOverscrollHandlingMode` 运行时切换、菜单选中态及相关 Example 单元/UI 测试。

## 背景

当前 Example 已提供两个并列的导航栏文本菜单：

1. Header 顶部行为：显示“安全区内”或“延伸到顶部”。
2. 顶部回弹模式：显示“关闭”“容器”或“子页面”。

两套切换逻辑和框架运行时语义已经存在，但并列文本按钮占用导航栏宽度，配置入口分散。用户确认将它们合并为一个齿轮设置入口，并使用两个二级菜单组织选项。

## 目标

1. 使用单个导航栏齿轮按钮承载 Example 配置。
2. 菜单包含“Header 顶部行为”和“顶部回弹模式”两个二级菜单。
3. 二级菜单分别显示当前 `AnchorPagerHeaderTopBehavior` 与 `AnchorPagerTopOverscrollHandlingMode` 的唯一勾选态。
4. 选择后立即应用现有运行时配置语义，并同步刷新菜单和 Example 测试探针。
5. 保留打开新示例和重新加载页面两个既有导航栏入口。
6. 通过 Example 单元测试与真实 UI 测试覆盖菜单结构、状态和模式切换。

## 非目标

1. 不修改 AnchorPager Public API、默认配置或框架滚动实现。
2. 不新增设置控制器、弹窗、持久化或用户偏好存储。
3. 不修改 Header、Pageboy containment、selection、scroll/inset ownership 或 overscroll owner 规则。
4. 不新增框架日志；现有 `overscroll.mode.changed` 继续记录真正的 mode 变化。
5. 不把 Example 菜单类型或测试探针暴露到 AnchorPager 模块。

## 方案选择

### 采用：同步重建统一 UIMenu

导航栏只保留一个带 `gearshape` 图标的 `UIBarButtonItem`。该 item 的根菜单由两个子 `UIMenu` 组成；每次选择配置后从 `pagerViewController.configuration` 重新构建菜单，使勾选态立即反映唯一配置事实。

该方案没有异步 provider、额外控制器或第二份状态，适合当前固定的五个选项，也便于单元测试直接检查菜单树。

### 不采用：UIDeferredMenuElement

每次展开时动态生成菜单可以省去主动刷新，但会引入异步 provider 和更多生命周期路径。当前配置选项固定，主动同步重建更直接。

### 不采用：设置弹窗

弹窗便于未来扩展更多配置，但会增加控制器、展示生命周期和 UI 测试成本，超出本次需求。

## 组件与职责

### 统一设置按钮

`ExamplePagerViewController` 只保存一个 `settingsItem` 引用：

- 图标：优先使用 `gearshape`；若系统图像意外不可用则显示“设置”文本，保证入口仍可见。
- `accessibilityLabel`：`示例设置`。
- 根菜单：由 `makeSettingsMenu()` 同步生成。
- 图标和无障碍标签不随配置变化；当前值由子菜单中的勾选态表达。

导航栏右侧保留三个职责明确的 item：打开新示例、设置、重新加载页面。原 `headerTopBehaviorItem` 和 `topOverscrollHandlingItem` 不再单独安装或保存。两个子菜单保持标准嵌套展示，不使用 `.displayInline` 展平选项。

### Header 顶部行为子菜单

子菜单标题为“Header 顶部行为”，顺序固定为：

1. 安全区内
2. 延伸到顶部

选择后继续执行既有流程：写入 `configuration.header.topBehavior`，调用 `reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)`，然后刷新统一设置菜单。当前行为对应的 `UIAction.state` 为 `.on`，另一项为 `.off`。

### 顶部回弹模式子菜单

子菜单标题为“顶部回弹模式”，顺序固定为：

1. 关闭（`.none`）
2. 容器（`.container`）
3. 子页面（`.child`）

选择后继续执行既有流程：同步写入 `configuration.topOverscrollHandlingMode`，更新 `scrollCoordinationState.mode`，清空旧 presentation 指标，再刷新统一设置菜单与状态探针。当前 mode 对应的 `UIAction.state` 为 `.on`，其余为 `.off`。

## 数据流与状态所有权

```text
用户选择 UIAction
  → ExamplePagerViewController 现有 setter
  → AnchorPagerViewController.configuration（唯一配置事实）
  → Header layout refresh 或 overscroll mode reconcile
  → Example 探针同步
  → makeSettingsMenu() 从 configuration 重建勾选态
```

统一菜单不保存当前 Header 行为或顶部 mode 的副本。`scrollCoordinationState.mode` 只保留现有 UI 测试探针职责，不参与菜单状态判断或框架 owner 路由。

## 异常与边界

1. SF Symbol `gearshape` 在最低 iOS 14 基线可用；若系统无法生成图像，item 改用“设置”标题并保留相同 `accessibilityLabel` 和菜单，不回退为第二套配置入口。
2. `.child` 在无真实 scroll target 页面仍遵循框架现有不可用且不回退语义；Example 菜单只切换 mode，不伪造 scroll target。
3. reload、切页或 Header layout 不改变配置值；下次打开菜单仍从 `configuration` 生成正确勾选态。
4. 选项 action 使用弱引用捕获控制器，不新增闭包 retain cycle。
5. 不通过菜单直接写 container/child offset、bounce 属性、delegate 或 pan delegate。

## 测试设计

### Example 单元测试

严格执行 RED → GREEN：

1. 先把既有两个独立菜单测试改为统一设置菜单测试；生产代码未改时应因找不到“示例设置”齿轮入口而失败。
2. 验证导航栏存在打开新示例、示例设置和重新加载页面三个入口，不再存在“Header 顶部行为”“顶部回弹”两个独立 item。
3. 验证根菜单的两个子菜单标题、选项顺序和默认勾选态：安全区内 `.on`、容器 `.on`。
4. 执行 Header 行为 action，验证 Header 几何继续按 `.preserveVisualPosition` 更新，并验证重建后的菜单勾选“延伸到顶部”。
5. 逐一执行顶部回弹 action，验证 `configuration.topOverscrollHandlingMode`、探针 `mode` 和重建后的唯一勾选态一致。

测试通过现有 child hierarchy 取得 `AnchorPagerViewController`，不为测试扩大 Example 或框架 Public API。

### Example UI 测试

新增一条真实交互用例：

1. 启动默认 Example，确认探针为 `mode=container`。
2. 点击“示例设置”齿轮。
3. 打开“顶部回弹模式”子菜单。
4. 选择“子页面”。
5. 等待现有 `scroll-coordination-state` 探针报告 `mode=child` 且 presentation 指标已归零。

既有 `.none/.container/.child` launch argument、六类真实边界回弹、Header 顶部行为布局和 Example 完整 UI 回归继续保留。

## 影响范围

1. **Public API：** 无变化。
2. **框架内部分层：** 无变化；不修改 Core、Paging、Overscroll、Header 或 Store。
3. **UIKit containment/lifecycle：** 无变化；只替换 Example 的导航栏 item 组合。
4. **滚动与 owner：** 继续通过 `configuration` 的现有运行时 didSet 路径切换，不增加 offset writer。
5. **日志：** 无新日志事件；框架现有 mode 日志继续有效。
6. **测试：** 更新 Example 菜单单元测试，增加一条真实菜单切换 UI 测试，并运行相邻 Header/mode 回归。
7. **文档：** 更新 README 示例说明、`docs/task-list.md`、本规格和后续实施计划；新规格登记到 `AGENTS.md`。

## 完成定义

1. 导航栏只显示一个齿轮配置入口，不再显示两个配置文本按钮。
2. 两个二级菜单、选项顺序与勾选态符合设计。
3. Header 行为和顶部回弹模式切换继续使用既有配置与刷新语义。
4. 单元测试先出现预期 RED，再由最小实现转为 GREEN。
5. 真实 UI 测试证明用户可从齿轮菜单切换到 `.child`，探针同步为 `mode=child`。
6. Example 完整单元/UI、generic Simulator build、必要 Framework 回归和 `git diff --check` 通过。
7. 自审确认 Public API、containment、scroll/inset/owner、日志和文档边界未变化。
