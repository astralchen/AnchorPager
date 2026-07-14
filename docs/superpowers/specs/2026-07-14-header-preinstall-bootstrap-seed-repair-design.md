# Header 安装前 Bootstrap Seed 修复设计

**日期：** 2026-07-14

**状态：** 书面规格已确认，实施计划已建立；RED/GREEN、全量验收和复审待完成

**适用范围：** automatic Header 首次真实内容安装、Header identity replacement、bootstrap fitting、Header UIViewController containment、启动期 Auto Layout 约束告警及相关测试。

**实施计划：** `docs/superpowers/plans/2026-07-14-header-preinstall-bootstrap-seed-repair.md`

## 背景与复现证据

2026-07-14 用户再次在 Example 首次启动时观察到 `Unable to simultaneously satisfy constraints`。冲突同时包含：

1. Header host 的 required `height == 0`。
2. `ExampleHeaderView` 内部标题栈的 `top == safeArea.top + 20`。
3. 标题栈的 `bottom <= safeArea.bottom - 20`。
4. 业务 Header view 与 host 的 required top/bottom 贴边约束。

模拟器统一日志复现了同一冲突；UIKit 为恢复布局临时打断标题栈 bottom 约束。日志发生在真实 Header 的 `header.view.install` 事件之前，而正式 `header.measure` 在其后。

## 根因

此前 `dfabd6c` 增加了正式测量前的 bootstrap seed，但只修正了 `measureHeaderHeight(in:)` 中 `layoutIfNeeded()` 前的高度。真实启动顺序仍是：

```text
loadView
  → 安装空占位 Header
  → 建立 required host height == 0

reloadData commit
  → installHeaderHost()
  → HeaderViewHost.install(real content)
      → remove placeholder
      → addSubview(real Header)
      → 激活 Header 与 host 的 top/bottom 约束
      → Auto Layout 在 host height == 0 时报告冲突
      → header.view.install
  → 使 lastMeasuredHeaderHeight 失效
  → measureHeaderHeight()
      → bootstrap fitting
      → 把 host height 改为非零 seed
```

因此原 bootstrap 执行得太晚。现有 `testAutomaticHeaderBootstrapNeverLaysOutConstrainedContentAtRequiredZeroHeight` 只在 `layoutSubviews()` 中记录最终 attached content 的 bounds；UIKit 约束求解器能在该回调之前发现冲突并恢复，所以测试出现假阴性。

## 目标

1. 新 Header 内容附着到 host 之前，host required height 已更新为该内容的 bootstrap seed。
2. Header view 的四边贴边约束激活时不得与旧的 zero-height host 形成瞬时冲突。
3. 正式 measurement、cache、Header top behavior、safe area 中立语义和 layout output 保持不变。
4. UIViewController Header 继续遵循 `addChild → addSubview → didMove`，不得为了预测量而改变 containment 语义。
5. 同一 Header identity 重复安装继续 no-op，不重复 bootstrap，不清空正式 measurement cache。
6. Public API、paging、child lifecycle、scroll/inset/overscroll、日志事件和业务 Header 约束均不改变。

## 非目标

1. 不降低 Header host 或业务 Header 内部约束的优先级。
2. 不通过异步 delay、下一 run loop、重复 layout 或捕获并忽略 UIKit 告警掩盖时序问题。
3. 不使用临时 staging controller，不移动已经 containment 的业务 Header 到第二个容器。
4. 不改变 automatic/ranged/fixed Header 高度解析规则。
5. 不新增 Public API 或测试专用生产入口。

## 方案选择

### 采用：安装事务内同步预置 seed

`AnchorPagerHeaderViewHost.install` 增加 internal 安装准备参数：measurement size 与同步 `prepareHostForContent` 回调。只有 identity 确实变化时，Host 才执行：

```text
移除旧内容
  → 取得 incoming view
  → compressed fitting / preferredContentSize
  → 同步回调 bootstrap seed
  → ViewController 把 host required height 更新为 seed
  → addSubview + 激活四边约束
  → 完成 containment 与安装日志
```

回调不保存、不逃逸、不发布 layout state。它只把即将安装内容的 seed 写入现有 `headerHeightConstraint`。正式 `measureHeaderHeight(in:)` 随后仍执行正式 fitting，只有正式结果更新 `lastMeasuredHeaderHeight`、layout output 和 `header.measure` 日志。

### 不采用：临时停用或降低 host height 约束

这会让安装期间的 Header 几何变为 ambiguous，并引入额外 constraint activation 状态；如果异常或重入发生在中间阶段，host 可能停留在错误优先级。

### 不采用：独立 staging host

