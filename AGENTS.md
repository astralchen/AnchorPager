# AGENTS.md

本文件是 AnchorPager 仓库的代理工作指令。任何自动化代理、编码代理或审查代理在修改本仓库前都必须先阅读并遵守本文件。

## 语言要求

1. 所有回复必须使用中文。
2. 所有代码解释、分析、提交说明、审查意见和文档说明必须使用中文。
3. 代码中的 DocC 注释和必要实现注释也使用中文，除非 Swift/UIKit/API 命名本身必须使用英文。

## 项目定位

AnchorPager 是一个从零开发的独立 UIKit 容器框架，用于实现：

1. 可变 Header
2. 吸顶分段栏
3. 多页面横向分页
4. 纵向嵌套滚动
5. 顶部 overscroll 事件处理
6. 状态栏点击顶滚
7. 尺寸变化后的布局恢复
8. 完整 child view controller 生命周期管理

AnchorPager 与任何现有项目没有关系。不得迁移、引用、复用或沿用任何旧项目代码、API、目录结构、文档或测试。

## 必读文档

开始任何实现前必须阅读：

1. `docs/requirements.md`
2. `docs/task-list.md`
3. `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`
4. `docs/architecture.md`
5. `docs/superpowers/specs/2026-07-10-header-scroll-settlement-design.md`（涉及主容器滚动结束、Header 坐标转换或顶部行为切换时）
6. `docs/superpowers/specs/2026-07-11-dual-header-top-behavior-bounce-stability-design.md`（涉及双顶部行为、automatic Header 测量或主容器可见 bounce 时）
7. `docs/superpowers/specs/2026-07-11-example-header-safe-area-content-design.md`（涉及示例 Header 的安全区内容布局时）
8. `docs/superpowers/specs/2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md`（涉及 v0.3–v0.5、Tabman adapter 几何、bar 高度、child inset ownership、page offset 或纵向滚动 owner 时）
9. `docs/superpowers/specs/2026-07-12-v0-4-reload-terminal-repair-design.md`（涉及 v0.4 空数据 reload、paging adapter terminal、reload 重入或 appearance cancel 验收时）
10. `docs/superpowers/specs/2026-07-12-v0-4-child-lifecycle-cache-design.md`（涉及 v0.4 page identity、按需加载、cache window、reload generation、offset snapshot、历史无滚动包装 containment 或 appearance lifecycle 时）
11. `docs/superpowers/specs/2026-07-12-v0-4-generation-atomicity-repair-design.md`（涉及 v0.4 deferred reload、provider/visible generation、跨 generation PageState 隔离或 v0.5 committed current 入口时）
12. `docs/superpowers/specs/2026-07-12-swift-6-2-toolchain-baseline-design.md`（涉及 Package manifest、Swift 工具链、并发诊断、CI 或版本技术基线时）
13. `docs/superpowers/specs/2026-07-13-v0-5-scroll-coordination-design.md`（涉及 v0.5 纵向 handoff、child delegate/gesture ownership、simultaneous recognition、顶部下拉临时边界或真实 pan UI 验收时）
14. `docs/superpowers/specs/2026-07-13-plain-page-direct-containment-design.md`（涉及无 UIScrollView 页面、直接 Pageboy containment、nil scroll target、synthetic wrapper 移除、plain page 尺寸或物理屏幕底边时）
15. `docs/superpowers/specs/2026-07-13-boundary-bounce-ownership-design.md`（涉及无滚动页双边界 bounce、顶部 overscroll mode、container/child bounce owner、业务 child 原生 bounce 配置保留或可见 presentation 验收时）
16. `docs/superpowers/specs/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement-design.md`（涉及无滚动页底部页面内容层回弹、bar 安全区吸顶、Paging adapter presentation surface、LayoutContext 分层可见坐标或 Header 首次 bootstrap 测量时）
17. `docs/superpowers/specs/2026-07-14-example-unified-settings-menu-design.md`（涉及 Example 统一设置入口、Header 顶部行为菜单、顶部 overscroll mode 菜单或真实菜单交互 UI 测试时）
18. `docs/superpowers/specs/2026-07-14-header-preinstall-bootstrap-seed-repair-design.md`（涉及 Header identity replacement、真实内容附着前 bootstrap seed、启动期 zero-height 约束冲突或 Header UIViewController 安装时序时）
19. `docs/superpowers/specs/2026-07-14-container-top-inset-fixed-header-presentation-design.md`（涉及主容器顶部 inset、raw/logical offset、Header 固定高度 presentation、顶部行为切换、bar 吸顶或 v0.5/v0.6 边界重新验收时）

