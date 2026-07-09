# AnchorPager v0.1 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 AnchorPager v0.1 的可编译 UIKit/Swift Package 基础，交付 Public API skeleton、日志门面、Header/Scroll/fallback 基础能力和 Tabman/Pageboy internal adapter 边界。

**Current Status:** v0.1 可视分页核心路径已完成。当前已创建可构建的 `AnchorPagerExample` 示例工程，并通过单元测试和 UI test 验证 Header、分段栏、页面内容、分段栏点击切页、横向滑动切页、public API 程序化切页、fallback page scroll host 和关键日志事件。本轮稳定化已补齐程序化 selection 确认后提交、cancel 不提前提交、Header 重复安装幂等和基础 layout context 回调。横向 page 的实际 containment 由 Tabman/Pageboy adapter 执行；纵向嵌套滚动协调、managed inset ownership、完整 page cache window 和 Tabman 驱动的 appearance lifecycle 语义按后续版本推进。

**Architecture:** `AnchorPagerViewController` 是唯一 public 容器入口；Public API 不暴露 Tabman/Pageboy 类型。Tabman/Pageboy adapter 执行横向 page containment，AnchorPager 维护 page identity、selection 和 reload 对外语义。Header、Children、Paging、Logging 按目录分层，v0.1 只实现可测试的基础承载和分页选择状态，不实现完整纵向滚动协调、overscroll owner 或尺寸变化状态机。

**Tech Stack:** Swift 6、iOS 14+、UIKit、Swift Package Manager、Tabman `from: "4.0.1"`、Pageboy `from: "5.0.2"`、XCTest。

## Global Constraints

- Package name、Library product、Module name 均为 `AnchorPager`。
- Minimum OS 为 iOS 14。
- Language 为 Swift 6。
- UI stack 为 UIKit。
- Package manager 为 Swift Package Manager。
- Horizontal paging 使用 Tabman + Pageboy。
- 横向 page 的实际 UIKit containment 由 Tabman/Pageboy adapter 执行，AnchorPager 不对同一 page view controller 重复 `addChild`。
- Tabman/Pageboy 类型只出现在 adapter/internal 层，不出现在 `Sources/AnchorPager/Public/`。
- Public API、data source、delegate、coordinator 状态更新保持 `@MainActor`。
- 只有直接操作 UIKit 状态或维护 UI lifecycle/coordinator 状态的内部类型整体使用 `@MainActor`；日志、断言、纯计算工具等非 UI 基础设施不得为了方便整体限制主线程。
- 不复制参考项目源码、public API 或命名。
- 不引入具体业务场景、内容类型、数据模型或场景命名。
- 不使用 `Task.detached` 绕过 actor 隔离。
- 不使用 `@unchecked Sendable`、`nonisolated(unsafe)`、`@preconcurrency` 粗暴压制并发问题。
- 新增关键事件必须通过 `AnchorPagerLogger` 记录，并用可注入 log sink 测试。
- 每个任务完成时运行对应测试；版本收尾运行 `git diff --check`、`swift package resolve` 和可用的 Xcode 测试命令。

---

### Task 1: Package 与目录骨架

**Files:**
- Create: `Package.swift`
- Create: `Sources/AnchorPager/Public/`
- Create: `Sources/AnchorPager/Core/`
- Create: `Sources/AnchorPager/Layout/`
- Create: `Sources/AnchorPager/Header/`
- Create: `Sources/AnchorPager/Children/`
- Create: `Sources/AnchorPager/Paging/`
- Create: `Sources/AnchorPager/Overscroll/`
- Create: `Sources/AnchorPager/Gesture/`
- Create: `Sources/AnchorPager/Logging/`
- Create: `Tests/AnchorPagerTests/`

**Interfaces:**
- Produces: Swift package target `AnchorPager` and test target `AnchorPagerTests`.

- [x] Step 1: 创建 `Package.swift`，设置 iOS 14、Swift 6、Tabman 4.0.1、Pageboy 5.0.2。
- [x] Step 2: 创建目录骨架。
- [x] Step 3: 运行 `swift package resolve`，预期能解析 Tabman/Pageboy。
- [x] Step 4: 运行 `git diff --check`，预期通过。

### Task 2: 日志基础设施

**Files:**
- Create: `Sources/AnchorPager/Logging/AnchorPagerLogger.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerLoggerTests.swift`

