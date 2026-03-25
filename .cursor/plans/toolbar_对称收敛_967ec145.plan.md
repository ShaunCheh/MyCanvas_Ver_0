---
name: toolbar 对称收敛
overview: 将 iOS/macOS 的 toolbar 测量与落位链路进一步收敛为同一套结构模型：共享层负责布局常量、内容尺寸公式、像素对齐与两阶段 placement 数据流，平台层仅保留 UI API 与 blocker/safeBounds 等必要差异。计划严格对应已确认的五个阶段，不扩展到按钮绘制、产品交互差异或跨平台基类抽象。
todos:
  - id: phase-1-metrics-naming
    content: 统一布局常量来源与 placement scale 命名，不改行为
    status: pending
  - id: phase-2-measurement-contract
    content: 抽取共享的内容测量契约，固定 host 的对外职责
    status: pending
  - id: phase-3-placement-pass
    content: 抽取共享的两阶段 toolbar placement 数据流
    status: pending
  - id: phase-4-platform-differences
    content: 显式收敛平台必需差异：blocker 集合与 safeBounds 来源
    status: pending
  - id: phase-5-validation
    content: 完成静态检查与关键行为回归验证
    status: pending
isProject: false
---

# Toolbar 平台对称收敛计划

## 范围与边界

- 目标：把 `toolbar` 收敛成同一套结构模型，做到“共享层负责测量规则与纯布局数据流，平台层只保留 UI API 差异”。
- 保持不变：`UIButton` / `NSButton` 的具体渲染实现、`iOS` 独有的 `historyButtons` blocker、`macOS` 当前没有浮动 history 按钮的产品现状。
- 不纳入本次主线：颜色 token 统一、symbol 配置完全共享、把 `AppKit/UIKit` 强行抽成公共基类。

## 目标结构

- 共享层负责：布局常量、内容尺寸公式、像素对齐、两阶段 placement 的纯数据编排。
- 平台层负责：`stackView` 的底层测量 API、`safeBounds` 来源、blocker 集合、按钮视觉实现。
- 最终状态：`[MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift)` 和 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift)` 对外暴露相同职责；`[MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)` 和 `[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)` 只保留平台必要差异。

## 分阶段计划

### Phase 1：统一布局常量与命名

- 目标：先把最容易漂移的常量和命名统一，不改行为。
- 动作：新增共享代码文件，建议命名为 `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarChromeMetrics.swift`，承载 `spacing`、`horizontalInset`、`verticalInset`、`buttonEdge` 这类真正影响测量结果的常量。
- 动作：让 `[MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift)` 和 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift)` 改为读取共享 metrics，而不是各自维护一套测量常量。
- 动作：统一控制器里的 scale 命名，建议两端都收敛成 `toolbarPlacementScale()` 或 `toolbarPlacementPixelScale()`，避免现在 `toolbarPlacementScale()` / `toolbarPlacementBackingScale()` 语义相同但名字不同。
- 验收：常量来源只剩一处；两端 `measuredContentSize()` 在 `0` / `3` / `4` 个按钮场景下数值与现状一致。

### Phase 2：抽取共享的“内容测量契约”

