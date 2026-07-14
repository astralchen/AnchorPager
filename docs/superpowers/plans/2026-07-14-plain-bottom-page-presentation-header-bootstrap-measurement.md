# 无滚动页底部内容层回弹与 Header Bootstrap 测量 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**目标：** 保留无滚动页由外层 `verticalScrollView` 提供的 UIKit 原生底部回弹物理，但只移动 Pageboy 页面内容层，确保 Header/Tabman bar 不越过顶部安全区；同时消除 automatic Header 首次 required `height == 0` 中立布局引发的约束冲突。

**架构：** `AnchorPagerViewController` 把 container raw overflow 拆成 chrome translation 与 page-surface translation；顶部 container bounce 继续变换共享 `viewportView`，plain bottom 仅通过 `AnchorPagerPagingHostViewController` 转发到 adapter 内标准 `UIPageViewController.view`。`AnchorPagerLayoutContext` 继续报告实际可见坐标。Header 首次无缓存时先做不发布状态的 compressed fitting，再用 seed 建立 required 中立几何并执行正式测量。Scroll/Overscroll coordinator、PageStateStore、Pageboy containment、业务 child scroll ownership 均不改变。

**技术栈：** Swift 6.2、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、Tabman 4.0.1、Pageboy 5.0.2、XCTest/XCUITest、Xcode 26.3。

**当前状态：** 设计已确认并提交为 `7a72e15`；生产修复、RED/GREEN、完整验收和独立复审尚未执行，v0.5 Task 7 与 v0.6 当前不标记 Ready。

---

## 全局约束

- 不修改任何 Public API；`AnchorPagerLayoutContext` 只修正既有“实际可见坐标”语义。
- 不读取 Pageboy private/internal symbol；adapter 只通过 UIKit 标准 `children` containment 定位 `UIPageViewController`。
- 不对业务 page controller 再次 `addChild`，不直接修改业务 page 根 view 的 transform。
- 不设置业务 child `UIScrollView.delegate`、业务 pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。
- 不创建 synthetic scroll wrapper；plain page 保持 committed page 非 nil、committed scroll target 为 nil。
- `AnchorPagerScrollCoordinator` 仍是协调期唯一 offset 写入者；`AnchorPagerOverscrollCoordinator` 不增加 UIKit/page/provider 引用。
- presentation 不进入 LayoutEngine output、Store、generation、cache、snapshot、managed inset 或 scroll range。
- 高频 scroll callback 不逐帧写日志；page surface 缺失只在“可用 → 不可用”状态变化时记录一次。
- 每个任务遵循 RED → 最小 GREEN → 聚焦回归 → 自审 → `git diff --check` → 中文单一主题提交。

---

## 文件与职责

- `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`：internal 页面 presentation surface 定位、transform 写入和 teardown 前归零。
- `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`：转发 page translation，按不可用状态去重日志，并在 adapter 安装/移除时清理状态。
- `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：计算 chrome/page 分层 presentation、plain committed 门禁、LayoutContext 可见坐标和统一 cancel 清理。
- `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`：提供不发布状态、不写正式测量日志的 bootstrap fitting。
- `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`：surface/bar 排他、归零和 removal 清理。
- `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`：surface unavailable 日志去重和状态恢复。
- `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：plain bottom 分层坐标、真实页面移动、cancel/reload/header layout 清理、top/child 相邻回归和首次非零 Header 布局。
- `Tests/AnchorPagerTests/AnchorPagerHeaderViewHostTests.swift`：bootstrap 与正式 measurement 的返回值/日志边界。
- `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`：增加 bar current/max 探针字段。
- `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`：分开采样 page content 与 bar presentation。
- `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`：探针序列化与 reset 单元测试。
- `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：plain bottom 页面可见回弹、bar 固定和终态归零真实手势验收。
- `README.md`、`docs/requirements.md`、`docs/architecture.md`、`docs/task-list.md`、相关 specs/plans、`AGENTS.md`：同步最终契约、状态、测试与复审证据。

---

### Task 1：建立 Paging Page Presentation Surface

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`

