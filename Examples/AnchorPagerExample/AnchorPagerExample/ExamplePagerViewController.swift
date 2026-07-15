import AnchorPager
import UIKit

final class ExamplePagerViewController: UIViewController {
    private let launchArguments: [String]
    private let pagerViewController: AnchorPagerViewController
    private let appearanceRecorder: ExampleAppearanceRecorder?
    private var settingsItem: UIBarButtonItem?
    private var pageGeneration = 1
    private lazy var pages = makePages()
    private var didApplyInitialContainerState = false
    private weak var exampleHeaderView: ExampleHeaderView?
    private var expandedHeaderBaselineY: CGFloat?
    private var expandedHeaderBaselineHeight: CGFloat?
    private var expandedHeaderContentTopDistance: CGFloat?
    private var expandedBarBaselineY: CGFloat?
    private var collapsedBarBaselineY: CGFloat?
    private var collapsedContentBaselineY: CGFloat?
    private weak var scrollCoordinationStateControl: UIButton?
    private weak var selectionTraceControl: UIButton?
    private weak var rapidSelectionControl: UIButton?
    private weak var trackedCompetitionTraceView: UIView?
    private var selectionTrace = ExampleSelectionTrace()
    private var hasVisibleSelectionTerminal = false
    private var didTriggerTrackedScrollCompetition = false
    private var didTriggerSizeTransitionSelection = false
    private var scrollCoordinationState = ExampleScrollCoordinationState(
        page: "short",
        hasScrollTarget: true,
        mode: "container",
        collapseProgress: 0,
        containerTopInset: 0,
        headerHeight: 0,
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

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        launchArguments = arguments
        pagerViewController = AnchorPagerViewController(
            configuration: ExamplePagerViewController.initialConfiguration(
                arguments: arguments
            )
        )
        appearanceRecorder = arguments.contains("--anchorPagerAppearanceRecorder")
            ? ExampleAppearanceRecorder()
            : nil
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        let arguments = ProcessInfo.processInfo.arguments
        launchArguments = arguments
        pagerViewController = AnchorPagerViewController(
            configuration: ExamplePagerViewController.initialConfiguration(
                arguments: arguments
            )
        )
        appearanceRecorder = arguments.contains("--anchorPagerAppearanceRecorder")
            ? ExampleAppearanceRecorder()
            : nil
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "AnchorPager"
        view.backgroundColor = .systemBackground
        scrollCoordinationState.mode = identifier(
            for: pagerViewController.configuration.topOverscrollHandlingMode
        )
        installNavigationItem()
        installPager()
        installScrollCoordinationStateControl()
        installSelectionTraceControl()
        installRapidSelectionControlIfNeeded()
        installTrackedCompetitionTraceIfNeeded()
        if appearanceRecorder != nil {
            installAppearanceRecorderControl()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if pagerViewController.effectiveSelectedIndex != nil {
            hasVisibleSelectionTerminal = true
            updateRapidSelectionControl()
        }
        guard !didApplyInitialContainerState else { return }
        didApplyInitialContainerState = true
        if launchArguments.contains("--anchorPagerInitialContainerCollapsed") {
            pagerViewController.reloadHeaderLayout(offsetAdjustment: .resetToCollapsed)
        }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        guard !didTriggerSizeTransitionSelection,
              !sizeTransitionSelectionTargets.isEmpty else {
            return
        }
        didTriggerSizeTransitionSelection = true
        for index in sizeTransitionSelectionTargets {
            pagerViewController.setSelectedIndex(index, animated: true)
        }
    }

    private func installNavigationItem() {
        let pushItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.right.circle"),
            style: .plain,
            target: self,
            action: #selector(pushAnchorPagerExample)
        )
        pushItem.accessibilityLabel = "打开 AnchorPager"

        let settingsItem = makeSettingsItem()
        self.settingsItem = settingsItem
        let reloadItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(reloadPages)
        )
        reloadItem.accessibilityLabel = "重新加载页面"
        navigationItem.rightBarButtonItems = [
            pushItem,
            settingsItem,
            reloadItem
        ]
    }

    @objc private func reloadPages() {
        scrollCoordinationState.resetPresentationMetrics()
        resetHeaderGeometryBaseline()
        updateScrollCoordinationStateControl()
        pageGeneration += 1
        pages = makePages()
        pagerViewController.reloadData()
    }

    @objc private func resetAppearanceRecorder() {
        appearanceRecorder?.reset()
    }

    @objc private func pushAnchorPagerExample() {
        let viewController = ExamplePagerViewController()
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func makeSettingsItem() -> UIBarButtonItem {
        let image = UIImage(systemName: "gearshape")
        let item = UIBarButtonItem(
            title: image == nil ? "设置" : nil,
            image: image,
            primaryAction: nil,
            menu: makeSettingsMenu()
        )
        item.accessibilityLabel = "示例设置"
        return item
    }

    private func makeSettingsMenu() -> UIMenu {
        UIMenu(
            title: "示例设置",
            children: [
                makeHeaderTopBehaviorMenu(),
                makeTopOverscrollHandlingMenu()
            ]
        )
    }

    private func updateSettingsMenu() {
        settingsItem?.menu = makeSettingsMenu()
    }

    private func makeTopOverscrollHandlingMenu() -> UIMenu {
        let current = pagerViewController.configuration.topOverscrollHandlingMode
        let modes: [AnchorPagerTopOverscrollHandlingMode] = [.none, .container, .child]
        return UIMenu(
            title: "顶部回弹模式",
            children: modes.map { mode in
                UIAction(
                    title: title(for: mode),
                    state: current == mode ? .on : .off
                ) { [weak self] _ in
                    self?.setTopOverscrollHandlingMode(mode)
                }
            }
        )
    }

    private func setTopOverscrollHandlingMode(_ mode: AnchorPagerTopOverscrollHandlingMode) {
        pagerViewController.configuration.topOverscrollHandlingMode = mode
        scrollCoordinationState.mode = identifier(for: mode)
        scrollCoordinationState.resetPresentationMetrics()
        updateSettingsMenu()
        updateScrollCoordinationStateControl()
    }

    private func title(for mode: AnchorPagerTopOverscrollHandlingMode) -> String {
        switch mode {
        case .none:
            "关闭"
        case .container:
            "容器"
        case .child:
            "子页面"
        }
    }

    private func identifier(for mode: AnchorPagerTopOverscrollHandlingMode) -> String {
        switch mode {
        case .none:
            "none"
        case .container:
            "container"
        case .child:
            "child"
        }
    }

    private func makeHeaderTopBehaviorMenu() -> UIMenu {
        let current = pagerViewController.configuration.header.topBehavior
        return UIMenu(
            title: "Header 顶部行为",
            children: [
                UIAction(
                    title: title(for: .insideSafeArea),
                    state: current == .insideSafeArea ? .on : .off
                ) { [weak self] _ in
                    self?.setHeaderTopBehavior(.insideSafeArea)
                },
                UIAction(
                    title: title(for: .extendsUnderTopSafeArea),
                    state: current == .extendsUnderTopSafeArea ? .on : .off
                ) { [weak self] _ in
                    self?.setHeaderTopBehavior(.extendsUnderTopSafeArea)
                }
            ]
        )
    }

    private func setHeaderTopBehavior(_ behavior: AnchorPagerHeaderTopBehavior) {
        guard pagerViewController.configuration.header.topBehavior != behavior else { return }

        scrollCoordinationState.resetPresentationMetrics()
        resetHeaderGeometryBaseline()
        pagerViewController.configuration.header.topBehavior = behavior
        pagerViewController.reloadHeaderLayout(offsetAdjustment: .preserveVisualPosition)
        updateSettingsMenu()
        updateScrollCoordinationStateControl()
    }

    private func title(for behavior: AnchorPagerHeaderTopBehavior) -> String {
        switch behavior {
        case .insideSafeArea:
            "安全区内"
        case .extendsUnderTopSafeArea:
            "延伸到顶部"
        }
    }

    private func installPager() {
        pagerViewController.dataSource = self
        pagerViewController.delegate = self

        addChild(pagerViewController)
        pagerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pagerViewController.view)
        NSLayoutConstraint.activate([
            pagerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pagerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pagerViewController.didMove(toParent: self)

        pagerViewController.reloadData()
        pagerViewController.setSelectedIndex(initialSelectedIndex(), animated: false)
    }

    private func installScrollCoordinationStateControl() {
        let control = UIButton(type: .custom)
        control.accessibilityIdentifier = "scroll-coordination-state"
        control.accessibilityLabel = "纵向滚动协调状态"
        control.accessibilityValue = scrollCoordinationState.accessibilityValue
        control.addTarget(
            self,
            action: #selector(resetScrollCoordinationPresentationMetrics),
            for: .touchUpInside
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(control)
        scrollCoordinationStateControl = control

        NSLayoutConstraint.activate([
            control.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            control.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            control.widthAnchor.constraint(equalToConstant: 20),
            control.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func installSelectionTraceControl() {
        let control = UIButton(type: .custom)
        control.accessibilityIdentifier = "selection-event-trace"
        control.accessibilityLabel = "页面选择事件"
        control.accessibilityValue = selectionTrace.serializedValue
        control.addTarget(
            self,
            action: #selector(resetSelectionTrace),
            for: .touchUpInside
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(control)
        selectionTraceControl = control

        NSLayoutConstraint.activate([
            control.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            control.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 28
            ),
            control.widthAnchor.constraint(equalToConstant: 20),
            control.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func installRapidSelectionControlIfNeeded() {
        guard !rapidSelectionTargets.isEmpty || !rapidBarSelectionTargets.isEmpty else {
            return
        }
        let control = UIButton(type: .custom)
        control.accessibilityIdentifier = "rapid-selection-trigger"
        control.accessibilityLabel = "连续页面选择"
        control.addTarget(
            self,
            action: #selector(performRapidSelections),
            for: .touchUpInside
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(control)
        rapidSelectionControl = control
        updateRapidSelectionControl()

        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            control.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: 20),
            control.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func installTrackedCompetitionTraceIfNeeded() {
        guard argumentValue(after: "--anchorPagerTrackedScrollCompetition") != nil else {
            return
        }
        let traceView = UIView()
        traceView.accessibilityIdentifier = "tracked-competition-trace"
        traceView.accessibilityLabel = "跟踪滚动竞争状态"
        traceView.accessibilityValue = trackedCompetitionTraceValue(
            triggered: false,
            tracking: false,
            oldVisibleAfterPublic: false
        )
        traceView.isAccessibilityElement = true
        traceView.isUserInteractionEnabled = false
        traceView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(traceView)
        trackedCompetitionTraceView = traceView

        NSLayoutConstraint.activate([
            traceView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            traceView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 4
            ),
            traceView.widthAnchor.constraint(equalToConstant: 1),
            traceView.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    @objc private func resetSelectionTrace() {
        selectionTrace.reset()
        updateSelectionTraceControl()
    }

    @objc private func performRapidSelections() {
        guard hasVisibleSelectionTerminal else { return }
        for index in rapidSelectionTargets {
            pagerViewController.setSelectedIndex(index, animated: true)
        }
        for index in rapidBarSelectionTargets {
            activateBarItem(at: index)
        }
    }

    private func updateSelectionTraceControl() {
        selectionTraceControl?.accessibilityValue = selectionTrace.serializedValue
    }

    private func updateRapidSelectionControl() {
        rapidSelectionControl?.isEnabled = hasVisibleSelectionTerminal
        rapidSelectionControl?.accessibilityValue = [
            "ready=\(hasVisibleSelectionTerminal ? 1 : 0)",
            "apiTargets=\(rapidSelectionTargets.map(String.init).joined(separator: ","))",
            "barTargets=\(rapidBarSelectionTargets.map(String.init).joined(separator: ","))"
        ].joined(separator: ";")
    }

    private var rapidSelectionTargets: [Int] {
        argumentValue(after: "--anchorPagerRapidSelectionTargets")?
            .split(separator: ",")
            .compactMap { Int($0) } ?? []
    }

    private var rapidBarSelectionTargets: [Int] {
        argumentValue(after: "--anchorPagerRapidBarSelectionTargets")?
            .split(separator: ",")
            .compactMap { Int($0) } ?? []
    }

    private var sizeTransitionSelectionTargets: [Int] {
        argumentValue(after: "--anchorPagerSizeTransitionSelectionTargets")?
            .split(separator: ",")
            .compactMap { Int($0) } ?? []
    }

    private func activateBarItem(at index: Int) {
        guard pages.indices.contains(index),
              let title = pages[index].title else {
            return
        }
        pagerViewController.view.layoutIfNeeded()
        firstControl(in: pagerViewController.view) {
            $0.accessibilityLabel == title
                && $0.accessibilityTraits.contains(.button)
        }?.sendActions(for: .touchUpInside)
    }

    private func firstControl(
        in root: UIView,
        matching predicate: (UIControl) -> Bool
    ) -> UIControl? {
        if let control = root as? UIControl, predicate(control) {
            return control
        }
        for subview in root.subviews {
            if let control = firstControl(in: subview, matching: predicate) {
                return control
            }
        }
        return nil
    }

    private func argumentValue(after key: String) -> String? {
        guard let index = launchArguments.firstIndex(of: key),
              launchArguments.indices.contains(index + 1) else {
            return nil
        }
        return launchArguments[index + 1]
    }

    @objc private func resetScrollCoordinationPresentationMetrics() {
        scrollCoordinationState.resetPresentationMetrics()
        updateScrollCoordinationStateControl()
    }

    private func updateSelectedPageState(at index: Int) {
        guard pages.indices.contains(index) else { return }
        scrollCoordinationState.resetPresentationMetrics()
        scrollCoordinationState.page = pageIdentifier(at: index)

        if let page = pages[index] as? ExampleScrollPageViewController {
            scrollCoordinationState.hasScrollTarget = true
            page.reportCurrentScrollState()
        } else if pages[index] is ExampleHorizontalPageViewController {
            scrollCoordinationState.hasScrollTarget = true
            scrollCoordinationState.childDistance = 0
            updateScrollCoordinationStateControl()
        } else {
            scrollCoordinationState.hasScrollTarget = false
            scrollCoordinationState.childDistance = 0
            updateScrollCoordinationStateControl()
        }
    }

    private func updateChildScrollState(
        page: String,
        distance: CGFloat,
        topOverflow: CGFloat,
        bottomOverflow: CGFloat
    ) {
        guard page == scrollCoordinationState.page else { return }
        scrollCoordinationState.childDistance = max(0, distance)
        scrollCoordinationState.childTopOverflow = topOverflow
        scrollCoordinationState.maximumChildTopOverflow = max(
            scrollCoordinationState.maximumChildTopOverflow,
            topOverflow
        )
        scrollCoordinationState.childBottomOverflow = bottomOverflow
        scrollCoordinationState.maximumChildBottomOverflow = max(
            scrollCoordinationState.maximumChildBottomOverflow,
            bottomOverflow
        )
        recordMomentumSample(childDistance: max(0, distance))
        updateScrollCoordinationStateControl()
    }

    private func recordMomentumSample(childDistance: CGFloat) {
        let scrollView = pagerViewController.verticalScrollView
        let containerDistance = max(
            0,
            scrollView.contentOffset.y + scrollView.contentInset.top
        )
        let collapsedDistance = max(
            0,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.contentInset.top
                + scrollView.contentInset.bottom
        )
        scrollCoordinationState.recordMomentumSample(
            containerDistance: containerDistance,
            childDistance: childDistance,
            collapsedDistance: collapsedDistance
        )
    }

    private func recordContainerPresentation(_ context: AnchorPagerLayoutContext) {
        let scrollView = pagerViewController.verticalScrollView
        let expandedRawOffset = -scrollView.contentInset.top
        let maximumRawOffset = max(
            expandedRawOffset,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.contentInset.bottom
        )
        let topOverflow = max(0, expandedRawOffset - scrollView.contentOffset.y)
        let bottomOverflow = max(0, scrollView.contentOffset.y - maximumRawOffset)
        let isStable = topOverflow <= 0.5 && bottomOverflow <= 0.5
        scrollCoordinationState.containerTopInset = scrollView.contentInset.top

        if isStable {
            scrollCoordinationState.containerPresentation = 0
            scrollCoordinationState.barPresentation = 0
            if scrollCoordinationState.collapseProgress <= 0.01 {
                expandedHeaderBaselineY = context.headerFrame.minY
                expandedHeaderBaselineHeight = context.headerFrame.height
                expandedBarBaselineY = context.barFrame.minY
            }
            if scrollCoordinationState.collapseProgress >= 0.99 {
                collapsedBarBaselineY = context.barFrame.minY
                collapsedContentBaselineY = context.contentFrame.minY
            }
        }

        if let headerBaselineY = expandedHeaderBaselineY,
           let headerBaselineHeight = expandedHeaderBaselineHeight {
            scrollCoordinationState.recordHeaderGeometry(
                currentHeight: context.headerFrame.height,
                baselineHeight: headerBaselineHeight,
                currentMinY: context.headerFrame.minY,
                baselineMinY: headerBaselineY
            )
        } else {
            scrollCoordinationState.headerHeight = context.headerFrame.height
        }

        recordHeaderContentGeometry(isStable: isStable)

        if topOverflow > 0.5,
           let headerBaseline = expandedHeaderBaselineY,
           let barBaseline = expandedBarBaselineY {
            let presentation = context.headerFrame.minY - headerBaseline
            let barPresentation = context.barFrame.minY - barBaseline
            scrollCoordinationState.containerPresentation = presentation
            scrollCoordinationState.maximumContainerTopPresentation = max(
                scrollCoordinationState.maximumContainerTopPresentation,
                presentation
            )
            scrollCoordinationState.barPresentation = barPresentation
            scrollCoordinationState.maximumBarPresentation = max(
                scrollCoordinationState.maximumBarPresentation,
                abs(barPresentation)
            )
        } else if bottomOverflow > 0.5,
                  let contentBaseline = collapsedContentBaselineY,
                  let barBaseline = collapsedBarBaselineY {
            let presentation = context.contentFrame.minY - contentBaseline
            let barPresentation = context.barFrame.minY - barBaseline
            scrollCoordinationState.containerPresentation = presentation
            scrollCoordinationState.maximumContainerBottomPresentation = max(
                scrollCoordinationState.maximumContainerBottomPresentation,
                -presentation
            )
            scrollCoordinationState.barPresentation = barPresentation
            scrollCoordinationState.maximumBarPresentation = max(
                scrollCoordinationState.maximumBarPresentation,
                abs(barPresentation)
            )
        }
        requestVisibleMomentumSample()
        updateScrollCoordinationStateControl()
    }

    private func requestVisibleMomentumSample() {
        let selectedIndex = pagerViewController.selectedIndex
        guard pages.indices.contains(selectedIndex) else { return }
        if let page = pages[selectedIndex] as? ExampleScrollPageViewController {
            page.requestScrollPresentationSample()
        } else if pages[selectedIndex] is ExamplePlainPageViewController {
            recordMomentumSample(childDistance: 0)
        }
    }

    private func recordHeaderContentGeometry(isStable: Bool) {
        guard let exampleHeaderView else { return }
        let currentTopDistance = exampleHeaderView.contentTopDistance

        if isStable && scrollCoordinationState.collapseProgress <= 0.01 {
            expandedHeaderContentTopDistance = currentTopDistance
        }

        guard let baseline = expandedHeaderContentTopDistance else {
            scrollCoordinationState.headerContentTopDistance = currentTopDistance
            return
        }

        scrollCoordinationState.recordHeaderContentTopDistance(
            current: currentTopDistance,
            baseline: baseline
        )
    }

    private func resetHeaderGeometryBaseline() {
        expandedHeaderBaselineY = nil
        expandedHeaderBaselineHeight = nil
        expandedHeaderContentTopDistance = nil
        expandedBarBaselineY = nil
        collapsedBarBaselineY = nil
        collapsedContentBaselineY = nil
    }

    private func updateScrollCoordinationStateControl() {
        scrollCoordinationStateControl?.accessibilityValue =
            scrollCoordinationState.accessibilityValue
    }

    private func pageIdentifier(at index: Int) -> String {
        ["empty", "short", "long", "plain", "horizontal"][index]
    }

    private func installAppearanceRecorderControl() {
        guard let appearanceRecorder else { return }

        let control = UIButton(type: .custom)
        control.accessibilityIdentifier = "page-appearance-events"
        control.accessibilityLabel = "页面生命周期事件"
        control.accessibilityValue = appearanceRecorder.serializedEvents
        control.addTarget(self, action: #selector(resetAppearanceRecorder), for: .touchUpInside)
        control.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(control)

        appearanceRecorder.didUpdate = { [weak control] events in
            control?.accessibilityValue = events
        }

        NSLayoutConstraint.activate([
            control.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            control.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: 20),
            control.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func initialSelectedIndex() -> Int {
        let arguments = launchArguments
        guard let argumentIndex = arguments.firstIndex(of: "--anchorPagerInitialIndex"),
              arguments.indices.contains(argumentIndex + 1),
              let requestedIndex = Int(arguments[argumentIndex + 1]) else {
            return 1
        }
        return min(max(0, requestedIndex), pages.count - 1)
    }

    private static func initialConfiguration(
        arguments: [String]
    ) -> AnchorPagerConfiguration {
        var configuration = AnchorPagerConfiguration.default
        guard let argumentIndex = arguments.firstIndex(of: "--anchorPagerTopOverscrollMode"),
              arguments.indices.contains(argumentIndex + 1) else {
            return configuration
        }

        switch arguments[argumentIndex + 1] {
        case "none":
            configuration.topOverscrollHandlingMode = .none
        case "container":
            configuration.topOverscrollHandlingMode = .container
        case "child":
            configuration.topOverscrollHandlingMode = .child
        default:
            break
        }
        return configuration
    }

    var isAppearanceRecorderEnabledForTesting: Bool {
        appearanceRecorder != nil
    }

    var activeScrollPresentationSamplerCountForTesting: Int {
        pages.compactMap { $0 as? ExampleScrollPageViewController }
            .filter(\.isScrollPresentationSamplingActive)
            .count
    }

    func scrollPageForTesting(at index: Int) -> UIViewController? {
        guard pages.indices.contains(index),
              pages[index] is ExampleScrollPageViewController else {
            return nil
        }
        return pages[index]
    }

    func pageForTesting(at index: Int) -> UIViewController? {
        guard pages.indices.contains(index) else { return nil }
        return pages[index]
    }

    private func makePages() -> [UIViewController] {
        [
            ExampleScrollPageViewController(
                title: "无内容页",
                identifier: "empty",
                rows: 0,
                generation: pageGeneration,
                appearanceRecorder: appearanceRecorder,
                onScrollStateChange: makeScrollStateHandler(),
                onTrackedScroll: makeTrackedScrollHandler()
            ),
            ExampleScrollPageViewController(
                title: "短页",
                identifier: "short",
                rows: 6,
                generation: pageGeneration,
                appearanceRecorder: appearanceRecorder,
                onScrollStateChange: makeScrollStateHandler(),
                onTrackedScroll: makeTrackedScrollHandler()
            ),
            ExampleScrollPageViewController(
                title: "长页",
                identifier: "long",
                rows: 30,
                generation: pageGeneration,
                appearanceRecorder: appearanceRecorder,
                onScrollStateChange: makeScrollStateHandler(),
                onTrackedScroll: makeTrackedScrollHandler()
            ),
            ExamplePlainPageViewController(
                title: "无滚动页",
                identifier: "plain",
                appearanceRecorder: appearanceRecorder
            ),
            ExampleHorizontalPageViewController(
                title: "横向业务页",
                identifier: "horizontal",
                appearanceRecorder: appearanceRecorder
            )
        ]
    }

    private func makeScrollStateHandler() -> (String, CGFloat, CGFloat, CGFloat) -> Void {
        { [weak self] page, distance, topOverflow, bottomOverflow in
            self?.updateChildScrollState(
                page: page,
                distance: distance,
                topOverflow: topOverflow,
                bottomOverflow: bottomOverflow
            )
        }
    }

    private func makeTrackedScrollHandler() -> () -> Void {
        { [weak self] in
            self?.performTrackedScrollCompetitionIfNeeded()
        }
    }

    private func performTrackedScrollCompetitionIfNeeded() {
        guard !didTriggerTrackedScrollCompetition,
              let action = argumentValue(
                after: "--anchorPagerTrackedScrollCompetition"
              ) else {
            return
        }
        let visibleIndex = pagerViewController.effectiveSelectedIndex
            ?? pagerViewController.selectedIndex
        let oldVisiblePage = pages.indices.contains(visibleIndex)
            ? pages[visibleIndex]
            : nil
        trackedCompetitionTraceView?.accessibilityValue = trackedCompetitionTraceValue(
            triggered: true,
            tracking: true,
            oldVisibleAfterPublic: false
        )
        didTriggerTrackedScrollCompetition = true
        switch action {
        case "reload":
            prepareTrackedReloadGeneration()
            pagerViewController.reloadData()
        case "layout":
            pagerViewController.reloadHeaderLayout(
                offsetAdjustment: .preserveVisualPosition
            )
        case "reload-layout":
            prepareTrackedReloadGeneration()
            pagerViewController.reloadData()
            pagerViewController.reloadHeaderLayout(
                offsetAdjustment: .preserveVisualPosition
            )
        default:
            break
        }
        trackedCompetitionTraceView?.accessibilityValue = trackedCompetitionTraceValue(
            triggered: true,
            tracking: true,
            oldVisibleAfterPublic: oldVisiblePage?.viewIfLoaded?.window != nil
        )
    }

    private func trackedCompetitionTraceValue(
        triggered: Bool,
        tracking: Bool,
        oldVisibleAfterPublic: Bool
    ) -> String {
        [
            "triggered=\(triggered ? 1 : 0)",
            "tracking=\(tracking ? 1 : 0)",
            "oldVisibleAfterPublic=\(oldVisibleAfterPublic ? 1 : 0)"
        ].joined(separator: ";")
    }

    private func prepareTrackedReloadGeneration() {
        scrollCoordinationState.resetPresentationMetrics()
        resetHeaderGeometryBaseline()
        updateScrollCoordinationStateControl()
        pageGeneration += 1
        pages = makePages()
    }
}

private final class ExampleAppearanceRecorder {
    var didUpdate: ((String) -> Void)? {
        didSet {
            didUpdate?(serializedEvents)
        }
    }

    private var events: [String] = []

    var serializedEvents: String {
        events.joined(separator: "|")
    }

    func record(page: String, callback: String) {
        events.append("\(page).\(callback)")
        didUpdate?(serializedEvents)
    }

    func reset() {
        events.removeAll(keepingCapacity: true)
        didUpdate?(serializedEvents)
    }
}

extension ExamplePagerViewController: AnchorPagerViewControllerDataSource {
    func numberOfViewControllers(in pagerViewController: AnchorPagerViewController) -> Int {
        pages.count
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        titleForViewControllerAt index: Int
    ) -> String {
        pages[index].title ?? "无标题"
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        viewControllerAt index: Int
    ) -> UIViewController {
        pages[index]
    }

    func headerContent(in pagerViewController: AnchorPagerViewController) -> AnchorPagerHeaderContent {
        let headerView = ExampleHeaderView()
        exampleHeaderView = headerView
        return .view(headerView)
    }
}

extension ExamplePagerViewController: AnchorPagerViewControllerDelegate {
    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didSelectViewControllerAt index: Int
    ) {
        selectionTrace.record(index: index)
        updateSelectionTraceControl()
        if view.window != nil {
            hasVisibleSelectionTerminal = true
            updateRapidSelectionControl()
        }
        updateSelectedPageState(at: index)
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateHeaderCollapseProgress progress: CGFloat
    ) {
        scrollCoordinationState.collapseProgress = progress
        updateScrollCoordinationStateControl()
    }

    func pagerViewController(
        _ pagerViewController: AnchorPagerViewController,
        didUpdateLayout context: AnchorPagerLayoutContext
    ) {
        recordContainerPresentation(context)
    }
}

private final class ExampleHeaderView: UIView {
    private let stackView = UIStackView()

    var contentTopDistance: CGFloat {
        layoutIfNeeded()
        return stackView.frame.minY - bounds.minY
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .systemBlue

        let titleLabel = UILabel()
        titleLabel.text = "AnchorPager Example"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = .white

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Header UIView、显式 scroll view、无 scroll view child"
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .white
        subtitleLabel.numberOfLines = 0

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor,
                constant: -20
            )
        ])
    }
}

private final class ExampleScrollPageViewController: UIViewController, UIScrollViewDelegate {
    private let pageTitle: String
    private let pageIdentifier: String
    private let rows: Int
    private let generation: Int
    private let appearanceRecorder: ExampleAppearanceRecorder?
    private let onScrollStateChange: (String, CGFloat, CGFloat, CGFloat) -> Void
    private let onTrackedScroll: () -> Void
    private let scrollView = UIScrollView()
    private let appearanceLabel = UILabel()
    private var willAppearCount = 0
    private var didAppearCount = 0
    private var willDisappearCount = 0
    private var didDisappearCount = 0
    private var needsScrollPresentationSample = false
    private var scrollPresentationDisplayLink: CADisplayLink?
    private lazy var scrollPresentationDisplayLinkTarget = ExampleDisplayLinkTarget {
        [weak self] in
        self?.sampleScrollPresentationIfNeeded()
    }

    var isScrollPresentationSamplingActive: Bool {
        scrollPresentationDisplayLink != nil
    }

    init(
        title: String,
        identifier: String,
        rows: Int,
        generation: Int,
        appearanceRecorder: ExampleAppearanceRecorder?,
        onScrollStateChange: @escaping (String, CGFloat, CGFloat, CGFloat) -> Void,
        onTrackedScroll: @escaping () -> Void
    ) {
        self.pageTitle = title
        self.pageIdentifier = identifier
        self.rows = rows
        self.generation = generation
        self.appearanceRecorder = appearanceRecorder
        self.onScrollStateChange = onScrollStateChange
        self.onTrackedScroll = onTrackedScroll
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        anchorPagerScrollView = scrollView
        scrollView.bounces = true
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        installScrollView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScrollPresentationSampling()
        willAppearCount += 1
        updateAppearanceLabel()
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewWillAppear")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppearCount += 1
        updateAppearanceLabel()
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewDidAppear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        willDisappearCount += 1
        updateAppearanceLabel()
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewWillDisappear")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopScrollPresentationSampling()
        didDisappearCount += 1
        updateAppearanceLabel()
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewDidDisappear")
    }

    deinit {
        MainActor.assumeIsolated {
            scrollPresentationDisplayLink?.invalidate()
        }
    }

    private func installScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        let generationLabel = UILabel()
        generationLabel.text = "页面代际 \(generation)"
        generationLabel.accessibilityIdentifier = "page-generation-\(generation)-\(pageIdentifier)"
        generationLabel.font = .preferredFont(forTextStyle: .caption1)
        generationLabel.textColor = .secondaryLabel
        stackView.addArrangedSubview(generationLabel)

        appearanceLabel.text = "页面生命周期"
        appearanceLabel.accessibilityIdentifier = "page-appearance-\(pageIdentifier)"
        appearanceLabel.font = .preferredFont(forTextStyle: .caption2)
        appearanceLabel.textColor = .tertiaryLabel
        stackView.addArrangedSubview(appearanceLabel)
        updateAppearanceLabel()

        for row in 0..<rows {
            let label = UILabel()
            label.text = "\(pageTitle) - \(row + 1)"
            if row == 0 {
                label.accessibilityIdentifier = "scroll-page-first-row"
            }
            label.font = .preferredFont(forTextStyle: .body)
            label.textColor = .label
            label.backgroundColor = .secondarySystemBackground
            label.layer.cornerRadius = 6
            label.layer.masksToBounds = true
            stackView.addArrangedSubview(label)
            label.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func updateAppearanceLabel() {
        appearanceLabel.accessibilityValue = [
            "willAppear=\(willAppearCount)",
            "didAppear=\(didAppearCount)",
            "willDisappear=\(willDisappearCount)",
            "didDisappear=\(didDisappearCount)"
        ].joined(separator: ",")
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        needsScrollPresentationSample = true
        if scrollView.isTracking {
            onTrackedScroll()
        }
    }

    func reportCurrentScrollState() {
        let distance = scrollView.contentOffset.y + scrollView.contentInset.top
        let maximumDistance = max(
            0,
            scrollView.contentSize.height
                + scrollView.contentInset.top
                + scrollView.contentInset.bottom
                - scrollView.bounds.height
        )
        let topOverflow = max(0, -distance)
        let bottomOverflow = max(0, distance - maximumDistance)
        onScrollStateChange(
            pageIdentifier,
            distance,
            topOverflow,
            bottomOverflow
        )
    }

    func requestScrollPresentationSample() {
        needsScrollPresentationSample = true
    }

    private func startScrollPresentationSampling() {
        guard scrollPresentationDisplayLink == nil else { return }
        let displayLink = CADisplayLink(
            target: scrollPresentationDisplayLinkTarget,
            selector: #selector(ExampleDisplayLinkTarget.displayLinkDidFire)
        )
        displayLink.add(to: .main, forMode: .common)
        scrollPresentationDisplayLink = displayLink
    }

    private func stopScrollPresentationSampling() {
        scrollPresentationDisplayLink?.invalidate()
        scrollPresentationDisplayLink = nil
        needsScrollPresentationSample = false
    }

    private func sampleScrollPresentationIfNeeded() {
        guard needsScrollPresentationSample else { return }
        needsScrollPresentationSample = false
        reportCurrentScrollState()
    }
}

private final class ExampleHorizontalPageViewController:
    UIViewController,
    UIScrollViewDelegate {
    private let pageIdentifier: String
    private let appearanceRecorder: ExampleAppearanceRecorder?
    private let horizontalScrollView = UIScrollView()
    private let ownershipProbe = UIView()
    private var baselineScrollDelegateIdentifier: ObjectIdentifier?
    private var baselinePanDelegateIdentifier: ObjectIdentifier?

    init(
        title: String,
        identifier: String,
        appearanceRecorder: ExampleAppearanceRecorder?
    ) {
        pageIdentifier = identifier
        self.appearanceRecorder = appearanceRecorder
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        installHorizontalScrollView()
        installLowerPagingRegion()

        horizontalScrollView.delegate = self
        horizontalScrollView.bounces = true
        horizontalScrollView.alwaysBounceVertical = false
        horizontalScrollView.isScrollEnabled = true
        anchorPagerScrollView = horizontalScrollView
        baselineScrollDelegateIdentifier = objectIdentifier(
            horizontalScrollView.delegate
        )
        baselinePanDelegateIdentifier = objectIdentifier(
            horizontalScrollView.panGestureRecognizer.delegate
        )
        updateOwnershipProbe()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        horizontalScrollView.layoutIfNeeded()
        updateOwnershipProbe()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewWillAppear")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewDidAppear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewWillDisappear")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewDidDisappear")
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateOwnershipProbe()
    }

    private func installHorizontalScrollView() {
        horizontalScrollView.accessibilityIdentifier = "horizontal-business-scroll"
        horizontalScrollView.showsHorizontalScrollIndicator = true
        horizontalScrollView.showsVerticalScrollIndicator = false
        horizontalScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(horizontalScrollView)

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        horizontalScrollView.addSubview(stackView)

        for index in 1...4 {
            let card = UILabel()
            card.text = "横向业务内容 \(index)"
            card.textAlignment = .center
            card.font = .preferredFont(forTextStyle: .headline)
            card.textColor = .label
            card.backgroundColor = .secondarySystemBackground
            card.layer.cornerRadius = 12
            card.layer.masksToBounds = true
            card.widthAnchor.constraint(equalToConstant: 240).isActive = true
            stackView.addArrangedSubview(card)
        }

        NSLayoutConstraint.activate([
            horizontalScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            horizontalScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            horizontalScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            horizontalScrollView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.46),

            stackView.leadingAnchor.constraint(
                equalTo: horizontalScrollView.contentLayoutGuide.leadingAnchor,
                constant: 16
            ),
            stackView.trailingAnchor.constraint(
                equalTo: horizontalScrollView.contentLayoutGuide.trailingAnchor,
                constant: -16
            ),
            stackView.topAnchor.constraint(
                equalTo: horizontalScrollView.contentLayoutGuide.topAnchor,
                constant: 16
            ),
            stackView.bottomAnchor.constraint(
                equalTo: horizontalScrollView.contentLayoutGuide.bottomAnchor,
                constant: -16
            ),
            stackView.heightAnchor.constraint(
                equalTo: horizontalScrollView.frameLayoutGuide.heightAnchor,
                constant: -32
            )
        ])
    }

    private func installLowerPagingRegion() {
        let region = UIView()
        region.accessibilityIdentifier = "horizontal-pageboy-hit-region"
        region.accessibilityLabel = "页面横向分页区域"
        region.isAccessibilityElement = true
        region.backgroundColor = .tertiarySystemBackground
        region.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(region)

        let label = UILabel()
        label.text = "在此区域左右滑动切换页面"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        region.addSubview(label)

        ownershipProbe.accessibilityIdentifier = "horizontal-business-probe"
        ownershipProbe.accessibilityLabel = "横向业务滚动所有权"
        ownershipProbe.isAccessibilityElement = true
        ownershipProbe.isUserInteractionEnabled = false
        ownershipProbe.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ownershipProbe)

        NSLayoutConstraint.activate([
            region.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            region.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            region.topAnchor.constraint(equalTo: horizontalScrollView.bottomAnchor),
            region.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.centerXAnchor.constraint(equalTo: region.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: region.centerYAnchor),
            ownershipProbe.trailingAnchor.constraint(equalTo: region.trailingAnchor),
            ownershipProbe.bottomAnchor.constraint(equalTo: region.bottomAnchor),
            ownershipProbe.widthAnchor.constraint(equalToConstant: 1),
            ownershipProbe.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func updateOwnershipProbe() {
        let scrollDelegateIsStable = objectIdentifier(horizontalScrollView.delegate)
            == baselineScrollDelegateIdentifier
        let panDelegateIsStable = objectIdentifier(
            horizontalScrollView.panGestureRecognizer.delegate
        ) == baselinePanDelegateIdentifier
        let hasHorizontalRange = horizontalScrollView.contentSize.width
            + horizontalScrollView.adjustedContentInset.left
            + horizontalScrollView.adjustedContentInset.right
            > horizontalScrollView.bounds.width + 0.5
        ownershipProbe.accessibilityValue = [
            "scrollDelegate=\(scrollDelegateIsStable ? 1 : 0)",
            "panDelegate=\(panDelegateIsStable ? 1 : 0)",
            "bounces=\(horizontalScrollView.bounces ? 1 : 0)",
            "alwaysBounceVertical=\(horizontalScrollView.alwaysBounceVertical ? 1 : 0)",
            "isScrollEnabled=\(horizontalScrollView.isScrollEnabled ? 1 : 0)",
            "horizontalRange=\(hasHorizontalRange ? 1 : 0)"
        ].joined(separator: ";")
    }

    private func objectIdentifier(_ object: AnyObject?) -> ObjectIdentifier? {
        object.map(ObjectIdentifier.init)
    }
}

private final class ExampleDisplayLinkTarget: NSObject {
    private let onDisplay: () -> Void

    init(onDisplay: @escaping () -> Void) {
        self.onDisplay = onDisplay
    }

    @objc func displayLinkDidFire() {
        onDisplay()
    }
}

private final class ExamplePlainPageViewController: UIViewController {
    private let pageTitle: String
    private let pageIdentifier: String
    private let appearanceRecorder: ExampleAppearanceRecorder?

    init(
        title: String,
        identifier: String,
        appearanceRecorder: ExampleAppearanceRecorder?
    ) {
        self.pageTitle = title
        self.pageIdentifier = identifier
        self.appearanceRecorder = appearanceRecorder
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewWillAppear")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewDidAppear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewWillDisappear")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        appearanceRecorder?.record(page: pageIdentifier, callback: "viewDidDisappear")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .tertiarySystemBackground

        let rootProbe = UIView()
        rootProbe.accessibilityIdentifier = "plain-page-root"
        rootProbe.isAccessibilityElement = true
        rootProbe.isUserInteractionEnabled = false
        rootProbe.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(rootProbe, at: 0)

        let label = UILabel()
        label.text = pageTitle
        label.accessibilityIdentifier = "plain-page-content"
        label.font = .preferredFont(forTextStyle: .title3)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            rootProbe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootProbe.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootProbe.topAnchor.constraint(equalTo: view.topAnchor),
            rootProbe.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
