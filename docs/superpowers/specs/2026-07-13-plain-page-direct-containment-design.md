# 无滚动页面直接 Containment 设计

> 2026-07-13 修订：本文关于无滚动页“折叠后继续上推不产生额外纵向距离”的验收已被 `2026-07-13-boundary-bounce-ownership-design.md` 取代。页面仍没有 child scroll target，外层 container 在底部边界提供原生物理。
> 2026-07-14 修订：plain bottom 可见 presentation 只移动 Pageboy 页面 surface，不移动 Header/bar；最新契约见 `2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement-design.md`。

**日期：** 2026-07-13

**状态：** 已完成；direct containment 专项与 2026-07-14 plain bottom 分层 presentation 修订、完整验收和整分支 fresh-pass 复审均完成，关联 v0.5/v0.6 当前为 Ready

## 背景

修复前实现曾把没有 `UIScrollView` 的业务页面包装进 `AnchorPagerPageScrollHostViewController`，由内部 synthetic `UIScrollView` 充当统一 scroll target。该设计最初用于复用 managed inset、offset snapshot、纵向手势和 fallback containment，但真实调试证明它把“页面显示几何”和“滚动内容几何”错误地绑定在一起：fallback child 的最小高度减去 managed top/bottom 后，业务根 view 底边停在安全区或 Tab Bar 上方；`alwaysBounceVertical` 还引入了无真实内容却可滚动或回弹的路径。

用户已明确：业务页面内部没有 `UIScrollView` 时，不需要 AnchorPager 为它设置 content inset、indicator inset、offset snapshot 或 child bounce。页面根 view/背景应按 Pageboy 提供的分页 viewport 完整铺开；如果宿主把 AnchorPager 布局到物理屏幕底部，页面也必须延伸到物理屏幕底部。业务内容是否避开 safe area 由 UIKit 和业务页面自己决定。

## 目标

1. 无滚动页面直接作为 Pageboy page，由 Pageboy/UIKit 执行唯一 containment 与 appearance lifecycle。
2. 无滚动页面的业务根 view 完整等于 Pageboy page viewport，不因 bar、safe area、Tab Bar 或 managed inset 被 AnchorPager 缩短。
3. 无滚动页面没有 synthetic scroll target；Store 对该页保存有效 page identity，但 scroll target 为 `nil`。
4. Header 折叠和展开只由 `verticalScrollView` 消费；无 child offset、snapshot、inset、bounce 或 simultaneous pair。
5. 真实滚动页面的 scroll discovery、managed inset、snapshot、delegate 保留和纵向 handoff 行为不变。
6. 不扩大 public API，不泄漏 Tabman/Pageboy 类型。

## 非目标

1. 不修改真实 `UIScrollView` 页面现有 managed inset 语义。
2. 不实现 v0.6 overscroll mode 或 v0.7 完整手势优先级。
3. 不替业务页面设置 `additionalSafeAreaInsets`，也不改变其 safe-area 布局策略。
4. 不保留一个“零滚动”的 synthetic `UIScrollView` 作为兼容层。
5. 不让 AnchorPager 对普通 Pageboy page 再次执行 `addChild`。

## 方案选择

### 采用：原始页面直接交给 Pageboy，scroll target 为 nil

该方案与真实领域模型一致：page identity 和 scroll identity 是两个独立可选事实。页面可以存在而没有滚动目标。Pageboy 继续负责横向 containment；Store 只管理 identity、retention、generation 和 committed 语义；ScrollCoordinator 只在 committed current scroll target 非 nil 时绑定 child。

### 不采用：保留 fallback UIScrollView，但把 inset 归零

虽然能减少当前症状，仍会保留虚假的 pan、contentSize、offset、bounce、snapshot 和 cleanup owner，后续版本还会继续把“无滚动页”误判为 child scroll owner。

### 不采用：业务 view 铺满，另建隐藏 scroll range