**Interfaces:**
- Produces: `AnchorPagerPagingAdapter.setPagePresentationTranslationY(_:) -> Bool`。
- Produces: `AnchorPagerPagingHostViewController.setPagePresentationTranslationY(_:) -> Bool`。
- Consumes: Tabman/Pageboy 已有标准 UIKit child containment；不把 `UIPageViewController` 暴露出 Paging internal 层。

- [x] **Step 1：先写 adapter surface/bar 排他的失败测试**

在 `AnchorPagerPagingAdapterTests` 新增：

```swift
@MainActor
func testPagePresentationMovesPageboySurfaceWithoutMovingBarAndCanReset() throws {
    let page = UIViewController()
    let adapter = AnchorPagerPagingAdapter()
    adapter.setBarHeight(44)
    reload(adapter, titles: ["Plain"], viewControllers: [page], selectedIndex: 0)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = adapter
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    window.layoutIfNeeded()

    let pageViewController = try XCTUnwrap(
        adapter.children.compactMap { $0 as? UIPageViewController }.first
    )
    let barView = try XCTUnwrap(adapter.bars.first as? UIView)
    let barFrame = barView.frame
    let barTransform = barView.transform

    XCTAssertTrue(adapter.setPagePresentationTranslationY(-24))
    XCTAssertEqual(pageViewController.view.transform.ty, -24, accuracy: 0.001)
    XCTAssertEqual(barView.frame, barFrame)
    XCTAssertEqual(barView.transform, barTransform)

    XCTAssertTrue(adapter.setPagePresentationTranslationY(0))
    XCTAssertEqual(pageViewController.view.transform, .identity)
}
```

新增 `testPrepareForRemovalResetsPagePresentationBeforeContainmentTeardown`：通过 `adapter.children.compactMap { $0 as? UIPageViewController }.first` 记录 page surface，设置 `-24`，调用 `prepareForRemoval()`，断言旧 surface 在 containment teardown 前已经恢复 `.identity`。bar 身份固定通过 public `adapter.bars.first as? UIView` 取得，不使用 subview 顺序。

- [x] **Step 2：写 PagingHost 不可用日志去重的失败测试**

在 `AnchorPagerPagingHostViewControllerTests` 新增 `testMissingPagePresentationSurfaceLogsOnceUntilStateRecovers`：

```swift
let host = AnchorPagerPagingHostViewController()
var events: [AnchorPagerLogger.Event] = []
AnchorPagerLogger.sink = { events.append($0) }
defer { AnchorPagerLogger.sink = nil }

XCTAssertFalse(host.setPagePresentationTranslationY(-12))
XCTAssertFalse(host.setPagePresentationTranslationY(-18))
XCTAssertTrue(host.setPagePresentationTranslationY(0))
XCTAssertFalse(host.setPagePresentationTranslationY(-12))

XCTAssertEqual(
    events.filter { $0.event == "paging.pagePresentation.unavailable" }.count,
    2
)
```

- [x] **Step 3：运行 RED，确认失败原因只是不具备新 internal 接口**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests/testPagePresentationMovesPageboySurfaceWithoutMovingBarAndCanReset -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests/testPrepareForRemovalResetsPagePresentationBeforeContainmentTeardown -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests/testMissingPagePresentationSurfaceLogsOnceUntilStateRecovers test
```

预期：编译失败，明确缺少 `setPagePresentationTranslationY(_:)`；不得出现不相关测试或依赖失败。

- [x] **Step 4：在 adapter 实现最小 surface 接缝**

在 `AnchorPagerPagingAdapter` 增加：

```swift
@discardableResult
func setPagePresentationTranslationY(_ translationY: CGFloat) -> Bool {
    guard let pageViewController = children
        .compactMap({ $0 as? UIPageViewController })
        .first,
        pageViewController.isViewLoaded else {
        return translationY == 0
    }

    pageViewController.view.transform = translationY == 0
        ? .identity
        : CGAffineTransform(translationX: 0, y: translationY)
    return true
}
```

在 `prepareForRemoval()` 的任何 Pageboy delete/teardown 之前调用 `setPagePresentationTranslationY(0)`；不遍历或变换业务 page root。

- [x] **Step 5：在 PagingHost 实现转发与状态变化日志**

新增 `private var isPagePresentationSurfaceUnavailable = false`，并实现：

```swift
@discardableResult
func setPagePresentationTranslationY(_ translationY: CGFloat) -> Bool {
    let didApply = activeAdapter?.setPagePresentationTranslationY(translationY)
        ?? (translationY == 0)
    let isUnavailable = !didApply && translationY != 0
    if isUnavailable && !isPagePresentationSurfaceUnavailable {
        AnchorPagerLogger.log(
            .error,
            category: .paging,
            event: "paging.pagePresentation.unavailable"
        )
    }
    isPagePresentationSurfaceUnavailable = isUnavailable
    return didApply
}
```

`installAdapter()` 建立新 adapter 前把 unavailable 状态归零；`removeActiveAdapterIfNeeded` 在 `prepareForRemoval()` 前显式请求 translation `0`，移除后再归零状态。不得因 surface 缺失退化为变换 Host、bar 或业务 page root。

- [x] **Step 6：运行 GREEN 与 Paging 相邻回归**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests test
git diff --check
```

