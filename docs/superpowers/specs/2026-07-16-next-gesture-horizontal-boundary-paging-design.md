# 横向业务滚动边界下一手势分页接力设计

**日期：** 2026-07-16

**状态：** 设计已确认；生产实现、TDD、真实 UI 门禁与 fresh-pass 尚未开始

**适用范围：** 横向业务 `UIScrollView`、`UICollectionViewCompositionalLayout` 原生 orthogonal section、Pageboy 横向分页手势起点仲裁、旧逐页静态分页开关移除、系统返回优先级、reload/surface replacement 与真实 UIKit 验收。

## 背景

当前 Compositional Layout 专项通过公开 DataSource 方法
`pagerViewController(_:allowsInteractiveHorizontalPagingAt:)` 对横向业务页整体关闭
Pageboy 的 `isScrollEnabled`。该方案能保证业务横向内容稳定获胜，但也会关闭同页普通区域分页，
并且业务内容到边缘后仍无法继续离页。

用户确认新的交互语义：保留 `UICollectionViewCompositionalLayout` 原生
`.orthogonalScrollingBehavior`，不追求同一次触摸中的连续位移接力；当前手势到达业务边缘后先结束，
下一次从该边缘继续向外拖时再由 Pageboy 原生分页。

同一次触摸不能安全转交的根因不是边界计算，而是 UIKit recognizer winner 在手势开始后已经确定；
Pageboy 5.0.2 和底层 `UIPageViewController` 也没有向外提供 begin/update/finish 的交互进度驱动。
因此不得用 recognizer reset、动态开关业务滚动、直接写 Pageboy offset 或伪造 programmatic selection
模拟同手势接力。

参考公开能力：

- Apple 允许用 gesture delegate 协调同时识别与失败关系：<https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate>
- Compositional Layout 继续使用公开 orthogonal 行为：<https://developer.apple.com/documentation/uikit/nscollectionlayoutsection/orthogonalscrollingbehavior>
- Pageboy 5.0.2 只提供原生交互分页与 programmatic `scrollToPage`，不提供外部交互进度驱动：<https://github.com/uias/Pageboy>

## 目标

1. 删除 `pagerViewController(_:allowsInteractiveHorizontalPagingAt:)` 及其整个静态 metadata/Host/Adapter 状态链。
2. 不增加新的 Public API，不要求业务页面实现手势路由协议。
3. 横向业务内容在手势开始时仍可沿当前方向滚动，则本次手势完整归业务内容处理。
4. 业务内容已位于对应边缘时，下一次向边缘外拖允许 Pageboy 原生分页。
5. 普通页面区域继续直接支持 Pageboy 横向分页。
6. 保留 Compositional Layout 原生 `.orthogonalScrollingBehavior`，不替换为手写横向 CollectionView。
7. 不设置业务 scroll delegate、业务 pan delegate、Pageboy 内建 pan delegate，也不修改业务 bounce、offset 或 `isScrollEnabled`。
8. 保持 interactive-pop、Pageboy containment/lifecycle、selection transaction、纵向 handoff 和 overscroll 所有权不变。

## 非目标

1. 不支持同一次触摸到边缘后的剩余位移连续转交。
2. 不调用私有 selector，不判断 UIKit 私有类名，不缓存固定私有 subview 层级。
3. 不把 orthogonal 内部滚动容器登记为 `anchorPagerScrollView` 或纵向 Store target。
4. 不在业务滚动区域之外建立页面级静态禁用。
5. 不用 `visibleItemsInvalidationHandler` 驱动框架分页；该回调仍只用于 Example 状态探针。
6. 不扩大 v0.8 的 `scrollsToTop`、尺寸恢复或其他版本职责。

## 交互语义

每次触摸只在横向方向明确、recognizer 仍处于 `.possible` 时仲裁一次：

| 手势起点状态 | 当前方向 | 本次结果 |
| --- | --- | --- |
| 触点路径上没有有效横向业务 scroll | 任意横向 | Pageboy 分页 |
| 业务 scroll 位于稳定范围内 | 仍有业务距离 | 业务滚动 |
| 业务 scroll 位于左侧物理边缘 | 手指向右、继续向边缘外 | Pageboy 分页 |
| 业务 scroll 位于左侧物理边缘 | 手指向左、回到内容内 | 业务滚动 |
| 业务 scroll 位于右侧物理边缘 | 手指向左、继续向边缘外 | Pageboy 分页 |
| 业务 scroll 位于右侧物理边缘 | 手指向右、回到内容内 | 业务滚动 |
| 本次业务手势中途才到边缘 | 任意剩余位移 | 不重新仲裁；松手后下一次再判断 |

