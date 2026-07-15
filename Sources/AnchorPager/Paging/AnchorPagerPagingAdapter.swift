import Pageboy
import Tabman
import UIKit

@MainActor
protocol AnchorPagerPageProviding: AnyObject {
    func pageViewController(at index: Int) -> UIViewController?
}

@MainActor
protocol AnchorPagerPagingAdapterDelegate: AnyObject {
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdatePagingSurface surface: AnchorPagerPagingSurfaceObservation.Surface?
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        pagingPanDidChange state: UIGestureRecognizer.State
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didRequestBarSelectionAt index: Int
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didBeginInteractiveSelectionAt index: Int,
        animated: Bool
    ) -> AnchorPagerPagingSelectionRequestIdentifier?
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        willSelect index: Int,
        animated: Bool,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didSelect index: Int,
        animated: Bool,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didComplete requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
        finished: Bool,
        currentIndex: Int?
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        executorDidBecomeReadyFor requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdateBarInsets barInsets: UIEdgeInsets
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didReloadAt index: Int,
        terminalBarInsets: UIEdgeInsets,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    )
    func pagingAdapterDidBecomeReadyForReload(_ adapter: AnchorPagerPagingAdapter)
}

extension AnchorPagerPagingAdapterDelegate {
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdatePagingSurface surface: AnchorPagerPagingSurfaceObservation.Surface?
    ) {}
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        pagingPanDidChange state: UIGestureRecognizer.State
    ) {}
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {}
    func pagingAdapterDidBecomeReadyForReload(_ adapter: AnchorPagerPagingAdapter) {}
}

@MainActor
final class AnchorPagerPagingAdapter: TabmanViewController, PageboyViewControllerDataSource, TMBarDataSource {
    weak var eventDelegate: AnchorPagerPagingAdapterDelegate?
    weak var pageProvider: AnchorPagerPageProviding?

    private var titles: [String] = []
    private var configuredPageCount = 0
    private var defaultSelectedIndex = 0
    private var committedSelectedIndex = 0
    private var pendingPageboySelectionIndex: Int?
    private var executingSelection: ExecutingSelection?
    private var executorReadyRequestIdentifier: AnchorPagerPagingSelectionRequestIdentifier?
    private var installedBar: TMBar?
    private var barHeightConstraint: NSLayoutConstraint?
    private var requestedBarHeight: CGFloat?
    private var lastReportedBarInsets: UIEdgeInsets?
    private var reloadSelectionCallbackSuppressionDepth = 0
    private let pagingSurfaceObservation = AnchorPagerPagingSurfaceObservation()
    // 只在对应同步 reloadData 调用栈内存在，避免晚到回调借用后续 request 标识。
    private var reloadCallbackRequestIdentifier: AnchorPagerPagingReloadRequestIdentifier?

    private struct ExecutingSelection: Equatable {
        let request: AnchorPagerPagingSelectionRequest
        let previousIndex: Int
    }

    /// 当前是否可以同步执行 Pageboy reload 或空态 teardown。
    ///
    /// 该查询只读取 AnchorPager 已有 selection 状态和 Pageboy public 滚动状态，
    /// 不得修改 data source 或第三方状态。
    var isReadyForReload: Bool {
        pendingPageboySelectionIndex == nil &&
            executingSelection == nil &&
            executorReadyRequestIdentifier == nil
    }

    /// 当前通过公开 UIKit containment 发现的 Pageboy 分页手势表面。
    var pagingSurface: AnchorPagerPagingSurfaceObservation.Surface? {
        pagingSurfaceObservation.surface
    }

    override var isUserInteractionEnabled: Bool {
        didSet {
            publishExecutorReadyIfPossible()
        }
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        let shouldSuppressInitialReloadSelection = configuredPageCount > 0
        if shouldSuppressInitialReloadSelection {
            reloadSelectionCallbackSuppressionDepth += 1
        }
        super.viewDidLoad()
        if shouldSuppressInitialReloadSelection {
            reloadSelectionCallbackSuppressionDepth -= 1
        }
        installBarIfNeeded()
        refreshPagingSurfaceObservation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshPagingSurfaceObservation()

        let resolvedInsets = sanitizedBarInsets(barInsets)
        guard lastReportedBarInsets != resolvedInsets else { return }

        lastReportedBarInsets = resolvedInsets
        AnchorPagerLogger.log(.debug, category: .paging, event: "paging.barInsetsChanged")
        eventDelegate?.pagingAdapter(self, didUpdateBarInsets: resolvedInsets)
    }

