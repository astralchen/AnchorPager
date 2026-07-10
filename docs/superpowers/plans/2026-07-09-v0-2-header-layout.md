# AnchorPager v0.2 Header 与布局稳定版实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Header 高度、安全区域、遮挡、吸顶 frame 和 `reloadHeaderLayout(offsetAdjustment:)` 固化为可测试的 v0.2 布局契约。

**Architecture:** v0.2 新增 `AnchorPagerLayoutEngine` 作为纯计算层，负责 Header 高度解析、折叠进度、Header/bar/content frame、safe area 本地遮挡和 managed inset 目标值计算。`AnchorPagerViewController` 只负责 UIKit 测量、读取当前 `verticalScrollView.contentOffset`、将 safe area layout frame 转为本地遮挡、应用约束和派发 delegate/log，不把第三方分页类型或内部状态词暴露到 public API。Header UIView/UIViewController containment 继续由 `AnchorPagerHeaderViewHost` 管理，横向 page containment 仍只由 Tabman/Pageboy adapter 执行。

**Tech Stack:** Swift 6、iOS 14+、UIKit、CoreGraphics、Swift Package Manager、Tabman `from: "4.0.1"`、Pageboy `5.0.2`、XCTest。

## Global Constraints

- Package name、Library product、Module name 均为 `AnchorPager`。
- Minimum OS 为 iOS 14。
- Language 为 Swift 6。
- UI stack 为 UIKit。
- Package manager 为 Swift Package Manager。
- Horizontal paging 使用 Tabman + Pageboy。
- Tabman/Pageboy 类型只允许出现在 adapter/internal 层，不得泄漏到 `Sources/AnchorPager/Public/`。
- 横向 page 的实际 UIKit containment 由 Tabman/Pageboy adapter 执行，AnchorPager 不对同一 page view controller 重复 `addChild`。
- Public API、data source、delegate、coordinator 状态更新保持 `@MainActor`。
- 纯计算布局引擎不绑定 MainActor，不操作 UIKit 对象。
- 不使用 `Task.detached`、`@unchecked Sendable`、`nonisolated(unsafe)` 或 `@preconcurrency` 粗暴压制并发问题。
- 新增关键布局、safe area、frame、inset 日志必须通过 `AnchorPagerLogger` 和 log sink 测试。
- 每个实现任务先写失败测试，再写实现；任务完成时运行对应测试和 `git diff --check`。
- 涉及 UI frame、safe area、navigation/tab/tool bar 的行为优先用同进程 UIKit 集成测试断言几何结果；UI test 无法稳定断言系统 bar 精确 frame 时，在本计划和验收记录中说明替代自动化验证。

---

## 影响范围评估

- Public API：不新增 public 类型或方法；仅补齐既有 `AnchorPagerHeaderHeightMode`、`AnchorPagerHeaderTopBehavior`、`AnchorPagerHeaderOffsetAdjustment` 行为。
- 内部分层：新增 `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`；`AnchorPagerViewController` 移除内嵌高度解析，改为调用 engine。
- UIKit containment：Header view controller 仍通过 `AnchorPagerHeaderViewHost` 标准 containment；v0.2 不改变横向 page containment。
- Child lifecycle：不改 Tabman/Pageboy page lifecycle，不接入 v0.4 page state store。
- Scroll discovery：不改变 v0.1 lookup 规则；只读取当前 `verticalScrollView.contentOffset` 参与 Header offset 策略。
- Inset ownership：v0.2 只计算并记录容器级 managed inset 目标值，完整 child inset 写入留给 v0.3。
- Paging adapter：不改变 public selection commit/cancel 语义，不扩展 adapter public surface。
- Gesture/overscroll：不实现 v0.5+ 滚动协调和 v0.6 overscroll owner，仅保证 layout reload 不破坏当前 offset。
- 日志：新增 `layout.headerHeightResolved`、`layout.headerFrameChanged`、`layout.barFrameChanged`、`layout.safeAreaChanged`、`layout.boundsChanged`、`inset.managedTargetChanged`。
- 测试：新增纯计算单测、UIKit 集成测试和日志测试；现有示例 UI test 继续作为可视路径回归。
- 示例工程和文档：v0.2 完成时更新 README、architecture、task-list 和本计划验收记录。

