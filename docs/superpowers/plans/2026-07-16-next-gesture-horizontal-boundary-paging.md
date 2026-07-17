# 横向业务边缘下一手势分页接力实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **执行状态（2026-07-16）：BLOCKED。** Task 1/2 曾完成为未装配的内部实验基础；Task 3 的
> Framework RED/GREEN 已执行，临时装配聚焦测试 51/51 通过，但真实 UIKit 硬门禁 0/2：普通业务
> 横向 scroll 与原生 orthogonal 都在第一笔 interior 拖动时无法消费。已触发停止条件并用
> `apply_patch` 清理 Task 3 生产、测试与 Example 临时变更；删除 Task 1/2 实验基础前，其聚焦回归
> 21/21 通过。用户随后确认删除未装配的 Task 1/2 实验源码、专属测试和日志断言，只保留失败证据
> 与本计划的历史尝试正文；清理后 Framework 439/439 与 Example generic Simulator build 通过。
> 当前生产继续使用 `allowsInteractiveHorizontalPagingAt` 及其 metadata/Host/Adapter 静态策略链；
> Task 4–7 均未开始，不得按本计划继续执行。
>
> **证据：** Framework 临时装配 GREEN：
> `/Users/sondra/Library/Developer/Xcode/DerivedData/AnchorPager-doqoqfcvrimbvshlhdiujkppdgrb/Logs/Test/Test-AnchorPager-2026.07.16_18-35-22-+0800.xcresult`；
> 真实 UIKit FAIL：`/private/tmp/AnchorPagerTask3UIKitGate-20260716-1840.xcresult`；
> 清理后 21/21：
> `/Users/sondra/Library/Developer/Xcode/DerivedData/AnchorPager-doqoqfcvrimbvshlhdiujkppdgrb/Logs/Test/Test-AnchorPager-2026.07.16_18-44-33-+0800.xcresult`。
> 清理后 Framework 439/439：
> `/Users/sondra/Library/Developer/Xcode/DerivedData/AnchorPager-doqoqfcvrimbvshlhdiujkppdgrb/Logs/Test/Test-AnchorPager-2026.07.17_09-42-12-+0800.xcresult`；
> Example generic Simulator build：`** BUILD SUCCEEDED **`。

**Goal:** 删除逐页静态横向分页开关，以框架自有 route gate 自动判断触点路径上的横向 `UIScrollView` 边界，使业务内容在当前手势内完整滚动，并在边缘后的下一次向外拖中由 Pageboy 原生分页。

**Architecture:** Paging surface 持有一个 AnchorPager 自有 `UIPanGestureRecognizer`；Pageboy paging pan 静态等待该 gate 失败。gate 只在手势起点沿 hit-test 祖先链读取公开 `UIScrollView` 几何：任一候选仍可消费则 gate 成功并与业务 pan 同时识别，全部候选已在对应外边缘则 gate 失败并放行 Pageboy。旧 Public Bool、reload metadata、PagingHost committed snapshot 和 Adapter `isScrollEnabled` 开关在真实 UIKit 硬门禁通过后整体删除。

**Tech Stack:** Swift 6.2、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、Tabman 4.0.1、Pageboy 5.0.2、`UICollectionViewCompositionalLayout` 原生 `.orthogonalScrollingBehavior`、XCTest/XCUITest、Xcode 26.6、iPhone 17 Pro / iOS 26.5 Simulator。

## Global Constraints

- 所有 UIKit、手势和 coordinator 状态保持 `@MainActor`；纯边界模型不得整体依赖 UIKit。
- 不新增 Public API；删除 `pagerViewController(_:allowsInteractiveHorizontalPagingAt:)` 后不保留 deprecated 空壳。
- 不设置 Pageboy、业务 `UIScrollView` 或业务内建 pan 的 delegate，不写业务 offset，不切换业务或 Pageboy `isScrollEnabled`/bounce。
- 不识别 UIKit 私有类名、私有 selector 或固定 subview 索引；只沿当前触点的真实 superview 链读取公开 `UIScrollView` 属性。
- 不把 orthogonal 内部 scroll 登记为纵向 target；根 `UICollectionView` 仍是组合布局页唯一 `anchorPagerScrollView`。
- 当前业务手势中途到边缘不得重新仲裁；松手后的下一次向外拖才允许 Pageboy。
- Pageboy containment、selection semantic/completion/executor-ready、appearance lifecycle、Store generation、managed inset、纵向 handoff、overscroll 和 interactive-pop 契约保持不变。
- Task 3 是停止门禁：普通横向 scroll 或原生 orthogonal 任一路径不稳定，就删除尚未提交的实验装配、保留当前静态策略并向用户报告；不得继续 Task 4。
- 每个任务遵循 RED → 确认失败原因 → GREEN → 聚焦回归 → 自审 → 中文提交；提交前运行 `git diff --check`。

## 文件职责映射

**新增文件：**

- `Sources/AnchorPager/Gesture/AnchorPagerHorizontalScrollBoundaryResolver.swift`：纯值几何、横向主方向和“内容/分页边缘/无候选”决策。
- `Sources/AnchorPager/Gesture/AnchorPagerHorizontalPagingRouteGate.swift`：AnchorPager 自有 pan、hit-test 祖先链发现、一次性 should-begin 和同时识别策略。
- `Tests/AnchorPagerTests/AnchorPagerHorizontalScrollBoundaryResolverTests.swift`：纯边界、inset、bounce、非法几何和双物理方向测试。
- `Tests/AnchorPagerTests/AnchorPagerHorizontalPagingRouteGateTests.swift`：命中链、嵌套 scroll、delegate/configuration 隔离和日志测试。

**修改文件：**

