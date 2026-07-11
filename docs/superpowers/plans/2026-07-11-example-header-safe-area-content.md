# ExampleHeaderView 安全区内容布局实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让示例 Header 的标题和副标题在两种顶部行为下都明确使用安全区域上下各 20 pt 的内容间距，同时保留蓝色背景延伸和现有 UIKit bounce。

**Architecture:** AnchorPager 继续只决定 Header 外框、分段栏和页面 viewport 的几何；`ExampleHeaderView` 单独负责自身内容位置。左右约束保留 `layoutMarginsGuide`，上下约束改为 `safeAreaLayoutGuide`，不修改框架布局引擎、automatic 中立测量或 presentation bounce。

**Tech Stack:** Swift 6、iOS 14+、UIKit、Swift Package Manager、Tabman `4.0.1`、Pageboy `5.0.2`、Swift Testing、XCTest、XCUITest。

## Global Constraints

- Package name、Library product、Module name 均为 `AnchorPager`。
- Minimum OS 为 iOS 14，Language 为 Swift 6，UI stack 为 UIKit。
- 不修改 AnchorPager Public API、LayoutEngine、Header host、paging adapter、containment 或 lifecycle。
- 蓝色 Header 背景继续覆盖 `ExampleHeaderView.bounds`；只调整标题栈的纵向约束。
- 左右继续使用 `layoutMarginsGuide`，上下使用 `safeAreaLayoutGuide`，上下常量保持 20 pt。
- 不修改 `additionalSafeAreaInsets`、`insetsLayoutMarginsFromSafeArea` 或设备专用高度。
- 不改变主容器 scroll range、viewport transform、bounce、child inset 或 overscroll owner。
- 所有生产代码变更必须先看到对应测试按预期失败。
- 复用 Booted iPhone 17 `28B089AA-A03D-49CE-A037-D999D84E9606`，不主动 shutdown、reboot、erase 或 clean。

## File Structure

- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`：同进程验证标题栈相对 Header safe area 的上下间距和 extends 外框起点。
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：真实应用中验证两种顶部行为的标题顶部安全区间距。
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`：把 `ExampleHeaderView` 标题栈上下约束改到 `safeAreaLayoutGuide`。
- Modify: `docs/superpowers/specs/2026-07-11-example-header-safe-area-content-design.md`：记录实施、测试和自审结果。
- Modify: `docs/task-list.md`：登记 v0.2 示例安全区内容 follow-up 的真实完成状态。
- Modify: `AGENTS.md`：登记本计划为涉及示例 Header 安全区内容布局时的必读计划。

---

### Task 1: 测试先行实现 ExampleHeaderView 安全区内容约束

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift:202-207`

**Interfaces:**
- Consumes: `AnchorPagerHeaderTopBehavior`、`AnchorPagerViewController.reloadHeaderLayout(offsetAdjustment:)`
- Produces: `ExampleHeaderView` 标题栈相对 `safeAreaLayoutGuide` 的 20 pt 上下间距
- Preserves: Header 蓝色背景 bounds、双顶部行为外框语义、分段栏基线和 viewport bounce

- [x] **Step 1: 新增同进程安全区布局回归测试**

在 `AnchorPagerExampleTests` 中新增：

```swift
@Test func headerContentUsesSafeAreaForVerticalPaddingInBothTopBehaviors() throws {
    let viewController = ExamplePagerViewController()
    let navigationController = UINavigationController(rootViewController: viewController)
    let tabBarController = UITabBarController()
    tabBarController.viewControllers = [navigationController]
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = tabBarController
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    viewController.loadViewIfNeeded()
    window.layoutIfNeeded()
    let pagerViewController = try #require(
        viewController.children.compactMap { $0 as? AnchorPagerViewController }.first
    )
    let titleLabel = try #require(
        firstSubview(in: pagerViewController.view, as: UILabel.self) {
            $0.text == "AnchorPager Example"
        }
    )
    let stackView = try #require(titleLabel.superview as? UIStackView)
    let headerView = try #require(stackView.superview)
    let layoutProbe = LayoutProbe()
    pagerViewController.delegate = layoutProbe

    for behavior in [
        AnchorPagerHeaderTopBehavior.insideSafeArea,
        .extendsUnderTopSafeArea
    ] {
        pagerViewController.configuration.header.topBehavior = behavior
        pagerViewController.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
        window.layoutIfNeeded()

        let safeAreaFrame = headerView.safeAreaLayoutGuide.layoutFrame
        #expect(abs(stackView.frame.minY - (safeAreaFrame.minY + 20)) < 0.5)
        #expect(abs(stackView.frame.maxY - (safeAreaFrame.maxY - 20)) < 0.5)

        if behavior == .extendsUnderTopSafeArea {
            let context = try #require(layoutProbe.layoutContexts.last)
            #expect(abs(context.headerFrame.minY) < 0.5)
        }
    }
}
```

在测试文件末尾新增只遍历真实 UIKit 层级的 helper：

```swift
@MainActor
private func firstSubview<T: UIView>(
    in rootView: UIView,
    as type: T.Type,
    matching predicate: (T) -> Bool
) -> T? {
    if let rootView = rootView as? T, predicate(rootView) {
        return rootView
    }
    for subview in rootView.subviews {
        if let match = firstSubview(in: subview, as: type, matching: predicate) {
            return match
        }
    }
    return nil
}
```

- [x] **Step 2: 新增真实应用 UI 回归测试**

在 `AnchorPagerExampleUITests` 中新增：

```swift
@MainActor
func testHeaderContentKeepsTwentyPointTopSafeAreaPaddingWhenSwitchingBehaviors() throws {
    let app = XCUIApplication()
    app.launch()

    let navigationBar = app.navigationBars["AnchorPager"]
    let title = app.staticTexts["AnchorPager Example"]
    let behaviorButton = navigationBar.buttons["Header 顶部行为"]
    XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
    XCTAssertTrue(title.waitForExistence(timeout: 3))
    XCTAssertTrue(behaviorButton.waitForExistence(timeout: 3))
    XCTAssertEqual(title.frame.minY, navigationBar.frame.maxY + 20, accuracy: 1)

    behaviorButton.tap()
    let extendedAction = app.buttons["延伸到顶部"]
    XCTAssertTrue(extendedAction.waitForExistence(timeout: 3))
    extendedAction.tap()

    XCTAssertEqual(title.frame.minY, navigationBar.frame.maxY + 20, accuracy: 1)
}
```

- [x] **Step 3: 运行两个目标测试并确认 RED**

先运行同进程测试：

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-example-header-safe-area -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerExampleTests/AnchorPagerExampleTests/headerContentUsesSafeAreaForVerticalPaddingInBothTopBehaviors test
```