    func setBarHeight(_ height: CGFloat?) {
        let resolvedHeight: CGFloat?
        if let height, (!height.isFinite || height < 0) {
            AnchorPagerAssertions.failure("AnchorPager bar height must be finite and nonnegative.")
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.barHeightInvalid")
            resolvedHeight = 0
        } else {
            resolvedHeight = height
        }

        guard requestedBarHeight != resolvedHeight else { return }

        requestedBarHeight = resolvedHeight
        updateBarHeightConstraintIfNeeded()
    }

    @discardableResult
    func setPagePresentationTranslationY(_ translationY: CGFloat) -> Bool {
        guard let pageViewController = children
            .compactMap({ $0 as? UIPageViewController })
            .first,
            pageViewController.isViewLoaded else {
            return translationY == 0
        }

        pageViewController.view.transform = translationY == 0
            ? .identity
            : CGAffineTransform(translationX: 0, y: translationY)
        return true
    }

    func reload(
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier,
        titles: [String],
        pageCount: Int,
        selectedIndex: Int
    ) {
        performReload(
            requestIdentifier: requestIdentifier,
            titles: titles,
            pageCount: pageCount,
            selectedIndex: selectedIndex
        )
    }

    private func performReload(
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier,
        titles: [String],
        pageCount: Int,
        selectedIndex: Int
    ) {
        self.titles = titles
        configuredPageCount = Swift.max(0, pageCount)
        if (0..<configuredPageCount).contains(selectedIndex) {
            defaultSelectedIndex = selectedIndex
        } else {
            defaultSelectedIndex = 0
        }
        committedSelectedIndex = defaultSelectedIndex
        cancelSelectionExecutionStructurally()

        if isViewLoaded {
            let previousRequestIdentifier = reloadCallbackRequestIdentifier
            reloadCallbackRequestIdentifier = requestIdentifier
            reloadSelectionCallbackSuppressionDepth += 1
            reloadData()
            reloadSelectionCallbackSuppressionDepth -= 1
            reloadCallbackRequestIdentifier = previousRequestIdentifier
            refreshPagingSurfaceObservation()
            bars.forEach { bar in
                if configuredPageCount > 0 {
                    bar.reloadData(at: 0...configuredPageCount - 1, context: .full)
                }
            }
        }
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.reload")
    }

    /// 清空 Pageboy 业务页面后，允许 PagingHost 安全移除当前 adapter。
    ///
    /// Pageboy 5.0.2 的零页 `reloadData()` 不会清理内部页面；这里通过 public
    /// delete-last-page 进入零页状态，再清理只剩第三方 plumbing 的 containment。
    /// 升级依赖时必须重新验证该兼容点。
    @discardableResult
    func prepareForRemoval() -> Bool {
        _ = setPagePresentationTranslationY(0)
        let oldPageCount = pageCount ?? 0
        let deletionIndex = Swift.min(
            Swift.max(0, committedSelectedIndex),
            Swift.max(0, oldPageCount - 1)
        )
        titles = []
        configuredPageCount = 0
        defaultSelectedIndex = 0
        committedSelectedIndex = 0
        cancelSelectionExecutionStructurally()

        guard isViewLoaded else { return true }

        reloadSelectionCallbackSuppressionDepth += 1
        defer { reloadSelectionCallbackSuppressionDepth -= 1 }
        guard oldPageCount > 0 else {
            guard pageCount == 0, currentIndex == nil else { return false }
            tearDownChildTreeForRemoval()
            return true
        }

        var didDeletionCompleteSynchronously = false
        deletePage(at: deletionIndex, then: .doNothing) {
            didDeletionCompleteSynchronously = true
        }
        guard didDeletionCompleteSynchronously,
              pageCount == 0,
              currentIndex == nil else { return false }
        tearDownChildTreeForRemoval()
        return true
    }

