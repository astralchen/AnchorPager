import UIKit

@MainActor
final class AnchorPagerHeaderViewHost {
    let view = UIView()

    private weak var parentViewController: UIViewController?
    private var currentView: UIView?
    private var currentViewController: UIViewController?

    init() {
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    func install(_ content: AnchorPagerHeaderContent, in parentViewController: UIViewController) {
        self.parentViewController = parentViewController
        installHostViewIfNeeded(in: parentViewController.view)
        removeContent(keepHostView: true)

        switch content {
        case let .view(headerView):
            installHeaderView(headerView)
            AnchorPagerLogger.log(.info, category: .header, event: "header.view.install")
        case let .viewController(headerViewController):
            parentViewController.addChild(headerViewController)
            installHeaderView(headerViewController.view)
            headerViewController.didMove(toParent: parentViewController)
            currentViewController = headerViewController
            AnchorPagerLogger.log(.info, category: .header, event: "header.controller.add")
            AnchorPagerLogger.log(.info, category: .lifecycle, event: "header.controller.didMove")
        }
    }

    func remove() {
        removeContent(keepHostView: false)
    }

    func measure(in size: CGSize) -> CGFloat {
        let measuredHeight = measuredContentHeight(in: size)
        let height = measuredHeight.isFinite ? max(0, measuredHeight) : 0
        if measuredHeight < 0 || !measuredHeight.isFinite {
            AnchorPagerAssertions.failure("AnchorPager header measured an invalid height.")
        }
        AnchorPagerLogger.log(.debug, category: .layout, event: "header.measure")
        return height
    }

    private func installHostViewIfNeeded(in parentView: UIView) {
        guard view.superview == nil else { return }

        parentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            view.topAnchor.constraint(equalTo: parentView.topAnchor)
        ])
    }

    private func installHeaderView(_ headerView: UIView) {
        currentView = headerView
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func removeContent(keepHostView: Bool) {
        if let currentViewController {
            currentViewController.willMove(toParent: nil)
            currentViewController.view.removeFromSuperview()
            currentViewController.removeFromParent()
            AnchorPagerLogger.log(.info, category: .header, event: "header.controller.remove")
            AnchorPagerLogger.log(.info, category: .lifecycle, event: "header.controller.removeFromParent")
        } else {
            currentView?.removeFromSuperview()
        }

        currentView = nil
        currentViewController = nil

        if !keepHostView {
            view.removeFromSuperview()
            parentViewController = nil
        }
    }

    private func measuredContentHeight(in size: CGSize) -> CGFloat {
        if let preferredHeight = currentViewController?.preferredContentSize.height,
           preferredHeight > 0 {
            return preferredHeight
        }

        guard let currentView else { return 0 }

        let fittingSize = currentView.systemLayoutSizeFitting(
            CGSize(width: size.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if fittingSize.height > 0 {
            return fittingSize.height
        }

        if currentView.bounds.height > 0 {
            return currentView.bounds.height
        }

        let intrinsicHeight = currentView.intrinsicContentSize.height
        if intrinsicHeight > 0, intrinsicHeight != UIView.noIntrinsicMetric {
            return intrinsicHeight
        }

        return 0
    }
}
