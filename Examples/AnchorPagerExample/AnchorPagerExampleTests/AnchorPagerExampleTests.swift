import AnchorPager
import Testing
import UIKit
@testable import AnchorPagerExample

@MainActor
struct AnchorPagerExampleTests {
    @Test func scrollCoordinationStateSerializesStableAccessibilityValue() {
        let state = ExampleScrollCoordinationState(
            page: "long",
            hasScrollTarget: true,
            mode: "container",
            collapseProgress: 1,
            containerTopInset: 59,
            headerHeight: 100,
            maximumHeaderHeightDelta: 0.25,
            headerCollapseTranslation: 80,
            childDistance: 42,
            containerPresentation: 1.25,
            maximumContainerTopPresentation: 12.5,
            maximumContainerBottomPresentation: 8,
            barPresentation: -0.25,
            maximumBarPresentation: 0.75,
            childTopOverflow: 2,
            maximumChildTopOverflow: 5,
            childBottomOverflow: 4,
            maximumChildBottomOverflow: 7,
            headerContentTopDistance: 88,
            maximumHeaderContentTopDistanceDelta: 0.4,
            canonicalTotal: 122,
            maximumDirectionReversal: 6,
            maximumStableInvariantViolation: 2,
            didHandoffContainerToChild: true,
            didHandoffChildToContainer: false,
            momentumSampleCount: 9
        )

        #expect(
            state.accessibilityValue
                == "page=long;hasScrollTarget=1;mode=container;collapse=1.00;containerTopInset=59.00;headerHeight=100.00;headerHeightDeltaMax=0.25;headerCollapse=80.00;distance=42.00;containerCurrent=1.25;containerTopMax=12.50;containerBottomMax=8.00;barCurrent=-0.25;barMax=0.75;childTopCurrent=2.00;childTopMax=5.00;childBottomCurrent=4.00;childBottomMax=7.00;headerContentTop=88.00;headerContentTopDeltaMax=0.40;canonical=122.00;reversalMax=6.00;invariantMax=2.00;containerToChild=1;childToContainer=0;samples=9"
        )
    }

    @Test func plainScrollCoordinationStateReportsNoScrollTarget() {
        let state = ExampleScrollCoordinationState(
            page: "plain",
            hasScrollTarget: false,
            mode: "container",
            collapseProgress: 1,
            containerTopInset: 0,
            headerHeight: 100,
            maximumHeaderHeightDelta: 0,
            headerCollapseTranslation: 80,
            childDistance: 0,
            containerPresentation: 0,
            maximumContainerTopPresentation: 0,
            maximumContainerBottomPresentation: 0,
            barPresentation: 0,
            maximumBarPresentation: 0,
            childTopOverflow: 0,
            maximumChildTopOverflow: 0,
            childBottomOverflow: 0,
            maximumChildBottomOverflow: 0
        )

        #expect(
            state.accessibilityValue
                == "page=plain;hasScrollTarget=0;mode=container;collapse=1.00;containerTopInset=0.00;headerHeight=100.00;headerHeightDeltaMax=0.00;headerCollapse=80.00;distance=0.00;containerCurrent=0.00;containerTopMax=0.00;containerBottomMax=0.00;barCurrent=0.00;barMax=0.00;childTopCurrent=0.00;childTopMax=0.00;childBottomCurrent=0.00;childBottomMax=0.00;headerContentTop=0.00;headerContentTopDeltaMax=0.00;canonical=0.00;reversalMax=0.00;invariantMax=0.00;containerToChild=0;childToContainer=0;samples=0"
        )
    }

    @Test func scrollCoordinationStateResetsPresentationMetrics() {
        var state = ExampleScrollCoordinationState(
            page: "long",
            hasScrollTarget: true,
            mode: "container",
            collapseProgress: 0,
            containerTopInset: 59,
            headerHeight: 100,
            maximumHeaderHeightDelta: 3,
            headerCollapseTranslation: 40,
            childDistance: 0,
            containerPresentation: 3,
            maximumContainerTopPresentation: 12,
            maximumContainerBottomPresentation: 8,
            barPresentation: -2,
            maximumBarPresentation: 4,
            childTopOverflow: 2,
            maximumChildTopOverflow: 5,
            childBottomOverflow: 4,
            maximumChildBottomOverflow: 7,
            headerContentTopDistance: 88,
            maximumHeaderContentTopDistanceDelta: 4
        )

        state.resetPresentationMetrics()

        #expect(state.containerPresentation == 0)
        #expect(state.maximumContainerTopPresentation == 0)
        #expect(state.maximumContainerBottomPresentation == 0)
        #expect(state.containerTopInset == 59)
        #expect(state.headerHeight == 100)
        #expect(state.maximumHeaderHeightDelta == 0)
        #expect(state.headerCollapseTranslation == 0)
        #expect(state.barPresentation == 0)
        #expect(state.maximumBarPresentation == 0)
        #expect(state.childTopOverflow == 0)
        #expect(state.maximumChildTopOverflow == 0)
        #expect(state.childBottomOverflow == 0)
        #expect(state.maximumChildBottomOverflow == 0)
        #expect(state.headerContentTopDistance == 88)
        #expect(state.maximumHeaderContentTopDistanceDelta == 0)
        #expect(state.canonicalTotal == 0)
        #expect(state.maximumDirectionReversal == 0)
        #expect(state.maximumStableInvariantViolation == 0)
        #expect(state.didHandoffContainerToChild == false)
        #expect(state.didHandoffChildToContainer == false)
        #expect(state.momentumSampleCount == 0)
    }

    @Test func scrollCoordinationStateRecordsMomentumDirectionAndOwnership() {
        var state = ExampleScrollCoordinationState(
            page: "long",
            hasScrollTarget: true,
            mode: "container",
            collapseProgress: 0,
            containerTopInset: 0,
            headerHeight: 100,
            maximumHeaderHeightDelta: 0,
            headerCollapseTranslation: 0,
            childDistance: 0,
            containerPresentation: 0,
            maximumContainerTopPresentation: 0,
            maximumContainerBottomPresentation: 0,
            barPresentation: 0,
            maximumBarPresentation: 0,
            childTopOverflow: 0,
            maximumChildTopOverflow: 0,
            childBottomOverflow: 0,
            maximumChildBottomOverflow: 0
        )

        state.recordMomentumSample(
            containerDistance: 40,
            childDistance: 0,
            collapsedDistance: 100
        )
        state.recordMomentumSample(
            containerDistance: 100,
            childDistance: 10,
            collapsedDistance: 100
        )
        state.recordMomentumSample(
            containerDistance: 90,
            childDistance: 0,
            collapsedDistance: 100
        )
        state.recordMomentumSample(
            containerDistance: 80,
            childDistance: 5,
            collapsedDistance: 100
        )

        #expect(abs(state.canonicalTotal - 85) < 0.001)
        #expect(abs(state.maximumDirectionReversal - 20) < 0.001)
        #expect(abs(state.maximumStableInvariantViolation - 20) < 0.001)
        #expect(state.didHandoffContainerToChild)
        #expect(state.didHandoffChildToContainer)
        #expect(state.momentumSampleCount == 4)
    }

    @Test func selectionTraceSerializesAndResetsPublicTerminals() {
        var trace = ExampleSelectionTrace()

        trace.record(index: 1)
        trace.record(index: 3)
        trace.record(index: 2)

        #expect(trace.serializedValue == "1,3,2")
        trace.reset()
        #expect(trace.serializedValue.isEmpty)
    }

    @Test func horizontalBusinessPageIsFifthAndKeepsDelegateConfiguration() throws {
        let viewController = ExamplePagerViewController(arguments: [])
        viewController.loadViewIfNeeded()
        let pager = try #require(
            viewController.children.compactMap { $0 as? AnchorPagerViewController }.first
        )

        #expect(pager.dataSource?.numberOfViewControllers(in: pager) == 5)
        #expect(
            pager.dataSource?.pagerViewController(
                pager,
                titleForViewControllerAt: 4
            ) == "横向业务页"
        )
        let page = try #require(viewController.pageForTesting(at: 4))
        page.loadViewIfNeeded()
        page.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        page.view.layoutIfNeeded()
        let horizontalScrollView = try #require(
            firstSubview(in: page.view, as: UIScrollView.self) {
                $0.accessibilityIdentifier == "horizontal-business-scroll"
            }
        )
        let probe = try #require(
            firstSubview(in: page.view, as: UIView.self) {
                $0.accessibilityIdentifier == "horizontal-business-probe"
            }
        )

        #expect(page.anchorPagerScrollView === horizontalScrollView)
        #expect(horizontalScrollView.contentSize.width > horizontalScrollView.bounds.width)
        #expect(
            probe.accessibilityValue
                == "scrollDelegate=1;panDelegate=1;bounces=1;alwaysBounceVertical=0;isScrollEnabled=1;horizontalRange=1"
        )
    }

    @Test func rapidSelectionControlOnlyInstallsForLaunchArgument() {
        let normal = ExamplePagerViewController(arguments: [])
        normal.loadViewIfNeeded()
        let enabled = ExamplePagerViewController(arguments: [
            "--anchorPagerRapidSelectionTargets",
            "1,3,2",
        ])
        enabled.loadViewIfNeeded()

        #expect(
            firstSubview(in: normal.view, as: UIButton.self) {
                $0.accessibilityIdentifier == "rapid-selection-trigger"
            } == nil
        )
        #expect(
            firstSubview(in: enabled.view, as: UIButton.self) {
                $0.accessibilityIdentifier == "rapid-selection-trigger"
            } != nil
        )
    }

    @Test func scrollCoordinationStateRecordsStableHeaderGeometry() {
        var state = ExampleScrollCoordinationState(
            page: "short",
            hasScrollTarget: true,
            mode: "container",
            collapseProgress: 0.5,
            containerTopInset: 59,
            headerHeight: 100,
            maximumHeaderHeightDelta: 0,
            headerCollapseTranslation: 0,
            childDistance: 0,
            containerPresentation: 0,
            maximumContainerTopPresentation: 0,
            maximumContainerBottomPresentation: 0,
            barPresentation: 0,
            maximumBarPresentation: 0,
            childTopOverflow: 0,
            maximumChildTopOverflow: 0,
            childBottomOverflow: 0,
            maximumChildBottomOverflow: 0
        )

        state.recordHeaderGeometry(
            currentHeight: 99.8,
            baselineHeight: 100,
            currentMinY: 29,
            baselineMinY: 59
        )
        state.recordHeaderGeometry(
            currentHeight: 100.3,
            baselineHeight: 100,
            currentMinY: 19,
            baselineMinY: 59
        )

        #expect(abs(state.headerHeight - 100.3) < 0.001)
        #expect(abs(state.maximumHeaderHeightDelta - 0.3) < 0.001)
        #expect(abs(state.headerCollapseTranslation - 40) < 0.001)

        state.recordHeaderContentTopDistance(current: 87.8, baseline: 88)
        state.recordHeaderContentTopDistance(current: 88.4, baseline: 88)

        #expect(abs(state.headerContentTopDistance - 88.4) < 0.001)
        #expect(abs(state.maximumHeaderContentTopDistanceDelta - 0.4) < 0.001)
    }

    @Test func rootControllerInstallsAnchorPager() {
        let tabBarController = makeExampleRootViewController()
        let navigationController = tabBarController.viewControllers?.first as? UINavigationController
        let viewController = navigationController?.viewControllers.first as? ExamplePagerViewController

        viewController?.loadViewIfNeeded()

        #expect(tabBarController.viewControllers?.count == 1)
        #expect(navigationController?.tabBarItem.title == "AnchorPager")
        #expect(navigationController?.tabBarItem.image != nil)
        #expect(navigationController?.tabBarItem.selectedImage != nil)
        #expect(viewController?.title == "AnchorPager")
    }

    @Test func pagerNavigationShowsUnifiedSettingsMenuWithCurrentConfiguration() throws {
        let viewController = ExamplePagerViewController()
        viewController.loadViewIfNeeded()

        let items = viewController.navigationItem.rightBarButtonItems ?? []
        let settingsItem = try #require(items.first {
            $0.accessibilityLabel == "示例设置"
        })
        let submenus = settingsItem.menu?.children.compactMap { $0 as? UIMenu } ?? []
        let headerMenu = try #require(submenus.first { $0.title == "Header 顶部行为" })
        let overscrollMenu = try #require(submenus.first { $0.title == "顶部回弹模式" })
        let headerActions = headerMenu.children.compactMap { $0 as? UIAction }
        let overscrollActions = overscrollMenu.children.compactMap { $0 as? UIAction }

        #expect(items.count == 3)
        #expect(items.contains { $0.accessibilityLabel == "打开 AnchorPager" })
        #expect(items.contains { $0.accessibilityLabel == "重新加载页面" })
        #expect(!items.contains { $0.accessibilityLabel == "Header 顶部行为" })
        #expect(!items.contains { $0.accessibilityLabel == "顶部回弹" })
        #expect(settingsItem.image != nil || settingsItem.title == "设置")
        #expect(submenus.map(\.title) == ["Header 顶部行为", "顶部回弹模式"])
        #expect(headerActions.map(\.title) == ["安全区内", "延伸到顶部"])
        #expect(headerActions.map(\.state) == [.off, .on])
        #expect(overscrollActions.map(\.title) == ["关闭", "容器", "子页面"])
        #expect(overscrollActions.map(\.state) == [.off, .on, .off])
    }

    @Test func unifiedSettingsMenuSwitchesTopOverscrollModesAndRefreshesSelection() throws {
        guard #available(iOS 16.0, *) else { return }
        let viewController = ExamplePagerViewController()
        viewController.loadViewIfNeeded()
        let pager = try #require(
            viewController.children.compactMap { $0 as? AnchorPagerViewController }.first
        )
        let stateProbe = try #require(
            firstSubview(in: viewController.view, as: UIButton.self) {
                $0.accessibilityIdentifier == "scroll-coordination-state"
            }
        )

        for (title, expectedMode, expectedIdentifier) in [
            ("关闭", AnchorPagerTopOverscrollHandlingMode.none, "none"),
            ("子页面", .child, "child"),
            ("容器", .container, "container")
        ] {
            let settingsItem = try #require(
                viewController.navigationItem.rightBarButtonItems?.first {
                    $0.accessibilityLabel == "示例设置"
                }
            )
            let menu = try #require(
                settingsItem.menu?.children.compactMap { $0 as? UIMenu }.first {
                    $0.title == "顶部回弹模式"
                }
            )
            let action = try #require(
                menu.children.compactMap { $0 as? UIAction }.first { $0.title == title }
            )

            action.performWithSender(nil, target: nil)

            #expect(pager.configuration.topOverscrollHandlingMode == expectedMode)
            #expect(
                stateProbe.accessibilityValue?.contains("mode=\(expectedIdentifier)") == true
            )
            let refreshedMenu = try #require(
                settingsItem.menu?.children.compactMap { $0 as? UIMenu }.first {
                    $0.title == "顶部回弹模式"
                }
            )
            let refreshedActions = refreshedMenu.children.compactMap { $0 as? UIAction }
            #expect(refreshedActions.filter { $0.state == .on }.map(\.title) == [title])
        }
    }

    @Test func normalLaunchDoesNotEnableAppearanceRecorder() {
        let viewController = ExamplePagerViewController()

        viewController.loadViewIfNeeded()

        #expect(viewController.isAppearanceRecorderEnabledForTesting == false)
        #expect(
            firstSubview(in: viewController.view, as: UIButton.self) {
                $0.accessibilityIdentifier == "page-appearance-events"
            } == nil
        )
    }

    @Test func scrollPresentationSamplerFollowsVisiblePageLifecycle() throws {
        let viewController = ExamplePagerViewController()
        viewController.loadViewIfNeeded()
        let scrollPage = try #require(viewController.scrollPageForTesting(at: 1))
        scrollPage.loadViewIfNeeded()
        #expect(viewController.activeScrollPresentationSamplerCountForTesting == 0)

        scrollPage.beginAppearanceTransition(true, animated: false)
        scrollPage.endAppearanceTransition()
        #expect(viewController.activeScrollPresentationSamplerCountForTesting == 1)

        scrollPage.beginAppearanceTransition(false, animated: false)
        scrollPage.endAppearanceTransition()
        #expect(viewController.activeScrollPresentationSamplerCountForTesting == 0)
    }

    @Test func headerTopBehaviorMenuAppliesExtendsUnderTopSafeAreaCoverage() async throws {
        try await withPagerWindow { viewController, window in
            viewController.loadViewIfNeeded()
            window.layoutIfNeeded()
            let pagerViewController = try #require(
                viewController.children.compactMap { $0 as? AnchorPagerViewController }.first
            )
            try await waitForInitialSelection(in: pagerViewController)
            pagerViewController.configuration.header.topBehavior = .insideSafeArea
            pagerViewController.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
            window.layoutIfNeeded()
            #expect(pagerViewController.verticalScrollView.contentInset.top > 1)
            let layoutProbe = LayoutProbe()
            pagerViewController.delegate = layoutProbe
            let insideTopInset = pagerViewController.verticalScrollView.contentInset.top
            pagerViewController.verticalScrollView.contentOffset.y = 80 - insideTopInset
            pagerViewController.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
            window.layoutIfNeeded()
            let collapsedContext = try #require(layoutProbe.layoutContexts.last)

            let settingsItem = try #require(
                viewController.navigationItem.rightBarButtonItems?.first {
                    $0.accessibilityLabel == "示例设置"
                }
            )
            let headerMenu = try #require(
                settingsItem.menu?.children.compactMap { $0 as? UIMenu }.first {
                    $0.title == "Header 顶部行为"
                }
            )
            let extendsAction = try #require(
                headerMenu.children.compactMap { $0 as? UIAction }.first {
                    $0.title == "延伸到顶部"
                }
            )
            if #available(iOS 16.0, *) {
                extendsAction.performWithSender(nil, target: nil)
            }
            window.layoutIfNeeded()
            let switchedContext = try #require(layoutProbe.layoutContexts.last)
            let refreshedHeaderMenu = try #require(
                settingsItem.menu?.children.compactMap { $0 as? UIMenu }.first {
                    $0.title == "Header 顶部行为"
                }
            )
            let expectedHeaderHeight = collapsedContext.headerFrame.height
                + insideTopInset

            #expect(
                refreshedHeaderMenu.children.compactMap { $0 as? UIAction }.map(\.state)
                    == [.off, .on]
            )
            #expect(abs(pagerViewController.verticalScrollView.contentInset.top) < 0.5)
            #expect(abs(pagerViewController.verticalScrollView.contentOffset.y - 80) < 0.5)
            #expect(
                abs(
                    switchedContext.headerFrame.minY
                        - (collapsedContext.headerFrame.minY - insideTopInset)
                ) < 0.5
            )
            #expect(abs(switchedContext.headerFrame.height - expectedHeaderHeight) < 0.5)
            #expect(abs(switchedContext.barFrame.minY - switchedContext.headerFrame.maxY) < 0.5)
            #expect(abs(switchedContext.barFrame.minY - collapsedContext.barFrame.minY) < 0.5)
        }
    }

    @Test func headerContentUsesSafeAreaForVerticalPaddingInBothTopBehaviors() async throws {
        try await withPagerWindow { viewController, window in
            viewController.loadViewIfNeeded()
            window.layoutIfNeeded()
            let pagerViewController = try #require(
                viewController.children.compactMap { $0 as? AnchorPagerViewController }.first
            )
            try await waitForInitialSelection(in: pagerViewController)
            let titleLabel = try #require(
                firstSubview(in: pagerViewController.view, as: UILabel.self) {
                    $0.text == "AnchorPager Example"
                }
            )
            let subtitleLabel = try #require(
                firstSubview(in: pagerViewController.view, as: UILabel.self) {
                    $0.text == "Header UIView、显式 scroll view、无 scroll view child"
                }
            )
            let stackView = try #require(titleLabel.superview as? UIStackView)
            let headerView = try #require(stackView.superview)
            let layoutProbe = LayoutProbe()
            pagerViewController.delegate = layoutProbe

            for behavior in [
                AnchorPagerHeaderTopBehavior.insideSafeArea,
                .extendsUnderTopSafeArea
            ] {
                pagerViewController.configuration.header.topBehavior = behavior
                pagerViewController.reloadHeaderLayout(offsetAdjustment: .resetToExpanded)
                window.layoutIfNeeded()

                let safeAreaFrame = headerView.safeAreaLayoutGuide.layoutFrame
                #expect(stackView.frame.minY >= safeAreaFrame.minY + 20 - 0.5)
                let titleIntrinsicHeight = titleLabel.intrinsicContentSize.height
                let subtitleFittingHeight = subtitleLabel.systemLayoutSizeFitting(
                    CGSize(
                        width: subtitleLabel.bounds.width,
                        height: UIView.layoutFittingCompressedSize.height
                    ),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                ).height
                #expect(abs(titleLabel.bounds.height - titleIntrinsicHeight) < 0.5)
                #expect(abs(subtitleLabel.bounds.height - subtitleFittingHeight) < 0.5)
                #expect(abs(subtitleLabel.frame.minY - titleLabel.frame.maxY - 8) < 0.5)
                #expect(abs(stackView.frame.maxY - (safeAreaFrame.maxY - 20)) < 0.5)

                if behavior == .extendsUnderTopSafeArea {
                    let initialHeaderHeight = headerView.bounds.height
                    let initialStackFrame = stackView.frame
                    let initialTitleFrame = titleLabel.frame
                    let initialSubtitleFrame = subtitleLabel.frame
                    let initialContext = try #require(layoutProbe.layoutContexts.last)
                    #expect(abs(initialContext.headerFrame.minY) < 0.5)
                    let topObstruction = max(
                        headerView.safeAreaInsets.top,
                        safeAreaFrame.minY - headerView.bounds.minY
                    )
                    let overflowSamples = [
                        max(24, topObstruction * 0.5),
                        max(48, topObstruction + 24)
                    ]

                    for overflow in overflowSamples {
                        pagerViewController.verticalScrollView.contentOffset = CGPoint(
                            x: 0,
                            y: -overflow
                        )
                        await Task.yield()
                        window.layoutIfNeeded()
                        let bouncedContext = try #require(layoutProbe.layoutContexts.last)
                        #expect(abs(headerView.bounds.height - initialHeaderHeight) < 0.5)
                        #expect(abs(stackView.frame.minY - initialStackFrame.minY) < 0.5)
                        #expect(abs(stackView.frame.maxY - initialStackFrame.maxY) < 0.5)
                        #expect(abs(titleLabel.frame.minY - initialTitleFrame.minY) < 0.5)
                        #expect(abs(titleLabel.frame.height - initialTitleFrame.height) < 0.5)
                        #expect(abs(subtitleLabel.frame.minY - initialSubtitleFrame.minY) < 0.5)
                        #expect(abs(subtitleLabel.frame.height - initialSubtitleFrame.height) < 0.5)
                        #expect(abs(subtitleLabel.frame.minY - titleLabel.frame.maxY - 8) < 0.5)
                        #expect(
                            bouncedContext.headerFrame.minY
                                > initialContext.headerFrame.minY + 1
                        )
                        #expect(
                            abs(
                                (bouncedContext.barFrame.minY - initialContext.barFrame.minY)
                                    - (bouncedContext.headerFrame.minY
                                        - initialContext.headerFrame.minY)
                            ) < 0.5
                        )
                    }
                    pagerViewController.verticalScrollView.contentOffset = .zero
                    await Task.yield()
                    window.layoutIfNeeded()
                    #expect(abs(stackView.frame.minY - initialStackFrame.minY) < 0.5)
                    #expect(abs(headerView.bounds.height - initialHeaderHeight) < 0.5)
                }
            }
        }
    }
}

