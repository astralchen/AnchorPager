# v0.5 纵向滚动协调实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Header container 与 committed current child 的连续纵向 handoff，同时保留业务 child 的 `UIScrollView.delegate` 与 pan delegate，并以真实 simulator drag 验收唯一滚动 owner。

**Architecture:** 纯 `AnchorPagerScrollPositionResolver` 从 pan 起点计算 canonical total，再把位置分配到 container/child；internal `AnchorPagerContainerScrollView` 由子类自身只放行 committed current child pan，不设置任何内建 pan delegate；`AnchorPagerChildScrollBinding` 只用 KVO 与 target-action 观察 child。MainActor `AnchorPagerScrollCoordinator` 组合三者，并由 `AnchorPagerViewController` 在 committed reload/selection terminal 后同步重绑定，不读取 provider pending、不写 managed inset、不接管 page identity。

**Tech Stack:** Swift 6.2+、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、XCTest、XCUITest、Tabman 4.0.1、Pageboy 5.0.2。

**当前状态：** Ready；Task 1–7、plain direct page 和 boundary owner 修订均已实现，前三轮复审问题均已修复；第四次整分支独立复审 Critical 0、Important 0，两个 Minor 已在最终状态提交中修复。

## Global Constraints

- Package、Library product、Module 均保持 `AnchorPager`。
- 最低工具链 Swift 6.2，语言模式 Swift 6，最低系统 iOS 14，UI stack UIKit。
- Tabman/Pageboy 只存在于 internal adapter 层，不进入 public API。
- 横向业务 page containment 与 appearance 继续由 Pageboy/UIKit 执行。
- AnchorPager 任何时候都不得设置业务 child 的 `UIScrollView.delegate`，包括临时替换、forwarding proxy、保存后恢复和测试注入。
- AnchorPager 不得替换业务 child 的 `panGestureRecognizer.delegate`。
- simultaneous recognition 只通过自有 container `UIScrollView` 子类放行 committed current child pair；禁止设置 container 或 child 的内建 `panGestureRecognizer.delegate`。
- ScrollCoordinator 只读 Store committed current/empty，不读取 provider pending，不缓存 Host/Adapter/provider，不复制 generation/cache/snapshot/inset ownership。
- 所有 UIKit、coordinator、data source 和 delegate 路径保持 `@MainActor`；不使用 `Task.detached`、`@unchecked Sendable`、`nonisolated(unsafe)` 或 `@preconcurrency`。
- 不通过切换 `isScrollEnabled`、timer、dispatch delay、重复 layout 或强制 reset 掩盖 handoff 问题。
- 历史 Task 1–6 曾临时约定顶部额外下拉只保留 container 原生 bounce、child 固定顶部；该规则已由 v0.6 双边界回弹实现取代，当前实现按 public mode 路由顶部 owner。
- v0.5 不做跨 owner 惯性合成；完整 `verticalDecelerating` interaction state 留给 v0.7。
- 高频 pan/KVO/scroll callback 不逐帧输出普通日志。
- 每个任务完成后先自审再提交；涉及 UI 的任务必须提供真实 simulator 手势测试。

---

## 文件结构

新增文件：

```text
Sources/AnchorPager/Core/AnchorPagerScrollPositionResolver.swift
Sources/AnchorPager/Gesture/AnchorPagerContainerScrollView.swift
Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift
Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift
Sources/AnchorPager/Core/AnchorPagerVerticalScrollDelegate.swift
Tests/AnchorPagerTests/AnchorPagerScrollPositionResolverTests.swift
Tests/AnchorPagerTests/AnchorPagerContainerScrollViewTests.swift
Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift
Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift
```

修改文件：

```text
Sources/AnchorPager/Public/AnchorPagerViewController.swift
Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift
Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
README.md
docs/architecture.md
docs/task-list.md
docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md
docs/superpowers/specs/2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md
docs/superpowers/specs/2026-07-13-v0-5-scroll-coordination-design.md
docs/superpowers/plans/2026-07-13-v0-5-scroll-coordination.md
```

---

### Task 1: Canonical total 纯位置解析器

**Files:**
- Create: `Sources/AnchorPager/Core/AnchorPagerScrollPositionResolver.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerScrollPositionResolverTests.swift`

**Interfaces:**
- Consumes: pan 起点 total、起点/当前 translation、collapsible distance、child 最大 distance、稳定 fallback pair。
- Produces: `AnchorPagerScrollPositionResolver.Position` 与 `resolve(_:)`，供 Task 4 的 ScrollCoordinator 使用。

- [x] **Step 1: 写完整 RED 测试**

```swift
import XCTest
@testable import AnchorPager

final class AnchorPagerScrollPositionResolverTests: XCTestCase {
    func testUpwardTranslationDistributesAcrossContainerAndChildWithoutDroppingDelta() {
        let result = AnchorPagerScrollPositionResolver.resolve(.init(
            gestureStartTotal: 80,
            gestureStartTranslationY: 0,
            currentTranslationY: -70,
            containerCollapsedOffset: 100,
            childMaximumDistance: 500,
            fallback: .init(containerOffset: 80, childDistance: 0)
        ))
        XCTAssertEqual(result, .init(containerOffset: 100, childDistance: 50))
    }

    func testDownwardTranslationConsumesChildBeforeExpandingContainer() {
        let result = AnchorPagerScrollPositionResolver.resolve(.init(
            gestureStartTotal: 180,
            gestureStartTranslationY: 0,
            currentTranslationY: 130,
            containerCollapsedOffset: 100,
            childMaximumDistance: 500,
            fallback: .init(containerOffset: 100, childDistance: 80)
        ))
        XCTAssertEqual(result, .init(containerOffset: 50, childDistance: 0))
    }

    func testShortChildClampsDistanceToZero() {
        let result = AnchorPagerScrollPositionResolver.resolve(.init(
            gestureStartTotal: 100,
            gestureStartTranslationY: 0,
            currentTranslationY: -90,
            containerCollapsedOffset: 100,
            childMaximumDistance: 0,
            fallback: .init(containerOffset: 100, childDistance: 0)
        ))
        XCTAssertEqual(result, .init(containerOffset: 100, childDistance: 0))
    }

    func testNonFiniteInputReturnsStableFallback() {
        let fallback = AnchorPagerScrollPositionResolver.Position(
            containerOffset: 40,
            childDistance: 0
        )
        let result = AnchorPagerScrollPositionResolver.resolve(.init(
            gestureStartTotal: .nan,
            gestureStartTranslationY: 0,
            currentTranslationY: 0,
            containerCollapsedOffset: 100,
            childMaximumDistance: 500,
            fallback: fallback
        ))
        XCTAssertEqual(result, fallback)
    }

    func testChildMaximumDistanceIncludesContentInsets() {
        XCTAssertEqual(
            AnchorPagerScrollPositionResolver.childMaximumDistance(
                contentSizeHeight: 900,
                boundsHeight: 600,
                contentInsetTop: 50,
                contentInsetBottom: 30
            ),
            380
        )
    }
}
```

- [x] **Step 2: 运行测试并确认 RED**

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerScrollPositionResolverTests test
```

Expected: 编译失败，提示找不到 `AnchorPagerScrollPositionResolver`。

- [x] **Step 3: 实现纯解析器**

```swift
import CoreGraphics

struct AnchorPagerScrollPositionResolver {
    struct Position: Equatable {
        var containerOffset: CGFloat
        var childDistance: CGFloat
    }

    struct Input {
        var gestureStartTotal: CGFloat
        var gestureStartTranslationY: CGFloat
        var currentTranslationY: CGFloat
        var containerCollapsedOffset: CGFloat
        var childMaximumDistance: CGFloat
        var fallback: Position
    }