如果当前任务是在执行、继续、审查或验收某个开发计划，还必须阅读对应计划文档。当前已登记计划：

1. `docs/superpowers/plans/2026-07-09-v0-1-foundation.md`
2. `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
3. `docs/superpowers/plans/2026-07-10-header-scroll-viewport.md`（涉及主容器滚动范围、Header viewport、顶部行为切换或回弹修复时）
4. `docs/superpowers/plans/2026-07-11-dual-header-top-behavior-bounce-stability.md`（涉及双顶部行为、中立测量或可见 bounce 修复时）
5. `docs/superpowers/plans/2026-07-11-example-header-safe-area-content.md`（涉及示例 Header 的安全区内容布局时）
6. `docs/superpowers/plans/2026-07-11-v0-3-fixed-paging-inset-ownership.md`（执行、继续、审查或验收 v0.3 固定分页视口、optional bar height 或 child inset ownership 时）
7. `docs/superpowers/plans/2026-07-12-v0-4-child-lifecycle-cache.md`（执行、继续、审查或验收 v0.4 page state、按需加载、缓存窗口、reload generation、offset snapshot 或 appearance lifecycle 时）
8. `docs/superpowers/plans/2026-07-12-v0-4-reload-terminal-repair.md`（执行、继续、审查或验收 v0.4 空数据 reload terminal、paging host、reload 重入或 appearance cancel 修复时）
9. `docs/superpowers/plans/2026-07-12-v0-4-generation-atomicity-repair.md`（执行、继续、审查或验收 v0.4 deferred reload request、provider/visible generation、PageState 隔离或 v0.5 committed current 门禁时）
10. `docs/superpowers/plans/2026-07-12-swift-6-2-toolchain-baseline.md`（执行、继续、审查或验收 Swift 6.2 tools version、Swift 6 language mode、同步析构或 `isolated deinit` 已知工具链限制时）
11. `docs/superpowers/plans/2026-07-13-v0-5-scroll-coordination.md`（执行、继续、审查或验收 v0.5 纵向 handoff、container scroll view simultaneous recognition、child observation、真实 pan UI test 或顶部临时 bounce 时）
12. `docs/superpowers/plans/2026-07-13-plain-page-direct-containment.md`（执行、继续、审查或验收无 UIScrollView 页面直接 Pageboy containment、synthetic wrapper 移除、nil scroll target、物理屏幕底边或 container-only pan 时）
13. `docs/superpowers/plans/2026-07-13-boundary-bounce-ownership.md`（执行、继续、审查或验收 native boundary pass-through、顶部 mode、业务 child bounce 配置保留、双边界 presentation 或真实回弹 UI 时）
14. `docs/superpowers/plans/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement.md`（执行、继续、审查或验收 plain bottom 页面/chrome 分层、Paging page surface、LayoutContext 可见坐标、Header bootstrap 测量或 bar 安全区 UI 修复时）
15. `docs/superpowers/plans/2026-07-14-example-unified-settings-menu.md`（执行、继续、审查或验收 Example 齿轮设置入口、Header/顶部回弹二级菜单、菜单选中态或真实菜单 UI 测试时）
16. `docs/superpowers/plans/2026-07-14-header-preinstall-bootstrap-seed-repair.md`（执行、继续、审查或验收 Header 真实内容附着前 seed、启动期 zero-height 约束冲突、Header identity no-op 或 UIViewController Header 安装时序时）
17. `docs/superpowers/plans/2026-07-14-container-top-inset-fixed-header-presentation.md`（执行、继续、审查或验收主容器顶部 inset、raw/logical offset、固定高度 Header canonical presentation、顶部行为迁移或 v0.5/v0.6 Ready 恢复时）

实现过程中如果发现本文档与上述文档冲突，以更严格的约束为准；如果仍无法判断，先更新设计或向用户确认，不要自行扩大 public API。

## 技术基线

1. Package name：`AnchorPager`
2. Library product：`AnchorPager`
3. Module name：`AnchorPager`
4. Minimum toolchain：Swift 6.2
5. Language mode：Swift 6
6. Minimum OS：iOS 14
7. UI stack：UIKit
8. Package manager：Swift Package Manager
9. Horizontal paging：Tabman + Pageboy
10. Tabman 版本从 `4.0.1` 开始
11. Pageboy 解析或直接依赖到 `5.0.2`

## 当前阶段门禁

1. v0.5 纵向 handoff、plain direct page、stable/native boundary 分离和 v0.6 三种顶部 mode 的初始实现到 `47abcd6`；初次独立复审的 3 个 Important 已修复到 `f81ca1e`，第二次整分支复审的零稳定区间边界反向切换 Important 已修复到 `5b80893`，第三次整分支复审发现的已呈现 `.top/.child` 回稳总量跳变 Important 已修复到 `128821f`；第二、三次复审的文档 Minor 均已同步修正。
2. 第四次整分支独立复审覆盖 `be2d783...13b3d95`，结论为 Critical 0、Important 0、Minor 2；README 旧验收摘要和 `.container` 顶部 UI 缺少严格 child owner 排他断言两个 Minor 已在最终状态提交中修复。
3. 2026-07-13 最终验收为 Framework 283/283、Example 37/37（10 单元 + 27 UI）、0 fail、0 skip，generic Simulator build 成功；结果均为 0 error、0 warning、0 analyzer warning。Framework 结果包 `/private/tmp/AnchorPagerPresentedTopFrameworkFull-20260713-2258.xcresult` 对应生产代码 HEAD `128821f`；本次只修改 Example UI 测试和长期文档。v0.5 Task 7 与 v0.6 均为 Ready。
4. 2026-07-14 plain bottom/bar 安全区与 Header bootstrap 回归已修复到生产代码 HEAD `c37e829`：plain bottom 只移动 Pageboy 页面 surface，Header/bar 保持 canonical；Header measurement cache 按内容身份失效并使用 bootstrap seed；selection、reload、尺寸变化、adapter removal 与 deinit 均同步恢复 presentation。Apple Swift 6.3.3 / Xcode 26.6 下，Framework 293/293、Example 37/37（10 单元 + 27 UI）与 generic Simulator build 全部通过，0 fail、0 skip、0 error/warning/analyzer warning。整分支 fresh-pass 复审发现的 1 个 Important（deinit 未显式归零 page surface）已在 `c37e829` 修复并完成 RED/GREEN，复审终态为 Critical 0、Important 0、Minor 0；v0.5 Task 7 与 v0.6 恢复 Ready。
5. 2026-07-14 后续真实启动日志证明 `dfabd6c` 只修复了正式测量前的 zero-height layout；生产提交 `d6ece31` 已在真实 Header 附着前同步写入 incoming bootstrap seed，并通过附着瞬间、UIView/UIViewController 安装顺序和同 identity no-op 的 RED/GREEN。Apple Swift 6.3.3 / Xcode 26.6 下，Framework 296/296、Example 38/38（10 单元 + 28 UI）与 generic Simulator build 全部通过，0 fail、0 skip、0 error/warning/analyzer warning；新进程 Header 安装日志存在且 UIKit `LayoutConstraints` 查询无冲突。整分支 fresh-pass 为 Critical 0、Important 0、Minor 0，v0.5 Task 7 与 v0.6 恢复 Ready。
6. 2026-07-14 主容器 top inset 与固定高度 Header 专项已完成 TDD 实现和首轮全量验收：`.insideSafeArea` 使用本地顶部遮挡作为真实 `contentInset.top`，`.extendsUnderTopSafeArea` 为 `0`；raw/logical offset、`H + D - I` range、固定 Header canonical presentation、container top 与 plain bottom 分层均已收口。专项实现 HEAD 为 `1847aac`，正式验收 HEAD `ce09f2b` 只额外消除了测试代码的两条编译警告。Apple Swift 6.3.3 / Xcode 26.6 下，Framework 318/318、Example 41/41（11 单元 + 30 UI）与 generic Simulator build 全部通过，0 fail、0 skip、0 error/warning/analyzer warning；Header 真实手势运行日志无 UIKit 约束冲突。实现者自审与最终 fresh-pass 尚待完成，因此第 5 条 Ready 仍只保留为历史结论，当前继续关闭 v0.5 Task 7 与 v0.6 Ready 门禁，不得进入 v0.7。

## 架构边界

1. Public API 命名参考 UIKit，保持领域无关。
2. 第三方库类型不得泄漏到 AnchorPager public API。
3. Tabman 和 Pageboy 只允许出现在 adapter/internal 层。
4. Tabman/Pageboy 负责横向分页、页面切换事件、分段栏、indicator 渲染，以及横向 page 的实际 UIKit containment 执行。
5. AnchorPager 负责 Header 布局、吸顶、纵向滚动协调、child scroll inset、顶部 overscroll 事件处理、状态栏点击顶滚、page lifecycle 策略和对外状态语义。
6. AnchorPager 不得对已经交给 Tabman/Pageboy adapter 执行横向分页的同一个 page view controller 再次 `addChild`，避免双重 containment。
7. 必须禁用或绕开 Tabman 自动 child inset，避免与 AnchorPager 的 Header/分段栏预留空间管理冲突。
8. 内部状态机词如 pin anchor、owner、handoff 不得暴露到 public API。
9. 如果 Tabman/Pageboy API 限制影响设计，优先调整 internal adapter，不扩大 public API。
10. AnchorPager 任何时刻都不得设置横向业务 child 的 `UIScrollView.delegate`，包括临时替换、forwarding proxy、解绑后恢复或为测试注入代理；child 滚动观察必须使用不占用该 delegate 的内部机制。
11. AnchorPager 不得设置业务 child 的内建 pan delegate 或 `isScrollEnabled`，不得保存、修改或恢复业务 child 的 `bounces`、`alwaysBounceVertical`。
12. `AnchorPagerScrollCoordinator` 负责协调期 offset 写入；`AnchorPagerOverscrollCoordinator` 只能管理 owner 策略和生命周期，不得持有 UIKit/page/provider 或直接写 offset。
13. 无滚动页 original controller 直接由 Pageboy containment，committed page 非 nil、scroll target 为 nil；顶部 `.child` 不可用且不回退，底部 bounce 的原生物理由 container 处理，但可见 presentation 只允许移动 Pageboy 页面 surface，不得移动 Header/bar，也不得直接修改业务 page 根 view transform。
14. 主容器顶部 inset 由 `AnchorPagerHeaderTopBehavior` 独立拥有：`.insideSafeArea` 等于当前本地顶部安全区遮挡，`.extendsUnderTopSafeArea` 为 `0`；ScrollCoordinator、OverscrollCoordinator 和 LayoutEngine 只消费归一化后的逻辑 container offset，业务 Header 根视图不得在滚动热路径缩高。

## 变更影响评估

1. 新增功能、修改重要逻辑或修复问题前，必须先梳理影响范围，再开始实现。
2. 影响范围至少覆盖 public API、内部分层、UIKit containment、child lifecycle、scroll discovery、inset ownership、paging adapter、gesture/overscroll、日志、测试、示例工程和文档。
3. 设计必须兼顾后续版本扩展，不得为了当前单点修复破坏既有架构边界、状态语义或未来版本路线。
4. 如果变更可能影响 public API、跨模块契约、第三方 adapter 边界、线程/actor 隔离、生命周期或用户可见行为，必须先更新设计说明或计划文档，再实现。
5. 修复问题时必须同时分析回归风险和相邻路径，避免只修当前复现场景却引入分页、滚动、生命周期或示例工程新问题。
6. 无法确定影响范围时，先补充设计记录或向用户确认，不得直接扩大 public API 或绕开现有约束。
7. 审查或实现过程中如果发现“现有实现的真实职责”和文档、计划或架构假设不一致，尤其是第三方库职责、UIKit containment、appearance lifecycle、selection commit/cancel、scroll/inset ownership 等边界问题，必须及时提醒用户，并同步更新对应文档，不能只在代码里临时绕过。
8. 修复问题或编写新功能前，必须全面梳理相关数据流、状态所有权、约束或回调关系、相邻版本职责、回归路径和文档契约；未完成关系梳理不得开始写实现代码。
9. 关系梳理发现现有设计或架构存在职责闭环、所有权冲突、跨层泄漏、状态语义矛盾或会阻碍后续版本扩展时，必须立即停止局部实现并提醒用户，先更新设计、架构或计划文档；不得在错误设计上追加回调、条件分支、异步延迟、强制 reset 或重复 layout 等补丁掩盖问题。

## 目录规划

目标结构：

```text
Package.swift
Sources/AnchorPager/
  Public/
  Core/
  Layout/
  Header/
  Children/
  Paging/
  Overscroll/
  Gesture/
  Logging/
