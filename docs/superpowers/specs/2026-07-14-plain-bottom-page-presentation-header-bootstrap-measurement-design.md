# 无滚动页底部内容层回弹与 Header 首次测量修复设计

**日期：** 2026-07-14

**状态：** 设计与实施计划已确认，实施与重新验收待完成

**适用范围：** 无 `UIScrollView` 页面底部 container 回弹、Paging adapter presentation 分层、`AnchorPagerLayoutContext` 可见坐标、automatic Header 首次中立测量及示例约束告警。

**实施计划：** `docs/superpowers/plans/2026-07-14-plain-bottom-page-presentation-header-bootstrap-measurement.md`

## 背景与证据

2026-07-14 真实设备尺寸的模拟器验收发现两个相邻问题：

1. 无滚动页在 Header 完全折叠后继续上推，外层 `verticalScrollView` 正确进入 `.bottom/.container` owner，但当前 `viewportView` 使用 `topOverflow - bottomOverflow` 整体变换，导致 Header、Tabman bar 和 Pageboy 页面一起上移。bar 因而越过本地顶部安全区；松手后 UIKit 回弹归位，所以终态正常。
2. 首次安装 automatic Header 时，中立测量在没有缓存高度的情况下把 Header host 的 required height 设为 `0`，随后同步 `layoutIfNeeded()`。示例 Header 的标题栈要求 `top == safeArea.top + 20` 且 `bottom <= safeArea.bottom - 20`，与 `height == 0` 无法同时满足，UIKit 会报告约束冲突并临时打断 bottom 约束。

对比路径进一步确认第一项根因：真实 child 含 `UIScrollView` 时，底部 owner 是 child，container 保持 collapsed boundary，Header/bar 正常吸顶；只有 scroll target 为 nil 的 plain page 走 container bottom presentation。现有 `testPlainBottomOverflowTranslatesViewportUpWithoutChangingCanonicalRange` 和 2026-07-13 边界规格还把“整个 viewport 上移”写成期望，因此这是既有 presentation 契约错误，不是偶发回调顺序问题。

## 目标

1. `verticalScrollView` 继续作为无滚动页底部手势、阻尼、减速和原生回弹的唯一物理 owner。
2. 无滚动页底部 overflow 只移动 Pageboy 页面 presentation surface；Header 和 bar 始终保持 canonical 吸顶位置。
3. container 顶部 owner 的现有整体下拉保持不变；真实 child 顶部/底部原生回弹保持不变。
4. LayoutEngine output、scroll range、managed inset、snapshot、generation 和 collapse progress 继续只保存 canonical 状态。
5. automatic Header 首次测量不得让带内容约束的 Header 以 required `height == 0` 参与布局。
6. 不扩大 Public API，不恢复 synthetic scroll wrapper，不修改业务 child view 的 transform、scroll delegate、pan delegate、`isScrollEnabled`、`bounces` 或 `alwaysBounceVertical`。

## 非目标

1. 不修改顶部 `.none/.container/.child` 路由或默认值。
2. 不实现自定义 rubber-band 曲线、跨 owner velocity 合成或 v0.7 interaction state。
3. 不调整 Pageboy containment、selection terminal、reload generation、cache window、appearance forwarding 或 child inset ownership。
4. 不让无滚动页获得 synthetic child scroll target、offset snapshot 或 managed inset。
5. 不以禁用 container bounce、强制回写 offset、异步 delay 或终态重复 layout 掩盖中间态问题。

## 设计决策一：物理 Owner 与可见 Presentation 分层

稳定位置仍为：

```text
containerStable = clamp(containerOffset, 0...collapsibleDistance)
childStable = clamp(childDistanceFromTop, 0...childMaximumDistance)
```

container 原生 overflow 仍从 `verticalScrollView.contentOffset.y` 读取：

```text
containerTopOverflow = max(0, -containerOffset)
containerBottomOverflow = max(0, containerOffset - collapsibleDistance)
```

但可见变换拆为两层：

```text
chromeTranslationY = containerTopOverflow
pageTranslationY = containerTopOverflow - plainContainerBottomOverflow
```

其中 `plainContainerBottomOverflow` 只有在 committed current page 非 nil、committed current scroll target 为 nil，且 container 实际越过 collapsed boundary 时才等于 `containerBottomOverflow`；其他路径为 `0`。

行为矩阵：

| 场景 | Header/bar | Pageboy 页面 surface | 原生物理 owner |
| --- | --- | --- | --- |
| container 顶部 owner | 下移 `topOverflow` | 随父层一起下移 | `verticalScrollView` |
| plain page 底部 owner | 保持 canonical | 上移 `bottomOverflow` | `verticalScrollView` |
| 真实 child 顶部/底部 owner | 保持 canonical | adapter surface 保持 identity，只有 child 内容回弹 | 业务 child `UIScrollView` |
| stable range | canonical | identity | 无边界 owner |

