import ObjectiveC
import UIKit

@MainActor private var anchorPagerExplicitScrollViewKey: UInt8 = 0
@MainActor private var anchorPagerUsesDefaultLookupKey: UInt8 = 0

private final class AnchorPagerWeakScrollViewBox: NSObject {
    weak var scrollView: UIScrollView?

    init(scrollView: UIScrollView?) {
        self.scrollView = scrollView
    }
}

@MainActor
extension UIViewController {
    /// AnchorPager 用于 Header 折叠与纵向协调的页面滚动视图。
    ///
    /// 显式设置优先；未设置时按默认规则查找。只有横向滚动视图的页面应关闭
    /// ``anchorPagerUsesDefaultScrollViewLookup``，且不要把横向滚动视图设置到此属性。
    public var anchorPagerScrollView: UIScrollView? {
        get {
            if let box = objc_getAssociatedObject(
                self,
                &anchorPagerExplicitScrollViewKey
            ) as? AnchorPagerWeakScrollViewBox,
                let scrollView = box.scrollView {
                AnchorPagerLogger.log(.debug, category: .scroll, event: "scroll.explicit")
                return scrollView
            }
            return anchorPagerDefaultScrollView
        }
        set {
            if let newValue {
                objc_setAssociatedObject(
                    self,
                    &anchorPagerExplicitScrollViewKey,
                    AnchorPagerWeakScrollViewBox(scrollView: newValue),
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            } else {
                objc_setAssociatedObject(
                    self,
                    &anchorPagerExplicitScrollViewKey,
                    nil,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }

    /// 是否启用纵向协调目标的默认滚动视图查找。
    ///
    /// 默认查找不推断滚动轴向。只有横向滚动视图的页面应将此属性设为 `false`。
    public var anchorPagerUsesDefaultScrollViewLookup: Bool {
        get {
            guard let number = objc_getAssociatedObject(
                self,
                &anchorPagerUsesDefaultLookupKey
            ) as? NSNumber else {
                return true
            }
            return number.boolValue
        }
        set {
            objc_setAssociatedObject(
                self,
                &anchorPagerUsesDefaultLookupKey,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    /// 按确定性深度优先规则查找的默认纵向协调目标。
    ///
    /// 查找结果不包含轴向推断；混合滚动页面应显式设置纵向父滚动视图。
    public var anchorPagerDefaultScrollView: UIScrollView? {
        guard anchorPagerUsesDefaultScrollViewLookup, isViewLoaded else { return nil }

        let childRootViews = Set(children.compactMap { child -> ObjectIdentifier? in
            guard child.isViewLoaded else { return nil }
            return ObjectIdentifier(child.view)
        })

        let scrollView = anchorPagerFirstEligibleScrollView(
            in: view,
            childRootViews: childRootViews,
            isRoot: true
        )

        if scrollView != nil {
            AnchorPagerLogger.log(.debug, category: .scroll, event: "scroll.defaultLookup")
        }
        return scrollView
    }

    private func anchorPagerFirstEligibleScrollView(
        in rootView: UIView,
        childRootViews: Set<ObjectIdentifier>,
        isRoot: Bool
    ) -> UIScrollView? {
        if !isRoot, childRootViews.contains(ObjectIdentifier(rootView)) {
            return nil
        }

        if let scrollView = rootView as? UIScrollView,
           anchorPagerIsEligibleScrollView(scrollView) {
            return scrollView
        }

        for subview in rootView.subviews {
            if let scrollView = anchorPagerFirstEligibleScrollView(
                in: subview,
                childRootViews: childRootViews,
                isRoot: false
            ) {
                return scrollView
            }
        }

        return nil
    }

    private func anchorPagerIsEligibleScrollView(_ scrollView: UIScrollView) -> Bool {
        !scrollView.isHidden
            && scrollView.alpha > 0.01
            && scrollView.isUserInteractionEnabled
    }
}
