# 自有横向分页与业务边缘自动接力设计

**日期：** 2026-07-17

**状态：** Task 1 已执行并在首轮真实 UIKit 停止门禁以 2/4 失败：原生 orthogonal 回到起点后的下一手势未分页，末页业务 bounce 探针未达到；实验已完整清理，Framework 439/439 与 Example generic Simulator build 通过。Task 2–9 Blocked，重启前必须修订阶段 0 设计；当前 Tabman/Pageboy 静态生产链保持不变

**适用范围：** AnchorPager 横向分页执行层、页面 `UIViewController` containment、分段栏与 indicator、普通横向业务 `UIScrollView`、`UICollectionViewCompositionalLayout` 原生 `.orthogonalScrollingBehavior`、下一次手势边缘接力、selection/reload transaction、系统侧滑返回、页面缓存、plain page presentation 和第三方依赖迁移。

## 决策摘要

本设计取代 2026-07-16 被真实 UIKit 门禁否定的 Pageboy 外挂 route-gate 方案。最终方向是：

1. AnchorPager 自行实现横向分页容器、分页滚动表面、页面 containment、分段栏和 indicator。
2. 完成真实 UIKit 硬门禁和全量迁移后，从 `Package.swift` 删除 Tabman 4.0.1 与 Pageboy 5.0.2。
3. 删除 Public DataSource 方法 `pagerViewController(_:allowsInteractiveHorizontalPagingAt:)` 及其 generation-aware 静态策略链，不增加替代 Public API。
4. 保留 Compositional Layout 原生 `.orthogonalScrollingBehavior`，不改写为业务自建横向 CollectionView。
   Example 已有 `.continuousGroupLeadingBoundary` 行为保持不变；专项只增加测试探针，不改为其他 orthogonal case。
5. 业务横向内容到边缘的同一次手势不接力；松手后下一次继续向外拖时自动分页。
6. AnchorPager 不设置业务 `UIScrollView.delegate`、业务内建 pan delegate，也不写业务 offset、bounce 或 `isScrollEnabled`。
7. 自有 route recognizer 与自有 PagingScrollView 原生 pan 共享一次路由决策；当前命中路径上的业务 pan 只在本次触摸的动态仲裁中等待 route，业务仍可消费时 route/paging 都失败并释放业务 pan，已在边缘且存在相邻页时 route 与 paging pan 同时开始并使业务 pan 失败。
8. `AnchorPagerPagingScrollView` 只负责分页滚动物理和几何，不管理 `UIViewController`；`AnchorPagerPagingContainerViewController` 才是类似 `UIPageViewController` 的自定义 container。
9. 消失页面在 terminal 当场结束 appearance 并解除 containment，但 controller 实例进入有界的 `recentlyRetired` 单槽缓存，不要求立即释放。

## 背景与根因

当前生产链路为：

```text
AnchorPagerPagingHostViewController
└─ AnchorPagerPagingAdapter: TabmanViewController
   └─ Pageboy / UIPageViewController / internal UIScrollView
```

Compositional Layout 专项通过逐页 Public Bool 对横向业务页面关闭 Pageboy `isScrollEnabled`。它可以保证业务横向内容稳定获胜，但同页普通区域也无法分页，业务内容到边缘后的下一次手势仍不能自动离页。

2026-07-16 的 route-gate 实验尝试在 Pageboy paging surface 上增加框架自有 pan，并建立：

```text
Pageboy paging pan -> require route gate to fail
```

Task 3 的 Framework 聚焦测试为 51/51，但真实 UIKit UI 门禁为 0/2：

- 普通横向业务 scroll 的 interior 左拖卡片位置为 `16 -> 16`；
- 原生 orthogonal section 在 5 秒内没有形成预期横向进度。

证据保存在 `/private/tmp/AnchorPagerTask3UIKitGate-20260716-1840.xcresult`。根因不是边界公式，而是 Pageboy/`UIPageViewController` 内建 recognizer、外挂 route gate 和 descendant 业务 pan 的失败依赖无法形成可控闭环；内容应该消费时已经被阻断。

用户随后明确授权修改或替换 Pageboy/`UIPageViewController` 分页架构边界，并确认完全移除 Tabman/Pageboy，由 AnchorPager 自行承担分段栏、indicator、横向分页和 containment。

## 官方能力核对

Apple 的公开契约支持本设计的分层：

1. `UIPageViewController` 是管理内容页控制器导航的 container view controller，而不是 scroll view：<https://developer.apple.com/documentation/uikit/uipageviewcontroller>
2. 自定义 container 必须用 `addChild`、安装 child view、`didMove(toParent:)` 建立关系，并在移除时按标准顺序解除：<https://developer.apple.com/library/archive/featuredarticles/ViewControllerPGforiPhoneOS/ImplementingaContainerViewController.html>
3. `UIScrollView` 负责 content size、offset、paging 和滚动物理，不提供 child controller containment：<https://developer.apple.com/documentation/uikit/uiscrollview>
4. `UIView.gestureRecognizerShouldBegin(_:)` 可在 recognizer 仍为 `.possible`、准备转入 `.began` 时让它失败：<https://developer.apple.com/documentation/uikit/uiview/gesturerecognizershouldbegin(_:)>。
5. 对动态创建或位于不同 view hierarchy 的 recognizer，Apple 建议使用 gesture delegate 的动态 failure requirement，而不是事后永久调用 `require(toFail:)`：<https://developer.apple.com/documentation/uikit/preferring-one-gesture-over-another>、<https://developer.apple.com/documentation/uikit/uigesturerecognizer/require(tofail:)>。
6. `UIGestureRecognizer` 子类可以通过公开 prevention/failure 扩展点定义 recognizer 间规则，但这些能力仍必须由真实 UIKit 验证：<https://developer.apple.com/documentation/uikit/uigesturerecognizer>。

