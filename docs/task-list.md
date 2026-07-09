# AnchorPager 任务清单

本文档用于跟踪 AnchorPager 从 v0.1 到 v1.1+ 的开发任务。需求基线见 `docs/requirements.md`，版本演进设计见 `docs/superpowers/specs/2026-07-09-anchorpager-version-roadmap-design.md`。

## 状态说明

- `[ ]` 未开始
- `[x]` 已完成

## 全局约束

- [ ] 保持 Package name、Library product、Module name 均为 `AnchorPager`
- [ ] 最低系统版本保持 iOS 14
- [ ] 语言目标保持 Swift 6
- [ ] UI stack 保持 UIKit
- [ ] 使用 Swift Package Manager
- [ ] 横向分页使用 Tabman + Pageboy
- [ ] Tabman/Pageboy 类型只出现在 internal adapter 层
- [ ] Public API 不暴露第三方库类型
- [ ] Public API、data source、delegate、coordinator 状态更新保持 `@MainActor`
- [ ] 不复制参考项目源码、public API 或命名
- [ ] 不引入具体业务场景、内容类型、数据模型或场景命名
- [ ] 不使用 `Task.detached` 绕过 actor 隔离
- [ ] 不使用 `@unchecked Sendable`、`nonisolated(unsafe)`、`@preconcurrency` 粗暴压制并发问题
- [ ] 每个重要行为都有对应测试
- [ ] 每完成一个实现任务都同步提交对应测试
- [ ] 触达用户可见 UI、UIKit 生命周期、手势、滚动、分页或系统交互的任务包含必要 UI 测试
- [ ] 无法稳定使用 UI 测试覆盖的 UI 行为写明原因，并提供替代自动化验证
- [ ] 每个任务验收记录实际运行过的测试命令和结果
- [ ] 必要事件通过统一内部日志门面记录
- [ ] 日志使用 `os.Logger`，不在框架库中散落 `print`
- [ ] 高频滚动路径不逐帧输出普通日志
- [ ] 日志不得输出业务数据、用户内容或可能包含隐私的数据
- [ ] 新增关键日志事件时同步提交日志测试
- [ ] 每个版本完成前运行 `git diff --check`

## v0.1：可视分页核心版

目标：先交付真实可见的 Header、分段栏和多页面横向分页路径。

### 工程与依赖

- [ ] 创建 `Package.swift`
- [ ] 配置 iOS 14+ platform
- [ ] 配置 Swift 6 language mode
- [ ] 添加 Tabman 依赖，版本从 `4.0.1` 开始
- [ ] 确认 Pageboy 解析到 `5.0.2`
- [ ] 创建 `Sources/AnchorPager/`
- [ ] 创建 `Tests/AnchorPagerTests/`
- [ ] 创建 `Examples/AnchorPagerExample/`
- [ ] 创建 `README.md`
- [ ] 创建 `docs/architecture.md`

### 日志基础设施

- [ ] 创建 `Sources/AnchorPager/Logging/AnchorPagerLogger.swift`
- [ ] 使用 `os.Logger` 作为日志底层
- [ ] 定义 subsystem：`com.anchorpager.AnchorPager`
- [ ] 定义 lifecycle category
- [ ] 定义 layout category
- [ ] 定义 header category
- [ ] 定义 paging category
- [ ] 定义 children category
- [ ] 定义 scroll category
- [ ] 定义 inset category
- [ ] 定义 overscroll category
- [ ] 定义 gesture category
- [ ] 定义 accessibility category
- [ ] 定义 resource category
- [ ] 提供内部可注入 log sink 以便测试
- [ ] 测试日志 category 和 level 记录
- [ ] 测试日志不依赖人工查看控制台

### Public API Skeleton

