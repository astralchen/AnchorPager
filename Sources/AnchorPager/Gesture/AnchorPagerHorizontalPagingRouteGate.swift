import UIKit

@MainActor
final class AnchorPagerHorizontalPagingRouteGate:
    UIPanGestureRecognizer,
    UIGestureRecognizerDelegate {
    typealias HitTest = (UIView, CGPoint) -> UIView?
    typealias Velocity = (UIPanGestureRecognizer, UIView) -> CGPoint

    private weak var pagingScrollView: UIScrollView?
    private weak var pagingPan: UIPanGestureRecognizer?
    private let hitTest: HitTest
    private let velocityProvider: Velocity

    init(
        pagingScrollView: UIScrollView,
        pagingPan: UIPanGestureRecognizer,
        hitTest: @escaping HitTest = { root, point in root.hitTest(point, with: nil) },
        velocity: @escaping Velocity = { pan, view in pan.velocity(in: view) }
    ) {
        self.pagingScrollView = pagingScrollView
        self.pagingPan = pagingPan
        self.hitTest = hitTest
        velocityProvider = velocity
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === self,
              let pagingScrollView else {
            return false
        }
        let point = location(in: pagingScrollView)
        let velocity = velocityProvider(self, pagingScrollView)
        let hitView = hitTest(pagingScrollView, point)
        let decision = AnchorPagerHorizontalScrollBoundaryResolver.decision(
            for: horizontalGeometries(from: hitView, stoppingAt: pagingScrollView),
            velocity: velocity
        )
        AnchorPagerLogger.log(
            .debug,
            category: .gesture,
            event: decision.logEvent
        )
        return decision == .content
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === self && otherGestureRecognizer !== pagingPan
    }

    private func horizontalGeometries(
        from hitView: UIView?,
        stoppingAt pagingScrollView: UIScrollView
    ) -> [AnchorPagerHorizontalScrollBoundaryResolver.Geometry] {
        var geometries: [AnchorPagerHorizontalScrollBoundaryResolver.Geometry] = []
        var current = hitView
        while let view = current, view !== pagingScrollView {
            if let scrollView = view as? UIScrollView {
                let inset = scrollView.adjustedContentInset
                geometries.append(.init(
                    contentOffsetX: scrollView.contentOffset.x,
                    contentSizeWidth: scrollView.contentSize.width,
                    boundsWidth: scrollView.bounds.width,
                    adjustedInsetLeft: inset.left,
                    adjustedInsetRight: inset.right
                ))
            }
            current = view.superview
        }
        return geometries
    }
}

private extension AnchorPagerHorizontalScrollBoundaryResolver.Decision {
    var logEvent: String {
        switch self {
        case .content: "gesture.horizontalRoute.content"
        case .pagingBoundary: "gesture.horizontalRoute.pagingBoundary"
        case .noCandidate: "gesture.horizontalRoute.noCandidate"
        }
    }
}
