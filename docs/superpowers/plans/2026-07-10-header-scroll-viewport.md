# Header 主容器视口与滚动范围解耦实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Header/paging 可视 viewport 与 UIScrollView content range 解耦，消除 `contentOffset → 约束 → contentSize → contentOffset` 反馈闭环，并修复顶部行为切换后下拉回弹留下安全区空白的问题。

**Architecture:** `scrollRangeView` 只通过 `contentLayoutGuide` 定义稳定滚动范围，`viewportView` 只通过 `frameLayoutGuide` 承载 Header 和 paging adapter。LayoutEngine 继续输出可见坐标；滚动热路径复用缓存测量更新 viewport 几何和 collapse progress，不修改滚动范围、不重复测量、不输出逐帧普通日志。

**Tech Stack:** Swift 6、iOS 14+、UIKit、Swift Package Manager、Tabman `4.0.1`、Pageboy `5.0.2`、XCTest、XCUITest。

## Global Constraints

- Package name、Library product、Module name 均为 `AnchorPager`。
- Minimum OS 为 iOS 14，Language 为 Swift 6，UI stack 为 UIKit。
- Horizontal paging 使用 Tabman + Pageboy，第三方类型只允许出现在 adapter/internal 层。
- 横向 page containment 仍由 Tabman/Pageboy adapter 执行，AnchorPager 不重复 `addChild`。
- Public API、data source、delegate 和 UIKit coordinator 状态保持 MainActor。
- 不新增 Public API，不修改 child managed inset ownership，不提前实现 v0.5 child scroll owner。
- 每项生产代码变更前必须先看到对应回归测试按预期失败。
- 滚动热路径不得重复测量 Header，不得逐帧输出普通日志。
- 触发设计规格中的架构停机条件时立即停止实现并提醒用户。

## File Structure

- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：拆分 range/viewport，处理滚动更新和重入保护。
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：覆盖几何、回弹、progress 和日志。
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：覆盖真实用户路径。
- Modify: `README.md`、`docs/architecture.md`、`docs/task-list.md`：同步长期契约。
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`：追加 follow-up 与验证。
- Modify: `docs/superpowers/specs/2026-07-10-header-scroll-settlement-design.md`：追加实现结论。
- Modify: `AGENTS.md`：登记本计划。

---

### Task 1: 用失败测试固定滚动几何与问题复现

**Files:**
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift:451`

**Interfaces:**
- Consumes: `verticalScrollView`、`reloadHeaderLayout(offsetAdjustment:)`
- Produces: content size 与 offset 解耦契约
- Produces: 双向 top behavior 切换后回弹归位契约

- [x] **Step 1: 新增 content size 不依赖 offset 的测试**

```swift
@MainActor
func testContainerScrollRangeDoesNotDependOnCurrentContentOffset() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 120, min: 0)
    let pager = AnchorPagerViewController(configuration: configuration)
    let dataSource = StubDataSource(
        count: 1,
        viewControllers: [ScrollChildViewController()],
        headerContent: .view(FixedFittingView(height: 120))
    )
    pager.dataSource = dataSource
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = pager
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    pager.reloadData()
    window.layoutIfNeeded()
    let expectedHeight = pager.verticalScrollView.bounds.height + 120
    XCTAssertEqual(pager.verticalScrollView.contentSize.height, expectedHeight, accuracy: 0.5)

    pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 60)
    pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
    window.layoutIfNeeded()
    XCTAssertEqual(pager.verticalScrollView.contentSize.height, expectedHeight, accuracy: 0.5)
}
```

- [x] **Step 2: 新增顶部行为切换并回弹后的测试**

```swift
@MainActor
func testHeaderReturnsToSafeAreaAfterTopBehaviorSwitchAndBounce() throws {
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
    let navigationController = UINavigationController(rootViewController: pager)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = navigationController
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    pager.reloadData()
    window.layoutIfNeeded()
    pager.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
    window.layoutIfNeeded()
    let host = try XCTUnwrap(headerView.superview)
    let initialFrame = host.convert(host.bounds, to: pager.view)

    pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 60)
    pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
    pager.configuration.header.topBehavior = .extendsUnderTopSafeArea
    pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
    pager.configuration.header.topBehavior = .insideSafeArea
    pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
    window.layoutIfNeeded()

    pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: -24)
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
    pager.verticalScrollView.contentOffset = .zero
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
    window.layoutIfNeeded()

    let finalFrame = host.convert(host.bounds, to: pager.view)
    let context = try XCTUnwrap(delegate.layoutContexts.last)
    XCTAssertEqual(finalFrame.minY, initialFrame.minY, accuracy: 0.5)
    XCTAssertEqual(finalFrame.minY, context.headerFrame.minY, accuracy: 0.5)
}
```

