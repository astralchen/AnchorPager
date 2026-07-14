# Example 统一设置菜单 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Example 导航栏中独立的 Header 顶部行为和顶部回弹按钮合并为单个齿轮设置入口，用两个标准二级菜单切换配置并保持现有运行时语义。

**Architecture:** `ExamplePagerViewController` 只保存一个 `settingsItem`，其菜单始终从 `pagerViewController.configuration` 同步重建；Header 行为继续走 `.preserveVisualPosition` 布局刷新，顶部 mode 继续走 configuration didSet、探针 mode 更新和 presentation 指标清零。框架模块、Public API、owner、offset、containment、inset 与日志均不改变。

**Tech Stack:** Swift 6.2+、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、XCTest、Swift Testing、XCUITest、Xcode 26.6。

## Global Constraints

- Package、Library product 与 Module name 保持 `AnchorPager`；最低工具链 Swift 6.2、语言模式 Swift 6、最低系统 iOS 14。
- 只修改 Example、Example tests 和长期文档；不修改 `Sources/AnchorPager/` 或任何 Public API。
- 根菜单固定包含“Header 顶部行为”“顶部回弹模式”两个标准嵌套 `UIMenu`，不使用 `.displayInline` 展平。
- 设置 item 优先显示 `gearshape`；图像意外不可用时显示“设置”文本，`accessibilityLabel` 始终为“示例设置”。
- 菜单勾选态只读取 `pagerViewController.configuration`，不得保存第二份 Header behavior 或 top mode 状态。
- `.child` + nil scroll target 继续不可用且不回退；菜单不创建 synthetic scroll target，不写 offset/bounce/delegate/pan delegate。
- UIAction closure 使用弱引用；不新增设置控制器、持久化、异步 deferred menu 或框架日志。
- 所有用户可见行为先写并运行失败测试，再写生产代码；完整 UI 回归、generic build、自审和文档状态必须在同一任务周期完成。

---

## 文件与职责

- `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`：统一设置 item、根菜单、两个子菜单和同步重建入口。
- `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`：菜单树、默认勾选态、Header/mode action 与重建状态的同进程测试。
- `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：真实打开齿轮二级菜单，切换 Header behavior 和 top mode。
- `README.md`：更新 Example 可交互配置入口说明。
- `docs/task-list.md`：记录 RED/GREEN、UI、完整验收和自审证据。
- `docs/superpowers/specs/2026-07-14-example-unified-settings-menu-design.md`：完成后更新规格状态与证据。
- `docs/superpowers/plans/2026-07-14-example-unified-settings-menu.md`：勾选执行步骤并记录实际命令、结果和提交。
- `AGENTS.md`：登记本实施计划，保证后续代理执行或复审时必读。

---

### Task 1：以 TDD 合并 Example 设置菜单并覆盖真实交互

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift:101-199`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift:240-325,578-625`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift:14-16,64-224`

**Interfaces:**
- Consumes: `AnchorPagerViewController.configuration.header.topBehavior`、`configuration.topOverscrollHandlingMode`、`reloadHeaderLayout(offsetAdjustment:)` 与现有 `ExampleScrollCoordinationState` 探针。
- Produces: Example internal `makeSettingsItem() -> UIBarButtonItem`、`makeSettingsMenu() -> UIMenu`、`updateSettingsMenu()`；不产生框架 API。

- [x] **Step 1：先把单元测试改成统一菜单契约**

在 `AnchorPagerExampleTests` 中用以下两个测试替换旧的两个独立菜单测试：