该方案把显示层和 synthetic scroll 层拆开，但 synthetic scroll 本身仍没有领域意义，并增加 hit testing、accessibility、gesture、生命周期和资源清理复杂度。

## 页面身份与 Store 数据流

`AnchorPagerPageStateStore.PageIdentityPayload` 保留 original page、actual page、optional scroll view、optional claimed scroll identifier；移除 fallback host identity 和 fallback containment/cleanup preservation。

页面解析规则改为：

1. data source 返回 original page，Store 加载其 view 并执行 scroll discovery。
2. 找到未冲突的显式或默认 scroll target：actual page 仍为 original，保存该 scroll target。
3. 找不到 scroll target：actual page 仍为 original，scroll view 为 `nil`。
4. 显式 scroll target 与其他页面冲突时，保留 assertion 和 `inset.targetCollision`；如果还能发现未冲突的默认目标则使用它，否则降级为 original page + nil scroll target。
5. data source 缺失或同一 controller 被多个 index 复用时，沿用空白 page 降级；空白 page 直接交给 Pageboy，scroll target 为 nil。

`committedCurrentPageViewController` 与 `committedCurrentScrollView` 必须保持独立：

- 空数据：两者均为 nil。
- 无滚动当前页：page 非 nil，scroll 为 nil。
- 真实滚动当前页：page、scroll 均非 nil。

因此后续 v0.6/v0.8 必须同时读取 committed current page/scroll，不能把 `scroll == nil` 等同于 empty。

## Containment 与生命周期

所有非空横向页面，包括无滚动页、空白降级页和真实滚动页，均由 Pageboy/UIKit 执行唯一 containment。AnchorPager 不再为普通业务页创建 wrapper，也不再执行 fallback `addChild`/remove。

Store 的 retention lease 仍可强持有 actual page，但 retain/release 不手工转发 appearance。reload generation commit/cancel 只清理 generation state、managed scroll ownership 和 snapshot；旧页面的实际横向移除继续由 PagingHost/adapter terminal 负责。

## Insets、尺寸与坐标

无滚动页必须满足：

```text
actualPageViewController === originalViewController
scrollView == nil
managedInsetOwnership == false
childDistanceFromTop == 0
```

AnchorPager 不向无滚动页写入 `contentInset`、`scrollIndicatorInsets`、`contentOffset`、`contentSize`、`additionalSafeAreaInsets`、`bounces` 或 `alwaysBounceVertical`。

页面根 view 的 frame 完全由 Pageboy content viewport 决定。固定 paging viewport 的 bottom 仍以 AnchorPager 本地 bounds 底边为几何终点，bottom obstruction 只用于真实 scroll target 的 managed inset，不得缩短无滚动 page frame。Header 展开时，page root 可能延伸到 AnchorPager 或 window 底部之外；UIKit 与 XCUITest 的几何验收都应验证转换后的 `maxY` 不小于对应 bounds 或物理屏幕的 `maxY`，不能假设 accessibility frame 会被祖先 viewport 裁剪。

## 纵向手势

无滚动当前页时，ScrollCoordinator 绑定 nil：container 的 weak child pan pair 清空，不创建 child observation 或 pan target，canonical total 只有 container collapse distance。向上拖动最多折叠 Header；向下拖动最多展开 Header或进入 v0.5 临时 container bounce；page 不产生 offset、bounce 或 snapshot。

UIKit 的祖先 `verticalScrollView.panGestureRecognizer` 可以从普通 descendant view 上开始识别拖拽，不需要 synthetic child pan。必须用真实 simulator coordinate drag 验证，不能只调用 resolver 或直接写 offset。

## 日志

页面首次解析为无 scroll target 时记录一次 `scroll.target.none`，category 为 `scroll`，level 为 `debug`。不得在 layout/drag 热路径重复输出。移除 `fallbackHost.create`；共享 scroll 冲突继续使用 `inset.targetCollision`。

