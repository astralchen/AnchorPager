# AnchorPager 版本演进设计

## 背景

AnchorPager 是一个全新的 UIKit 容器框架，目标是提供可变 Header、吸顶分段栏、多页面横向分页、纵向嵌套滚动、顶部 overscroll 事件处理、状态栏点击顶滚、尺寸变化恢复和完整 child view controller 生命周期管理。

当前仓库只有 MIT 许可证，没有既有 Swift Package、源码、示例或测试。本设计从零定义 AnchorPager 的版本演进路线，不迁移、引用、复用或沿用任何旧项目代码、接口、目录结构、文档或测试。

## 设计原则

1. AnchorPager 的 public API 保持领域无关，只使用 UIKit 风格命名。
2. Tabman 和 Pageboy 只允许出现在 internal adapter 层，不泄漏到 public API。
3. v0.1 优先交付可视分页路径，让 Header、分段栏、横向滑动和页面切换真实运行。
4. 后续版本逐步收紧布局、inset、child 生命周期、纵向滚动协调、overscroll、手势状态机和系统级边界行为。
5. 每个版本都必须可编译、可测试、可示例验证；不把不可验证的半成品合入主线。
6. Swift 6 并发检查问题不通过 `@unchecked Sendable`、`nonisolated(unsafe)` 或 `@preconcurrency` 粗暴压制。
7. UIKit 状态更新、public API、data source、delegate 和 coordinator 操作保持 MainActor 语义；日志、断言、纯计算工具等非 UI 基础设施不得为了方便整体限制主线程。
8. 每个实现任务完成时必须同步提供测试，不能把测试推迟到后续任务统一补。
9. 触达用户可见 UI、UIKit 生命周期、手势、滚动、分页、状态栏点击、尺寸变化或辅助功能的任务必须包含必要 UI 测试。
10. 必要事件必须通过统一内部日志门面记录，方便后续调试、开发和问题修复。
11. 日志使用 `os.Logger`，避免在框架库中散落 `print`。
12. 高频滚动路径只记录状态变化、阈值跨越、owner 切换、异常或采样日志，避免逐帧输出。
13. 新增功能、重要逻辑变更和问题修复必须先完成影响评估，覆盖 public API、内部分层、UIKit containment、child lifecycle、scroll discovery、inset ownership、paging adapter、gesture/overscroll、日志、测试、示例工程和文档。
14. 任何局部修复都不得破坏后续版本扩展路线；如果影响跨模块契约、线程/actor 隔离、生命周期或用户可见行为，必须先更新设计说明或计划文档，再实现。

## 依赖基线

AnchorPager 的最低系统版本为 iOS 14，语言目标为 Swift 6，包管理器为 Swift Package Manager。

截至 2026-07-09 核对：

1. Tabman 最新发布为 4.0.1，发布页说明该版本更新到 Pageboy 5.0.2，并且 Tabman 4.0.0 起支持 Swift 6、要求 iOS 14 或更高版本。来源：https://github.com/uias/Tabman/releases
2. Pageboy 最新发布为 5.0.2，Pageboy 5.0.0 起要求 iOS 14、Xcode 16，并支持 Swift 6 严格并发。来源：https://github.com/uias/Pageboy/releases

v0.1 计划锁定：

1. Tabman：`from: "4.0.1"`
2. Pageboy：由 Tabman 依赖解析到 `5.0.2`，如实现中必须直接依赖 Pageboy，则同样锁定 `from: "5.0.2"`

## 总体架构

AnchorPagerViewController 是唯一 public 容器入口。它负责数据加载、Header 承载、页面选择状态、外部配置、delegate 回调和 UIKit containment 边界。

内部按职责拆分：

