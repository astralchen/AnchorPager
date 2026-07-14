# Header 双顶部行为稳定回弹实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留 Header 双顶部行为，通过纯内容高度、中立测量和 viewport presentation translation 修复可见 bounce 消失及回弹后 automatic Header 高度增长。

**Architecture:** LayoutEngine 统一两种顶部行为的分段栏基线，并把 top obstruction 排除在纯内容折叠距离之外。`AnchorPagerViewController` 在安全区下方的中立几何中测量 Header，继续用独立 `scrollRangeView` 定义稳定范围，负 offset 仅通过 `viewportView.transform` 映射为可见 UIKit bounce。

**Tech Stack:** Swift 6、iOS 14+、UIKit、Swift Package Manager、Tabman `4.0.1`、Pageboy `5.0.2`、XCTest、XCUITest。

**2026-07-14 修订状态：** 历史计划完成；首次无缓存时的 required zero-height 中立布局规则已被 bootstrap fitting seed 设计取代，修复计划待按 `2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement-design.md` 另行实施和验收。

## Global Constraints

- Package name、Library product、Module name 均为 `AnchorPager`。
- Minimum OS 为 iOS 14，Language 为 Swift 6，UI stack 为 UIKit。
- 保留 `AnchorPagerHeaderTopBehavior`、`topBehavior` 和两个现有枚举 case，不扩大 Public API。
- Tabman/Pageboy 类型只允许出现在 internal adapter，横向 page containment 仍由 adapter 执行。
- Header UIViewController containment 不得因测量 remove/re-add。
- 不修改 child scroll discovery、managed inset ownership、child scroll owner 或 overscroll owner。
- scroll range 不得读取当前 offset；bounce transform 不得参与 content size。
- UIKit 路径保持 MainActor，不使用异步延迟或不安全并发绕过。
- 所有生产代码变更必须先看到对应测试按预期失败。
- 复用当前 Booted iPhone 17、设备 UUID和固定 DerivedData，不主动 shutdown、reboot 或 clean。

## File Structure

- Modify: `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`：统一双顶部行为 canonical 几何。
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：中立测量、canonical/presentation 映射和 viewport bounce。
- Modify: `Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift`：双模式基线、纯内容折叠距离测试。
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：真实 margins Header、高度稳定、可见 bounce、range/context/log 测试。
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`：真实切换和下拉终态回归。
- Modify: `README.md`、`docs/requirements.md`、`docs/architecture.md`、`docs/task-list.md`：长期契约。
- Modify: 相关历史 spec/plan、新设计、本计划和 `AGENTS.md`：follow-up、实施记录和索引。

---

### Task 1: 统一 LayoutEngine 双顶部行为基线

**Files:**
- Modify: `Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift:50-125`
- Modify: `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift:57-85`

**Interfaces:**
- Consumes: `AnchorPagerLayoutEngine.Input.headerTopBehavior`
- Produces: 两种模式共享的 bar baseline
- Preserves: `ResolvedHeaderHeight` 仅表示纯内容高度

- [x] **Step 1: 先修改双模式几何测试**

新增：

```swift
func testTopBehaviorsKeepSameBarBaseline() {
    let inside = AnchorPagerLayoutEngine().layout(
        for: input(
            measuredHeaderHeight: 100,
            headerHeightMode: .fixed(max: 100, min: 20),
            headerTopBehavior: .insideSafeArea,
            topObstructionHeight: 44,
            contentOffsetY: 30
        )
    )
    let extended = AnchorPagerLayoutEngine().layout(
        for: input(
            measuredHeaderHeight: 100,
            headerHeightMode: .fixed(max: 100, min: 20),
            headerTopBehavior: .extendsUnderTopSafeArea,
            topObstructionHeight: 44,
            contentOffsetY: 30
        )
    )

    XCTAssertEqual(inside.barFrame.minY, extended.barFrame.minY)
    XCTAssertEqual(inside.headerFrame.height, 70)
    XCTAssertEqual(extended.headerFrame.height, 114)
    XCTAssertEqual(inside.resolvedHeaderHeight.collapsibleDistance, 80)
    XCTAssertEqual(extended.resolvedHeaderHeight.collapsibleDistance, 80)
}
```

更新既有 extends 断言：纯内容 108、顶部遮挡 116 时 Header frame 高度为 `224`；纯内容 160、offset 80 时 frame 高度为 `196`。

- [x] **Step 2: 运行 LayoutEngine 定向测试并确认 RED**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-dual-header-bounce -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests test
```