再运行 UI 测试：

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-example-header-safe-area -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderContentKeepsTwentyPointTopSafeAreaPaddingWhenSwitchingBehaviors test
```

Expected: 两个测试都因标题栈当前使用 `layoutMarginsGuide` 而失败；实际顶部间距包含系统 layout margin，不等于 safe area 上方 20 pt。失败必须是布局断言，不得是测试装配或元素查找错误。

- [x] **Step 4: 实现最小安全区约束修改**

只修改 `ExampleHeaderView.configure()` 中的纵向约束：

```swift
NSLayoutConstraint.activate([
    stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
    stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
    stackView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
    stackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
])
```

- [x] **Step 5: 重跑两个目标测试并确认 GREEN**

Run: Step 3 的两个命令。

Expected: 同进程测试与 UI 测试均通过；extends context 的 `headerFrame.minY == 0`，证明只移动内容约束，没有改变 Header 外框。

- [x] **Step 6: 自审并提交 Task 1**

确认 diff 只包含两个测试文件和 `ExamplePagerViewController.swift`；没有修改 Public API、框架 Sources、Header 高度模式、滚动范围或 bounce。

```bash
git diff --check
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "调整示例 Header 内容到安全区域"
```

---

### Task 2: 文档、完整验证与最终自审

**Files:**
- Modify: `docs/superpowers/specs/2026-07-11-example-header-safe-area-content-design.md`
- Modify: `docs/superpowers/plans/2026-07-11-example-header-safe-area-content.md`
- Modify: `docs/task-list.md`

**Interfaces:**
- Consumes: Task 1 的安全区约束和 RED/GREEN 证据
- Produces: v0.2 示例安全区 follow-up 的长期实施与验收记录
- Preserves: 已完成的 v0.2 核心契约和后续版本边界

- [x] **Step 1: 同步长期文档**

在设计文档增加“实施记录”，写明：

- 标题栈左右仍使用 `layoutMarginsGuide`，上下改用 `safeAreaLayoutGuide`。
- 蓝色背景、Header 外框、分段栏基线和 viewport bounce 未修改。
- 同进程测试覆盖上下 20 pt safe-area 间距和 extends 外框起点。
- UI 测试覆盖 inside → extends 后标题仍位于导航栏下方 20 pt。

在 `docs/task-list.md` 的 v0.2 区域和当前执行入口增加已完成 follow-up，引用本计划。

- [x] **Step 2: 运行完整框架测试**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-example-header-safe-area-core -parallel-testing-enabled NO -enableCodeCoverage NO test
```

Expected: 83 tests、0 failures、0 skipped。

