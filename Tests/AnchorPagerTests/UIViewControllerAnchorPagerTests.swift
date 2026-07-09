import UIKit
import XCTest
@testable import AnchorPager

final class UIViewControllerAnchorPagerTests: XCTestCase {
    @MainActor
    func testExplicitScrollViewTakesPriorityOverDefaultLookup() {
        let viewController = UIViewController()
        viewController.loadViewIfNeeded()
        let defaultScrollView = UIScrollView()
        let explicitScrollView = UIScrollView()
        viewController.view.addSubview(defaultScrollView)
        viewController.anchorPagerScrollView = explicitScrollView

        XCTAssertTrue(viewController.anchorPagerScrollView === explicitScrollView)
    }

    @MainActor
    func testDefaultLookupFindsFirstDepthFirstScrollView() {
        let viewController = UIViewController()
        viewController.loadViewIfNeeded()
        let container = UIView()
        let scrollView = UIScrollView()
        viewController.view.addSubview(container)
        container.addSubview(scrollView)

        XCTAssertTrue(viewController.anchorPagerDefaultScrollView === scrollView)
        XCTAssertTrue(viewController.anchorPagerScrollView === scrollView)
    }

    @MainActor
    func testDefaultLookupChoosesFirstEligibleScrollView() {
        let viewController = UIViewController()
        viewController.loadViewIfNeeded()
        let firstContainer = UIView()
        let secondContainer = UIView()
        let firstScrollView = UIScrollView()
        let secondScrollView = UIScrollView()
        viewController.view.addSubview(firstContainer)
        viewController.view.addSubview(secondContainer)
        firstContainer.addSubview(firstScrollView)
        secondContainer.addSubview(secondScrollView)

        XCTAssertTrue(viewController.anchorPagerDefaultScrollView === firstScrollView)
    }

    @MainActor
    func testDefaultLookupIgnoresHiddenTransparentAndDisabledScrollViews() {
        let viewController = UIViewController()
        viewController.loadViewIfNeeded()
        let hiddenScrollView = UIScrollView()
        let transparentScrollView = UIScrollView()
        let disabledScrollView = UIScrollView()
        let eligibleScrollView = UIScrollView()
        hiddenScrollView.isHidden = true
        transparentScrollView.alpha = 0.001
        disabledScrollView.isUserInteractionEnabled = false
        viewController.view.addSubview(hiddenScrollView)
        viewController.view.addSubview(transparentScrollView)
        viewController.view.addSubview(disabledScrollView)
        viewController.view.addSubview(eligibleScrollView)

        XCTAssertTrue(viewController.anchorPagerDefaultScrollView === eligibleScrollView)
    }

    @MainActor
    func testDefaultLookupCanBeDisabled() {
        let viewController = UIViewController()
        viewController.loadViewIfNeeded()
        let scrollView = UIScrollView()
        viewController.view.addSubview(scrollView)

        viewController.anchorPagerUsesDefaultScrollViewLookup = false

        XCTAssertNil(viewController.anchorPagerDefaultScrollView)
        XCTAssertNil(viewController.anchorPagerScrollView)
    }

    @MainActor
    func testDefaultLookupDoesNotCrossChildViewControllerBoundary() {
        let parent = UIViewController()
        let child = UIViewController()
        parent.loadViewIfNeeded()
        child.loadViewIfNeeded()
        let childScrollView = UIScrollView()
        child.view.addSubview(childScrollView)
        parent.addChild(child)
        parent.view.addSubview(child.view)
        child.didMove(toParent: parent)

        XCTAssertNil(parent.anchorPagerDefaultScrollView)
        XCTAssertTrue(child.anchorPagerDefaultScrollView === childScrollView)
    }

    @MainActor
    func testExplicitAndDefaultLookupWriteScrollLogs() {
        let viewController = UIViewController()
        viewController.loadViewIfNeeded()
        let defaultScrollView = UIScrollView()
        let explicitScrollView = UIScrollView()
        viewController.view.addSubview(defaultScrollView)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        _ = viewController.anchorPagerDefaultScrollView
        viewController.anchorPagerScrollView = explicitScrollView
        _ = viewController.anchorPagerScrollView

        XCTAssertTrue(events.contains(.init(category: .scroll, level: .debug, event: "scroll.defaultLookup")))
        XCTAssertTrue(events.contains(.init(category: .scroll, level: .debug, event: "scroll.explicit")))
    }
}