- [ ] 创建 `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- [ ] 实现 `AnchorPagerViewController`
- [ ] 暴露 `dataSource`
- [ ] 暴露 `delegate`
- [ ] 暴露 `configuration`
- [ ] 暴露只读 `selectedIndex`
- [ ] 暴露只读 `effectiveSelectedIndex`
- [ ] 暴露 `verticalScrollView`
- [ ] 实现 `init(configuration:)`
- [ ] 实现 `reloadData()`
- [ ] 实现 `setSelectedIndex(_:animated:)`
- [ ] 实现 `reloadHeaderLayout(offsetAdjustment:)`
- [ ] 为 init 和 deinit 加入 lifecycle 日志
- [ ] 为 reloadData begin/end 加入 lifecycle 日志
- [ ] 为 setSelectedIndex 请求、越界 no-op 和 commit 加入 paging 日志
- [ ] 创建 `AnchorPagerViewControllerDataSource`
- [ ] 创建 `AnchorPagerViewControllerDelegate`
- [ ] 创建 `AnchorPagerHeaderContent`
- [ ] 创建 `AnchorPagerConfiguration`
- [ ] 创建 `AnchorPagerHeaderConfiguration`
- [ ] 创建 `AnchorPagerBarConfiguration`
- [ ] 创建 `AnchorPagerPagingConfiguration`
- [ ] 创建 `AnchorPagerHeaderHeightMode`
- [ ] 创建 `AnchorPagerHeaderTopBehavior`
- [ ] 创建 `AnchorPagerHeaderOffsetAdjustment`
- [ ] 创建 `AnchorPagerTopOverscrollHandlingMode`
- [ ] 创建 `AnchorPagerLayoutContext`
- [ ] 为 public/open API 添加简洁 DocC 注释

### Header 基础承载

- [ ] 创建 `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`
- [ ] 支持 `AnchorPagerHeaderContent.view`
- [ ] 支持 `AnchorPagerHeaderContent.viewController`
- [ ] Header viewController 使用标准 `addChild`、添加 view、`didMove(toParent:)`
- [ ] Header viewController 移除时使用 `willMove(toParent: nil)`、移除 view、`removeFromParent`
- [ ] 提供基础 Header 高度测量
- [ ] 默认 Header height mode 为 automatic，min 为 0，max 为 nil
- [ ] 默认 Header top behavior 为 insideSafeArea
- [ ] 为 Header view 承载加入 header 日志
- [ ] 为 Header viewController add/remove 加入 header 和 lifecycle 日志
- [ ] 为 Header 基础测量结果加入 layout 日志

### Tabman/Pageboy Adapter

- [ ] 创建 `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- [ ] 创建 `Sources/AnchorPager/Paging/AnchorPagerTabBarAdapter.swift`
- [ ] 在 adapter 内部接入 Tabman
- [ ] 在 adapter 内部接入 Pageboy
- [ ] 支持标题数据传入分段栏
- [ ] 支持 child view controller 数据传入分页容器
- [ ] 支持分段栏点击切页
- [ ] 支持横向滑动切页
- [ ] 支持 `setSelectedIndex(_:animated:)` 驱动切页
- [ ] 收敛 Tabman/Pageboy page change 事件
- [ ] 禁用或绕开 Tabman 自动 child inset
- [ ] 确保横向 paging scroll view 不暴露到 public API
- [ ] 为分页开始、完成、取消加入 paging 日志
- [ ] 为 Tabman/Pageboy 回调缺失、重复或乱序加入 paging 日志

### Child 基础管理

- [ ] 创建 `Sources/AnchorPager/Children/AnchorPagerChildViewControllerStore.swift`
- [ ] 首次加载 child 时执行 `addChild`
- [ ] 首次加载 child 时添加 child view
- [ ] 首次加载 child 时执行 `didMove(toParent:)`
- [ ] reloadData 时清理旧 child
- [ ] 空页时 `selectedIndex` 对外保持 0
- [ ] 空页时 `effectiveSelectedIndex` 为 nil
- [ ] setSelectedIndex 越界时 no-op
- [ ] Debug 下 setSelectedIndex 越界触发 assertionFailure
- [ ] 为 child add/remove 加入 children 日志
- [ ] 为 reloadData 清理旧 child 加入 children 日志

### Scroll View Discovery

- [ ] 创建 `Sources/AnchorPager/Public/UIViewController+AnchorPager.swift`
- [ ] 使用 associated object 存储显式 `anchorPagerScrollView`
- [ ] 使用 associated object 存储 `anchorPagerUsesDefaultScrollViewLookup`
- [ ] 默认启用 `anchorPagerUsesDefaultScrollViewLookup`
- [ ] 实现只读计算属性 `anchorPagerDefaultScrollView`
- [ ] 默认查找使用确定性深度优先策略
- [ ] 默认查找忽略 hidden UIScrollView
- [ ] 默认查找忽略 alpha 接近 0 的 UIScrollView
- [ ] 默认查找忽略 `isUserInteractionEnabled == false` 的 UIScrollView
- [ ] 多个候选时选择第一个符合规则的 UIScrollView
- [ ] 不跨 child view controller 边界查找
- [ ] 无候选 UIScrollView 时使用内部 page scroll host
- [ ] 为显式 scroll view 命中加入 scroll 日志
- [ ] 为默认 lookup 命中加入 scroll 日志
- [ ] 为 fallback page scroll host 加入 scroll 日志