Apple 没有承诺 `UIPageViewController` 对消失页面的具体缓存数量或释放时点。因此本设计不模仿未公开缓存，而是定义可测试的 AnchorPager retention 语义。

## 目标

1. 普通横向 `UIScrollView` 和原生 orthogonal section 在内部仍可正常滚动。
2. 业务 scroll 已位于对应边缘时，下一次向外拖自动切换 AnchorPager 页面。
3. 同一次触摸中途到边缘不改变 owner，不执行剩余位移接力。
4. 页面普通区域继续支持原生横向分页。
5. 统一交互分页、分段栏选择和 Public `setSelectedIndex` 的 Host selection transaction。
6. 保持 v0.4 page identity/generation/cache、v0.5 纵向 owner、v0.6 顶部行为、v0.7 interaction/reload/layout arbitration 的对外语义。
7. 保持 plain page 底部 presentation 只移动页面 surface，不移动 Header 或分段栏。
8. 完整管理 child containment、appearance、取消、reload、尺寸变化和资源释放。
9. 删除第三方依赖后不让原 Tabman/Pageboy 类型或术语泄漏到 Public API。

## 非目标

1. 不支持同一次手势到边缘后的连续位移接力。
2. 不设置、替换或代理业务 `UIScrollView.delegate` 或业务内建 pan delegate。
3. 不写业务 offset，不保存、修改或恢复业务 bounce、`alwaysBounceVertical`、`isScrollEnabled`。
4. 不识别 UIKit 私有类名、私有 selector 或固定 orthogonal subview 索引。
5. 不替换 Compositional Layout 原生 `.orthogonalScrollingBehavior`。
6. 不要求业务页面实现 `AnchorPagerHorizontalGestureDisposition`、协议、闭包或页面级 Bool。
7. 不把 orthogonal 内部 scroll 登记为纵向 `anchorPagerScrollView`；组合布局根 CollectionView 仍是唯一纵向 target。
8. 不在本专项增加完整 bar 样式 Public API；只迁移当前标题、选择、indicator 和高度契约。
9. 不承诺 AnchorPager 释放引用后业务 controller 立即 `deinit`。

## 方案比较

### 方案 A：继续外挂 Pageboy route gate

已被真实 UIKit 0/2 门禁否定。继续追加 failure relation、delegate proxy、recognizer reset 或 offset 注入只会放大第三方内建状态的不透明性，不采用。

### 方案 B：fork Pageboy/Tabman

可以接触更多内部实现，但仍保留 `UIPageViewController` 的 recognizer 和 terminal 约束，还会形成长期 fork、版本同步与隐式行为成本，不采用。

### 方案 C：完全自有 PagingContainer + PagingScrollView

AnchorPager 同时拥有分页几何、route recognizer、selection transaction 和 containment，可以在手势开始前同步准备 source/target，并使用公开 UIKit 能力控制自己的 recognizer。该方案分层清晰、可验证且不扩大 Public API，采用。

## 总体架构

```text
AnchorPagerViewController
└─ AnchorPagerPagingHostViewController
   └─ AnchorPagerPagingContainerViewController
      ├─ pagePresentationView
      │  └─ AnchorPagerPagingScrollView
      │     ├─ sourcePageView
      │     └─ targetPageView
      └─ AnchorPagerSegmentBarView
```

辅助内部类型：

```text
AnchorPagerPagingTransitionCoordinator
AnchorPagerHorizontalGestureRouter
AnchorPagerPagingRoutePanGestureRecognizer
AnchorPagerPagingAppearanceCoordinator
```

### AnchorPagerPagingHostViewController

Host 继续是唯一 selection/reload request owner：

- 同时最多一个 active request 和一个 latest pending request；
- 管理 prepared/active/settling/terminal selection phase；
- 读取 Store committed/pending generation；
- 执行 willSelect/didSelect/didCancel 的唯一语义出口；
- 仲裁 reload、layout、尺寸变化和 teardown；
- 不计算逐帧 content offset，不 containment 业务页面；
- 不持有逐页横向静态 Bool。

Host 始终安装一个稳定的 PagingContainer。空数据不替换 Container，也不再需要 Pageboy delete-last-page 和 empty adapter shim。

### AnchorPagerPagingContainerViewController

Container 是类似 `UIPageViewController` 的自定义 container：

- 是业务页面唯一 UIKit parent；
- 从 Host 接收 source/target/index/request identifier；
- 管理 child view 安装、frames、appearance 与 terminal；
- 持有 PagingScrollView、SegmentBar 和 transition coordinator；
- 向 Host 报告交互 began/progress/commit/cancel 和 bar obstruction；
- 不拥有 generation/provider/cache 策略。

