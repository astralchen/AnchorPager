# Header 默认延伸到顶部安全区域外实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `AnchorPagerHeaderTopBehavior` 的默认选择从 `.insideSafeArea` 调整为 `.extendsUnderTopSafeArea`，同时保留显式 inside 行为、固定 Header/paging/bounce 架构和完整自动化验收。

**Architecture:** 只修改 `AnchorPagerHeaderConfiguration.init` 的默认参数，让 Header `.default`、整体配置 `.default`、Pager 无参数初始化和 Example 初始配置沿同一构造链自然继承。LayoutEngine、container geometry、ScrollCoordinator、OverscrollCoordinator 和裁剪层级不增加分支；Example 测试中需要 inside 的路径改为显式选择。

**Tech Stack:** Swift 6.2+、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、Tabman 4.0.1、Pageboy 5.0.2、XCTest、Swift Testing、XCUITest、Xcode 26.6。

## Global Constraints

- Package name、Library product、Module name 均保持 `AnchorPager`。
- 最低工具链保持 Swift 6.2，语言模式保持 Swift 6，最低系统版本保持 iOS 14。
- Public API 不新增、删除或重命名 symbol；只改变省略 `topBehavior` 时的默认行为。
- `.insideSafeArea` 必须继续可显式选择，并保留真实 container top inset 与 raw/logical offset 契约。
- 不修改固定 `viewportView` 裁剪、canonical content presentation、bar 吸顶或 Pageboy child bounds。
- Tabman/Pageboy 类型只允许出现在 internal adapter 层。
- 不修改业务 child 的 `UIScrollView.delegate`、pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。
- Header UIViewController containment、Pageboy page containment、Store generation/cache/snapshot 和 child managed inset ownership保持不变。
- 不新增日志事件；既有日志只反映真实状态变化，不为默认选择制造伪事件。
- 所有 UIKit/public/configuration 测试保持 MainActor 语义，不引入并发 unsafe 标记或异步延迟。
- 当前工作区已有 `Examples/AnchorPagerExample.xcodeproj/project.pbxproj` 用户改动；任何任务都不得修改、暂存、提交或回滚该文件。
- 每个实现任务使用 TDD，提交前运行 `git diff --check`，并用精确 `git add` 文件列表避免夹带用户改动。

---

## 文件结构与职责

- `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`：唯一 Public 默认值来源和对应 DocC。
- `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：无参数初始化、两级 `.default`、Pager 默认配置及显式 inside 的框架契约。
- `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`：Example 菜单默认勾选态与显式 inside → extends 几何迁移。
- `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：真实启动默认 extends、菜单切换、inside 专项折叠和 safe-area 内容路径。
- `README.md`：接入者默认行为、显式 inside 示例和“默认变化不等于取消裁剪”说明。
- `docs/requirements.md`、`docs/architecture.md`、`docs/task-list.md`、版本 roadmap：维护者长期契约和任务状态。
- `docs/superpowers/specs/2026-07-14-default-extends-under-top-safe-area-design.md`：本专项设计、实施、验收和 fresh-pass 证据。
- `AGENTS.md`：必读规格/计划索引与最终阶段门禁。

---

### Task 1：默认配置、Example 与真实 UI 的 RED→GREEN

**Files:**

- Modify: `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift:29-50`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift:2803-2812`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift:154-182`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift:260-323`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift:247-375`

**Interfaces:**

- Consumes: `AnchorPagerHeaderConfiguration.init(heightMode:topBehavior:)`、`AnchorPagerConfiguration.default`、`AnchorPagerViewController.init(configuration:)` 和 Example 现有 Header 顶部行为菜单。
- Produces: 所有默认构造路径的 `topBehavior == .extendsUnderTopSafeArea`；显式 `.insideSafeArea` 保持原语义；Example 初始菜单和真实 top inset 与 Public 默认一致。

- [ ] **Step 1：确认工作区基线并隔离用户改动**

Run:

```bash
git status --short
git diff -- Examples/AnchorPagerExample.xcodeproj/project.pbxproj
```

Expected: `project.pbxproj` 只包含用户已有的签名/平台设置差异；后续暂存列表不得包含它。

- [ ] **Step 2：把框架默认配置测试改成新契约**

把旧 `testConfigurationDefaultsMatchV01Baseline` 替换为：

```swift
@MainActor
func testConfigurationDefaultsUseExtendedHeaderTopBehavior() {
    let constructedHeader = AnchorPagerHeaderConfiguration()
    let defaultHeader = AnchorPagerHeaderConfiguration.default
    let constructedConfiguration = AnchorPagerConfiguration()
    let defaultConfiguration = AnchorPagerConfiguration.default
    let pager = AnchorPagerViewController()
    let explicitInside = AnchorPagerHeaderConfiguration(
        topBehavior: .insideSafeArea
    )

    XCTAssertEqual(constructedHeader.heightMode, .automatic(min: 0, max: nil))
    XCTAssertEqual(constructedHeader.topBehavior, .extendsUnderTopSafeArea)
    XCTAssertEqual(defaultHeader.topBehavior, .extendsUnderTopSafeArea)
    XCTAssertEqual(
        constructedConfiguration.header.topBehavior,
        .extendsUnderTopSafeArea
    )
    XCTAssertEqual(
        defaultConfiguration.header.topBehavior,
        .extendsUnderTopSafeArea
    )
    XCTAssertEqual(
        pager.configuration.header.topBehavior,
        .extendsUnderTopSafeArea
    )
    XCTAssertEqual(explicitInside.topBehavior, .insideSafeArea)
    XCTAssertNil(defaultConfiguration.bar.height)
    XCTAssertEqual(defaultConfiguration.topOverscrollHandlingMode, .container)
}
```

- [ ] **Step 3：调整 Example 单元测试的默认勾选态和显式迁移起点**

在 `pagerNavigationShowsUnifiedSettingsMenuWithCurrentConfiguration` 中把 Header action 断言改为：

```swift
#expect(headerActions.map(\.title) == ["安全区内", "延伸到顶部"])
#expect(headerActions.map(\.state) == [.off, .on])
```

在 `headerTopBehaviorMenuAppliesExtendsUnderTopSafeAreaCoverage` 取得 pager 并等待初始 selection 后，先显式建立 inside 起点：

```swift
pagerViewController.configuration.header.topBehavior = .insideSafeArea
pagerViewController.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
window.layoutIfNeeded()
#expect(pagerViewController.verticalScrollView.contentInset.top > 1)
```

其余 inside → extends 的 raw offset、Header 高度和 bar baseline 断言保持不变，确保测试验证运行时迁移而非依赖旧默认。

- [ ] **Step 4：调整真实 UI 测试，使默认验证与 inside 专项互不混淆**

在 UI 测试 helper 区新增：

```swift
private func selectHeaderTopBehavior(
    named title: String,
    in app: XCUIApplication
) {
    openSettingsSubmenu(named: "Header 顶部行为", in: app)
    let action = app.buttons[title]
    XCTAssertTrue(action.waitForExistence(timeout: 3))
    action.tap()
}
```

把 `testHeaderTopBehaviorMenuSwitchesVisibleConfiguration` 改为先验证默认 extends 与零 top inset，再切到 inside：

```swift
@MainActor
func testHeaderTopBehaviorMenuSwitchesVisibleConfiguration() throws {
    let app = XCUIApplication()
    app.launch()
    let probe = scrollCoordinationStateProbe(in: app)

    XCTAssertNotNil(waitForScrollState(from: probe) {
        $0.containerTopInset < 0.5 && $0.headerHeight > 1
    })
    openSettingsSubmenu(named: "Header 顶部行为", in: app)
    let safeAreaAction = app.buttons["安全区内"]
    let extendedAction = app.buttons["延伸到顶部"]
    XCTAssertTrue(safeAreaAction.waitForExistence(timeout: 3))
    XCTAssertTrue(extendedAction.waitForExistence(timeout: 3))
    XCTAssertTrue(extendedAction.isSelected)
    safeAreaAction.tap()

    openSettingsSubmenu(named: "Header 顶部行为", in: app)
    XCTAssertTrue(app.buttons["安全区内"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["安全区内"].isSelected)
    XCTAssertNotNil(waitForScrollState(from: probe) {
        $0.containerTopInset > 1
    })
}
```

