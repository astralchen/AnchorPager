# 自有横向分页与业务边缘自动接力 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 AnchorPager 自有分页 Container、PagingScrollView、分段栏和手势路由取代 Tabman/Pageboy，并让普通横向业务 `UIScrollView` 与 Compositional Layout 原生 orthogonal section 在边缘后的下一次向外拖动自动切换页面。

**Architecture:** `AnchorPagerPagingHostViewController` 保持 reload/selection transaction 唯一 owner，`AnchorPagerPagingContainerViewController` 成为唯一页面 UIKit parent，`AnchorPagerPagingScrollView` 只负责横向分页几何与原生滚动物理。自有 route recognizer 与 paging pan 共享一次同步路由决策，通过本次触摸的动态失败优先级在业务 pan 与页面 pan 之间二选一；第一任务先用真实 Framework 链路完成普通横向 scroll 和原生 orthogonal 的停止门禁，任一路径失败即完整清理实验并停止迁移。

**Tech Stack:** Swift 6.2 tools version、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、XCTest/XCUITest、`UIScrollView`、`UIGestureRecognizer`、`UICollectionViewCompositionalLayout`。

## Global Constraints

- Package、library product 与 module name 均保持 `AnchorPager`；最低 OS 保持 iOS 14。
- 所有 UIKit、data source、delegate、container、coordinator 状态更新保持 `@MainActor`；不得用 `@unchecked Sendable`、`nonisolated(unsafe)`、`@preconcurrency` 或 `Task.detached` 压制隔离问题。
- Public API 不得泄漏第三方类型；完成迁移后删除 `pagerViewController(_:allowsInteractiveHorizontalPagingAt:)`，且不增加替代 Public API。
- 必须保留 `UICollectionViewCompositionalLayout` 原生 `.orthogonalScrollingBehavior`，不得改写为业务自建横向 CollectionView。
- 同一次触摸中途到边缘不接力；松手后的下一次向外拖才允许页面接力。
- 不设置、替换、代理或恢复业务 `UIScrollView.delegate` 和业务内建 pan delegate；不写业务 offset、`bounces`、`alwaysBounceVertical`、`alwaysBounceHorizontal` 或 `isScrollEnabled`。
- 不识别 UIKit 私有类名、私有 selector、固定 subview 索引或 Pageboy 私有层级。
- `AnchorPagerPagingScrollView` 不得持有 `UIViewController`、Store、provider 或 generation；业务页面 containment 只由 `AnchorPagerPagingContainerViewController` 执行。
- `AnchorPagerPagingHostViewController` 是 active/latest reload 和 selection request 的唯一 owner；Container 不得自行提交 Public selection。
- plain page 底部 presentation 只能移动 `pagePresentationView`，不得移动 Header、SegmentBar、Container canonical frame 或业务 page 根 view transform。
- 消失页 terminal 当场结束 appearance 并解除 containment；controller 最多由 `recentlyRetired` 单槽强持有，不使用计时器或延迟释放。
- 首个实现任务的真实 UIKit 门禁未全部通过前，不删除当前 Tabman/Pageboy、逐页 Bool 或旧 Adapter；门禁失败后必须用 `apply_patch` 清理全部未采用的新链路并停止。
- 每个任务按 RED → GREEN → 聚焦回归 → 自审 → 中文提交执行；没有测试证据、自审记录和 `git diff --check` 的任务不得标记完成。

---

## 文件结构与职责映射

### 新建生产文件

- `Sources/AnchorPager/Gesture/AnchorPagerHorizontalGestureRouter.swift`：纯值边界模型、物理方向到逻辑页方向映射、四态路由决策；只为 `CGPoint` 与布局方向类型导入 UIKit，不保存 UIKit 对象。
- `Sources/AnchorPager/Gesture/AnchorPagerPagingRoutePanGestureRecognizer.swift`：记录本次触摸命中路径的业务 pan、缓存唯一 route session，并通过公开 gesture delegate 动态建立本次失败优先级。
- `Sources/AnchorPager/Paging/AnchorPagerPagingScrollView.swift`：分页 `UIScrollView`、source/target 两页几何、原生 pan/settling terminal；只接触 `UIView`。
- `Sources/AnchorPager/Paging/AnchorPagerPagingTransitionCoordinator.swift`：`idle/prepared/active/settling/terminal` 状态和 stale terminal 拒绝。
- `Sources/AnchorPager/Paging/AnchorPagerPagingAppearanceCoordinator.swift`：成对管理 source/target appearance transition，不拥有 selection/reload。
- `Sources/AnchorPager/Paging/AnchorPagerPagingContainerViewController.swift`：自定义 container、页面唯一 UIKit parent、稳定 page presentation surface、交互/程序化执行和 terminal 回调。
- `Sources/AnchorPager/Paging/AnchorPagerSegmentBarView.swift`：内部横向 `UICollectionView`、title、indicator、可访问性和高度测量。
- `Sources/AnchorPager/Children/AnchorPagerPageProviding.swift`：从旧 Adapter 文件迁出的内部 page provider 契约，供 Host/Container 使用。

### 新建测试文件

- `Tests/AnchorPagerTests/AnchorPagerHorizontalGestureRouterTests.swift`：边界、inset、bounce、LTR/RTL、多层候选、非法几何和无相邻页模型测试。
- `Tests/AnchorPagerTests/AnchorPagerPagingRoutePanGestureRecognizerTests.swift`：session 幂等、动态失败优先级、simultaneous、reset 和弱引用测试。
- `Tests/AnchorPagerTests/AnchorPagerPagingScrollViewTests.swift`：view-only 分层、页面几何、interactive progress、commit/cancel 和 boundary bounce 测试。
- `Tests/AnchorPagerTests/AnchorPagerPagingTransitionCoordinatorTests.swift`：状态转换、方向锁定、terminal 幂等和 stale callback 测试。
- `Tests/AnchorPagerTests/AnchorPagerPagingAppearanceCoordinatorTests.swift`：appearance 成对和平衡测试。
- `Tests/AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests.swift`：containment、interactive/programmatic、reload、size、teardown 与 presentation 测试。
- `Tests/AnchorPagerTests/AnchorPagerSegmentBarViewTests.swift`：title、选择、indicator、高度与 accessibility 测试。
- `Tests/AnchorPagerTests/AnchorPagerPagingHostReloadTests.swift`：稳定 Container 下 empty/nonempty、active/latest reload 和 generation terminal。
- `Tests/AnchorPagerTests/AnchorPagerPagingHostSelectionTests.swift`：API/bar/interactive 三入口、active/latest selection、重入和 stale terminal。
- `Tests/AnchorPagerTests/AnchorPagerPagingHostResourceTests.swift`：Host/Container/page/recognizer/animator 弱释放和清理。

### 修改与最终删除文件

- `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`：先增加仅门禁使用的内部 executor 模式，门禁通过后收口为稳定自有 Container 唯一执行器。
- `Sources/AnchorPager/Paging/AnchorPagerPagingSelectionRequest.swift`：把 Pageboy completion/readiness 语义收敛为 Container matching terminal。
- `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：迁移 snapshot、Host 回调、Store terminal、gesture priority 与 plain presentation；最终删除逐页 Bool 收集。
- `Sources/AnchorPager/Public/AnchorPagerProtocols.swift`：最终删除 `allowsInteractiveHorizontalPagingAt` 及默认实现。
- `Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift`：增加 `recentlyRetired` 单槽并把强 retention 与 managed inset ownership 解耦。
- `Sources/AnchorPager/Gesture/AnchorPagerGesturePriorityCoordinator.swift`：同时让 paging pan 和 route pan 等待 interactive-pop；不保存业务 pan relation。
- `Sources/AnchorPager/Gesture/AnchorPagerInteractionCoordinator.swift`：增加无副作用的交互准入查询，区分 prepared 与 active。
- `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`：门禁期只通过 launch argument 进入自有执行器，迁移完成后删除静态 Bool 回调。
- `Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift`：保留原生 `.orthogonalScrollingBehavior`，仅补充稳定 UI probe。
- `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：增加隔离硬门禁与最终完整交互矩阵。
- `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`、`Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`、`Tests/AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests.swift`、`Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift`、`Tests/AnchorPagerTests/AnchorPagerPagingSelectionRequestTests.swift`、`Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`：迁移现有契约并保留相邻版本回归。
- `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`、`Sources/AnchorPager/Paging/AnchorPagerTabBarAdapter.swift`、`Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift` 及对应测试：仅在新链路硬门禁与 Host 聚焦回归都通过后删除。
- `Package.swift`、`Package.resolved`：最终删除 Tabman/Pageboy 依赖；Example project 继续只引用本地 AnchorPager product，不改动该引用。
- `README.md`、`docs/architecture.md`、`docs/task-list.md`、`AGENTS.md`、本设计与被取代的 2026-07-16 spec/plan：同步最终架构、门禁证据和历史指针。

## 固定内部接口

下列签名是任务间契约；执行中若真实 UIKit 证明签名无法满足设计，必须停止、更新设计与本计划并重新确认，不能在单个任务里另造平行类型。