### 文档与示例

- [ ] README 写入最小接入示例
- [ ] README 写入 Header UIView 示例
- [ ] README 写入 Header UIViewController 示例
- [ ] README 写入显式 `anchorPagerScrollView` 示例
- [ ] README 写入无 UIScrollView child 示例
- [ ] `docs/architecture.md` 说明 public API 契约
- [ ] `docs/architecture.md` 说明 Tabman/Pageboy adapter 边界
- [ ] `docs/architecture.md` 说明默认 scroll view lookup 规则
- [ ] `docs/architecture.md` 记录 Tabman/Pageboy 验证版本
- [ ] `docs/architecture.md` 说明日志策略、category、过滤方式和性能注意事项
- [ ] README 说明如何查看和过滤 AnchorPager 日志
- [ ] 示例工程显示 Header、分段栏和多个页面
- [ ] 示例工程支持点击分段栏切页
- [ ] 示例工程支持横向滑动切页

### v0.1 测试

- [ ] Public API 编译测试
- [ ] selectedIndex 空页测试
- [ ] effectiveSelectedIndex 空页测试
- [ ] setSelectedIndex 越界 no-op 测试
- [ ] reloadData 后 selectedIndex clamp 测试
- [ ] Header UIView 基础承载测试
- [ ] Header UIViewController containment 测试
- [ ] 显式 `anchorPagerScrollView` 优先测试
- [ ] 默认 scroll view lookup 测试
- [ ] 多个 UIScrollView 选择顺序测试
- [ ] hidden、alpha、userInteractionEnabled 过滤测试
- [ ] 关闭默认查找测试
- [ ] 无 UIScrollView child fallback host 测试
- [ ] 不跨 child view controller 边界查找测试
- [ ] 基础 child add/remove containment 测试
- [ ] Tabman/Pageboy 类型不泄漏 public API 检查
- [ ] 日志门面单测
- [ ] reloadData 日志测试
- [ ] Header 承载日志测试
- [ ] child add/remove 日志测试
- [ ] 分页切换日志测试
- [ ] fallback host 日志测试

### v0.1 验收

- [ ] `swift package resolve` 通过
- [ ] Package 单测通过
- [ ] 示例工程可构建
- [ ] 示例工程可显示 Header、分段栏和多个页面
- [ ] 点击、横滑、API 三种切页方式可用
- [ ] v0.1 关键事件日志测试通过
- [ ] `git diff --check` 通过

## v0.2：Header 与布局稳定版

- [ ] 创建 `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`
- [ ] 实现 automatic height 测量
- [ ] 实现 fixed height clamp
- [ ] 实现 ranged height clamp
- [ ] 实现 insideSafeArea 布局
- [ ] 实现 extendsUnderTopSafeArea 布局
- [ ] 实现 Header runtime frame 变化
- [ ] 实现 `reloadHeaderLayout(.preserveVisualPosition)`
- [ ] 实现 `reloadHeaderLayout(.preserveCollapseProgress)`
- [ ] 实现 `reloadHeaderLayout(.resetToExpanded)`
- [ ] 实现 `reloadHeaderLayout(.resetToCollapsed)`
- [ ] 将顶部遮挡转换到本地坐标系
- [ ] 将底部遮挡转换到本地坐标系
- [ ] 为 Header 测量结果加入 layout 日志
- [ ] 为 Header frame 变化加入 layout 日志
- [ ] 为 bar frame 变化加入 layout 日志
- [ ] 为 safe area 和 bounds 变化加入 layout 日志
- [ ] 为 managed inset 变化加入 inset 日志
- [ ] 测试 Header automatic、fixed、ranged
- [ ] 测试 Header height clamp
- [ ] 测试 insideSafeArea、extendsUnderTopSafeArea
- [ ] 测试 navigation bar 显隐
- [ ] 测试 tab bar 和 toolbar 底部遮挡
- [ ] 测试 additionalSafeAreaInsets

