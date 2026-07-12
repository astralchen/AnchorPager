# Swift 6.2 最低工具链基线实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 AnchorPager 的最低 SwiftPM/编译器工具链提升到 Swift 6.2，同时保持 Swift 6 language mode、iOS 14 运行基线和已验证的同步 MainActor 资源析构。

**Architecture:** Package manifest 以 `swift-tools-version: 6.2` 建立最低工具链门禁，target 继续使用 `.v6` language mode。UIKit 容器保留经资源析构测试验证的 `deinit + MainActor.assumeIsolated`；`isolated deinit` 的 Swift 6.2.4/x86_64 allocator crash 作为工具链限制记录，当前有效文档统一描述工具链与语言模式。

**Tech Stack:** Swift 6.2+ toolchain、Swift 6 language mode、Xcode 26.3、UIKit、Swift Package Manager、iOS 14+、XCTest、Tabman 4.0.1、Pageboy 5.0.2

## Global Constraints

- Package 最低 tools version 必须为 6.2。
- `swiftLanguageModes: [.v6]` 保持不变，不使用不存在的 `.v6_2`。
- Minimum OS 保持 iOS 14。
- `AnchorPagerViewController` deinit 必须同步归还 Store/inset ownership；当前保留 `MainActor.assumeIsolated`，不使用
  `isolated deinit`、Task 或 delay，直到后续工具链复验通过。
- 不使用 `nonisolated(unsafe)`、`@unchecked Sendable` 或 `@preconcurrency` 压制 Swift 6.2 并发诊断。
- 不修改 AnchorPager public API，不改变 Tabman 4.0.1/Pageboy 5.0.2 依赖边界。
- 当前有效基线文档统一写为“最低工具链 Swift 6.2，语言模式 Swift 6”。
- 已完成的历史计划保留原始 Swift 6 执行记录，只补当前基线引用，不机械改写历史证据。
- 复用已启动的 iPhone 17 simulator，不执行无必要 boot/shutdown。

---

### Task 1: Manifest 与同步 deinit 工具链门禁

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Create: `Tests/AnchorPagerTests/AnchorPagerSwiftToolchainBaselineTests.swift`

**Interfaces:**
- Produces manifest contract `// swift-tools-version: 6.2`。
- Keeps `swiftLanguageModes: [.v6]`。
- Keeps verified `deinit + MainActor.assumeIsolated` for synchronous MainActor cleanup。

- [ ] **Step 1: 恢复工作区中尚未经过 TDD 的工具链改动**

仅用 `apply_patch` 把本任务开始前未提交的工具链实验恢复到当前 HEAD 语义：

```swift
// swift-tools-version: 6.0
```

```swift
deinit {
    MainActor.assumeIsolated {
        pageStateStore.releaseAll()
        managedInsetCoordinator.releaseAll()
    }
    AnchorPagerLogger.log(.info, category: .lifecycle, event: "deinit")
}
```

不得触碰同时存在的 PagingHost Task 1 文件。

- [ ] **Step 2: 写工具链源码契约 RED 测试**

创建 `AnchorPagerSwiftToolchainBaselineTests`：

```swift
import XCTest

final class AnchorPagerSwiftToolchainBaselineTests: XCTestCase {
    func testPackageRequiresSwift62AndKeepsSwift6LanguageMode() throws {
        let manifest = try String(contentsOf: packageRoot().appendingPathComponent("Package.swift"))
        XCTAssertTrue(manifest.hasPrefix("// swift-tools-version: 6.2"))
        XCTAssertTrue(manifest.contains("swiftLanguageModes: [.v6]"))
    }

    func testPagerKeepsVerifiedSynchronousMainActorDeinit() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/AnchorPager/Public/AnchorPagerViewController.swift")
        )
        XCTAssertTrue(source.contains("MainActor.assumeIsolated"))
        XCTAssertFalse(source.contains("isolated deinit"))
    }

    private func packageRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent("Package.swift").path
            ) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
```

- [ ] **Step 3: 运行测试并确认 RED**

```bash
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerSwiftToolchainBaselineTests test
```

Expected: manifest tools version 断言失败；deinit 契约保持通过，证明工具链升级没有混入已知崩溃路径。

- [ ] **Step 4: 提升 manifest 并保持已验证 deinit**

```swift
// swift-tools-version: 6.2
```

保留：

