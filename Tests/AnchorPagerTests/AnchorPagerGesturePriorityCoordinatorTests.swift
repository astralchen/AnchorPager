import UIKit
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerGesturePriorityCoordinatorTests: XCTestCase {
    func testFailureMatrixInstallsSystemAndHorizontalCurrentRelationsOnce() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let pagingPan = UIPanGestureRecognizer()
        let interactivePop = UIScreenEdgePanGestureRecognizer()
        let currentScrollView = makeScrollView(contentWidth: 640)
        let cachedScrollView = makeScrollView(contentWidth: 900)

        coordinator.bindPagingPan(pagingPan)
        coordinator.bindInteractivePopGesture(interactivePop)
        coordinator.bindCommittedScrollView(currentScrollView)
        coordinator.refresh()
        coordinator.refresh()

        XCTAssertEqual(
            recorder.relations,
            [
                .init(gesture: pagingPan, required: interactivePop),
                .init(
                    gesture: pagingPan,
                    required: currentScrollView.panGestureRecognizer
                ),
            ]
        )
        XCTAssertFalse(
            recorder.contains(
                gesture: pagingPan,
                required: cachedScrollView.panGestureRecognizer
            )
        )
    }

    func testPlainAndVerticalCurrentDoNotInstallChildRelation() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let pagingPan = UIPanGestureRecognizer()
        let verticalScrollView = makeScrollView(contentWidth: 320)

        coordinator.bindPagingPan(pagingPan)
        coordinator.bindCommittedScrollView(nil)
        coordinator.refresh()
        coordinator.bindCommittedScrollView(verticalScrollView)
        coordinator.refresh()

        XCTAssertTrue(recorder.relations.isEmpty)

        verticalScrollView.contentSize.width = 319
        verticalScrollView.contentInset.left = 1
        verticalScrollView.contentInset.right = 1
        coordinator.refresh()

        XCTAssertEqual(
            recorder.relations,
            [
                .init(
                    gesture: pagingPan,
                    required: verticalScrollView.panGestureRecognizer
                )
            ]
        )
    }

    func testSurfaceReplacementRebuildsCurrentRelationsAndKeepsInstalledPairMonotonic() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let firstPagingPan = UIPanGestureRecognizer()
        let secondPagingPan = UIPanGestureRecognizer()
        let interactivePop = UIScreenEdgePanGestureRecognizer()
        let currentScrollView = makeScrollView(contentWidth: 640)

        coordinator.bindPagingPan(firstPagingPan)
        coordinator.bindInteractivePopGesture(interactivePop)
        coordinator.bindCommittedScrollView(currentScrollView)
        coordinator.refresh()

        currentScrollView.contentSize.width = 320
        coordinator.refresh()
        XCTAssertEqual(recorder.relations.count, 2)

        coordinator.bindPagingPan(secondPagingPan)
        coordinator.refresh()
        XCTAssertEqual(
            recorder.relations,
            [
                .init(gesture: firstPagingPan, required: interactivePop),
                .init(
                    gesture: firstPagingPan,
                    required: currentScrollView.panGestureRecognizer
                ),
                .init(gesture: secondPagingPan, required: interactivePop),
            ]
        )

        currentScrollView.contentSize.width = 640
        coordinator.refresh()
        coordinator.bindPagingPan(firstPagingPan)
        coordinator.refresh()

        XCTAssertEqual(recorder.relations.count, 4)
        XCTAssertTrue(
            recorder.contains(
                gesture: secondPagingPan,
                required: currentScrollView.panGestureRecognizer
            )
        )
    }

    func testBindingRefreshAndInvalidatePreserveAllDelegateAndScrollConfiguration() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let pagingPan = UIPanGestureRecognizer()
        let interactivePop = UIScreenEdgePanGestureRecognizer()
        let pagingDelegate = GestureDelegate()
        let popDelegate = GestureDelegate()
        let scrollDelegate = ScrollDelegate()
        pagingPan.delegate = pagingDelegate
        interactivePop.delegate = popDelegate
        let currentScrollView = makeScrollView(contentWidth: 640)
        currentScrollView.delegate = scrollDelegate
        currentScrollView.isScrollEnabled = false
        currentScrollView.bounces = false
        currentScrollView.alwaysBounceVertical = true
        let childPanDelegate = currentScrollView.panGestureRecognizer.delegate

        coordinator.bindPagingPan(pagingPan)
        coordinator.bindInteractivePopGesture(interactivePop)
        coordinator.bindCommittedScrollView(currentScrollView)
        coordinator.refresh()
        coordinator.invalidate()
        coordinator.invalidate()

        XCTAssertTrue(pagingPan.delegate === pagingDelegate)
        XCTAssertTrue(interactivePop.delegate === popDelegate)
        XCTAssertTrue(currentScrollView.delegate === scrollDelegate)
        XCTAssertTrue(currentScrollView.panGestureRecognizer.delegate === childPanDelegate)
        XCTAssertFalse(currentScrollView.isScrollEnabled)
        XCTAssertFalse(currentScrollView.bounces)
        XCTAssertTrue(currentScrollView.alwaysBounceVertical)
    }

    func testBindingsAndInstalledRelationsDoNotRetainGesturesOrScrollViews() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        var pagingPan: UIPanGestureRecognizer? = UIPanGestureRecognizer()
        var scrollView: UIScrollView? = makeScrollView(contentWidth: 640)
        weak let weakPagingPan = pagingPan
        weak let weakScrollView = scrollView

        coordinator.bindPagingPan(pagingPan)
        coordinator.bindCommittedScrollView(scrollView)
        coordinator.refresh()
        pagingPan = nil
        scrollView = nil

        XCTAssertNil(weakPagingPan)
        XCTAssertNil(weakScrollView)
        coordinator.invalidate()
    }

    func testSourceUsesOnlyPublicFailureRelationAndDoesNotTakeDelegateOwnership() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/AnchorPager/Gesture/AnchorPagerGesturePriorityCoordinator.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("require(toFail:"))
        XCTAssertFalse(source.contains(".delegate ="))
        XCTAssertFalse(source.contains("setValue("))
        XCTAssertFalse(source.contains("value(forKey:"))
        XCTAssertFalse(source.contains("_UI"))
        XCTAssertFalse(source.contains("isScrollEnabled ="))
        XCTAssertFalse(source.contains(".bounces ="))
        XCTAssertFalse(source.contains(".alwaysBounceVertical ="))
    }

    private func makeCoordinator(
        recorder: FailureRelationRecorder
    ) -> AnchorPagerGesturePriorityCoordinator {
        AnchorPagerGesturePriorityCoordinator { gesture, required in
            recorder.record(gesture: gesture, required: required)
        }
    }

    private func makeScrollView(contentWidth: CGFloat) -> UIScrollView {
        let scrollView = UIScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 640)
        )
        scrollView.contentSize = CGSize(width: contentWidth, height: 1_200)
        return scrollView
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
private final class FailureRelationRecorder {
    struct Relation: Equatable {
        let gestureIdentifier: ObjectIdentifier
        let requiredIdentifier: ObjectIdentifier

        init(gesture: UIGestureRecognizer, required: UIGestureRecognizer) {
            gestureIdentifier = ObjectIdentifier(gesture)
            requiredIdentifier = ObjectIdentifier(required)
        }
    }

    private(set) var relations: [Relation] = []

    func record(
        gesture: UIGestureRecognizer,
        required: UIGestureRecognizer
    ) {
        relations.append(.init(gesture: gesture, required: required))
    }

    func contains(
        gesture: UIGestureRecognizer,
        required: UIGestureRecognizer
    ) -> Bool {
        relations.contains(.init(gesture: gesture, required: required))
    }
}

@MainActor
private final class GestureDelegate: NSObject, UIGestureRecognizerDelegate {}

@MainActor
private final class ScrollDelegate: NSObject, UIScrollViewDelegate {}
