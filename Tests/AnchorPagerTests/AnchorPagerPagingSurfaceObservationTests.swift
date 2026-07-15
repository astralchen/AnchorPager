import UIKit
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerPagingSurfaceObservationTests: XCTestCase {
    func testRefreshDiscoversOnlyContainedPageViewControllerPagingSurface() throws {
        let root = UIViewController()
        root.loadViewIfNeeded()
        let standaloneScrollView = UIScrollView()
        root.view.addSubview(standaloneScrollView)
        let pageViewController = makePageViewController()
        root.view.addSubview(pageViewController.view)
        let observation = AnchorPagerPagingSurfaceObservation()
        var surfaces: [AnchorPagerPagingSurfaceObservation.Surface?] = []
        observation.onSurfaceChanged = { surfaces.append($0) }

        observation.refresh(in: root)

        XCTAssertNil(observation.surface)
        XCTAssertTrue(surfaces.isEmpty)

        attach(pageViewController, to: root)
        observation.refresh(in: root)

        let surface = try XCTUnwrap(observation.surface)
        XCTAssertTrue(surface.pageViewController === pageViewController)
        XCTAssertTrue(surface.scrollView === pagingScrollView(in: pageViewController))
        XCTAssertTrue(surface.panGestureRecognizer === surface.scrollView.panGestureRecognizer)
        XCTAssertEqual(surfaces.count, 1)
    }

    func testRefreshPrefersPagingScrollViewOverBusinessPageScrollView() throws {
        let root = UIViewController()
        root.loadViewIfNeeded()
        let pageViewController = makePageViewController()
        let businessScrollView = UIScrollView()
        let businessPage = UIViewController()
        businessPage.view = businessScrollView
        pageViewController.setViewControllers(
            [businessPage],
            direction: .forward,
            animated: false
        )
        attach(pageViewController, to: root)
        let observation = AnchorPagerPagingSurfaceObservation()

        observation.refresh(in: root)

        let surface = try XCTUnwrap(observation.surface)
        XCTAssertTrue(surface.scrollView === pagingScrollView(in: pageViewController))
        XCTAssertFalse(surface.scrollView === businessScrollView)
    }

    func testSameIdentityIsIdempotentAndReplacementUnbindsBeforeBinding() throws {
        let recorder = TargetActionRecorder()
        let observation = makeObservation(recorder: recorder)
        let root = UIViewController()
        root.loadViewIfNeeded()
        let firstPageViewController = makePageViewController()
        attach(firstPageViewController, to: root)
        let firstScrollView = try XCTUnwrap(
            pagingScrollView(in: firstPageViewController)
        )
        let firstScrollDelegate = firstScrollView.delegate
        let firstPanDelegate = firstScrollView.panGestureRecognizer.delegate
        var surfaces: [AnchorPagerPagingSurfaceObservation.Surface?] = []
        observation.onSurfaceChanged = { surfaces.append($0) }

        observation.refresh(in: root)
        observation.refresh(in: root)

        let firstPan = try XCTUnwrap(observation.surface?.panGestureRecognizer)
        XCTAssertEqual(recorder.operations, [.add(ObjectIdentifier(firstPan))])
        XCTAssertEqual(surfaces.count, 1)

        detach(firstPageViewController)
        let secondPageViewController = makePageViewController()
        attach(secondPageViewController, to: root)
        let secondScrollView = try XCTUnwrap(
            pagingScrollView(in: secondPageViewController)
        )
        let secondScrollDelegate = secondScrollView.delegate
        let secondPanDelegate = secondScrollView.panGestureRecognizer.delegate
        observation.refresh(in: root)

        let secondPan = try XCTUnwrap(observation.surface?.panGestureRecognizer)
        XCTAssertEqual(
            recorder.operations,
            [
                .add(ObjectIdentifier(firstPan)),
                .remove(ObjectIdentifier(firstPan)),
                .add(ObjectIdentifier(secondPan))
            ]
        )
        XCTAssertEqual(surfaces.count, 2)
        XCTAssertTrue(surfaces[1]?.pageViewController === secondPageViewController)
        XCTAssertTrue(firstScrollView.delegate === firstScrollDelegate)
        XCTAssertTrue(firstScrollView.panGestureRecognizer.delegate === firstPanDelegate)
        XCTAssertTrue(secondScrollView.delegate === secondScrollDelegate)
        XCTAssertTrue(secondScrollView.panGestureRecognizer.delegate === secondPanDelegate)
    }

    func testPanTargetForwardsStateWithoutChangingDelegates() throws {
        let recorder = TargetActionRecorder()
        let observation = makeObservation(recorder: recorder)
        let root = UIViewController()
        root.loadViewIfNeeded()
        let pageViewController = makePageViewController()
        attach(pageViewController, to: root)
        let scrollView = try XCTUnwrap(pagingScrollView(in: pageViewController))
        let originalScrollDelegate = scrollView.delegate
        let originalPanDelegate = scrollView.panGestureRecognizer.delegate
        var states: [UIGestureRecognizer.State] = []
        observation.onPanStateChanged = { states.append($0) }

        observation.refresh(in: root)
        recorder.invokeLatestTarget()

        XCTAssertEqual(states, [.possible])
        XCTAssertTrue(scrollView.delegate === originalScrollDelegate)
        XCTAssertTrue(scrollView.panGestureRecognizer.delegate === originalPanDelegate)

        observation.invalidate()

        XCTAssertTrue(scrollView.delegate === originalScrollDelegate)
        XCTAssertTrue(scrollView.panGestureRecognizer.delegate === originalPanDelegate)
    }

    func testInvalidateAndDeinitAreIdempotent() throws {
        let recorder = TargetActionRecorder()
        let root = UIViewController()
        root.loadViewIfNeeded()
        let pageViewController = makePageViewController()
        attach(pageViewController, to: root)
        var observation: AnchorPagerPagingSurfaceObservation? = makeObservation(
            recorder: recorder
        )
        var surfaceChangeCount = 0
        observation?.onSurfaceChanged = { _ in surfaceChangeCount += 1 }
        observation?.refresh(in: root)
        let pan = try XCTUnwrap(observation?.surface?.panGestureRecognizer)

        observation?.invalidate()
        observation?.invalidate()

        XCTAssertNil(observation?.surface)
        XCTAssertEqual(
            recorder.operations,
            [.add(ObjectIdentifier(pan)), .remove(ObjectIdentifier(pan))]
        )
        XCTAssertEqual(surfaceChangeCount, 2)

        weak let weakObservation = observation
        observation = nil

        XCTAssertNil(weakObservation)
        XCTAssertEqual(
            recorder.operations,
            [.add(ObjectIdentifier(pan)), .remove(ObjectIdentifier(pan))]
        )

        let activeRecorder = TargetActionRecorder()
        var activeObservation: AnchorPagerPagingSurfaceObservation? = makeObservation(
            recorder: activeRecorder
        )
        activeObservation?.refresh(in: root)
        let activePan = try XCTUnwrap(
            activeObservation?.surface?.panGestureRecognizer
        )
        weak let weakActiveObservation = activeObservation

        activeObservation = nil

        XCTAssertNil(weakActiveObservation)
        XCTAssertEqual(
            activeRecorder.operations,
            [.add(ObjectIdentifier(activePan)), .remove(ObjectIdentifier(activePan))]
        )
    }

    func testSurfaceLifecycleUsesUnifiedLoggerWithoutIdentityPayload() {
        let root = UIViewController()
        root.loadViewIfNeeded()
        let pageViewController = makePageViewController()
        attach(pageViewController, to: root)
        let observation = AnchorPagerPagingSurfaceObservation()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        observation.refresh(in: root)
        observation.invalidate()

        XCTAssertEqual(
            events.filter { $0.event.hasPrefix("paging.surface.") },
            [
                AnchorPagerLogger.Event(
                    category: .paging,
                    level: .debug,
                    event: "paging.surface.bind"
                ),
                AnchorPagerLogger.Event(
                    category: .paging,
                    level: .debug,
                    event: "paging.surface.unbind"
                ),
            ]
        )
    }

    func testObservationSourceDoesNotUsePrivateNamesOrDelegateAndBounceWrites() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/AnchorPager/Paging/AnchorPagerPagingSurfaceObservation.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("UIQueuingScrollView"))
        XCTAssertFalse(source.contains("_UI"))
        XCTAssertFalse(source.contains(".delegate ="))
        XCTAssertFalse(source.contains("isScrollEnabled ="))
        XCTAssertFalse(source.contains(".bounces ="))
        XCTAssertFalse(source.contains(".alwaysBounceVertical ="))
    }

    private func makeObservation(
        recorder: TargetActionRecorder
    ) -> AnchorPagerPagingSurfaceObservation {
        AnchorPagerPagingSurfaceObservation(
            addTarget: { recognizer, target, action in
                recorder.add(recognizer: recognizer, target: target, action: action)
            },
            removeTarget: { recognizer, target, action in
                recorder.remove(recognizer: recognizer, target: target, action: action)
            }
        )
    }

    private func makePageViewController() -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        pageViewController.loadViewIfNeeded()
        return pageViewController
    }

    private func pagingScrollView(
        in pageViewController: UIPageViewController
    ) -> UIScrollView? {
        pageViewController.view.subviews.compactMap { $0 as? UIScrollView }.first
    }

    private func attach(
        _ child: UIViewController,
        to parent: UIViewController
    ) {
        if child.parent !== parent {
            parent.addChild(child)
        }
        if child.view.superview !== parent.view {
            parent.view.addSubview(child.view)
        }
        child.didMove(toParent: parent)
    }

    private func detach(_ child: UIViewController) {
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }

    private func packageRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent("Package.swift").path
            ) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

@MainActor
private final class TargetActionRecorder {
    enum Operation: Equatable {
        case add(ObjectIdentifier)
        case remove(ObjectIdentifier)
    }

    private final class Registration {
        weak var target: NSObject?
        let recognizer: UIGestureRecognizer
        let action: Selector

        init(target: NSObject, recognizer: UIGestureRecognizer, action: Selector) {
            self.target = target
            self.recognizer = recognizer
            self.action = action
        }
    }

    private(set) var operations: [Operation] = []
    private var latestRegistration: Registration?

    func add(
        recognizer: UIGestureRecognizer,
        target: Any?,
        action: Selector
    ) {
        operations.append(.add(ObjectIdentifier(recognizer)))
        latestRegistration = Registration(
            target: target as! NSObject,
            recognizer: recognizer,
            action: action
        )
    }

    func remove(
        recognizer: UIGestureRecognizer,
        target: Any?,
        action: Selector
    ) {
        operations.append(.remove(ObjectIdentifier(recognizer)))
        latestRegistration = nil
    }

    func invokeLatestTarget() {
        guard let registration = latestRegistration,
              let target = registration.target else { return }
        _ = target.perform(registration.action, with: registration.recognizer)
    }
}
