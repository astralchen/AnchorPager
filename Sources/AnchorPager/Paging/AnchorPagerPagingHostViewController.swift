import UIKit

@MainActor
enum AnchorPagerPagingReloadTerminal: Equatable {
    case page(index: Int)
    case empty
}

@MainActor
protocol AnchorPagerPagingHostViewControllerDelegate: AnyObject {
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal
    )
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willSelect index: Int,
        animated: Bool
    )
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didSelect index: Int,
        animated: Bool
    )
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    )
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didUpdateBarInsets barInsets: UIEdgeInsets
    )
}

@MainActor
final class AnchorPagerPagingHostViewController: UIViewController {
    weak var pageProvider: AnchorPagerPageProviding? {
        didSet {
            activeAdapter?.pageProvider = pageProvider
        }
    }

    weak var eventDelegate: AnchorPagerPagingHostViewControllerDelegate?
    private(set) var activeAdapter: AnchorPagerPagingAdapter?

    private var requestedBarHeight: CGFloat?
    private var lastReportedBarInsets: UIEdgeInsets = .zero

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        self.view = view
    }

    func reload(titles: [String], pageCount: Int, selectedIndex: Int) {
        guard pageCount > 0 else {
            removeActiveAdapterIfNeeded()
            reportZeroBarInsetsIfNeeded()
            AnchorPagerLogger.log(.info, category: .paging, event: "paging.reload.empty")
            eventDelegate?.pagingHost(self, didReload: .empty)
            return
        }

        let adapter = activeAdapter ?? installAdapter()
        adapter.pageProvider = pageProvider
        adapter.reload(titles: titles, pageCount: pageCount, selectedIndex: selectedIndex)
    }

    func setBarHeight(_ height: CGFloat?) {
        requestedBarHeight = height
        activeAdapter?.setBarHeight(height)
    }

    @discardableResult
    func setSelectedIndex(_ index: Int, animated: Bool) -> Bool {
        activeAdapter?.setSelectedIndex(index, animated: animated) ?? false
    }

    private func installAdapter() -> AnchorPagerPagingAdapter {
        let adapter = AnchorPagerPagingAdapter()
        adapter.pageProvider = pageProvider
        adapter.eventDelegate = self
        adapter.setBarHeight(requestedBarHeight)

        addChild(adapter)
        adapter.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(adapter.view)
        NSLayoutConstraint.activate([
            adapter.view.topAnchor.constraint(equalTo: view.topAnchor),
            adapter.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            adapter.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            adapter.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        adapter.didMove(toParent: self)
        activeAdapter = adapter
        AnchorPagerLogger.log(.debug, category: .lifecycle, event: "paging.adapter.install")
        return adapter
    }

    private func removeActiveAdapterIfNeeded() {
        guard let adapter = activeAdapter else { return }

        adapter.willMove(toParent: nil)
        adapter.view.removeFromSuperview()
        adapter.removeFromParent()
        activeAdapter = nil
        AnchorPagerLogger.log(.debug, category: .lifecycle, event: "paging.adapter.remove")
    }

    private func reportZeroBarInsetsIfNeeded() {
        guard lastReportedBarInsets != .zero else { return }
        lastReportedBarInsets = .zero
        eventDelegate?.pagingHost(self, didUpdateBarInsets: .zero)
    }
}

extension AnchorPagerPagingHostViewController: AnchorPagerPagingAdapterDelegate {
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        willSelect index: Int,
        animated: Bool
    ) {
        guard adapter === activeAdapter else { return }
        eventDelegate?.pagingHost(self, willSelect: index, animated: animated)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didSelect index: Int,
        animated: Bool
    ) {
        guard adapter === activeAdapter else { return }
        eventDelegate?.pagingHost(self, didSelect: index, animated: animated)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    ) {
        guard adapter === activeAdapter else { return }
        eventDelegate?.pagingHost(
            self,
            didCancelSelectionAt: index,
            returningTo: previousIndex
        )
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didUpdateBarInsets barInsets: UIEdgeInsets
    ) {
        guard adapter === activeAdapter else { return }
        lastReportedBarInsets = barInsets
        eventDelegate?.pagingHost(self, didUpdateBarInsets: barInsets)
    }

    func pagingAdapter(_ adapter: AnchorPagerPagingAdapter, didReloadAt index: Int) {
        guard adapter === activeAdapter else { return }
        eventDelegate?.pagingHost(self, didReload: .page(index: index))
    }
}
