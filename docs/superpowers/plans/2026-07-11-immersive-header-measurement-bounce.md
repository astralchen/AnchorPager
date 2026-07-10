# 单一沉浸式 Header、稳定测量与 Bounce 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除 `AnchorPagerHeaderTopBehavior`，将 Header 收敛为单一沉浸式几何，并通过中立测量和 viewport presentation translation 修复 automatic 高度增长与可见 bounce 回归。

**Architecture:** LayoutEngine 只计算纯内容高度和单一沉浸式 canonical frame；`AnchorPagerViewController` 在 top obstruction 下方建立同步中立测量几何，再把 Header 应用到物理顶部。稳定 scroll range 继续与 offset 解耦，负 offset 只通过 `viewportView.transform` 产生 presentation bounce，并同步到 public layout context。

**Tech Stack:** Swift 6、iOS 14+、UIKit、CoreGraphics、Swift Package Manager、Tabman `4.0.1`、Pageboy `5.0.2`、XCTest、Swift Testing、XCUITest。

## Global Constraints

- Package name、Library product、Module name 均为 `AnchorPager`。
- Minimum OS 为 iOS 14，Language 为 Swift 6，UI stack 为 UIKit。
- Horizontal paging 使用 Tabman + Pageboy，第三方类型只允许出现在 adapter/internal 层。
- 横向 page containment 仍由 Tabman/Pageboy adapter 执行，AnchorPager 不重复 `addChild`。
- 直接删除 `AnchorPagerHeaderTopBehavior` 和 `AnchorPagerHeaderConfiguration.topBehavior`，不保留 deprecated 兼容层。
- Header outer frame 始终从 pager bounds 顶部开始；Header 内容自行使用 UIKit safe area/layout margins。
- resolved Header height 与 collapsible distance 只表示纯内容高度，不包含 top obstruction。
- scroll range 继续只依赖 viewport height 和纯内容 collapsible distance，不依赖当前 offset。
- 每项生产代码变更前必须看到对应测试按预期失败。
- Header UIViewController containment、selection、scroll discovery、child inset ownership 和后续 coordinator 职责不变。
- 滚动热路径不重新测量、不修改 range、不逐帧输出普通日志。
- 触发设计规格中的架构停机条件时立即停止并报告用户。

## File Structure

- Modify: `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`：删除顶部行为 Public API。
- Modify: `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`：收敛为单一沉浸式 canonical geometry。
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：中立测量、最终 output 和 presentation bounce。
- Modify: `Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift`：纯内容高度、沉浸式 frame、scroll range 契约。
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：safe-area-sensitive automatic Header 和 bounce 集成测试。
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`：删除类型和属性的 public source contract。
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`：移除顶部行为菜单。
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`：替换菜单测试为沉浸式几何测试。
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：移除菜单路径并覆盖回弹终态高度。
- Modify: `README.md`、`docs/requirements.md`、`docs/architecture.md`、`docs/task-list.md`：同步当前长期契约。
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`：修订 v0.2 路线。
- Modify: `docs/superpowers/specs/2026-07-10-header-scroll-settlement-design.md`：标记双行为与无视觉 bounce 假设已废止。
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`、`docs/superpowers/plans/2026-07-10-header-scroll-viewport.md`：追加历史取代和验收记录。
- Modify: `docs/superpowers/specs/2026-07-11-immersive-header-measurement-bounce-design.md`：追加实施结论。
- Modify: `AGENTS.md`：登记本计划。

---

### Task 1: 删除顶部行为 Public API 并收敛 LayoutEngine

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`
- Modify: `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`

**Interfaces:**
- Produces: `AnchorPagerHeaderConfiguration.init(heightMode:)`
- Produces: `AnchorPagerLayoutEngine.Input` without `headerTopBehavior`
- Produces: `headerFrame.height = topObstructionHeight + visibleContentHeight`
- Preserves: `ResolvedHeaderHeight` as pure content height and `managedInsetTarget.top`

- [ ] **Step 1: 写 Public API 删除测试**