预期：两个测试类全部通过；新增日志测试为状态变化 2 次，而不是每次调用 3 次。

- [x] **Step 7：自审并提交 Task 1**

自审确认只操作 `UIPageViewController.view`、未依赖 child 顺序、未把 Pageboy/UIKit 类型泄漏到 Public、teardown 前 identity、日志不在成功热路径输出。

```bash
git add Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift
git commit -m "增加分页内容层回弹接缝"
```

**执行记录（2026-07-14）：** 目标 RED 因 adapter/host 缺少 presentation 接口按预期编译失败；最小实现后 3 项目标测试与 `AnchorPagerPagingAdapterTests`、`AnchorPagerPagingHostViewControllerTests` 两个完整测试类均通过。`git diff --check` 通过；自审确认只操作标准 `UIPageViewController.view`，bar/业务 page/containment/业务滚动配置不变，日志按不可用状态去重。基线首次全量构建显示两条既有 weak-variable 警告，增量 GREEN 未新增警告。

---

### Task 2：拆分 Plain Bottom Chrome 与 Page Presentation

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Consumes: `pageStateStore.committedCurrentPageViewController` 与 `committedCurrentScrollView`。
- Produces: private `ContainerPresentation`；Public `AnchorPagerLayoutContext` 类型不变。

- [ ] **Step 1：把旧 plain bottom 测试改成新契约并先运行 RED**

将 `testPlainBottomOverflowTranslatesViewportUpWithoutChangingCanonicalRange` 重命名为 `testPlainBottomOverflowMovesOnlyPageSurfaceAndRestoresCanonicalChrome`。在 collapsed offset `100` 保存 Header/bar/content context 和 plain page 在 pager 坐标中的 frame；把 offset 改为 `124` 后断言：

```swift
XCTAssertEqual(context.headerFrame, collapsedContext.headerFrame)
XCTAssertEqual(context.barFrame, collapsedContext.barFrame)
XCTAssertEqual(
    context.contentFrame.minY,
    collapsedContext.contentFrame.minY - 24,
    accuracy: 0.5
)
XCTAssertEqual(
    plainChild.view.convert(plainChild.view.bounds, to: pager.view).minY,
    collapsedPlainFrame.minY - 24,
    accuracy: 0.5
)
XCTAssertEqual(pager.verticalScrollView.contentSize, initialContentSize)
XCTAssertEqual(try XCTUnwrap(delegate.collapseProgresses.last), 1, accuracy: 0.001)
```