- [x] **Step 3: 运行完整示例测试**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-example-header-safe-area -parallel-testing-enabled NO -enableCodeCoverage NO test
```

Expected: 原 11 个测试加本计划新增的 2 个测试全部通过，0 failures、0 skipped。

- [x] **Step 4: 运行 generic build 与静态校验**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcodebuild-example-header-safe-area-generic build
git diff --check
rg -n "Tabman|Pageboy" Sources/AnchorPager/Public
rg -n "\\bprint\\(" Sources/AnchorPager
git status --short
```

Expected: generic build 和 diff check 通过；Public 扫描与 production `print` 扫描无输出；状态只包含本任务文档改动。

- [x] **Step 5: 完成最终代码自审**

逐项确认：Public API 无变化；第三方边界、containment/lifecycle、MainActor、scroll discovery、inset ownership、paging adapter、gesture/overscroll、日志事件和资源策略均未改变；新增测试覆盖真实 safe area 和用户可见切换路径；文档只标记实际通过的结果。

- [x] **Step 6: 提交文档与验收记录**

```bash
git add docs/superpowers/specs/2026-07-11-example-header-safe-area-content-design.md docs/superpowers/plans/2026-07-11-example-header-safe-area-content.md docs/task-list.md
git commit -m "记录示例 Header 安全区布局验收"
```

## Plan Self-Review

- Spec coverage：Task 1 覆盖上下 safe-area 约束、双顶部行为、背景/外框保持和 UI 路径；Task 2 覆盖文档、完整验证和自审。
- Placeholder scan：计划没有未定义实现、延后测试或模糊错误处理步骤；每个代码变更都给出完整代码和命令。
- Type consistency：测试只使用现有 `AnchorPagerHeaderTopBehavior`、`reloadHeaderLayout(offsetAdjustment:)`、`AnchorPagerLayoutContext` 和 UIKit 类型；不引入新生产接口。
- Scope：不修改框架 Sources、Public API、日志、paging adapter、containment、child inset、overscroll owner 或 bounce。

## Execution Record

- 全程复用 Booted iPhone 17 `28B089AA-A03D-49CE-A037-D999D84E9606`，未 shutdown、reboot、erase 或 clean。
- 首次 Swift Testing 函数级 `-only-testing` 命令没有匹配到测试，xcresult 为 0 tests；该结果未作为 RED 证据，随后改用 `-only-testing:AnchorPagerExampleTests` 执行整个示例单元测试 target。
- Unit RED：示例单元测试 4 个中 1 个失败、3 个通过；新增测试实际顶部间距比 `safeAreaFrame.minY + 20` 多 `8pt`。
- UI RED：目标 UI 测试 1 个失败；标题 `minY == 144`，期望的导航栏底部加 20 pt 为 `136`，差值同为 `8pt`。
- GREEN：只把标题栈上下约束从 `layoutMarginsGuide` 改为 `safeAreaLayoutGuide`；示例单元测试 target 4/4 通过，目标 UI 测试 1/1 通过。
- Task 1 自审：diff 只包含示例 view、示例单元测试和示例 UI 测试；未修改框架 Sources、Public API、Header 外框、scroll range 或 bounce。

## Final Verification

- 完整框架测试：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-example-header-safe-area-core -parallel-testing-enabled NO -enableCodeCoverage NO test`，xcresult 为 83 tests、83 passed、0 failed、0 skipped、exit 0。
- 完整示例测试：`xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-example-header-safe-area -parallel-testing-enabled NO -enableCodeCoverage NO test`，xcresult 为 13 tests、13 passed、0 failed、0 skipped、exit 0。
- 示例 generic build：`xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcodebuild-example-header-safe-area-generic build`，exit 0。
- `git diff --check` 通过；Public 目录 Tabman/Pageboy 扫描、production `print` 和不安全并发绕过扫描均无输出。
- Xcode 继续提示 Tabman/Pageboy 上游 `PrivacyInfo.xcprivacy` unhandled resource；该基线警告未因本任务增加，不影响本轮测试或 build。

## Final Self-Review

- Public API/第三方边界：未修改 `Sources/AnchorPager`，没有新增或变更 public 符号，Tabman/Pageboy 仍只位于 internal Paging 层。
- UIKit/生命周期：只改示例 Header 内部约束，没有 reparent、containment、appearance lifecycle 或 actor 隔离变化。
- Layout/scroll/inset：Header 蓝色背景和外框语义不变；LayoutEngine、automatic 中立测量、分段栏基线、scroll range、viewport bounce、child inset 和 overscroll owner 均未修改。
- 日志/资源：没有新增框架状态或关键事件，不需要新增日志；没有新增资源、observer、Task、KVO 或 display link。
- 测试/文档：同进程测试覆盖上下 safe-area 间距和 extends 外框，UI 测试覆盖用户可见切换；设计、计划和任务状态已同步真实 RED/GREEN 与最终验收结果。
