# 20260722_162446_macos_toolbar_manual_animation_phase8_log_cleanup_record

## 背景

本次记录对应 `macOS 工具条手写滑入滑出动画计划` 的阶段 8：移除临时日志。

阶段 2-7 中为了验证 macOS toolbar 手写滑入 / 滑出动画是否仍存在 `y` 或 `height` 插值，临时保留了 toolbar transition frame diagnostics。阶段 8 在验证通过后移除这些临时诊断日志，保留实际动画逻辑不变。

## 修改 1：移除 toolbar host 的 frame diagnostics 状态

修改前，`macOSCanvasToolbarHostView` 内部有日志开关和延迟采样队列，用于输出 transition frame 的 model / presentation sample。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 位置：macOSCanvasToolbarHostView 属性区；修改前，保留临时 frame diagnostics 状态
private static let isTransitionFrameDiagnosticLoggingEnabled = true

private var isTransitionRendering = false
private var transitionInteractivity = true
private var latestItemStates: [CanvasToolbarItemState] = []
private var transitionFrameDiagnosticWorkItems: [DispatchWorkItem] = []
```

修改后，删除日志开关和采样队列，仅保留 toolbar host 的实际渲染状态。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 位置：macOSCanvasToolbarHostView 属性区；修改后，只保留运行时渲染状态
private var isTransitionRendering = false
private var transitionInteractivity = true
private var latestItemStates: [CanvasToolbarItemState] = []
```

## 修改 2：移除 renderTransition / applyTransitionImmediately 的日志调用

修改前，普通 transition 渲染和手写立即应用入口都会调用 `logTransitionRenderRequest(...)`，输出 `[Canvas macOS][ToolbarHostTransition]`。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：renderTransition(_:animated:)；修改前，transition 渲染时输出 host transition 日志
if shouldAnimate == false {
    clearTransitionAnimations()
}
logTransitionRenderRequest(
    presentation: presentation,
    animated: shouldAnimate
)
isTransitionRendering = true
transitionInteractivity = presentation.isInteractive
```

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：applyTransitionImmediately(_:)；修改前，手写 driver 每帧立即应用时也输出 host transition 日志
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
}
```

修改后，两个入口都直接进入渲染逻辑，不再输出临时 transition 日志。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：renderTransition(_:animated:)；修改后，保留渲染逻辑，移除日志调用
if shouldAnimate == false {
    clearTransitionAnimations()
}
isTransitionRendering = true
transitionInteractivity = presentation.isInteractive
```

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：applyTransitionImmediately(_:)；修改后，手写 driver 立即应用时不再打印日志
func applyTransitionImmediately(
    _ presentation: CanvasToolbarTransitionPresentation
) {
    clearTransitionAnimations()
    isTransitionRendering = true
    transitionInteractivity = presentation.isInteractive
}
```

## 修改 3：移除 frame 应用路径中的诊断采样

修改前，`applyTransitionFrame(_:animated:)` 和 `applyTransitionFrameImmediately(_:)` 会在 noop、begin、immediate 等阶段输出 frame request/sample。动画路径还会注册多个延迟 `DispatchWorkItem` 采样 presentation layer。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：applyTransitionFrame(_:animated:)；修改前，frame 应用时输出 diagnostics 并调度采样
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

