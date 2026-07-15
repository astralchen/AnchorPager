import Foundation
import QuartzCore
import XCTest
@testable import AnchorPager

final class AnchorPagerVerticalDecelerationDriverTests: XCTestCase {
    func testModelMatchesMillisecondDecayReferenceValues() throws {
        let sample = try XCTUnwrap(
            AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: 1_000,
                decelerationRate: 0.998,
                fromElapsedTime: 0,
                toElapsedTime: 0.1
            )
        )

        XCTAssertEqual(sample.velocity, 818.567, accuracy: 0.001)
        XCTAssertEqual(sample.delta, 90.626, accuracy: 0.001)
        XCTAssertFalse(sample.isFinished)
    }

    func testModelPreservesSignAndSegmentedIntegrationEqualsWholeInterval() throws {
        let whole = try XCTUnwrap(
            AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: -1_000,
                decelerationRate: 0.998,
                fromElapsedTime: 0,
                toElapsedTime: 0.1
            )
        )
        let first = try XCTUnwrap(
            AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: -1_000,
                decelerationRate: 0.998,
                fromElapsedTime: 0,
                toElapsedTime: 0.04
            )
        )
        let second = try XCTUnwrap(
            AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: -1_000,
                decelerationRate: 0.998,
                fromElapsedTime: 0.04,
                toElapsedTime: 0.1
            )
        )

        XCTAssertLessThan(whole.velocity, 0)
        XCTAssertLessThan(whole.delta, 0)
        XCTAssertEqual(first.delta + second.delta, whole.delta, accuracy: 0.000_1)
        XCTAssertEqual(second.velocity, whole.velocity, accuracy: 0.000_1)
    }

    func testModelFinishesAtEpsilonAndRejectsInvalidInputs() throws {
        let finished = try XCTUnwrap(
            AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: 5,
                decelerationRate: 0.998,
                fromElapsedTime: 0,
                toElapsedTime: 0
            )
        )

        XCTAssertTrue(finished.isFinished)
        XCTAssertNil(
            AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: .infinity,
                decelerationRate: 0.998,
                fromElapsedTime: 0,
                toElapsedTime: 0.1
            )
        )
        XCTAssertNil(
            AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: 1_000,
                decelerationRate: 0,
                fromElapsedTime: 0,
                toElapsedTime: 0.1
            )
        )
        XCTAssertNil(
            AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: 1_000,
                decelerationRate: 1,
                fromElapsedTime: 0,
                toElapsedTime: 0.1
            )
        )
        XCTAssertNil(
            AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: 1_000,
                decelerationRate: 0.998,
                fromElapsedTime: 0.2,
                toElapsedTime: 0.1
            )
        )
        XCTAssertNil(
            AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: 1_000,
                decelerationRate: 0.998,
                fromElapsedTime: 0,
                toElapsedTime: 0.1,
                velocityEpsilon: .nan
            )
        )
    }

    func testSourceKeepsModelIndependentFromUIKitAndDriverFreeOfScrollOwnership() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/AnchorPager/Core/AnchorPagerVerticalDecelerationDriver.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("import UIKit"))
        XCTAssertFalse(source.contains("UIScrollView"))
        XCTAssertFalse(source.contains("UIViewController"))
        XCTAssertFalse(source.contains("pageProvider"))
        XCTAssertFalse(source.contains("Timer("))
        XCTAssertFalse(source.contains("asyncAfter"))
        XCTAssertEqual(
            source.components(separatedBy: "CADisplayLink(target:").count - 1,
            1
        )
    }

    @MainActor
    func testStartReplacementKeepsOnlyLatestRunAndCancelIsIdempotent() throws {
        let harness = DisplayLinkHarness()
        let clock = TestClock(now: 10)
        let driver = makeDriver(harness: harness, clock: clock)
        var samples: [AnchorPagerVerticalDecelerationModel.Sample] = []
        var cancelCount = 0
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        driver.onTick = { samples.append($0) }
        driver.onCancel = { cancelCount += 1 }

        driver.start(
            initialVelocity: 1_000,
            decelerationRate: 0.998,
            elapsedTime: 0
        )
        let firstLink = try XCTUnwrap(harness.links.first)
        XCTAssertTrue(firstLink.wasAdded)

        clock.now = 10.05
        firstLink.fire()
        driver.start(
            initialVelocity: -500,
            decelerationRate: 0.99,
            elapsedTime: 0.2
        )
        let secondLink = try XCTUnwrap(harness.links.last)

        XCTAssertTrue(firstLink.wasInvalidated)
        XCTAssertFalse(secondLink.wasInvalidated)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(samples.count, 1)

        firstLink.fire()
        XCTAssertEqual(samples.count, 1)
        clock.now = 10.1
        secondLink.fire()
        XCTAssertEqual(samples.count, 2)
        XCTAssertLessThan(try XCTUnwrap(samples.last).velocity, 0)

        driver.cancel()
        driver.cancel()

        XCTAssertTrue(secondLink.wasInvalidated)
        XCTAssertEqual(cancelCount, 2)
        XCTAssertEqual(
            events.map(\.event),
            [
                "scroll.deceleration.begin",
                "scroll.deceleration.cancel",
                "scroll.deceleration.begin",
                "scroll.deceleration.cancel",
            ]
        )
    }

    @MainActor
    func testFinishedTickInvalidatesLinkWithoutCancelCallbackOrTickLog() throws {
        let harness = DisplayLinkHarness()
        let clock = TestClock(now: 20)
        let driver = makeDriver(harness: harness, clock: clock)
        var samples: [AnchorPagerVerticalDecelerationModel.Sample] = []
        var cancelCount = 0
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }
        driver.onTick = { samples.append($0) }
        driver.onCancel = { cancelCount += 1 }

        driver.start(
            initialVelocity: 5,
            decelerationRate: 0.998,
            elapsedTime: 0
        )
        let link = try XCTUnwrap(harness.links.first)
        link.fire()

        XCTAssertEqual(samples.count, 1)
        XCTAssertTrue(try XCTUnwrap(samples.first).isFinished)
        XCTAssertTrue(link.wasInvalidated)
        XCTAssertEqual(cancelCount, 0)
        XCTAssertEqual(
            events.map(\.event),
            ["scroll.deceleration.begin", "scroll.deceleration.finish"]
        )
        XCTAssertFalse(events.contains { $0.event.contains("tick") })
    }

    @MainActor
    func testDeinitInvalidatesActiveDisplayLinkWithoutRetainingDriver() throws {
        let harness = DisplayLinkHarness()
        let clock = TestClock(now: 30)
        var driver: AnchorPagerVerticalDecelerationDriver? = makeDriver(
            harness: harness,
            clock: clock
        )
        driver?.start(
            initialVelocity: 1_000,
            decelerationRate: 0.998,
            elapsedTime: 0
        )
        let link = try XCTUnwrap(harness.links.first)
        weak let weakDriver = driver

        driver = nil

        XCTAssertNil(weakDriver)
        XCTAssertTrue(link.wasInvalidated)
    }

    @MainActor
    private func makeDriver(
        harness: DisplayLinkHarness,
        clock: TestClock
    ) -> AnchorPagerVerticalDecelerationDriver {
        AnchorPagerVerticalDecelerationDriver(
            displayLinkFactory: { target, action in
                harness.makeLink(target: target, action: action)
            },
            timeProvider: { clock.now }
        )
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
private final class TestClock {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }
}

@MainActor
private final class DisplayLinkHarness {
    private(set) var links: [TestDisplayLink] = []

    func makeLink(target: Any, action: Selector) -> TestDisplayLink {
        let link = TestDisplayLink(target: target as! NSObject, action: action)
        links.append(link)
        return link
    }
}

@MainActor
private final class TestDisplayLink: AnchorPagerDisplayLinking {
    private weak var target: NSObject?
    private let action: Selector
    private(set) var wasAdded = false
    private(set) var wasInvalidated = false

    init(target: NSObject, action: Selector) {
        self.target = target
        self.action = action
    }

    func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {
        wasAdded = true
    }

    func invalidate() {
        wasInvalidated = true
    }

    func fire() {
        guard !wasInvalidated else { return }
        _ = target?.perform(action)
    }
}
