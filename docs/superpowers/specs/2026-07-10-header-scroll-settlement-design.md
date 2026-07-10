# Header 回弹结束布局收敛设计

## 背景

AnchorPager v0.2 支持在运行时切换 `AnchorPagerHeaderTopBehavior`，示例工程通过
`.preserveVisualPosition` 在 `.insideSafeArea` 与
`.extendsUnderTopSafeArea` 之间迁移 Header 布局。

当前可稳定复现以下异常：

1. 默认以 `.insideSafeArea` 显示页面。
2. 切换到 `.extendsUnderTopSafeArea`。
3. 再切换回 `.insideSafeArea`。
4. 向下拖动主容器一小段距离后松手。
5. 等待回弹完全结束。
6. Header 顶部仍与安全区域顶部保留一段空白。

该空白是回弹结束后的稳定错误状态，不是 UIKit rubber-band 期间允许出现的瞬时位移。

## 根因

`AnchorPagerLayoutContext` 使用 `AnchorPagerViewController.view` 的本地可见坐标，Header
host 则位于 `verticalScrollView` 的 content 坐标系内。当前实现通过以下换算把可见坐标写入
Auto Layout 约束：

```swift
contentY = visibleY + verticalScrollView.contentOffset.y
```

这条换算本身只在“约束值与当前 content offset 同步”时成立。当前代码只在
`reloadHeaderLayout()`、`viewDidLayoutSubviews()` 和 safe area 变化路径中执行换算，没有监听
`verticalScrollView` 的拖拽、减速或回弹结束事件。

回弹过程中如果某次布局 pass 读取了瞬时 `contentOffset.y`，该值会被写入 Header 顶部约束。
UIScrollView 随后继续回弹到最终 offset，但 Header 约束不会再次更新，于是一次性的坐标换算结果
变成长期约束状态。最终空白高度等于过期的 offset 补偿量。

运行时切换 top behavior 不是根因，但它通过 `.preserveVisualPosition` 保留并重新应用 offset，
增加了上述不同步状态被暴露的机会。

## 职责关系

### LayoutEngine

`AnchorPagerLayoutEngine` 负责根据当前输入计算 Header、bar、content 的可见 frame。其
safe area、top behavior 和高度解析没有产生本问题，不应为了修复回弹状态而修改纯计算契约。

### AnchorPagerViewController

主控制器负责 UIKit 坐标转换、约束应用和最终布局状态收敛。本问题发生在该层，修复也应限制在该层。

### Header host

`AnchorPagerHeaderViewHost` 只承载 Header 内容并管理 UIViewController containment。它接收
顶部约束值，不拥有 scroll offset，也不负责判断滚动何时结束。本次不改变其职责。

### Paging adapter

Tabman/Pageboy 只负责横向分页和横向 page containment。主容器纵向回弹与分页 adapter 无关，
本次不修改 adapter，也不让第三方类型进入 Public API。

### 后续 ScrollCoordinator

v0.5 的 `AnchorPagerScrollCoordinator` 将负责 Header 与 child scroll view 的逐帧纵向协调、
owner 切换和 guarded contentOffset update。本次只补齐 v0.2 已有布局契约在一次主容器交互结束后的
最终收敛，不实现逐帧协调，不提前引入 v0.5 状态机。

## 方案比较

### 方案一：滚动结束后收敛布局

由 AnchorPager 内部持有自有 `verticalScrollView` 的 delegate，在以下终态回调中重新读取最终
`contentOffset` 并应用布局：

- 无减速的拖拽结束
- 减速或回弹结束
- 程序化滚动动画结束

滚动热路径不调用 `updateVisibleLayout()`，避免逐帧测量 Header、写约束、发送 layout context 或输出
日志。本方案不改变 public API，改动范围小，并可作为 v0.5 coordinator 接管 delegate 前的稳定终态入口。

这是本设计采用的方案。

### 方案二：关闭主容器 bounce

关闭 `alwaysBounceVertical` 可以阻止示例中的主要触发入口，但不能修复程序化 offset 或其他布局
pass 造成的坐标快照不同步，因此只隐藏症状，不采用。

### 方案三：将可视层移出 scroll content

把 Header 和 paging 可视层改为 frame 坐标承载，并为主滚动视图建立独立 content range，可以从结构上
消除当前坐标耦合。但该方案会同时改变 content size、Header 折叠、child viewport 和 v0.5 滚动协调
基础，超出本次 v0.2 回归修复范围，不采用。

## 详细设计

### Delegate 所有权

`verticalScrollView` 是 AnchorPager 创建并管理的主容器滚动视图。AnchorPager 在安装该滚动视图时
将自身设置为内部 delegate。现有 Public API 只暴露滚动视图用于读取和框架接入，没有承诺调用方拥有
delegate；文档需明确主容器 delegate 属于框架内部实现，调用方不得替换。

未来 v0.5 引入 `AnchorPagerScrollCoordinator` 时，可以把相同 UIScrollViewDelegate 入口迁移到
coordinator 或内部 delegate proxy，不改变 Public API。

