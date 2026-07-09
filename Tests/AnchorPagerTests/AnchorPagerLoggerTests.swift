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
}