回到 offset `100` 后断言三帧与真实 plain frame 全部恢复。运行：

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testPlainBottomOverflowMovesOnlyPageSurfaceAndRestoresCanonicalChrome test
```

预期：旧实现因 Header/bar 同时上移 `24 pt` 失败。

- [ ] **Step 2：先补 cancel/reload/header layout 的失败测试**

新增 `testPlainBottomPresentationResetsForSelectionReloadAndHeaderLayoutCancellation`，使用两个 plain controller 和固定 Header：

1. 对第一页制造 `24 pt` bottom overflow，并捕获 adapter 内 `UIPageViewController.view`。
2. `setSelectedIndex(1, animated: false)` 后断言 surface identity。
3. 对第二页再次制造 overflow，调用 `reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)`，断言 surface identity。
4. 再次制造 overflow，把 data source 改为空并调用 `reloadData()`，断言旧 surface identity、adapter 被移除、LayoutContext 不保留负向 page translation。

把现有 `testNegativeContainerOffsetTranslatesViewportAndLayoutContextWithoutChangingRange` 增强为 top bounce 时 Header/bar/content 同量 `+24` 且 adapter page surface 自身 transform 为 identity；保留真实 child bottom、plain direct containment、nil scroll target、物理底边测试不变。

- [ ] **Step 3：在 ViewController 引入分层 presentation 值对象**

删除 `containerOverscrollTranslationY(for:)`，新增：

```swift
private struct ContainerPresentation {
    let chromeTranslationY: CGFloat
    let pageSurfaceTranslationY: CGFloat

    var contentTranslationY: CGFloat {
        chromeTranslationY + pageSurfaceTranslationY
    }
}

private func containerPresentation(
    for output: AnchorPagerLayoutEngine.Output
) -> ContainerPresentation {
    let offset = verticalScrollView.contentOffset.y
    let collapsed = output.resolvedHeaderHeight.collapsibleDistance
    let topOverflow = Swift.max(0, -offset)
    let bottomOverflow = Swift.max(0, offset - collapsed)
    let hasCommittedPlainPage =
        pageStateStore.committedCurrentPageViewController != nil &&
        pageStateStore.committedCurrentScrollView == nil

    return ContainerPresentation(
        chromeTranslationY: topOverflow,
        pageSurfaceTranslationY: hasCommittedPlainPage ? -bottomOverflow : 0
    )
}
```

门禁必须同时要求 committed page 非 nil 和 committed scroll nil；empty/pending provider 不得成为 plain owner。

- [ ] **Step 4：按实际 surface 应用结果更新 transform 与 LayoutContext**

`applyLayoutOutput` 的顺序调整为：

```swift
let requestedPresentation = containerPresentation(for: output)
viewportView.transform = CGAffineTransform(
    translationX: 0,
    y: requestedPresentation.chromeTranslationY
)
let didApplyPagePresentation = pagingHost.setPagePresentationTranslationY(
    requestedPresentation.pageSurfaceTranslationY
)
let appliedPresentation = ContainerPresentation(
    chromeTranslationY: requestedPresentation.chromeTranslationY,
    pageSurfaceTranslationY: didApplyPagePresentation
        ? requestedPresentation.pageSurfaceTranslationY
        : 0
)
```

把 `layoutContext(for:translationY:)` 改为：Header/bar 只加 `chromeTranslationY`，content 加 `contentTranslationY`。surface 不可用时 context 不得报告未发生的 page 位移。

- [ ] **Step 5：统一边界取消与 presentation 清理**

新增 private helper：

```swift
private func cancelBoundaryPresentation() {
    scrollCoordinator?.cancelBoundaryHandling()
    viewportView.transform = .identity
    _ = pagingHost.setPagePresentationTranslationY(0)
}
```

用它替换 `viewWillTransition`、`reloadData`、`reloadHeaderLayout`、matching `willPerformReloadRequest`、`willSelect` 中现有五处直接 `cancelBoundaryHandling()`。`deinit` 的 `MainActor.assumeIsolated` 块也在释放 Store 前请求 page translation `0`。stable layout 每轮仍显式设置 page translation `0`，所以 didSelect、didCancel、committed rebind 和普通 settle 不依赖动画 completion 清理。

- [ ] **Step 6：运行目标 GREEN 与边界相邻回归**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testPlainBottomOverflowMovesOnlyPageSurfaceAndRestoresCanonicalChrome -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testPlainBottomPresentationResetsForSelectionReloadAndHeaderLayoutCancellation -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testNegativeContainerOffsetTranslatesViewportAndLayoutContextWithoutChangingRange -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testPlainPageRootReachesPagerAndWindowBottomWithoutFrameworkInsets -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testCommittedPlainPageBindsNoChildPanAndContainerStillCollapses test
git diff --check
```

