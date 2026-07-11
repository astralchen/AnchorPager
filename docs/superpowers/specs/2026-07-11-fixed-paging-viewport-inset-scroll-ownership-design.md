# 固定分页视口、Inset Ownership 与纵向滚动所有权设计

**日期：** 2026-07-11
**状态：** 已确认设计，尚未实现
**适用版本：** v0.3、v0.4、v0.5

## 背景

v0.2 已把主容器滚动范围与 Header/paging viewport 解耦，但当前
`AnchorPagerPagingAdapter` 的 top 和 height 都随 Header 折叠进度变化。该实现可以完成
Header 可视布局，却会让 Pageboy child 的 viewport 高度在纵向滚动热路径中持续变化，增加
child layout、content size、scroll indicator 和后续 container/child offset 交接的不稳定性。

同时，旧需求把 child managed top inset 描述为“Header + 分段栏预留空间”。这与当前真实层级不符：

```text
AnchorPager viewport
├─ Header
└─ Tabman adapter（top = Header.bottom）
   ├─ Tabman bar
   └─ Pageboy child
```

Header 和本地顶部遮挡已经由 adapter 的容器坐标消化；只有 Tabman adapter 内部实际覆盖
Pageboy child 的 bar 属于 child 局部 top obstruction。继续把 Header 或容器顶部遮挡写入 child
`contentInset.top` 会重复预留空间。

本设计固定 v0.3–v0.5 的分页几何、bar 高度、managed inset、page state 和纵向滚动 owner 边界。

## 目标

1. 保留 Header 在上、Tabman adapter 位于 Header 下方、bar 由 Tabman 管理的层级。
2. Header 折叠时只移动 Tabman adapter，不在滚动热路径改变 adapter 和 Pageboy child 高度。
3. child managed top 只表达 Tabman adapter 内的真实 bar obstruction。
4. 允许 bar 高度由 Tabman 自适应，也允许调用方显式覆盖高度。
5. AnchorPager 独立管理 child content inset、indicator inset 和 UIKit 自动 inset 策略。
6. 外部 inset 与 managed inset 使用可逆的差量所有权，不覆盖调用方已有额外 inset。
7. page state、inset ownership、滚动 owner 和 Tabman/Pageboy adapter 保持单向职责。
8. 为 v0.5 建立 container 先折叠、child 后滚动的唯一 owner 不变量。

## 非目标

1. v0.3 不实现 page cache window、完整 appearance lifecycle 或 offset snapshot 淘汰策略。
2. v0.3 不实现 container/child 的纵向手势交接。
3. v0.5 不实现顶部 overscroll mode；该职责仍属于 v0.6。
4. v0.5 不实现横向分页、系统返回手势、程序化分页和尺寸 transition 的完整交互状态机；该职责仍属于 v0.7。
5. 不把 Tabman、Pageboy、TMBar 或其内部状态暴露到 AnchorPager public API。

## 依赖源码结论

当前锁定版本为 Tabman 4.0.1、Pageboy 5.0.2。

源码确认：

1. Pageboy 把内部 `UIPageViewController.view` 约束到 Pageboy view 四边，因此 page child
   与 adapter viewport 同尺寸。
2. Tabman 的 `.top` bar 位于独立 `topBarContainer`，固定在 Tabman safe area 顶部；它覆盖
   Pageboy child，而不是缩短 Pageboy child frame。
3. Tabman 公开的 `barInsets.top` 来自 `topBarContainer.bounds.height`，可以作为实际 bar
   obstruction 的稳定 internal 输入。
4. Tabman 4.0.1 当前有效的 `AutoInsetter` 主要通过 child
   `additionalSafeAreaInsets` 表达 bar inset；源码中旧的 contentInset/contentOffset calculator
   没有被当前主路径调用。
5. AnchorPager 必须继续在 adapter `viewDidLoad` 前设置
   `automaticallyAdjustsChildInsets = false`，避免 Tabman 与 AnchorPager 同时拥有 child inset。

AnchorPager 只读取 Tabman public `barInsets`，不访问 `topBarContainer`、`AutoInsetter`、
`InsetStore` 或 Pageboy 内部 scroll view。

## Public API 调整

`AnchorPagerBarConfiguration.height` 改为 optional：