在 `AnchorPagerPagingAdapterTests.swift` 增加 source scan：

```swift
func testPublicSourcesDoNotContainRemovedHeaderTopBehavior() throws {
    let publicDirectory = try packageRoot()
        .appendingPathComponent("Sources")
        .appendingPathComponent("AnchorPager")
        .appendingPathComponent("Public")
    let swiftFiles = try FileManager.default.swiftFiles(in: publicDirectory)

    for file in swiftFiles {
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(contents.contains("AnchorPagerHeaderTopBehavior"))
        XCTAssertFalse(contents.contains("topBehavior"))
    }
}
```

更新默认配置测试，使其只断言：

```swift
let configuration = AnchorPagerConfiguration.default
XCTAssertEqual(configuration.header.heightMode, .automatic(min: 0, max: nil))
```

- [ ] **Step 2: 写单一沉浸式 LayoutEngine 测试**

删除 `testInsideSafeAreaPlacesHeaderBelowTopObstruction`、
`testExtendsUnderTopSafeAreaPlacesHeaderAtBoundsTop`、
`testExtendsUnderTopSafeAreaCoversTopObstructionWhenHeaderIsShorter` 和
`testExtendsUnderTopSafeAreaMaintainsTopObstructionCoverageWhileCollapsed`，替换为：

```swift
func testImmersiveHeaderAddsTopObstructionOutsideContentHeight() {
    let output = makeOutput(
        measuredHeaderHeight: 120,
        headerHeightMode: .fixed(max: 120, min: 20),
        topObstructionHeight: 44,
        contentOffsetY: 30
    )

    XCTAssertEqual(output.resolvedHeaderHeight.expanded, 120)
    XCTAssertEqual(output.resolvedHeaderHeight.collapsed, 20)
    XCTAssertEqual(output.resolvedHeaderHeight.collapsibleDistance, 100)
    XCTAssertEqual(output.headerFrame.minY, 0)
    XCTAssertEqual(output.headerFrame.height, 134)
    XCTAssertEqual(output.barFrame.minY, 134)
    XCTAssertEqual(output.managedInsetTarget.top, 212)
}
```

将测试 helper 改为：

```swift
private func makeOutput(
    bounds: CGRect = CGRect(x: 0, y: 0, width: 320, height: 640),
    measuredHeaderHeight: CGFloat = 120,
    headerHeightMode: AnchorPagerHeaderHeightMode = .automatic(min: 0, max: nil),
    barHeight: CGFloat = 48,
    topObstructionHeight: CGFloat = 0,
    bottomObstructionHeight: CGFloat = 0,
    contentOffsetY: CGFloat = 0
) -> AnchorPagerLayoutEngine.Output {
    AnchorPagerLayoutEngine().layout(
        for: .init(
            bounds: bounds,
            measuredHeaderHeight: measuredHeaderHeight,
            headerHeightMode: headerHeightMode,
            barHeight: barHeight,
            topObstructionHeight: topObstructionHeight,
            bottomObstructionHeight: bottomObstructionHeight,
            contentOffsetY: contentOffsetY
        )
    )
}
```

- [ ] **Step 3: 运行 Task 1 测试并确认 RED**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-immersive-header -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests/testPublicSourcesDoNotContainRemovedHeaderTopBehavior -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testConfigurationDefaultsMatchV01Baseline test
```

Expected: FAIL；当前 Public source 仍包含 `AnchorPagerHeaderTopBehavior`/`topBehavior`，LayoutEngine initializer 仍要求 `headerTopBehavior`，沉浸式 frame 公式不满足。

- [ ] **Step 4: 删除 Public API 并实现沉浸式纯计算公式**

`AnchorPagerHeaderConfiguration` 改为：

```swift
public struct AnchorPagerHeaderConfiguration: Sendable, Equatable {
    public var heightMode: AnchorPagerHeaderHeightMode