预期：目标和相邻回归全部通过；Header/bar 在 plain bottom 中 `0 pt` 位移，content/plain page 为 `-24 pt`，stable 后全部归零。

- [ ] **Step 7：自审并提交 Task 2**

自审 committed/pending/empty 门禁、LayoutContext 实际坐标、top/child 相邻路径、五个 cancel 入口、deinit、无二次 offset writer、无业务 root transform。

```bash
git add Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "分离无滚动页底部内容回弹"
```

---

### Task 3：修复 Automatic Header 首次 Bootstrap Measurement

**Files:**
- Modify: `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerHeaderViewHostTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Produces: `AnchorPagerHeaderViewHost.bootstrapMeasurement(in:) -> CGFloat`，仅 internal。
- Keeps: `measure(in:)` 的 invalid assertion、`header.measure.invalid` 与正式 `header.measure` 日志语义。

- [ ] **Step 1：写 bootstrap 不发布正式日志的失败测试**

在 `AnchorPagerHeaderViewHostTests` 新增 `testBootstrapMeasurementReturnsFittingHeightWithoutPublishingFormalMeasurementLog`：安装 `FixedFittingView(height: 64)`，调用 `bootstrapMeasurement(in:)`，断言返回 `64`，并断言 sink 中没有 `header.measure` 与 `header.measure.invalid`。

- [ ] **Step 2：写首次非零布局的 UIKit RED**

在 `AnchorPagerViewControllerTests` 增加 `ConstrainedLayoutRecordingHeaderView`：内部 content view 高 `44`，top 等于 safeArea top `+20`，bottom 小于等于 safeArea bottom `-20`；`layoutSubviews()` 仅在 `window != nil && bounds.width > 1 && bounds.height <= 0.5` 时把 `didLayoutAtRequiredZeroHeight` 置为 true。

新增 `testAutomaticHeaderBootstrapNeverLaysOutConstrainedContentAtRequiredZeroHeight`：

```swift
var configuration = AnchorPagerConfiguration.default
configuration.header.heightMode = .automatic(min: 0, max: nil)
let pager = AnchorPagerViewController(configuration: configuration)
let header = ConstrainedLayoutRecordingHeaderView()
let delegate = StubDelegate()
pager.dataSource = StubDataSource(
    count: 1,
    viewControllers: [UIViewController()],
    headerContent: .view(header)
)
pager.delegate = delegate
let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
window.rootViewController = pager
window.makeKeyAndVisible()
defer { window.isHidden = true }

pager.reloadData()
window.layoutIfNeeded()

XCTAssertFalse(header.didLayoutAtRequiredZeroHeight)
XCTAssertGreaterThan(try XCTUnwrap(delegate.layoutContexts.last).headerFrame.height, 0)
```

- [ ] **Step 3：运行 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerHeaderViewHostTests/testBootstrapMeasurementReturnsFittingHeightWithoutPublishingFormalMeasurementLog -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testAutomaticHeaderBootstrapNeverLaysOutConstrainedContentAtRequiredZeroHeight test
```

预期：先因缺少 `bootstrapMeasurement` 编译失败；接口补齐但 ViewController 未采用 seed 时，UIKit 测试应因记录到 zero-height layout 失败。

- [ ] **Step 4：实现无副作用 bootstrap fitting**

在 HeaderHost 新增：

```swift
func bootstrapMeasurement(in size: CGSize) -> CGFloat {
    let measuredHeight = measuredContentHeight(in: size)
    guard !isInvalidMeasuredHeight(measuredHeight) else { return 0 }
    return Swift.max(0, measuredHeight)
}
```

不在该方法中写 assertion、正式 measurement 日志或外部状态；`measure(in:)` 保持既有正式校验与日志。

- [ ] **Step 5：让首次中立布局使用 seed 并先清理两层 presentation**

把 `measureHeaderHeight(in:)` 改为：

