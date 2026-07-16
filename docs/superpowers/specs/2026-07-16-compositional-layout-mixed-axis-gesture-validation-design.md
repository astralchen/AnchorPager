# Compositional Layout 混合轴页面与手势冲突验证设计

**日期：** 2026-07-16

**状态：** 页面级横向分页策略、混合轴 Example、完整门禁与 fresh-pass 均已完成；专项 Ready

**后续设计：** 用户已确认以“业务横向内容到边缘后的下一次手势自动接力 Pageboy”取代本专项的逐页静态 Bool；当前生产事实仍以本文为准，后续尚未实现，详见 `2026-07-16-next-gesture-horizontal-boundary-paging-design.md`。

**适用范围：** Example 新增 `UICollectionViewCompositionalLayout` 页面、纵向根滚动目标、orthogonal section、Pageboy 横向分页竞争、真实手势探针与必要的框架根因修复。

## 背景

2026-07-16 横向-only 页面专项已经修复错误的纵向目标声明：只有横向业务内容的页面必须关闭默认 lookup，并向 AnchorPager 提交 nil scroll target。该结论不能直接套用到同时包含纵向主内容和横向业务区域的混合轴页面。

混合轴页面的正确接入契约已经在 `anchorPagerScrollView` DocC 中固定：只登记纵向父 scroll view，嵌套横向业务 scroll 不进入 managed inset、offset snapshot、ScrollCoordinator binding 或 container/current-child simultaneous pair。

本次新增一个真实 `UICollectionViewCompositionalLayout` 页面，用 UIKit orthogonal section 同时表达：

1. 根 `UICollectionView` 的纵向滚动；
2. section 内的横向业务滚动；
3. 根纵向滚动与 AnchorPager `verticalScrollView` 的连续 handoff；
4. section 横向滚动与 Pageboy 横向分页的真实 recognizer 竞争。

v0.7 已通过真实 UIKit 验证：任意业务横向 `UIScrollView` 自动优先于 Pageboy 当前不是已交付能力，`pagingPan.require(toFail: childPan)` 与附加隐式 guard 均不能安全使用。Compositional Layout 的 orthogonal section 由 UIKit 管理，是否形成不同的合法 winner 必须以新的真实 UI RED/GREEN 为准，不能由静态层级推断。

第六页接入后的相邻回归进一步暴露出旧第五页测试的边界依赖：横向业务页原来位于 Pageboy 末端，即使 Pageboy 抢到 pan 也无法提交下一页，所以“页面仍为 horizontal”并不等于业务横向 scroll 真正赢得竞争。追加第六页后，同一真实拖动稳定提交 index 5，完整状态探针变为 `page=compositional`。因此“index 4 保持默认交互分页”和“index 4 的业务横向区域不切页”不能同时成立。

## 目标

1. 在现有五个 Example 页面之后追加一个组合布局页，旧页面索引与语义保持不变。
2. 使用单个根 `UICollectionView` 和 `UICollectionViewCompositionalLayout` 同时提供纵向主滚动与横向 orthogonal section。
3. 只把根 `UICollectionView` 显式登记为 `anchorPagerScrollView`。
4. 纵向真实 drag 继续满足 Header/container 先折叠、根 CollectionView 后滚动的既有 handoff。
5. orthogonal section 命中区域的横向 drag 能产生可观测的横向进度，且不带动 Header、`verticalScrollView` 或 child 纵向距离。
6. 横向业务页与组合布局页都提交页面级策略，静态关闭各自页面的 Pageboy 横向拖拽分页；Tabman bar 与公开 `setSelectedIndex(_:animated:)` 仍可离页。
7. 保持业务 scroll delegate、pan delegate、`bounces`、`alwaysBounceVertical` 与 `isScrollEnabled` 所有权。
8. 如果真实 UI 暴露框架冲突，在同一专项内按根因继续修复并完成全量验收；不得用方向锁、强制 reset 或私有层级补丁掩盖问题。

## 非目标

