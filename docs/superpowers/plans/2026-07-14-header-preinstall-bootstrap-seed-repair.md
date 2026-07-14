# Header 安装前 Bootstrap Seed 修复实施计划

> **执行要求：** 实施时使用 `superpowers:test-driven-development`；声明完成前使用 `superpowers:verification-before-completion`。本计划不需要并行代理。

**目标：** 在真实 Header 内容附着到 host 之前同步写入 bootstrap seed，消除旧 required `height == 0` 与 Header 内部约束形成的瞬时冲突，同时保持正式测量、Header identity cache、UIViewController containment、Public API 与滚动/分页边界不变。

**架构：** `AnchorPagerHeaderViewHost` 把“incoming 内容的 bootstrap 测量”和“内容附着”纳入同一同步安装事务，并通过 nonescaping internal 回调把 seed 交给 `AnchorPagerViewController`。ViewController 在回调中创建或更新唯一的 `headerHeightConstraint`；正式 `measureHeaderHeight(in:)` 随后继续执行中立布局和正式 fitting。UIViewController Header 保持 `addChild → load/measure view → prepare seed → addSubview → didMove`。

**技术栈：** Swift 6.2、Swift 6 language mode、UIKit、iOS 14+、Swift Package Manager、XCTest/XCUITest、Tabman 4.0.1、Pageboy 5.0.2、Xcode 26.6。

**当前状态：** 设计已确认；实现、RED/GREEN、完整 Framework/Example/UI、运行时约束日志、generic build、自审与 fresh-pass 复审待完成。在这些门禁完成前，v0.5 Task 7 与 v0.6 不得恢复 Ready，也不得进入 v0.7。

---

## 全局约束

- 不修改 Public API，不新增测试专用生产入口，不泄漏 Tabman/Pageboy 类型。
- 不降低、停用或异步修复 Header 约束；prepare 回调同步、nonescaping、不保存。
- Header host 始终只有一个 required height constraint；seed 只更新其 constant。
- 同一 Header identity 的重复安装继续 no-op：不重复 fitting、不调用 prepare、不清空 `lastMeasuredHeaderHeight`。
- UIViewController Header 不得在 `addChild` 前为预测量加载 view；标准 containment 顺序不能改变。
- bootstrap invalid 值仍静默降级为 `0`；只有正式 measurement 执行 assertion 与 `header.measure.invalid` 日志。
- 不改变 layout context、collapse progress、scroll range、PageState、generation、inset、overscroll owner 或业务 child 配置。
- 每个实现任务遵循 RED → 最小 GREEN → 聚焦回归 → 自审 → `git diff --check` → 中文单一主题提交。

---

## 文件与职责

- `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`：incoming 内容 bootstrap、同步 prepare 顺序、安装 identity/no-op 与 UIViewController containment。
- `Sources/AnchorPager/Public/AnchorPagerViewController.swift`：统一 fitting size、在内容附着前创建/更新 host height constraint、正式 measurement 保持不变。
- `Tests/AnchorPagerTests/AnchorPagerHeaderViewHostTests.swift`：UIView/UIViewController 安装顺序、preferred size、同 identity no-op 与日志边界。
- `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`：从空占位切换真实约束 Header 时的附着瞬间 required host height。
- `README.md`、`docs/requirements.md`、`docs/architecture.md`、`docs/task-list.md`、本规格/计划、原 2026-07-14 规格/计划、`AGENTS.md`：当前门禁与最终证据。

---

### Task 1：建立附着瞬间的结构性 RED

**Files:**
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Produces:** 可直接证明真实 Header 附着时 host required height constant 的回归测试。

- [ ] **Step 1：扩展约束 Header fixture**

给 `ConstrainedLayoutRecordingHeaderView` 增加 `requiredHostHeightWhenAttached`，在 `didMoveToSuperview()` 且 `superview != nil` 时查找 host 上 active、required、单项 `height == constant` 约束并记录 constant。保留现有 `layoutSubviews()` 零高度探针，形成“约束激活瞬间”和“最终布局结果”两层证据。

```swift
private(set) var requiredHostHeightWhenAttached: CGFloat?

override func didMoveToSuperview() {
    super.didMoveToSuperview()
    guard let hostView = superview else { return }
    requiredHostHeightWhenAttached = hostView.constraints.first { constraint in
        constraint.isActive
            && constraint.priority == .required
            && (constraint.firstItem as? UIView) === hostView
            && constraint.firstAttribute == .height
            && constraint.secondItem == nil
    }?.constant
}
```

- [ ] **Step 2：新增 ViewController 回归测试**