```swift
enum AnchorPagerHorizontalPhysicalDirection: Equatable {
    case towardMinimum
    case towardMaximum
}

enum AnchorPagerHorizontalPageDirection: Equatable {
    case previous
    case next
}

struct AnchorPagerHorizontalScrollGeometry: Equatable {
    let contentOffsetX: CGFloat
    let contentSizeWidth: CGFloat
    let boundsWidth: CGFloat
    let adjustedInsetLeft: CGFloat
    let adjustedInsetRight: CGFloat
    let alwaysBounceHorizontal: Bool
}

enum AnchorPagerHorizontalRouteDecision: Equatable {
    case business
    case page(targetIndex: Int, direction: AnchorPagerHorizontalPageDirection)
    case pageBoundaryBounce(direction: AnchorPagerHorizontalPageDirection)
    case none
}

enum AnchorPagerHorizontalGestureRouter {
    static func resolve(
        geometries: [AnchorPagerHorizontalScrollGeometry],
        velocity: CGPoint,
        currentIndex: Int,
        pageCount: Int,
        layoutDirection: UIUserInterfaceLayoutDirection,
        epsilon: CGFloat = 0.5
    ) -> AnchorPagerHorizontalRouteDecision
}
```

Router 可使用 `CGPoint` 与 `UIUserInterfaceLayoutDirection`，因此文件导入 UIKit，但必须保持纯计算且不保存 UIKit 对象。物理方向规则固定为：`velocity.x > 0` 指向 minimum，`velocity.x < 0` 指向 maximum；LTR 下 minimum → previous、maximum → next，RTL 反向。

```swift
struct AnchorPagerPagingTransitionCoordinator {
    mutating func prepare(
        sourceIndex: Int,
        targetIndex: Int,
        direction: AnchorPagerHorizontalPageDirection,
        requestIdentifier: Int
    ) -> Bool
    mutating func activate(requestIdentifier: Int) -> Bool
    mutating func beginSettling(requestIdentifier: Int) -> Bool
    mutating func finish(
        commit: Bool,
        requestIdentifier: Int
    ) -> AnchorPagerPagingScrollTerminal?
    mutating func reset()
}
```

```swift
@MainActor
protocol AnchorPagerPagingRouteSessionDelegate: AnyObject {
    func routeDecision(
        for recognizer: AnchorPagerPagingRoutePanGestureRecognizer,
        touchedView: UIView?,
        velocity: CGPoint,
        businessScrollViews: [UIScrollView]
    ) -> AnchorPagerHorizontalRouteDecision

    func routeRecognizer(
        _ recognizer: AnchorPagerPagingRoutePanGestureRecognizer,
        preparePageAt targetIndex: Int,
        direction: AnchorPagerHorizontalPageDirection
    ) -> Bool

    func routeRecognizerDidAbandonPreparedPage(
        _ recognizer: AnchorPagerPagingRoutePanGestureRecognizer
    )
}

@MainActor
final class AnchorPagerPagingRoutePanGestureRecognizer: UIPanGestureRecognizer {
    weak var routeSessionDelegate: AnchorPagerPagingRouteSessionDelegate?
    private(set) var preparedDecision: AnchorPagerHorizontalRouteDecision?
    func prepareIfNeeded() -> AnchorPagerHorizontalRouteDecision
    func isBusinessPanInCurrentSession(_ gestureRecognizer: UIGestureRecognizer) -> Bool
}
```

```swift
@MainActor
protocol AnchorPagerPagingScrollViewDelegate: AnyObject {
    func pagingScrollViewDidBeginInteractiveTransition(_ scrollView: AnchorPagerPagingScrollView)
    func pagingScrollView(_ scrollView: AnchorPagerPagingScrollView, didUpdateProgress progress: CGFloat)
    func pagingScrollView(_ scrollView: AnchorPagerPagingScrollView, didReach terminal: AnchorPagerPagingScrollTerminal)
}

enum AnchorPagerPagingScrollTerminal: Equatable {
    case committed
    case cancelled
    case boundaryReturned
}

@MainActor
final class AnchorPagerPagingScrollView: UIScrollView {
    weak var pagingDelegate: AnchorPagerPagingScrollViewDelegate?
    let routePanGestureRecognizer: AnchorPagerPagingRoutePanGestureRecognizer
    func setIdlePageView(_ pageView: UIView?)
    func prepareTransition(sourceView: UIView, targetView: UIView, direction: AnchorPagerHorizontalPageDirection)
    func activatePreparedTransition()
    func settlePreparedTransition(commit: Bool, animated: Bool)
    func resetToIdle(pageView: UIView?)
}
```

```swift
@MainActor
protocol AnchorPagerPagingContainerViewControllerDelegate: AnyObject {
    func pagingContainer(
        _ container: AnchorPagerPagingContainerViewController,
        prepareInteractiveSelectionAt index: Int
    ) -> AnchorPagerPagingSelectionRequest?
    func pagingContainer(
        _ container: AnchorPagerPagingContainerViewController,
        didBegin request: AnchorPagerPagingSelectionRequest
    )
    func pagingContainer(
        _ container: AnchorPagerPagingContainerViewController,
        didAbandonPrepared request: AnchorPagerPagingSelectionRequest
    )
    func pagingContainer(
        _ container: AnchorPagerPagingContainerViewController,
        didReach terminal: AnchorPagerPagingContainerTerminal
    )
    func pagingContainer(_ container: AnchorPagerPagingContainerViewController, didRequestBarSelectionAt index: Int)
    func pagingContainer(_ container: AnchorPagerPagingContainerViewController, didResolveBarInsets insets: UIEdgeInsets)
}

enum AnchorPagerPagingContainerTerminal: Equatable {
    case selected(requestIdentifier: Int, index: Int)
    case cancelled(requestIdentifier: Int, index: Int, previousIndex: Int)
}

@MainActor
final class AnchorPagerPagingContainerViewController: UIViewController {
    weak var pageProvider: AnchorPagerPageProviding?
    weak var delegate: AnchorPagerPagingContainerViewControllerDelegate?
    private(set) var currentIndex: Int?
    var pagingPanGestureRecognizer: UIPanGestureRecognizer { get }
    var routePanGestureRecognizer: UIPanGestureRecognizer { get }
    var isReadyForReload: Bool { get }
    func reload(requestIdentifier: Int, titles: [String], selectedIndex: Int?)
    func executeSelection(_ request: AnchorPagerPagingSelectionRequest, previousIndex: Int) -> Bool
    func setBarHeight(_ height: CGFloat?)
    @discardableResult func setPagePresentationTranslationY(_ translationY: CGFloat) -> Bool
    func prepareForRemoval()
}
```

`AnchorPagerPageProviding` 的签名沿用现有 Adapter 内部契约，只移动文件，不改变 page identity 或 generation 语义：

```swift
@MainActor
protocol AnchorPagerPageProviding: AnyObject {
    func pageViewController(at index: Int) -> UIViewController?
}
```

---

### Task 1: 最小自有分页链路与真实 UIKit 停止门禁

这是第一项实现任务。它只回答一个问题：在不触碰业务 delegate/pan/offset/bounce/enable 的前提下，自有 route recognizer + 自有 PagingScrollView 是否能让普通横向 scroll 与原生 orthogonal 同时满足“内部业务滚动、同手势不接力、下一手势边缘分页”，并保留普通区域与无相邻页的 boundary ownership。4 条 UI 未连续三轮全部通过前不得开始 Task 2。

**Files:**
- Create: `Sources/AnchorPager/Gesture/AnchorPagerHorizontalGestureRouter.swift`
- Create: `Sources/AnchorPager/Gesture/AnchorPagerPagingRoutePanGestureRecognizer.swift`
- Create: `Sources/AnchorPager/Paging/AnchorPagerPagingScrollView.swift`
- Create: `Sources/AnchorPager/Paging/AnchorPagerPagingTransitionCoordinator.swift`
- Create: `Sources/AnchorPager/Paging/AnchorPagerPagingContainerViewController.swift`
- Create: `Sources/AnchorPager/Children/AnchorPagerPageProviding.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerHorizontalGestureRouterTests.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPagingRoutePanGestureRecognizerTests.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPagingScrollViewTests.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Sources/AnchorPager/Gesture/AnchorPagerGesturePriorityCoordinator.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**
- Consumes: 本计划“固定内部接口”、现有 `AnchorPagerPageProviding`、Host reload payload、Example 第五页普通横向 scroll 与第六页原生 orthogonal。
- Produces: `AnchorPagerHorizontalGestureRouter.resolve(...)`、route session、view-only PagingScrollView、最小 Container、仅 `-AnchorPagerSelfHostedPagingGate` launch argument 可达的内部执行模式、4 条 UI 连续三轮真实门禁证据。

- [ ] **Step 1: 写纯模型与 recognizer 的 RED 测试**

在三个新测试文件写出以下具名用例；断言必须直接覆盖固定接口，不能用 mock Pageboy：

```swift
func testInteriorBusinessScrollWinsWithoutPreparingPage() {
    let decision = AnchorPagerHorizontalGestureRouter.resolve(
        geometries: [.init(
            contentOffsetX: 40,
            contentSizeWidth: 400,
            boundsWidth: 200,
            adjustedInsetLeft: 0,
            adjustedInsetRight: 0,
            alwaysBounceHorizontal: false
        )],
        velocity: CGPoint(x: -600, y: 20),
        currentIndex: 4,
        pageCount: 6,
        layoutDirection: .leftToRight
    )
    XCTAssertEqual(decision, .business)
}