### AnchorPagerPagingScrollView

PagingScrollView 是专用分页滚动引擎：

- 使用公开 `UIScrollView` paging/content offset/deceleration；
- 固定 `scrollsToTop = false`，不参与系统点击状态栏顶滚 owner；
- 管理单页或 source/target 两页几何；
- 在 `gestureRecognizerShouldBegin(_:)` 中消费共享 route decision；
- 报告原生 pan 与 scroll terminal；
- 不持有或请求 `UIViewController`；
- 不调用 `addChild`、`didMove`、`removeFromParent`；
- 不访问 Store、provider、reload generation 或 Public DataSource；
- 不直接提交 selection。

因此：

```text
AnchorPagerPagingContainerViewController ≈ 自定义 UIPageViewController
AnchorPagerPagingScrollView             ≈ 其内部专用滚动 surface
```

### AnchorPagerPagingTransitionCoordinator

TransitionCoordinator 维护一笔分页执行的有限状态：

```text
idle
prepared(source, target, direction, requestID)
active(source, target, direction, requestID)
settling(source, target, progress, projectedTerminal)
terminal(commit | cancel)
```

它负责：

- source/target/direction/progress；
- native deceleration 和 programmatic animator 的 terminal 归一化；
- 方向反转时仍保持原 source/target，不在同一手势换另一目标；
- terminal 幂等和 stale callback 拒绝；
- 不决定 reload latest-wins，不触发 Public DataSource。

### AnchorPagerSegmentBarView

SegmentBar 使用内部横向 `UICollectionView` 和独立 indicator view：

- title 点击只向 Host 提交 selection request；
- indicator 根据 source、target、progress 插值；
- commit 后更新正式选中项，cancel 回到 source；
- 选中项自动滚入可见范围；
- button 保留 `.button`、`.selected` 和可访问标题；
- 不包含 Tabman 类型或回调。

## 分页视图层级与 presentation surface

Container 根视图采用固定分层：

```text
rootView
├─ pagePresentationView
│  └─ pagingScrollView
└─ segmentBarView
```

约束：

1. `pagePresentationView` 和 SegmentBar 都填充 PagingContainer 的既有 viewport 语义。
2. SegmentBar 作为页面上方 obstruction，页面继续通过现有 managed top inset 避让；不能把页面 frame 直接下移到 bar 下方形成第二套 inset 事实。
3. plain page bottom presentation 只能平移 `pagePresentationView`。
4. Header、SegmentBar 和 PagingContainer canonical frame 不随 plain bottom translation 移动。
5. selection、reload、尺寸变化、Container removal 和 deinit 都必须把 page presentation 恢复为 identity。

## 手势路由

### 唯一路由会话

每次触摸只创建一个 `AnchorPagerHorizontalGestureRouter.Session`。Session 在 recognizer 仍为 `.possible` 时收集：

- 起始触点命中路径；
- 物理 `velocity.x/y`；
- 命中路径上的候选业务 `UIScrollView` 只读几何；
- 当前 layout direction；
- 当前 source index 和物理方向对应的相邻 index；
- Host 是否允许开始新 selection；
- Container/PagingScrollView 几何是否有效。

Session 形成一次最终 decision：

```text
business
page(targetIndex, physicalDirection)
pageBoundaryBounce(physicalDirection)
none
```

PagingScrollView 与 route recognizer 必须消费同一个 Session，不得各自重新 hit-test 或计算边界。

最终决策顺序固定为：

1. 命中路径存在横向业务候选，且任一候选可沿当前方向消费：`.business`；
2. 存在业务候选、全部已在对应边缘，且存在相邻页：`.page`；
3. 存在业务候选、全部已在对应边缘，但不存在相邻页：`.business`，由业务表达自身边界 bounce；
4. 不存在业务候选且存在相邻页：`.page`；
5. 不存在业务候选且不存在相邻页：`.pageBoundaryBounce`，由 PagingScrollView 表达首尾页原生 bounce，但不建立 selection；
6. 速度、几何或 Host admission 无效：`.none`。

### recognizer 结构

```text
AnchorPagerPagingScrollView
├─ UIScrollView.panGestureRecognizer
└─ AnchorPagerPagingRoutePanGestureRecognizer
```

Route recognizer 及其 delegate 都属于 AnchorPager。框架不设置 PagingScrollView 内建 pan delegate，也不设置业务 pan delegate。

#### decision == business

```text
route recognizer -> failed
paging pan       -> failed
business pan     -> normal began
```

1. route recognizer 的 should-begin 返回 false；
2. PagingScrollView 的 `gestureRecognizerShouldBegin` 对自己的 pan 返回 false；
3. 业务 pan 不再等待 route，完整消费本次触摸；
4. 本次触摸中途到边缘不重新建立 Session。

#### decision == page

```text
route recognizer ─┐
                  ├─ simultaneous began
paging pan ───────┘
business pan -> 动态等待 route；route began 后 failed
```

