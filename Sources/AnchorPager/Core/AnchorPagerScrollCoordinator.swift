import UIKit

@MainActor
final class AnchorPagerScrollCoordinator {
    enum Owner: Equatable {
        case container
        case child
    }

    private let containerScrollView: AnchorPagerContainerScrollView
    private let overscrollCoordinator: AnchorPagerOverscrollCoordinator
    private var childBinding: AnchorPagerChildScrollBinding?
    private weak var committedChildScrollView: UIScrollView?
    private var bindingToken = 0
    private var collapsibleDistance: CGFloat = 0
    private var gestureStartTotal: CGFloat?
    private var gestureStartTranslationY: CGFloat = 0
    private var isApplyingGuardedOffsets = false
    private var isInvalidated = false
    private(set) var owner: Owner = .container

    var bindingTokenForTesting: Int { bindingToken }
    var activeBoundaryForTesting: AnchorPagerOverscrollCoordinator.ActiveOwner? {
        overscrollCoordinator.activeOwner
    }

    init(containerScrollView: AnchorPagerContainerScrollView) {
        self.containerScrollView = containerScrollView
        self.overscrollCoordinator = AnchorPagerOverscrollCoordinator(topMode: .container)
        containerScrollView.panGestureRecognizer.addTarget(
            self,
            action: #selector(handleContainerPan(_:))
        )
    }

    func updateGeometry(collapsibleDistance: CGFloat) {
        let next = max(0, collapsibleDistance.isFinite ? collapsibleDistance : 0)
        if abs(self.collapsibleDistance - next) > epsilon {
            overscrollCoordinator.cancel()
        }
        self.collapsibleDistance = next
        settleStableOffsets()
    }

