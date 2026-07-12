import UIKit

@MainActor
final class AnchorPagerManagedInsetCoordinator {
    struct Target: Equatable {
        var content: UIEdgeInsets
        var indicators: UIEdgeInsets
    }

    @MainActor
    private final class Record {
        weak var scrollView: UIScrollView?
        let originalAdjustmentBehavior: UIScrollView.ContentInsetAdjustmentBehavior
        let originalAutomaticallyAdjustsScrollIndicatorInsets: Bool
        var lastManagedContent: UIEdgeInsets = .zero
        var lastManagedIndicators: UIEdgeInsets = .zero

        init(scrollView: UIScrollView) {
            self.scrollView = scrollView
            self.originalAdjustmentBehavior = scrollView.contentInsetAdjustmentBehavior
            self.originalAutomaticallyAdjustsScrollIndicatorInsets =
                scrollView.automaticallyAdjustsScrollIndicatorInsets
        }
    }

    private var records: [ObjectIdentifier: Record] = [:]

    func apply(
        _ target: Target,
        to scrollView: UIScrollView,
        logsChanges: Bool = true
    ) {
        removeReleasedRecords()

        let identifier = ObjectIdentifier(scrollView)
        let existingRecord = records[identifier]
        let record = existingRecord ?? Record(scrollView: scrollView)
        let target = sanitized(target)

        guard record.lastManagedContent != target.content
                || record.lastManagedIndicators != target.indicators
                || scrollView.contentInsetAdjustmentBehavior != .never
                || scrollView.automaticallyAdjustsScrollIndicatorInsets else {
            if logsChanges {
                AnchorPagerLogger.log(.debug, category: .inset, event: "inset.ownership.skip")
            }
            return
        }

        let distanceFromTop = childDistanceFromTop(in: scrollView)
        let externalContent = scrollView.contentInset.subtracting(record.lastManagedContent)
        let externalIndicators = scrollView.verticalScrollIndicatorInsets
            .subtracting(record.lastManagedIndicators)
        let newContent = externalContent.adding(target.content)
        let newIndicators = externalIndicators.adding(target.indicators)

        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        scrollView.contentInset = newContent
        scrollView.verticalScrollIndicatorInsets = newIndicators
        scrollView.contentOffset = CGPoint(
            x: scrollView.contentOffset.x,
            y: -newContent.top + distanceFromTop
        )

        record.lastManagedContent = target.content
        record.lastManagedIndicators = target.indicators
        records[identifier] = record
        if logsChanges {
            AnchorPagerLogger.log(
                .debug,
                category: .inset,
                event: existingRecord == nil ? "inset.ownership.begin" : "inset.ownership.update"
            )
        }
    }

    func release(_ scrollView: UIScrollView) {
        let identifier = ObjectIdentifier(scrollView)
        guard let record = records.removeValue(forKey: identifier) else { return }

        let distanceFromTop = childDistanceFromTop(in: scrollView)
        let restoredContent = scrollView.contentInset.subtracting(record.lastManagedContent)
        let restoredIndicators = scrollView.verticalScrollIndicatorInsets
            .subtracting(record.lastManagedIndicators)

        scrollView.contentInset = restoredContent
        scrollView.verticalScrollIndicatorInsets = restoredIndicators
        scrollView.contentOffset = CGPoint(
            x: scrollView.contentOffset.x,
            y: -restoredContent.top + distanceFromTop
        )
        scrollView.contentInsetAdjustmentBehavior = record.originalAdjustmentBehavior
        scrollView.automaticallyAdjustsScrollIndicatorInsets =
            record.originalAutomaticallyAdjustsScrollIndicatorInsets
        AnchorPagerLogger.log(.debug, category: .inset, event: "inset.ownership.end")
    }

    func releaseAll() {
        let scrollViews = records.values.compactMap(\.scrollView)
        for scrollView in scrollViews {
            release(scrollView)
        }
        removeReleasedRecords()
    }

    private func childDistanceFromTop(in scrollView: UIScrollView) -> CGFloat {
        Swift.max(0, scrollView.contentOffset.y + scrollView.contentInset.top)
    }

    private func sanitized(_ target: Target) -> Target {
        Target(
            content: target.content.sanitizedManagedInset,
            indicators: target.indicators.sanitizedManagedInset
        )
    }

    private func removeReleasedRecords() {
        records = records.filter { $0.value.scrollView != nil }
    }
}

private extension UIEdgeInsets {
    func adding(_ other: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: top + other.top,
            left: left + other.left,
            bottom: bottom + other.bottom,
            right: right + other.right
        )
    }

    func subtracting(_ other: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: top - other.top,
            left: left - other.left,
            bottom: bottom - other.bottom,
            right: right - other.right
        )
    }

    var sanitizedManagedInset: UIEdgeInsets {
        UIEdgeInsets(
            top: top.nonNegativeFinite,
            left: left.nonNegativeFinite,
            bottom: bottom.nonNegativeFinite,
            right: right.nonNegativeFinite
        )
    }
}

private extension CGFloat {
    var nonNegativeFinite: CGFloat {
        guard isFinite else { return 0 }
        return Swift.max(0, self)
    }
}
