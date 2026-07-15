import UIKit
import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerGesturePriorityCoordinatorTests: XCTestCase {
    func testFailureMatrixInstallsOnlySystemBackRelationOnce() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let pagingPan = UIPanGestureRecognizer()
        let interactivePop = UIScreenEdgePanGestureRecognizer()

        coordinator.bindPagingPan(pagingPan)
        coordinator.bindInteractivePopGesture(interactivePop)
        coordinator.refresh()
        coordinator.refresh()

        XCTAssertEqual(
            recorder.relations,
            [.init(gesture: pagingPan, required: interactivePop)]
        )
    }

    func testBusinessChildPanIsNeverAddedToFailureMatrix() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let pagingPan = UIPanGestureRecognizer()
        let childScrollView = UIScrollView()
        childScrollView.contentSize.width = 900

        coordinator.bindPagingPan(pagingPan)
        coordinator.refresh()

        XCTAssertFalse(
            recorder.contains(
                gesture: pagingPan,
                required: childScrollView.panGestureRecognizer
            )
        )
    }

    func testSurfaceReplacementBuildsRelationForNewPagingPan() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let firstPagingPan = UIPanGestureRecognizer()
        let secondPagingPan = UIPanGestureRecognizer()
        let interactivePop = UIScreenEdgePanGestureRecognizer()

        coordinator.bindInteractivePopGesture(interactivePop)
        coordinator.bindPagingPan(firstPagingPan)
        coordinator.refresh()
        coordinator.bindPagingPan(secondPagingPan)
        coordinator.refresh()

        XCTAssertEqual(
            recorder.relations,
            [
                .init(gesture: firstPagingPan, required: interactivePop),
                .init(gesture: secondPagingPan, required: interactivePop),
            ]
        )
    }

    func testNewSystemRelationLogsOnce() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let pagingPan = UIPanGestureRecognizer()
        let interactivePop = UIScreenEdgePanGestureRecognizer()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        coordinator.bindPagingPan(pagingPan)
        coordinator.bindInteractivePopGesture(interactivePop)
        coordinator.refresh()
        coordinator.refresh()

        XCTAssertEqual(
            events,
            [
                .init(
                    category: .gesture,
                    level: .info,
                    event: "gesture.priority.interactivePop"
                )
            ]
        )
    }

    func testBindingRefreshAndInvalidatePreserveRecognizerDelegates() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let pagingPan = UIPanGestureRecognizer()
        let interactivePop = UIScreenEdgePanGestureRecognizer()
        let pagingDelegate = GestureDelegate()
        let popDelegate = GestureDelegate()
        pagingPan.delegate = pagingDelegate
        interactivePop.delegate = popDelegate

        coordinator.bindPagingPan(pagingPan)
        coordinator.bindInteractivePopGesture(interactivePop)
        coordinator.refresh()
        coordinator.invalidate()
        coordinator.invalidate()

        XCTAssertTrue(pagingPan.delegate === pagingDelegate)
        XCTAssertTrue(interactivePop.delegate === popDelegate)
        XCTAssertNil(coordinator.pagingPanForTesting)
    }

    func testBindingsAndInstalledRelationsDoNotRetainGestures() {
        let recorder = FailureRelationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        var pagingPan: UIPanGestureRecognizer? = UIPanGestureRecognizer()
        var interactivePop: UIGestureRecognizer? = UIScreenEdgePanGestureRecognizer()
        weak let weakPagingPan = pagingPan
        weak let weakInteractivePop = interactivePop

        coordinator.bindPagingPan(pagingPan)
        coordinator.bindInteractivePopGesture(interactivePop)
        coordinator.refresh()
        pagingPan = nil
        interactivePop = nil

        XCTAssertNil(weakPagingPan)
        XCTAssertNil(weakInteractivePop)
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
        XCTAssertFalse(source.contains("UIScrollView"))
        XCTAssertFalse(source.contains("contentOffset"))
    }

    private func makeCoordinator(
        recorder: FailureRelationRecorder
    ) -> AnchorPagerGesturePriorityCoordinator {
        AnchorPagerGesturePriorityCoordinator { gesture, required in
            recorder.record(gesture: gesture, required: required)
        }
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