1. Route delegate 对本次命中路径上的候选业务 pan 建立仅限当前触摸的动态优先级，使候选业务 pan 等待 route 的 possible/began 结果；该等待关系在最终 decision 形成前即可建立，不能依赖 page decision 形成后再补装；
2. Route 与 PagingScrollView 自有 paging pan 允许同时识别；
3. Route 只负责本次 recognizer prevention，不写页面或业务 offset；
4. PagingScrollView 原生 pan 执行实际横向滚动、减速和 terminal；
5. Route 不保存业务 scroll identity 到触摸结束之后。

Apple 对动态 recognizer hierarchy 建议使用 gesture delegate 的 `shouldRequireFailureOf` / `shouldBeRequiredToFailBy` 能力。具体回调方向必须先用单元测试证明“业务等待 route”：business decision 下 route 及时失败并释放业务 pan，page decision 下 route began 后业务 pan 失败；随后再用真实 UIKit 证明，不得仅凭方法名推定。

#### decision == none

以下情况 route 和 paging pan 都失败：

- 横向速度不明确；
- 纵向速度占优；
- Host 正在 reload/layout/selection terminal，不能开始新事务；
- 几何未布局、非有限或无法同步准备 target。

若触点位于业务 scroll，业务保留原生 bounce 或纵向处理，不产生分页死区。

#### decision == pageBoundaryBounce

只在触点路径没有横向业务候选、当前物理方向又没有相邻页时使用：

1. Route 与 paging pan 同时开始；
2. PagingScrollView 以单页 content geometry 和 `alwaysBounceHorizontal` 表达原生边界回弹；
3. 不创建 target、不进入 Host prepared/active selection、不发送 will/did/cancel；
4. 手势结束后 offset 回稳到单页基线；
5. 如果命中路径存在业务横向候选，即使没有相邻页也不得使用 pageBoundaryBounce，必须把边界表现留给业务。

### 与旧 route gate 的区别

旧失败关系：

```text
Pageboy paging pan -> 等待外挂 route gate
```

新关系：

```text
candidate business pan -> 动态等待 AnchorPager 自有 route
AnchorPager route       <-> AnchorPager paging pan 同时识别
```

AnchorPager 现在拥有 route、paging pan 所在的 scroll view、source/target 准备和 terminal，因此可以在返回 page decision 前同步建立有效的两页滚动范围。不得把旧的 `pagingPan.require(toFail: routeGate)` 迁移到新实现。

### 候选 scroll 发现

Router 从触点最深命中 view 沿真实 superview 链向 PagingScrollView 上行：

1. 只读取公开 `UIScrollView` 类型和属性；
2. 排除 PagingScrollView 自身；
3. 稳定横向 range 有效，或业务显式 `alwaysBounceHorizontal == true`，才视为横向业务候选；零 range 但允许横向 bounce 的候选只用于首尾 ownership，存在相邻页时仍视为已在双边缘；
4. 不递归扫描未命中子树；
5. 不按类名识别 orthogonal 内部实现；
6. 若存在多层横向 scroll，只要任一候选仍可沿当前方向消费，本次即归业务；
7. 全部候选都处于对应外边缘，且存在相邻页，才归分页。

Compositional Layout 当前系统实现会让 orthogonal 内容命中路径包含可滚动 `UIScrollView`，但 Apple 没有承诺固定内部层级，所以它是版本敏感的真实 UI 硬门禁。

### 纯边界公式

每个候选的稳定横向范围：

```text
minimumX = -adjustedContentInset.left
maximumX = max(
    minimumX,
    contentSize.width - bounds.width + adjustedContentInset.right
)
```

只有 `maximumX - minimumX > epsilon` 才是有效横向候选。初始 `epsilon = 0.5 pt`，所有输入必须有限。

`alwaysBounceHorizontal == true` 且稳定 range 不大于 epsilon 时，候选不能在内部消费距离，但在分页容器没有相邻页时仍拥有本次业务边界 bounce。框架只读该配置，不修改或恢复它。

```text
velocity.x > 0  -> 手指向右，期望 offset.x 降低
velocity.x < 0  -> 手指向左，期望 offset.x 升高
```

规则：

- offset 仍能沿期望方向进入稳定范围：业务可消费；
- 已处于 minimum，继续向 minimum 外拖：到物理左边缘；
- 已处于 maximum，继续向 maximum 外拖：到物理右边缘；
- 已在 bounce 区，向稳定范围内拖仍归业务，继续向同侧外拖才视为边缘；
- 短内容、零宽或非法几何不作为有效候选。

Router 先按物理坐标判断业务能否消费，再按 `effectiveUserInterfaceLayoutDirection` 把物理拖动映射为 previous/next page。LTR/RTL 映射不能反向影响业务 scroll 的物理边界公式。

## 手势开始前的同步准备

Idle 时 PagingScrollView 只布局 current page。方向明确并形成 `.page(target)` decision 后，Host/Container 必须在 recognizer 返回 true 前同步完成 prepared phase：

1. Host 校验没有 active selection/reload/layout/size terminal；
2. Store 获取或创建 target 页面，并增加 transition target lease；
3. Container 对 target 建立 containment，但不开始 appearance，不发送 willSelect；
4. PagingScrollView 建立 source/target 两页几何和有效 content range；
5. Router 发布唯一 prepared request identifier；PagingScrollView 和 route recognizer 无论谁先进入 should-begin，都只调用同一个幂等 `prepareIfNeeded`，不得依赖 UIKit 固定回调顺序；
6. route 与 paging pan 才允许从 `.possible` 进入 `.began`。

