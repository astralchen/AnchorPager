# 无滚动页面直接 Containment 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除无滚动页面的 synthetic fallback scroll host，让 original page 直接由 Pageboy containment、scroll target 为 nil，并保证页面根 view 到达 AnchorPager 与物理屏幕底边。

**Architecture:** `AnchorPagerPageStateStore` 把 page identity 与 optional scroll identity 作为两个独立事实；无滚动页保留 committed page，但不参与 managed inset、snapshot、child observation、bounce 或 simultaneous pair。Pageboy/UIKit 对所有横向业务页执行唯一 containment，外层 `verticalScrollView` 独立处理无滚动页上的 Header 折叠、展开与临时顶部 bounce。

**Tech Stack:** Swift 6.2、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、Tabman 4.0.1、Pageboy 5.0.2、XCTest/XCUITest、XcodeBuildMCP。

**当前状态：** 已完成；direct containment 专项与 2026-07-14 plain bottom 分层 page presentation 修订、完整重新验收和整分支 fresh-pass 复审均完成，关联 v0.5/v0.6 当前为 Ready。

## Global Constraints

- 所有 UIKit、Store、adapter、coordinator 和测试状态更新保持 `@MainActor`。
- 不扩大 AnchorPager public API，不向 public API 泄漏 Tabman/Pageboy 类型。
- AnchorPager 不得设置业务 child 的 `UIScrollView.delegate` 或任何 container/child 内建 pan delegate。
- 无滚动页不接收 `contentInset`、`scrollIndicatorInsets`、`contentOffset`、`contentSize`、`additionalSafeAreaInsets`、`bounces` 或 `alwaysBounceVertical` 写入。
- 无滚动页 original controller 直接交给 Pageboy；AnchorPager 不得建立第二层 wrapper containment。
- 空数据是 page/scroll 均为 nil；无滚动页是 page 非 nil、scroll 为 nil；真实滚动页是 page/scroll 均非 nil。
- 真实 scroll page 的 managed inset、snapshot、delegate 保留、cache generation 和纵向 handoff 行为不得改变。
- 修复完成前 v0.5 Task 7 保持暂停，不得标记 v0.5 Ready。
- 每个任务先运行 RED，再实现最小 GREEN；每个任务独立自审并使用中文提交。

---

### Task 1: PageStateStore page/scroll 三态与 nil scroll target

**Files:**
- Modify: `Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift`

**Interfaces:**
- Consumes: `UIViewController.anchorPagerScrollView: UIScrollView?`、`AnchorPagerManagedInsetCoordinator`、generation/retention API。
- Produces: `pageViewController(at:context:originalProvider:) -> UIViewController?` 对无滚动页返回 original；`scrollView(at:)` 与 `committedCurrentScrollView` 返回 nil；日志事件 `scroll.target.none`。

- [x] **Step 1: 把 fallback 单测改为 direct page RED**

把 `testPlainPageUsesSingleFallbackContainment` 替换为：

```swift
func testPlainPageUsesOriginalControllerWithoutScrollTargetOrInsetOwnership() {
    let coordinator = AnchorPagerManagedInsetCoordinator()
    let store = AnchorPagerPageStateStore(managedInsetCoordinator: coordinator)
    let child = UIViewController()
    store.beginReload(
        generation: 1,
        pageCount: 1,
        selectedIndex: 0,
        keepsAdjacentPagesLoaded: false
    )
    let context = AnchorPagerPageStateStore.AccessContext(
        managedInsetTarget: .init(
            content: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0),
            indicators: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)
        ),
        containerIsCollapsed: false
    )

    let actual = store.pageViewController(at: 0, context: context) { child }
    store.commitReload(generation: 1)
    store.updateManagedInsets(context.managedInsetTarget, logsChanges: true)

    XCTAssertTrue(actual === child)
    XCTAssertTrue(store.committedCurrentPageViewController === child)
    XCTAssertNil(store.scrollView(at: 0))
    XCTAssertNil(store.committedCurrentScrollView)
    XCTAssertNil(child.parent)
    XCTAssertEqual(store.lastManagedUpdateCount, 0)
}
```

新增日志测试：