@MainActor
private func withPagerWindow(
    _ operation: (ExamplePagerViewController, UIWindow) async throws -> Void
) async throws {
    let viewController = ExamplePagerViewController()
    let navigationController = UINavigationController(rootViewController: viewController)
    let tabBarController = UITabBarController()
    tabBarController.viewControllers = [navigationController]
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = tabBarController
    window.isHidden = false

    do {
        try await operation(viewController, window)
    } catch {
        await tearDown(window: window)
        throw error
    }
    await tearDown(window: window)
}

@MainActor
private func tearDown(window: UIWindow) async {
    window.isHidden = true
    await Task.yield()
    window.rootViewController = nil
}

@MainActor
private func waitForInitialSelection(
    in pagerViewController: AnchorPagerViewController
) async throws {
    let deadline = Date().addingTimeInterval(2)
    while pagerViewController.selectedIndex != 1, Date() < deadline {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    try #require(pagerViewController.selectedIndex == 1)
}

@MainActor
private final class LayoutProbe: AnchorPagerViewControllerDelegate {
    var layoutContexts: [AnchorPagerLayoutContext] = []

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didSelectViewControllerAt index: Int
    ) {}

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateHeaderCollapseProgress progress: CGFloat
    ) {}

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateLayout context: AnchorPagerLayoutContext
    ) {
        layoutContexts.append(context)
    }
}

@MainActor
private func firstSubview<T: UIView>(
    in rootView: UIView,
    as type: T.Type,
    matching predicate: (T) -> Bool
) -> T? {
    if let rootView = rootView as? T, predicate(rootView) {
        return rootView
    }
    for subview in rootView.subviews {
        if let match = firstSubview(in: subview, as: type, matching: predicate) {
            return match
        }
    }
    return nil
}
