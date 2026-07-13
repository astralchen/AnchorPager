import UIKit

@MainActor
protocol AnchorPagerVerticalScrollDelegateOwner: AnyObject {
    func verticalScrollViewDidScroll(_ scrollView: UIScrollView)
}

@MainActor
final class AnchorPagerVerticalScrollDelegate: NSObject, UIScrollViewDelegate {
    weak var owner: AnchorPagerVerticalScrollDelegateOwner?

    init(owner: AnchorPagerVerticalScrollDelegateOwner) {
        self.owner = owner
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        owner?.verticalScrollViewDidScroll(scrollView)
    }
}
