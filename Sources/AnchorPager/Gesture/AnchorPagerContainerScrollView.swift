import UIKit

@MainActor
final class AnchorPagerContainerScrollView: UIScrollView, UIGestureRecognizerDelegate {
    private weak var currentChildPan: UIPanGestureRecognizer?

    func bindCurrentChildPan(_ pan: UIPanGestureRecognizer?) {
        guard currentChildPan !== pan else { return }
        currentChildPan = pan
        if pan != nil {
            AnchorPagerLogger.log(
                .info,
                category: .gesture,
                event: "gesture.simultaneous.enabled"
            )
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let currentChildPan else { return false }
        return (gestureRecognizer === panGestureRecognizer
            && otherGestureRecognizer === currentChildPan)
            || (gestureRecognizer === currentChildPan
                && otherGestureRecognizer === panGestureRecognizer)
    }
}
