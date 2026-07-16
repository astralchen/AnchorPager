# Compositional Layout 混合轴页面与手势冲突验证 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Example 现有五页之后新增一个以根 `UICollectionView` 纵向滚动、以 Compositional Layout orthogonal section 横向滚动的第六页，并用真实 UIKit 手势验证纵向 handoff、正交区域横向 winner、非正交区域 Pageboy 分页及 reload/lifecycle；若真实证据暴露框架冲突，只按已确认的根因门禁继续修复。

**Architecture:** 根 CollectionView 是页面唯一 `anchorPagerScrollView`，进入 Store、managed inset、ScrollCoordinator binding 和 container/current-child 最小 simultaneous pair；orthogonal section 只由 UIKit 管理，并仅通过 `visibleItemsInvalidationHandler` 输出 Example 测试进度。初始实现不修改 AnchorPager Framework、Paging adapter 或 GesturePriorityCoordinator，不发现 UIKit 内部 orthogonal scroll identity。Pageboy 冲突以真实 UI 为分支门禁：原生通过则保持 Framework 零改动；若失败需要新公共契约，则暂停并先修订设计。

**Tech Stack:** Swift 6.2、Swift 6 language mode、UIKit、`UICollectionViewCompositionalLayout`、iOS 14+、Swift Package Manager、Tabman 4.0.1、Pageboy 5.0.2、Swift Testing、XCTest/XCUITest、Xcode 26.6、iPhone 17 Pro / iOS 26.5 Simulator。

## Global Constraints

- 设计基线固定为 `docs/superpowers/specs/2026-07-16-compositional-layout-mixed-axis-gesture-validation-design.md`。
- 新页面追加为 index 5；empty/short/long/plain/horizontal 的 index 0 至 4 不变。
- 根 `UICollectionView` 是唯一纵向 target；UIKit orthogonal 内部 scroll 不进入 discovery、inset、snapshot、binding、overscroll 或 synthetic deceleration。
- 不修改/替换业务 scroll delegate、pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。
- 不遍历 UIKit 私有类名/层级，不使用 KVC/private selector，不 toggle/reset recognizer，不添加异步 delay 或全局方向锁。
- 不恢复 v0.7 已被真实 UI 否定的 `pagingPan -> arbitrary childPan` relation 或 guard。
- 不扩大 Public API；如果证据表明必须建立显式横向接入契约，立即停止当前实现，先更新设计并取得用户确认。
- Framework 生产代码初始零改动；只有根因分支完成新设计确认后才允许进入 Framework TDD。
- 新页面使用 iOS 14 API；不得调用 iOS 17 才提供的 `orthogonalScrollingProperties`。
- 严格执行 RED → 最小 GREEN → 聚焦真实 UI → 相邻回归 → 完整门禁 → 自审/fresh-pass → 中文单一主题提交。

---

### Task 1：用单元和 UI 测试建立第六页与混合轴 RED

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: `ExamplePagerViewController.pageForTesting(at:)`、Example data source、`scroll-coordination-state`、selection trace 和现有 `launchPage`。
- Produces: 第六页结构、横向进度值语义、纵向 handoff、正交横向 winner、非正交 Pageboy 与 reload/rebind 的失败契约。

- [ ] **Step 1：先把现有第五页数量断言迁移为六页**

保持 `horizontalBusinessPageIsFifthAndKeepsDelegateConfiguration()` 的 index 4、nil target 与 ownership 断言不变，只把 data source 总数改为 6；再新增：