- `Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift`：为每个 paging surface 同步装卸 route gate，并随 surface 发布 gate identity。
- `Sources/AnchorPager/Gesture/AnchorPagerGesturePriorityCoordinator.swift`：安装 `pagingPan -> routeGate` 与既有 `pagingPan -> interactivePop` 两条公开失败关系。
- `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：把当前 surface gate 交给 GesturePriorityCoordinator；门禁通过后删除 Bool reload snapshot。
- `Sources/AnchorPager/Public/AnchorPagerProtocols.swift`：门禁通过后删除旧 Public Bool。
- `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`：门禁通过后删除 Bool request/committed snapshot/terminal 应用。
- `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`：删除静态 `setInteractiveHorizontalPagingEnabled`，保持 Pageboy 原生交互常开。
- `Tests/AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests.swift`：gate 装卸、replacement、deinit 和内建 delegate 隔离。
- `Tests/AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests.swift`：双失败关系矩阵、幂等和不保留业务 child relation。
- `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`：surface gate 装配与旧静态开关测试移除。
- `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`：删除旧 Bool generation/terminal 测试，保留 reload/selection 事务回归。
- `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：删除 Bool callback/reentry 测试，验证 Public 源码无替代路由 API。
- `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`：删除静态开关日志，保留 route gate 固定决策日志。
- `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`：删除静态 false，实现普通横向页边界 probe 和自动离页文案。
- `Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift`：保留原生 orthogonal，只扩充边界测试 probe。
- `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`：更新页面接入、probe 与原生 layout 断言。
- `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：普通横向双边、orthogonal leading 边缘、同手势不接力、下一手势分页和相邻回归。
- `README.md`、`docs/architecture.md`、`docs/task-list.md`、两份相关 spec/plan、`AGENTS.md`：只在真实门禁和全量验收后迁移为已完成事实。

---

### Task 1：建立纯横向边界决策模型

**Files:**
- Create: `Sources/AnchorPager/Gesture/AnchorPagerHorizontalScrollBoundaryResolver.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerHorizontalScrollBoundaryResolverTests.swift`

**Interfaces:**
- Consumes: `CGPoint`、业务 scroll 的只读几何值。
- Produces: `AnchorPagerHorizontalScrollBoundaryResolver.Geometry`、`Decision` 和 `decision(for:velocity:epsilon:) -> Decision`，供 Task 2 的 route gate 使用。

- [ ] **Step 1：写纯模型 RED**

创建测试文件，完整覆盖以下调用形式：

```swift
import CoreGraphics
import XCTest
@testable import AnchorPager

final class AnchorPagerHorizontalScrollBoundaryResolverTests: XCTestCase {
    private typealias Geometry = AnchorPagerHorizontalScrollBoundaryResolver.Geometry

    func testInteriorCanConsumeBothPhysicalDirections() {
        let geometry = makeGeometry(offsetX: 100, maximumX: 300)
        XCTAssertEqual(resolve([geometry], velocityX: 400), .content)
        XCTAssertEqual(resolve([geometry], velocityX: -400), .content)
    }

    func testMinimumBoundaryPagesOutwardAndConsumesInward() {
        let geometry = makeGeometry(offsetX: 0, maximumX: 300)
        XCTAssertEqual(resolve([geometry], velocityX: 400), .pagingBoundary)
        XCTAssertEqual(resolve([geometry], velocityX: -400), .content)
    }

    func testMaximumBoundaryPagesOutwardAndConsumesInward() {
        let geometry = makeGeometry(offsetX: 300, maximumX: 300)
        XCTAssertEqual(resolve([geometry], velocityX: -400), .pagingBoundary)
        XCTAssertEqual(resolve([geometry], velocityX: 400), .content)
    }

    func testNativeBounceUsesPhysicalReturnDirection() {
        XCTAssertEqual(resolve([makeGeometry(offsetX: -12, maximumX: 300)], velocityX: 400), .pagingBoundary)
        XCTAssertEqual(resolve([makeGeometry(offsetX: -12, maximumX: 300)], velocityX: -400), .content)
        XCTAssertEqual(resolve([makeGeometry(offsetX: 312, maximumX: 300)], velocityX: -400), .pagingBoundary)
        XCTAssertEqual(resolve([makeGeometry(offsetX: 312, maximumX: 300)], velocityX: 400), .content)
    }

    func testAnyNestedCandidateCanKeepGestureInContent() {
        let innerAtMaximum = makeGeometry(offsetX: 300, maximumX: 300)
        let outerInterior = makeGeometry(offsetX: 40, maximumX: 100)
        XCTAssertEqual(resolve([innerAtMaximum, outerInterior], velocityX: -400), .content)
    }

    func testAdjustedInsetsAndHalfPointEpsilonDefineStableRange() {
        let geometry = Geometry(
            contentOffsetX: -9.6,
            contentSizeWidth: 500,
            boundsWidth: 300,
            adjustedInsetLeft: 10,
            adjustedInsetRight: 20
        )
        XCTAssertEqual(resolve([geometry], velocityX: 400), .pagingBoundary)
    }

    func testVerticalZeroAndInvalidGeometryDoNotBlockPaging() {
        let valid = makeGeometry(offsetX: 100, maximumX: 300)
        XCTAssertEqual(
            AnchorPagerHorizontalScrollBoundaryResolver.decision(
                for: [valid],
                velocity: CGPoint(x: 20, y: 200)
            ),
            .noCandidate
        )
        XCTAssertEqual(resolve([valid], velocityX: 0), .noCandidate)
        XCTAssertEqual(resolve([makeGeometry(offsetX: .nan, maximumX: 300)], velocityX: 400), .noCandidate)
    }

    private func resolve(_ geometries: [Geometry], velocityX: CGFloat) -> AnchorPagerHorizontalScrollBoundaryResolver.Decision {
        AnchorPagerHorizontalScrollBoundaryResolver.decision(
            for: geometries,
            velocity: CGPoint(x: velocityX, y: 0)
        )
    }

    private func makeGeometry(offsetX: CGFloat, maximumX: CGFloat) -> Geometry {
        Geometry(
            contentOffsetX: offsetX,
            contentSizeWidth: maximumX + 300,
            boundsWidth: 300,
            adjustedInsetLeft: 0,
            adjustedInsetRight: 0
        )
    }
}
```

- [ ] **Step 2：运行 RED 并确认失败原因**

Run:

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerHorizontalScrollBoundaryResolverTests test
```