func testMaximumEdgeNextDragPreparesNextPage() {
    let decision = AnchorPagerHorizontalGestureRouter.resolve(
        geometries: [.init(
            contentOffsetX: 200,
            contentSizeWidth: 400,
            boundsWidth: 200,
            adjustedInsetLeft: 0,
            adjustedInsetRight: 0,
            alwaysBounceHorizontal: false
        )],
        velocity: CGPoint(x: -600, y: 20),
        currentIndex: 4,
        pageCount: 6,
        layoutDirection: .leftToRight
    )
    XCTAssertEqual(decision, .page(targetIndex: 5, direction: .next))
}

func testPrepareIfNeededSharesOneDecisionBetweenRouteAndPagingPan() {
    let harness = RouteSessionHarness(decision: .page(targetIndex: 5, direction: .next))
    let recognizer = AnchorPagerPagingRoutePanGestureRecognizer()
    recognizer.routeSessionDelegate = harness
    XCTAssertEqual(recognizer.prepareIfNeeded(), .page(targetIndex: 5, direction: .next))
    XCTAssertEqual(recognizer.prepareIfNeeded(), .page(targetIndex: 5, direction: .next))
    XCTAssertEqual(harness.decisionCallCount, 1)
    XCTAssertEqual(harness.prepareCallCount, 1)
}
```

另写 `testBusinessPanDynamicallyWaitsForRouteOnlyDuringCurrentTouch`、`testRouteAndOwnedPagingPanRecognizeSimultaneouslyForPageDecision`、`testResetClearsDecisionAndWeakBusinessCandidates`。测试 harness 只记录公开 delegate 回调和弱引用，不调用 recognizer 私有状态。

- [ ] **Step 2: 运行模型/recognizer RED**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task1-red-model \
  -only-testing:AnchorPagerTests/AnchorPagerHorizontalGestureRouterTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingRoutePanGestureRecognizerTests \
  test
```

Expected: 编译失败，明确报告新 Router/recognizer 类型不存在；若失败来自测试语法或 simulator 环境，先修复测试/环境，直到获得类型缺失或行为断言失败的 RED。

- [ ] **Step 3: 实现最小 Router、route recognizer 与 PagingScrollView**

实现固定签名，并把业务候选限制为触摸 view 到 PagingScrollView 之间命中路径上的 `UIScrollView.panGestureRecognizer`。Router 规则必须逐条写成可读分支：

```swift
guard velocity.x.isFinite, velocity.y.isFinite,
      abs(velocity.x) > abs(velocity.y), abs(velocity.x) > epsilon else {
    return .none
}

let physicalDirection: AnchorPagerHorizontalPhysicalDirection =
    velocity.x > 0 ? .towardMinimum : .towardMaximum
let pageDirection = logicalPageDirection(
    for: physicalDirection,
    layoutDirection: layoutDirection
)
let targetIndex = currentIndex + (pageDirection == .next ? 1 : -1)
let hasNeighbor = (0..<pageCount).contains(targetIndex)
let candidates = geometries.filter { $0.isHorizontalCandidate(epsilon: epsilon) }

if candidates.contains(where: { $0.canConsume(physicalDirection, epsilon: epsilon) }) {
    return .business
}
if !candidates.isEmpty {
    return hasNeighbor ? .page(targetIndex: targetIndex, direction: pageDirection) : .business
}
return hasNeighbor
    ? .page(targetIndex: targetIndex, direction: pageDirection)
    : .pageBoundaryBounce(direction: pageDirection)
```

route delegate 的动态优先级只对 `isBusinessPanInCurrentSession` 返回 true 的 recognizer 生效；`shouldRecognizeSimultaneouslyWith` 只允许 route 与所属 PagingScrollView 的 pan 同时识别。不得给业务 pan 调用永久 `require(toFail:)`，不得设置其 delegate。

route recognizer 导入 `UIKit.UIGestureRecognizerSubclass`，把自身设为自身的 `UIGestureRecognizerDelegate`，并用真实 UIKit 单测确定 `shouldRequireFailureOf` / `shouldBeRequiredToFailBy` 的回调方向，不依据方法名猜测。`gestureRecognizerShouldBegin` 与 PagingScrollView 的 `gestureRecognizerShouldBegin` 必须读取同一个 session：`.business/.none` 两者都返回 false；`.page` 只有同步 prepare 成功时两者才返回 true；`.pageBoundaryBounce` 两者返回 true但不创建 selection。若 route 已 prepared 而 paging pan 最终不能 begin，调用 `routeRecognizerDidAbandonPreparedPage(_:)`，两者同步失败并撤销 prepared target。

PagingScrollView 初始化固定配置：

```swift
isPagingEnabled = true
decelerationRate = .fast
alwaysBounceHorizontal = true
showsHorizontalScrollIndicator = false
showsVerticalScrollIndicator = false
scrollsToTop = false
contentInsetAdjustmentBehavior = .never
```

并在源码测试中断言 `AnchorPagerPagingScrollView.swift` 不包含 `UIViewController`、`addChild`、`removeFromParent`、`AnchorPagerPageStateStore`。Task 1 同步增加日志 sink 断言，固定事件只使用 `paging.route.business`、`paging.route.page`、`paging.route.pageBoundaryBounce`、`paging.route.none`、`paging.selection.prepared`、`paging.selection.began`，不得逐帧记录 progress、offset、velocity、命中类名或 view hierarchy。

- [ ] **Step 4: 写最小 Container/PagingScrollView RED**

新增以下用例：

```swift
func testPagingScrollViewContainsViewsButNoControllerKnowledge() {
    let scrollView = AnchorPagerPagingScrollView()
    let source = UIView()
    let target = UIView()
    scrollView.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
    scrollView.prepareTransition(sourceView: source, targetView: target, direction: .next)
    scrollView.layoutIfNeeded()
    XCTAssertEqual(source.frame, CGRect(x: 0, y: 0, width: 320, height: 500))
    XCTAssertEqual(target.frame, CGRect(x: 320, y: 0, width: 320, height: 500))
}

func testContainerIsSoleParentForSourceAndTargetDuringInteractiveTransition() throws {
    let harness = PagingContainerHarness(pageCount: 2)
    let container = AnchorPagerPagingContainerViewController()
    container.pageProvider = harness
    container.loadViewIfNeeded()
    container.reload(requestIdentifier: 1, titles: ["A", "B"], selectedIndex: 0)
    let request = AnchorPagerPagingSelectionRequest(identifier: 2, targetIndex: 1, animated: true, source: .interactive)
    XCTAssertTrue(container.executeSelection(request, previousIndex: 0))
    XCTAssertTrue(harness.controllers[0].parent === container)
    XCTAssertTrue(harness.controllers[1].parent === container)
    XCTAssertLessThanOrEqual(container.children.count, 2)
}
```

同时增加 `testPreparedRouteCancelsSynchronouslyWhenPagingPanCannotBegin`，断言 prepared target 解除 containment、route/paging 都失败、业务 pan 可继续开始，且不发送 willSelect/didSelect/didCancel。

- [ ] **Step 5: 运行最小 Container RED 并实现最少可验收链路**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task1-red-container \
  -only-testing:AnchorPagerTests/AnchorPagerPagingScrollViewTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests \
  test
```

Expected: 新方法不存在或 containment 断言失败。随后实现标准 `addChild → addSubview → didMove`，terminal 使用 `willMove(nil) → removeFromSuperview → removeFromParent`；Task 1 不实现 recentlyRetired，只保证 source/target 上限 2、commit/cancel 平衡和空态移除。

- [ ] **Step 6: 把新链路临时装配到真实 Framework 路径**

只新增 internal enum，不加 Public/SPI：

```swift
enum AnchorPagerPagingExecutionMode {
    case legacy
    case selfHostedGate

