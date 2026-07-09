# AnchorPager

AnchorPager 是一个 UIKit 容器框架，用于组合可变 Header、吸顶分段栏、多页面横向分页和 child scroll view 接入。当前仓库处于 v0.1 foundation 阶段，已建立 Swift Package、Public API skeleton、日志门面、Header/Child 基础承载、scroll view discovery 以及 Tabman/Pageboy internal adapter 边界。

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

v0.1 foundation 已提供内部 fallback scroll host 类型；完整自动接入会在后续页面装配流程中继续收敛。

## 日志

AnchorPager 通过内部 `AnchorPagerLogger` 使用 `os.Logger` 输出关键事件，subsystem 为 `com.anchorpager.AnchorPager`。当前 category 包括 `lifecycle`、`layout`、`header`、`paging`、`children`、`scroll`、`inset`、`overscroll`、`gesture`、`accessibility`、`resource`。

建议使用 Console.app 或 `log stream` 按 subsystem/category 过滤：

```bash
log stream --predicate 'subsystem == "com.anchorpager.AnchorPager"'
```

日志只记录状态变化、边界事件和降级路径，不输出业务数据、用户内容或完整 view 层级。

## 当前限制

v0.1 foundation 尚未交付完整示例工程、完整纵向嵌套滚动协调、顶部 overscroll owner、状态栏点击顶滚和尺寸变化恢复。Tabman/Pageboy 仅出现在 internal adapter 层，Public API 不暴露第三方类型。
