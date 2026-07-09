import UIKit

/// 独立 child containment 工具。横向 page 的实际 containment 由 Tabman/Pageboy adapter 执行，不能对同一个 page view controller 重复使用本类型接管。
@MainActor
final class AnchorPagerChildViewControllerStore {
    let view = UIView()

    private weak var parentViewController: UIViewController?
    private var viewControllers: [UIViewController] = []

    init() {
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    func setViewControllers(
        _ viewControllers: [UIViewController],
        in parentViewController: UIViewController
    ) {
        self.parentViewController = parentViewController
        installHostViewIfNeeded(in: parentViewController.view)
        removeInstalledChildren(keepHostView: true)

        self.viewControllers = viewControllers
        for childViewController in viewControllers {
            parentViewController.addChild(childViewController)
            installChildView(childViewController.view)
            childViewController.didMove(toParent: parentViewController)
            AnchorPagerLogger.log(.info, category: .children, event: "child.add")
        }
    }

    func viewController(at index: Int) -> UIViewController? {
        guard viewControllers.indices.contains(index) else { return nil }
        return viewControllers[index]
    }

    func removeAll() {
        removeInstalledChildren(keepHostView: false)
    }

    private func installHostViewIfNeeded(in parentView: UIView) {
        guard view.superview == nil else { return }

        parentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            view.topAnchor.constraint(equalTo: parentView.topAnchor),
            view.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
    }

    private func installChildView(_ childView: UIView) {
        childView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(childView)
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            childView.topAnchor.constraint(equalTo: view.topAnchor),
            childView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func removeInstalledChildren(keepHostView: Bool) {
        for childViewController in viewControllers {
            childViewController.willMove(toParent: nil)
            childViewController.view.removeFromSuperview()
            childViewController.removeFromParent()
            AnchorPagerLogger.log(.info, category: .children, event: "child.remove")
        }

        viewControllers.removeAll()

        if !keepHostView {
            view.removeFromSuperview()
            parentViewController = nil
        }
    }
}