```swift
func testPlainPageWritesNoScrollTargetLogOnceAcrossReuse() {
    let store = AnchorPagerPageStateStore(
        managedInsetCoordinator: AnchorPagerManagedInsetCoordinator()
    )
    let child = UIViewController()
    var events: [AnchorPagerLogger.Event] = []
    AnchorPagerLogger.sink = { events.append($0) }
    defer { AnchorPagerLogger.sink = nil }
    store.beginReload(
        generation: 1,
        pageCount: 1,
        selectedIndex: 0,
        keepsAdjacentPagesLoaded: false
    )

    _ = store.pageViewController(at: 0, context: .testZero) { child }
    _ = store.pageViewController(at: 0, context: .testZero) { child }

    XCTAssertEqual(events.filter { $0.event == "scroll.target.none" }.count, 1)
}
```

- [x] **Step 2: 更新 collision、generation 与 duplicate RED 期望**

逐项重命名并固定以下语义：

```swift
func testSharedExplicitScrollTargetUsesOriginalLaterPageWithNilScrollAndWritesLog()
func testMovedPlainPageMigrationKeepsOriginalIdentityWithoutContainment()
func testCommitDoesNotContainOrRemovePlainPage()
func testPendingCancelDoesNotContainOrRemovePlainPage()
func testSameControllerAtSameIndexMigratesDirectPageIdentity()
func testDuplicateControllerUsesDirectBlankPageWithNilScrollAndWritesLog()
```

共享 scroll 冲突断言使用：

```swift
XCTAssertTrue(firstActual === first)
XCTAssertTrue(secondActual === second)
XCTAssertNil(store.scrollView(at: 1))
XCTAssertTrue(events.contains(.init(
    category: .inset,
    level: .debug,
    event: "inset.targetCollision"
)))
```

duplicate 降级断言使用：

```swift
XCTAssertTrue(first === duplicate)
XCTAssertNotNil(second)
XCTAssertFalse(second === duplicate)
XCTAssertNil(store.scrollView(at: 1))
XCTAssertTrue(second?.children.isEmpty == true)
```

原先断言 Store 主动执行 fallback `willMove/removeFromParent` 的测试改为断言 plain child 始终没有 AnchorPager parent；Pageboy containment 留给 Task 2 集成测试。

- [x] **Step 3: 运行 Store RED**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests test
```

Expected: FAIL；plain page 仍返回 `AnchorPagerPageScrollHostViewController`、scroll 非 nil、缺少 `scroll.target.none`。

- [x] **Step 4: 最小化 PageIdentityPayload 与 CleanupPlan**

将 identity/cleanup 改为只保存 page 与 optional scroll：

```swift
private final class PageIdentityPayload {
    weak var originalViewController: UIViewController?
    weak var actualPageViewController: UIViewController?
    weak var scrollView: UIScrollView?
    var claimedScrollViewIdentifier: ObjectIdentifier?
    var originalViewControllerIdentifier: ObjectIdentifier?
    var hasLoadedBefore = false
}

private struct CleanupPlan {
    struct Entry {
        let state: GenerationPageState
        let scrollView: UIScrollView?
    }

    let generation: GenerationState
    let entries: [Entry]

    init(generation: GenerationState) {
        self.generation = generation
        entries = generation.pages.values.map { state in
            Entry(state: state, scrollView: state.identity.scrollView)
        }
    }
}
```

删除 `fallbackHost`、`ContainmentPreservation`、`makeFallbackHost` 以及 cleanup 中的 fallback containment 分支；generation cleanup 只释放真实 scroll ownership 并清空 state maps。

- [x] **Step 5: 实现 direct page + optional scroll 解析**

把页面解析局部变量改为 optional scroll：

```swift
originalViewController.loadViewIfNeeded()
let actualPageViewController = originalViewController
let resolvedScrollView = originalViewController.anchorPagerScrollView
let scrollView: UIScrollView?

if let resolvedScrollView,
   generation.claimedScrollViewIdentifiers
    .insert(ObjectIdentifier(resolvedScrollView)).inserted {
    scrollView = resolvedScrollView
} else if resolvedScrollView != nil {
    AnchorPagerAssertions.failure("AnchorPager pages must not share a scroll view.")
    AnchorPagerLogger.log(.debug, category: .inset, event: "inset.targetCollision")
    if let defaultScrollView = originalViewController.anchorPagerDefaultScrollView,
       generation.claimedScrollViewIdentifiers
        .insert(ObjectIdentifier(defaultScrollView)).inserted {
        scrollView = defaultScrollView
    } else {
        scrollView = nil
    }
} else {
    scrollView = nil
}