- [x] **Step 3: 新增 collapse progress 与滚动热路径测试**

```swift
@MainActor
func testContainerScrollingUpdatesCollapseProgressWithoutHotPathLogs() {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 120, min: 0)
    let pager = AnchorPagerViewController(configuration: configuration)
    let delegate = StubDelegate()
    let dataSource = StubDataSource(
        count: 1,
        viewControllers: [ScrollChildViewController()],
        headerContent: .view(FixedFittingView(height: 120))
    )
    pager.dataSource = dataSource
    pager.delegate = delegate
    pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
    pager.loadViewIfNeeded()
    pager.reloadData()
    pager.view.layoutIfNeeded()
    XCTAssertTrue(delegate.collapseProgresses.isEmpty)

    var events: [AnchorPagerLogger.Event] = []
    AnchorPagerLogger.sink = { events.append($0) }
    defer { AnchorPagerLogger.sink = nil }
    pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: 60)
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
    pager.view.layoutIfNeeded()

    XCTAssertNotNil(pager.verticalScrollView.delegate)
    XCTAssertFalse(pager.verticalScrollView.delegate === pager)
    XCTAssertEqual(delegate.collapseProgresses, [0.5])
    XCTAssertFalse(events.contains { $0.event == "header.measure" })
    XCTAssertFalse(events.contains { $0.event == "layout.headerFrameChanged" })
    XCTAssertFalse(events.contains { $0.event == "layout.barFrameChanged" })
    XCTAssertFalse(events.contains { $0.event == "inset.managedTargetChanged" })
}
```

- [x] **Step 4: 运行定向测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-header-viewport-red -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testContainerScrollRangeDoesNotDependOnCurrentContentOffset -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testHeaderReturnsToSafeAreaAfterTopBehaviorSwitchAndBounce -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testContainerScrollingUpdatesCollapseProgressWithoutHotPathLogs test
```

Expected: FAIL；旧实现的 `contentSize.height` 随 offset 改变，或 Header final `minY` 保留过期补偿。

---

### Task 2: 解耦 viewport 与 scroll range

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift:23-329`
- Test: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Produces: `scrollRangeView`、`viewportView`、`scrollRangeHeightConstraint`
- Produces: 私有 `VerticalScrollDelegate` proxy、`lastMeasuredHeaderHeight`、`isApplyingLayout`
- Produces: `applyLayoutOutput(_:environment:forceNotify:logsChanges:updatesScrollRange:)`
- Produces: `updateVisibleLayoutForScrolling()`、`scrollViewDidScroll(_:)`

- [x] **Step 1: 替换主容器内部属性**

```swift
@MainActor
private final class VerticalScrollDelegate: NSObject, UIScrollViewDelegate {
    weak var owner: AnchorPagerViewController?

    init(owner: AnchorPagerViewController) {
        self.owner = owner
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let owner, scrollView === owner.verticalScrollView else { return }
        owner.updateVisibleLayoutForScrolling()
    }
}

private let scrollRangeView = UIView()
private let viewportView = UIView()
private let headerViewHost = AnchorPagerHeaderViewHost()
private let layoutEngine = AnchorPagerLayoutEngine()
private let pagingAdapter = AnchorPagerPagingAdapter()
private var scrollRangeHeightConstraint: NSLayoutConstraint?
private var headerHeightConstraint: NSLayoutConstraint?
private var pagingTopConstraint: NSLayoutConstraint?
private var pagingHeightConstraint: NSLayoutConstraint?
private var lastMeasuredHeaderHeight: CGFloat?
private var isApplyingLayout = false
private lazy var verticalScrollDelegate = VerticalScrollDelegate(owner: self)
```

- [x] **Step 2: 安装独立 scroll range 和固定 viewport**