Expected: FAIL；旧实现使用 `max(content, obstruction)`，bar baseline 与 inside 不一致。

- [x] **Step 3: 实现最小纯计算修复**

```swift
let visibleContentHeight = Swift.max(
    resolvedHeaderHeight.collapsed,
    resolvedHeaderHeight.expanded - collapseOffset
)
let topPinY = bounds.minY + topObstructionHeight
let headerY: CGFloat
let headerFrameHeight: CGFloat
switch input.headerTopBehavior {
case .insideSafeArea:
    headerY = topPinY
    headerFrameHeight = visibleContentHeight
case .extendsUnderTopSafeArea:
    headerY = bounds.minY
    headerFrameHeight = topObstructionHeight + visibleContentHeight
}
let barY = topPinY + visibleContentHeight
```

- [x] **Step 4: 重跑 Task 1 测试并确认 GREEN**

Run: Step 2 相同命令。Expected: 全部 `AnchorPagerLayoutEngineTests` 通过。

- [x] **Step 5: 自审 Task 1**

确认未修改 Public API、managed inset、offset adjustment 或第三方边界；`collapsibleDistance` 不包含 obstruction。

---

### Task 2: 中立测量与 viewport presentation bounce

**Files:**
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift:487-600,1040-1090`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift:276-418`

**Interfaces:**
- Produces: `measureHeaderHeight(in:) -> CGFloat`
- Produces: `overscrollTranslationY: CGFloat`
- Produces: `layoutContext(for:translationY:) -> AnchorPagerLayoutContext`
- Preserves: `lastLayoutOutput` 为 canonical output

- [x] **Step 1: 新增真实 safe-area-sensitive Header helper**

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

- [x] **Step 2: 新增切换与重复测量稳定性测试**

新增 `testAutomaticHeaderHeightStaysStableAcrossTopBehaviorSwitchAndBounceSettlement`：在导航容器中记录 inside 初始 context，切到 extends 后断言 bar baseline 不变，再切回 inside，模拟 -24 → 0 并显式 reload，断言最终 Header 高度和 bar `minY` 等于初始值。

- [x] **Step 3: 新增负 offset 可见 bounce 测试**

新增 `testNegativeContainerOffsetTranslatesViewportAndLayoutContextWithoutChangingRange`，使用 fixed 120 Header：

```swift
let initialFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
let initialContentSize = pager.verticalScrollView.contentSize
pager.verticalScrollView.contentOffset = CGPoint(x: 0, y: -24)
pager.verticalScrollView.delegate?.scrollViewDidScroll?(pager.verticalScrollView)
window.layoutIfNeeded()
let bouncedFrame = headerHostView.convert(headerHostView.bounds, to: pager.view)
let bouncedContext = try XCTUnwrap(delegate.layoutContexts.last)

XCTAssertEqual(bouncedFrame.minY, initialFrame.minY + 24, accuracy: 0.5)
XCTAssertEqual(bouncedContext.headerFrame.minY, bouncedFrame.minY, accuracy: 0.5)
XCTAssertEqual(pager.verticalScrollView.contentSize, initialContentSize)
```

恢复 offset 为 0 后断言 actual frame 和 context 均回到初始位置。

- [x] **Step 4: 运行 Task 2 定向测试并确认 RED**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-dual-header-bounce -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testAutomaticHeaderHeightStaysStableAcrossTopBehaviorSwitchAndBounceSettlement -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testNegativeContainerOffsetTranslatesViewportAndLayoutContextWithoutChangingRange test
```

Expected: FAIL；旧实现污染 automatic height，且固定 viewport 不产生可见负 offset 位移。

- [x] **Step 5: 实现中立测量事务**

```swift
private func measureHeaderHeight(in environment: LayoutEnvironment) -> CGFloat {
    viewportView.transform = .identity
    headerViewHost.setTopOffset(environment.bounds.minY + environment.obstruction.top)
    headerHeightConstraint?.constant = lastMeasuredHeaderHeight ?? 0
    view.layoutIfNeeded()
    return headerViewHost.measure(
        in: CGSize(
            width: environment.bounds.width,
            height: UIView.layoutFittingCompressedSize.height
        )
    )
}
```

`updateVisibleLayout` 必须先获取 environment，再测量；只有最终 output 更新缓存、range、context、progress 和日志。

- [x] **Step 6: 实现 presentation translation 与 context 映射**

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

`applyLayoutOutput` 设置 transform 并派发 presentation-aware context，但继续保存 canonical `output`，结构日志也使用 canonical frame。

- [x] **Step 7: 运行完整控制器测试并确认 GREEN**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-dual-header-bounce -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test
```