```swift
@Test func compositionalPageIsSixthAndUsesRootCollectionAsVerticalTarget() throws {
    let viewController = ExamplePagerViewController(arguments: [])
    viewController.loadViewIfNeeded()
    let pager = try #require(
        viewController.children.compactMap { $0 as? AnchorPagerViewController }.first
    )

    #expect(pager.dataSource?.numberOfViewControllers(in: pager) == 6)
    #expect(
        pager.dataSource?.pagerViewController(
            pager,
            titleForViewControllerAt: 5
        ) == "组合布局页"
    )

    let page = try #require(viewController.pageForTesting(at: 5))
    page.loadViewIfNeeded()
    page.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
    page.view.layoutIfNeeded()
    let collectionView = try #require(
        firstSubview(in: page.view, as: UICollectionView.self) {
            $0.accessibilityIdentifier == "compositional-collection-view"
        }
    )

    #expect(collectionView.collectionViewLayout is UICollectionViewCompositionalLayout)
    #expect(page.anchorPagerScrollView === collectionView)
    #expect(collectionView.contentSize.height > collectionView.bounds.height + 0.5)
}
```

- [ ] **Step 2：运行结构单元 RED**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests/AnchorPagerExampleTests/compositionalPageIsSixthAndUsesRootCollectionAsVerticalTarget test
```

预期：FAIL，当前 data source 仍为 5，index 5 页面不存在。若因受限环境无法访问 Simulator/DerivedData，使用相同命令申请必要权限后重跑，不把基础设施错误记作功能 RED。

- [ ] **Step 3：增加横向进度纯值语义 RED**

新增 `compositionalScrollStateRecordsMaximumLeadingItemAndResets()`，要求 `ExampleCompositionalScrollState`：

```swift
var state = ExampleCompositionalScrollState()
state.record(horizontalOffset: 42, visibleItemIndexes: [1, 2])
state.record(horizontalOffset: 96, visibleItemIndexes: [2, 3])

#expect(state.currentHorizontalOffset == 96)
#expect(state.maximumHorizontalOffset == 96)
#expect(state.leadingHorizontalItem == 2)
#expect(state.serializedValue == "horizontalCurrent=96.00;horizontalMax=96.00;leading=2")

state.resetHorizontalMetrics()
#expect(state.serializedValue == "horizontalCurrent=0.00;horizontalMax=0.00;leading=-1")
```

运行该单测，预期先因类型不存在而编译 RED。该类型只能位于 Example target，不进入 Framework。

- [ ] **Step 4：先写四条真实 UI RED**

新增：

```text
testCompositionalVerticalRegionHandsOffToCollectionView()
testCompositionalOrthogonalRegionOwnsHorizontalDrag()
testCompositionalNonOrthogonalRegionStillPages()
testCompositionalReloadRebindsRootVerticalTarget()
```

统一使用 `launchPage(index: 5, mode: "container")`。新增 `compositional-scroll-probe` 解析 helper，但只按稳定字段字符串读取，不访问业务对象或 Framework internal。

初始共同断言：

```swift
state.page == "compositional"
state.hasScrollTarget
state.collapse < 0.01
abs(state.headerCollapse) < 0.5
```

UI RED 必须通过真实 `XCUIElement.coordinate` drag；不得直接设置任何 `contentOffset`。

- [ ] **Step 5：运行 UI RED**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalVerticalRegionHandsOffToCollectionView \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalOrthogonalRegionOwnsHorizontalDrag \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalNonOrthogonalRegionStillPages \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalReloadRebindsRootVerticalTarget test
```

预期：4 条均因 index 5 被旧逻辑 clamp 到 index 4，或组合布局元素/probe 不存在而 FAIL。记录实际 assertion，不因页面缺失而放宽后续阈值。

---

### Task 2：实现独立 Compositional Layout 页面与 Example 装配

**Files:**
- Create: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Test: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`

**Interfaces:**
- Consumes: `UIViewController.anchorPagerScrollView`、`ExampleScrollCoordinationState` callback、appearance recorder closure、Pageboy original page containment。
- Produces: 一个纵向根 CollectionView、一个原生 orthogonal section、普通纵向 sections、公开 handler 探针和可撤销显示帧采样资源。

- [ ] **Step 1：创建横向进度值类型**

在新文件中建立 internal `ExampleCompositionalScrollState`：

```swift
struct ExampleCompositionalScrollState: Equatable {
    private(set) var currentHorizontalOffset: CGFloat = 0
    private(set) var maximumHorizontalOffset: CGFloat = 0
    private(set) var leadingHorizontalItem = -1