1. `Public`：公开 API、配置、delegate、data source、UIViewController scroll 接入扩展。
2. `Core`：主控制器内部状态、reload 流程、选择提交规则、公共 coordinator 汇聚点，以及不依赖 UIKit 状态的内部断言等非 UI 基础设施。
3. `Layout`：Header、bar、child viewport、safe area、遮挡和 managed inset 的纯计算。
4. `Header`：Header view 和 Header view controller 的测量、承载、布局和 containment。
5. `Children`：child view controller store、缓存窗口、offset snapshot、fallback scroll host。
6. `Paging`：Tabman/Pageboy adapter，负责横向分页、分段栏渲染、indicator 和切页事件收敛。
7. `Overscroll`：顶部 overscroll owner、模式和手势期间状态。
8. `Gesture`：纵向拖拽、横向分页、程序化分页、layout reload、尺寸变化之间的 internal interaction state。
9. `Logging`：统一内部日志门面，封装 `os.Logger`、category、level、可测试 log sink 和消息格式。日志门面本身不绑定 MainActor，`log` 可从非主线程内部路径调用；测试 sink 单独隔离，避免把诊断路径强行串到主线程。

## 版本演进路线

### v0.1：可视分页核心版

目标：交付第一个可运行的 UIKit 容器框架，让使用者能看到 Header、分段栏和多页面横向分页。

范围：

1. 创建 Swift Package：`AnchorPager`。
2. 配置 iOS 14、Swift 6、Tabman 4.0.1。
3. 实现 `AnchorPagerViewController` public API skeleton。
4. 实现 data source、delegate、configuration、header content、height mode、top behavior、offset adjustment、top overscroll mode。
5. 实现 Header view 和 Header view controller 基础承载。
6. 实现 Tabman/Pageboy internal adapter，支持分段栏点击、横向滑动和程序化 `setSelectedIndex`。
7. 实现基础 child containment，确保首次加载走 `addChild`、添加 view、`didMove(toParent:)`。
8. 实现 `UIViewController.anchorPagerScrollView`、`anchorPagerUsesDefaultScrollViewLookup` 和确定性默认 scroll view lookup。
9. 实现内部 `AnchorPagerLogger`，覆盖 lifecycle、layout、header、paging、children、scroll、inset、overscroll、gesture、accessibility、resource category。
10. 为 reloadData、Header 承载、child containment、分页切换、越界 no-op、fallback host 等 v0.1 关键事件加入日志。
11. 建立 `docs/architecture.md`、`README.md` 和最小示例工程。
12. 建立核心单测目录，覆盖 public API 语义、scroll lookup、基础 Header 测量、基础 selectedIndex 行为和关键日志事件。

非目标：

1. 不承诺完整纵向嵌套滚动协调。
2. 不承诺完整顶部 overscroll owner 互斥。
3. 不承诺完整手势状态机。
4. 不承诺完整旋转、Split View、Stage Manager 恢复。

验收：

1. 示例工程能显示 Header、分段栏和多个 child 页面。
2. 点击分段栏、横向滑动、调用 `setSelectedIndex` 都能切换页面。
3. public API 不包含 Tabman 或 Pageboy 类型。
4. `swift package resolve` 成功。
5. Package 单测通过。
6. 关键日志事件测试通过。

### v0.2：Header 与布局稳定版

目标：把 Header 高度、安全区域和吸顶规则固化为可测试的布局契约。

范围：

1. 实现 `AnchorPagerLayoutEngine`。
2. 支持 `automatic(min:max:)`、`fixed(max:min:)`、`ranged(min:max:)`。
3. 支持 `insideSafeArea` 和 `extendsUnderTopSafeArea`。
4. 实现 Header 自动测量：UIView 使用 Auto Layout fitting size、bounds、intrinsicContentSize；UIViewController 使用 view fitting size 和 preferredContentSize。
5. 实现 `reloadHeaderLayout(offsetAdjustment:)` 的四种 offset 策略。
6. 支持 Header frame 和 height 运行时变化。
7. 将可见顶部和底部遮挡转换到 AnchorPagerViewController.view 本地坐标参与计算。
8. 记录 Header 测量结果、Header frame 变化、bar frame 变化、safe area 变化、bounds 变化和 managed inset 变化日志。

验收：

1. Header automatic、fixed、ranged 单测通过。
2. Header height clamp 单测通过。
3. insideSafeArea、extendsUnderTopSafeArea 布局单测通过。
4. navigation bar 显隐、tab bar、toolbar、additionalSafeAreaInsets 单测通过。
5. Header controller containment 测试通过。

### v0.3：Scroll Discovery 与 Inset Ownership 版

目标：把 child scroll 接入和 inset 所有权做成稳定契约。