几何准备必须视觉等价：

- 向 next：source 在 `x = 0`，target 在 `x = width`，offset 从 `0` 开始；
- 向 previous：target 在 `x = 0`，source 在 `x = width`，同步把 offset 设为 `width`，屏幕内容不能跳变；
- cancel 或 terminal 后把 current 重新基准化到 `x = 0`，content size 恢复单页。

Prepared phase 不产生 Public interaction state、willSelect 或 appearance。只有 PagingScrollView 原生 pan 确实 `.began` 后，Host 才把事务升级为 active。

若 route 已准备但 paging pan 未能开始，route 必须同样失败并同步撤销 prepared target；不能让 route 单独阻止业务 pan。该原子性是 Task 0 的停止门禁，不能通过异步补偿掩盖。

## 交互、选择与 terminal

### 交互开始

Paging pan `.began` 后：

1. Host 激活 matching prepared request；
2. 发送一次 willSelect；
3. AppearanceCoordinator 为 source/target 开始平衡的 appearance transition；
4. InteractionCoordinator 进入 horizontal interaction；
5. indicator 开始跟随 progress。

### 交互更新

Progress 由 PagingScrollView 归一化 offset 得到，限定在当前 source/target 方向。手势反向只表示回撤，不能在同一手势把 target 换成另一侧页面。

逐帧 progress 只更新页面 offset、indicator 和必要 presentation，不触发 data source、reload 或普通日志。

### 交互 terminal

PagingScrollView 使用原生 target content offset/deceleration，并把最终结果标准化为：

```text
commit(target)
cancel(source)
```

Commit：

1. target 成为 current；
2. 完成 source disappear/target appear；
3. 发送 matching didSelect；
4. Store 提交 current/transition retention；
5. source 解除 active containment，并进入 retention 收口；
6. indicator 和 bar selection 固定到 target；
7. Host drain latest pending request。

Cancel：

1. source 恢复 current；
2. appearance 成对取消/完成，不重复 source appear；
3. 发送 matching didCancel；
4. target 解除 containment 和 transition lease；
5. 页面和 indicator 回到 source；
6. Host drain latest pending request。

Terminal 必须以 request identifier 匹配，stale deceleration、animator completion 或 size callback 不得结束后续事务。

### 分段栏与 Public 选择

分段栏点击、`setSelectedIndex` 和交互分页都先进入 Host 同一 selection 队列：

- 非动画选择同步安装目标、提交 current 并完成回调；
- 动画选择使用内部 `UIViewPropertyAnimator` 驱动 PagingScrollView offset，不伪造 pan；
- 非相邻选择仍是一次 source/target transition，不逐页回调中间 index；
- active 期间新选择遵循 latest-wins；
- 程序化 animator 和原生 interactive pan 不能同时成为 offset owner。

## Containment 与 appearance

Container 覆盖 `shouldAutomaticallyForwardAppearanceMethods = false`，由 `AnchorPagerPagingAppearanceCoordinator` 统一处理：

1. 初始非空 reload 按 `addChild -> 安装 view/约束 -> didMove` 安装 current。
2. Idle 且父 Container 出现/消失时，只向 current 转发。
3. Prepared target 已 containment 但尚未 active 时不产生 appearance。
4. Active 后 source/target 建立成对 `beginAppearanceTransition` / `endAppearanceTransition`。
5. Commit、cancel、父容器中途消失、reload、尺寸变化和 teardown 都必须平衡结束。
6. Offscreen Store cache 只强持有 controller 实例，不保持 active containment。
7. Store 不调用 appearance 方法；只有 Container/AppearanceCoordinator 执行。

同一时刻 active containment 最多包含 current 以及一笔 transition target。缓存 controller 可以存在，但必须未 containment。

## 最近退场页面缓存

为避免刚完成 A -> B 后反向滑动立即重新创建 A，引入内部 `recentlyRetired` 单槽 retention：

```text
A -> B commit
current: B
recentlyRetired: A

B -> A
target: reuse A

B -> C
release retired A
source: B
target: C
```

规则：

1. Commit terminal 当场完成 A 的 disappearance、移除 view 并解除 containment。
2. 在解除 active transition lease 前，Store 原子增加 `.recentlyRetired` lease，防止实例瞬间释放。
3. recentlyRetired 只保留 controller/identity payload，不继续占有可见 presentation、appearance 或纵向 managed inset ownership。
4. 退场时先保存 child distance snapshot、归还 managed inset ownership；重新激活时再恢复 ownership 和 offset。
5. 下一笔不同目标的 selection 真正开始时替换旧 retired；若 retired 正是新 target，则先增加 transition target lease，再移除 retired lease，实例不能出现释放窗口。
6. `keepsAdjacentPagesLoaded == true` 时，符合 configuredAdjacent 的已加载页面进入正式相邻缓存；相同页面不重复占用 retired 槽。
7. `keepsAdjacentPagesLoaded == false` 仍表示不建立完整相邻窗口，但允许一个确定性、短生命周期的退场实例。
8. matching reload generation commit、memory warning、Container teardown 和 Store releaseAll 立即清空 retired。
9. 不使用 timer、主队列 delay 或“缓存若干秒”。
10. AnchorPager 清空 lease 后也不承诺立即 `deinit`，因为业务方可能仍有强引用。

