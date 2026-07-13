import UIKit

@MainActor
final class AnchorPagerChildScrollBinding: NSObject {
    let token: Int

    private weak var scrollView: UIScrollView?
    private let originalBounces: Bool
    private var contentOffsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    private var onContentOffsetChanged: ((CGPoint) -> Void)?
    private var onContentSizeChanged: ((CGSize) -> Void)?
    private var onPan: ((UIGestureRecognizer.State, CGFloat) -> Void)?
    private var isValid = true

    init(
        scrollView: UIScrollView,
        token: Int,
        onContentOffsetChanged: @escaping (CGPoint) -> Void,
        onContentSizeChanged: @escaping (CGSize) -> Void,
        onPan: @escaping (UIGestureRecognizer.State, CGFloat) -> Void
    ) {
        self.scrollView = scrollView
        self.originalBounces = scrollView.bounces
        self.token = token
        self.onContentOffsetChanged = onContentOffsetChanged
        self.onContentSizeChanged = onContentSizeChanged
        self.onPan = onPan
        super.init()

        contentOffsetObservation = scrollView.observe(
            \.contentOffset,
            options: [.new]
        ) { [weak self] _, change in
            guard let self, let value = change.newValue else { return }
            MainActor.assumeIsolated {
                guard self.isValid else { return }
                self.onContentOffsetChanged?(value)
            }
        }
        contentSizeObservation = scrollView.observe(
            \.contentSize,
            options: [.new]
        ) { [weak self] _, change in
            guard let self, let value = change.newValue else { return }
            MainActor.assumeIsolated {
                guard self.isValid else { return }
                self.onContentSizeChanged?(value)
            }
        }
        scrollView.panGestureRecognizer.addTarget(
            self,
            action: #selector(handlePan(_:))
        )
    }

    func invalidate() {
        guard isValid else { return }
        isValid = false

        if let scrollView {
            scrollView.bounces = originalBounces
            scrollView.panGestureRecognizer.removeTarget(
                self,
                action: #selector(handlePan(_:))
            )
        }
        contentOffsetObservation?.invalidate()
        contentSizeObservation?.invalidate()
        contentOffsetObservation = nil
        contentSizeObservation = nil
        onContentOffsetChanged = nil
        onContentSizeChanged = nil
        onPan = nil

        AnchorPagerLogger.log(
            .debug,
            category: .resource,
            event: "resource.scrollObservation.release"
        )
    }

    func setAllowsNativeBounce(_ allowsNativeBounce: Bool) {
        guard isValid, let scrollView else { return }
        scrollView.bounces = allowsNativeBounce && originalBounces
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard isValid else { return }
        onPan?(pan.state, pan.translation(in: pan.view).y)
    }
}
