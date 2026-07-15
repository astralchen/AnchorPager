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
    private var nextSelectionRequestIdentifier: AnchorPagerPagingSelectionRequestIdentifier = 1
    private var committedSelectionIndex: Int?
    private var committedSelectionPageCount = 0
    private var activeSelectionTransaction: AnchorPagerPagingSelectionTransaction?
    private var pendingExplicitSelectionRequest: AnchorPagerPagingSelectionRequest?
    private var forwardedWillSelectRequestIdentifier: AnchorPagerPagingSelectionRequestIdentifier?

    var activeSelectionRequestForTesting: AnchorPagerPagingSelectionRequest? {
        activeSelectionTransaction?.request
    }

    var pendingExplicitSelectionRequestForTesting: AnchorPagerPagingSelectionRequest? {
        pendingExplicitSelectionRequest
    }

    var committedSelectionIndexForTesting: Int? {
        committedSelectionIndex
    }

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
        pendingExplicitSelectionRequest = nil
        if activeReloadRequest != nil ||
            isStartingReloadRequest ||
            activeAdapter?.isReadyForReload == false ||
            shouldWaitForActiveSelection(before: request) {
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
        enqueueSelection(index: index, animated: animated, source: .api)
    }

    @discardableResult
    func enqueueSelection(
        index: Int,
        animated: Bool,
        source: AnchorPagerPagingSelectionSource
    ) -> Bool {
        guard source.isExplicit else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.selection.reject")
            return false
        }
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
        guard let activeAdapter,
              (0..<committedSelectionPageCount).contains(index),
              let committedSelectionIndex else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.selection.reject")
            return false
        }

        let request = AnchorPagerPagingSelectionRequest(
            identifier: nextSelectionRequestIdentifier,
            targetIndex: index,
            animated: animated,
            source: source
        )
        let admission = AnchorPagerPagingExplicitSelectionAdmission.resolve(
            request: request,
            committedIndex: committedSelectionIndex,
            activeRequest: activeSelectionTransaction?.request,
            pendingRequest: pendingExplicitSelectionRequest
        )
        switch admission {
        case .start:
            nextSelectionRequestIdentifier += 1
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.selection.enqueue")
            return startSelection(request, on: activeAdapter)
        case .replaceLatest:
            nextSelectionRequestIdentifier += 1
            let didReplace = pendingExplicitSelectionRequest != nil
            pendingExplicitSelectionRequest = request
            AnchorPagerLogger.log(
                .debug,
                category: .paging,
                event: didReplace
                    ? "paging.selection.replacePending"
                    : "paging.selection.enqueue"
            )
            return true
        case .noOp, .duplicate, .rejectedInteractive:
            return false
        }
    }

    @discardableResult
    func performPendingSelectionIfPossible() -> Bool {
        guard activeSelectionTransaction == nil,
              pendingReloadRequest == nil,
              activeReloadRequest == nil,
              !isStartingReloadRequest,
              let adapter = activeAdapter,
              let request = pendingExplicitSelectionRequest else {
            return false
        }
        pendingExplicitSelectionRequest = nil
        guard let committedSelectionIndex,
              (0..<committedSelectionPageCount).contains(request.targetIndex),
              request.targetIndex != committedSelectionIndex else {
            return false
        }
        return startSelection(request, on: adapter)
    }

    @discardableResult
    private func startSelection(
        _ request: AnchorPagerPagingSelectionRequest,
        on adapter: AnchorPagerPagingAdapter
    ) -> Bool {
        guard activeSelectionTransaction == nil,
              adapter === activeAdapter else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.selection.reject")
            return false
        }
        let previousIndex = committedSelectionIndex ?? adapter.currentIndex ?? request.targetIndex
        activeSelectionTransaction = AnchorPagerPagingSelectionTransaction(
            request: request,
            previousIndex: previousIndex,
            adapterIdentifier: ObjectIdentifier(adapter)
        )
        forwardedWillSelectRequestIdentifier = nil
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.selection.start")
        guard adapter.executeSelection(request, previousIndex: previousIndex) else {
            if activeSelectionTransaction?.request.identifier == request.identifier {
                activeSelectionTransaction = nil
                forwardedWillSelectRequestIdentifier = nil
            }
            AnchorPagerLogger.log(.debug, category: .paging, event: "paging.selection.reject")
            if !performPendingReloadIfNeeded() {
                _ = performPendingSelectionIfPossible()
            }
            return false
        }
        return true
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
        cancelActiveSelectionStructurally(for: adapter)

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
        guard !shouldWaitForActiveSelection(before: request) else { return true }
        pendingReloadRequest = nil
        _ = performReload(request)
        return true
    }

    private func shouldWaitForActiveSelection(before request: ReloadRequest) -> Bool {
        guard activeSelectionTransaction != nil else { return false }
        let canStructurallyTeardown = request.pageCount == 0 &&
            activeAdapter?.isReadyForReload == true
        return !canStructurallyTeardown
    }

    private func cancelActiveSelectionStructurally(for adapter: AnchorPagerPagingAdapter) {
        guard let transaction = activeSelectionTransaction,
              transaction.adapterIdentifier == ObjectIdentifier(adapter) else {
            return
        }
        activeSelectionTransaction = nil
        forwardedWillSelectRequestIdentifier = nil
        pendingExplicitSelectionRequest = nil
        AnchorPagerLogger.log(
            .debug,
            category: .paging,
            event: "paging.selection.structuralCancel"
        )
        guard transaction.semanticTerminal == nil else { return }
        eventDelegate?.pagingHost(
            self,
            didCancelSelectionAt: transaction.request.targetIndex,
            returningTo: transaction.previousIndex
        )
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
            switch terminal {
            case let .page(index):
                committedSelectionIndex = index
                committedSelectionPageCount = request.pageCount
            case .empty:
                committedSelectionIndex = nil
                committedSelectionPageCount = 0
            }
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
        _ = enqueueSelection(index: index, animated: true, source: .bar)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didBeginInteractiveSelectionAt index: Int,
        animated: Bool
    ) -> AnchorPagerPagingSelectionRequestIdentifier? {
        guard matchesActiveSelectionAdapter(adapter),
              (0..<committedSelectionPageCount).contains(index) else {
            logStaleSelectionTerminal()
            return nil
        }
        if let transaction = activeSelectionTransaction {
            guard transaction.request.source == .interactive,
                  transaction.request.targetIndex == index,
                  transaction.adapterIdentifier == ObjectIdentifier(adapter) else {
                logStaleSelectionTerminal()
                return nil
            }
            return transaction.request.identifier
        }

        let requestIdentifier = nextSelectionRequestIdentifier
        nextSelectionRequestIdentifier += 1
        let request = AnchorPagerPagingSelectionRequest(
            identifier: requestIdentifier,
            targetIndex: index,
            animated: animated,
            source: .interactive
        )
        activeSelectionTransaction = AnchorPagerPagingSelectionTransaction(
            request: request,
            previousIndex: committedSelectionIndex ?? adapter.currentIndex ?? index,
            adapterIdentifier: ObjectIdentifier(adapter)
        )
        forwardedWillSelectRequestIdentifier = nil
        AnchorPagerLogger.log(.info, category: .paging, event: "paging.selection.start")
        return requestIdentifier
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        willSelect index: Int,
        animated: Bool,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    ) {
        guard matches(
            adapter: adapter,
            requestIdentifier: requestIdentifier,
            targetIndex: index
        ) else {
            logStaleSelectionTerminal()
            return
        }
        guard forwardedWillSelectRequestIdentifier != requestIdentifier else { return }
        forwardedWillSelectRequestIdentifier = requestIdentifier
        eventDelegate?.pagingHost(self, willSelect: index, animated: animated)
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didSelect index: Int,
        animated: Bool,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    ) {
        guard var transaction = matchingSelectionTransaction(
            adapter: adapter,
            requestIdentifier: requestIdentifier,
            targetIndex: index
        ), transaction.recordSemanticTerminal(
            .selected(index: index),
            requestIdentifier: requestIdentifier,
            targetIndex: index,
            adapterIdentifier: ObjectIdentifier(adapter)
        ) else {
            logStaleSelectionTerminal()
            return
        }
        activeSelectionTransaction = transaction
        committedSelectionIndex = index
        eventDelegate?.pagingHost(self, didSelect: index, animated: animated)
        finishActiveSelectionIfReady()
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didCancelSelectionAt index: Int,
        returningTo previousIndex: Int,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    ) {
        guard var transaction = matchingSelectionTransaction(
            adapter: adapter,
            requestIdentifier: requestIdentifier,
            targetIndex: index
        ), transaction.recordSemanticTerminal(
            .cancelled(index: index, previousIndex: previousIndex),
            requestIdentifier: requestIdentifier,
            targetIndex: index,
            adapterIdentifier: ObjectIdentifier(adapter)
        ) else {
            logStaleSelectionTerminal()
            return
        }
        activeSelectionTransaction = transaction
        eventDelegate?.pagingHost(
            self,
            didCancelSelectionAt: index,
            returningTo: previousIndex
        )
        finishActiveSelectionIfReady()
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        didComplete requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
        finished: Bool,
        currentIndex: Int?
    ) {
        guard var transaction = matchingSelectionTransaction(
            adapter: adapter,
            requestIdentifier: requestIdentifier
        ), transaction.request.source.isExplicit else {
            logStaleSelectionTerminal()
            return
        }

        var recoveredTerminal: AnchorPagerPagingSelectionSemanticTerminal?
        if transaction.semanticTerminal == nil {
            if finished, currentIndex == transaction.request.targetIndex {
                let terminal = AnchorPagerPagingSelectionSemanticTerminal.selected(
                    index: transaction.request.targetIndex
                )
                guard transaction.recordSemanticTerminal(
                    terminal,
                    requestIdentifier: requestIdentifier,
                    targetIndex: transaction.request.targetIndex,
                    adapterIdentifier: ObjectIdentifier(adapter)
                ) else {
                    logStaleSelectionTerminal()
                    return
                }
                recoveredTerminal = terminal
            } else if !finished {
                let terminal = AnchorPagerPagingSelectionSemanticTerminal.cancelled(
                    index: transaction.request.targetIndex,
                    previousIndex: transaction.previousIndex
                )
                guard transaction.recordSemanticTerminal(
                    terminal,
                    requestIdentifier: requestIdentifier,
                    targetIndex: transaction.request.targetIndex,
                    adapterIdentifier: ObjectIdentifier(adapter)
                ) else {
                    logStaleSelectionTerminal()
                    return
                }
                recoveredTerminal = terminal
            }
        }
        guard transaction.acknowledgeProgrammaticCompletion(
            requestIdentifier: requestIdentifier,
            targetIndex: transaction.request.targetIndex,
            adapterIdentifier: ObjectIdentifier(adapter)
        ) else {
            logStaleSelectionTerminal()
            return
        }
        activeSelectionTransaction = transaction
        if let recoveredTerminal {
            AnchorPagerLogger.log(
                .debug,
                category: .paging,
                event: "paging.selection.missingSemantic"
            )
            forwardRecoveredSelectionTerminal(
                recoveredTerminal,
                request: transaction.request
            )
        } else if transaction.semanticTerminal == nil {
            logStaleSelectionTerminal()
        }
        finishActiveSelectionIfReady()
    }

    func pagingAdapter(
        _ adapter: AnchorPagerPagingAdapter,
        executorDidBecomeReadyFor requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier
    ) {
        guard var transaction = matchingSelectionTransaction(
            adapter: adapter,
            requestIdentifier: requestIdentifier
        ), transaction.request.source.isExplicit,
        transaction.didAcknowledgeCompletion,
        transaction.acknowledgeExecutorReady(
            requestIdentifier: requestIdentifier,
            targetIndex: transaction.request.targetIndex,
            adapterIdentifier: ObjectIdentifier(adapter)
        ) else {
            logStaleSelectionTerminal()
            return
        }
        activeSelectionTransaction = transaction
        finishActiveSelectionIfReady()
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
        if !performPendingReloadIfNeeded() {
            _ = performPendingSelectionIfPossible()
        }
    }

    private func matchesActiveSelectionAdapter(_ adapter: AnchorPagerPagingAdapter) -> Bool {
        adapter === activeAdapter
    }

    private func matches(
        adapter: AnchorPagerPagingAdapter,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
        targetIndex: Int
    ) -> Bool {
        guard let transaction = activeSelectionTransaction else { return false }
        return adapter === activeAdapter
            && transaction.adapterIdentifier == ObjectIdentifier(adapter)
            && transaction.request.identifier == requestIdentifier
            && transaction.request.targetIndex == targetIndex
    }

    private func matchingSelectionTransaction(
        adapter: AnchorPagerPagingAdapter,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
        targetIndex: Int? = nil
    ) -> AnchorPagerPagingSelectionTransaction? {
        guard adapter === activeAdapter,
              let transaction = activeSelectionTransaction,
              transaction.adapterIdentifier == ObjectIdentifier(adapter),
              transaction.request.identifier == requestIdentifier else {
            return nil
        }
        if let targetIndex,
           transaction.request.targetIndex != targetIndex {
            return nil
        }
        return transaction
    }

    private func forwardRecoveredSelectionTerminal(
        _ terminal: AnchorPagerPagingSelectionSemanticTerminal,
        request: AnchorPagerPagingSelectionRequest
    ) {
        switch terminal {
        case let .selected(index):
            committedSelectionIndex = index
            eventDelegate?.pagingHost(self, didSelect: index, animated: request.animated)
        case let .cancelled(index, previousIndex):
            eventDelegate?.pagingHost(
                self,
                didCancelSelectionAt: index,
                returningTo: previousIndex
            )
        }
    }

    private func finishActiveSelectionIfReady() {
        guard activeSelectionTransaction?.isReadyToFinish == true else { return }
        activeSelectionTransaction = nil
        forwardedWillSelectRequestIdentifier = nil
        if !performPendingReloadIfNeeded() {
            _ = performPendingSelectionIfPossible()
        }
    }

    private func logStaleSelectionTerminal() {
        AnchorPagerLogger.log(
            .debug,
            category: .paging,
            event: "paging.selection.staleTerminal"
        )
    }
}
