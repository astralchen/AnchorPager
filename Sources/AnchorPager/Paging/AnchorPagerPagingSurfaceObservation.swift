import UIKit

/// 观察 Pageboy 通过公开 UIKit containment 暴露的分页手势表面。
///
/// 该类型只持有 target-action，不接管第三方或业务滚动视图的 delegate 与回弹配置。
@MainActor
final class AnchorPagerPagingSurfaceObservation: NSObject {
    struct Surface {
        let pageViewController: UIPageViewController
        let scrollView: UIScrollView
        let panGestureRecognizer: UIPanGestureRecognizer
    }

    typealias TargetAction = (UIGestureRecognizer, Any?, Selector) -> Void

    var onSurfaceChanged: ((Surface?) -> Void)?
    var onPanStateChanged: ((UIGestureRecognizer.State) -> Void)?

    private(set) var surface: Surface?

    private let addTarget: TargetAction
    private let removeTarget: TargetAction

    init(
        addTarget: @escaping TargetAction = { recognizer, target, action in
            recognizer.addTarget(target as Any, action: action)
        },
        removeTarget: @escaping TargetAction = { recognizer, target, action in
            recognizer.removeTarget(target, action: action)
        }
    ) {
        self.addTarget = addTarget
        self.removeTarget = removeTarget
        super.init()
    }

    deinit {
        MainActor.assumeIsolated {
            unbindCurrentSurface(shouldNotify: false)
        }
    }

    func refresh(in rootViewController: UIViewController) {
        let nextSurface = discoverSurface(in: rootViewController)
        if isSameSurface(surface, nextSurface) {
            return
        }

        unbindCurrentSurface(shouldNotify: false)

        guard let nextSurface else {
            onSurfaceChanged?(nil)
            return
        }
        addTarget(
            nextSurface.panGestureRecognizer,
            self,
            #selector(handlePan(_:))
        )
        surface = nextSurface
        AnchorPagerLogger.log(
            .debug,
            category: .paging,
            event: "paging.surface.bind"
        )
        onSurfaceChanged?(nextSurface)
    }

    func invalidate() {
        guard surface != nil else { return }
        unbindCurrentSurface(shouldNotify: true)
    }

    @objc private func handlePan(_ panGestureRecognizer: UIPanGestureRecognizer) {
        guard surface?.panGestureRecognizer === panGestureRecognizer else { return }
        onPanStateChanged?(panGestureRecognizer.state)
    }

    private func unbindCurrentSurface(shouldNotify: Bool) {
        guard let surface else { return }
        removeTarget(
            surface.panGestureRecognizer,
            self,
            #selector(handlePan(_:))
        )
        self.surface = nil
        AnchorPagerLogger.log(
            .debug,
            category: .paging,
            event: "paging.surface.unbind"
        )
        if shouldNotify {
            onSurfaceChanged?(nil)
        }
    }

    private func discoverSurface(
        in rootViewController: UIViewController
    ) -> Surface? {
        guard let pageViewController = nearestContainedPageViewController(
            in: rootViewController
        ), pageViewController.isViewLoaded,
        let scrollView = shallowestScrollView(in: pageViewController.view) else {
            return nil
        }

        return Surface(
            pageViewController: pageViewController,
            scrollView: scrollView,
            panGestureRecognizer: scrollView.panGestureRecognizer
        )
    }

    private func nearestContainedPageViewController(
        in rootViewController: UIViewController
    ) -> UIPageViewController? {
        var pendingViewControllers = rootViewController.children
        var nextIndex = 0
        while nextIndex < pendingViewControllers.count {
            let candidate = pendingViewControllers[nextIndex]
            nextIndex += 1
            if let pageViewController = candidate as? UIPageViewController {
                return pageViewController
            }
            pendingViewControllers.append(contentsOf: candidate.children)
        }
        return nil
    }

    private func shallowestScrollView(in rootView: UIView) -> UIScrollView? {
        var pendingViews = rootView.subviews
        var nextIndex = 0
        while nextIndex < pendingViews.count {
            let candidate = pendingViews[nextIndex]
            nextIndex += 1
            if let scrollView = candidate as? UIScrollView {
                return scrollView
            }
            pendingViews.append(contentsOf: candidate.subviews)
        }
        return nil
    }

    private func isSameSurface(_ lhs: Surface?, _ rhs: Surface?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.pageViewController === rhs.pageViewController
                && lhs.scrollView === rhs.scrollView
                && lhs.panGestureRecognizer === rhs.panGestureRecognizer
        default:
            return false
        }
    }
}