    private func tearDownChildTreeForRemoval() {
        pagingSurfaceObservation.invalidate()

        func tearDown(_ viewController: UIViewController) {
            for child in viewController.children {
                tearDown(child)
            }
            viewController.willMove(toParent: nil)
            viewController.viewIfLoaded?.removeFromSuperview()
            viewController.removeFromParent()
        }

        for child in children {
            tearDown(child)
        }
    }

    @discardableResult
    func executeSelection(
        _ request: AnchorPagerPagingSelectionRequest,
        previousIndex: Int
    ) -> Bool {
        guard request.source.isExplicit else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.selection.reject")
            return false
        }
        guard (0..<configuredPageCount).contains(request.targetIndex) else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.setSelectedIndex.outOfRange")
            return false
        }
        guard executingSelection == nil,
              executorReadyRequestIdentifier == nil else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.selection.reject")
            return false
        }

        AnchorPagerLogger.log(.info, category: .paging, event: "paging.setSelectedIndex.request")
        executingSelection = ExecutingSelection(
            request: request,
            previousIndex: previousIndex
        )
        var isResolvingPageboyAcceptance = true
        var deferredCompletion: Bool?
        let didStartScroll = scrollToPage(
            .at(index: request.targetIndex),
            animated: request.animated
        ) { [weak self] _, _, finished in
            if isResolvingPageboyAcceptance {
                deferredCompletion = finished
                return
            }
            self?.finishProgrammaticTransition(
                requestIdentifier: request.identifier,
                targetIndex: request.targetIndex,
                finished: finished
            )
        }
        isResolvingPageboyAcceptance = false
        if !didStartScroll {
            if executingSelection?.request.identifier == request.identifier {
                executingSelection = nil
            }
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.setSelectedIndex.rejected")
            notifyReloadReadinessIfNeeded()
            return false
        }
        if let deferredCompletion {
            finishProgrammaticTransition(
                requestIdentifier: request.identifier,
                targetIndex: request.targetIndex,
                finished: deferredCompletion
            )
        }
        return true
    }

    func numberOfViewControllers(in pageboyViewController: PageboyViewController) -> Int {
        configuredPageCount
    }

    func viewController(
        for pageboyViewController: PageboyViewController,
        at index: PageboyViewController.PageIndex
    ) -> UIViewController? {
        guard (0..<configuredPageCount).contains(index) else { return nil }
        return pageProvider?.pageViewController(at: index)
    }

    func defaultPage(for pageboyViewController: PageboyViewController) -> PageboyViewController.Page? {
        guard (0..<configuredPageCount).contains(defaultSelectedIndex) else { return nil }
        return .at(index: defaultSelectedIndex)
    }

    func barItem(for bar: TMBar, at index: Int) -> TMBarItemable {
        let title = titles.indices.contains(index) ? titles[index] : ""
        return TMBarItem(title: title)
    }

    override func bar(_ bar: TMBar, didRequestScrollTo index: PageIndex) {
        eventDelegate?.pagingAdapter(self, didRequestBarSelectionAt: index)
    }

    override func pageboyViewController(
        _ pageboyViewController: PageboyViewController,
        willScrollToPageAt index: PageIndex,
        direction: NavigationDirection,
        animated: Bool
    ) {
        super.pageboyViewController(
            pageboyViewController,
            willScrollToPageAt: index,
            direction: direction,
            animated: animated
        )
        guard reloadSelectionCallbackSuppressionDepth == 0 else { return }
        guard let requestIdentifier = requestIdentifierForWillSelect(
            at: index,
            animated: animated
        ) else {
            return
        }
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.willSelect")
        recordWillSelectCallback(at: index)
        eventDelegate?.pagingAdapter(
            self,
            willSelect: index,
            animated: animated,
            requestIdentifier: requestIdentifier
        )
    }

    override func pageboyViewController(
        _ pageboyViewController: PageboyViewController,
        didScrollToPageAt index: PageIndex,
        direction: NavigationDirection,
        animated: Bool
    ) {
        super.pageboyViewController(
            pageboyViewController,
            didScrollToPageAt: index,
            direction: direction,
            animated: animated
        )
        guard reloadSelectionCallbackSuppressionDepth == 0 else { return }
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.didSelect")
        recordTerminalSelectionCallback(at: index)
        guard let execution = matchingExecution(at: index) else {
            logStaleSelectionTerminal()
            return
        }
        committedSelectedIndex = index
        eventDelegate?.pagingAdapter(
            self,
            didSelect: index,
            animated: animated,
            requestIdentifier: execution.request.identifier
        )
        finishInteractiveExecutionIfNeeded(execution)
    }

    override func pageboyViewController(
        _ pageboyViewController: PageboyViewController,
        didCancelScrollToPageAt index: PageboyViewController.PageIndex,
        returnToPageAt previousIndex: PageboyViewController.PageIndex
    ) {
        super.pageboyViewController(
            pageboyViewController,
            didCancelScrollToPageAt: index,
            returnToPageAt: previousIndex
        )
        guard reloadSelectionCallbackSuppressionDepth == 0 else { return }
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.didCancel")
        recordTerminalSelectionCallback(at: index)
        guard let execution = matchingExecution(at: index) else {
            logStaleSelectionTerminal()
            return
        }
        eventDelegate?.pagingAdapter(
            self,
            didCancelSelectionAt: index,
            returningTo: previousIndex,
            requestIdentifier: execution.request.identifier
        )
        finishInteractiveExecutionIfNeeded(execution)
    }

    override func pageboyViewController(
        _ pageboyViewController: PageboyViewController,
        didReloadWith currentViewController: UIViewController,
        currentPageIndex: PageIndex
    ) {
        super.pageboyViewController(
            pageboyViewController,
            didReloadWith: currentViewController,
            currentPageIndex: currentPageIndex
        )
        refreshPagingSurfaceObservation()
        if let reloadCallbackRequestIdentifier {
            view.layoutIfNeeded()
            let terminalBarInsets = sanitizedBarInsets(barInsets)
            eventDelegate?.pagingAdapter(
                self,
                didReloadAt: currentPageIndex,
                terminalBarInsets: terminalBarInsets,
                requestIdentifier: reloadCallbackRequestIdentifier
            )
        } else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.reload.stale")
        }
    }

    private func configure() {
        automaticallyAdjustsChildInsets = false
        dataSource = self
        pagingSurfaceObservation.onSurfaceChanged = { [weak self] surface in
            guard let self else { return }
            eventDelegate?.pagingAdapter(
                self,
                didUpdatePagingSurface: surface
            )
        }
        pagingSurfaceObservation.onPanStateChanged = { [weak self] state in
            guard let self else { return }
            eventDelegate?.pagingAdapter(self, pagingPanDidChange: state)
        }
    }

    private func refreshPagingSurfaceObservation() {
        pagingSurfaceObservation.refresh(in: self)
    }

    private func recordWillSelectCallback(at index: Int) {
        if let pendingPageboySelectionIndex {
            if pendingPageboySelectionIndex == index {
                AnchorPagerLogger.log(.debug, category: .paging, event: "paging.callback.duplicateWillSelect")
            } else {
                AnchorPagerLogger.log(.debug, category: .paging, event: "paging.callback.outOfOrder")
            }
        }

        pendingPageboySelectionIndex = index
    }

    private func recordTerminalSelectionCallback(at index: Int) {
        guard let pendingPageboySelectionIndex else {
            if executingSelection?.request.targetIndex == index {
                return
            }
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.callback.missingWillSelect")
            return
        }

        guard pendingPageboySelectionIndex == index else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.callback.outOfOrder")
            return
        }

        self.pendingPageboySelectionIndex = nil
    }

    func finishProgrammaticTransition(
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
        targetIndex: Int,
        finished: Bool
    ) {
        guard let execution = executingSelection,
              execution.request.source.isExplicit,
              execution.request.identifier == requestIdentifier,
              execution.request.targetIndex == targetIndex else {
            logStaleSelectionTerminal()
            return
        }

        executingSelection = nil
        if pendingPageboySelectionIndex == targetIndex {
            pendingPageboySelectionIndex = nil
        }
        if execution.request.animated {
            executorReadyRequestIdentifier = requestIdentifier
        }
        eventDelegate?.pagingAdapter(
            self,
            didComplete: requestIdentifier,
            finished: finished,
            currentIndex: currentIndex
        )
        if !execution.request.animated {
            publishExecutorReady(requestIdentifier)
        }
        notifyReloadReadinessIfNeeded()
    }

    private func requestIdentifierForWillSelect(
        at index: Int,
        animated: Bool
    ) -> AnchorPagerPagingSelectionRequestIdentifier? {
        if let execution = executingSelection {
            guard execution.request.targetIndex == index else {
                logStaleSelectionTerminal()
                return nil
            }
            return execution.request.identifier
        }

        guard let requestIdentifier = eventDelegate?.pagingAdapter(
            self,
            didBeginInteractiveSelectionAt: index,
            animated: animated
        ) else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.selection.reject")
            return nil
        }
        let request = AnchorPagerPagingSelectionRequest(
            identifier: requestIdentifier,
            targetIndex: index,
            animated: animated,
            source: .interactive
        )
        executingSelection = ExecutingSelection(
            request: request,
            previousIndex: committedSelectedIndex
        )
        return requestIdentifier
    }

    private func matchingExecution(at index: Int) -> ExecutingSelection? {
        guard let executingSelection,
              executingSelection.request.targetIndex == index else {
            return nil
        }
        return executingSelection
    }

    private func finishInteractiveExecutionIfNeeded(_ execution: ExecutingSelection) {
        guard execution.request.source == .interactive,
              executingSelection == execution else {
            return
        }
        executingSelection = nil
        notifyReloadReadinessIfNeeded()
    }

    private func publishExecutorReadyIfPossible() {
        guard isUserInteractionEnabled,
              let requestIdentifier = executorReadyRequestIdentifier else {
            return
        }
        executorReadyRequestIdentifier = nil
        publishExecutorReady(requestIdentifier)
        notifyReloadReadinessIfNeeded()
    }

    private func publishExecutorReady(
        _ requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    ) {
        AnchorPagerLogger.log(
            .debug,
            category: .paging,
            event: "paging.selection.executorReady"
        )
        eventDelegate?.pagingAdapter(
            self,
            executorDidBecomeReadyFor: requestIdentifier
        )
    }

    private func cancelSelectionExecutionStructurally() {
        pendingPageboySelectionIndex = nil
        executingSelection = nil
        executorReadyRequestIdentifier = nil
    }

    private func notifyReloadReadinessIfNeeded() {
        if isReadyForReload {
            eventDelegate?.pagingAdapterDidBecomeReadyForReload(self)
        }
    }

    private func logStaleSelectionTerminal() {
        AnchorPagerLogger.log(
            .debug,
            category: .paging,
            event: "paging.selection.staleTerminal"
        )
    }

    private func installBarIfNeeded() {
        guard bars.isEmpty else { return }
        let bar = AnchorPagerTabBarAdapter.makeDefaultBar()
        installedBar = bar
        addBar(bar, dataSource: self, at: .top)
        updateBarHeightConstraintIfNeeded()
    }

    private func updateBarHeightConstraintIfNeeded() {
        guard let installedBar else { return }

        if let requestedBarHeight {
            let constraint = barHeightConstraint
                ?? installedBar.heightAnchor.constraint(equalToConstant: requestedBarHeight)
            constraint.constant = requestedBarHeight
            constraint.isActive = true
            barHeightConstraint = constraint
        } else {
            barHeightConstraint?.isActive = false
            barHeightConstraint = nil
        }
        viewIfLoaded?.setNeedsLayout()
    }

    private func sanitizedBarInsets(_ insets: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: sanitizedInset(insets.top),
            left: sanitizedInset(insets.left),
            bottom: sanitizedInset(insets.bottom),
            right: sanitizedInset(insets.right)
        )
    }

    private func sanitizedInset(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return Swift.max(0, value)
    }
}