Tests/AnchorPagerTests/
Examples/AnchorPagerExample/
docs/architecture.md
README.md
```

新增文件时按职责放置。不要把多个 coordinator、adapter、layout engine 和测试夹在一个大文件中。

## 开发顺序

v0.1–v0.6 的历史实现已完成；2026-07-14 主容器顶部 inset 与固定高度 Header presentation 专项的 TDD 实现和首轮全量验收已通过，但 v0.5 Task 7/v0.6 门禁仍等待实现者自审与最终 fresh-pass。复审清零 Critical/Important 并用最终 HEAD 重跑全量门禁前不得恢复 Ready，也不得提前进入 v0.7。

v0.1 的优先顺序：

1. Swift Package 与依赖
2. 日志基础设施
3. Public API skeleton
4. Header 基础承载
5. Tabman/Pageboy adapter
6. Child 基础管理
7. Scroll view discovery
8. README、architecture 文档和示例工程
9. 对应单元测试、集成测试和必要 UI 测试

## 测试硬性要求

1. 每完成一个实现任务都必须同步提交对应测试。
2. 不允许把当前任务应有的测试推迟到后续任务统一补。
3. 触达用户可见 UI、UIKit 生命周期、手势、滚动、分页、状态栏点击、尺寸变化、safe area、Dynamic Type、Reduce Motion、RTL 或示例工程行为的任务，必须包含必要 UI 测试。
4. 如果某个 UI 行为无法通过 UI 测试稳定覆盖，必须在任务说明中写明原因，并提供替代的自动化验证。
5. 任务验收说明必须列出实际运行过的测试命令和结果。
6. 任何任务如果没有测试证据，视为未完成。

## 代码审查硬性要求

1. 每完成一个实现任务或重要修复后，必须先做一次代码自审，再继续下一个任务或声明完成。
2. 自审至少覆盖：架构边界、public API 是否扩大或泄漏第三方类型、UIKit containment/lifecycle、并发隔离、日志事件、测试覆盖、文档状态和验收命令。
3. 涉及 Tabman/Pageboy、Header、child lifecycle、reloadData、setSelectedIndex、scroll discovery、inset、overscroll 或示例工程 UI 的改动，必须重点检查职责归属是否仍符合本文档和 `docs/architecture.md`。
4. 自审发现实现与计划或文档假设不一致时，必须及时提醒用户，并在继续开发前更新对应文档；不要把架构问题留到版本末尾。
5. 任务验收说明必须记录自审结论；没有自审记录的任务不得标记完成。

优先验证命令：

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=<available simulator>' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
```

