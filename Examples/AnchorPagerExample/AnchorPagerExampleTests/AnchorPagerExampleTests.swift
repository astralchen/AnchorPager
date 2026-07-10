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
}