该设计要求 Store 把“controller retention”和“managed inset ownership”进一步解耦；不得因为 `.recentlyRetired` 仍为强引用就继续更新不可见页面 offset/inset。

## 分段栏高度与外观

`AnchorPagerBarConfiguration.height` Public 契约保持：

- 非 `nil`：显式高度是唯一高度约束；
- `nil`：SegmentBar 根据 title intrinsic size 和内部度量自适应；
- Container 布局完成后只报告实际 bar obstruction；
- 主容器和 managed child inset 只消费实际 obstruction，不直接消费配置值。

负数或非有限显式高度继续走内部 assertion、固定 paging 日志并降级为 `0`；不得把非法值送入约束系统。

默认内部度量迁移当前 Tabman system bar 的有效外观：

- `UIFont.preferredFont(forTextStyle: .headline)`；
- 标题上下各 12pt；
- item 间距 16pt；
- indicator 4pt；
- system material 背景和底部分隔线。

不得重新引入隐藏固定 48pt。自适应高度变化只在结构性布局点报告 `barObstructionChanged`，不能在滚动热路径形成反复 layout。

## Reload、generation 与空数据

1. Host 仍保持 active + latest pending reload request。
2. Active selection 期间 reload 只进入 pending，不中途替换 source/target。
3. Matching terminal 后 Host 再执行 latest reload。
4. 非空 reload 原子 stage provider generation、确定 target current、安装新 current，再由 ViewController acknowledgement 提交 Store/public metadata/bar obstruction。
5. 空 reload 移除所有 active containment、清空 bar、恢复 page presentation、提交 `.empty` 和零 obstruction。
6. Stable Container 不因 empty/nonempty reload 被移除重建。
7. 无 Pageboy 后删除 delete-last-page、adapter removal shim、Pageboy completion suppression 和相关 terminal 兼容状态。
8. 同一 generation 同 index 仍复用 live identity；重复 controller index 仍断言并降级，不能形成双 containment。
9. Reload generation replacement 必须清理旧 `.recentlyRetired` lease 和 ownership snapshot，不能跨不匹配 generation 泄漏。

## 尺寸、布局与方向变化

1. Idle 尺寸变化：保持 current index，重建单页 frame 和 offset 0。
2. Prepared 尚未 began：撤销 prepared，按新尺寸重建后等待下一次手势。
3. Active interactive 期间系统取消 pan：按 cancel 收口，不猜测 commit。
4. Programmatic animator 期间尺寸变化：保存 normalized progress，重建 source/target frames，再继续同一 request；无法安全 rebase 时 cancel 并由 Host drain latest。
5. Layout direction 变化：idle 时更新物理 previous/next 映射；active 期间不改变既有 source/target，terminal 后应用新方向。
6. 零宽、非有限 bounds 或 detached window 下不能进入 prepared/active。

## MainActor 与并发边界

1. Host、Container、PagingScrollView、SegmentBar、GestureRouter、route recognizer、TransitionCoordinator、AppearanceCoordinator 和 Store 都是 `@MainActor` UIKit/状态类型。
2. 纯边界公式可以拆成不持有 UIKit 对象的值类型；它不整体绑定 MainActor，也不保存共享可变状态。
3. 日志门面继续保持非 MainActor，可注入 sink 单独同步保护。
4. 不使用 `Task.detached`、`nonisolated(unsafe)`、`@unchecked Sendable` 或 `@preconcurrency` 绕过隔离。
5. Prepared、terminal、teardown 和 route reset 都必须同步完成，不通过 Task、DispatchQueue delay 或 timer 猜测 UIKit 时序。

## 系统返回与其他手势

1. navigation interactive-pop 继续优先于 route 和 paging pan。
2. GesturePriorityCoordinator 对自有 paging pan 和 route recognizer 都建立等待 interactive-pop 的公开关系。
3. Route 不阻止 system recognizer，也不建立反向依赖。
4. Pop `.began` 时取消 matching prepared selection；若 paging 尚未 active，不产生 will/did/cancel Public 事件。
5. 纵向/斜向手势 route 和 paging pan 都失败，现有 container/child simultaneous 纵向协调保持不变。
6. Route 不是 InteractionCoordinator 的第二个 state owner；只有 paging pan 真正 began 才建立 horizontal interaction。

## 纵向滚动与业务所有权保持

本设计不改变：

- `anchorPagerScrollView` 只表达纵向 target；
- horizontal-only 页面可以显式 nil target；
- Compositional Layout 页的根 CollectionView 是唯一纵向 target；
- ScrollCoordinator 是纵向协调期唯一 offset writer；
- OverscrollCoordinator 只管理 owner/policy；
- child delegate、业务 pan delegate、bounce 和 `isScrollEnabled` 归业务/UIKit；
- Header、container top inset、bar obstruction 与 child managed inset 的现有归一化模型。