在下列测试 `app.launch()` 后、读取初始 inside 几何前加入：

```swift
selectHeaderTopBehavior(named: "安全区内", in: app)
```

需要加入的测试：

```text
testInsideSafeAreaUsesTopInsetAndKeepsHeaderHeightDuringCollapse
testExtendsUnderTopSafeAreaUsesZeroTopInsetAndPreservesBarPosition
```

`testHeaderContentKeepsTwentyPointTopSafeAreaPaddingWhenSwitchingBehaviors` 保留默认 extends 的首次安全间距断言，然后实际切到 inside：

```swift
selectHeaderTopBehavior(named: "安全区内", in: app)

XCTAssertEqual(title.frame.minY, navigationBar.frame.maxY + 20, accuracy: 1)
XCTAssertEqual(subtitle.frame.minY - title.frame.maxY, 8, accuracy: 1)
XCTAssertLessThanOrEqual(title.frame.height, 44)
```

`testHeaderReturnsAfterTopBehaviorSwitchAndPullDown` 的两次实际切换改为：

```swift
selectHeaderTopBehavior(named: "安全区内", in: app)
selectHeaderTopBehavior(named: "延伸到顶部", in: app)
```

- [ ] **Step 5：运行 RED，确认只失败于旧默认值**

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testConfigurationDefaultsUseExtendedHeaderTopBehavior test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleTests/AnchorPagerExampleTests/pagerNavigationShowsUnifiedSettingsMenuWithCurrentConfiguration -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderTopBehaviorMenuSwitchesVisibleConfiguration test
```

Expected: Framework 精确失败于实际 `.insideSafeArea`；Example 单元/UI 精确失败于默认菜单仍勾选“安全区内”或初始 top inset 非零。编译、containment、约束和其他断言不得失败。

- [ ] **Step 6：最小修改唯一默认源和 DocC**

把 `AnchorPagerHeaderConfiguration` 初始化器改为：

```swift
/// 创建 Header 配置。
///
/// - Parameters:
///   - heightMode: Header 高度模式。
///   - topBehavior: Header 顶部绘制行为，默认为延伸到顶部系统区域。
public init(
    heightMode: AnchorPagerHeaderHeightMode = .automatic(min: 0, max: nil),
    topBehavior: AnchorPagerHeaderTopBehavior = .extendsUnderTopSafeArea
) {
    self.heightMode = heightMode
    self.topBehavior = topBehavior
}
```

不得修改 `AnchorPagerHeaderConfiguration.default`、`AnchorPagerConfiguration.default`、
`AnchorPagerViewController` 或 Example 初始化代码；这些路径必须通过现有构造链自动继承。

- [ ] **Step 7：运行聚焦 GREEN**

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleTests/AnchorPagerExampleTests -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderTopBehaviorMenuSwitchesVisibleConfiguration -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testInsideSafeAreaUsesTopInsetAndKeepsHeaderHeightDuringCollapse -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testExtendsUnderTopSafeAreaUsesZeroTopInsetAndPreservesBarPosition -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderContentKeepsTwentyPointTopSafeAreaPaddingWhenSwitchingBehaviors -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderReturnsAfterTopBehaviorSwitchAndPullDown test
```

Expected: 所列 Framework、Example 单元与 5 条 UI 测试全部通过，0 fail、0 skip。

- [ ] **Step 8：检查实现范围并提交**

Run:

```bash
git diff --check
git diff -- Sources/AnchorPager/Public/AnchorPagerConfiguration.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git status --short
```