    static func resolve(_ input: Input) -> Position {
        let values = [
            input.gestureStartTotal,
            input.gestureStartTranslationY,
            input.currentTranslationY,
            input.containerCollapsedOffset,
            input.childMaximumDistance
        ]
        guard values.allSatisfy(\.isFinite) else { return input.fallback }

        let collapsedOffset = max(0, input.containerCollapsedOffset)
        let childMaximumDistance = max(0, input.childMaximumDistance)
        let upwardDelta = input.gestureStartTranslationY - input.currentTranslationY
        let desiredTotal = min(
            max(0, input.gestureStartTotal + upwardDelta),
            collapsedOffset + childMaximumDistance
        )
        return Position(
            containerOffset: min(desiredTotal, collapsedOffset),
            childDistance: max(0, desiredTotal - collapsedOffset)
        )
    }

    static func childMaximumDistance(
        contentSizeHeight: CGFloat,
        boundsHeight: CGFloat,
        contentInsetTop: CGFloat,
        contentInsetBottom: CGFloat
    ) -> CGFloat {
        let values = [contentSizeHeight, boundsHeight, contentInsetTop, contentInsetBottom]
        guard values.allSatisfy(\.isFinite) else { return 0 }
        return max(0, contentSizeHeight + contentInsetTop + contentInsetBottom - boundsHeight)
    }
}
```

- [x] **Step 4: 运行解析器测试并确认 GREEN**

Run: Task 1 Step 2 的同一命令。

Expected: 5 tests，0 failures。

- [x] **Step 5: 自审并提交**

确认文件只 import CoreGraphics、不绑定 MainActor、不出现 UIKit/Tabman/Pageboy、所有非有限输入有确定降级。

实际结果（2026-07-13，Swift 6.3.3 / iPhone 17）：RED 因目标类型不存在而失败；GREEN 5 项通过，0 fail。

```bash
git diff --check
git add Sources/AnchorPager/Core/AnchorPagerScrollPositionResolver.swift \
  Tests/AnchorPagerTests/AnchorPagerScrollPositionResolverTests.swift
git commit -m "实现纵向滚动位置解析器"
```

---

### Task 2: Container scroll view simultaneous recognition 边界

**Files:**
- Create: `Sources/AnchorPager/Gesture/AnchorPagerContainerScrollView.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerContainerScrollViewTests.swift`

**Interfaces:**
- Consumes: AnchorPager 自有 container scroll view 与 Store committed current child pan。
- Produces: `AnchorPagerContainerScrollView.bindCurrentChildPan(_:)`；scroll view 子类自身只允许 container/current child pair simultaneous，绝不设置 container 或 child pan delegate。

- [x] **Step 1: 保留 UIKit 失败证据并删除错误 proxy RED**

已执行原计划 proxy 测试，5/5 均稳定抛出：

```text
UIScrollView's built-in pan gesture recognizer must have its scroll view as its delegate.
```

删除错误生产文件与测试，禁止通过捕获异常、KVC 或其他未公开入口绕过 UIKit 不变量。

- [x] **Step 2: 写 container 子类完整 RED 测试**

```swift
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerContainerScrollViewTests: XCTestCase {
    func testOnlyCommittedContainerChildPairRecognizesSimultaneously() {
        let container = AnchorPagerContainerScrollView()
        let child = UIScrollView()
        let unrelated = UIPanGestureRecognizer()
        container.bindCurrentChildPan(child.panGestureRecognizer)

        XCTAssertTrue(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: child.panGestureRecognizer
        ))
        XCTAssertFalse(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: unrelated
        ))
        XCTAssertFalse(container.gestureRecognizer(
            child.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: unrelated
        ))
    }

    func testRebindRejectsOldChildAndNilRemovesPair() {
        let container = AnchorPagerContainerScrollView()
        let oldChild = UIScrollView()
        let currentChild = UIScrollView()
        container.bindCurrentChildPan(oldChild.panGestureRecognizer)
        container.bindCurrentChildPan(currentChild.panGestureRecognizer)

        XCTAssertFalse(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: oldChild.panGestureRecognizer
        ))
        XCTAssertTrue(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: currentChild.panGestureRecognizer
        ))
        container.bindCurrentChildPan(nil)
        XCTAssertFalse(container.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: currentChild.panGestureRecognizer
        ))
    }

    func testBindingNeverChangesContainerOrChildPanDelegateIdentity() {
        let container = AnchorPagerContainerScrollView()
        let child = UIScrollView()
        let originalContainerDelegate = container.panGestureRecognizer.delegate
        let originalChildDelegate = child.panGestureRecognizer.delegate

        container.bindCurrentChildPan(child.panGestureRecognizer)
        container.bindCurrentChildPan(nil)

        XCTAssertTrue(container.panGestureRecognizer.delegate === originalContainerDelegate)
        XCTAssertTrue(child.panGestureRecognizer.delegate === originalChildDelegate)
    }

    func testUIKitPanDelegateDispatchesToContainerSubclassMethod() {
        let container = AnchorPagerContainerScrollView()
        let child = UIScrollView()
        container.bindCurrentChildPan(child.panGestureRecognizer)

        XCTAssertTrue(container.panGestureRecognizer.delegate === container)
        XCTAssertEqual(
            container.panGestureRecognizer.delegate?.gestureRecognizer?(
                container.panGestureRecognizer,
                shouldRecognizeSimultaneouslyWith: child.panGestureRecognizer
            ),
            true
        )
    }
}
```

- [x] **Step 3: 运行测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerContainerScrollViewTests test
```

Expected: 编译失败，提示找不到 `AnchorPagerContainerScrollView`。

- [x] **Step 4: 实现 container scroll view 子类**

```swift
import UIKit

@MainActor
final class AnchorPagerContainerScrollView: UIScrollView, UIGestureRecognizerDelegate {
    private weak var currentChildPan: UIPanGestureRecognizer?

    func bindCurrentChildPan(_ pan: UIPanGestureRecognizer?) {
        guard currentChildPan !== pan else { return }
        currentChildPan = pan
        if pan != nil {
            AnchorPagerLogger.log(
                .info,
                category: .gesture,
                event: "gesture.simultaneous.enabled"
            )
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let currentChildPan else { return false }
        return (gestureRecognizer === panGestureRecognizer
            && otherGestureRecognizer === currentChildPan)
            || (gestureRecognizer === currentChildPan
                && otherGestureRecognizer === panGestureRecognizer)
    }
}
```

- [x] **Step 5: 运行子类与日志回归**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerContainerScrollViewTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
```

Expected: 全部通过，0 failures；UIKit 实际 pan delegate 仍为 container，child pan delegate identity 不变。

Actual: RED 因找不到 `AnchorPagerContainerScrollView` 失败；首次最小实现的直接方法测试通过，但 UIKit optional protocol dispatch 返回 nil。与 JXPagingView 对照后补充显式 `UIGestureRecognizerDelegate` 声明，最终 container 5 tests + logger 6 tests，共 11 tests，0 failures；新增 sink 测试确认相同 pair 幂等绑定只记录一次 `gesture.simultaneous.enabled`。

- [x] **Step 6: 自审并提交**

确认生产代码不存在 `.panGestureRecognizer.delegate =`，只通过子类方法建立 committed pair；Public API 尚未改变，Task 5 再把该 internal 实例装入 `verticalScrollView`。

```bash
git diff --check
git add Sources/AnchorPager/Gesture/AnchorPagerContainerScrollView.swift \
  Tests/AnchorPagerTests/AnchorPagerContainerScrollViewTests.swift