这意味着 `verticalScrollView` 继续提供 UIKit 原生回弹曲线，但它的 raw overflow 不再等价于“整个 viewport 必须平移”。物理 owner 与 presentation target 是两个职责。

## 设计决策二：Paging Adapter 提供内部页面 Presentation Surface

`AnchorPagerPagingAdapter` 在 internal 层定位 Pageboy 标准 containment 中的 `UIPageViewController.view`，并提供仅供 `AnchorPagerPagingHostViewController` 使用的页面 presentation 更新入口。该 surface 包含当前页和横向过渡中的相邻页，但不包含 Tabman bar。

约束：

1. 只使用 UIKit 标准 child containment 查询 `UIPageViewController`，不读取 Pageboy private/internal symbol，不向 Public API 暴露 Tabman/Pageboy 类型。
2. 不直接修改业务 page controller 根 view 的 transform，避免覆盖业务动画或跨 generation 残留状态。
3. 不修改 Pageboy 横向 scroll view delegate、pan delegate 或滚动开关。
4. `setPagePresentationTranslationY(0)` 必须幂等；adapter removal、empty terminal、selection/reload cancel、rotation、Header layout reload、committed rebind 和释放路径都要恢复 identity。
5. presentation surface 暂时不可用时不得退化为移动 Header/bar；应保持 canonical 并通过统一日志记录受控降级。

`AnchorPagerViewController` 继续让 `viewportView` 承担顶部整体 presentation；plain bottom 的负向位移通过 PagingHost 转交 adapter 页面 surface。不得新增第二个 offset writer，ScrollCoordinator 的 owner/offset 规则不变。

## 设计决策三：Layout Context 报告真实分层坐标

`AnchorPagerLayoutContext` Public 结构不变，frame 继续使用 `AnchorPagerViewController.view` 本地实际可见坐标：

1. container 顶部回弹：`headerFrame`、`barFrame`、`contentFrame` 都加入 `containerTopOverflow`。
2. plain bottom 回弹：`headerFrame`、`barFrame` 保持 canonical，只有 `contentFrame` 减去 `containerBottomOverflow`。
3. child owner 回弹：三者保持 canonical；child 自身可见 offset 不进入 LayoutContext。
4. settle/cancel 后三个 frame 同步恢复 canonical，collapse progress 和 contentSize 始终不变。

Example 显示帧探针必须分别记录 chrome 与 page presentation。plain bottom UI 不能再用 Header frame 上移证明回弹；必须同时证明页面内容有负向 presentation、bar 位移小于 `0.5 pt`，并在松手后全部归零。

## 设计决策四：Header 首次 Bootstrap Measurement

中立测量仍负责消除最终 top behavior、safe area 和 presentation transform 对纯内容高度的污染，但首次无缓存时不再执行 required zero-height layout。

流程：

1. 清除 viewport/page presentation transform，把 Header host 放到 `bounds.minY + topObstruction`。
2. 若存在最近一次有效纯内容高度，继续使用该高度建立中立几何。
3. 若没有缓存，先对当前 Header 内容执行一次不发布状态的 compressed fitting，得到 finite、nonnegative bootstrap seed。
4. 把 seed 写入 host required height 后同步 layout，使 Header 自身顶部 safe area 在中立位置归零。
5. 再执行现有正式 fitting measurement，正式结果才更新 `lastMeasuredHeaderHeight`、canonical output 和既有 `header.measure` 日志。
6. bootstrap 为 `0` 只允许表示 Header 确实没有可测内容；带 required 内部内容约束的非空 Header 不得经历 zero-height layout。

bootstrap 阶段不更新 layout context、collapse progress、scroll range、managed inset、frame 日志缓存或 page presentation。Header UIViewController containment 与 `preferredContentSize.height` 优先级保持不变。

## 生命周期与清理

1. stable range 的每次布局都会把 page presentation 归零，不依赖动画 completion 猜测终态。
2. `reloadData()`、matching Host will-perform、will-select、selection cancel、`reloadHeaderLayout()`、尺寸过渡、committed page rebind、empty terminal 和 deinit 的既有 boundary cancel 之后，必须同步恢复 page surface identity。
3. adapter teardown 在移除 Pageboy containment 前恢复 transform，不能把 presentation 状态留给被缓存或复用的业务页面。
4. page presentation 不进入 Store payload、offset snapshot、managed inset ownership 或 reload generation。

## 影响范围