范围：

1. 使用 associated object 存储显式设置的 `anchorPagerScrollView`。
2. 默认查找采用确定性深度优先策略。
3. 默认查找忽略 hidden、alpha 接近 0、`isUserInteractionEnabled == false` 的 UIScrollView。
4. 多个候选只选择第一个符合规则的 UIScrollView。
5. 默认查找不跨 child view controller 边界。
6. 支持关闭默认查找。
7. 无候选 UIScrollView 时使用内部 page scroll host。
8. 区分 managed inset 和外部追加 inset，不覆盖调用方原有 contentInset。
9. AnchorPager 接管的 child scroll view 设置 `contentInsetAdjustmentBehavior = .never`，并在文档说明。
10. 记录显式 scroll view 命中、默认 lookup 命中、fallback host、managed inset 写入或跳过日志。

验收：

1. 显式 scroll view 优先测试通过。
2. 默认嵌套查找、过滤规则、多候选稳定性测试通过。
3. 关闭默认查找和无 scroll view fallback host 测试通过。
4. 不跨 child view controller 边界测试通过。
5. managed inset 不覆盖外部 contentInset 测试通过。

### v0.4：Child 生命周期与缓存版

目标：让 child containment、reload、缓存和释放行为可信。

范围：

1. 实现 `AnchorPagerChildViewControllerStore`。
2. 定义缓存窗口，默认至少保留 current page，可配置是否保留相邻页。
3. 卸载 child 前保存 scroll offset、managed inset 状态和 appearance 状态。
4. `reloadData` 清理旧 child、旧 offset snapshot 和旧 Tabman/Pageboy 状态。
5. `reloadData` 后 selectedIndex 越界时 clamp 到有效范围。
6. 空页时 selectedIndex 对外保持 0，effectiveSelectedIndex 为 nil。
7. `setSelectedIndex` 越界时 no-op，并在 Debug 下 assertionFailure。
8. data source 返回重复 view controller 时触发 Debug assertion，并在 Release 中只保留第一次出现的实例，重复页面使用内部空白承载页，避免同一个 UIViewController 被重复 containment。
9. 记录 child add/remove、cache window 更新、offset snapshot 保存/恢复、重复 view controller 降级日志。

验收：

1. child add/remove containment 单测通过。
2. child appearance lifecycle 顺序测试通过。
3. child cache window 和 unload offset snapshot 测试通过。
4. reloadData 后旧 child 可释放测试通过。
5. selectedIndex/effectiveSelectedIndex、越界 no-op、reloadData clamp 测试通过。

### v0.5：纵向嵌套滚动协调版

目标：实现 Header 折叠/展开和当前 child 纵向滚动之间的协作。

范围：

1. 实现 `AnchorPagerScrollCoordinator`。
2. Header 未完全折叠时优先响应向上滚动。
3. Header 未完全展开时优先响应向下滚动。
4. Header 完全折叠后，当前 child scroll view 正常滚动。
5. 不同 contentSize child 切换时保持合理可见位置。
6. 处理 Header 接近完全展开、完全折叠、child top boundary 时的 UIKit rubber-band 抖动。
7. 主动设置 contentOffset 时使用 guarded update，避免 scrollViewDidScroll 重入污染状态。
8. child contentSize 变化时避免重复写入相同 managed inset 导致滚动震荡。
9. 记录 Header 完全展开、Header 完全折叠、child top boundary、scroll owner 切换、guarded contentOffset update 被触发或跳过日志。

验收：

1. Header 展开/折叠单测通过。
2. child top boundary 抖动测试通过。
3. 不同 contentSize child 切换测试通过。
4. contentOffset guarded update 防重入测试通过。
5. contentSize 变化不导致 managed inset 重复写入测试通过。

### v0.6：顶部 Overscroll 事件处理版

目标：实现 none、container、child 三种顶部 overscroll handling 模式。

范围：

