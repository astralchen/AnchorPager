import UIKit
import XCTest
@testable import AnchorPager

final class AnchorPagerHeaderViewHostTests: XCTestCase {
    @MainActor
    func testInstallsHeaderViewInsideHostView() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerView = UIView()
        let host = AnchorPagerHeaderViewHost()

        host.install(.view(headerView), in: parent)

        XCTAssertTrue(host.view.superview === parent.view)
        XCTAssertTrue(headerView.superview === host.view)
    }

    @MainActor
    func testInstallsAndRemovesHeaderViewControllerUsingContainment() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerController = UIViewController()
        let host = AnchorPagerHeaderViewHost()

        host.install(.viewController(headerController), in: parent)

        XCTAssertTrue(headerController.parent === parent)
        XCTAssertTrue(headerController.view.superview === host.view)

        host.remove()

        XCTAssertNil(headerController.parent)
        XCTAssertNil(headerController.view.superview)
        XCTAssertNil(host.view.superview)
    }

    @MainActor
    func testReinstallingSameHeaderViewIsNoOp() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerView = CountingHeaderView()
        let host = AnchorPagerHeaderViewHost()

        host.install(.view(headerView), in: parent)
        host.install(.view(headerView), in: parent)

        XCTAssertTrue(headerView.superview === host.view)
        XCTAssertEqual(headerView.removeFromSuperviewCallCount, 0)
        XCTAssertEqual(host.view.subviews.filter { $0 === headerView }.count, 1)
    }

    @MainActor
    func testReinstallingSameHeaderViewControllerDoesNotRemoveAndReaddContainment() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerController = UIViewController()
        let host = AnchorPagerHeaderViewHost()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        host.install(.viewController(headerController), in: parent)
        events.removeAll()
        host.install(.viewController(headerController), in: parent)

        XCTAssertTrue(headerController.parent === parent)
        XCTAssertTrue(headerController.view.superview === host.view)
        XCTAssertFalse(events.contains(.init(category: .header, level: .info, event: "header.controller.remove")))
        XCTAssertFalse(events.contains(.init(category: .lifecycle, level: .info, event: "header.controller.removeFromParent")))
        XCTAssertEqual(events.filter { $0.event == "header.controller.add" }.count, 0)
    }

    @MainActor
    func testMeasuresHeaderViewFromAutoLayoutFittingSize() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerView = FixedFittingView(height: 64)
        let host = AnchorPagerHeaderViewHost()
        host.install(.view(headerView), in: parent)

        let height = host.measure(in: CGSize(width: 320, height: 0))

        XCTAssertEqual(height, 64)
    }

    @MainActor
    func testMeasuresHeaderViewControllerFromPreferredContentSize() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerController = UIViewController()
        headerController.preferredContentSize = CGSize(width: 320, height: 80)
        let host = AnchorPagerHeaderViewHost()
        host.install(.viewController(headerController), in: parent)

        let height = host.measure(in: CGSize(width: 320, height: 0))

        XCTAssertEqual(height, 80)
    }

    @MainActor
    func testHeaderInstallMeasureAndRemoveWriteLogs() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerController = UIViewController()
        let host = AnchorPagerHeaderViewHost()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        host.install(.viewController(headerController), in: parent)
        _ = host.measure(in: CGSize(width: 320, height: 0))
        host.remove()

        XCTAssertTrue(events.contains(.init(category: .header, level: .info, event: "header.controller.add")))
        XCTAssertTrue(events.contains(.init(category: .lifecycle, level: .info, event: "header.controller.didMove")))
        XCTAssertTrue(events.contains(.init(category: .layout, level: .debug, event: "header.measure")))
        XCTAssertTrue(events.contains(.init(category: .header, level: .info, event: "header.controller.remove")))
    }
}

private final class FixedFittingView: UIView {
    private let measuredHeight: CGFloat

    init(height: CGFloat) {
        self.measuredHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        CGSize(width: targetSize.width, height: measuredHeight)
    }
}

private final class CountingHeaderView: UIView {
    private(set) var removeFromSuperviewCallCount = 0

    override func removeFromSuperview() {
        removeFromSuperviewCallCount += 1
        super.removeFromSuperview()
    }
}
