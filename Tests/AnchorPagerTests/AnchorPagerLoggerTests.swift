import UIKit
import XCTest
@testable import AnchorPager

final class AnchorPagerLoggerTests: XCTestCase {
    func testLoggerTypeIsNotMainActorIsolated() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let loggerSourceURL = packageRootURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("AnchorPager")
            .appendingPathComponent("Logging")
            .appendingPathComponent("AnchorPagerLogger.swift")
        let source = try String(contentsOf: loggerSourceURL, encoding: .utf8)
        let normalizedSource = source
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        XCTAssertFalse(normalizedSource.contains("@MainActor enum AnchorPagerLogger"))
    }

    func testLogCanBeCalledFromBackgroundQueueWithoutMainActorHop() async {
        let completed = expectation(description: "background log completed")

        DispatchQueue.global(qos: .utility).async {
            AnchorPagerLogger.log(.info, category: .resource, event: "logger.background")
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 2)
    }

    @MainActor
    func testBackgroundLogDeliversSinkEventOnMainActor() async {
        let received = expectation(description: "background sink event received")
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { event in
            XCTAssertTrue(Thread.isMainThread)
            events.append(event)
            received.fulfill()
        }
        defer { AnchorPagerLogger.sink = nil }

        DispatchQueue.global(qos: .utility).async {
            AnchorPagerLogger.log(.info, category: .resource, event: "logger.backgroundSink")
        }

        await fulfillment(of: [received], timeout: 2)

        XCTAssertEqual(
            events,
            [
                AnchorPagerLogger.Event(
                    category: .resource,
                    level: .info,
                    event: "logger.backgroundSink"
                )
            ]
        )
    }

    @MainActor
    func testCategoriesCoverRequiredDiagnosticsAreas() {
        let categories = Set(AnchorPagerLogger.Category.allCases.map(\.rawValue))

        XCTAssertEqual(
            categories,
            [
                "lifecycle",
                "layout",
                "header",
                "paging",
                "children",
                "scroll",
                "inset",
                "overscroll",
                "gesture",
                "accessibility",
                "resource"
            ]
        )
    }

    @MainActor
    func testInjectedSinkReceivesCategoryLevelAndEventName() {
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { event in
            events.append(event)
        }
        defer { AnchorPagerLogger.sink = nil }

        AnchorPagerLogger.log(.info, category: .lifecycle, event: "reloadData.begin")

        XCTAssertEqual(
            events,
            [
                AnchorPagerLogger.Event(
                    category: .lifecycle,
                    level: .info,
                    event: "reloadData.begin"
                )
            ]
        )
    }

    @MainActor
    func testSinkCanCaptureMultipleLevelsWithoutConsoleInspection() {
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { event in
            events.append(event)
        }
        defer { AnchorPagerLogger.sink = nil }

        AnchorPagerLogger.log(.debug, category: .layout, event: "layout.measured")
        AnchorPagerLogger.log(.error, category: .resource, event: "resource.release_failed")

        XCTAssertEqual(events.map(\.level), [.debug, .error])
        XCTAssertEqual(events.map(\.category), [.layout, .resource])
        XCTAssertEqual(events.map(\.event), ["layout.measured", "resource.release_failed"])
    }

    @MainActor
    func testInteractionCoordinatorLogsDoNotContainRuntimeIdentifier() {
        let coordinator = AnchorPagerInteractionCoordinator()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        XCTAssertTrue(coordinator.begin(.programmaticPaging(identifier: 9_876)))
        XCTAssertTrue(coordinator.finish(.programmaticPaging(identifier: 9_876)))

        XCTAssertEqual(events.map(\.event), [
            "interaction.state.begin",
            "interaction.state.finish",
        ])
        XCTAssertFalse(events.contains { $0.event.contains("9876") })
        XCTAssertTrue(events.allSatisfy { $0.category == .gesture })
    }

    @MainActor
    func testInteractivePagingLogsUseFixedPagingEventsWithoutPageMetadata() {
        let adapter = AnchorPagerPagingAdapter()
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        adapter.setInteractiveHorizontalPagingEnabled(false)
        adapter.setInteractiveHorizontalPagingEnabled(true)

        XCTAssertEqual(
            events.map(\.event),
            ["paging.interactivePaging.disabled", "paging.interactivePaging.enabled"]
        )
        XCTAssertTrue(events.allSatisfy { $0.category == .paging })
    }

    @MainActor
    func testHorizontalRouteDecisionLogsContainNoGeometryOrHierarchyPayload() {
        let paging = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let business = UIScrollView(frame: paging.bounds)
        business.contentSize = CGSize(width: 900, height: 700)
        paging.addSubview(business)
        var velocity = CGPoint(x: -400, y: 0)
        let gate = AnchorPagerHorizontalPagingRouteGate(
            pagingScrollView: paging,
            pagingPan: paging.panGestureRecognizer,
            hitTest: { _, _ in business },
            velocity: { _, _ in velocity }
        )
        paging.addGestureRecognizer(gate)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        business.contentOffset.x = 100
        XCTAssertTrue(gate.gestureRecognizerShouldBegin(gate))
        business.contentOffset.x = 510
        XCTAssertFalse(gate.gestureRecognizerShouldBegin(gate))
        velocity = CGPoint(x: 0, y: 400)
        XCTAssertFalse(gate.gestureRecognizerShouldBegin(gate))

        XCTAssertEqual(
            events,
            [
                AnchorPagerLogger.Event(
                    category: .gesture,
                    level: .debug,
                    event: "gesture.horizontalRoute.content"
                ),
                AnchorPagerLogger.Event(
                    category: .gesture,
                    level: .debug,
                    event: "gesture.horizontalRoute.pagingBoundary"
                ),
                AnchorPagerLogger.Event(
                    category: .gesture,
                    level: .debug,
                    event: "gesture.horizontalRoute.noCandidate"
                ),
            ]
        )
    }

    func testVerticalDecelerationDriverUsesOnlyFixedLifecycleEvents() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRootURL.appendingPathComponent(
                "Sources/AnchorPager/Core/AnchorPagerVerticalDecelerationDriver.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("scroll.deceleration.begin"))
        XCTAssertTrue(source.contains("scroll.deceleration.finish"))
        XCTAssertTrue(source.contains("scroll.deceleration.cancel"))
        XCTAssertFalse(source.contains("scroll.deceleration.tick"))
        XCTAssertFalse(source.contains("\\(initialVelocity)"))
        XCTAssertFalse(source.contains("\\(decelerationRate)"))
    }
}