if scrollView == nil {
    AnchorPagerLogger.log(.debug, category: .scroll, event: "scroll.target.none")
}

state.identity.actualPageViewController = actualPageViewController
state.identity.scrollView = scrollView
state.identity.claimedScrollViewIdentifier = scrollView.map(ObjectIdentifier.init)
```

`applyManagedInsets`、snapshot save/restore 和 ownership release 保持现有 `guard let scrollView else { return }`；不得给 nil scroll page 创建替代 owner。

- [x] **Step 6: 运行 Store GREEN 与相邻 inset/cache 测试**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests \
  -only-testing:AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests test
```

Expected: PASS，0 failures、0 skips；plain page 不进入 managed update count，真实 scroll snapshot/inset 测试保持通过。

- [x] **Step 7: 自审并提交 Store 三态**

确认：page/scroll/empty 三态、generation migration、shared scroll collision、retention、ownership preservation、日志不重复、无 fallback containment。

```bash
git diff --check
git add Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift \
  Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift
git commit -m "重建无滚动页面状态语义"
```

---

### Task 2: 删除 fallback host 并验证 Pageboy 直接 containment 与几何

**Files:**
- Delete: `Sources/AnchorPager/Children/AnchorPagerPageScrollHostViewController.swift`
- Delete: `Tests/AnchorPagerTests/AnchorPagerPageScrollHostViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`

**Interfaces:**
- Consumes: Task 1 的 original page + nil scroll target。
- Produces: Pageboy 对 plain original page 的唯一 containment；plain root 未裁剪几何至少覆盖 pager/window 底部；nil binding 不建立 simultaneous pair。

- [x] **Step 1: 写直接 containment 与物理底边 RED**

把 `testReloadDataWrapsChildWithoutScrollViewInFallbackHost` 替换为：

```swift
func testReloadDataProvidesPlainChildDirectlyToPagingAdapter() throws {
    let pager = AnchorPagerViewController()
    let plainChild = UIViewController()
    pager.dataSource = StubDataSource(count: 1, viewControllers: [plainChild])
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = pager
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    pager.reloadData()
    window.layoutIfNeeded()
    let adapter = try XCTUnwrap(installedAdapter(in: pager))
    let page = adapter.viewController(for: adapter, at: 0)

    XCTAssertTrue(page === plainChild)
    XCTAssertNotNil(plainChild.parent)
    XCTAssertFalse(plainChild.parent is AnchorPagerViewController)
    XCTAssertTrue(plainChild.view.window === window)
}
```

把 fallback bottom obstruction 测试替换为：

```swift
func testPlainPageRootReachesPagerAndWindowBottomWithoutFrameworkInsets() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 80, min: 0)
    let pager = AnchorPagerViewController(configuration: configuration)
    let plainChild = UIViewController()
    plainChild.additionalSafeAreaInsets = UIEdgeInsets(top: 3, left: 0, bottom: 7, right: 0)
    pager.dataSource = StubDataSource(
        count: 1,
        viewControllers: [plainChild],
        headerContent: .view(FixedFittingView(height: 80))
    )
    let tabController = UITabBarController()
    tabController.viewControllers = [pager]
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = tabController
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    pager.reloadData()
    window.layoutIfNeeded()
    let pageFrameInPager = plainChild.view.convert(plainChild.view.bounds, to: pager.view)
    let pageFrameInWindow = plainChild.view.convert(plainChild.view.bounds, to: window)

    XCTAssertGreaterThanOrEqual(pageFrameInPager.maxY, pager.view.bounds.maxY - 1)
    XCTAssertGreaterThanOrEqual(pageFrameInWindow.maxY, window.bounds.maxY - 1)
    XCTAssertEqual(plainChild.additionalSafeAreaInsets.top, 3, accuracy: 0.001)
    XCTAssertEqual(plainChild.additionalSafeAreaInsets.bottom, 7, accuracy: 0.001)
}
```