    public init(
        heightMode: AnchorPagerHeaderHeightMode = .automatic(min: 0, max: nil)
    ) {
        self.heightMode = heightMode
    }
}
```

删除 `AnchorPagerHeaderTopBehavior`。LayoutEngine `Input` 删除该字段，并将 frame 计算收敛为：

```swift
let visibleContentHeight = Swift.max(
    resolvedHeaderHeight.collapsed,
    resolvedHeaderHeight.expanded - collapseOffset
)
let headerFrame = CGRect(
    x: bounds.minX,
    y: bounds.minY,
    width: bounds.width,
    height: topObstructionHeight + visibleContentHeight
)
let barFrame = CGRect(
    x: bounds.minX,
    y: headerFrame.maxY,
    width: bounds.width,
    height: barHeight
)
```

从 `AnchorPagerViewController.makeLayoutOutput` 删除 `headerTopBehavior` 传参，并机械删除核心测试中的旧字段赋值。

- [ ] **Step 5: 重新运行 Task 1 测试并确认 GREEN**

Run: Step 3 相同命令。

Expected: PASS；Public source 无删除符号，LayoutEngine/header configuration 测试通过。

- [ ] **Step 6: 运行 `git diff --check` 并提交 Task 1**

```bash
git diff --check
git add Sources/AnchorPager/Public/AnchorPagerConfiguration.swift Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift
git commit -m "移除 Header 顶部行为 API"
```

---

### Task 2: 中立测量与 viewport presentation bounce

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Produces: `measureHeaderContent(in:) -> CGFloat`
- Produces: `overscrollTranslationY -> CGFloat`
- Produces: `layoutContext(for:translationY:) -> AnchorPagerLayoutContext`
- Preserves: `scrollRangeHeightConstraint.constant == collapsibleDistance`

- [ ] **Step 1: 写 safe-area-sensitive automatic Header 稳定性测试**

增加真实 Auto Layout Header helper：

```swift
private final class SafeAreaSensitiveHeaderView: UIView {
    let contentView = UIView()

    init(contentHeight: CGFloat) {
        super.init(frame: .zero)
        directionalLayoutMargins = .zero

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            contentView.heightAnchor.constraint(equalToConstant: contentHeight)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }
}
```

新增集成测试：

```swift
@MainActor
func testImmersiveAutomaticHeaderMeasurementDoesNotAccumulateTopSafeArea() throws {
    let pager = AnchorPagerViewController()
    let headerView = SafeAreaSensitiveHeaderView(contentHeight: 80)
    let delegate = StubDelegate()
    let dataSource = StubDataSource(
        count: 1,
        viewControllers: [ScrollChildViewController()],
        headerContent: .view(headerView)
    )
    pager.dataSource = dataSource
    pager.delegate = delegate
    let navigationController = UINavigationController(rootViewController: pager)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = navigationController
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    pager.reloadData()
    window.layoutIfNeeded()
    pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
    window.layoutIfNeeded()
    let initialContext = try XCTUnwrap(delegate.layoutContexts.last)

    for _ in 0..<3 {
        pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()
    }
    let finalContext = try XCTUnwrap(delegate.layoutContexts.last)

    XCTAssertEqual(initialContext.headerFrame.minY, 0, accuracy: 0.5)
    XCTAssertEqual(finalContext.headerFrame.height, initialContext.headerFrame.height, accuracy: 0.5)
    XCTAssertEqual(finalContext.barFrame.minY, initialContext.barFrame.minY, accuracy: 0.5)
    let contentFrame = headerView.contentView.convert(headerView.contentView.bounds, to: pager.view)
    XCTAssertGreaterThanOrEqual(contentFrame.minY, pager.view.safeAreaInsets.top - 0.5)
}
```

- [ ] **Step 2: 写可见 bounce 与 layout context 测试**

```swift
@MainActor
func testNegativeContainerOffsetTranslatesViewportAndRestoresAtZero() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 120, min: 0)
    let pager = AnchorPagerViewController(configuration: configuration)
    let headerView = FixedFittingView(height: 120)
    let delegate = StubDelegate()
    let dataSource = StubDataSource(
        count: 1,
        viewControllers: [ScrollChildViewController()],
        headerContent: .view(headerView)
    )
    pager.dataSource = dataSource
    pager.delegate = delegate
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = pager
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    pager.reloadData()
    window.layoutIfNeeded()
    let host = try XCTUnwrap(headerView.superview)
    let initialFrame = host.convert(host.bounds, to: pager.view)
    let initialContentSize = pager.verticalScrollView.contentSize

    pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: -24)
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
    window.layoutIfNeeded()
    let bouncedFrame = host.convert(host.bounds, to: pager.view)
    let bouncedContext = try XCTUnwrap(delegate.layoutContexts.last)

    XCTAssertEqual(bouncedFrame.minY, initialFrame.minY + 24, accuracy: 0.5)
    XCTAssertEqual(bouncedContext.headerFrame.minY, bouncedFrame.minY, accuracy: 0.5)
    XCTAssertEqual(pager.verticalScrollView.contentSize, initialContentSize)

    pager.verticalScrollView.contentOffset = .zero
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
    window.layoutIfNeeded()
    let restoredFrame = host.convert(host.bounds, to: pager.view)

    XCTAssertEqual(restoredFrame.minY, initialFrame.minY, accuracy: 0.5)
    XCTAssertTrue(delegate.collapseProgresses.isEmpty)
}
```

- [ ] **Step 3: 运行 Task 2 测试并确认 RED**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-immersive-header -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testImmersiveAutomaticHeaderMeasurementDoesNotAccumulateTopSafeArea -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testNegativeContainerOffsetTranslatesViewportAndRestoresAtZero test
```

