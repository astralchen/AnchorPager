import UIKit

/// UIKit 嵌套分页容器入口。
@MainActor
open class AnchorPagerViewController: UIViewController {
    /// 提供页面、标题和 Header 内容的数据源。
    public weak var dataSource: AnchorPagerViewControllerDataSource?

    /// 接收页面选择、Header 折叠和布局更新事件的代理。
    public weak var delegate: AnchorPagerViewControllerDelegate?

    /// 容器配置。
    public var configuration: AnchorPagerConfiguration

    /// 当前选中索引。空页时保持 0。
    public private(set) var selectedIndex: Int = 0

    /// 当前有效选中索引。空页时为 nil。
    public var effectiveSelectedIndex: Int? {
        pageCount > 0 ? selectedIndex : nil
    }

    /// AnchorPager 管理的纵向容器滚动视图。
    public let verticalScrollView = UIScrollView()

    private let contentView = UIView()
    private let headerViewHost = AnchorPagerHeaderViewHost()
    private let pagingAdapter = AnchorPagerPagingAdapter()
    private var headerHeightConstraint: NSLayoutConstraint?
    private var pagingHeightConstraint: NSLayoutConstraint?
    private var currentHeaderContent: AnchorPagerHeaderContent?
    private var currentTitles: [String] = []
    private var currentViewControllers: [UIViewController] = []
    private var fallbackPageHosts: [ObjectIdentifier: AnchorPagerPageScrollHostViewController] = [:]
    private var pageCount = 0

