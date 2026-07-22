# 20260722_161245_macos_toolbar_manual_animation_phase5_record

## 背景

本次记录对应 `macOS 工具条手写滑入滑出动画计划` 的阶段 5：清理隐藏态 frame 回落问题。

阶段 2-4 已经将 macOS toolbar transition 改为手写 driver、slide-only 只插值 `x`、并为 host view 提供了非动画立即应用路径。本次阶段 5 继续处理 reading 态 toolbar 为空时的隐藏 frame：保留完整 offscreen hidden frame，并在 reading layout 与 reading → editing 起点中优先使用它，避免回落到小尺寸 fallback。

## 修改 1：统一清理和读取 preserved hidden frame

修改前，`resolvedOverlayToolbarFrame(for:placementResult:)` 在 toolbar 为空时直接读取 `preservedHiddenToolbarFrame`，并在函数内临时做 sanitized 处理；当 toolbar 非空时直接把属性设为 `nil`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：resolvedOverlayToolbarFrame(for:placementResult:)；修改前，直接操作 preservedHiddenToolbarFrame
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

修改后，新增 `preserveHiddenToolbarFrame(_:)` 和 `sanitizedPreservedHiddenToolbarFrame()`，保存和读取都走同一条 sanitized 路径。非空 toolbar 时也通过 helper 清空，避免散落的直接赋值。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：resolvedOverlayToolbarFrame(for:placementResult:)；修改后，空 toolbar 优先使用清洗后的完整 hidden frame
private func resolvedOverlayToolbarFrame(
    for toolbarState: CanvasToolbarState,
    placementResult: CanvasToolbarPlacementPassResult
) -> CGRect {
    guard toolbarState.items.isEmpty else {
        preserveHiddenToolbarFrame(nil)
        return placementResult.toolbarFrame
    }

    return sanitizedPreservedHiddenToolbarFrame()
        ?? placementResult.hiddenToolbarFrame
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：preserveHiddenToolbarFrame(_:)；新增，保存前清洗完整 hidden frame
private func preserveHiddenToolbarFrame(_ frame: CGRect?) {
    preservedHiddenToolbarFrame = frame.flatMap { candidateFrame in
        CanvasChromeLayoutGeometry.sanitizedRect(candidateFrame)
    }
}

// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：sanitizedPreservedHiddenToolbarFrame()；新增，读取时再次保证 frame 合法
private func sanitizedPreservedHiddenToolbarFrame() -> CGRect? {
    guard let preservedHiddenToolbarFrame else {
        return nil
    }

    return CanvasChromeLayoutGeometry.sanitizedRect(
        preservedHiddenToolbarFrame
    )
}
```

## 修改 2：transition 完成时保存完整 offscreen frame

修改前，`finishToolbarModeTransition(applying:)` 在 settled state 为空时直接把 `transitionContext?.frames.offscreenFrame` 赋给 `preservedHiddenToolbarFrame`；非空时直接置空。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：finishToolbarModeTransition(applying:)；修改前，直接保存或清空 preservedHiddenToolbarFrame
if settledState.items.isEmpty {
    preservedHiddenToolbarFrame = transitionContext?.frames.offscreenFrame
} else {
    preservedHiddenToolbarFrame = nil
}
cancelManualToolbarTransition()
toolbarTransitionRuntime = nil
```

修改后，保存和清空都通过 `preserveHiddenToolbarFrame(_:)`，确保保存的是清洗后的完整 offscreen hidden frame。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：finishToolbarModeTransition(applying:)；修改后，通过 helper 保存完整 offscreen hidden frame
if settledState.items.isEmpty {
    preserveHiddenToolbarFrame(transitionContext?.frames.offscreenFrame)
} else {
    preserveHiddenToolbarFrame(nil)
}
cancelManualToolbarTransition()
toolbarTransitionRuntime = nil
```

## 修改 3：空 toolbar 的 steady frame 优先使用 preserved frame

修改前，`resolvedSteadyToolbarFrame(for:)` 不读取 `preservedHiddenToolbarFrame`。如果 state 为空，它会走 placement pass 的 `hiddenToolbarFrame`，这可能是根据空 measured size 推导出的 fallback hidden frame。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：resolvedSteadyToolbarFrame(for:)；修改前，空 state 仍由 placement pass 计算 hidden frame
private func resolvedSteadyToolbarFrame(
    for state: CanvasToolbarState
) -> CGRect {
    let placementResult = CanvasToolbarPlacementPass.resolve(
        safeBounds: toolbarLayoutSafeBounds(),
        toolbarPreferredPlacement: state.placement,
        toolbarMeasuredSize: measuredToolbarHostSize(for: state),
        baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
        scale: toolbarPlacementScale(),
        solver: toolbarPlacementSolver
    )
    let steadyFrame = state.items.isEmpty
        ? placementResult.hiddenToolbarFrame
        : placementResult.toolbarFrame
}
```

修改后，state 为空且存在 preserved hidden frame 时，直接返回该完整 frame，避免 reading 态 steady layout 回落到小 fallback。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：resolvedSteadyToolbarFrame(for:)；修改后，空 state 优先使用完整 preserved hidden frame
private func resolvedSteadyToolbarFrame(
    for state: CanvasToolbarState
) -> CGRect {
    if state.items.isEmpty,
       let preservedHiddenToolbarFrame = sanitizedPreservedHiddenToolbarFrame()
    {
        return preservedHiddenToolbarFrame
    }

    let placementResult = CanvasToolbarPlacementPass.resolve(
        safeBounds: toolbarLayoutSafeBounds(),
        toolbarPreferredPlacement: state.placement,
        toolbarMeasuredSize: measuredToolbarHostSize(for: state),
        baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
        scale: toolbarPlacementScale(),
        solver: toolbarPlacementSolver
    )
    let steadyFrame = state.items.isEmpty
        ? placementResult.hiddenToolbarFrame
        : placementResult.toolbarFrame
}
```

## 修改 4：记录 transition 开始前是否已有 active runtime

修改前，`beginToolbarModeTransition(to:)` 会直接调用 `cancelAndRebaseToolbarTransitionIfNeeded(targetMode:)`，之后再准备 context。普通 reading → editing 和中途反向切换没有显式区分。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：beginToolbarModeTransition(to:)；修改前，没有记录是否是中途 rebase
dismissContextMenu()
cancelAndRebaseToolbarTransitionIfNeeded(targetMode: targetMode)

guard let context = prepareToolbarTransitionContext(direction: direction) else {
    toolbarTransitionRuntime = nil
    updatePreparedToolbarPlacement()
    return
}
```

修改后，在 rebase 前保存 `hadActiveToolbarTransition`。后续只有“非 rebase 的普通 reading → editing”才会强制同步 offscreen 起点；中途反向切换继续沿用当前 progress，不被硬切到起点。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：beginToolbarModeTransition(to:)；修改后，记录 transition 开始前是否已有 active runtime
dismissContextMenu()
let hadActiveToolbarTransition = toolbarTransitionRuntime != nil
cancelAndRebaseToolbarTransitionIfNeeded(targetMode: targetMode)

guard let context = prepareToolbarTransitionContext(direction: direction) else {
    toolbarTransitionRuntime = nil
    updatePreparedToolbarPlacement()
    return
}
```

## 修改 5：toEditing 初始 presentation 同步到完整 offscreen 起点

修改前，初始 presentation 由 `CanvasToolbarTransitionGeometry.presentation(for:context:)` 直接生成，并作为 runtime 的 `currentPresentation` 与 host 的第一帧。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：beginToolbarModeTransition(to:)；修改前，直接应用 initialPresentation
let initialPresentation = CanvasToolbarTransitionGeometry.presentation(
    for: initialStage,
    context: context
)

toolbarTransitionRuntime = CanvasToolbarTransitionRuntime(
    context: context,
    stage: initialStage,
    currentPresentation: initialPresentation,
    pendingLayoutReconcile: true
)
toolbarHostView.applyTransitionImmediately(initialPresentation)
```

修改后，先生成 `synchronizedInitialPresentation`。普通 reading → editing 且初始 stage 为 `.entering` 时，会把 frame 明确同步到 `context.frames.offscreenFrame`，切断 reading 态可能残留的小 hidden frame。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：beginToolbarModeTransition(to:)；修改后，应用同步后的初始 presentation
let initialPresentation = CanvasToolbarTransitionGeometry.presentation(
    for: initialStage,
    context: context
)
let synchronizedInitialPresentation = synchronizedInitialToolbarPresentation(
    initialPresentation,
    stage: initialStage,
    direction: direction,
    context: context,
    shouldSynchronizeOffscreenStart: hadActiveToolbarTransition == false
)

toolbarTransitionRuntime = CanvasToolbarTransitionRuntime(
    context: context,
    stage: initialStage,
    currentPresentation: synchronizedInitialPresentation,
    pendingLayoutReconcile: true
)
toolbarHostView.applyTransitionImmediately(synchronizedInitialPresentation)
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：synchronizedInitialToolbarPresentation(_:stage:direction:context:shouldSynchronizeOffscreenStart:)；新增，只处理普通 toEditing entering 起点
private func synchronizedInitialToolbarPresentation(
    _ presentation: CanvasToolbarTransitionPresentation,
    stage: CanvasToolbarTransitionStage,
    direction: CanvasToolbarTransitionDirection,
    context: CanvasToolbarTransitionContext,
    shouldSynchronizeOffscreenStart: Bool
) -> CanvasToolbarTransitionPresentation {
    guard shouldSynchronizeOffscreenStart,
          direction == .toEditing,
          case .entering = stage
    else {
        return presentation
    }

    var synchronizedPresentation = presentation
    synchronizedPresentation.frame = normalizedToolbarFrame(
        context.frames.offscreenFrame,
        fallback: presentation.frame
    )
    return synchronizedPresentation
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
# 命令：git status --short，显示阶段 5 代码改动和本记录文件
M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
?? commit_records/20260722_161245_macos_toolbar_manual_animation_phase5_record.md
```

本次没有提交代码。
