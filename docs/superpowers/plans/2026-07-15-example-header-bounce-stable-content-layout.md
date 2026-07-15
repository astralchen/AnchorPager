# Example Header 顶部回弹内容稳定布局实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 正式保留 Example Header 的顶部安全下限与底部稳定锚点，并用同进程和真实手势自动化证明跨越完整顶部遮挡时文字相对 Header 顶部距离不变。

**Architecture:** AnchorPager framework、container raw/logical offset、Header 固定高度 presentation 与 overscroll owner 全部保持不变。Example 在现有 scroll coordination probe 中增加只读 Header 内容局部距离采样；`ExampleHeaderView` 使用 `top >= safeArea.top + 20`、`bottom == safeArea.bottom - 20`，让动态顶部 safe area 只作为安全下限，底部 guide 负责稳定局部位置。

**Tech Stack:** Swift 6.2+、Swift 6 language mode、UIKit、Swift Testing、XCTest/XCUITest、Swift Package Manager、Xcode 26.6、iOS 14+。

## Global Constraints

- Package、library product 与 module name 均为 `AnchorPager`。
- Minimum toolchain 为 Swift 6.2，language mode 为 Swift 6，minimum OS 为 iOS 14。
- UI stack 只使用 UIKit；horizontal paging 继续由 Tabman 4.0.1 与 Pageboy 5.0.2 internal adapter 负责。
- 不新增或修改 Public API，不把 Tabman/Pageboy 类型泄漏到 Public。
- 不修改业务 child `UIScrollView.delegate`、pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。
- 不修改 AnchorPager Header 高度、container inset、raw/logical offset、LayoutContext、scroll/overscroll owner 或日志热路径。
- Header UIViewController 与 Pageboy page containment、generation/cache/snapshot、managed inset ownership 保持原 owner。
- 所有源码与测试说明使用中文；每项实现遵循 RED → GREEN，并在提交前运行 `git diff --check`。
- 用户已有的 `Examples/AnchorPagerExample.xcodeproj/project.pbxproj` 修改不属于本任务，不暂存、不提交、不回滚。

---

### Task 1: 用真实显示帧门禁正式保留 Example Header 约束

**Files:**
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift`
- Modify: `Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift`

**Interfaces:**
- Consumes: `AnchorPagerLayoutContext` 的最终可见 Header frame、现有 `scroll-coordination-state` accessibility probe、`ExampleHeaderView` 当前 automatic Auto Layout 内容。
- Produces: `ExampleScrollCoordinationState.headerContentTopDistance: CGFloat`、`maximumHeaderContentTopDistanceDelta: CGFloat`、`recordHeaderContentTopDistance(current:baseline:)`，以及真实 container top drag 的局部内容稳定门禁。
- Preserves: `top >= safeArea.top + 20`、`bottom == safeArea.bottom - 20`，Header 高度固定、标题/副标题 intrinsic height 与 `8 pt` 间距。

- [x] **Step 1: 扩展状态模型和单元测试，先定义可观测契约**

在 `ExampleScrollCoordinationState` 的存储属性末尾增加：

```swift
var headerContentTopDistance: CGFloat = 0
var maximumHeaderContentTopDistanceDelta: CGFloat = 0
```

在 `accessibilityValue` 数组末尾增加：

```swift
"headerContentTop=\(formatted(headerContentTopDistance))",
"headerContentTopDeltaMax=\(formatted(maximumHeaderContentTopDistanceDelta))"
```

在 `resetPresentationMetrics()` 中只清零累计变化，保留当前距离作为稳定状态：

```swift
maximumHeaderContentTopDistanceDelta = 0
```

增加状态记录方法：

```swift
mutating func recordHeaderContentTopDistance(
    current: CGFloat,
    baseline: CGFloat
) {
    headerContentTopDistance = current
    maximumHeaderContentTopDistanceDelta = max(
        maximumHeaderContentTopDistanceDelta,
        abs(current - baseline)
    )
}
```

扩展 `scrollCoordinationStateSerializesStableAccessibilityValue()`：在 memberwise initializer 末尾传入

```swift
headerContentTopDistance: 88,
maximumHeaderContentTopDistanceDelta: 0.4
```

并让预期字符串以以下字段结束：

```text
;headerContentTop=88.00;headerContentTopDeltaMax=0.40
```

扩展 `plainScrollCoordinationStateReportsNoScrollTarget()` 的预期字符串，以以下字段结束：

```text
;headerContentTop=0.00;headerContentTopDeltaMax=0.00
```

扩展 `scrollCoordinationStateResetsPresentationMetrics()` 的 initializer：

```swift
headerContentTopDistance: 88,
maximumHeaderContentTopDistanceDelta: 4
```

在 reset 后增加：

```swift
#expect(state.headerContentTopDistance == 88)
#expect(state.maximumHeaderContentTopDistanceDelta == 0)
```

扩展 `scrollCoordinationStateRecordsStableHeaderGeometry()`，在现有 Header frame 断言后执行：

```swift
state.recordHeaderContentTopDistance(current: 87.8, baseline: 88)
state.recordHeaderContentTopDistance(current: 88.4, baseline: 88)