**Interfaces:**
- Produces: internal `AnchorPagerLogger`，`log` 不绑定 MainActor
- Produces: `AnchorPagerLogger.Category` with `lifecycle`、`layout`、`header`、`paging`、`children`、`scroll`、`inset`、`overscroll`、`gesture`、`accessibility`、`resource`
- Produces: `AnchorPagerLogger.Level`
- Produces: injectable `AnchorPagerLogger.sink`，sink 单独由 MainActor 隔离

- [x] Step 1: 先写日志 category、level 和 sink 捕获测试。
- [x] Step 2: 运行 logger 单测，预期因类型不存在失败。
- [x] Step 3: 实现 `AnchorPagerLogger`，底层用 `os.Logger`，`log` 支持非主线程调用，sink 用于测试。
- [x] Step 4: 运行 logger 单测，预期通过。

### Task 3: Public API Skeleton

**Files:**
- Create: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Create: `Sources/AnchorPager/Public/AnchorPagerConfiguration.swift`
- Create: `Sources/AnchorPager/Public/AnchorPagerProtocols.swift`
- Create: `Sources/AnchorPager/Public/AnchorPagerLayoutContext.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Interfaces:**
- Consumes: `AnchorPagerLogger`
- Produces: `@MainActor open class AnchorPagerViewController: UIViewController`
- Produces: `AnchorPagerViewControllerDataSource`
- Produces: `AnchorPagerViewControllerDelegate`
- Produces: `AnchorPagerHeaderContent`
- Produces: `AnchorPagerConfiguration` and nested configuration/value enums

- [x] Step 1: 先写空页、越界 no-op、reloadData clamp、lifecycle/paging 日志测试。
- [x] Step 2: 运行 Public API 测试，预期因类型不存在失败。
- [x] Step 3: 实现 Public API skeleton 和 DocC 注释。
- [x] Step 4: 运行 Public API 测试，预期通过。

### Task 4: Header 基础承载

**Files:**
- Create: `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerHeaderViewHostTests.swift`

**Interfaces:**
- Consumes: `AnchorPagerHeaderContent`
- Produces: `@MainActor internal final class AnchorPagerHeaderViewHost`
- Produces: `install(_:in:)`、`remove()`、`measure(in:)`

- [x] Step 1: 先写 UIView 承载、UIViewController containment、测量和日志测试。
- [x] Step 2: 运行 Header 测试，预期因 host 不存在失败。
- [x] Step 3: 实现 Header host 的 add/remove/measure。
- [x] Step 4: 运行 Header 测试，预期通过。

### Task 5: Child 基础管理

**Files:**
- Create: `Sources/AnchorPager/Children/AnchorPagerChildViewControllerStore.swift`
- Create: `Sources/AnchorPager/Children/AnchorPagerPageScrollHostViewController.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerChildViewControllerStoreTests.swift`

**Interfaces:**
- Produces: `@MainActor internal final class AnchorPagerChildViewControllerStore`
- Produces: `setViewControllers(_:in:)`、`viewController(at:)`、`removeAll()`
- Produces: fallback host for child without `UIScrollView`

- [x] Step 1: 先写 child add/remove containment、reload 清理和 fallback host 日志测试。
- [x] Step 2: 运行 Child 测试，预期因 store 不存在失败。
- [x] Step 3: 实现 Child store 和 fallback host。
- [x] Step 4: 运行 Child 测试，预期通过。

说明：本任务完成的是独立 `AnchorPagerChildViewControllerStore` 和 `AnchorPagerPageScrollHostViewController`。横向 page 的实际 containment 由 Tabman/Pageboy adapter 执行；后续 v0.4 应将该 store 重定位或替换为 page state store，不能把同一个 page view controller 再次交给主容器 `addChild`。

### Task 6: Scroll View Discovery

**Files:**
- Create: `Sources/AnchorPager/Public/UIViewController+AnchorPager.swift`
- Create: `Tests/AnchorPagerTests/UIViewControllerAnchorPagerTests.swift`

**Interfaces:**
- Produces: `UIViewController.anchorPagerScrollView`
- Produces: `UIViewController.anchorPagerUsesDefaultScrollViewLookup`
- Produces: `UIViewController.anchorPagerDefaultScrollView`

- [x] Step 1: 先写显式优先、默认 DFS、多候选顺序、hidden/alpha/userInteraction 过滤、关闭默认查找、不跨 child VC 的测试。
- [x] Step 2: 运行 Scroll Discovery 测试，预期因 extension 不存在失败。
- [x] Step 3: 实现 associated object 和确定性 DFS lookup。
- [x] Step 4: 运行 Scroll Discovery 测试，预期通过。

### Task 7: Tabman/Pageboy Adapter 最小边界

**Files:**
- Create: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Create: `Sources/AnchorPager/Paging/AnchorPagerTabBarAdapter.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerPublicSurfaceTests.swift`

**Interfaces:**
- Consumes: Tabman/Pageboy inside `Sources/AnchorPager/Paging/`
- Produces: internal adapter that accepts titles and child view controllers, and lets Tabman/Pageboy execute horizontal page containment
- Produces: source-level public surface test ensuring Public API has no `Tabman`/`Pageboy`

- [x] Step 1: 先写 public surface source scan 测试，确认 `Sources/AnchorPager/Public/` 不包含 `Tabman` 或 `Pageboy`。
- [x] Step 2: 运行 public surface 测试，预期先通过或因包未编译失败。
- [x] Step 3: 实现最小 adapter，禁用或绕开自动 child inset，并将分页事件收敛为 internal delegate。
- [x] Step 4: 运行 public surface 测试和 package 编译测试。

### Task 8: 文档与任务状态

**Files:**
- Create/Modify: `README.md`
- Create/Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`

