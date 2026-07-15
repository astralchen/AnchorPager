import CoreGraphics

@MainActor
final class AnchorPagerOverscrollCoordinator {
    enum Boundary: Equatable {
        case top
        case bottom
    }

    enum Owner: Equatable {
        case container
        case child
    }

    struct ActiveOwner: Equatable {
        let boundary: Boundary
        let owner: Owner
    }

    enum Route: Equatable {
        case clampStableBoundary(Boundary)
        case passThrough(ActiveOwner)
    }

    enum ObservationResult: Equatable {
        case inactive
        case active
        case finished
    }

    enum UnpresentedOwnerFinishResult: Equatable {
        case inactive
        case presented
        case finished
    }

    private(set) var topMode: AnchorPagerTopOverscrollHandlingMode
    private(set) var activeOwner: ActiveOwner?
    private var activeHasPresentedOverflow = false
    private var requestedBoundary: Boundary?
    private var didLogUnavailable = false
    private let epsilon: CGFloat = 0.5

    init(topMode: AnchorPagerTopOverscrollHandlingMode) {
        self.topMode = topMode
    }

    func updateTopMode(_ mode: AnchorPagerTopOverscrollHandlingMode) {
        guard topMode != mode else { return }
        cancel()
        topMode = mode
        AnchorPagerLogger.log(.info, category: .overscroll, event: "overscroll.mode.changed")
    }

    func begin(boundary: Boundary, hasChild: Bool) -> Route {
        if let activeOwner {
            guard activeOwner.boundary != boundary,
                  !activeHasPresentedOverflow else {
                return .passThrough(activeOwner)
            }
            finish()
        }
        if requestedBoundary != boundary {
            requestedBoundary = boundary
            AnchorPagerLogger.log(
                .info,
                category: .overscroll,
                event: boundary == .top
                    ? "overscroll.boundary.top"
                    : "overscroll.boundary.bottom"
            )
        }

        let owner: Owner?
        switch boundary {
        case .top:
            switch topMode {
            case .none:
                owner = nil
            case .container:
                owner = .container
            case .child:
                owner = hasChild ? .child : nil
                if !hasChild, !didLogUnavailable {
                    didLogUnavailable = true
                    AnchorPagerLogger.log(
                        .info,
                        category: .overscroll,
                        event: "overscroll.owner.unavailable"
                    )
                }
            }
        case .bottom:
            owner = hasChild ? .child : .container
        }

        guard let owner else {
            return .clampStableBoundary(boundary)
        }
        let active = ActiveOwner(boundary: boundary, owner: owner)
        activeOwner = active
        activeHasPresentedOverflow = false
        AnchorPagerLogger.log(
            .info,
            category: .overscroll,
            event: owner == .container
                ? "overscroll.owner.container.begin"
                : "overscroll.owner.child.begin"
        )
        return .passThrough(active)
    }

    func observeActiveOverflow(_ distance: CGFloat) -> ObservationResult {
        guard activeOwner != nil else { return .inactive }
        let overflow = distance.isFinite ? max(0, distance) : 0
        if overflow > epsilon {
            activeHasPresentedOverflow = true
            return .active
        }
        guard activeHasPresentedOverflow else { return .active }
        finish()
        return .finished
    }

    func endInteraction() -> Bool {
        requestedBoundary = nil
        didLogUnavailable = false
        guard activeOwner != nil, !activeHasPresentedOverflow else { return false }
        finish()
        return true
    }

    func finishUnpresentedActiveOwner() -> UnpresentedOwnerFinishResult {
        guard activeOwner != nil else { return .inactive }
        guard !activeHasPresentedOverflow else { return .presented }
        finish()
        return .finished
    }

    func reachedStableRange() {
        guard activeOwner == nil else { return }
        requestedBoundary = nil
        didLogUnavailable = false
    }

    @discardableResult
    func cancel() -> Bool {
        requestedBoundary = nil
        didLogUnavailable = false
        activeHasPresentedOverflow = false
        guard activeOwner != nil else { return false }
        activeOwner = nil
        AnchorPagerLogger.log(.info, category: .overscroll, event: "overscroll.owner.cancel")
        return true
    }

    private func finish() {
        activeOwner = nil
        activeHasPresentedOverflow = false
        requestedBoundary = nil
        didLogUnavailable = false
        AnchorPagerLogger.log(.info, category: .overscroll, event: "overscroll.owner.finish")
    }
}