- **Public API：** 无变化；`AnchorPagerLayoutContext` 只修正既有“实际可见坐标”语义。
- **内部分层：** ViewController 计算 chrome/page presentation；PagingHost 转发；PagingAdapter 只操作 Pageboy 页面 surface。
- **UIKit containment / child lifecycle：** Pageboy 仍是业务页面唯一 containment 执行者；不新增、删除或重复 `addChild`。
- **scroll discovery / inset ownership / snapshot：** 无变化。
- **gesture / overscroll：** owner 路由、simultaneous recognition、原生 offset 和业务 bounce 配置不变。
- **日志：** 既有 owner 日志不变；只有 presentation surface 缺失的受控降级需要新增 paging/resource 事件及日志测试，滚动热路径不逐帧输出。
- **Example：** 探针区分 page 与 chrome presentation；真实 UI 验证 bar 安全区和页面回弹。
- **文档：** 本设计取代 2026-07-13 边界规格中“plain bottom 整个 viewport 上移”的当前契约，并修订 2026-07-11 首次中立测量使用 `0` 的规则。

## 被否决方案

1. **直接变换当前业务 child 根 view：** 改动较小，但会占用业务 view 的 transform，可能与业务动画、横向过渡、cache/reload 生命周期冲突。
2. **整体移动 paging host 再反向补偿 bar：** 形成双 transform，bar 背景、命中测试、accessibility frame 和 Tabman 内部 container 可能不同步。
3. **关闭 plain bottom bounce 或实现自定义物理：** 前者不满足已确认行为，后者复制 UIKit 阻尼/速度状态并产生第二套物理 owner。
4. **恢复 synthetic scroll wrapper：** 重新引入错误尺寸、inset、snapshot、虚假 owner 和 containment 风险。

## TDD 与验收设计

### Framework RED

1. 把 plain bottom UIKit 测试改为断言：overflow `24 pt` 时 Header/bar frame 保持 collapsed canonical，`contentFrame` 和真实 plain page presentation 上移 `24 pt`，contentSize/collapse progress 不变，回稳后全部恢复。
2. Paging adapter 测试证明页面 surface 可移动且 Tabman bar frame 不变；归零、reload、empty/removal 后 transform 为 identity。
3. 增加带真实 Auto Layout 内部约束、可记录 `layoutSubviews()` 高度的 Header fixture；首次 automatic layout 必须测得正确高度，且非空内容从未以 zero height 参与 layout。
4. 保留 container top 整体下移、真实 child bottom 只移动 child、plain direct containment、物理底边、nil scroll target、无 managed inset/snapshot 的相邻回归。
5. 若新增 presentation surface unavailable 日志，使用可注入 sink 验证只在状态变化时记录，不逐帧重复。

必须先运行上述目标测试并观察它们因旧的共享 viewport transform/zero-height bootstrap 语义而失败，再写生产实现。

### Example RED

1. `testPlainContainerBottomBounceIsVisible` 记录 page bottom presentation max 大于 `1 pt`，同时 bar/chrome presentation max 小于 `0.5 pt`，松手后 current 全部小于 `0.5 pt`。
2. UI 中 bar `minY` 在整个显示采样期间不得小于 collapsed safe-area baseline 减 `0.5 pt`；plain root 继续覆盖物理屏幕底部。
3. 首次启动不再输出 `Unable to simultaneously satisfy constraints`；自动化以 nonzero-layout fixture 为稳定门禁，控制台输出作为补充验收证据。
4. 真实 child bottom、container top、child top、`.none`、切页/reload/rotation cancel 的既有 UI 用例继续通过。

### 完整验收

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -parallel-testing-enabled NO test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
```

静态门禁继续确认 Public 无 Tabman/Pageboy、业务 child delegate/pan delegate/`isScrollEnabled`/bounce 属性无框架写入、无 synthetic wrapper、无并发 unsafe 标记。用户可见 UI 修复完成后必须执行代码自审和独立复审；Critical/Important 清零前不得恢复 v0.5/v0.6 Ready。

## 完成定义

1. plain bottom 的 native physics owner 仍为 `verticalScrollView`，但只有 Pageboy 页面内容产生向上 presentation。
2. Header 和 bar 在 plain bottom 回弹期间保持安全区吸顶位置，松手后页面 surface 恢复 identity。
3. 真实 child 的顶部/底部 bounce 和业务配置保持不变。
4. automatic Header 首次布局无 required zero-height 内容冲突，测量结果稳定。
5. Public API、Pageboy containment、Store generation/cache/snapshot、managed inset 和日志热路径边界不变。
6. RED/GREEN 目标测试、完整 Framework/Example/UI、generic build、静态扫描、`git diff --check`、自审和独立复审均有新鲜通过证据。