```swift
@Test func pagerNavigationShowsUnifiedSettingsMenuWithCurrentConfiguration() throws {
    let viewController = ExamplePagerViewController()
    viewController.loadViewIfNeeded()

    let items = viewController.navigationItem.rightBarButtonItems ?? []
    let settingsItem = try #require(items.first {
        $0.accessibilityLabel == "示例设置"
    })
    let submenus = settingsItem.menu?.children.compactMap { $0 as? UIMenu } ?? []
    let headerMenu = try #require(submenus.first { $0.title == "Header 顶部行为" })
    let overscrollMenu = try #require(submenus.first { $0.title == "顶部回弹模式" })
    let headerActions = headerMenu.children.compactMap { $0 as? UIAction }
    let overscrollActions = overscrollMenu.children.compactMap { $0 as? UIAction }

    #expect(items.count == 3)
    #expect(items.contains { $0.accessibilityLabel == "打开 AnchorPager" })
    #expect(items.contains { $0.accessibilityLabel == "重新加载页面" })
    #expect(!items.contains { $0.accessibilityLabel == "Header 顶部行为" })
    #expect(!items.contains { $0.accessibilityLabel == "顶部回弹" })
    #expect(settingsItem.image != nil || settingsItem.title == "设置")
    #expect(submenus.map(\.title) == ["Header 顶部行为", "顶部回弹模式"])
    #expect(headerActions.map(\.title) == ["安全区内", "延伸到顶部"])
    #expect(headerActions.map(\.state) == [.on, .off])
    #expect(overscrollActions.map(\.title) == ["关闭", "容器", "子页面"])
    #expect(overscrollActions.map(\.state) == [.off, .on, .off])
}

@Test func unifiedSettingsMenuSwitchesTopOverscrollModesAndRefreshesSelection() throws {
    guard #available(iOS 16.0, *) else { return }
    let viewController = ExamplePagerViewController()
    viewController.loadViewIfNeeded()
    let pager = try #require(
        viewController.children.compactMap { $0 as? AnchorPagerViewController }.first
    )

    let stateProbe = try #require(
        firstSubview(in: viewController.view, as: UIButton.self) {
            $0.accessibilityIdentifier == "scroll-coordination-state"
        }
    )

    for (title, expectedMode, expectedIdentifier) in [
        ("关闭", AnchorPagerTopOverscrollHandlingMode.none, "none"),
        ("子页面", .child, "child"),
        ("容器", .container, "container")
    ] {
        let settingsItem = try #require(
            viewController.navigationItem.rightBarButtonItems?.first {
                $0.accessibilityLabel == "示例设置"
            }
        )
        let menu = try #require(
            settingsItem.menu?.children.compactMap { $0 as? UIMenu }.first {
                $0.title == "顶部回弹模式"
            }
        )
        let action = try #require(
            menu.children.compactMap { $0 as? UIAction }.first { $0.title == title }
        )

        action.performWithSender(nil, target: nil)

        #expect(pager.configuration.topOverscrollHandlingMode == expectedMode)
        #expect(
            stateProbe.accessibilityValue?.contains("mode=\(expectedIdentifier)") == true
        )
        let refreshedMenu = try #require(
            settingsItem.menu?.children.compactMap { $0 as? UIMenu }.first {
                $0.title == "顶部回弹模式"
            }
        )
        let refreshedActions = refreshedMenu.children.compactMap { $0 as? UIAction }
        #expect(refreshedActions.filter { $0.state == .on }.map(\.title) == [title])
    }
}
```

同时把 `headerTopBehaviorMenuAppliesExtendsUnderTopSafeAreaCoverage` 取得 action 的片段改为从统一设置 item 的 Header 子菜单读取：

```swift
let settingsItem = try #require(
    viewController.navigationItem.rightBarButtonItems?.first {
        $0.accessibilityLabel == "示例设置"
    }
)
let headerMenu = try #require(
    settingsItem.menu?.children.compactMap { $0 as? UIMenu }.first {
        $0.title == "Header 顶部行为"
    }
)
let extendsAction = try #require(
    headerMenu.children.compactMap { $0 as? UIAction }.first {
        $0.title == "延伸到顶部"
    }
)
```

在执行 `extendsAction` 并完成布局后，再从同一个 `settingsItem.menu` 重新取得 Header 子菜单，断言重建后的状态为 `[.off, .on]`，避免只验证几何而漏掉勾选态刷新：

```swift
let refreshedHeaderMenu = try #require(
    settingsItem.menu?.children.compactMap { $0 as? UIMenu }.first {
        $0.title == "Header 顶部行为"
    }
)
#expect(
    refreshedHeaderMenu.children.compactMap { $0 as? UIAction }.map(\.state)
        == [.off, .on]
)
```

- [x] **Step 2：先更新真实 UI 测试，使其要求齿轮二级菜单**

新增一条 top mode 真实交互测试，不替换既有 Header 行为覆盖：

```swift
@MainActor
func testUnifiedSettingsMenuSwitchesTopOverscrollMode() throws {
    let app = XCUIApplication()
    app.launch()
    let probe = scrollCoordinationStateProbe(in: app)
    XCTAssertNotNil(waitForScrollState(from: probe) {
        $0.mode == "container" && $0.hasZeroPresentationMetrics
    })

    openSettingsSubmenu(named: "顶部回弹模式", in: app)
    let childAction = app.buttons["子页面"]
    XCTAssertTrue(childAction.waitForExistence(timeout: 3))
    childAction.tap()

    XCTAssertNotNil(waitForScrollState(from: probe) {
        $0.mode == "child" && $0.hasZeroPresentationMetrics
    })
}
```