```swift
swiftLanguageModes: [.v6]
```

ViewController 保持：

```swift
deinit {
    MainActor.assumeIsolated {
        pageStateStore.releaseAll()
        managedInsetCoordinator.releaseAll()
    }
    AnchorPagerLogger.log(.info, category: .lifecycle, event: "deinit")
}
```

- [ ] **Step 5: 运行工具链和资源析构回归**

```bash
swift --version
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AnchorPagerTests/AnchorPagerSwiftToolchainBaselineTests \
  -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testDeinitReleasesInsetOwnership \
  -only-testing:AnchorPagerTests/AnchorPagerPageStateStoreTests test
```

Expected: Swift 6.2+；源码契约和资源清理测试全部通过。

- [ ] **Step 6: 提交工具链门禁**

```bash
git add Package.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift \
  Tests/AnchorPagerTests/AnchorPagerSwiftToolchainBaselineTests.swift
git commit -m "提升最低工具链到 Swift 6.2"
```

---

### Task 2: 当前有效文档与完整验收

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `docs/requirements.md`
- Modify: `docs/task-list.md`
- Modify: `docs/architecture.md`
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- Modify: `docs/superpowers/specs/2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md`
- Modify: `docs/superpowers/specs/2026-07-12-v0-4-generation-atomicity-repair-design.md`
- Modify: `docs/superpowers/plans/2026-07-12-v0-4-generation-atomicity-repair.md`
- Modify: `docs/superpowers/plans/2026-07-12-swift-6-2-toolchain-baseline.md`

**Interfaces:**
- Documents the current normative baseline。
- Historical completed plans remain unchanged except explicit links where they are still used as current guidance。

- [ ] **Step 1: 同步技术基线表述**

统一使用：

```text
Minimum toolchain：Swift 6.2
Language mode：Swift 6
Minimum OS：iOS 14
```

README 增加构建要求；architecture 记录 Swift 6.2.4/x86_64 `isolated deinit` allocator crash，并保留
`MainActor.assumeIsolated` 的 UIKit 主线程析构约束。

- [ ] **Step 2: 审查历史与当前文档边界**

保留 v0.1–v0.4 已完成计划中的历史“Swift 6”执行文本；roadmap、requirements、task-list、AGENTS 和正在执行的
generation atomicity plan 必须明确最低工具链 Swift 6.2+、语言模式 Swift 6。fixed-paging spec 当前析构契约继续使用
已验证的 `deinit + MainActor.assumeIsolated`，并记录 `isolated deinit` 的 allocator crash 限制。

- [ ] **Step 3: 运行文档与 manifest 一致性检查**

```bash
rg -n "Minimum toolchain|最低工具链|swift-tools-version|swiftLanguageModes|MainActor.assumeIsolated|isolated deinit" \
  Package.swift AGENTS.md README.md docs Sources/AnchorPager/Public/AnchorPagerViewController.swift
git diff --check
```

Expected: 当前规范全部指向 Swift 6.2；生产源码保留 `MainActor.assumeIsolated` 且不包含 `isolated deinit`；历史记录
未被错误改写。

- [ ] **Step 4: 运行完整 Swift 6.2 验收**

```bash
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test
```

记录 Swift 版本、tests/fail/skip、耗时和第三方 privacy warnings。

- [ ] **Step 5: 自审并提交文档**

自审 Package/public API、iOS floor、Swift language mode、deinit 同步资源归还、已知 isolated deinit 工具链限制、
并发 unsafe 标记、历史文档和当前计划。

```bash
git add AGENTS.md README.md docs
git commit -m "同步 Swift 6.2 工具链文档基线"
```

---

## 实施检查点

1. Task 1 独立复审 manifest、language mode、deinit 同步清理和 isolated deinit crash 规避边界。
2. Task 2 完整验收通过后，恢复 v0.4 generation atomicity Task 1 GREEN。
3. Swift 6.2 变更不得混入 PagingHost request 实现提交。

## 计划自审

- 设计覆盖：manifest、language mode、已验证 deinit、已知 isolated deinit 限制、文档和完整验收均有明确任务。
- 类型一致：`.v6` 只表示 language mode；最低工具链只由 tools version 和文档表达。
- 范围：不修改 public API、iOS floor 或第三方版本。
- 占位符扫描：未发现未决项、空白步骤或模糊后续描述。