## File Structure

- Create: `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`
  - 纯计算布局引擎；输入 measured height、height mode、top behavior、bar height、bounds、safe area 本地遮挡、content offset；输出 Header/bar/content frame、resolved heights、collapse progress 和 managed inset target。
- Create: `Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift`
  - 覆盖 automatic/fixed/ranged、height clamp、insideSafeArea、extendsUnderTopSafeArea、offset adjustment 和 managed inset 目标值。
- Modify: `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`
  - 保持 containment 语义，补齐 UIViewController view fitting size 与 invalid measurement 日志/断言边界。
- Modify: `Tests/AnchorPagerTests/AnchorPagerHeaderViewHostTests.swift`
  - 补 Header view controller view fitting size、invalid measurement 和重复安装回归测试。
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
  - 调用 layout engine，应用 Header top/height 约束、paging height、`reloadHeaderLayout` 四种 offsetAdjustment、safe area/bounds 变化日志和 layout context。
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
  - 补 UIKit 集成测试：runtime header height、四种 offsetAdjustment、safe area top/bottom、navigation bar、tab bar、toolbar、additionalSafeAreaInsets 和日志。
- Modify: `README.md`
  - 说明 v0.2 Header height mode、top behavior 和 offset adjustment 当前契约。
- Modify: `docs/architecture.md`
  - 新增 LayoutEngine、safe area、Header runtime frame 和 v0.2 known limitations。
- Modify: `docs/task-list.md`
  - v0.2 对应任务按真实完成状态勾选，并记录 UI test 替代验证原因。
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
  - 每个任务完成后更新 checkbox、Self-review record 和 Verification Record。

## Task 1: LayoutEngine 纯计算契约

**Files:**
- Create: `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerLayoutEngineTests.swift`
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`

**Interfaces:**
- Consumes: `AnchorPagerHeaderHeightMode`、`AnchorPagerHeaderTopBehavior`、`AnchorPagerHeaderOffsetAdjustment`
- Produces: `struct AnchorPagerLayoutEngine`
- Produces: `AnchorPagerLayoutEngine.Input`
- Produces: `AnchorPagerLayoutEngine.Output`
- Produces: `AnchorPagerLayoutEngine.ResolvedHeaderHeight`
- Produces: `func layout(for input: Input) -> Output`
- Produces: `func adjustedContentOffsetY(current: CGFloat, old: Output?, new: Output, strategy: AnchorPagerHeaderOffsetAdjustment) -> CGFloat`

- [x] Step 1: 写失败测试 `testAutomaticHeightUsesMeasuredHeightClampedByMinAndMax`，断言 measured `120`、`.automatic(min: 40, max: 96)` 解析为 expanded `96`、collapsed `40`。
- [x] Step 2: 写失败测试 `testFixedHeightUsesMaxAsExpandedAndMinAsCollapsed`，断言 `.fixed(max: 88, min: 24)` 解析为 expanded `88`、collapsed `24`。
- [x] Step 3: 写失败测试 `testRangedHeightClampsMeasuredHeight`，断言 measured `20` 得到 expanded `64`，measured `160` 得到 expanded `120`。
- [x] Step 4: 写失败测试 `testInsideSafeAreaPlacesHeaderBelowTopObstruction`，断言 top obstruction `44` 时 Header `minY == 44`、bar 紧跟 Header。
- [x] Step 5: 写失败测试 `testExtendsUnderTopSafeAreaPlacesHeaderAtBoundsTop`，断言 top obstruction `44` 时 Header `minY == 0`、bar 吸顶基线仍不小于 `44`。
- [x] Step 6: 写失败测试 `testOffsetAdjustmentStrategiesReturnExpectedContentOffset`，覆盖 `.preserveVisualPosition`、`.preserveCollapseProgress`、`.resetToExpanded`、`.resetToCollapsed`。
- [x] Step 7: 运行 `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-layout-engine -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests test`，预期因类型不存在或断言失败而失败。
- [x] Step 8: 实现 `AnchorPagerLayoutEngine`，只 import `CoreGraphics`，不使用 UIKit 类型。
- [x] Step 9: 重新运行 Task 1 测试，预期通过。
- [x] Step 10: 运行 `git diff --check`。
- [x] Step 11: 自审纯计算边界、public API 泄漏、日志是否不应出现在 engine 内，并更新本计划 checkbox。

## Task 2: Header 测量边界补齐

**Files:**
- Modify: `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerHeaderViewHostTests.swift`
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`

