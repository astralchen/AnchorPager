# AnchorPager 需求文档

## 1. 项目目标

AnchorPager 是一个全新的独立 UIKit 容器框架，用于实现可变 Header、吸顶分段栏、多页面横向分页、纵向嵌套滚动和顶部 overscroll 事件处理。

框架必须从零开发，与任何现有项目没有关系。不得迁移、引用、复用或沿用任何旧项目代码、API、目录结构、文档或测试。

## 2. 基础信息

1. Package name：`AnchorPager`
2. Library product：`AnchorPager`
3. Module name：`AnchorPager`
4. Minimum OS：iOS 14
5. Language：Swift 6
6. UI stack：UIKit
7. Package manager：Swift Package Manager
8. Horizontal paging：Tabman + Pageboy
9. Vertical nested scrolling model：参考 JXPagingView + JXSegmentedView 的设计思路
10. 核心框架保持领域无关，不包含具体应用场景、内容类型、数据模型或场景命名

## 3. 参考项目

1. JXPagingView：https://github.com/pujiaxin33/JXPagingView
2. JXSegmentedView：https://github.com/pujiaxin33/JXSegmentedView
3. Tabman：https://github.com/uias/Tabman
4. Pageboy：https://github.com/uias/Pageboy

参考项目只用于理解设计思想。AnchorPager 不复制源码、public API 或命名。

## 4. 总体原则

1. Public API 命名参考 UIKit，避免过度自造术语。
2. 第三方库类型不得泄漏到 AnchorPager public API。
3. Tabman 和 Pageboy 只允许出现在 adapter/internal 层。
4. Tabman 和 Pageboy 负责横向分页、页面切换事件、分段栏和 indicator 渲染。
5. AnchorPager 负责 Header 布局、吸顶、纵向滚动协调、child scroll inset、顶部 overscroll 事件处理、状态栏点击顶滚和 UIKit containment。
6. 必须禁用或绕开 Tabman 自动 child inset，避免与 AnchorPager 的 Header/分段栏预留空间管理冲突。
7. 内部状态机词如 pin anchor、owner、handoff 不得暴露到 public API。
8. 必须锁定 Tabman/Pageboy 的最低可用版本，并在 `docs/architecture.md` 记录验证过的版本。
9. 如果 Tabman/Pageboy API 限制影响设计，优先调整 internal adapter，不扩大 public API。

## 5. Public API 要求

核心入口为 `AnchorPagerViewController`：

```swift
@MainActor
open class AnchorPagerViewController: UIViewController {
    public weak var dataSource: AnchorPagerViewControllerDataSource?
    public weak var delegate: AnchorPagerViewControllerDelegate?

    public var configuration: AnchorPagerConfiguration

    public private(set) var selectedIndex: Int { get }
    public var effectiveSelectedIndex: Int? { get }

    public var verticalScrollView: UIScrollView { get }

    public init(configuration: AnchorPagerConfiguration = .default)

    public func reloadData()
    public func setSelectedIndex(_ selectedIndex: Int, animated: Bool)
    public func reloadHeaderLayout(offsetAdjustment: AnchorPagerHeaderOffsetAdjustment = .preserveVisualPosition)
}
```

数据源协议：

```swift
@MainActor
public protocol AnchorPagerViewControllerDataSource: AnyObject {
    func numberOfViewControllers(in pagerViewController: AnchorPagerViewController) -> Int

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        titleForViewControllerAt index: Int
    ) -> String

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        viewControllerAt index: Int
    ) -> UIViewController

    func headerContent(in pagerViewController: AnchorPagerViewController) -> AnchorPagerHeaderContent
}
```

代理协议：

```swift
@MainActor
public protocol AnchorPagerViewControllerDelegate: AnyObject {
    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didSelectViewControllerAt index: Int
    )

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateHeaderCollapseProgress progress: CGFloat
    )

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateLayout context: AnchorPagerLayoutContext
    )
}
```

Header 内容：

```swift
@MainActor
public enum AnchorPagerHeaderContent {
    case view(UIView)
    case viewController(UIViewController)
}
```

配置类型：

```swift
public struct AnchorPagerConfiguration: Sendable, Equatable {
    public var header: AnchorPagerHeaderConfiguration
    public var bar: AnchorPagerBarConfiguration
    public var paging: AnchorPagerPagingConfiguration
    public var topOverscrollHandlingMode: AnchorPagerTopOverscrollHandlingMode
}

public struct AnchorPagerHeaderConfiguration: Sendable, Equatable {
    public var heightMode: AnchorPagerHeaderHeightMode
    public var topBehavior: AnchorPagerHeaderTopBehavior
}
```

