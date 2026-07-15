import CoreGraphics
import Foundation

struct ExampleScrollCoordinationState: Equatable {
    var page: String
    var hasScrollTarget: Bool
    var mode: String
    var collapseProgress: CGFloat
    var containerTopInset: CGFloat
    var headerHeight: CGFloat
    var maximumHeaderHeightDelta: CGFloat
    var headerCollapseTranslation: CGFloat
    var childDistance: CGFloat
    var containerPresentation: CGFloat
    var maximumContainerTopPresentation: CGFloat
    var maximumContainerBottomPresentation: CGFloat
    var barPresentation: CGFloat
    var maximumBarPresentation: CGFloat
    var childTopOverflow: CGFloat
    var maximumChildTopOverflow: CGFloat
    var childBottomOverflow: CGFloat
    var maximumChildBottomOverflow: CGFloat
    var headerContentTopDistance: CGFloat = 0
    var maximumHeaderContentTopDistanceDelta: CGFloat = 0
    var canonicalTotal: CGFloat = 0
    var maximumDirectionReversal: CGFloat = 0
    var maximumStableInvariantViolation: CGFloat = 0
    var didHandoffContainerToChild = false
    var didHandoffChildToContainer = false
    var momentumSampleCount = 0
    var momentumPreviousCanonicalTotal: CGFloat?
    var momentumPreviousDirection = 0
    var momentumPreviousContainerDistance: CGFloat?
    var momentumPreviousChildDistance: CGFloat?

    var accessibilityValue: String {
        [
            "page=\(page)",
            "hasScrollTarget=\(hasScrollTarget ? 1 : 0)",
            "mode=\(mode)",
            "collapse=\(formatted(collapseProgress))",
            "containerTopInset=\(formatted(containerTopInset))",
            "headerHeight=\(formatted(headerHeight))",
            "headerHeightDeltaMax=\(formatted(maximumHeaderHeightDelta))",
            "headerCollapse=\(formatted(headerCollapseTranslation))",
            "distance=\(formatted(childDistance))",
            "containerCurrent=\(formatted(containerPresentation))",
            "containerTopMax=\(formatted(maximumContainerTopPresentation))",
            "containerBottomMax=\(formatted(maximumContainerBottomPresentation))",
            "barCurrent=\(formatted(barPresentation))",
            "barMax=\(formatted(maximumBarPresentation))",
            "childTopCurrent=\(formatted(childTopOverflow))",
            "childTopMax=\(formatted(maximumChildTopOverflow))",
            "childBottomCurrent=\(formatted(childBottomOverflow))",
            "childBottomMax=\(formatted(maximumChildBottomOverflow))",
            "headerContentTop=\(formatted(headerContentTopDistance))",
            "headerContentTopDeltaMax=\(formatted(maximumHeaderContentTopDistanceDelta))",
            "canonical=\(formatted(canonicalTotal))",
            "reversalMax=\(formatted(maximumDirectionReversal))",
            "invariantMax=\(formatted(maximumStableInvariantViolation))",
            "containerToChild=\(didHandoffContainerToChild ? 1 : 0)",
            "childToContainer=\(didHandoffChildToContainer ? 1 : 0)",
            "samples=\(momentumSampleCount)"
        ].joined(separator: ";")
    }

    mutating func resetPresentationMetrics() {
        maximumHeaderHeightDelta = 0
        headerCollapseTranslation = 0
        containerPresentation = 0
        maximumContainerTopPresentation = 0
        maximumContainerBottomPresentation = 0
        barPresentation = 0
        maximumBarPresentation = 0
        childTopOverflow = 0
        maximumChildTopOverflow = 0
        childBottomOverflow = 0
        maximumChildBottomOverflow = 0
        maximumHeaderContentTopDistanceDelta = 0
        canonicalTotal = 0
        maximumDirectionReversal = 0
        maximumStableInvariantViolation = 0
        didHandoffContainerToChild = false
        didHandoffChildToContainer = false
        momentumSampleCount = 0
        momentumPreviousCanonicalTotal = nil
        momentumPreviousDirection = 0
        momentumPreviousContainerDistance = nil
        momentumPreviousChildDistance = nil
    }

    mutating func recordHeaderGeometry(
        currentHeight: CGFloat,
        baselineHeight: CGFloat,
        currentMinY: CGFloat,
        baselineMinY: CGFloat
    ) {
        headerHeight = currentHeight
        maximumHeaderHeightDelta = max(
            maximumHeaderHeightDelta,
            abs(currentHeight - baselineHeight)
        )
        headerCollapseTranslation = max(0, baselineMinY - currentMinY)
    }

    mutating func recordHeaderContentTopDistance(
        current: CGFloat,
        baseline: CGFloat
    ) {
        headerContentTopDistance = current
        maximumHeaderContentTopDistanceDelta = max(
            maximumHeaderContentTopDistanceDelta,
            abs(current - baseline)
        )
    }

    mutating func recordMomentumSample(
        containerDistance: CGFloat,
        childDistance: CGFloat,
        collapsedDistance: CGFloat
    ) {
        let container = max(0, containerDistance)
        let child = max(0, childDistance)
        let collapsed = max(0, collapsedDistance)
        let nextCanonicalTotal = container + child

        if let previousTotal = momentumPreviousCanonicalTotal {
            let delta = nextCanonicalTotal - previousTotal
            let direction = delta > 0.5 ? 1 : (delta < -0.5 ? -1 : 0)
            if direction != 0,
               momentumPreviousDirection != 0,
               direction != momentumPreviousDirection {
                maximumDirectionReversal = max(
                    maximumDirectionReversal,
                    abs(delta)
                )
            }
            if direction != 0 {
                momentumPreviousDirection = direction
            }
        }

        if child > 0.5 {
            maximumStableInvariantViolation = max(
                maximumStableInvariantViolation,
                abs(container - collapsed)
            )
        }
        if let previousContainer = momentumPreviousContainerDistance,
           let previousChild = momentumPreviousChildDistance,
           previousChild <= 0.5,
           child > 0.5,
           previousContainer <= collapsed + 0.5,
           container >= collapsed - 0.5 {
            didHandoffContainerToChild = true
        }
        if let previousContainer = momentumPreviousContainerDistance,
           let previousChild = momentumPreviousChildDistance,
           previousChild > 0.5,
           child <= 0.5,
           previousContainer >= collapsed - 0.5,
           container <= collapsed + 0.5 {
            didHandoffChildToContainer = true
        }

        canonicalTotal = nextCanonicalTotal
        momentumSampleCount += 1
        momentumPreviousCanonicalTotal = nextCanonicalTotal
        momentumPreviousContainerDistance = container
        momentumPreviousChildDistance = child
    }

    private func formatted(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}

struct ExampleSelectionTrace: Equatable {
    private(set) var indexes: [Int] = []

    var serializedValue: String {
        indexes.map(String.init).joined(separator: ",")
    }

    mutating func record(index: Int) {
        indexes.append(index)
    }

    mutating func reset() {
        indexes.removeAll(keepingCapacity: true)
    }
}
