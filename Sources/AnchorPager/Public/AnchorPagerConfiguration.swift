import CoreGraphics

/// AnchorPager 的整体配置。
public struct AnchorPagerConfiguration: Sendable, Equatable {
    /// Header 相关配置。
    public var header: AnchorPagerHeaderConfiguration

    /// 分段栏相关配置。
    public var bar: AnchorPagerBarConfiguration

    /// 横向分页相关配置。
    public var paging: AnchorPagerPagingConfiguration

    /// 顶部 overscroll 处理模式。
    public var topOverscrollHandlingMode: AnchorPagerTopOverscrollHandlingMode

    /// 默认配置。
    public static let `default` = AnchorPagerConfiguration()

    /// 创建配置。
    public init(
        header: AnchorPagerHeaderConfiguration = .default,
        bar: AnchorPagerBarConfiguration = .default,
        paging: AnchorPagerPagingConfiguration = .default,
        topOverscrollHandlingMode: AnchorPagerTopOverscrollHandlingMode = .none
    ) {
        self.header = header
        self.bar = bar
        self.paging = paging
        self.topOverscrollHandlingMode = topOverscrollHandlingMode
    }
}

/// Header 高度和顶部行为配置。
public struct AnchorPagerHeaderConfiguration: Sendable, Equatable {
    /// Header 高度模式。
    public var heightMode: AnchorPagerHeaderHeightMode

    /// Header 顶部绘制行为。
    public var topBehavior: AnchorPagerHeaderTopBehavior

    /// 默认 Header 配置。
    public static let `default` = AnchorPagerHeaderConfiguration()

    /// 创建 Header 配置。
    public init(
        heightMode: AnchorPagerHeaderHeightMode = .automatic(min: 0, max: nil),
        topBehavior: AnchorPagerHeaderTopBehavior = .insideSafeArea
    ) {
        self.heightMode = heightMode
        self.topBehavior = topBehavior
    }
}

/// 分段栏基础配置。
public struct AnchorPagerBarConfiguration: Sendable, Equatable {
    /// 分段栏显式高度。为 `nil` 时使用内部分页适配器的自适应高度。
    public var height: CGFloat?

    /// 默认分段栏配置。
    public static let `default` = AnchorPagerBarConfiguration()

    /// 创建分段栏配置。
    ///
    /// - Parameter height: 可选显式高度；为 `nil` 时由内部分页适配器自适应。
    public init(height: CGFloat? = nil) {
        self.height = height
    }
}

/// 横向分页基础配置。
public struct AnchorPagerPagingConfiguration: Sendable, Equatable {
    /// 是否额外强保留当前页两侧已经按需加载的相邻页面。
    ///
    /// 开启不会主动创建尚未请求的页面；关闭时仍会保留当前页和切页事务中的来源页、目标页。
    public var keepsAdjacentPagesLoaded: Bool

    /// 默认分页配置。
    public static let `default` = AnchorPagerPagingConfiguration()

    /// 创建分页配置。
    public init(keepsAdjacentPagesLoaded: Bool = false) {
        self.keepsAdjacentPagesLoaded = keepsAdjacentPagesLoaded
    }
}

/// Header 高度模式。
public enum AnchorPagerHeaderHeightMode: Sendable, Equatable {
    /// 自动测量高度，并用可选最大值限制。
    case automatic(min: CGFloat, max: CGFloat?)

    /// 固定范围高度。
    case fixed(max: CGFloat, min: CGFloat)

    /// 最小和最大高度范围。
    case ranged(min: CGFloat, max: CGFloat)
}

/// Header 顶部绘制行为。
public enum AnchorPagerHeaderTopBehavior: Sendable, Equatable {
    /// Header 从本地顶部遮挡下方开始布局。
    case insideSafeArea

    /// Header 从容器 bounds 顶部开始布局。
    ///
    /// `headerFrame.height` 等于本地顶部遮挡加当前可见纯内容高度，
    /// 并保持 `barFrame.minY == headerFrame.maxY`。因此该模式与
    /// `insideSafeArea` 使用相同的分段栏和 child 内容基线，只改变
    /// Header 外框是否延伸到顶部系统区域。
    case extendsUnderTopSafeArea
}

/// Header 重新布局时的 offset 调整策略。
public enum AnchorPagerHeaderOffsetAdjustment: Sendable, Equatable {
    /// 保持当前视觉位置。
    case preserveVisualPosition

    /// 保持当前折叠进度。
    case preserveCollapseProgress

    /// 重置为展开状态。
    case resetToExpanded

    /// 重置为折叠状态。
    case resetToCollapsed
}

/// 顶部 overscroll 处理模式。
public enum AnchorPagerTopOverscrollHandlingMode: Sendable, Equatable {
    /// 不接管顶部 overscroll。
    case none

    /// 由容器滚动视图处理顶部 overscroll。
    case container

    /// 由当前 child 滚动视图处理顶部 overscroll。
    case child
}