```swift
public struct AnchorPagerBarConfiguration: Sendable, Equatable {
    public var height: CGFloat?

    public static let `default` = AnchorPagerBarConfiguration()

    public init(height: CGFloat? = nil) {
        self.height = height
    }
}
```

语义：

1. `nil`：不向实际 Tabman bar 添加高度约束，由 Tabman bar 的 intrinsic content size 和布局决定。
2. 非 `nil`：internal paging adapter 给实际 Tabman bar 添加高度约束。
3. 负数或非有限显式高度在 Debug 下 assertion，Release 中按 `0` 处理并记录诊断日志。
4. 最终 bar 几何始终以 Tabman 完成布局后的 `barInsets.top` 为事实来源；配置值只是布局策略。
5. 默认值从当前 `48` 改为 `nil`。这是计划中的 public API 语义变更，必须在 v0.3 实现、DocC、README 和测试中同步完成。

## 固定高度 Paging Adapter

### 几何模型

设：

```text
topPinY = bounds.minY + topObstruction
collapsedHeaderBottom = topPinY + collapsedHeaderHeight
currentHeaderBottom = topPinY + currentVisibleHeaderHeight
```

Tabman adapter frame 为：

```text
adapter.minY = currentHeaderBottom
adapter.height = bounds.maxY - collapsedHeaderBottom
```

核心不变量：

1. `adapter.minY` 随 Header 展开/折叠移动。
2. `adapter.height` 只在 bounds、safe area obstruction 或 resolved collapsed Header height
   等结构性输入变化时更新。
3. 普通纵向滚动热路径不得修改 adapter height。
4. Header 展开时 adapter 底部会超出 viewport，超出部分由已有
   `viewportView.clipsToBounds = true` 裁剪。
5. Header 完全折叠时 adapter 底部与 AnchorPager viewport 底部对齐。
6. bottom obstruction 不缩短 adapter；它通过 child managed bottom inset 和 indicator inset 避让。

Pageboy child 的 bounds 在 Header 折叠热路径中保持不变。旋转、Split View 或 window bounds
变化属于结构性布局，可以改变 adapter 和 child viewport 尺寸。

### LayoutEngine 输出语义

LayoutEngine 继续负责：

1. resolved Header expanded/collapsed height。
2. collapse offset/progress。
3. Header frame。
4. adapter 的动态 top 和固定高度 frame。
5. container collapsible distance。

LayoutEngine 不再把“顶部遮挡 + expanded Header + bar”命名为 child managed inset target。
bar 高度来自 Tabman 布局后的 adapter callback，不应成为 Header 纯计算层的先验输入。

`AnchorPagerLayoutContext.barFrame` 和无 obstruction content frame 在 barInsets 可用后更新。
首次还没有实际 barInsets 时可以复用最近一次有效值；没有缓存时使用 `0`，收到 adapter
布局回调后幂等收敛。该两阶段布局不得反向改变 adapter height，避免形成 bar measurement 与
container geometry 的反馈闭环。

## Bar Geometry 数据流

```text
configuration.bar.height
├─ nil ────────> Tabman 自适应布局
└─ value ──────> internal bar height constraint
                         ↓
                 Tabman viewDidLayoutSubviews
                         ↓
                 public barInsets.top
                         ↓
          PagingAdapter internal delegate callback
                         ↓
      LayoutContext + ManagedInsetCoordinator
```

Paging adapter 的回调只返回 `UIEdgeInsets` 或领域无关的 internal value，不返回 Tabman 类型。
adapter 只在 resolved barInsets 变化时回调；重复布局不得产生重复普通日志或重复 inset 写入。

## Managed Inset Ownership

### Child 局部目标

```text
managedContentInset.top = pagingAdapter.barInsets.top
managedContentInset.bottom = localBottomObstruction
managedIndicatorInset.top = pagingAdapter.barInsets.top
managedIndicatorInset.bottom = localBottomObstruction
```

Header height、Header top behavior、container top obstruction 不进入 child managed top。
left/right 默认 managed value 为 `0`，必须保留调用方现有值。

indicator 的 top/bottom 必须由 AnchorPager 完整接管：top 不得越过 Tabman bar 底部，bottom 不得与
UIKit 自动 safe area 调整重复叠加。ownership 生效期间把
`automaticallyAdjustsScrollIndicatorInsets` 设为 `false`，ownership 结束时恢复接管前的值。

fallback page scroll host 使用同一 managed inset 规则，不建立第二套 inset 语义。