#expect(abs(state.headerContentTopDistance - 88.4) < 0.001)
#expect(abs(state.maximumHeaderContentTopDistanceDelta - 0.4) < 0.001)
```

- [x] **Step 2: 在 Example 中增加只读 Header 内容几何探针**

在 `ExamplePagerViewController` 的 Header baseline 属性旁增加：

```swift
private weak var exampleHeaderView: ExampleHeaderView?
private var expandedHeaderContentTopDistance: CGFloat?
```

把 `headerContent(in:)` 改为显式保留当前 Example Header 弱引用：

```swift
func headerContent(
    in pagerViewController: AnchorPagerViewController
) -> AnchorPagerHeaderContent {
    let headerView = ExampleHeaderView()
    exampleHeaderView = headerView
    return .view(headerView)
}
```

在 `ExampleHeaderView` 把局部 `stackView` 提升为属性：

```swift
private let stackView = UIStackView()

var contentTopDistance: CGFloat {
    layoutIfNeeded()
    return stackView.frame.minY - bounds.minY
}
```

`configure()` 中用同一个属性添加 arranged subviews：

```swift
stackView.addArrangedSubview(titleLabel)
stackView.addArrangedSubview(subtitleLabel)
stackView.axis = .vertical
stackView.spacing = 8
stackView.translatesAutoresizingMaskIntoConstraints = false
addSubview(stackView)
```

保留用户已经验证的正式约束：

```swift
NSLayoutConstraint.activate([
    stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
    stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
    stackView.topAnchor.constraint(
        greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor,
        constant: 20
    ),
    stackView.bottomAnchor.constraint(
        equalTo: safeAreaLayoutGuide.bottomAnchor,
        constant: -20
    )
])
```

在 `ExamplePagerViewController` 增加只读采样方法：

```swift
private func recordHeaderContentGeometry(isStable: Bool) {
    guard let exampleHeaderView else { return }
    let currentTopDistance = exampleHeaderView.contentTopDistance

    if isStable && scrollCoordinationState.collapseProgress <= 0.01 {
        expandedHeaderContentTopDistance = currentTopDistance
    }

    guard let baseline = expandedHeaderContentTopDistance else {
        scrollCoordinationState.headerContentTopDistance = currentTopDistance
        return
    }

    scrollCoordinationState.recordHeaderContentTopDistance(
        current: currentTopDistance,
        baseline: baseline
    )
}
```

在 `recordContainerPresentation(_:)` 计算 `isStable` 并记录 Header frame 后、更新 accessibility control 前调用：

```swift
recordHeaderContentGeometry(isStable: isStable)
```

在 `resetHeaderGeometryBaseline()` 末尾加入：

```swift
expandedHeaderContentTopDistance = nil
```

探针只能读取 Example Header 本地 frame；不得设置 offset、触发 layout reload 或改变任何 AnchorPager owner。

- [x] **Step 3: 扩展同进程测试覆盖跨越完整顶部遮挡**

在 `headerContentUsesSafeAreaForVerticalPaddingInBothTopBehaviors()` 的每种静止行为断言中，把旧顶部等式/底部上限改为正式契约：

```swift
let safeAreaFrame = headerView.safeAreaLayoutGuide.layoutFrame
#expect(stackView.frame.minY >= safeAreaFrame.minY + 20 - 0.5)
#expect(abs(stackView.frame.maxY - (safeAreaFrame.maxY - 20)) < 0.5)
```

在 `.extendsUnderTopSafeArea` 分支记录完整局部几何与初始 context：

```swift
let initialHeaderHeight = headerView.bounds.height
let initialStackFrame = stackView.frame
let initialTitleFrame = titleLabel.frame
let initialSubtitleFrame = subtitleLabel.frame
let initialContext = try #require(layoutProbe.layoutContexts.last)
let topObstruction = max(
    headerView.safeAreaInsets.top,
    safeAreaFrame.minY - headerView.bounds.minY
)
let overflowSamples = [
    max(24, topObstruction * 0.5),
    max(48, topObstruction + 24)
]
```

逐个进入真实 top overflow，并让 UIKit 完成相邻 run-loop 布局：

```swift
for overflow in overflowSamples {
    pagerViewController.verticalScrollView.contentOffset = CGPoint(
        x: 0,
        y: -overflow
    )
    await Task.yield()
    window.layoutIfNeeded()

    let bouncedContext = try #require(layoutProbe.layoutContexts.last)
    #expect(abs(headerView.bounds.height - initialHeaderHeight) < 0.5)
    #expect(abs(stackView.frame.minY - initialStackFrame.minY) < 0.5)
    #expect(abs(stackView.frame.maxY - initialStackFrame.maxY) < 0.5)
    #expect(abs(titleLabel.frame.minY - initialTitleFrame.minY) < 0.5)
    #expect(abs(titleLabel.frame.height - initialTitleFrame.height) < 0.5)
    #expect(abs(subtitleLabel.frame.minY - initialSubtitleFrame.minY) < 0.5)
    #expect(abs(subtitleLabel.frame.height - initialSubtitleFrame.height) < 0.5)
    #expect(abs(subtitleLabel.frame.minY - titleLabel.frame.maxY - 8) < 0.5)
    #expect(bouncedContext.headerFrame.minY > initialContext.headerFrame.minY + 1)
    #expect(
        abs(
            (bouncedContext.barFrame.minY - initialContext.barFrame.minY)
                - (bouncedContext.headerFrame.minY - initialContext.headerFrame.minY)
        ) < 0.5
    )
}