Expected: FAIL；重复结构测量会把最终 safe area 计入 fitting height，负 offset 下实际 Header frame 不移动。

- [ ] **Step 4: 实现中立测量事务**

在 `AnchorPagerViewController` 中新增：

```swift
private func measureHeaderContent(in environment: LayoutEnvironment) -> CGFloat {
    viewportView.transform = .identity
    headerViewHost.setTopOffset(environment.bounds.minY + environment.obstruction.top)
    headerHeightConstraint?.constant = lastMeasuredHeaderHeight ?? 0
    view.layoutIfNeeded()

    let width = environment.bounds.width > 0
        ? environment.bounds.width
        : UIScreen.main.bounds.width
    return headerViewHost.measure(
        in: CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
    )
}
```

`updateVisibleLayout` 先建立 `LayoutEnvironment`，再调用上述方法；只有最终 output 才更新
`lastMeasuredHeaderHeight`、range、layout context、progress 和日志。

- [ ] **Step 5: 实现 presentation bounce 与 context 映射**

新增：

```swift
private var overscrollTranslationY: CGFloat {
    Swift.max(0, -verticalScrollView.contentOffset.y)
}

private func layoutContext(
    for output: AnchorPagerLayoutEngine.Output,
    translationY: CGFloat
) -> AnchorPagerLayoutContext {
    AnchorPagerLayoutContext(
        selectedIndex: effectiveSelectedIndex,
        headerFrame: output.headerFrame.offsetBy(dx: 0, dy: translationY),
        barFrame: output.barFrame.offsetBy(dx: 0, dy: translationY),
        contentFrame: output.contentFrame.offsetBy(dx: 0, dy: translationY)
    )
}
```

在最终 `applyLayoutOutput` 中：

```swift
let translationY = overscrollTranslationY
viewportView.transform = CGAffineTransform(translationX: 0, y: translationY)
let context = layoutContext(for: output, translationY: translationY)
```

canonical `lastLayoutOutput`、range 和 progress 不包含 translation。

- [ ] **Step 6: 重新运行 Task 2 测试与控制器回归**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-immersive-header -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

Expected: PASS；控制器测试全部通过，滚动热路径日志测试仍不出现 `header.measure` 或普通 frame/inset 日志。

- [ ] **Step 7: 运行 `git diff --check` 并提交 Task 2**