**Interfaces:**
- Consumes: `AnchorPagerHeaderViewHost.measure(in:) -> CGFloat`
- Produces: Header UIViewController 测量顺序：`preferredContentSize.height` > view fitting size > bounds height > intrinsic height
- Produces: invalid measurement 时 Debug assertion，Release 降级为 `0`

- [x] Step 1: 写失败测试 `testMeasuresHeaderViewControllerFromViewFittingSizeWhenPreferredSizeIsEmpty`。
- [x] Step 2: 写失败测试 `testInvalidHeaderMeasurementFallsBackToZeroAndWritesLayoutLog`。
- [x] Step 3: 运行 `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-header -only-testing:AnchorPagerTests/AnchorPagerHeaderViewHostTests test`，预期新增测试失败。
- [x] Step 4: 调整 `AnchorPagerHeaderViewHost.measuredContentHeight(in:)`，让 UIViewController 在 preferred size 无效时继续测量其 view。
- [x] Step 5: 保持重复安装同一个 Header view/controller 的 no-op 语义不变。
- [x] Step 6: 重新运行 Task 2 测试，预期通过。
- [x] Step 7: 运行 `git diff --check`。
- [x] Step 8: 自审 Header containment、测量顺序、日志事件和测试覆盖，并更新本计划 checkbox。

## Task 3: ViewController 布局引擎接入

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`

**Interfaces:**
- Consumes: `AnchorPagerLayoutEngine.layout(for:)`
- Consumes: `AnchorPagerLayoutEngine.adjustedContentOffsetY(current:old:new:strategy:)`
- Produces: `reloadHeaderLayout(.preserveVisualPosition)` 保持当前视觉 offset
- Produces: `reloadHeaderLayout(.preserveCollapseProgress)` 保持折叠进度
- Produces: `reloadHeaderLayout(.resetToExpanded)` 将 `verticalScrollView.contentOffset.y` 设为 `-adjustedContentInsetTop`
- Produces: `reloadHeaderLayout(.resetToCollapsed)` 将 `verticalScrollView.contentOffset.y` 设为折叠上限
- Produces: delegate layout context 使用 engine 输出的 Header/bar/content frame

- [x] Step 1: 写失败测试 `testReloadHeaderLayoutPreservesVisualPositionWhenHeaderHeightChanges`。
- [x] Step 2: 写失败测试 `testReloadHeaderLayoutPreservesCollapseProgressWhenHeaderHeightChanges`。
- [x] Step 3: 写失败测试 `testReloadHeaderLayoutCanResetToExpandedAndCollapsed`。
- [x] Step 4: 写失败测试 `testRuntimeHeaderFrameChangeUpdatesLayoutContext`。
- [x] Step 5: 运行 `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-controller -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test`，预期新增测试失败。
- [x] Step 6: 将 `resolvedHeaderHeight(for:)` 替换为 layout engine 调用。
- [x] Step 7: 在 `reloadHeaderLayout(offsetAdjustment:)` 中先计算 old output，再测量并计算 new output，最后按策略设置 `verticalScrollView.contentOffset.y`。
- [x] Step 8: 应用 Header height constraint、paging height constraint 和 layout context。
- [x] Step 9: 重新运行 Task 3 测试，预期通过。
- [x] Step 10: 运行 `git diff --check`。
- [x] Step 11: 自审 `reloadData`、`setSelectedIndex`、Tabman adapter 边界和 offsetAdjustment 状态语义，并更新本计划 checkbox。

## Task 4: Safe Area 与本地遮挡集成

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`

