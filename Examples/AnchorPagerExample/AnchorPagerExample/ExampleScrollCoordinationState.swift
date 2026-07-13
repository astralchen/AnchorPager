import CoreGraphics
import Foundation

struct ExampleScrollCoordinationState: Equatable {
    var page: String
    var collapseProgress: CGFloat
    var childDistance: CGFloat
    var containerSawTopBounce: Bool
    var childSawTopBounce: Bool

    var accessibilityValue: String {
        [
            "page=\(page)",
            "collapse=\(formatted(collapseProgress))",
            "distance=\(formatted(childDistance))",
            "containerBounce=\(containerSawTopBounce ? 1 : 0)",
            "childBounce=\(childSawTopBounce ? 1 : 0)"
        ].joined(separator: ";")
    }

    mutating func resetBounceFlags() {
        containerSawTopBounce = false
        childSawTopBounce = false
    }

    private func formatted(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
