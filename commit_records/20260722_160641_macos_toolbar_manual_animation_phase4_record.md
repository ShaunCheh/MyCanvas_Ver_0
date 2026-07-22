# 20260722_160641_macos_toolbar_manual_animation_phase4_record

## 背景

本次记录对应 `macOS 工具条手写滑入滑出动画计划` 的阶段 4：为 macOS toolbar host 提供明确的非动画 presentation 应用能力。

阶段 2 已将 macOS toolbar transition 改为手写逐帧 driver，阶段 3 已让 `.entering` / `.exiting` 只插值 `x`。本次阶段 4 的目标是让手写 driver 不再复用普通 `renderTransition(_:animated:)` 路径，而是调用一个明确的“立即应用”入口，确保每帧都直接写 frame / alpha / scale，并先清理 layer animation。

## 修改 1：新增 host 立即应用 presentation 入口

修改前，`macOSCanvasToolbarHostView` 只有 `renderTransition(_:animated:)` 作为 transition presentation 渲染入口。即使传入 `animated: false`，手写 driver 仍和普通 transition 路径共用同一个方法。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：renderTransition(_:animated:)；修改前，普通 transition 与手写 driver 共用入口
func renderTransition(
    _ presentation: CanvasToolbarTransitionPresentation,
    animated explicitAnimated: Bool? = nil
) {
    let shouldAnimate = explicitAnimated ?? shouldAnimateTransitionChanges
    if shouldAnimate == false {
        clearTransitionAnimations()
    }
    logTransitionRenderRequest(
        presentation: presentation,
        animated: shouldAnimate
    )
    isTransitionRendering = true
    transitionInteractivity = presentation.isInteractive
    backgroundView.isHidden = presentation.showsBackground == false
    applyTransitionFrame(presentation.frame, animated: shouldAnimate)
    syncButtons(with: presentation.itemStates)
    applyContentTransitionAppearance(
        alpha: presentation.contentAlpha,
        scale: presentation.contentScale,
        animated: shouldAnimate
    )
    isHidden = presentation.keepsHostVisible == false
}
```

修改后，新增 `applyTransitionImmediately(_:)`。该方法专门服务手写 driver：先清理动画，再直接应用 frame、按钮状态、alpha、scale，不调用 `animator()`。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：applyTransitionImmediately(_:)；新增，手写动画逐帧使用的非动画入口
func applyTransitionImmediately(
    _ presentation: CanvasToolbarTransitionPresentation
) {
    clearTransitionAnimations()
    logTransitionRenderRequest(
        presentation: presentation,
        animated: false
    )
    isTransitionRendering = true
    transitionInteractivity = presentation.isInteractive
    backgroundView.isHidden = presentation.showsBackground == false
    applyTransitionFrameImmediately(presentation.frame)
    syncButtons(with: presentation.itemStates)
    applyContentTransitionAppearance(
        alpha: presentation.contentAlpha,
        scale: presentation.contentScale,
        animated: false
    )
    isHidden = presentation.keepsHostVisible == false
}
```

## 修改 2：新增直接 frame 应用 helper