Expected: PASS；热路径测试继续确认没有 `header.measure` 和普通 frame/inset 日志。

- [x] **Step 8: 自审 Task 2**

确认中立测量不破坏 containment、transform 不参与 range、context 与实际 frame 一致、delegate proxy 无循环、child 职责未提前实现。

---

### Task 3: 示例真实路径回归

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift:47-75`

**Interfaces:**
- Consumes: 现有 Header 顶部行为菜单
- Produces: 分段栏终态高度回归证据

- [x] **Step 1: 将 UI 回归从标题 minY 改为分段栏 minY**

```swift
let tabItem = app.descendants(matching: .any)["短页"]
XCTAssertTrue(tabItem.waitForExistence(timeout: 3))
let initialMinY = tabItem.frame.minY
```

保留 inside → extends → inside 和真实拖拽；predicate 比较 `tabItem.frame.minY`，覆盖截图 2 中 Header 高度增长导致的分段栏下移。

- [x] **Step 2: 运行 UI 回归**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/example-dual-header-bounce -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderReturnsAfterTopBehaviorSwitchAndPullDown test
```

Expected: PASS；复用 Booted 模拟器，不重启。实时 bounce 中间 frame 由同进程测试覆盖。

- [x] **Step 3: 自审 Task 3**

确认菜单和两个 top behavior 仍存在，UI test 覆盖真实菜单、拖拽和终态高度。

---

### Task 4: 文档、完整验证与最终自审

**Files:**
- Modify: `README.md`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-10-header-scroll-settlement-design.md`
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- Modify: `docs/superpowers/plans/2026-07-10-header-scroll-viewport.md`
- Modify: 新设计、本计划、`AGENTS.md`

- [x] **Step 1: 同步长期文档**

写明：双模式保留；切换只改变 Header 外框是否延伸；bar/content baseline 一致；height mode 和折叠距离表示纯内容；automatic 使用中立测量；range 保持稳定；负 offset 使用 viewport transform；layout context 使用实际可见坐标；后续 child/overscroll owner 不提前实现。

- [x] **Step 2: 扫描边界与差异**

```bash
rg -n "Tabman|Pageboy" Sources/AnchorPager/Public
rg -n "viewportView|scrollRangeView|overscrollTranslationY|measureHeaderHeight" Sources Tests docs
git diff --check
git status --short
```

Expected: Public 不泄漏第三方类型；旧单一沉浸式文档保持删除，所有其他改动可解释。

- [x] **Step 3: 运行完整核心测试**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-dual-header-bounce -parallel-testing-enabled NO -enableCodeCoverage NO test
```

Expected: exit 0、0 failures。

