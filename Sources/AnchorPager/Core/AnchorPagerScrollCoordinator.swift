import UIKit

enum AnchorPagerVerticalPanSource: Hashable, Sendable {
    case container
    case child(token: Int)
}

enum AnchorPagerVerticalInteractionEvent: Equatable, Sendable {
    case beganDragging(identifier: Int)
    case enteredTopOverscroll(identifier: Int)
    case leftTopOverscroll(identifier: Int)
    case beganDecelerating(identifier: Int)
    case finishedDragging(identifier: Int)
    case finishedDecelerating(identifier: Int)
    case cancelled(identifier: Int)
}

@MainActor
protocol AnchorPagerScrollCoordinatorInteractionDelegate: AnyObject {
    func scrollCoordinator(
        _ coordinator: AnchorPagerScrollCoordinator,
        didEmit event: AnchorPagerVerticalInteractionEvent
    )
}

@MainActor
final class AnchorPagerScrollCoordinator {
    enum Owner: Equatable {
        case container
        case child
    }

    enum DecelerationPhase: Equatable {
        case monitoringNative
        case synthetic
    }

    typealias DecelerationDriverFactory = () -> AnchorPagerVerticalDecelerationDriving
    typealias DecelerationRateProvider = (UIScrollView) -> CGFloat

    private enum ActiveBoundaryEnforcementResult {
        case inactive
        case active
        case finished(AnchorPagerOverscrollCoordinator.ActiveOwner)
    }

    private let containerScrollView: AnchorPagerContainerScrollView
    private let overscrollCoordinator: AnchorPagerOverscrollCoordinator
    private let decelerationDriverFactory: DecelerationDriverFactory
    private let decelerationRateProvider: DecelerationRateProvider
    weak var interactionDelegate: AnchorPagerScrollCoordinatorInteractionDelegate?
    private var childBinding: AnchorPagerChildScrollBinding?
    private weak var committedChildScrollView: UIScrollView?
    private var bindingToken = 0
    private var containerGeometry: AnchorPagerContainerScrollGeometry = .zero
    private var gestureStartTotal: CGFloat?
    private var gestureStartTranslationY: CGFloat = 0
    private var activePanSources: Set<AnchorPagerVerticalPanSource> = []
    private var primaryPanSource: AnchorPagerVerticalPanSource?
    private var nextVerticalInteractionIdentifier = 0
    private var verticalInteractionIdentifier: Int?
    private var pendingBoundaryRecoveryInteractionIdentifier: Int?
    private var topOverscrollInteractionIdentifier: Int?
    private var didCancelCurrentPanInteraction = false
    private var didAttemptDecelerationForInteraction = false
    private var isApplyingGuardedOffsets = false
    private var isInvalidated = false
    private var decelerationDriver: AnchorPagerVerticalDecelerationDriving?
    private var decelerationContext: DecelerationContext?
    private(set) var owner: Owner = .container

    private struct DecelerationContext {
        let interactionIdentifier: Int
        let nativeOwner: Owner
        let initialCanonicalTotal: CGFloat
        var accumulatedModelDelta: CGFloat
        var canonicalTotal: CGFloat
        var phase: DecelerationPhase
        var nativeBoundaryReached: Bool
    }

    var bindingTokenForTesting: Int { bindingToken }
    var activeBoundaryForTesting: AnchorPagerOverscrollCoordinator.ActiveOwner? {
        overscrollCoordinator.activeOwner
    }
    var decelerationPhaseForTesting: DecelerationPhase? {
        decelerationContext?.phase
    }

    init(
        containerScrollView: AnchorPagerContainerScrollView,
        topOverscrollHandlingMode: AnchorPagerTopOverscrollHandlingMode = .container,
        decelerationDriverFactory: @escaping DecelerationDriverFactory = {
            AnchorPagerVerticalDecelerationDriver()
        },
        decelerationRateProvider: @escaping DecelerationRateProvider = {
            $0.decelerationRate.rawValue
        }
    ) {
        self.containerScrollView = containerScrollView
        self.decelerationDriverFactory = decelerationDriverFactory
        self.decelerationRateProvider = decelerationRateProvider
        self.overscrollCoordinator = AnchorPagerOverscrollCoordinator(
            topMode: topOverscrollHandlingMode
        )
        containerScrollView.panGestureRecognizer.addTarget(
            self,
            action: #selector(handleContainerPan(_:))
        )
    }

    deinit {
        MainActor.assumeIsolated {
            cancelActiveVerticalInteractionForStructuralChange()
        }
    }

    func updateTopOverscrollHandlingMode(_ mode: AnchorPagerTopOverscrollHandlingMode) {
        guard overscrollCoordinator.topMode != mode else { return }
        cancelActiveVerticalInteractionForStructuralChange()
        let hadActiveOwner = overscrollCoordinator.activeOwner != nil
        overscrollCoordinator.updateTopMode(mode)
        if hadActiveOwner {
            settleStableOffsets()
        }
    }

