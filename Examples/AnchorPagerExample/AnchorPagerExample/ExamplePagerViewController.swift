import AnchorPager
import UIKit

final class ExamplePagerViewController: UIViewController {
    private let pagerViewController = AnchorPagerViewController()
    private var headerTopBehaviorItem: UIBarButtonItem?
    private let pages: [UIViewController] = [
        ExampleScrollPageViewController(title: "无内容页", rows: 0),
        ExampleScrollPageViewController(title: "短页", rows: 6),
        ExampleScrollPageViewController(title: "长页", rows: 30),
        ExamplePlainPageViewController(title: "无滚动页")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "AnchorPager"
        view.backgroundColor = .systemBackground
        installNavigationItem()
        installPager()
    }

    private func installNavigationItem() {
        let pushItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.right.circle"),
            style: .plain,
            target: self,
            action: #selector(pushAnchorPagerExample)
        )
        pushItem.accessibilityLabel = "打开 AnchorPager"

        let headerTopBehaviorItem = makeHeaderTopBehaviorItem()
        self.headerTopBehaviorItem = headerTopBehaviorItem
        navigationItem.rightBarButtonItems = [pushItem, headerTopBehaviorItem]
    }

    @objc private func pushAnchorPagerExample() {
        let viewController = ExamplePagerViewController()
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func makeHeaderTopBehaviorItem() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            title: title(for: pagerViewController.configuration.header.topBehavior),
            image: nil,
            primaryAction: nil,
            menu: makeHeaderTopBehaviorMenu()
        )
        item.accessibilityLabel = "Header 顶部行为"
        item.accessibilityValue = title(for: pagerViewController.configuration.header.topBehavior)
        return item
    }

    private func makeHeaderTopBehaviorMenu() -> UIMenu {
        let current = pagerViewController.configuration.header.topBehavior
        return UIMenu(
            title: "Header 顶部行为",
            children: [
                UIAction(
                    title: title(for: .insideSafeArea),
                    state: current == .insideSafeArea ? .on : .off
                ) { [weak self] _ in
                    self?.setHeaderTopBehavior(.insideSafeArea)
                },
                UIAction(
                    title: title(for: .extendsUnderTopSafeArea),
                    state: current == .extendsUnderTopSafeArea ? .on : .off
                ) { [weak self] _ in
                    self?.setHeaderTopBehavior(.extendsUnderTopSafeArea)
                }
            ]
        )
    }

    private func setHeaderTopBehavior(_ behavior: AnchorPagerHeaderTopBehavior) {
        guard pagerViewController.configuration.header.topBehavior != behavior else { return }

        pagerViewController.configuration.header.topBehavior = behavior
        pagerViewController.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        updateHeaderTopBehaviorItem()
    }

    private func updateHeaderTopBehaviorItem() {
        let currentTitle = title(for: pagerViewController.configuration.header.topBehavior)
        headerTopBehaviorItem?.title = currentTitle
        headerTopBehaviorItem?.accessibilityValue = currentTitle
        headerTopBehaviorItem?.menu = makeHeaderTopBehaviorMenu()
    }

    private func title(for behavior: AnchorPagerHeaderTopBehavior) -> String {
        switch behavior {
        case .insideSafeArea:
            "安全区内"
        case .extendsUnderTopSafeArea:
            "延伸到顶部"
        }
    }

    private func installPager() {
        pagerViewController.dataSource = self
        pagerViewController.delegate = self

        addChild(pagerViewController)
        pagerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pagerViewController.view)
        NSLayoutConstraint.activate([
            pagerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pagerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pagerViewController.didMove(toParent: self)

        pagerViewController.reloadData()
        pagerViewController.setSelectedIndex(initialSelectedIndex(), animated: false)
    }

    private func initialSelectedIndex() -> Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard let argumentIndex = arguments.firstIndex(of: "--anchorPagerInitialIndex"),
              arguments.indices.contains(argumentIndex + 1),
              let requestedIndex = Int(arguments[argumentIndex + 1]) else {
            return 1
        }
        return min(max(0, requestedIndex), pages.count - 1)
    }
}

extension ExamplePagerViewController: AnchorPagerViewControllerDataSource {
    func numberOfViewControllers(in pagerViewController: AnchorPagerViewController) -> Int {
        pages.count
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        titleForViewControllerAt index: Int
    ) -> String {
        pages[index].title ?? "无标题"
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        viewControllerAt index: Int
    ) -> UIViewController {
        pages[index]
    }

    func headerContent(in pagerViewController: AnchorPagerViewController) -> AnchorPagerHeaderContent {
        .view(ExampleHeaderView())
    }
}

extension ExamplePagerViewController: AnchorPagerViewControllerDelegate {
    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didSelectViewControllerAt index: Int
    ) {}

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateHeaderCollapseProgress progress: CGFloat
    ) {}

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateLayout context: AnchorPagerLayoutContext
    ) {}
}

private final class ExampleHeaderView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .systemBlue

        let titleLabel = UILabel()
        titleLabel.text = "AnchorPager Example"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = .white

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Header UIView、显式 scroll view、无 scroll view child"
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .white
        subtitleLabel.numberOfLines = 0

        let stackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
}

private final class ExampleScrollPageViewController: UIViewController {
    private let pageTitle: String
    private let rows: Int
    private let scrollView = UIScrollView()

    init(title: String, rows: Int) {
        self.pageTitle = title
        self.rows = rows
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        anchorPagerScrollView = scrollView
        installScrollView()
    }

    private func installScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        for row in 0..<rows {
            let label = UILabel()
            label.text = "\(pageTitle) - \(row + 1)"
            label.font = .preferredFont(forTextStyle: .body)
            label.textColor = .label
            label.backgroundColor = .secondarySystemBackground
            label.layer.cornerRadius = 6
            label.layer.masksToBounds = true
            stackView.addArrangedSubview(label)
            label.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }
}

private final class ExamplePlainPageViewController: UIViewController {
    private let pageTitle: String

    init(title: String) {
        self.pageTitle = title
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .tertiarySystemBackground

        let label = UILabel()
        label.text = pageTitle
        label.font = .preferredFont(forTextStyle: .title3)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
