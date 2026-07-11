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
- [ ] 横向 page 的实际 UIKit containment 由 Tabman/Pageboy adapter 执行，AnchorPager 不对同一 page view controller 重复 `addChild`
- [ ] Public API 不暴露第三方库类型
- [ ] Public API、data source、delegate、coordinator 状态更新保持 `@MainActor`
- [ ] 只有直接操作 UIKit 状态或维护 UI lifecycle/coordinator 状态的内部类型整体使用 `@MainActor`
- [ ] 非 UI 基础设施不因方便整体限制主线程，必要时使用 `nonisolated`、task-local 或真实同步机制表达隔离
- [ ] 不复制参考项目源码、public API 或命名
- [ ] 不引入具体业务场景、内容类型、数据模型或场景命名
- [ ] 新增功能、修改重要逻辑或修复问题前先梳理影响范围
- [ ] 变更影响评估覆盖 public API、内部分层、UIKit containment、child lifecycle、scroll discovery、inset ownership、paging adapter、gesture/overscroll、日志、测试、示例工程和文档
- [ ] 修复问题或编写新功能前全面梳理数据流、状态所有权、约束或回调关系、相邻版本职责、回归路径和文档契约，未完成梳理不写实现代码
- [ ] 发现实现真实职责与文档、计划或架构假设不一致时，及时提醒用户并同步更新对应文档
- [ ] 发现设计或架构存在职责闭环、所有权冲突、跨层泄漏、状态语义矛盾或阻碍后续扩展时立即停止局部实现并提醒用户，先更新设计、架构或计划文档，不在错误设计上追加补丁
- [ ] 设计兼顾后续版本扩展，不为当前单点修复破坏架构边界、状态语义或未来版本路线
- [ ] 影响跨模块契约、线程/actor 隔离、生命周期或用户可见行为的变更先更新设计说明或计划文档
- [ ] 不使用 `Task.detached` 绕过 actor 隔离
- [ ] 不使用 `@unchecked Sendable`、`nonisolated(unsafe)`、`@preconcurrency` 粗暴压制并发问题
- [ ] 每个重要行为都有对应测试
- [ ] 每完成一个实现任务都同步提交对应测试
- [ ] 触达用户可见 UI、UIKit 生命周期、手势、滚动、分页或系统交互的任务包含必要 UI 测试
- [ ] 无法稳定使用 UI 测试覆盖的 UI 行为写明原因，并提供替代自动化验证
- [ ] 每个任务验收记录实际运行过的测试命令和结果
- [ ] 每完成一个实现任务或重要修复后先做代码自审，并记录自审结论
- [ ] 必要事件通过统一内部日志门面记录
- [ ] 日志使用 `os.Logger`，不在框架库中散落 `print`
- [ ] 高频滚动路径不逐帧输出普通日志
- [ ] 日志不得输出业务数据、用户内容或可能包含隐私的数据
- [ ] 新增关键日志事件时同步提交日志测试
- [ ] 每个版本完成前运行 `git diff --check`

## v0.1：可视分页核心版

目标：先交付真实可见的 Header、分段栏和多页面横向分页路径。

### 工程与依赖

- [x] 创建 `Package.swift`
- [x] 配置 iOS 14+ platform
- [x] 配置 Swift 6 language mode
- [x] 添加 Tabman 依赖，版本从 `4.0.1` 开始
- [x] 确认 Pageboy 解析到 `5.0.2`
- [x] 创建 `Sources/AnchorPager/`
- [x] 创建 `Tests/AnchorPagerTests/`
- [x] 创建 `Examples/AnchorPagerExample/`
- [x] 创建 `README.md`
- [x] 创建 `docs/architecture.md`

### 日志基础设施

- [x] 创建 `Sources/AnchorPager/Logging/AnchorPagerLogger.swift`
- [x] 使用 `os.Logger` 作为日志底层
- [x] 定义 subsystem：`com.anchorpager.AnchorPager`
- [x] 定义 lifecycle category
- [x] 定义 layout category
- [x] 定义 header category
- [x] 定义 paging category
- [x] 定义 children category
- [x] 定义 scroll category
- [x] 定义 inset category
- [x] 定义 overscroll category
- [x] 定义 gesture category
- [x] 定义 accessibility category
- [x] 定义 resource category
- [x] 提供内部可注入 log sink 以便测试
- [x] `AnchorPagerLogger.log` 支持非主线程调用
- [x] 测试非主线程日志会将 sink 事件投递回 MainActor
- [x] 测试日志 category 和 level 记录
- [x] 测试日志不依赖人工查看控制台

