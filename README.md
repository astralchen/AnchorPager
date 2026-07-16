# AnchorPager

AnchorPager 是一个 UIKit 容器框架，用于组合可变 Header、吸顶分段栏、多页面横向分页和纵向嵌套滚动。当前实现已在 v0.4 page identity、cache、reload generation 与 managed inset 基础上完成 container/current child 连续 handoff、无滚动页面直接 Pageboy containment、稳定区间与原生边界分离，以及 `.none`、`.container`、`.child` 三种顶部 overscroll 路由。默认顶部模式为 `.container`。

2026-07-13 使用 Apple Swift 6.3.3、iPhone 17 Pro / iOS 26.5 完成最终验收：生产代码 HEAD `128821f` 对应的最近 Framework 结果包 `/private/tmp/AnchorPagerPresentedTopFrameworkFull-20260713-2258.xcresult` 为 283/283；本次补强 owner 排他断言后的 Example 为 37/37（10 项单元测试 + 27 项 UI 测试），均为 0 failure、0 skip；Example generic iOS Simulator build 成功。三份最终结果的 error、warning 与 analyzer warning 均为 0。第四次整分支独立复审覆盖 `be2d783...13b3d95`，结论为 Critical 0、Important 0、Minor 2；README 旧验收摘要和 `.container` 顶部真实 UI 缺少 `childTopMax < 0.5` 严格断言两个 Minor 已在本提交修复，v0.5 Task 7 与 v0.6 均达到 Ready。

2026-07-14 后续用户验收发现：`c37e829` 的 Header bootstrap 只覆盖正式中立测量前，真实 Header 会先附着到旧 `height == 0` host 并瞬时触发内部约束冲突。生产提交 `d6ece31` 已把 incoming fitting 和 required host height 更新前移到内容附着之前；UIViewController Header 保持 `addChild → load/measure → seed → addSubview → didMove`，正式 measurement/cache/log 语义不变。Apple Swift 6.3.3 / Xcode 26.6 下，Framework 296/296、Example 38/38（10 项单元测试 + 28 项 UI 测试）与 generic Simulator build 全部通过，0 fail、0 skip、0 error/warning/analyzer warning；独立新进程实际执行 Header 安装后未产生 UIKit `LayoutConstraints` 冲突。fresh-pass 复审为 Critical 0、Important 0、Minor 0，v0.5 Task 7 与 v0.6 恢复 Ready。

2026-07-14 主容器 top inset 与固定高度 Header 专项已在最终生产 HEAD `424a0a3` 收口：`.insideSafeArea` 使用本地顶部遮挡作为真实 `contentInset.top`，`.extendsUnderTopSafeArea` 使用 `0`；业务 Header 根视图在正常折叠中保持完整高度，由 AnchorPager 自有 presentation surface 上移。fresh-pass 发现的 safe-area/bounds active boundary 清理、缺失 `willSelect` 的 plain selection terminal 清理、geometry 迁移日志和 Public DocC 共 2 个 Important、2 个 Minor 均已通过 RED/GREEN 修复，终态 Critical 0、Important 0、Minor 0。Framework 322/322、Example 41/41（11 项单元测试 + 30 项 UI 测试）与 generic Simulator build 全部通过，0 fail、0 skip、0 error/warning/analyzer warning；v0.5 Task 7 与 v0.6 已恢复 Ready。

2026-07-15 Header 默认顶部行为专项已在生产代码 HEAD `3bdcfb6` 完成：`AnchorPagerHeaderTopBehavior` 默认使用 `.extendsUnderTopSafeArea`，未显式配置时 Header 背景从容器顶部开始并覆盖顶部系统区域；需要让 Header 背景从安全区域下方开始时，仍可显式选择 `.insideSafeArea`。这只是默认选择变化，不改变固定高度 Header、bar 吸顶基线或 viewport 裁剪语义。Apple Swift 6.3.3 / Xcode 26.6 下，Framework 322/322、Example 41/41（11 项单元测试 + 30 项 UI 测试）与 generic Simulator build 全部通过，0 fail、0 skip、0 error/warning/analyzer warning；默认启动与显式 inside 运行时日志未出现 UIKit 约束冲突。fresh-pass 覆盖 `97e8fc2...f4d9f41`，结论为 Critical 0、Important 0、Minor 0。

## 安装