修改后，frame 应用路径只保留实际 frame 写入或 AppKit animator 调用，不再输出和采样。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：applyTransitionFrame(_:animated:)；修改后，只保留实际 frame 应用逻辑
private func applyTransitionFrame(
    _ targetFrame: CGRect,
    animated: Bool
) {
    guard frame != targetFrame else {
        return
    }

    if animated {
        animator().setFrameOrigin(targetFrame.origin)
        animator().setFrameSize(targetFrame.size)
    } else {
        frame = targetFrame
    }
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：applyTransitionFrameImmediately(_:)；修改后，立即路径只直接设置 frame
private func applyTransitionFrameImmediately(_ targetFrame: CGRect) {
    guard frame != targetFrame else {
        return
    }

    frame = targetFrame
}
```

## 修改 4：删除 toolbar host 诊断函数

修改前，host view 中存在一组只服务临时日志的函数。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数组：临时 toolbar diagnostics；修改前，用于输出 frame request / frame sample / render request
private func scheduleTransitionFrameDiagnostics(
    sourceFrame: CGRect,
    targetFrame: CGRect,
    duration: TimeInterval
) {
    // 按 t0/t25/t50/t75/t100 调度 presentation layer 采样。
}

private func cancelTransitionFrameDiagnostics() {
    // 取消还未执行的诊断采样任务。
}

private func logTransitionFrameRequest(
    event: String,
    targetFrame: CGRect,
    animated: Bool
) {
    // 输出 [Canvas macOS][ToolbarFrameDiagnostics]。
}

private func logTransitionFrameSample(
    label: String,
    sourceFrame: CGRect,
    targetFrame: CGRect
) {
    // 输出 modelFrame / presentationFrame / delta。
}

private func logTransitionRenderRequest(
    presentation: CanvasToolbarTransitionPresentation,
    animated: Bool
) {
    // 输出 [Canvas macOS][ToolbarHostTransition]。
}
```

修改后，以上函数全部移除；`clearTransitionAnimations()` 只负责清除 layer animation。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：clearTransitionAnimations()；修改后，只保留动画清理职责
private func clearTransitionAnimations() {
    layer?.removeAllAnimations()
    backgroundView.layer?.removeAllAnimations()
    contentClipView.layer?.removeAllAnimations()
    buttonsStackView.layer?.removeAllAnimations()
}
```

## 修改 5：移除 controller 的 toolbar transition 打印调用

修改前，`prepareToolbarTransitionContext(direction:)` 构建 context 后会输出 `[Canvas macOS][ToolbarTransition] event=contextBuilt`；`animateToolbarTransition(to:duration:completion:)` 会输出 `event=animate`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：prepareToolbarTransitionContext(direction:)；修改前，构建 context 后输出日志
let context = CanvasToolbarTransitionContext(
    direction: direction,
    visibleSnapshot: CanvasToolbarTransitionSnapshot(
        state: visibleState,
        frame: visibleFrame
    ),
    settledState: settledState,
    frames: CanvasToolbarTransitionFrames(
        visibleFrame: visibleFrame,
        collapsedFrame: collapsedFrame,
        offscreenFrame: offscreenFrame
    ),
    configuration: configuration
)
logToolbarTransitionContext(context)
return context
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：animateToolbarTransition(to:duration:completion:)；修改前，动画前输出 target presentation 日志
let targetPresentation = CanvasToolbarTransitionGeometry.presentation(
    for: targetStage,
    context: runtime.context
)
logToolbarTransitionAnimation(
    context: runtime.context,
    stage: targetStage,
    presentation: targetPresentation,
    duration: duration
)
let expectedDirection = runtime.context.direction
```

修改后，两个位置都不再输出临时 transition 日志。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：prepareToolbarTransitionContext(direction:)；修改后，构建 context 后直接返回
let context = CanvasToolbarTransitionContext(
    direction: direction,
    visibleSnapshot: CanvasToolbarTransitionSnapshot(
        state: visibleState,
        frame: visibleFrame
    ),
    settledState: settledState,
    frames: CanvasToolbarTransitionFrames(
        visibleFrame: visibleFrame,
        collapsedFrame: collapsedFrame,
        offscreenFrame: offscreenFrame
    ),
    configuration: configuration
)
return context
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：animateToolbarTransition(to:duration:completion:)；修改后，计算 target presentation 后直接进入状态更新
let targetPresentation = CanvasToolbarTransitionGeometry.presentation(
    for: targetStage,
    context: runtime.context
)
let expectedDirection = runtime.context.direction
```

## 修改 6：删除 controller 中只服务 toolbar 日志的 helper

修改前，controller 里存在只服务 toolbar transition 日志的格式化函数和判断函数。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数组：toolbar transition 临时日志 helper；修改前，仅用于打印 transition diagnostics
private func describe(
    toolbarTransitionDirection: CanvasToolbarTransitionDirection
) -> String {
    // 格式化 toReading / toEditing。
}

private func describe(
    toolbarTransitionStage: CanvasToolbarTransitionStage
) -> String {
    // 格式化 steadyVisible / entering / exiting 等 stage。
}

private func logToolbarTransitionContext(
    _ context: CanvasToolbarTransitionContext
) {
    // 输出 contextBuilt 诊断日志。
}

private func logToolbarTransitionAnimation(
    context: CanvasToolbarTransitionContext,
    stage: CanvasToolbarTransitionStage,
    presentation: CanvasToolbarTransitionPresentation,
    duration: TimeInterval
) {
    // 输出 animate 诊断日志。
}

private func toolbarSlideDirectionDescription(
    for frames: CanvasToolbarTransitionFrames
) -> String {
    // 判断 right/left/up/down/diagonal，仅用于日志。
}

private func toolbarCollapseVerticalAnchorDescription(
    for frames: CanvasToolbarTransitionFrames
) -> String {
    // 判断 collapse anchor，仅用于日志。
}
```

修改后，这些 helper 全部删除；其他非 toolbar 的现有日志函数不属于本次阶段 8 范围，未修改。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 阶段 8：删除 toolbar transition 临时日志 helper
// No replacement code is required because the helpers only served temporary diagnostics.
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

已执行临时日志残留搜索：

```shell
# terminal
# 验证命令：确认 toolbar transition 临时日志标识无残留
rg "ToolbarFrameDiagnostics|ToolbarHostTransition|\\[Canvas macOS\\]\\[ToolbarTransition\\]|logToolbarTransition|isTransitionFrameDiagnosticLoggingEnabled|transitionFrameDiagnosticWorkItems|toolbarSlideDirectionDescription|toolbarCollapseVerticalAnchorDescription|describe\\(toolbarTransition" MyCanvas_Ver_0/Platform
```

结果：无匹配。

## 当前状态

当前 changes：

```shell
# terminal
# 命令：git status --short，显示阶段 8 代码改动和本记录文件
M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
?? commit_records/20260722_162446_macos_toolbar_manual_animation_phase8_log_cleanup_record.md
```

本次没有提交代码。