把既有 `testHeaderTopBehaviorMenuSwitchesVisibleConfiguration`、`testHeaderContentKeepsTwentyPointTopSafeAreaPaddingWhenSwitchingBehaviors` 和 `testHeaderReturnsAfterTopBehaviorSwitchAndPullDown` 三条 Header 菜单 UI 测试中直接点击 `behaviorButton` 的代码改为：

```swift
openSettingsSubmenu(named: "Header 顶部行为", in: app)
let extendedAction = app.buttons["延伸到顶部"]
XCTAssertTrue(extendedAction.waitForExistence(timeout: 3))
extendedAction.tap()
```

其中 `testHeaderTopBehaviorMenuSwitchesVisibleConfiguration` 不再读取已删除文本 item 的 `accessibilityValue`；改为首次打开时断言“安全区内”已选中，选择“延伸到顶部”后重新打开子菜单并断言“延伸到顶部”已选中：

```swift
openSettingsSubmenu(named: "Header 顶部行为", in: app)
XCTAssertTrue(app.buttons["安全区内"].isSelected)
app.buttons["延伸到顶部"].tap()

openSettingsSubmenu(named: "Header 顶部行为", in: app)
XCTAssertTrue(app.buttons["延伸到顶部"].isSelected)
```

`testHeaderReturnsAfterTopBehaviorSwitchAndPullDown` 切回安全区时再次调用 helper：

```swift
openSettingsSubmenu(named: "Header 顶部行为", in: app)
XCTAssertTrue(app.buttons["安全区内"].waitForExistence(timeout: 3))
app.buttons["安全区内"].tap()
```

在 UI test 类的 private helper 区新增：

```swift
@MainActor
private func openSettingsSubmenu(named title: String, in app: XCUIApplication) {
    let settingsButton = app.navigationBars["AnchorPager"].buttons["示例设置"]
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
    settingsButton.tap()

    let submenu = app.buttons[title]
    XCTAssertTrue(submenu.waitForExistence(timeout: 3))
    submenu.tap()
}
```

- [x] **Step 3：运行 RED，确认失败来自统一设置入口尚不存在**

运行 Example 单元测试：

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleTests test
```

预期：FAIL；`pagerNavigationShowsUnifiedSettingsMenuWithCurrentConfiguration`、mode 切换测试和 Header action 测试均因找不到 `accessibilityLabel == "示例设置"` 失败，而不是编译错误或模拟器启动错误。

再运行新增 UI 用例：

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testUnifiedSettingsMenuSwitchesTopOverscrollMode test
```

预期：FAIL；失败点为导航栏不存在“示例设置”按钮。

- [x] **Step 4：实现最小统一设置菜单**

在 `ExamplePagerViewController` 中把两个 item 属性替换为：

```swift
private var settingsItem: UIBarButtonItem?
```

把 `installNavigationItem()` 中两个配置 item 的建立和数组替换为：

```swift
let settingsItem = makeSettingsItem()
self.settingsItem = settingsItem

navigationItem.rightBarButtonItems = [
    pushItem,
    settingsItem,
    reloadItem
]
```

删除 `makeHeaderTopBehaviorItem()`、`makeTopOverscrollHandlingItem()`、`updateHeaderTopBehaviorItem()` 和 `updateTopOverscrollHandlingItem()`，新增：

```swift
private func makeSettingsItem() -> UIBarButtonItem {
    let image = UIImage(systemName: "gearshape")
    let item = UIBarButtonItem(
        title: image == nil ? "设置" : nil,
        image: image,
        primaryAction: nil,
        menu: makeSettingsMenu()
    )
    item.accessibilityLabel = "示例设置"
    return item
}

private func makeSettingsMenu() -> UIMenu {
    UIMenu(
        title: "示例设置",
        children: [
            makeHeaderTopBehaviorMenu(),
            makeTopOverscrollHandlingMenu()
        ]
    )
}

private func updateSettingsMenu() {
    settingsItem?.menu = makeSettingsMenu()
}
```

把 `makeTopOverscrollHandlingMenu()` 的标题改为：

```swift
title: "顶部回弹模式"
```

把两个 setter 的刷新调用统一为：

```swift
updateSettingsMenu()
```

其他配置写入、Header layout refresh、探针 mode 和 presentation reset 代码保持原样。

- [x] **Step 5：运行 GREEN 单元测试**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleTests test
```

预期：Example 单元测试全部 PASS，0 fail、0 skip、0 warning。

- [x] **Step 6：运行新增及相邻真实菜单 UI GREEN**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testUnifiedSettingsMenuSwitchesTopOverscrollMode \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderTopBehaviorMenuSwitchesVisibleConfiguration \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderContentKeepsTwentyPointTopSafeAreaPaddingWhenSwitchingBehaviors \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderReturnsAfterTopBehaviorSwitchAndPullDown \
  test
```