### Public API Skeleton

- [x] 创建 `Sources/AnchorPager/Public/AnchorPagerViewController.swift`
- [x] 实现 `AnchorPagerViewController`
- [x] 暴露 `dataSource`
- [x] 暴露 `delegate`
- [x] 暴露 `configuration`
- [x] 暴露只读 `selectedIndex`
- [x] 暴露只读 `effectiveSelectedIndex`
- [x] 暴露 `verticalScrollView`
- [x] 实现 `init(configuration:)`
- [x] 实现 `reloadData()`
- [x] 实现 `setSelectedIndex(_:animated:)`
- [x] 实现 `reloadHeaderLayout(offsetAdjustment:)`
- [x] 为 init 和 deinit 加入 lifecycle 日志
- [x] 为 reloadData begin/end 加入 lifecycle 日志
- [x] 为 setSelectedIndex 请求、越界 no-op 和 commit 加入 paging 日志
- [x] 创建 `AnchorPagerViewControllerDataSource`
- [x] 创建 `AnchorPagerViewControllerDelegate`
- [x] 创建 `AnchorPagerHeaderContent`
- [x] 创建 `AnchorPagerConfiguration`
- [x] 创建 `AnchorPagerHeaderConfiguration`
- [x] 创建 `AnchorPagerBarConfiguration`
- [x] 创建 `AnchorPagerPagingConfiguration`
- [x] 创建 `AnchorPagerHeaderHeightMode`
- [x] 创建 `AnchorPagerHeaderTopBehavior`
- [x] 创建 `AnchorPagerHeaderOffsetAdjustment`
- [x] 创建 `AnchorPagerTopOverscrollHandlingMode`
- [x] 创建 `AnchorPagerLayoutContext`
- [x] 为 public/open API 添加简洁 DocC 注释

### Header 基础承载

- [x] 创建 `Sources/AnchorPager/Header/AnchorPagerHeaderViewHost.swift`
- [x] 支持 `AnchorPagerHeaderContent.view`
- [x] 支持 `AnchorPagerHeaderContent.viewController`
- [x] Header viewController 使用标准 `addChild`、添加 view、`didMove(toParent:)`
- [x] Header viewController 移除时使用 `willMove(toParent: nil)`、移除 view、`removeFromParent`
- [x] 提供基础 Header 高度测量
- [x] 默认 Header height mode 为 automatic，min 为 0，max 为 nil
- [x] 默认 Header top behavior 为 insideSafeArea
- [x] 为 Header view 承载加入 header 日志
- [x] 为 Header viewController add/remove 加入 header 和 lifecycle 日志
- [x] 为 Header 基础测量结果加入 layout 日志
- [x] 重复安装同一个 Header view 时保持幂等，不触发 remove/re-add
- [x] 重复安装同一个 Header viewController 时保持幂等，不重复 UIKit containment

### Tabman/Pageboy Adapter

- [x] 创建 `Sources/AnchorPager/Paging/AnchorPagerPagingAdapter.swift`
- [x] 创建 `Sources/AnchorPager/Paging/AnchorPagerTabBarAdapter.swift`
- [x] 在 adapter 内部接入 Tabman
- [x] 在 adapter 内部接入 Pageboy
- [x] 支持标题数据传入分段栏
- [x] 支持 child view controller 数据传入分页容器
- [x] 支持分段栏点击切页
- [x] 支持横向滑动切页
- [x] 支持 `setSelectedIndex(_:animated:)` 驱动切页
- [x] 收敛 Tabman/Pageboy page change 事件
- [x] 可见状态下 `setSelectedIndex` 只在 adapter 确认完成后提交 public `selectedIndex`
- [x] 分页取消或回弹不通知 public selection delegate
- [x] adapter 拒绝新程序化请求时保留已接受的上一笔 pending selection
- [x] 禁用或绕开 Tabman 自动 child inset
- [x] 确保横向 paging scroll view 不暴露到 public API
- [x] 为分页开始、完成、取消加入 paging 日志
- [x] 为 Tabman/Pageboy 回调缺失、重复或乱序加入 paging 日志

### v0.1 稳定化收尾