Expected: FAIL，错误只应为 `AnchorPagerHorizontalScrollBoundaryResolver` 尚不存在；如果先出现 Package/Xcode 环境错误，先修复环境，不写实现掩盖。

- [ ] **Step 3：写最小纯模型 GREEN**

新增：

```swift
import CoreGraphics

struct AnchorPagerHorizontalScrollBoundaryResolver {
    struct Geometry: Equatable {
        let contentOffsetX: CGFloat
        let contentSizeWidth: CGFloat
        let boundsWidth: CGFloat
        let adjustedInsetLeft: CGFloat
        let adjustedInsetRight: CGFloat
    }

    enum Decision: Equatable {
        case content
        case pagingBoundary
        case noCandidate
    }

    static func decision(
        for geometries: [Geometry],
        velocity: CGPoint,
        epsilon: CGFloat = 0.5
    ) -> Decision {
        guard velocity.x.isFinite,
              velocity.y.isFinite,
              abs(velocity.x) > abs(velocity.y),
              abs(velocity.x) > epsilon else {
            return .noCandidate
        }

        let ranges = geometries.compactMap { geometry -> (CGFloat, CGFloat, CGFloat)? in
            guard geometry.contentOffsetX.isFinite,
                  geometry.contentSizeWidth.isFinite,
                  geometry.boundsWidth.isFinite,
                  geometry.adjustedInsetLeft.isFinite,
                  geometry.adjustedInsetRight.isFinite,
                  geometry.boundsWidth > 0 else {
                return nil
            }
            let minimumX = -geometry.adjustedInsetLeft
            let maximumX = max(
                minimumX,
                geometry.contentSizeWidth
                    - geometry.boundsWidth
                    + geometry.adjustedInsetRight
            )
            guard maximumX - minimumX > epsilon else { return nil }
            return (geometry.contentOffsetX, minimumX, maximumX)
        }
        guard !ranges.isEmpty else { return .noCandidate }

        let canConsume = ranges.contains { range in
            let (offsetX, minimumX, maximumX) = range
            if velocity.x > 0 {
                return offsetX > minimumX + epsilon
            }
            return offsetX < maximumX - epsilon
        }
        return canConsume ? .content : .pagingBoundary
    }
}
```

- [ ] **Step 4：跑聚焦 GREEN、SwiftFormat 风格检查与提交**

Run: 重复 Step 2 命令；Expected: 全部 PASS、0 skip。

随后：

```bash
git diff --check
git add Sources/AnchorPager/Gesture/AnchorPagerHorizontalScrollBoundaryResolver.swift Tests/AnchorPagerTests/AnchorPagerHorizontalScrollBoundaryResolverTests.swift
git commit -m "建立横向滚动边界决策模型"
```

自审：纯模型只依赖 CoreGraphics；不出现 UIKit、Tabman、Pageboy、业务命名或日志热路径。

---

### Task 2：实现框架自有 route gate

**Files:**
- Create: `Sources/AnchorPager/Gesture/AnchorPagerHorizontalPagingRouteGate.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerHorizontalPagingRouteGateTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `AnchorPagerHorizontalScrollBoundaryResolver.decision(for:velocity:epsilon:)`。
- Produces: `AnchorPagerHorizontalPagingRouteGate.init(pagingScrollView:pagingPan:hitTest:velocity:)`；`gestureRecognizerShouldBegin(_:)` 返回 `true` 仅表示“内容消费，本次阻止 Pageboy”。

- [ ] **Step 1：写 hit-test、嵌套候选和所有权 RED**

测试必须使用真实 UIView/UIScrollView 祖先链，注入固定 hit view 与 velocity，至少包含：

```swift
@MainActor
func testInteriorBusinessScrollMakesGateBeginWithoutChangingDelegates() {
    let paging = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    let business = UIScrollView(frame: paging.bounds)
    business.contentSize = CGSize(width: 900, height: 700)
    business.contentOffset.x = 120
    paging.addSubview(business)
    let originalScrollDelegate = business.delegate
    let originalPanDelegate = business.panGestureRecognizer.delegate
    let gate = AnchorPagerHorizontalPagingRouteGate(
        pagingScrollView: paging,
        pagingPan: paging.panGestureRecognizer,
        hitTest: { _, _ in business },
        velocity: { _, _ in CGPoint(x: -400, y: 0) }
    )
    paging.addGestureRecognizer(gate)

    XCTAssertTrue(gate.gestureRecognizerShouldBegin(gate))
    XCTAssertTrue(business.delegate === originalScrollDelegate)
    XCTAssertTrue(business.panGestureRecognizer.delegate === originalPanDelegate)
    XCTAssertFalse(gate.cancelsTouchesInView)
}

@MainActor
func testBoundaryMakesGateFailAndNestedOuterCandidateCanStillConsume() {
    let paging = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    let outer = UIScrollView(frame: paging.bounds)
    outer.contentSize = CGSize(width: 600, height: 700)
    outer.contentOffset.x = 80
    let inner = UIScrollView(frame: outer.bounds)
    inner.contentSize = CGSize(width: 900, height: 700)
    inner.contentOffset.x = 510
    paging.addSubview(outer)
    outer.addSubview(inner)
    let gate = AnchorPagerHorizontalPagingRouteGate(
        pagingScrollView: paging,
        pagingPan: paging.panGestureRecognizer,
        hitTest: { _, _ in inner },
        velocity: { _, _ in CGPoint(x: -400, y: 0) }
    )
    paging.addGestureRecognizer(gate)

    XCTAssertTrue(gate.gestureRecognizerShouldBegin(gate))

    outer.contentOffset.x = 210
    XCTAssertFalse(gate.gestureRecognizerShouldBegin(gate))
}

