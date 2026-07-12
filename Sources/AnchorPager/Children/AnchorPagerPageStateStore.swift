import UIKit

@MainActor
final class AnchorPagerPageStateStore {
    struct AccessContext {
        var managedInsetTarget: AnchorPagerManagedInsetCoordinator.Target
        var containerIsCollapsed: Bool
    }

    private final class PageState {
        weak var originalViewController: UIViewController?
        weak var actualPageViewController: UIViewController?
        weak var scrollView: UIScrollView?
        weak var fallbackHost: AnchorPagerPageScrollHostViewController?
        var retainedPage: UIViewController?
    }

    private final class GenerationState {
        let identifier: Int
        let pageCount: Int
        var currentIndex: Int
        var keepsAdjacentPagesLoaded: Bool
        var pages: [Int: PageState] = [:]
        var claimedScrollViewIdentifiers: Set<ObjectIdentifier> = []

        init(
            identifier: Int,
            pageCount: Int,
            currentIndex: Int,
            keepsAdjacentPagesLoaded: Bool
        ) {
            self.identifier = identifier
            self.pageCount = pageCount
            self.currentIndex = currentIndex
            self.keepsAdjacentPagesLoaded = keepsAdjacentPagesLoaded
        }
    }

    private let managedInsetCoordinator: AnchorPagerManagedInsetCoordinator
    private var committedGeneration: GenerationState?
    private var pendingGeneration: GenerationState?

    init(managedInsetCoordinator: AnchorPagerManagedInsetCoordinator) {
        self.managedInsetCoordinator = managedInsetCoordinator
    }

    func beginReload(
        generation: Int,
        pageCount: Int,
        selectedIndex: Int,
        keepsAdjacentPagesLoaded: Bool
    ) {
        let count = Swift.max(0, pageCount)
        let currentIndex = (0..<count).contains(selectedIndex) ? selectedIndex : 0
        pendingGeneration = GenerationState(
            identifier: generation,
            pageCount: count,
            currentIndex: currentIndex,
            keepsAdjacentPagesLoaded: keepsAdjacentPagesLoaded
        )
        AnchorPagerLogger.log(.info, category: .children, event: "children.page.generation.begin")
    }

    func pageViewController(
        at index: Int,
        context: AccessContext,
        originalProvider: () -> UIViewController?
    ) -> UIViewController? {
        guard let generation = activeGeneration,
              (0..<generation.pageCount).contains(index) else {
            return nil
        }

        let state = generation.pages[index] ?? PageState()
        generation.pages[index] = state
        if let livePage = state.actualPageViewController {
            applyManagedInsets(context.managedInsetTarget, to: state)
            AnchorPagerLogger.log(.debug, category: .children, event: "children.page.reuse")
            return livePage
        }

        let originalViewController: UIViewController
        if let providedViewController = originalProvider() {
            originalViewController = providedViewController
        } else {
            originalViewController = UIViewController()
            AnchorPagerLogger.log(
                .error,
                category: .children,
                event: "children.page.dataSourceMissing"
            )
        }
        originalViewController.loadViewIfNeeded()
        let actualPageViewController: UIViewController
        let scrollView: UIScrollView
        let resolvedScrollView = originalViewController.anchorPagerScrollView
        if let resolvedScrollView,
           generation.claimedScrollViewIdentifiers
            .insert(ObjectIdentifier(resolvedScrollView)).inserted {
            actualPageViewController = originalViewController
            scrollView = resolvedScrollView
        } else if resolvedScrollView != nil {
            AnchorPagerAssertions.failure("AnchorPager pages must not share a scroll view.")
            AnchorPagerLogger.log(
                .debug,
                category: .inset,
                event: "inset.targetCollision"
            )
            if let defaultScrollView = originalViewController.anchorPagerDefaultScrollView,
               generation.claimedScrollViewIdentifiers
                .insert(ObjectIdentifier(defaultScrollView)).inserted {
                actualPageViewController = originalViewController
                scrollView = defaultScrollView
            } else {
                let fallbackHost = makeFallbackHost(
                    for: originalViewController,
                    state: state,
                    generation: generation
                )
                actualPageViewController = fallbackHost
                scrollView = fallbackHost.scrollView
            }
        } else {
            let fallbackHost = makeFallbackHost(
                for: originalViewController,
                state: state,
                generation: generation
            )
            actualPageViewController = fallbackHost
            scrollView = fallbackHost.scrollView
        }

        state.originalViewController = originalViewController
        state.actualPageViewController = actualPageViewController
        state.scrollView = scrollView
        if index == generation.currentIndex {
            state.retainedPage = actualPageViewController
        }
        applyManagedInsets(context.managedInsetTarget, to: state)
        AnchorPagerLogger.log(.info, category: .children, event: "children.page.load")
        return actualPageViewController
    }

    func scrollView(at index: Int) -> UIScrollView? {
        activeGeneration?.pages[index]?.scrollView
    }

    func livePageViewController(at index: Int) -> UIViewController? {
        activeGeneration?.pages[index]?.actualPageViewController
    }

    func commitReload(generation: Int) {
        guard pendingGeneration?.identifier == generation else { return }
        committedGeneration = pendingGeneration
        pendingGeneration = nil
        AnchorPagerLogger.log(.info, category: .children, event: "children.page.generation.commit")
    }

    func releaseAll() {
        let scrollViews = [pendingGeneration, committedGeneration]
            .compactMap { $0 }
            .flatMap { $0.pages.values.compactMap(\.scrollView) }
        scrollViews.forEach(managedInsetCoordinator.release)
        pendingGeneration = nil
        committedGeneration = nil
    }

    private var activeGeneration: GenerationState? {
        pendingGeneration ?? committedGeneration
    }

    private func applyManagedInsets(
        _ target: AnchorPagerManagedInsetCoordinator.Target,
        to state: PageState
    ) {
        guard let scrollView = state.scrollView else { return }
        state.fallbackHost?.setManagedContentInsets(target.content)
        managedInsetCoordinator.apply(target, to: scrollView)
    }

    private func makeFallbackHost(
        for originalViewController: UIViewController,
        state: PageState,
        generation: GenerationState
    ) -> AnchorPagerPageScrollHostViewController {
        let fallbackHost = AnchorPagerPageScrollHostViewController(
            contentViewController: originalViewController
        )
        fallbackHost.loadViewIfNeeded()
        generation.claimedScrollViewIdentifiers.insert(ObjectIdentifier(fallbackHost.scrollView))
        state.fallbackHost = fallbackHost
        return fallbackHost
    }
}
