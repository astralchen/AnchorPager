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

如果当前任务是在执行、继续、审查或验收某个开发计划，还必须阅读对应计划文档。当前已登记计划：

1. `docs/superpowers/plans/2026-07-09-v0-1-foundation.md`

实现过程中如果发现本文档与上述文档冲突，以更严格的约束为准；如果仍无法判断，先更新设计或向用户确认，不要自行扩大 public API。

## 技术基线

1. Package name：`AnchorPager`
2. Library product：`AnchorPager`
3. Module name：`AnchorPager`
4. Minimum OS：iOS 14
5. Language：Swift 6
6. UI stack：UIKit
7. Package manager：Swift Package Manager
8. Horizontal paging：Tabman + Pageboy
9. Tabman 版本从 `4.0.1` 开始
10. Pageboy 解析或直接依赖到 `5.0.2`

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

## 变更影响评估

1. 新增功能、修改重要逻辑或修复问题前，必须先梳理影响范围，再开始实现。
2. 影响范围至少覆盖 public API、内部分层、UIKit containment、child lifecycle、scroll discovery、inset ownership、paging adapter、gesture/overscroll、日志、测试、示例工程和文档。
3. 设计必须兼顾后续版本扩展，不得为了当前单点修复破坏既有架构边界、状态语义或未来版本路线。
4. 如果变更可能影响 public API、跨模块契约、第三方 adapter 边界、线程/actor 隔离、生命周期或用户可见行为，必须先更新设计说明或计划文档，再实现。
5. 修复问题时必须同时分析回归风险和相邻路径，避免只修当前复现场景却引入分页、滚动、生命周期或示例工程新问题。
6. 无法确定影响范围时，先补充设计记录或向用户确认，不得直接扩大 public API 或绕开现有约束。
7. 审查或实现过程中如果发现“现有实现的真实职责”和文档、计划或架构假设不一致，尤其是第三方库职责、UIKit containment、appearance lifecycle、selection commit/cancel、scroll/inset ownership 等边界问题，必须及时提醒用户，并同步更新对应文档，不能只在代码里临时绕过。

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

当前首个实现版本是 v0.1 可视分页核心版。按 `docs/task-list.md` 逐项推进，不要跳过基础设施直接实现后续版本。

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
