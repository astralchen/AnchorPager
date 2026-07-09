import Pageboy
import Tabman
import UIKit

@MainActor
protocol AnchorPagerPagingAdapterDelegate: AnyObject {
    func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, willSelect index: Int, animated: Bool)
    func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, didSelect index: Int, animated: Bool)
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    )
}

@MainActor
final class AnchorPagerPagingAdapter: TabmanViewController, PageboyViewControllerDataSource, TMBarDataSource {
    weak var eventDelegate: AnchorPagerPagingAdapterDelegate?

    private var titles: [String] = []
    private var viewControllers: [UIViewController] = []
    private var defaultSelectedIndex = 0
    private var pendingSelectionIndex: Int?

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
        super.viewDidLoad()
        installBarIfNeeded()
    }

    func reload(
        titles: [String],
        viewControllers: [UIViewController],
        selectedIndex: Int
    ) {
        self.titles = titles
        self.viewControllers = viewControllers
        if viewControllers.indices.contains(selectedIndex) {
            defaultSelectedIndex = selectedIndex
        } else {
            defaultSelectedIndex = 0
        }
        pendingSelectionIndex = nil

        dataSource = self
        if isViewLoaded {
            reloadData()
            bars.forEach { bar in
                if !viewControllers.isEmpty {
                    bar.reloadData(at: 0...viewControllers.count - 1, context: .full)
                }
            }
        }
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.reload")
    }

    func setSelectedIndex(_ index: Int, animated: Bool) {
        guard viewControllers.indices.contains(index) else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.setSelectedIndex.outOfRange")
            return
        }

        AnchorPagerLogger.log(.info, category: .paging, event: "paging.setSelectedIndex.request")
        scrollToPage(.at(index: index), animated: animated, completion: nil)
    }

    func numberOfViewControllers(in pageboyViewController: PageboyViewController) -> Int {
        viewControllers.count
    }

    func viewController(
        for pageboyViewController: PageboyViewController,
        at index: PageboyViewController.PageIndex
    ) -> UIViewController? {
        guard viewControllers.indices.contains(index) else { return nil }
        return viewControllers[index]
    }

    func defaultPage(for pageboyViewController: PageboyViewController) -> PageboyViewController.Page? {
        guard viewControllers.indices.contains(defaultSelectedIndex) else { return nil }
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
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.didSelect")
        recordTerminalSelectionCallback(at: index)
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
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.didCancel")
        recordTerminalSelectionCallback(at: index)
        eventDelegate?.pagingAdapter(
            self,
            didCancelSelectionAt: index,
            returningTo: previousIndex
        )
    }

    private func configure() {
        automaticallyAdjustsChildInsets = false
        dataSource = self
    }

    private func recordWillSelectCallback(at index: Int) {
        if let pendingSelectionIndex {
            if pendingSelectionIndex == index {
                AnchorPagerLogger.log(.debug, category: .paging, event: "paging.callback.duplicateWillSelect")
            } else {
                AnchorPagerLogger.log(.debug, category: .paging, event: "paging.callback.outOfOrder")
            }
        }

        pendingSelectionIndex = index
    }

    private func recordTerminalSelectionCallback(at index: Int) {
        guard let pendingSelectionIndex else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.callback.missingWillSelect")
            return
        }

        if pendingSelectionIndex != index {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.callback.outOfOrder")
        }

        self.pendingSelectionIndex = nil
    }

    private func installBarIfNeeded() {
        guard bars.isEmpty else { return }
        let bar = AnchorPagerTabBarAdapter.makeDefaultBar()
        addBar(bar, dataSource: self, at: .top)
    }
}
