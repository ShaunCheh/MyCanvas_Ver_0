# 20260722_154751_macOS 工具条滑入定位日志与完整隐藏 Frame 修复记录

## 记录范围

本记录根据当前 `git diff` 与 working tree changes 整理，记录刚刚针对 macOS 阅读态切回编辑态时工具条斜向上滑入的问题所做的修改。

当前涉及文件：

- `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 1. 添加 macOS toolbar frame 逐帧定位日志

### 修改前

`macOSCanvasToolbarHostView` 只有 transition render request 日志，能看到 controller 传入的目标 frame，但看不到 AppKit 动画过程中 model layer / presentation layer 的实时 frame。因此无法判断斜向滑动是目标 frame 本身有 y 位移，还是动画层从旧 frame 继续插值。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: applyTransitionFrame(_:animated:)
// 功能说明: 修改前只执行 frame 动画，没有记录每一段动画的实时 presentation frame。
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

### 修改后

新增 `isTransitionFrameDiagnosticLoggingEnabled`、`transitionFrameDiagnosticWorkItems` 和一组诊断方法。每次 frame transition 会打印：

- 动画开始时的 `currentFrame`、`targetFrame`、`originDelta`、`sizeDelta`
- t0 / t25 / t50 / t75 / t100 的 `modelFrame` 与 `presentationFrame`
- `targetDeltaFromSource`、`modelDeltaFromSource`、`presentationDeltaFromSource`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: macOSCanvasToolbarHostView
// 功能说明: 开关和 work item 列表用于控制、取消 toolbar frame 逐帧定位日志。
private static let isTransitionFrameDiagnosticLoggingEnabled = true

private var transitionFrameDiagnosticWorkItems: [DispatchWorkItem] = []
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: applyTransitionFrame(_:animated:)
// 功能说明: frame 动画前记录目标变化；动画时安排采样；非动画设置时记录 immediate sample。
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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: scheduleTransitionFrameDiagnostics(sourceFrame:targetFrame:duration:)
// 功能说明: 在动画过程的多个时间点采样 model frame 与 presentation frame，定位 y/height 是否被隐式动画带入。
private func scheduleTransitionFrameDiagnostics(
    sourceFrame: CGRect,
    targetFrame: CGRect,
    duration: TimeInterval
) {
    guard Self.isTransitionFrameDiagnosticLoggingEnabled else {
        return
    }

    cancelTransitionFrameDiagnostics()

    let sanitizedDuration = max(duration, 0)
    let samplePoints: [(label: String, delay: TimeInterval)] = [
        ("t0", 0),
        ("t25", sanitizedDuration * 0.25),
        ("t50", sanitizedDuration * 0.50),
        ("t75", sanitizedDuration * 0.75),
        ("t100", sanitizedDuration)
    ]

    transitionFrameDiagnosticWorkItems = samplePoints.map { samplePoint in
        let workItem = DispatchWorkItem { [weak self] in
            self?.logTransitionFrameSample(
                label: samplePoint.label,
                sourceFrame: sourceFrame,
                targetFrame: targetFrame
            )
        }

        if samplePoint.delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + samplePoint.delay,
                execute: workItem
            )
        }
        return workItem
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: logTransitionFrameSample(label:sourceFrame:targetFrame:)
// 功能说明: 输出动画采样点，用于判断真实 presentation layer 是否出现 y 方向位移。
private func logTransitionFrameSample(
    label: String,
    sourceFrame: CGRect,
    targetFrame: CGRect
) {
    guard Self.isTransitionFrameDiagnosticLoggingEnabled else {
        return
    }

    let modelFrame = frame
    let presentationFrame = layer?.presentation()?.frame
    let presentationDescription = presentationFrame.map(describe(rect:)) ?? "nil"
    let modelDeltaFromSource = CGPoint(
        x: modelFrame.minX - sourceFrame.minX,
        y: modelFrame.minY - sourceFrame.minY
    )
    let presentationDeltaFromSource = presentationFrame.map { frame in
        CGPoint(
            x: frame.minX - sourceFrame.minX,
            y: frame.minY - sourceFrame.minY
        )
    }
    let presentationDeltaDescription = presentationDeltaFromSource
        .map(describe(point:)) ?? "nil"
    let targetDeltaFromSource = CGPoint(
        x: targetFrame.minX - sourceFrame.minX,
        y: targetFrame.minY - sourceFrame.minY
    )

    print(
        "[Canvas macOS][ToolbarFrameDiagnostics] " +
        "event=animationSample " +
        "sample=\(label) " +
        "sourceFrame=\(describe(rect: sourceFrame)) " +
        "targetFrame=\(describe(rect: targetFrame)) " +
        "modelFrame=\(describe(rect: modelFrame)) " +
        "presentationFrame=\(presentationDescription) " +
        "targetDeltaFromSource=\(describe(point: targetDeltaFromSource)) " +
        "modelDeltaFromSource=\(describe(point: modelDeltaFromSource)) " +
        "presentationDeltaFromSource=\(presentationDeltaDescription)"
    )
}
```

## 2. 定位结果

日志证明：`toReading` 滑出本身是水平的，`slideDelta.y == 0`，采样中的 `presentationDeltaFromSource.y` 也为 `0`。

问题发生在 `toEditing` 之前：阅读态隐藏后，toolbar host 被后续 overlay layout 回落到了 68x68 的 collapsed hidden fallback：

