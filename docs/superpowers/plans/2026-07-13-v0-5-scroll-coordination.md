# v0.5 纵向滚动协调实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Header container 与 committed current child 的连续纵向 handoff，同时保留业务 child 的 `UIScrollView.delegate` 与 pan delegate，并以真实 simulator drag 验收唯一滚动 owner。

**Architecture:** 纯 `AnchorPagerScrollPositionResolver` 从 pan 起点计算 canonical total，再把位置分配到 container/child；`AnchorPagerPanGestureDelegateProxy` 只代理自有 container pan，`AnchorPagerChildScrollBinding` 只用 KVO 与 target-action 观察 child。MainActor `AnchorPagerScrollCoordinator` 组合三者，并由 `AnchorPagerViewController` 在 committed reload/selection terminal 后同步重绑定，不读取 provider pending、不写 managed inset、不接管 page identity。

**Tech Stack:** Swift 6.2+、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、XCTest、XCUITest、Tabman 4.0.1、Pageboy 5.0.2。

## Global Constraints

- Package、Library product、Module 均保持 `AnchorPager`。
- 最低工具链 Swift 6.2，语言模式 Swift 6，最低系统 iOS 14，UI stack UIKit。
- Tabman/Pageboy 只存在于 internal adapter 层，不进入 public API。
- 横向业务 page containment 与 appearance 继续由 Pageboy/UIKit 执行。
- AnchorPager 任何时候都不得设置业务 child 的 `UIScrollView.delegate`，包括临时替换、forwarding proxy、保存后恢复和测试注入。
- AnchorPager 不得替换业务 child 的 `panGestureRecognizer.delegate`。
- simultaneous recognition 只通过自有 container pan forwarding proxy 放行 committed current child pair。
- ScrollCoordinator 只读 Store committed current/empty，不读取 provider pending，不缓存 Host/Adapter/provider，不复制 generation/cache/snapshot/inset ownership。
- 所有 UIKit、coordinator、data source 和 delegate 路径保持 `@MainActor`；不使用 `Task.detached`、`@unchecked Sendable`、`nonisolated(unsafe)` 或 `@preconcurrency`。
- 不通过切换 `isScrollEnabled`、timer、dispatch delay、重复 layout 或强制 reset 掩盖 handoff 问题。
- v0.5 顶部额外下拉只保留 container 原生 bounce，child 固定顶部；正式 mode 路由留给 v0.6。
- v0.5 不做跨 owner 惯性合成；完整 `verticalDecelerating` interaction state 留给 v0.7。
- 高频 pan/KVO/scroll callback 不逐帧输出普通日志。
- 每个任务完成后先自审再提交；涉及 UI 的任务必须提供真实 simulator 手势测试。

---

## 文件结构

新增文件：

```text
Sources/AnchorPager/Core/AnchorPagerScrollPositionResolver.swift
Sources/AnchorPager/Gesture/AnchorPagerPanGestureDelegateProxy.swift
Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift
Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift
Sources/AnchorPager/Core/AnchorPagerVerticalScrollDelegate.swift
Tests/AnchorPagerTests/AnchorPagerScrollPositionResolverTests.swift
Tests/AnchorPagerTests/AnchorPagerPanGestureDelegateProxyTests.swift
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

- [ ] **Step 1: 写完整 RED 测试**

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

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerScrollPositionResolverTests test
```

Expected: 编译失败，提示找不到 `AnchorPagerScrollPositionResolver`。

- [ ] **Step 3: 实现纯解析器**

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

- [ ] **Step 4: 运行解析器测试并确认 GREEN**

Run: Task 1 Step 2 的同一命令。

Expected: 5 tests，0 failures。

- [ ] **Step 5: 自审并提交**

确认文件只 import CoreGraphics、不绑定 MainActor、不出现 UIKit/Tabman/Pageboy、所有非有限输入有确定降级。

```bash
git diff --check
git add Sources/AnchorPager/Core/AnchorPagerScrollPositionResolver.swift \
  Tests/AnchorPagerTests/AnchorPagerScrollPositionResolverTests.swift
git commit -m "实现纵向滚动位置解析器"
```

---

### Task 2: Container pan gesture forwarding proxy

**Files:**
- Create: `Sources/AnchorPager/Gesture/AnchorPagerPanGestureDelegateProxy.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPanGestureDelegateProxyTests.swift`

**Interfaces:**
- Consumes: AnchorPager 自有 `verticalScrollView.panGestureRecognizer`。
- Produces: `install()`、`bindCurrentChildPan(_:)`、`invalidate()`；只允许 container/current child pair simultaneous，绝不设置 child pan delegate。

