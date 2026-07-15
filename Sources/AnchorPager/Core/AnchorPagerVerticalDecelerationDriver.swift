import Foundation
import QuartzCore

struct AnchorPagerVerticalDecelerationModel {
    struct Sample: Equatable, Sendable {
        let delta: CGFloat
        let velocity: CGFloat
        let isFinished: Bool
    }

    static func sample(
        initialVelocity: CGFloat,
        decelerationRate: CGFloat,
        fromElapsedTime: TimeInterval,
        toElapsedTime: TimeInterval,
        velocityEpsilon: CGFloat = 5
    ) -> Sample? {
        guard initialVelocity.isFinite,
              decelerationRate.isFinite,
              decelerationRate > 0,
              decelerationRate < 1,
              fromElapsedTime.isFinite,
              toElapsedTime.isFinite,
              fromElapsedTime >= 0,
              toElapsedTime >= fromElapsedTime,
              velocityEpsilon.isFinite,
              velocityEpsilon >= 0 else {
            return nil
        }

        let initialVelocity = Double(initialVelocity)
        let decelerationRate = Double(decelerationRate)
        let logarithmicRate = log(decelerationRate)
        let fromFactor = exp(1_000 * fromElapsedTime * logarithmicRate)
        let toFactor = exp(1_000 * toElapsedTime * logarithmicRate)
        let velocity = initialVelocity * toFactor
        let delta = initialVelocity * (fromFactor - toFactor)
            / (-1_000 * logarithmicRate)
        guard velocity.isFinite, delta.isFinite else { return nil }

        return Sample(
            delta: CGFloat(delta),
            velocity: CGFloat(velocity),
            isFinished: abs(velocity) <= Double(velocityEpsilon)
        )
    }
}

@MainActor
protocol AnchorPagerVerticalDecelerationDriving: AnyObject {
    var onTick: ((AnchorPagerVerticalDecelerationModel.Sample) -> Void)? { get set }
    var onCancel: (() -> Void)? { get set }

    func start(
        initialVelocity: CGFloat,
        decelerationRate: CGFloat,
        elapsedTime: TimeInterval
    )
    func cancel()
}

@MainActor
protocol AnchorPagerDisplayLinking: AnyObject {
    func add(to runloop: RunLoop, forMode mode: RunLoop.Mode)
    func invalidate()
}

extension CADisplayLink: AnchorPagerDisplayLinking {}

@MainActor
private final class AnchorPagerVerticalDecelerationDisplayLinkTarget: NSObject {
    weak var driver: AnchorPagerVerticalDecelerationDriver?

    init(driver: AnchorPagerVerticalDecelerationDriver) {
        self.driver = driver
    }

    @objc func displayLinkDidFire() {
        driver?.displayLinkDidFire()
    }
}

@MainActor
final class AnchorPagerVerticalDecelerationDriver: AnchorPagerVerticalDecelerationDriving {
    typealias DisplayLinkFactory = (Any, Selector) -> AnchorPagerDisplayLinking
    typealias TimeProvider = () -> TimeInterval

    var onTick: ((AnchorPagerVerticalDecelerationModel.Sample) -> Void)?
    var onCancel: (() -> Void)?

    private struct RunContext {
        let identifier: Int
        let initialVelocity: CGFloat
        let decelerationRate: CGFloat
        let initialElapsedTime: TimeInterval
        let startTime: TimeInterval
        var previousElapsedTime: TimeInterval
    }

    private enum StopReason {
        case finished
        case cancelled
    }

    private let displayLinkFactory: DisplayLinkFactory
    private let timeProvider: TimeProvider
    private lazy var displayLinkTarget =
        AnchorPagerVerticalDecelerationDisplayLinkTarget(driver: self)
    private var displayLink: AnchorPagerDisplayLinking?
    private var runContext: RunContext?
    private var nextRunIdentifier = 0

    init(
        displayLinkFactory: @escaping DisplayLinkFactory = { target, action in
            CADisplayLink(target: target, selector: action)
        },
        timeProvider: @escaping TimeProvider = CACurrentMediaTime
    ) {
        self.displayLinkFactory = displayLinkFactory
        self.timeProvider = timeProvider
    }

    deinit {
        MainActor.assumeIsolated {
            stopActiveRun(reason: .cancelled, notifiesCancel: false)
        }
    }

    func start(
        initialVelocity: CGFloat,
        decelerationRate: CGFloat,
        elapsedTime: TimeInterval
    ) {
        if runContext != nil {
            stopActiveRun(reason: .cancelled, notifiesCancel: true)
        }

        let startTime = timeProvider()
        guard startTime.isFinite,
              AnchorPagerVerticalDecelerationModel.sample(
                initialVelocity: initialVelocity,
                decelerationRate: decelerationRate,
                fromElapsedTime: elapsedTime,
                toElapsedTime: elapsedTime
              ) != nil else {
            logStop(.cancelled)
            onCancel?()
            return
        }

        nextRunIdentifier &+= 1
        runContext = RunContext(
            identifier: nextRunIdentifier,
            initialVelocity: initialVelocity,
            decelerationRate: decelerationRate,
            initialElapsedTime: elapsedTime,
            startTime: startTime,
            previousElapsedTime: elapsedTime
        )
        let displayLink = displayLinkFactory(
            displayLinkTarget,
            #selector(
                AnchorPagerVerticalDecelerationDisplayLinkTarget.displayLinkDidFire
            )
        )
        self.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
        AnchorPagerLogger.log(
            .debug,
            category: .scroll,
            event: "scroll.deceleration.begin"
        )
    }

    func cancel() {
        guard runContext != nil else { return }
        stopActiveRun(reason: .cancelled, notifiesCancel: true)
    }

    fileprivate func displayLinkDidFire() {
        guard var context = runContext else { return }
        let now = timeProvider()
        let elapsedTime = context.initialElapsedTime + now - context.startTime
        guard let sample = AnchorPagerVerticalDecelerationModel.sample(
            initialVelocity: context.initialVelocity,
            decelerationRate: context.decelerationRate,
            fromElapsedTime: context.previousElapsedTime,
            toElapsedTime: elapsedTime
        ) else {
            stopActiveRun(reason: .cancelled, notifiesCancel: true)
            return
        }

        context.previousElapsedTime = elapsedTime
        runContext = context
        let identifier = context.identifier
        onTick?(sample)
        guard runContext?.identifier == identifier else { return }
        if sample.isFinished {
            stopActiveRun(reason: .finished, notifiesCancel: false)
        }
    }

    private func stopActiveRun(
        reason: StopReason,
        notifiesCancel: Bool
    ) {
        guard runContext != nil || displayLink != nil else { return }
        displayLink?.invalidate()
        displayLink = nil
        runContext = nil
        logStop(reason)
        if notifiesCancel {
            onCancel?()
        }
    }

    private func logStop(_ reason: StopReason) {
        switch reason {
        case .finished:
            AnchorPagerLogger.log(
                .debug,
                category: .scroll,
                event: "scroll.deceleration.finish"
            )
        case .cancelled:
            AnchorPagerLogger.log(
                .debug,
                category: .scroll,
                event: "scroll.deceleration.cancel"
            )
        }
    }
}
