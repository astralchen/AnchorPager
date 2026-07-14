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
            "childBottomMax=\(formatted(maximumChildBottomOverflow))"
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

    private func formatted(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