- [ ] **Step 1: 写 RED 测试**

```swift
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerPanGestureDelegateProxyTests: XCTestCase {
    func testOnlyCommittedContainerChildPairRecognizesSimultaneously() {
        let container = UIScrollView()
        let child = UIScrollView()
        let unrelated = UIPanGestureRecognizer()
        let proxy = AnchorPagerPanGestureDelegateProxy(containerPan: container.panGestureRecognizer)
        proxy.install()
        proxy.bindCurrentChildPan(child.panGestureRecognizer)

        XCTAssertTrue(proxy.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: child.panGestureRecognizer
        ))
        XCTAssertFalse(proxy.gestureRecognizer(
            container.panGestureRecognizer,
            shouldRecognizeSimultaneouslyWith: unrelated
        ))
    }

    func testChildPanDelegateIsNeverChanged() {
        let container = UIScrollView()
        let child = UIScrollView()
        let childDelegate = RecordingGestureDelegate()
        child.panGestureRecognizer.delegate = childDelegate
        let proxy = AnchorPagerPanGestureDelegateProxy(containerPan: container.panGestureRecognizer)

        proxy.install()
        proxy.bindCurrentChildPan(child.panGestureRecognizer)
        proxy.invalidate()

        XCTAssertTrue(child.panGestureRecognizer.delegate === childDelegate)
    }

    func testInvalidateRestoresOriginalContainerDelegateWhenStillOwned() {
        let container = UIScrollView()
        let original = RecordingGestureDelegate()
        container.panGestureRecognizer.delegate = original
        let proxy = AnchorPagerPanGestureDelegateProxy(containerPan: container.panGestureRecognizer)
        proxy.install()

        proxy.invalidate()

        XCTAssertTrue(container.panGestureRecognizer.delegate === original)
    }
}

@MainActor
private final class RecordingGestureDelegate: NSObject, UIGestureRecognizerDelegate {}
```

- [ ] **Step 2: 运行测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerPanGestureDelegateProxyTests test
```

Expected: 编译失败，提示找不到 proxy 类型。

- [ ] **Step 3: 实现 proxy 与完整 forwarding**

实现以下固定接口：

```swift
import UIKit

@MainActor
final class AnchorPagerPanGestureDelegateProxy: NSObject, UIGestureRecognizerDelegate {
    private weak var containerPan: UIPanGestureRecognizer?
    private weak var originalDelegate: (any UIGestureRecognizerDelegate)?
    private weak var currentChildPan: UIPanGestureRecognizer?
    private var isInstalled = false

    init(containerPan: UIPanGestureRecognizer) {
        self.containerPan = containerPan
    }

    func install() {
        guard let containerPan, containerPan.delegate !== self else { return }
        originalDelegate = containerPan.delegate
        containerPan.delegate = self
        isInstalled = true
    }

    func bindCurrentChildPan(_ pan: UIPanGestureRecognizer?) {
        currentChildPan = pan
    }

    func invalidate() {
        currentChildPan = nil
        guard isInstalled, let containerPan else { return }
        if containerPan.delegate === self {
            containerPan.delegate = originalDelegate
        } else {
            AnchorPagerLogger.log(
                .error,
                category: .gesture,
                event: "gesture.simultaneous.degraded"
            )
        }
        isInstalled = false
        originalDelegate = nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if isCurrentPair(gestureRecognizer, otherGestureRecognizer) {
            return true
        }
        return originalDelegate?.gestureRecognizer?(
            gestureRecognizer,
            shouldRecognizeSimultaneouslyWith: otherGestureRecognizer
        ) ?? false
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        originalDelegate?.responds(to: selector) == true ? originalDelegate : super.forwardingTarget(for: selector)
    }

    private func isCurrentPair(
        _ first: UIGestureRecognizer,
        _ second: UIGestureRecognizer
    ) -> Bool {
        guard let containerPan, let currentChildPan else { return false }
        return (first === containerPan && second === currentChildPan)
            || (first === currentChildPan && second === containerPan)
    }
}
```

同时补测试覆盖原 delegate 的 `gestureRecognizerShouldBegin(_:)` 被 forwarding，container delegate 被外部替换后 `invalidate()` 不覆盖新值并记录 `gesture.simultaneous.degraded`。

- [ ] **Step 4: 运行 proxy 与日志回归**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerPanGestureDelegateProxyTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
```

Expected: 全部通过，0 failures；child pan delegate identity 不变。

- [ ] **Step 5: 自审并提交**