    static var processDefault: Self {
        ProcessInfo.processInfo.arguments.contains("-AnchorPagerSelfHostedPagingGate")
            ? .selfHostedGate
            : .legacy
    }
}
```

Host 默认继续走旧 Adapter；`.selfHostedGate` 始终安装最小 Container 并使用同一 provider、selection terminal 与现有 Store 回调。`AnchorPagerViewController.refreshGesturePriorities()` 从 Host 读取统一的 `pagingPanGestureRecognizer` 和 `routePanGestureRecognizer`；`AnchorPagerGesturePriorityCoordinator` 对两者分别建立 `pan.require(toFail: interactivePop)`，不得建立 paging pan → route pan 依赖。

Example 仅在启动参数存在时让第五/第六页跳过旧逐页 Bool 的禁用效果，并读取 `-AnchorPagerSelfHostedPagingGateInitialIndex 4|5` 直接选择硬门禁起始页；最小 Container 尚未实现正式 SegmentBar，门禁不能借用 Tabman bar。这两段兼容分支在 Task 6 删除，不能成为长期运行时开关。

- [ ] **Step 7: 写两条隔离真实 UI 硬门禁**

在 UI tests 增加统一启动 helper：

```swift
private func launchSelfHostedPagingGate(initialIndex: Int) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
        "-AnchorPagerSelfHostedPagingGate",
        "-AnchorPagerSelfHostedPagingGateInitialIndex",
        String(initialIndex)
    ]
    app.launch()
    return app
}
```

新增四条精确用例：

```swift
func testSelfHostedGateOrdinaryHorizontalScrollStopsThenNextGesturePages() throws
func testSelfHostedGateNativeOrthogonalStopsThenNextGesturePages() throws
func testSelfHostedGateCompositionalOrdinaryRegionPagesAndBoundaryBounces() throws
func testSelfHostedGateTerminalBusinessEdgeKeepsBusinessBounce() throws
```

每条用例都必须记录并断言四个探针：

1. interior drag 后业务内容 accessibility frame 的 `minX` 发生至少 20 pt 变化，page index 不变；
2. 同一 drag 到边缘后 page index 仍不变；
3. 手指松开，下一次同方向向外 drag 后 page index 变为相邻页；
4. 返回页面后业务 delegate identity 与测试前一致，且控制台没有 gesture cycle、appearance imbalance 或 constraint 关键字。

第三条必须证明 orthogonal 外普通区域直接分页，并在首/尾无相邻页面时由 PagingScrollView 呈现原生 boundary bounce 且 Public selection 计数不变。第四条必须在最后一页命中仍登记为业务候选的边缘，证明无相邻页时手势仍归业务 bounce、页面 index 和 Public selection 计数不变。

原生 orthogonal 测试只能操作 `ExampleCompositionalPageViewController` 现有 `.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary` section，不能改变该业务布局行为、寻找或替换其内部私有 scroll 类。

- [ ] **Step 8: 运行真实 UIKit 停止门禁并执行硬分支**

Run:

```bash
for run in 1 2 3; do
  xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
    -scheme AnchorPagerExample \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
    -derivedDataPath ".build/self-hosted-task1-ui-gate-${run}" \
    -parallel-testing-enabled NO \
    -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSelfHostedGateOrdinaryHorizontalScrollStopsThenNextGesturePages \
    -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSelfHostedGateNativeOrthogonalStopsThenNextGesturePages \
    -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSelfHostedGateCompositionalOrdinaryRegionPagesAndBoundaryBounces \
    -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSelfHostedGateTerminalBusinessEdgeKeepsBusinessBounce \
    -resultBundlePath "/private/tmp/AnchorPagerSelfHostedTask1UIKitGate-${run}.xcresult" \
    test || exit 1
done
```

Expected: 4 tests、0 fail、0 skip，四个测试重复运行 3 轮仍全部通过。

若任一轮失败：保留当轮 `/private/tmp/AnchorPagerSelfHostedTask1UIKitGate-1.xcresult`、`-2.xcresult` 或 `-3.xcresult`；用 `apply_patch` 删除本任务列出的 6 个新生产文件、4 个新测试文件以及 Host/ViewController/GesturePriority/Example/UI test/logger 的临时分支，恢复 `AnchorPagerPageProviding` 到旧 Adapter 文件并保持 Public Bool 生产事实。随后运行：

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task1-cleanup-framework \
  test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/self-hosted-task1-cleanup-build \
  build
git diff --check
```

Expected: Framework 恢复当前 439/439，generic build 成功，diff check 无输出。更新设计、计划、task-list 记录失败原因；提交 `清理自有分页真实手势实验`；停止且不执行 Task 2。

若 3 轮全部通过：继续 Step 9。

- [ ] **Step 9: 运行 Task 1 聚焦回归、自审并提交**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task1-green \
  -only-testing:AnchorPagerTests/AnchorPagerHorizontalGestureRouterTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingRoutePanGestureRecognizerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingScrollViewTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests \
  test
! rg -n "UIViewController|addChild|removeFromParent|AnchorPagerPageStateStore" \
  Sources/AnchorPager/Paging/AnchorPagerPagingScrollView.swift
rg -n "delegate\s*=|contentOffset\s*=|bounces\s*=|alwaysBounce(Horizontal|Vertical)\s*=|isScrollEnabled\s*=" \
  Sources/AnchorPager/Gesture/AnchorPagerPagingRoutePanGestureRecognizer.swift \
  Sources/AnchorPager/Paging/AnchorPagerPagingScrollView.swift \
  Sources/AnchorPager/Paging/AnchorPagerPagingContainerViewController.swift
git diff --check
```

Expected: 所列测试全通过；controller 符号扫描无输出；所有权扫描只命中自有 recognizer/PagingScrollView 的合法内部配置，不命中业务 scroll 写入；`git diff --check` 无输出。自审必须记录：业务 delegate/pan/offset/bounce/enable 零写入、PagingScrollView 零 controller 符号、Container 标准 containment、旧生产默认仍为 legacy、没有永久业务 failure relation。

Commit:

```bash
git add Sources/AnchorPager Tests/AnchorPagerTests Examples/AnchorPagerExample docs
git commit -m "验证自有分页横向手势硬门禁"
```

---

### Task 2: 补齐路由模型、共享 Session 与分页滚动物理

**Files:**
- Modify: `Sources/AnchorPager/Gesture/AnchorPagerHorizontalGestureRouter.swift`
- Modify: `Sources/AnchorPager/Gesture/AnchorPagerPagingRoutePanGestureRecognizer.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingScrollView.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingTransitionCoordinator.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerHorizontalGestureRouterTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingRoutePanGestureRecognizerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingScrollViewTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingTransitionCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**
- Consumes: Task 1 的固定 Router、route session、PagingScrollView 与 `AnchorPagerPagingScrollTerminal`。
- Produces: 完整四态路由矩阵、call-order 无关的单 session、原生 boundary bounce、不重复 terminal 的 transition state machine。

- [ ] **Step 1: 写完整边界与状态机 RED**

至少增加这些具名测试：

```swift
func testAdjustedInsetsDefineMinimumAndMaximumEdges()
func testAnyNestedCandidateThatCanConsumeKeepsBusinessOwnership()
func testShortAlwaysBounceHorizontalCandidateWithoutPageNeighborKeepsBusinessOwnership()
func testShortAlwaysBounceHorizontalCandidateWithPageNeighborRoutesToPage()
func testBusinessCandidateAtEdgeWithoutNeighborKeepsBusinessBoundaryBounce()
func testNoBusinessCandidateWithoutNeighborUsesPageBoundaryBounce()
func testCandidateInBounceRegionMovingTowardStableRangeStaysBusiness()
func testCandidateInBounceRegionMovingFurtherOutRoutesToNeighborPage()
func testRTLMapsPhysicalMaximumTowardPreviousPage()
func testNonFiniteOrVerticalVelocityReturnsNone()
func testRouteFirstAndPagingFirstCallOrdersPrepareExactlyOnce()
func testSameTouchNeverChangesDecisionAfterBusinessReachesEdge()
func testInteractiveDirectionReversalKeepsOriginalPreparedTarget()
func testZeroWidthOrDetachedPagingSurfaceCannotPrepareTransition()
func testTransitionRejectsSecondTerminalAndStaleRequestIdentifier()
func testBoundaryBounceReturnsWithoutSelectionTerminal()
```

状态机断言示例：

```swift
var coordinator = AnchorPagerPagingTransitionCoordinator()
XCTAssertTrue(coordinator.prepare(sourceIndex: 1, targetIndex: 2, direction: .next, requestIdentifier: 9))
XCTAssertTrue(coordinator.activate(requestIdentifier: 9))
XCTAssertEqual(coordinator.finish(commit: true, requestIdentifier: 9), .committed)
XCTAssertNil(coordinator.finish(commit: false, requestIdentifier: 9))
XCTAssertNil(coordinator.finish(commit: true, requestIdentifier: 8))
```

- [ ] **Step 2: 运行 RED**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task2-red \
  -only-testing:AnchorPagerTests/AnchorPagerHorizontalGestureRouterTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingRoutePanGestureRecognizerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingScrollViewTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingTransitionCoordinatorTests \
  test
```

Expected: adjusted inset、RTL、call-order、boundary terminal 或 stale terminal 新断言失败。

- [ ] **Step 3: 实现完整模型与状态机**

`AnchorPagerHorizontalScrollGeometry` 使用下列规范范围：

```swift
let minimumX = -adjustedInsetLeft
let maximumX = max(minimumX, contentSizeWidth - boundsWidth + adjustedInsetRight)
let hasScrollableRange = maximumX - minimumX > epsilon