```swift
private func measureHeaderHeight(in environment: LayoutEnvironment) -> CGFloat {
    viewportView.transform = .identity
    _ = pagingHost.setPagePresentationTranslationY(0)
    headerViewHost.setTopOffset(environment.bounds.minY + environment.obstruction.top)
    let fittingSize = CGSize(
        width: environment.bounds.width,
        height: UIView.layoutFittingCompressedSize.height
    )
    let neutralHeight = lastMeasuredHeaderHeight
        ?? headerViewHost.bootstrapMeasurement(in: fittingSize)
    headerHeightConstraint?.constant = neutralHeight
    view.layoutIfNeeded()
    return headerViewHost.measure(in: fittingSize)
}
```

仅正式返回值由既有 caller 更新 `lastMeasuredHeaderHeight`；bootstrap 不更新 context/progress/range/frame 日志缓存。

- [ ] **Step 6：运行 GREEN 与 automatic Header 相邻回归**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerHeaderViewHostTests -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testAutomaticHeaderBootstrapNeverLaysOutConstrainedContentAtRequiredZeroHeight -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadHeaderLayoutPreservesVisualPositionWhenHeaderHeightChanges -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadHeaderLayoutPreservesCollapseProgressWhenHeaderHeightChanges -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testRuntimeHeaderFrameChangeUpdatesLayoutContext test
git diff --check
```

预期：全部通过；bootstrap 测得 `64` 但没有正式日志，正式测量仍保留 `header.measure`。

- [ ] **Step 7：自审并提交 Task 3**

自审 UIView/UIViewController Header、`preferredContentSize` 优先级、safe area 中立位置、无缓存/有缓存、invalid 降级、presentation 清理和日志边界。

```bash
git add Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerHeaderViewHostTests.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "修复页眉首次中立测量"
```

---

### Task 4：升级 Example 探针与真实 UI 验收

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Adds Example-only fields: `barPresentation`、`maximumBarPresentation`。
- Adds accessibility probe fields: `barCurrent`、`barMax`。

- [ ] **Step 1：先更新 Example 单元/UI 期望并运行 RED**

所有 `ExampleScrollCoordinationState` 构造增加 bar 两字段；序列化字符串在 `containerBottomMax` 后加入 `barCurrent`、`barMax`；reset 测试断言二者归零。UI parser 增加同名字段，并把 `hasZeroPresentationMetrics` 加入 `abs(barCurrent) < 0.5 && barMax < 0.5`。

把 `testPlainContainerBottomBounceIsVisible` 的等待条件改为：

```swift
$0.containerBottomMax > 1
    && $0.barMax < 0.5
    && abs($0.containerCurrent) < 0.5
    && abs($0.barCurrent) < 0.5
```

保留 `hasScrollTarget == false` 和 settled 后 plain root 到物理屏幕底部断言。

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleTests/AnchorPagerExampleTests test
```

预期：Example model 尚无 bar 字段，编译失败。

- [ ] **Step 2：实现 page/bar 分层探针**

在 Example controller 增加 expanded/collapsed bar baseline 和 collapsed content baseline。stable 时按 collapse progress 更新 Header、bar、content baseline并把 current presentation 归零；top overflow 继续用 Header frame 计算 `containerPresentation`，同时用 expanded bar baseline 更新 bar current/max；bottom overflow 改用：

```swift
let pagePresentation = context.contentFrame.minY - collapsedContentBaselineY
let barPresentation = context.barFrame.minY - collapsedBarBaselineY
scrollCoordinationState.containerPresentation = pagePresentation
scrollCoordinationState.maximumContainerBottomPresentation = max(
    scrollCoordinationState.maximumContainerBottomPresentation,
    -pagePresentation
)
scrollCoordinationState.barPresentation = barPresentation
scrollCoordinationState.maximumBarPresentation = max(
    scrollCoordinationState.maximumBarPresentation,
    abs(barPresentation)
)
```

所有 baseline 必须来自 stable LayoutContext，不能读取或变换业务 view。`resetPresentationMetrics()` 清零 current/max 但保留 baseline。