Expected: 生产实现只有一个默认参数变化和 DocC；测试只调整默认断言及显式模式前置；
`project.pbxproj` 仍为未暂存用户改动。

Commit:

```bash
git add Sources/AnchorPager/Public/AnchorPagerConfiguration.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "默认 Header 延伸到顶部安全区域外"
```

---

### Task 2：同步默认行为文档而不提前写入最终验收结论

**Files:**

- Modify: `README.md:109-145`
- Modify: `docs/requirements.md:248-260`
- Modify: `docs/requirements.md:432-443`
- Modify: `docs/architecture.md:48-65`
- Modify: `docs/architecture.md:112-130`
- Modify: `docs/task-list.md:130-155`
- Modify: `docs/task-list.md:450-520`
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md:145-195`
- Modify: `docs/superpowers/specs/2026-07-14-default-extends-under-top-safe-area-design.md`

**Interfaces:**

- Consumes: Task 1 已通过聚焦测试的 Public 默认值和 Example 初始行为。
- Produces: 接入者与维护者一致的“默认 extends、显式 inside、裁剪架构不变”长期契约；最终全量测试数字仍保持未发布状态。

- [ ] **Step 1：更新 README 接入示例与兼容性说明**

把 Header 配置示例改为默认 extends，并单独展示显式 inside：

```swift
var configuration = AnchorPagerConfiguration.default
configuration.header.heightMode = .automatic(min: 44, max: 180)
// 默认 topBehavior 为 .extendsUnderTopSafeArea。

// 如需让 Header 背景从顶部安全区域下方开始：
configuration.header.topBehavior = .insideSafeArea

let pager = AnchorPagerViewController(configuration: configuration)
```

在随后说明中明确：默认值变更只影响未显式设置的接入；两种模式的固定 Header 高度、bar baseline 和
viewport 裁剪不变，默认 extends 不等于“折叠时不裁剪”。

- [ ] **Step 2：更新 requirements 当前默认契约**

把 Header 要求第 3 条和默认行为第 2 条分别改为：

```text
3. Header 默认延伸到顶部系统区域；需要让 Header 背景从安全区域下方开始时显式使用 insideSafeArea。
```

```text
2. Header 默认 topBehavior 为 extendsUnderTopSafeArea；insideSafeArea 继续作为显式可选模式。
```

Public API 章节补充默认参数为 `.extendsUnderTopSafeArea`，不得修改两种模式的几何公式。

- [ ] **Step 3：更新 architecture、task-list 与 roadmap**

`docs/architecture.md` 在 Public API/LayoutEngine 章节加入：

```text
AnchorPagerHeaderConfiguration 的默认 topBehavior 为 extendsUnderTopSafeArea。该默认只通过
Header 初始化器定义；两级 .default、Pager 无参数初始化和 Example 不保存第二份默认值。
```

`docs/task-list.md`：

1. 把 v0.1 的旧 inside 默认条目标记为“历史默认”，不篡改当时实施事实。
2. 在当前 v0.5/v0.6 专项记录后新增本设计确认、Task 1 聚焦 RED/GREEN 和“全量验收待 Task 3”的真实状态。

roadmap 在 Header 布局版本说明中补充当前默认已改为 extends，同时注明 Public case、geometry、owner 和
containment 均未改变。

- [ ] **Step 4：更新专项设计的实施中状态**

把设计状态改为：

```text
**状态：** 实现与聚焦 RED/GREEN 已完成；全量验收、自审和 fresh-pass 待完成
```

记录 Task 1 的真实提交、实际运行命令和聚焦结果；不得预填 Framework/Example 全量测试总数，也不得提前标记最终完成。

- [ ] **Step 5：扫描默认值矛盾并提交文档**

Run:

```bash
rg -n "默认.*insideSafeArea|默认显示在安全区域内|默认.*extendsUnderTopSafeArea|默认延伸" README.md docs AGENTS.md
git diff --check
git status --short
```

Expected: 仍命中的 inside 默认只能是明确标注的历史记录、旧规格实施步骤或显式配置示例；当前长期契约均为 extends。`project.pbxproj` 未暂存。

Commit:

```bash
git add README.md docs/requirements.md docs/architecture.md docs/task-list.md docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md docs/superpowers/specs/2026-07-14-default-extends-under-top-safe-area-design.md
git commit -m "同步 Header 默认顶部行为文档"
```

---

### Task 3：最终全量验收、自审与 fresh-pass

**Files:**

- Modify after successful gates: `AGENTS.md`
- Modify after successful gates: `README.md`
- Modify after successful gates: `docs/architecture.md`
- Modify after successful gates: `docs/requirements.md`
- Modify after successful gates: `docs/task-list.md`
- Modify after successful gates: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- Modify after successful gates: `docs/superpowers/specs/2026-07-14-default-extends-under-top-safe-area-design.md`
- Modify: `docs/superpowers/plans/2026-07-14-default-extends-under-top-safe-area.md`

**Interfaces:**

- Consumes: Task 1 的实现/测试提交和 Task 2 的行为文档提交。
- Produces: 最终生产 HEAD、完整 xcresult、运行时约束日志、静态门禁、fresh-pass 结论和真实完成状态。

- [ ] **Step 1：运行基础与完整 Framework 门禁**

Run:

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -resultBundlePath /private/tmp/AnchorPagerDefaultHeaderFramework-20260714.xcresult test
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerDefaultHeaderFramework-20260714.xcresult
xcrun xcresulttool get build-results issues --path /private/tmp/AnchorPagerDefaultHeaderFramework-20260714.xcresult
```