在现有 `testAutomaticHeaderBootstrapNeverLaysOutConstrainedContentAtRequiredZeroHeight` 相邻位置新增：

```swift
@MainActor
func testAutomaticHeaderBootstrapSeedsHostBeforeConstrainedContentAttachment() throws {
    var configuration = AnchorPagerConfiguration.default
    configuration.header.heightMode = .automatic(min: 0, max: nil)
    let pager = AnchorPagerViewController(configuration: configuration)
    let header = ConstrainedLayoutRecordingHeaderView()
    let dataSource = StubDataSource(
        count: 1,
        viewControllers: [UIViewController()],
        headerContent: .view(header)
    )
    pager.dataSource = dataSource
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = pager
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    pager.reloadData()

    XCTAssertGreaterThan(
        try XCTUnwrap(header.requiredHostHeightWhenAttached),
        0
    )
}
```

- [ ] **Step 3：运行 RED 并保存精确失败**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testAutomaticHeaderBootstrapSeedsHostBeforeConstrainedContentAttachment test
```

预期：测试编译并只因记录值为 `0`、不满足 `> 0` 而失败；不得把现有 `didLayoutAtRequiredZeroHeight == false` 误当作通过证据。

---

### Task 2：定义 HeaderHost 安装事务并完成最小 GREEN

**Files:**
- Modify: `Tests/AnchorPagerTests/AnchorPagerHeaderViewHostTests.swift`
- Modify: `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`
- Modify: `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- Modify: `Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift`

**Produces:** incoming bootstrap、同步 prepare、正确 UIViewController containment 与唯一 host height constraint。

- [ ] **Step 1：先补 HeaderHost 合同测试**

新增 `testInstallPreparesBootstrapHeightBeforeAttachingHeaderView`：使用 fitting height 为 `64`、可记录 `didMoveToSuperview` 的 view，断言事件严格以 `prepare:64` 开始，随后才是 `attach`。

扩展 `testReinstallingSameHeaderViewIsNoOp`：prepare 计数首次为 `1`，重复安装后仍为 `1`。

新增 `testInstallingHeaderViewControllerPreparesAfterContainmentBeginsAndBeforeAttachment`：fixture 在 `loadView` 记录 parent 已存在，在 view attach 和 controller `didMove(toParent:)` 记录事件，断言顺序：

```text
loadWithParent → prepare → attach → didMove
```

新测试直接调用预期 internal 接口：

```swift
host.install(
    .view(headerView),
    in: parent,
    bootstrapMeasurementSize: CGSize(width: 320, height: 0),
    prepareHostForContent: { height in events.append("prepare:\(height)") }
)
```

- [ ] **Step 2：运行接口 RED**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerHeaderViewHostTests/testInstallPreparesBootstrapHeightBeforeAttachingHeaderView -only-testing:AnchorPagerTests/AnchorPagerHeaderViewHostTests/testInstallingHeaderViewControllerPreparesAfterContainmentBeginsAndBeforeAttachment test
```

预期：当前实现因缺少新的 internal 参数而编译失败；记录该失败后再改生产代码。

- [ ] **Step 3：扩展 HeaderHost internal 安装接口**

把 `install` 改为要求显式 measurement size 和同步回调；不提供默认值，避免生产调用方绕过安装前 seed：

```swift
@discardableResult
func install(
    _ content: AnchorPagerHeaderContent,
    in parentViewController: UIViewController,
    hostParentView: UIView? = nil,
    bootstrapMeasurementSize: CGSize,
    prepareHostForContent: (CGFloat) -> Void
) -> Bool
```

顺序要求：

```swift
guard !isDisplaying(content) else { /* noop log */ return false }
removeContent(keepHostView: true)

switch content {
case let .view(headerView):
    prepareHostForContent(
        bootstrapMeasurement(for: headerView, preferredHeight: nil, in: size)
    )
    installHeaderView(headerView)
case let .viewController(controller):
    parentViewController.addChild(controller)
    let headerView = controller.view!
    prepareHostForContent(
        bootstrapMeasurement(
            for: headerView,
            preferredHeight: controller.preferredContentSize.height,
            in: size
        )
    )
    installHeaderView(headerView)
    controller.didMove(toParent: parentViewController)
}
```

将现有 `measuredContentHeight(in:)` 重构为可同时服务 current content 和 incoming content 的私有纯同步 helper。测量优先级保持：有效正 `preferredHeight` → fitting → bounds → intrinsic → `0`；invalid 值沿原路径返回，由 bootstrap 静默归零、formal measure 写 assertion/log。

- [ ] **Step 4：让 ViewController 在附着前写唯一约束**

新增私有 helper：

```swift
private func headerMeasurementSize(in environment: LayoutEnvironment) -> CGSize