pagerViewController.verticalScrollView.contentOffset = .zero
await Task.yield()
window.layoutIfNeeded()
#expect(abs(stackView.frame.minY - initialStackFrame.minY) < 0.5)
#expect(abs(headerView.bounds.height - initialHeaderHeight) < 0.5)
```

- [x] **Step 4: 扩展真实 UI 状态解析和顶部回弹用例**

在 UI test 私有 `ScrollCoordinationState` 增加：

```swift
let headerContentTop: CGFloat
let headerContentTopDeltaMax: CGFloat
```

在 `hasZeroPresentationMetrics` 增加：

```swift
&& headerContentTopDeltaMax < 0.5
```

在解析 guard 末尾增加：

```swift
let headerContentTopValue = fields["headerContentTop"],
let headerContentTop = Double(headerContentTopValue),
let headerContentTopDeltaMaxValue = fields["headerContentTopDeltaMax"],
let headerContentTopDeltaMax = Double(headerContentTopDeltaMaxValue)
```

在 initializer 赋值末尾增加：

```swift
self.headerContentTop = CGFloat(headerContentTop)
self.headerContentTopDeltaMax = CGFloat(headerContentTopDeltaMax)
```

扩展 `testPlainContainerTopBounceIsVisible()`：先等待 Header 内容 baseline 并重置累计值，再执行现有真实 drag：

```swift
XCTAssertNotNil(waitForScrollState(from: probe) {
    $0.headerContentTop > 1 && $0.headerContentTopDeltaMax < 0.5
})
probe.tap()