1. 不在 RED 前宣称 AnchorPager 已支持任意嵌套横向业务 scroll 自动优先于 Pageboy。
2. 不把 UIKit 为 orthogonal section 创建的内部 scroll view 登记为纵向 target。
3. 不遍历、缓存或依赖 UIKit 私有类名、固定 subview 层级或私有 selector。
4. 不替换业务 `UIScrollView.delegate`、任一内建 pan delegate，也不切换 `isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。
5. 不修改 Pageboy containment、selection transaction、appearance lifecycle、Store generation、managed inset 或 offset snapshot 契约；只把页面级策略作为现有 reload metadata transaction 的一部分原子提交。
6. 不为单个 Example 场景增加全局方向锁或 contentSize/velocity 轴向启发式。
7. 不提前实现 v0.8 的 `scrollsToTop` owner 或尺寸恢复能力。
8. 不继续依赖“横向业务页恰好位于分页末端”掩盖 Pageboy 与业务横向 pan 的真实竞争。

## 方案比较

### 采用：单个纵向 UICollectionView + 原生 orthogonal section

根 CollectionView 使用垂直主轴的 `UICollectionViewCompositionalLayout`。第一个 section 设置 `orthogonalScrollingBehavior = .continuousGroupLeadingBoundary`，后续 section 使用普通纵向组并提供足够内容高度。

优点：

1. 直接验证用户指定的 Compositional Layout 混合轴能力。
2. 纵向 target 只有一个明确实例，符合现有 scroll discovery 与 ownership 契约。
3. 横向进度可以通过公开的 `visibleItemsInvalidationHandler` 取得，不需要发现 UIKit 内部 scroll view。
4. 页面 data source、delegate、lifecycle 与测试探针都留在 Example，不把业务类型带入框架。

### 不采用：纵向 CollectionView cell 内嵌独立横向 CollectionView

该方案可以显式持有两个 CollectionView，测试和 recognizer identity 更容易控制，但它验证的是普通嵌套 scroll，而不是 Compositional Layout 的 orthogonal section，偏离本次目标。

### 不采用：方向锁、私有 scroll discovery 或 recognizer 重置

方向锁不能归还错误建立的 inset、snapshot、boundary 和 binding ownership；私有层级 discovery 在系统版本变化时不稳定；切换 recognizer enabled 或强制 reset 会中断当前触摸并破坏 velocity/terminal 语义。三者都不能作为根因修复。

## 手势根因修订：页面级静态横向分页策略

### 采用方案

新增一个按页面索引提供的公开 data source 策略：

```swift
func pagerViewController(
    _ pagerViewController: AnchorPagerViewController,
    allowsInteractiveHorizontalPagingAt index: Int
) -> Bool
```

`AnchorPagerViewControllerDataSource` 的 public extension 提供默认实现 `true`，因此现有接入方保持源码兼容，现有页面也保持 Pageboy 横向拖拽分页。返回 `false` 的语义仅为：当该 index 成为 committed current page 后，关闭 Pageboy 自身分页 scroll view 的交互式横向拖拽；Tabman bar 点击和 `setSelectedIndex(_:animated:)` 仍使用现有 Host explicit selection transaction。

Example 对包含横向业务内容且要求业务手势稳定获胜的 index 4、index 5 返回 `false`。结果是：

1. index 4 的横向业务 `UIScrollView` 不再与 Pageboy 争夺同向 pan，也不再因为新增后继页面而意外切页；
2. index 5 的 orthogonal section 成为该页唯一横向手势 owner，左右双向拖拽都由 UIKit 业务内容消费；
3. index 5 的普通纵向 cell 区域不再通过横向拖拽离开该页；
4. 用户仍可点击分段栏或调用公开 API 离开 index 4、index 5；
5. 从默认允许交互分页的 index 3 可横向拖入 disabled index 4，matching did-select 提交后静态关闭目标页的后续分页拖拽。

该策略是页面级、静态、generation-aware 的能力，不承诺 hit-region 级动态 winner，也不承诺任意业务横向 child 在默认 `true` 页面自动优先于 Pageboy。

### 为什么不保留 index 4 -> index 5 的交互拖入

页面级 Bool 在 source committed page 生效。若 index 4 为 `true`，Pageboy 与该页业务横向 scroll 继续竞争，真实 UIKit 已证明 Pageboy 可以提交 index 5；若 index 4 为 `false`，Pageboy pan 不启动，也就不可能从 index 4 交互拖入 index 5。两项目标在页面级静态策略下互斥。

最小且职责闭合的取舍是让业务横向内容优先：index 4、index 5 均为 `false`，enabled-to-disabled terminal 改由不含横向业务内容的 index 3 拖入 index 4 验证。若未来必须同时支持“同页业务区域横向滚动”和“另一命中区域 Pageboy 分页”，需另立命中区域级公开契约；当前不得把该第三种状态塞入 Bool，也不得依赖业务子树发现或 recognizer reset。

### 为什么使用 data source Bool，而不是新枚举或页面关联属性

1. 当前只有“允许/不允许 Pageboy 交互式横向分页”两个稳定状态；Bool 精确表达该门禁，不为尚无语义的第三种状态扩大 Public API。
2. data source 能在 `reloadData()` 的 metadata 采集阶段按 index 同步取得策略，无需提前创建或加载业务页面。
3. 策略与 page count、title 使用同一 transaction token，可与 reload generation 原子提交；页面关联属性会把策略读取时机绑定到懒加载页面，形成 provider generation 与 visible generation 的跨层竞态。
4. 全局 `AnchorPagerPagingConfiguration` 开关无法表达不同页面的策略，并会无条件改变所有页面行为。

若未来 UIKit/第三方提供可撤销且公开的命中区级仲裁能力，应另立设计；不得把新语义追加为当前 Bool 的隐式第三状态。

## 策略数据流与所有权

### Metadata 采集

`AnchorPagerViewController.reloadData()` 在读取每个 title 的同一轮 MainActor transaction 中读取对应 Bool，并在每次 data source callback 后继续校验现有 reload transaction token。`ReloadSnapshot` 新增与 `pageCount` 等长的策略数组；重入、负 count 降级、首次 view 未加载预发布和 latest staged snapshot 仍沿用现有规则。

策略不从 page controller、`anchorPagerScrollView`、业务 view hierarchy 或 recognizer 推断，也不触发页面预加载。

### PagingHost 唯一 committed owner

`AnchorPagerPagingHostViewController.ReloadRequest` 携带策略数组。Host 继续独占 active/latest reload 与 selection transaction，并新增 committed 策略快照；Adapter 不保存策略队列或第二套 generation。

Host 只在以下 matching terminal 更新并应用策略：

1. 非空 reload terminal 已被 `AnchorPagerViewController` acknowledgement 后，提交新 page count、selected index 和策略快照；
2. matching selection did-select 或合法 missing-semantic recovery 提交新 current index 时，读取 committed 快照中该 index 的策略；
3. selection cancel 保持 source index 与既有策略不变；
4. empty terminal 清空 committed 策略，且空态不存在 Adapter；
5. stale request、旧 Adapter callback、identifier/target mismatch 和未 acknowledgement 的 reload terminal 都不得修改策略。

如果内部策略数量与 committed page count 不一致，Debug 断言、记录固定 paging 错误事件，并保守关闭 Pageboy 交互分页；正常 public data source 路径不会产生该状态。

### Adapter 第三方执行边界

Adapter 只增加 internal 执行入口，例如：

```swift
func setInteractiveHorizontalPagingEnabled(_ isEnabled: Bool)
```

该入口只写 Pageboy `PageboyViewController.isScrollEnabled`，即 Adapter 自己拥有的分页 `UIScrollView`；不得遍历或修改业务 child 的 `isScrollEnabled`，也不得设置 Pageboy/业务 scroll 或 pan delegate。相同值重复应用为 no-op。

Pageboy 5.0.2 的公开实现会把该值同步写到当前内部 paging scroll view，并在内部 page view controller 重建时重新应用；程序化 `scrollToPage` 不依赖该值。因此 bar/API 选择路径保持可用。任何 Pageboy 版本升级都必须重新验证这一契约。

### Terminal 时序

1. `enabled source -> disabled target`：整个 interactive transition 使用 source 的已提交 `true`；matching did-select 到达后，Host 先提交 target index 并让 Adapter 应用 `false`，再向 ViewController/Store 转发 public current commit，最后结束现有 transaction。
2. `disabled source -> enabled/disabled target`：横向 pan 无法启动；bar/API 仍可建立 programmatic transaction。matching did-select 后按 target 策略切换。
3. programmatic cancel：不在 will-select 或 completion 前乐观切换策略，cancel 后继续使用 source committed 策略。
4. reload 修改当前页策略：pending snapshot 不影响可见页；只有 matching reload acknowledgement 才切换，旧 generation callback 不能覆盖新策略。
5. adapter install/replacement：默认保持 Pageboy 的 `true`，matching 非空 reload terminal 后立即重放 committed target 策略；用户事件之间不存在异步开关窗口。

策略切换不创建新的 `AnchorPagerInteractionState`，不参与 GesturePriorityCoordinator，也不成为第二个 selection、reload 或 recognizer owner。

## 页面结构

新增独立文件：

```text
Examples/AnchorPagerExample/AnchorPagerExample/
  ExampleCompositionalPageViewController.swift