```bash
git diff --check
git add Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "稳定沉浸式 Header 测量并恢复回弹"
```

---

### Task 3: 迁移示例工程与用户路径测试

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Removes: Header 顶部行为菜单、按钮状态和运行时切换入口
- Produces: 单一沉浸式 Header 用户路径和回弹终态 UI 回归

- [ ] **Step 1: 先修改示例测试固定新契约**

删除菜单结构和菜单切换测试，新增：

```swift
@Test func immersiveHeaderStartsAtBoundsTopAndKeepsContentBelowSafeArea() throws {
    let viewController = ExamplePagerViewController()
    let navigationController = UINavigationController(rootViewController: viewController)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = navigationController
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    viewController.loadViewIfNeeded()
    window.layoutIfNeeded()
    let pager = try #require(
        viewController.children.compactMap { $0 as? AnchorPagerViewController }.first
    )
    let probe = LayoutProbe()
    pager.delegate = probe
    pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
    window.layoutIfNeeded()
    let context = try #require(probe.layoutContexts.last)

    #expect(abs(context.headerFrame.minY) < 0.5)
    #expect(context.headerFrame.height > viewController.view.safeAreaInsets.top)
    #expect(abs(context.barFrame.minY - context.headerFrame.maxY) < 0.5)
    #expect(viewController.navigationItem.rightBarButtonItems?.count == 1)
}
```

将原 UI 回归替换为：

```swift
@MainActor
func testImmersiveHeaderHeightReturnsAfterPullDown() throws {
    let app = XCUIApplication()
    app.launch()

    let tabItem = app.descendants(matching: .any)["短页"]
    XCTAssertTrue(tabItem.waitForExistence(timeout: 3))
    XCTAssertFalse(app.navigationBars["AnchorPager"].buttons["Header 顶部行为"].exists)
    let initialMinY = tabItem.frame.minY

    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56))
    start.press(forDuration: 0.1, thenDragTo: end)

    let returned = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
            abs(tabItem.frame.minY - initialMinY) < 1
        },
        object: nil
    )
    XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 3), .completed)
}
```

- [ ] **Step 2: 运行示例测试并确认 RED**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-immersive-header -parallel-testing-enabled NO -enableCodeCoverage NO test
```

Expected: FAIL 或编译失败；示例仍引用已删除 API，并仍显示顶部行为菜单。

- [ ] **Step 3: 删除示例菜单并保留 push 导航入口**

`installNavigationItem()` 收敛为：

```swift
private func installNavigationItem() {
    let pushItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.right.circle"),
        style: .plain,
        target: self,
        action: #selector(pushAnchorPagerExample)
    )
    pushItem.accessibilityLabel = "打开 AnchorPager"
    navigationItem.rightBarButtonItems = [pushItem]
}
```

删除 `headerTopBehaviorItem`、menu/action/title helpers 和 `setHeaderTopBehavior`。

- [ ] **Step 4: 重新运行示例测试并确认 GREEN**

Run: Step 2 相同命令。

Expected: PASS；示例单测和 UI tests 全部通过。

- [ ] **Step 5: 运行 generic build、`git diff --check` 并提交 Task 3**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild-immersive-header build
git diff --check
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "迁移示例到单一沉浸式 Header"
```

---

### Task 4: 长期文档、完整验证与自审

**Files:**
- Modify: `README.md`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- Modify: `docs/superpowers/specs/2026-07-10-header-scroll-settlement-design.md`
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- Modify: `docs/superpowers/plans/2026-07-10-header-scroll-viewport.md`
- Modify: `docs/superpowers/specs/2026-07-11-immersive-header-measurement-bounce-design.md`
- Modify: `docs/superpowers/plans/2026-07-11-immersive-header-measurement-bounce.md`

**Interfaces:**
- Produces: 当前单一沉浸式 Public API、几何、测量和 bounce 长期契约
- Produces: 历史双行为方案的明确废止标记
- Produces: 完整验收和自审证据

- [ ] **Step 1: 同步长期文档**