构建 AnchorPager 需要 Swift 6.2 或更高版本工具链；Package 使用 Swift 6 language mode，运行时最低支持 iOS 14。
`swiftLanguageModes: [.v6]` 表示语言模式，不表示最低工具链仍为 Swift 6.0。

```swift
.package(url: "<repo-url>", branch: "main")
```

```swift
.product(name: "AnchorPager", package: "AnchorPager")
```

## 最小接入

```swift
import AnchorPager
import UIKit

final class PagerHostViewController: UIViewController, AnchorPagerViewControllerDataSource {
    private let pager = AnchorPagerViewController()
    private let pages = [UIViewController(), UIViewController(), UIViewController()]

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(pager)
        view.addSubview(pager.view)
        pager.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pager.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pager.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pager.view.topAnchor.constraint(equalTo: view.topAnchor),
            pager.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pager.didMove(toParent: self)

        pager.dataSource = self
        pager.reloadData()
    }

    func numberOfViewControllers(in pagerViewController: AnchorPagerViewController) -> Int {
        pages.count
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        titleForViewControllerAt index: Int
    ) -> String {
        "Page \(index + 1)"
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        viewControllerAt index: Int
    ) -> UIViewController {
        pages[index]
    }

    func headerContent(in pagerViewController: AnchorPagerViewController) -> AnchorPagerHeaderContent {
        .view(makeHeaderView())
    }

    private func makeHeaderView() -> UIView {
        let label = UILabel()
        label.text = "Header"
        label.textAlignment = .center
        label.backgroundColor = .secondarySystemBackground
        return label
    }
}
```

## Header UIView

```swift
func headerContent(in pagerViewController: AnchorPagerViewController) -> AnchorPagerHeaderContent {
    let headerView = UILabel()
    headerView.text = "Header"
    headerView.textAlignment = .center
    return .view(headerView)
}
```

## Header UIViewController

```swift
func headerContent(in pagerViewController: AnchorPagerViewController) -> AnchorPagerHeaderContent {
    .viewController(HeaderViewController())
}
```

Header 使用 `UIViewController` 时，AnchorPager 内部通过标准 UIKit containment 承载。

横向页面的实际分页和 page view controller containment 由内部 Tabman/Pageboy adapter 执行。AnchorPager 维护 public API、selection、reload、scroll discovery 和真实 scroll target 的 inset/scroll 策略，应用代码不需要直接使用 Tabman 或 Pageboy 类型。无滚动页直接作为 Pageboy page，不建立 AnchorPager 对业务页面的第二层 containment。

可见状态下调用 `setSelectedIndex(_:animated:)` 时，AnchorPager 会等内部分页 adapter 确认完成后再更新 `selectedIndex` 并通知 delegate；取消或回弹不会提前提交。若分页 adapter 正在处理上一笔切页而拒绝新请求，v0.1 不做请求排队，当前 public 选择状态保持不变。

## Header 布局配置

`AnchorPagerConfiguration.header.heightMode` 控制 Header 展开和折叠高度：

```swift
var configuration = AnchorPagerConfiguration.default
configuration.header.heightMode = .automatic(min: 44, max: 180)
// 默认 topBehavior 为 .extendsUnderTopSafeArea。

// 如需让 Header 背景从顶部安全区域下方开始：
configuration.header.topBehavior = .insideSafeArea

let pager = AnchorPagerViewController(configuration: configuration)
```

分段栏高度默认由内部分页适配器自适应，也可以显式覆盖：

```swift
var configuration = AnchorPagerConfiguration.default
configuration.bar.height = nil // 默认：自适应实际分段栏高度
configuration.bar.height = 56  // 可选：显式覆盖
```

当前 height mode 语义：

- `.automatic(min:max:)`：使用 Header 测量高度作为展开高度，并按 min/max 夹取。
- `.fixed(max:min:)`：使用 `max` 作为展开高度，`min` 作为折叠高度。
- `.ranged(min:max:)`：使用 Header 测量高度，并限制在 min/max 范围内。

