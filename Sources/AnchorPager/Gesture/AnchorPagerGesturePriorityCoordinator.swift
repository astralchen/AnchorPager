import UIKit

/// 管理系统返回与分页之间经过真实 UIKit 验证的公开失败依赖。
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

    func refresh() {
        installedRelations.removeAll { !$0.isAlive }
        guard let pagingPan else { return }

        guard let interactivePopGesture,
              interactivePopGesture !== pagingPan,
              installRelationIfNeeded(
                  from: pagingPan,
                  to: interactivePopGesture
              ) else { return }
        AnchorPagerLogger.log(
            .info,
            category: .gesture,
            event: "gesture.priority.interactivePop"
        )
    }

    func invalidate() {
        pagingPan = nil
        interactivePopGesture = nil
        installedRelations.removeAll()
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
    ) -> Bool {
        guard !installedRelations.contains(where: {
            $0.matches(gesture: gesture, requiredGesture: requiredGesture)
        }) else { return false }

        failureInstaller(gesture, requiredGesture)
        installedRelations.append(
            InstalledRelation(
                gesture: gesture,
                requiredGesture: requiredGesture
            )
        )
        return true
    }
}