- [x] `reloadHeaderLayout()` 执行基础 Header 重新测量
- [x] `reloadHeaderLayout()` 发送基础 `AnchorPagerLayoutContext`
- [x] 文档说明 v0.1 不对忙碌状态下被拒绝的程序化切页做请求排队
- [x] 文档说明 v0.1 `reloadData()` 仍会提前加载 child view 以执行 scroll discovery
- [x] 文档说明 `topOverscrollHandlingMode`、`header.topBehavior`、`paging.keepsAdjacentPagesLoaded` 等后续版本配置项当前只保留 skeleton/default
- [x] 本轮稳定化改动已完成代码自审，重点检查 selection 事务、Tabman/Pageboy 边界、Header containment 幂等、并发隔离、日志和测试覆盖

### Child 基础管理

- [x] 创建 `Sources/AnchorPager/Children/AnchorPagerChildViewControllerStore.swift`
- [x] 首次加载 child 时执行 `addChild`
- [x] 首次加载 child 时添加 child view
- [x] 首次加载 child 时执行 `didMove(toParent:)`
- [x] reloadData 时清理旧 child
- [x] 空页时 `selectedIndex` 对外保持 0
- [x] 空页时 `effectiveSelectedIndex` 为 nil
- [x] setSelectedIndex 越界时 no-op
- [x] Debug 下 setSelectedIndex 越界触发 assertionFailure
- [x] 为 child add/remove 加入 children 日志
- [x] 为 reloadData 清理旧 child 加入 children 日志

说明：v0.1 的 `AnchorPagerChildViewControllerStore` 是独立基础 containment 工具；横向 page 的实际 containment 由 Tabman/Pageboy adapter 执行。后续 v0.4 应将该工具重定位或替换为 page state store，不能对同一 page view controller 形成双重 containment。

### Scroll View Discovery

- [x] 创建 `Sources/AnchorPager/Public/UIViewController+AnchorPager.swift`
- [x] 使用 associated object 存储显式 `anchorPagerScrollView`
- [x] 使用 associated object 存储 `anchorPagerUsesDefaultScrollViewLookup`
- [x] 默认启用 `anchorPagerUsesDefaultScrollViewLookup`
- [x] 实现只读计算属性 `anchorPagerDefaultScrollView`
- [x] 默认查找使用确定性深度优先策略
- [x] 默认查找忽略 hidden UIScrollView
- [x] 默认查找忽略 alpha 接近 0 的 UIScrollView
- [x] 默认查找忽略 `isUserInteractionEnabled == false` 的 UIScrollView
- [x] 多个候选时选择第一个符合规则的 UIScrollView
- [x] 不跨 child view controller 边界查找
- [x] 无候选 UIScrollView 时使用内部 page scroll host
- [x] 为显式 scroll view 命中加入 scroll 日志
- [x] 为默认 lookup 命中加入 scroll 日志
- [x] 为 fallback page scroll host 加入 scroll 日志

### 文档与示例

- [x] README 写入最小接入示例
- [x] README 写入 Header UIView 示例
- [x] README 写入 Header UIViewController 示例
- [x] README 写入显式 `anchorPagerScrollView` 示例
- [x] README 写入无 UIScrollView child 示例
- [x] `docs/architecture.md` 说明 public API 契约
- [x] `docs/architecture.md` 说明 Tabman/Pageboy adapter 边界
- [x] `docs/architecture.md` 说明默认 scroll view lookup 规则
- [x] `docs/architecture.md` 记录 Tabman/Pageboy 验证版本
- [x] `docs/architecture.md` 说明日志策略、category、过滤方式和性能注意事项
- [x] README 说明如何查看和过滤 AnchorPager 日志
- [x] 示例工程显示 Header、分段栏和多个页面
- [x] 示例工程支持点击分段栏切页
- [x] 示例工程支持横向滑动切页

### v0.1 测试