    func updateGeometry(
        _ geometry: AnchorPagerContainerScrollGeometry,
        targetLogicalOffset: CGFloat? = nil
    ) {
        let previous = currentStablePosition()
        if containerGeometry != geometry {
            cancelActiveVerticalInteractionForStructuralChange()
            overscrollCoordinator.cancel()
        }
        containerGeometry = geometry

        guard let targetLogicalOffset else {
            settleStableOffsets()
            return
        }

        let containerTarget = geometry.clampedLogicalOffset(targetLogicalOffset)
        let childTarget = containerTarget >= geometry.collapsibleDistance - epsilon
            ? previous.childDistance
            : 0
        apply(
            .init(containerOffset: containerTarget, childDistance: childTarget),
            transitionBaseline: previous
        )
    }

    func bindCommittedChild(_ scrollView: UIScrollView?) {
        guard !isInvalidated, committedChildScrollView !== scrollView else { return }

        cancelActiveVerticalInteractionForStructuralChange()
        overscrollCoordinator.cancel()
        endCurrentBindingIfNeeded()
        committedChildScrollView = scrollView
        containerScrollView.bindCurrentChildPan(scrollView?.panGestureRecognizer)
        bindingToken &+= 1
        guard let scrollView else {
            transitionOwnerIfNeeded(to: .container)
            settleStableOffsets()
            return
        }

        AnchorPagerLogger.log(.info, category: .scroll, event: "scroll.binding.begin")
        let token = bindingToken
        childBinding = AnchorPagerChildScrollBinding(
            scrollView: scrollView,
            token: token,
            onContentOffsetChanged: { [weak self] _ in
                self?.childDidChange(token: token)
            },
            onContentSizeChanged: { [weak self] _ in
                self?.childGeometryDidChange(token: token)
            },
            onPan: { [weak self] state, translationY, velocityY in
                self?.handlePan(
                    source: .child(token: token),
                    state: state,
                    translationY: translationY,
                    velocityY: velocityY
                )
            }
        )
        settleStableOffsets()
    }

    func containerDidScroll() {
        guard !isInvalidated else { return }
        guard !isApplyingGuardedOffsets else { return }
        if handleDecelerationNativeCallback(source: .container) {
            return
        }
        if handleObservedBoundaryIfNeeded() {
            return
        }
        settleStableOffsets()
    }

    func handlePan(state: UIGestureRecognizer.State, translationY: CGFloat) {
        handlePan(
            source: .container,
            state: state,
            translationY: translationY,
            velocityY: 0
        )
    }

    func handlePan(
        source: AnchorPagerVerticalPanSource,
        state: UIGestureRecognizer.State,
        translationY: CGFloat,
        velocityY: CGFloat
    ) {
        guard !isInvalidated else { return }
        guard isCurrentPanSource(source) else {
            AnchorPagerLogger.log(
                .debug,
                category: .scroll,
                event: "scroll.binding.stale"
            )
            return
        }
        switch state {
        case .began:
            beginVerticalPanIfNeeded(source: source, translationY: translationY)
        case .changed:
            guard primaryPanSource == source,
                  let gestureStartTotal else { return }
            let input = AnchorPagerScrollPositionResolver.Input(
                gestureStartTotal: gestureStartTotal,
                gestureStartTranslationY: gestureStartTranslationY,
                currentTranslationY: translationY,
                containerCollapsedOffset: containerGeometry.collapsibleDistance,
                childMaximumDistance: childMaximumDistance,
                fallback: currentStablePosition()
            )
            guard let desiredTotal = AnchorPagerScrollPositionResolver
                .unclampedDesiredTotal(input) else {
                apply(AnchorPagerScrollPositionResolver.resolve(input))
                return
            }
            let maximumStableTotal = containerGeometry.collapsibleDistance
                + childMaximumDistance
            if desiredTotal < -boundaryEpsilon {
                beginBoundary(.top, resolverInput: input)
            } else if desiredTotal > maximumStableTotal + boundaryEpsilon {
                beginBoundary(.bottom, resolverInput: input)
            } else if overscrollCoordinator.activeOwner == nil {
                overscrollCoordinator.reachedStableRange()
                apply(AnchorPagerScrollPositionResolver.resolve(input))
            } else {
                let previousBoundaryOwner = overscrollCoordinator.activeOwner
                switch overscrollCoordinator.finishUnpresentedActiveOwner() {
                case .inactive:
                    overscrollCoordinator.reachedStableRange()
                    apply(AnchorPagerScrollPositionResolver.resolve(input))
                case .finished:
                    reportTopBoundaryTransition(
                        from: previousBoundaryOwner,
                        to: overscrollCoordinator.activeOwner
                    )
                    overscrollCoordinator.reachedStableRange()
                    apply(AnchorPagerScrollPositionResolver.resolve(input))
                case .presented:
                    handleActiveBoundaryEnforcementResult(
                        enforceAndObserveActiveBoundary(),
                        resolverInput: input
                    )
                }
            }
        case .ended, .cancelled, .failed:
            finishVerticalPanSource(
                source,
                state: state,
                velocityY: velocityY
            )
        default:
            break
        }
    }