```swift
verticalScrollView.delegate = verticalScrollDelegate

scrollRangeView.translatesAutoresizingMaskIntoConstraints = false
scrollRangeView.isUserInteractionEnabled = false
verticalScrollView.addSubview(scrollRangeView)
let scrollRangeHeightConstraint = scrollRangeView.heightAnchor.constraint(
    equalTo: verticalScrollView.frameLayoutGuide.heightAnchor
)
NSLayoutConstraint.activate([
    scrollRangeView.leadingAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.leadingAnchor),
    scrollRangeView.trailingAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.trailingAnchor),
    scrollRangeView.topAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.topAnchor),
    scrollRangeView.bottomAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.bottomAnchor),
    scrollRangeView.widthAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.widthAnchor),
    scrollRangeHeightConstraint
])
self.scrollRangeHeightConstraint = scrollRangeHeightConstraint

viewportView.translatesAutoresizingMaskIntoConstraints = false
viewportView.clipsToBounds = true
verticalScrollView.addSubview(viewportView)
NSLayoutConstraint.activate([
    viewportView.leadingAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.leadingAnchor),
    viewportView.trailingAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.trailingAnchor),
    viewportView.topAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.topAnchor),
    viewportView.bottomAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.bottomAnchor)
])
```

- [x] **Step 3: 将 Header 和 paging adapter 改挂到 viewport**

```swift
headerViewHost.install(headerContent, in: self, hostParentView: viewportView)

viewportView.addSubview(adapterView)
let pagingTopConstraint = adapterView.topAnchor.constraint(equalTo: headerViewHost.view.bottomAnchor)
let pagingHeightConstraint = adapterView.heightAnchor.constraint(equalToConstant: 0)
NSLayoutConstraint.activate([
    adapterView.leadingAnchor.constraint(equalTo: viewportView.leadingAnchor),
    adapterView.trailingAnchor.constraint(equalTo: viewportView.trailingAnchor),
    pagingTopConstraint,
    pagingHeightConstraint
])
self.pagingTopConstraint = pagingTopConstraint
self.pagingHeightConstraint = pagingHeightConstraint
```

- [x] **Step 4: 集中应用 LayoutEngine output**

```swift
private func applyLayoutOutput(
    _ output: AnchorPagerLayoutEngine.Output,
    environment: LayoutEnvironment,
    forceNotify: Bool,
    logsChanges: Bool,
    updatesScrollRange: Bool
) {
    if updatesScrollRange {
        scrollRangeHeightConstraint?.constant = output.resolvedHeaderHeight.collapsibleDistance
    }
    headerHeightConstraint?.constant = output.headerFrame.height
    headerViewHost.setTopOffset(output.headerFrame.minY)
    pagingTopConstraint?.constant = Swift.max(0, output.barFrame.minY - output.headerFrame.maxY)
    pagingHeightConstraint?.constant = output.barFrame.height + output.contentFrame.height
    if logsChanges { logLayoutChanges(output: output, environment: environment) }

    if lastLayoutOutput?.collapseProgress != output.collapseProgress {
        delegate?.pagerViewController(self, didUpdateHeaderCollapseProgress: output.collapseProgress)
    }
    let context = AnchorPagerLayoutContext(
        selectedIndex: effectiveSelectedIndex,
        headerFrame: output.headerFrame,
        barFrame: output.barFrame,
        contentFrame: output.contentFrame
    )
    if forceNotify || context != lastLayoutContext {
        lastLayoutContext = context
        delegate?.pagerViewController(self, didUpdateLayout: context)
    }
    lastLayoutOutput = output
}
```

完整 `updateVisibleLayout` 以 `isApplyingLayout` 和 `defer` 防重入，缓存
`lastMeasuredHeaderHeight`，保留现有 offset adjustment，最后调用上述方法并传入
`logsChanges: true, updatesScrollRange: true`。删除 `scrollContentCoordinateY(forVisibleY:)`。

- [x] **Step 5: 实现不测量、不写日志的滚动热路径**

```swift
private func updateVisibleLayoutForScrolling() {
    guard !isApplyingLayout,
          isViewLoaded,
          headerViewHost.view.superview != nil,
          let measuredHeaderHeight = lastMeasuredHeaderHeight else { return }
    isApplyingLayout = true
    defer { isApplyingLayout = false }

    let environment = currentLayoutEnvironment()
    let output = makeLayoutOutput(
        measuredHeaderHeight: measuredHeaderHeight,
        contentOffsetY: verticalScrollView.contentOffset.y,
        environment: environment
    )
    applyLayoutOutput(
        output,
        environment: environment,
        forceNotify: false,
        logsChanges: false,
        updatesScrollRange: false
    )
}
```