    /// 创建 AnchorPager 容器。
    public init(configuration: AnchorPagerConfiguration = .default) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        configurePagingAdapter()
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "init")
    }

    /// 从 storyboard 或 nib 创建 AnchorPager 容器。
    public required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        configurePagingAdapter()
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "init")
    }

    deinit {
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "deinit")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        installVerticalScrollViewIfNeeded()
        reloadVisibleContentIfNeeded()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateVisibleLayout()
    }

    /// 重新加载页面、标题和 Header 数据。
    public func reloadData() {
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "reloadData.begin")

        let requestedCount = dataSource?.numberOfViewControllers(in: self) ?? 0
        if requestedCount < 0 {
            AnchorPagerAssertions.failure("AnchorPager page count must not be negative.")
            pageCount = 0
        } else {
            pageCount = requestedCount
        }

        if pageCount == 0 {
            selectedIndex = 0
            currentTitles = []
            currentViewControllers = []
        } else if selectedIndex >= pageCount {
            selectedIndex = pageCount - 1
        }

        currentHeaderContent = dataSource?.headerContent(in: self)
        currentTitles = (0..<pageCount).map { index in
            dataSource?.pagerViewController(self, titleForViewControllerAt: index) ?? ""
        }
        var activeFallbackHostIdentifiers = Set<ObjectIdentifier>()
        currentViewControllers = (0..<pageCount).map { index in
            pageViewController(
                for: dataSource?.pagerViewController(self, viewControllerAt: index) ?? UIViewController(),
                activeFallbackHostIdentifiers: &activeFallbackHostIdentifiers
            )
        }
        let staleFallbackHosts = removeStaleFallbackPageHosts(
            keeping: activeFallbackHostIdentifiers
        )

        reloadVisibleContentIfNeeded()
        staleFallbackHosts.forEach { $0.removeContentForReloadData() }
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "reloadData.end")
    }

    /// 设置当前选中页面。
    public func setSelectedIndex(_ selectedIndex: Int, animated: Bool) {
        AnchorPagerLogger.log(.info, category: .paging, event: "setSelectedIndex.request")

        guard selectedIndex >= 0, selectedIndex < pageCount else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "setSelectedIndex.outOfRange")
            AnchorPagerAssertions.failure("AnchorPager selectedIndex is out of range.")
            return
        }

        self.selectedIndex = selectedIndex
        AnchorPagerLogger.log(.info, category: .paging, event: "setSelectedIndex.commit")
        delegate?.pagerViewController(self, didSelectViewControllerAt: selectedIndex)
        pagingAdapter.setSelectedIndex(selectedIndex, animated: animated)
    }

    /// 重新测量并布局 Header。
    public func reloadHeaderLayout(
        offsetAdjustment: AnchorPagerHeaderOffsetAdjustment = .preserveVisualPosition
    ) {
        AnchorPagerLogger.log(.info, category: .layout, event: "reloadHeaderLayout")
    }

    private func installVerticalScrollViewIfNeeded() {
        guard verticalScrollView.superview == nil else { return }

        verticalScrollView.alwaysBounceVertical = true
        verticalScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(verticalScrollView)
        NSLayoutConstraint.activate([
            verticalScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            verticalScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            verticalScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            verticalScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentView.translatesAutoresizingMaskIntoConstraints = false
        verticalScrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func configurePagingAdapter() {
        pagingAdapter.eventDelegate = self
    }

    private func reloadVisibleContentIfNeeded() {
        guard isViewLoaded else { return }

        installVerticalScrollViewIfNeeded()
        installHeaderHost()
        installPagingAdapterIfNeeded()
        updateVisibleLayout()
        pagingAdapter.reload(
            titles: currentTitles,
            viewControllers: currentViewControllers,
            selectedIndex: selectedIndex
        )
    }

    private func installHeaderHost() {
        let headerContent = currentHeaderContent ?? .view(UIView())
        headerViewHost.install(headerContent, in: self, hostParentView: contentView)

        if headerHeightConstraint == nil {
            let headerHeightConstraint = headerViewHost.view.heightAnchor.constraint(equalToConstant: 0)
            headerHeightConstraint.isActive = true
            self.headerHeightConstraint = headerHeightConstraint
        }
    }

    private func installPagingAdapterIfNeeded() {
        let didAddPagingAdapter = pagingAdapter.parent == nil
        if pagingAdapter.parent == nil {
            addChild(pagingAdapter)
        }

        if pagingAdapter.view.superview == nil {
            let adapterView = pagingAdapter.view!
            adapterView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(adapterView)
            NSLayoutConstraint.activate([
                adapterView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                adapterView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                adapterView.topAnchor.constraint(equalTo: headerViewHost.view.bottomAnchor),
                adapterView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])

            let pagingHeightConstraint = adapterView.heightAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.heightAnchor)
            pagingHeightConstraint.isActive = true
            self.pagingHeightConstraint = pagingHeightConstraint
        }

        if didAddPagingAdapter {
            pagingAdapter.didMove(toParent: self)
        }
    }

    private func updateVisibleLayout() {
        guard isViewLoaded, headerViewHost.view.superview != nil else { return }

        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let measuredHeight = headerViewHost.measure(
            in: CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        )
        headerHeightConstraint?.constant = resolvedHeaderHeight(for: measuredHeight)
        pagingHeightConstraint?.isActive = true
    }

    private func resolvedHeaderHeight(for measuredHeight: CGFloat) -> CGFloat {
        switch configuration.header.heightMode {
        case let .automatic(min, max):
            let lowerBounded = Swift.max(min, measuredHeight)
            guard let max else { return lowerBounded }
            return Swift.min(max, lowerBounded)
        case let .fixed(max, min):
            return Swift.max(min, max)
        case let .ranged(min, max):
            return Swift.min(max, Swift.max(min, measuredHeight))
        }
    }

    private func commitSelectedIndex(_ index: Int, animated: Bool) {
        guard index != selectedIndex else { return }

        selectedIndex = index
        AnchorPagerLogger.log(.info, category: .paging, event: "setSelectedIndex.commit")
        delegate?.pagerViewController(self, didSelectViewControllerAt: index)
    }

    private func pageViewController(
        for childViewController: UIViewController,
        activeFallbackHostIdentifiers: inout Set<ObjectIdentifier>
    ) -> UIViewController {
        if childViewController is AnchorPagerPageScrollHostViewController {
            return childViewController
        }

        childViewController.loadViewIfNeeded()
        if childViewController.anchorPagerScrollView != nil {
            return childViewController
        }

        let childIdentifier = ObjectIdentifier(childViewController)
        activeFallbackHostIdentifiers.insert(childIdentifier)

        if let existingHost = fallbackPageHosts[childIdentifier] {
            return existingHost
        }

        let fallbackHost = AnchorPagerPageScrollHostViewController(
            contentViewController: childViewController
        )
        fallbackPageHosts[childIdentifier] = fallbackHost
        return fallbackHost
    }

    private func removeStaleFallbackPageHosts(
        keeping activeFallbackHostIdentifiers: Set<ObjectIdentifier>
    ) -> [AnchorPagerPageScrollHostViewController] {
        let staleIdentifiers = fallbackPageHosts.keys.filter {
            !activeFallbackHostIdentifiers.contains($0)
        }

        return staleIdentifiers.compactMap { identifier in
            fallbackPageHosts.removeValue(forKey: identifier)
        }
    }
}

extension AnchorPagerViewController: AnchorPagerPagingAdapterDelegate {
    func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, willSelect index: Int, animated: Bool) {}

    func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, didSelect index: Int, animated: Bool) {
        guard index >= 0, index < pageCount else { return }
        commitSelectedIndex(index, animated: animated)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    ) {}
}
