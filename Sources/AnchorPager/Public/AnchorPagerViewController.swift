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
    public var configuration: AnchorPagerConfiguration {
        didSet {
            guard isViewLoaded else { return }
            pageStateStore.setKeepsAdjacentPagesLoaded(
                configuration.paging.keepsAdjacentPagesLoaded
            )
            pageStateStore.updateManagedInsets(
                currentManagedInsetTarget,
                logsChanges: false
            )
            view.setNeedsLayout()
        }
    }

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
    private let pagingHost = AnchorPagerPagingHostViewController()
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
    private var resolvedBarInsets: UIEdgeInsets = .zero
    private var currentManagedInsetTarget: AnchorPagerManagedInsetCoordinator.Target = .zero
    private lazy var pageStateStore = AnchorPagerPageStateStore(
        managedInsetCoordinator: managedInsetCoordinator
    )
    private var reloadGeneration = 0
    private var reloadTransactionIdentifier = 0
    private var pendingReloadGeneration: Int?
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
        configurePagingHost()
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "init")
    }

    /// 从 storyboard 或 nib 创建 AnchorPager 容器。
    public required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        configurePagingHost()
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "init")
    }

    deinit {
        MainActor.assumeIsolated {
            pageStateStore.releaseAll()
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
        reloadTransactionIdentifier &+= 1
        let transactionIdentifier = reloadTransactionIdentifier
        let reloadDataSource = dataSource

        let requestedCount = reloadDataSource?.numberOfViewControllers(in: self) ?? 0
        guard isCurrentReloadTransaction(transactionIdentifier) else { return }

        let resolvedPageCount: Int
        if requestedCount < 0 {
            AnchorPagerAssertions.failure("AnchorPager page count must not be negative.")
            AnchorPagerLogger.log(
                .error,
                category: .children,
                event: "children.page.invalidCount"
            )
            resolvedPageCount = 0
        } else {
            resolvedPageCount = requestedCount
        }

        let resolvedHeaderContent = reloadDataSource?.headerContent(in: self)
        guard isCurrentReloadTransaction(transactionIdentifier) else { return }

        var resolvedTitles: [String] = []
        resolvedTitles.reserveCapacity(resolvedPageCount)
        for index in 0..<resolvedPageCount {
            let title = reloadDataSource?.pagerViewController(
                self,
                titleForViewControllerAt: index
            ) ?? ""
            guard isCurrentReloadTransaction(transactionIdentifier) else { return }
            resolvedTitles.append(title)
        }

        let resolvedSelectedIndex: Int
        if resolvedPageCount == 0 {
            resolvedSelectedIndex = 0
        } else {
            resolvedSelectedIndex = Swift.min(selectedIndex, resolvedPageCount - 1)
        }

        AnchorPagerLogger.log(.info, category: .lifecycle, event: "reloadData.begin")
        pageCount = resolvedPageCount
        selectedIndex = resolvedSelectedIndex
        currentHeaderContent = resolvedHeaderContent
        currentTitles = resolvedTitles
        reloadGeneration &+= 1
        pendingReloadGeneration = reloadGeneration
        pageStateStore.beginReload(
            generation: reloadGeneration,
            pageCount: resolvedPageCount,
            selectedIndex: resolvedSelectedIndex,
            keepsAdjacentPagesLoaded: configuration.paging.keepsAdjacentPagesLoaded
        )

        reloadVisibleContentIfNeeded()
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "reloadData.end")
    }

    private func isCurrentReloadTransaction(_ transactionIdentifier: Int) -> Bool {
        guard transactionIdentifier == reloadTransactionIdentifier else {
            AnchorPagerLogger.log(
                .debug,
                category: .lifecycle,
                event: "lifecycle.reloadData.cancelled"
            )
            return false
        }
        return true
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

        if !isViewLoaded || pagingHost.activeAdapter == nil {
            pageStateStore.didSelect(selectedIndex, context: pageAccessContext)
            commitSelectedIndex(selectedIndex, animated: animated)
            return
        }

        let didAcceptRequest = pagingHost.setSelectedIndex(selectedIndex, animated: animated)
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
        verticalScrollView.showsVerticalScrollIndicator = false
        verticalScrollView.showsHorizontalScrollIndicator = false
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

    private func configurePagingHost() {
        pagingHost.eventDelegate = self
        pagingHost.pageProvider = self
    }

    private func reloadVisibleContentIfNeeded() {
        guard isViewLoaded else { return }

        installVerticalScrollViewIfNeeded()
        installHeaderHost()
        installPagingHostIfNeeded()
        updateVisibleLayout()
        pagingHost.reload(
            titles: currentTitles,
            pageCount: pageCount,
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

    private func installPagingHostIfNeeded() {
        let didAddPagingHost = pagingHost.parent == nil
        if pagingHost.parent == nil {
            addChild(pagingHost)
        }

        if pagingHost.view.superview == nil {
            let hostView = pagingHost.view!
            hostView.translatesAutoresizingMaskIntoConstraints = false
            viewportView.addSubview(hostView)
            let pagingTopConstraint = hostView.topAnchor.constraint(equalTo: headerViewHost.view.bottomAnchor)
            let pagingHeightConstraint = hostView.heightAnchor.constraint(equalToConstant: 0)
            NSLayoutConstraint.activate([
                hostView.leadingAnchor.constraint(equalTo: viewportView.leadingAnchor),
                hostView.trailingAnchor.constraint(equalTo: viewportView.trailingAnchor),
                pagingTopConstraint,
                pagingHeightConstraint
            ])

            self.pagingTopConstraint = pagingTopConstraint
            self.pagingHeightConstraint = pagingHeightConstraint
        }

        if didAddPagingHost {
            pagingHost.didMove(toParent: self)
        }
    }

    private func updateVisibleLayout(
        forceNotify: Bool = false,
        offsetAdjustment: AnchorPagerHeaderOffsetAdjustment? = nil
    ) {
        guard !isApplyingLayout,
              isViewLoaded,
              headerViewHost.view.superview != nil else { return }

        pagingHost.setBarHeight(configuration.bar.height)
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

        applyManagedInsets(output: output, logsChanges: logsChanges)

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

    private func applyManagedInsets(
        output: AnchorPagerLayoutEngine.Output,
        logsChanges: Bool
    ) {
        let target = AnchorPagerManagedInsetCoordinator.Target(
            content: UIEdgeInsets(
                top: resolvedBarInsets.top,
                left: 0,
                bottom: output.childBottomObstruction,
                right: 0
            ),
            indicators: UIEdgeInsets(
                top: resolvedBarInsets.top,
                left: 0,
                bottom: output.childBottomObstruction,
                right: 0
            )
        )
        currentManagedInsetTarget = target
        pageStateStore.setKeepsAdjacentPagesLoaded(
            configuration.paging.keepsAdjacentPagesLoaded
        )
        pageStateStore.updateManagedInsets(target, logsChanges: logsChanges)
    }

    private var pageAccessContext: AnchorPagerPageStateStore.AccessContext {
        AnchorPagerPageStateStore.AccessContext(
            managedInsetTarget: currentManagedInsetTarget,
            containerIsCollapsed: isContainerCollapsed
        )
    }

    private var isContainerCollapsed: Bool {
        guard let output = lastLayoutOutput else { return false }
        let collapsibleDistance = output.resolvedHeaderHeight.collapsibleDistance
        return collapsibleDistance <= 0.5
            || output.collapseOffset >= collapsibleDistance - 0.5
    }
}

extension AnchorPagerViewController: AnchorPagerPageProviding {
    func pageViewController(at index: Int) -> UIViewController? {
        pageStateStore.pageViewController(
            at: index,
            context: pageAccessContext
        ) { [weak self] in
            guard let self, let dataSource = self.dataSource else { return nil }
            return dataSource.pagerViewController(self, viewControllerAt: index)
        }
    }
}

extension AnchorPagerViewController: AnchorPagerPagingHostViewControllerDelegate {
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {
        guard resolvedBarInsets != barInsets else { return }
        resolvedBarInsets = barInsets
        view.setNeedsLayout()
        if !isApplyingLayout {
            updateVisibleLayout()
        }
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willSelect index: Int,
        animated: Bool
    ) {
        pageStateStore.willSelect(
            from: selectedIndex,
            to: index,
            context: pageAccessContext
        )
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didSelect index: Int,
        animated: Bool
    ) {
        guard index >= 0, index < pageCount else { return }
        pageStateStore.didSelect(index, context: pageAccessContext)
        commitSelectedIndex(index, animated: animated)
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    ) {
        guard previousIndex >= 0, previousIndex < pageCount else { return }
        pageStateStore.didCancelSelection(
            at: index,
            returningTo: previousIndex,
            context: pageAccessContext
        )
        AnchorPagerLogger.log(.debug, category: .paging, event: "setSelectedIndex.cancel")
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal
    ) {
        guard let pendingReloadGeneration else { return }
        pageStateStore.commitReload(generation: pendingReloadGeneration)
        self.pendingReloadGeneration = nil
        if case let .page(index) = terminal,
           index >= 0,
           index < pageCount {
            pageStateStore.didSelect(index, context: pageAccessContext)
        }
    }
}
