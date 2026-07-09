import UIKit

/// UIKit 嵌套分页容器入口。
@MainActor
open class AnchorPagerViewController: UIViewController {
    /// 提供页面、标题和 Header 内容的数据源。
    public weak var dataSource: AnchorPagerViewControllerDataSource?

    /// 接收页面选择、Header 折叠和布局更新事件的代理。
    public weak var delegate: AnchorPagerViewControllerDelegate?

    /// 容器配置。
    public var configuration: AnchorPagerConfiguration

    /// 当前选中索引。空页时保持 0。
    public private(set) var selectedIndex: Int = 0

    /// 当前有效选中索引。空页时为 nil。
    public var effectiveSelectedIndex: Int? {
        pageCount > 0 ? selectedIndex : nil
    }

    /// AnchorPager 管理的纵向容器滚动视图。
    public let verticalScrollView = UIScrollView()

    private var pageCount = 0

    /// 创建 AnchorPager 容器。
    public init(configuration: AnchorPagerConfiguration = .default) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "init")
    }

    /// 从 storyboard 或 nib 创建 AnchorPager 容器。
    public required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "init")
    }

    deinit {
        MainActor.assumeIsolated {
            AnchorPagerLogger.log(.info, category: .lifecycle, event: "deinit")
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        installVerticalScrollViewIfNeeded()
    }

    /// 重新加载页面、标题和 Header 数据。
    public func reloadData() {
        AnchorPagerLogger.log(.info, category: .lifecycle, event: "reloadData.begin")

        let requestedCount = dataSource?.numberOfViewControllers(in: self) ?? 0
        if requestedCount < 0 {
            AnchorPagerAssertions.failure("AnchorPager page count must not be negative.")
            pageCount = 0
        } else {
            pageCount = requestedCount
        }

        if pageCount == 0 {
            selectedIndex = 0
        } else if selectedIndex >= pageCount {
            selectedIndex = pageCount - 1
        }

        AnchorPagerLogger.log(.info, category: .lifecycle, event: "reloadData.end")
    }

    /// 设置当前选中页面。
    public func setSelectedIndex(_ selectedIndex: Int, animated: Bool) {
        AnchorPagerLogger.log(.info, category: .paging, event: "setSelectedIndex.request")

        guard selectedIndex >= 0, selectedIndex < pageCount else {
            AnchorPagerLogger.log(.debug, category: .paging, event: "setSelectedIndex.outOfRange")
            AnchorPagerAssertions.failure("AnchorPager selectedIndex is out of range.")
            return
        }

        self.selectedIndex = selectedIndex
        AnchorPagerLogger.log(.info, category: .paging, event: "setSelectedIndex.commit")
        delegate?.pagerViewController(self, didSelectViewControllerAt: selectedIndex)
    }

    /// 重新测量并布局 Header。
    public func reloadHeaderLayout(
        offsetAdjustment: AnchorPagerHeaderOffsetAdjustment = .preserveVisualPosition
    ) {
        AnchorPagerLogger.log(.info, category: .layout, event: "reloadHeaderLayout")
    }

    private func installVerticalScrollViewIfNeeded() {
        guard verticalScrollView.superview == nil else { return }

        verticalScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(verticalScrollView)
        NSLayoutConstraint.activate([
            verticalScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            verticalScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            verticalScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            verticalScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