## 测试门禁

### Store 与 containment

1. 无滚动页返回 original controller，不创建 wrapper，scroll target 为 nil。
2. Pageboy 直接 containment original controller；AnchorPager 不形成第二 parent。
3. selection complete/cancel、reload commit/cancel、empty terminal 和 cache window 不改变 page/scroll 的独立语义。
4. 相邻 generation 同实例迁移不重复 containment。
5. shared scroll collision 无可用替代目标时降级为 original page + nil scroll target。

### Insets与几何

1. 无滚动页没有 managed inset ownership，Store managed update count 不包含它。
2. 页面根 view 在 Header 展开、折叠、切页和 reload 后始终等于 Pageboy content viewport。
3. 页面根 view 底边至少覆盖 AnchorPager bounds 底边；示例 root under Tab Bar 时至少覆盖 window 物理底边。
4. UIKit safe area 或业务 `additionalSafeAreaInsets` 不被 AnchorPager 改写。

### 手势与 UI

1. 在无滚动页中央真实上推，Header 折叠且 page root 底边不变。
2. Header 折叠后继续上推，page 不产生 child distance；container 可按边界 owner 规格呈现底部原生回弹。
3. 真实下拉只展开 Header或触发 container bounce，page 无 child bounce。
4. Example 探针不得为 plain 页写死 `distance=0` 来替代内部事实；改为报告 `hasScrollTarget=0` 和 plain root/window 几何。
5. 真实列表页、短页、横向分页、reload 和 appearance lifecycle 全量回归通过。

## 文件影响

已删除 synthetic scroll wrapper 生产实现及其专用测试；已修改 PageStateStore、Store/ViewController/PagingAdapter/Example 测试，以及 README、architecture、requirements、task-list 和 v0.3/v0.4/v0.5 相关状态文档。

## 回归风险

1. **Pageboy containment：** 验证 original page 的 parent、appearance complete/cancel 和 reload teardown。
2. **nil 与 empty：** 所有 committed-current 消费者同时看 page/scroll，不能只看 scroll。
3. **缓存迁移：** 去掉 fallback payload 后，跨 generation identity 和 retention lease 仍保持 original controller。
4. **手势入口：** 证明 container pan 能从普通 child 内容区域开始。
5. **共享 scroll 冲突：** 降级为 nil 后不能继续写冲突 scroll 的 inset 或 offset。

## 完成定义

1. 仓库不再包含 fallback scroll host 生产实现或 wrapper containment。
2. 无滚动页直接由 Pageboy containment，根 view 到达 AnchorPager/物理屏幕底部。
3. 无滚动页没有 AnchorPager managed inset、offset、snapshot 或 bounce 写入。
4. 真实 pan、完整 framework tests、Example tests、generic simulator build 和 `git diff --check` 全部通过。
5. public API 不变化，业务 child scroll delegate/pan delegate 不被设置。
6. 文档不再把无滚动页描述为 fallback scroll owner。

## 边界集成复验（2026-07-13）

最终边界实现、`f81ca1e`、`5b80893` 与 `128821f` 复审修复均未改变 direct containment、committed page 非 nil / scroll target nil、无 managed inset/snapshot/child observation 和物理底边契约。plain page 顶部 `.container` 与底部边界的原生物理均由外层 container 提供；`.child` 顶部不可用且不回退。2026-07-13 历史验收为 Framework 283/283、Example 37/37 与 generic Simulator build 全部通过。

2026-07-14 用户确认 plain bottom 继续由 `verticalScrollView` 处理原生回弹，但仅页面内容区域上移；Header/bar 必须保持安全区吸顶。该修订只改变 adapter 内页面 presentation surface，不改变 original Pageboy containment、nil scroll target、root 物理底边或 container-only pan。实现、全量验收和整分支 fresh-pass 复审已在生产代码 HEAD `c37e829` 完成，关联 v0.5/v0.6 当前为 Ready。