**Interfaces:**
- Consumes: `view.safeAreaLayoutGuide.layoutFrame`
- Produces: local top obstruction `max(safeAreaLayoutGuide.layoutFrame.minY - view.bounds.minY, view.safeAreaInsets.top, additionalSafeAreaInsets.top, 0)`
- Produces: local bottom obstruction `max(view.bounds.maxY - safeAreaLayoutGuide.layoutFrame.maxY, view.safeAreaInsets.bottom, additionalSafeAreaInsets.bottom, 0)`
- Produces: `viewSafeAreaInsetsDidChange()` 触发布局更新

- [x] Step 1: 写失败测试 `testInsideSafeAreaUsesAdditionalSafeAreaInsetsTop`。
- [x] Step 2: 写失败测试 `testBottomObstructionDoesNotClipContentFrame`。
- [x] Step 3: 写失败测试 `testNavigationBarVisibilityChangesTopObstruction`，用 `UINavigationController` 承载 pager 并断言 context top 改变。
- [x] Step 4: 写失败测试 `testTabBarObstructionDoesNotClipContentFrame` 和 `testNavigationToolbarObstructionDoesNotClipContentFrame`，用 `UITabBarController` 与 `UINavigationController` toolbar 承载并断言 content frame 延伸到容器 bounds 底部。
- [x] Step 5: 运行 `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-safe-area -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test`，预期新增测试失败。
- [x] Step 6: 在 `AnchorPagerViewController` 中新增私有本地遮挡计算 helper，并在 `viewSafeAreaInsetsDidChange()`、`viewDidLayoutSubviews()` 后复用。
- [x] Step 7: 重新运行 Task 4 测试，预期通过。
- [x] Step 8: 运行 `git diff --check`。
- [x] Step 9: 自审 safe area 对非 root 容器、本地坐标转换、Header top behavior 和底部遮挡的覆盖，并更新本计划 checkbox。

## Task 5: v0.2 布局与 inset 日志

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`

**Interfaces:**
- Produces: `layout.headerHeightResolved`
- Produces: `layout.headerFrameChanged`
- Produces: `layout.barFrameChanged`
- Produces: `layout.safeAreaChanged`
- Produces: `layout.boundsChanged`
- Produces: `inset.managedTargetChanged`

- [x] Step 1: 写失败测试 `testHeaderAndBarFrameChangesWriteLayoutLogs`。
- [x] Step 2: 写失败测试 `testSafeAreaBoundsAndManagedInsetChangesWriteLogs`。
- [x] Step 3: 运行 `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-logs -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test`，预期新增日志测试失败。
- [x] Step 4: 在应用新 layout output 时比较上一帧，只有状态变化时记录日志，避免逐帧噪声。
- [x] Step 5: 重新运行 Task 5 测试，预期通过。
- [x] Step 6: 运行 `git diff --check`。
- [x] Step 7: 自审日志 category、event 命名、隐私数据和热路径噪声风险，并更新本计划 checkbox。

## Task 6: 文档、任务状态与版本验收

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`

**Interfaces:**
- Produces: README v0.2 Header/layout 接入说明
- Produces: architecture v0.2 LayoutEngine、safe area、offset adjustment 和 limitations
- Produces: task-list v0.2 勾选状态和验收记录

- [x] Step 1: 更新 README，说明 height mode、top behavior、`reloadHeaderLayout` 四种策略和当前 v0.2 不写 child inset 的限制。
- [x] Step 2: 更新 architecture，说明 LayoutEngine 输入输出、本地遮挡计算、Header frame 策略、日志策略和 known limitations。
- [x] Step 3: 更新 `docs/task-list.md` 中已完成的 v0.2 项，并说明 UI test 替代验证：系统 bar 精确几何由同进程 UIKit 集成测试覆盖，示例 UI test 保留可视路径回归。
- [x] Step 4: 运行 `git diff --check`。
- [x] Step 5: 运行 `swift package resolve`。
- [x] Step 6: 运行 `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-final test`。
- [x] Step 7: 运行 `xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild-v02 build`。
- [x] Step 8: 如可用，运行示例工程 UI test：`xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-v02-ui -parallel-testing-enabled NO test`。
- [x] Step 9: 完成代码自审，记录架构边界、public API、UIKit containment/lifecycle、并发隔离、日志、测试、文档和验收命令。

