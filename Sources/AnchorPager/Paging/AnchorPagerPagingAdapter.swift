import Pageboy
import Tabman
import UIKit

@MainActor
protocol AnchorPagerPageProviding: AnyObject {
    func pageViewController(at index: Int) -> UIViewController?
}

@MainActor
protocol AnchorPagerPagingAdapterDelegate: AnyObject {
    func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, willSelect index: Int, animated: Bool)
    func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, didSelect index: Int, animated: Bool)
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdateBarInsets barInsets: UIEdgeInsets
    )
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didReloadAt index: Int,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    )
    func pagingAdapterDidBecomeReadyForReload(_ adapter: AnchorPagerPagingAdapter)
}

extension AnchorPagerPagingAdapterDelegate {
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
    private var pendingProgrammaticSelection: ProgrammaticSelection?
    private var isProgrammaticTransitionCompletionPending = false
    private var installedBar: TMBar?
    private var barHeightConstraint: NSLayoutConstraint?
    private var requestedBarHeight: CGFloat?
    private var lastReportedBarInsets: UIEdgeInsets?
    private var reloadSelectionCallbackSuppressionDepth = 0
    // 只在对应同步 reloadData 调用栈内存在，避免晚到回调借用后续 request 标识。
    private var reloadCallbackRequestIdentifier: AnchorPagerPagingReloadRequestIdentifier?

    private struct ProgrammaticSelection: Equatable {
        let index: Int
        let previousIndex: Int
        let animated: Bool
    }

    /// 当前是否可以同步执行 Pageboy reload 或空态 teardown。
    ///
    /// 该查询只读取 AnchorPager 已有 selection 状态和 Pageboy public 滚动状态，
    /// 不得修改 data source 或第三方状态。
    var isReadyForReload: Bool {
        pendingPageboySelectionIndex == nil &&
            pendingProgrammaticSelection == nil &&
            !isProgrammaticTransitionCompletionPending
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
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

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
        pendingPageboySelectionIndex = nil
        pendingProgrammaticSelection = nil
        isProgrammaticTransitionCompletionPending = false

        if isViewLoaded {
            let previousRequestIdentifier = reloadCallbackRequestIdentifier
            reloadCallbackRequestIdentifier = requestIdentifier
            reloadSelectionCallbackSuppressionDepth += 1
            reloadData()
            reloadSelectionCallbackSuppressionDepth -= 1
            reloadCallbackRequestIdentifier = previousRequestIdentifier
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
        let oldPageCount = pageCount ?? 0
        let deletionIndex = Swift.min(
            Swift.max(0, committedSelectedIndex),
            Swift.max(0, oldPageCount - 1)
        )
        titles = []
        configuredPageCount = 0
        defaultSelectedIndex = 0
        committedSelectedIndex = 0
        pendingPageboySelectionIndex = nil
        pendingProgrammaticSelection = nil
        isProgrammaticTransitionCompletionPending = false

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
    func setSelectedIndex(_ index: Int, animated: Bool) -> Bool {
        guard (0..<configuredPageCount).contains(index) else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.setSelectedIndex.outOfRange")
            return false
        }

        AnchorPagerLogger.log(.info, category: .paging, event: "paging.setSelectedIndex.request")
        let previousProgrammaticSelection = pendingProgrammaticSelection
        let previousProgrammaticTransitionCompletionPending =
            isProgrammaticTransitionCompletionPending
        let requestedSelection = ProgrammaticSelection(
            index: index,
            previousIndex: committedSelectedIndex,
            animated: animated
        )
        pendingProgrammaticSelection = requestedSelection
        isProgrammaticTransitionCompletionPending = true

        let didStartScroll = scrollToPage(.at(index: index), animated: animated) { [weak self] _, _, finished in
            self?.finishProgrammaticTransition(at: index, finished: finished)
        }
        if !didStartScroll {
            pendingProgrammaticSelection = previousProgrammaticSelection
            isProgrammaticTransitionCompletionPending =
                previousProgrammaticTransitionCompletionPending
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.setSelectedIndex.rejected")
        }
        return didStartScroll
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
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.willSelect")
        recordWillSelectCallback(at: index)
        eventDelegate?.pagingAdapter(self, willSelect: index, animated: animated)
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
        committedSelectedIndex = index
        clearProgrammaticSelectionIfNeeded(at: index)
        eventDelegate?.pagingAdapter(self, didSelect: index, animated: animated)
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
        let didFinishProgrammaticSelection = finishProgrammaticSelection(at: index, finished: false)
        if !didFinishProgrammaticSelection {
            eventDelegate?.pagingAdapter(
                self,
                didCancelSelectionAt: index,
                returningTo: previousIndex
            )
        }
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
        if let reloadCallbackRequestIdentifier {
            view.layoutIfNeeded()
            eventDelegate?.pagingAdapter(
                self,
                didReloadAt: currentPageIndex,
                requestIdentifier: reloadCallbackRequestIdentifier
            )
        } else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.reload.stale")
        }
    }

    private func configure() {
        automaticallyAdjustsChildInsets = false
        dataSource = self
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
            if pendingProgrammaticSelection?.index == index {
                return
            }
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.callback.missingWillSelect")
            return
        }

        if pendingPageboySelectionIndex != index {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.callback.outOfOrder")
        }

        self.pendingPageboySelectionIndex = nil
    }

    private func clearProgrammaticSelectionIfNeeded(at index: Int) {
        guard pendingProgrammaticSelection?.index == index else { return }
        pendingProgrammaticSelection = nil
    }

    func finishProgrammaticTransition(at index: Int, finished: Bool) {
        isProgrammaticTransitionCompletionPending = false
        _ = finishProgrammaticSelection(at: index, finished: finished)
        if isReadyForReload {
            eventDelegate?.pagingAdapterDidBecomeReadyForReload(self)
        }
    }

    @discardableResult
    private func finishProgrammaticSelection(at index: Int, finished: Bool) -> Bool {
        guard let pendingProgrammaticSelection,
              pendingProgrammaticSelection.index == index else {
            return false
        }

        self.pendingProgrammaticSelection = nil
        if finished {
            committedSelectedIndex = index
            eventDelegate?.pagingAdapter(
                self,
                didSelect: index,
                animated: pendingProgrammaticSelection.animated
            )
        } else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.setSelectedIndex.cancel")
            eventDelegate?.pagingAdapter(
                self,
                didCancelSelectionAt: index,
                returningTo: pendingProgrammaticSelection.previousIndex
            )
        }
        return true
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