    func handleChildChangeForTesting(token: Int) {
        childDidChange(token: token)
    }

    func cancelBoundaryHandling() {
        cancelActiveVerticalInteractionForStructuralChange()
        let didCancel = overscrollCoordinator.cancel()
        if didCancel {
            apply(currentStablePosition())
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        cancelActiveVerticalInteractionForStructuralChange()
        overscrollCoordinator.cancel()
        bindingToken &+= 1
        endCurrentBindingIfNeeded()
        committedChildScrollView = nil
        containerScrollView.bindCurrentChildPan(nil)
        containerScrollView.panGestureRecognizer.removeTarget(
            self,
            action: #selector(handleContainerPan(_:))
        )
        gestureStartTotal = nil
        activePanSources.removeAll()
        primaryPanSource = nil
        verticalInteractionIdentifier = nil
    }

    func cancelSyntheticDeceleration() {
        guard let context = decelerationContext else { return }
        decelerationContext = nil
        let driver = decelerationDriver
        decelerationDriver = nil
        driver?.cancel()
        emitInteractionEvent(.cancelled(identifier: context.interactionIdentifier))
    }
}

@MainActor
private extension AnchorPagerScrollCoordinator {
    var epsilon: CGFloat { 0.001 }
    var boundaryEpsilon: CGFloat { 0.5 }

    var childTopOffset: CGFloat {
        guard let committedChildScrollView else { return 0 }
        return -committedChildScrollView.contentInset.top
    }

    var childMaximumDistance: CGFloat {
        guard let child = committedChildScrollView else { return 0 }
        return AnchorPagerScrollPositionResolver.childMaximumDistance(
            contentSizeHeight: child.contentSize.height,
            boundsHeight: child.bounds.height,
            contentInsetTop: child.contentInset.top,
            contentInsetBottom: child.contentInset.bottom
        )
    }

    func isCurrentPanSource(_ source: AnchorPagerVerticalPanSource) -> Bool {
        switch source {
        case .container:
            return true
        case let .child(token):
            return token == bindingToken && committedChildScrollView != nil
        }
    }

    func beginVerticalPanIfNeeded(
        source: AnchorPagerVerticalPanSource,
        translationY: CGFloat
    ) {
        if verticalInteractionIdentifier == nil {
            cancelSyntheticDeceleration()
            cancelPendingBoundaryRecoveryInteractionIfNeeded()
            nextVerticalInteractionIdentifier &+= 1
            let interactionIdentifier = nextVerticalInteractionIdentifier
            verticalInteractionIdentifier = interactionIdentifier
            gestureStartTotal = currentCanonicalTotal()
            gestureStartTranslationY = translationY
            primaryPanSource = source
            didAttemptDecelerationForInteraction = false
            didCancelCurrentPanInteraction = false
            emitInteractionEvent(
                .beganDragging(identifier: interactionIdentifier)
            )
        }
        activePanSources.insert(source)
    }

    func finishVerticalPanSource(
        _ source: AnchorPagerVerticalPanSource,
        state: UIGestureRecognizer.State,
        velocityY: CGFloat
    ) {
        guard let interactionIdentifier = verticalInteractionIdentifier else {
            settleStableOffsets()
            return
        }

        if state == .ended {
            startDecelerationIfPossible(source: source, velocityY: velocityY)
        } else {
            cancelSyntheticDeceleration()
            didCancelCurrentPanInteraction = true
        }
        activePanSources.remove(source)
        guard activePanSources.isEmpty else { return }

        let didStartDeceleration = decelerationContext?.interactionIdentifier
            == interactionIdentifier
        let interactionWasCancelled = didCancelCurrentPanInteraction
        gestureStartTotal = nil
        primaryPanSource = nil
        verticalInteractionIdentifier = nil
        didAttemptDecelerationForInteraction = false
        didCancelCurrentPanInteraction = false

        if didStartDeceleration {
            return
        }
        if interactionWasCancelled {
            overscrollCoordinator.cancel()
            topOverscrollInteractionIdentifier = nil
            emitInteractionEvent(.cancelled(identifier: interactionIdentifier))
            settleStableOffsets()
            return
        }

        let previousBoundaryOwner = overscrollCoordinator.activeOwner
        if overscrollCoordinator.endInteraction() {
            reportTopBoundaryTransition(
                from: previousBoundaryOwner,
                to: overscrollCoordinator.activeOwner,
                interactionIdentifier: interactionIdentifier
            )
            settleStableOffsets()
        } else if overscrollCoordinator.activeOwner != nil {
            pendingBoundaryRecoveryInteractionIdentifier = interactionIdentifier
            return
        } else {
            settleStableOffsets()
        }
        emitInteractionEvent(.finishedDragging(identifier: interactionIdentifier))
    }

