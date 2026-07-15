import UIKit

/// 管理系统返回、分页和当前业务横向滚动之间的公开失败依赖。
@MainActor
final class AnchorPagerGesturePriorityCoordinator {
    typealias FailureInstaller = (UIGestureRecognizer, UIGestureRecognizer) -> Void

    private final class InstalledRelation {
        weak var gesture: UIGestureRecognizer?
        weak var requiredGesture: UIGestureRecognizer?

        init(
            gesture: UIGestureRecognizer,
            requiredGesture: UIGestureRecognizer
        ) {
            self.gesture = gesture
            self.requiredGesture = requiredGesture
        }

        var isAlive: Bool {
            gesture != nil && requiredGesture != nil
        }

        func matches(
            gesture: UIGestureRecognizer,
            requiredGesture: UIGestureRecognizer
        ) -> Bool {
            self.gesture === gesture && self.requiredGesture === requiredGesture
        }
    }

    private weak var pagingPan: UIPanGestureRecognizer?
    private weak var interactivePopGesture: UIGestureRecognizer?
    private weak var committedScrollView: UIScrollView?
    private var installedRelations: [InstalledRelation] = []
    private let failureInstaller: FailureInstaller

    init(
        failureInstaller: @escaping FailureInstaller = { gesture, required in
            gesture.require(toFail: required)
        }
    ) {
        self.failureInstaller = failureInstaller
    }

    func bindPagingPan(_ pan: UIPanGestureRecognizer?) {
        pagingPan = pan
    }

    func bindInteractivePopGesture(_ gesture: UIGestureRecognizer?) {
        interactivePopGesture = gesture
    }

    func bindCommittedScrollView(_ scrollView: UIScrollView?) {
        committedScrollView = scrollView
    }

    func refresh() {
        installedRelations.removeAll { !$0.isAlive }
        guard let pagingPan else { return }

        if let interactivePopGesture,
           interactivePopGesture !== pagingPan {
            installRelationIfNeeded(
                from: pagingPan,
                to: interactivePopGesture
            )
        }

        if let committedScrollView,
           hasHorizontalScrollRange(committedScrollView) {
            let childPan = committedScrollView.panGestureRecognizer
            if childPan !== pagingPan {
                installRelationIfNeeded(from: pagingPan, to: childPan)
            }
        }
    }

    func invalidate() {
        pagingPan = nil
        interactivePopGesture = nil
        committedScrollView = nil
        installedRelations.removeAll { !$0.isAlive }
    }

    var committedScrollViewForTesting: UIScrollView? {
        committedScrollView
    }

    var pagingPanForTesting: UIPanGestureRecognizer? {
        pagingPan
    }

    func hasInstalledRelationForTesting(
        from gesture: UIGestureRecognizer,
        to requiredGesture: UIGestureRecognizer
    ) -> Bool {
        installedRelations.contains {
            $0.matches(gesture: gesture, requiredGesture: requiredGesture)
        }
    }

    private func installRelationIfNeeded(
        from gesture: UIGestureRecognizer,
        to requiredGesture: UIGestureRecognizer
    ) {
        guard !installedRelations.contains(where: {
            $0.matches(gesture: gesture, requiredGesture: requiredGesture)
        }) else { return }

        failureInstaller(gesture, requiredGesture)
        installedRelations.append(
            InstalledRelation(
                gesture: gesture,
                requiredGesture: requiredGesture
            )
        )
    }

    private func hasHorizontalScrollRange(_ scrollView: UIScrollView) -> Bool {
        let contentWidth = scrollView.contentSize.width
        let boundsWidth = scrollView.bounds.width
        let insets = scrollView.adjustedContentInset
        guard contentWidth.isFinite,
              boundsWidth.isFinite,
              insets.left.isFinite,
              insets.right.isFinite else {
            return false
        }
        return contentWidth + insets.left + insets.right > boundsWidth + 0.5
    }
}