Header 高度模式：

```swift
public enum AnchorPagerHeaderHeightMode: Sendable, Equatable {
    case automatic(min: CGFloat, max: CGFloat?)
    case fixed(max: CGFloat, min: CGFloat)
    case ranged(min: CGFloat, max: CGFloat)
}
```

Header 顶部行为：

```swift
public enum AnchorPagerHeaderTopBehavior: Sendable, Equatable {
    case insideSafeArea
    case extendsUnderTopSafeArea
}
```

Header offset adjustment：

```swift
public enum AnchorPagerHeaderOffsetAdjustment: Sendable, Equatable {
    case preserveVisualPosition
    case preserveCollapseProgress
    case resetToExpanded
    case resetToCollapsed
}
```

顶部 overscroll 模式：

```swift
public enum AnchorPagerTopOverscrollHandlingMode: Sendable, Equatable {
    case none
    case container
    case child
}
```

## 6. UIViewController Scroll 接入要求

通过 UIViewController extension 提供 scroll view 接入点：

```swift
@MainActor
extension UIViewController {
    public var anchorPagerScrollView: UIScrollView? { get set }
    public var anchorPagerUsesDefaultScrollViewLookup: Bool { get set }
    public var anchorPagerDefaultScrollView: UIScrollView? { get }
}
```

要求：

1. 每个 UIViewController 默认都可以作为 AnchorPager child。
2. 显式设置的 scroll view 优先级最高。
3. 未显式设置时，默认实现按确定性规则在 view 层级查找 UIScrollView。
4. 如果最终没有 scroll view，则 AnchorPager 使用内部 page scroll host 承载 child.view。
5. extension 属性通过 associated object 存储显式设置值。
6. `anchorPagerDefaultScrollView` 是只读计算属性，不缓存失效 view 引用。
7. 默认查找必须确定性，建议深度优先，并在 `docs/architecture.md` 固定。
8. 默认查找忽略 hidden、alpha 接近 0、非 userInteractionEnabled 的 UIScrollView。
9. 多个候选时只选第一个符合规则的候选，不做领域推断。
10. 不跨 child view controller 边界查找。
11. 必须支持关闭默认查找。

## 7. Header 要求

1. Header content 支持 UIView 和 UIViewController。
2. Header 使用 UIViewController 时，必须通过标准 UIKit containment 管理。
3. Header 默认显示在安全区域内。
4. Header 默认使用 automatic height，最小高度为 0，不设置固定最大高度。
5. automatic 高度根据 Header 内容测量结果决定。
6. Header 是 UIView 时，默认使用 Auto Layout fitting size、当前 bounds 或 intrinsicContentSize 计算高度。
7. Header 是 UIViewController 时，默认使用其 view 的 Auto Layout fitting size 或 preferredContentSize 作为测量来源。
8. Header heightMode 必须支持 automatic、fixed、ranged 三种模式。
9. insideSafeArea 模式下，Header 顶部从 navigation bar bottom 或 safeArea.top 开始。
10. extendsUnderTopSafeArea 模式下，Header 可从容器 view 顶部开始绘制。
11. 沉浸式 Header 只影响 Header 视觉 frame，不改变分段栏吸顶基线和 child 内容安全区域。
12. Header frame 和 height 可以运行时变化。
13. `reloadHeaderLayout` 必须支持重新测量、重新布局，并按 offsetAdjustment 保持视觉状态。
14. Header 视觉迁移不能反复 add/remove header view controller。

## 8. 安全区域要求

1. 必须适配 safe area、navigation bar、tab bar、toolbar、additionalSafeAreaInsets 和容器嵌套场景。
2. 布局计算不能假设 AnchorPagerViewController 是 window root。
3. 可见顶部和底部遮挡必须转换到 AnchorPagerViewController.view 本地坐标系后参与布局。
4. 分段栏吸顶基线必须基于当前可见顶部遮挡计算，不固定使用 view.safeAreaInsets.top。
5. child managed contentInset.top 表达 Header + 分段栏预留空间。
6. child managed contentInset.bottom 和 scrollIndicatorInsets.bottom 避让底部 safe area、tab bar、toolbar 或其他可见底部遮挡。
7. 框架必须区分自身 managed inset 和外部追加 inset，不覆盖调用方已有额外 contentInset。
8. 框架接管的 scroll view 建议设置 `contentInsetAdjustmentBehavior = .never`，并在文档说明。
9. safe area、bar 显隐、横竖屏、Split View、Stage Manager 尺寸变化后必须重新计算布局，并尽量保持 selectedIndex、Header 折叠进度和当前 child 可见位置。