1. 实现 `AnchorPagerOverscrollCoordinator`。
2. AnchorPager 不创建、不包装、不暴露任何顶部拉取控件。
3. AnchorPager 不定义顶部拉取事件回调或任务生命周期。
4. Header 完全展开前，滚动优先用于展开 Header。
5. `none` 模式不接管顶部 overscroll。
6. `container` 模式下，Header 完全展开后的继续下拉由 verticalScrollView 处理。
7. `child` 模式下，Header 完全展开后的继续下拉由当前 child scroll view 或内部 page scroll host 处理。
8. 同一次下拉手势中只能有一个 top overscroll owner。
9. owner 进入和退出使用明确阈值，避免反复切换。
10. 横向分页、Header layout reload、屏幕旋转或 child 切换期间取消 active top overscroll handling。
11. 记录 overscroll mode、owner 进入、owner 退出、owner cancel 和阈值判定日志。

验收：

1. 三种 overscroll mode 单测通过。
2. top overscroll owner 互斥测试通过。
3. Header 展开优先于 overscroll 测试通过。
4. owner 进入/退出阈值测试通过。
5. 横向分页和 reload 期间取消策略测试通过。

### v0.7：手势与交互状态机版

目标：将复杂交互统一纳入 internal state，避免 UIKit 回调乱序导致状态污染。

范围：

1. 定义 internal interaction state：idle、verticalDragging、verticalDecelerating、horizontalPaging、programmaticPaging、topOverscrolling、layoutReloading、transitioningSize。
2. 同一时刻只有一个主交互 owner。
3. 每个状态都有 begin、update、finish、cancel 路径。
4. setSelectedIndex、分段栏点击、横向滑动完成、横向滑动取消走同一套 selection commit/cancel 规则。
5. selectedIndex 只在页面切换确认完成后提交。
6. 非相邻页面切换不连续滚过中间页，直接建立 source/target 过渡语义。
7. 快速连续 `setSelectedIndex` 或连续点击时，旧 completion 不能覆盖新请求状态。
8. reloadData 和 reloadHeaderLayout 发生在非 idle 状态时，执行明确 cancel 或延迟合并策略。
9. 系统返回手势、横向分页手势、child 横向 content scroll 手势之间有明确优先级；第一页 leading-edge 返回手势不被吞掉。
10. 记录 interaction state begin、重要 update 边界、finish、cancel、非法 transition 忽略日志。

验收：

1. paging cancel 不提交 selectedIndex 测试通过。
2. 快速连续 setSelectedIndex 测试通过。
3. 非相邻页面切换测试通过。
4. reloadData/reloadHeaderLayout 非 idle 策略测试通过。
5. 横向分页与纵向拖拽竞争测试通过。
6. 系统返回手势与横向分页手势优先级测试通过。

### v0.8：状态栏点击与尺寸变化版

目标：补齐系统级 UIKit 行为。

范围：

1. 实现 scrollsToTop owner 管理。
2. AnchorPager 管理范围内任一时刻只有一个 UIScrollView 的 scrollsToTop 为 true。
3. 横向 paging scroll view 永远不能响应 scrollsToTop。
4. Header 未完全折叠时，verticalScrollView 作为唯一 scroll-to-top 响应者。
5. Header 已完全折叠且当前 child 可见时，当前 child scroll view 或内部 page scroll host 作为唯一响应者。
6. 空页状态下，AnchorPager 管理的所有 scroll view 都关闭 scrollsToTop。
7. 在 viewWillTransition、viewSafeAreaInsetsDidChange、viewDidLayoutSubviews 后重新计算布局。
8. 尺寸变化后保持 selectedIndex，尽量保持 Header 折叠进度和当前 child 可见内容位置。
9. 拖拽、减速、分页、top overscroll 期间发生尺寸变化时，延迟合并布局请求到 idle 或执行明确 cancel。
10. 记录 scrollsToTop owner 变化、尺寸变化请求、布局延迟合并和 cancel 日志。

验收：

1. scrollsToTop 唯一 owner 测试通过。
2. Header 折叠状态下 owner 切换测试通过。
3. 空页关闭 scrollsToTop 测试通过。
4. 页面切换、reloadData、Header layout reload、屏幕旋转后重新计算 owner 测试通过。
5. screen rotation、bounds change、safe area change 后 Header、bar、child inset 一致性测试通过。

### v0.9：可访问性、RTL 与示例矩阵版

目标：把框架从功能可用提升到 UIKit 质量可交付。

范围：

