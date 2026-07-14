import CoreGraphics

/// AnchorPager 当前布局结果的只读快照。
public struct AnchorPagerLayoutContext: Sendable, Equatable {
    /// 当前有效选中索引。
    public let selectedIndex: Int?

    /// Header 在 pager 本地坐标中的最终可见 frame。
    ///
    /// 正常折叠只改变位置，不缩小 Header 高度；容器顶部回弹产生的
    /// presentation 位移已经包含在该 frame 中。
    public let headerFrame: CGRect

    /// 分段栏在 pager 本地坐标中的最终可见 frame。
    public let barFrame: CGRect

    /// Child 内容区域在 pager 本地坐标中的最终可见 frame。
    public let contentFrame: CGRect

    /// 创建布局快照。
    public init(
        selectedIndex: Int? = nil,
        headerFrame: CGRect = .zero,
        barFrame: CGRect = .zero,
        contentFrame: CGRect = .zero
    ) {
        self.selectedIndex = selectedIndex
        self.headerFrame = headerFrame
        self.barFrame = barFrame
        self.contentFrame = contentFrame
    }
}
