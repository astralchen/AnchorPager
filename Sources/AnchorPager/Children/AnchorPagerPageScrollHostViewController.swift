import UIKit

@MainActor
final class AnchorPagerPageScrollHostViewController: UIViewController {
    let scrollView = UIScrollView()

    private let contentViewController: UIViewController

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
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installContentViewControllerIfNeeded()
    }

    private func installContentViewControllerIfNeeded() {
        guard contentViewController.parent !== self else { return }

        addChild(contentViewController)
        let contentView = contentViewController.view!
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        contentViewController.didMove(toParent: self)
    }
}