Header height mode 表示不包含顶部安全区遮挡的纯内容高度，可折叠距离也只由内容的展开/折叠高度决定。默认 `.extendsUnderTopSafeArea`；只有显式选择 `AnchorPagerHeaderTopBehavior.insideSafeArea` 时，Header frame 才从本地顶部 safe area 或系统栏遮挡下方开始，高度始终为完整展开内容高度。`.extendsUnderTopSafeArea` 下，Header frame 从容器 bounds 顶部开始，高度始终为“顶部遮挡 + 完整展开内容高度”。正常折叠只让固定高度 Header 向上移动，不修改业务 Header 根视图高度。两种模式的分段栏和 child 内容基线一致，切换只改变 Header 外框是否延伸到顶部系统区域。例如展开内容高度为 `108`、顶部遮挡为 `116` 时，extends 模式的 `headerFrame.height == 224`，折叠期间该高度保持不变。默认 extends 不代表取消折叠时的物理屏幕边界裁剪。

automatic/ranged Header 会在顶部遮挡下方的中立几何中测量，避免 Header 当前展示位置的 safe area 或 `layoutMarginsGuide` 被重复计入内容高度。测量缓存只属于当前 Header 内容身份；内容更换时旧缓存失效，首次正式中立布局前先以不发布状态的 compressed fitting 取得非负 seed，因此非空约束内容不会以 required `height == 0` 参与布局。该测量只在结构性布局路径执行；滚动热路径继续复用当前 Header 最近一次有效纯内容高度。

AnchorPager 自有的主容器 `verticalScrollView` 会关闭 UIKit 自动 content inset 调整。该主容器的 `contentInsetAdjustmentBehavior` 保持 `.never`，其 delegate 与 `contentInset` 均由 AnchorPager 内部管理，调用方不得替换或写入。`.insideSafeArea` 的 `contentInset.top` 等于当前本地顶部遮挡，`.extendsUnderTopSafeArea` 为 `0`；left/bottom/right 始终为 `0`。主容器只表示 Header 折叠范围，横纵滚动指示器保持隐藏；用户可见滚动进度只由当前真实 child scroll target 表达，无滚动页面没有滚动指示器。

主容器内部把滚动范围和可见内容解耦。设顶部 inset 为 `I`、纯内容可折叠距离为 `D`、viewport 高度为 `H`：raw offset 与逻辑折叠量的关系为 `logical = raw + I`，展开/折叠 raw 边界分别是 `-I` 与 `D - I`，`scrollRangeView` 高度为 `H + D - I`。Header 和横向 paging adapter 位于 `frameLayoutGuide` 对应的固定 viewport 内，正常折叠只移动不裁剪的 canonical content presentation surface，不参与 `contentSize` 反算。顶部 container overflow 由 UIKit bounce 驱动共享 viewport，使 Header、分段栏和页面整体下移；plain bottom overflow 的原生物理仍来自 container，但可见 presentation 只移动 adapter 内 `UIPageViewController.view`，不移动 Header/bar，也不手工实现弹簧动画。

横向分页 adapter 的 top 跟随 Header bottom，高度固定为 Header 完全折叠时的最大 viewport 高度。Header 折叠热路径只移动承载 Header 与 adapter 的 canonical content presentation，不改变 Header 根视图高度或 Pageboy child bounds；展开时超出 viewport 的底部由容器裁剪。bottom safe area、tab bar 和 toolbar 不裁剪横向区域，而是写入 child 的 managed bottom inset。该 bottom 使用 child 局部坐标：等于 adapter 当前底端到 pager 安全可见底端的距离；展开时包含尚未折叠距离，完全折叠时收敛为根容器底部遮挡。

当 Header 内容高度或配置运行时变化时，调用：

```swift
pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
```

四种 offset 策略：

- `.preserveVisualPosition`：尽量保持当前可见 Header 高度。
- `.preserveCollapseProgress`：按旧折叠进度迁移到新高度范围。
- `.resetToExpanded`：回到展开位置。
- `.resetToCollapsed`：移动到当前折叠上限。

child managed top 只等于实际分段栏对页面的遮挡，不包含 Header 或顶部 safe area；Header 和顶部系统遮挡由 adapter frame 处理。滚动指示器 top 同步避让实际分段栏，content/indicator bottom 等于 adapter 当前底端到 pager 安全可见底端的 child 局部遮挡，保证最后内容和指示器都不会进入 tab bar、toolbar 或底部安全区域。

