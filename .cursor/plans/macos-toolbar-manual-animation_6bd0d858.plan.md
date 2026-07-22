---
name: macOS-toolbar-manual-animation
overview: 将 macOS 工具条编辑/阅读切换的滑入滑出从 AppKit animator 切换为手动 frame 驱动，确保 slide-only 动画期间只改变 x，不再出现 y/height 残留插值。保留现有 transition context/stage 计算和 collapse/expand 代码，先只替换 macOS 执行动画层。
todos:
  - id: manual-driver-entry
    content: 替换 macOS toolbar transition 的 NSAnimationContext 入口为手写 driver
    status: completed
  - id: axis-locked-frame
    content: 实现 slide-only 每帧只插值 x，固定 y/width/height
    status: pending
  - id: host-immediate-apply
    content: 为 macOS toolbar host 提供无 AppKit animator 的立即应用 presentation 路径
    status: pending
  - id: preserve-hidden-frame
    content: 保留并修正完整 offscreen hidden frame，避免 reading 态回落 68x68
    status: pending
  - id: verify-transition
    content: 运行 macOS build、toolbar 测试，并用日志验证 y/height 不再变化
    status: pending
isProject: false
---

# macOS 工具条手写滑入滑出动画计划

## 目标

让 macOS 上阅读态与编辑态切换时，工具条严格水平滑入 / 滑出：

- `x` 按 easing 插值变化。
- `y`、`width`、`height` 在动画开始前固定到目标尺寸，不参与动画。
- 不再使用 `NSAnimationContext.runAnimationGroup` / `animator().setFrameOrigin` / `animator().setFrameSize` 驱动 toolbar frame。
- 保留现有 `CanvasToolbarTransitionStage`、`CanvasToolbarTransitionContext`、`collapsing` / `expanding` 代码，只让当前 slide-only 流程用新的手写 animator。

## 阶段 1：隔离 macOS 手写动画入口

改动文件：

- [`/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`](/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)

计划：

- 保留 `animateToolbarTransition(to:duration:completion:)` 作为唯一外部入口。
- 将当前 `NSAnimationContext.runAnimationGroup` 分支替换为新的 macOS 手写驱动函数，例如 `runManualToolbarTransition(to:duration:completion:)`。
- `duration <= 0` 分支继续直接 render，不做动画。
- 继续更新 `toolbarTransitionRuntime.stage` 和 `currentPresentation`，避免打断/反向切换的状态机丢失。

关键点：controller 仍然使用 `CanvasToolbarTransitionGeometry.presentation(for:context:)` 计算目标 presentation，但不再把 frame 动画交给 AppKit。

## 阶段 2：实现主线程逐帧 driver

改动文件：

- [`/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`](/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)

计划：

- 新增一个 controller 级别的动画状态，例如：
  - 当前动画 token / UUID
  - `DispatchSourceTimer` 或 `Timer`
  - 起始 frame
  - 目标 frame
  - 开始时间、duration
- 默认使用主线程 `Timer`，间隔约 `1 / 60` 秒。原因是 toolbar 动画很短、只动一个 view，主线程 timer 足够稳定，也比引入 `CVDisplayLink` 简洁。
- 每帧计算 progress：`elapsed / duration`，范围 clamp 到 `0...1`。
- 使用 easeInOut 曲线，先复刻当前系统动画的感觉。
- 每帧直接设置 toolbar frame，不使用 `animator()`。

## 阶段 3：只插值允许变化的轴

改动文件：

- [`/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`](/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)

计划：

- 对 slide-only 的 `.entering` / `.exiting`：
  - 动画开始前，把 toolbar host 的 `y`、`width`、`height` 立即固定到目标 frame。
  - 每帧只插值 `x`。
- 对保留的 `.collapsing` / `.expanding`：
  - 暂时不主动使用，但保留兼容路径。
  - 如果以后重新启用，可走完整 rect 插值或独立策略。
- 对当前需求，重点保证 `.entering` / `.exiting` 不会再从旧 presentation layer 的 `y=301.5, height=68` 斜向插值。

## 阶段 4：host view 提供非动画 frame 应用能力

改动文件：

- [`/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`](/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift)

计划：

- 保留 `renderTransition(_:animated:)` 给普通非手写路径使用。
- 新增或调整一个明确的“立即应用 presentation”能力，要求：
  - 清掉当前 layer animation。
  - 直接设置 `frame`。
  - 直接设置 alpha / scale。
  - 不触发 `animator()`。
- 手写 driver 每帧调用该非动画路径，确保 AppKit 不插入 presentation layer 动画。
- 保留当前 `[Canvas macOS][ToolbarFrameDiagnostics]` 日志，先用于验证；稳定后再按你的要求决定是否移除。

## 阶段 5：清理隐藏态 frame 回落问题

改动文件：

- [`/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`](/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)

计划：

- 保留并修正 `preservedHiddenToolbarFrame` 思路，但不依赖它解决动画插值。
- 在 `toReading` 完成后保存完整 `offscreenFrame`。
- 在 reading layout pass 中继续优先使用完整 hidden frame，避免回落到 68x68 fallback。
- 在 `toEditing` 开始前，手写 animator 会显式把 host frame 同步到完整 offscreen 起点，彻底切断旧 presentation frame。

## 阶段 6：结束态对齐 steady layout

改动文件：

- [`/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`](/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)

计划：

- 动画完成时，强制应用 target presentation 的最终 frame。
- 然后再调用 `finishToolbarModeTransition(applying:)`。
- 对比日志中的 target frame 与最终 overlay layout frame，比如当前出现过的 `y=79.00` 到 `y=77.50` 差异。
- 如果差异仍存在，下一步把 `toEditing` 的 `visibleFrame` 改为和完成后的 `performOverlayLayoutPass()` 同源，避免动画 target 和 steady layout 使用不同输入。

## 阶段 7：验证与回归

验证命令：

- macOS build：`xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64'`
- toolbar placement 测试：`xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64' -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests`

手动验证：

- macOS 编辑态 -> 阅读态：工具条只向右水平滑出。
- macOS 阅读态 -> 编辑态：工具条只向左水平滑入。
- 日志中 `.entering` / `.exiting` 的 `presentationDeltaFromSource.y` 应保持 `0` 或接近 `0`。
- 滑动完成后，工具条不再出现高度或 y 方向二次调整。

## 阶段 8：日志策略

- 第一轮实现保留 frame diagnostics，方便确认没有 y/height 插值。
- 验证稳定后，再按你的指示处理：
  - 要么保留开关但默认关闭。
  - 要么移除临时日志。