## 9. Child 生命周期与缓存要求

1. AnchorPagerViewController 是 child containment 和 appearance lifecycle 的唯一管理者。
2. child 首次加载必须执行 addChild、添加 view、didMove(toParent:)。
3. child 卸载必须执行 willMove(toParent: nil)、移除 view、removeFromParent。
4. 横向分页切换、懒加载、卸载、reloadData、setSelectedIndex 都不能破坏生命周期语义。
5. page 切换必须正确转发 viewWillAppear、viewDidAppear、viewWillDisappear、viewDidDisappear。
6. 必须定义 child view controller 缓存窗口，默认至少保留 current page，可选择保留相邻 page。
7. 卸载 child 前必须保存 scroll offset、managed inset 状态和 appearance 状态。
8. reloadData 必须清理旧 child、旧 offset snapshot 和旧 Tabman/Pageboy 状态。
9. Tabman/Pageboy 事件必须通过 adapter 收敛后再驱动 child lifecycle。
10. 测试必须覆盖生命周期事件顺序和 reloadData 后旧 child 可释放。

## 10. API Contract 要求

1. dataSource 返回 page count 小于 0 时按 0 处理或触发 assertion，策略必须固定。
2. setSelectedIndex 越界时为 no-op，并在 Debug 下 assertionFailure。
3. reloadData 后 selectedIndex 越界时应 clamp 到有效范围；无页面时 effectiveSelectedIndex 为 nil。
4. 空页时 selectedIndex 对外保持 0，effectiveSelectedIndex 为 nil。
5. dataSource 返回重复 viewController 时必须有明确处理策略，并写入文档。
6. 所有 public 方法必须标注 MainActor 语义，禁止后台线程驱动 UIKit 状态。

## 11. Top Overscroll Handling 要求

1. AnchorPager 不提供、创建或包装任何顶部拉取控件。
2. AnchorPager 不定义顶部拉取事件回调或任务生命周期。
3. AnchorPager 只处理顶部 overscroll 相关 scroll event 和 gesture state。
4. 支持 none、container、child 三种模式。
5. container 模式下，Header 完全展开后的继续下拉由 verticalScrollView 处理。
6. child 模式下，Header 完全展开后的继续下拉由当前 child scroll view 或内部 page scroll host 处理。
7. 同一次下拉手势中只能有一个 top overscroll owner。
8. Header 展开优先级高于 top overscroll handling。
9. 横向分页、Header layout reload、屏幕旋转或 child 切换期间，active top overscroll handling 必须有明确暂停、取消或恢复策略。

## 12. 状态栏点击顶滚要求

1. 正确处理系统状态栏点击触发的 scroll-to-top。
2. AnchorPager 管理范围内任一时刻只能有一个 UIScrollView 的 scrollsToTop 为 true。
3. 横向分页 scroll view 永远不能响应 scrollsToTop。
4. Header 未完全折叠时，verticalScrollView 作为唯一 scroll-to-top 响应者。
5. Header 已完全折叠且当前 child 可见时，当前 child scroll view 或内部 page scroll host 作为唯一响应者。
6. 非当前 child、已卸载 child、横向 paging scroll view、内部辅助 scroll view 必须关闭 scrollsToTop。
7. 页面切换、reloadData、Header layout reload、屏幕旋转、child 加载或卸载后必须重新计算 scrollsToTop owner。
8. 空页状态下，AnchorPager 管理的所有 scroll view 都关闭 scrollsToTop。

## 13. 屏幕旋转与尺寸变化要求

1. 支持屏幕旋转、Split View、Stage Manager、窗口尺寸变化和 safe area 变化。
2. 不允许只在 viewDidLoad 固定计算布局；必须在 viewWillTransition(to:with:)、viewSafeAreaInsetsDidChange、viewDidLayoutSubviews 等生命周期中重新计算。
3. 尺寸变化后保持 selectedIndex，尽量保持 Header 折叠进度和当前 child 可见内容位置。
4. 横竖屏切换后 child managed contentInset、scrollIndicatorInsets、contentOffset、Tabman/Pageboy 页面位置和 Header frame 必须一致。
5. 旋转期间如果正在拖拽、减速、分页或 top overscroll handling，必须避免状态互相覆盖，必要时延迟合并布局请求到 idle。