1. 分段栏 item 支持 selected 和 button accessibility traits。
2. Header、bar、child 内容保持合理 VoiceOver 访问顺序。
3. 支持 Dynamic Type，分段栏高度或 item 布局变化后触发布局更新。
4. 支持 Reduce Motion，非必要动画降级或缩短。
5. 支持 left-to-right 和 right-to-left layout direction。
6. 明确 RTL 下横向分页方向、分段栏 indicator 位置、非相邻页面过渡方向。
7. 示例工程覆盖基础分页、不同 contentSize、Header 安全区域模式、Header 动态高度、顶部 overscroll、屏幕旋转、无 UIScrollView child。
8. 至少一个 UI test 覆盖 Header 展开优先于顶部 overscroll handling。
9. 日志 category 和可测试 log sink 文档化，便于 UI 测试失败后定位事件路径。

验收：

1. Dynamic Type 测试通过。
2. Reduce Motion 测试通过。
3. RTL layout direction 测试通过。
4. Example build 验证通过。
5. UI test 覆盖 Header 展开优先于顶部 overscroll handling。

### v1.0：稳定 API 发布版

目标：冻结核心 public API，达到稳定发布质量。

范围：

1. 补齐 public/open API 的 DocC 注释。
2. 完善 README：最小接入、Header UIView、Header UIViewController、显式 anchorPagerScrollView、无 UIScrollView child 示例。
3. 完善 `docs/architecture.md`：public API 契约、状态机、safe area 策略、scroll view discovery 策略、inset ownership、child lifecycle、gesture priority、known limitations。
4. 记录 Tabman/Pageboy 已验证版本和 adapter 边界。
5. 清理 internal 状态命名，确保不暴露 pin anchor、owner、handoff 等内部词。
6. 修复 Swift 6 并发警告。
7. 完成资源生命周期清理：KVO、Notification、gesture delegate、display link、Task、closure callback 在 child 卸载或 deinit 时释放。
8. 检查 child store、adapter、coordinator 之间不存在 retain cycle。
9. 清理日志 category 和消息格式，确保关键事件可定位且无隐私数据。
10. README 和 `docs/architecture.md` 说明日志策略、category、过滤方式和性能注意事项。

验收：

1. `git diff --check` 通过。
2. `swift package resolve` 通过。
3. `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=<available simulator>' test` 通过。
4. `xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build` 通过。
5. public API 不暴露第三方类型。
6. README 和 architecture 文档覆盖完整契约。

### v1.1 及后续：增强与维护版

目标：在不破坏 v1.0 public API 的前提下提升质量、兼容性和可配置能力。

方向：

1. 性能 profiling 和滚动帧率优化。
2. 更多 child 缓存策略。
3. 更丰富但仍领域无关的 bar 样式配置。
4. 更细粒度的动画降级策略。
5. 更多 UI tests 和真实设备验证。
6. Tabman/Pageboy 新版本兼容验证。
7. 根据真实项目接入反馈修复边界问题。

破坏性 API 变更只进入明确的 v2.0 设计流程。

## 数据流

1. 使用者设置 dataSource、delegate 和 configuration。
2. `reloadData` 请求 dataSource 提供 page count、title、child view controller 和 Header content。
3. HeaderCoordinator 承载并测量 Header。
4. LayoutEngine 根据 Header、bar、safe area、底部遮挡和当前折叠状态生成 layout context。
5. Paging adapter 将 title 和 child view controller 交给 Tabman/Pageboy，并把 page change 事件收敛回 AnchorPager。
6. Child store 管理已加载 child、缓存窗口、offset snapshot 和 fallback scroll host。
7. ScrollCoordinator 在 v0.5 起协调 verticalScrollView 与当前 child scroll view。
8. OverscrollCoordinator 在 v0.6 起处理顶部 overscroll owner。
9. GestureCoordinator 在 v0.7 起统一处理交互状态和 selection commit/cancel。
10. Logging 层记录关键事件，内部可测试 log sink 用于验证日志路径。
11. Delegate 收到 didSelect、Header collapse progress 和 layout context 更新。

## 错误处理和边界策略