- [x] **Step 2: 写 nil binding 与 container-only gesture RED**

新增：

```swift
func testCommittedPlainPageBindsNoChildPanAndContainerStillCollapses() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 100, min: 0)
    let pager = AnchorPagerViewController(configuration: configuration)
    pager.dataSource = StubDataSource(count: 1, viewControllers: [UIViewController()])
    pager.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    pager.loadViewIfNeeded()
    pager.reloadData()
    pager.view.layoutIfNeeded()
    let container = try XCTUnwrap(
        pager.verticalScrollView as? AnchorPagerContainerScrollView
    )
    let unrelatedPan = UIPanGestureRecognizer()

    XCTAssertFalse(container.gestureRecognizer(
        container.panGestureRecognizer,
        shouldRecognizeSimultaneouslyWith: unrelatedPan
    ))

    pager.verticalScrollView.contentOffset.y = 60
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
    XCTAssertEqual(pager.verticalScrollView.contentOffset.y, 60, accuracy: 0.5)
}
```

- [x] **Step 3: 运行 UIKit RED**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

Expected: FAIL；旧 fallback 类型/几何期望仍存在，plain root bottom 尚未满足 direct page 契约。

- [x] **Step 4: 更新 adapter teardown 测试为普通 direct page**

把 `testPrepareForRemovalSynchronouslyClearsFallbackPageWithoutPagingEvents` 改为：

```swift
func testPrepareForRemovalSynchronouslyClearsPlainPageWithoutPagingEvents() {
    let plainPage = UIViewController()
    let adapter = AnchorPagerPagingAdapter()
    let delegate = RecordingPagingDelegate()
    adapter.eventDelegate = delegate
    reload(adapter, titles: ["Plain"], viewControllers: [plainPage], selectedIndex: 0)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = adapter
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    window.layoutIfNeeded()
    XCTAssertNotNil(plainPage.parent)
    XCTAssertNotNil(plainPage.view.superview)
    delegate.events.removeAll()

    let didCompleteSynchronously = adapter.prepareForRemoval()

    XCTAssertTrue(didCompleteSynchronously)
    XCTAssertNil(plainPage.parent)
    XCTAssertNil(plainPage.view.superview)
    XCTAssertEqual(delegate.events, [])
}
```

- [x] **Step 5: 删除 fallback host 生产文件与专用测试**

使用 `apply_patch` 删除两个文件，并删除 ViewController tests 中所有 `AnchorPagerPageScrollHostViewController` 类型断言、fallback managed inset 断言和 AnchorPager wrapper containment 断言。保留真实 scroll page inset、reload terminal、appearance 和资源释放测试。

- [x] **Step 6: 运行 UIKit GREEN 与生命周期回归**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests test
```

Expected: PASS，0 failures、0 skips；plain page 由 Pageboy parent 管理，真实 scroll binding 保持不变。

- [x] **Step 7: 源码边界扫描、自审并提交**

```bash
rg -n 'AnchorPagerPageScrollHostViewController|fallbackHost.create' Sources Tests
rg -n '\.delegate\s*=|panGestureRecognizer\.delegate\s*=' Sources/AnchorPager
git diff --check
```

Expected: 第一条无结果；第二条只允许 `verticalScrollView.delegate = verticalScrollDelegate`，不得出现业务 child/pan delegate 赋值。

```bash
git add Sources/AnchorPager/Children \
  Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift \
  Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift
