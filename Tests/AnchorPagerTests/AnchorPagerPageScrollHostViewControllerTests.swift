import UIKit
import XCTest
@testable import AnchorPager

final class AnchorPagerPageScrollHostViewControllerTests: XCTestCase {
    @MainActor
    func testFallbackHostContainsNonScrollChild() {
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
    func testFallbackHostKeepsPlainChildVisibleWithinViewport() {
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

        XCTAssertGreaterThanOrEqual(
            child.view.frame.height,
            host.scrollView.frameLayoutGuide.layoutFrame.height
        )
    }

    @MainActor
    func testFallbackHostContentRemovalIsIdempotent() {
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
    func testFallbackHostCreationWritesLog() {
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        _ = AnchorPagerPageScrollHostViewController(contentViewController: UIViewController())

        XCTAssertTrue(events.contains(.init(
            category: .scroll,
            level: .info,
            event: "fallbackHost.create"
        )))
    }
}
