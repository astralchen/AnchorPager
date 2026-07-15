import UIKit

@MainActor
final class AnchorPagerHeaderViewHost {
    let view = UIView()

    private weak var parentViewController: UIViewController?
    private var currentView: UIView?
    private var currentViewController: UIViewController?
    private var topConstraint: NSLayoutConstraint?

    init() {
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    @discardableResult
    func install(
        _ content: AnchorPagerHeaderContent,
        in parentViewController: UIViewController,
        hostParentView: UIView? = nil,
        bootstrapMeasurementSize: CGSize,
        prepareHostForContent: (CGFloat) -> Void
    ) -> Bool {
        self.parentViewController = parentViewController
        installHostViewIfNeeded(in: hostParentView ?? parentViewController.view)
        guard !isDisplaying(content) else {
            AnchorPagerLogger.log(.debug, category: .header, event: "header.install.noop")
            return false
        }
        removeContent(keepHostView: true)

        switch content {
        case let .view(headerView):
            prepareHostForContent(
                bootstrapMeasurement(
                    for: headerView,
                    preferredHeight: nil,
                    in: bootstrapMeasurementSize
                )
            )
            installHeaderView(headerView)
            AnchorPagerLogger.log(.info, category: .header, event: "header.view.install")
        case let .viewController(headerViewController):
            parentViewController.addChild(headerViewController)
            let headerView = headerViewController.view!
            prepareHostForContent(
                bootstrapMeasurement(
                    for: headerView,
                    preferredHeight: headerViewController.preferredContentSize.height,
                    in: bootstrapMeasurementSize
                )
            )
            installHeaderView(headerView)
            headerViewController.didMove(toParent: parentViewController)
            currentViewController = headerViewController
            AnchorPagerLogger.log(.info, category: .header, event: "header.controller.add")
            AnchorPagerLogger.log(.info, category: .lifecycle, event: "header.controller.didMove")
        }
        return true
    }

    func remove() {
        removeContent(keepHostView: false)
    }

    func setTopOffset(_ offset: CGFloat) {
        topConstraint?.constant = offset
    }

    func measure(in size: CGSize) -> CGFloat {
        let measuredHeight = measuredContentHeight(in: size)
        if isInvalidMeasuredHeight(measuredHeight) {
            AnchorPagerAssertions.failure("AnchorPager header measured an invalid height.")
            AnchorPagerLogger.log(.error, category: .layout, event: "header.measure.invalid")
            return 0
        }

        let height = max(0, measuredHeight)
        AnchorPagerLogger.log(.debug, category: .layout, event: "header.measure")
        return height
    }

    func bootstrapMeasurement(in size: CGSize) -> CGFloat {
        let measuredHeight = measuredContentHeight(in: size)
        guard !isInvalidMeasuredHeight(measuredHeight) else { return 0 }
        return max(0, measuredHeight)
    }

    private func bootstrapMeasurement(
        for headerView: UIView,
        preferredHeight: CGFloat?,
        in size: CGSize
    ) -> CGFloat {
        let measuredHeight = measuredContentHeight(
            for: headerView,
            preferredHeight: preferredHeight,
            in: size
        )
        guard !isInvalidMeasuredHeight(measuredHeight) else { return 0 }
        return max(0, measuredHeight)
    }

    private func installHostViewIfNeeded(in parentView: UIView) {
        guard view.superview !== parentView else { return }

        view.removeFromSuperview()
        parentView.addSubview(view)
        let topConstraint = view.topAnchor.constraint(equalTo: parentView.topAnchor)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            topConstraint
        ])
        self.topConstraint = topConstraint
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

    private func isDisplaying(_ content: AnchorPagerHeaderContent) -> Bool {
        switch content {
        case let .view(headerView):
            return currentView === headerView && currentViewController == nil && headerView.superview === view
        case let .viewController(headerViewController):
            return currentViewController === headerViewController
                && currentView === headerViewController.view
                && headerViewController.parent === parentViewController
                && headerViewController.view.superview === view
        }
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
            topConstraint = nil
            parentViewController = nil
        }
    }

    private func measuredContentHeight(in size: CGSize) -> CGFloat {
        measuredContentHeight(
            for: currentView,
            preferredHeight: currentViewController?.preferredContentSize.height,
            in: size
        )
    }

    private func measuredContentHeight(
        for headerView: UIView?,
        preferredHeight: CGFloat?,
        in size: CGSize
    ) -> CGFloat {
        if let preferredHeight,
           preferredHeight > 0 {
            return preferredHeight
        }
        if let preferredHeight,
           isInvalidMeasuredHeight(preferredHeight) {
            return preferredHeight
        }

        guard let headerView else { return 0 }

        let fittingSize = headerView.systemLayoutSizeFitting(
            CGSize(width: size.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if fittingSize.height > 0 {
            return fittingSize.height
        }
        if isInvalidMeasuredHeight(fittingSize.height) {
            return fittingSize.height
        }

        if headerView.bounds.height > 0 {
            return headerView.bounds.height
        }
        if isInvalidMeasuredHeight(headerView.bounds.height) {
            return headerView.bounds.height
        }

        let intrinsicHeight = headerView.intrinsicContentSize.height
        if intrinsicHeight > 0, intrinsicHeight != UIView.noIntrinsicMetric {
            return intrinsicHeight
        }
        if intrinsicHeight != UIView.noIntrinsicMetric,
           isInvalidMeasuredHeight(intrinsicHeight) {
            return intrinsicHeight
        }

        return 0
    }

    private func isInvalidMeasuredHeight(_ height: CGFloat) -> Bool {
        height < 0 || !height.isFinite
    }
}