`AnchorPagerLayoutContext` 回调中的 `headerFrame`、`barFrame` 和 `contentFrame` 使用 pager view 的本地最终可见坐标。正常折叠时固定高度 Header、bar 和内容 frame 已包含逻辑折叠位移；顶部 container bounce 时三者再包含同量正向 viewport presentation；plain bottom bounce 时 Header/bar 保持折叠后的 canonical 位置，只有 `contentFrame` 包含页面 surface 的负向位移。`reloadHeaderLayout(offsetAdjustment:)` 仍只使用稳定逻辑折叠状态，不会把瞬时 bounce 位移写入 Header 高度或折叠进度。

## 显式 Scroll View

```swift
final class ListPageViewController: UIViewController {
    private let tableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(tableView)
        anchorPagerScrollView = tableView
    }
}
```

显式设置的 `anchorPagerScrollView` 优先级高于默认查找。该属性只表示参与 Header 折叠、纵向 handoff、managed inset、offset snapshot 和边界 owner 的纵向协调目标，不是页面内任意 `UIScrollView` 的登记入口。

只有横向业务滚动视图的页面必须关闭默认查找，并保持纵向目标为 nil：

```swift
final class HorizontalOnlyPageViewController: UIViewController {
    private let horizontalScrollView = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(horizontalScrollView)
        anchorPagerUsesDefaultScrollViewLookup = false
    }
}
```

页面同时包含纵向父 scroll 和嵌套横向业务 scroll 时，只把纵向父 scroll 设置为 `anchorPagerScrollView`。默认查找保持确定性的深度优先规则，不依据 `contentSize` 或运行时手势推断轴向；接入方必须显式表达 horizontal-only 或混合页面的纵向目标语义。

页面内的横向业务滚动需要稳定优先于 Pageboy 时，可按页面关闭交互式横向分页：

```swift
func pagerViewController(
    _ pagerViewController: AnchorPagerViewController,
    allowsInteractiveHorizontalPagingAt index: Int
) -> Bool {
    !pagesWithHorizontalBusinessContent.contains(index)
}
```

该方法默认返回 `true`。返回 `false` 只关闭 committed current page 的 Pageboy 横向拖拽；分段栏与 `setSelectedIndex(_:animated:)` 仍可切页。策略是页面级静态门禁：业务横向内容到达边界后不会把同一次拖动交接给 Pageboy，也不支持同一页面按命中区域分别启停分页。策略与 page count/title 在同一 reload generation 原子提交，不会预加载页面或修改业务 scroll/pan delegate、bounce 与 `isScrollEnabled`。

AnchorPager 接管目标 scroll view 时会把 `contentInsetAdjustmentBehavior` 设为 `.never`、把 `automaticallyAdjustsScrollIndicatorInsets` 设为 `false`，并在现有外部 inset 上差量叠加 managed top/bottom。页面被 reload 移除或容器释放时，只移除最后一次 managed 部分，并恢复两项原始自动调整状态。调用方运行时修改外部 inset 时，应基于当前总 inset 做增量修改；若直接用不包含 managed 部分的绝对值覆盖整个 `contentInset`，框架无法从 UIKit 单一属性推断调用方意图。

## 纵向协调与边界回弹

默认 `configuration.topOverscrollHandlingMode == .container`。三种顶部模式的语义为：

- `.none`：Header 展开后收敛到稳定顶部，不保留可见顶部回弹。
- `.container`：由 AnchorPager 自有 `verticalScrollView` 呈现顶部回弹。
- `.child`：只在当前已提交页面存在真实 scroll target 时，把顶部边界路由给该业务 scroll view；无滚动页或空态不会回退到 container。

底部 owner 与顶部 mode 无关：真实 scroll page 的底部回弹由业务 child 处理，无滚动页的底部回弹由 container 处理。AnchorPager 不保存、修改或恢复业务 child 的 `bounces`、`alwaysBounceVertical`，也不设置业务 child 的 `UIScrollView.delegate`、内建 `panGestureRecognizer.delegate` 或 `isScrollEnabled`；短内容是否允许 child 原生回弹由业务方配置。

纵向协调只绑定 Store 的 committed current scroll target。框架通过 KVO 和 pan target-action 观察 child，并由自有 container scroll view 子类只放行 committed pair 的 simultaneous recognition。原生边界 owner 活跃时不反向执行 canonical clamp；container 顶部与底部 presentation 使用对称位移，回弹结束后再收敛到稳定区间。切页、matching reload、Header layout reload、尺寸过渡和顶部 mode 切换都会同步取消 active boundary，且不会读取 pending provider page。

## 无 UIScrollView Child

```swift
final class PlainPageViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }
}
```