**Interfaces:**
- Consumes: 已实现 API 名称和当前 known limitations。
- Produces: 接入者 README、维护者 architecture、已完成任务勾选。

- [x] Step 1: 写 README 的最小接入、Header UIView、Header UIViewController、显式 scroll view、无 UIScrollView child 示例。
- [x] Step 2: 写 architecture 的 public API 契约、adapter 边界、scroll lookup、日志策略和 v0.1 limitations。
- [x] Step 3: 更新 `docs/task-list.md` 中本计划已完成的条目。
- [x] Step 4: 运行 `git diff --check`。

### Task 9: 验收验证

**Files:**
- No source edits unless verification exposes defects.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: final verification evidence.

- [x] Step 1: 运行 `git diff --check`，预期通过。
- [x] Step 2: 运行 `swift package resolve`，预期通过。
- [x] Step 3: 运行 `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`，预期通过。
- [x] Step 4: 示例工程已创建，运行 `Examples/AnchorPagerExample.xcodeproj` build 和基础启动测试。

### Task 10: v0.1 主容器基础可视接线

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: `AnchorPagerHeaderViewHost`、`AnchorPagerPagingAdapter`
- Produces: `reloadData()` 后 Header、分段栏和当前页面内容可见的基础主容器路径

- [x] Step 1: 先写 `AnchorPagerViewController` 单测，验证 `reloadData()` 会把 Header 和 paging adapter 安装进主容器。
- [x] Step 2: 先写示例 UI test，验证启动后可看到 Header、分段栏和当前页面内容。
- [x] Step 3: 将 Header host 和 `AnchorPagerPagingAdapter` 串入 `AnchorPagerViewController`，并保持 Tabman/Pageboy 类型不进入 public API。
- [x] Step 4: 运行新增单测和 UI test，确认基础可视路径通过。

