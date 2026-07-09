import UIKit

/// AnchorPager 的数据源。
@MainActor
public protocol AnchorPagerViewControllerDataSource: AnyObject {
    /// 返回页面数量。
    func numberOfViewControllers(in pagerViewController: AnchorPagerViewController) -> Int

    /// 返回指定页面标题。
    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        titleForViewControllerAt index: Int
    ) -> String

    /// 返回指定页面控制器。
    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        viewControllerAt index: Int
    ) -> UIViewController

    /// 返回 Header 内容。
    func headerContent(in pagerViewController: AnchorPagerViewController) -> AnchorPagerHeaderContent
}

/// AnchorPager 的事件代理。
@MainActor
public protocol AnchorPagerViewControllerDelegate: AnyObject {
    /// 页面选中后调用。
    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didSelectViewControllerAt index: Int
    )

    /// Header 折叠进度变化后调用。
    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateHeaderCollapseProgress progress: CGFloat
    )

    /// 布局结果更新后调用。
    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateLayout context: AnchorPagerLayoutContext
    )
}

/// Header 内容来源。
@MainActor
public enum AnchorPagerHeaderContent {
    /// 使用 UIView 作为 Header。
    case view(UIView)

    /// 使用 UIViewController 作为 Header。
    case viewController(UIViewController)
}