Router 对业务横向 scroll 的引用只存在于当前触摸仲裁，不进入 Store、scroll discovery 或纵向 coordinator。

## 资源生命周期

1. Container、PagingScrollView、route recognizer、bar 和 coordinators 都随稳定 Host 建立一次。
2. Empty reload 只清页面和 bar item，不销毁 stable Container。
3. Prepared/active/cancel/commit cleanup 幂等，不能依赖 timer、Task 或主队列 delay。
4. Route session 在 touches ended/cancelled/reset 时清空临时候选 recognizer identity。
5. Interactive-pop identity replacement 重新建立自有 recognizer 关系，不缓存旧 navigation controller。
6. Teardown 顺序：取消 transaction -> 平衡 appearance -> 归还 Store ownership/lease -> 移除 child -> 清 bar/page presentation -> 解绑事件闭包。
7. 弱引用测试必须证明旧 page、retired page、route session、Compositional Layout handler、Container 和 Host 均能释放。

## 日志

固定低频事件：

```text
paging.route.business
paging.route.page
paging.route.pageBoundaryBounce
paging.route.none
paging.selection.prepared
paging.selection.began
paging.selection.committed
paging.selection.cancelled
paging.reload.deferred
paging.barObstructionChanged
children.page.retire
children.page.retiredRelease
```

约束：

- 不逐帧记录 progress、offset 或 velocity；
- 不输出命中 view 层级、类名、业务标题或用户内容；
- 只记录状态变化和异常 terminal；
- 日志测试使用现有可注入 sink，不依赖人工控制台。

## Public API 与依赖迁移

真实 UIKit 硬门禁和新 Container 核心回归通过前，旧生产链保持不变。通过后按同一迁移阶段删除：

1. `AnchorPagerDataSource.pagerViewController(_:allowsInteractiveHorizontalPagingAt:)` 和默认实现；
2. reload snapshot 的 interactive permission 数组；
3. Host request/committed paging permission；
4. Adapter `setInteractiveHorizontalPagingEnabled(_:)`；
5. Example index 4/5 的静态 false；
6. `AnchorPagerPagingAdapter` 与 `AnchorPagerTabBarAdapter`；
7. PagingSurfaceObservation 中只服务 Pageboy 的发现逻辑；
8. Tabman/Pageboy import、Package dependency 和 resolved dependency；
9. 第三方专属测试、日志和文档契约。

Public 保留：

- `AnchorPagerBarConfiguration`；
- 现有 title/data source、selection、reload、paging cache 配置；
- 所有 UIKit/Swift 领域无关类型。

不保留 deprecated Bool 空壳，不增加外部 horizontal disposition 协议。

## 实施阶段与停止门禁

### 阶段 0：隔离原型

在不删除旧 Adapter/Public Bool/依赖的前提下，新增自有 PagingContainer 最小路径和 test-only Example 启动入口。必须先证明：

1. 普通横向 `UIScrollView` interior 双向滚动成功且 page index 不变；
2. 普通横向 scroll 同一次手势到边缘不分页；
3. 松手后下一次向外拖分页；
4. 原生 orthogonal section 重复以上三项；
5. orthogonal 外普通区域直接分页；
6. 无相邻页不丢手势并保留业务 bounce；
7. 首尾页普通区域保留 PagingScrollView 原生 boundary bounce，但不产生 selection；
8. route/paging pan 同时 began，业务 pan 在 page route 下失败；
9. business route 下 route/paging 都失败，业务 pan began；
10. prepared 但 paging pan 未 began 时不允许 route 单独吞手势；
11. 不修改任何业务 delegate/offset/bounce/enable；
12. 无 gesture cycle、appearance 不平衡、双 terminal 或 runtime constraint。

普通 scroll 或 orthogonal 任一硬门禁不稳定，立即停止，不进入迁移阶段，不删除第三方依赖和 Public Bool。不得改用私有层级、业务 delegate proxy、recognizer reset 或 offset 注入。

#### 2026-07-17 阶段 0 执行结论：未通过并已清理

Task 1 按测试先行完成隔离 Router、route recognizer、PagingScrollView、最小 Container 和仅启动参数可达的 Host 临时链路。真实 UIKit 首轮 4 条 UI 门禁结果为 2/4：普通横向 `UIScrollView` 的内部滚动与下一手势分页通过，原生 orthogonal 外普通区域分页及页面 boundary bounce 通过；原生 orthogonal 回到起点后的下一次向外手势未分页，无相邻页业务候选的原生 bounce 探针也未成立。证据保留于 `/private/tmp/AnchorPagerSelfHostedTask1UIKitGate-1.xcresult`。

依照本节停止规则，没有执行第二、三轮，也没有进入 Task 2。Task 1 的 6 个临时生产文件、全部临时测试、Host/ViewController/GesturePriority/Example 分支与探针均已用 `apply_patch` 清理；当前生产继续使用 Tabman/Pageboy、`AnchorPagerPagingAdapter` 和 `allowsInteractiveHorizontalPagingAt` 静态策略。该次失败只否定本设计当前阶段 0 的具体 recognizer/Container 装配，后续若要重启自有分页迁移，必须先修订设计并重新建立能够同时覆盖原生 orthogonal 与无相邻页业务 bounce 的真实 UIKit 停止门禁。