git commit -m "移除无滚动页面包装容器"
```

---

### Task 3: Example 真实 plain root 几何与 pan 验收

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: direct plain page、public `verticalScrollView` 与 collapse delegate。
- Produces: `scroll-coordination-state` 新字段 `hasScrollTarget`；`plain-page-root` 可访问几何；真实 container-only pan UI 证据。

- [x] **Step 1: 写状态序列化 RED**

为 `ExampleScrollCoordinationState` 增加 `hasScrollTarget: Bool` 的测试期望：

```swift
@Test func plainScrollCoordinationStateReportsNoScrollTarget() {
    let state = ExampleScrollCoordinationState(
        page: "plain",
        hasScrollTarget: false,
        collapseProgress: 1,
        childDistance: 0,
        containerSawTopBounce: false,
        childSawTopBounce: false
    )

    #expect(
        state.accessibilityValue
            == "page=plain;hasScrollTarget=0;collapse=1.00;distance=0.00;containerBounce=0;childBounce=0"
    )
}
```

- [x] **Step 2: 写 physical-bottom 与真实 pan UI RED**

用以下测试替换 `testShortAndFallbackPagesRemainStableAcrossVerticalDrag` 的 plain 部分并新增独立测试：

```swift
@MainActor
func testPlainPageRootReachesPhysicalBottomAndUsesContainerOnlyPan() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--anchorPagerInitialIndex", "3"]
    app.launch()
    let root = app.otherElements["plain-page-root"]
    let stateProbe = scrollCoordinationStateProbe(in: app)
    XCTAssertTrue(root.waitForExistence(timeout: 3))
    let initialFrame = root.frame

    XCTAssertGreaterThanOrEqual(initialFrame.maxY, app.frame.maxY - 1)
    XCTAssertNotNil(waitForScrollState(from: stateProbe) {
        $0.page == "plain" && !$0.hasScrollTarget && $0.distance == 0
    })

    drag(in: app, from: 0.76, to: 0.24)

    XCTAssertNotNil(waitForScrollState(from: stateProbe) {
        $0.page == "plain" && !$0.hasScrollTarget
            && $0.collapse >= 0.99 && $0.distance == 0 && !$0.childBounce
    })
    let collapsedFrame = root.frame
    XCTAssertGreaterThanOrEqual(collapsedFrame.maxY, app.frame.maxY - 1)
    XCTAssertEqual(collapsedFrame.height, initialFrame.height, accuracy: 1)

    drag(in: app, from: 0.76, to: 0.24)
    XCTAssertEqual(root.frame, collapsedFrame)
}
```

`ScrollCoordinationState` UI parser 同步解析 `hasScrollTarget`。

- [x] **Step 3: 运行 Example RED**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleTests \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainPageRootReachesPhysicalBottomAndUsesContainerOnlyPan test
```

Expected: FAIL；状态缺少 `hasScrollTarget`、plain root 缺少 identifier 或 frame bottom 不匹配。

- [x] **Step 4: 实现 Example-only 状态与根 view 几何探针**

状态序列化字段顺序固定为：

```swift
[
    "page=\(page)",
    "hasScrollTarget=\(hasScrollTarget ? 1 : 0)",
    "collapse=\(formatted(collapseProgress))",
    "distance=\(formatted(childDistance))",
    "containerBounce=\(containerSawTopBounce ? 1 : 0)",
    "childBounce=\(childSawTopBounce ? 1 : 0)"
].joined(separator: ";")
```

在 `ExampleScrollCoordinationState` 的初始值、所有构造点与 `updateSelectedPageState(at:)` 中同步传入 `hasScrollTarget`：真实 scroll page 设为 true，plain page 设为 false。plain page 仍保持 distance 0，但 UI 验收同时读取 `hasScrollTarget=0` 和真实 root frame，不再只信任写死距离。

在 `ExamplePlainPageViewController.viewDidLoad()` 添加不拦截触摸的背景探针：

```swift
let rootProbe = UIView()
rootProbe.accessibilityIdentifier = "plain-page-root"
rootProbe.isAccessibilityElement = true
rootProbe.isUserInteractionEnabled = false
rootProbe.translatesAutoresizingMaskIntoConstraints = false
view.insertSubview(rootProbe, at: 0)
NSLayoutConstraint.activate([
    rootProbe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
    rootProbe.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    rootProbe.topAnchor.constraint(equalTo: view.topAnchor),
    rootProbe.bottomAnchor.constraint(equalTo: view.bottomAnchor)
])
```

- [x] **Step 5: 运行 Example 聚焦 GREEN**

使用 Step 3 相同命令。

Expected: PASS，状态序列化与 physical-bottom/pan UI 均 0 failures、0 skips。