@MainActor
func testGateOnlyAllowsSimultaneousRecognitionWithNonPagingRecognizer() {
    let paging = UIScrollView()
    let business = UIScrollView()
    let gate = AnchorPagerHorizontalPagingRouteGate(
        pagingScrollView: paging,
        pagingPan: paging.panGestureRecognizer
    )

    XCTAssertTrue(
        gate.gestureRecognizer(
            gate,
            shouldRecognizeSimultaneouslyWith: business.panGestureRecognizer
        )
    )
    XCTAssertFalse(
        gate.gestureRecognizer(
            gate,
            shouldRecognizeSimultaneouslyWith: paging.panGestureRecognizer
        )
    )
}

@MainActor
func testDecisionLogsContainNoGeometryOrHierarchyPayload() {
    let paging = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    let business = UIScrollView(frame: paging.bounds)
    business.contentSize = CGSize(width: 900, height: 700)
    paging.addSubview(business)
    var velocity = CGPoint(x: -400, y: 0)
    let gate = AnchorPagerHorizontalPagingRouteGate(
        pagingScrollView: paging,
        pagingPan: paging.panGestureRecognizer,
        hitTest: { _, _ in business },
        velocity: { _, _ in velocity }
    )
    paging.addGestureRecognizer(gate)
    var events: [AnchorPagerLogger.Event] = []
    AnchorPagerLogger.sink = { events.append($0) }
    defer { AnchorPagerLogger.sink = nil }

    business.contentOffset.x = 100
    XCTAssertTrue(gate.gestureRecognizerShouldBegin(gate))
    business.contentOffset.x = 510
    XCTAssertFalse(gate.gestureRecognizerShouldBegin(gate))
    velocity = CGPoint(x: 0, y: 400)
    XCTAssertFalse(gate.gestureRecognizerShouldBegin(gate))

    XCTAssertEqual(
        events.map(\.event),
        [
            "gesture.horizontalRoute.content",
            "gesture.horizontalRoute.pagingBoundary",
            "gesture.horizontalRoute.noCandidate",
        ]
    )
}
```

源码隔离测试精确断言新文件不包含：`.delegate =`（除 `delegate = self` 的 gate 自有赋值，可改用专门断言）、`setValue(`、`value(forKey:`、`_UI`、`contentOffset =`、`isScrollEnabled =`、`.bounces =`。

- [ ] **Step 2：运行 route gate RED**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerHorizontalPagingRouteGateTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
```

Expected: 新类型不存在导致 FAIL；既有 Logger 测试仍通过。

- [ ] **Step 3：实现 gate 的完整最小结构**

实现保持在单一文件中：

```swift
import UIKit

@MainActor
final class AnchorPagerHorizontalPagingRouteGate:
    UIPanGestureRecognizer,
    UIGestureRecognizerDelegate {
    typealias HitTest = (UIView, CGPoint) -> UIView?
    typealias Velocity = (UIPanGestureRecognizer, UIView) -> CGPoint

    private weak var pagingScrollView: UIScrollView?
    private weak var pagingPan: UIPanGestureRecognizer?
    private let hitTest: HitTest
    private let velocityProvider: Velocity

    init(
        pagingScrollView: UIScrollView,
        pagingPan: UIPanGestureRecognizer,
        hitTest: @escaping HitTest = { root, point in root.hitTest(point, with: nil) },
        velocity: @escaping Velocity = { pan, view in pan.velocity(in: view) }
    ) {
        self.pagingScrollView = pagingScrollView
        self.pagingPan = pagingPan
        self.hitTest = hitTest
        velocityProvider = velocity
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === self,
              let pagingScrollView else {
            return false
        }
        let point = location(in: pagingScrollView)
        let velocity = velocityProvider(self, pagingScrollView)
        let hitView = hitTest(pagingScrollView, point)
        let decision = AnchorPagerHorizontalScrollBoundaryResolver.decision(
            for: horizontalGeometries(from: hitView, stoppingAt: pagingScrollView),
            velocity: velocity
        )
        AnchorPagerLogger.log(
            .debug,
            category: .gesture,
            event: decision.logEvent
        )
        return decision == .content
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === self && otherGestureRecognizer !== pagingPan
    }

    private func horizontalGeometries(
        from hitView: UIView?,
        stoppingAt pagingScrollView: UIScrollView
    ) -> [AnchorPagerHorizontalScrollBoundaryResolver.Geometry] {
        var geometries: [AnchorPagerHorizontalScrollBoundaryResolver.Geometry] = []
        var current = hitView
        while let view = current, view !== pagingScrollView {
            if let scrollView = view as? UIScrollView {
                let inset = scrollView.adjustedContentInset
                geometries.append(.init(
                    contentOffsetX: scrollView.contentOffset.x,
                    contentSizeWidth: scrollView.contentSize.width,
                    boundsWidth: scrollView.bounds.width,
                    adjustedInsetLeft: inset.left,
                    adjustedInsetRight: inset.right
                ))
            }
            current = view.superview
        }
        return geometries
    }
}

private extension AnchorPagerHorizontalScrollBoundaryResolver.Decision {
    var logEvent: String {
        switch self {
        case .content: "gesture.horizontalRoute.content"
        case .pagingBoundary: "gesture.horizontalRoute.pagingBoundary"
        case .noCandidate: "gesture.horizontalRoute.noCandidate"
        }
    }
}
```

- [ ] **Step 4：跑 GREEN、全量 Framework 快速回归并提交**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerHorizontalScrollBoundaryResolverTests \
  -only-testing:AnchorPagerTests/AnchorPagerHorizontalPagingRouteGateTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
git diff --check
git add Sources/AnchorPager/Gesture Tests/AnchorPagerTests/AnchorPagerHorizontalPagingRouteGateTests.swift Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift
git commit -m "实现横向分页起点仲裁手势"
```

Expected: 聚焦测试全过；自审确认只设置 gate 自己的 delegate，任何既有 recognizer delegate 均未写入。

---

### Task 3：装配 paging surface 并通过真实 UIKit 停止门禁

> **实际结果：失败并停止。** 下列步骤曾按 TDD 临时执行，但因 Step 6 的真实 UIKit 结果为 0/2，
> 全部 Task 3 未提交装配、测试和 Example 改动已清理，所以不把任何复选框标记为已完成。
> Framework 临时装配为 51/51；普通横向业务页首笔 interior 拖动位移为 0，原生 orthogonal
> 首笔 interior 拖动也未建立横向进度。Task 4 及后续任务为 blocked/not started。

**Files:**
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift`
- Modify: `Sources/AnchorPager/Gesture/AnchorPagerGesturePriorityCoordinator.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: Task 2 的 `AnchorPagerHorizontalPagingRouteGate`。
- Produces: `Surface.routeGateGestureRecognizer`；Coordinator 新入口 `bindHorizontalRouteGate(_:)`；真实 UIKit 证明通过后才允许 Task 4 删除静态策略。

- [ ] **Step 1：写 surface/coordinator RED**

把测试期望改为：

```swift
let surface = try XCTUnwrap(observation.surface)
XCTAssertTrue(surface.routeGateGestureRecognizer.view === surface.scrollView)
XCTAssertTrue(surface.routeGateGestureRecognizer.delegate === surface.routeGateGestureRecognizer)
```

replacement 测试记录 first gate，刷新 second surface 后断言：

```swift
XCTAssertNil(firstGate.view)
XCTAssertTrue(secondGate.view === secondScrollView)
XCTAssertTrue(firstScrollView.delegate === firstScrollDelegate)
XCTAssertTrue(firstScrollView.panGestureRecognizer.delegate === firstPanDelegate)
```

Coordinator 关系矩阵改为精确两条：

```swift
[
    .init(gesture: pagingPan, required: routeGate),
    .init(gesture: pagingPan, required: interactivePop),
]
```

并保留 `testBusinessChildPanIsNeverAddedToFailureMatrix`，证明 relation 指向 gate 而非业务 pan。
ViewController 的 `testGesturePriorityUsesPagingSurfaceAndSystemBackOnly` 同步改名为
`testGesturePriorityUsesPagingSurfaceRouteGateAndSystemBack`，断言容器提交的是同一 Surface 内的
paging pan/gate pair，并继续忽略业务横向 page 的 pan。

- [ ] **Step 2：运行 Framework RED**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests \
  -only-testing:AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests test
```

Expected: `Surface` 缺少 gate、Coordinator 缺少 bind 入口导致 FAIL。

- [ ] **Step 3：装配 gate 与失败关系**

`Surface` 增加：

```swift
let routeGateGestureRecognizer: AnchorPagerHorizontalPagingRouteGate
```

Observation bind 时按以下固定顺序执行：创建 gate → `scrollView.addGestureRecognizer(gate)` → 安装 paging pan target-action → 发布 Surface。unbind 顺序相反：移除 target-action → `removeGestureRecognizer(gate)` → 清空 surface → 发 unbind 日志。相同 page/scroll/pan identity 仍为 no-op，gate identity 不参与重复发现。

Coordinator 增加弱绑定：

```swift
private weak var horizontalRouteGate: UIGestureRecognizer?

func bindHorizontalRouteGate(_ gesture: UIGestureRecognizer?) {
    horizontalRouteGate = gesture
}
```

`refresh()` 先安装 `pagingPan -> horizontalRouteGate`，再安装 `pagingPan -> interactivePop`；两条关系分别记录一次 `gesture.priority.horizontalRoute` 和既有 `gesture.priority.interactivePop`。`invalidate()` 清空两个弱引用与关系记录。

ViewController 的刷新入口统一读取同一 surface：

```swift
private func refreshGesturePriorities() {
    let surface = pagingHost.activeAdapter?.pagingSurface
    gesturePriorityCoordinator.bindPagingPan(surface?.panGestureRecognizer)
    gesturePriorityCoordinator.bindHorizontalRouteGate(
        surface?.routeGateGestureRecognizer
    )
    gesturePriorityCoordinator.bindInteractivePopGesture(
        navigationController?.interactivePopGestureRecognizer
    )
    gesturePriorityCoordinator.refresh()
}
```

- [ ] **Step 4：先跑 Framework GREEN**

重复 Step 2 命令。Expected: PASS；源码扫描确认：

```bash
rg -n '\.delegate\s*=|contentOffset\s*=|isScrollEnabled\s*=|\.bounces\s*=' Sources/AnchorPager/Gesture Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift
```

Expected: 仅 gate 自己 `delegate = self`；无业务/Pageboy pan delegate、offset、enable 或 bounce 写入。

- [ ] **Step 5：写普通横向与原生 orthogonal 真实 UI 门禁**

本任务暂不删除旧 API，只把 Example 的现有方法临时改为所有页面返回 `true`：

```swift
func pagerViewController(
    _ pagerViewController: AnchorPagerViewController,
    allowsInteractiveHorizontalPagingAt index: Int
) -> Bool {
    true
}
```

新增两个测试：

```swift
func testHorizontalBusinessScrollKeepsCurrentGestureAtBoundaryThenNextGesturePages()
func testCompositionalOrthogonalKeepsCurrentGestureAtBoundaryThenNextGesturePages()
```

普通横向测试从 index 4 开始：业务中部左拖必须改变卡片位置且 selection trace 为空；最后一笔从 interior 到 trailing 的拖动结束后仍是 `horizontal`；下一笔从 trailing 继续左拖必须提交 `[5]`。随后 bar 返回 index 4，把业务 scroll 置于 leading，下一笔向右外拖必须提交 index 3。

组合布局测试从 index 5 开始：先左拖建立 `horizontalCurrent > 30`；一笔右拖回到 `horizontalCurrent < 0.5` 后页面仍为 `compositional`、trace 为空；下一笔继续右拖必须提交 `[4]`。全程断言 probe 中 scroll/pan delegate、bounce、enable 和纵向 target 稳定。

- [ ] **Step 6：运行真实 UIKit 硬门禁并作停止判断**

```bash
xcodebuild -quiet \
  -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalBusinessScrollKeepsCurrentGestureAtBoundaryThenNextGesturePages \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalOrthogonalKeepsCurrentGestureAtBoundaryThenNextGesturePages test
```

Expected: 2/2 PASS、0 skip；控制台无 gesture cycle、appearance imbalance 或 UIKit delegate 异常。

若任一失败：保留测试证据；用 `apply_patch` 删除本任务尚未提交的装配与 Example 临时改动，重复 Task 1/2 聚焦测试确认工作区恢复；停止计划并向用户报告。不得执行 Task 4。

- [ ] **Step 7：门禁通过后跑相邻回归、自审并提交**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests \
  -only-testing:AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testGesturePriorityUsesPagingSurfaceRouteGateAndSystemBack test
git diff --check
git add Sources/AnchorPager/Gesture Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests Examples/AnchorPagerExample
git commit -m "验证横向边缘下一手势分页可行性"
```

自审重点：route gate 是唯一新增 recognizer；不持有业务 scroll；旧静态 API 尚在但 Example 全部返回 true；Pageboy 原生 terminal/appearance 是 UI 唯一成功依据。

---

### Task 4：删除逐页静态分页策略全链

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerProtocols.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingHostViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`

**Interfaces:**
- 原计划接口前提：Task 3 应先提供通过真实 UIKit 门禁的自动 route gate；实际 Task 3 未通过门禁，当前不存在可供本任务消费的有效装配，因此 Task 4 不得开始。
- Produces: `reload(requestIdentifier:titles:pageCount:selectedIndex:)` 唯一 Host reload 签名；Public DataSource 恢复为 count/title/page/header 四项；Pageboy 交互始终保持原生启用。

- [ ] **Step 1：写“旧符号必须消失”RED**

在 ViewController 测试新增源码契约：

```swift
func testPublicAndProductionSourcesContainNoStaticInteractivePagingPolicy() throws {
    let root = try packageRoot()
    let paths = [
        "Sources/AnchorPager/Public/AnchorPagerProtocols.swift",
        "Sources/AnchorPager/Public/AnchorPagerViewController.swift",
        "Sources/AnchorPager/Paging/AnchorPagerPagingHostViewController.swift",
        "Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift",
    ]
    for path in paths {
        let source = try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("allowsInteractiveHorizontalPagingAt"))
        XCTAssertFalse(source.contains("interactiveHorizontalPagingPermissions"))
        XCTAssertFalse(source.contains("setInteractiveHorizontalPagingEnabled"))
        XCTAssertFalse(source.contains("paging.interactivePaging."))
    }
}
```

Run 该测试，Expected: FAIL 并精确命中四类旧符号。

- [ ] **Step 2：删除 Public/ViewController metadata**

从 `AnchorPagerViewControllerDataSource` 和 extension 完整删除 Bool 方法。`ReloadSnapshot` 删除 Bool 数组；`reloadData()` 只按 index 采集 title：

```swift
var resolvedTitles: [String] = []
resolvedTitles.reserveCapacity(resolvedPageCount)
for index in 0..<resolvedPageCount {
    resolvedTitles.append(
        reloadDataSource?.pagerViewController(
            self,
            titleForViewControllerAt: index
        ) ?? ""
    )
    guard isCurrentReloadTransaction(transactionIdentifier) else { return }
}
```

`submitStagedReloadIfNeeded()` 调用恢复为四项 payload，不再转发 permissions。

- [ ] **Step 3：删除 Host/Adapter 静态状态**

`ReloadRequest` 只保留 identifier/titles/pageCount/selectedIndex；Host `reload` 签名改为：

```swift
func reload(
    requestIdentifier: AnchorPagerPagingReloadRequestIdentifier,
    titles: [String],
    pageCount: Int,
    selectedIndex: Int
)
```

删除 `resolvedInteractiveHorizontalPagingPermissions`、committed Bool 数组、`applyCommittedInteractivePagingPolicy` 及其 reload/selection terminal 调用。`commitSelection` 只写：

```swift
private func commitSelection(
    _ index: Int,
    on adapter: AnchorPagerPagingAdapter
) {
    guard adapter === activeAdapter else { return }
    committedSelectionIndex = index
}
```

Adapter 删除 `setInteractiveHorizontalPagingEnabled`，不新增任何 `isScrollEnabled` 写入。

- [ ] **Step 4：迁移测试夹具并删除旧策略用例**

删除只验证以下内容的测试：默认 Bool、callback reentry、invalid metadata fail-closed、reload/selection terminal 策略切换、Adapter disable/enable 日志和 disabled 时 programmatic selection。保留并复跑相邻 reload、explicit/bar selection、surface replacement 和 lifecycle 测试。

所有 `host.reload(...interactiveHorizontalPagingPermissions:)` 调用移除该参数；Example DataSource 删除 Task 3 临时 Bool 方法。Example 单元测试改为只断言 index 4/5 页面结构和 ownership，不再调用已删除 API；横向页说明文案改成“业务内容到边缘后，再次向外拖动切换页面”。

- [ ] **Step 5：运行聚焦 GREEN 与零符号扫描**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test

rg -n 'allowsInteractiveHorizontalPagingAt|interactiveHorizontalPagingPermissions|setInteractiveHorizontalPagingEnabled|paging\.interactivePaging\.' Sources Tests Examples README.md docs/architecture.md docs/task-list.md AGENTS.md
```

Expected: Framework 聚焦测试全部 PASS；源码/测试/Example 无旧符号。长期历史计划/spec 暂时允许命中，Task 7 负责加迁移说明而不篡改历史步骤。

- [ ] **Step 6：自审并提交**

```bash
git diff --check
git add Sources/AnchorPager/Public Sources/AnchorPager/Paging Tests/AnchorPagerTests Examples/AnchorPagerExample/AnchorPagerExample Examples/AnchorPagerExample/AnchorPagerExampleTests
git commit -m "移除逐页静态横向分页策略"
```

自审：Public API 没有替代协议；Host 不再持有横向策略 generation；Pageboy `isScrollEnabled` 没有新写入；route gate 不进入 Host/Interaction/Store。

---

### Task 5：完善双边界 probe 与最终真实 UI 语义

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleCompositionalPageViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: Task 4 的零配置自动路由。
- Produces: 普通横向 probe 的 `offsetX`/`maximumX`；组合布局继续使用公开 invalidation handler 的 `horizontalCurrent`；最终可重复 UI 门禁。

- [ ] **Step 1：先写 Example probe RED**

普通横向 ownership value 扩展为：

```text
scrollDelegate=1;panDelegate=1;bounces=1;alwaysBounceVertical=0;isScrollEnabled=1;horizontalRange=1;offsetX=0.00;maximumX=622.00
```

数值按 POSIX locale 两位小数序列化。Example 单元测试解析字段并断言 `maximumX > 0`、初始 `abs(offsetX) <= 0.5`。组合布局测试继续精确断言 layout 类型是 `UICollectionViewCompositionalLayout`，源码仍包含：

```swift
section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
```

- [ ] **Step 2：实现 probe，保持业务配置不变**

在 `updateOwnershipProbe()` 只读并追加：

```swift
let inset = horizontalScrollView.adjustedContentInset
let minimumX = -inset.left
let maximumX = max(
    minimumX,
    horizontalScrollView.contentSize.width
        - horizontalScrollView.bounds.width
        + inset.right
)
let offsetX = horizontalScrollView.contentOffset.x
```

不得添加新的 delegate、timer 或 display link。组合布局页不发现内部 scroll、不写 orthogonal offset。

- [ ] **Step 3：把最终 UI 用例拆成稳定单责任测试**

保留 Task 3 两个门禁测试，并新增/改名为以下最终集合：

```swift
testHorizontalBusinessInteriorOwnsWholeGestureWithoutVerticalMovement()
testHorizontalBusinessTrailingBoundaryPagesOnNextOutwardGesture()
testHorizontalBusinessLeadingBoundaryPagesOnNextOutwardGesture()
testCompositionalOrthogonalInteriorOwnsWholeGesture()
testCompositionalOrthogonalLeadingBoundaryPagesOnNextOutwardGesture()
testCompositionalNonOrthogonalRegionUsesPageboyPaging()
```

每个测试都先 reset selection/state probe，只以真实 `didSelect` trace、页面 identifier、业务 offset/card frame 和 stable ownership 交叉判断。禁止用“目标页不存在”证明 Pageboy 没有获胜。

- [ ] **Step 4：运行 Example unit + 六项 UI GREEN**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleTests test

xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalBusinessInteriorOwnsWholeGestureWithoutVerticalMovement \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalBusinessTrailingBoundaryPagesOnNextOutwardGesture \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalBusinessLeadingBoundaryPagesOnNextOutwardGesture \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalOrthogonalInteriorOwnsWholeGesture \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalOrthogonalLeadingBoundaryPagesOnNextOutwardGesture \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalNonOrthogonalRegionUsesPageboyPaging test
```

Expected: Example unit 全过；UI 6/6、0 skip。每个边缘用例必须先证明“到边缘的当前手势未切页”，再证明下一笔 outward drag 产生唯一 matching terminal。

- [ ] **Step 5：自审并提交**

```bash
git diff --check
git add Examples/AnchorPagerExample
git commit -m "验收横向业务边缘分页语义"
```

自审：原生 orthogonal 行未变化；probe 只读；横向业务页仍 nil 纵向 target；组合页根 CollectionView 仍唯一纵向 target。

---

### Task 6：验收 reload、surface replacement、系统返回与资源释放

**Files:**
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: Task 3 的 gate lifecycle、Task 4 的零静态策略、Task 5 的 probe。
- Produces: replacement/deinit 无泄漏证据，以及 interactive-pop/reload 后自动路由仍工作的最终回归证据。

- [ ] **Step 1：写资源与 replacement RED**

扩展 Observation 测试：持有 weak first gate；replacement 后断言 first gate 已从 view 移除，释放 first page/surface 后 weak gate 为 nil；`invalidate()` 两次不重复 remove。扩展 ViewController 测试：empty reload 删除 Adapter 后 `gesturePriorityCoordinatorForTesting` 的 paging pan/gate 都为 nil；非空 replacement 后关系只指向新 pair。

- [ ] **Step 2：补齐最小清理实现并跑 Framework GREEN**

只有 RED 暴露真实缺口时才改生产代码。允许的修复仅限：Observation 同步 remove gate、Coordinator 清弱绑定、Adapter `prepareForRemoval()` 既有 invalidate 时序。不得增加 delay、Task、手势 reset 或业务引用。

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerTests/AnchorPagerPagingSurfaceObservationTests \
  -only-testing:AnchorPagerTests/AnchorPagerGesturePriorityCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

- [ ] **Step 3：新增 reload 后 orthogonal 路由与 interactive-pop UI 回归**

扩展现有 `testCompositionalReloadRebindsRootVerticalTarget`：reload generation 2 后先建立 orthogonal interior offset，再回 leading，下一手势提交 index 4；旧 generation view 不存在，ownership probe 保持稳定。复跑 `testLeadingEdgeInteractivePopWinsOverPageboyPaging`，其起点分别覆盖普通内容和横向业务区域，navigation pop 成功且 selection trace 不变。

- [ ] **Step 4：运行相邻 UI 矩阵并提交**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalReloadRebindsRootVerticalTarget \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testLeadingEdgeInteractivePopWinsOverPageboyPaging \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testCompositionalVerticalRegionHandsOffToCollectionView \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalBusinessRegionDoesNotDriveVerticalContainer test
git diff --check
git add Sources/AnchorPager Tests/AnchorPagerTests Examples/AnchorPagerExample/AnchorPagerExampleUITests
git commit -m "验收横向路由重载与资源生命周期"
```

Expected: UI 4/4、0 skip；Framework 聚焦全过；无旧 gate/surface/page retain。

---

### Task 7：迁移文档、全量门禁与 fresh-pass

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md`
- Modify: `docs/superpowers/specs/2026-07-16-compositional-layout-mixed-axis-gesture-validation-design.md`
- Modify: `docs/superpowers/specs/2026-07-16-next-gesture-horizontal-boundary-paging-design.md`
- Modify: `docs/superpowers/plans/2026-07-16-compositional-layout-mixed-axis-gesture-validation.md`
- Modify: `docs/superpowers/plans/2026-07-16-next-gesture-horizontal-boundary-paging.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Tasks 1–6 的真实提交和 xcresult 证据。
- Produces: 当前生产事实、最终测试计数、Known Limitations、版本门禁和 fresh-pass 结论。

- [ ] **Step 1：先迁移接入文档与历史状态**

README 删除旧 Bool 示例，改为：普通页面零配置；命中横向业务 scroll 时框架自动判断；当前手势中途到边缘不接力；下一次 outward drag Pageboy；Compositional Layout 保持原生 orthogonal；系统层级变化仍由真实 UI 版本门禁保障。

历史 Compositional spec/plan 保留原完成记录，在顶部追加“已由下一手势自动边界路由专项取代”的终态链接，不重写旧 RED/GREEN 步骤。Architecture 删除“当前生产静态 Bool”段，替换为最终 route gate 数据流、失败关系、命中链、纯模型和 lifecycle。Task-list 只勾选真实完成项。

- [ ] **Step 2：运行源码边界扫描**

```bash
rg -n 'allowsInteractiveHorizontalPagingAt|interactiveHorizontalPagingPermissions|setInteractiveHorizontalPagingEnabled|paging\.interactivePaging\.' Sources Tests Examples README.md docs/architecture.md docs/task-list.md AGENTS.md
rg -n 'import (Tabman|Pageboy)' Sources/AnchorPager/Public
rg -n '\.delegate\s*=|contentOffset\s*=|isScrollEnabled\s*=|\.bounces\s*=' Sources/AnchorPager/Gesture Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift
rg -n '_UI|UIQueuingScrollView|setValue\(|value\(forKey:' Sources/AnchorPager
```

Expected: 第一、二、四条零命中；第三条只允许 route gate 自身 delegate 与既有明确合法代码，逐条人工解释。历史 specs/plans 可保留旧符号，不能误报为当前 API。

- [ ] **Step 3：运行 Framework 全量**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/AnchorPagerHorizontalBoundaryFrameworkFull.xcresult test
```

Expected: 全部 PASS、0 fail、0 skip。

- [ ] **Step 4：运行 Example 全量与 generic build**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/AnchorPagerHorizontalBoundaryExampleFull.xcresult test

xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -resultBundlePath /private/tmp/AnchorPagerHorizontalBoundaryBuild.xcresult build
```

Expected: Example unit/UI 全部 PASS、0 skip；generic build 成功。

- [ ] **Step 5：查询 xcresult 与运行时问题**

依次运行：

```bash
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerHorizontalBoundaryFrameworkFull.xcresult
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerHorizontalBoundaryExampleFull.xcresult
xcrun xcresulttool get build-results --path /private/tmp/AnchorPagerHorizontalBoundaryBuild.xcresult
xcrun xcresulttool get log --path /private/tmp/AnchorPagerHorizontalBoundaryExampleFull.xcresult --type console
```

前两项记录测试计数和 0 failure；build result 确认 0 error、0 warning、0 analyzer warning。检查最后一项控制台输出中的 `LayoutConstraints`、`gesture recognizer` + `cycle`、`Unbalanced calls`、`deallocated while`、`Main Thread Checker` 和 allocator 错误，预期零命中。

- [ ] **Step 6：完成 fresh-pass 自审**

逐项检查：Public API 删除是否完整；Tabman/Pageboy 类型是否仍只在 internal；gate 是否只读业务 scroll；Pageboy containment/lifecycle；Host/Store generation；纵向 inset/offset/overscroll；interactive-pop；reload/surface replacement/deinit；日志隐私与频率；Example 原生 orthogonal；测试是否覆盖双物理边界和“同手势不接力”。发现 Critical/Important 必须先 RED/GREEN 修复并复跑受影响全量；Minor 同步文档后再形成终态。

- [ ] **Step 7：记录真实计数、提交最终状态**

把实际 HEAD、Framework/Example 计数、xcresult 路径、warning/runtime 查询和 fresh-pass 结论写回设计、计划、task-list、architecture、README 与 AGENTS。

```bash
git diff --check
git status --short
git add README.md AGENTS.md docs
git commit -m "完成横向边缘分页接力验收"
```

完成标准：工作区无未解释改动；设计中的 8 项完成定义全部满足；只有此时才把专项状态改为 Ready。

## 计划自审记录

1. **Spec coverage：** Tasks 1–2 覆盖纯边界和 gate；Task 3 覆盖真实 UIKit 停止门禁；Task 4 覆盖 Public/metadata/Host/Adapter 删除；Task 5 覆盖普通横向双边与原生 orthogonal；Task 6 覆盖 reload、surface、interactive-pop 和资源；Task 7 覆盖日志、完整回归、文档与 fresh-pass。设计中的 Public、containment、discovery/inset、paging、gesture/overscroll、日志、测试、Example 和文档影响面均有明确任务。
2. **停止条件：** Task 3 在任何 Public 删除前验证普通 scroll 与原生 orthogonal；失败路径明确要求清理未提交装配并停止，不允许私有 API、delegate proxy、Pageboy fork 或 offset 注入。
3. **类型一致性：** `Geometry`、`Decision`、`AnchorPagerHorizontalPagingRouteGate`、`Surface.routeGateGestureRecognizer` 和 `bindHorizontalRouteGate(_:)` 在首次产生后保持同名；后续任务没有引入页面协议或第二套路由类型。
4. **真实 UI 可达性：** index 4 同时有上一页和下一页，承担双物理边缘提交；index 5 是末页，只验证存在相邻页的 leading 边缘，trailing 由纯模型和 index 4 真实 UI 共同覆盖，不再要求不存在的 next terminal。
5. **历史与当前事实：** 旧 Compositional plan 作为已完成历史保留；只有新专项全量通过后，长期文档才从静态 Bool 迁移到自动 route gate。