- [x] Public API 编译测试
- [x] selectedIndex 空页测试
- [x] effectiveSelectedIndex 空页测试
- [x] setSelectedIndex 越界 no-op 测试
- [x] reloadData 后 selectedIndex clamp 测试
- [x] Header UIView 基础承载测试
- [x] Header UIViewController containment 测试
- [x] Header UIView 重复安装幂等测试
- [x] Header UIViewController 重复安装不重复 containment 测试
- [x] 显式 `anchorPagerScrollView` 优先测试
- [x] 默认 scroll view lookup 测试
- [x] 多个 UIScrollView 选择顺序测试
- [x] hidden、alpha、userInteractionEnabled 过滤测试
- [x] 关闭默认查找测试
- [x] 无 UIScrollView child fallback host 测试
- [x] 不跨 child view controller 边界查找测试
- [x] 基础 child add/remove containment 测试
- [x] Tabman/Pageboy 类型不泄漏 public API 检查
- [x] 日志门面单测
- [x] reloadData 日志测试
- [x] Header 承载日志测试
- [x] child add/remove 日志测试
- [x] 分页切换日志测试
- [x] 程序化切页确认后提交测试
- [x] 程序化切页取消不通知 delegate 测试
- [x] adapter 拒绝第二次切页时保留首次 pending selection 测试
- [x] `reloadHeaderLayout()` 基础 layout context 回调测试
- [x] fallback host 日志测试
- [x] `AnchorPagerAssertions` 非 MainActor 调用测试
- [x] 示例工程基础启动 UI test
- [x] 示例工程 Header、分段栏和页面内容 UI test
- [x] 示例工程分段栏点击切页 UI test
- [x] 示例工程横向滑动切页 UI test
- [x] 示例工程 public API 切页 UI test

### v0.1 验收

- [x] `swift package resolve` 通过
- [x] Package 单测通过
- [x] iOS Simulator 测试目标编译通过
- [x] 示例工程可构建
- [x] 示例工程可显示 Header、分段栏和多个页面
- [x] 点击、横滑、API 三种切页方式可用
- [x] v0.1 关键事件日志测试通过
- [x] `git diff --check` 通过

## v0.2：Header 与布局稳定版