## v0.3：Scroll Discovery 与 Inset Ownership 版

- [ ] 固化默认 scroll view lookup 文档
- [ ] 实现 managed inset 数据结构
- [ ] 区分 managed inset 和外部 contentInset
- [ ] 设置接管 scroll view 的 `contentInsetAdjustmentBehavior = .never`
- [ ] 实现 child managed contentInset.top
- [ ] 实现 child managed contentInset.bottom
- [ ] 实现 scrollIndicatorInsets.bottom 避让
- [ ] 测试 managed inset 不覆盖外部 contentInset
- [ ] 测试 contentInsetAdjustmentBehavior 策略
- [ ] 测试 fallback page scroll host inset
- [ ] 更新 README 的 scroll 接入说明
- [ ] 更新 `docs/architecture.md` 的 inset ownership 章节
- [ ] 为 managed inset 写入加入 inset 日志
- [ ] 为 managed inset 跳过重复写入加入 inset 日志

## v0.4：Child 生命周期与缓存版

- [ ] 实现 child cache window
- [ ] 默认至少保留 current page
- [ ] 支持配置是否保留相邻 page
- [ ] 卸载 child 前保存 scroll offset snapshot
- [ ] 卸载 child 前保存 managed inset 状态
- [ ] 卸载 child 前保存 appearance 状态
- [ ] reloadData 清理旧 child
- [ ] reloadData 清理旧 offset snapshot
- [ ] reloadData 清理旧 Tabman/Pageboy 状态
- [ ] dataSource 返回负数 page count 时固定策略
- [ ] dataSource 返回重复 viewController 时固定策略
- [ ] 为 cache window 更新加入 children 日志
- [ ] 为 offset snapshot 保存和恢复加入 children 日志
- [ ] 为重复 viewController 降级加入 children 日志
- [ ] 测试 child appearance lifecycle 顺序
- [ ] 测试 child cache window
- [ ] 测试 unload offset snapshot
- [ ] 测试 reloadData 后旧 child 可释放
- [ ] 更新 `docs/architecture.md` 的 child lifecycle 章节

## v0.5：纵向嵌套滚动协调版

- [ ] 创建 `Sources/AnchorPager/Core/AnchorPagerScrollCoordinator.swift`
- [ ] Header 未完全折叠时优先响应向上滚动
- [ ] Header 未完全展开时优先响应向下滚动
- [ ] Header 完全折叠后当前 child scroll view 正常滚动
- [ ] 支持不同 contentSize child 切换
- [ ] 处理 Header 展开阈值附近抖动
- [ ] 处理 Header 折叠阈值附近抖动
- [ ] 处理 child top boundary rubber-band 抖动
- [ ] 实现 guarded contentOffset update
- [ ] 避免 contentSize 变化重复写 managed inset
- [ ] 为 Header 完全展开加入 scroll 日志
- [ ] 为 Header 完全折叠加入 scroll 日志
- [ ] 为 child top boundary 加入 scroll 日志
- [ ] 为 scroll owner 切换加入 scroll 日志
- [ ] 为 guarded contentOffset update 触发或跳过加入 scroll 日志
- [ ] 测试高频滚动路径不逐帧输出普通日志
- [ ] 测试 Header 展开和折叠
- [ ] 测试 child top boundary 抖动
- [ ] 测试不同 contentSize child 切换
- [ ] 测试 guarded update 防重入
- [ ] 测试 contentSize 变化不震荡

## v0.6：顶部 Overscroll 事件处理版

- [ ] 创建 `Sources/AnchorPager/Overscroll/AnchorPagerOverscrollCoordinator.swift`
- [ ] 实现 `.none`
- [ ] 实现 `.container`
- [ ] 实现 `.child`
- [ ] Header 完全展开前优先展开 Header
- [ ] container 模式由 verticalScrollView 处理继续下拉
- [ ] child 模式由当前 child scroll view 或 page scroll host 处理继续下拉
- [ ] 同一次下拉手势只允许一个 top overscroll owner
- [ ] 实现 owner 进入阈值
- [ ] 实现 owner 退出阈值
- [ ] 横向分页期间取消 active overscroll handling
- [ ] Header layout reload 期间取消 active overscroll handling
- [ ] 屏幕旋转期间取消 active overscroll handling
- [ ] child 切换期间取消 active overscroll handling
- [ ] 为 overscroll mode 加入 overscroll 日志
- [ ] 为 owner 进入和退出加入 overscroll 日志
- [ ] 为 owner cancel 加入 overscroll 日志
- [ ] 为阈值判定加入 overscroll 日志
- [ ] 测试三种 overscroll mode
- [ ] 测试 owner 互斥
- [ ] 测试 Header 展开优先级
- [ ] 测试 owner 阈值稳定性

