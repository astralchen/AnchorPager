import XCTest
@testable import AnchorPager

@MainActor
final class AnchorPagerChildScrollBindingTests: XCTestCase {
    func testBindingPreservesBusinessScrollAndPanDelegates() {
        let scrollView = UIScrollView()
        let scrollDelegate = RecordingScrollDelegate()
        scrollView.delegate = scrollDelegate
        let originalPanDelegate = scrollView.panGestureRecognizer.delegate

        let binding = makeBinding(scrollView: scrollView)
        binding.invalidate()

        XCTAssertTrue(scrollView.delegate === scrollDelegate)
        XCTAssertTrue(scrollView.panGestureRecognizer.delegate === originalPanDelegate)
    }

    func testBindingReportsOffsetAndContentSizeWithoutDelegateWrites() {
        let scrollView = UIScrollView()
        var offsets: [CGPoint] = []
        var sizes: [CGSize] = []
        let binding = AnchorPagerChildScrollBinding(
            scrollView: scrollView,
            token: 7,
            onContentOffsetChanged: { offsets.append($0) },
            onContentSizeChanged: { sizes.append($0) },
            onPan: { _, _ in }
        )

        scrollView.contentOffset = CGPoint(x: 0, y: 20)
        scrollView.contentSize = CGSize(width: 320, height: 900)

        XCTAssertEqual(offsets.last?.y, 20)
        XCTAssertEqual(sizes.last?.height, 900)
        binding.invalidate()
    }

    func testInvalidatedBindingIgnoresLaterChanges() {
        let scrollView = UIScrollView()
        var callbackCount = 0
        let binding = AnchorPagerChildScrollBinding(
            scrollView: scrollView,
            token: 2,
            onContentOffsetChanged: { _ in callbackCount += 1 },
            onContentSizeChanged: { _ in callbackCount += 1 },
            onPan: { _, _ in callbackCount += 1 }
        )
        binding.invalidate()

        scrollView.contentOffset.y = 30
        scrollView.contentSize.height = 800

        XCTAssertEqual(callbackCount, 0)
    }

    func testInvalidateLogsResourceReleaseOnlyOnce() {
        let scrollView = UIScrollView()
        let binding = makeBinding(scrollView: scrollView)
        var events: [AnchorPagerLogger.Event] = []
        AnchorPagerLogger.sink = { events.append($0) }
        defer { AnchorPagerLogger.sink = nil }

        binding.invalidate()
        binding.invalidate()

        XCTAssertEqual(
            events.filter { $0.event == "resource.scrollObservation.release" }.count,
            1
        )
    }

    func testBindingSourceNeverAssignsOrStoresBusinessDelegates() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/AnchorPager/Children/AnchorPagerChildScrollBinding.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let normalized = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        XCTAssertFalse(normalized.contains("scrollView.delegate ="))
        XCTAssertFalse(normalized.contains("panGestureRecognizer.delegate ="))
        XCTAssertFalse(normalized.contains("originalScrollDelegate"))
        XCTAssertFalse(normalized.contains("savedScrollDelegate"))
    }

    private func makeBinding(scrollView: UIScrollView) -> AnchorPagerChildScrollBinding {
        AnchorPagerChildScrollBinding(
            scrollView: scrollView,
            token: 1,
            onContentOffsetChanged: { _ in },
            onContentSizeChanged: { _ in },
            onPan: { _, _ in }
        )
    }
}

@MainActor
private final class RecordingScrollDelegate: NSObject, UIScrollViewDelegate {}