1. dataSource 缺失时 page count 视为 0。
2. Swift 协议返回 `Int`，page count 不存在小于 0 的合理业务语义；如果 dataSource 返回负数，Debug 下 assertionFailure，Release 中按 0 处理。
3. `setSelectedIndex` 越界时 no-op，Debug 下 assertionFailure。
4. reloadData 后 selectedIndex 越界时 clamp；无页面时 selectedIndex 对外保持 0，effectiveSelectedIndex 为 nil。
5. 重复 view controller 在 Debug 下 assertionFailure；Release 中只保留第一次出现的实例，重复页面使用内部空白承载页。
6. Header 测量结果为负数或非有限数时按最小高度处理，Debug 下 assertionFailure。
7. Tabman/Pageboy 回调缺失、重复或乱序时，adapter 将事件标准化后再驱动 AnchorPager 状态。
8. UIKit containment 调用失败不被静默吞掉，Debug 下触发 assertion，Release 中尽量回到空页或 fallback host 状态。

## 测试策略

测试随版本递增，不把完整矩阵推迟到 v1.0 才补。

每个任务的完成定义必须包含测试证据。纯计算、状态转换和 API contract 使用单元测试或集成测试覆盖；涉及 UIKit 可见行为、用户交互、分页、滚动、手势、状态栏点击、旋转、safe area、Dynamic Type、Reduce Motion、RTL 或示例工程行为时，必须补充必要 UI 测试。如果某个 UI 行为无法通过 UI 测试稳定覆盖，任务说明必须写明原因，并提供可重复运行的替代自动化验证。

日志同样需要测试。新增关键日志事件时，任务必须通过内部 log sink 或等价机制验证 category、level 和事件名称；高频滚动路径必须测试不会在普通状态下逐帧输出噪声日志。

1. v0.1 覆盖 public API skeleton、基础分页、scroll lookup、基础 Header、selectedIndex 和日志门面。
2. v0.2 覆盖布局引擎、Header 高度、安全区域和遮挡。
3. v0.3 覆盖 scroll discovery、fallback host 和 inset ownership。
4. v0.4 覆盖 child containment、appearance lifecycle、reload、缓存和释放。
5. v0.5 覆盖纵向滚动协调、rubber-band 边界和 guarded update。
6. v0.6 覆盖 overscroll mode、owner 互斥和阈值。
7. v0.7 覆盖 interaction state、selection commit/cancel 和手势优先级。
8. v0.8 覆盖 scrollsToTop owner、旋转、bounds change 和 safe area change。
9. v0.9 覆盖 Dynamic Type、Reduce Motion、RTL、Example build 和至少一个 UI test。
10. v1.0 运行完整验证命令并修复 Swift 6 并发警告。

## 文档策略

1. `README.md` 面向接入者，包含可复制的最小示例和常见接入方式。
2. `docs/architecture.md` 面向维护者，说明架构、状态机、safe area、scroll discovery、inset ownership、child lifecycle、gesture priority、第三方适配边界和 known limitations。
3. public/open API 使用 DocC 注释。
4. 每个版本完成时更新文档中的实现状态和限制说明。
5. README 和 `docs/architecture.md` 说明日志策略、category、推荐过滤方式和性能注意事项。

## 发布门槛

每个版本发布前必须满足：

1. 版本范围内功能完成。
2. 版本范围内测试通过。
3. 示例工程仍可构建。
4. public API 没有意外泄漏第三方类型。
5. 文档说明当前能力和限制。
6. `git diff --check` 通过。
7. 版本内每个已完成任务都有对应测试证据。
8. 版本内所有需要 UI 测试的任务都有 UI 测试或明确的自动化替代验证说明。
9. 版本内新增关键事件均有日志，或明确说明无需日志的原因。

v1.0 额外要求：

1. 完整验证命令通过。
2. Swift 6 并发警告清理完毕。
3. 资源生命周期检查通过。
4. known limitations 明确记录。
5. public API 冻结。
6. 日志 category、消息格式和隐私策略完成审查。

## 当前决策

本项目先按“v0.1 可视分页核心版”进入实现计划。后续版本按本设计顺序推进，除非 Tabman/Pageboy API 限制或测试发现需要调整内部 adapter；此类调整不得扩大 public API，也不得破坏第三方类型不泄漏的边界。