Expected: resolve/test exit 0，Framework 0 fail、0 skip，issue summary 为 0 error、0 warning、0 analyzer warning。记录工具返回的真实测试总数。

- [ ] **Step 2：运行完整 Example 单元/UI 与 generic build**

Run:

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -resultBundlePath /private/tmp/AnchorPagerDefaultHeaderExample-20260714.xcresult test
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerDefaultHeaderExample-20260714.xcresult
xcrun xcresulttool get build-results issues --path /private/tmp/AnchorPagerDefaultHeaderExample-20260714.xcresult
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -resultBundlePath /private/tmp/AnchorPagerDefaultHeaderBuild-20260714.xcresult build
xcrun xcresulttool get build-results issues --path /private/tmp/AnchorPagerDefaultHeaderBuild-20260714.xcresult
```

Expected: Example 全部测试 0 fail、0 skip；generic build 成功；两份 issue summary 均为 0 error、0 warning、0 analyzer warning。分别记录单元与 UI 的真实数量。

- [ ] **Step 3：捕获默认启动与显式 inside 的运行时约束日志**

Run:

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderTopBehaviorMenuSwitchesVisibleConfiguration -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testInsideSafeAreaUsesTopInsetAndKeepsHeaderHeightDuringCollapse test > /private/tmp/AnchorPagerDefaultHeaderRuntime-20260714.log 2>&1
rg -n "Unable to simultaneously satisfy constraints|UIViewAlertForUnsatisfiableConstraints" /private/tmp/AnchorPagerDefaultHeaderRuntime-20260714.log
```

Expected: 第一条命令 exit 0；第二条无匹配输出。若出现约束冲突，先补 RED 并修复，不得在验收文档中豁免。

- [ ] **Step 4：执行静态架构门禁**

Run:

```bash
rg -n "\.delegate\s*=|panGestureRecognizer\.delegate\s*=|isScrollEnabled\s*=|\.bounces\s*=|alwaysBounceVertical\s*=" Sources/AnchorPager
rg -n "Tabman|Pageboy" Sources/AnchorPager/Public
rg -n "topBehavior: AnchorPagerHeaderTopBehavior =" Sources Tests Examples
rg -n "default.*insideSafeArea|默认.*insideSafeArea|默认显示在安全区域内" README.md docs AGENTS.md
git diff --check
```

Expected:

