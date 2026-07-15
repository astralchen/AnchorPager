enum AnchorPagerInteractionState: Equatable, Sendable {
    case idle
    case verticalDragging(identifier: Int)
    case verticalDecelerating(identifier: Int)
    case horizontalPaging(identifier: Int)
    case programmaticPaging(identifier: Int)
    case topOverscrolling(identifier: Int)
    case layoutReloading(identifier: Int)
    case transitioningSize(identifier: Int)
}

extension AnchorPagerInteractionState {
    var identifier: Int? {
        switch self {
        case .idle:
            nil
        case let .verticalDragging(identifier),
             let .verticalDecelerating(identifier),
             let .horizontalPaging(identifier),
             let .programmaticPaging(identifier),
             let .topOverscrolling(identifier),
             let .layoutReloading(identifier),
             let .transitioningSize(identifier):
            identifier
        }
    }

    var canResumeAfterSizeTransition: Bool {
        switch self {
        case .horizontalPaging, .programmaticPaging, .layoutReloading:
            true
        case .idle,
             .verticalDragging,
             .verticalDecelerating,
             .topOverscrolling,
             .transitioningSize:
            false
        }
    }

    var isVerticalInteraction: Bool {
        switch self {
        case .verticalDragging, .verticalDecelerating, .topOverscrolling:
            true
        case .idle,
             .horizontalPaging,
             .programmaticPaging,
             .layoutReloading,
             .transitioningSize:
            false
        }
    }
}
