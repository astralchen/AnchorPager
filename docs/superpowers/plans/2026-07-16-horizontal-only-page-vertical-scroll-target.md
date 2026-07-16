# 横向业务页面纵向滚动目标语义修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让只包含横向业务 `UIScrollView` 的 Example 页面提交 nil 纵向 scroll target，消除横向拖动带动 `verticalScrollView`/Header 的错误协调，同时保持现有 Framework、Pageboy 和业务手势所有权边界。

**Architecture:** 修复发生在 Example 接入声明源头：关闭该页默认 scroll lookup，并不再把横向业务 scroll 写入 `anchorPagerScrollView`。Framework 继续复用 existing original Pageboy page + nil target 路径；DocC 和长期文档明确 `anchorPagerScrollView` 是纵向协调目标，不增加方向锁或轴向启发式。

**Tech Stack:** Swift 6.2、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、Tabman 4.0.1、Pageboy 5.0.2、Swift Testing、XCTest/XCUITest、Xcode 26.6、iPhone 17 Pro / iOS 26.5 Simulator。

## Global Constraints

- 设计基线固定为 `docs/superpowers/specs/2026-07-16-horizontal-only-page-vertical-scroll-target-design.md`。
- Public API symbol 不变；只补充 `anchorPagerScrollView` 与 default lookup opt-out 的既有语义。
- 不修改 `AnchorPagerScrollCoordinator`、`AnchorPagerContainerScrollView`、`AnchorPagerChildScrollBinding`、OverscrollCoordinator 或 Paging adapter。
- 不设置/替换业务 scroll delegate、pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。
- 不通过 `contentSize`、velocity 或 runtime class 猜测 scroll 轴向。
- 横向业务 scroll 自动优先于 Pageboy 仍不属于本修复交付能力。
- 严格执行 RED → 最小 GREEN → 聚焦回归 → 完整门禁 → 自审 → 中文单一主题提交。

---

### Task 1：用单元与真实 UI 固定错误目标声明

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: 现有 `UIViewController.anchorPagerScrollView`、`anchorPagerUsesDefaultScrollViewLookup`、`scroll-coordination-state` 与 `horizontal-business-probe`。
- Produces: 横向-only 页面 nil target 的单元契约，以及真实横向命中区域不驱动 container 的 UI 回归。

- [ ] **Step 1：修改 Example 单元测试形成 RED**

在 `horizontalBusinessPageIsFifthAndKeepsDelegateConfiguration()` 中保留页面 index、横向 range 与 ownership probe 断言，并把目标断言改为：

```swift
#expect(page.anchorPagerUsesDefaultScrollViewLookup == false)
#expect(page.anchorPagerDefaultScrollView == nil)
#expect(page.anchorPagerScrollView == nil)
```

- [ ] **Step 2：运行单元 RED**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:AnchorPagerExampleTests/AnchorPagerExampleTests/horizontalBusinessPageIsFifthAndKeepsDelegateConfiguration test
```

预期：FAIL，现有页面仍启用默认 lookup，且 `anchorPagerScrollView` 返回 `horizontalScrollView`。

- [ ] **Step 3：新增真实 UI RED**

新增 `testHorizontalBusinessRegionDoesNotDriveVerticalContainer()`：使用 `launchPage(index: 4, mode: "container")`，确认初始 `horizontal` 页为 nil target；重置 probe 后从 `horizontal-business-scroll` 内 `dx: 0.82, dy: 0.45` 拖到 `dx: 0.18, dy: 0.55`。最终断言：

```swift
XCTAssertFalse(state.hasScrollTarget)
XCTAssertLessThan(state.collapse, 0.01)
XCTAssertLessThan(abs(state.headerCollapse), 0.5)
XCTAssertTrue(state.hasZeroPresentationMetrics)
XCTAssertEqual(
    ownership.value as? String,
    "scrollDelegate=1;panDelegate=1;bounces=1;alwaysBounceVertical=0;isScrollEnabled=1;horizontalRange=1"
)
```

- [ ] **Step 4：运行 UI RED**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalBusinessRegionDoesNotDriveVerticalContainer test
```

预期：FAIL 于 `hasScrollTarget == false` 或 container/Header 稳定断言；不得通过放宽阈值掩盖目标声明错误。

---

### Task 2：最小修正 Example 纵向目标声明

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Test: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Test: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: `anchorPagerUsesDefaultScrollViewLookup` existing opt-out。
- Produces: original Pageboy page + nil committed vertical scroll target；业务横向 scroll 仍由 Example 自己管理。

- [ ] **Step 1：写最小实现**

在 `ExampleHorizontalPageViewController.viewDidLoad()` 中保留业务配置，但把：