    func startDecelerationIfPossible(
        source: AnchorPagerVerticalPanSource,
        velocityY: CGFloat
    ) {
        guard !didAttemptDecelerationForInteraction,
              sourceMatchesCurrentOwner(source),
              let interactionIdentifier = verticalInteractionIdentifier else {
            return
        }
        didAttemptDecelerationForInteraction = true

        let canonicalVelocity = -velocityY
        let rate = decelerationRate(for: owner)
        let initialTotal = currentCanonicalTotal()
        guard canonicalVelocity.isFinite,
              abs(canonicalVelocity) > 5,
              rate.isFinite,
              rate > 0,
              rate < 1,
              canHandoff(
                from: owner,
                canonicalVelocity: canonicalVelocity,
                initialTotal: initialTotal
              ) else {
            logRejectedDeceleration()
            return
        }

        let nativeOwner = owner
        let driver = decelerationDriverFactory()
        decelerationDriver = driver
        decelerationContext = DecelerationContext(
            interactionIdentifier: interactionIdentifier,
            nativeOwner: nativeOwner,
            initialCanonicalTotal: initialTotal,
            accumulatedModelDelta: 0,
            canonicalTotal: initialTotal,
            phase: .monitoringNative,
            nativeBoundaryReached: nativeOwnerBoundaryReached(nativeOwner)
        )
        emitInteractionEvent(
            .beganDecelerating(identifier: interactionIdentifier)
        )
        driver.onTick = { [weak self] sample in
            self?.consumeDecelerationSample(
                sample,
                interactionIdentifier: interactionIdentifier
            )
        }
        driver.onCancel = { [weak self] in
            self?.decelerationDriverDidCancel(
                interactionIdentifier: interactionIdentifier
            )
        }
        driver.start(
            initialVelocity: canonicalVelocity,
            decelerationRate: rate,
            elapsedTime: 0
        )
    }

    func sourceMatchesCurrentOwner(_ source: AnchorPagerVerticalPanSource) -> Bool {
        switch (owner, source) {
        case (.container, .container), (.child, .child):
            return true
        default:
            return false
        }
    }

    func decelerationRate(for owner: Owner) -> CGFloat {
        switch owner {
        case .container:
            return decelerationRateProvider(containerScrollView)
        case .child:
            guard let committedChildScrollView else { return .nan }
            return decelerationRateProvider(committedChildScrollView)
        }
    }

    func canHandoff(
        from owner: Owner,
        canonicalVelocity: CGFloat,
        initialTotal: CGFloat
    ) -> Bool {
        switch owner {
        case .container:
            return canonicalVelocity > 5
                && committedChildScrollView != nil
                && childMaximumDistance > epsilon
                && initialTotal
                    < containerGeometry.collapsibleDistance + childMaximumDistance - epsilon
        case .child:
            return canonicalVelocity < -5
                && containerGeometry.collapsibleDistance > epsilon
                && initialTotal > epsilon
        }
    }

    func nativeOwnerBoundaryReached(_ owner: Owner) -> Bool {
        switch owner {
        case .container:
            let logicalOffset = containerGeometry.logicalOffset(
                forRawOffset: containerScrollView.contentOffset.y
            )
            return logicalOffset
                >= containerGeometry.collapsibleDistance - boundaryEpsilon
        case .child:
            let distance = (committedChildScrollView?.contentOffset.y ?? childTopOffset)
                - childTopOffset
            return distance <= boundaryEpsilon
        }
    }

    func handleDecelerationNativeCallback(
        source: AnchorPagerVerticalPanSource
    ) -> Bool {
        guard var context = decelerationContext,
              sourceMatchesNativeOwner(source, context.nativeOwner) else {
            return false
        }

        if context.phase == .synthetic {
            lockLateNativeOwnerAtHandoffBoundary(context.nativeOwner)
            return true
        }
        guard context.nativeBoundaryReached
            || nativeOwnerBoundaryReached(context.nativeOwner) else {
            return false
        }

        context.nativeBoundaryReached = true
        decelerationContext = context
        lockNativeOwnerAtHandoffBoundary(context.nativeOwner)
        return true
    }

    func sourceMatchesNativeOwner(
        _ source: AnchorPagerVerticalPanSource,
        _ nativeOwner: Owner
    ) -> Bool {
        switch (nativeOwner, source) {
        case (.container, .container), (.child, .child):
            return true
        default:
            return false
        }
    }