drag(in: app, from: 0.30, to: 0.72)
```

取得现有 bounce state 后增加：

```swift
XCTAssertGreaterThan(state.containerTopMax, 1)
XCTAssertLessThan(state.headerHeightDeltaMax, 0.5)
XCTAssertLessThan(state.headerContentTopDeltaMax, 0.5)
```

- [x] **Step 5: 在临时 worktree 验证旧约束形成正确 RED**

先按 `superpowers:using-git-worktrees` 的安全检查创建只用于 RED 的 detached worktree：

```bash
git worktree add --detach /private/tmp/AnchorPagerExampleHeaderRED 39de95c
```

把主工作区本 Task 的四个文件 diff 应用到临时 worktree；随后只在临时 worktree 把 Example Header 约束恢复为旧语义：

```bash
git diff --binary -- Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift | git -C /private/tmp/AnchorPagerExampleHeaderRED apply -
```

使用 `apply_patch` 只替换临时 worktree 的两条关系：

```swift
stackView.topAnchor.constraint(
    equalTo: safeAreaLayoutGuide.topAnchor,
    constant: 20
)
stackView.bottomAnchor.constraint(
    lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor,
    constant: -20
)
```

运行临时 worktree 的聚焦单元与真实 UI：

```bash
cd /private/tmp/AnchorPagerExampleHeaderRED
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/AnchorPagerExampleHeaderREDData -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerExampleTests/AnchorPagerExampleTests/headerContentUsesSafeAreaForVerticalPaddingInBothTopBehaviors test
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/AnchorPagerExampleHeaderREDData -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainContainerTopBounceIsVisible test
```

Expected: 至少真实 UI 用例因 `headerContentTopDeltaMax >= 0.5` 失败；同进程测试如果 UIKit 在该测试宿主中传播完整局部 safe area，也应在本地 frame 断言失败。Header height 与 container top presentation 断言必须通过，证明失败只来自文字相对 Header 顶部漂移。

保留失败摘要后移除临时 worktree：

```bash
cd /Users/sondra/Documents/GitHub/AnchorPager
git worktree remove /private/tmp/AnchorPagerExampleHeaderRED
```

- [x] **Step 6: 在主工作区验证用户约束与全部聚焦测试 GREEN**

确认主工作区仍是正式约束，不允许从临时 worktree 带回旧约束。运行：

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/AnchorPagerExampleHeaderGreenData -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerExampleTests test
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/AnchorPagerExampleHeaderGreenData -parallel-testing-enabled NO -enableCodeCoverage NO -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testPlainContainerTopBounceIsVisible -only-testing:AnchorPagerExampleUITests/AnchorPagerExampleUITests/testHeaderContentKeepsTwentyPointTopSafeAreaPaddingWhenSwitchingBehaviors test
```

Expected: Example 单元 target 全部通过；两个 UI 用例通过。真实 top presentation 大于 `1 pt`，Header 高度与内容顶部距离最大变化都小于 `0.5 pt`，静止 inside/extends 安全区和 `8 pt` 文本间距继续通过。

- [x] **Step 7: 自审并提交源码与测试**

检查：Example probe 只读本地 frame；无 framework/Public/containment/offset writer/logging 变化；Dynamic Type、automatic fitting、静止 safe area、真实 pan 和回稳都有覆盖；工程文件未暂存。

```bash
git diff --check
git status --short
git add Examples/AnchorPagerExample/AnchorPagerExample/ExampleScrollCoordinationState.swift Examples/AnchorPagerExample/AnchorPagerExample/ExamplePagerViewController.swift Examples/AnchorPagerExample/AnchorPagerExampleTests/AnchorPagerExampleTests.swift Examples/AnchorPagerExample/AnchorPagerExampleUITests/AnchorPagerExampleUITests.swift
git diff --cached --check
git commit -m "稳定示例 Header 顶部回弹内容位置"
```

Expected: 提交只包含上述四个 Example 源码/测试文件；`project.pbxproj` 保持未暂存。

---

