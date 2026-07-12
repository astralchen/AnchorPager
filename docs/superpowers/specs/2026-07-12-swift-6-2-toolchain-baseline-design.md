# Swift 6.2 最低工具链基线设计

**日期：** 2026-07-12

**状态：** 已确认

**适用范围：** Package manifest、开发环境、CI/验收命令、项目长期技术基线和后续版本计划

## 背景

AnchorPager 当前已提交的 Package manifest 仍使用：

```swift
// swift-tools-version: 6.0
```

本次变更将它提升为 `6.2`。当前验证环境为 Apple Swift 6.2.4 / Xcode 26.3；AGENTS、requirements、task-list
和 roadmap 仍将技术基线笼统写为“Swift 6”，也需要同步，避免继续暗示 Swift 6.0/6.1 受支持。

SwiftPM 的 tools version 与 Swift language mode 是两个不同维度：

- tools version 决定解析 Package manifest 所需的最低 SwiftPM/编译器工具链；
- `swiftLanguageModes: [.v6]` 选择 Swift 6 语言模式。SwiftPM 不使用 `.v6_2` 表示 Swift 6.2 工具链。

## 决策

1. AnchorPager 的最低开发和构建工具链调整为 Swift 6.2。
2. `Package.swift` 保持 `// swift-tools-version: 6.2`。
3. `swiftLanguageModes: [.v6]` 保持不变，继续启用 Swift 6 language mode 和严格并发语义。
4. `AnchorPagerViewController` 暂时保留已验证的 `deinit + MainActor.assumeIsolated` 同步资源归还。验证环境
   Xcode 26.3 / Swift 6.2.4 / x86_64 iPhone 17 Simulator 中，改用 `isolated deinit` 会在 lifecycle deinit 后稳定触发
   allocator `pointer being freed was not allocated` 崩溃；恢复现有实现后同一析构测试通过。不得提交该崩溃路径，
   也不得用条件编译、异步 Task 或 unsafe 标记掩盖。
5. Minimum OS 继续为 iOS 14；UIKit、Tabman 4.0.1、Pageboy 5.0.2 基线不变。
6. AGENTS、requirements、task-list、roadmap、architecture、README 和当前有效实施计划使用统一表述：
   “最低工具链 Swift 6.2，语言模式 Swift 6”。
7. 已完成的历史计划保留当时的“Swift 6”执行记录，不机械改写历史验收文本；如果历史文档被引用为当前约束，补充
   当前基线链接或说明。

## 验收

1. `swift --version` 必须报告 Swift 6.2 或更高版本。
2. `Package.swift` tools version 必须不低于 6.2。
3. `swift package resolve` 通过。
4. Framework 全量测试、Example generic build 和 Example 全量测试使用 Swift 6.2+ 工具链通过。
5. 文档不得把 `.v6` language mode 误写为最低工具链仍是 Swift 6.0，也不得发明不存在的 `.v6_2` language mode。
6. deinit 资源归还测试继续证明 Store、fallback 和 managed inset 在控制器析构时同步清理。
7. 工具链升级不要求生产源码出现 `isolated deinit`；后续 Xcode/Swift 升级时必须以同一资源析构测试单独复验，
   通过前不得替换 `MainActor.assumeIsolated`。

## 对后续版本的影响

1. v0.4 代际原子性修复及 v0.5–v1.0 后续开发统一以 Swift 6.2+ 为验收环境。
2. Swift 6.2 新增或收紧的并发诊断必须从 actor/ownership 根因修复，不使用 unsafe 标记压制。
3. CI 或贡献文档后续新增工具链矩阵时，不再要求 Swift 6.0/6.1 兼容。
4. 该调整不扩大 AnchorPager public API，也不改变运行时最低 iOS 版本。
5. `isolated deinit` 作为已知工具链限制留在后续兼容验证清单，不阻塞 Swift 6.2 最低 tools version 本身。