```

不继续把新页面实现追加到现有 `ExamplePagerViewController.swift` 大文件。

页面使用以下结构：

```text
ExampleCompositionalPageViewController
└─ UICollectionView（纵向根滚动，唯一 anchorPagerScrollView）
   ├─ Section 0：横向卡片
   │  └─ orthogonalScrollingBehavior = continuousGroupLeadingBoundary
   └─ Section 1...N：普通纵向卡片/列表
```

页面追加为 index 5，现有 index 0...4 保持：

```text
0 empty
1 short
2 long
3 plain
4 horizontal
5 compositional
```

页面标题为“组合布局页”，内部稳定 identifier 为 `compositional`。`pageIdentifier(at:)`、初始 index clamp、reload 重建和状态探针同步扩展到第六页。

## Layout 契约

1. 使用 iOS 14 可用的 Compositional Layout API，不使用 iOS 17 才提供的 `orthogonalScrollingProperties`。
2. Section 0 使用可见宽度小于容器宽度的横向 group，确保首屏能表达后续内容并形成真实横向 range。
3. 普通纵向 section 提供足够 item 数，使根 CollectionView 在常见 iPhone Simulator viewport 下具有确定的纵向 range。
4. Cell 使用公开 UIKit API 配置，不依赖 storyboard 或额外第三方依赖。
5. `visibleItemsInvalidationHandler` 只记录 orthogonal `contentOffset.x`、最大绝对进度和当前可见 leading item 等 Example 测试信息，不持有 UIKit 内部 scroll view。
6. 横向 handler 不写根 CollectionView offset，不调用 AnchorPager API，不成为第二个手势或 selection owner。

## 滚动目标与所有权数据流

纵向路径：

```text
root UICollectionView
  -> UIViewController.anchorPagerScrollView
  -> AnchorPagerPageStateStore committed scroll target
  -> ManagedInsetCoordinator
  -> AnchorPagerScrollCoordinator binding
  -> container pan <-> root collection pan 最小 simultaneous pair
