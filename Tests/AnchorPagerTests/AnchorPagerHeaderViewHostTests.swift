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

        install(.view(headerView), in: parent, using: host)

        XCTAssertTrue(host.view.superview === parent.view)
        XCTAssertTrue(headerView.superview === host.view)
    }

    @MainActor
    func testInstallsAndRemovesHeaderViewControllerUsingContainment() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerController = UIViewController()
        let host = AnchorPagerHeaderViewHost()

        install(.viewController(headerController), in: parent, using: host)

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
        var preparationCount = 0

        let didInstall = install(
            .view(headerView),
            in: parent,
            using: host,
            prepareHostForContent: { _ in preparationCount += 1 }
        )
        let didReinstall = install(
            .view(headerView),
            in: parent,
            using: host,
            prepareHostForContent: { _ in preparationCount += 1 }
        )

        XCTAssertTrue(didInstall)
        XCTAssertFalse(didReinstall)
        XCTAssertEqual(preparationCount, 1)
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

        install(.viewController(headerController), in: parent, using: host)
        events.removeAll()
        install(.viewController(headerController), in: parent, using: host)

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
        install(.view(headerView), in: parent, using: host)

        let height = host.measure(in: CGSize(width: 320, height: 0))

        XCTAssertEqual(height, 64)
    }

    @MainActor
    func testBootstrapMeasurementReturnsFittingHeightWithoutPublishingFormalMeasurementLog() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerView = FixedFittingView(height: 64)
        let host = AnchorPagerHeaderViewHost()
        install(.view(headerView), in: parent, using: host)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        let height = host.bootstrapMeasurement(in: CGSize(width: 320, height: 0))

        XCTAssertEqual(height, 64)
        XCTAssertFalse(events.contains { $0.event == "header.measure" })
        XCTAssertFalse(events.contains { $0.event == "header.measure.invalid" })
    }

    @MainActor
    func testMeasuresHeaderViewControllerFromPreferredContentSize() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerController = UIViewController()
        headerController.preferredContentSize = CGSize(width: 320, height: 80)
        let host = AnchorPagerHeaderViewHost()
        install(.viewController(headerController), in: parent, using: host)

        let height = host.measure(in: CGSize(width: 320, height: 0))

        XCTAssertEqual(height, 80)
    }

    @MainActor
    func testMeasuresHeaderViewControllerFromViewFittingSizeWhenPreferredSizeIsEmpty() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerController = FittingHeaderViewController(height: 92)
        let host = AnchorPagerHeaderViewHost()
        install(.viewController(headerController), in: parent, using: host)

        let height = host.measure(in: CGSize(width: 320, height: 0))

        XCTAssertEqual(height, 92)
    }

    @MainActor
    func testInvalidHeaderMeasurementFallsBackToZeroAndWritesLayoutLog() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let headerView = InvalidFittingView()
        let host = AnchorPagerHeaderViewHost()
        install(.view(headerView), in: parent, using: host)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        let height = AnchorPagerAssertions.$isEnabled.withValue(false) {
            host.measure(in: CGSize(width: 320, height: 0))
        }

        XCTAssertEqual(height, 0)
        XCTAssertTrue(
            events.contains(
                .init(category: .layout, level: .error, event: "header.measure.invalid")
            )
        )
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

        install(.viewController(headerController), in: parent, using: host)
        _ = host.measure(in: CGSize(width: 320, height: 0))
        host.remove()

        XCTAssertTrue(events.contains(.init(category: .header, level: .info, event: "header.controller.add")))
        XCTAssertTrue(events.contains(.init(category: .lifecycle, level: .info, event: "header.controller.didMove")))
        XCTAssertTrue(events.contains(.init(category: .layout, level: .debug, event: "header.measure")))
        XCTAssertTrue(events.contains(.init(category: .header, level: .info, event: "header.controller.remove")))
    }

    @MainActor
    func testInstallPreparesBootstrapHeightBeforeAttachingHeaderView() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        var events: [String] = []
        let headerView = AttachmentRecordingFittingView(height: 64) {
            events.append("attach")
        }
        let host = AnchorPagerHeaderViewHost()

        install(
            .view(headerView),
            in: parent,
            using: host,
            prepareHostForContent: { height in
                events.append("prepare:\(Int(height))")
            }
        )

        XCTAssertEqual(events, ["prepare:64", "attach"])
    }

    @MainActor
    func testInstallingHeaderViewControllerPreparesAfterContainmentBeginsAndBeforeAttachment() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        var events: [String] = []
        let headerController = ContainmentRecordingHeaderViewController(
            expectedParent: parent,
            onEvent: { events.append($0) }
        )
        let host = AnchorPagerHeaderViewHost()

        install(
            .viewController(headerController),
            in: parent,
            using: host,
            prepareHostForContent: { height in
                events.append("prepare:\(Int(height))")
            }
        )

        XCTAssertEqual(
            events,
            ["loadWithParent", "prepare:80", "attach", "didMove"]
        )
    }

    @MainActor
    @discardableResult
    private func install(
        _ content: AnchorPagerHeaderContent,
        in parentViewController: UIViewController,
        using host: AnchorPagerHeaderViewHost,
        prepareHostForContent: (CGFloat) -> Void = { _ in }
    ) -> Bool {
        host.install(
            content,
            in: parentViewController,
            bootstrapMeasurementSize: CGSize(width: 320, height: 0),
            prepareHostForContent: prepareHostForContent
        )
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

private final class FittingHeaderViewController: UIViewController {
    private let measuredHeight: CGFloat

    init(height: CGFloat) {
        self.measuredHeight = height
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = FixedFittingView(height: measuredHeight)
    }
}

private final class InvalidFittingView: UIView {
    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        CGSize(width: targetSize.width, height: -12)
    }
}

private final class AttachmentRecordingFittingView: UIView {
    private let measuredHeight: CGFloat
    private let onAttach: () -> Void

    init(height: CGFloat, onAttach: @escaping () -> Void) {
        self.measuredHeight = height
        self.onAttach = onAttach
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil {
            onAttach()
        }
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        CGSize(width: targetSize.width, height: measuredHeight)
    }
}

private final class ContainmentRecordingHeaderViewController: UIViewController {
    private weak var expectedParent: UIViewController?
    private let onEvent: (String) -> Void

    init(
        expectedParent: UIViewController,
        onEvent: @escaping (String) -> Void
    ) {
        self.expectedParent = expectedParent
        self.onEvent = onEvent
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        onEvent(parent === expectedParent ? "loadWithParent" : "loadWithoutParent")
        view = AttachmentRecordingFittingView(height: 80) { [onEvent] in
            onEvent("attach")
        }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil {
            onEvent("didMove")
        }
    }
}