主控制器本身不得声明 `UIScrollViewDelegate` conformance，避免扩大 public surface；滚动入口只通过上述
私有 `VerticalScrollDelegate` proxy 转发。

- [x] **Step 6: 更新 DocC**

```swift
/// AnchorPager 管理的纵向容器滚动视图。
///
/// 该滚动视图的 delegate 由 AnchorPager 内部管理，调用方不得替换。
public let verticalScrollView = UIScrollView()
```

- [x] **Step 7: 运行 Task 1 测试并确认 GREEN**

Run: Task 1 Step 4 相同命令。

Expected: PASS，3 tests、0 failures。

- [x] **Step 8: 运行现有控制器测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-header-viewport-controller -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

Expected: PASS；若暴露 viewport/contentFrame 契约冲突，触发架构停机条件并先报告用户。

---

### Task 3: 示例 UI 回归与文档收敛

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift:29`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- Modify: `docs/superpowers/specs/2026-07-10-header-scroll-settlement-design.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: 修正后的 Header/top behavior/scroll geometry
- Produces: 真实用户路径 UI 回归、文档、验证和自审记录

- [x] **Step 1: 新增示例 UI 回归测试**

```swift
@MainActor
func testHeaderReturnsAfterTopBehaviorSwitchAndPullDown() throws {
    let app = XCUIApplication()
    app.launch()
    let headerTitle = app.staticTexts["AnchorPager Example"]
    XCTAssertTrue(headerTitle.waitForExistence(timeout: 3))
    let initialMinY = headerTitle.frame.minY
    let behaviorButton = app.navigationBars["AnchorPager"].buttons["Header 顶部行为"]

    behaviorButton.tap()
    XCTAssertTrue(app.buttons["延伸到顶部"].waitForExistence(timeout: 3))
    app.buttons["延伸到顶部"].tap()
    behaviorButton.tap()
    XCTAssertTrue(app.buttons["安全区内"].waitForExistence(timeout: 3))
    app.buttons["安全区内"].tap()

    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56))
    start.press(forDuration: 0.1, thenDragTo: end)

    let returned = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in abs(headerTitle.frame.minY - initialMinY) < 1 },
        object: nil
    )
    XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 3), .completed)
}
```

- [x] **Step 2: 运行新增 UI test**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-header-viewport-ui -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderReturnsAfterTopBehaviorSwitchAndPullDown test
```

Expected: PASS。若 XCUITest 无法稳定识别回弹结束，记录失败证据，移除不稳定测试，以 Task 1 同进程
UIKit 几何测试作为替代自动化验证。

- [x] **Step 3: 更新长期文档**

必须写明：

```text
- scrollRangeView 通过 contentLayoutGuide 定义滚动范围。
- Header/paging 位于 frameLayoutGuide viewport，不参与 contentSize 反算。
- verticalScrollView.delegate 由 AnchorPager 管理。
- scrollViewDidScroll 只更新可见几何/progress，不重复测量、不逐帧写日志。
- child owner、managed inset、overscroll coordinator 仍属于后续版本。
```

在 v0.2 plan 和本设计记录 RED/GREEN 命令、UI test 或替代原因、自审结论。

- [x] **Step 4: 运行完整验证**

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-header-viewport-final -enableCodeCoverage NO test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild-header-viewport build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-header-viewport-final-ui -parallel-testing-enabled NO -enableCodeCoverage NO test
```

Expected: 所有命令 exit 0；记录实际测试数量和失败数量。

- [x] **Step 5: 完成代码自审**

逐项记录 Public API、分层、containment、scroll/inset、gesture/overscroll、并发/资源、日志、测试、示例和
文档结论。确认没有在错误架构上追加终态回调、强制 reset、异步延迟或重复 layout 补丁。

## Plan Self-Review

