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
    func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, didReloadAt index: Int)
}

extension AnchorPagerPagingAdapterDelegate {
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {}
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
    private var installedBar: TMBar?
    private var barHeightConstraint: NSLayoutConstraint?
    private var requestedBarHeight: CGFloat?
    private var lastReportedBarInsets: UIEdgeInsets?
    private var reloadSelectionCallbackSuppressionDepth = 0

    private struct ProgrammaticSelection: Equatable {
        let index: Int
        let previousIndex: Int
        let animated: Bool
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

        if isViewLoaded {
            reloadSelectionCallbackSuppressionDepth += 1
            reloadData()
            reloadSelectionCallbackSuppressionDepth -= 1
            bars.forEach { bar in
                if configuredPageCount > 0 {
                    bar.reloadData(at: 0...configuredPageCount - 1, context: .full)
                }
            }
        }
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.reload")
    }

    @discardableResult
    func setSelectedIndex(_ index: Int, animated: Bool) -> Bool {
        guard (0..<configuredPageCount).contains(index) else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.setSelectedIndex.outOfRange")
            return false
        }

        AnchorPagerLogger.log(.info, category: .paging, event: "paging.setSelectedIndex.request")
        let previousProgrammaticSelection = pendingProgrammaticSelection
        let requestedSelection = ProgrammaticSelection(
            index: index,
            previousIndex: committedSelectedIndex,
            animated: animated
        )
        pendingProgrammaticSelection = requestedSelection

        let didStartScroll = scrollToPage(.at(index: index), animated: animated) { [weak self] _, _, finished in
            self?.finishProgrammaticSelection(at: index, finished: finished)
        }
        if !didStartScroll {
            pendingProgrammaticSelection = previousProgrammaticSelection
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
        eventDelegate?.pagingAdapter(self, didReloadAt: currentPageIndex)
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
