# AnchorPager

AnchorPager 是一个 UIKit 容器框架，用于组合可变 Header、吸顶分段栏、多页面横向分页和 child scroll view 接入。当前仓库处于 v0.3 Scroll Discovery 与 Inset Ownership 阶段，已实现固定分页 viewport、分段栏自适应/显式高度、child managed inset 差量所有权、fallback 统一接入，以及 reload/deinit 归还语义。

## 安装

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

横向页面的实际分页和 page view controller containment 由内部 Tabman/Pageboy adapter 执行。AnchorPager 维护 public API、selection、reload、scroll discovery、fallback host 和后续 inset/scroll 策略，应用代码不需要直接使用 Tabman 或 Pageboy 类型。

可见状态下调用 `setSelectedIndex(_:animated:)` 时，AnchorPager 会等内部分页 adapter 确认完成后再更新 `selectedIndex` 并通知 delegate；取消或回弹不会提前提交。若分页 adapter 正在处理上一笔切页而拒绝新请求，v0.1 不做请求排队，当前 public 选择状态保持不变。

## Header 布局配置

`AnchorPagerConfiguration.header.heightMode` 控制 Header 展开和折叠高度：

```swift
var configuration = AnchorPagerConfiguration.default
configuration.header.heightMode = .automatic(min: 44, max: 180)
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

Header height mode 表示不包含顶部安全区遮挡的纯内容高度，可折叠距离也只由内容的展开/折叠高度决定。`AnchorPagerHeaderTopBehavior.insideSafeArea` 下，Header frame 从本地顶部 safe area 或系统栏遮挡下方开始，高度为当前可见内容高度；`.extendsUnderTopSafeArea` 下，Header frame 从容器 bounds 顶部开始，高度为“顶部遮挡 + 当前可见内容高度”。因此两种模式的分段栏和 child 内容基线一致，切换只改变 Header 外框是否延伸到顶部系统区域。例如内容高度为 `108`、顶部遮挡为 `116` 时，extends 模式的 `headerFrame.height == 224`。

automatic/ranged Header 会在顶部遮挡下方的中立几何中测量，避免 Header 当前展示位置的 safe area 或 `layoutMarginsGuide` 被重复计入内容高度。该测量只在结构性布局路径执行；滚动热路径继续复用最近一次有效纯内容高度。

AnchorPager 自有的主容器 `verticalScrollView` 会关闭 UIKit 自动 content inset 调整，避免 navigation bar、safe area 等顶部遮挡被系统和 AnchorPager 布局引擎重复叠加。该主容器的 `contentInsetAdjustmentBehavior` 应保持 `.never`，其 delegate 由 AnchorPager 内部管理，调用方不得替换。主容器只表示 Header 折叠范围，横纵滚动指示器保持隐藏；用户可见滚动进度由当前 child/fallback 表达。

主容器内部把滚动范围和可见内容解耦：`scrollRangeView` 通过 `contentLayoutGuide` 定义固定的 `viewport height + Header 内容可折叠距离`，Header 和横向 paging adapter 则位于 `frameLayoutGuide` 对应的固定 viewport。非负 `contentOffset` 只驱动 LayoutEngine 计算 Header/bar 的 canonical frame，不参与 `contentSize` 反算；负 offset 由 UIKit bounce 驱动，并通过 viewport presentation translation 同步移动 Header、分段栏和页面，不手工实现弹簧动画。

横向分页 adapter 的 top 跟随 Header bottom，高度固定为 Header 完全折叠时的最大 viewport 高度。Header 折叠热路径只移动 adapter，不改变 Pageboy child bounds；展开时超出 viewport 的底部由容器裁剪。bottom safe area、tab bar 和 toolbar 不裁剪横向区域，而是写入 child 的 managed bottom inset。该 bottom 使用 child 局部坐标：等于 adapter 当前底端到 pager 安全可见底端的距离；展开时包含尚未折叠距离，完全折叠时收敛为根容器底部遮挡。

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

`AnchorPagerLayoutContext` 回调中的 `headerFrame`、`barFrame` 和 `contentFrame` 使用 pager view 的本地实际可见坐标。正常折叠时它们等于 LayoutEngine 的 canonical frame；负 offset bounce 期间会包含 viewport presentation translation，因此实际 Header/paging frame 与 context 始终对齐。`reloadHeaderLayout(offsetAdjustment:)` 仍只使用 canonical 折叠状态，不会把瞬时 bounce 位移写入 Header 高度或折叠进度。

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

显式设置的 `anchorPagerScrollView` 优先级高于默认查找。

AnchorPager 接管目标 scroll view 时会把 `contentInsetAdjustmentBehavior` 设为 `.never`、把 `automaticallyAdjustsScrollIndicatorInsets` 设为 `false`，并在现有外部 inset 上差量叠加 managed top/bottom。页面被 reload 移除或容器释放时，只移除最后一次 managed 部分，并恢复两项原始自动调整状态。调用方运行时修改外部 inset 时，应基于当前总 inset 做增量修改；若直接用不包含 managed 部分的绝对值覆盖整个 `contentInset`，框架无法从 UIKit 单一属性推断调用方意图。

## 无 UIScrollView Child

```swift
final class PlainPageViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }
}
```

无候选 `UIScrollView` 时，AnchorPager 会先使用内部 fallback scroll host 包装普通 child，再交给横向分页 adapter。fallback 与真实 scroll page 使用同一套 managed inset 规则；普通 child 的最小高度按扣除 managed top/bottom 后的可用 viewport 计算。

## 示例工程

仓库包含 `Examples/AnchorPagerExample.xcodeproj`，用于验证示例 App 能接入本地 `AnchorPager` package、以 `UITabBarController` 作为 window root、首屏直接显示 AnchorPager 示例页，并可通过导航按钮 push 另一个 AnchorPager 示例页来验证 `hidesBottomBarWhenPushed` 隐藏 tab bar。示例页保持默认自适应 bar，通过 public API 提供 Header、真实 scroll view child 和 fallback child；UI test 同时验证两类页面在 managed inset 生效后仍可见。

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## 日志

AnchorPager 通过内部 `AnchorPagerLogger` 使用 `os.Logger` 输出关键事件，subsystem 为 `com.anchorpager.AnchorPager`。`AnchorPagerLogger.log` 可从非主线程内部路径调用；测试用 sink 会回到 MainActor 记录事件。当前 category 包括 `lifecycle`、`layout`、`header`、`paging`、`children`、`scroll`、`inset`、`overscroll`、`gesture`、`accessibility`、`resource`。

v0.3 布局日志包括 Header 高度解析、Header frame、bar frame、safe area 和 bounds 变化；inset 日志记录 ownership begin/update/end/skip 与 scroll target collision。日志只在状态变化时输出，避免普通布局 pass 或滚动热路径产生重复噪声。

建议使用 Console.app 或 `log stream` 按 subsystem/category 过滤：

```bash
log stream --predicate 'subsystem == "com.anchorpager.AnchorPager"'
```

日志只记录状态变化、边界事件和降级路径，不输出业务数据、用户内容或完整 view 层级。

## 当前限制

v0.3 当前已交付固定分页 viewport、optional bar height、真实 bar obstruction、child/fallback managed inset ownership 和归还语义。完整纵向嵌套滚动协调、顶部 overscroll owner、状态栏点击顶滚、尺寸变化恢复、page cache window 和 Tabman 驱动的 appearance lifecycle 语义仍在后续版本。Tabman/Pageboy 仅出现在 internal adapter 层，Public API 不暴露第三方类型。