仓库尚未具备对应 target 时，必须说明未运行原因，并运行当前阶段可用的替代校验。

## 日志硬性要求

1. 必要事件必须通过统一内部日志门面记录，方便后续调试、开发和问题修复。
2. 日志门面命名为 `AnchorPagerLogger` 或同等清晰名称。
3. 日志底层优先使用 `os.Logger`。
4. 不得在框架库中散落 `print`。
5. 日志 subsystem 建议为 `com.anchorpager.AnchorPager`。
6. category 至少覆盖 lifecycle、layout、header、paging、children、scroll、inset、overscroll、gesture、accessibility、resource。
7. 高频滚动路径不得逐帧输出普通日志，只记录状态变化、阈值跨越、owner 切换、异常或采样日志。
8. 日志不得输出业务数据、用户内容、完整 view 层级或可能包含隐私的数据。
9. 新增关键日志事件时必须同步提交日志测试。
10. 日志测试应通过内部可注入 log sink 或等价机制验证，不依赖人工查看控制台。
11. 日志门面不得整体限制为 `@MainActor`；`AnchorPagerLogger.log` 必须可从非主线程内部路径调用。需要隔离的测试 sink 可以单独使用 MainActor 或等价同步机制保护。

## UIKit 与并发要求

1. UIKit 类型、公开 API、data source、delegate、coordinator 状态更新保持 `@MainActor`。
2. 只有直接操作 UIKit 状态或维护 UI lifecycle/coordinator 状态的内部类型应整体使用 `@MainActor`；日志、断言、纯计算工具等非 UI 基础设施不得为了方便整体限制主线程。
3. 若类型本身不需要 actor 隔离，优先移除不必要的 `@MainActor`；只有在 actor 或 global actor 内提供同步非隔离入口时才考虑 `nonisolated`，不得使用 `nonisolated(unsafe)` 粗暴绕过。
4. 不使用 `Task.detached` 绕过 actor 隔离。
5. 不使用 `@unchecked Sendable`、`nonisolated(unsafe)`、`@preconcurrency` 粗暴压制问题，除非有明确线程安全说明并写入文档。
6. Header 使用 UIViewController 时必须通过标准 UIKit containment 管理。
7. AnchorPagerViewController 是 child lifecycle 策略、page identity、reload 清理和对外状态语义的唯一管理者；横向 page 的实际 UIKit containment 可以由内部 Tabman/Pageboy adapter 执行。
8. page 切换、reloadData、setSelectedIndex、懒加载和卸载都不能破坏生命周期语义；不得让 AnchorPager 与 Tabman/Pageboy 对同一 page view controller 形成双重 containment。