- Spec coverage：Task 1 固定问题、几何、progress 与热路径；Task 2 完成视口/range 解耦和重入保护；Task 3 覆盖 UI、文档、验证与自审。
- 占位符扫描：未发现未定内容或缺失实现步骤。
- Type consistency：`VerticalScrollDelegate`、`scrollRangeView`、`viewportView`、`scrollRangeHeightConstraint`、`lastMeasuredHeaderHeight`、`isApplyingLayout`、`applyLayoutOutput` 和 `updateVisibleLayoutForScrolling` 命名一致。
- Scope：不修改 LayoutEngine 纯计算契约，不接管 child inset/owner，不改变 Paging containment。

## Execution Record

- 按用户要求在 `codex/v0-2-layout` 分支原地实施，未创建 worktree。
- 为减少 Simulator 冷启动，RED/GREEN/控制器回归复用已启动的 `iPhone 17 Pro` 和 `.build/xcodebuild-header-viewport-baseline`。
- 基线核心测试 `xcodebuild ... test` exit 0。
- RED：3 tests、3 failures；`contentSize 844 != 964`、Header `176 != 116`、progress `[] != [0.5]`。
- GREEN：3 个目标测试通过；控制器回归 33 tests、0 failures。
- API 边界 RED：直接 self-conformance 时内部 delegate 身份断言失败；私有 proxy 后通过。
- Progress 语义 RED：初始 progress 不应通知断言失败；只在既有 progress 变化时通知后通过。
- 示例 UI 回归 `testHeaderReturnsAfterTopBehaviorSwitchAndPullDown` exit 0。
- 最终核心测试复用 `.build/xcodebuild-header-viewport-baseline`，80 tests、0 failures、exit 0。
- 最终示例测试复用 `.build/example-xcodebuild-header-viewport`，11 tests、0 failures、exit 0。
- 示例 generic build exit 0。首次命令误带仅 testing 支持的 `-enableCodeCoverage`，Xcode 在编译前以参数错误退出；移除后正式 build 通过。
- `swift package resolve` 在沙盒内因 SwiftPM/clang 用户缓存权限失败，提升权限后从缓存解析 Tabman 4.0.1、Pageboy 5.0.2 并通过；`git diff --check` 通过。
- 最终验收复用了既有 DerivedData；没有主动 shutdown 或重启 Simulator。CoreSimulator 在不同 test action 间自行管理测试设备，后续定向热路径测试复用了 Booted 的 `iPhone 17 Pro`。

## Final Self-Review

- Public API：未新增或删除 public 类型、属性、方法或第三方类型；只补充现有 `verticalScrollView.delegate` 由框架保留的 DocC/文档契约。主控制器没有声明 public `UIScrollViewDelegate` conformance。
- 分层与范围：LayoutEngine 仍为纯计算；`scrollRangeView` 只定义 range，`viewportView` 只承载可见 Header/paging。range 高度只依赖 viewport 和 resolved collapsible distance，不依赖 offset。
- Containment/lifecycle：Header view controller 仍由 Header host 标准管理；paging adapter 仍只 addChild 一次，横向 page containment 仍由 Tabman/Pageboy adapter 执行。移动 host 的父 view 没有重复 add/remove child。
- Delegate/并发：私有 delegate proxy 由控制器强持有、弱引用 owner，UIScrollView 弱持有 delegate，不形成循环；UIKit 路径继续由 `@MainActor` 隔离，没有不安全并发绕过。
- Scroll/inset/gesture：主容器 offset 只驱动可见 output；未修改 scroll discovery、外部 child inset、gesture/overscroll、状态栏点击顶滚或 v0.5 owner/handoff 语义。
- 日志与性能：滚动入口复用 `lastMeasuredHeaderHeight`，不更新 range、不调用 `header.measure`、不写布局/inset普通日志；测试在滚动后追加 `layoutIfNeeded()`，确认下一布局周期也不产生这些热路径事件。初次布局不误报 progress，相同 progress 不重复通知。
- 测试/示例/文档：核心几何、range、delegate、progress、日志和真实菜单/回弹 UI 路径均有自动化覆盖；README、architecture、requirements、task-list、v0.2 计划、本计划和设计说明已同步。没有发现 Critical 或 Important 级问题。
- 已知非阻塞项：Xcode/SwiftPM 仍报告 Tabman、Pageboy 上游 `PrivacyInfo.xcprivacy` unhandled resource 提示，本次未改依赖版本或资源规则，不属于本修复引入。