git commit -m "建立容器纵向手势识别边界"
```

---

### Task 3: Child observation binding，不占用 UIScrollView.delegate

**Files:**
- Create: `Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift`

**Interfaces:**
- Consumes: Store committed current `UIScrollView?`。
- Produces: `AnchorPagerChildScrollBinding`，通过 KVO/target-action发出 offset、contentSize 和 pan state，提供同步 `invalidate()`。

- [x] **Step 1: 写 RED 测试**

```swift
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerChildScrollBindingTests: XCTestCase {
    func testBindingPreservesBusinessScrollAndPanDelegates() {
        let scrollView = UIScrollView()
        let scrollDelegate = RecordingScrollDelegate()
        scrollView.delegate = scrollDelegate
        let originalPanDelegate = scrollView.panGestureRecognizer.delegate

        let binding = AnchorPagerChildScrollBinding(
            scrollView: scrollView,
            token: 1,
            onContentOffsetChanged: { _ in },
            onContentSizeChanged: { _ in },
            onPan: { _, _ in }
        )
        binding.invalidate()

        XCTAssertTrue(scrollView.delegate === scrollDelegate)
        XCTAssertTrue(scrollView.panGestureRecognizer.delegate === originalPanDelegate)
    }

    func testBindingReportsOffsetContentSizeAndPanWithoutDelegateWrites() {
        let scrollView = UIScrollView()
        var offsets: [CGPoint] = []
        var sizes: [CGSize] = []
        let binding = AnchorPagerChildScrollBinding(
            scrollView: scrollView,
            token: 7,
            onContentOffsetChanged: { offsets.append($0) },
            onContentSizeChanged: { sizes.append($0) },
            onPan: { _, _ in }
        )

        scrollView.contentOffset = CGPoint(x: 0, y: 20)
        scrollView.contentSize = CGSize(width: 320, height: 900)

        XCTAssertEqual(offsets.last?.y, 20)
        XCTAssertEqual(sizes.last?.height, 900)
        binding.invalidate()
    }

    func testInvalidatedBindingIgnoresLaterChanges() {
        let scrollView = UIScrollView()
        var callbackCount = 0
        let binding = AnchorPagerChildScrollBinding(
            scrollView: scrollView,
            token: 2,
            onContentOffsetChanged: { _ in callbackCount += 1 },
            onContentSizeChanged: { _ in callbackCount += 1 },
            onPan: { _, _ in callbackCount += 1 }
        )
        binding.invalidate()
        scrollView.contentOffset.y = 30
        scrollView.contentSize.height = 800
        XCTAssertEqual(callbackCount, 0)
    }
}
```

- [x] **Step 2: 运行测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerChildScrollBindingTests test
```

Expected: 编译失败，提示找不到 binding 类型。

- [x] **Step 3: 实现 binding**

```swift
import UIKit

@MainActor
final class AnchorPagerChildScrollBinding: NSObject {
    let token: Int
    private weak var scrollView: UIScrollView?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    private var onContentOffsetChanged: ((CGPoint) -> Void)?
    private var onContentSizeChanged: ((CGSize) -> Void)?
    private var onPan: ((UIGestureRecognizer.State, CGFloat) -> Void)?
    private var isValid = true

    init(
        scrollView: UIScrollView,
        token: Int,
        onContentOffsetChanged: @escaping (CGPoint) -> Void,
        onContentSizeChanged: @escaping (CGSize) -> Void,
        onPan: @escaping (UIGestureRecognizer.State, CGFloat) -> Void
    ) {
        self.scrollView = scrollView
        self.token = token
        self.onContentOffsetChanged = onContentOffsetChanged
        self.onContentSizeChanged = onContentSizeChanged
        self.onPan = onPan
        super.init()
        contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, change in
            guard let self, self.isValid, let value = change.newValue else { return }
            MainActor.assumeIsolated { self.onContentOffsetChanged?(value) }
        }
        contentSizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, change in
            guard let self, self.isValid, let value = change.newValue else { return }
            MainActor.assumeIsolated { self.onContentSizeChanged?(value) }
        }
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
    }

    func invalidate() {
        guard isValid else { return }
        isValid = false
        if let scrollView {
            scrollView.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
        }
        contentOffsetObservation?.invalidate()
        contentSizeObservation?.invalidate()
        contentOffsetObservation = nil
        contentSizeObservation = nil
        onContentOffsetChanged = nil
        onContentSizeChanged = nil
        onPan = nil
        AnchorPagerLogger.log(
            .debug,
            category: .resource,
            event: "resource.scrollObservation.release"
        )
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard isValid else { return }
        onPan?(pan.state, pan.translation(in: pan.view).y)
    }
}
```

若 Swift 6 对 KVO closure 隔离产生诊断，只允许把 closure 内容同步桥接到 `MainActor.assumeIsolated`；不得给类型增加 unsafe Sendable 标记或异步 Task。

- [x] **Step 4: 增加生产源码禁止项测试并运行 GREEN**

把以下测试加入 `AnchorPagerChildScrollBindingTests`：

```swift
func testBindingSourceNeverAssignsOrStoresBusinessScrollDelegate() throws {
    let testURL = URL(fileURLWithPath: #filePath)
    let packageRoot = testURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = packageRoot
        .appendingPathComponent("Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let normalized = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")

    XCTAssertFalse(normalized.contains("scrollView.delegate ="))
    XCTAssertFalse(normalized.contains("originalScrollDelegate"))
    XCTAssertFalse(normalized.contains("savedScrollDelegate"))
}
```

Run: Task 3 Step 2 命令。

Expected: 3+ tests，0 failures。

Actual: RED 因找不到 `AnchorPagerChildScrollBinding` 失败；GREEN 中 binding 5 tests + logger 6 tests，共 11 tests，0 failures。测试额外确认 `invalidate()` 幂等且只记录一次 `resource.scrollObservation.release`，生产源码不存在 scroll/pan delegate 写入或保存路径。

- [x] **Step 5: 自审并提交**

确认 invalidation 顺序是先失效、再移除 target、最后 invalidate KVO；不保存 child delegate；旧 callback 无法穿透 token/resource 生命周期。

```bash
git diff --check
git add Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift \
  Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift
git commit -m "添加子页面滚动只读绑定"
```

---

### Task 4: ScrollCoordinator owner、handoff、bounce 与日志

**Files:**
- Create: `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift`

**Interfaces:**
- Consumes: Task 1 resolver、Task 2 `AnchorPagerContainerScrollView`、Task 3 binding、committed child `UIScrollView?`。
- Produces: `updateGeometry(collapsibleDistance:)`、`bindCommittedChild(_:)`、`containerDidScroll()`、`handlePan(state:translationY:)`、`invalidate()`。

- [x] **Step 1: 写 coordinator RED 测试**

```swift
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerScrollCoordinatorTests: XCTestCase {
    func testUpwardPanCollapsesContainerThenScrollsChild() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)
        XCTAssertEqual(fixture.container.contentOffset.y, 100, accuracy: 0.001)
        XCTAssertEqual(fixture.child.contentOffset.y + fixture.child.contentInset.top, 50, accuracy: 0.001)
    }

    func testDownwardPanReturnsChildThenExpandsContainer() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = 100
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 80
        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: 130)
        XCTAssertEqual(fixture.child.contentOffset.y, -fixture.child.contentInset.top, accuracy: 0.001)
        XCTAssertEqual(fixture.container.contentOffset.y, 50, accuracy: 0.001)
    }

    func testExpandedTopBouncePinsChildAndKeepsContainerNegativeOffset() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.container.contentOffset.y = -24
        fixture.child.contentOffset.y = -fixture.child.contentInset.top - 12
        fixture.coordinator.containerDidScroll()
        XCTAssertEqual(fixture.container.contentOffset.y, -24, accuracy: 0.001)
        XCTAssertEqual(fixture.child.contentOffset.y, -fixture.child.contentInset.top, accuracy: 0.001)
    }

    func testSameChildRebindIsIdempotentAndDifferentChildInvalidatesOldBinding() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        let replacement = fixture.makeChild(maximumDistance: 300)
        fixture.coordinator.bindCommittedChild(fixture.child)
        fixture.coordinator.bindCommittedChild(replacement)
        fixture.child.contentOffset.y = -fixture.child.contentInset.top + 90
        XCTAssertEqual(replacement.contentOffset.y, -replacement.contentInset.top, accuracy: 0.001)
    }

    func testEmptyCommitBindsNilAndLeavesContainerSafe() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        fixture.coordinator.bindCommittedChild(nil)
        fixture.container.contentOffset.y = 60
        fixture.coordinator.containerDidScroll()
        XCTAssertEqual(fixture.container.contentOffset.y, 60, accuracy: 0.001)
    }

    func testGuardedWritesDoNotReenter() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)
        XCTAssertEqual(events.filter { $0.event == "scroll.offset.guard.apply" }.count, 1)
        XCTAssertLessThanOrEqual(
            events.filter { $0.event == "scroll.offset.guard.skip" }.count,
            2
        )
    }

    func testOwnerAndBoundaryLogsOnlyEmitOnStateChanges() {
        let fixture = Fixture(collapsedOffset: 100, childMaximumDistance: 500)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        fixture.coordinator.handlePan(state: .began, translationY: 0)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)
        fixture.coordinator.handlePan(state: .changed, translationY: -150)
        XCTAssertEqual(events.filter { $0.event == "scroll.owner.child" }.count, 1)
        XCTAssertEqual(events.filter { $0.event == "scroll.boundary.collapsed" }.count, 1)
    }
}

@MainActor
private final class Fixture {
    let container = AnchorPagerContainerScrollView()
    let child: UIScrollView
    let coordinator: AnchorPagerScrollCoordinator

    init(collapsedOffset: CGFloat, childMaximumDistance: CGFloat) {
        child = UIScrollView()
        container.bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        child.bounds = CGRect(x: 0, y: 0, width: 320, height: 600)
        child.contentInset = UIEdgeInsets(top: 50, left: 0, bottom: 0, right: 0)
        child.contentSize = CGSize(width: 320, height: 550 + childMaximumDistance)
        child.contentOffset.y = -child.contentInset.top
        coordinator = AnchorPagerScrollCoordinator(containerScrollView: container)
        coordinator.updateGeometry(collapsibleDistance: collapsedOffset)
        coordinator.bindCommittedChild(child)
    }

    func makeChild(maximumDistance: CGFloat) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.bounds = child.bounds
        scrollView.contentInset = child.contentInset
        scrollView.contentSize = CGSize(width: 320, height: 550 + maximumDistance)
        scrollView.contentOffset.y = -scrollView.contentInset.top
        return scrollView
    }
}
```

