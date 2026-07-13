import CoreGraphics
import Foundation

struct ExampleScrollCoordinationState: Equatable {
    var page: String
    var hasScrollTarget: Bool
    var mode: String
    var collapseProgress: CGFloat
    var childDistance: CGFloat
    var containerPresentation: CGFloat
    var maximumContainerTopPresentation: CGFloat
    var maximumContainerBottomPresentation: CGFloat
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
            "distance=\(formatted(childDistance))",
            "containerCurrent=\(formatted(containerPresentation))",
            "containerTopMax=\(formatted(maximumContainerTopPresentation))",
            "containerBottomMax=\(formatted(maximumContainerBottomPresentation))",
            "childTopCurrent=\(formatted(childTopOverflow))",
            "childTopMax=\(formatted(maximumChildTopOverflow))",
            "childBottomCurrent=\(formatted(childBottomOverflow))",
            "childBottomMax=\(formatted(maximumChildBottomOverflow))"
        ].joined(separator: ";")
    }

    mutating func resetPresentationMetrics() {
        containerPresentation = 0
        maximumContainerTopPresentation = 0
        maximumContainerBottomPresentation = 0
        childTopOverflow = 0
        maximumChildTopOverflow = 0
        childBottomOverflow = 0
        maximumChildBottomOverflow = 0
    }

    private func formatted(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