### 阶段 1：Container 与 lifecycle

完成 source/target geometry、containment、appearance、interactive/programmatic terminal、recentlyRetired 和资源测试；旧生产 Adapter 仍可作为回退事实。

### 阶段 2：Host 执行层迁移

把 Host 的 executor 从 Adapter 切到稳定 Container，迁移 bar obstruction、selection、reload、plain presentation 和 GesturePriorityCoordinator；保留旧代码直到新链路聚焦/相邻回归通过。

### 阶段 3：删除旧策略和依赖

真实 UI、Framework 聚焦和 Example 回归通过后，整体删除 static Bool、Adapter、Tabman/Pageboy 和兼容 shim。禁止长期保留双执行器或运行时开关。

### 阶段 4：全量验收与 fresh-pass

执行 Framework 全量、Example unit/UI 全量、generic Simulator build、warning/analyzer/runtime diagnostics、资源释放检查和整分支独立复审。完成前不得把新架构标记 Ready。

## 测试矩阵

### 纯模型

- minimum/maximum/interior/bounce 区；
- adjusted inset、短内容、零宽、NaN/Infinity、0.5pt epsilon；
- 多层命中 scroll 的“任一可消费”规则；
- 横向、纵向、零速度；
- LTR/RTL 的物理边界与逻辑 page 映射；
- 首尾页无相邻 target。
- 零 range + `alwaysBounceHorizontal` 的业务 ownership 与普通区域 pageBoundaryBounce。

### recognizer 与 route

- 唯一 Session 复用，不重复 hit-test；
- business/page/pageBoundaryBounce/none 四态；
- pageBoundaryBounce 不建立 selection transaction；
- 动态业务 pan 等待 route 的实际方向；
- route 与 paging pan simultaneous；
- interactive-pop 双优先关系；
- touches reset/deinit 清理；
- 不设置业务或内建 pan delegate；
- 不产生永久业务 failure relation；
- prepared/paging began 原子性。

### Container/lifecycle

- 初始、commit、cancel、反向回撤、快速甩动；
- current/target 双 containment 上限；
- appearance 精确平衡；
- 父 Container 中途出现/消失；
- recentlyRetired 复用、替换、memory warning、reload 和 teardown；
- Store retention 与 managed inset ownership 解耦；
- duplicate controller fallback；
- weak release。

### Host transaction

- bar/API/interactive 三入口统一；
- active + latest pending selection/reload；
- reentrant will/did callbacks；
- stale terminal；
- empty/nonempty reload；
- generation replacement；
- size/layout arbitration；
- nonadjacent programmatic selection。

### bar 与 presentation

- 自适应/显式 bar height；
- indicator progress、commit、cancel；
- title reload、选中项可见和无障碍 trait；
- plain bottom 只移动 pagePresentationView；
- selection/reload/size/deinit 恢复 identity。

### 真实 UI

- 普通横向业务页双物理边缘；
- 原生 orthogonal 双物理边缘；
- 同一次手势不接力与下一次手势接力；
- 业务 interior 位移和 page index 双探针；
- 无相邻页边界；
- LTR/RTL；
- 系统侧滑返回；
- 纵向根 CollectionView、Header 折叠和 child handoff；
- plain page、空 reload、分段栏点击、Public 选择；
- runtime gesture/appearance/constraint/resource 诊断零问题。

## 文档迁移

实现完成时同步：

- `Package.swift` 与技术基线；
- `README.md` 接入与行为说明；
- `docs/architecture.md` 的 paging、containment、gesture、bar、cache 和 known limitations；
- `docs/task-list.md` 对应任务与真实验收；
- `AGENTS.md` 技术基线、架构边界和当前阶段门禁；
- 2026-07-16 被否定 spec/plan 的 superseded 指针；
- 新实施计划与每任务 RED/GREEN/验收记录。

旧版本文档保留历史事实，不改写已经完成的 Tabman/Pageboy 版本验收；只增加被本设计取代的说明。

## 完成定义

只有同时满足以下条件才算完成：

1. 普通横向 scroll 与原生 orthogonal 真实 UIKit 硬门禁全部通过；
2. 同手势不接力、下一手势自动分页符合确认语义；
3. 新 Container 的 containment/appearance/selection/reload/size/resource 测试通过；
4. recentlyRetired 与 Store ownership 解耦测试通过；
5. static Public Bool、Adapter、Tabman/Pageboy 依赖完整删除；
6. Framework/Example/build 全量通过，0 fail、0 skip；
7. warning、analyzer、runtime constraint、gesture cycle、appearance 和资源诊断零问题；
8. 文档同步且 fresh-pass 为 Critical 0、Important 0、Minor 0；
9. 未引入业务 delegate/pan/offset/bounce/enable 写入或私有 UIKit 依赖。

## 后续步骤

详细实施计划见 `docs/superpowers/plans/2026-07-17-self-hosted-horizontal-paging-auto-handoff.md`。执行时按 Task 拆分 RED → GREEN → 聚焦回归 → 自审 → 中文提交；Task 1 必须先完成普通横向 scroll 与原生 orthogonal 的真实 Framework 停止门禁，未通过前不得删除旧生产链路。