- [ ] **Step 3：运行 Example 单元与目标 UI GREEN**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleTests/AnchorPagerExampleTests -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainContainerBottomBounceIsVisible test
```

预期：Example 单元全部通过；真实拖拽采到 page bottom max `> 1 pt`、bar max `< 0.5 pt`，松手后 current 全部 `< 0.5 pt`，plain root settled 时到达物理屏幕底部。

- [ ] **Step 4：运行边界 owner 相邻 UI 回归**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainContainerTopBounceIsVisible -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testRealChildContainerTopBounceIsVisible -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testRealChildBottomBounceUsesChild -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSwitchingPagesRebindsVerticalOwnerWithoutJump test
git diff --check
```

预期：container top、real child top/bottom 和切页 owner 全部通过；plain bottom 新探针没有影响 child owner 排他。

- [ ] **Step 5：自审并提交 Task 4**

自审探针只读 LayoutContext、stable baseline 不被 overscroll 污染、UI reset 可靠、bar max 不继承前一段手势、无测试专用框架 Public API。

```bash
git add Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "补强无滚动页回弹界面验收"
```

---

### Task 5：同步长期文档、全量验收与复审门禁

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-11-dual-header-top-behavior-bounce-stability-design.md`
- Modify: `docs/superpowers/specs/2026-07-13-boundary-bounce-ownership-design.md`
- Modify: `docs/superpowers/specs/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement-design.md`
- Modify: `docs/superpowers/plans/2026-07-11-dual-header-top-behavior-bounce-stability.md`
- Modify: `docs/superpowers/plans/2026-07-13-boundary-bounce-ownership.md`
- Modify: `docs/superpowers/plans/2026-07-13-v0-5-scroll-coordination.md`
- Modify: `docs/superpowers/plans/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement.md`

- [ ] **Step 1：同步最终架构与测试契约，但暂不提前标记 Ready**

文档必须明确：

1. plain bottom 的物理 owner 仍是 `verticalScrollView`，visible target 仅是 Pageboy page surface。
2. Header/bar canonical；top container 仍整体移动；real child 路径不变。
3. LayoutContext 的 content frame 在 plain bottom 反映实际 page translation。
4. 首次 automatic Header 使用 bootstrap seed，不再 required zero-height layout。
5. Public API、Pageboy containment、Store/inset/snapshot、业务 child 配置不变。
6. Task 1–4 的实际提交、目标测试和已知未完成门禁如实记录；完整验收和复审完成前保持 Not Ready。

- [ ] **Step 2：执行静态架构门禁**

```bash
rg -n 'import (Tabman|Pageboy)' Sources/AnchorPager/Public
rg -n '(scrollView|child).*\.delegate\s*=|panGestureRecognizer\.delegate\s*=|isScrollEnabled\s*=|\.bounces\s*=|\.alwaysBounceVertical\s*=' Sources/AnchorPager/Children Sources/AnchorPager/Core Sources/AnchorPager/Gesture Sources/AnchorPager/Overscroll Sources/AnchorPager/Paging
rg -n 'AnchorPagerPageScrollHost|synthetic.*scroll|nonisolated\(unsafe\)|@unchecked Sendable|@preconcurrency' Sources
git diff --check
```

预期：前三个 `rg` 无输出（exit 1），`git diff --check` exit 0。外层 `verticalScrollView.delegate` 与 `alwaysBounceVertical` 的既有合法配置不在扫描目录中。

- [ ] **Step 3：解析依赖并运行完整 Framework**

```bash
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -resultBundlePath /private/tmp/AnchorPagerPlainBottomFramework-20260714-7a72e15.xcresult test
```

预期：全部 Framework 测试通过，0 fail、0 skip；记录实际 test count、Swift/Xcode 版本、结果包路径和生产代码 HEAD。

- [ ] **Step 4：运行完整 Example 单元/UI 与 generic build**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO -resultBundlePath /private/tmp/AnchorPagerPlainBottomExample-20260714-7a72e15.xcresult test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -resultBundlePath /private/tmp/AnchorPagerPlainBottomBuild-20260714-7a72e15.xcresult build
```

预期：Example unit/UI 全部通过，0 fail、0 skip；generic Simulator build 成功。结果包均为 0 error、0 warning、0 analyzer warning。首次启动控制台不再出现本任务所述 `UIView.height == 0` 与 Header safe-area content 的 unsatisfiable constraints；自动化门禁以 `ConstrainedLayoutRecordingHeaderView` 测试为准，控制台检查为补充证据。