- [x] **Step 2: 运行测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests test
```

Expected: 编译失败，提示找不到 coordinator 类型。

- [x] **Step 3: 实现 coordinator 固定接口**

```swift
import UIKit

@MainActor
final class AnchorPagerScrollCoordinator {
    enum Owner: Equatable { case container, child }

    private let containerScrollView: AnchorPagerContainerScrollView
    private var childBinding: AnchorPagerChildScrollBinding?
    private weak var committedChildScrollView: UIScrollView?
    private var bindingToken = 0
    private var collapsibleDistance: CGFloat = 0
    private var gestureStartTotal: CGFloat?
    private var gestureStartTranslationY: CGFloat = 0
    private var isApplyingGuardedOffsets = false
    private(set) var owner: Owner = .container

    init(containerScrollView: AnchorPagerContainerScrollView) {
        self.containerScrollView = containerScrollView
        containerScrollView.panGestureRecognizer.addTarget(
            self,
            action: #selector(handleContainerPan(_:))
        )
    }

    func updateGeometry(collapsibleDistance: CGFloat) {
        self.collapsibleDistance = max(0, collapsibleDistance.isFinite ? collapsibleDistance : 0)
        settleStableOffsets()
    }

    func bindCommittedChild(_ scrollView: UIScrollView?) {
        guard committedChildScrollView !== scrollView else { return }
        childBinding?.invalidate()
        childBinding = nil
        committedChildScrollView = scrollView
        containerScrollView.bindCurrentChildPan(scrollView?.panGestureRecognizer)
        bindingToken &+= 1
        guard let scrollView else { return }
        let token = bindingToken
        childBinding = AnchorPagerChildScrollBinding(
            scrollView: scrollView,
            token: token,
            onContentOffsetChanged: { [weak self] _ in self?.childDidChange(token: token) },
            onContentSizeChanged: { [weak self] _ in self?.childDidChange(token: token) },
            onPan: { [weak self] state, _ in
                self?.childPanStateDidChange(state: state, token: token)
            }
        )
        settleStableOffsets()
    }

    func containerDidScroll() {
        guard !isApplyingGuardedOffsets else { return }
        if containerScrollView.contentOffset.y < 0 {
            pinChildToTop()
        } else {
            settleStableOffsets()
        }
    }

    func handlePan(state: UIGestureRecognizer.State, translationY: CGFloat) {
        switch state {
        case .began:
            gestureStartTotal = currentCanonicalTotal()
            gestureStartTranslationY = translationY
        case .changed:
            guard let gestureStartTotal else { return }
            apply(AnchorPagerScrollPositionResolver.resolve(.init(
                gestureStartTotal: gestureStartTotal,
                gestureStartTranslationY: gestureStartTranslationY,
                currentTranslationY: translationY,
                containerCollapsedOffset: collapsibleDistance,
                childMaximumDistance: childMaximumDistance,
                fallback: currentStablePosition()
            )))
        case .ended, .cancelled, .failed:
            gestureStartTotal = nil
            settleStableOffsets()
        default:
            break
        }
    }

    func invalidate() {
        bindingToken &+= 1
        childBinding?.invalidate()
        childBinding = nil
        committedChildScrollView = nil
        containerScrollView.bindCurrentChildPan(nil)
        containerScrollView.panGestureRecognizer.removeTarget(
            self,
            action: #selector(handleContainerPan(_:))
        )
    }
}
```

在同一类型内加入以下 helpers：

```swift
private let epsilon: CGFloat = 0.001

private var childTopOffset: CGFloat {
    guard let committedChildScrollView else { return 0 }
    return -committedChildScrollView.contentInset.top
}

private var childMaximumDistance: CGFloat {
    guard let child = committedChildScrollView else { return 0 }
    return AnchorPagerScrollPositionResolver.childMaximumDistance(
        contentSizeHeight: child.contentSize.height,
        boundsHeight: child.bounds.height,
        contentInsetTop: child.contentInset.top,
        contentInsetBottom: child.contentInset.bottom
    )
}

private func currentStablePosition() -> AnchorPagerScrollPositionResolver.Position {
    let container = min(max(0, containerScrollView.contentOffset.y), collapsibleDistance)
    let childDistance = committedChildScrollView.map {
        min(max(0, $0.contentOffset.y + $0.contentInset.top), childMaximumDistance)
    } ?? 0
    return .init(containerOffset: container, childDistance: childDistance)
}

private func currentCanonicalTotal() -> CGFloat {
    let position = currentStablePosition()
    return position.containerOffset + position.childDistance
}

private func apply(_ position: AnchorPagerScrollPositionResolver.Position) {
    guard !isApplyingGuardedOffsets else {
        AnchorPagerLogger.log(.debug, category: .scroll, event: "scroll.offset.guard.skip")
        return
    }
    isApplyingGuardedOffsets = true
    defer { isApplyingGuardedOffsets = false }

    let nextOwner: Owner = position.childDistance > epsilon ? .child : .container
    let childTarget = childTopOffset + position.childDistance
    var didWrite = false
    let writeContainer = {
        if abs(self.containerScrollView.contentOffset.y - position.containerOffset) > self.epsilon {
            self.containerScrollView.contentOffset.y = position.containerOffset
            didWrite = true
        }
    }
    let writeChild = {
        guard let child = self.committedChildScrollView,
              abs(child.contentOffset.y - childTarget) > self.epsilon else { return }
        child.contentOffset.y = childTarget
        didWrite = true
    }
    if nextOwner == .child {
        writeContainer()
        writeChild()
    } else {
        writeChild()
        writeContainer()
    }
    transitionOwnerIfNeeded(to: nextOwner)
    if didWrite {
        AnchorPagerLogger.log(.debug, category: .scroll, event: "scroll.offset.guard.apply")
    }
}

private func settleStableOffsets() {
    if containerScrollView.contentOffset.y < 0 {
        pinChildToTop()
        return
    }
    let current = currentStablePosition()
    let normalized: AnchorPagerScrollPositionResolver.Position
    if current.childDistance > epsilon {
        normalized = .init(containerOffset: collapsibleDistance, childDistance: current.childDistance)
    } else {
        normalized = .init(containerOffset: current.containerOffset, childDistance: 0)
    }
    apply(normalized)
}