### Task 11: v0.1 收尾验证与 fallback 可见性修复

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Sources/AnchorPager/Children/AnchorPagerPageScrollHostViewController.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerChildViewControllerStoreTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`

**Interfaces:**
- Consumes: `AnchorPagerPageScrollHostViewController`、`AnchorPagerPagingAdapter`
- Produces: 无 UIScrollView child 在 fallback host 中可见
- Produces: 示例工程点击、横滑、public API 三种切页方式 UI 验收
- Produces: Tabman/Pageboy 回调缺失、重复或乱序日志
- Produces: reloadData 清理旧 fallback child 和 children 日志

- [x] Step 1: 先写 fallback host viewport 高度、主容器 fallback 包装、示例点击/横滑/API 切页 UI test。
- [x] Step 2: 观察新增测试失败，确认普通 child 在 fallback host 中高度为 0，public API 切页后“无滚动页”不可见。
- [x] Step 3: 实现主容器 fallback host 接入和 fallback content 最小 viewport 高度约束。
- [x] Step 4: 先写 Pageboy 回调异常日志和 reloadData 旧 fallback child 清理测试，并观察失败。
- [x] Step 5: 实现 adapter 回调异常日志和 reloadData stale fallback host 清理。
- [x] Step 6: 更新 README、architecture 和 task-list 反映 v0.1 当前状态。

### Task 12: v0.1 架构审查后稳定化收尾

**Files:**
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`
- Modify: `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerHeaderViewHostTests.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerPagingAdapterTests.swift`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`

**Interfaces:**
- Consumes: `AnchorPagerPagingAdapter` 的 Pageboy/Tabman selection callback
- Produces: 程序化选择事务，只有 Pageboy/Tabman 确认后才提交 public `selectedIndex` 和 delegate 通知
- Produces: Header host 幂等安装，重复安装同一个 UIView 或 UIViewController 不触发 remove/re-add containment
- Produces: v0.1 基础 `AnchorPagerLayoutContext` 回调，记录当前 Header frame 和 content frame
- Produces: 明确 v0.1 对未落地配置项、reload 非空闲策略和 scroll discovery 预加载行为的文档边界

- [x] Step 1: 先写选择事务测试，覆盖程序化切页请求不提前提交、didSelect 后提交、didCancel 不通知 delegate。
- [x] Step 2: 先写 adapter 测试，覆盖 `setSelectedIndex` 返回值、completion/cancel 日志、乱序回调和第二次请求被拒绝时保留首次 pending selection。
- [x] Step 3: 先写 Header host 幂等安装测试，覆盖同一 header view/controller 重复安装不移除重加。
- [x] Step 4: 先写基础布局回调测试，覆盖 `reloadHeaderLayout` 会重新测量并发送 layout context。
- [x] Step 5: 实现选择事务、adapter completion/cancel 处理、Header 幂等安装和 layout context 回调。
- [x] Step 6: 对本任务改动做代码自审，重点检查 Tabman/Pageboy 职责边界、UIKit containment/lifecycle、并发隔离、日志和测试覆盖。
- [x] Step 7: 更新 README、architecture、task-list，说明 v0.1 已修复项和仍归属后续版本的架构边界。
- [x] Step 8: 运行 `git diff --check`、SwiftPM resolve、可用的包测试和示例工程 build/UI test，并记录结果。

**Self-review record:**
- selection 事务：public `selectedIndex` 只由 adapter 终态回调提交；cancel 不通知 delegate；被拒绝的新请求不会清空已接受的上一笔 pending selection。
- Tabman/Pageboy 边界：第三方类型仍只出现在 `Sources/AnchorPager/Paging/` 和测试中，Public API 未暴露 Tabman/Pageboy。
- UIKit containment：Header 同内容重复安装 no-op；横向 page containment 仍由 adapter 执行，主容器不重复 `addChild` page。
- 并发隔离：未新增 `Task.detached`、`@unchecked Sendable`、`nonisolated(unsafe)` 或 `@preconcurrency`。
- 测试与文档：新增选择事务、Header 幂等和 layout context 测试；README、architecture、task-list 和本计划已同步更新。

## Verification Record

- `git diff --check`：通过。
- `swift package resolve`：通过，解析到 Tabman `4.0.1`、Pageboy `5.0.2`。沙盒内首次运行因 SwiftPM/clang 用户缓存目录权限失败，提升权限后通过。
- `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild test`：通过，43 个测试、0 失败。
- `xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild build`：通过。
- `xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-v01-ui -parallel-testing-enabled NO test`：通过，1 个示例工程单测和 5 个 UI test 通过。
- `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild -only-testing:AnchorPagerTests/AnchorPagerChildViewControllerStoreTests/testFallbackPageScrollHostKeepsPlainChildVisibleWithinViewport -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadDataWrapsChildWithoutScrollViewInFallbackHost -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadDataKeepsScrollViewChildUnwrapped test`：通过。
- `xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-v01-ui -parallel-testing-enabled NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testLaunchArgumentSelectsPageThroughPublicAPI -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalSwipeSelectsNextPageContent test`：通过。
- `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild -only-testing:AnchorPagerTests/AnchorPagerPagingAdapterTests/testAdapterLogsMissingDuplicateAndOutOfOrderPageboyCallbacks -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadDataRemovesStaleFallbackChildAndWritesChildrenLog test`：通过。
- `swift test --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios14.0-simulator --filter 'AnchorPager(ViewController|PagingAdapter|HeaderViewHost)Tests'`：源码和测试目标编译通过，随后 SwiftPM 尝试在 macOS 宿主加载 iOS-simulator XCTest bundle，因平台不兼容失败；该命令不能作为运行型测试结果。
- `swift build --build-tests --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios14.0-simulator`：通过，确认 AnchorPager 和新增 iOS Simulator 测试目标可编译。
- `xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild-v01-stabilization build`：通过。
- `xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild-v01-stabilization-ui -parallel-testing-enabled NO test`：通过，1 个示例工程单测和 5 个 UI test 通过。
- `git diff --check`：Task 12 收尾后通过。
- `swift package resolve`：沙盒内因 SwiftPM/clang 用户缓存权限失败，提升权限后通过。