## Git 与提交要求

1. 修改前先查看 `git status --short`。
2. 不要回滚用户或其他代理已做的无关修改。
3. 不要使用破坏性命令，例如 `git reset --hard`、`git checkout --` 或未确认的删除操作。
4. 每个提交保持主题单一。
5. 文档、测试、实现可以分开提交；同一个实现任务的测试必须与实现一起提交或紧随同任务提交。
6. Git 提交描述必须使用中文，包含提交标题和需要时的提交正文。
7. 提交前至少运行 `git diff --check`。

## 文档要求

1. public/open API 使用简洁 DocC 注释。
2. `README.md` 面向接入者，包含最小接入、Header UIView、Header UIViewController、显式 scroll view、无 UIScrollView child 示例。
3. `docs/architecture.md` 面向维护者，说明架构、状态机、safe area、scroll discovery、inset ownership、child lifecycle、gesture priority、第三方适配边界、日志策略和 known limitations。
4. 每个版本完成时更新 `docs/task-list.md` 对应状态。
5. 每次开发完成、任务状态变化或发生重要设计/API/架构/依赖/测试/验收变更时，必须同步更新对应文档，包括但不限于 `README.md`、`docs/architecture.md`、`docs/task-list.md`、相关 `docs/superpowers/specs/` 和 `docs/superpowers/plans/` 文档。
6. 新增长期有效文档时，必须同步登记到本文件的「必读文档」或本节文档索引中，说明其适用场景，避免后续代理漏读。
7. 文档只标记真实完成状态；示例工程、UI 测试、验收命令或功能装配未完成时必须保留未完成标记，并写明未运行或未完成原因。

## 完成定义

一个任务只有在同时满足以下条件时才算完成：

1. 功能或文档变更已按范围完成。
2. 对应测试已新增或更新。
3. 必要 UI 测试已新增或明确说明替代验证。
4. 必要日志已新增，并有日志测试。
5. 已运行可用验证命令并记录结果。
6. `git diff --check` 通过。
7. 没有泄漏 Tabman/Pageboy 类型到 public API。
8. 没有引入具体业务场景命名。
9. 工作区没有未解释的无关改动。