- [x] **Step 6: 运行全部 Task 6 手势场景**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleTests \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSingleUpwardDragCollapsesHeaderThenContinuesIntoLongChild \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSingleDownwardDragReturnsLongChildThenExpandsHeader \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testShortAndPlainPagesRemainStableAcrossVerticalDrag \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testExpandedTopPullUsesContainerBounceWithoutChildBounce \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSwitchingPagesRebindsVerticalOwnerWithoutJump \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainPageRootReachesPhysicalBottomAndUsesContainerOnlyPan test
```

Expected: PASS；记录实际测试数、0 failures、0 skips 和墙钟时间。

- [x] **Step 7: 自审并提交 Example 验收**

确认 root probe 仅存在 Example target、不拦截触摸、不隐藏 label accessibility；所有手势使用真实 coordinate drag，无固定 sleep。

```bash
git diff --check
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift \
  Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift \
  Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift \
  Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "验证无滚动页面完整几何"
```

---

### Task 4: 文档清理、完整验收与修复复审

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-13-plain-page-direct-containment-design.md`
- Modify: `docs/superpowers/plans/2026-07-13-plain-page-direct-containment.md`
- Modify: `docs/superpowers/plans/2026-07-13-v0-5-scroll-coordination.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Task 1–3 的实现、测试结果和提交。
- Produces: 无 fallback owner 的当前文档、完整验收证据、可重新进入 v0.5 Task 7 的门禁状态。

- [x] **Step 1: 清理当前文档中的 fallback 现行语义**

执行：

```bash
rg -n 'fallback host|fallback scroll host|AnchorPagerPageScrollHostViewController' \
  README.md docs/architecture.md docs/requirements.md docs/task-list.md AGENTS.md
```

保留历史计划/旧规格中的 superseded 记录；README、architecture、requirements 的现行描述必须统一为：original page 直接 Pageboy containment、scroll target nil、无 managed inset/snapshot/bounce。把 task-list 本修复五项标记为完成，并把 v0.5 Task 7 从“暂停”改为“可重新开始但尚未完成”。

- [x] **Step 2: 运行依赖与源码静态门禁**

```bash
swift package resolve
git diff --check
rg -n 'AnchorPagerPageScrollHostViewController|fallbackHost.create' Sources Tests
rg -n '\.delegate\s*=|panGestureRecognizer\.delegate\s*=' Sources/AnchorPager
```

Expected: resolve 成功；diff check 无输出；fallback 生产/测试符号无结果；delegate 扫描只有框架自有 container delegate proxy 允许项。

- [x] **Step 3: 运行 Framework 全量测试**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO test
```

Expected: 全部 Framework tests 0 failures、0 skips；记录测试数与墙钟时间。

