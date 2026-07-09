import CoreGraphics

/// AnchorPager 当前布局结果的只读快照。
public struct AnchorPagerLayoutContext: Sendable, Equatable {
    /// 当前有效选中索引。
    public let selectedIndex: Int?

    /// Header frame。
    public let headerFrame: CGRect

    /// 分段栏 frame。
    public let barFrame: CGRect

    /// Child 内容区域 frame。
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