确认只有 `containerPan.delegate =` 写入，生产文件中不存在 child pan delegate 写入，proxy teardown 幂等且不形成 retain cycle。

```bash
git diff --check
git add Sources/AnchorPager/Gesture/AnchorPagerPanGestureDelegateProxy.swift \
  Tests/AnchorPagerTests/AnchorPagerPanGestureDelegateProxyTests.swift
git commit -m "建立容器纵向手势代理边界"
```

---

### Task 3: Child observation binding，不占用 UIScrollView.delegate

**Files:**
- Create: `Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerChildScrollBindingTests.swift`

**Interfaces:**
- Consumes: Store committed current `UIScrollView?`。
- Produces: `AnchorPagerChildScrollBinding`，通过 KVO/target-action发出 offset、contentSize 和 pan state，提供同步 `invalidate()`。

- [ ] **Step 1: 写 RED 测试**

```swift
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerChildScrollBindingTests: XCTestCase {
    func testBindingPreservesBusinessScrollAndPanDelegates() {
        let scrollView = UIScrollView()
        let scrollDelegate = RecordingScrollDelegate()
        let panDelegate = RecordingGestureDelegate()
        scrollView.delegate = scrollDelegate
        scrollView.panGestureRecognizer.delegate = panDelegate

        let binding = AnchorPagerChildScrollBinding(
            scrollView: scrollView,
            token: 1,
            onContentOffsetChanged: { _ in },
            onContentSizeChanged: { _ in },
            onPan: { _, _ in }
        )
        binding.invalidate()

        XCTAssertTrue(scrollView.delegate === scrollDelegate)
        XCTAssertTrue(scrollView.panGestureRecognizer.delegate === panDelegate)
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

- [ ] **Step 2: 运行测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerChildScrollBindingTests test
```

Expected: 编译失败，提示找不到 binding 类型。

- [ ] **Step 3: 实现 binding**

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
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard isValid else { return }
        onPan?(pan.state, pan.translation(in: pan.view).y)
    }
}
```

若 Swift 6 对 KVO closure 隔离产生诊断，只允许把 closure 内容同步桥接到 `MainActor.assumeIsolated`；不得给类型增加 unsafe Sendable 标记或异步 Task。

- [ ] **Step 4: 增加生产源码禁止项测试并运行 GREEN**

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

- [ ] **Step 5: 自审并提交**

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
- Consumes: Task 1 resolver、Task 2 proxy、Task 3 binding、container `UIScrollView`、committed child `UIScrollView?`。
- Produces: `updateGeometry(collapsibleDistance:)`、`bindCommittedChild(_:)`、`containerDidScroll()`、`handlePan(state:translationY:)`、`invalidate()`。

- [ ] **Step 1: 写 coordinator RED 测试**

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
    let container = UIScrollView()
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

- [ ] **Step 2: 运行测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests test
```

Expected: 编译失败，提示找不到 coordinator 类型。

- [ ] **Step 3: 实现 coordinator 固定接口**

```swift
import UIKit

@MainActor
final class AnchorPagerScrollCoordinator {
    enum Owner: Equatable { case container, child }

    private let containerScrollView: UIScrollView
    private let panProxy: AnchorPagerPanGestureDelegateProxy
    private var childBinding: AnchorPagerChildScrollBinding?
    private weak var committedChildScrollView: UIScrollView?
    private var bindingToken = 0
    private var collapsibleDistance: CGFloat = 0
    private var gestureStartTotal: CGFloat?
    private var gestureStartTranslationY: CGFloat = 0
    private var isApplyingGuardedOffsets = false
    private(set) var owner: Owner = .container

    init(containerScrollView: UIScrollView) {
        self.containerScrollView = containerScrollView
        panProxy = AnchorPagerPanGestureDelegateProxy(
            containerPan: containerScrollView.panGestureRecognizer
        )
        panProxy.install()
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
        panProxy.bindCurrentChildPan(scrollView?.panGestureRecognizer)
        bindingToken &+= 1
        guard let scrollView else { return }
        let token = bindingToken
        childBinding = AnchorPagerChildScrollBinding(
            scrollView: scrollView,
            token: token,
            onContentOffsetChanged: { [weak self] _ in self?.childDidChange(token: token) },
            onContentSizeChanged: { [weak self] _ in self?.childDidChange(token: token) },
            onPan: { [weak self] state, translationY in
                self?.handlePan(state: state, translationY: translationY)
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
        containerScrollView.panGestureRecognizer.removeTarget(
            self,
            action: #selector(handleContainerPan(_:))
        )
        panProxy.invalidate()
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

- [ ] **Step 4: 添加日志与乱序/旧 token 测试**

新增以下测试并使用 `AnchorPagerLogger.sink` 做精确事件计数：

```swift
func testRepeatedChangedDoesNotRepeatOwnerOrBoundaryLogs()
func testOldBindingTokenCannotModifyReplacementChild()
func testContainerToChildAndChildToContainerEmitOneHandoffEach()
func testInvalidateEmitsOneBindingAndResourceReleaseEvent()
```

`testOldBindingTokenCannotModifyReplacementChild` 必须通过 internal 测试入口 `handleChildChangeForTesting(token:)` 传入 rebind 前 token，断言 replacement offset 未变化且只出现一次 `scroll.binding.stale`。该入口只包一层 `childDidChange(token:)`，不进入 public API。

- [ ] **Step 5: 运行 coordinator 组合测试**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerScrollPositionResolverTests \
  -only-testing:AnchorPagerTests/AnchorPagerPanGestureDelegateProxyTests \
  -only-testing:AnchorPagerTests/AnchorPagerChildScrollBindingTests \
  -only-testing:AnchorPagerTests/AnchorPagerScrollCoordinatorTests \
  -only-testing:AnchorPagerTests/AnchorPagerLoggerTests test
```