switch physicalDirection {
case .towardMinimum:
    return contentOffsetX > minimumX + epsilon
case .towardMaximum:
    return contentOffsetX < maximumX - epsilon
}
```

仅当全部输入 finite 且 `boundsWidth > 0` 才参与路由；非法 geometry 从候选中丢弃。零 range 且 `alwaysBounceHorizontal == true` 的 scroll 仍是业务候选，但不能在内部消费距离：存在相邻页时它视为已在对应边缘并路由到 `.page`，不存在相邻页时才由 `.business` 保留业务 boundary bounce。候选已在 bounce 区时，向稳定范围内拖仍归业务，继续向同侧外拖才视为边缘。route 与 paging pan 均调用同一个 `prepareIfNeeded()`，该方法只允许一次 hit-path 采集、一次 decision、一次 Container prepare。

TransitionCoordinator 固定状态：

```swift
enum State: Equatable {
    case idle
    case prepared(Transaction)
    case active(Transaction)
    case settling(Transaction)
}
```

terminal 后立即回 `.idle`；commit/cancel/boundaryReturned 只由 PagingScrollView 的 delegate 出口上报一次。日志只记录 decision 状态变化和非法输入，不逐帧记录 progress。

- [ ] **Step 4: 运行 GREEN、源码所有权扫描、自审并提交**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task2-green \
  -only-testing:AnchorPagerTests/AnchorPagerHorizontalGestureRouterTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingRoutePanGestureRecognizerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingScrollViewTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingTransitionCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests \
  test
rg -n "delegate\s*=|contentOffset\s*=|bounces\s*=|alwaysBounce(Horizontal|Vertical)\s*=|isScrollEnabled\s*=" \
  Sources/AnchorPager/Gesture/AnchorPagerHorizontalGestureRouter.swift \
  Sources/AnchorPager/Gesture/AnchorPagerPagingRoutePanGestureRecognizer.swift \
  Sources/AnchorPager/Paging/AnchorPagerPagingScrollView.swift \
  Sources/AnchorPager/Paging/AnchorPagerPagingContainerViewController.swift
git diff --check
```

Expected: 聚焦测试通过；扫描只命中 PagingScrollView/route recognizer 自身合法配置和内部 delegate，不命中业务 scroll 写入。旧 Adapter 仍存在但不纳入该新链路所有权扫描。自审确认 route session 不依赖 UIKit should-begin 调用顺序，首尾页 ownership 与设计一致。

Commit:

```bash
git add Sources/AnchorPager/Gesture Sources/AnchorPager/Paging Tests/AnchorPagerTests
git commit -m "完善横向边界路由与分页滚动物理"
```

---

### Task 3: 自有分段栏、indicator 与 obstruction

**Files:**
- Create: `Sources/AnchorPager/Paging/AnchorPagerSegmentBarView.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerSegmentBarViewTests.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingContainerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`

**Interfaces:**
- Consumes: Container 的稳定 `pagePresentationView` 和 delegate `didRequestBarSelectionAt` / `didResolveBarInsets`。
- Produces: `AnchorPagerSegmentBarView.reload(titles:selectedIndex:)`、`setSelectedIndex(_:animated:)`、`setTransition(from:to:progress:)`、`resetTransition(to:)`、`resolvedHeight`。

- [ ] **Step 1: 写 bar RED**

新建内部 delegate：

```swift
@MainActor
protocol AnchorPagerSegmentBarViewDelegate: AnyObject {
    func segmentBarView(_ barView: AnchorPagerSegmentBarView, didSelectItemAt index: Int)
    func segmentBarView(_ barView: AnchorPagerSegmentBarView, didResolveHeight height: CGFloat)
}
```

写以下具名测试：

```swift
func testReloadCreatesAccessibleButtonsAndSelectsCommittedIndex()
func testIndicatorInterpolatesBetweenSourceAndTargetFrames()
func testCancelResetsIndicatorToSourceWithoutSelectionCallback()
func testSelectedItemScrollsIntoVisibleBounds()
func testAdaptiveHeightUsesHeadlineMetricsAndExactHeightOverridesIt()
func testDefaultAppearanceUsesSystemMaterialAndBottomSeparator()
func testInvalidExplicitHeightFallsBackToZeroAndLogsOnce()
func testContainerReportsBarObstructionAsTopInsetOnly()
```

核心断言：每个 item 具 `.button`，正式选中项另具 `.selected`；默认字体 `.preferredFont(forTextStyle: .headline)`，竖向 padding 12、item spacing 16、indicator 高 4，背景使用 system material 并带底部分隔线；显式 height 为有限非负值时精确采用。

- [ ] **Step 2: 运行 RED 并实现 bar**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task3-red \
  -only-testing:AnchorPagerTests/AnchorPagerSegmentBarViewTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests \
  test
```

Expected: bar 类型/方法缺失或 indicator/highlight 断言失败。

实现内部水平 `UICollectionViewFlowLayout` 与独立 indicator view；禁止复刻 Tabman 类型名。`resolvedHeight` 变化时只回调一次并记录 `paging.barObstructionChanged`，非法高度继续记录 `paging.barHeightInvalid`；Container 将 `UIEdgeInsets(top: resolvedHeight, left: 0, bottom: 0, right: 0)` 交给 Host，页面 frame 不下移形成第二套事实。

- [ ] **Step 3: 连接交互 progress、程序化 animator 与 bar terminal**

Container 在 progress 回调调用：

```swift
segmentBarView.setTransition(from: previousIndex, to: request.targetIndex, progress: progress)
```

commit 调用 `setSelectedIndex(request.targetIndex, animated: false)`；cancel 调用 `resetTransition(to: previousIndex)`；bar 点击只上报 index，不能直接改 currentIndex 或向 provider 取页。

- [ ] **Step 4: 运行 GREEN、自审并提交**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task3-green \
  -only-testing:AnchorPagerTests/AnchorPagerSegmentBarViewTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests \
  test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task3-example \
  -only-testing:AnchorPagerExampleTests \
  test
git diff --check
```

Expected: bar/Container/Example unit 全通过。自审确认实际 obstruction 单一来源、plain presentation 不移动 bar、无 Tabman 类型复制、Dynamic Type 可重新测高。

Commit:

```bash
git add Sources/AnchorPager/Paging Tests/AnchorPagerTests Examples/AnchorPagerExample
git commit -m "实现自有分段栏与指示器"
```

---

### Task 4: Container containment、appearance 与 recentlyRetired

**Files:**
- Create: `Sources/AnchorPager/Paging/AnchorPagerPagingAppearanceCoordinator.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPagingAppearanceCoordinatorTests.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingContainerViewController.swift`
- Modify: `Sources/AnchorPager/Children/AnchorPagerPageStateStore.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPageStateStoreTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**
- Consumes: Task 1 Container terminal、Task 2 transition state、现有 `AnchorPagerPageStateStore.PageState` 和 managed inset ownership。
- Produces: 精确 appearance forwarding、terminal 当场解除 containment、`recentlyRetired` 单槽复用/替换/清理，retention 与 inset ownership 分离。

- [ ] **Step 1: 写 lifecycle/retired RED**

增加 recording controller，记录 `beginAppearanceTransition`/`endAppearanceTransition`、parent、view window 和 deinit。至少覆盖：

```swift
func testCommitBalancesSourceDisappearAndTargetAppearBeforeRemovingSource()
func testCancelBalancesTargetDisappearAndSourceReappearBeforeRemovingTarget()
func testInitialReloadWhileContainerVisibleBalancesCurrentAppearance()
func testEmptyReloadWhileContainerVisibleBalancesCurrentDisappearance()
func testContainerNeverContainsMoreThanSourceAndTarget()
func testParentAppearanceInterruptionEndsEveryOpenTransitionExactlyOnce()
func testCommittedSourceBecomesRecentlyRetiredWithoutInsetOwnership()
func testReverseSelectionReusesRecentlyRetiredControllerIdentity()
func testDifferentTransitionReplacesSingleRetiredSlotAndReleasesOldController()
func testConfiguredAdjacentPageDoesNotDuplicateRecentlyRetiredLease()
func testReloadMemoryWarningAndTeardownClearRecentlyRetired()
func testDuplicateControllerForTwoIndexesFailsSelectionWithoutDoubleContainment()
```

Store 核心断言示例：

```swift
store.willSelect(from: 0, to: 1, context: context)
store.didSelect(1, context: context)
XCTAssertEqual(store.recentlyRetiredIndexForTesting, 0)
XCTAssertTrue(store.recentlyRetiredPageForTesting === page)
XCTAssertFalse(store.managedInsetOwnerIndexesForTesting.contains(0))
XCTAssertEqual(store.snapshotForTesting(at: 0), expectedSnapshot)
```

- [ ] **Step 2: 运行 RED**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task4-red \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAppearanceCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests \
  test
```

Expected: appearance coordinator、retired API 或 ownership 断言失败。

- [ ] **Step 3: 实现 appearance 与单槽缓存**

Container 覆写：

```swift
override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
```

AppearanceCoordinator 只接受 source/target controller 与 Container 当前 appearance 状态，公开内部方法固定为：

```swift
func begin(source: UIViewController, target: UIViewController, animated: Bool)
func commit(source: UIViewController, target: UIViewController)
func cancel(source: UIViewController, target: UIViewController)
func beginContainerAppearance(
    appearing: Bool,
    animated: Bool,
    controllers: [UIViewController]
)
func endContainerAppearance()
func finishForTeardown()
```

Container 在 `viewWillAppear/viewDidAppear/viewWillDisappear/viewDidDisappear` 调用 container appearance 方法；idle 只传 current，active 传 source/target，prepared target 不传。可见 Container 中初次 nonempty reload 与 empty reload 也必须通过同一 coordinator 成对补齐 current appearance，不能依赖 UIKit 自动 forwarding。

