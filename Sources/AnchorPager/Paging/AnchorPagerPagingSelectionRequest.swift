typealias AnchorPagerPagingSelectionRequestIdentifier = Int

enum AnchorPagerPagingSelectionSource: Equatable {
    case api
    case bar
    case interactive

    var isExplicit: Bool {
        self != .interactive
    }
}

struct AnchorPagerPagingSelectionRequest: Equatable {
    let identifier: AnchorPagerPagingSelectionRequestIdentifier
    let targetIndex: Int
    let animated: Bool
    let source: AnchorPagerPagingSelectionSource
}

enum AnchorPagerPagingSelectionSemanticTerminal: Equatable {
    case selected(index: Int)
    case cancelled(index: Int, previousIndex: Int)
}

struct AnchorPagerPagingSelectionTransaction: Equatable {
    let request: AnchorPagerPagingSelectionRequest
    let previousIndex: Int
    let adapterIdentifier: ObjectIdentifier
    private(set) var semanticTerminal: AnchorPagerPagingSelectionSemanticTerminal?
    private(set) var didAcknowledgeCompletion: Bool
    private(set) var didAcknowledgeExecutorReady: Bool

    init(
        request: AnchorPagerPagingSelectionRequest,
        previousIndex: Int,
        adapterIdentifier: ObjectIdentifier
    ) {
        self.request = request
        self.previousIndex = previousIndex
        self.adapterIdentifier = adapterIdentifier
        semanticTerminal = nil
        didAcknowledgeCompletion = false
        didAcknowledgeExecutorReady = false
    }

    var isReadyToFinish: Bool {
        guard semanticTerminal != nil else { return false }
        guard request.source.isExplicit else { return true }
        return didAcknowledgeCompletion && didAcknowledgeExecutorReady
    }

    @discardableResult
    mutating func recordSemanticTerminal(
        _ terminal: AnchorPagerPagingSelectionSemanticTerminal,
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
        targetIndex: Int,
        adapterIdentifier: ObjectIdentifier
    ) -> Bool {
        guard matches(
            requestIdentifier: requestIdentifier,
            targetIndex: targetIndex,
            adapterIdentifier: adapterIdentifier
        ), semanticTerminal == nil,
        terminal.matches(targetIndex: request.targetIndex, previousIndex: previousIndex) else {
            return false
        }
        semanticTerminal = terminal
        return true
    }

    @discardableResult
    mutating func acknowledgeProgrammaticCompletion(
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
        targetIndex: Int,
        adapterIdentifier: ObjectIdentifier
    ) -> Bool {
        guard request.source.isExplicit,
              matches(
                  requestIdentifier: requestIdentifier,
                  targetIndex: targetIndex,
                  adapterIdentifier: adapterIdentifier
              ),
              !didAcknowledgeCompletion else {
            return false
        }
        didAcknowledgeCompletion = true
        if !request.animated {
            didAcknowledgeExecutorReady = true
        }
        return true
    }

    @discardableResult
    mutating func acknowledgeExecutorReady(
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
        targetIndex: Int,
        adapterIdentifier: ObjectIdentifier
    ) -> Bool {
        guard request.source.isExplicit,
              matches(
                  requestIdentifier: requestIdentifier,
                  targetIndex: targetIndex,
                  adapterIdentifier: adapterIdentifier
              ),
              !didAcknowledgeExecutorReady else {
            return false
        }
        didAcknowledgeExecutorReady = true
        return true
    }

    private func matches(
        requestIdentifier: AnchorPagerPagingSelectionRequestIdentifier,
        targetIndex: Int,
        adapterIdentifier: ObjectIdentifier
    ) -> Bool {
        request.identifier == requestIdentifier
            && request.targetIndex == targetIndex
            && self.adapterIdentifier == adapterIdentifier
    }
}

enum AnchorPagerPagingExplicitSelectionAdmission: Equatable {
    case start
    case noOp
    case duplicate
    case replaceLatest
    case rejectedInteractive

    static func resolve(
        request: AnchorPagerPagingSelectionRequest,
        committedIndex: Int,
        activeRequest: AnchorPagerPagingSelectionRequest?,
        pendingRequest: AnchorPagerPagingSelectionRequest?
    ) -> Self {
        guard request.source.isExplicit else { return .rejectedInteractive }
        guard let activeRequest else {
            return request.targetIndex == committedIndex ? .noOp : .start
        }
        guard request.targetIndex == activeRequest.targetIndex else {
            return .replaceLatest
        }
        if let pendingRequest,
           pendingRequest.targetIndex != activeRequest.targetIndex {
            return .replaceLatest
        }
        return .duplicate
    }
}

private extension AnchorPagerPagingSelectionSemanticTerminal {
    func matches(targetIndex: Int, previousIndex: Int) -> Bool {
        switch self {
        case let .selected(index):
            return index == targetIndex
        case let .cancelled(index, terminalPreviousIndex):
            return index == targetIndex && terminalPreviousIndex == previousIndex
        }
    }
}