```

横向路径：

```text
orthogonal section UIKit implementation
  -> UIKit 原生横向识别与滚动
  -> visibleItemsInvalidationHandler
  -> Example accessibility probe
```

横向路径不得进入：

- `anchorPagerScrollView`；
- PageStateStore claimed scroll identity；
- managed inset ownership；
- child distance snapshot；
- ScrollCoordinator binding；
- OverscrollCoordinator top/bottom owner；
- synthetic vertical deceleration。

## Containment 与 Lifecycle

1. `ExampleCompositionalPageViewController` original controller 继续由 Pageboy 唯一 containment。
2. 页面不额外创建 child view controller，不改变 Tabman/Pageboy appearance forwarding。
3. 新页面记录与其他 Example 页面一致的 `viewWillAppear`、`viewDidAppear`、`viewWillDisappear`、`viewDidDisappear` 事件。
4. 为避免把 `ExampleAppearanceRecorder` 的私有实现跨文件泄漏，新页面接收领域无关的 appearance callback closure；父页面负责连接现有 recorder。
5. reload 后旧页面、CollectionView、layout handler 和 closure 必须可释放，不形成 controller/layout/handler retain cycle。

## Example 状态与测试探针

现有 `ExampleScrollCoordinationState` 继续表达：

- 当前页 identifier；
- 是否存在纵向 target；
- Header collapse；
- container presentation；
- child 纵向 distance 与边界 presentation。

组合布局页新增一个 Example-only accessibility probe，至少记录：

```text
scrollDelegateStable
panDelegateStable
bounces
alwaysBounceVertical
isScrollEnabled
verticalRange
horizontalProgress
maximumHorizontalProgress
leadingHorizontalItem
```

其中横向进度只能来自 `visibleItemsInvalidationHandler` 的公开参数。probe 允许测试重置本轮最大值，但重置不得修改真实 scroll position、recognizer 或 selection。

组合布局页必须接入现有可见帧纵向采样时钟，或提供同等的显示帧采样入口，避免只记录 UIKit delegate/KVO 同轮瞬时 offset。页面离场与析构同步停止采样资源。

## 手势成功标准

### 纵向命中区域

1. 从普通纵向 cell 区域向上真实 drag。
2. Header/container 先消费 collapsible distance。
3. container collapsed 后，剩余位移进入根 CollectionView。
4. committed target 始终是根 CollectionView，orthogonal section 不参与纵向 owner。

### Orthogonal 横向命中区域

1. 从横向卡片内部执行带少量纵向分量的真实横向 drag。
2. `maximumHorizontalProgress` 明显大于阈值。
3. public/committed 页面仍为 `compositional`，不产生 Pageboy selection terminal。
4. Header collapse、container offset、child distance 和纵向 presentation 保持在统一 epsilon 内。
5. 根 CollectionView delegate、pan delegate 与业务配置保持基线。

### 非 Orthogonal 横向命中区域

1. 从普通纵向 cell 区域执行真实横向 drag。
2. committed page 保持 index 5，selection trace 为空，orthogonal 横向进度也不变化。
3. 点击分段栏可从 index 5 切到 index 4；公开 API 也可完成同一 explicit selection。
4. index 4 业务横向区域的真实 drag 保持 committed page 为 horizontal，业务横向 range 可见，纵向 presentation 为零。
5. 从默认允许交互分页的 index 3 横向拖入 index 4；提交 index 4 后，后续 Pageboy 横向拖拽关闭，证明 matching target terminal 的策略切换。

## 冲突分型与修复门禁

真实 RED 按以下结果分类：

1. **页面被切走：** Pageboy paging pan 抢占 orthogonal 横向手势。
2. **Header/container 移动：** 根纵向 target 或方向竞争产生错误纵向输入。
3. **横向内容不动且页面不切换：** orthogonal section 布局、range、命中或测试手势无效。
4. **多方同时变化：** 同一手势出现多个可见 owner，需检查 UIKit winner 与现有 interaction admission。

如果第 1、2 或 4 类需要修改 Framework，必须先证明修复可在以下边界内闭合：

1. 使用 UIKit/Tabman/Pageboy 已公开且当前版本可验证的入口；
2. 不读取业务私有 view tree，不设置既有 recognizer delegate；
3. 不建立已被 v0.7 真实 UI 否定的 `pagingPan -> arbitrary childPan` 关系；
4. 不新增第二个 selection、interaction、offset 或 boundary owner；
5. 不改变横向-only 页 nil target 和普通纵向页既有行为。

当前第 1 类真实 RED 已完成分型，且用户已确认采用页面级静态策略。后续实现只允许沿本文的 data source metadata → PagingHost committed snapshot → Adapter Pageboy 开关路径闭合；不得在旧设计上临时追加 hit-test 特判、异步 delay、gesture reset 或私有层级遍历。

## TDD 策略

### Example 单元 RED

1. data source 页面数要求为 6，前五页标题和索引不变，第六页标题为“组合布局页”。
2. index 5 页面是独立组合布局 controller，根布局类型为 `UICollectionViewCompositionalLayout`。
3. `anchorPagerScrollView` 与根 CollectionView identity 相同，纵向 range 大于 epsilon。
4. ownership probe 的 delegate、pan delegate、bounce/enable 配置均等于业务基线。
5. 横向进度值类型的 record、maximum、leading item 和 reset 序列化确定可重复。
6. appearance callback 与 reload 后新 generation 页面身份保持现有语义。
7. Example data source 对 index 4、index 5 返回 `false`，index 0...3 继承默认 `true`。

旧实现会首先精确失败于页面数仍为 5、index 5 不存在和组合布局探针缺失。

### Example 真实 UI RED

新增或聚焦以下真实 coordinate drag：

1. `testCompositionalVerticalRegionHandsOffToCollectionView`：普通纵向区域向上 drag，最终 `collapse >= 0.99` 且 child distance 大于零。
2. `testCompositionalOrthogonalRegionOwnsHorizontalDrag`：横向区域左右双向 drag，横向进度分别增加/减少，页面不变、纵向指标和 presentation 均小于 epsilon。
3. 将旧 `testCompositionalNonOrthogonalRegionStillPages` 改为页面级契约：非正交区域横向 drag 不切页，bar/API 仍可离开 index 5。
4. 从 index 3 横向拖入 index 4 后拖动横向业务区域，证明 target terminal 后已关闭 Pageboy pan，页面保持 horizontal。
5. 通过 bar/API 从 index 4 进入 index 5，再拖动 orthogonal 区域，证明 explicit selection terminal 同样重放目标页 `false` 策略。
6. 相邻 reload/rebind 回归：reload 或离场再返回后，index 5 仍提交根 CollectionView target 和 `false` 策略，旧页面资源不再更新 probe。

测试必须以 `visibleItemsInvalidationHandler` 的进度和现有 layout/scroll state 同时取证；不得只断言元素存在，也不得通过测试代码直接写 `contentOffset` 代替真实手势。

### Framework 测试

先建立 Framework RED，再做最小实现：

1. Public data source 默认实现为 `true`，旧 conformer 无需新增方法即可编译；显式逐页 Bool 在 reload metadata 中按 index 保序。
2. data source callback 重入时旧 transaction 的部分策略数组零写入；latest snapshot 与 title/page count 同 generation。
3. pending reload 不改变 committed Adapter 状态；matching acknowledged reload 才提交，stale/未 acknowledgement terminal 不应用。
4. `enabled -> disabled` interactive did-select 在 public current commit 前应用 target 策略；cancel 保持 source 策略。
5. disabled source 的 Pageboy pan 不开始 interactive selection，但 API 与 bar 仍能完成 programmatic transaction；target 为 enabled 时 terminal 后恢复。
6. nonanimated/animated、missing-semantic recovery、active + latest pending、reload-first drain 和 empty teardown 不因策略新增而改变 terminal 计数或顺序。
7. Adapter surface 初装、Pageboy 内部 surface refresh 和 Adapter replacement 会重放 committed policy；相同值不重复日志。
8. 业务 child 的 scroll delegate、pan delegate、`isScrollEnabled`、`bounces`、`alwaysBounceVertical` 保持不变；container/current-child simultaneous pair、interactive-pop relation、scroll discovery 与 overscroll 不变。

## 日志

页面级策略是新的 committed paging 状态，必须在 `paging` category 记录固定事件：

- `paging.interactivePaging.enabled`
- `paging.interactivePaging.disabled`
- `paging.interactivePaging.invalidMetadata`

enabled/disabled 只在 Adapter 实际状态变化时记录，reload/selection/pan 热路径中的相同值为 no-op；invalid metadata 对同一异常 transaction 只记录一次。日志不得包含 index、页面标题、业务 cell、offset 数值或 view hierarchy，并通过注入 sink 测试。

## 2026-07-16 真实 UI 门禁结论

首轮门禁证明 Pageboy paging pan 与 UIKit orthogonal 内部 pan 的同向竞争会使业务 pan 无法成为 winner。已验证并撤回的 `pagingPan -> childPan`、业务子树/共同祖先 hit-region guard、simultaneous/non-preventing guard 不能复用；Compositional Layout 又不通过公开 API 暴露 orthogonal 内部 scroll/pan identity，因此不能建立更窄且可撤销的静态 failure relation。

页面级 Framework 策略实现后的证据为：

1. Framework metadata、Adapter 开关、Host committed snapshot 与 selection terminal 已分别完成 TDD；默认 `true`、显式逐页策略、reload 重入、stale/rejected terminal、missing semantic、empty teardown、日志与业务 child ownership 回归均通过。
2. Example target-level 单元测试 18/18 通过；第六页、根 `UICollectionView` identity、纵向 range、业务 delegate/pan/bounce 配置、横向进度纯值语义和 index 5 `false` 均成立。
3. `/private/tmp/AnchorPagerTask6OrthogonalGreen-20260716-1520.xcresult` 中 orthogonal 左右真实 drag 通过；`/private/tmp/AnchorPagerTask6PagePolicyGreen-20260716-1525.xcresult` 中页面级非正交禁用、bar/API 离页和原 index 4 拖入 index 5 均通过。
4. 六项相邻回归 `/private/tmp/AnchorPagerTask6PagePolicyRegression-20260716-1527.xcresult` 为 4 pass、2 fail；其中横向业务页失败于终态 probe 不再是 horizontal，interactive-pop 另行保留复验门禁。
5. 横向业务用例在关闭代码覆盖率后单独复验仍稳定失败。诊断结果 `/private/tmp/AnchorPagerTask6HorizontalDiagnostic-20260716.xcresult` 明确记录 `page=compositional;hasScrollTarget=1`，其余 container/Header/child presentation 均为零。这证明新增后继页面后，index 4 的 Pageboy pan 提交了 index 5，而不是纵向 owner 回归或测试基础设施误报。
6. 旧横向-only 设计所写“该测试不把业务横向 scroll 一定赢过 Pageboy 作为条件”只在 index 4 位于末端时成立；追加第六页后，“页面仍为 horizontal”已经客观要求 Pageboy 不提交后继页。继续让 index 4 返回默认 `true` 会依赖失效的边界偶然性。

### 已确认修订边界

截至本门禁记录：

1. 已实现的 Public Bool、Host committed snapshot 与 Adapter Pageboy 开关边界保持不变，不回退 Framework TDD，也不增加第二套手势策略。
2. 不允许为当前 Example 加入方向锁、私有层级 discovery、recognizer reset、动态 `isScrollEnabled` 或手工 offset 驱动。
3. “orthogonal 区域由业务滚动、同页其他区域仍由 Pageboy 分页”的命中区级双 owner 目标，无法在现有公开 UIKit/Tabman/Pageboy 入口和既定 ownership 约束内闭合。
4. index 4、index 5 都属于“页面内横向业务手势必须稳定获胜”的页面，Example 必须对二者返回 `false`；index 0...3 保持默认 `true`。
5. enabled-to-disabled 的真实 interactive terminal 由 index 3 拖入 index 4 验证；index 4 与 index 5 之间只通过 Tabman bar 或公开 API 切换。
6. 横向业务页原“下半区域左右滑动切换页面”的提示与新策略冲突，实施时改为通过分段栏或公开入口切页的准确说明，不保留不可用的手势承诺。

二次修订已完成用户书面复核、计划同步、Example 策略 RED/GREEN、UI 合同迁移和 interactive-pop 隔离复验；最终实现未越过上述边界。

### 最终验收

生产代码 HEAD `db4b9bc`。Framework 439/439，结果包 `/private/tmp/AnchorPagerCompositionalPolicyFramework-20260716.xcresult`；Example 70/70（19 单元 + 51 UI），结果包 `/private/tmp/AnchorPagerCompositionalPolicyExample-20260716.xcresult`；generic Simulator build 结果包 `/private/tmp/AnchorPagerCompositionalPolicyBuild-20260716.xcresult`。三份结果均为 0 error、0 warning、0 analyzer warning，测试 0 fail、0 skip；诊断中的 UIKit 约束、gesture dependency cycle、appearance imbalance、KVO/observer 与 display-link/resource 问题关键字零命中。fresh-pass 覆盖 `0db297d...db4b9bc`，终态 Critical 0、Important 0、Minor 0。

## 文档与计划

1. 本设计登记到 `AGENTS.md` 必读文档。
2. 用户复核本文后修订并重新登记对应详细实施计划。
3. 实施完成时同步更新 `README.md`、`docs/requirements.md`、`docs/architecture.md`、`docs/task-list.md`、v0.7 规格/计划和 AGENTS 当前阶段门禁。
4. 文档必须区分“Compositional Layout orthogonal section 已验证能力”和“任意业务横向 UIScrollView 自动优先”限制，不能用单个用例扩大能力声明。

## 完整验收

实施完成后至少运行：

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=<available simulator>' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=<available simulator>' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
```