预期：4 条真实 UI 全部 PASS；齿轮入口、两个二级菜单、top mode 探针更新、Header 勾选态、双向切换和回弹恢复均正常。

- [x] **Step 7：自审并提交 Task 1**

自审确认：

1. 生产修改只在 Example target；`Sources/AnchorPager/` 无变化。
2. configuration 是菜单勾选态唯一事实；probe 不反向驱动配置。
3. Header setter 保留 `.preserveVisualPosition`，top mode setter 保留 reset/reconcile 语义。
4. UIAction 使用 `[weak self]`，没有新增 controller/item/menu retain cycle。
5. 没有设置 child delegate/pan/bounce/offset，没有修改 containment、inset、snapshot 或日志。

```bash
git diff --check
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "统一示例设置菜单"
```

**Task 1 执行记录（2026-07-14）：**

- Example 单元基线退出码 0。
- 修改测试后的单元 RED 精确失败 3 条：统一菜单结构、顶部 mode 切换、Header action；消除测试自身类型转换警告后复跑仍为同样 3 条预期失败。
- 新增真实菜单 UI RED 精确失败于等待“示例设置”按钮，1 fail、0 unexpected；结果包 `/private/tmp/AnchorPagerUnifiedSettingsUIRed-20260714-1143.xcresult`。
- 最小实现后 Example 单元测试退出码 0；新增 mode UI 与 3 条 Header 相邻 UI 共 4 条退出码 0。
- 自审确认仅修改三个 Example 文件，未触达 `Sources/AnchorPager/`、Public API、containment、scroll/inset/owner、日志或业务 child delegate/bounce。
- 实现与测试提交：`7b1b6f7 统一示例设置菜单`。

---

### Task 2：同步文档、完整验收与最终复审

**Files:**
- Modify: `README.md:215-220`
- Modify: `docs/task-list.md:496-500`
- Modify: `docs/superpowers/specs/2026-07-14-example-unified-settings-menu-design.md:5,130-149`
- Modify: `docs/superpowers/plans/2026-07-14-example-unified-settings-menu.md`

**Interfaces:**
- Consumes: Task 1 的齿轮设置入口和通过的 Example RED/GREEN 证据。
- Produces: 完整 Example/UI/build、相邻 Framework 回归、自审和 Ready 文档终态。

- [x] **Step 1：更新接入者与长期状态文档**

在 README 的 Example 段落明确：

```markdown
示例导航栏使用单个“示例设置”齿轮菜单切换 Header 顶部行为和顶部回弹模式；两组配置位于独立二级菜单，当前值以勾选态显示，切换后立即应用。
```

在 `docs/task-list.md` 将实施项更新为实际提交、RED/GREEN 和 UI 证据；在设计规格和本计划中只登记已经运行的命令与结果，不提前填写通过数或 Ready。

- [x] **Step 2：运行相邻 Framework mode 回归**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testRuntimeTopModeChangeCancelsContainerPresentationAndKeepsChildConfiguration test
```

预期：PASS，证明 Example 改为统一入口没有绕开框架现有运行时 mode reconcile 契约。

- [x] **Step 3：运行完整 Example 单元/UI**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -resultBundlePath /private/tmp/AnchorPagerExampleUnifiedSettingsFull-20260714.xcresult test
```

预期：全部 Example 单元/UI PASS，0 fail、0 skip；解析 xcresult 并记录实际总数、单元/UI 数、error/warning/analyzer warning。