## v0.7：手势与交互状态机版

- [ ] 创建 `Sources/AnchorPager/Gesture/AnchorPagerInteractionState.swift`
- [ ] 创建 `Sources/AnchorPager/Gesture/AnchorPagerGestureCoordinator.swift`
- [ ] 定义 idle
- [ ] 定义 verticalDragging
- [ ] 定义 verticalDecelerating
- [ ] 定义 horizontalPaging
- [ ] 定义 programmaticPaging
- [ ] 定义 topOverscrolling
- [ ] 定义 layoutReloading
- [ ] 定义 transitioningSize
- [ ] 每个状态实现 begin 路径
- [ ] 每个状态实现 update 路径
- [ ] 每个状态实现 finish 路径
- [ ] 每个状态实现 cancel 路径
- [ ] 统一 setSelectedIndex selection commit/cancel
- [ ] 统一分段栏点击 selection commit/cancel
- [ ] 统一横向滑动 selection commit/cancel
- [ ] selectedIndex 只在确认完成后提交
- [ ] 非相邻页面切换使用 source/target 过渡语义
- [ ] 快速连续 setSelectedIndex 不被旧 completion 覆盖
- [ ] reloadData 非 idle 时执行 cancel 或延迟合并
- [ ] reloadHeaderLayout 非 idle 时执行 cancel 或延迟合并
- [ ] 系统返回手势优先级明确
- [ ] child 横向 content scroll 手势优先级明确
- [ ] 为 interaction state begin 加入 gesture 日志
- [ ] 为重要 update 边界加入 gesture 日志
- [ ] 为 finish 和 cancel 加入 gesture 日志
- [ ] 为非法 transition 忽略加入 gesture 日志
- [ ] 测试 paging cancel 不提交 selectedIndex
- [ ] 测试快速连续 setSelectedIndex
- [ ] 测试非相邻页面切换
- [ ] 测试横向分页与纵向拖拽竞争
- [ ] 测试系统返回手势与横向分页手势优先级

## v0.8：状态栏点击与尺寸变化版

- [ ] 实现 scrollsToTop owner manager
- [ ] 任一时刻只允许一个 managed UIScrollView 的 scrollsToTop 为 true
- [ ] 横向 paging scroll view 永不响应 scrollsToTop
- [ ] Header 未完全折叠时 verticalScrollView 响应 scroll-to-top
- [ ] Header 已完全折叠时当前 child scroll view 响应 scroll-to-top
- [ ] 空页时关闭所有 managed scrollsToTop
- [ ] 页面切换后重新计算 scrollsToTop owner
- [ ] reloadData 后重新计算 scrollsToTop owner
- [ ] reloadHeaderLayout 后重新计算 scrollsToTop owner
- [ ] child 加载和卸载后重新计算 scrollsToTop owner
- [ ] viewWillTransition 后重新计算布局
- [ ] viewSafeAreaInsetsDidChange 后重新计算布局
- [ ] viewDidLayoutSubviews 后重新计算布局
- [ ] 尺寸变化后保持 selectedIndex
- [ ] 尺寸变化后尽量保持 Header 折叠进度
- [ ] 尺寸变化后尽量保持当前 child 可见内容位置
- [ ] 为 scrollsToTop owner 变化加入 scroll 日志
- [ ] 为尺寸变化请求加入 layout 日志
- [ ] 为布局延迟合并和 cancel 加入 layout 日志
- [ ] 测试 scrollsToTop 唯一 owner
- [ ] 测试 Header 折叠状态 owner 切换
- [ ] 测试空页关闭 scrollsToTop
- [ ] 测试旋转后 Header、bar、child inset 一致性

## v0.9：可访问性、RTL 与示例矩阵版