1. delegate/bounce 写入只命中 AnchorPager 自有 `verticalScrollView`，不得命中业务 child。
2. Public 目录没有 Tabman/Pageboy。
3. 生产 Public 默认只命中 `.extendsUnderTopSafeArea`；测试夹具可显式保留 inside 以隔离几何。
4. inside 默认文档命中只能是明确历史记录或迁移说明。
5. `git diff --check` 通过。

- [ ] **Step 5：做实现者自审和 fresh-pass**

Review range:

```bash
git diff 97e8fc2...HEAD -- Sources Tests Examples README.md docs AGENTS.md
```

逐项确认：

1. 默认值只有 `AnchorPagerHeaderConfiguration.init` 一个来源。
2. 没有为了默认变化修改 LayoutEngine、container geometry、ScrollCoordinator、OverscrollCoordinator 或裁剪层。
3. 显式 inside 的 top inset、raw 展开边界、Header 固定高度和 bar baseline 仍有测试。
4. Example 初始 extends、inside 切换和 safe-area 内容均由真实 UI 覆盖。
5. Public symbol、Header/Pageboy containment、Store、managed inset、业务 child ownership 和并发边界未变化。
6. 没有新增日志事件或逐帧输出。
7. 文档没有把默认 extends 描述成取消裁剪。
8. `project.pbxproj` 用户改动未进入任一专项提交。

若发现 Critical/Important 或行为 Minor，必须先写 RED、完成最小修复、重跑受影响门禁并单独提交；未清零前不进入下一步。

- [ ] **Step 6：写入真实最终结果并关闭专项**

只有 Step 1–5 全部通过后，才更新 AGENTS、README、requirements、architecture、task-list、roadmap、设计状态和本计划勾选项。记录内容必须来自本轮命令输出：

1. 最终生产代码 HEAD。
2. Framework、Example 单元/UI 的真实总数、0 fail、0 skip。
3. 三份 xcresult 路径与 0 error/warning/analyzer warning。
4. runtime log 路径与约束关键字零命中。
5. fresh-pass 的 Critical/Important/Minor 结论。
6. 明确新默认不改变 viewport 裁剪或 v0.5/v0.6 Ready 架构门禁。

- [ ] **Step 7：最终一致性检查并提交验收状态**

Run:

```bash
rg -n "默认.*insideSafeArea|默认显示在安全区域内|全量验收.*待|fresh-pass.*待" AGENTS.md README.md docs
git diff --check
git status --short
```

Expected: 当前态没有旧默认或待验收矛盾；历史文字均有历史标记；工作区只剩用户原有 `project.pbxproj` 修改。

Commit:

```bash
git add AGENTS.md README.md docs/requirements.md docs/architecture.md docs/task-list.md docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md docs/superpowers/specs/2026-07-14-default-extends-under-top-safe-area-design.md docs/superpowers/plans/2026-07-14-default-extends-under-top-safe-area.md
git commit -m "完成 Header 默认顶部行为验收"
```

---

## 最终完成标准

1. `AnchorPagerHeaderConfiguration()`、两级 `.default`、Pager 无参数配置和 Example 初始配置统一为 `.extendsUnderTopSafeArea`。
2. 显式 `.insideSafeArea` 的 top inset、raw/logical offset、Header 固定高度和 bar baseline 保持现有契约。
3. 默认 extends 的真实启动背景、安全区内容、菜单勾选和 zero top inset 有自动化证据。
4. 固定 viewport 裁剪、canonical presentation、Pageboy child bounds、plain/真实 child bounce owner 不变。
5. Public API 不扩大，Tabman/Pageboy 不泄漏，业务 child delegate/pan/bounce ownership 不改变。
6. Framework、Example 单元/UI、generic build、运行时约束、静态扫描、`git diff --check`、自审和 fresh-pass 全部通过。
7. README、requirements、architecture、task-list、roadmap、AGENTS、设计与计划均记录真实最终状态。
8. 用户已有 `project.pbxproj` 改动始终未被本专项修改、暂存、提交或回滚。