判断使用物理坐标和手指 `velocity.x`，不把“左/右”提前转换成页面语义。这样 LTR/RTL 都以
UIScrollView 实际 offset 可消费方向为准；Pageboy 自己继续解释最终分页方向。

## 采用方案：框架自有起点仲裁手势

### 为什么不能代理内建 pan delegate

Pageboy paging surface 是 `UIScrollView`，其内建 pan delegate 属于 UIKit/第三方滚动实现。
AnchorPager 不替换或 forwarding 该 delegate，否则会接管不属于框架的 recognizer 生命周期，并违反
既有 delegate ownership。业务 scroll 的 pan delegate 同样保持原样。

### 仲裁手势结构

Paging Adapter 为当前 Pageboy paging surface 安装一个框架自有、无视觉输出的
`UIPanGestureRecognizer`，下称 route gate：

```text
Pageboy paging surface
├─ Pageboy paging pan
└─ AnchorPager route gate
      └─ 只读取触点、velocity 与命中路径上的 UIScrollView 几何
```

固定失败关系为：

```text
Pageboy paging pan -> require route gate to fail
Pageboy paging pan -> require interactive-pop to fail
```

route gate 的行为：

1. 当前业务 scroll 可消费该方向时，gate 进入识别成功；Pageboy 因失败依赖退出本次竞争。
2. gate 对业务 recognizer 返回同时识别，`cancelsTouchesInView = false`，不阻止业务原生 pan。
3. 当前方向已经越出所有候选业务 scroll 的对应边缘时，gate 在 should-begin 阶段失败；Pageboy 的等待条件解除并走原生分页。
4. 纵向占优、速度不明确或触点不在有效横向 scroll 中时，gate 失败，不介入既有 UIKit/ Pageboy 判断。
5. gate 本次成功后直到触摸结束都不重新读取边界，因此天然形成“下一次手势接力”。

该结构与已证伪的 `pagingPan.require(toFail: childPan)` 不同：Pageboy 不直接依赖业务内建 pan，
route gate 是框架拥有且允许与业务同时识别的中立 recognizer，避免把 UIKit 的嵌套 scroll 依赖图闭合成环。
但这项差异必须由真实 UIKit RED/GREEN 证明，不能只靠单元测试推定。

## 自动发现与边界计算

### 命中路径

gate 在 Pageboy paging surface 坐标中取得触点，并通过公开 `hitTest(_:with:)` 获得最深命中视图；
随后只沿该视图到 paging surface 的实际 superview 链向上检查 `UIScrollView`：

1. 排除 Pageboy paging surface 自身；
2. 排除无有效横向 range 的 scroll；
3. 不按类名识别 orthogonal，不递归扫描未命中的业务子树；
4. 不保存业务 scroll identity，判断完成后立即释放局部引用；
5. 若存在嵌套横向 scroll，只要命中路径中任一候选仍能消费当前方向，就让内容处理；全部候选都处于对应外边缘时才允许 Pageboy。

Compositional Layout 当前系统实现会让触点命中的 orthogonal 内容处于某个 `UIScrollView`
祖先中。框架只按公开 `UIScrollView` 能力读取该实例，不使用私有类名或 selector；系统并未承诺固定层级，
所以这项发现是版本敏感的真实 UI 门禁，而不是可脱离验收的静态保证。

### 纯边界模型

候选 scroll 的稳定横向范围为：

```text
minimumX = -adjustedContentInset.left
maximumX = max(
    minimumX,
    contentSize.width - bounds.width + adjustedContentInset.right
)
```

只有 `maximumX - minimumX > epsilon` 才是有效横向候选。所有输入必须有限；非法或未布局几何不参与
阻止 Pageboy。内部 epsilon 初始采用 `0.5 pt`，并由纯模型测试覆盖临界值。

手指向右意味着期望 `contentOffset.x` 下降；手指向左意味着期望 offset 上升：

```text
velocity.x > 0  -> offset.x > minimumX + epsilon 时内容仍可消费
velocity.x < 0  -> offset.x < maximumX - epsilon 时内容仍可消费
```