修改前，frame 的应用集中在 `applyTransitionFrame(_:animated:)`。当 `animated == true` 时它会走 `animator().setFrameOrigin` / `animator().setFrameSize`；当 `animated == false` 时直接写 `frame`。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：applyTransitionFrame(_:animated:)；修改前，普通 frame 应用入口同时支持 animated / immediate
private func applyTransitionFrame(
    _ targetFrame: CGRect,
    animated: Bool
) {
    guard frame != targetFrame else {
        logTransitionFrameRequest(
            event: "applyTransitionFrame.noop",
            targetFrame: targetFrame,
            animated: animated
        )
        return
    }

    logTransitionFrameRequest(
        event: "applyTransitionFrame.begin",
        targetFrame: targetFrame,
        animated: animated
    )

    if animated {
        scheduleTransitionFrameDiagnostics(
            sourceFrame: frame,
            targetFrame: targetFrame,
            duration: NSAnimationContext.current.duration
        )
        animator().setFrameOrigin(targetFrame.origin)
        animator().setFrameSize(targetFrame.size)
    } else {
        cancelTransitionFrameDiagnostics()
        frame = targetFrame
        logTransitionFrameSample(
            label: "immediate",
            sourceFrame: frame,
            targetFrame: targetFrame
        )
    }
}
```

修改后，新增 `applyTransitionFrameImmediately(_:)`。该 helper 明确只做非动画 frame 写入，保留 frame diagnostics 日志，并在写入前取消 transition frame diagnostics。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：applyTransitionFrameImmediately(_:)；新增，明确不走 AppKit animator 的 frame 应用路径
private func applyTransitionFrameImmediately(_ targetFrame: CGRect) {
    guard frame != targetFrame else {
        logTransitionFrameRequest(
            event: "applyTransitionFrameImmediately.noop",
            targetFrame: targetFrame,
            animated: false
        )
        return
    }

    let sourceFrame = frame
    logTransitionFrameRequest(
        event: "applyTransitionFrameImmediately.begin",
        targetFrame: targetFrame,
        animated: false
    )

    cancelTransitionFrameDiagnostics()
    frame = targetFrame
    logTransitionFrameSample(
        label: "immediate",
        sourceFrame: sourceFrame,
        targetFrame: targetFrame
    )
}
```

## 修改 3：transition 初始化帧改用立即路径

修改前，`macOSViewController` 在创建 `toolbarTransitionRuntime` 后，用 `renderTransition(..., animated: false)` 应用初始 presentation。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：toggleWorkspaceMode(to:)；修改前，初始 transition presentation 走普通 renderTransition
toolbarTransitionRuntime = CanvasToolbarTransitionRuntime(
    context: context,
    stage: initialStage,
    currentPresentation: initialPresentation,
    pendingLayoutReconcile: true
)
toolbarHostView.renderTransition(
    initialPresentation,
    animated: false
)
```

修改后，初始 presentation 也走 `applyTransitionImmediately(_:)`，避免手写 transition 链路一开始仍复用普通 transition 渲染入口。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：toggleWorkspaceMode(to:)；修改后，初始 transition presentation 直接应用
toolbarTransitionRuntime = CanvasToolbarTransitionRuntime(
    context: context,
    stage: initialStage,
    currentPresentation: initialPresentation,
    pendingLayoutReconcile: true
)
toolbarHostView.applyTransitionImmediately(initialPresentation)
```

## 修改 4：手写 driver 每帧改用立即路径

修改前，`runManualToolbarTransition(from:to:targetStage:duration:completion:)` 每帧仍调用 `renderTransition(..., animated: false)`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:targetStage:duration:completion:)；修改前，每帧复用普通 transition 渲染入口
self.toolbarHostView.renderTransition(
    presentation,
    animated: false
)
```

修改后，每帧调用 `applyTransitionImmediately(_:)`，确保手写 timer driver 的每一帧都清理 layer animation 并直接写 presentation。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:targetStage:duration:completion:)；修改后，每帧使用明确的立即应用入口
self.toolbarHostView.applyTransitionImmediately(presentation)
```

## 修改 5：手写 driver 结束帧改用立即路径

修改前，timer 完成时使用 `renderTransition(..., animated: false)` 强制应用 `targetPresentation`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:targetStage:duration:completion:)；修改前，结束帧走普通 transition 渲染入口
self.toolbarHostView.renderTransition(
    targetPresentation,
    animated: false
)
completion()
```

修改后，结束帧也使用 `applyTransitionImmediately(_:)`，保证最终帧与逐帧路径一致。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:targetStage:duration:completion:)；修改后，结束帧也直接应用
self.toolbarHostView.applyTransitionImmediately(targetPresentation)
completion()
```

## 验证

已执行 lints 检查：

```shell
# terminal
# 验证命令：检查本次修改的 macOS toolbar host 和 controller
ReadLints(paths: [
    "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift",
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
# 命令：git status --short，显示阶段 4 代码改动和本记录文件
M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
?? commit_records/20260722_160641_macos_toolbar_manual_animation_phase4_record.md
```

本次没有提交代码。
