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
    private struct ReloadRequest {
        let titles: [String]
        let pageCount: Int
        let selectedIndex: Int
    }

    weak var pageProvider: AnchorPagerPageProviding? {
        didSet {
            activeAdapter?.pageProvider = pageProvider
        }
    }

    weak var eventDelegate: AnchorPagerPagingHostViewControllerDelegate?
    private(set) var activeAdapter: AnchorPagerPagingAdapter?

    private var requestedBarHeight: CGFloat?
    private var lastReportedBarInsets: UIEdgeInsets = .zero
    private var activeAdapterConstraints: [NSLayoutConstraint] = []
    private var pendingReloadRequest: ReloadRequest?

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        self.view = view
    }

    func reload(titles: [String], pageCount: Int, selectedIndex: Int) {
        let request = ReloadRequest(
            titles: titles,
            pageCount: pageCount,
            selectedIndex: selectedIndex
        )
        if let activeAdapter, !activeAdapter.isReadyForReload {
            pendingReloadRequest = request
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.reload.deferred")
            return
        }

        pendingReloadRequest = nil
        performReload(request)
    }

    private func performReload(_ request: ReloadRequest) {
        guard request.pageCount > 0 else {
            guard removeActiveAdapterIfNeeded(pendingRequestOnFailure: request) else { return }
            reportZeroBarInsetsIfNeeded()
            AnchorPagerLogger.log(.info, category: .paging, event: "paging.reload.empty")
            eventDelegate?.pagingHost(self, didReload: .empty)
            return
        }

        let adapter = activeAdapter ?? installAdapter()
        adapter.pageProvider = pageProvider
        adapter.reload(
            titles: request.titles,
            pageCount: request.pageCount,
            selectedIndex: request.selectedIndex
        )
    }

    func setBarHeight(_ height: CGFloat?) {
        requestedBarHeight = height
        activeAdapter?.setBarHeight(height)
    }

    @discardableResult
    func setSelectedIndex(_ index: Int, animated: Bool) -> Bool {
        guard pendingReloadRequest == nil else {
            AnchorPagerLogger.log(
                .debug,
                category: .paging,
                event: "paging.setSelectedIndex.reloadPending"
            )
            return false
        }
        return activeAdapter?.setSelectedIndex(index, animated: animated) ?? false
    }

    private func installAdapter() -> AnchorPagerPagingAdapter {
        let adapter = AnchorPagerPagingAdapter()
        adapter.pageProvider = pageProvider
        adapter.eventDelegate = self
        adapter.setBarHeight(requestedBarHeight)

        addChild(adapter)
        adapter.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(adapter.view)
        let constraints = [
            adapter.view.topAnchor.constraint(equalTo: view.topAnchor),
            adapter.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            adapter.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            adapter.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        activeAdapterConstraints = constraints
        adapter.didMove(toParent: self)
        activeAdapter = adapter
        AnchorPagerLogger.log(.debug, category: .lifecycle, event: "paging.adapter.install")
        return adapter
    }

    @discardableResult
    private func removeActiveAdapterIfNeeded(
        pendingRequestOnFailure request: ReloadRequest
    ) -> Bool {
        guard let adapter = activeAdapter else { return true }
        guard adapter.prepareForRemoval() else {
            pendingReloadRequest = request
            AnchorPagerAssertions.failure(
                "AnchorPager could not synchronously prepare the paging adapter for removal."
            )
            AnchorPagerLogger.log(
                .error,
                category: .paging,
                event: "paging.adapter.remove.rejected"
            )
            return false
        }

        adapter.willMove(toParent: nil)
        NSLayoutConstraint.deactivate(activeAdapterConstraints)
        activeAdapterConstraints = []
        adapter.view.removeFromSuperview()
        adapter.removeFromParent()
        activeAdapter = nil
        AnchorPagerLogger.log(.debug, category: .lifecycle, event: "paging.adapter.remove")
        return true
    }

    @discardableResult
    private func performPendingReloadIfNeeded() -> Bool {
        guard let request = pendingReloadRequest else { return false }
        guard activeAdapter?.isReadyForReload != false else { return true }
        pendingReloadRequest = nil
        performReload(request)
        return true
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
        guard !performPendingReloadIfNeeded() else { return }
        eventDelegate?.pagingHost(self, didSelect: index, animated: animated)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int
    ) {
        guard adapter === activeAdapter else { return }
        guard !performPendingReloadIfNeeded() else { return }
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

    func pagingAdapterDidBecomeReadyForReload(_ adapter: AnchorPagerPagingAdapter) {
        guard adapter === activeAdapter else { return }
        _ = performPendingReloadIfNeeded()
    }
}