如果 scroll 已处于原生 bounce 区，向稳定范围内拖仍归内容，继续向同侧边缘外拖才归 Pageboy。
框架只读上述值，不夹紧或恢复业务 offset。

## 分层与所有权

### 新增内部职责

1. `AnchorPagerHorizontalScrollBoundaryResolver`：不依赖 UIKit 的纯边界计算与方向判断。
2. `AnchorPagerHorizontalPagingRouteGate`：框架自有 recognizer/delegate，负责一次性 hit-test 与 should-begin 决策。
3. `AnchorPagerPagingSurfaceObservation`：在 surface identity 变化时装卸 gate，并向既有 GesturePriorityCoordinator 提交新的 paging-pan/gate pair。
4. `AnchorPagerGesturePriorityCoordinator`：继续集中安装不可撤销的公开失败关系；不读取业务 scroll 几何。

### 保持不变的职责

- PagingHost 继续独占 reload 与 selection transaction，但不再持有横向分页 Bool snapshot。
- Adapter 继续执行 Tabman/Pageboy containment 和分页，不持有业务页面策略。
- InteractionCoordinator 只消费 Pageboy 已经开始后的 horizontal lifecycle，不观察 route gate 成败。
- ScrollCoordinator 仍是纵向协调期唯一 offset writer。
- OverscrollCoordinator 仍只管理纵向边界策略。
- PageStateStore、scroll discovery 和 managed inset 仍只处理显式纵向 target。

route gate 不是 selection、interaction 或 offset owner；它只决定 Pageboy 本次 recognizer 是否有资格开始。

## 旧静态策略移除

真实 gate 门禁通过后，按同一实施任务删除：

1. Public DataSource 的 `pagerViewController(_:allowsInteractiveHorizontalPagingAt:)` 与默认实现；
2. `ReloadSnapshot.interactiveHorizontalPagingPermissions`；
3. PagingHost request/committed policy snapshot 与 terminal 应用；
4. Adapter 的 `setInteractiveHorizontalPagingEnabled(_:)` 及对应日志；
5. Example index 4/5 的静态 `false`；
6. 只验证静态开关的单元/UI 测试和文档说明。

这是用户明确授权的 Public API 删除。不得用 deprecated 空壳保留旧方法，也不得再增加页面协议或闭包作为
自动路径的必要条件。普通页面和业务横向页面的 Pageboy surface 均保持 `isScrollEnabled = true`。

## Reload、替换与资源生命周期

1. 相同 paging surface 的重复 refresh 必须幂等，只存在一个 gate 和一组失败关系。
2. surface replacement 先把 gate 从旧 view 移除、清空 closure/delegate 引用，再绑定新 surface。
3. UIKit 不提供移除 `require(toFail:)` 的 API；旧关系只随旧 recognizer/surface 一起释放，不得尝试私有撤销。
4. adapter removal、empty reload、Host teardown 与 deinit 必须同步移除 gate，不使用异步 Task 或 delay。
5. gate 不强持有 page、provider、Store、Host 或业务 scroll；一次命中判断之外不保存 scroll identity。
6. active Pageboy transition、reload、layout 或尺寸事务仍由现有 admission/drain 规则阻止新 paging，不为 gate 增加第二套事务状态。
7. 资源测试必须证明旧 surface、gate、页面和 Compositional Layout handler 均可释放。

## 系统返回与相邻手势

1. interactive-pop 继续是 Pageboy paging pan 的优先失败依赖。
2. route gate 不阻止 interactive-pop，不对系统 recognizer 建立反向依赖。
3. leading-edge pop 命中业务横向区域时仍必须由真实导航栈证明 pop 优先；不能用页面 index 或业务 offset 绕开系统手势。
4. 纵向/斜向手势中 gate 必须失败，根 CollectionView 与 AnchorPager 既有纵向 simultaneous pair 不变。
5. route gate 不产生 `AnchorPagerInteractionState`，因此不会延迟 reload/layout/selection drain。

## 日志

只在每次 gate should-begin 形成最终决策时记录一条低频固定事件：

- `gesture.horizontalRoute.content`
- `gesture.horizontalRoute.pagingBoundary`
- `gesture.horizontalRoute.noCandidate`

