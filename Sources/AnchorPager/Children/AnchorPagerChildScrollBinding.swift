import UIKit

@MainActor
final class AnchorPagerChildScrollBinding: NSObject {
    struct PanSample: Equatable {
        let state: UIGestureRecognizer.State
        let translationY: CGFloat
        let velocityY: CGFloat
    }

    typealias PanSampleProvider = (UIPanGestureRecognizer) -> PanSample

    let token: Int

    private weak var scrollView: UIScrollView?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    private var onContentOffsetChanged: ((CGPoint) -> Void)?
    private var onContentSizeChanged: ((CGSize) -> Void)?
    private var onPan: ((UIGestureRecognizer.State, CGFloat, CGFloat) -> Void)?
    private let panSampleProvider: PanSampleProvider
    private var isValid = true

    init(
        scrollView: UIScrollView,
        token: Int,
        onContentOffsetChanged: @escaping (CGPoint) -> Void,
        onContentSizeChanged: @escaping (CGSize) -> Void,
        onPan: @escaping (UIGestureRecognizer.State, CGFloat, CGFloat) -> Void,
        panSampleProvider: @escaping PanSampleProvider = { pan in
            PanSample(
                state: pan.state,
                translationY: pan.translation(in: pan.view).y,
                velocityY: pan.velocity(in: pan.view).y
            )
        }
    ) {
        self.scrollView = scrollView
        self.token = token
        self.onContentOffsetChanged = onContentOffsetChanged
        self.onContentSizeChanged = onContentSizeChanged
        self.onPan = onPan
        self.panSampleProvider = panSampleProvider
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

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard isValid else { return }
        let sample = panSampleProvider(pan)
        onPan?(sample.state, sample.translationY, sample.velocityY)
    }

    func handlePanForTesting(_ pan: UIPanGestureRecognizer) {
        handlePan(pan)
    }
}
