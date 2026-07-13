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

    private final class PageIdentityPayload {
        weak var originalViewController: UIViewController?
        weak var actualPageViewController: UIViewController?
        weak var scrollView: UIScrollView?
        var claimedScrollViewIdentifier: ObjectIdentifier?
        var originalViewControllerIdentifier: ObjectIdentifier?
        var hasLoadedBefore = false
    }

    private final class GenerationPageState {
        let identity: PageIdentityPayload
        var retainedPage: UIViewController?
        var retentionReasons: Set<RetentionReason> = []
        var childDistanceFromTop: CGFloat
        var ownsManagedInset = false

        init(identity: PageIdentityPayload, childDistanceFromTop: CGFloat = 0) {
            self.identity = identity
            self.childDistanceFromTop = childDistanceFromTop
        }
    }

    private final class GenerationState {
        let identifier: Int
        let pageCount: Int
        var currentIndex: Int
        var keepsAdjacentPagesLoaded: Bool
        var pages: [Int: GenerationPageState] = [:]
        var claimedScrollViewIdentifiers: Set<ObjectIdentifier> = []
        var originalControllerIndexes: [ObjectIdentifier: Int] = [:]
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

    private struct CleanupPlan {
        struct Entry {
            let state: GenerationPageState
            let scrollView: UIScrollView?
        }

        let generation: GenerationState
        let entries: [Entry]

        init(generation: GenerationState) {
            self.generation = generation
            entries = generation.pages.values.map { state in
                Entry(
                    state: state,
                    scrollView: state.identity.scrollView
                )
            }
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

    var committedCurrentIndex: Int? {
        guard let generation = committedGeneration,
              (0..<generation.pageCount).contains(generation.currentIndex) else {
            return nil
        }
        return generation.currentIndex
    }

    var committedCurrentPageViewController: UIViewController? {
        guard let generation = committedGeneration,
              let currentIndex = committedCurrentIndex else {
            return nil
        }
        return generation.pages[currentIndex]?.identity.actualPageViewController
    }

    var committedCurrentScrollView: UIScrollView? {
        guard let generation = committedGeneration,
              let currentIndex = committedCurrentIndex else {
            return nil
        }
        return generation.pages[currentIndex]?.identity.scrollView
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
            release(
                pendingGeneration,
                preservingOwnership: ownershipPreservation(in: committedGeneration)
            )
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
        guard let generation = providerGeneration,
              (0..<generation.pageCount).contains(index) else {
            return nil
        }

        let existingState = generation.pages[index]
        if let livePage = existingState?.identity.actualPageViewController {
            guard let existingState else { return nil }
            applyManagedInsets(context.managedInsetTarget, to: existingState)
            AnchorPagerLogger.log(.debug, category: .children, event: "children.page.reuse")
            return livePage
        }
        if let existingState,
           existingState.identity.originalViewController == nil,
           let originalIdentifier = existingState.identity.originalViewControllerIdentifier {
            generation.originalControllerIndexes.removeValue(forKey: originalIdentifier)
            existingState.identity.originalViewControllerIdentifier = nil
        }

        let requestedGenerationIdentifier = generation.identifier
        let providedViewController = existingState?.identity.originalViewController
            ?? originalProvider()
        guard providerGeneration === generation,
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
            ?? GenerationPageState(identity: PageIdentityPayload())
        generation.pages[index] = state
        generation.originalControllerIndexes[originalIdentifier] = index

        if let livePage = state.identity.actualPageViewController {
            if let claimedIdentifier = state.identity.claimedScrollViewIdentifier {
                generation.claimedScrollViewIdentifiers.insert(claimedIdentifier)
            }
            applyManagedInsets(context.managedInsetTarget, to: state)
            reconcileRetention(in: generation)
            AnchorPagerLogger.log(.debug, category: .children, event: "children.page.reuse")
            return livePage
        }
        if let claimedIdentifier = state.identity.claimedScrollViewIdentifier {
            releaseOwnership(for: state, in: generation)
            generation.claimedScrollViewIdentifiers.remove(claimedIdentifier)
            state.identity.claimedScrollViewIdentifier = nil
        }

        originalViewController.loadViewIfNeeded()
        let actualPageViewController = originalViewController
        let scrollView: UIScrollView?
        let resolvedScrollView = originalViewController.anchorPagerScrollView
        if let resolvedScrollView,
           generation.claimedScrollViewIdentifiers
            .insert(ObjectIdentifier(resolvedScrollView)).inserted {
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
                scrollView = defaultScrollView
            } else {
                scrollView = nil
            }
        } else {
            scrollView = nil
        }
        if scrollView == nil {
            AnchorPagerLogger.log(.debug, category: .scroll, event: "scroll.target.none")
        }

        state.identity.originalViewController = originalViewController
        state.identity.originalViewControllerIdentifier = originalIdentifier
        state.identity.actualPageViewController = actualPageViewController
        state.identity.scrollView = scrollView
        state.identity.claimedScrollViewIdentifier = scrollView.map(ObjectIdentifier.init)
        applyManagedInsets(context.managedInsetTarget, to: state)
        reconcileRetention(in: generation)
        AnchorPagerLogger.log(
            .info,
            category: .children,
            event: state.identity.hasLoadedBefore
                ? "children.page.recreate"
                : "children.page.load"
        )
        state.identity.hasLoadedBefore = true
        return actualPageViewController
    }

    func scrollView(at index: Int) -> UIScrollView? {
        visibleGeneration?.pages[index]?.identity.scrollView
    }

    func livePageViewController(at index: Int) -> UIViewController? {
        visibleGeneration?.pages[index]?.identity.actualPageViewController
    }

    func retentionReasons(at index: Int) -> Set<RetentionReason> {
        visibleGeneration?.pages[index]?.retentionReasons ?? []
    }

    func childDistanceFromTop(at index: Int) -> CGFloat {
        visibleGeneration?.pages[index]?.childDistanceFromTop ?? 0
    }

    func pageStateIdentifier(at index: Int) -> ObjectIdentifier? {
        visibleGeneration?.pages[index].map(ObjectIdentifier.init)
    }

    func isPageRetained(at index: Int) -> Bool {
        visibleGeneration?.pages[index]?.retainedPage != nil
    }

    func setKeepsAdjacentPagesLoaded(_ keepsAdjacentPagesLoaded: Bool) {
        guard let generation = visibleGeneration,
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
        guard let generation = visibleGeneration else {
            lastManagedUpdateCount = 0
            return
        }
        let activeStates = activeRetentionIndexes(in: generation)
            .compactMap { generation.pages[$0] }
            .filter { $0.identity.scrollView != nil }
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
        guard let generation = visibleGeneration,
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
        guard let generation = visibleGeneration,
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
        guard let generation = visibleGeneration,
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
        let oldCleanupPlan = oldGeneration.map(CleanupPlan.init)
        if let oldGeneration {
            releaseLeases(in: oldGeneration)
        }
        if let committedGeneration {
            reconcileRetention(
                in: committedGeneration,
                forceOwnershipReconciliation: true
            )
        }
        if let oldCleanupPlan {
            cleanup(
                oldCleanupPlan,
                preservingOwnership: ownershipPreservation(in: committedGeneration)
            )
        }
        AnchorPagerLogger.log(.info, category: .children, event: "children.page.generation.commit")
    }

    func releaseAll() {
        let pendingCleanupPlan = pendingGeneration.map(CleanupPlan.init)
        let committedCleanupPlan = committedGeneration.map(CleanupPlan.init)
        if let pendingCleanupPlan {
            releaseLeases(in: pendingCleanupPlan.generation)
            cleanup(
                pendingCleanupPlan,
                preservingOwnership: ownershipPreservation(in: committedGeneration)
            )
        }
        if let committedCleanupPlan {
            releaseLeases(in: committedCleanupPlan.generation)
            cleanup(
                committedCleanupPlan,
                preservingOwnership: []
            )
        }
        pendingGeneration = nil
        committedGeneration = nil
    }

    private var providerGeneration: GenerationState? {
        pendingGeneration ?? committedGeneration
    }

    private var visibleGeneration: GenerationState? {
        committedGeneration ?? pendingGeneration
    }

    private func applyManagedInsets(
        _ target: AnchorPagerManagedInsetCoordinator.Target,
        to state: GenerationPageState,
        logsChanges: Bool = true
    ) {
        guard let scrollView = state.identity.scrollView else { return }
        managedInsetCoordinator.apply(target, to: scrollView, logsChanges: logsChanges)
        state.ownsManagedInset = true
    }

    private func migratedState(
        for originalViewController: UIViewController,
        to newIndex: Int,
        in generation: GenerationState
    ) -> GenerationPageState? {
        guard let committedGeneration,
              committedGeneration !== generation,
              let (oldIndex, state) = committedGeneration.pages.first(where: {
                  $0.value.identity.originalViewController === originalViewController
              }) else {
            return nil
        }
        let currentDistance = state.identity.scrollView.map {
            childDistanceFromTop(in: $0)
        } ?? state.childDistanceFromTop
        let migratedState = GenerationPageState(
            identity: state.identity,
            childDistanceFromTop: oldIndex == newIndex ? currentDistance : 0
        )
        if let originalIdentifier = state.identity.originalViewControllerIdentifier {
            generation.originalControllerIndexes[originalIdentifier] = newIndex
        }
        if let claimedIdentifier = state.identity.claimedScrollViewIdentifier {
            generation.claimedScrollViewIdentifiers.insert(claimedIdentifier)
        }
        return migratedState
    }

    private func reconcileRetention(
        in generation: GenerationState,
        forceOwnershipReconciliation: Bool = false
    ) {
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

            guard reasons != state.retentionReasons || forceOwnershipReconciliation else {
                continue
            }
            let wasRetained = !state.retentionReasons.isEmpty
            let isRetained = !reasons.isEmpty
            if wasRetained, !isRetained {
                saveSnapshotAndReleaseOwnership(for: state, in: generation)
            } else if forceOwnershipReconciliation, !isRetained {
                releaseOwnership(for: state, in: generation)
            }
            state.retentionReasons = reasons
            state.retainedPage = isRetained
                ? state.identity.actualPageViewController
                : nil
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

    private func saveSnapshotAndReleaseOwnership(
        for state: GenerationPageState,
        in generation: GenerationState
    ) {
        guard let scrollView = state.identity.scrollView else { return }
        state.childDistanceFromTop = childDistanceFromTop(in: scrollView)
        AnchorPagerLogger.log(
            .debug,
            category: .children,
            event: "children.page.snapshot.save"
        )
        releaseOwnership(for: state, in: generation)
    }

    private func releaseOwnership(
        for state: GenerationPageState,
        in generation: GenerationState,
        preserving explicitPreservation: Set<ObjectIdentifier>? = nil
    ) {
        releaseOwnership(
            for: state,
            scrollView: state.identity.scrollView,
            in: generation,
            preserving: explicitPreservation
        )
    }

    private func releaseOwnership(
        for state: GenerationPageState,
        scrollView: UIScrollView?,
        in generation: GenerationState,
        preserving explicitPreservation: Set<ObjectIdentifier>?
    ) {
        guard state.ownsManagedInset else {
            return
        }
        state.ownsManagedInset = false
        guard let scrollView else { return }
        let preservation = explicitPreservation
            ?? ownershipPreservation(in: otherGeneration(for: generation))
        guard !preservation.contains(ObjectIdentifier(scrollView)) else { return }
        managedInsetCoordinator.release(scrollView)
    }

    private func applySnapshot(
        at index: Int,
        context: AccessContext,
        in generation: GenerationState
    ) {
        guard let state = generation.pages[index],
              let scrollView = state.identity.scrollView else {
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

    private func ownershipPreservation(
        in generation: GenerationState?
    ) -> Set<ObjectIdentifier> {
        guard let generation else { return [] }
        return Set(generation.pages.values.compactMap { state in
            guard state.ownsManagedInset, let scrollView = state.identity.scrollView else {
                return nil
            }
            return ObjectIdentifier(scrollView)
        })
    }

    private func otherGeneration(for generation: GenerationState) -> GenerationState? {
        let otherGeneration: GenerationState?
        if generation === committedGeneration {
            otherGeneration = pendingGeneration
        } else if generation === pendingGeneration {
            otherGeneration = committedGeneration
        } else {
            otherGeneration = nil
        }
        return otherGeneration
    }

    private func release(
        _ generation: GenerationState,
        preservingOwnership ownershipPreservation: Set<ObjectIdentifier>
    ) {
        let cleanupPlan = CleanupPlan(generation: generation)
        releaseLeases(in: generation)
        cleanup(
            cleanupPlan,
            preservingOwnership: ownershipPreservation
        )
    }

    private func releaseLeases(in generation: GenerationState) {
        for state in generation.pages.values {
            state.retentionReasons = []
            state.retainedPage = nil
        }
    }

    private func cleanup(
        _ plan: CleanupPlan,
        preservingOwnership ownershipPreservation: Set<ObjectIdentifier>
    ) {
        for entry in plan.entries {
            releaseOwnership(
                for: entry.state,
                scrollView: entry.scrollView,
                in: plan.generation,
                preserving: ownershipPreservation
            )
        }
        let generation = plan.generation
        generation.pages.removeAll()
        generation.claimedScrollViewIdentifiers.removeAll()
        generation.originalControllerIndexes.removeAll()
    }
}