### Task 2: 完整回归、文档终态与 fresh-pass

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-11-example-header-safe-area-content-design.md`
- Modify: `docs/superpowers/specs/2026-07-15-example-header-bounce-stable-content-layout-design.md`
- Modify: `docs/superpowers/plans/2026-07-15-example-header-bounce-stable-content-layout.md`

**Interfaces:**
- Consumes: Task 1 的源码提交、RED/GREEN 摘要和测试结果。
- Produces: 完整验收结果包、当前阶段门禁、自审/fresh-pass 结论与长期文档终态。
- Preserves: v0.5 Task 7/v0.6 Ready；若任一测试或 Critical/Important 审查项未清零，文档必须保留未完成状态。

- [x] **Step 1: 运行基础与完整测试门禁**

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -resultBundlePath /private/tmp/AnchorPagerExampleHeaderBounceFramework.xcresult test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/AnchorPagerExampleHeaderBounceFullData -parallel-testing-enabled NO -enableCodeCoverage NO -resultBundlePath /private/tmp/AnchorPagerExampleHeaderBounceExample.xcresult test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/AnchorPagerExampleHeaderBounceBuildData -resultBundlePath /private/tmp/AnchorPagerExampleHeaderBounceBuild.xcresult build
```

Expected: Framework 322/322、Example 41/41（11 单元 + 30 UI）全部 0 fail、0 skip；generic Simulator build 成功。若实际测试总数因 Xcode 发现规则变化不同，只记录 xcresult 真实数字，不修改门禁含义。

- [x] **Step 2: 检查结果包、运行时约束与静态禁止项**

```bash
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerExampleHeaderBounceFramework.xcresult
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerExampleHeaderBounceExample.xcresult
xcrun xcresulttool get build-results --path /private/tmp/AnchorPagerExampleHeaderBounceBuild.xcresult
xcrun simctl spawn booted log show --last 10m --style compact --predicate 'subsystem == "com.apple.UIKit" AND category == "LayoutConstraints"'
rg -n "Tabman|Pageboy" Sources/AnchorPager/Public
rg -n "\.delegate\s*=|panGestureRecognizer\.delegate\s*=|isScrollEnabled\s*=|\.bounces\s*=|alwaysBounceVertical\s*=" Sources/AnchorPager
```

Expected: test failure/skip、error、warning、analyzer warning 全为 `0`；UIKit 日志没有本任务触发的 `Unable to simultaneously satisfy constraints`；Public 扫描零命中；delegate/bounce 扫描只允许命中 AnchorPager 自有 `verticalScrollView` 的既有配置。

- [x] **Step 3: 执行 fresh-pass 代码自审**

从 Task 1 提交的 parent 到当前 HEAD 重新阅读完整 diff，不沿用实现时假设。逐项记录：

1. Public API 与第三方类型泄漏为零。
2. Example probe 只读取 `ExampleHeaderView.contentTopDistance`，不写任何 container/child offset。
3. Header UIView/UIViewController 与 Pageboy containment、selection/reload lifecycle 无变化。
4. Header automatic bootstrap、Dynamic Type、静止 safe area 和真实 top bounce 约束没有职责闭环。
5. container/child inset、delegate、pan、bounce、ScrollCoordinator/OverscrollCoordinator owner 无变化。
6. 没有新增框架日志；滚动热路径只扩展示例 accessibility probe，不输出逐帧控制台日志。
7. 测试同时证明 container presentation 存在、Header 高度固定、内容局部距离固定与回稳。
8. `project.pbxproj` 未进入任何任务提交。

Critical 或 Important 非零时先补设计并回到 RED；不得直接写完成文档。

- [x] **Step 4: 更新长期文档为真实终态**

仅在前三步全部通过后：

1. 把 `docs/task-list.md` 的本专项条目标为完成。
2. 把新设计状态改为“已完成”，记录生产提交、RED 旧约束失败、GREEN、完整测试数字、结果包和自审结论。
3. 在旧 safe-area 设计的取代说明后补最终实施记录，明确旧顶部对齐只保留为历史。
4. 在 `README.md` 说明 Example 默认 extends 下真实 container 回弹保持 Header 高度和内部文字局部距离。
5. 在 `docs/architecture.md` 的 Example/顶部 bounce 说明中登记：框架继续整体移动 viewport，Example 通过底部稳定锚点避免动态 safe-area top 抵消位移。
6. 在 `AGENTS.md` 当前阶段门禁登记最终生产 HEAD、测试数字、诊断和 fresh-pass 结论。
7. 勾选本计划全部步骤并写入实际命令、结果包和未触达边界。

