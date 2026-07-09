import Testing
import UIKit
@testable import AnchorPagerExample

@MainActor
struct AnchorPagerExampleTests {
    @Test func rootControllerInstallsAnchorPager() {
        let viewController = ExamplePagerViewController()
        viewController.loadViewIfNeeded()

        #expect(viewController.title == "AnchorPager")
    }
}