    func lockNativeOwnerAtHandoffBoundary(_ nativeOwner: Owner) {
        switch nativeOwner {
        case .container:
            writeContainerBoundary(containerGeometry.collapsibleDistance)
            pinChildToTop()
        case .child:
            pinChildToTop()
            writeContainerBoundary(containerGeometry.collapsibleDistance)
        }
    }

    func lockLateNativeOwnerAtHandoffBoundary(_ nativeOwner: Owner) {
        switch nativeOwner {
        case .container:
            writeContainerBoundary(containerGeometry.collapsibleDistance)
        case .child:
            pinChildToTop()
        }
    }

    func consumeDecelerationSample(
        _ sample: AnchorPagerVerticalDecelerationModel.Sample,
        interactionIdentifier: Int
    ) {
        guard var context = decelerationContext else { return }
        guard context.interactionIdentifier == interactionIdentifier else { return }
        guard sample.delta.isFinite, sample.velocity.isFinite else {
            cancelSyntheticDeceleration()
            return
        }

        context.accumulatedModelDelta += sample.delta
        switch context.phase {
        case .monitoringNative:
            guard context.nativeBoundaryReached else {
                if sample.isFinished {
                    finishDecelerationInteraction(
                        interactionIdentifier: interactionIdentifier,
                        cancelsDriver: false
                    )
                } else {
                    decelerationContext = context
                }
                return
            }
            context.phase = .synthetic
            let boundaryTotal = containerGeometry.collapsibleDistance
            let projectedTotal = context.initialCanonicalTotal
                + context.accumulatedModelDelta
            switch context.nativeOwner {
            case .container:
                context.canonicalTotal = boundaryTotal
                    + max(0, projectedTotal - boundaryTotal)
            case .child:
                context.canonicalTotal = boundaryTotal
                    + min(0, projectedTotal - boundaryTotal)
            }
            AnchorPagerLogger.log(
                .info,
                category: .scroll,
                event: "scroll.deceleration.handoff"
            )
        case .synthetic:
            context.canonicalTotal += sample.delta
        }

        let didReachTerminalBoundary = applySyntheticPosition(&context)
        if didReachTerminalBoundary {
            decelerationContext = context
            finishDecelerationInteraction(
                interactionIdentifier: interactionIdentifier,
                cancelsDriver: true
            )
        } else if sample.isFinished {
            decelerationContext = context
            finishDecelerationInteraction(
                interactionIdentifier: interactionIdentifier,
                cancelsDriver: false
            )
        } else {
            decelerationContext = context
        }
    }

    private func applySyntheticPosition(
        _ context: inout DecelerationContext
    ) -> Bool {
        let maximumTotal = containerGeometry.collapsibleDistance + childMaximumDistance
        let desiredTotal = context.canonicalTotal
        let clampedTotal = min(max(0, desiredTotal), maximumTotal)
        context.canonicalTotal = clampedTotal
        apply(AnchorPagerScrollPositionResolver.resolveCanonicalTotal(
            clampedTotal,
            containerCollapsedOffset: containerGeometry.collapsibleDistance,
            childMaximumDistance: childMaximumDistance,
            fallback: currentStablePosition()
        ))

        switch context.nativeOwner {
        case .container:
            return desiredTotal >= maximumTotal
        case .child:
            return desiredTotal <= 0
        }
    }

    func decelerationDriverDidCancel(interactionIdentifier: Int) {
        guard decelerationContext?.interactionIdentifier == interactionIdentifier else {
            return
        }
        decelerationContext = nil
        decelerationDriver = nil
        emitInteractionEvent(.cancelled(identifier: interactionIdentifier))
    }

    func finishDecelerationInteraction(
        interactionIdentifier: Int,
        cancelsDriver: Bool
    ) {
        guard decelerationContext?.interactionIdentifier == interactionIdentifier else {
            return
        }
        decelerationContext = nil
        if cancelsDriver {
            let driver = decelerationDriver
            decelerationDriver = nil
            driver?.cancel()
        }
        emitInteractionEvent(
            .finishedDecelerating(identifier: interactionIdentifier)
        )
    }

    func logRejectedDeceleration() {
        AnchorPagerLogger.log(
            .debug,
            category: .scroll,
            event: "scroll.deceleration.cancel"
        )
    }

    func currentStablePosition() -> AnchorPagerScrollPositionResolver.Position {
        let container = containerGeometry.clampedLogicalOffset(
            containerGeometry.logicalOffset(
                forRawOffset: containerScrollView.contentOffset.y
            )
        )
        let childDistance = committedChildScrollView.map {
            min(
                max(0, $0.contentOffset.y + $0.contentInset.top),
                childMaximumDistance
            )
        } ?? 0
        return .init(containerOffset: container, childDistance: childDistance)
    }