### 终态收敛入口

新增单一私有入口，例如：

```swift
private func reconcileLayoutAfterContainerScrolling()
```

该入口只调用不带 `offsetAdjustment` 的 `updateVisibleLayout()`，因此：

1. 使用 UIScrollView 已经确定的最终 `contentOffset`。
2. 不主动再次设置 content offset。
3. 不触发 offsetAdjustment 递归。
4. 重新计算 Header 高度和可见 frame。
5. 重新写入可见坐标到 content 坐标的最终转换结果。
6. 仅在 layout context 实际变化时通知 delegate。

`scrollViewDidEndDragging(_:willDecelerate:)` 只在 `decelerate == false` 时收敛；存在减速或回弹时由
`scrollViewDidEndDecelerating(_:)` 收敛，避免同一次交互重复处理。程序化动画由
`scrollViewDidEndScrollingAnimation(_:)` 收敛。

### 非目标

本次不实现：

- `scrollViewDidScroll` 逐帧 Header 折叠
- 主容器与 child scroll view 的 offset 转移
- top overscroll owner 或模式处理
- interaction state、hysteresis 或 guarded contentOffset update
- 状态栏点击顶滚
- 尺寸变化恢复

这些能力继续按 v0.5–v0.8 路线推进。

## 影响范围

### Public API

不新增或删除 public 类型、属性和方法，不改变 top behavior 或 offset adjustment 的枚举语义。补充
`verticalScrollView` delegate 由框架管理的文档说明。

### 内部分层

只修改 `AnchorPagerViewController` 的主容器滚动终态处理；LayoutEngine、Header host、Paging、
Children、Logging 分层不调整。

### UIKit containment 与 lifecycle

不增加或移除任何 child/header view controller，不改变 `addChild`、`didMove`、`willMove`、
`removeFromParent` 顺序。

### Scroll discovery 与 inset ownership

不改变 child scroll discovery，不写入外部 child contentInset，不提前实现 v0.3 managed inset。
主容器继续使用 `.never` content inset adjustment。

### Paging adapter

不修改 Tabman/Pageboy adapter，不改变 selection commit/cancel 或 page containment。

### Gesture 与 overscroll

只消费主容器滚动的终态通知，不决定手势 owner，也不改变 bounce 动画。回弹期间允许出现 UIKit
正常的瞬时位移，但回弹结束后必须收敛到正确 frame。

### 并发与资源

UIScrollViewDelegate 回调和布局更新都在 MainActor/UIKit 主线程执行。不新增 KVO、Notification、
Task、display link 或 closure observer，因此没有新增清理资源，也不需要不安全并发绕过。

### 日志

终态收敛复用现有 `layout.headerFrameChanged`、`layout.barFrameChanged` 等状态变化日志。不新增滚动热路径
日志，避免逐帧噪声。若最终 frame 没有变化，不产生重复日志。

## 测试设计

### 同进程 UIKit 回归测试

新增测试完整覆盖：

1. 在导航控制器中安装 pager。
2. 建立非零主容器 offset 并用 `.preserveVisualPosition` 应用布局。
3. 依次切换到 `.extendsUnderTopSafeArea` 和 `.insideSafeArea`。
4. 模拟 UIScrollView 回到最终 offset。
5. 触发滚动终态 delegate 回调。
6. 断言 Header 实际 frame 顶部与 `AnchorPagerLayoutContext.headerFrame.minY` 一致。
7. 断言 `.insideSafeArea` 的 Header 顶部等于本地 top obstruction，不存在残余空白。

测试在实现前必须失败，失败值应体现实际 Header 顶部比期望值多出过期 offset。

另增加 delegate 所有权测试，断言主容器安装后内部 delegate 已配置。

### 示例 UI 回归

优先增加同一次应用运行内的相对 frame 测试：记录初始 Header frame，完成两次菜单切换和下拉回弹，
等待滚动稳定后断言 Header 顶部回到初始位置。相对 frame 比较避免依赖不同设备上的绝对系统 bar 高度。

如果 XCUITest 无法稳定识别 UIScrollView 回弹结束时刻，则以同进程 UIKit 精确几何测试作为替代自动化
验证，并在实施计划和验收记录中写明原因；现有菜单 UI test 继续覆盖真实菜单交互路径。

### 回归验证

至少运行：

```bash
git diff --check
swift package resolve
xcodebuild -scheme AnchorPager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Examples/AnchorPagerExample.xcodeproj -scheme AnchorPagerExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test
```

## 完成标准

1. 回归测试先失败后通过。
2. 回弹结束后 Header 实际 frame 与 layout context 一致。
3. `.insideSafeArea` 下 Header 顶部没有残余 offset 空白。
4. 不产生逐帧布局日志。
5. 不扩大 Public API，不泄漏 Tabman/Pageboy 类型。
6. Header/page containment、selection、scroll discovery 和 inset ownership 行为不变。
7. 核心测试、示例测试、示例 build 和 `git diff --check` 通过。
8. README、architecture、task-list 和 v0.2 计划记录同步更新。
