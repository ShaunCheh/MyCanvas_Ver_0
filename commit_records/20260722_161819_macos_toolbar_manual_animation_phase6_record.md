# 20260722_161819_macos_toolbar_manual_animation_phase6_record

## 背景

本次记录对应 `macOS 工具条手写滑入滑出动画计划` 的阶段 6：结束态对齐 steady layout。

阶段 2-5 已经完成手写逐帧 driver、slide-only 只插值 `x`、host 非动画立即应用路径，以及 hidden frame 回落处理。本次阶段 6 的目标是让动画完成时先对齐最终 frame，再进入 `finishToolbarModeTransition(applying:)`，避免 target presentation 与 finish 后 overlay layout 计算出的 steady frame 不一致。

## 修改 1：`duration <= 0` 路径也对齐 completion frame

修改前，`animateToolbarTransition(to:duration:completion:)` 在 `duration <= 0` 时直接取消 timer，并通过普通 `renderTransition(..., animated: false)` 应用 `targetPresentation`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：animateToolbarTransition(to:duration:completion:)；修改前，零时长路径直接应用 targetPresentation
if duration <= 0 {
    cancelManualToolbarTransition()
    toolbarHostView.renderTransition(
        targetPresentation,
        animated: false
    )
    completion()
    return
}
```

修改后，零时长路径也先生成 `completionPresentation`。该 presentation 会根据目标 stage 把 frame 对齐到最终 steady layout 或完整 offscreen frame，再立即应用。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：animateToolbarTransition(to:duration:completion:)；修改后，零时长路径先对齐 completion frame
if duration <= 0 {
    let completionPresentation = reconciledToolbarCompletionPresentation(
        targetPresentation,
        targetStage: targetStage,
        context: runtime.context
    )
    updateCurrentToolbarTransitionPresentation(
        completionPresentation,
        targetStage: targetStage,
        expectedDirection: expectedDirection
    )
    cancelManualToolbarTransition()
    toolbarHostView.applyTransitionImmediately(completionPresentation)
    completion()
    return
}
```

## 修改 2：手写 driver 接收 transition context

修改前，`runManualToolbarTransition(from:to:targetStage:duration:completion:)` 只知道 source / target presentation 与 target stage，不持有 `CanvasToolbarTransitionContext`。结束帧只能使用旧的 `targetPresentation`，无法基于 context 计算完成态 frame。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:targetStage:duration:completion:)；修改前，driver 不接收 context
runManualToolbarTransition(
    from: sourcePresentation,
    to: targetPresentation,
    targetStage: targetStage,
    duration: duration
) { [weak self] in
    guard let self else {
        return
    }
    guard let currentRuntime = self.toolbarTransitionRuntime,
          currentRuntime.context.direction == expectedDirection,
          currentRuntime.stage == targetStage
    else {
        return
    }

    completion()
}
```

修改后，调用时传入 `runtime.context`，driver 完成时可以根据 direction、settled state、offscreen frame 等信息计算真正的 completion presentation。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：animateToolbarTransition(to:duration:completion:)；修改后，将 runtime.context 传入手写 driver
runManualToolbarTransition(
    from: sourcePresentation,
    to: targetPresentation,
    context: runtime.context,
    targetStage: targetStage,
    duration: duration
) { [weak self] in
    guard let self else {
        return
    }
    guard let currentRuntime = self.toolbarTransitionRuntime,
          currentRuntime.context.direction == expectedDirection,
          currentRuntime.stage == targetStage
    else {
        return
    }

    completion()
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:context:targetStage:duration:completion:)；修改后，driver 签名包含 context
private func runManualToolbarTransition(
    from sourcePresentation: CanvasToolbarTransitionPresentation,
    to targetPresentation: CanvasToolbarTransitionPresentation,
    context: CanvasToolbarTransitionContext,
    targetStage: CanvasToolbarTransitionStage,
    duration: TimeInterval,
    completion: @escaping () -> Void
) {
    // 手写 timer driver 逻辑保持不变，完成时使用 context 对齐终态 frame。
}
```

## 修改 3：timer 完成时先对齐最终 frame

修改前，timer 到达 `linearProgress >= 1` 后，直接应用 `targetPresentation`，然后调用 completion。若 `targetPresentation.frame` 与 finish 后 overlay layout 的 frame 不同，用户会看到动画完成后的二次 y / height 调整。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:targetStage:duration:completion:)；修改前，完成时直接应用 targetPresentation
timer.invalidate()
if self.toolbarManualTransitionTimer === timer {
    self.toolbarManualTransitionTimer = nil
}
self.toolbarHostView.applyTransitionImmediately(targetPresentation)
completion()
```

修改后，timer 完成时先生成 `completionPresentation`，更新 runtime 的 current presentation，再应用该最终 presentation，最后才调用 completion / finish。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:context:targetStage:duration:completion:)；修改后，完成时应用对齐后的 completionPresentation
timer.invalidate()
if self.toolbarManualTransitionTimer === timer {
    self.toolbarManualTransitionTimer = nil
}
let completionPresentation = self.reconciledToolbarCompletionPresentation(
    targetPresentation,
    targetStage: targetStage,
    context: context
)
self.updateCurrentToolbarTransitionPresentation(
    completionPresentation,
    targetStage: targetStage,
    expectedDirection: context.direction
)
self.toolbarHostView.applyTransitionImmediately(completionPresentation)
completion()
```