## 14. 手势与过渡临界点要求

1. 必须定义清晰的 internal interaction state，例如 idle、verticalDragging、verticalDecelerating、horizontalPaging、programmaticPaging、topOverscrolling、layoutReloading、transitioningSize。
2. 同一时刻只能有一个主交互 owner；状态切换必须有 begin、update、finish、cancel 路径。
3. 横向分页、纵向滚动、Header 拖拽、top overscroll、状态栏点击、layout reload、屏幕旋转之间必须有明确优先级。
4. Header 接近完全展开、完全折叠、child top boundary 时必须稳定处理 UIKit rubber-band 抖动。
5. top overscroll 进入和退出必须有 hysteresis 或明确阈值，避免 owner 反复切换。
6. setSelectedIndex、分段栏点击、横向滑动完成、横向滑动取消必须走同一套 selection commit/cancel 规则。
7. selectedIndex 只能在页面切换确认完成后提交；取消或回弹不能提前提交。
8. 非相邻页面切换不连续滚过中间页，应直接建立 source/target 过渡语义。
9. 快速连续 setSelectedIndex 或连续点击时，旧 transition completion 不能覆盖新请求状态。
10. reloadData 和 reloadHeaderLayout 发生在非 idle 状态时，必须延迟到安全点或执行明确 cancel 流程。
11. Header height 变化时，必须避免 contentInset 和 contentOffset 递归触发导致跳动。
12. 主动设置 contentOffset 必须有 guarded update，避免 scrollViewDidScroll 重入污染状态。
13. child contentSize 变化时，不能反复重写相同 managed inset 导致滚动位置震荡。
14. 不假设 UIKit 回调顺序固定；必须处理缺失、重复或乱序的边界回调。
15. 系统返回手势、横向分页手势、child 横向 content scroll 手势之间必须有明确优先级；第一页 leading-edge 返回手势不应被吞掉。
16. 所有 internal state 命名要便于测试定位，但不得暴露到 public API。

## 15. Accessibility 与 Layout Direction 要求

1. 分段栏 item 必须支持 selected 和 button accessibility traits。
2. Header、bar、child 内容不应破坏 VoiceOver 访问顺序。
3. 支持 Dynamic Type，分段栏高度或 item 布局变化后必须触发布局更新。
4. 支持 Reduce Motion，非必要动画应可降级或缩短。
5. 必须支持 left-to-right 和 right-to-left layout direction。
6. 横向分页方向、分段栏 indicator 位置、非相邻页面过渡方向必须在 RTL 下行为明确。

## 16. Resource Lifecycle 要求

1. KVO、Notification、gesture delegate、display link、Task、closure callback 必须在 child 卸载或 deinit 时释放。
2. 不允许 child store、adapter、coordinator 之间形成 retain cycle。
3. reloadData 后旧 child 应可释放。
4. deinit 时必须清理内部 observer、gesture 关系和 pending transition。

## 17. 日志与可观测性要求

1. 必须在必要事件位置加入日志，方便后续调试、开发和问题修复。
2. 框架内部优先使用 `os.Logger`，不得在生产路径散落 `print`。
3. 必须提供内部日志门面，例如 `AnchorPagerLogger`，统一管理 subsystem、category、level 和消息格式。
4. 日志 subsystem 建议为 `com.anchorpager.AnchorPager`。
5. 日志 category 至少覆盖 lifecycle、layout、header、paging、children、scroll、inset、overscroll、gesture、accessibility、resource。
6. 必须记录关键生命周期事件：init、deinit、reloadData begin/end、child add/remove、header controller add/remove。
7. 必须记录关键布局事件：Header 测量结果、Header frame 变化、bar frame 变化、safe area 变化、bounds 变化、managed inset 变化。
8. 必须记录关键分页事件：setSelectedIndex 请求、越界 no-op、分页开始、分页完成、分页取消、selectedIndex commit。
9. 必须记录关键滚动协调事件：Header 完全展开、Header 完全折叠、child top boundary、scroll owner 切换、guarded contentOffset update 被触发或跳过。
10. 必须记录顶部 overscroll 事件：mode、owner 进入、owner 退出、owner cancel、阈值判定结果。
11. 必须记录手势和交互状态机事件：state begin、state update 中的重要边界、state finish、state cancel、非法或重复 transition 被忽略。
12. 必须记录状态栏点击顶滚 owner 变化。
13. 必须记录异常和降级策略：重复 viewController、无 scroll view fallback host、Header 测量异常、Tabman/Pageboy 回调缺失或乱序。
14. 高频滚动路径不得逐帧打印普通日志，只能记录状态变化、阈值跨越、owner 切换、异常或显式调试开关下的采样日志。
15. 日志不得输出业务数据、用户内容、完整 view 层级或可能包含隐私的数据。
16. 日志必须可测试。实现时应通过内部可注入 log sink 或等价机制验证关键事件确实发出，不依赖人工查看控制台。
17. README 和 `docs/architecture.md` 必须说明日志策略、category、如何过滤日志以及性能注意事项。