private func setHeaderHostHeight(_ height: CGFloat) {
    if let headerHeightConstraint {
        headerHeightConstraint.constant = height
        return
    }
    let constraint = headerViewHost.view.heightAnchor.constraint(equalToConstant: height)
    constraint.isActive = true
    headerHeightConstraint = constraint
}
```

`installHeaderHost()` 在调用 Host 前取得当前 environment/fitting size，并传入：

```swift
prepareHostForContent: { [unowned self] seed in
    setHeaderHostHeight(seed)
}
```

删除 install 返回后才创建 `constant: 0` 的旧分支。只有 `didReplaceHeader == true` 才清空 `lastMeasuredHeaderHeight`。`measureHeaderHeight(in:)` 复用同一 `headerMeasurementSize(in:)`，正式测量逻辑与日志不变。

- [ ] **Step 5：更新 HeaderHost 既有测试调用**

测试文件增加 `@MainActor` 私有 install helper，为所有既有直接安装显式提供 `CGSize(width: 320, height: 0)` 和空 prepare；新顺序测试继续直连真实回调。不得给生产接口增加默认空回调来减少测试改动。

- [ ] **Step 6：运行聚焦 GREEN**

```bash
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AnchorPagerTests/AnchorPagerHeaderViewHostTests -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testAutomaticHeaderBootstrapSeedsHostBeforeConstrainedContentAttachment -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testAutomaticHeaderBootstrapNeverLaysOutConstrainedContentAtRequiredZeroHeight -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testReloadDataInstallsVisibleHeaderAndPagingAdapter -only-testing:AnchorPagerTests/AnchorPagerViewControllerTests/testAutomaticHeaderHeightStaysStableAcrossTopBehaviorSwitchAndBounceSettlement test
git diff --check
```

预期：HeaderHost 全类与四条 ViewController Header 相邻测试全部通过。

- [ ] **Step 7：实施自审并提交**

自审必须逐项确认：Public API 无变化；prepare 仅 identity change 调用；VC 先 `addChild`、后 load/measure、再 attach/`didMove`；无第二条 host height constraint；invalid/log 语义不变；未触碰 paging/scroll/inset/overscroll。

```bash
git diff --check
git status --short
git add Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift Sources/AnchorPager/Public/AnchorPagerViewController.swift Tests/AnchorPagerTests/AnchorPagerHeaderViewHostTests.swift Tests/AnchorPagerTests/AnchorPagerViewControllerTests.swift
git commit -m '修复页眉安装前零高度约束冲突'
```

---

### Task 3：运行时约束日志与完整自动化验收

**Files:**
- No production changes expected.
- Result bundles: `/private/tmp/AnchorPagerHeaderPreinstallFramework-20260714.xcresult`、`/private/tmp/AnchorPagerHeaderPreinstallExample-20260714.xcresult`、`/private/tmp/AnchorPagerHeaderPreinstallBuild-20260714.xcresult`。

**Produces:** 新鲜 Framework、Example/UI、generic build、UIKit LayoutConstraints 与静态架构证据。

- [ ] **Step 1：解析依赖并运行完整 Framework**

```bash
swift package resolve
xcodebuild -quiet -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -resultBundlePath /private/tmp/AnchorPagerHeaderPreinstallFramework-20260714.xcresult test
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerHeaderPreinstallFramework-20260714.xcresult
xcrun xcresulttool get build-results --path /private/tmp/AnchorPagerHeaderPreinstallFramework-20260714.xcresult
```

记录实际 passed/failed/skipped 与 error/warning/analyzer warning；不预填通过数。

- [ ] **Step 2：运行完整 Example 单元/UI**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -resultBundlePath /private/tmp/AnchorPagerHeaderPreinstallExample-20260714.xcresult test
xcrun xcresulttool get test-results summary --path /private/tmp/AnchorPagerHeaderPreinstallExample-20260714.xcresult
xcrun xcresulttool get build-results --path /private/tmp/AnchorPagerHeaderPreinstallExample-20260714.xcresult
```

Example 必须完整运行，不能只以新结构测试替代真实 app/UI 验收。

- [ ] **Step 3：运行 generic Simulator build**

```bash
xcodebuild -quiet -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' -resultBundlePath /private/tmp/AnchorPagerHeaderPreinstallBuild-20260714.xcresult build
xcrun xcresulttool get build-results --path /private/tmp/AnchorPagerHeaderPreinstallBuild-20260714.xcresult
```