## 修改 4：新增 completion presentation 对齐 helper

新增 `reconciledToolbarCompletionPresentation(_:targetStage:context:)`。它只负责在终态需要对齐时替换 frame，保留原 presentation 的 item states、background、alpha、scale、interactivity 等属性。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：reconciledToolbarCompletionPresentation(_:targetStage:context:)；新增，生成对齐后的完成态 presentation
private func reconciledToolbarCompletionPresentation(
    _ presentation: CanvasToolbarTransitionPresentation,
    targetStage: CanvasToolbarTransitionStage,
    context: CanvasToolbarTransitionContext
) -> CanvasToolbarTransitionPresentation {
    guard let reconciledFrame = reconciledToolbarCompletionFrame(
        targetStage: targetStage,
        context: context,
        fallback: presentation.frame
    ) else {
        return presentation
    }

    var reconciledPresentation = presentation
    reconciledPresentation.frame = reconciledFrame
    return reconciledPresentation
}
```

## 修改 5：按目标 stage 选择完成态 frame 来源

新增 `reconciledToolbarCompletionFrame(targetStage:context:fallback:)`。规则如下：

- `.steadyVisible`：使用 `resolvedSteadyToolbarFrame(for: context.settledState)`。
- `.entering(progress >= 0.999)` / `.expanding(progress >= 0.999)`：使用 `resolvedSteadyToolbarFrame(for: context.settledState)`。
- `.hidden` / `.exiting(progress >= 0.999)`：使用 `context.frames.offscreenFrame`。
- 其他中间阶段：不替换 frame。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：reconciledToolbarCompletionFrame(targetStage:context:fallback:)；新增，按终态阶段选择 frame 来源
private func reconciledToolbarCompletionFrame(
    targetStage: CanvasToolbarTransitionStage,
    context: CanvasToolbarTransitionContext,
    fallback: CGRect
) -> CGRect? {
    switch targetStage {
    case .steadyVisible:
        return resolvedSteadyToolbarFrame(
            for: context.settledState
        )

    case .hidden:
        return normalizedToolbarFrame(
            context.frames.offscreenFrame,
            fallback: fallback
        )

    case let .entering(progress)
        where clampedToolbarTransitionProgress(progress) >= 0.999:
        return resolvedSteadyToolbarFrame(
            for: context.settledState
        )

    case let .expanding(progress)
        where clampedToolbarTransitionProgress(progress) >= 0.999:
        return resolvedSteadyToolbarFrame(
            for: context.settledState
        )

    case let .exiting(progress)
        where clampedToolbarTransitionProgress(progress) >= 0.999:
        return normalizedToolbarFrame(
            context.frames.offscreenFrame,
            fallback: fallback
        )

    case .collapsing, .entering, .exiting, .expanding:
        return nil
    }
}
```

## 修改 6：同步 runtime 的 current presentation

新增 `updateCurrentToolbarTransitionPresentation(_:targetStage:expectedDirection:)`。在应用 completion presentation 之前，同步更新 `toolbarTransitionRuntime.currentPresentation`，避免 finish 前 runtime 仍保存旧的 target frame。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：updateCurrentToolbarTransitionPresentation(_:targetStage:expectedDirection:)；新增，保持 runtime 与最终帧一致
private func updateCurrentToolbarTransitionPresentation(
    _ presentation: CanvasToolbarTransitionPresentation,
    targetStage: CanvasToolbarTransitionStage,
    expectedDirection: CanvasToolbarTransitionDirection
) {
    guard var runtime = toolbarTransitionRuntime,
          runtime.context.direction == expectedDirection,
          runtime.stage == targetStage
    else {
        return
    }

    runtime.currentPresentation = presentation
    toolbarTransitionRuntime = runtime
}
```

## 验证

已执行 lints 检查：

```shell
# terminal
# 验证命令：检查本次修改的 macOSViewController.swift
ReadLints(paths: [
    "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
])
```

结果：无 linter 错误。

已执行 macOS build：

```shell
# terminal
# 验证命令：macOS arm64 build
xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64'
```

结果：build 通过。

## 当前状态

当前 changes：

```shell
# terminal
# 命令：git status --short，显示阶段 6 代码改动和本记录文件
M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
?? commit_records/20260722_161819_macos_toolbar_manual_animation_phase6_record.md
```

本次没有提交代码。