- [x] **Step 4: 运行 Example generic build 与全量测试**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO test
```

Expected: build 成功；全部 Example unit/UI tests 0 failures、0 skips；记录测试数与墙钟时间。

- [x] **Step 5: 完成代码自审**

逐项记录结论：

1. public API 与第三方类型泄漏；
2. Pageboy 对 plain/scroll page 的唯一 containment 与 appearance complete/cancel；
3. Store page/scroll/empty 三态、generation migration、retention 和 cleanup；
4. nil scroll page 不参与 managed inset、snapshot、bounce、observation 或 simultaneous pair；
5. shared scroll collision 不写冲突目标；
6. 真实 scroll page delegate/pan delegate、inset 和 handoff 无回归；
7. plain root 到 pager/window bottom，真实 pan 只驱动 container；
8. 日志只在首次解析状态变化时输出；
9. Example probe 不写入框架 API且不伪造 fallback offset；
10. 文档与真实实现一致，v0.5 只重新开放 Task 7，不提前 Ready。

- [x] **Step 6: 写入实际验收结果并提交**

把 Step 2–5 的实际命令、测试数、失败/跳过数、墙钟时间和自审结论写入本计划与 v0.5 总计划。

```bash
git diff --check
git add README.md docs AGENTS.md
git commit -m "完成无滚动页面直接承载验收"
```

- [x] **Step 7: 确认工作区状态**

```bash
git status --short
git log -4 --oneline
```

Expected: 工作区无未解释改动；最近四个实施提交依次覆盖 Store 三态、wrapper 移除、Example 验收和最终文档，设计提交 `1801b8f` 位于它们之前。

## 实际验收记录

### 实施提交与 RED/GREEN

1. `1b4d542 重建无滚动页面状态语义`：Store RED 共 34 项、26 项按预期失败；实现后 Store 与 managed inset 相关 40 项全部通过。
2. `7e92fdd 移除无滚动页面包装容器`：删除 synthetic wrapper，Pageboy 直接 containment、nil binding、reload/teardown 和生命周期相关 126 项全部通过。
3. `62a34a8 验证无滚动页面完整几何`：状态序列化 RED 先因缺少 `hasScrollTarget` 编译失败；实现后 8 项单元测试与 6 个真实手势场景共 14 项全部通过，0 failures、0 skips，墙钟约 77.6 秒。重命名整理后，8 项单元测试与 3 个 plain page 聚焦 UI 场景再次通过。

### 完整验收

- `swift --version`：Apple Swift 6.3.3，满足最低 Swift 6.2 基线。
- `swift package resolve`：成功。
- `xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO test`：提交前复验 220 tests、0 failures、0 skips；xcresult 记录约 4.511 秒，测试 observer 约 3.229 秒。
- `xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build`：提交前复验成功。
- `xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO test`：提交前复验 30 tests、0 failures、0 skips；xcresult 记录约 233.599 秒，测试 observer 约 230.004 秒。
- `git diff --check`：通过。
- `rg -n 'AnchorPagerPageScrollHostViewController|fallbackHost.create' Sources Tests`：无结果。
- public API Tabman/Pageboy 扫描：无结果。
- unsafe 并发标记扫描：无结果。
- delegate 赋值扫描仅命中框架自有 `verticalScrollView.delegate = verticalScrollDelegate`，没有业务 child `UIScrollView.delegate` 或 pan delegate 写入。
- 唯一剩余输出为运行目标/LLDB 模拟器环境提示，没有新增生产 warning。

### 代码自审结论

1. public API 未扩大，Tabman/Pageboy 类型未泄漏；Pageboy 继续对 plain/scroll page 执行唯一 containment 与 appearance complete/cancel。
2. Store 明确区分 empty、plain page 和真实 scroll page 三态；generation migration、retention、reload commit/cancel 与 cleanup 只归还真实 scroll ownership。
3. nil scroll page 不参与 managed inset、snapshot、child observation、bounce、simultaneous pair 或 scroll-to-top 替代 owner；shared scroll 冲突目标不会被写入。
4. 真实 scroll page 的业务 delegate/pan delegate、managed inset、snapshot 与纵向 handoff 路径保持不变。
5. UIKit 与真实 simulator drag 均证明 plain root 至少覆盖 pager/window 物理底边；当时的第二次上推验收证明没有 synthetic child distance。后续 container bottom 可见 bounce 由 `2026-07-13-boundary-bounce-ownership-design.md` 接管，不改变 nil child scroll target 事实。
6. `scroll.target.none` 只在首次解析无目标状态时记录；Example 的 root/state probe 仅位于示例 target，不拦截触摸，也不伪造 synthetic offset。
7. 文档已统一为 direct containment + nil scroll target；本专项修复完成，第四次整分支独立复审和最终状态门禁均已完成，v0.5 Task 7 标记 Ready。

### 边界 owner 集成后的新鲜复验

- `f81ca1e`、`5b80893` 与 `128821f` 复审修复后，生产代码 HEAD `128821f` 对应 Framework 283/283 结果包 `/private/tmp/AnchorPagerPresentedTopFrameworkFull-20260713-2258.xcresult`；最终 Example 37/37 与 generic Simulator build 通过，0 fail、0 skip。
- plain page 仍为 original Pageboy containment、committed scroll target nil、无 managed inset/snapshot/child pan；顶部 `.container`、底部 container presentation、`.child` 顶部不可用且不回退的真实 UI 均通过。
- `testPlainPageRootReachesPhysicalBottomAndUsesContainerOnlyPan`、plain top/bottom bounce 用例均包含在本轮 Example 全量 xcresult 中。
- 第四次整分支独立复审为 Critical 0、Important 0、Minor 2；两个 Minor 已在最终状态提交中修复，本补充随 v0.5/v0.6 标记 Ready。
- 2026-07-14 分层 page presentation 在生产代码 HEAD `c37e829` 完成复验：Framework 293/293、Example 37/37 与 generic Simulator build 全部通过，0 fail、0 skip、0 error/warning/analyzer warning；direct containment、nil scroll target、物理底边和 container-only pan 均无回归。