`RetentionReason` 增加 `.recentlyRetired`，`GenerationState` 增加唯一 `recentlyRetiredIndex`，并新增 `handleMemoryWarning()`、`recentlyRetiredIndexForTesting`、`recentlyRetiredPageForTesting` 与 `managedInsetOwnerIndexesForTesting`。`didSelect` 在清空 transition source 前原子完成：保存 source offset snapshot → 释放 source managed inset ownership → 若 source 未由 `configuredAdjacent` 正式持有则把 source 写入 retired slot → 提交 target current，并记录 `children.page.retire`。`reconcileRetention` 必须把 controller 强 retention reasons 与 `activeRetentionIndexes` 的 managed inset ownership 分开计算，`.recentlyRetired` 不得进入 active indexes。

下一笔 `willSelect` 若 target 命中 retired，先增加 `.transitionTarget` 再移除 `.recentlyRetired`，不得出现释放窗口；若 target 不同，清理旧 retired 并记录 `children.page.retiredRelease`。若页面已由 `configuredAdjacent` 正式 retention 持有，不重复写入 retired slot。matching reload generation replacement、`handleMemoryWarning()`、Host removal、`releaseAll()` 和 deinit 同步清空。

- [ ] **Step 4: 运行 GREEN、资源探针、自审并提交**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task4-green \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAppearanceCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests \
  test
git diff --check
```

Expected: 全通过，弱引用在 slot 替换/clear 后为 nil。自审确认 appearance 完成早于 containment removal、retired 页不再参与纵向 owner 或 inset、无 timer/async-after、duplicate controller 不形成双 parent。

Commit:

```bash
git add Sources/AnchorPager/Paging Sources/AnchorPager/Children Tests/AnchorPagerTests
git commit -m "收口分页生命周期与最近退场缓存"
```

---

### Task 5: Host reload/selection transaction 迁移

**Files:**
- Create: `Tests/AnchorPagerTests/AnchorPagerPagingHostReloadTests.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPagingHostSelectionTests.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPagingHostResourceTests.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingSelectionRequest.swift`
- Modify: `Sources/AnchorPager/Gesture/AnchorPagerInteractionCoordinator.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingSelectionRequestTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerInteractionCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**
- Consumes: 稳定 Container delegate/terminal、Store retired、现有 Host active/latest reload 和 selection 语义。
- Produces: Container sole executor、prepared 与 active interaction 分离、API/bar/interactive 三入口统一、Pageboy completion/readiness 状态删除。

- [ ] **Step 1: 把旧 Host 测试按职责复制为新契约 RED**

新测试文件覆盖以下具名语义，不引用 `AnchorPagerPagingAdapter`、`activeAdapter` 或 Pageboy：

```swift
func testStableContainerExistsBeforeFirstReloadAndSurvivesEmptyReload()
func testActiveReloadSerializesOnlyLatestPendingReload()
func testReloadTerminalPublishesBarInsetsAndGenerationAtomically()
func testAPIBarAndInteractiveSelectionsShareIdentifierSequence()
func testActiveSelectionKeepsOneLatestPendingSelection()
func testPreparedInteractiveSelectionDoesNotBeginInteractionUntilPagingPanBegins()
func testAbandonedPreparedSelectionClearsTargetWithoutPublicCancelTerminal()
func testBusinessDecisionDoesNotCreateSelectionOrInteraction()
func testMatchingContainerTerminalFinishesExactlyOnce()
func testStaleContainerTerminalCannotFinishReplacementRequest()
func testReentrantDidSelectDrainsLatestRequestAfterCommittedTerminal()
func testNonadjacentProgrammaticSelectionUsesOneSourceTargetTransition()
func testAnimatedProgrammaticSelectionUsesOnePropertyAnimatorTerminal()
func testReduceMotionProgrammaticSelectionCommitsWithoutAnimator()
func testHostContainerAndPagesReleaseAfterTeardown()
```

InteractionCoordinator 增加无副作用入口并写 RED：

```swift
func canBegin(_ state: AnchorPagerInteractionState) -> Bool
```

断言 `canBegin(.paging(id: 7))` 不改变 `state`；只有 Container 实际报告 `didBegin request` 后 Host 才调用现有 `begin`。

- [ ] **Step 2: 运行 RED**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task5-red \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostReloadTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostSelectionTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostResourceTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingSelectionRequestTests \
  -only-testing:AnchorPagerTests/AnchorPagerInteractionCoordinatorTests \
  test
```

Expected: stable Container、无副作用 admission 或新 matching terminal 断言失败。

- [ ] **Step 3: 把 Host 收口为 Container 唯一执行器**

删除 Task 1 的 `AnchorPagerPagingExecutionMode` 分支，Host init 就标准 containment 安装一个 Container，空数据只清页面/bar。Host 对外统一暴露：

```swift
var pagingPanGestureRecognizer: UIPanGestureRecognizer { container.pagingPanGestureRecognizer }
var routePanGestureRecognizer: UIPanGestureRecognizer { container.routePanGestureRecognizer }
```

`AnchorPagerPagingSelectionTransaction` 改为：

```swift
struct AnchorPagerPagingSelectionTransaction: Equatable {
    let request: AnchorPagerPagingSelectionRequest
    let previousIndex: Int
    let executorIdentifier: ObjectIdentifier
    private(set) var semanticTerminal: AnchorPagerPagingSelectionSemanticTerminal?
}
```

删除 `didAcknowledgeCompletion`、`didAcknowledgeExecutorReady` 和两个 acknowledge 方法。只有匹配 `request.identifier + targetIndex + executorIdentifier` 的 Container semantic terminal 可结束请求。程序化动画由 Container 内部唯一 `UIViewPropertyAnimator` 驱动 PagingScrollView offset，非相邻页仍只有 source/target 两页；Reduce Motion 或非动画请求同步提交。animator completion 归一化为同一个 terminal，不进入 Host 的双确认协议，也不能与 interactive pan 同时成为 offset owner。

Host 收到 matching terminal 时分别记录 `paging.selection.committed` 或 `paging.selection.cancelled`；active selection 期间只保留 latest reload 并在首次进入 deferred 时记录一次 `paging.reload.deferred`。日志不得包含 index、request identifier、title 或 provider 内容，现有 logger sink tests 必须精确断言固定 event。

- [ ] **Step 4: 迁移 ViewController/Store terminal 与重入**

保留现有回调顺序：Host `willSelect` → Store `willSelect` → terminal → Store `didSelect/didCancel` → rebind committed scroll → Public delegate → drain latest。Provider 只能读取 committed 或当前 active reload 指定 generation；pending generation 不得被 Container 越权获取。

selection/reload/layout/size 互斥继续由 InteractionCoordinator 仲裁；prepared 仅预取 target 并建立 containment，pan `.began` 才进入 `.paging`，因此 route 最终失败为 `.business` 时不得留下 interaction busy 状态。

- [ ] **Step 5: 运行 Host GREEN 与完整 Framework 回归**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task5-green \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostReloadTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostSelectionTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostResourceTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingSelectionRequestTests \
  -only-testing:AnchorPagerTests/AnchorPagerInteractionCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  test
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task5-framework \
  test
git diff --check
```

Expected: 聚焦与 Framework 全量均 0 fail、0 skip。此时旧 Adapter 测试可继续单独存在，但生产 Host 已无 Adapter 路径。

- [ ] **Step 6: 自审并提交**

自审必须逐项记录：Host 是唯一 active/latest owner；Container 不读 generation；Store 仍是 page identity/lifecycle policy owner；matching terminal 单一；prepared 不伪造 active；empty reload 保持稳定 Container；重入和 stale callback 不双提交。

Commit:

```bash
git add Sources/AnchorPager Tests/AnchorPagerTests
git commit -m "迁移分页主机事务到自有容器"
```

---

### Task 6: 尺寸、plain presentation、系统返回与示例正式装配

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingContainerViewController.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingScrollView.swift`
- Modify: `Sources/AnchorPager/Gesture/AnchorPagerGesturePriorityCoordinator.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: sole Container Host、`setPagePresentationTranslationY`、paging/route pans、existing layout/size/plain bottom policies。
- Produces: canonical size migration、plain presentation 分层、interactive-pop 双优先、Example 无 launch-argument 的正式新链路。

- [ ] **Step 1: 写尺寸/presentation/priority RED**

增加：

```swift
func testSizeChangeCancelsPreparedAndActiveInteractiveBeforeRebuildingFrames()
func testSizeChangeRebasesProgrammaticAnimatorProgressAndKeepsRequestIdentity()
func testIdleSizeChangeKeepsCurrentIndexAndResetsOffsetToZero()
func testLayoutDirectionChangeDuringActiveTransitionAppliesOnlyAfterTerminal()
func testPlainBottomMovesOnlyPagePresentationView()
func testSelectionReloadSizeAndRemovalResetPagePresentationToIdentity()
func testInteractivePopHasPriorityOverPagingAndRoutePans()
func testInteractivePopBeganAbandonsPreparedSelectionWithoutPublicTerminal()
func testGesturePriorityReplacementDropsDeadRelationsWithoutRetainingOldPans()
```

`AnchorPagerGesturePriorityCoordinator` 的接口改为：