## Follow-up: 主容器滚动视图自动 inset 修复

**Problem:** `AnchorPagerViewController` 已经把 navigation bar、safe area 和其他系统遮挡转换为本地 obstruction 并应用到 Header/bar/content frame。如果 `verticalScrollView` 继续使用 UIKit 默认 `contentInsetAdjustmentBehavior`，系统会再次给主容器内容叠加 top inset，导致 Header 实际位置低于 `AnchorPagerLayoutContext.headerFrame`，示例工程中表现为 Header 与导航栏之间出现额外空白。

**Impact:** 不新增 public API，不改变 Tabman/Pageboy adapter 边界，不改变 Header view controller containment，不写入 child scroll view managed inset。影响范围只限 AnchorPager 自有 `verticalScrollView` 的 inset ownership，使 v0.2 的实际可见 Header frame 与 layout engine 输出一致。child scroll view 的 managed inset ownership 仍属于 v0.3。

- [x] Step 1: 写失败测试，验证导航控制器下 Header 实际 frame 与 `AnchorPagerLayoutContext.headerFrame` 一致。
- [x] Step 2: 将 AnchorPager 自有 `verticalScrollView.contentInsetAdjustmentBehavior` 设为 `.never`。
- [x] Step 3: 重新运行相关控制器测试和示例 UI test。
- [x] Step 4: 更新 README、architecture 和 task-list 中 v0.2/v0.3 的 inset 边界说明。
- [x] Step 5: 完成自审并记录验收命令。

## Follow-up: 横向区域延伸到容器底部

**Problem:** v0.2 早期实现把 bottom obstruction 直接从 content frame 高度中扣除，导致 tab bar、toolbar 或 bottom safe area 存在时，横向 paging adapter 停在安全区域上方。用户期望横向区域默认延伸到物理屏幕最底部，底部避让应由 child managed inset 负责。

**Impact:** 不新增 public API，不改变 Header view/controller containment，不改变 Tabman/Pageboy adapter 边界，不提前写入 child scroll view inset。影响范围只限 `AnchorPagerLayoutEngine` 的 content frame 底部计算，以及相关测试和文档。bottom obstruction 仍保留在 `managedInsetTarget.bottom`，供 v0.3 使用。

- [x] Step 1: 写失败测试，覆盖 LayoutEngine bottom obstruction 不裁剪 content frame，且保留 managed inset target。
- [x] Step 2: 更新控制器集成测试，覆盖 additional bottom safe area、tab bar 和 toolbar 下 content frame 仍到容器 bounds 底部。
- [x] Step 3: 将 content frame 底部改为 `bounds.maxY`。
- [x] Step 4: 重新运行相关控制器测试、示例测试和 `git diff --check`。
- [x] Step 5: 完成自审并记录验收命令。

## Follow-up: 无滚动页 fallback 底部延伸

**Problem:** 无候选 `UIScrollView` 的 child 会被内部 fallback scroll host 包装。fallback host 的根视图是 `UIScrollView`，如果继续使用 UIKit 默认 `.automatic` content inset，tab bar、toolbar 或 bottom safe area 会把 plain child 的可见底部抬高，使“无滚动页”没有延伸到横向 content frame 底部。

**Impact:** 不新增 public API，不改变 Tabman/Pageboy adapter 边界，不改变 Header containment，不写入接入方 child scroll view managed inset。影响范围只限 AnchorPager 内部 fallback scroll host 的自动 inset 策略，以及相关测试和文档。

- [x] Step 1: 写失败测试，断言 fallback scroll host 使用 `.never` content inset adjustment。
- [x] Step 2: 写集成测试，断言 `UITabBarController` 场景下 plain child 底部等于 `AnchorPagerLayoutContext.contentFrame.maxY`。
- [x] Step 3: 将 fallback scroll host 的 `scrollView.contentInsetAdjustmentBehavior` 设为 `.never`。
- [x] Step 4: 运行可用的编译、示例 UI tests 和 `git diff --check`。
- [x] Step 5: 完成自审并记录验收命令。

## UI Test 替代验证说明