private func pinChildToTop() {
    guard let child = committedChildScrollView,
          abs(child.contentOffset.y - childTopOffset) > epsilon else { return }
    let containerOffset = containerScrollView.contentOffset.y
    isApplyingGuardedOffsets = true
    child.contentOffset.y = childTopOffset
    containerScrollView.contentOffset.y = containerOffset
    isApplyingGuardedOffsets = false
}

private func childDidChange(token: Int) {
    guard token == bindingToken else {
        AnchorPagerLogger.log(.debug, category: .scroll, event: "scroll.binding.stale")
        return
    }
    guard !isApplyingGuardedOffsets else {
        AnchorPagerLogger.log(.debug, category: .scroll, event: "scroll.offset.guard.skip")
        return
    }
    if containerScrollView.contentOffset.y < collapsibleDistance - epsilon {
        pinChildToTop()
        return
    }
    settleStableOffsets()
}

private func childPanStateDidChange(
    state: UIGestureRecognizer.State,
    token: Int
) {
    guard token == bindingToken else {
        AnchorPagerLogger.log(.debug, category: .scroll, event: "scroll.binding.stale")
        return
    }
    guard gestureStartTotal == nil,
          state == .ended || state == .cancelled || state == .failed else { return }
    settleStableOffsets()
}

private func transitionOwnerIfNeeded(to nextOwner: Owner) {
    guard owner != nextOwner else { return }
    owner = nextOwner
    AnchorPagerLogger.log(
        .info,
        category: .scroll,
        event: nextOwner == .container ? "scroll.owner.container" : "scroll.owner.child"
    )
}

@objc private func handleContainerPan(_ pan: UIPanGestureRecognizer) {
    handlePan(state: pan.state, translationY: pan.translation(in: pan.view).y)
}
```

在 `apply(_:)` 中以旧/新 position 判断 expanded、collapsed、child top 与双向 handoff，仅在跨越时输出对应事件；测试固定验证这些事件不会因重复 callback 重发。

- [x] **Step 4: 添加日志与乱序/旧 token 测试**

新增以下测试并使用 `AnchorPagerLogger.sink` 做精确事件计数：

```swift
func testRepeatedChangedDoesNotRepeatOwnerOrBoundaryLogs()
func testOldBindingTokenCannotModifyReplacementChild()
func testContainerToChildAndChildToContainerEmitOneHandoffEach()
func testInvalidateEmitsOneBindingAndResourceReleaseEvent()
```

`testOldBindingTokenCannotModifyReplacementChild` 必须通过 internal 测试入口 `handleChildChangeForTesting(token:)` 传入 rebind 前 token，断言 replacement offset 未变化且只出现一次 `scroll.binding.stale`。该入口只包一层 `childDidChange(token:)`，不进入 public API。

- [x] **Step 5: 运行 coordinator 组合测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerScrollPositionResolverTests \
  -only-testing:AnchorPagerTests/AnchorPagerContainerScrollViewTests \
  -only-testing:AnchorPagerTests/AnchorPagerChildScrollBindingTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
```

Expected: 全部通过，0 failures；无逐帧普通日志断言失败。

Actual: coordinator RED 因找不到类型失败；首轮 10 tests 全部 GREEN。Task 1–4 组合回归共 31 tests，0 failures，覆盖双向 handoff、短内容上限、container 单 bounce、guard 重入、旧 binding token、幂等 rebind/teardown 和状态变化日志。child pan target 仅观察绑定终态，canonical delta 始终只取 container pan translation，消除了计划初稿的双输入矛盾。

- [x] **Step 6: 自审并提交**

重点检查唯一 owner、不设置 child delegate、guard 重入、KVO/pan target 释放、container bounce 临时边界、MainActor 和不读取 page/provider。

```bash
git diff --check
git add Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift \
  Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift \
  Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift
git commit -m "实现纵向滚动协调状态"
```

---

### Task 5: ViewController committed terminal 集成

**Files:**
- Create: `Sources/AnchorPager/Core/AnchorPagerVerticalScrollDelegate.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Consumes: Task 4 coordinator、Store `committedCurrentScrollView`、既有 reload/selection terminal。
- Produces: `reconcileCommittedScrollBinding()` 唯一接线入口；container scroll delegate 先协调 offset、再更新可见布局。

- [x] **Step 1: 写 ViewController RED 测试**

在 `AnchorPagerViewControllerTests` 加入以下完整场景；公共 arrange 使用 fixed 100 pt collapsible Header、真实 window 和现有 `installedAdapter(in:)` helper：

```swift
@MainActor
func testInitialPageTerminalBindsCommittedChildWithoutReplacingDelegate() {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 100, min: 0)
    let child = ScrollChildViewController()
    child.loadViewIfNeeded()
    let businessDelegate = RecordingScrollDelegate()
    child.scrollView.delegate = businessDelegate
    child.scrollView.contentSize = CGSize(width: 320, height: 1200)
    let pager = AnchorPagerViewController(configuration: configuration)
    let dataSource = StubDataSource(count: 1, viewControllers: [child])
    pager.dataSource = dataSource
    pager.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    pager.loadViewIfNeeded()
    pager.reloadData()
    pager.view.layoutIfNeeded()

    pager.verticalScrollView.contentOffset.y = 50
    child.scrollView.contentOffset.y = -child.scrollView.contentInset.top + 20

    XCTAssertEqual(child.scrollView.contentOffset.y, -child.scrollView.contentInset.top, accuracy: 0.5)
    XCTAssertTrue(child.scrollView.delegate === businessDelegate)
}

@MainActor
func testCompletedSelectionRebindsNewCommittedChildAfterStoreCommit() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 100, min: 0)
    let source = ScrollChildViewController()
    let target = ScrollChildViewController()
    source.loadViewIfNeeded()
    target.loadViewIfNeeded()
    let sourceDelegate = RecordingScrollDelegate()
    let targetDelegate = RecordingScrollDelegate()
    source.scrollView.delegate = sourceDelegate
    target.scrollView.delegate = targetDelegate
    let pager = AnchorPagerViewController(configuration: configuration)
    let dataSource = StubDataSource(count: 2, viewControllers: [source, target])
    pager.dataSource = dataSource
    pager.loadViewIfNeeded()
    pager.reloadData()
    pager.setSelectedIndex(1, animated: true)
    let adapter = try XCTUnwrap(installedAdapter(in: pager))
    adapter.pageboyViewController(adapter, didScrollToPageAt: 1, direction: .forward, animated: true)

    pager.verticalScrollView.contentOffset.y = 50
    target.scrollView.contentOffset.y = -target.scrollView.contentInset.top + 30

    XCTAssertEqual(target.scrollView.contentOffset.y, -target.scrollView.contentInset.top, accuracy: 0.5)
    XCTAssertTrue(source.scrollView.delegate === sourceDelegate)
    XCTAssertTrue(target.scrollView.delegate === targetDelegate)
}

@MainActor
func testCancelledSelectionRebindsSourceCommittedChild() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 100, min: 0)
    let source = ScrollChildViewController()
    let target = ScrollChildViewController()
    source.loadViewIfNeeded()
    target.loadViewIfNeeded()
    let sourceDelegate = RecordingScrollDelegate()
    let targetDelegate = RecordingScrollDelegate()
    source.scrollView.delegate = sourceDelegate
    target.scrollView.delegate = targetDelegate
    let pager = AnchorPagerViewController(configuration: configuration)
    let dataSource = StubDataSource(count: 2, viewControllers: [source, target])
    pager.dataSource = dataSource
    pager.loadViewIfNeeded()
    pager.reloadData()
    pager.setSelectedIndex(1, animated: true)
    let adapter = try XCTUnwrap(installedAdapter(in: pager))
    adapter.pageboyViewController(adapter, didCancelScrollToPageAt: 1, returnToPageAt: 0)

    pager.verticalScrollView.contentOffset.y = 50
    source.scrollView.contentOffset.y = -source.scrollView.contentInset.top + 25

    XCTAssertEqual(source.scrollView.contentOffset.y, -source.scrollView.contentInset.top, accuracy: 0.5)
    XCTAssertTrue(source.scrollView.delegate === sourceDelegate)
    XCTAssertTrue(target.scrollView.delegate === targetDelegate)
}

