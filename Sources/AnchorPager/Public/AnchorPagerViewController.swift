import UIKit

/// UIKit 嵌套分页容器入口。
@MainActor
open class AnchorPagerViewController: UIViewController {
    @MainActor
    private final class VerticalScrollDelegate: NSObject, UIScrollViewDelegate {
        weak var owner: AnchorPagerViewController?

        init(owner: AnchorPagerViewController) {
            self.owner = owner
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let owner,
                  scrollView === owner.verticalScrollView else { return }
            owner.updateVisibleLayoutForScrolling()
        }
    }

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
    ///
    /// 该滚动视图的 delegate 由 AnchorPager 内部管理，调用方不得替换。
    public let verticalScrollView = UIScrollView()

    private let scrollRangeView = UIView()
    private let viewportView = UIView()
    private let headerViewHost = AnchorPagerHeaderViewHost()
    private let layoutEngine = AnchorPagerLayoutEngine()
    private let pagingAdapter = AnchorPagerPagingAdapter()
    private let managedInsetCoordinator = AnchorPagerManagedInsetCoordinator()
    private var scrollRangeHeightConstraint: NSLayoutConstraint?
    private var headerHeightConstraint: NSLayoutConstraint?
    private var pagingTopConstraint: NSLayoutConstraint?
    private var pagingHeightConstraint: NSLayoutConstraint?
    private var lastMeasuredHeaderHeight: CGFloat?
    private var isApplyingLayout = false
    private lazy var verticalScrollDelegate = VerticalScrollDelegate(owner: self)
    private var currentHeaderContent: AnchorPagerHeaderContent?
    private var currentTitles: [String] = []
    private var currentViewControllers: [UIViewController] = []
    private var activePageScrollViews: [UIScrollView] = []
    private var fallbackPageHosts: [ObjectIdentifier: AnchorPagerPageScrollHostViewController] = [:]
    private var resolvedBarInsets: UIEdgeInsets = .zero
    private var lastManagedInsetTarget: AnchorPagerManagedInsetCoordinator.Target?
    private var lastManagedScrollViewIdentifiers: [ObjectIdentifier] = []
    private var lastLayoutContext: AnchorPagerLayoutContext?
    private var lastLayoutOutput: AnchorPagerLayoutEngine.Output?
    private var lastLoggedResolvedHeaderHeight: AnchorPagerLayoutEngine.ResolvedHeaderHeight?
    private var lastLoggedHeaderFrame: CGRect?
    private var lastLoggedBarFrame: CGRect?
    private var lastLoggedSafeAreaObstruction: LocalSafeAreaObstruction?
    private var lastLoggedBounds: CGRect?
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
        MainActor.assumeIsolated {
            managedInsetCoordinator.releaseAll()
        }
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

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateVisibleLayout()
    }

    /// 重新加载页面、标题和 Header 数据。
    public func reloadData() {
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "reloadData.begin")
        let previouslyActiveScrollViews = activePageScrollViews

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
            activePageScrollViews = []
        } else if selectedIndex >= pageCount {
            selectedIndex = pageCount - 1
        }

        currentHeaderContent = dataSource?.headerContent(in: self)
        currentTitles = (0..<pageCount).map { index in
            dataSource?.pagerViewController(self, titleForViewControllerAt: index) ?? ""
        }
        var claimedScrollViews = Set<ObjectIdentifier>()
        var activeFallbackHostIdentifiers = Set<ObjectIdentifier>()
        let preparedPages = (0..<pageCount).map { index in
            preparePage(
                for: dataSource?.pagerViewController(self, viewControllerAt: index) ?? UIViewController(),
                claimedScrollViews: &claimedScrollViews,
                activeFallbackHostIdentifiers: &activeFallbackHostIdentifiers
            )
        }
        currentViewControllers = preparedPages.map(\.viewController)
        activePageScrollViews = preparedPages.map(\.scrollView)
        let staleFallbackHosts = removeStaleFallbackPageHosts(
            keeping: activeFallbackHostIdentifiers
        )

        reloadVisibleContentIfNeeded()
        let activeIdentifiers = Set(activePageScrollViews.map(ObjectIdentifier.init))
        previouslyActiveScrollViews
            .filter { !activeIdentifiers.contains(ObjectIdentifier($0)) }
            .forEach(managedInsetCoordinator.release)
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

        guard selectedIndex != self.selectedIndex else { return }

        if !isViewLoaded || pagingAdapter.parent == nil {
            commitSelectedIndex(selectedIndex, animated: animated)
            return
        }

        let didAcceptRequest = pagingAdapter.setSelectedIndex(selectedIndex, animated: animated)
        if !didAcceptRequest {
            AnchorPagerLogger.log(.debug, category: .paging, event: "setSelectedIndex.rejected")
        }
    }

    /// 重新测量并布局 Header。
    public func reloadHeaderLayout(
        offsetAdjustment: AnchorPagerHeaderOffsetAdjustment = .preserveVisualPosition
    ) {
        AnchorPagerLogger.log(.info, category: .layout, event: "reloadHeaderLayout")
        updateVisibleLayout(forceNotify: true, offsetAdjustment: offsetAdjustment)
        view.setNeedsLayout()
    }

    private func installVerticalScrollViewIfNeeded() {
        guard verticalScrollView.superview == nil else { return }

        verticalScrollView.alwaysBounceVertical = true
        verticalScrollView.contentInsetAdjustmentBehavior = .never
        verticalScrollView.delegate = verticalScrollDelegate
        verticalScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(verticalScrollView)
        NSLayoutConstraint.activate([
            verticalScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            verticalScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            verticalScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            verticalScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        scrollRangeView.translatesAutoresizingMaskIntoConstraints = false
        scrollRangeView.isUserInteractionEnabled = false
        verticalScrollView.addSubview(scrollRangeView)
        let scrollRangeHeightConstraint = scrollRangeView.heightAnchor.constraint(
            equalTo: verticalScrollView.frameLayoutGuide.heightAnchor
        )
        NSLayoutConstraint.activate([
            scrollRangeView.leadingAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.leadingAnchor),
            scrollRangeView.trailingAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.trailingAnchor),
            scrollRangeView.topAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.topAnchor),
            scrollRangeView.bottomAnchor.constraint(equalTo: verticalScrollView.contentLayoutGuide.bottomAnchor),
            scrollRangeView.widthAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.widthAnchor),
            scrollRangeHeightConstraint
        ])
        self.scrollRangeHeightConstraint = scrollRangeHeightConstraint

        viewportView.translatesAutoresizingMaskIntoConstraints = false
        viewportView.clipsToBounds = true
        verticalScrollView.addSubview(viewportView)
        NSLayoutConstraint.activate([
            viewportView.leadingAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.leadingAnchor),
            viewportView.trailingAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.trailingAnchor),
            viewportView.topAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.topAnchor),
            viewportView.bottomAnchor.constraint(equalTo: verticalScrollView.frameLayoutGuide.bottomAnchor)
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
        headerViewHost.install(headerContent, in: self, hostParentView: viewportView)

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
            viewportView.addSubview(adapterView)
            let pagingTopConstraint = adapterView.topAnchor.constraint(equalTo: headerViewHost.view.bottomAnchor)
            let pagingHeightConstraint = adapterView.heightAnchor.constraint(equalToConstant: 0)
            NSLayoutConstraint.activate([
                adapterView.leadingAnchor.constraint(equalTo: viewportView.leadingAnchor),
                adapterView.trailingAnchor.constraint(equalTo: viewportView.trailingAnchor),
                pagingTopConstraint,
                pagingHeightConstraint
            ])

            self.pagingTopConstraint = pagingTopConstraint
            self.pagingHeightConstraint = pagingHeightConstraint
        }

        if didAddPagingAdapter {
            pagingAdapter.didMove(toParent: self)
        }
    }

    private func updateVisibleLayout(
        forceNotify: Bool = false,
        offsetAdjustment: AnchorPagerHeaderOffsetAdjustment? = nil
    ) {
        guard !isApplyingLayout,
              isViewLoaded,
              headerViewHost.view.superview != nil else { return }

        pagingAdapter.setBarHeight(configuration.bar.height)
        isApplyingLayout = true
        defer { isApplyingLayout = false }

        let layoutEnvironment = currentLayoutEnvironment()
        let measuredHeight = measureHeaderHeight(in: layoutEnvironment)
        lastMeasuredHeaderHeight = measuredHeight
        let oldLayoutOutput = lastLayoutOutput.map {
            layoutOutputByApplyingContentOffset(
                $0,
                contentOffsetY: verticalScrollView.contentOffset.y
            )
        }
        var layoutOutput = makeLayoutOutput(
            measuredHeaderHeight: measuredHeight,
            contentOffsetY: verticalScrollView.contentOffset.y,
            environment: layoutEnvironment
        )
        if let offsetAdjustment {
            let adjustedOffsetY = layoutEngine.adjustedContentOffsetY(
                current: verticalScrollView.contentOffset.y,
                old: oldLayoutOutput,
                new: layoutOutput,
                strategy: offsetAdjustment
            )
            if abs(verticalScrollView.contentOffset.y - adjustedOffsetY) > 0.001 {
                verticalScrollView.setContentOffset(
                    CGPoint(x: verticalScrollView.contentOffset.x, y: adjustedOffsetY),
                    animated: false
                )
            }
            layoutOutput = makeLayoutOutput(
                measuredHeaderHeight: measuredHeight,
                contentOffsetY: adjustedOffsetY,
                environment: layoutEnvironment
            )
        }

        applyLayoutOutput(
            layoutOutput,
            environment: layoutEnvironment,
            forceNotify: forceNotify,
            logsChanges: true,
            updatesScrollRange: true
        )
    }

    private func updateVisibleLayoutForScrolling() {
        guard !isApplyingLayout,
              isViewLoaded,
              headerViewHost.view.superview != nil,
              let measuredHeaderHeight = lastMeasuredHeaderHeight else { return }

        isApplyingLayout = true
        defer { isApplyingLayout = false }

        let environment = currentLayoutEnvironment()
        let output = makeLayoutOutput(
            measuredHeaderHeight: measuredHeaderHeight,
            contentOffsetY: verticalScrollView.contentOffset.y,
            environment: environment
        )
        applyLayoutOutput(
            output,
            environment: environment,
            forceNotify: false,
            logsChanges: false,
            updatesScrollRange: false
        )
    }

    private func applyLayoutOutput(
        _ output: AnchorPagerLayoutEngine.Output,
        environment: LayoutEnvironment,
        forceNotify: Bool,
        logsChanges: Bool,
        updatesScrollRange: Bool
    ) {
        let translationY = overscrollTranslationY
        viewportView.transform = CGAffineTransform(translationX: 0, y: translationY)

        if updatesScrollRange {
            scrollRangeHeightConstraint?.constant = output.resolvedHeaderHeight.collapsibleDistance
        }
        headerHeightConstraint?.constant = output.headerFrame.height
        headerViewHost.setTopOffset(output.headerFrame.minY)
        pagingTopConstraint?.constant = Swift.max(
            0,
            output.pagingFrame.minY - output.headerFrame.maxY
        )
        pagingHeightConstraint?.constant = output.pagingFrame.height

        if updatesScrollRange {
            applyManagedInsets(environment: environment)
        }

        if logsChanges {
            logLayoutChanges(output: output, environment: environment)
        }

        if let previousCollapseProgress = lastLayoutOutput?.collapseProgress,
           previousCollapseProgress != output.collapseProgress {
            delegate?.pagerViewController(
                self,
                didUpdateHeaderCollapseProgress: output.collapseProgress
            )
        }

        let context = layoutContext(for: output, translationY: translationY)
        if forceNotify || context != lastLayoutContext {
            lastLayoutContext = context
            delegate?.pagerViewController(self, didUpdateLayout: context)
        }
        lastLayoutOutput = output
    }

    private func measureHeaderHeight(in environment: LayoutEnvironment) -> CGFloat {
        viewportView.transform = .identity
        headerViewHost.setTopOffset(environment.bounds.minY + environment.obstruction.top)
        headerHeightConstraint?.constant = lastMeasuredHeaderHeight ?? 0
        view.layoutIfNeeded()

        return headerViewHost.measure(
            in: CGSize(
                width: environment.bounds.width,
                height: UIView.layoutFittingCompressedSize.height
            )
        )
    }

    private var overscrollTranslationY: CGFloat {
        Swift.max(0, -verticalScrollView.contentOffset.y)
    }

    private func layoutContext(
        for output: AnchorPagerLayoutEngine.Output,
        translationY: CGFloat
    ) -> AnchorPagerLayoutContext {
        AnchorPagerLayoutContext(
            selectedIndex: effectiveSelectedIndex,
            headerFrame: output.headerFrame.offsetBy(dx: 0, dy: translationY),
            barFrame: output.barFrame.offsetBy(dx: 0, dy: translationY),
            contentFrame: output.contentFrame.offsetBy(dx: 0, dy: translationY)
        )
    }

    private func makeLayoutOutput(
        measuredHeaderHeight: CGFloat,
        contentOffsetY: CGFloat,
        environment: LayoutEnvironment? = nil
    ) -> AnchorPagerLayoutEngine.Output {
        let environment = environment ?? currentLayoutEnvironment()
        return layoutEngine.layout(
            for: AnchorPagerLayoutEngine.Input(
                bounds: environment.bounds,
                measuredHeaderHeight: measuredHeaderHeight,
                headerHeightMode: configuration.header.heightMode,
                headerTopBehavior: configuration.header.topBehavior,
                barHeight: resolvedBarInsets.top,
                topObstructionHeight: environment.obstruction.top,
                bottomObstructionHeight: environment.obstruction.bottom,
                contentOffsetY: contentOffsetY
            )
        )
    }

    private struct LayoutEnvironment {
        var bounds: CGRect
        var obstruction: LocalSafeAreaObstruction
    }

    private struct LocalSafeAreaObstruction: Equatable {
        var top: CGFloat
        var bottom: CGFloat
    }

    private func currentLayoutEnvironment() -> LayoutEnvironment {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let height = view.bounds.height > 0 ? view.bounds.height : UIScreen.main.bounds.height
        return LayoutEnvironment(
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            obstruction: localSafeAreaObstruction()
        )
    }

    private func localSafeAreaObstruction() -> LocalSafeAreaObstruction {
        let bounds = view.bounds
        let layoutFrame = view.safeAreaLayoutGuide.layoutFrame
        let safeAreaInsets = view.safeAreaInsets
        return LocalSafeAreaObstruction(
            top: Swift.max(
                nonNegativeFinite(layoutFrame.minY - bounds.minY),
                nonNegativeFinite(safeAreaInsets.top),
                nonNegativeFinite(additionalSafeAreaInsets.top)
            ),
            bottom: Swift.max(
                nonNegativeFinite(bounds.maxY - layoutFrame.maxY),
                nonNegativeFinite(safeAreaInsets.bottom),
                nonNegativeFinite(additionalSafeAreaInsets.bottom)
            )
        )
    }

    private func nonNegativeFinite(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return Swift.max(0, value)
    }

    private func logLayoutChanges(
        output: AnchorPagerLayoutEngine.Output,
        environment: LayoutEnvironment
    ) {
        if lastLoggedResolvedHeaderHeight != output.resolvedHeaderHeight {
            AnchorPagerLogger.log(.debug, category: .layout, event: "layout.headerHeightResolved")
            lastLoggedResolvedHeaderHeight = output.resolvedHeaderHeight
        }

        if lastLoggedHeaderFrame != output.headerFrame {
            AnchorPagerLogger.log(.debug, category: .layout, event: "layout.headerFrameChanged")
            lastLoggedHeaderFrame = output.headerFrame
        }

        if lastLoggedBarFrame != output.barFrame {
            AnchorPagerLogger.log(.debug, category: .layout, event: "layout.barFrameChanged")
            lastLoggedBarFrame = output.barFrame
        }

        if lastLoggedSafeAreaObstruction != environment.obstruction {
            AnchorPagerLogger.log(.info, category: .layout, event: "layout.safeAreaChanged")
            lastLoggedSafeAreaObstruction = environment.obstruction
        }

        if lastLoggedBounds != environment.bounds {
            AnchorPagerLogger.log(.info, category: .layout, event: "layout.boundsChanged")
            lastLoggedBounds = environment.bounds
        }
    }

    private func layoutOutputByApplyingContentOffset(
        _ output: AnchorPagerLayoutEngine.Output,
        contentOffsetY: CGFloat
    ) -> AnchorPagerLayoutEngine.Output {
        var output = output
        let collapsibleDistance = output.resolvedHeaderHeight.collapsibleDistance
        let collapseOffset = Swift.min(
            collapsibleDistance,
            Swift.max(0, contentOffsetY)
        )
        output.collapseOffset = collapseOffset
        output.collapseProgress = collapsibleDistance > 0
            ? collapseOffset / collapsibleDistance
            : 0
        return output
    }

    private func commitSelectedIndex(_ index: Int, animated: Bool) {
        guard index != selectedIndex else { return }

        selectedIndex = index
        AnchorPagerLogger.log(.info, category: .paging, event: "setSelectedIndex.commit")
        delegate?.pagerViewController(self, didSelectViewControllerAt: index)
    }

    private struct PreparedPage {
        let viewController: UIViewController
        let scrollView: UIScrollView
    }

    private func fallbackPageHost(
        for childViewController: UIViewController,
        activeFallbackHostIdentifiers: inout Set<ObjectIdentifier>
    ) -> AnchorPagerPageScrollHostViewController {
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

    private func preparePage(
        for childViewController: UIViewController,
        claimedScrollViews: inout Set<ObjectIdentifier>,
        activeFallbackHostIdentifiers: inout Set<ObjectIdentifier>
    ) -> PreparedPage {
        childViewController.loadViewIfNeeded()

        if let resolvedScrollView = childViewController.anchorPagerScrollView,
           claimedScrollViews.insert(ObjectIdentifier(resolvedScrollView)).inserted {
            return PreparedPage(
                viewController: childViewController,
                scrollView: resolvedScrollView
            )
        }

        if childViewController.anchorPagerScrollView != nil {
            AnchorPagerAssertions.failure("AnchorPager pages must not share a scroll view.")
            AnchorPagerLogger.log(.debug, category: .inset, event: "inset.targetCollision")
            if let defaultScrollView = childViewController.anchorPagerDefaultScrollView,
               claimedScrollViews.insert(ObjectIdentifier(defaultScrollView)).inserted {
                return PreparedPage(
                    viewController: childViewController,
                    scrollView: defaultScrollView
                )
            }
        }

        let fallbackHost = fallbackPageHost(
            for: childViewController,
            activeFallbackHostIdentifiers: &activeFallbackHostIdentifiers
        )
        fallbackHost.loadViewIfNeeded()
        claimedScrollViews.insert(ObjectIdentifier(fallbackHost.scrollView))
        return PreparedPage(
            viewController: fallbackHost,
            scrollView: fallbackHost.scrollView
        )
    }

    private func applyManagedInsets(environment: LayoutEnvironment) {
        let target = AnchorPagerManagedInsetCoordinator.Target(
            content: UIEdgeInsets(
                top: resolvedBarInsets.top,
                left: 0,
                bottom: environment.obstruction.bottom,
                right: 0
            ),
            indicators: UIEdgeInsets(
                top: 0,
                left: 0,
                bottom: environment.obstruction.bottom,
                right: 0
            )
        )
        let identifiers = activePageScrollViews.map(ObjectIdentifier.init)
        guard target != lastManagedInsetTarget
                || identifiers != lastManagedScrollViewIdentifiers else { return }

        for (viewController, scrollView) in zip(currentViewControllers, activePageScrollViews) {
            if let fallbackHost = viewController as? AnchorPagerPageScrollHostViewController {
                fallbackHost.setManagedContentInsets(target.content)
            }
            managedInsetCoordinator.apply(target, to: scrollView)
        }
        lastManagedInsetTarget = target
        lastManagedScrollViewIdentifiers = identifiers
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
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {
        guard resolvedBarInsets != barInsets else { return }
        resolvedBarInsets = barInsets
        view.setNeedsLayout()
        if !isApplyingLayout {
            updateVisibleLayout()
        }
    }

    func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, willSelect index: Int, animated: Bool) {}

    func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, didSelect index: Int, animated: Bool) {
        guard index >= 0, index < pageCount else { return }
        commitSelectedIndex(index, animated: animated)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    ) {
        guard previousIndex >= 0, previousIndex < pageCount else { return }
        AnchorPagerLogger.log(.debug, category: .paging, event: "setSelectedIndex.cancel")
    }
}