## 18. 建议内部模块

1. `AnchorPagerRootView`
2. `AnchorPagerLayoutEngine`
3. `AnchorPagerHeaderViewHost`
4. `AnchorPagerHeaderCoordinator`
5. `AnchorPagerChildViewControllerStore`
6. `AnchorPagerPageCoordinator`
7. `AnchorPagerScrollCoordinator`
8. `AnchorPagerOverscrollCoordinator`
9. `AnchorPagerGestureCoordinator`
10. `AnchorPagerTabBarAdapter`
11. `AnchorPagerLogger`

## 19. 工程结构要求

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
Tests/AnchorPagerTests/
Examples/AnchorPagerExample/
docs/architecture.md
README.md
```

## 20. 默认行为

1. Header 默认使用 automatic height，最小高度为 0，不设置固定最大高度。
2. Header 默认 topBehavior 为 insideSafeArea。
3. 分段栏默认高度为 48。
4. 默认支持点击分段栏、API 选择、横向滑动切页。
5. 默认启用 UIViewController.anchorPagerDefaultScrollView 自动查找。
6. 空页时 selectedIndex 对外保持 0，effectiveSelectedIndex 为 nil。
7. 支持不同 contentSize 的 child。
8. 支持状态栏点击滚到顶部，保证 window 内只有一个 scrollsToTop 响应者。
9. 可以嵌入普通 UIKit 容器层级。

## 21. Documentation 要求

1. `docs/architecture.md` 必须包含 public API 契约、状态机、safe area 策略、scroll view discovery 策略、inset ownership、child lifecycle、gesture priority 和 known limitations。
2. `README.md` 必须包含最小接入示例、Header UIView 示例、Header UIViewController 示例、显式 anchorPagerScrollView 示例、无 UIScrollView child 示例。
3. 文档必须说明 Tabman/Pageboy 的适配边界，以及第三方类型不会出现在 public API。
4. 文档必须说明默认 scroll view lookup 的确定性规则和关闭方式。
5. 文档必须说明内部日志策略、日志 category、推荐过滤方式和性能注意事项。

## 22. 开发顺序

1. 创建全新 Swift Package：AnchorPager。
2. 配置 iOS 14+ 和 Tabman 依赖。
3. 编写 `docs/architecture.md`，定义架构、API、生命周期规则、Header 安全区域规则、Header 动态 frame 规则、child scroll view 解析规则、inset ownership、top overscroll event 规则、状态栏点击顶滚规则、手势临界点规则、旋转适配规则、日志策略、参考项目和非目标。
4. 实现 public API skeleton。
5. 实现内部日志门面和关键事件日志测试。
6. 实现 UIViewController anchorPagerScrollView extension、associated object 显式设置、默认嵌套查找和测试。
7. 实现 AnchorPagerLayoutEngine 和单元测试。
8. 实现 Header 管理、Header controller containment 和 Header 动态 frame 更新。
9. 实现 child store、child containment、缓存窗口和 lifecycle 转发。
10. 封装 Tabman/Pageboy adapter。
11. 实现纵向嵌套滚动协调。
12. 实现顶部 overscroll event handling。
13. 实现手势仲裁和交互状态机。
14. 实现状态栏点击顶滚 owner 管理。
15. 实现屏幕旋转、bounds 变化和 safe area 变化后的布局恢复。
16. 创建示例工程，覆盖基础分页、不同 contentSize、Header 安全区域模式、Header 动态高度、顶部 overscroll、屏幕旋转。
17. 补充 Swift Testing 和必要 UI tests。
18. 补 README 和架构文档。
19. 运行验证并修复 Swift 6 并发警告。

## 23. 测试要求

每完成一个实现任务都必须有对应测试。任务不能只以代码完成作为完成标准，必须同时提供可重复运行的测试或验证命令。涉及 UIKit 可见行为、用户交互、分页、滚动、手势、状态栏点击、旋转、safe area、Dynamic Type、Reduce Motion、RTL 或示例工程行为的任务，必须补充必要 UI 测试；如果某个任务无法通过 UI 测试稳定覆盖，必须在对应任务说明中写明原因，并提供替代的自动化验证。

1. LayoutEngine 单测
2. Header automatic、fixed、ranged height 单测
3. Header height clamp 单测
4. Header insideSafeArea、extendsUnderTopSafeArea 布局单测
5. Header frame runtime change 单测
6. Header controller containment 单测
7. safeAreaInsets.top、safeAreaInsets.bottom 变化布局测试
8. navigation bar 可见、隐藏切换测试
9. tab bar、toolbar 底部遮挡测试
10. additionalSafeAreaInsets 参与布局测试
11. 非 root child view controller 本地坐标转换测试
12. managed inset 不覆盖外部 contentInset 测试
13. selectedIndex/effectiveSelectedIndex 空页单测
14. setSelectedIndex 越界 no-op 测试
15. reloadData 后 selectedIndex clamp 测试
16. child cache window、unload offset snapshot 测试
17. reloadData 后旧 child 释放测试
18. UIViewController.anchorPagerScrollView 显式设置测试
19. UIViewController.anchorPagerDefaultScrollView 默认嵌套查找测试
20. 显式设置优先于默认查找测试
21. 多个 UIScrollView 时选择规则稳定性测试
22. hidden、alpha、userInteractionEnabled 过滤测试
23. 关闭默认查找后使用内部 page scroll host 测试
24. 无候选 UIScrollView 时使用内部 page scroll host 测试
25. 不跨 child view controller 边界查找测试
26. child add/remove containment 单测
27. child appearance lifecycle 顺序测试
28. top overscroll owner 互斥单测
29. top overscroll handling mode 单测
30. Header 展开/折叠阈值附近抖动测试
31. top overscroll owner 进入/退出 hysteresis 测试
32. 横向分页与纵向拖拽竞争测试
33. paging cancel 不提交 selectedIndex 测试
34. 快速连续 setSelectedIndex 旧 completion 不覆盖新状态测试
35. reloadData、reloadHeaderLayout 非 idle 合并或取消测试
36. contentOffset guarded update 防重入测试
37. contentSize 变化不导致 managed inset 重复写入测试
38. 系统返回手势与横向分页手势优先级测试
39. status bar tap scrollsToTop owner 切换测试
40. 状态栏点击发生在 paging、dragging、topOverscrolling 时的策略测试
41. Dynamic Type、Reduce Motion 行为测试
42. RTL layout direction 测试
43. observer、callback 生命周期测试
44. screen rotation、bounds change layout 单测
45. safe area change 后 Header、分段栏、child inset 保持一致性测试
46. Example build 验证
47. 至少一个 UI test 覆盖 Header 展开优先于顶部 overscroll handling
48. 日志门面单测
49. 关键生命周期日志测试
50. 关键布局日志测试
51. 关键分页日志测试
52. 高频滚动路径不逐帧输出普通日志测试

## 24. 验证命令

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=<available simulator>' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
```