    func bindCommittedChild(_ scrollView: UIScrollView?) {
        guard !isInvalidated, committedChildScrollView !== scrollView else { return }

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
                self?.childDidChange(token: token)
            },
            onPan: { [weak self] state, _ in
                self?.childPanStateDidChange(state: state, token: token)
            }
        )
        settleStableOffsets()
    }

    func containerDidScroll() {
        guard !isInvalidated else { return }
        guard !isApplyingGuardedOffsets else {
            AnchorPagerLogger.log(
                .debug,
                category: .scroll,
                event: "scroll.offset.guard.skip"
            )
            return
        }
        if handleObservedBoundaryIfNeeded() {
            return
        }
        settleStableOffsets()
    }

    func handlePan(state: UIGestureRecognizer.State, translationY: CGFloat) {
        guard !isInvalidated else { return }
        switch state {
        case .began:
            gestureStartTotal = currentCanonicalTotal()
            gestureStartTranslationY = translationY
        case .changed:
            guard let gestureStartTotal else { return }
            let input = AnchorPagerScrollPositionResolver.Input(
                gestureStartTotal: gestureStartTotal,
                gestureStartTranslationY: gestureStartTranslationY,
                currentTranslationY: translationY,
                containerCollapsedOffset: collapsibleDistance,
                childMaximumDistance: childMaximumDistance,
                fallback: currentStablePosition()
            )
            guard let desiredTotal = AnchorPagerScrollPositionResolver
                .unclampedDesiredTotal(input) else {
                apply(AnchorPagerScrollPositionResolver.resolve(input))
                return
            }
            let maximumStableTotal = collapsibleDistance + childMaximumDistance
            if desiredTotal < -boundaryEpsilon {
                beginBoundary(.top)
            } else if desiredTotal > maximumStableTotal + boundaryEpsilon {
                beginBoundary(.bottom)
            } else if overscrollCoordinator.activeOwner == nil {
                overscrollCoordinator.reachedStableRange()
                apply(AnchorPagerScrollPositionResolver.resolve(input))
            } else {
                enforceAndObserveActiveBoundary()
            }
        case .ended, .cancelled, .failed:
            gestureStartTotal = nil
            if overscrollCoordinator.endInteraction() {
                settleStableOffsets()
            } else if overscrollCoordinator.activeOwner == nil {
                settleStableOffsets()
            }
        default:
            break
        }
    }

    func handleChildChangeForTesting(token: Int) {
        childDidChange(token: token)
    }

    func cancelBoundaryHandling() {
        let didCancel = overscrollCoordinator.cancel()
        if didCancel {
            apply(currentStablePosition())
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
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

    func currentStablePosition() -> AnchorPagerScrollPositionResolver.Position {
        let container = min(
            max(0, containerScrollView.contentOffset.y),
            collapsibleDistance
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

    func apply(_ position: AnchorPagerScrollPositionResolver.Position) {
        guard !isApplyingGuardedOffsets else {
            AnchorPagerLogger.log(
                .debug,
                category: .scroll,
                event: "scroll.offset.guard.skip"
            )
            return
        }

        let previous = currentStablePosition()
        isApplyingGuardedOffsets = true
        defer { isApplyingGuardedOffsets = false }

        let nextOwner: Owner = position.childDistance > epsilon ? .child : .container
        let childTarget = childTopOffset + position.childDistance

        let writeContainer = {
            if abs(self.containerScrollView.contentOffset.y - position.containerOffset)
                > self.epsilon {
                self.containerScrollView.contentOffset.y = position.containerOffset
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
            enforceAndObserveActiveBoundary()
            return
        }
        let current = currentStablePosition()
        let normalized: AnchorPagerScrollPositionResolver.Position
        if current.childDistance > epsilon {
            normalized = .init(
                containerOffset: collapsibleDistance,
                childDistance: current.childDistance
            )
        } else {
            normalized = .init(
                containerOffset: current.containerOffset,
                childDistance: 0
            )
        }
        apply(normalized)
    }

    func pinChildToTop() {
        guard let child = committedChildScrollView,
              abs(child.contentOffset.y - childTopOffset) > epsilon else { return }
        isApplyingGuardedOffsets = true
        defer { isApplyingGuardedOffsets = false }
        child.contentOffset.y = childTopOffset
        transitionOwnerIfNeeded(to: .container)
    }

    func beginBoundary(_ boundary: AnchorPagerOverscrollCoordinator.Boundary) {
        let route = overscrollCoordinator.begin(
            boundary: boundary,
            hasChild: committedChildScrollView != nil
        )
        switch route {
        case let .clampStableBoundary(boundary):
            switch boundary {
            case .top:
                apply(.init(containerOffset: 0, childDistance: 0))
            case .bottom:
                apply(.init(
                    containerOffset: collapsibleDistance,
                    childDistance: childMaximumDistance
                ))
            }
        case .passThrough:
            enforceAndObserveActiveBoundary()
        }
    }

    func enforceAndObserveActiveBoundary() {
        guard let active = overscrollCoordinator.activeOwner else { return }
        switch (active.boundary, active.owner) {
        case (.top, .container):
            pinChildToTop()
        case (.top, .child):
            writeContainerBoundary(0)
        case (.bottom, .child):
            writeContainerBoundary(collapsibleDistance)
        case (.bottom, .container):
            break
        }

        let result = overscrollCoordinator.observeActiveOverflow(
            activeOverflowDistance(active)
        )
        if result == .finished {
            settleStableOffsets()
        }
    }

    func activeOverflowDistance(
        _ active: AnchorPagerOverscrollCoordinator.ActiveOwner
    ) -> CGFloat {
        switch (active.boundary, active.owner) {
        case (.top, .container):
            return max(0, -containerScrollView.contentOffset.y)
        case (.top, .child):
            let distance = (committedChildScrollView?.contentOffset.y ?? childTopOffset)
                - childTopOffset
            return max(0, -distance)
        case (.bottom, .child):
            let distance = (committedChildScrollView?.contentOffset.y ?? childTopOffset)
                - childTopOffset
            return max(0, distance - childMaximumDistance)
        case (.bottom, .container):
            return max(0, containerScrollView.contentOffset.y - collapsibleDistance)
        }
    }

    func writeContainerBoundary(_ target: CGFloat) {
        guard abs(containerScrollView.contentOffset.y - target) > epsilon else { return }
        isApplyingGuardedOffsets = true
        defer { isApplyingGuardedOffsets = false }
        containerScrollView.contentOffset.y = target
    }

    func handleObservedBoundaryIfNeeded() -> Bool {
        let childDistance = committedChildScrollView.map {
            $0.contentOffset.y + $0.contentInset.top
        }
        if overscrollCoordinator.activeOwner == nil {
            if containerScrollView.contentOffset.y < -boundaryEpsilon
                || (childDistance ?? 0) < -boundaryEpsilon {
                beginBoundary(.top)
            } else if let childDistance,
                      childDistance > childMaximumDistance + boundaryEpsilon {
                beginBoundary(.bottom)
            } else if committedChildScrollView == nil,
                      containerScrollView.contentOffset.y
                        > collapsibleDistance + boundaryEpsilon {
                beginBoundary(.bottom)
            }
        }
        guard overscrollCoordinator.activeOwner != nil else { return false }
        enforceAndObserveActiveBoundary()
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
        guard !isApplyingGuardedOffsets else {
            AnchorPagerLogger.log(
                .debug,
                category: .scroll,
                event: "scroll.offset.guard.skip"
            )
            return
        }
        if handleObservedBoundaryIfNeeded() {
            return
        }
        if containerScrollView.contentOffset.y < collapsibleDistance - epsilon {
            pinChildToTop()
            return
        }
        settleStableOffsets()
    }

    func childPanStateDidChange(
        state: UIGestureRecognizer.State,
        token: Int
    ) {
        guard token == bindingToken else {
            AnchorPagerLogger.log(
                .debug,
                category: .scroll,
                event: "scroll.binding.stale"
            )
            return
        }
        guard gestureStartTotal == nil,
              state == .ended || state == .cancelled || state == .failed else { return }
        settleStableOffsets()
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
        if previous.containerOffset < collapsibleDistance - epsilon,
           current.containerOffset >= collapsibleDistance - epsilon {
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
            state: pan.state,
            translationY: pan.translation(in: pan.view).y
        )
    }
}