detached staging 对普通 UIView 可行，但 UIViewController Header 会增加 view 加载、parent、safe area 与迁移时序，复杂度明显高于当前问题，且容易破坏 containment 语义。

## 组件职责与数据流

### AnchorPagerHeaderViewHost

1. 判断 incoming content 是否与当前 identity 相同。
2. identity 相同：记录既有 no-op 日志并返回，不调用准备回调。
3. identity 不同：按 content 类型取得即将安装的 view。
4. 使用与现有 bootstrap 相同的测量优先级：UIViewController 正数 `preferredContentSize.height` 优先，其次 compressed fitting、已有 bounds、intrinsic height。
5. 在 `addSubview` 和四边约束激活之前同步传出 finite、nonnegative seed。
6. invalid seed 保持现有 bootstrap 降级为 `0` 的规则；正式测量仍负责 assertion 与 `header.measure.invalid` 日志。

### AnchorPagerViewController

1. 根据当前 layout environment 生成与正式测量一致的 fitting width。
2. 在安装准备回调中创建或更新现有 `headerHeightConstraint`。
3. 首次空占位内容可以使用真实测量得到的 `0`；带可测内容约束的 incoming Header 必须先得到正 seed。
4. 安装成功后才使旧 `lastMeasuredHeaderHeight` 失效；同 identity no-op 保留 cache。
5. 随后继续现有正式测量、layout engine、offset adjustment 和 delegate context 流程。

### UIViewController Header containment

controller 路径保持以下顺序：

```text
parent.addChild(headerViewController)
  → 读取 headerViewController.view 并执行 bootstrap fitting
  → prepareHostForContent(seed)
  → 把 controller.view 加入 host 并激活约束
  → headerViewController.didMove(toParent: parent)
```

这样既保证测量前已经进入 UIKit containment transaction，也保证 view 附着前 host 高度有效。

## 生命周期与异常路径

1. identity replacement 的旧内容先按现有规则移除；新内容只有在 seed 写入后才附着。
2. 同 identity reload 不重复 fitting，不改变 host height，不清空 cache。
3. 真实零内容可以保留 seed `0`；测试必须区分“可测非空内容”与空占位内容。
4. invalid seed 不产生新的 bootstrap 日志；正式测量继续统一报告异常。
5. 本次不改变 reload generation、selection terminal、Pageboy containment 或 appearance forwarding。
6. 不新增异步工作，因此 reload 重入和 cancellation 不增加新的悬挂状态。

## 测试设计

严格执行 RED → GREEN：

1. 扩展 constrained Header fixture，在 `didMoveToSuperview()` 记录附着瞬间 host required height constant。
2. 新增 ViewController 测试：从空占位 Header reload 到带 safe-area 上下约束的真实 Header；当前实现应记录 `0` 并形成 RED，修复后必须记录正 seed。
3. 保留并继续通过既有 `testAutomaticHeaderBootstrapNeverLaysOutConstrainedContentAtRequiredZeroHeight`。
4. 增加 HeaderViewHost 顺序测试：准备回调发生在 view 附着之前；同 identity no-op 不重复回调。
5. 增加 UIViewController Header 测试：bootstrap 时 controller 已有 parent，`didMove` 仍在 view 安装之后完成。
6. 运行 Header/ViewController 聚焦测试、完整 Framework、完整 Example 38 条、generic Simulator build。
7. 补充运行时验收：用新进程 PID 查询模拟器 `com.apple.UIKit:LayoutConstraints`，确认没有新的 `Unable to simultaneously satisfy constraints`；自动化结构测试是主门禁，日志查询是补充证据。

## 影响范围

- **Public API：** 无变化。
- **Header internal：** install transaction 增加同步 bootstrap preparation；formal measurement 语义不变。
- **UIKit containment：** UIViewController Header 顺序保持标准语义。
- **Layout/scroll/inset/overscroll：** 无状态机或 owner 变化。
- **Paging/Pageboy：** 无变化。
- **日志：** 不新增事件；继续使用现有 install/measure 日志。
- **测试：** 修正此前只观察 `layoutSubviews()` 的覆盖缺口，增加附着时序和 containment 回归。
- **文档：** 本规格补充并收紧 2026-07-14 原 Header bootstrap 设计。

## 完成定义

1. 可测非空 Header 附着瞬间 host required height 大于 `0`。
2. Example 新进程启动不再产生本次 Header zero-height 约束冲突。
3. 同 identity no-op、UIView/UIViewController Header、automatic/ranged/fixed measurement 均保持既有行为。
4. Public API、containment、paging、scroll/inset/overscroll 和日志边界不变。
5. RED/GREEN、聚焦测试、完整 Framework/Example/UI、generic build、`git diff --check`、自审和 fresh-pass 复审均有新鲜证据。