@MainActor
func testEmptyReloadUnbindsOldChildObservationAndPreservesItsDelegate() {
    let child = ScrollChildViewController()
    child.loadViewIfNeeded()
    let businessDelegate = RecordingScrollDelegate()
    child.scrollView.delegate = businessDelegate
    let dataSource = StubDataSource(count: 1, viewControllers: [child])
    let pager = AnchorPagerViewController()
    pager.dataSource = dataSource
    pager.loadViewIfNeeded()
    pager.reloadData()
    dataSource.count = 0
    dataSource.titles = []
    dataSource.viewControllers = []
    pager.reloadData()
    let detachedOffset = child.scrollView.contentOffset.y + 40
    child.scrollView.contentOffset.y = detachedOffset

    XCTAssertEqual(child.scrollView.contentOffset.y, detachedOffset, accuracy: 0.001)
    XCTAssertTrue(child.scrollView.delegate === businessDelegate)
}

@MainActor
func testPendingReloadDoesNotBindProviderPendingScrollViewBeforeTerminal() throws {
    let committed = ScrollChildViewController()
    let neighbor = ScrollChildViewController()
    let pending = ScrollChildViewController()
    committed.loadViewIfNeeded()
    let businessDelegate = RecordingScrollDelegate()
    committed.scrollView.delegate = businessDelegate
    let dataSource = StubDataSource(count: 2, viewControllers: [committed, neighbor])
    let pager = AnchorPagerViewController()
    pager.dataSource = dataSource
    pager.loadViewIfNeeded()
    pager.reloadData()
    let adapter = try XCTUnwrap(installedAdapter(in: pager))
    adapter.pageboyViewController(adapter, willScrollToPageAt: 1, direction: .forward, animated: true)
    dataSource.count = 1
    dataSource.titles = ["Pending"]
    dataSource.viewControllers = [pending]
    pager.reloadData()

    pager.verticalScrollView.contentOffset.y = 20
    committed.scrollView.contentOffset.y = -committed.scrollView.contentInset.top + 10

    XCTAssertEqual(committed.scrollView.contentOffset.y, -committed.scrollView.contentInset.top, accuracy: 0.5)
    XCTAssertFalse(pending.isViewLoaded)
    XCTAssertTrue(committed.scrollView.delegate === businessDelegate)
}

@MainActor
func testContainerScrollCoordinatesBeforePublishingLayoutContext() {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .fixed(max: 100, min: 0)
    let child = ScrollChildViewController()
    let delegate = StubDelegate()
    let pager = AnchorPagerViewController(configuration: configuration)
    let dataSource = StubDataSource(count: 1, viewControllers: [child])
    pager.dataSource = dataSource
    pager.delegate = delegate
    pager.loadViewIfNeeded()
    pager.reloadData()
    child.scrollView.contentOffset.y = -child.scrollView.contentInset.top + 20
    pager.verticalScrollView.contentOffset.y = 50
    pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)

    XCTAssertEqual(child.scrollView.contentOffset.y, -child.scrollView.contentInset.top, accuracy: 0.5)
    XCTAssertEqual(delegate.layoutContexts.last?.headerFrame.height, 50, accuracy: 0.5)
}

@MainActor
func testDeinitSynchronouslyReleasesScrollBindingAndPreservesBusinessDelegate() {
    let child = ScrollChildViewController()
    child.loadViewIfNeeded()
    let businessDelegate = RecordingScrollDelegate()
    child.scrollView.delegate = businessDelegate
    weak var weakPager: AnchorPagerViewController?
    var pager: AnchorPagerViewController? = AnchorPagerViewController()
    weakPager = pager
    let dataSource = StubDataSource(count: 1, viewControllers: [child])
    pager?.dataSource = dataSource
    pager?.loadViewIfNeeded()
    pager?.reloadData()
    pager = nil

    XCTAssertNil(weakPager)
    XCTAssertTrue(child.scrollView.delegate === businessDelegate)
}

@MainActor
private final class RecordingScrollDelegate: NSObject, UIScrollViewDelegate {}
```

- [x] **Step 2: 运行 ViewController 测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

Expected: 新测试因没有 coordinator binding/terminal 接线而失败。

- [x] **Step 3: 提取 container delegate**

创建：

```swift
import UIKit

@MainActor
protocol AnchorPagerVerticalScrollDelegateOwner: AnyObject {
    func verticalScrollViewDidScroll(_ scrollView: UIScrollView)
}

@MainActor
final class AnchorPagerVerticalScrollDelegate: NSObject, UIScrollViewDelegate {
    weak var owner: AnchorPagerVerticalScrollDelegateOwner?

    init(owner: AnchorPagerVerticalScrollDelegateOwner) {
        self.owner = owner
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        owner?.verticalScrollViewDidScroll(scrollView)
    }
}
```

删除 ViewController 内嵌 `VerticalScrollDelegate`，保持 public `verticalScrollView.delegate` 仍由 AnchorPager 独占。

- [x] **Step 4: 接入 coordinator 与 committed rebind**

把现有 public 属性改为显式基类静态类型，保持 API 仍只暴露 UIKit：

```swift
public let verticalScrollView: UIScrollView = AnchorPagerContainerScrollView()

private var anchorContainerScrollView: AnchorPagerContainerScrollView {
    guard let scrollView = verticalScrollView as? AnchorPagerContainerScrollView else {
        preconditionFailure("verticalScrollView 必须由 AnchorPagerContainerScrollView 提供")
    }
    return scrollView
}
```

再增加：

```swift
private lazy var scrollCoordinator = AnchorPagerScrollCoordinator(
    containerScrollView: anchorContainerScrollView
)

private func reconcileCommittedScrollBinding() {
    scrollCoordinator.bindCommittedChild(pageStateStore.committedCurrentScrollView)
}
```

固定调用顺序：

1. `applyLayoutOutput`：先 apply managed inset，再 `updateGeometry(collapsibleDistance:)`，再发布 layout/progress。
2. container `scrollViewDidScroll`：先 `scrollCoordinator.containerDidScroll()`，再 `updateVisibleLayoutForScrolling()`。
3. selection did：`pageStateStore.didSelect` → `reconcileCommittedScrollBinding` → public selection commit。
4. selection cancel：Store 恢复 source → rebind source → cancel log。
5. reload terminal：Store commit → terminal `didSelect` → 安装 Header/可见布局 → rebind committed current/empty → ack。
6. deinit：先 `scrollCoordinator.invalidate()`，再释放 Store/inset ownership。

不得从 `willSelect`、`willPerformReload`、provider callback 或 staged snapshot 绑定 child。

- [x] **Step 5: 添加源码门禁测试**

读取 `Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift`、`Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`、`Sources/AnchorPager/Gesture/AnchorPagerContainerScrollView.swift` 和 `Sources/AnchorPager/Public/AnchorPagerViewController.swift`，断言不存在对 `committedCurrentScrollView.delegate`、`childScrollView.delegate`、`scrollView.delegate` 或任意 `.panGestureRecognizer.delegate` 的赋值；允许唯一既有 `verticalScrollView.delegate = verticalScrollDelegate`。同时断言生产源码不包含 `Task.detached`、`nonisolated(unsafe)` 或 `@unchecked Sendable`。

- [x] **Step 6: 运行框架聚焦回归**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests \
  -only-testing:AnchorPagerTests/AnchorPagerManagedInsetCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingHostViewControllerTests \
  -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests test
```

Expected: 全部通过，0 failures；现有 Pageboy child bounds、inset、reload generation 和 appearance 测试不回归。

