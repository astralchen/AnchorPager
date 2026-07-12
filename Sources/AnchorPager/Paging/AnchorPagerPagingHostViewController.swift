import UIKit

typealias AnchorPagerPagingReloadRequestIdentifier = Int

@MainActor
enum AnchorPagerPagingReloadTerminal: Equatable {
    case page(index: Int)
    case empty
}

@MainActor
protocol AnchorPagerPagingHostViewControllerDelegate: AnyObject {
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willPerformReloadRequest identifier: AnchorPagerPagingReloadRequestIdentifier
    ) -> Bool
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    )
    // Task 3 接入请求标识后删除该兼容协议方法。
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

extension AnchorPagerPagingHostViewControllerDelegate {
    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        willPerformReloadRequest identifier: AnchorPagerPagingReloadRequestIdentifier
    ) -> Bool {
        true
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    ) {
        pagingHost(host, didReload: terminal)
    }

    func pagingHost(
        _ host: AnchorPagerPagingHostViewController,
        didReload terminal: AnchorPagerPagingReloadTerminal
    ) {}
}

@MainActor
final class AnchorPagerPagingHostViewController: UIViewController {
    private struct ReloadRequest {
        let identifier: AnchorPagerPagingReloadRequestIdentifier
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
    private var activeReloadRequest: ReloadRequest?
    private var finishingReloadRequestIdentifier: AnchorPagerPagingReloadRequestIdentifier?
    private var isStartingReloadRequest = false
    private var nextCompatibilityRequestIdentifier = -1

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        self.view = view
    }

    // Task 3 接入显式请求标识后删除该兼容入口。
    func reload(titles: [String], pageCount: Int, selectedIndex: Int) {
        let requestIdentifier = nextCompatibilityRequestIdentifier
        nextCompatibilityRequestIdentifier -= 1
        reload(
            requestIdentifier: requestIdentifier,
            titles: titles,
            pageCount: pageCount,
            selectedIndex: selectedIndex
        )
    }

    func reload(
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier,
        titles: [String],
        pageCount: Int,
        selectedIndex: Int
    ) {
        let request = ReloadRequest(
            identifier: requestIdentifier,
            titles: titles,
            pageCount: pageCount,
            selectedIndex: selectedIndex
        )
        if activeReloadRequest != nil ||
            isStartingReloadRequest ||
            activeAdapter?.isReadyForReload == false {
            pendingReloadRequest = request
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.reload.deferred")
            return
        }

        pendingReloadRequest = nil
        _ = performReload(request)
    }

    @discardableResult
    private func performReload(_ request: ReloadRequest) -> Bool {
        isStartingReloadRequest = true
        let shouldPerform = eventDelegate?.pagingHost(
            self,
            willPerformReloadRequest: request.identifier
        ) ?? true
        isStartingReloadRequest = false

        guard shouldPerform else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.reload.stale")
            _ = performPendingReloadIfNeeded()
            return false
        }

        activeReloadRequest = request
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.reload.begin")
        guard request.pageCount > 0 else {
            guard removeActiveAdapterIfNeeded(pendingRequestOnFailure: request) else {
                activeReloadRequest = nil
                return false
            }
            reportZeroBarInsetsIfNeeded()
            AnchorPagerLogger.log(.info, category: .paging, event: "paging.reload.empty")
            finishActiveReload(with: .empty, requestIdentifier: request.identifier)
            return true
        }

        let adapter = activeAdapter ?? installAdapter()
        adapter.pageProvider = pageProvider
        adapter.reload(
            requestIdentifier: request.identifier,
            titles: request.titles,
            pageCount: request.pageCount,
            selectedIndex: request.selectedIndex
        )
        return true
    }

    func setBarHeight(_ height: CGFloat?) {
        requestedBarHeight = height
        activeAdapter?.setBarHeight(height)
    }

    @discardableResult
    func setSelectedIndex(_ index: Int, animated: Bool) -> Bool {
        guard pendingReloadRequest == nil,
              activeReloadRequest == nil,
              !isStartingReloadRequest else {
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
        guard activeReloadRequest == nil, !isStartingReloadRequest else { return true }
        guard activeAdapter?.isReadyForReload != false else { return true }
        pendingReloadRequest = nil
        _ = performReload(request)
        return true
    }

    private func finishActiveReload(
        with terminal: AnchorPagerPagingReloadTerminal,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    ) {
        guard finishingReloadRequestIdentifier == nil,
              let request = activeReloadRequest,
              request.identifier == requestIdentifier else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.reload.stale")
            return
        }
        finishingReloadRequestIdentifier = requestIdentifier
        eventDelegate?.pagingHost(
            self,
            didReload: terminal,
            requestIdentifier: request.identifier
        )
        activeReloadRequest = nil
        finishingReloadRequestIdentifier = nil
        _ = performPendingReloadIfNeeded()
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
        AnchorPagerLogger.log(.debug, category: .paging, event: "paging.reload.stale")
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didReloadAt index: Int,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    ) {
        guard adapter === activeAdapter else { return }
        finishActiveReload(
            with: .page(index: index),
            requestIdentifier: requestIdentifier
        )
    }

    func pagingAdapterDidBecomeReadyForReload(_ adapter: AnchorPagerPagingAdapter) {
        guard adapter === activeAdapter else { return }
        _ = performPendingReloadIfNeeded()
    }
}
