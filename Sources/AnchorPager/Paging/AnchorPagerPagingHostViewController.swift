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
        finalBarInsets: UIEdgeInsets,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    ) -> Bool
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
    private var activeReloadFinalBarInsets: UIEdgeInsets?
    private var finishingReloadRequestIdentifier: AnchorPagerPagingReloadRequestIdentifier?
    private var isStartingReloadRequest = false
    private var isPagePresentationSurfaceUnavailable = false
    // Task 3 会把 identifier 与 active/latest pending transaction 一并收口到 Host。
    private var nextSelectionRequestIdentifier: AnchorPagerPagingSelectionRequestIdentifier = 1

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        self.view = view
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
        activeReloadFinalBarInsets = lastReportedBarInsets
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.reload.begin")
        guard request.pageCount > 0 else {
            guard removeActiveAdapterIfNeeded(pendingRequestOnFailure: request) else {
                activeReloadRequest = nil
                activeReloadFinalBarInsets = nil
                return false
            }
            activeReloadFinalBarInsets = .zero
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
    func setPagePresentationTranslationY(_ translationY: CGFloat) -> Bool {
        let didApply = activeAdapter?.setPagePresentationTranslationY(translationY)
            ?? (translationY == 0)
        let isUnavailable = !didApply && translationY != 0
        if isUnavailable && !isPagePresentationSurfaceUnavailable {
            AnchorPagerLogger.log(
                .error,
                category: .paging,
                event: "paging.pagePresentation.unavailable"
            )
        }
        isPagePresentationSurfaceUnavailable = isUnavailable
        return didApply
    }

    @discardableResult
    func setSelectedIndex(_ index: Int, animated: Bool) -> Bool {
        executeSelection(index: index, animated: animated, source: .api)
    }

    @discardableResult
    private func executeSelection(
        index: Int,
        animated: Bool,
        source: AnchorPagerPagingSelectionSource
    ) -> Bool {
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
        guard let activeAdapter else { return false }
        let requestIdentifier = nextSelectionRequestIdentifier
        nextSelectionRequestIdentifier += 1
        let request = AnchorPagerPagingSelectionRequest(
            identifier: requestIdentifier,
            targetIndex: index,
            animated: animated,
            source: source
        )
        return activeAdapter.executeSelection(
            request,
            previousIndex: activeAdapter.currentIndex ?? index
        )
    }

    private func installAdapter() -> AnchorPagerPagingAdapter {
        isPagePresentationSurfaceUnavailable = false
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
        _ = setPagePresentationTranslationY(0)
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
        isPagePresentationSurfaceUnavailable = false
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
        let finalBarInsets = activeReloadFinalBarInsets ?? lastReportedBarInsets
        let didCommitTerminal = eventDelegate?.pagingHost(
            self,
            didReload: terminal,
            finalBarInsets: finalBarInsets,
            requestIdentifier: request.identifier
        ) ?? true
        activeReloadRequest = nil
        activeReloadFinalBarInsets = nil
        if didCommitTerminal {
            lastReportedBarInsets = finalBarInsets
        }
        finishingReloadRequestIdentifier = nil
        _ = performPendingReloadIfNeeded()
    }

}

extension AnchorPagerPagingHostViewController: AnchorPagerPagingAdapterDelegate {
    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didRequestBarSelectionAt index: Int
    ) {
        guard adapter === activeAdapter else { return }
        _ = executeSelection(index: index, animated: true, source: .bar)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didBeginInteractiveSelectionAt index: Int,
        animated: Bool
    ) -> AnchorPagerPagingSelectionRequestIdentifier? {
        guard adapter === activeAdapter else { return nil }
        let requestIdentifier = nextSelectionRequestIdentifier
        nextSelectionRequestIdentifier += 1
        return requestIdentifier
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        willSelect index: Int,
        animated: Bool,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    ) {
        guard adapter === activeAdapter else { return }
        pagingAdapter(adapter, willSelect: index, animated: animated)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didSelect index: Int,
        animated: Bool,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    ) {
        guard adapter === activeAdapter else { return }
        pagingAdapter(adapter, didSelect: index, animated: animated)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    ) {
        guard adapter === activeAdapter else { return }
        pagingAdapter(
            adapter,
            didCancelSelectionAt: index,
            returningTo: previousIndex
        )
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didComplete requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
        finished: Bool,
        currentIndex: Int?
    ) {
        guard adapter === activeAdapter else { return }
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        executorDidBecomeReadyFor requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    ) {
        guard adapter === activeAdapter else { return }
    }

    // Task 2 的签名兼容入口；Task 3 建立 transaction 后由 matching callback 直接提交。
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
        if activeReloadRequest != nil {
            activeReloadFinalBarInsets = barInsets
            return
        }
        lastReportedBarInsets = barInsets
        eventDelegate?.pagingHost(self, didUpdateBarInsets: barInsets)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didReloadAt index: Int,
        terminalBarInsets: UIEdgeInsets,
        requestIdentifier: AnchorPagerPagingReloadRequestIdentifier
    ) {
        guard adapter === activeAdapter,
              activeReloadRequest?.identifier == requestIdentifier else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.reload.stale")
            return
        }
        activeReloadFinalBarInsets = terminalBarInsets
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