    func currentCanonicalTotal() -> CGFloat {
        let position = currentStablePosition()
        return position.containerOffset + position.childDistance
    }

    func apply(
        _ position: AnchorPagerScrollPositionResolver.Position,
        transitionBaseline: AnchorPagerScrollPositionResolver.Position? = nil
    ) {
        guard !isApplyingGuardedOffsets else { return }

        let previous = transitionBaseline ?? currentStablePosition()
        isApplyingGuardedOffsets = true
        defer { isApplyingGuardedOffsets = false }

        let nextOwner: Owner = position.childDistance > epsilon ? .child : .container
        let containerTarget = containerGeometry.rawOffset(
            forLogicalOffset: position.containerOffset
        )
        let childTarget = childTopOffset + position.childDistance

        let writeContainer = {
            if abs(self.containerScrollView.contentOffset.y - containerTarget)
                > self.epsilon {
                self.containerScrollView.contentOffset.y = containerTarget
            }
        }
        let writeChild = {
            guard let child = self.committedChildScrollView,
                  abs(child.contentOffset.y - childTarget) > self.epsilon else { return }
            child.contentOffset.y = childTarget
        }

        if nextOwner == .child {
            writeContainer()
            writeChild()
        } else {
            writeChild()
            writeContainer()
        }

        logTransitions(from: previous, to: position)
        transitionOwnerIfNeeded(to: nextOwner)
    }

    func settleStableOffsets() {
        if overscrollCoordinator.activeOwner != nil {
            handleActiveBoundaryEnforcementResult(
                enforceAndObserveActiveBoundary(),
                resolverInput: nil
            )
            return
        }
        apply(normalizedStablePosition())
    }

    func normalizedStablePosition() -> AnchorPagerScrollPositionResolver.Position {
        let current = currentStablePosition()
        if current.childDistance > epsilon {
            return .init(
                containerOffset: containerGeometry.collapsibleDistance,
                childDistance: current.childDistance
            )
        }
        return .init(
            containerOffset: current.containerOffset,
            childDistance: 0
        )
    }

    func pinChildToTop() {
        guard let child = committedChildScrollView,
              abs(child.contentOffset.y - childTopOffset) > epsilon else { return }
        isApplyingGuardedOffsets = true
        defer { isApplyingGuardedOffsets = false }
        child.contentOffset.y = childTopOffset
        transitionOwnerIfNeeded(to: .container)
    }

    func beginBoundary(
        _ boundary: AnchorPagerOverscrollCoordinator.Boundary,
        resolverInput: AnchorPagerScrollPositionResolver.Input? = nil
    ) {
        let previousBoundaryOwner = overscrollCoordinator.activeOwner
        let route = overscrollCoordinator.begin(
            boundary: boundary,
            hasChild: committedChildScrollView != nil
        )
        reportTopBoundaryTransition(
            from: previousBoundaryOwner,
            to: overscrollCoordinator.activeOwner
        )
        switch route {
        case let .clampStableBoundary(boundary):
            switch boundary {
            case .top:
                apply(.init(containerOffset: 0, childDistance: 0))
            case .bottom:
                apply(.init(
                    containerOffset: containerGeometry.collapsibleDistance,
                    childDistance: childMaximumDistance
                ))
            }
        case .passThrough:
            handleActiveBoundaryEnforcementResult(
                enforceAndObserveActiveBoundary(),
                resolverInput: resolverInput
            )
        }
    }

    private func enforceAndObserveActiveBoundary() -> ActiveBoundaryEnforcementResult {
        guard let active = overscrollCoordinator.activeOwner else { return .inactive }
        switch (active.boundary, active.owner) {
        case (.top, .container):
            pinChildToTop()
        case (.top, .child):
            writeContainerBoundary(0)
        case (.bottom, .child):
            writeContainerBoundary(containerGeometry.collapsibleDistance)
        case (.bottom, .container):
            break
        }

        let result = overscrollCoordinator.observeActiveOverflow(
            activeOverflowDistance(active)
        )
        switch result {
        case .inactive:
            return .inactive
        case .active:
            return .active
        case .finished:
            return .finished(active)
        }
    }

    private func handleActiveBoundaryEnforcementResult(
        _ result: ActiveBoundaryEnforcementResult,
        resolverInput: AnchorPagerScrollPositionResolver.Input?
    ) {
        guard case let .finished(finishedOwner) = result else { return }
        reportTopBoundaryTransition(from: finishedOwner, to: nil)
        overscrollCoordinator.reachedStableRange()
        if let resolverInput {
            apply(AnchorPagerScrollPositionResolver.resolve(resolverInput))
        } else {
            applyStablePositionAfterObservedBoundaryFinish(finishedOwner)
        }
        finishPendingBoundaryRecoveryInteractionIfNeeded()
    }

