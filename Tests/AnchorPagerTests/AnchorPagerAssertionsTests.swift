import XCTest
@testable import AnchorPager

final class AnchorPagerAssertionsTests: XCTestCase {
    func testAssertionsTypeIsNotMainActorIsolated() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assertionsSourceURL = packageRootURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("AnchorPager")
            .appendingPathComponent("Core")
            .appendingPathComponent("AnchorPagerAssertions.swift")
        let source = try String(contentsOf: assertionsSourceURL, encoding: .utf8)
        let normalizedSource = source
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        XCTAssertFalse(normalizedSource.contains("@MainActor enum AnchorPagerAssertions"))
        XCTAssertFalse(normalizedSource.contains("nonisolated(unsafe)"))
    }

    func testFailureCanBeCalledFromBackgroundQueueWhenAssertionsAreDisabled() async {
        let completed = expectation(description: "background assertion completed")

        DispatchQueue.global(qos: .utility).async {
            AnchorPagerAssertions.$isEnabled.withValue(false) {
                AnchorPagerAssertions.failure("disabled assertion should not fire")
            }
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 2)
    }
}