当页面没有显式或默认发现的 `UIScrollView` 时，AnchorPager 直接把 original page 交给 Pageboy/UIKit containment，Store 保持 page 非 nil、scroll target 为 nil。框架不会为该页面创建替代 `UIScrollView`，也不会写入 managed inset、offset snapshot、child bounce、`additionalSafeAreaInsets` 或业务页面手势代理。页面根 view 按固定 paging viewport 铺开并至少覆盖宿主的物理屏幕底边；业务内容是否避开 safe area 由页面自身决定。该页只有 container pan：顶部 `.container` 由共享 viewport 整体呈现；底部仍由 container 提供原生物理，但只移动 Pageboy 页面 surface；`.child` 顶部因没有真实 scroll target 而不可用。

## 页面生命周期与缓存

`reloadData()` 只同步 Header、标题和页面数量，不会预先创建全部页面。Tabman/Pageboy 需要某个 index 时，内部 `PageStateStore` 才会向 data source 请求对应控制器；同一 reload generation、同一 index 的控制器只要仍存活，就会保持稳定身份。AnchorPager 默认强保留当前页和进行中的切页 source/target；设置 `configuration.paging.keepsAdjacentPagesLoaded = true` 后，还会保留已经加载过的当前页相邻页面。

页面离开缓存窗口时，AnchorPager 会保存其 `childDistanceFromTop` 并归还 managed inset ownership。之后若 data source 为该 index 提供新实例：当主容器已经完全折叠时，页面恢复自己的滚动位置；当主容器尚未完全折叠时，目标页面归到顶部，以维持当前阶段唯一纵向 owner 的约束。Pageboy/UIKit 仍是普通页面 containment 和 appearance lifecycle 的唯一执行者，缓存强引用变化不会触发手工 appearance forwarding。Pageboy/UIKit 可能暂时持有临近页面，因此离开 AnchorPager 缓存窗口不等于承诺页面立即释放。

`reloadData()` 的元数据采集使用 latest-wins transaction；count、Header 或 title 回调中重入 reload 时，过期事务不会发布部分快照。已有可见页面时，新快照先 staged：Host deferred 或 Pageboy reload 执行期间，public selection、Header、旧可见页、Store committed current 和旧 inset ownership 保持同一已提交事实；Host 真正开始 matching request 后才激活 provider generation，只有带同一 request identifier 的 page/empty terminal 被 ViewController 确认后，才原子提交 Store、public metadata、Header 与 request-scoped bar inset。首次 view 尚未加载且没有 committed 页面时可以预发布初始 metadata，但不会因此加载 paging view；首次 terminal 仍提交同一 request。

非空 reload 由 Pageboy `didReloadWith` 产生 page terminal；非空到空时，internal adapter 使用当前锁定 Pageboy 5.0.2 的 public delete-last-page 路径先退出业务页 containment，稳定 paging host 再移除 adapter，并把 `.zero` bar inset 随 empty terminal 提交。这是集中在 `Paging/` 内的版本兼容点；升级 Pageboy 前必须重审 delete/reload 源码顺序、request provenance、terminal acknowledgement、provider activation 和 appearance，并重跑空态 containment、事件静默与延迟释放测试。

## 示例工程