    func applyStablePositionAfterObservedBoundaryFinish(
        _ finishedOwner: AnchorPagerOverscrollCoordinator.ActiveOwner
    ) {
        guard finishedOwner.boundary == .top,
              finishedOwner.owner == .child,
              let child = committedChildScrollView else {
            apply(normalizedStablePosition())
            return
        }
        let containerBoundary: CGFloat = 0
        let rawChildDistance = child.contentOffset.y - childTopOffset
        apply(AnchorPagerScrollPositionResolver.resolveCanonicalTotal(
            containerBoundary + rawChildDistance,
            containerCollapsedOffset: containerGeometry.collapsibleDistance,
            childMaximumDistance: childMaximumDistance,
            fallback: currentStablePosition()
        ))
    }

    func activeOverflowDistance(
        _ active: AnchorPagerOverscrollCoordinator.ActiveOwner
    ) -> CGFloat {
        switch (active.boundary, active.owner) {
        case (.top, .container):
            return containerGeometry.topOverflow(
                forRawOffset: containerScrollView.contentOffset.y
            )
        case (.top, .child):
            let distance = (committedChildScrollView?.contentOffset.y ?? childTopOffset)
                - childTopOffset
            return max(0, -distance)
        case (.bottom, .child):
            let distance = (committedChildScrollView?.contentOffset.y ?? childTopOffset)
                - childTopOffset
            return max(0, distance - childMaximumDistance)
        case (.bottom, .container):
            return containerGeometry.bottomOverflow(
                forRawOffset: containerScrollView.contentOffset.y
            )
        }
    }

    func writeContainerBoundary(_ logicalTarget: CGFloat) {
        let rawTarget = containerGeometry.rawOffset(forLogicalOffset: logicalTarget)
        guard abs(containerScrollView.contentOffset.y - rawTarget) > epsilon else { return }
        isApplyingGuardedOffsets = true
        defer { isApplyingGuardedOffsets = false }
        containerScrollView.contentOffset.y = rawTarget
    }

    func handleObservedBoundaryIfNeeded() -> Bool {
        let containerLogicalOffset = containerGeometry.logicalOffset(
            forRawOffset: containerScrollView.contentOffset.y
        )
        let childDistance = committedChildScrollView.map {
            $0.contentOffset.y + $0.contentInset.top
        }
        if overscrollCoordinator.activeOwner == nil {
            if containerLogicalOffset < -boundaryEpsilon {
                beginBoundary(.top)
                return true
            } else if (childDistance ?? 0) < -boundaryEpsilon,
                      containerLogicalOffset <= boundaryEpsilon {
                beginBoundary(.top)
                return true
            } else if let childDistance,
                      containerLogicalOffset
                        >= containerGeometry.collapsibleDistance - boundaryEpsilon,
                      childDistance > childMaximumDistance + boundaryEpsilon {
                beginBoundary(.bottom)
                return true
            } else if committedChildScrollView == nil,
                      containerLogicalOffset
                        > containerGeometry.collapsibleDistance + boundaryEpsilon {
                beginBoundary(.bottom)
                return true
            }
        }
        guard overscrollCoordinator.activeOwner != nil else { return false }
        handleActiveBoundaryEnforcementResult(
            enforceAndObserveActiveBoundary(),
            resolverInput: nil
        )
        return true
    }

    func childDidChange(token: Int) {
        guard token == bindingToken else {
            AnchorPagerLogger.log(
                .debug,
                category: .scroll,
                event: "scroll.binding.stale"
            )
            return
        }
        guard !isApplyingGuardedOffsets else { return }
        if handleDecelerationNativeCallback(source: .child(token: token)) {
            return
        }
        if handleObservedBoundaryIfNeeded() {
            return
        }
        let containerLogicalOffset = containerGeometry.logicalOffset(
            forRawOffset: containerScrollView.contentOffset.y
        )
        if containerLogicalOffset < containerGeometry.collapsibleDistance - epsilon {
            pinChildToTop()
            return
        }
        settleStableOffsets()
    }

    func childGeometryDidChange(token: Int) {
        guard token == bindingToken else {
            AnchorPagerLogger.log(
                .debug,
                category: .scroll,
                event: "scroll.binding.stale"
            )
            return
        }
        cancelActiveVerticalInteractionForStructuralChange()
        childDidChange(token: token)
    }

    func emitInteractionEvent(_ event: AnchorPagerVerticalInteractionEvent) {
        interactionDelegate?.scrollCoordinator(self, didEmit: event)
    }

