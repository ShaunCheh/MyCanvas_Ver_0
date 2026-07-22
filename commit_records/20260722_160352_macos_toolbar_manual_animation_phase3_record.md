# 20260722_160352_macos_toolbar_manual_animation_phase3_record

## 背景

本次记录对应 `macOS 工具条手写滑入滑出动画计划` 的阶段 3：只插值允许变化的轴。

阶段 2 已经把 macOS toolbar transition 切到主线程手写逐帧 driver。本次阶段 3 在该 driver 内区分 slide-only 阶段与保留的 collapse / expand 阶段：`.entering` / `.exiting` 只允许 `x` 参与动画，`y / width / height` 在动画开始前直接固定到目标 frame。

## 修改 1：把目标 stage 传入手写 driver

修改前，`animateToolbarTransition(to:duration:completion:)` 调用手写 driver 时只传入 source / target presentation。driver 不知道当前目标 stage，因此无法判断这次动画是 slide-only 还是未来保留的 collapse / expand。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：animateToolbarTransition(to:duration:completion:)；修改前，driver 不接收 targetStage
runManualToolbarTransition(
    from: sourcePresentation,
    to: targetPresentation,
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

修改后，调用处把 `targetStage` 传入 driver，让 driver 可以针对 `.entering` / `.exiting` 启用水平滑动锁定。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：animateToolbarTransition(to:duration:completion:)；修改后，向 driver 传入 targetStage
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

## 修改 2：slide 阶段开始前固定 y / width / height

修改前，`runManualToolbarTransition(from:to:duration:completion:)` 直接从 `sourcePresentation` 插值到 `targetPresentation`。如果 source frame 曾经处于旧的 presentation layer 或 fallback frame，`y / width / height` 也会参与插值。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:duration:completion:)；修改前，直接从 sourcePresentation 插值
let elapsed = CACurrentMediaTime() - startTime
let linearProgress = sanitizedDuration <= 0
    ? 1
    : min(max(CGFloat(elapsed / sanitizedDuration), 0), 1)
let easedProgress = self.easeInOutToolbarProgress(linearProgress)
let presentation = self.interpolatedToolbarPresentation(
    from: sourcePresentation,
    to: targetPresentation,
    progress: easedProgress
)

self.toolbarHostView.renderTransition(
    presentation,
    animated: false
)
```

修改后，driver 先根据 `targetStage` 判断是否是 `.entering` / `.exiting`。如果是 slide-only，先生成 `initialPresentation`，立即把 toolbar 的 `y / width / height` 固定到目标 frame，再用这个固定后的 presentation 作为动画起点。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:targetStage:duration:completion:)；修改后，slide-only 先固定目标尺寸和 y
let locksFrameToHorizontalSlide = locksToolbarFrameToHorizontalSlide(
    for: targetStage
)
let initialPresentation = initialManualToolbarPresentation(
    from: sourcePresentation,
    to: targetPresentation,
    locksFrameToHorizontalSlide: locksFrameToHorizontalSlide
)

toolbarHostView.renderTransition(
    initialPresentation,
    animated: false
)
```

## 修改 3：新增 slide-only stage 判断

新增 `locksToolbarFrameToHorizontalSlide(for:)`。当前只对 `.entering` 和 `.exiting` 返回 `true`，也就是编辑态 / 阅读态切换的滑入滑出阶段。`.collapsing` / `.expanding` 仍返回 `false`，保留完整 rect 插值路径，避免删除或破坏未来恢复收缩 / 展开的能力。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：locksToolbarFrameToHorizontalSlide(for:)；新增，区分 slide-only 与保留的完整 rect 动画
private func locksToolbarFrameToHorizontalSlide(
    for targetStage: CanvasToolbarTransitionStage
) -> Bool {
    switch targetStage {
    case .entering, .exiting:
        return true
    case .steadyVisible, .hidden, .collapsing, .expanding:
        return false
    }
}
```

## 修改 4：新增初始 presentation 固定逻辑

新增 `initialManualToolbarPresentation(from:to:locksFrameToHorizontalSlide:)`。当启用水平锁定时，只保留 source 的 `x` 作为动画起点；`y / width / height` 直接使用目标值。这样动画开始前就切断旧 frame 的纵向和尺寸残留。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：initialManualToolbarPresentation(from:to:locksFrameToHorizontalSlide:)；新增，slide-only 开始前固定目标 y/size
private func initialManualToolbarPresentation(
    from sourcePresentation: CanvasToolbarTransitionPresentation,
    to targetPresentation: CanvasToolbarTransitionPresentation,
    locksFrameToHorizontalSlide: Bool
) -> CanvasToolbarTransitionPresentation {
    guard locksFrameToHorizontalSlide else {
        return sourcePresentation
    }

    var presentation = sourcePresentation
    presentation.frame = CGRect(
        x: sourcePresentation.frame.minX,
        y: targetPresentation.frame.minY,
        width: targetPresentation.frame.width,
        height: targetPresentation.frame.height
    ).standardized
    return presentation
}
```

## 修改 5：插值函数支持水平锁定

