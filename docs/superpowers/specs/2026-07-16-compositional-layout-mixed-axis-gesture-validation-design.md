# Compositional Layout 混合轴页面与手势冲突验证设计

**日期：** 2026-07-16

**状态：** 用户已确认设计；待详细实施计划、TDD、真实 UI 验收与完整门禁

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

## 目标

1. 在现有五个 Example 页面之后追加一个组合布局页，旧页面索引与语义保持不变。
2. 使用单个根 `UICollectionView` 和 `UICollectionViewCompositionalLayout` 同时提供纵向主滚动与横向 orthogonal section。
3. 只把根 `UICollectionView` 显式登记为 `anchorPagerScrollView`。
4. 纵向真实 drag 继续满足 Header/container 先折叠、根 CollectionView 后滚动的既有 handoff。
5. orthogonal section 命中区域的横向 drag 能产生可观测的横向进度，且不带动 Header、`verticalScrollView` 或 child 纵向距离。
6. orthogonal section 之外的横向 drag 继续由 Pageboy 完成页面切换。
7. 保持业务 scroll delegate、pan delegate、`bounces`、`alwaysBounceVertical` 与 `isScrollEnabled` 所有权。
8. 如果真实 UI 暴露框架冲突，在同一专项内按根因继续修复并完成全量验收；不得用方向锁、强制 reset 或私有层级补丁掩盖问题。

## 非目标