- [x] **Step 5: 复查文档一致性并提交终态**

```bash
rg -n "文本组顶部对齐|top == safeArea|bottom <= safeArea|顶部安全下限|底部稳定" AGENTS.md README.md docs
rg -n "T[B]D|T[O]DO|待[定]|实现后[补]充" docs/superpowers/specs/2026-07-15-example-header-bounce-stable-content-layout-design.md docs/superpowers/plans/2026-07-15-example-header-bounce-stable-content-layout.md
git diff --check
git status --short
git add AGENTS.md README.md docs/architecture.md docs/task-list.md docs/superpowers/specs/2026-07-11-example-header-safe-area-content-design.md docs/superpowers/specs/2026-07-15-example-header-bounce-stable-content-layout-design.md docs/superpowers/plans/2026-07-15-example-header-bounce-stable-content-layout.md
git diff --cached --check
git commit -m "完成示例 Header 回弹稳定布局验收"
```

Expected: 旧约束只出现在明确标记为历史/被取代的段落；当前事实统一为顶部安全下限与底部稳定等式。最终工作区只保留用户原有且未解释归属的 `project.pbxproj` 修改，没有本任务未提交文件。

## 计划自审

1. **Spec coverage：** Task 1 覆盖正式约束、跨完整顶部遮挡、同进程 frame、真实手势探针、Header 固定高度、文本 intrinsic/8 pt、回稳和 RED/GREEN；Task 2 覆盖完整测试、运行时约束、静态门禁、自审、文档和完成状态。
2. **边界：** 没有修改 framework/Public/containment/inset/scroll/overscroll/logging；Example probe 是只读观察者。
3. **TDD：** 用户源码修改在计划前已存在，使用临时旧约束 worktree 证明新增测试真实失败；主工作区不回滚用户修改。
4. **UI 测试：** XCUITest drag 返回后读取累计显示帧指标，解决手指按住期间无法同步查询 frame 的限制。
5. **类型一致性：** 生产状态和 UI parser 统一使用 `headerContentTopDistance`/`headerContentTop` 与 `maximumHeaderContentTopDistanceDelta`/`headerContentTopDeltaMax`；accessibility key 固定为 `headerContentTop`、`headerContentTopDeltaMax`。
6. **提交范围：** Task 1 四个 Example 文件；Task 2 七个文档文件；用户 `project.pbxproj` 始终排除。

## 实际执行记录

1. 隔离旧约束的真实 UI RED 失败于 `headerContentTopDeltaMax = 116 pt`；结果包为 `/private/tmp/AnchorPagerExampleHeaderREDData/Logs/Test/Test-AnchorPagerExample-2026.07.15_11-12-47-+0800.xcresult`。旧约束下同进程测试仍通过，证明必须保留真实多帧 UI 门禁。
2. 正式约束下 Example 单元 target 与两条聚焦 UI 测试全部 GREEN；源码和测试提交为 `1f7e3f4`。
3. `git diff --check` 与 `swift package resolve` 通过；Apple Swift 6.3.3 / Xcode 26.6、iPhone 17 Pro / iOS 26.5 下 Framework 322/322、Example 41/41（11 单元 + 30 UI）均为 0 fail、0 skip，generic Simulator build 成功。
4. 三份最终结果包为 `/private/tmp/AnchorPagerExampleHeaderBounceFramework-20260715-1120.xcresult`、`/private/tmp/AnchorPagerExampleHeaderBounceExample-20260715-1121.xcresult`、`/private/tmp/AnchorPagerExampleHeaderBounceBuild-20260715-1128.xcresult`；均为 0 error、0 warning、0 analyzer warning。
5. UIKit `LayoutConstraints` 查询无冲突；Public 第三方类型扫描零命中；delegate/bounce 扫描只命中 AnchorPager 自有 `verticalScrollView` 的既有配置。
6. fresh-pass `afaefce...1f7e3f4` 结论为 Critical 0、Important 0、Minor 0；未修改 framework/Public/containment/offset writer/inset/gesture/bounce/logging owner。
7. 用户已有 `Examples/AnchorPagerExample.xcodeproj/project.pbxproj` 修改始终未暂存、未提交、未回滚。
