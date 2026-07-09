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
        XCTAssertTrue(child.parent === host)
        XCTAssertTrue(child.view.superview === host.scrollView)
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