- [ ] **Step 5：执行实现者自审**

逐项检查并在本计划末尾记录结论：

- Public API/第三方泄漏。
- UIKit containment、selection/reload terminal、appearance lifecycle。
- plain committed/pending/empty 门禁。
- top/plain bottom/real child presentation 与 LayoutContext。
- cancel、settle、reload、selection、rotation、empty、removal、deinit 清理。
- Header UIView/UIViewController、有缓存/无缓存、invalid measurement。
- actor 隔离、日志去重、测试覆盖、文档状态和验收命令。

- [ ] **Step 6：执行独立代码复审并清零阻塞问题**

复审范围从 `7a72e15` 到最新生产提交，重点比较 Paging adapter surface、ViewController owner/presentation 门禁、Header bootstrap 和 Example UI 探针。Critical/Important 必须修复并重新运行受影响目标与完整验收；Minor 要么修复，要么在计划中给出明确不阻塞理由。复审未清零前不得恢复 Ready。

- [ ] **Step 7：写入真实验收证据并恢复门禁状态**

只有 Step 2–6 全部完成后，才把 design/spec/plan 状态改为完成，在 `docs/task-list.md` 勾选专项修复与 v0.5/v0.6 当前 Ready，并写入实际测试总数、结果包、HEAD、0 error/warning/analyzer warning、自审和独立复审结论。

```bash
git diff --check
git add README.md AGENTS.md docs/requirements.md docs/architecture.md docs/task-list.md docs/superpowers/specs/2026-07-11-dual-header-top-behavior-bounce-stability-design.md docs/superpowers/specs/2026-07-13-boundary-bounce-ownership-design.md docs/superpowers/specs/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement-design.md docs/superpowers/plans/2026-07-11-dual-header-top-behavior-bounce-stability.md docs/superpowers/plans/2026-07-13-boundary-bounce-ownership.md docs/superpowers/plans/2026-07-13-v0-5-scroll-coordination.md docs/superpowers/plans/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement.md
git commit -m "同步内容层回弹修复验收"
```

---

## 最终完成定义

- [ ] plain bottom native physics 仍由外层 container 提供，页面内容可见上移，Header/bar 始终保持安全区吸顶。
- [ ] top container、real child top/bottom、plain direct containment、nil scroll target、物理屏幕底边均无回归。
- [ ] stable、cancel、selection、reload、header layout、rotation、empty、removal、deinit 后 page surface identity。
- [ ] automatic Header 首次非空约束内容从未以 required zero height 参与布局，正式测量与 invalid 日志语义保持。
- [ ] Public API、Pageboy containment、Store/generation/cache/snapshot/inset、业务 child delegate/pan/bounce 配置不变。
- [ ] 聚焦 RED/GREEN、完整 Framework、完整 Example/UI、generic build、静态扫描和 `git diff --check` 均有新鲜通过证据。
- [ ] 实现者自审完成，独立复审 Critical 0、Important 0，长期文档只标记真实状态。

---

## 计划自审记录（2026-07-14）

- [x] 规格覆盖：设计中的物理 owner/presentation 分层、committed plain 门禁、LayoutContext、Header bootstrap、日志、清理、Example UI 与 Ready 门禁均映射到具体任务。
- [x] 文件与类型核对：所有修改路径存在；`committedCurrentPageViewController`、`committedCurrentScrollView`、`adapter.children`、`adapter.bars` 和五处 `cancelBoundaryHandling()` 均已按当前源码核实。
- [x] 测试名称核对：计划引用的既有 Framework/Example UI 测试名称与当前源码一致；新测试名称在各 Task 中唯一确定。
- [x] 第三方边界核对：Tabman 4.0.1 的 `TMBar` 约束为 `UIView`，Pageboy 内部页面容器可通过标准 child `UIPageViewController` 识别；计划不使用第三方 private/internal symbol。
- [x] 占位符扫描：没有遗留实现占位、开放选择或设备占位；目标设备固定为 `iPhone 17 Pro,OS=26.5`。
- [x] 状态真实性：当前只登记“设计与计划已确认”，没有提前勾选实现、测试、验收、复审或 Ready。