```swift
// 文件路径: 日志摘录
// 函数名: macOS toolbar transition diagnostics
// 功能说明: toEditing 前 currentHostFrame 已经从完整 offscreen frame 变成了 68x68 小方块。
currentHostFrame={{640.00, 280.50}, {68.00, 68.00}}
visibleFrame={{552.00, 79.00}, {68.00, 516.00}}
offscreenFrame={{640.00, 79.00}, {68.00, 516.00}}
```

因此，虽然 `toEditing` 的目标滑入动画是水平的，presentation layer 仍会从旧的 `y=280.50` 追到 `y=79.00`，视觉上表现为斜向上滑入。

## 3. 保存完整 offscreen hidden frame

### 修改前

`performOverlayLayoutPass()` 在 toolbar state 为空时直接使用 placement pass 的 `hiddenToolbarFrame`。该 hidden frame 是 collapsed fallback，大小为 68x68，位置居中在右侧。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performOverlayLayoutPass()
// 功能说明: 修改前阅读态 layout 会把隐藏 toolbar frame 回落到 placement pass 的 collapsed hidden frame。
applyToolbarFrame(
    toolbarState.items.isEmpty
        ? toolbarPlacementResult.hiddenToolbarFrame
        : toolbarPlacementResult.toolbarFrame
)
```

### 修改后

新增 `preservedHiddenToolbarFrame`，在 `performOverlayLayoutPass()` 中通过 `resolvedOverlayToolbarFrame(for:placementResult:)` 决定实际应用的 toolbar frame：

- toolbar 有 items：清空 preserved frame，使用正常 visible toolbar frame
- toolbar 没有 items：优先使用保存的完整 offscreen frame
- 没有保存值时：回退到原来的 `hiddenToolbarFrame`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: macOSViewController
// 功能说明: 保存阅读态隐藏后的完整 offscreen toolbar frame，避免下一次编辑态滑入从 68x68 小方块开始。
private var preservedHiddenToolbarFrame: CGRect?
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performOverlayLayoutPass()
// 功能说明: 修改后 overlay layout 使用统一 resolver，避免空 toolbar 时直接回落到 collapsed fallback。
let resolvedToolbarFrame = resolvedOverlayToolbarFrame(
    for: toolbarState,
    placementResult: toolbarPlacementResult
)
applyToolbarFrame(resolvedToolbarFrame)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: resolvedOverlayToolbarFrame(for:placementResult:)
// 功能说明: 阅读态隐藏时优先保留完整 offscreen frame；编辑态恢复时清空保存值。
private func resolvedOverlayToolbarFrame(
    for toolbarState: CanvasToolbarState,
    placementResult: CanvasToolbarPlacementPassResult
) -> CGRect {
    guard toolbarState.items.isEmpty else {
        preservedHiddenToolbarFrame = nil
        return placementResult.toolbarFrame
    }

    guard
        let rawPreservedHiddenToolbarFrame = preservedHiddenToolbarFrame,
        let sanitizedPreservedHiddenToolbarFrame = CanvasChromeLayoutGeometry
            .sanitizedRect(rawPreservedHiddenToolbarFrame)
    else {
        return placementResult.hiddenToolbarFrame
    }

    return sanitizedPreservedHiddenToolbarFrame
}
```

## 4. transition finish 时记录 hidden frame

### 修改前

`finishToolbarModeTransition(applying:)` 只结束 runtime、完成 host transition，并在需要时执行 layout reconcile。它没有把刚滑出去的完整 offscreen frame 保存下来，因此后续阅读态 layout 会使用 placement pass 的 68x68 fallback。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: finishToolbarModeTransition(applying:)
// 功能说明: 修改前 transition 结束后没有保留完整 offscreen frame。
private func finishToolbarModeTransition(
    applying settledState: CanvasToolbarState
) {
    let pendingLayoutReconcile = toolbarTransitionRuntime?.pendingLayoutReconcile
        ?? true
    toolbarTransitionRuntime = nil
    toolbarHostView.completeTransition(applying: settledState)
    if pendingLayoutReconcile {
        updatePreparedToolbarPlacement()
    }
}
```

### 修改后

当 settled state 为空 toolbar（阅读态隐藏工具条）时，保存当前 transition context 的 `frames.offscreenFrame`。当 settled state 有 items（编辑态显示工具条）时，清空保存值。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: finishToolbarModeTransition(applying:)
// 功能说明: 阅读态隐藏后保存完整 offscreen frame，防止后续 layout 把隐藏工具条缩回 68x68。
private func finishToolbarModeTransition(
    applying settledState: CanvasToolbarState
) {
    let transitionContext = toolbarTransitionRuntime?.context
    let pendingLayoutReconcile = toolbarTransitionRuntime?.pendingLayoutReconcile
        ?? true
    if settledState.items.isEmpty {
        preservedHiddenToolbarFrame = transitionContext?.frames.offscreenFrame
    } else {
        preservedHiddenToolbarFrame = nil
    }
    toolbarTransitionRuntime = nil
    toolbarHostView.completeTransition(applying: settledState)
    if pendingLayoutReconcile {
        updatePreparedToolbarPlacement()
    }
}
```

## 5. 编译修正过程

实现过程中曾出现两个编译问题，并已修复：

- 初次使用了不存在的类型名 `CanvasToolbarPlacementResult`，实际类型是 `CanvasToolbarPlacementPassResult`
- 对 `preservedHiddenToolbarFrame` optional 直接传给 `sanitizedRect`，后改为先绑定 raw frame 再 sanitize

最终 macOS build 已通过。

## 验证情况

已执行并通过：

- `ReadLints` 检查 `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`，无 linter errors
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64'`

创建本记录前，当前 `git status --short` 显示本次代码改动为：

- `M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- `M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

本次仅创建记录文件，没有提交 commit。
