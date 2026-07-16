import AnchorPager
import Foundation
import UIKit

struct ExampleCompositionalScrollState: Equatable {
    private(set) var currentHorizontalOffset: CGFloat = 0
    private(set) var maximumHorizontalOffset: CGFloat = 0
    private(set) var leadingHorizontalItem = -1

    mutating func record(
        horizontalOffset: CGFloat,
        visibleItemIndexes: [Int]
    ) {
        let offset = max(0, horizontalOffset.isFinite ? horizontalOffset : 0)
        currentHorizontalOffset = offset
        maximumHorizontalOffset = max(maximumHorizontalOffset, offset)
        leadingHorizontalItem = visibleItemIndexes.min() ?? -1
    }

    mutating func resetHorizontalMetrics() {
        currentHorizontalOffset = 0
        maximumHorizontalOffset = 0
        leadingHorizontalItem = -1
    }

    var serializedValue: String {
        [
            "horizontalCurrent=\(formatted(currentHorizontalOffset))",
            "horizontalMax=\(formatted(maximumHorizontalOffset))",
            "leading=\(leadingHorizontalItem)"
        ].joined(separator: ";")
    }

    private func formatted(_ value: CGFloat) -> String {
        String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(value)
        )
    }
}

final class ExampleCompositionalPageViewController:
    UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate {
    private enum Section: Int, CaseIterable {
        case horizontal
        case vertical
    }

    private static let cellReuseIdentifier = "compositional-cell"
    private static let generationHeaderReuseIdentifier = "compositional-generation-header"
    private static let horizontalItemCount = 6
    private static let verticalItemCount = 18

    private let pageIdentifier: String
    private let generation: Int
    private let onAppearance: (String, String) -> Void
    private let onScrollStateChange: (String, CGFloat, CGFloat, CGFloat) -> Void
    private let ownershipProbe = UIButton(type: .custom)
    private var horizontalState = ExampleCompositionalScrollState()
    private var baselineScrollDelegateIdentifier: ObjectIdentifier?
    private var baselinePanDelegateIdentifier: ObjectIdentifier?
    private var needsScrollPresentationSample = false
    private var scrollPresentationDisplayLink: CADisplayLink?
    private lazy var scrollPresentationDisplayLinkTarget =
        ExampleCompositionalDisplayLinkTarget { [weak self] in
            self?.sampleScrollPresentationIfNeeded()
        }

    private lazy var collectionView: UICollectionView = {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .vertical
        let layout = UICollectionViewCompositionalLayout(
            sectionProvider: { [weak self] sectionIndex, environment in
                self?.makeSection(at: sectionIndex, environment: environment)
            },
            configuration: configuration
        )
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    var isScrollPresentationSamplingActive: Bool {
        scrollPresentationDisplayLink != nil
    }

    init(
        title: String,
        identifier: String,
        generation: Int,
        onAppearance: @escaping (String, String) -> Void,
        onScrollStateChange: @escaping (String, CGFloat, CGFloat, CGFloat) -> Void
    ) {
        pageIdentifier = identifier
        self.generation = generation
        self.onAppearance = onAppearance
        self.onScrollStateChange = onScrollStateChange
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        configureCollectionView()
        configureOwnershipProbe()
        anchorPagerScrollView = collectionView
        baselineScrollDelegateIdentifier = objectIdentifier(collectionView.delegate)
        baselinePanDelegateIdentifier = objectIdentifier(
            collectionView.panGestureRecognizer.delegate
        )
        updateOwnershipProbe()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.layoutIfNeeded()
        updateOwnershipProbe()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScrollPresentationSampling()
        onAppearance(pageIdentifier, "viewWillAppear")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppearance(pageIdentifier, "viewDidAppear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onAppearance(pageIdentifier, "viewWillDisappear")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopScrollPresentationSampling()
        onAppearance(pageIdentifier, "viewDidDisappear")
    }

    deinit {
        MainActor.assumeIsolated {
            scrollPresentationDisplayLink?.invalidate()
        }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        Section.allCases.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        switch Section(rawValue: section) {
        case .horizontal:
            Self.horizontalItemCount
        case .vertical:
            Self.verticalItemCount
        case nil:
            0
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: Self.cellReuseIdentifier,
            for: indexPath
        ) as? ExampleCompositionalCollectionViewCell else {
            preconditionFailure("组合布局示例 cell 注册错误")
        }

        switch Section(rawValue: indexPath.section) {
        case .horizontal:
            cell.configure(
                title: "组合横向内容 \(indexPath.item + 1)",
                accessibilityIdentifier: "compositional-horizontal-card-\(indexPath.item + 1)",
                backgroundColor: .secondarySystemBackground
            )
        case .vertical:
            cell.configure(
                title: "组合纵向内容 \(indexPath.item + 1)",
                accessibilityIdentifier: "compositional-vertical-card-\(indexPath.item + 1)",
                backgroundColor: .tertiarySystemBackground
            )
        case nil:
            break
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: Self.generationHeaderReuseIdentifier,
                for: indexPath
              ) as? ExampleCompositionalGenerationHeaderView else {
            preconditionFailure("组合布局示例 supplementary view 注册错误")
        }
        header.configure(generation: generation, pageIdentifier: pageIdentifier)
        return header
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        needsScrollPresentationSample = true
        updateOwnershipProbe()
    }

    func reportCurrentScrollState() {
        let distance = collectionView.contentOffset.y + collectionView.contentInset.top
        let maximumDistance = max(
            0,
            collectionView.contentSize.height
                + collectionView.contentInset.top
                + collectionView.contentInset.bottom
                - collectionView.bounds.height
        )
        onScrollStateChange(
            pageIdentifier,
            distance,
            max(0, -distance),
            max(0, distance - maximumDistance)
        )
    }

    func requestScrollPresentationSample() {
        needsScrollPresentationSample = true
    }

    private func configureCollectionView() {
        collectionView.accessibilityIdentifier = "compositional-collection-view"
        collectionView.backgroundColor = .systemBackground
        collectionView.showsVerticalScrollIndicator = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.bounces = true
        collectionView.alwaysBounceVertical = true
        collectionView.isScrollEnabled = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(
            ExampleCompositionalCollectionViewCell.self,
            forCellWithReuseIdentifier: Self.cellReuseIdentifier
        )
        collectionView.register(
            ExampleCompositionalGenerationHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: Self.generationHeaderReuseIdentifier
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureOwnershipProbe() {
        ownershipProbe.accessibilityIdentifier = "compositional-scroll-probe"
        ownershipProbe.accessibilityLabel = "组合布局滚动所有权"
        ownershipProbe.addTarget(
            self,
            action: #selector(resetHorizontalMetrics),
            for: .touchUpInside
        )
        ownershipProbe.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ownershipProbe)

        NSLayoutConstraint.activate([
            ownershipProbe.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            ownershipProbe.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ownershipProbe.widthAnchor.constraint(equalToConstant: 20),
            ownershipProbe.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func makeSection(
        at sectionIndex: Int,
        environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        switch Section(rawValue: sectionIndex) {
        case .horizontal:
            makeHorizontalSection(environment: environment)
        case .vertical:
            makeVerticalSection()
        case nil:
            nil
        }
    }

    private func makeHorizontalSection(
        environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalHeight(1)
            )
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.78),
                heightDimension: .absolute(180)
            ),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 16,
            leading: 16,
            bottom: 12,
            trailing: 16
        )
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        section.visibleItemsInvalidationHandler = { [weak self] items, offset, _ in
            let itemIndexes = items
                .filter { $0.representedElementCategory == .cell }
                .map(\.indexPath.item)
            self?.recordHorizontal(
                offsetX: offset.x,
                visibleItemIndexes: itemIndexes
            )
        }
        _ = environment
        return section
    }

    private func makeVerticalSection() -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalHeight(1)
            )
        )
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(72)
            ),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 20,
            trailing: 16
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(32)
            ),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]
        return section
    }

    private func recordHorizontal(
        offsetX: CGFloat,
        visibleItemIndexes: [Int]
    ) {
        horizontalState.record(
            horizontalOffset: offsetX,
            visibleItemIndexes: visibleItemIndexes
        )
        updateOwnershipProbe()
    }

    @objc private func resetHorizontalMetrics() {
        horizontalState.resetHorizontalMetrics()
        updateOwnershipProbe()
    }

    private func updateOwnershipProbe() {
        let scrollDelegateIsStable = objectIdentifier(collectionView.delegate)
            == baselineScrollDelegateIdentifier
        let panDelegateIsStable = objectIdentifier(
            collectionView.panGestureRecognizer.delegate
        ) == baselinePanDelegateIdentifier
        let hasVerticalRange = collectionView.contentSize.height
            + collectionView.adjustedContentInset.top
            + collectionView.adjustedContentInset.bottom
            > collectionView.bounds.height + 0.5
        ownershipProbe.accessibilityValue = [
            "scrollDelegate=\(scrollDelegateIsStable ? 1 : 0)",
            "panDelegate=\(panDelegateIsStable ? 1 : 0)",
            "bounces=\(collectionView.bounces ? 1 : 0)",
            "alwaysBounceVertical=\(collectionView.alwaysBounceVertical ? 1 : 0)",
            "isScrollEnabled=\(collectionView.isScrollEnabled ? 1 : 0)",
            "verticalRange=\(hasVerticalRange ? 1 : 0)",
            horizontalState.serializedValue
        ].joined(separator: ";")
    }

    private func startScrollPresentationSampling() {
        guard scrollPresentationDisplayLink == nil else { return }
        let displayLink = CADisplayLink(
            target: scrollPresentationDisplayLinkTarget,
            selector: #selector(ExampleCompositionalDisplayLinkTarget.displayLinkDidFire)
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

    private func objectIdentifier(_ object: AnyObject?) -> ObjectIdentifier? {
        object.map(ObjectIdentifier.init)
    }
}

private final class ExampleCompositionalCollectionViewCell: UICollectionViewCell {
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    func configure(
        title: String,
        accessibilityIdentifier: String,
        backgroundColor: UIColor
    ) {
        titleLabel.text = title
        contentView.backgroundColor = backgroundColor
        self.accessibilityIdentifier = accessibilityIdentifier
        accessibilityLabel = title
        isAccessibilityElement = true
    }
}

private final class ExampleCompositionalGenerationHeaderView: UICollectionReusableView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    func configure(generation: Int, pageIdentifier: String) {
        label.text = "页面代际 \(generation)"
        label.accessibilityIdentifier = "page-generation-\(generation)-\(pageIdentifier)"
    }
}

private final class ExampleCompositionalDisplayLinkTarget: NSObject {
    private let onDisplay: () -> Void

    init(onDisplay: @escaping () -> Void) {
        self.onDisplay = onDisplay
    }

    @objc func displayLinkDidFire() {
        onDisplay()
    }
}