v0.2 的 navigation bar、tab bar、toolbar、additionalSafeAreaInsets 几何行为需要精确断言 Header/bar/content frame。XCUITest 对系统 bar 精确 frame 暴露不稳定，且不同模拟器和系统版本可能产生像素级差异。本计划使用同进程 UIKit 集成测试创建 `UINavigationController`、`UITabBarController` 和 toolbar 场景，直接断言 `AnchorPagerLayoutContext` 的本地坐标结果；示例工程 UI test 继续作为可见路径回归，不作为几何精度断言来源。

## Self-review Record

- Task 1：`AnchorPagerLayoutEngine` 是 internal 纯计算类型，只 import `CoreGraphics`，不操作 UIKit 对象，不绑定 MainActor，不新增 public API。`Sources/AnchorPager/Public/` 和 `Sources/AnchorPager/Layout/` 未出现 Tabman/Pageboy 引用。Task 1 不新增关键日志事件，原因是 engine 只产出可比较结果，日志应由应用布局结果的 UIKit 层记录。测试覆盖 automatic/fixed/ranged 高度解析、safe area top behavior、bar 吸顶基线和四种 offset adjustment。
- Task 2：`AnchorPagerHeaderViewHost` 的 UIViewController containment 语义未改变，同 Header view/controller 重复安装仍保持 no-op。测量顺序固定为 preferredContentSize > view fitting size > bounds height > intrinsic height，负数或非有限测量会触发内部断言并记录 `layout/header.measure.invalid`，Release 路径降级为 0。Header、Layout 和 Public 目录未泄漏 Tabman/Pageboy。
- Task 3：`AnchorPagerViewController` 已改为通过 `AnchorPagerLayoutEngine` 生成 layout context，旧内嵌高度解析已移除。offset adjustment 只在显式 `reloadHeaderLayout(offsetAdjustment:)` 路径执行，普通 `viewDidLayoutSubviews` 不会主动改变 `verticalScrollView.contentOffset`。`reloadData`、`setSelectedIndex` 和 adapter selection commit/cancel 语义未改，Public API 未扩大。
- Task 4：本地遮挡从 `safeAreaLayoutGuide.layoutFrame`、`view.safeAreaInsets` 和 `additionalSafeAreaInsets` 取非负最大值，覆盖未入 window 的单元测试、非 root navigation/tab/toolbar 容器和显式 additional insets。Header host 只新增 internal top offset 约束，paging adapter 只跟随 engine 输出调整 top spacing 与高度，未改变 Header view controller containment 或 page containment。bottom obstruction 不裁剪横向区域，保留在 managed inset target 中。Task 4 不新增日志事件，原因是 safe area/bounds/frame/inset 变化日志按计划集中在 Task 5。
- Task 5：布局日志只记录状态变化，不在无变化的 `reloadHeaderLayout` 或布局 pass 中重复输出。事件名固定为 `layout.headerHeightResolved`、`layout.headerFrameChanged`、`layout.barFrameChanged`、`layout.safeAreaChanged`、`layout.boundsChanged` 和 `inset.managedTargetChanged`；日志内容只包含事件名，不输出用户内容、业务数据、完整 view 层级或几何数值。日志仍通过 `AnchorPagerLogger` sink 测试，未让 logger 绑定 MainActor。
- Task 6：README、architecture、task-list 和本计划均已同步 v0.2 状态。Public API 未新增类型或方法，Tabman/Pageboy 仍只出现在 internal adapter 和测试导入路径，Header containment 与横向 page containment 边界未改变。v0.2 验收使用同进程 UIKit 集成测试覆盖系统 bar 几何，示例 UI test 作为可视路径回归；child managed inset 写入、纵向嵌套滚动、overscroll、状态栏点击顶滚、尺寸变化恢复和 page lifecycle 仍按后续版本推进。
- Follow-up：主容器 `verticalScrollView.contentInsetAdjustmentBehavior = .never` 只改变 AnchorPager 自有滚动视图的 inset ownership，不新增 public API，不改变 Header view/controller containment，不改变 Tabman/Pageboy adapter 边界，也不写入 child scroll view managed inset。新增导航控制器集成测试直接断言 Header host frame 与 `AnchorPagerLayoutContext.headerFrame` 对齐，覆盖用户可见的导航栏下额外空白回归。示例 UI test 同步到当前四页示例页表，只修正测试期望，不回退示例工程已有改动。
- Follow-up：横向 content frame 底部现在固定到 `bounds.maxY`，bottom safe area、tab bar 和 toolbar 不再裁剪 paging adapter。bottom obstruction 仍通过 `managedInsetTarget.bottom` 保留给后续 child inset ownership。改动不新增 public API，不改变 Header view/controller containment，不改变 Tabman/Pageboy adapter 边界，也不提前写入 child scroll view inset。测试覆盖纯计算、additional bottom safe area、tab bar、toolbar、完整框架测试和示例 UI 路径。
- Follow-up：内部 fallback scroll host 现在禁用 UIKit 自动 content inset，避免无滚动页 plain child 在 tab bar/safe area 下被系统 inset 抬高底部。改动不新增 public API，不改变 Tabman/Pageboy adapter 边界，不改变 Header containment，也不写入接入方 child scroll view managed inset。新增测试覆盖 fallback host 的 inset 策略和 UITabBarController 场景下 plain child bottom 与 layout context contentFrame bottom 对齐。

