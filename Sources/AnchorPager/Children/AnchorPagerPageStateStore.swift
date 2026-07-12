import UIKit

@MainActor
final class AnchorPagerPageStateStore {
    enum RetentionReason: Hashable {
        case current
        case transitionSource
        case transitionTarget
        case configuredAdjacent
    }

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
        var retentionReasons: Set<RetentionReason> = []
        var childDistanceFromTop: CGFloat = 0
        var claimedScrollViewIdentifier: ObjectIdentifier?
        var originalViewControllerIdentifier: ObjectIdentifier?
        var hasLoadedBefore = false
    }

    private final class GenerationState {
        let identifier: Int
        let pageCount: Int
        var currentIndex: Int
        var keepsAdjacentPagesLoaded: Bool
        var pages: [Int: PageState] = [:]
        var claimedScrollViewIdentifiers: Set<ObjectIdentifier> = []
        var originalControllerIndexes: [ObjectIdentifier: Int] = [:]
        var migratedPreviousDistances: [ObjectIdentifier: CGFloat] = [:]
        var transitionSourceIndex: Int?
        var transitionTargetIndex: Int?

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
    private(set) var lastManagedUpdateCount = 0

    var committedGenerationIdentifier: Int? {
        committedGeneration?.identifier
    }

    var pendingGenerationIdentifier: Int? {
        pendingGeneration?.identifier
    }

    init(managedInsetCoordinator: AnchorPagerManagedInsetCoordinator) {
        self.managedInsetCoordinator = managedInsetCoordinator
    }

    func beginReload(
        generation: Int,
        pageCount: Int,
        selectedIndex: Int,
        keepsAdjacentPagesLoaded: Bool
    ) {
        if let pendingGeneration {
            restoreMigratedDistances(in: pendingGeneration)
            let committedStateIdentifiers = Set(
                committedGeneration?.pages.values.map(ObjectIdentifier.init) ?? []
            )
            release(pendingGeneration, preserving: committedStateIdentifiers)
            if let committedGeneration {
                reconcileRetention(in: committedGeneration)
            }
            AnchorPagerLogger.log(
                .debug,
                category: .children,
                event: "children.page.generation.cancel"
            )
        }
        if pageCount < 0 {
            AnchorPagerLogger.log(
                .error,
                category: .children,
                event: "children.page.invalidCount"
            )
        }
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

        let existingState = generation.pages[index]
        if let livePage = existingState?.actualPageViewController {
            guard let existingState else { return nil }
            applyManagedInsets(context.managedInsetTarget, to: existingState)
            AnchorPagerLogger.log(.debug, category: .children, event: "children.page.reuse")
            return livePage
        }
        if let existingState,
           existingState.originalViewController == nil,
           let originalIdentifier = existingState.originalViewControllerIdentifier {
            generation.originalControllerIndexes.removeValue(forKey: originalIdentifier)
            existingState.originalViewControllerIdentifier = nil
        }

        let requestedGenerationIdentifier = generation.identifier
        let providedViewController = existingState?.originalViewController ?? originalProvider()
        guard activeGeneration === generation,
              generation.identifier == requestedGenerationIdentifier else {
            AnchorPagerLogger.log(
                .debug,
                category: .children,
                event: "children.page.generation.cancel"
            )
            return nil
        }

        var originalViewController: UIViewController
        if let providedViewController {
            originalViewController = providedViewController
        } else {
            originalViewController = UIViewController()
            AnchorPagerLogger.log(
                .error,
                category: .children,
                event: "children.page.dataSourceMissing"
            )
        }
        var originalIdentifier = ObjectIdentifier(originalViewController)
        if let claimedIndex = generation.originalControllerIndexes[originalIdentifier],
           claimedIndex != index {
            AnchorPagerAssertions.failure(
                "AnchorPager pages must not reuse one view controller at multiple indexes."
            )
            AnchorPagerLogger.log(
                .debug,
                category: .children,
                event: "children.page.duplicateController"
            )
            originalViewController = UIViewController()
            originalIdentifier = ObjectIdentifier(originalViewController)
        }
        let state = existingState
            ?? migratedState(
                for: originalViewController,
                to: index,
                in: generation
            )
            ?? PageState()
        generation.pages[index] = state
        generation.originalControllerIndexes[originalIdentifier] = index

        if let livePage = state.actualPageViewController {
            if let claimedIdentifier = state.claimedScrollViewIdentifier {
                generation.claimedScrollViewIdentifiers.insert(claimedIdentifier)
            }
            applyManagedInsets(context.managedInsetTarget, to: state)
            reconcileRetention(in: generation)
            AnchorPagerLogger.log(.debug, category: .children, event: "children.page.reuse")
            return livePage
        }
        if let claimedIdentifier = state.claimedScrollViewIdentifier {
            if let previousScrollView = state.scrollView {
                managedInsetCoordinator.release(previousScrollView)
            }
            state.fallbackHost?.setManagedContentInsets(.zero)
            generation.claimedScrollViewIdentifiers.remove(claimedIdentifier)
            state.claimedScrollViewIdentifier = nil
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
        state.originalViewControllerIdentifier = originalIdentifier
        state.actualPageViewController = actualPageViewController
        state.scrollView = scrollView
        state.claimedScrollViewIdentifier = ObjectIdentifier(scrollView)
        applyManagedInsets(context.managedInsetTarget, to: state)
        reconcileRetention(in: generation)
        AnchorPagerLogger.log(
            .info,
            category: .children,
            event: state.hasLoadedBefore ? "children.page.recreate" : "children.page.load"
        )
        state.hasLoadedBefore = true
        return actualPageViewController
    }

    func scrollView(at index: Int) -> UIScrollView? {
        activeGeneration?.pages[index]?.scrollView
    }

    func livePageViewController(at index: Int) -> UIViewController? {
        activeGeneration?.pages[index]?.actualPageViewController
    }

    func retentionReasons(at index: Int) -> Set<RetentionReason> {
        activeGeneration?.pages[index]?.retentionReasons ?? []
    }

    func childDistanceFromTop(at index: Int) -> CGFloat {
        activeGeneration?.pages[index]?.childDistanceFromTop ?? 0
    }

    func pageStateIdentifier(at index: Int) -> ObjectIdentifier? {
        activeGeneration?.pages[index].map(ObjectIdentifier.init)
    }

    func isPageRetained(at index: Int) -> Bool {
        activeGeneration?.pages[index]?.retainedPage != nil
    }

    func setKeepsAdjacentPagesLoaded(_ keepsAdjacentPagesLoaded: Bool) {
        guard let generation = activeGeneration,
              generation.keepsAdjacentPagesLoaded != keepsAdjacentPagesLoaded else {
            return
        }
        generation.keepsAdjacentPagesLoaded = keepsAdjacentPagesLoaded
        reconcileRetention(in: generation)
    }

    func updateManagedInsets(
        _ target: AnchorPagerManagedInsetCoordinator.Target,
        logsChanges: Bool
    ) {
        guard let generation = activeGeneration else {
            lastManagedUpdateCount = 0
            return
        }
        let activeStates = activeRetentionIndexes(in: generation)
            .compactMap { generation.pages[$0] }
            .filter { $0.scrollView != nil }
        lastManagedUpdateCount = activeStates.count
        for state in activeStates {
            applyManagedInsets(target, to: state, logsChanges: logsChanges)
        }
    }

    func willSelect(
        from sourceIndex: Int,
        to targetIndex: Int,
        context: AccessContext
    ) {
        guard let generation = activeGeneration,
              (0..<generation.pageCount).contains(sourceIndex),
              (0..<generation.pageCount).contains(targetIndex) else {
            return
        }
        generation.transitionSourceIndex = sourceIndex
        generation.transitionTargetIndex = targetIndex
        reconcileRetention(in: generation)
        applyManagedInsets(context.managedInsetTarget, at: targetIndex, in: generation)
        applySnapshot(at: targetIndex, context: context, in: generation)
    }

    func didSelect(_ index: Int, context: AccessContext) {
        guard let generation = activeGeneration,
              (0..<generation.pageCount).contains(index) else {
            return
        }
        generation.currentIndex = index
        generation.transitionSourceIndex = nil
        generation.transitionTargetIndex = nil
        reconcileRetention(in: generation)
        applyManagedInsets(context.managedInsetTarget, at: index, in: generation)
        applySnapshot(at: index, context: context, in: generation)
    }

    func didCancelSelection(
        at targetIndex: Int,
        returningTo sourceIndex: Int,
        context: AccessContext
    ) {
        guard let generation = activeGeneration,
              (0..<generation.pageCount).contains(sourceIndex),
              (0..<generation.pageCount).contains(targetIndex) else {
            return
        }
        generation.currentIndex = sourceIndex
        generation.transitionSourceIndex = nil
        generation.transitionTargetIndex = nil
        reconcileRetention(in: generation)
        applyManagedInsets(context.managedInsetTarget, at: sourceIndex, in: generation)
    }

    func commitReload(generation: Int) {
        guard pendingGeneration?.identifier == generation else {
            AnchorPagerLogger.log(
                .debug,
                category: .children,
                event: "children.page.generation.cancel"
            )
            return
        }
        let oldGeneration = committedGeneration
        committedGeneration = pendingGeneration
        pendingGeneration = nil
        if let oldGeneration {
            let preservedStateIdentifiers = Set(
                committedGeneration?.pages.values.map(ObjectIdentifier.init) ?? []
            )
            release(oldGeneration, preserving: preservedStateIdentifiers)
        }
        AnchorPagerLogger.log(.info, category: .children, event: "children.page.generation.commit")
    }

    func releaseAll() {
        var releasedStateIdentifiers: Set<ObjectIdentifier> = []
        for generation in [pendingGeneration, committedGeneration].compactMap({ $0 }) {
            let stateIdentifiers = Set(generation.pages.values.map(ObjectIdentifier.init))
            release(generation, preserving: releasedStateIdentifiers)
            releasedStateIdentifiers.formUnion(stateIdentifiers)
        }
        pendingGeneration = nil
        committedGeneration = nil
    }

    private var activeGeneration: GenerationState? {
        pendingGeneration ?? committedGeneration
    }

    private func applyManagedInsets(
        _ target: AnchorPagerManagedInsetCoordinator.Target,
        to state: PageState,
        logsChanges: Bool = true
    ) {
        guard let scrollView = state.scrollView else { return }
        state.fallbackHost?.setManagedContentInsets(target.content)
        managedInsetCoordinator.apply(target, to: scrollView, logsChanges: logsChanges)
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

    private func migratedState(
        for originalViewController: UIViewController,
        to newIndex: Int,
        in generation: GenerationState
    ) -> PageState? {
        guard let committedGeneration,
              committedGeneration !== generation,
              let (oldIndex, state) = committedGeneration.pages.first(where: {
                  $0.value.originalViewController === originalViewController
              }) else {
            return nil
        }
        let currentDistance = state.scrollView.map {
            childDistanceFromTop(in: $0)
        } ?? state.childDistanceFromTop
        generation.migratedPreviousDistances[ObjectIdentifier(state)] = currentDistance
        state.childDistanceFromTop = oldIndex == newIndex ? currentDistance : 0
        return state
    }

    private func reconcileRetention(in generation: GenerationState) {
        for (index, state) in generation.pages {
            var reasons: Set<RetentionReason> = []
            if index == generation.currentIndex {
                reasons.insert(.current)
            }
            if generation.keepsAdjacentPagesLoaded,
               abs(index - generation.currentIndex) == 1 {
                reasons.insert(.configuredAdjacent)
            }
            if index == generation.transitionSourceIndex {
                reasons.insert(.transitionSource)
            }
            if index == generation.transitionTargetIndex {
                reasons.insert(.transitionTarget)
            }

            guard reasons != state.retentionReasons else { continue }
            let wasRetained = !state.retentionReasons.isEmpty
            let isRetained = !reasons.isEmpty
            if wasRetained, !isRetained {
                saveSnapshotAndReleaseOwnership(for: state)
            }
            state.retentionReasons = reasons
            state.retainedPage = isRetained ? state.actualPageViewController : nil
            if wasRetained != isRetained {
                AnchorPagerLogger.log(
                    .debug,
                    category: .children,
                    event: isRetained ? "children.page.retain" : "children.page.release"
                )
            }
        }
    }

    private func applyManagedInsets(
        _ target: AnchorPagerManagedInsetCoordinator.Target,
        at index: Int,
        in generation: GenerationState
    ) {
        guard let state = generation.pages[index] else { return }
        applyManagedInsets(target, to: state)
    }

    private func saveSnapshotAndReleaseOwnership(for state: PageState) {
        guard let scrollView = state.scrollView else { return }
        state.childDistanceFromTop = childDistanceFromTop(in: scrollView)
        AnchorPagerLogger.log(
            .debug,
            category: .children,
            event: "children.page.snapshot.save"
        )
        managedInsetCoordinator.release(scrollView)
        state.fallbackHost?.setManagedContentInsets(.zero)
    }

    private func applySnapshot(
        at index: Int,
        context: AccessContext,
        in generation: GenerationState
    ) {
        guard let state = generation.pages[index],
              let scrollView = state.scrollView else {
            return
        }
        let distance = context.containerIsCollapsed ? state.childDistanceFromTop : 0
        state.childDistanceFromTop = distance
        scrollView.contentOffset = CGPoint(
            x: scrollView.contentOffset.x,
            y: -scrollView.contentInset.top + distance
        )
        AnchorPagerLogger.log(
            .debug,
            category: .children,
            event: context.containerIsCollapsed
                ? "children.page.snapshot.restore"
                : "children.page.snapshot.reset"
        )
    }

    private func childDistanceFromTop(in scrollView: UIScrollView) -> CGFloat {
        Swift.max(0, scrollView.contentOffset.y + scrollView.contentInset.top)
    }

    private func activeRetentionIndexes(in generation: GenerationState) -> Set<Int> {
        var indexes = Set([generation.currentIndex])
        if let sourceIndex = generation.transitionSourceIndex {
            indexes.insert(sourceIndex)
        }
        if let targetIndex = generation.transitionTargetIndex {
            indexes.insert(targetIndex)
        }
        if generation.keepsAdjacentPagesLoaded {
            let previousIndex = generation.currentIndex - 1
            let nextIndex = generation.currentIndex + 1
            if (0..<generation.pageCount).contains(previousIndex) {
                indexes.insert(previousIndex)
            }
            if (0..<generation.pageCount).contains(nextIndex) {
                indexes.insert(nextIndex)
            }
        }
        return indexes
    }

    private func release(
        _ generation: GenerationState,
        preserving preservedStateIdentifiers: Set<ObjectIdentifier>
    ) {
        for state in generation.pages.values
        where !preservedStateIdentifiers.contains(ObjectIdentifier(state)) {
            if let scrollView = state.scrollView {
                managedInsetCoordinator.release(scrollView)
            }
            state.fallbackHost?.setManagedContentInsets(.zero)
            state.fallbackHost?.removeContentForReloadData()
            state.retentionReasons = []
            state.retainedPage = nil
        }
        generation.pages.removeAll()
        generation.claimedScrollViewIdentifiers.removeAll()
        generation.originalControllerIndexes.removeAll()
        generation.migratedPreviousDistances.removeAll()
    }

    private func restoreMigratedDistances(in generation: GenerationState) {
        for state in generation.pages.values {
            guard let distance = generation.migratedPreviousDistances[ObjectIdentifier(state)] else {
                continue
            }
            state.childDistanceFromTop = distance
        }
    }
}
