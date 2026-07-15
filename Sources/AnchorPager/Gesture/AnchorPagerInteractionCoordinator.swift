@MainActor
final class AnchorPagerInteractionCoordinator {
    private enum Operation: Equatable {
        case begin
        case updateBoundary
        case finish
        case cancel
    }

    private struct InvalidTransition: Equatable {
        let operation: Operation
        let currentState: AnchorPagerInteractionState
        let requestedState: AnchorPagerInteractionState
    }

    private(set) var state: AnchorPagerInteractionState = .idle
    private var suspendedState: AnchorPagerInteractionState?
    private var lastInvalidTransition: InvalidTransition?

    var isReadyForDeferredWorkDrain: Bool {
        state == .idle
    }

    @discardableResult
    func begin(_ requestedState: AnchorPagerInteractionState) -> Bool {
        if requestedState == state {
            return true
        }
        if case let .transitioningSize(identifier) = requestedState {
            return transitionToSize(identifier: identifier)
        }

        let isValid: Bool
        switch (state, requestedState) {
        case (.idle, .idle):
            isValid = false
        case (.idle, .verticalDragging),
             (.idle, .horizontalPaging),
             (.idle, .programmaticPaging),
             (.idle, .layoutReloading):
            isValid = true
        case let (
            .verticalDragging(currentIdentifier),
            .verticalDecelerating(requestedIdentifier)
        ), let (
            .verticalDragging(currentIdentifier),
            .topOverscrolling(requestedIdentifier)
        ):
            isValid = currentIdentifier == requestedIdentifier
        default:
            isValid = false
        }
        guard isValid else {
            logInvalid(.begin, requestedState: requestedState)
            return false
        }

        state = requestedState
        didPerformValidTransition(
            level: .info,
            event: "interaction.state.begin"
        )
        return true
    }

    @discardableResult
    func updateBoundary(to requestedState: AnchorPagerInteractionState) -> Bool {
        if requestedState == state {
            return true
        }
        let isValid: Bool
        switch (state, requestedState) {
        case let (
            .verticalDragging(currentIdentifier),
            .topOverscrolling(requestedIdentifier)
        ), let (
            .topOverscrolling(currentIdentifier),
            .verticalDragging(requestedIdentifier)
        ):
            isValid = currentIdentifier == requestedIdentifier
        default:
            isValid = false
        }
        guard isValid else {
            logInvalid(.updateBoundary, requestedState: requestedState)
            return false
        }

        state = requestedState
        didPerformValidTransition(
            level: .debug,
            event: "interaction.state.updateBoundary"
        )
        return true
    }

    @discardableResult
    func finish(_ requestedState: AnchorPagerInteractionState) -> Bool {
        if finishSuspendedStateIfMatching(requestedState, event: "interaction.state.finish") {
            return true
        }
        guard requestedState == state, requestedState != .idle else {
            logInvalid(.finish, requestedState: requestedState)
            return false
        }
        if case let .transitioningSize(identifier) = requestedState {
            return finishSizeTransitionIfMatching(identifier: identifier, isCancellation: false)
        }

        switch requestedState {
        case let .topOverscrolling(identifier):
            state = .verticalDragging(identifier: identifier)
        default:
            state = .idle
        }
        didPerformValidTransition(
            level: .info,
            event: "interaction.state.finish"
        )
        return true
    }

    @discardableResult
    func cancel(_ requestedState: AnchorPagerInteractionState) -> Bool {
        if finishSuspendedStateIfMatching(requestedState, event: "interaction.state.cancel") {
            return true
        }
        guard requestedState == state, requestedState != .idle else {
            logInvalid(.cancel, requestedState: requestedState)
            return false
        }
        if case let .transitioningSize(identifier) = requestedState {
            return finishSizeTransitionIfMatching(identifier: identifier, isCancellation: true)
        }

        state = .idle
        didPerformValidTransition(
            level: .info,
            event: "interaction.state.cancel"
        )
        return true
    }

    func beginSizeTransition(identifier: Int) {
        _ = transitionToSize(identifier: identifier)
    }

    func finishSizeTransition(identifier: Int) {
        _ = finishSizeTransitionIfMatching(identifier: identifier, isCancellation: false)
    }

    @discardableResult
    private func transitionToSize(identifier: Int) -> Bool {
        let requestedState = AnchorPagerInteractionState.transitioningSize(
            identifier: identifier
        )
        if state == requestedState {
            return true
        }
        guard case .transitioningSize = state else {
            suspendedState = state.canResumeAfterSizeTransition ? state : nil
            state = requestedState
            didPerformValidTransition(
                level: .info,
                event: "interaction.state.begin"
            )
            return true
        }

        logInvalid(.begin, requestedState: requestedState)
        return false
    }

    @discardableResult
    private func finishSizeTransitionIfMatching(
        identifier: Int,
        isCancellation: Bool
    ) -> Bool {
        let requestedState = AnchorPagerInteractionState.transitioningSize(
            identifier: identifier
        )
        guard state == requestedState else {
            logInvalid(
                isCancellation ? .cancel : .finish,
                requestedState: requestedState
            )
            return false
        }

        state = suspendedState ?? .idle
        suspendedState = nil
        didPerformValidTransition(
            level: .info,
            event: isCancellation
                ? "interaction.state.cancel"
                : "interaction.state.finish"
        )
        return true
    }

    private func finishSuspendedStateIfMatching(
        _ requestedState: AnchorPagerInteractionState,
        event: String
    ) -> Bool {
        guard case .transitioningSize = state,
              suspendedState == requestedState else {
            return false
        }
        suspendedState = nil
        didPerformValidTransition(level: .info, event: event)
        return true
    }

    private func didPerformValidTransition(
        level: AnchorPagerLogger.Level,
        event: String
    ) {
        lastInvalidTransition = nil
        AnchorPagerLogger.log(level, category: .gesture, event: event)
    }

    private func logInvalid(
        _ operation: Operation,
        requestedState: AnchorPagerInteractionState
    ) {
        let invalidTransition = InvalidTransition(
            operation: operation,
            currentState: state,
            requestedState: requestedState
        )
        guard invalidTransition != lastInvalidTransition else { return }
        lastInvalidTransition = invalidTransition
        AnchorPagerLogger.log(
            .debug,
            category: .gesture,
            event: "interaction.state.invalidTransition"
        )
    }
}