必须逐项写明：

```text
- AnchorPagerHeaderTopBehavior/topBehavior 已直接删除，无兼容层。
- Header outer frame 始终从 pager bounds 顶部开始。
- Header 内容通过标准 UIKit safe area/layout margins 自主避让。
- height mode 表示纯内容高度；top obstruction 不进入 collapsible distance。
- automatic height 在 top obstruction 下方的中立几何中测量。
- scrollRangeView 继续定义稳定 range。
- 负 offset 通过 viewport presentation translation 恢复可见 bounce。
- layout context 在 bounce 期间使用实际可见坐标。
- child inset/owner/overscroll coordinator 仍属于后续版本。
```

历史文档保留原复现和 RED/GREEN 证据，但在相关章节顶部或 follow-up 结论明确标记已被 2026-07-11 设计取代。

- [ ] **Step 2: 扫描残留删除符号**

```bash
rg -n "AnchorPagerHeaderTopBehavior|topBehavior|insideSafeArea|extendsUnderTopSafeArea" Sources Tests Examples README.md docs AGENTS.md
```

Expected: 只允许在明确标注为历史/已废止的设计和验收记录中出现；Sources、当前测试、示例和 README 不得出现。

- [ ] **Step 3: 运行完整核心测试并提取结果**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-immersive-header -parallel-testing-enabled NO -enableCodeCoverage NO test
```

Expected: exit 0、0 failures；使用 `xcresulttool` 记录实际测试数量。

- [ ] **Step 4: 运行完整示例测试和 generic build**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-immersive-header -parallel-testing-enabled NO -enableCodeCoverage NO test
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild-immersive-header build
```

Expected: 两条命令 exit 0、0 failures；记录示例测试实际数量。

- [ ] **Step 5: 运行 SwiftPM 和差异校验**

```bash
swift package resolve
git diff --check
git status --short
```

Expected: resolve 和 diff check 通过；工作区只包含本任务已解释文档改动。

- [ ] **Step 6: 完成代码自审**

逐项记录：

```text
Public API：删除符号完整，无第三方类型泄漏，无无意新增 API。
Layout：纯内容高度、top obstruction、canonical/presentation 坐标职责清晰。
Containment：Header controller 和 Paging/Pageboy containment 未变。
Scroll/Inset：range 不依赖 offset，child inset/owner 未提前实现。
Bounce：只使用 transform，不手工弹簧、不修改 range。
并发/资源：MainActor 边界不变，无新增 observer/retain cycle。
日志：滚动热路径无普通逐帧日志，provisional measurement 不污染状态日志。
测试：RED/GREEN、完整核心、示例、UI、generic build 均有证据。
文档：requirements、architecture、roadmap、task-list、历史规格和计划同步。
```

- [ ] **Step 7: 更新计划 checkbox/验收记录并提交文档**

```bash
git diff --check
git add README.md docs AGENTS.md
git commit -m "同步单一沉浸式 Header 文档"
```

## Plan Self-Review

- Spec coverage：Task 1 覆盖 Public API 与 LayoutEngine；Task 2 覆盖中立测量、presentation bounce 和 context；Task 3 覆盖示例真实路径；Task 4 覆盖长期文档、完整验证和自审。
- Placeholder scan：未使用 TBD、TODO、模糊“类似处理”或未定义实现步骤。
- Type consistency：`measureHeaderContent(in:)`、`overscrollTranslationY`、`layoutContext(for:translationY:)`、`lastMeasuredHeaderHeight`、`scrollRangeHeightConstraint` 和现有类型一致。
- Scope：不修改 Header/Page containment、Paging adapter API、child inset ownership、scroll discovery 或后续 owner/coordinator。
- TDD：每个生产代码任务均先新增/修改会失败的真实行为测试，再实现和回归。
- Simulator：所有 Xcode 测试复用 `iPhone 17 Pro`、`.build/xcodebuild-immersive-header` 和 `.build/example-xcodebuild-immersive-header`；不主动 shutdown/reboot。