```swift
func bindPagingPan(_ pan: UIPanGestureRecognizer?)
func bindRoutePan(_ pan: UIPanGestureRecognizer?)
func bindInteractivePopGesture(_ gesture: UIGestureRecognizer?)
```

只安装 `pagingPan -> interactivePop`、`routePan -> interactivePop` 两条 relation。

- [ ] **Step 2: 运行 RED 并实现 canonical migration**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task6-red \
  -only-testing:AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  test
```

Expected: size/presentation/route priority 新断言失败。

实现时 Container 根层级固定为 `pagePresentationView` + `segmentBarView`；translation 只写 `pagePresentationView.transform`。prepared 或 active interactive 遇到尺寸变化时同步 cancel 并按新 bounds 重建 current；只有程序化 animator 可以在 bounds 变化前读取规范化 progress、重建 source/target frames 后恢复同 request 的等价 offset，无法安全 rebase 时 cancel 并由 Host drain latest。active 期间布局方向变化只记录 pending direction，terminal 后再应用，不能反转既有 source/target。

- [ ] **Step 3: 删除门禁 launch argument，正式运行 Example 新链路**

删除 `-AnchorPagerSelfHostedPagingGate`、`-AnchorPagerSelfHostedPagingGateInitialIndex` 判断和所有 legacy/selfHosted 分支。Example 不再通过 launch parameter 选择 executor 或初始页，但暂时保留 Public Bool 方法到 Task 7 统一删除；新 Host 不读取该 Bool，所以它不影响业务边缘路由。

把 Task 1 四条 UI 测试移除 `SelfHostedGate` 前缀并改为正式回归：

```swift
func testOrdinaryHorizontalScrollStopsThenNextGesturePages()
func testNativeOrthogonalStopsThenNextGesturePages()
func testCompositionalOrdinaryRegionPagesAndBoundaryBounces()
func testTerminalBusinessEdgeKeepsBusinessBounce()
```

并增加：

```swift
func testLeadingEdgeInteractivePopWinsOverSelfHostedPaging()
func testPlainBottomBounceKeepsSegmentBarAndHeaderCanonical()
```

- [ ] **Step 4: 运行 GREEN 与相邻 UI 回归、自审并提交**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task6-green \
  -only-testing:AnchorPagerTests/AnchorPagerPagingContainerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task6-ui \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testOrdinaryHorizontalScrollStopsThenNextGesturePages \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testNativeOrthogonalStopsThenNextGesturePages \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalOrdinaryRegionPagesAndBoundaryBounces \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testTerminalBusinessEdgeKeepsBusinessBounce \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testLeadingEdgeInteractivePopWinsOverSelfHostedPaging \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainBottomBounceKeepsSegmentBarAndHeaderCanonical \
  test
git diff --check
```

Expected: 聚焦 Framework 与 6 条 UI 全通过。自审确认无长期 executor 开关、两条系统返回 relation 正确、bar/header 不随 plain translation、size 不制造 terminal。

Commit:

```bash
git add Sources/AnchorPager Tests/AnchorPagerTests Examples/AnchorPagerExample
git commit -m "收口自有分页尺寸与手势优先级"
```

---

### Task 7: 删除逐页静态策略、Adapter 与第三方依赖

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerProtocols.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`
- Delete: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Delete: `Sources/AnchorPager/Paging/AnchorPagerTabBarAdapter.swift`
- Delete: `Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift`
- Delete: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Delete: `Tests/AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests.swift`
- Modify: `Package.swift`
- Modify: `Package.resolved`

**Interfaces:**
- Consumes: Task 5 sole Container Host 与 Task 6 正式 Example 链路。
- Produces: 零逐页 Bool、零 Adapter/Tabman/Pageboy 生产符号、无第三方 package dependencies 的 AnchorPager。

- [ ] **Step 1: 写删除契约 RED**

把旧默认/收集测试替换为源码和行为门禁：

```swift
func testReloadMetadataNoLongerQueriesPerPageHorizontalPagingPolicy()
func testHorizontalBusinessPagesRequireNoRoutingProtocolOrCallback()
```

增加 shell 静态断言并先运行：

```bash
rg -n "allowsInteractiveHorizontalPagingAt|AnchorPagerPagingAdapter|AnchorPagerTabBarAdapter|AnchorPagerPagingSurfaceObservation|import Tabman|import Pageboy|Tabman|Pageboy" Sources Tests Examples/AnchorPagerExample/AnchorPagerExample Package.swift
```

Expected: RED，命中当前 Public Bool、Adapter、imports、tests 与 package dependencies。

- [ ] **Step 2: 删除 Public Bool 和 generation-aware policy 链**

删除协议方法、默认实现、reload metadata 字段、snapshot 校验、Host committed policy、Adapter `isScrollEnabled` 写入及对应日志。不得新增页面协议、闭包、枚举或 opt-in 替代。Example index 4/5 的显式 false 实现同步删除。

- [ ] **Step 3: 删除 Adapter/SurfaceObservation 与迁移剩余测试**

把仍验证有效契约的 Adapter 用例迁到 Container/Host 测试：bar height、reload readiness、programmatic selection、removal、presentation surface、weak release。删除只验证 Pageboy callback 顺序、Pageboy scroll discovery 或 Tabman acknowledgement 的测试，不把第三方特性伪装成新 Container 契约。

移动 `AnchorPagerPageProviding` 后，旧 Adapter 文件可完整删除。确保 `AnchorPagerViewController.refreshGesturePriorities()` 只使用 Host 显式暴露的两个 pan，不再运行 scroll hierarchy discovery。

- [ ] **Step 4: 删除 Package 依赖并重新解析**

`Package.swift` 的 `dependencies` 改为空数组，AnchorPager target 的 `dependencies` 改为空数组；Example project 现有 package product 仅指向本地 AnchorPager，保持不变。运行：

```bash
swift package resolve
rg -n "allowsInteractiveHorizontalPagingAt|AnchorPagerPagingAdapter|AnchorPagerTabBarAdapter|AnchorPagerPagingSurfaceObservation|import Tabman|import Pageboy|Tabman|Pageboy" Sources Tests Examples/AnchorPagerExample/AnchorPagerExample Package.swift
```

Expected: resolve 成功；第二个命令无输出。历史 docs 可以保留 Tabman/Pageboy 事实，不纳入此零命中命令。

- [ ] **Step 5: 运行 Framework/Example 回归、自审并提交**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task7-framework \
  test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/self-hosted-task7-build \
  build
git diff --check
```

Expected: Framework 全量和 generic build 通过，0 error/warning。自审确认 Public API 仅做已确认删除、无替代路由 API、无双 executor、无第三方类型/依赖/兼容 shim。

Commit:

```bash
git add Package.swift Package.resolved Sources Tests Examples/AnchorPagerExample
git commit -m "移除静态分页策略与第三方分页依赖"
```

---

### Task 8: 完整真实 UI、资源与相邻版本回归

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostResourceTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**
- Consumes: 无第三方依赖的最终生产链路。
- Produces: 双物理边缘、LTR/RTL、bar/API/reload/size/plain/vertical/resource 的完整自动化证据。

- [ ] **Step 1: 写最终 UI/resource 验证用例**

补齐以下具名 UI tests：

```swift
func testOrdinaryHorizontalScrollMinimumEdgeNextGesturePagesBackward()
func testOrdinaryHorizontalScrollMaximumEdgeNextGesturePagesForward()
func testNativeOrthogonalMinimumEdgeNextGesturePagesBackward()
func testNativeOrthogonalMaximumEdgeNextGesturePagesForward()
func testSameGestureReachingEdgeNeverPagesUntilFingerLifts()
func testPageBoundaryWithoutBusinessCandidateUsesNativeBounceWithoutSelection()
func testBusinessBoundaryWithoutNeighborKeepsBusinessBounce()
func testRTLPhysicalEdgesMapToLogicalPreviousAndNext()
func testVerticalRootCollectionAndHeaderHandoffRemainStableAfterHorizontalPaging()
func testBarAndPublicSelectionShareLatestPendingQueueWithInteractivePaging()
func testReloadAndSizeTransitionKeepSingleSelectionTerminal()
func testRecentlyRetiredReusesReversePageThenReplacesFrameworkSlotAfterDifferentTransition()
```

资源单测同时弱持有 Host、Container、PagingScrollView、route recognizer、source/target、retired page 和 animator，分别在 reload empty、memory warning、teardown 后断言预期释放；只允许当前/adjacent/recentlyRetired 三类设计内强引用。

- [ ] **Step 2: 运行新增 UI 验证**

Run:

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task8-red-ui \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testOrdinaryHorizontalScrollMinimumEdgeNextGesturePagesBackward \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testNativeOrthogonalMaximumEdgeNextGesturePagesForward \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSameGestureReachingEdgeNeverPagesUntilFingerLifts \
  test