### 所有权记录

每个被接管的 scroll view 对应一个 MainActor internal record：

```text
weak scrollView
originalContentInsetAdjustmentBehavior
originalAutomaticallyAdjustsScrollIndicatorInsets
lastManagedContentInset
lastManagedIndicatorInset
```

record 不强持有 scroll view。页面身份、缓存窗口和 offset snapshot 不存放在 inset coordinator。

### 应用算法

```text
externalContentInset = currentContentInset - lastManagedContentInset
newContentInset = externalContentInset + newManagedContentInset

externalIndicatorInset = currentIndicatorInset - lastManagedIndicatorInset
newIndicatorInset = externalIndicatorInset + newManagedIndicatorInset
```

应用前把被接管 child 的 `contentInsetAdjustmentBehavior` 设为 `.never`，并把
`automaticallyAdjustsScrollIndicatorInsets` 设为 `false`。相同目标不重复写入；若任一自动调整状态
被外部改回，下一次结构性 apply 必须重新建立 ownership。
UICollectionView 只有在实际 inset 改变且布局需要时才 invalidate layout。

调用方在 AnchorPager 管理期间可以基于当前总 inset 做增量修改。若调用方直接用一个不包含
managed 部分的绝对值覆盖整个 `contentInset`，框架无法从 UIKit 单一属性推断其意图；README
必须把“修改时保留当前 managed 部分”记录为接入限制，不为此扩大 public API。

### 归还算法

ownership 在以下时机结束：

1. reloadData 替换或移除页面。
2. page 的显式/default scroll target 改变并完成安全切换。
3. fallback host 清理。
4. page state 卸载。
5. AnchorPagerViewController 释放。

归还时：

```text
restoredContentInset = currentContentInset - lastManagedContentInset
restoredIndicatorInset = currentIndicatorInset - lastManagedIndicatorInset
```

然后恢复原始 `contentInsetAdjustmentBehavior` 和 `automaticallyAdjustsScrollIndicatorInsets`。
如果 weak scroll view 已释放，直接丢弃 record。

Swift 6 对 `deinit` 采用 nonisolated 编译检查，即使所属 `UIViewController` 整体标记为
`@MainActor`。因此控制器释放时通过 `MainActor.assumeIsolated` 同步执行 `releaseAll()`；该断言
建立在 UIKit 控制器创建、使用和释放均位于主线程的框架约束上。不得改成异步 Task、延迟归还、
`nonisolated(unsafe)` 或 `@unchecked Sendable` 来绕开释放顺序。

### Offset 与 Bar 高度变化

page state 不保存绝对 child offset，而保存：

```text
childTopOffset = -contentInset.top
childDistanceFromTop = max(0, contentOffset.y - childTopOffset)
```

top managed inset 变化后：

```text
newContentOffsetY = newChildTopOffset + childDistanceFromTop
```

这样自适应 bar、显式 bar height、Dynamic Type 或其他合法 bar 高度变化不会改变 child 相对顶部的
内容位置。bottom inset 变化不迁移 top offset。

## Page State 与 Reload

### PageStateStore

v0.4 的 page state 保存：

```text
page identity
原始 child view controller
交给 Tabman/Pageboy 的实际 page view controller
weak child scroll view
fallback host
childDistanceFromTop
必要 appearance/cache 状态
```

PageStateStore 不写 inset，不直接调整 container/child owner。

### reloadData 收敛顺序

1. 结束或明确取消当前分页/滚动事务。
2. 保存当前页面 `childDistanceFromTop`。
3. 从 data source 获取并验证新页面身份。
4. 建立新 page state，执行 scroll discovery 或 fallback 选择。
5. 让 Tabman/Pageboy reload。
6. 等 adapter 完成 bar 布局并获得 resolved barInsets。
7. 应用新页面 managed inset。
8. 按 container 状态恢复或归一化当前 child offset。
9. 在旧页面不再可见后归还旧 inset ownership。
10. 清理旧 fallback host、page state 和 adapter 状态。

旧 ownership 不应在 Tabman 页面替换前提前归还，避免仍可见的旧页面发生中间态跳动。

## 纵向滚动所有权

### 稳定状态不变量

```text
containerExpandedOffset = 0
containerCollapsedOffset = collapsibleDistance
childTopOffset = -child.contentInset.top
```

必须满足：