- [x] **Step 4：运行 Example generic Simulator build**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -resultBundlePath /private/tmp/AnchorPagerExampleUnifiedSettingsBuild-20260714.xcresult build
```

预期：build succeeded，0 error、0 warning、0 analyzer warning。若沙箱阻止 Xcode/SwiftPM 缓存或 CoreSimulator，使用同一命令获准重试并如实记录首次环境失败。

- [x] **Step 5：运行最终静态门禁与实现者自审**

```bash
git diff --check
git status --short
rg -n 'headerTopBehaviorItem|topOverscrollHandlingItem' Examples/AnchorPagerExample/AnchorPagerExample
rg -n 'accessibilityLabel == "Header 顶部行为"|accessibilityLabel == "顶部回弹"' Examples/AnchorPagerExample/AnchorPagerExample
git diff --name-only HEAD~1..HEAD
```

结果：生产 target 的旧属性/旧独立 item 扫描零命中；测试 target 仅保留两条“旧入口必须不存在”的负向断言；实现提交只触达三个 Example 文件。自审覆盖 Public API、框架源码、containment/lifecycle、scroll/inset/owner、actor 隔离、闭包生命周期、可访问性、测试和文档。

- [x] **Step 6：执行与实现步骤分离的 fresh-pass 复审**

复审 Task 1 提交，重点检查：

1. 二级菜单没有被 `.displayInline` 展平，顺序和标题与规格一致。
2. 每次 action 后从 configuration 重建菜单，不存在 stale checkmark。
3. Header 与 top mode 两条既有副作用没有丢失或重复。
4. XCUITest 通过真实齿轮/子菜单操作，不使用 launch argument 冒充菜单交互。
5. 没有扩大 Example 或框架测试专用 API。

Critical/Important 必须修复并重跑受影响测试；Minor 要么修复，要么在计划中记录明确不阻塞理由。

- [x] **Step 7：写入真实验收证据并提交文档**

只有 Step 2–6 全部通过后，才把设计状态改为完成，在 task-list 勾选统一设置菜单实施和验收，并记录实际结果包、测试总数、工具链、提交和复审结论。

```bash
git diff --check
git add README.md docs/task-list.md docs/superpowers/specs/2026-07-14-example-unified-settings-menu-design.md docs/superpowers/plans/2026-07-14-example-unified-settings-menu.md
git commit -m "完成示例设置菜单验收"
```

**Task 2 执行记录（2026-07-14）：**

- Framework 相邻 mode 回归退出码 0。
- 完整 Example 结果包 `/private/tmp/AnchorPagerExampleUnifiedSettingsFull-20260714.xcresult`：38/38（10 单元 + 28 UI）、0 fail、0 skip；build-results summary 为 0 error、0 warning、0 analyzer warning。
- generic Simulator 构建结果包 `/private/tmp/AnchorPagerExampleUnifiedSettingsBuild-20260714.xcresult`：status succeeded，0 error、0 warning、0 analyzer warning。
- 静态门禁确认生产 target 无旧独立 item；Task 1 提交只包含三个 Example 文件，`Sources/AnchorPager/` 零变化。
- fresh-pass 复审覆盖标准嵌套菜单、configuration 唯一事实、同步菜单重建、Header/mode 副作用、弱引用、真实 XCUITest 和架构边界；结论 Critical 0、Important 0、Minor 0。
- 验收工具链：Xcode 26.6（17F113）、Apple Swift 6.3.3；测试设备 iPhone 17 Pro / iOS 26.5。

---

## 最终完成定义

- [x] 单个齿轮 item 替换两个独立配置文本 item，导航栏其余入口不变。
- [x] 标准二级菜单标题、顺序、默认值和唯一勾选态符合规格。
- [x] Header behavior 与 top mode 的 action、副作用和菜单重建全部通过同进程测试。
- [x] 真实 XCUITest 从齿轮进入子菜单并把 mode 从 container 切换到 child。
- [x] 既有 Header 安全区、双向行为切换和回弹恢复 UI 用例通过新入口。
- [x] Example 完整单元/UI、generic build、相邻 Framework mode 回归和 `git diff --check` 均有新鲜证据。
- [x] 实现者自审与 fresh-pass 复审清零 Critical/Important，长期文档只标记真实状态。

## 计划自审记录（2026-07-14）

- [x] 规格覆盖：齿轮入口、图像降级、两个标准二级菜单、唯一状态源、Header/mode 副作用、弱引用、单元/UI/文档均映射到任务。
- [x] TDD 顺序：所有新菜单结构、mode 切换和旧 Header UI 路径先改测试并运行 RED，生产实现位于 RED 之后。
- [x] 类型一致：`makeSettingsItem()`、`makeSettingsMenu()`、`updateSettingsMenu()` 在 Task 1 唯一定义，后续步骤名称一致。
- [x] 回归覆盖：3 条旧 Header 菜单 UI 路径全部保留并改走统一 helper，另新增 1 条 top mode 真实交互；单元 Header action 同步改走子菜单。
- [x] 边界覆盖：没有框架源码/Public API/containment/owner/inset/logging 变更；`.child` + nil 语义保持。
- [x] 占位符扫描：计划没有 TBD、TODO、未选方案、设备占位或未定义方法；目标设备固定为 iPhone 17 Pro / iOS 26.5。
- [x] 实施后复审：实现与计划一致；修正静态扫描范围后没有生产残留，Critical 0、Important 0、Minor 0。