仓库包含 `Examples/AnchorPagerExample.xcodeproj`，用于验证示例 App 能接入本地 `AnchorPager` package、以 `UITabBarController` 作为 window root、首屏直接显示 AnchorPager 示例页，并可通过导航按钮 push 另一个 AnchorPager 示例页来验证 `hidesBottomBarWhenPushed` 隐藏 tab bar。示例页保持默认自适应 bar，通过 public API 提供 Header、真实 scroll view child 和无滚动 child；UI test 验证真实 scroll 页的 managed inset，以及无滚动页的直接 containment、物理底边和 container-only pan。示例导航栏使用单个“示例设置”齿轮菜单切换 Header 顶部行为和顶部回弹模式；两组配置位于独立二级菜单，当前值以勾选态显示，切换后立即应用。默认 `.extendsUnderTopSafeArea` 配合 container 顶部回弹时，框架仍整体移动 Header、bar 和 page；Example Header 通过顶部安全下限与底部稳定锚点保持自身高度和文字相对 Header 顶部距离不变。

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test
```

## 日志

AnchorPager 通过内部 `AnchorPagerLogger` 使用 `os.Logger` 输出关键事件，subsystem 为 `com.anchorpager.AnchorPager`。`AnchorPagerLogger.log` 可从非主线程内部路径调用；测试用 sink 会回到 MainActor 记录事件。当前 category 包括 `lifecycle`、`layout`、`header`、`paging`、`children`、`scroll`、`inset`、`overscroll`、`gesture`、`accessibility`、`resource`。

布局日志包括 Header 高度解析、Header frame、bar frame、safe area 和 bounds 变化；inset 日志记录 ownership begin/update/end/skip 与 scroll target collision。v0.4 的 children 日志记录页面 load/reuse/recreate、缓存 retain/release、snapshot save/restore/reset、reload generation begin/commit/cancel 和重复控制器降级。日志只在状态变化时输出，managed inset 与滚动热路径不会逐帧产生 children 日志。

建议使用 Console.app 或 `log stream` 按 subsystem/category 过滤：

```bash
log stream --predicate 'subsystem == "com.anchorpager.AnchorPager"'
```

日志只记录状态变化、边界事件和降级路径，不输出业务数据、用户内容或完整 view 层级。

## 当前限制

v0.5 连续纵向 handoff、无滚动页直接承载、stable/native boundary 分离、两类底部回弹路径、plain bottom 页面 surface/bar 分层、Header 安装前 bootstrap seed、主容器真实 top inset/固定高度 Header presentation、v0.6 三种顶部模式，以及 v0.7 统一交互状态、快速选择事务、系统返回优先级和双向跨 owner 惯性均已实现。状态栏点击顶滚和尺寸变化后的滚动位置恢复留给 v0.8；refresh control 或业务刷新任务不属于 AnchorPager。Tabman/Pageboy 仅出现在 internal adapter 层，Public API 不暴露第三方类型。

v0.7 最终生产代码 HEAD `07a3443` 已通过 Framework 426/426、Example 60/60（16 单元 + 44 UI）和 generic iOS Simulator build；全部 0 fail、0 skip、0 error、0 warning、0 analyzer warning，fresh-pass 终态为 Critical 0、Important 0、Minor 0。

2026-07-16 横向-only 页面纵向目标修复生产代码 HEAD `984a009` 已把 Example 第五页改为 original Pageboy page + nil 纵向 target；横向业务 scroll 不再进入 managed inset、snapshot、纵向 binding 或 container/current-child simultaneous pair。Framework 426/426、Example 61/61（16 单元 + 45 UI）与 generic iOS Simulator build 全部通过，0 fail、0 skip、0 error、0 warning、0 analyzer warning；fresh-pass 终态 Critical 0、Important 0、Minor 0，v0.7 恢复 Ready。

2026-07-16 Compositional Layout 混合轴专项生产代码 HEAD `db4b9bc` 已追加第六页：根 `UICollectionView` 是唯一纵向 target，orthogonal section 只走业务横向路径；Example index 4、index 5 显式关闭 Pageboy 交互分页，index 3→4 验证 enabled-to-disabled terminal，index 4↔5 只使用分段栏/API。Framework 439/439、Example 70/70（19 单元 + 51 UI）与 generic Simulator build 全部通过，0 fail、0 skip、0 error、0 warning、0 analyzer warning；运行时问题关键字零命中，fresh-pass 终态 Critical 0、Important 0、Minor 0。

当前不保证默认 `true` 页面内部任意横向 `UIScrollView` 自动优先于 Pageboy。真实 UIKit 验收证明 direct failure relation 与无侵入 guard 都无法在不接管既有 delegate、不重置手势、不依赖私有层级且不阻塞页面其他区域的前提下稳定改变同向嵌套 scroll winner；框架因此不安装业务 child failure relation。需要业务横向手势稳定获胜时，接入方应对整个页面返回 `false`，并通过分段栏/API 离页。

在 Xcode 26.3 / Swift 6.2.4 的 x86_64 iPhone 17 Simulator 验证中，把控制器同步析构改为
`isolated deinit` 会在生命周期析构后稳定触发 allocator `pointer being freed was not allocated` 崩溃。
当前生产实现因此保留普通 `deinit + MainActor.assumeIsolated`，同步归还 Store 与 inset ownership；在后续工具链用同一资源析构测试复验通过前，不替换为 `isolated deinit`，也不使用异步 Task 或 unsafe 标记绕开清理顺序。