```

Expected: Task 1–7 已实现的行为使三条新增验证通过。若缺少可观测值，只允许在 Example 增加 accessibility identifier/value 或扩展既有 `selection-event-trace`、`horizontal-business-probe`、`compositional-scroll-probe`，不允许增加生产路由开关或触碰 orthogonal 私有层级。

- [ ] **Step 3: 对验证失败执行停止规则**

Task 8 不计划新增生产行为。任一验证失败时停止本任务，在本计划中重新打开对应 owner 的既有任务并先增加最小 RED：边界公式回到 `AnchorPagerHorizontalGestureRouterTests`，recognizer 竞争回到 `AnchorPagerPagingRoutePanGestureRecognizerTests`，offset/terminal 回到 `AnchorPagerPagingScrollViewTests` 与 `AnchorPagerPagingTransitionCoordinatorTests`，containment/appearance 回到 Container/Appearance tests，request latest-wins 回到 Host selection/reload tests，retention/inset 回到 PageStateStore tests。修复后重跑该 owner 的完整任务门禁，再从 Task 8 Step 1 重新执行。若缺口要求跨 owner 回调、业务 offset 写入或私有 API，先更新设计与计划并重新确认，不得用延迟/reset 补丁绕过。

- [ ] **Step 4: 运行 Framework、Example unit、UI 全量和 generic build**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task8-framework \
  -resultBundlePath /private/tmp/AnchorPagerSelfHostedFrameworkFull.xcresult \
  test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-task8-example \
  -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/AnchorPagerSelfHostedExampleFull.xcresult \
  test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/self-hosted-task8-build \
  -resultBundlePath /private/tmp/AnchorPagerSelfHostedGenericBuild.xcresult \
  build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/self-hosted-task8-analyze \
  -resultBundlePath /private/tmp/AnchorPagerSelfHostedGenericAnalyze.xcresult \
  analyze
```

Expected: 四条命令全部 0 fail、0 skip、0 error/warning/analyzer warning。

- [ ] **Step 5: 检查 xcresult、运行时问题与静态所有权**

Run:

```bash
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerSelfHostedFrameworkFull.xcresult
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerSelfHostedExampleFull.xcresult
xcrun xcresulttool get build-results build-tasks --path /private/tmp/AnchorPagerSelfHostedGenericBuild.xcresult
xcrun xcresulttool get build-results build-tasks --path /private/tmp/AnchorPagerSelfHostedGenericAnalyze.xcresult
rg -n "delegate\s*=|contentOffset\s*=|bounces\s*=|alwaysBounce(Horizontal|Vertical)\s*=|isScrollEnabled\s*=" Sources/AnchorPager/Gesture Sources/AnchorPager/Paging
rg -n "NSClassFromString|perform\(|value\(forKey:|_UI|orthogonal.*subviews|subviews\[[0-9]+\]" Sources/AnchorPager
git diff --check
```

Expected: 结果摘要零失败/警告；业务所有权扫描仅命中自有 PagingScrollView；私有 API 扫描无输出；`git diff --check` 无输出。

- [ ] **Step 6: 自审并提交**

自审逐项覆盖 public API、containment/appearance、selection/reload generation、scroll discovery、inset ownership、plain presentation、interactive-pop、LTR/RTL、Dynamic Type、Reduce Motion、资源释放、日志 privacy、Example 与 UI 稳定性。

Commit:

```bash
git add Sources Tests Examples/AnchorPagerExample
git commit -m "补齐自有分页完整交互与资源回归"
```

---

### Task 9: 文档、全量终验与 fresh-pass

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-17-self-hosted-horizontal-paging-auto-handoff-design.md`
- Modify: `docs/superpowers/specs/2026-07-16-next-gesture-horizontal-boundary-paging-design.md`
- Modify: `docs/superpowers/plans/2026-07-16-next-gesture-horizontal-boundary-paging.md`
- Modify: `docs/superpowers/plans/2026-07-17-self-hosted-horizontal-paging-auto-handoff.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Task 1–8 的真实命令、测试数量、xcresult、提交和自审结论。
- Produces: 面向接入者与维护者一致的最终事实、历史 superseded 指针、可复现验收记录和零问题 fresh-pass。

- [ ] **Step 1: 更新长期文档**

README 明确：普通业务横向 scroll 与原生 orthogonal 零配置；同手势不接力，下一手势边缘分页；不再存在逐页 Bool；不承诺页面立即 deinit。Architecture 画出：

```text
AnchorPagerViewController
└─ AnchorPagerPagingHostViewController
   └─ AnchorPagerPagingContainerViewController
      ├─ pagePresentationView
      │  └─ AnchorPagerPagingScrollView
      └─ AnchorPagerSegmentBarView
```

并写清 Host/Container/ScrollView/Router/Store owner、recognizer priority、appearance、recentlyRetired、plain presentation、bar obstruction、known limitation。AGENTS 技术基线改为自有分页，不再写 Tabman/Pageboy 当前依赖；历史门禁记录保留 commit/xcresult 事实。

- [ ] **Step 2: 更新任务状态与历史指针**

`docs/task-list.md` 逐任务登记真实 RED/GREEN/测试数量/提交；本设计状态只有在 Task 8 全量通过后才改为“实现完成，待 fresh-pass”。2026-07-16 Pageboy route-gate spec/plan 顶部增加“已被 2026-07-17 自有分页设计取代”的链接，不改写原 0/2 失败证据。

- [ ] **Step 3: 执行最终可复现门禁**

Run:

```bash
swift package resolve
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-final-framework \
  -resultBundlePath /private/tmp/AnchorPagerSelfHostedFinalFramework.xcresult \
  test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/self-hosted-final-example \
  -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/AnchorPagerSelfHostedFinalExample.xcresult \
  test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/self-hosted-final-build \
  -resultBundlePath /private/tmp/AnchorPagerSelfHostedFinalBuild.xcresult \
  build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/self-hosted-final-analyze \
  -resultBundlePath /private/tmp/AnchorPagerSelfHostedFinalAnalyze.xcresult \
  analyze
git diff --check
```

Expected: resolve 成功；Framework/Example 0 fail、0 skip；generic build/analyze 0 error/warning/analyzer warning；diff check 无输出。

- [ ] **Step 4: 执行 fresh-pass 审查**

从设计提交 `66abcdc` 到当前 HEAD 审查完整差异，逐文件核对：

```bash
git diff --stat 66abcdc...HEAD
git diff --check 66abcdc...HEAD
rg -n "allowsInteractiveHorizontalPagingAt|import Tabman|import Pageboy|AnchorPagerPagingAdapter|AnchorPagerTabBarAdapter|AnchorPagerPagingSurfaceObservation" Sources Tests Examples/AnchorPagerExample/AnchorPagerExample Package.swift
```

审查结论按 Critical/Important/Minor 记录。任何非零问题都先写 RED、修复、重跑受影响聚焦测试和最终门禁；只有 Critical 0、Important 0、Minor 0 才把设计、task-list 和 AGENTS 标为 Ready。

- [ ] **Step 5: 提交最终文档状态**

```bash
git add README.md docs AGENTS.md
git commit -m "完成自有横向分页架构验收"
```

提交后再运行 `git status --short`，Expected: 无输出。最终交付记录实际 HEAD、每个 xcresult 路径、Framework/Example 测试数量、0 fail/skip/warning/analyzer warning 与 fresh-pass 结论。

---

## 计划自审结果

### Spec coverage

- 自有 Container/PagingScrollView 分层：Task 1、4、5。
- 普通横向 scroll 与原生 orthogonal 的第一任务硬门禁：Task 1，4 条 UI 同时覆盖两类业务内容、普通区域/boundary ownership、三轮稳定与失败清理分支。
- 同手势不接力/下一手势自动分页：Task 1、2、8。
- 四态路由、LTR/RTL、首尾业务 bounce 和 page boundary bounce：Task 2、8。
- 不接管业务 delegate/pan/offset/bounce/enable、不使用私有 API：Global Constraints、Task 1、2、8 静态扫描。
- SegmentBar/indicator/height/obstruction/accessibility：Task 3。
- containment/appearance/recentlyRetired/ownership 解耦：Task 4。
- Host active/latest、prepared/active、reload/generation/reentrancy：Task 5。
- size/plain presentation/interactive-pop：Task 6。
- 删除 Public Bool、Adapter、Tabman/Pageboy：Task 7。
- 完整 UI/resource/diagnostics/docs/fresh-pass：Task 8、9。
- 未发现设计条款缺少实施任务。

### Placeholder scan

已按 writing-plans 的禁用占位表达清单完成全文扫描，扫描结果为零。每个代码变更步骤都给出固定签名、关键分支或具名测试，命令均包含确定 scheme、destination、derived data 与 expected result。

### Type consistency

- Router、route recognizer、PagingScrollView、Container、SegmentBar 和 provider 的名称与签名在固定接口及各任务一致。
- 统一 terminal 使用 `AnchorPagerPagingScrollTerminal`（ScrollView）和 `AnchorPagerPagingContainerTerminal`（Container），Host 只消费后者。
- selection request identifier 始终为 `Int`；Task 5 只把 `adapterIdentifier` 改名为 `executorIdentifier`，没有平行 transaction。
- `pagingPanGestureRecognizer` 与 `routePanGestureRecognizer` 均由 Container → Host → GesturePriorityCoordinator 单向暴露。
- `setPagePresentationTranslationY(_:)` 始终只属于 Container/Host presentation 链。
- 未发现跨任务方法名或返回类型不一致。