## Verification Record

- `swift package resolve`：沙盒内因 SwiftPM/clang 用户缓存权限失败；提升权限后通过。
- `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-baseline test`：沙盒内因 CoreSimulatorService/Xcode 缓存权限失败；提升权限后通过，51 个测试、0 失败。
- Task 1 RED：`xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-layout-engine -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests test` 提升权限后失败，核心失败为 `Cannot find type 'AnchorPagerLayoutEngine' in scope`，符合测试先行预期。中途发现一次测试 helper 参数顺序语法错误，已修正后重跑。
- Task 1 GREEN：同一 `xcodebuild` 命令通过，`AnchorPagerLayoutEngineTests` 6 个测试、0 失败。
- `git diff --check`：Task 1 后通过。
- Task 2 RED：`xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-header -only-testing:AnchorPagerTests/AnchorPagerHeaderViewHostTests test` 提升权限后失败，核心失败为 `testInvalidHeaderMeasurementFallsBackToZeroAndWritesLayoutLog` 未收到 `header.measure.invalid`，符合测试先行预期。
- Task 2 GREEN：同一 `xcodebuild` 命令通过，`AnchorPagerHeaderViewHostTests` 9 个测试、0 失败。
- `git diff --check`：Task 2 后通过。
- Task 3 RED：`xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-controller -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test` 提升权限后失败，核心失败为三种 offset adjustment 未迁移 `contentOffset`。中途发现一次实现命名冲突和一次测试语义错误，已修正后重跑。
- Task 3 GREEN：同一 `xcodebuild` 命令通过，`AnchorPagerViewControllerTests` 19 个测试、0 失败。
- `git diff --check`：Task 3 后通过。
- Task 4 RED：`xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-safe-area -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test` 提升权限后失败，核心失败为 inside/additionalSafeAreaInsets、extendsUnderTopSafeArea、bottom obstruction、navigation bar 和 tab bar 几何断言未满足，符合测试先行预期。
- Task 4 GREEN：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-safe-area -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test` 提升权限后通过，`AnchorPagerViewControllerTests` 25 个测试、0 失败。
- `git diff --check`：Task 4 后通过。
- Task 5 RED：`xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-logs -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test` 提升权限后失败，核心失败为新增日志测试未捕获 layout/frame/safe area/inset 变化事件，符合测试先行预期。
- Task 5 GREEN：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-logs -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test` 提升权限后通过，`AnchorPagerViewControllerTests` 27 个测试、0 失败。
- `git diff --check`：Task 5 后通过。
- Task 6：`git diff --check` 通过。
- Task 6：`swift package resolve` 沙盒内因 SwiftPM/clang 用户缓存权限失败；提升权限后通过。
- Task 6：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-final test` 提升权限后通过，71 个测试、0 失败。
- Task 6：`xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild-v02 build` 提升权限后通过。
- Task 6：`xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-v02-ui -parallel-testing-enabled NO test` 提升权限后通过，6 个测试、0 失败。
- Follow-up RED：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-inset-followup -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testNavigationBarDoesNotDoubleApplyTopInsetToHeaderFrame test` 提升权限后失败，核心失败为主容器 `contentInsetAdjustmentBehavior` 仍是 `.automatic`，符合修复前预期。
- Follow-up GREEN：同一 `xcodebuild` 命令提升权限后通过，新增单测 1 个、0 失败。
- Follow-up：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-inset-followup -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests test` 提升权限后通过，28 个测试、0 失败。
- Follow-up：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-v02-inset-final test` 提升权限后通过，72 个测试、0 失败。
- Follow-up：`xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild-v02-inset build` 提升权限后通过。
- Follow-up：首次运行 `xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-v02-inset-ui -parallel-testing-enabled NO test` 提升权限后失败，失败原因是 UI test 仍按三页示例期望点击/断言，而当前示例工程已有四页页表。同步 UI test 期望后同一命令通过，6 个测试、0 失败。
- Follow-up：`swift package resolve` 沙盒内因 SwiftPM/clang 用户缓存权限失败；提升权限后通过。
- Follow-up：`git diff --check` 通过。
- Follow-up RED：新增 XCTest 后，`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-bottom-extends-red -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests/testBottomObstructionDoesNotClipContentFrameAndPreservesManagedInsetTarget test` 提升权限后卡在 Xcode 测试日志收尾，已终止，未作为 RED 证据。改用同一 LayoutEngine 源码的临时纯计算检查：`swiftc -module-cache-path .build/TempModuleCache Sources/AnchorPager/Public/AnchorPagerConfiguration.swift Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift /private/tmp/AnchorPagerLayoutRedCheck.swift -o /private/tmp/AnchorPagerLayoutRedCheck` 编译通过，`/private/tmp/AnchorPagerLayoutRedCheck` 修复前失败，输出 `RED: contentFrame.maxY=557.0, expected 640`。
- Follow-up GREEN：同一临时纯计算检查修复后通过，0 输出、exit 0。
- Follow-up GREEN：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-bottom-extends-green -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerLayoutEngineTests/testBottomObstructionDoesNotClipContentFrameAndPreservesManagedInsetTarget -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testBottomObstructionDoesNotClipContentFrame -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testTabBarObstructionDoesNotClipContentFrame -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testNavigationToolbarObstructionDoesNotClipContentFrame test` 提升权限后通过。
- Follow-up GREEN：`xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-bottom-extends-final -enableCodeCoverage NO test` 提升权限后通过。
- Follow-up GREEN：`xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild-bottom-extends build` 提升权限后通过。
- Follow-up GREEN：`xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-bottom-extends-ui -parallel-testing-enabled NO -enableCodeCoverage NO test` 提升权限后通过。
- Follow-up：`swift package resolve` 沙盒内因 SwiftPM/clang 用户缓存权限失败；提升权限后通过。
- Follow-up：`git diff --check` 通过。
- Follow-up RED：新增 fallback host 单测和 UITabBarController 集成测试后，尝试运行 `xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild-fallback-bottom-red -enableCodeCoverage NO -only-testing:AnchorPagerTests/AnchorPagerChildViewControllerStoreTests/testFallbackPageScrollHostContainsNonScrollChild -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testFallbackPageHostExtendsPlainChildToContentFrameBottomInTabBarController test`，提升权限请求被自动审批层拒绝，未获得断言级 RED 结果。普通 sandbox 重跑同一 package 测试失败在 CoreSimulatorService/用户缓存权限，未进入测试执行。
- Follow-up GREEN：XcodeBuildMCP `build_sim` 使用 `Examples/AnchorPagerExample.xcodeproj` 的 `AnchorPager` scheme 编译通过。
- Follow-up GREEN：XcodeBuildMCP `build_sim` 使用 `AnchorPagerExample` scheme 编译通过。
- Follow-up GREEN：XcodeBuildMCP `test_sim` 使用 `AnchorPagerExample` scheme、`-parallel-testing-enabled NO -enableCodeCoverage NO` 通过，7 个 UI tests、0 失败。
- Follow-up：`git diff --check` 通过。