日志不包含类名、view hierarchy、业务内容、坐标或 offset。逐帧 pan、`visibleItemsInvalidationHandler`
和业务 scroll callback 不输出普通日志。相同 sink 注入路径覆盖事件测试。

## TDD 与真实 UIKit 硬门禁

### Task 0：隔离可行性 RED/GREEN

在删除旧静态策略或修改 Public API 前，先只装配内部实验 gate，并完成：

1. 普通嵌套横向 `UIScrollView` 中部双向拖动：业务 offset 改变，页面不切换；
2. 同一手势到达边缘：手指未松开时页面不切换；
3. 松手后从边缘再次向外拖：Pageboy 提交相邻页；
4. Compositional Layout 原生 orthogonal section 重复以上三项；
5. orthogonal 普通纵向区域横拖：Pageboy 可离页；
6. 业务 delegate、pan delegate、bounce、`isScrollEnabled` 与根纵向 target 全程不变；
7. 无 gesture cycle、recognizer reset、双 selection terminal 或 appearance 不平衡。

如果普通嵌套 scroll 或原生 orthogonal 任一场景不能稳定满足，立即停止生产实现；保留当前静态策略，
向用户报告真实证据。未经新的设计确认，不得改用私有层级、内建 delegate proxy、Pageboy fork 或 offset 注入。

### 纯模型与内部单元测试

至少覆盖：

- 左右边缘、稳定范围、原生 bounce 区和 `0.5 pt` 临界值；
- adjusted inset、短内容、零宽、NaN/Infinity 和未布局几何；
- 多层命中 scroll 中“任一仍可消费”规则；
- 横向/纵向/零速度判定和 LTR/RTL 物理方向；
- gate 与 paging surface bind/unbind/replacement/deinit 幂等；
- Pageboy->gate、Pageboy->interactive-pop 关系共存；
- gate 同时识别不修改任何既有 delegate/configuration；
- static Bool metadata、Host snapshot 与 Adapter `isScrollEnabled` 封装完整移除。

### Example 与真实 UI 回归

除 Task 0 外，最终至少验收：

- index 4 普通横向业务 scroll 的中部、两端与下一手势离页；
- index 5 原生 orthogonal 双向内容滚动、两端下一手势离页、非正交区域分页；
- 根 CollectionView 双向纵向 handoff、Header/bar/container 稳定；
- Tabman bar、公开 API、interactive Pageboy、cancel、reload、appearance、surface replacement；
- leading-edge interactive-pop；
- empty/short/long/plain、横向-only nil vertical target 与 v0.5/v0.6 边界回归；
- generic Simulator build、warning/analyzer/runtime constraint/gesture-cycle/resource 查询和 fresh-pass。

## 影响范围结论

- **Public API：** 删除旧 Bool，不新增替代 API；属于明确授权的源码破坏性变更。
- **内部架构：** 新增只读 route gate 与纯边界模型；删除 generation-aware 横向策略链。
- **Containment/lifecycle：** Pageboy 继续唯一 containment；只增加 surface recognizer 的同步装卸。
- **Scroll discovery/inset：** 纵向 target 契约不变；横向命中路径只用于单次手势判断，不写 Store。
- **Paging adapter：** Pageboy `isScrollEnabled` 恢复常开；原生 paging transaction 不变。
- **Gesture/overscroll：** 只改变横向 recognizer 起点资格；纵向 Scroll/Overscroll 不变。
- **日志：** 增加固定起点决策事件，删除静态策略切换事件。
- **测试/Example/文档：** 两个横向业务页都需新增边缘下一手势真实 UI 探针，并迁移所有旧静态策略断言。

## 完成定义

只有同时满足以下条件才可标记完成：

1. Task 0 在普通嵌套 scroll 与原生 orthogonal 两条路径均通过；
2. 旧 Public Bool 与完整 metadata/Host/Adapter 状态链已删除；
3. 外部页面无需实现新协议或回调；
4. 当前手势不接力、下一手势边缘外拖可 Pageboy 分页的真实 UI 证据稳定；
5. 业务与 Pageboy/UIKit 内建 delegate、bounce、offset、`isScrollEnabled` 所有权未被接管；
6. Pageboy containment、selection/lifecycle、interactive-pop 与纵向协调回归全部通过；
7. Framework、Example unit/UI、generic build、日志/资源/运行时查询与 fresh-pass 全部通过；
8. `git diff --check` 通过，长期文档只记录真实完成状态。