- [x] **Step 4: 运行完整示例测试和 generic build**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/example-dual-header-bounce -parallel-testing-enabled NO -enableCodeCoverage NO test
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-dual-header-bounce build
```

Expected: 两条命令 exit 0、0 failures。

- [x] **Step 5: 运行依赖和差异校验**

```bash
swift package resolve
git diff --check
git status --short
```

Expected: resolve 和 diff check 通过；状态中保留并解释用户原有删除及本任务改动。

- [x] **Step 6: 完成最终代码自审**

记录 Public API、Layout、Containment、Scroll/Inset、Bounce、并发/资源、日志、测试和文档九项结论。

## Plan Self-Review

- Spec coverage：Task 1 覆盖双模式 canonical 几何；Task 2 覆盖中立测量、presentation bounce、range、context 和日志；Task 3 覆盖真实路径；Task 4 覆盖文档、验证和自审。
- Placeholder scan：未发现占位符、模糊实现步骤或延后测试。
- Type consistency：`measureHeaderHeight(in:)`、`overscrollTranslationY`、`layoutContext(for:translationY:)`、`lastMeasuredHeaderHeight`、`lastLayoutOutput` 与现有类型一致。
- Scope：不修改 Paging adapter、Header containment、child inset、scroll discovery 或后续 owner/coordinator。
- TDD：Task 1 和 Task 2 均先新增真实失败测试，再实现最小修复；Task 3 用真实 UI 终态验证。

## Execution Record

- 按用户要求在 `codex/v0-2-layout` 当前 checkout 原地执行；保留用户已删除的旧单一沉浸式 spec/plan，不创建 worktree。
- 全程复用 Booted `iPhone 17`（`28B089AA-A03D-49CE-A037-D999D84E9606`）和固定 DerivedData，没有 shutdown、reboot 或 clean。
- 基线完整核心测试 exit 0。
- Task 1 RED：`AnchorPagerLayoutEngineTests` 执行 10 个测试、6 个失败、0 unexpected；旧 extends 高度为 `100/116`，旧双模式 bar baseline 为 `114 != 70`。
- Task 1 GREEN：LayoutEngine 定向测试 exit 0。
- Task 2 RED：负 offset 下实际 Header `minY == 62`，预期随 -24 offset 下移到 `86`；真实示例 UI 回归改为比较分段栏 `minY` 后超时失败。
- Task 2/3 GREEN：两个定向控制器测试 exit 0；完整 `AnchorPagerViewControllerTests` 35 个、0 失败；真实示例 UI 回归 exit 0。
- Task 2 中首次 RED 暴露测试临时 data source 被 weak 引用释放，修正为局部强持有后重新取得有效 RED；未把测试装配错误计作产品失败证据。
- 现有 Xcode/SwiftPM 仍提示 Tabman/Pageboy `PrivacyInfo.xcprivacy` unhandled resource；依赖版本和资源规则未变，不属于本修复引入。

## Final Verification

- 完整核心测试：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,id=28B089AA-A03D-49CE-A037-D999D84E9606' -derivedDataPath .build/xcodebuild-dual-header-bounce -resultBundlePath .build/results/core-final-20260711-0746.xcresult -parallel-testing-enabled NO -enableCodeCoverage NO test`，exit 0；xcresult 为 83 tests、83 passed、0 failed、0 skipped。
- 首次完整示例测试执行 11 个测试、1 个失败；失败项为示例旧 `max(content, obstruction)` 期望。更新为 `content + obstruction` 并增加切换前后 bar baseline 断言后，使用 `.build/results/example-final-2-20260711-0754.xcresult` 重跑，11 tests、11 passed、0 failed、0 skipped、exit 0。
- 示例 generic build：`xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-dual-header-bounce build`，exit 0。
- `swift package resolve` 首次在沙盒内因用户级 SwiftPM/clang 缓存权限失败；提升权限后使用现有缓存解析 Tabman 4.0.1、Pageboy 5.0.2，exit 0。
- 最终 Public DocC 和文档同步后重新运行完整核心测试，result bundle 为 `.build/results/core-fresh-final-20260711-0757.xcresult`：83 tests、83 passed、0 failed、0 skipped、exit 0。
- 最终 Public DocC 和文档同步后重新运行完整示例测试，result bundle 为 `.build/results/example-fresh-final-20260711-0759.xcresult`：11 tests、11 passed、0 failed、0 skipped、exit 0。
- 最终源码状态再次运行 generic iOS Simulator build 和 `swift package resolve`，两者均 exit 0。
- Xcode/SwiftPM 继续提示 Tabman/Pageboy 上游 `PrivacyInfo.xcprivacy` resource；不影响测试/build，且不是本次变更引入。

## Final Self-Review

- Public API：保留 `AnchorPagerHeaderTopBehavior`、`topBehavior` 和两个 case；未新增/删除 public 符号，Public 目录扫描无 Tabman/Pageboy 泄漏。
- Layout：resolved height/collapsible distance 只表示纯内容；top obstruction 只作为 inside 起点或 extends underlay；两种模式共享 bar/content baseline。
- Measurement：结构路径使用 safe-area-neutral 几何；临时约束不写入 last output、context、progress、range 或状态日志缓存。
- Containment/lifecycle：Header view/controller 不因测量 reparent 或重复 add/remove；paging adapter 和横向 page containment 职责未变。
- Scroll/Inset：range 不依赖 offset；未写入 child inset，未提前实现 child scroll owner、overscroll owner 或 interaction state。
- Bounce：仅使用 viewport transform 映射 UIKit 负 offset，不手工实现弹簧，不修改 content size；canonical output 与 presentation context 分离。
- 并发/资源：UIKit 路径继续由 MainActor 隔离；现有 weak-owner delegate proxy 不形成循环；未新增 observer、Task、KVO 或 display link。
- 日志/性能：滚动热路径继续复用缓存测量，不写逐帧普通 layout/inset 日志；中立测量复用既有 `header.measure` 结构日志，无新关键事件需要新增 category。
- 测试：LayoutEngine、真实 Header、negative offset、range/context/log、控制器相邻路径、示例菜单/拖拽终态均有自动化证据。
- 文档：README、requirements、architecture、task-list、历史 follow-up、新设计/计划和 AGENTS 索引已同步；旧单一沉浸式 spec/plan 保持用户删除状态。