    func reportTopBoundaryTransition(
        from previous: AnchorPagerOverscrollCoordinator.ActiveOwner?,
        to current: AnchorPagerOverscrollCoordinator.ActiveOwner?,
        interactionIdentifier explicitIdentifier: Int? = nil
    ) {
        let interactionIdentifier = explicitIdentifier
            ?? verticalInteractionIdentifier
            ?? pendingBoundaryRecoveryInteractionIdentifier
        guard let interactionIdentifier else { return }

        let previousWasTop = previous?.boundary == .top
        let currentIsTop = current?.boundary == .top
        if previousWasTop, !currentIsTop,
           topOverscrollInteractionIdentifier == interactionIdentifier {
            topOverscrollInteractionIdentifier = nil
            emitInteractionEvent(
                .leftTopOverscroll(identifier: interactionIdentifier)
            )
        }
        if !previousWasTop, currentIsTop,
           topOverscrollInteractionIdentifier != interactionIdentifier {
            topOverscrollInteractionIdentifier = interactionIdentifier
            emitInteractionEvent(
                .enteredTopOverscroll(identifier: interactionIdentifier)
            )
        }
    }

    func finishPendingBoundaryRecoveryInteractionIfNeeded() {
        guard verticalInteractionIdentifier == nil,
              let interactionIdentifier = pendingBoundaryRecoveryInteractionIdentifier else {
            return
        }
        pendingBoundaryRecoveryInteractionIdentifier = nil
        emitInteractionEvent(.finishedDragging(identifier: interactionIdentifier))
    }

    func cancelPendingBoundaryRecoveryInteractionIfNeeded() {
        guard let interactionIdentifier = pendingBoundaryRecoveryInteractionIdentifier else {
            return
        }
        pendingBoundaryRecoveryInteractionIdentifier = nil
        topOverscrollInteractionIdentifier = nil
        emitInteractionEvent(.cancelled(identifier: interactionIdentifier))
    }

    func cancelActiveVerticalInteractionForStructuralChange() {
        let draggingIdentifier = verticalInteractionIdentifier
        let boundaryIdentifier = pendingBoundaryRecoveryInteractionIdentifier
        cancelSyntheticDeceleration()

        gestureStartTotal = nil
        activePanSources.removeAll()
        primaryPanSource = nil
        verticalInteractionIdentifier = nil
        pendingBoundaryRecoveryInteractionIdentifier = nil
        didAttemptDecelerationForInteraction = false
        didCancelCurrentPanInteraction = false
        topOverscrollInteractionIdentifier = nil

        if let draggingIdentifier {
            emitInteractionEvent(.cancelled(identifier: draggingIdentifier))
        }
        if let boundaryIdentifier, boundaryIdentifier != draggingIdentifier {
            emitInteractionEvent(.cancelled(identifier: boundaryIdentifier))
        }
    }

    func endCurrentBindingIfNeeded() {
        guard childBinding != nil else { return }
        childBinding?.invalidate()
        childBinding = nil
        AnchorPagerLogger.log(.info, category: .scroll, event: "scroll.binding.end")
    }

    func transitionOwnerIfNeeded(to nextOwner: Owner) {
        guard owner != nextOwner else { return }
        owner = nextOwner
        AnchorPagerLogger.log(
            .info,
            category: .scroll,
            event: nextOwner == .container
                ? "scroll.owner.container"
                : "scroll.owner.child"
        )
    }

    func logTransitions(
        from previous: AnchorPagerScrollPositionResolver.Position,
        to current: AnchorPagerScrollPositionResolver.Position
    ) {
        if previous.containerOffset < containerGeometry.collapsibleDistance - epsilon,
           current.containerOffset >= containerGeometry.collapsibleDistance - epsilon {
            AnchorPagerLogger.log(
                .info,
                category: .scroll,
                event: "scroll.boundary.collapsed"
            )
        }
        if previous.containerOffset > epsilon, current.containerOffset <= epsilon {
            AnchorPagerLogger.log(
                .info,
                category: .scroll,
                event: "scroll.boundary.expanded"
            )
        }
        if previous.childDistance > epsilon, current.childDistance <= epsilon {
            AnchorPagerLogger.log(
                .info,
                category: .scroll,
                event: "scroll.boundary.childTop"
            )
        }
        if previous.childDistance <= epsilon, current.childDistance > epsilon {
            AnchorPagerLogger.log(
                .info,
                category: .scroll,
                event: "scroll.handoff.containerToChild"
            )
        }
        if previous.childDistance > epsilon, current.childDistance <= epsilon {
            AnchorPagerLogger.log(
                .info,
                category: .scroll,
                event: "scroll.handoff.childToContainer"
            )
        }
    }

    @objc func handleContainerPan(_ pan: UIPanGestureRecognizer) {
        handlePan(
            source: .container,
            state: pan.state,
            translationY: pan.translation(in: pan.view).y,
            velocityY: pan.velocity(in: pan.view).y
        )
    }
}