同时检查：

1. Framework 与 Example 测试 0 fail、0 skip；
2. xcresult 0 error、0 warning、0 analyzer warning；
3. UIKit 约束、gesture dependency cycle、appearance imbalance、资源泄漏关键词零命中；
4. framework 源码 ownership 静态扫描；
5. 任务级自审和最终 fresh-pass；
6. 没有未解释的工作区改动。

## 影响范围

1. **Public API：** Data source 增加带默认实现的逐页 Bool；默认 `true` 保持旧接入行为。
2. **内部分层：** ViewController 负责 metadata 采集，PagingHost 负责 committed policy，Adapter 只写 Pageboy 自有 `isScrollEnabled`；Interaction/Scroll/Overscroll/Store 不新增 owner。
3. **Containment/lifecycle：** Pageboy 保持唯一 page containment；新页复用既有 appearance 语义。
4. **Scroll discovery：** 显式提交根 CollectionView，orthogonal 内部 scroll 不参与 discovery。
5. **Inset/snapshot：** managed inset 和 child distance 只作用于根 CollectionView。
6. **Paging adapter：** 新增静态 Pageboy 交互分页开关入口，不保存策略 generation/queue，不影响 explicit selection。
7. **Gesture/overscroll：** 纵向复用 committed pair；不新增 failure relation、delegate、方向锁或动态 hit-test owner。
8. **日志：** 新增 committed policy 状态变化/异常 metadata 固定事件及 sink 测试。
9. **测试/示例：** 新增独立页面、Public/Host/Adapter TDD、三类真实手势、bar/API 和 reload/rebind 相邻回归。
10. **文档：** 新规格、后续计划及长期能力/限制说明同步更新。

