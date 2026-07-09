import XCTest
@testable import AnchorPager

final class AnchorPagerLoggerTests: XCTestCase {
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