    mutating func record(
        horizontalOffset: CGFloat,
        visibleItemIndexes: [Int]
    ) {
        let offset = max(0, horizontalOffset.isFinite ? horizontalOffset : 0)
        currentHorizontalOffset = offset
        maximumHorizontalOffset = max(maximumHorizontalOffset, offset)
        leadingHorizontalItem = visibleItemIndexes.min() ?? -1
    }

    mutating func resetHorizontalMetrics() {
        currentHorizontalOffset = 0
        maximumHorizontalOffset = 0
        leadingHorizontalItem = -1
    }

    var serializedValue: String {
        [
            "horizontalCurrent=\(formatted(currentHorizontalOffset))",
            "horizontalMax=\(formatted(maximumHorizontalOffset))",
            "leading=\(leadingHorizontalItem)"
        ].joined(separator: ";")
    }

    private func formatted(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
```

非有限 offset 降级为 0；serialization 固定两位小数，保证 UI parser 稳定。

- [ ] **Step 2：创建页面骨架与唯一纵向 target**

新增 internal `ExampleCompositionalPageViewController`，构造参数至少包含：

```swift
init(
    title: String,
    identifier: String,
    generation: Int,
    onAppearance: @escaping (String, String) -> Void,
    onScrollStateChange: @escaping (String, CGFloat, CGFloat, CGFloat) -> Void
)
```

`viewDidLoad()` 中：

```swift
collectionView.delegate = self
collectionView.dataSource = self
collectionView.bounces = true
collectionView.alwaysBounceVertical = true
collectionView.isScrollEnabled = true
anchorPagerScrollView = collectionView
```

不得设置 `anchorPagerUsesDefaultScrollViewLookup = false`；显式根 target 已具有最高优先级。记录根 collection delegate 与 pan delegate baseline，只用于 Example probe。

- [ ] **Step 3：建立 iOS 14 Compositional Layout**

layout configuration 显式使用 `.vertical`。Section 0：

```swift
let item = NSCollectionLayoutItem(
    layoutSize: .init(
        widthDimension: .fractionalWidth(1),
        heightDimension: .fractionalHeight(1)
    )
)
let group = NSCollectionLayoutGroup.horizontal(
    layoutSize: .init(
        widthDimension: .fractionalWidth(0.78),
        heightDimension: .absolute(180)
    ),
    subitems: [item]
)
let section = NSCollectionLayoutSection(group: group)
section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
```

Section 1 使用普通纵向 group，至少 18 个固定高度 cell，确保 390×700 viewport 下纵向 range 大于 0.5pt。不得使用 `orthogonalScrollingProperties`。

`visibleItemsInvalidationHandler`：

```swift
section.visibleItemsInvalidationHandler = { [weak self] items, offset, _ in
    let indexes = items
        .filter { $0.representedElementCategory == .cell }
        .map(\.indexPath.item)
    self?.recordHorizontal(offsetX: offset.x, visibleItemIndexes: indexes)
}
```

layout/section closure 只能 weak 捕获 controller，避免 `controller -> collection -> layout -> handler -> controller` 环。

- [ ] **Step 4：建立稳定内容和 accessibility 命中区域**

注册业务 cell 并提供：

```text
compositional-collection-view
compositional-horizontal-card-1 至 compositional-horizontal-card-N
compositional-vertical-card-1 至 compositional-vertical-card-N
page-generation-<generation>-compositional
compositional-scroll-probe
```

横向/纵向 cell 使用不同背景和文字，真实 UI 能按 cell frame 选择命中区域。probe 使用不遮挡主要内容的小型透明 `UIButton`，tap 只重置横向最大进度，不写真实 scroll offset。

probe 的稳定 serialization 为：

```text
scrollDelegate=1;panDelegate=1;bounces=1;alwaysBounceVertical=1;isScrollEnabled=1;verticalRange=1;horizontalCurrent=<x>;horizontalMax=<max>;leading=<index>
```

- [ ] **Step 5：接入纵向显示帧采样和生命周期**

根 CollectionView `scrollViewDidScroll` 只标记“需要采样”；`CADisplayLink` 在可见帧调用：

```swift
distance = contentOffset.y + contentInset.top
maximumDistance = max(
    0,
    contentSize.height + contentInset.top + contentInset.bottom - bounds.height
)
topOverflow = max(0, -distance)
bottomOverflow = max(0, distance - maximumDistance)
```

`viewWillAppear` 启动 sampler；`viewDidDisappear` 停止；`deinit` 在 MainActor 同步 invalidate。四个 appearance callback 通过 `onAppearance` 记录，不跨文件暴露私有 recorder 类型。

- [ ] **Step 6：把页面追加到父控制器**

修改：

1. `makePages()` 在 horizontal 后追加 compositional page，并传入 `pageGeneration`。
2. `pageIdentifier(at:)` 追加 `compositional`。
3. `updateSelectedPageState(at:)` 把组合页标记为 `hasScrollTarget = true` 并立即报告根纵向状态。
4. `requestVisibleMomentumSample()` 请求组合页显示帧采样。
5. `activeScrollPresentationSamplerCountForTesting` 同时统计普通 scroll page 与组合页。
6. appearance closure weak 捕获父控制器，避免 page array 与 recorder 形成环。

- [ ] **Step 7：运行 Example unit GREEN**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests test
```

预期：全部 Example unit PASS；新页 root collection target identity、纵向 range、probe value 和旧第五页 nil target 同时成立。

- [ ] **Step 8：运行 generic build**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' build
```

预期：成功，Swift 6 actor/lifecycle 无编译警告；文件由 Xcode filesystem-synchronized group 自动纳入 target，不手改 `.pbxproj`。

---

### Task 3：验收纵向 handoff 与非正交区域 Pageboy 分页

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify if RED proves Example-only issue: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift`
- Modify if probe assembly is incomplete: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`

**Interfaces:**
- Consumes: 根 CollectionView committed target、现有 ScrollCoordinator 纵向 pair、Pageboy 页面 pan。
- Produces: orthogonal 之外两个互补命中区的真实 winner 证据。

- [ ] **Step 1：收紧纵向 handoff UI 断言**

在 `compositional-vertical-card-1` 内从下向上执行真实 drag；必要时重复固定次数，但不得直接写 offset。最终要求：

```swift
state.page == "compositional"
state.hasScrollTarget
state.collapse >= 0.99
state.distance > 0.5
state.containerToChild
state.invariantMax <= 0.5
```

同时读取 compositional probe，确认 root delegate/pan delegate/bounce/enable 字段为稳定基线、`verticalRange=1`。

- [ ] **Step 2：运行纵向 handoff 测试**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalVerticalRegionHandsOffToCollectionView test
```

若失败只允许修正 Example content range、probe 采样或手势命中坐标；如果 committed target 不是根 CollectionView，回到 Task 2 修复声明源头，不修改 Framework resolver。

- [ ] **Step 3：收紧非正交 Pageboy UI 断言**

从普通纵向 cell 内向右横拖，使最后一页返回 index 4。重置 selection trace 后要求：

```swift
selectionEventSequence(from: trace) == [4]
horizontal-business-scroll 出现
compositional page 不再可见
```

该用例证明没有给整个组合页面安装全局横向阻断。

- [ ] **Step 4：运行非正交分页测试和相邻 Pageboy 回归**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalNonOrthogonalRegionStillPages \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalSwipeSelectsNextPageContent \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalBusinessRegionDoesNotDriveVerticalContainer test
```

预期：3/3 PASS，新增页不改变普通 Pageboy 或 horizontal-only nil target 行为。

---

### Task 4：用正交区域双向真实 drag 判定 UIKit winner

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify only for Example layout/probe defect: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift`
- Do not modify before design amendment: `Sources/AnchorPager/**`

**Interfaces:**
- Consumes: UIKit orthogonal section、Pageboy paging pan、selection trace、Compositional progress probe。
- Produces: 原生 orthogonal winner 的可交付证据，或进入设计修订的精确失败分类。

- [ ] **Step 1：用向左 drag 证明 orthogonal section 真实移动**

重置 compositional probe、`scroll-coordination-state` presentation metrics 和 selection trace；在 `compositional-horizontal-card-1` 内以少量纵向分量从 `dx: 0.82, dy: 0.45` 拖到 `dx: 0.18, dy: 0.55`。等待：

```swift
compositional.maximumHorizontalOffset > 30
compositional.currentHorizontalOffset > 20
scrollState.page == "compositional"
scrollState.collapse < 0.01
abs(scrollState.headerCollapse) < 0.5
scrollState.distance < 0.5
scrollState.hasZeroPresentationMetrics
selection trace 为空
```

index 5 位于 Pageboy 尾端，因此“页面未切换”不是单独证据；必须同时满足横向 offset 明显变化。

- [ ] **Step 2：用向右 drag 与 Pageboy previous-page 直接竞争**

保留 Step 1 已产生的非零 horizontal offset，再从当前可见横向 card 向右 drag。要求：

```swift
currentHorizontalOffset 比 Step 1 至少减少 20pt
page 仍为 compositional
selection trace 仍为空
纵向 metrics 仍在 0.5pt epsilon 内
```

该方向同时具备 Pageboy 返回 index 4 的可能性，能直接证明 orthogonal region 的 winner，而不是尾页边界假通过。

- [ ] **Step 3：运行正交区域 UI**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalOrthogonalRegionOwnsHorizontalDrag test
```

- [ ] **Step 4A：原生 UIKit GREEN 路径**

如果双向 offset、页面、selection trace 和纵向稳定性全部 PASS：

1. 记录“Compositional Layout orthogonal section 已验证”的窄能力；
2. 保持 Framework、GesturePriorityCoordinator、Paging adapter 零改动；
3. 不把结果扩大为任意业务横向 `UIScrollView` 自动优先；
4. 继续 Task 5。

- [ ] **Step 4B：Pageboy/纵向竞争 RED 路径**

如果失败，先按设计分型记录：

```text
页面切到 4 / selection trace=[4] -> Pageboy 抢占
horizontalMax=0 且页面不变 -> layout/range/命中问题
collapse/distance/presentation > epsilon -> 错误纵向竞争
横向与页面/纵向同时变化 -> 多 owner
```

只允许用公开 probe、selection terminal、layout context 和现有 recognizer observation 取证。若排除 Example layout/test 缺陷后仍是 Framework 冲突：

1. 不修改任何 `Sources/AnchorPager` 文件；
2. 不尝试 direct relation、guard、delegate replacement、reset 或 private discovery；
3. 把失败结果和所需显式接入能力写回设计；
4. 更新影响评估并请求用户确认新契约；
5. 本计划在该门禁暂停，确认后的 Framework TDD 使用修订计划继续。

---

### Task 5：验收 reload/rebind、appearance 与采样资源

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify if needed: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift`
- Modify if needed: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`

**Interfaces:**
- Consumes: page generation、Pageboy reload terminal、committed current rebind、appearance recorder、display-link lifecycle。
- Produces: 新 generation root target、旧资源清理与返回页面后手势能力的回归证据。

- [ ] **Step 1：补组合页面 sampler lifecycle 单元测试**

加载 index 5 page，并先收紧为 `ExampleCompositionalPageViewController`，再直接执行标准 appearance transition：

```swift
let page = try #require(
    viewController.pageForTesting(at: 5) as? ExampleCompositionalPageViewController
)
#expect(page.isScrollPresentationSamplingActiveForTesting == false)
page.beginAppearanceTransition(true, animated: false)
page.endAppearanceTransition()
#expect(page.isScrollPresentationSamplingActiveForTesting)
page.beginAppearanceTransition(false, animated: false)
page.endAppearanceTransition()
#expect(page.isScrollPresentationSamplingActiveForTesting == false)
```

同时保持现有普通 scroll page sampler 测试通过，确保没有创建两套不受 lifecycle 管理的 timer。

- [ ] **Step 2：完成 reload UI**

启动 index 5，确认 `page-generation-1-compositional`；点击 accessibility label 为“重新加载页面”的导航按钮，等待：

```text
page-generation-2-compositional 出现
scroll state.page == compositional
hasScrollTarget == true
collapse/presentation 回到合法稳定状态
compositional probe 的 ownership/verticalRange 基线成立
```

随后在新 generation orthogonal card 做一次短横向 drag，要求新 probe 进度变化；旧 generation 元素不再存在。

- [ ] **Step 3：运行 lifecycle/reload 聚焦回归**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleTests/AnchorPagerExampleTests/scrollPresentationSamplerFollowsVisiblePageLifecycle \
  -only-testing:AnchorPagerExampleTests/AnchorPagerExampleTests/compositionalPresentationSamplerFollowsVisiblePageLifecycle \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalReloadRebindsRootVerticalTarget \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testReloadReplacesOldPageGenerationAndKeepsPageInteractive \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompletedPageSwitchProducesOneAdditionalDidAppear \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCancelledInteractivePagingKeepsAppearanceAndSelectionConsistent test
```

预期：全部 PASS，无旧 handler 更新新 probe、appearance imbalance 或 display link 残留。

- [ ] **Step 4：任务级自审并提交 Example 实现**

自审：

1. `anchorPagerScrollView === root collectionView`；
2. orthogonal handler 不保存内部 scroll identity；
3. layout/display-link/appearance closures 均 weak 或同步释放；
4. Framework production diff 为空；
5. 旧五页 index、horizontal-only nil target 和 Pageboy swipe 不变；
6. UI tests 使用真实 drag，未写 offset。

```bash
git diff --check
git add Examples/AnchorPagerExample
git commit -m "新增组合布局混合滚动示例"
```

只有 Task 2–5 全部聚焦测试为 GREEN 才允许提交并进入 Task 6。若 Task 4B 按门禁暂停，则不得创建本实现提交或把当前状态描述为已交付；先报告证据并等待修订设计确认。

---

### Task 6：同步能力边界、全量门禁与 fresh-pass

**Files:**
- Modify: `README.md`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- Modify: `docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md`
- Modify: `docs/superpowers/specs/2026-07-16-compositional-layout-mixed-axis-gesture-validation-design.md`
- Modify: `docs/superpowers/plans/2026-07-15-v0-7-interaction-selection-momentum.md`
- Modify: `docs/superpowers/plans/2026-07-16-compositional-layout-mixed-axis-gesture-validation.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Task 1–5 的新鲜 RED/GREEN、真实 winner、reload/lifecycle 和 ownership 证据。
- Produces: 窄能力声明、限制保留、完整验收记录和最终专项状态。

- [ ] **Step 1：按真实结果更新长期文档**

原生 GREEN 时明确：

1. Example 第六页验证根 CollectionView 纵向 target + UIKit orthogonal section；
2. 验证范围只覆盖当前 UIKit/Tabman/Pageboy/系统组合；
3. 任意业务横向 `UIScrollView` 自动优先限制仍保留；
4. Framework 生产代码、Public API 与日志零改动，因此无需新增 Framework logger event。

如果 Task 4B 触发，本步骤只记录专项 blocked/pending design，不把能力标记完成，也不运行伪完成门禁。

- [ ] **Step 2：运行静态边界检查**

```bash
git diff --check
rg -n 'import (Tabman|Pageboy)' Sources/AnchorPager/Public
rg -n 'orthogonal|compositional' Sources/AnchorPager
git diff -- Sources/AnchorPager
rg -n '\.(delegate|isScrollEnabled|bounces|alwaysBounceVertical)\s*=' Sources/AnchorPager/Children Sources/AnchorPager/Gesture Sources/AnchorPager/Core Sources/AnchorPager/Paging
```

预期：Public 无第三方 import；Framework 不含 Compositional 业务知识；原生 GREEN 路径 `Sources/AnchorPager` 无 diff；没有新增业务 child ownership 写入。

- [ ] **Step 3：解析依赖并运行 Framework 全量**

```bash
swift package resolve
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -resultBundlePath /private/tmp/AnchorPagerCompositionalFramework-20260716.xcresult test
```

- [ ] **Step 4：运行 Example 全量和 generic build**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/AnchorPagerCompositionalExample-20260716.xcresult test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -resultBundlePath /private/tmp/AnchorPagerCompositionalBuild-20260716.xcresult build
```

若结果包已存在，先选择新的唯一时间戳路径，不删除用户结果包。命令需要访问 CoreSimulator、DerivedData 或 SwiftPM cache 时按仓库权限规则申请执行，不把 sandbox 拒绝当成测试结果。

- [ ] **Step 5：检查 xcresult 与运行时诊断**

使用 `xcrun xcresulttool get test-results summary --path <xcresult>` 与 `xcrun xcresulttool get build-results --path <xcresult>` 记录：

```text
testsCount
passedTests
failedTests
skippedTests
errorCount
warningCount
analyzerWarningCount
```

导出/检索诊断，要求 UIKit `LayoutConstraints`、gesture dependency cycle、appearance imbalance、KVO/observer、display-link/resource lifecycle 问题关键词零命中。记录实际 Framework/Example test count，不预填预计数量。

- [ ] **Step 6：执行完整代码自审和 fresh-pass**

从已确认设计重新检查：

1. Public API 与第三方类型泄漏；
2. Pageboy 唯一 containment、selection terminal 与 appearance；
3. root target、managed inset、snapshot 和 committed binding；
4. orthogonal handler 与 Pageboy winner 的能力边界；
5. child delegate/pan/bounce ownership；
6. display link、layout handler、closure 和 reload generation 资源释放；
7. 日志“无需新增”结论是否与生产 diff 一致；
8. 单元/UI/全量结果、文档状态和工作区解释。

fresh-pass 发现 Important 时必须先补 RED/GREEN 并重跑受影响门禁；不得仅修改验收文字。

- [ ] **Step 7：提交长期文档和验收记录**

```bash
git diff --check
git add AGENTS.md README.md docs
git commit -m "验收组合布局混合轴手势"
```

最终在 `AGENTS.md`、task-list、规格和本计划记录生产 HEAD、测试总数、xcresult、0 fail/skip/warning 结论及 fresh-pass 结果；只有真实完成项才勾选。

## 计划自审

1. **设计覆盖：** Task 1 建立结构/纯值/UI RED；Task 2 只实现 Example 单根纵向 target 和 UIKit orthogonal；Task 3–4 分离纵向、页面与正交 winner；Task 5 覆盖 reload/lifecycle；Task 6 完成长期文档、全量门禁与复审。
2. **TDD 顺序：** 页面、probe、四条真实 UI 均先有 RED；最小 Example 实现后逐类转 GREEN。Framework 在真实根因和新设计确认前保持零改动。
3. **冲突止损：** 正交失败路径有明确暂停点，不复活 v0.7 已否定方案，也不在计划中预授权 Public API 扩大。
4. **所有权：** root CollectionView 是唯一 vertical target；orthogonal handler 只读公开 offset，未安排内部 scroll discovery、delegate 接管、gesture reset 或第二 writer。
5. **Containment/lifecycle：** Pageboy 唯一 containment、appearance callback、reload generation、display-link/layout closure 清理均有单元/UI/自审证据。
6. **日志：** 原生 Example 方案明确无需新增 Framework 日志；只有未来经重新确认的 Framework 状态变化才要求日志和 sink 测试。
7. **验收：** 聚焦单元、四类 UI、相邻 paging/boundary/lifecycle、Framework/Example 全量、generic build、xcresult、运行时诊断和静态扫描均列出命令。
8. **完整性：** 没有未实现标记、延期项或未选择方案；唯一条件分支由真实 UIKit 证据决定，并有明确继续/暂停动作。
