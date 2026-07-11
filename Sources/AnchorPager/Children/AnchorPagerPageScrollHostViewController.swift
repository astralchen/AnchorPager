import UIKit

@MainActor
final class AnchorPagerPageScrollHostViewController: UIViewController {
    let scrollView = UIScrollView()

    private let contentViewController: UIViewController
    private var contentMinimumHeightConstraint: NSLayoutConstraint?

    init(contentViewController: UIViewController) {
        self.contentViewController = contentViewController
        super.init(nibName: nil, bundle: nil)
        AnchorPagerLogger.log(.info, category: .scroll, event: "fallbackHost.create")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installContentViewControllerIfNeeded()
    }

    func removeContentForReloadData() {
        guard contentViewController.parent === self else { return }

        contentViewController.willMove(toParent: nil)
        contentViewController.view.removeFromSuperview()
        contentViewController.removeFromParent()
        AnchorPagerLogger.log(.info, category: .children, event: "reloadData.child.remove")
    }

    func setManagedContentInsets(_ insets: UIEdgeInsets) {
        let top = insets.top.isFinite ? Swift.max(0, insets.top) : 0
        let bottom = insets.bottom.isFinite ? Swift.max(0, insets.bottom) : 0
        contentMinimumHeightConstraint?.constant = -(top + bottom)
    }

    private func installContentViewControllerIfNeeded() {
        guard contentViewController.parent !== self else { return }

        addChild(contentViewController)
        let contentView = contentViewController.view!
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        let contentMinimumHeightConstraint = contentView.heightAnchor.constraint(
            greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor
        )
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentMinimumHeightConstraint
        ])
        self.contentMinimumHeightConstraint = contentMinimumHeightConstraint
        contentViewController.didMove(toParent: self)
    }
}
