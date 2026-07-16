# 横向业务页面纵向滚动目标语义修复设计

**日期：** 2026-07-16

**状态：** 已确认，实施与验收进行中

**适用范围：** `UIViewController.anchorPagerScrollView` 接入语义、默认 scroll lookup opt-out、Example 横向业务页、Store committed scroll target、managed inset、纵向 binding 与 simultaneous pair。

**实施计划：** `docs/superpowers/plans/2026-07-16-horizontal-only-page-vertical-scroll-target.md`

## 问题与证据

Example 第五页上半区域包含一个只承担横向业务内容的 `UIScrollView`。当前页面在 `viewDidLoad()` 中显式执行：

```swift
anchorPagerScrollView = horizontalScrollView
```

这会形成以下真实数据流：

```text
ExampleHorizontalPageViewController.horizontalScrollView
  -> UIViewController.anchorPagerScrollView
  -> AnchorPagerPageStateStore.identity.scrollView
  -> committedCurrentScrollView
  -> ManagedInsetCoordinator ownership / offset snapshot
  -> ScrollCoordinator.bindCommittedChild
  -> AnchorPagerContainerScrollView.bindCurrentChildPan
  -> container 与横向业务 pan 的 simultaneous pair
```

`AnchorPagerChildScrollBinding` 与 `AnchorPagerScrollCoordinator` 只读取 pan 的纵向 translation/velocity；因此横向拖动中正常存在的微小纵向分量会被错误地当成纵向协调输入，带动公开的 `verticalScrollView`、Header 折叠或边界 presentation。

根因不是全局方向判定缺失，而是横向业务视图被错误登记为纵向协调目标。一旦登记，即使增加方向锁，它仍会错误参与 managed inset、snapshot、top/bottom owner、synthetic deceleration 和资源绑定。

## 目标

1. 明确 `anchorPagerScrollView` 只表示页面参与 AnchorPager 纵向协调的 scroll target。
2. 横向业务页保留真实横向 `UIScrollView`，但对 AnchorPager 提交 nil 纵向目标。
3. 横向业务拖动不再带动 `verticalScrollView`、Header collapse 或纵向边界 presentation。
4. 业务 scroll delegate、pan delegate、`bounces`、`alwaysBounceVertical` 与 `isScrollEnabled` 保持业务所有。
5. 不扩大 Public API，不改变 Tabman/Pageboy containment、Store generation、ScrollCoordinator 或手势优先级架构。

## 非目标

1. 本修复不声明业务横向 `UIScrollView` 自动优先于 Pageboy；该同向嵌套 winner 仍遵守 v0.7 已验证的限制。
2. 不增加全局横纵方向锁，不修改 `AnchorPagerContainerScrollView` 的 simultaneous 规则。
3. 不依据 `contentSize`、`alwaysBounceVertical`、scroll indicator 或运行时 velocity 自动推断目标轴向。
4. 不新增 `anchorPagerVerticalScrollView` 等 Public API alias，也不重命名现有 symbol。
5. 不修改真实纵向页面、混合页面中显式登记的纵向父 scroll 或 plain page 的 nil target 行为。

## 采用方案

### 纵向目标契约

`anchorPagerScrollView` 的语义固定为：AnchorPager 用于 Header 折叠、纵向 handoff、managed inset、offset snapshot 和边界 owner 的页面纵向滚动目标。

接入规则：

1. 页面只有一个纵向 scroll：可显式设置，或依赖默认确定性 lookup。
2. 页面有纵向父 scroll 与嵌套横向业务 scroll：只登记纵向父 scroll。
3. 页面只有横向业务 scroll：设置 `anchorPagerUsesDefaultScrollViewLookup = false`，不设置 `anchorPagerScrollView`；结果为 original Pageboy page + nil scroll target。
4. 页面没有任何 scroll：保持既有 plain direct page + nil target。

默认 lookup 继续保持 axis-agnostic 的确定性深度优先规则。它无法在首次 layout 前可靠判断动态内容的最终轴向，也不能推断混合轴页面的业务意图；因此横向-only 页面必须显式 opt out，框架不引入启发式过滤。

### Example 修复

`ExampleHorizontalPageViewController.viewDidLoad()` 在安装业务横向 scroll 后执行：

```swift
anchorPagerUsesDefaultScrollViewLookup = false
```

并删除：

```swift
anchorPagerScrollView = horizontalScrollView
```

由于 Store 在页面首次按需加载后解析目标，这一声明会让该页提交 nil committed scroll target。随后：

- ManagedInsetCoordinator 不接管横向业务 scroll；
- PageStateStore 不保存它的纵向 distance snapshot；
- ScrollCoordinator 绑定 nil child；
- ContainerScrollView 清除 current child simultaneous pair；
- 顶部 `.child` 在该页不可用且不回退；
- plain/container 既有纵向物理与 Pageboy containment 保持不变。