1. container 未完全折叠时，当前 child 必须停在 childTopOffset。
2. 当前 child 离开顶部时，container 必须停在 containerCollapsedOffset。
3. 非当前 child 不参与 owner 判断，也不能驱动 Header。

### 向上交接

1. container 尚未完全折叠：container 消费位移，child 保持顶部。
2. container 到达 collapsed offset：container 锁定，把同一手势剩余 delta 交给 child。
3. child 正常滚动：Header 和 adapter 不再移动。

### 向下交接

1. child 尚未回到顶部：child 消费位移，container 保持完全折叠。
2. child 到达顶部：child 锁定，把同一手势剩余 delta 交给 container。
3. container 回到 expanded offset：Header 完全展开。
4. 完全展开后的额外下拉由 v0.6 overscroll mode 决定 owner。

不得通过反复切换 `isScrollEnabled` 实现 handoff，避免中断 pan、丢失 velocity 或产生手势断点。
ScrollCoordinator 通过私有 delegate proxy、guarded offset update 和剩余 delta 转移维护唯一 owner。

### 最小纵向手势同时识别

同一根手指完成 container/child 连续交接需要：

```text
verticalScrollView.panGestureRecognizer
<-> currentChild.panGestureRecognizer
```

进行受限 simultaneous recognition。因此“当前 container 与当前 child 的最小纵向手势对”前移到
v0.5。v0.7 继续负责横向分页、系统返回手势、child 横向滚动、程序化分页、取消路径和完整
interaction state 优先级。

### 页面切换

1. container 完全折叠时切页：container 保持 collapsed offset，目标页恢复自己的
   `childDistanceFromTop`。
2. container 尚未完全折叠时切页：container 位置不变，目标 child 归到顶部，该页
   `childDistanceFromTop` 更新为 `0`。
3. 不暂存非零 child distance 等待 Header 再次折叠后突然恢复，避免临界点内容跳跃。
4. 不为了恢复目标 child offset 强制折叠 Header，避免切页导致 Header 突然消失。

## 尺寸与 Header 变化

旋转、Split View、window bounds 或 safe area 变化时：

1. 暂停新的 owner 切换。
2. 保存 container collapse progress 和当前 child distance。
3. 重算 Header 与固定 adapter frame。
4. 等 Tabman 完成布局并重新读取 barInsets。
5. 应用 managed inset。
6. 恢复 container progress。
7. container 完全折叠时恢复 child distance；否则当前 child 归顶部。
8. 重新计算 owner。

`reloadHeaderLayout(offsetAdjustment:)` 先按既有策略迁移 container。迁移结果完全折叠时保留
child distance；结果部分展开时当前 child 归顶部。

## 异常与降级

1. scroll target 已释放：在安全同步点重新发现；仍找不到则使用 fallback host。
2. 同一 UIScrollView 被不同页面声明：Debug assertion；Release 中后出现页面忽略冲突的显式
   target，再执行默认 lookup 或 fallback。
3. resolved barInsets 为负数或非有限数：按 `0` 处理并记录日志。
4. adapter bar layout 回调重复：值未变化时不写 inset、不输出普通日志。
5. Tabman 回调缺失或乱序：以 adapter 当前稳定页面执行一次幂等收敛，不重复 containment。
6. ownership 归还时 scroll view 已释放：丢弃 weak record，不执行 UIKit 写入。

## 内部组件职责

```text
AnchorPagerViewController
├─ AnchorPagerLayoutEngine
├─ AnchorPagerPagingAdapter
├─ AnchorPagerManagedInsetCoordinator
├─ AnchorPagerPageStateStore       v0.4
└─ AnchorPagerScrollCoordinator    v0.5
```

建议文件：

```text
Sources/AnchorPager/
  Layout/AnchorPagerLayoutEngine.swift
  Children/AnchorPagerManagedInsetCoordinator.swift
  Children/AnchorPagerPageStateStore.swift
  Children/AnchorPagerPageScrollHostViewController.swift
  Core/AnchorPagerScrollCoordinator.swift
  Paging/AnchorPagerPagingAdapter.swift
  Paging/AnchorPagerTabBarAdapter.swift
```

## 日志

新增事件：

```text
paging.barInsetsChanged
paging.barHeightInvalid

inset.ownership.begin
inset.ownership.update
inset.ownership.skip
inset.ownership.end
inset.targetCollision

children.offset.snapshot
children.offset.restore
children.offset.resetToTop

scroll.owner.container
scroll.owner.child
scroll.handoff.containerToChild
scroll.handoff.childToContainer
```

