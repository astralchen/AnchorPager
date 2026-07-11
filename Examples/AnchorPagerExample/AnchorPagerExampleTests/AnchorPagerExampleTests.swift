import AnchorPager
import Testing
import UIKit
@testable import AnchorPagerExample

@MainActor
struct AnchorPagerExampleTests {
    @Test func rootControllerInstallsAnchorPager() {
        let tabBarController = makeExampleRootViewController()
        let navigationController = tabBarController.viewControllers?.first as? UINavigationController
        let viewController = navigationController?.viewControllers.first as? ExamplePagerViewController

        viewController?.loadViewIfNeeded()

        #expect(tabBarController.viewControllers?.count == 1)
        #expect(navigationController?.tabBarItem.title == "AnchorPager")
        #expect(navigationController?.tabBarItem.image != nil)
        #expect(navigationController?.tabBarItem.selectedImage != nil)
        #expect(viewController?.title == "AnchorPager")
    }

    @Test func pagerNavigationShowsHeaderTopBehaviorMenuWithCurrentConfiguration() {
        let viewController = ExamplePagerViewController()

        viewController.loadViewIfNeeded()

        let items = viewController.navigationItem.rightBarButtonItems ?? []
        let behaviorItem = items.first { $0.accessibilityLabel == "Header 顶部行为" }
        let actions = behaviorItem?.menu?.children.compactMap { $0 as? UIAction } ?? []

        #expect(items.contains { $0.accessibilityLabel == "打开 AnchorPager" })
        #expect(behaviorItem?.title == "安全区内")
        #expect(actions.map(\.title) == ["安全区内", "延伸到顶部"])
        #expect(actions.map(\.state) == [.on, .off])
    }

    @Test func headerTopBehaviorMenuAppliesExtendsUnderTopSafeAreaCoverage() throws {
        let viewController = ExamplePagerViewController()
        let navigationController = UINavigationController(rootViewController: viewController)
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [navigationController]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
        let pagerViewController = try #require(
            viewController.children.compactMap { $0 as? AnchorPagerViewController }.first
        )
        let layoutProbe = LayoutProbe()
        pagerViewController.delegate = layoutProbe
        pagerViewController.verticalScrollView.contentOffset = CGPoint(x: 0, y: 80)
        pagerViewController.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        window.layoutIfNeeded()
        let collapsedContext = try #require(layoutProbe.layoutContexts.last)

        let behaviorItem = try #require(
            viewController.navigationItem.rightBarButtonItems?.first {
                $0.accessibilityLabel == "Header 顶部行为"
            }
        )
        let extendsAction = try #require(
            behaviorItem.menu?.children.compactMap { $0 as? UIAction }.first {
                $0.title == "延伸到顶部"
            }
        )
        if #available(iOS 16.0, *) {
            extendsAction.performWithSender(nil, target: nil)
        }
        window.layoutIfNeeded()
        let switchedContext = try #require(layoutProbe.layoutContexts.last)
        let expectedHeaderHeight = collapsedContext.headerFrame.height
            + collapsedContext.headerFrame.minY

        #expect(abs(pagerViewController.verticalScrollView.contentOffset.y - 80) < 0.5)
        #expect(abs(switchedContext.headerFrame.minY) < 0.5)
        #expect(abs(switchedContext.headerFrame.height - expectedHeaderHeight) < 0.5)
        #expect(abs(switchedContext.barFrame.minY - switchedContext.headerFrame.maxY) < 0.5)
        #expect(abs(switchedContext.barFrame.minY - collapsedContext.barFrame.minY) < 0.5)
    }

    @Test func headerContentUsesSafeAreaForVerticalPaddingInBothTopBehaviors() throws {
        let viewController = ExamplePagerViewController()
        let navigationController = UINavigationController(rootViewController: viewController)
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [navigationController]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
        let pagerViewController = try #require(
            viewController.children.compactMap { $0 as? AnchorPagerViewController }.first
        )
        let titleLabel = try #require(
            firstSubview(in: pagerViewController.view, as: UILabel.self) {
                $0.text == "AnchorPager Example"
            }
        )
        let subtitleLabel = try #require(
            firstSubview(in: pagerViewController.view, as: UILabel.self) {
                $0.text == "Header UIView、显式 scroll view、无 scroll view child"
            }
        )
        let stackView = try #require(titleLabel.superview as? UIStackView)
        let headerView = try #require(stackView.superview)
        let layoutProbe = LayoutProbe()
        pagerViewController.delegate = layoutProbe

        for behavior in [
            AnchorPagerHeaderTopBehavior.insideSafeArea,
            .extendsUnderTopSafeArea
        ] {
            pagerViewController.configuration.header.topBehavior = behavior
            pagerViewController.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
            window.layoutIfNeeded()

            let safeAreaFrame = headerView.safeAreaLayoutGuide.layoutFrame
            #expect(abs(stackView.frame.minY - (safeAreaFrame.minY + 20)) < 0.5)
            let titleIntrinsicHeight = titleLabel.intrinsicContentSize.height
            let subtitleFittingHeight = subtitleLabel.systemLayoutSizeFitting(
                CGSize(
                    width: subtitleLabel.bounds.width,
                    height: UIView.layoutFittingCompressedSize.height
                ),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            #expect(abs(titleLabel.bounds.height - titleIntrinsicHeight) < 0.5)
            #expect(abs(subtitleLabel.bounds.height - subtitleFittingHeight) < 0.5)
            #expect(abs(subtitleLabel.frame.minY - titleLabel.frame.maxY - 8) < 0.5)
            #expect(stackView.frame.maxY <= safeAreaFrame.maxY - 20 + 0.5)

            if behavior == .extendsUnderTopSafeArea {
                let context = try #require(layoutProbe.layoutContexts.last)
                #expect(abs(context.headerFrame.minY) < 0.5)
                let titleFrameBeforeBounce = titleLabel.frame
                let subtitleFrameBeforeBounce = subtitleLabel.frame
                pagerViewController.verticalScrollView.contentOffset = CGPoint(x: 0, y: -24)
                window.layoutIfNeeded()
                #expect(abs(titleLabel.frame.minY - titleFrameBeforeBounce.minY) < 0.5)
                #expect(abs(titleLabel.frame.height - titleFrameBeforeBounce.height) < 0.5)
                #expect(abs(subtitleLabel.frame.minY - subtitleFrameBeforeBounce.minY) < 0.5)
                #expect(abs(subtitleLabel.frame.height - subtitleFrameBeforeBounce.height) < 0.5)
                #expect(abs(subtitleLabel.frame.minY - titleLabel.frame.maxY - 8) < 0.5)
                pagerViewController.verticalScrollView.contentOffset = .zero
            }
        }
    }
}

@MainActor
private final class LayoutProbe: AnchorPagerViewControllerDelegate {
    var layoutContexts: [AnchorPagerLayoutContext] = []

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didSelectViewControllerAt index: Int
    ) {}

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateHeaderCollapseProgress progress: CGFloat
    ) {}

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateLayout context: AnchorPagerLayoutContext
    ) {
        layoutContexts.append(context)
    }
}

@MainActor
private func firstSubview<T: UIView>(
    in rootView: UIView,
    as type: T.Type,
    matching predicate: (T) -> Bool
) -> T? {
    if let rootView = rootView as? T, predicate(rootView) {
        return rootView
    }
    for subview in rootView.subviews {
        if let match = firstSubview(in: subview, as: type, matching: predicate) {
            return match
        }
    }
    return nil
}