Actual: 最小 RED 同时证明旧 container 类型和未绑定 child；接线后最小 2 tests GREEN。首次聚焦回归的 162 tests 中仅旧 v0.3 “部分折叠仍保留 child distance=37”两处断言失败；该预期与 v0.5 已确认唯一 owner 不变量冲突，更新为归顶且不延迟恢复后，最终 163 tests、0 failures。源码门禁确认只有 `verticalScrollView.delegate = verticalScrollDelegate`，不存在业务 child 或任意内建 pan delegate 写入。

- [x] **Step 7: 自审并提交**

```bash
git diff --check
git add Sources/AnchorPager/Core/AnchorPagerVerticalScrollDelegate.swift \
  Sources/AnchorPager/Public/AnchorPagerViewController.swift \
  Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m "接入已提交页面纵向协调"
```

---

### Task 6: Example 状态探针与真实 pan UI 验收

**Files:**
- Modify: `Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift`
- Modify: `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerScrollCoordinatorTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`

**Interfaces:**
- Consumes: public collapse delegate、public `verticalScrollView` 只读状态、Example page 自己拥有的 scroll delegate。
- Produces: 仅 Example target 可见的 `scroll-coordination-state` accessibility value；不扩大框架 API。

- [x] **Step 1: 写 Example RED 单测和 UI 测试**

Example 单测验证状态序列化：

```swift
XCTAssertEqual(
    ExampleScrollCoordinationState(
        page: "long",
        collapseProgress: 1,
        childDistance: 42,
        containerSawTopBounce: false,
        childSawTopBounce: false
    ).accessibilityValue,
    "page=long;collapse=1.00;distance=42.00;containerBounce=0;childBounce=0"
)
```

UI 测试增加：

```swift
@MainActor func testSingleUpwardDragCollapsesHeaderThenContinuesIntoLongChild()
@MainActor func testSingleDownwardDragReturnsLongChildThenExpandsHeader()
@MainActor func testShortAndFallbackPagesRemainStableAcrossVerticalDrag()
@MainActor func testExpandedTopPullUsesContainerBounceWithoutChildBounce()
@MainActor func testSwitchingPagesRebindsVerticalOwnerWithoutJump()
```

每个测试必须使用 `press(forDuration:thenDragTo:)` 或带 velocity/hold 的真实 coordinate drag，并通过 `scroll-coordination-state`、Header/bar frame 和目标 row hittable 状态共同断言。

- [x] **Step 2: 运行 Example 测试并确认 RED**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleTests \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSingleUpwardDragCollapsesHeaderThenContinuesIntoLongChild \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testExpandedTopPullUsesContainerBounceWithoutChildBounce test
```

Expected: 状态类型/元素不存在或 handoff 断言失败。

- [x] **Step 3: 实现 Example-only 状态探针**

在 Example 文件新增 `ExampleScrollCoordinationState` 和一个 20×20 透明测试 control，identifier 固定为 `scroll-coordination-state`。`ExamplePagerViewController` 通过 public collapse delegate 与 `verticalScrollView` KVO 更新 container 状态；`ExampleScrollPageViewController` 由页面自身设置 `scrollView.delegate = self` 并通过 closure 回报 child distance/bounce。该 delegate 赋值属于业务 child 自己，不得移动到 AnchorPager framework。

状态字段固定为：

```swift
struct ExampleScrollCoordinationState: Equatable {
    var page: String
    var hasScrollTarget: Bool
    var collapseProgress: CGFloat
    var childDistance: CGFloat
    var containerSawTopBounce: Bool
    var childSawTopBounce: Bool

    var accessibilityValue: String {
        String(
            format: "page=%@;hasScrollTarget=%d;collapse=%.2f;distance=%.2f;containerBounce=%d;childBounce=%d",
            page,
            hasScrollTarget ? 1 : 0,
            collapseProgress,
            childDistance,
            containerSawTopBounce ? 1 : 0,
            childSawTopBounce ? 1 : 0
        )
    }
}
```

页面切换、reload 和每次测试启动必须重置 bounce flags，避免跨场景污染。

- [x] **Step 4: 实现并稳定五个 UI 场景**

坐标使用页面内容中央，避开 navigation/tab bar 和横向边缘。用 predicate 等待状态，不使用固定 sleep。plain page 通过 `hasScrollTarget=0`、container bounce flag、plain root/window 几何和 Header/bar frame 证明没有 child scroll owner，不使用 synthetic offset 替代事实。

首轮真实 pan 结果：Example 单元测试和单次上推 handoff 通过，但展开态下拉记录到 `childBounce=1`。根因是 UIKit 可能先向业务 child delegate 发布原生负 offset，再触发框架 KVO 收敛；现有只断言最终 offset 的 coordinator 单元测试未覆盖该瞬态。

修复前先增加框架 RED 测试，固定以下租约语义：绑定在顶部时 child `bounces == false`；container pan 期间保持关闭；手势结束且 child distance 大于 0 后恢复绑定前值；解绑/失效始终恢复绑定前值。实现只允许由 `AnchorPagerChildScrollBinding` 保存与恢复该属性，ScrollCoordinator 决定租约时机，不得设置 child delegate、pan delegate 或 `isScrollEnabled`。

- [x] **Step 5: 运行 Example 聚焦与全量测试**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test
```

Expected: Example build 通过；全部单元/UI 测试 0 failures、0 skips。记录实际 test 数量与墙钟时间。

- [x] **Step 6: 自审并提交**

确认测试探针只存在 Example target，框架 public API 无变化；Example 自己拥有的 child delegate 未被框架覆盖；UI 测试是真实 drag 且不靠 sleep。

```bash
git diff --check
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift \
  Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift \
  Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "验证纵向滚动真实手势交接"
```

**Actual:** 首轮 Example 状态类型 RED 因类型不存在而编译失败；探针实现后聚焦集 7 项通过、1 项真实 pan 失败，失败明确记录到展开态下拉时 `childBounce=1`。根因确认是 UIKit 先向业务 delegate 发布原生负 offset、框架 KVO 后收敛，原“最终 offset 等于顶部”测试不足以证明唯一 bounce owner。设计先补充 committed child `bounces` 临时租约，再增加 2 个 coordinator RED 测试；iOS simulator 上 12 项 coordinator 测试由 2 failures 转为 12/12。修复后关键真实 pan 2/2、Task 6 聚合集 12/12 通过。旧 v0.3 UI 用例同步改为显式满足 v0.5 前置条件：长页到底时 Header 已折叠；在短页真实下拉展开后切回长页才验证回顶。最终 iPhone 17 Pro / iOS 26.5 Example 全量 28 tests、0 failures、0 skips，墙钟 218.3 秒。

**Review:** 探针和序列化类型仅位于 Example target；框架 public API、Tabman/Pageboy adapter containment、Store generation/page identity、managed inset 和业务 delegate/pan delegate 均未变化。Example 页面自己设置其 scroll delegate；框架仅在 committed binding 内由 binding 保存/恢复业务 `bounces`，ScrollCoordinator 决定顶部/手势期间的临时租约，解绑、空态和 invalidate 同步恢复原值。五个新 UI 场景全部使用真实 coordinate drag 和 predicate，没有固定 sleep。

---

### 无滚动页面 direct containment 专项修复门禁

Task 1–6 完成后的真实视图层级检查发现，历史 synthetic scroll wrapper 会缩短无滚动业务页根 view。专项设计与计划见 `docs/superpowers/specs/2026-07-13-plain-page-direct-containment-design.md` 和 `docs/superpowers/plans/2026-07-13-plain-page-direct-containment.md`。

专项修复已完成：Store 采用 page/optional scroll 三态，plain original page 直接交给 Pageboy，synthetic wrapper 已删除；plain page 不参与 managed inset、snapshot、child bounce 或 simultaneous pair。专项全量验收为 Framework 220 tests、Example 30 tests，均 0 failures、0 skips；Example generic simulator build 成功。

后续真实运行发现 `alwaysBounceVertical` 虽已开启，但 active pan 的 canonical clamp 会抵消肉眼可见 bounce；旧 UI 探针只证明出现过瞬时负 offset。Task 7 当时因此再次暂停。修订设计见 `docs/superpowers/specs/2026-07-13-boundary-bounce-ownership-design.md`：stable/native boundary 分离与无滚动页双边界 presentation 现已实现并完成实现者验收，但仍须进入本 Task 7 独立复审；不得沿用旧探针提前标记 v0.5 Ready。