## 架构停机条件

出现以下任一情况必须停止局部实现并修订设计：

1. 需要把 orthogonal 内部 scroll view 登记为纵向 target。
2. 需要设置或替换业务 scroll/pan delegate，修改业务 bounce 或 `isScrollEnabled`。
3. 需要依赖 UIKit 私有类名、固定 view hierarchy、KVC 或 private selector。
4. 需要重建 Pageboy containment、绕过 Host selection transaction 或复制 Interaction Coordinator 状态。
5. 需要增加全局方向锁、异步 delay、强制 gesture reset 或重复 layout 掩盖真实 winner。
6. 需要在已确认 Bool 之外继续扩大 Public API，或让 Bool 隐式承载命中区级第三种状态。
7. 连续最小修复在不同共享状态产生新的 owner、terminal 或 lifecycle 问题。

## 设计自审

1. 页面只有一个明确纵向 target，混合轴所有权与横向-only nil target 契约不冲突。
2. orthogonal 横向进度只通过公开 handler 观察，不读取 UIKit 私有层级。
3. Host 成为页面策略唯一 committed owner；Pageboy、Store、Inset、Scroll、Overscroll 与 Interaction 的其他事实源保持不变。
4. 真实 UI 同时验证纵向 handoff、正交横向 winner、页面其他区域不分页以及 bar/API 离页能力，没有用直接 offset 写入替代手势。
5. 已明确 v0.7 任意业务横向 child 的既有限制；业务手势稳定获胜来自接入方对 index 4、index 5 显式返回 `false`，不会被表述为自动优先能力。
6. Public API 只增加带默认实现的逐页 Bool；私有 API、delegate 接管和补丁式修复均设置了停机门禁。
7. 测试、日志、资源释放、文档、完整门禁和自审都有明确完成条件，没有 TODO、TBD 或未决方案。