Example 的 `hasScrollTarget` 探针必须改为 false，不能继续把横向业务 scroll 报告为纵向 target。

## 方案否决

### 全局方向锁

方向锁只能在一次手势中屏蔽部分纵向位移，不能归还已经错误建立的 inset、snapshot、boundary、deceleration 和 binding ownership；还会改变所有真实纵向页的斜向手势语义，因此不作为本问题修复。

### 根据 contentSize 自动过滤

`contentSize` 在首次 discovery 时可能尚未完成 layout，短纵向内容可能没有垂直 range，动态内容和混合轴页面也会在运行时变化。用它决定 scroll target 会让 generation、reload 和尺寸变化依赖不稳定时序。

### 新增 Public API alias

现有 `anchorPagerScrollView` 已能表达纵向目标，配合 `anchorPagerUsesDefaultScrollViewLookup` 可以完整表示横向-only 页面。新增 alias 会扩大 API、增加两份事实和迁移成本，当前没有必要。

## 影响范围

- **Public API：** symbol 不变；补充 DocC 与 README 语义。
- **内部分层：** 不修改生产 framework；Store 对 Example 第五页从真实 scroll target 转为 nil。
- **Containment/lifecycle：** original controller 继续由 Pageboy 唯一 containment；appearance、selection 与 generation 不变。
- **Scroll discovery：** 复用现有 opt-out；不修改确定性 lookup 算法。
- **Inset/snapshot：** 横向业务 scroll 不再参与；真实纵向页不变。
- **Gesture/overscroll：** 不新增 relation、guard 或方向锁；该页不再建立 container/current-child simultaneous pair。
- **日志：** 复用既有一次性 `scroll.target.none`，不新增热路径日志。
- **Example/UI：** 修正第五页 probe，并增加横向命中区域的真实 UI 回归。
- **文档：** 同步 README、architecture、requirements、task-list、v0.7 规格/计划、roadmap 与 AGENTS 索引。

## TDD 与验收

### Example 单元 RED

把现有 `horizontalBusinessPageIsFifthAndKeepsDelegateConfiguration()` 收紧为：

```swift
#expect(page.anchorPagerUsesDefaultScrollViewLookup == false)
#expect(page.anchorPagerDefaultScrollView == nil)
#expect(page.anchorPagerScrollView == nil)
```

同时继续证明业务横向 range 存在，scroll/pan delegate identity 与 bounce/enable 配置稳定。旧实现会因默认 lookup 仍启用且显式 target 非 nil 精确失败。

### Example 真实 UI RED

新增 `testHorizontalBusinessRegionDoesNotDriveVerticalContainer()`：

1. 以第五页启动，先确认 `page == horizontal`、`hasScrollTarget == false`、Header 展开、presentation 为零。
2. 在 `horizontal-business-scroll` 命中区域执行带少量纵向分量的真实横向 drag。
3. 断言页面仍为 horizontal，`collapse < 0.01`、`headerCollapse < 0.5 pt`、container/child presentation max 均小于 `0.5 pt`。
4. 断言业务 ownership probe 的 delegate/configuration 字段保持全 1 基线。

该测试不把“业务横向 scroll 一定赢过 Pageboy”作为本修复通过条件，避免混入 v0.7 已明确不支持的另一项能力。

### 相邻与完整门禁

聚焦运行 Example unit、新 UI 与 plain/current-child rebind 相邻回归；最终运行 Framework、Example 全量、generic Simulator build、xcresult 诊断、静态 ownership 扫描和 `git diff --check`。

## 架构停机条件

出现以下任一情况必须停止实现并重新设计：

1. 需要修改 Framework ScrollCoordinator/ContainerScrollView 才能让横向页提交 nil target。
2. 需要设置或替换业务 scroll/pan delegate、`isScrollEnabled` 或 bounce 配置。
3. 需要通过 contentSize/velocity 启发式在框架内自动判断轴向。
4. 需要改变 Pageboy containment、selection terminal、Store generation 或 Public API。
5. 修复纵向带动问题必须同时宣称业务横向 scroll 自动赢过 Pageboy。

## 设计自审

1. 根因修复发生在目标声明源头，错误 scroll 不再进入任何纵向 ownership 链。
2. Framework 现有 nil target、plain direct page、managed inset、binding teardown 和顶部 `.child` unavailable 契约可以直接复用。
3. Public API、Tabman/Pageboy 边界、业务 delegate/configuration 所有权均未扩大或改变。
4. 用户可见行为有真实 UI 证据，接入语义有单元测试和长期文档；没有 TODO、TBD 或未决方案。
