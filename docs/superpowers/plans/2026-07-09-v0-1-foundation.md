# AnchorPager v0.1 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 AnchorPager v0.1 的可编译 UIKit/Swift Package 基础，交付 Public API skeleton、日志门面、Header/Child/Scroll 基础能力和 Tabman/Pageboy internal adapter 边界。

**Current Status:** 已完成 v0.1 foundation 范围并提交到 `codex/v0-1-foundation`，并已创建可构建的 `AnchorPagerExample` 示例工程与基础启动 UI test。本计划覆盖的是基础设施、API 骨架、内部承载、scroll discovery、adapter 边界和示例工程接入；完整 v0.1 可视分页验收仍需要后续把 Header、Tabman/Pageboy adapter、child store 和 fallback host 串入 `AnchorPagerViewController`。

**Architecture:** `AnchorPagerViewController` 是唯一 public 容器入口；Public API 不暴露 Tabman/Pageboy 类型。Header、Children、Paging、Logging 按目录分层，v0.1 只实现可测试的基础承载和分页选择状态，不实现完整纵向滚动协调、overscroll owner 或尺寸变化状态机。

**Tech Stack:** Swift 6、iOS 14+、UIKit、Swift Package Manager、Tabman `from: "4.0.1"`、Pageboy `from: "5.0.2"`、XCTest。

## Global Constraints

- Package name、Library product、Module name 均为 `AnchorPager`。
- Minimum OS 为 iOS 14。
- Language 为 Swift 6。
- UI stack 为 UIKit。
- Package manager 为 Swift Package Manager。
- Horizontal paging 使用 Tabman + Pageboy。
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

说明：本任务完成的是独立 `AnchorPagerChildViewControllerStore` 和 `AnchorPagerPageScrollHostViewController`。`AnchorPagerViewController.reloadData()` 接入 child store 清理旧 child 属于完整主容器装配，仍保留在 `docs/task-list.md` 的未完成项中。

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
- Produces: internal adapter that accepts titles and child view controllers
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

## Verification Record

- `git diff --check`：通过。
- `swift package resolve`：通过，解析到 Tabman `4.0.1`、Pageboy `5.0.2`。
- `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcodebuild test`：通过，37 个测试、0 失败。
- `xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/example-xcodebuild build`：通过。
- `xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/example-xcodebuild test`：通过，1 个示例工程单测和 1 个基础启动 UI test 通过。
