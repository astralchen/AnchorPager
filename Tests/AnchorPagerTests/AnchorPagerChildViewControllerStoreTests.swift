import UIKit
import XCTest
@testable import AnchorPager

final class AnchorPagerChildViewControllerStoreTests: XCTestCase {
    @MainActor
    func testSetViewControllersAddsChildrenUsingContainment() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let child = UIViewController()
        let store = AnchorPagerChildViewControllerStore()

        store.setViewControllers([child], in: parent)

        XCTAssertTrue(store.view.superview === parent.view)
        XCTAssertTrue(child.parent === parent)
        XCTAssertTrue(child.view.superview === store.view)
        XCTAssertTrue(store.viewController(at: 0) === child)
    }

    @MainActor
    func testSetViewControllersRemovesOldChildrenBeforeInstallingNewOnes() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let oldChild = UIViewController()
        let newChild = UIViewController()
        let store = AnchorPagerChildViewControllerStore()
        store.setViewControllers([oldChild], in: parent)

        store.setViewControllers([newChild], in: parent)

        XCTAssertNil(oldChild.parent)
        XCTAssertNil(oldChild.view.superview)
        XCTAssertTrue(newChild.parent === parent)
        XCTAssertTrue(store.viewController(at: 0) === newChild)
    }

    @MainActor
    func testRemoveAllClearsChildrenAndHostView() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let child = UIViewController()
        let store = AnchorPagerChildViewControllerStore()
        store.setViewControllers([child], in: parent)

        store.removeAll()

        XCTAssertNil(child.parent)
        XCTAssertNil(child.view.superview)
        XCTAssertNil(store.view.superview)
        XCTAssertNil(store.viewController(at: 0))
    }

    @MainActor
    func testFallbackPageScrollHostContainsNonScrollChild() {
        let child = UIViewController()
        child.view.backgroundColor = .red
        let host = AnchorPagerPageScrollHostViewController(contentViewController: child)

        host.loadViewIfNeeded()

        XCTAssertTrue(host.scrollView === host.view)
        XCTAssertEqual(host.scrollView.contentInsetAdjustmentBehavior, .never)
        XCTAssertTrue(child.parent === host)
        XCTAssertTrue(child.view.superview === host.scrollView)
    }

    @MainActor
    func testFallbackPageScrollHostKeepsPlainChildVisibleWithinViewport() {
        let child = UIViewController()
        let label = UILabel()
        label.text = "Plain"
        label.translatesAutoresizingMaskIntoConstraints = false
        child.loadViewIfNeeded()
        child.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: child.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: child.view.centerYAnchor)
        ])
        let host = AnchorPagerPageScrollHostViewController(contentViewController: child)
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)

        host.loadViewIfNeeded()
        host.view.layoutIfNeeded()

        XCTAssertGreaterThanOrEqual(child.view.frame.height, host.scrollView.frameLayoutGuide.layoutFrame.height)
    }

    @MainActor
    func testFallbackPageScrollHostContentRemovalIsIdempotent() {
        let child = UIViewController()
        let host = AnchorPagerPageScrollHostViewController(contentViewController: child)
        host.loadViewIfNeeded()

        host.removeContentForReloadData()
        host.removeContentForReloadData()

        XCTAssertNil(child.parent)
        XCTAssertNil(child.view.superview)
        XCTAssertTrue(host.children.isEmpty)
    }

    @MainActor
    func testChildStoreAndFallbackHostWriteLogs() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let child = UIViewController()
        let store = AnchorPagerChildViewControllerStore()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        store.setViewControllers([child], in: parent)
        store.removeAll()
        _ = AnchorPagerPageScrollHostViewController(contentViewController: UIViewController())

        XCTAssertTrue(events.contains(.init(category: .children, level: .info, event: "child.add")))
        XCTAssertTrue(events.contains(.init(category: .children, level: .info, event: "child.remove")))
        XCTAssertTrue(events.contains(.init(category: .scroll, level: .info, event: "fallbackHost.create")))
    }
}