- [ ] **Step 4：补充新进程运行时 LayoutConstraints 查询**

在 Example 已由测试安装后启动新进程：

```bash
xcrun simctl launch --terminate-running-process booted com.sondra.AnchorPagerExample
xcrun simctl spawn booted log show --last 20s --style compact --predicate 'process == "AnchorPagerExample" AND subsystem == "com.apple.UIKit" AND category == "LayoutConstraints" AND eventMessage CONTAINS[c] "simultaneously satisfy"'
```

预期没有本次 Header `height == 0` 冲突。运行时查询是补充证据；Task 1/2 的结构测试才是确定性主门禁。

- [ ] **Step 5：运行静态边界扫描与工作区校验**

```bash
rg -n 'delegate\s*=|panGestureRecognizer\.delegate|isScrollEnabled\s*=|bounces\s*=|alwaysBounceVertical\s*=' Sources/AnchorPager
rg -n '@unchecked Sendable|nonisolated\(unsafe\)|@preconcurrency|AnchorPagerPageScrollHostViewController' Sources/AnchorPager
rg -n 'import (Tabman|Pageboy)|\b(Tabman|Pageboy)' Sources/AnchorPager/Public
git diff --check
git status --short
```

新增改动不得命中任何架构禁项；既有命中必须逐条解释，不能只看命令退出码。

---

### Task 4：文档终态、自审与 Fresh-pass 复审

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/task-list.md`
- Modify: `docs/superpowers/specs/2026-07-14-header-preinstall-bootstrap-seed-repair-design.md`
- Modify: `docs/superpowers/plans/2026-07-14-header-preinstall-bootstrap-seed-repair.md`
- Modify: `docs/superpowers/specs/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement-design.md`
- Modify: `docs/superpowers/plans/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement.md`

**Produces:** 只反映真实测试结果的门禁终态与整分支复审记录。

- [ ] **Step 1：同步实际实现和验收证据**

文档必须说明：旧 bootstrap 为什么太晚；新 prepare 在 attach 前；UIViewController containment 顺序；同 identity no-op；formal measurement/log 不变；实际提交；完整测试通过数；结果包；运行时 LayoutConstraints 查询；generic build；Public API/第三方/child ownership 无变化。

只有 Task 3 全部通过后，才允许把 v0.5 Task 7/v0.6 恢复 Ready，并解除“不得进入 v0.7”。

- [ ] **Step 2：执行完整自审**

覆盖：

1. 数据流：placeholder `0` → incoming fitting → prepare constraint → attach → formal measure。
2. UIKit：UIViewController `addChild/addSubview/didMove` 和 identity replacement/no-op。
3. 约束：唯一 required host height，不降优先级、不留下 zero-height 瞬时窗口。
4. 状态：cache 只在 replacement 失效；不发布 bootstrap layout state。
5. 边界：Public API、Pageboy、scroll/inset/overscroll、日志事件无变化。
6. 测试：结构、相邻、完整 UI、日志补充和结果包证据齐全。

- [ ] **Step 3：执行 fresh-pass 整分支复审**

```bash
git diff c37e829...HEAD -- Sources Tests Examples README.md AGENTS.md docs
git diff --check
```

按 Critical / Important / Minor 输出结论。任何 Critical/Important 必须先修复并补 RED/GREEN，再重跑受影响测试；不得带着未解决问题恢复 Ready。

- [ ] **Step 4：提交文档终态**

```bash
git add README.md AGENTS.md docs/requirements.md docs/architecture.md docs/task-list.md docs/superpowers/specs/2026-07-14-header-preinstall-bootstrap-seed-repair-design.md docs/superpowers/plans/2026-07-14-header-preinstall-bootstrap-seed-repair.md docs/superpowers/specs/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement-design.md docs/superpowers/plans/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement.md
git commit -m '同步页眉安装时序验收记录'
git status --short
```

工作区必须干净；若有无关改动，必须明确归属并保留，不能回滚或混入提交。

---

## 完成定义

1. 可测非空 Header 附着瞬间 host required height 为正，Example 不再出现本次 zero-height 约束冲突。
2. UIView/UIViewController 顺序、同 identity no-op、automatic/ranged/fixed formal measurement 与现有日志语义保持。
3. Framework、Example 单元/UI、generic build、运行时日志补充、静态扫描和 `git diff --check` 均有新鲜证据。
4. 自审和整分支 fresh-pass 复审没有未解决 Critical/Important。
5. 文档只登记实际提交、实际通过数和实际结果包；满足后才恢复 v0.5 Task 7/v0.6 Ready。