```swift
anchorPagerScrollView = horizontalScrollView
```

替换为：

```swift
anchorPagerUsesDefaultScrollViewLookup = false
```

- [ ] **Step 2：运行单元 GREEN**

重复 Task 1 单元命令，预期 PASS。

- [ ] **Step 3：运行 UI GREEN**

重复 Task 1 UI 命令，预期 PASS；`verticalScrollView`/Header presentation 保持稳定，ownership probe 不变。

- [ ] **Step 4：运行相邻回归**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHorizontalSwipeSelectsNextPageContent \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainPageRootReachesPhysicalBottomAndUsesContainerOnlyPan \
  -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testSwitchingPagesRebindsVerticalOwnerWithoutJump test
```

预期：3/3 PASS，Pageboy 横向切页、plain nil target 与真实纵向 rebind 无回归。

---

### Task 3：同步接入契约、完整验收与自审

**Files:**
- Modify: `Sources/AnchorPager/Public/UIViewController+AnchorPager.swift`
- Modify: `README.md`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
- Modify: `docs/superpowers/specs/2026-07-15-v0-7-interaction-selection-momentum-design.md`
- Modify: `docs/superpowers/plans/2026-07-15-v0-7-interaction-selection-momentum.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: 本专项 RED/GREEN 与现有 v0.7 全量门禁。
- Produces: 纵向目标接入文档、最终测试/复审记录和恢复后的 v0.7 Ready 状态。

- [ ] **Step 1：更新 DocC 与长期文档**

明确：`anchorPagerScrollView` 是纵向协调目标；horizontal-only 页面关闭默认 lookup 且不显式设置；混合页面只登记纵向父 scroll；默认 lookup 不做轴向推断。记录本修复不改变业务横向 scroll 与 Pageboy 的 winner 限制。

- [ ] **Step 2：运行静态门禁**

```bash
git diff --check
rg -n 'import (Tabman|Pageboy)' Sources/AnchorPager/Public
rg -n '\.(delegate|isScrollEnabled|bounces|alwaysBounceVertical)\s*=' Sources/AnchorPager/Children Sources/AnchorPager/Gesture Sources/AnchorPager/Core Sources/AnchorPager/Paging
```

预期：Public 无第三方 import；Framework 没有新增业务 child ownership 写入；本专项不修改 Gesture/Core/Paging 生产实现。

- [ ] **Step 3：运行 Framework 全量**

```bash
xcodebuild -scheme AnchorPager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -resultBundlePath /private/tmp/AnchorPagerHorizontalVerticalTargetFramework-20260716.xcresult test
```

- [ ] **Step 4：运行 Example 全量与 generic build**

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/AnchorPagerHorizontalVerticalTargetExample-20260716.xcresult test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj \
  -scheme AnchorPagerExample \
  -destination 'generic/platform=iOS Simulator' \
  -resultBundlePath /private/tmp/AnchorPagerHorizontalVerticalTargetBuild-20260716.xcresult build
```

- [ ] **Step 5：检查 xcresult、运行时问题与需求覆盖**

使用 `xcresulttool` 记录 test count、fail/skip/error/warning/analyzer warning；检索 UIKit constraints、gesture cycle、appearance 与 resource lifecycle 问题。逐项对照本设计目标、非目标和停机条件。

- [ ] **Step 6：执行代码自审**

检查 Public API、Tabman/Pageboy containment、child lifecycle、scroll discovery、managed inset、snapshot、container simultaneous pair、overscroll、日志、MainActor、Example probe、UI 测试和文档；确认 Framework 生产滚动/手势文件零改动。

- [ ] **Step 7：提交**

```bash
git add AGENTS.md README.md Sources/AnchorPager/Public/UIViewController+AnchorPager.swift Examples docs
git commit -m "修复横向页面纵向滚动目标"
```

提交前必须运行 `git diff --check`；只有完整门禁和自审均有新鲜证据后，才能把专项与 v0.7 恢复为 Ready。

## 计划自审

1. **规格覆盖：** Task 1 固定根因 RED，Task 2 只实施源头声明修复，Task 3 覆盖 DocC、全量门禁、自审和状态恢复。
2. **占位符扫描：** 无 TODO、TBD、“稍后处理”或未选择方案。
3. **类型一致性：** 全程复用现有 Public `anchorPagerScrollView`、`anchorPagerUsesDefaultScrollViewLookup` 与 Example probe，不引入新 symbol。
4. **边界一致性：** 未安排任何 ScrollCoordinator、ContainerScrollView、PagingAdapter、业务 delegate 或 bounce 修改；Pageboy winner 限制保持独立。