- [ ] 分段栏 item 支持 selected accessibility trait
- [ ] 分段栏 item 支持 button accessibility trait
- [ ] 保持 Header、bar、child 的 VoiceOver 顺序
- [ ] 支持 Dynamic Type
- [ ] Dynamic Type 变化后触发布局更新
- [ ] 支持 Reduce Motion
- [ ] Reduce Motion 下非必要动画降级或缩短
- [ ] 支持 LTR
- [ ] 支持 RTL
- [ ] 明确 RTL 下横向分页方向
- [ ] 明确 RTL 下分段栏 indicator 位置
- [ ] 明确 RTL 下非相邻页面过渡方向
- [ ] 示例工程覆盖基础分页
- [ ] 示例工程覆盖不同 contentSize
- [ ] 示例工程覆盖 Header 安全区域模式
- [ ] 示例工程覆盖 Header 动态高度
- [ ] 示例工程覆盖顶部 overscroll
- [ ] 示例工程覆盖屏幕旋转
- [ ] 示例工程覆盖无 UIScrollView child
- [ ] 至少一个 UI test 覆盖 Header 展开优先于顶部 overscroll handling
- [ ] UI 测试失败路径可通过日志 category 定位关键事件

## v1.0：稳定 API 发布版

- [ ] 冻结核心 public API
- [ ] 补齐 public/open API DocC 注释
- [ ] README 覆盖最小接入示例
- [ ] README 覆盖 Header UIView 示例
- [ ] README 覆盖 Header UIViewController 示例
- [ ] README 覆盖显式 anchorPagerScrollView 示例
- [ ] README 覆盖无 UIScrollView child 示例
- [ ] `docs/architecture.md` 覆盖 public API 契约
- [ ] `docs/architecture.md` 覆盖状态机
- [ ] `docs/architecture.md` 覆盖 safe area 策略
- [ ] `docs/architecture.md` 覆盖 scroll view discovery 策略
- [ ] `docs/architecture.md` 覆盖 inset ownership
- [ ] `docs/architecture.md` 覆盖 child lifecycle
- [ ] `docs/architecture.md` 覆盖 gesture priority
- [ ] `docs/architecture.md` 覆盖 known limitations
- [ ] `docs/architecture.md` 覆盖日志策略和 category
- [ ] README 覆盖日志过滤方式
- [ ] 记录 Tabman/Pageboy 已验证版本
- [ ] 清理 internal 状态命名，避免泄漏内部术语
- [ ] 修复 Swift 6 并发警告
- [ ] 清理 KVO 生命周期
- [ ] 清理 Notification 生命周期
- [ ] 清理 gesture delegate 生命周期
- [ ] 清理 display link 生命周期
- [ ] 清理 Task 生命周期
- [ ] 清理 closure callback 生命周期
- [ ] 检查 child store、adapter、coordinator 不形成 retain cycle
- [ ] 审查日志 category 和消息格式
- [ ] 审查日志隐私策略
- [ ] 确认没有散落 `print`
- [ ] 确认没有绕过日志门面的直接日志输出
- [ ] `git diff --check` 通过
- [ ] `swift package resolve` 通过
- [ ] `xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=<available simulator>' test` 通过
- [ ] `xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build` 通过
- [ ] public API 不暴露第三方类型
- [ ] 关键事件均有日志或明确无需日志说明
- [ ] 发布说明记录当前能力和限制

## v1.1+：增强与维护版

- [ ] 建立滚动性能 profiling 流程
- [ ] 优化滚动帧率
- [ ] 增加更多 child 缓存策略
- [ ] 增加领域无关的 bar 样式配置
- [ ] 细化动画降级策略
- [ ] 增加更多 UI tests
- [ ] 增加真实设备验证
- [ ] 验证 Tabman 新版本兼容性
- [ ] 验证 Pageboy 新版本兼容性
- [ ] 根据真实项目接入反馈修复边界问题
- [ ] 如需破坏性 API 变更，进入 v2.0 设计流程

## 当前执行入口

- [ ] 以 v0.1 可视分页核心版作为首个实现版本
- [ ] 实现前创建 v0.1 详细实现计划
- [ ] 实现时遵循测试先行
- [ ] 每个任务完成后运行对应测试
- [ ] 每个任务完成时确认是否需要 UI 测试
- [ ] 需要 UI 测试的任务必须在同一任务内完成 UI 测试
- [ ] 不允许把当前任务应有的测试推迟到后续任务
- [ ] 每个任务完成时确认是否需要日志
- [ ] 需要日志的任务必须在同一任务内完成日志和日志测试
- [ ] 每个版本完成后更新本文档状态