修改前，`interpolatedToolbarPresentation` 只接收 `progress`，并把 source / target frame 交给完整 frame 插值。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：interpolatedToolbarPresentation(from:to:progress:)；修改前，不区分 slide-only
private func interpolatedToolbarPresentation(
    from sourcePresentation: CanvasToolbarTransitionPresentation,
    to targetPresentation: CanvasToolbarTransitionPresentation,
    progress: CGFloat
) -> CanvasToolbarTransitionPresentation {
    let t = min(max(progress, 0), 1)
    return CanvasToolbarTransitionPresentation(
        frame: interpolatedToolbarFrame(
            from: sourcePresentation.frame,
            to: targetPresentation.frame,
            progress: t
        ),
        itemStates: targetPresentation.itemStates,
        showsBackground: targetPresentation.showsBackground,
        contentAlpha: interpolatedToolbarValue(
            from: sourcePresentation.contentAlpha,
            to: targetPresentation.contentAlpha,
            progress: t
        ),
        contentScale: interpolatedToolbarValue(
            from: sourcePresentation.contentScale,
            to: targetPresentation.contentScale,
            progress: t
        ),
        keepsHostVisible: sourcePresentation.keepsHostVisible ||
            targetPresentation.keepsHostVisible,
        isInteractive: false
    )
}
```

修改后，`interpolatedToolbarPresentation` 继续插值 alpha / scale，但 frame 插值会把 `locksFrameToHorizontalSlide` 传下去，由 frame helper 决定是否只插值 `x`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：interpolatedToolbarPresentation(from:to:progress:locksFrameToHorizontalSlide:)；修改后，frame 插值支持水平锁定
private func interpolatedToolbarPresentation(
    from sourcePresentation: CanvasToolbarTransitionPresentation,
    to targetPresentation: CanvasToolbarTransitionPresentation,
    progress: CGFloat,
    locksFrameToHorizontalSlide: Bool
) -> CanvasToolbarTransitionPresentation {
    let t = min(max(progress, 0), 1)
    return CanvasToolbarTransitionPresentation(
        frame: interpolatedToolbarFrame(
            from: sourcePresentation.frame,
            to: targetPresentation.frame,
            progress: t,
            locksFrameToHorizontalSlide: locksFrameToHorizontalSlide
        ),
        itemStates: targetPresentation.itemStates,
        showsBackground: targetPresentation.showsBackground,
        contentAlpha: interpolatedToolbarValue(
            from: sourcePresentation.contentAlpha,
            to: targetPresentation.contentAlpha,
            progress: t
        ),
        contentScale: interpolatedToolbarValue(
            from: sourcePresentation.contentScale,
            to: targetPresentation.contentScale,
            progress: t
        ),
        keepsHostVisible: sourcePresentation.keepsHostVisible ||
            targetPresentation.keepsHostVisible,
        isInteractive: false
    )
}
```

## 修改 6：frame 插值只允许 x 变化

修改前，`interpolatedToolbarFrame(from:to:progress:)` 对 `x / y / width / height` 都做插值。这正是会产生斜向滑动或动画结束后尺寸轻微变化的风险来源。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：interpolatedToolbarFrame(from:to:progress:)；修改前，完整 rect 插值
private func interpolatedToolbarFrame(
    from sourceFrame: CGRect,
    to targetFrame: CGRect,
    progress: CGFloat
) -> CGRect {
    CGRect(
        x: interpolatedToolbarValue(
            from: sourceFrame.minX,
            to: targetFrame.minX,
            progress: progress
        ),
        y: interpolatedToolbarValue(
            from: sourceFrame.minY,
            to: targetFrame.minY,
            progress: progress
        ),
        width: interpolatedToolbarValue(
            from: sourceFrame.width,
            to: targetFrame.width,
            progress: progress
        ),
        height: interpolatedToolbarValue(
            from: sourceFrame.height,
            to: targetFrame.height,
            progress: progress
        )
    ).standardized
}
```

修改后，如果 `locksFrameToHorizontalSlide == true`，只插值 `x`，并强制 `y / width / height` 使用 target frame。否则仍走完整 rect 插值，服务于保留的 collapse / expand 路径。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：interpolatedToolbarFrame(from:to:progress:locksFrameToHorizontalSlide:)；修改后，slide-only 只插值 x
private func interpolatedToolbarFrame(
    from sourceFrame: CGRect,
    to targetFrame: CGRect,
    progress: CGFloat,
    locksFrameToHorizontalSlide: Bool
) -> CGRect {
    if locksFrameToHorizontalSlide {
        return CGRect(
            x: interpolatedToolbarValue(
                from: sourceFrame.minX,
                to: targetFrame.minX,
                progress: progress
            ),
            y: targetFrame.minY,
            width: targetFrame.width,
            height: targetFrame.height
        ).standardized
    }

    return CGRect(
        x: interpolatedToolbarValue(
            from: sourceFrame.minX,
            to: targetFrame.minX,
            progress: progress
        ),
        y: interpolatedToolbarValue(
            from: sourceFrame.minY,
            to: targetFrame.minY,
            progress: progress
        ),
        width: interpolatedToolbarValue(
            from: sourceFrame.width,
            to: targetFrame.width,
            progress: progress
        ),
        height: interpolatedToolbarValue(
            from: sourceFrame.height,
            to: targetFrame.height,
            progress: progress
        )
    ).standardized
}
```

## 验证

已执行 lints 检查：

```shell
# terminal
# 验证命令：检查 macOSViewController.swift 的 IDE lints
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

当前阶段 3 只修改了：

```shell
# terminal
# 命令：git status --short，显示阶段 3 代码改动和本记录文件
# 当前 changes：阶段 3 代码改动，以及本记录文件
M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
?? commit_records/20260722_160352_macos_toolbar_manual_animation_phase3_record.md
```

本次没有修改计划文件，也没有提交代码。