- 目标：把“内容尺寸 = stack 尺寸 + inset”这件事上移到共享层，但不强行合并 `UIView/NSView`。
- 动作：在共享层新增一个小 helper，建议放在 `Toolbar` 或 `CanvasChromeLayoutContext` 旁边，例如 `CanvasToolbarMeasurement`，只负责把 `stackMeasuredSize + metrics` 变成宿主尺寸。
- 动作：保留平台差异在 host 内部。
- 动作：`iOS` 继续在 `[MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift)` 内部用 `systemLayoutSizeFitting(...)` 量 `buttonsStackView`。
- 动作：`macOS` 继续在 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift)` 内部用 `fittingSize`。
- 动作：把两端 host 的公开职责固定为同一组语义：`registerButtons(...)`、`render(_:)`、`measuredContentSize()`；不要求跨平台共用一个协议类型，但要求对外接口语义完全一致。
- 验收：两端 `measuredContentSize()` 只剩“平台测 stack + 调共享 helper”这两个步骤；空 toolbar、横向/纵向布局时结果可预测且一致。

### Phase 3：抽取共享的两阶段 placement 数据流

- 目标：消除控制器里重复的“第一次不带 toolbar blocker，第二次带 toolbar blocker”的编排代码。
- 动作：在共享层新增一个纯数据 helper，建议命名为 `CanvasToolbarPlacementPass` 或 `CanvasChromeToolbarLayoutPass`。
- 动作：这个 helper 只吃纯数据：`safeBounds`、`toolbarPreferredPlacement`、`toolbarMeasuredSize`、`baseChromeBlockers`、`scale`、`CanvasToolbarPlacementSolver`。
- 动作：这个 helper 只产出纯结果：`toolbarFrame`、带 `toolbar` blocker 的 `CanvasChromeLayoutContext`。
- 动作：`[MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)` 和 `[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)` 改为调用这条共享 pass，自身只保留：组装 `safeBounds`、收集 blocker、实际给 `toolbarHostView.frame` 赋值、minimap / context menu 的坐标转换。
- 验收：控制器里与 toolbar placement 相关的重复代码显著减少；`CanvasToolbarPlacementSolver` 本身不需要改算法。

### Phase 4：显式表达“平台必需差异”

- 目标：不是把差异抹掉，而是把差异从“散落代码”收敛成“明确策略点”。
- 动作：在两个控制器里分别收敛出 `baseChromeBlockersForToolbarLayout()` 之类的私有入口。
- 动作：`iOS` 版本显式返回 `backButton + historyButtons + optional toolbar`；`macOS` 版本显式返回 `backButton + optional toolbar`。
- 动作：把 `safeBounds` 来源也显式收敛成平台私有入口，例如 `toolbarLayoutSafeBounds()`。
- 动作：`iOS` 继续基于 `chromeOverlayView.safeAreaLayoutGuide.layoutFrame`。
- 动作：`macOS` 继续基于 `view.bounds + safeAreaInsets`，或者在这一阶段顺手统一成等价 helper。
- 验收：以后如果产品要改 blocker 策略，修改点是明确的，不会再混进 placement 主流程里。

### Phase 5：回归验证与收口

- 目标：确保这次收敛只是结构优化，不引入行为回归。
- 动作：静态检查至少覆盖 `[MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift)`、`[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift)`、`[MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)`、`[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)`、`[MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift)` 以及新增的共享 toolbar metrics / placement pass 文件。
- 动作：行为回归至少覆盖 `3` 按钮 / `4` 按钮切换、进入/退出 text inline edit、iOS 的 `historyButtons` 避让仍生效、macOS 窗口 resize 后 `toolbar` 不再出现尺寸抖动、小窗口 / 极限 safe area 下 solver 不异常退回 `.zero`。
- 动作：如果环境允许，再补两类测试：共享层纯函数测试，给固定 `safeBounds + blockers + measuredSize`，断言输出 frame；测量公式测试，给固定 `stackSize + inset`，断言 host size。
- 验收：视觉行为不变、重复代码减少、平台差异被收敛到少数明确入口。

## 建议的执行顺序

- 主线建议先做 `Phase 1 -> Phase 2 -> Phase 3`。这三步能拿到大部分收益，而且风险可控。
- `Phase 4` 建议在 `Phase 3` 稳定后再做，它不是为了解决当前 bug，而是为了让后续维护不再漂移。
- `Phase 5` 不要压缩，尤其是 iOS 的 blocker 回归和 macOS 的 resize 回归。

## 风险点

- 最大风险不是共享 helper 本身，而是误把平台差异也“统一”掉，特别是 iOS 的 `historyButtons` blocker。
- 第二个风险是 `safeBounds` 来源变化后，solver 输入轻微偏移，导致 `toolbar` 落点改变。
- 第三个风险是把 host 测量抽过头，反而重新把 `UIView/NSView` 当前 frame 带回测量链。

## 主线完成定义

- 建议把“主线完成”的定义定在 `Phase 3` 结束：那时结构已经真正收敛，但还没有为了追求形式对称去动不该动的产品差异。