事件只携带稳定名称，不记录几何数值、页面标题、业务内容或完整 view hierarchy。bar/inset 值未变化
时不重复普通日志；滚动热路径只记录 owner 或阈值变化，不逐帧记录。

## 测试策略

### v0.3

1. Tabman bar 覆盖 Pageboy child 的真实 UIKit 集成测试。
2. optional bar height：默认 nil 使用 Tabman 自适应高度；显式值约束实际 bar。
3. adapter 从展开到折叠只改变 top，高度和 Pageboy child bounds 不变。
4. 展开时 adapter 超出 viewport 的部分被裁剪。
5. managed top 等于 resolved `barInsets.top`，不包含 Header 或顶部 safe area。
6. external content inset 和 indicator inset得到保留。
7. 相同 target 跳过重复写入。
8. ownership 结束后归还 inset 和 adjustment behavior。
9. fallback host 使用相同 inset 规则。
10. bar 高度变化时保持 child distance-from-top。
11. 新增日志均通过注入 sink 验证。
12. 示例工程真实列表页和 fallback 页 UI test。

### v0.4

1. page identity、重复 controller 和共享 scroll target 冲突。
2. cache window、offset snapshot 和 ownership 生命周期。
3. reload 后旧 child、scroll view 和 fallback host 可释放。
4. container 部分展开时切页，目标 child 归顶部。
5. container 完全折叠时切页，目标 child 恢复独立 offset。

### v0.5

1. 向上 container 到 child 的连续交接。
2. 向下 child 到 container 的连续交接。
3. 同一 pan 的剩余 delta 不丢失。
4. guarded update 不重入。
5. 短内容、长内容和不同 contentSize 页面。
6. Header 展开、折叠和 child top boundary 的 rubber-band 稳定性。
7. Header 滚动期间 adapter height 和 Pageboy child bounds 不变。
8. 高频滚动路径不逐帧输出普通日志。

## 版本边界调整

1. v0.3 实现 optional bar height、固定高度 adapter、barInsets callback 和 managed inset ownership。
2. v0.4 实现 page state、cache、lifecycle、offset snapshot 和 ownership 清理闭环。
3. v0.5 实现 ScrollCoordinator，并包含当前 container/current child 的最小纵向 simultaneous recognition。
4. v0.6 保持顶部 overscroll owner 职责。
5. v0.7 保持完整手势与交互状态机职责，不重复实现 v0.5 的纵向基础 handoff。

## 影响范围

1. **Public API：** `AnchorPagerBarConfiguration.height` 从 `CGFloat` 改为 `CGFloat?`，默认从 48 改为 nil。
2. **Layout：** adapter height 改为 collapsed-state fixed height；bar geometry 改为两阶段收敛。
3. **Paging adapter：** 保留 Tabman bar 实例，支持 optional height constraint 和 barInsets callback。
4. **Child lifecycle：** v0.4 page state 保存 distance-from-top，并在清理时归还 inset ownership。
5. **Scroll discovery：** 发现结果进入 ownership coordinator；共享 target 冲突必须降级。
6. **Inset ownership：** 由新 coordinator 单独负责，不依赖 Tabman AutoInsetter。
7. **Gesture/overscroll：** v0.5 前移最小纵向 simultaneous recognition，v0.6/v0.7 其余边界不变。
8. **日志：** 新增 paging/inset/children/scroll 状态变化事件。
9. **测试与示例：** 必须补 UIKit 集成测试和真实可见 UI test。
10. **文档：** requirements、roadmap、architecture、task-list、README、DocC 和计划必须同步。

## 自审结论

1. 文档没有未决占位符或未选择的设计分支。
2. Header、Tabman/Pageboy、inset ownership、page state 和 scroll owner 的职责单向且不形成反馈闭环。
3. Tabman/Pageboy 类型没有进入 public API；adapter callback 使用 UIKit/领域无关 internal value。
4. optional bar height 的默认、自适应、显式覆盖、异常值和真实几何来源均已固定。
5. v0.3–v0.5 可以分别制定实施计划，不需要在单个版本提前实现后续完整功能。
6. 用户可见布局、滚动、生命周期和 inset 行为均列出自动化测试或 UI test 要求。