Expected: 全部通过，0 failures；无逐帧普通日志断言失败。

- [ ] **Step 6: 自审并提交**

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

- [ ] **Step 1: 写 ViewController RED 测试**

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

- [ ] **Step 2: 运行 ViewController 测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

Expected: 新测试因没有 coordinator binding/terminal 接线而失败。

- [ ] **Step 3: 提取 container delegate**

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

- [ ] **Step 4: 接入 coordinator 与 committed rebind**

在 ViewController 增加：

```swift
private lazy var scrollCoordinator = AnchorPagerScrollCoordinator(
    containerScrollView: verticalScrollView
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

- [ ] **Step 5: 添加源码门禁测试**

读取 `Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift`、`Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift` 和 `Sources/AnchorPager/Public/AnchorPagerViewController.swift`，断言不存在对 `committedCurrentScrollView.delegate`、`childScrollView.delegate`、`scrollView.delegate` 的赋值；允许唯一既有 `verticalScrollView.delegate = verticalScrollDelegate`。同时断言生产源码不包含 `Task.detached`、`nonisolated(unsafe)` 或 `@unchecked Sendable`。

- [ ] **Step 6: 运行框架聚焦回归**

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

- [ ] **Step 7: 自审并提交**

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
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`

**Interfaces:**
- Consumes: public collapse delegate、public `verticalScrollView` 只读状态、Example page 自己拥有的 scroll delegate。
- Produces: 仅 Example target 可见的 `scroll-coordination-state` accessibility value；不扩大框架 API。

- [ ] **Step 1: 写 Example RED 单测和 UI 测试**

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

- [ ] **Step 2: 运行 Example 测试并确认 RED**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleTests \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSingleUpwardDragCollapsesHeaderThenContinuesIntoLongChild \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testExpandedTopPullUsesContainerBounceWithoutChildBounce test
```

Expected: 状态类型/元素不存在或 handoff 断言失败。

- [ ] **Step 3: 实现 Example-only 状态探针**

在 Example 文件新增 `ExampleScrollCoordinationState` 和一个 20×20 透明测试 control，identifier 固定为 `scroll-coordination-state`。`ExamplePagerViewController` 通过 public collapse delegate 与 `verticalScrollView` KVO 更新 container 状态；`ExampleScrollPageViewController` 由页面自身设置 `scrollView.delegate = self` 并通过 closure 回报 child distance/bounce。该 delegate 赋值属于业务 child 自己，不得移动到 AnchorPager framework。

状态字段固定为：

```swift
struct ExampleScrollCoordinationState: Equatable {
    var page: String
    var collapseProgress: CGFloat
    var childDistance: CGFloat
    var containerSawTopBounce: Bool
    var childSawTopBounce: Bool

    var accessibilityValue: String {
        String(
            format: "page=%@;collapse=%.2f;distance=%.2f;containerBounce=%d;childBounce=%d",
            page,
            collapseProgress,
            childDistance,
            containerSawTopBounce ? 1 : 0,
            childSawTopBounce ? 1 : 0
        )
    }
}
```

页面切换、reload 和每次测试启动必须重置 bounce flags，避免跨场景污染。

- [ ] **Step 4: 实现并稳定五个 UI 场景**

坐标使用页面内容中央，避开 navigation/tab bar 和横向边缘。用 predicate 等待状态，不使用固定 sleep。fallback 页无法直接读取内部 scroll offset时，以 `page=plain`、container bounce flag、plain content frame 和 Header/bar frame 作为替代自动化证据，并在计划验收记录中说明内部 fallback offset 已由框架集成测试覆盖。

- [ ] **Step 5: 运行 Example 聚焦与全量测试**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test
```