## 25. 代码质量要求

1. UIKit 类型、公开 API、data source、delegate、coordinator 状态更新保持 `@MainActor`。
2. 不使用 `Task.detached` 绕过 actor 隔离。
3. 不使用 `@unchecked Sendable`、`nonisolated(unsafe)`、`@preconcurrency` 压制问题，除非有明确线程安全说明。
4. public/open API 使用简洁 DocC 注释。
5. 第三方库类型不泄漏到 AnchorPager public API。
6. 核心框架不能包含具体应用场景专属类型或命名。
7. 优先小步实现，每个重要行为都有对应测试。
8. 每个实现任务完成时必须同步提交测试，不能把测试推迟到后续任务统一补。
9. 触达用户可见 UI、UIKit 生命周期、手势、滚动、分页或系统交互的任务必须包含必要 UI 测试。
10. 任务验收说明必须列出实际运行过的测试命令和结果。
11. 日志必须通过统一内部门面输出，避免零散调用 `print` 或直接散落 `Logger`。
12. 日志必须以状态变化和异常定位为主，不得在滚动热路径持续输出高频噪声。

## 26. 一句话目标

AnchorPager 是一个 UIKit nested paging container，提供 automatic dynamic header sizing、safe-area-aware layout、deterministic scroll-view discovery、inset ownership、top overscroll event handling、gesture edge-case handling、status-bar scroll-to-top ownership、rotation-resilient layout、complete child view controller lifecycle 和 Tabman-backed horizontal paging。
