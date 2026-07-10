# AnchorPager

AnchorPager 是一个 UIKit 容器框架，用于组合可变 Header、吸顶分段栏、多页面横向分页和 child scroll view 接入。当前仓库处于 v0.2 Header 与布局稳定阶段，已建立 Swift Package、Public API skeleton、日志门面、Header/fallback 基础承载、scroll view discovery、Tabman/Pageboy internal adapter 边界，并已固化 Header height mode、safe area/top behavior、`reloadHeaderLayout(offsetAdjustment:)` 和布局日志的基础契约。

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

横向页面的实际分页和 page view controller containment 由内部 Tabman/Pageboy adapter 执行。AnchorPager 维护 public API、selection、reload、scroll discovery、fallback host 和后续 inset/scroll 策略，不要求接入方直接使用 Tabman 或 Pageboy 类型。

可见状态下调用 `setSelectedIndex(_:animated:)` 时，AnchorPager 会等内部分页 adapter 确认完成后再更新 `selectedIndex` 并通知 delegate；取消或回弹不会提前提交。若分页 adapter 正在处理上一笔切页而拒绝新请求，v0.1 不做请求排队，当前 public 选择状态保持不变。

## Header 布局配置

`AnchorPagerConfiguration.header.heightMode` 控制 Header 展开和折叠高度：

```swift
var configuration = AnchorPagerConfiguration.default
configuration.header.heightMode = .automatic(min: 44, max: 180)
configuration.header.topBehavior = .insideSafeArea

let pager = AnchorPagerViewController(configuration: configuration)
```

当前 height mode 语义：

- `.automatic(min:max:)`：使用 Header 测量高度作为展开高度，并按 min/max 夹取。
- `.fixed(max:min:)`：使用 `max` 作为展开高度，`min` 作为折叠高度。
- `.ranged(min:max:)`：使用 Header 测量高度，并限制在 min/max 范围内。

`AnchorPagerHeaderTopBehavior.insideSafeArea` 会让 Header 从本地顶部 safe area 或系统栏遮挡下方开始；`.extendsUnderTopSafeArea` 会让 Header 从容器 bounds 顶部开始，但分段栏吸顶基线仍不高于顶部遮挡。

AnchorPager 自有的主容器 `verticalScrollView` 会关闭 UIKit 自动 content inset 调整，避免 navigation bar、safe area 等顶部遮挡被系统和 AnchorPager 布局引擎重复叠加。接入方不应重新打开这个主容器的 `contentInsetAdjustmentBehavior`。

横向分页 adapter 的区域默认延伸到容器 `bounds` 底部，也就是在全屏容器中延伸到物理屏幕最底部。bottom safe area、tab bar 和 toolbar 仍会被转换为 managed inset target；v0.2 只计算和记录该目标值，不用它裁剪横向区域，也不写入 child scroll view。

当 Header 内容高度或配置运行时变化时，调用：

```swift
pager.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
```

四种 offset 策略：

- `.preserveVisualPosition`：尽量保持当前可见 Header 高度。
- `.preserveCollapseProgress`：按旧折叠进度迁移到新高度范围。
- `.resetToExpanded`：回到展开位置。
- `.resetToCollapsed`：移动到当前折叠上限。

v0.2 会计算 Header、分段栏、内容 frame 和容器级 managed inset 目标值，并接管 AnchorPager 自有主容器与内部 fallback scroll host 的自动 inset 策略；尚不写入接入方 child scroll view 的 managed content inset。完整 child inset ownership 属于 v0.3。

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

## 无 UIScrollView Child

```swift
final class PlainPageViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }
}
```

无候选 `UIScrollView` 时，AnchorPager 会先使用内部 fallback scroll host 包装普通 child，再交给横向分页 adapter。fallback host 会禁用 UIKit 自动 content inset，并让普通 child 至少覆盖页面 viewport，因此无 scroll view 页面也会延伸到横向内容区域底部。

## 示例工程

仓库包含 `Examples/AnchorPagerExample.xcodeproj`，用于验证示例 App 能接入本地 `AnchorPager` package、以 `UITabBarController` 作为 window root、首屏直接显示 AnchorPager 示例页，并可通过导航按钮 push 另一个 AnchorPager 示例页来验证 `hidesBottomBarWhenPushed` 隐藏 tab bar。示例页通过 public API 提供 Header、分段栏、显式 scroll view child 和无 scroll view child。当前示例工程可构建，并已有基础启动、root tab bar、导航按钮 push 后隐藏 tab bar、Header/分段栏/页面内容可视、分段栏点击切页、横向滑动切页和 public API 切页 UI test。

```bash
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## 日志

AnchorPager 通过内部 `AnchorPagerLogger` 使用 `os.Logger` 输出关键事件，subsystem 为 `com.anchorpager.AnchorPager`。`AnchorPagerLogger.log` 可从非主线程内部路径调用；测试用 sink 会回到 MainActor 记录事件。当前 category 包括 `lifecycle`、`layout`、`header`、`paging`、`children`、`scroll`、`inset`、`overscroll`、`gesture`、`accessibility`、`resource`。

v0.2 布局日志包括 Header 高度解析、Header frame、bar frame、safe area、bounds 和 managed inset 目标值变化。日志只在状态变化时输出，避免普通布局 pass 或滚动热路径产生重复噪声。

建议使用 Console.app 或 `log stream` 按 subsystem/category 过滤：

```bash
log stream --predicate 'subsystem == "com.anchorpager.AnchorPager"'
```

日志只记录状态变化、边界事件和降级路径，不输出业务数据、用户内容或完整 view 层级。

## 当前限制

v0.2 当前已交付基础 Header/分段栏/页面内容显示路径、确认后提交的程序化切页、Header 重复安装幂等处理、Header 高度解析、safe area/top behavior、`reloadHeaderLayout(offsetAdjustment:)` 和布局日志。完整纵向嵌套滚动协调、child managed inset ownership、顶部 overscroll owner、状态栏点击顶滚、尺寸变化恢复、page cache window 和 Tabman 驱动的 appearance lifecycle 语义仍在后续版本。Tabman/Pageboy 仅出现在 internal adapter 层，Public API 不暴露第三方类型。