Expected: Example build 通过；全部单元/UI 测试 0 failures、0 skips。记录实际 test 数量与墙钟时间。

- [ ] **Step 6: 自审并提交**

确认测试探针只存在 Example target，框架 public API 无变化；Example 自己拥有的 child delegate 未被框架覆盖；UI 测试是真实 drag 且不靠 sleep。

```bash
git diff --check
git add Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift \
  Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift \
  Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git commit -m "验证纵向滚动真实手势交接"
```

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

- [ ] **Step 1: 更新接入和维护文档**

README 必须说明：

- AnchorPager 不设置业务 child `UIScrollView.delegate`；
- container/child handoff 与 committed current 语义；
- v0.5 顶部额外下拉临时由 container bounce；
- v0.5 不跨 owner 转移减速 velocity；
- 示例和日志过滤方式。

architecture/spec/task-list 必须记录真实完成范围，不提前勾选 v0.6/v0.7。

- [ ] **Step 2: 运行源码与文档门禁**

```bash
git diff --check
rg -n "Task\.detached|nonisolated\(unsafe\)|@unchecked Sendable|@preconcurrency" Sources/AnchorPager
rg -n "committedCurrentScrollView.*delegate|childScrollView.*delegate|scrollView\.delegate\s*=" \
  Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift \
  Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift \
  Sources/AnchorPager/Public/AnchorPagerViewController.swift
```

Expected: `git diff --check` 通过；unsafe 扫描无结果；child delegate 禁止项扫描无结果。ViewController 允许的 container delegate 赋值必须使用精确 `verticalScrollView.delegate = verticalScrollDelegate`，人工自审确认不属于 child。

- [ ] **Step 3: 运行完整验收**

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

- [ ] **Step 4: 执行代码自审**

逐项记录结论：public API、Tabman/Pageboy 泄漏、Pageboy containment/appearance、Store committed/pending、child delegate 绝对禁止项、container pan forwarding、KVO/target cleanup、guarded offset、inset ownership、临时 bounce、MainActor/析构、日志热路径、Example UI test、文档状态和验收命令。

- [ ] **Step 5: 执行独立复审门禁**

比较 v0.5 开始前提交 `d8367c9` 到实现 HEAD。Critical/Important 必须清零；任何职责闭环、代理覆盖、双 owner、terminal 前绑定 pending 或 UI test 不稳定都先修复并重跑对应 RED/GREEN，不以文档豁免。

- [ ] **Step 6: 根据真实结果更新状态并提交**

只有完整验收和独立复审通过后，才把 v0.5 标记完成并开放 v0.6；否则保留未完成状态并写明具体未通过命令。

```bash
git add README.md docs AGENTS.md
git commit -m "完成 v0.5 纵向滚动协调验收"
```

---

## 实施检查点

1. Task 1 后确认 resolver 不依赖 UIKit callback 顺序。
2. Task 2 后确认只代理 container pan，child pan delegate identity 不变。
3. Task 3 后确认业务 child `UIScrollView.delegate` 没有任何写入路径。
4. Task 4 后确认 handoff、guard、binding 和日志不复制 Store/Inset/Paging 职责。
5. Task 5 后确认只在 committed reload/selection complete/cancel terminal 后 rebind。
6. Task 6 后确认真实 drag 覆盖长页、短页、fallback、切页和唯一 container bounce。
7. Task 7 后确认完整测试、代码自审和独立复审均有记录。

## 计划自审

- Spec coverage：代理所有权、canonical distance、guarded update、临时 bounce、committed binding、资源清理、日志、UI test 与后续版本边界分别由 Task 1–7 覆盖。
- Type consistency：resolver `Position/Input` 由 Task 1 产出；proxy 和 binding 由 Task 2/3 产出；Task 4 只消费这些固定接口；Task 5 只消费 coordinator public-internal 方法。
- Scope：不实现 v0.6 overscroll mode，不实现 v0.7 完整 interaction state或跨 owner 惯性合成。
- Delegate gate：Framework 任何任务都不设置业务 child `UIScrollView.delegate`；只有 Example 业务 child 自己可拥有其 delegate。
- Placeholder scan：所有任务均给出固定文件、接口、测试名、命令、预期结果和提交边界，没有未决实现分支。