1. 不在 RED 前宣称 AnchorPager 已支持任意嵌套横向业务 scroll 自动优先于 Pageboy。
2. 不把 UIKit 为 orthogonal section 创建的内部 scroll view 登记为纵向 target。
3. 不遍历、缓存或依赖 UIKit 私有类名、固定 subview 层级或私有 selector。
4. 不替换业务 `UIScrollView.delegate`、任一内建 pan delegate，也不切换 `isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。
5. 不修改 Pageboy containment、selection transaction、appearance lifecycle、reload generation、managed inset 或 offset snapshot 契约。
6. 不为单个 Example 场景增加全局方向锁或 contentSize/velocity 轴向启发式。
7. 不提前实现 v0.8 的 `scrollsToTop` owner 或尺寸恢复能力。

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
2. Pageboy 仍可从 index 5 切到相邻 index 4，或从 index 4 切入 index 5。
3. 不因组合布局页存在而给整个页面安装全局横向阻断。

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

若满足根因修复必须扩大 Public API 或引入显式业务横向接入契约，则暂停生产实现，先修订本文、requirements、architecture 和计划，并再次取得用户确认。不得在旧设计上临时追加 hit-test 特判、异步 delay、gesture reset 或私有层级遍历。

## TDD 策略

### Example 单元 RED

1. data source 页面数要求为 6，前五页标题和索引不变，第六页标题为“组合布局页”。
2. index 5 页面是独立组合布局 controller，根布局类型为 `UICollectionViewCompositionalLayout`。
3. `anchorPagerScrollView` 与根 CollectionView identity 相同，纵向 range 大于 epsilon。
4. ownership probe 的 delegate、pan delegate、bounce/enable 配置均等于业务基线。
5. 横向进度值类型的 record、maximum、leading item 和 reset 序列化确定可重复。
6. appearance callback 与 reload 后新 generation 页面身份保持现有语义。

旧实现会首先精确失败于页面数仍为 5、index 5 不存在和组合布局探针缺失。

### Example 真实 UI RED

新增或聚焦以下真实 coordinate drag：

1. `testCompositionalVerticalRegionHandsOffToCollectionView`：普通纵向区域向上 drag，最终 `collapse >= 0.99` 且 child distance 大于零。
2. `testCompositionalOrthogonalRegionOwnsHorizontalDrag`：横向区域带少量纵向分量 drag，横向进度大于阈值、页面不变、纵向指标和 presentation 均小于 epsilon。
3. `testCompositionalNonOrthogonalRegionStillPages`：非正交区域横向 drag 仍切换到相邻页。
4. 相邻 reload/rebind 回归：reload 或离场再返回后，index 5 仍提交根 CollectionView target，旧页面资源不再更新 probe。

测试必须以 `visibleItemsInvalidationHandler` 的进度和现有 layout/scroll state 同时取证；不得只断言元素存在，也不得通过测试代码直接写 `contentOffset` 代替真实手势。

### Framework 测试

如果 Example 原生方案直接 GREEN，Framework 生产代码不改，只运行现有 Framework 全量回归并记录“无需新增框架日志/测试”的理由。

如果 RED 触发 Framework 根因修复，则先为具体失败建立 Framework/UIKit RED，再做最小实现；必须同步覆盖：

1. Pageboy selection commit/cancel；
2. container/current child 最小 simultaneous pair；
3. 系统返回优先级；
4. 横向-only nil target；
5. 业务 delegate/pan/bounce ownership；
6. teardown、identity replacement 和日志。

## 日志

组合布局页和 accessibility probe 属于 Example 测试基础设施，不是框架关键状态，因此原生方案直接通过时不新增 `AnchorPagerLogger` 事件，避免在横向 layout 热路径产生普通日志。

若框架修复引入新的稳定状态、失败关系或 transaction boundary，必须使用既有 `gesture`/`paging`/`resource` category，事件只记录状态变化且同步增加注入 sink 测试；不得记录页面标题、业务 cell、offset 数值或 view hierarchy。

## 文档与计划

1. 本设计登记到 `AGENTS.md` 必读文档。
2. 用户复核本文后创建并登记对应详细实施计划。
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

1. **Public API：** 初始方案不变；任何扩大都触发设计停机与重新确认。
2. **内部分层：** 初始只增加 Example page/probe；Framework coordinator/adapter 不预改。
3. **Containment/lifecycle：** Pageboy 保持唯一 page containment；新页复用既有 appearance 语义。
4. **Scroll discovery：** 显式提交根 CollectionView，orthogonal 内部 scroll 不参与 discovery。
5. **Inset/snapshot：** managed inset 和 child distance 只作用于根 CollectionView。
6. **Paging adapter：** 初始不变；真实冲突若要求修改，必须先通过根因门禁。
7. **Gesture/overscroll：** 纵向复用 committed pair；横向 winner 以真实 UI 取证，不预装 relation。
8. **日志：** 原生 Example 方案无需新框架日志；框架修复才同步增加状态日志和测试。
9. **测试/示例：** 新增独立页面、结构单测、三类真实手势和 reload/rebind 相邻回归。
10. **文档：** 新规格、后续计划及长期能力/限制说明同步更新。

## 架构停机条件

出现以下任一情况必须停止局部实现并修订设计：

1. 需要把 orthogonal 内部 scroll view 登记为纵向 target。
2. 需要设置或替换业务 scroll/pan delegate，修改业务 bounce 或 `isScrollEnabled`。
3. 需要依赖 UIKit 私有类名、固定 view hierarchy、KVC 或 private selector。
4. 需要重建 Pageboy containment、绕过 Host selection transaction 或复制 Interaction Coordinator 状态。
5. 需要增加全局方向锁、异步 delay、强制 gesture reset 或重复 layout 掩盖真实 winner。
6. 需要扩大 Public API 但尚未更新设计并取得用户确认。
7. 连续最小修复在不同共享状态产生新的 owner、terminal 或 lifecycle 问题。

## 设计自审

1. 页面只有一个明确纵向 target，混合轴所有权与横向-only nil target 契约不冲突。
2. orthogonal 横向进度只通过公开 handler 观察，不读取 UIKit 私有层级。
3. Pageboy、Store、Inset、Scroll、Overscroll 与 Interaction 的现有唯一事实源保持不变。
4. 真实 UI 同时验证纵向 handoff、正交横向 winner 和页面其他区域的 Pageboy 能力，没有用直接 offset 写入替代手势。
5. 已明确 v0.7 任意业务横向 child 的既有限制，单个 Compositional Layout 用例不会自动扩大公开能力声明。
6. Public API 扩大、私有 API、delegate 接管和补丁式修复均设置了停机门禁。
7. 测试、日志、资源释放、文档、完整门禁和自审都有明确完成条件，没有 TODO、TBD 或未决方案。