- [x] 创建 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md` 详细实施计划
- [x] 创建 `Sources/AnchorPager/Layout/AnchorPagerLayoutEngine.swift`
- [x] 实现 automatic height 测量
- [x] 实现 fixed height clamp
- [x] 实现 ranged height clamp
- [x] 实现 insideSafeArea 布局
- [x] 实现 extendsUnderTopSafeArea 布局
- [x] `extendsUnderTopSafeArea` 下 Header frame 高度等于顶部遮挡加可见纯内容高度，并保持 `barFrame.minY == headerFrame.maxY`
- [x] 两种 Header top behavior 保持相同分段栏和 child 内容基线
- [x] Header height mode 与可折叠距离只表示纯内容高度，不包含顶部遮挡
- [x] automatic/ranged Header 在顶部遮挡下方的中立几何中测量，避免 safe area/layout margins 污染
- [x] 实现 Header runtime frame 变化
- [x] 实现 `reloadHeaderLayout(.preserveVisualPosition)`
- [x] 实现 `reloadHeaderLayout(.preserveCollapseProgress)`
- [x] 实现 `reloadHeaderLayout(.resetToExpanded)`
- [x] 实现 `reloadHeaderLayout(.resetToCollapsed)`
- [x] 将顶部遮挡转换到本地坐标系
- [x] 将底部遮挡转换到本地坐标系
- [x] 横向分页区域默认延伸到容器 `bounds` 底部，底部遮挡只进入 managed inset target
- [x] 禁用 AnchorPager 自有主容器 `verticalScrollView` 自动 content inset，避免 Header 顶部遮挡重复叠加
- [x] 禁用无滚动页 fallback scroll host 自动 content inset，避免 plain child 底部停在安全区域上方
- [x] 示例工程导航栏支持切换 `AnchorPagerHeaderTopBehavior`、显示当前配置，并使用 `.preserveVisualPosition` 刷新布局
- [x] 主容器使用独立 `scrollRangeView` 固定 content range，滚动范围不依赖当前 `contentOffset`
- [x] Header 和 paging adapter 位于 `frameLayoutGuide` viewport，不参与 `contentSize` 反算
- [x] 负主容器 offset 通过 viewport presentation translation 恢复 Header、分段栏和页面的可见 UIKit bounce
- [x] bounce 期间 layout context 使用实际可见坐标，canonical output 不受 presentation translation 污染
- [x] 主容器内部 delegate proxy 驱动 Header/bar 可见几何和 collapse progress，且不扩大 Public API
- [x] 滚动热路径复用 Header 测量结果，不重复测量或逐帧输出普通布局日志
- [x] 测试顶部行为双向切换并下拉回弹后 Header 高度和分段栏基线恢复
- [x] 为 Header 测量结果加入 layout 日志
- [x] 为 Header frame 变化加入 layout 日志
- [x] 为 bar frame 变化加入 layout 日志
- [x] 为 safe area 和 bounds 变化加入 layout 日志
- [x] 为 managed inset 变化加入 inset 日志
- [x] 测试 Header automatic、fixed、ranged
- [x] 测试 Header height clamp
- [x] 测试 insideSafeArea、extendsUnderTopSafeArea
- [x] 测试 navigation bar 显隐
- [x] 测试 navigation controller 下 Header 实际 frame 与 layout context 对齐
- [x] 测试 tab bar 和 toolbar 底部遮挡
- [x] 测试无滚动页 fallback host 底部延伸到 content frame 底部
- [x] 测试示例工程 `AnchorPagerHeaderTopBehavior` 菜单显示、切换和 `extendsUnderTopSafeArea` 顶部遮挡覆盖
- [x] 示例 Header 标题栈上下约束到 `safeAreaLayoutGuide`，两种顶部行为下保持 20 pt 内容间距
- [x] 示例 Header 文本组顶部对齐，标题与副标题保持固定 8 pt 间距且负 offset 不拉伸 label
- [x] 测试 additionalSafeAreaInsets

## v0.3：Scroll Discovery 与 Inset Ownership 版

- [x] 创建 `docs/superpowers/specs/2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md`，固定 v0.3–v0.5 几何、inset 和 owner 边界
- [x] 创建 v0.3 详细实施计划：`docs/superpowers/plans/2026-07-11-v0-3-fixed-paging-inset-ownership.md`
- [x] 固化默认 scroll view lookup 文档
- [x] 将 `AnchorPagerBarConfiguration.height` 改为 optional，默认 nil
- [x] nil 高度使用 Tabman bar 自适应布局，显式高度约束实际 bar
- [x] Paging adapter 在布局后通过 public `barInsets` 回报实际 bar obstruction
- [x] Tabman adapter 使用 collapsed-state fixed height，滚动热路径只移动 top
- [x] 测试 Header 折叠期间 adapter height 和 Pageboy child bounds 不变
- [x] 实现 managed inset 数据结构
- [x] 区分 managed inset 和外部 contentInset
- [x] 设置接管 scroll view 的 `contentInsetAdjustmentBehavior = .never`
- [x] ownership 结束时移除最后一次 managed inset 并恢复原始 adjustment behavior
- [x] 实现 child managed contentInset.top
- [x] 实现 child managed contentInset.bottom
- [x] 实现 scrollIndicatorInsets.bottom 避让
- [x] bar 高度变化时按 child distance-from-top 保持可见内容
- [x] 测试 managed inset 不覆盖外部 contentInset
- [x] 测试 contentInsetAdjustmentBehavior 策略
- [x] 测试 fallback page scroll host inset
- [x] 测试 optional bar height、自适应 barInsets 和显式高度
- [x] 测试 ownership 归还、重复 target 跳过和 scroll target 冲突降级
- [x] 示例工程真实列表页和 fallback 页 UI test
- [x] 更新 README 的 scroll 接入说明
- [x] 更新 `docs/architecture.md` 的 inset ownership 章节
- [x] 为 managed inset 写入加入 inset 日志
- [x] 为 managed inset 跳过重复写入加入 inset 日志

## v0.4：Child 生命周期与缓存版

- [ ] 实现 page state store
- [ ] 重定位或替换 `AnchorPagerChildViewControllerStore`，避免与 Tabman/Pageboy 双重 containment
- [ ] 实现 child cache window
- [ ] 默认至少保留 current page
- [ ] 支持配置是否保留相邻 page
- [ ] 卸载 child 前保存 scroll offset snapshot
- [ ] 卸载 child 前保存 managed inset 状态
- [ ] 卸载 child 前保存 appearance 状态
- [ ] reloadData 清理旧 page state 和旧 fallback host content
- [ ] reloadData 清理旧 offset snapshot
- [ ] reloadData 清理旧 Tabman/Pageboy 状态
- [ ] dataSource 返回负数 page count 时固定策略
- [ ] dataSource 返回重复 viewController 时固定策略
- [ ] 为 cache window 更新加入 children 日志
- [ ] 为 offset snapshot 保存和恢复加入 children 日志
- [ ] 为重复 viewController 降级加入 children 日志
- [ ] 测试 Tabman 驱动的 child appearance lifecycle 顺序
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
- [ ] 当前 container 与当前 child 支持受限纵向 simultaneous recognition
- [ ] 同一 pan 在 container/child 边界转移剩余 delta
- [ ] container 未完全折叠时当前 child 保持顶部
- [ ] child 离开顶部时 container 保持完全折叠
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
- [ ] 测试向上和向下 handoff 不丢失剩余 delta
- [ ] 测试 Header 折叠热路径不改变 Pageboy child bounds
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

- [ ] 复用 v0.5 已建立的 current container/current child 最小纵向 simultaneous recognition，不重复建立第二套纵向 handoff
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

- [x] v0.1 可视分页核心版已完成，验收记录见 `docs/superpowers/plans/2026-07-09-v0-1-foundation.md`
- [x] v0.2 Header 与布局稳定版已创建详细实施计划：`docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 Task 1：LayoutEngine 纯计算契约已完成，验证记录见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 Task 2：Header 测量边界补齐已完成，验证记录见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 Task 3：ViewController 布局引擎接入已完成，验证记录见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 Task 4：Safe Area 与本地遮挡集成已完成，验证记录见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 Task 5：v0.2 布局与 inset 日志已完成，验证记录见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 Task 6：文档、任务状态与版本验收已完成，验证记录见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 follow-up：主容器自动 content inset 已禁用，修复 navigation bar 下 Header 与 layout context 顶部位置不一致的问题；验证记录见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 follow-up：内部 fallback scroll host 自动 content inset 已禁用，修复无滚动页底部没有延伸到 content frame 底部的问题；验证记录见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 follow-up：示例工程已新增 `AnchorPagerHeaderTopBehavior` 菜单，可显示并切换当前 Header 顶部行为配置，且切换时使用 `.preserveVisualPosition` 刷新布局；验证记录见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 历史 follow-up（已被主容器架构修订取代）：曾在 Header host 写入 scroll content 约束前补偿 `contentOffset.y`；该方案后来确认会形成 offset/constraint/contentSize 反馈闭环，现已移除且不得恢复；历史验证见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 follow-up：`extendsUnderTopSafeArea` 下 Header 可视 frame 高度至少覆盖本地顶部遮挡，修复当前 Header 内容高度小于顶部遮挡时 Header 与分段栏之间出现空隙的问题；验证记录见 `docs/superpowers/plans/2026-07-09-v0-2-header-layout.md`
- [x] v0.2 follow-up：主容器 scroll range 与 Header/paging viewport 已解耦，移除 `visibleY + contentOffset` 约束反馈闭环，修复顶部行为切换后下拉回弹残留空白；验证记录见 `docs/superpowers/plans/2026-07-10-header-scroll-viewport.md`
- [x] v0.2 follow-up：保留 Header 双顶部行为并统一分段栏基线；automatic Header 使用中立测量，负 offset 使用 viewport presentation translation，修复视觉 bounce 消失和回弹后高度增长；验证记录见 `docs/superpowers/plans/2026-07-11-dual-header-top-behavior-bounce-stability.md`
- [x] v0.2 follow-up：示例 Header 蓝色背景保持顶部行为语义，标题栈上下改用 safe area 并保留 20 pt 间距；验证记录见 `docs/superpowers/plans/2026-07-11-example-header-safe-area-content.md`
- [x] v0.2 follow-up：示例 Header 标题栈 bottom 改为 safe area 上限约束，文本组顶部对齐并在下拉中保持固定 8 pt 间距；验证记录见 `docs/superpowers/plans/2026-07-11-example-header-safe-area-content.md`
- [x] v0.2 Header 与布局稳定版已完成；后续从 v0.3 Scroll Discovery 与 Inset Ownership 版继续
- [x] v0.3–v0.5 固定分页视口、optional bar height、inset ownership 和纵向 owner 架构已确认；设计见 `docs/superpowers/specs/2026-07-11-fixed-paging-viewport-inset-scroll-ownership-design.md`
- [x] 实现时遵循测试先行
- [x] 每个任务完成后运行对应测试
- [x] 每个任务完成时确认是否需要 UI 测试
- [x] v0.2 系统 bar 几何行为使用同进程 UIKit 集成测试作为 UI test 替代验证，原因和范围记录在 v0.2 plan
- [x] 不允许把当前任务应有的测试推迟到后续任务
- [x] 每个任务完成时确认是否需要日志
- [x] 需要日志的任务必须在同一任务内完成日志和日志测试
- [x] 每个版本完成后更新本文档状态