2026-07-13 JXPagingView 源码复核后再次修订：本计划 Task 6 记录的 child `bounces` 临时租约属于已完成但被取代的历史实现，不再是最终契约。后续实施必须删除该租约，不保存、不修改、不恢复业务 child 的 `bounces`/`alwaysBounceVertical`；`.container`/`.none` 通过 guarded stable-boundary write 约束非 owner，`.child` 与真实 child bottom 按业务 scroll view 自身配置执行原生回弹。新的实施步骤以同日边界 bounce 专项计划为准，本历史计划不回写已完成 RED/GREEN 记录。

---

### Task 7: 文档、状态、完整验收与最终复审

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- Modify: `docs/superpowers/specs/2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md`
- Modify: `docs/superpowers/specs/2026-07-13-v0-5-scroll-coordination-design.md`
- Modify: `docs/superpowers/plans/2026-07-13-v0-5-scroll-coordination.md`

**Interfaces:**
- Consumes: Task 1–6 的最终实现、测试计数和 warning。
- Produces: 真实 v0.5 状态、known limitations、验收记录和 v0.6 开放/不开放结论。

- [x] **Step 1: 更新接入和维护文档**

README 必须说明：

- AnchorPager 不设置业务 child `UIScrollView.delegate`；
- container/child handoff 与 committed current 语义；
- v0.5 顶部额外下拉临时由 container bounce；
- v0.5 不跨 owner 转移减速 velocity；
- 示例和日志过滤方式。

architecture/spec/task-list 必须记录真实完成范围，不提前勾选 v0.6/v0.7。

- [x] **Step 2: 运行源码与文档门禁**

```bash
git diff --check
rg -n "Task\.detached|nonisolated\(unsafe\)|@unchecked Sendable|@preconcurrency" Sources/AnchorPager
rg -n "committedCurrentScrollView.*delegate|childScrollView.*delegate|scrollView\.delegate\s*=" \
  Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift \
  Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift \
  Sources/AnchorPager/Public/AnchorPagerViewController.swift
```

Expected: `git diff --check` 通过；unsafe 扫描无结果；child delegate 禁止项扫描无结果。ViewController 允许的 container delegate 赋值必须使用精确 `verticalScrollView.delegate = verticalScrollDelegate`，人工自审确认不属于 child。

- [x] **Step 3: 运行完整验收**

```bash
swift --version
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test
git diff --check
```

Expected: Swift 6.2 或更高；resolve、Framework、Example build、Example 单元/UI 全部成功；0 failures、0 skips。只允许记录已知 Pageboy/Tabman privacy resource 或模拟器环境提示，任何新增生产 warning 必须在完成前解决。

- [x] **Step 4: 执行代码自审**

逐项记录结论：public API、Tabman/Pageboy 泄漏、Pageboy containment/appearance、Store committed/pending、child delegate 绝对禁止项、container 子类 simultaneous recognition、KVO/target cleanup、guarded offset、inset ownership、临时 bounce、MainActor/析构、日志热路径、Example UI test、文档状态和验收命令。

- [x] **Step 5: 执行初次独立复审门禁**

比较 v0.5 开始前提交 `d8367c9` 到实现 HEAD。Critical/Important 必须清零；任何职责闭环、代理覆盖、双 owner、terminal 前绑定 pending 或 UI test 不稳定都先修复并重跑对应 RED/GREEN，不以文档豁免。

初次独立复审发现 3 个 Important，均已由 `f81ca1e` 按 RED→GREEN 修复并完成聚焦与全量验收。

- [x] **Step 5b: 执行修复后的再次独立复审门禁**

第四次整分支独立复审覆盖 `be2d783...13b3d95` 并重点比较 `b00d204...128821f`，尤其是 `5b80893...128821f`；结论为 Critical 0、Important 0、Minor 2。两个 Minor 已在最终状态提交中修复。

- [x] **Step 6: 根据真实结果更新状态并提交**

只有完整验收和独立复审通过后，才把 v0.5 标记完成并开放 v0.6；否则保留未完成状态并写明具体未通过命令。

```bash
git add README.md docs AGENTS.md
git commit -m "完成纵向边界回弹验收"
```

---

## Task 7 实现者验收补充（2026-07-13）

- 最终边界契约以 `2026-07-13-boundary-bounce-ownership.md` 为准；本计划中已被取代的临时 container-only top bounce 和 child `bounces` 租约仅保留为历史实施记录。
- 初始实现者验收：Apple Swift 6.3.3；resolve exit 0；Framework 264 项、Example 36 项，均 0 fail、0 skip；generic Simulator build 成功；三份 xcresult 0 warning。
- 实现者完成 public API、containment/appearance、Store generation/cache/snapshot/inset、offset writer、业务属性禁止项、stable/native、presentation、cancel、日志和真实 UI 十项自审，未发现阻塞性缺陷。
- 实现提交基线为 `47abcd6`，文档记录提交标题为 `同步纵向边界回弹验收记录`。初次独立复审发现的未呈现 owner 反向回稳、部分折叠 Header child top KVO 路由和 `.none` 探针假阳性已由 `f81ca1e` 修复。
- 再次整分支复审发现的零稳定区间 boundary 反向切换问题由 `5b80893` 在纯 Overscroll policy 内修复；architecture 的 top/bottom 对称 presentation 与 v0.5/v0.7 职责同步更正。
- 第三次整分支复审发现已呈现 `.top/.child` observer finish 丢失 raw total 的 Important，以及 requirements 仍要求 guarded apply/skip 逐帧日志的 Minor；`128821f` 以显式 finish result、pan input 同轮重放、observer-only raw total 经同一 Resolver container-first 分配完成修复，requirements 同步改为只记录状态变化或受控采样。
- 第四次整分支独立复审：Critical 0、Important 0、Minor 2；README 旧验收摘要和 `.container` 顶部 UI 缺少严格 child owner 排他断言两个 Minor 已在最终状态提交中修复。
- 最终验收：生产代码 HEAD `128821f` 对应 Framework 283/283（`/private/tmp/AnchorPagerPresentedTopFrameworkFull-20260713-2258.xcresult`）；新增严格断言的目标 UI 1/1、Example 37/37（10 单元 + 27 UI）和 generic Simulator build 全部成功，0 fail、0 skip，结果均为 0 error/warning/analyzer warning。Step 5b/6 完成，v0.5 Task 7 标记 Ready。

---

## 实施检查点

1. Task 1 后确认 resolver 不依赖 UIKit callback 顺序。
2. Task 2 后确认 container 子类只放行 committed pair，container/child pan delegate identity 均不变。
3. Task 3 后确认业务 child `UIScrollView.delegate` 没有任何写入路径。
4. Task 4 后确认 handoff、guard、binding 和日志不复制 Store/Inset/Paging 职责。
5. Task 5 后确认只在 committed reload/selection complete/cancel terminal 后 rebind。
6. Task 6 后确认真实 drag 覆盖长页、短页、plain direct page、切页和唯一 container bounce。
7. Task 7 后确认完整测试、代码自审和独立复审均有记录。

## 计划自审

- Spec coverage：代理所有权、canonical distance、guarded update、临时 bounce、committed binding、资源清理、日志、UI test 与后续版本边界分别由 Task 1–7 覆盖。
- Type consistency：resolver `Position/Input` 由 Task 1 产出；container 子类和 binding 由 Task 2/3 产出；Task 4 只消费这些固定接口；Task 5 只消费 coordinator public-internal 方法。
- Scope：不实现 v0.6 overscroll mode，不实现 v0.7 完整 interaction state或跨 owner 惯性合成。
- Delegate gate：Framework 任何任务都不设置业务 child `UIScrollView.delegate`；只有 Example 业务 child 自己可拥有其 delegate。
- Placeholder scan：所有任务均给出固定文件、接口、测试名、命令、预期结果和提交边界，没有未决实现分支。
