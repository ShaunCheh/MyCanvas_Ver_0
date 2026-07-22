# 20260722_160044_macos_toolbar_manual_animation_phase2_record

## 背景

本次记录对应 `macOS 工具条手写滑入滑出动画计划` 的阶段 2：实现主线程逐帧 driver。

目标是将 macOS 工具条编辑态 / 阅读态切换的动画执行从 AppKit 的 `NSAnimationContext` 分支切到手写逐帧驱动。阶段 2 只负责建立 driver 和接入入口；`slide-only` 的只插值 `x`、固定 `y/width/height` 属于后续阶段。

## 修改 1：为 controller 增加手写动画状态

修改前，controller 只保存 toolbar transition runtime 和 hidden frame，没有逐帧动画的 token / timer 状态。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// macOSViewController toolbar transition state：修改前，没有手写动画 timer 状态
private let toolbarPlacementSolver = CanvasToolbarPlacementSolver()
private let toolbarHostView = macOSCanvasToolbarHostView()
private var toolbarTransitionRuntime: CanvasToolbarTransitionRuntime?
private var preservedHiddenToolbarFrame: CGRect?
```

修改后，新增 `toolbarManualTransitionTimer` 和 `toolbarManualTransitionID`。`Timer` 负责主线程逐帧推进，`UUID` 作为动画 token，用来取消旧动画或忽略过期回调。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// macOSViewController toolbar transition state：修改后，加入手写动画 timer 与 token
private let toolbarPlacementSolver = CanvasToolbarPlacementSolver()
private let toolbarHostView = macOSCanvasToolbarHostView()
private var toolbarTransitionRuntime: CanvasToolbarTransitionRuntime?
private var toolbarManualTransitionTimer: Timer?
private var toolbarManualTransitionID = UUID()
private var preservedHiddenToolbarFrame: CGRect?
```

## 修改 2：替换 AppKit animation 入口

修改前，`animateToolbarTransition(to:duration:completion:)` 在 `duration > 0` 时使用 `NSAnimationContext.runAnimationGroup`，并通过 `toolbarHostView.renderTransition(..., animated: true)` 交给 AppKit animator 执行动画。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：animateToolbarTransition(to:duration:completion:)
// 修改前：动画由 NSAnimationContext / AppKit animator 驱动
NSAnimationContext.runAnimationGroup { context in
    context.duration = duration
    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    self.toolbarHostView.renderTransition(
        targetPresentation,
        animated: true
    )
} completionHandler: { [weak self] in
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

修改后，先保存 `sourcePresentation`，再调用 `runManualToolbarTransition(from:to:duration:completion:)`。这样 controller 仍然沿用原来的 transition context / stage / presentation 计算，但 frame 应用不再走 AppKit 的动画框架。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：animateToolbarTransition(to:duration:completion:)
// 修改后：动画改由手写逐帧 driver 驱动
let expectedDirection = runtime.context.direction
let sourcePresentation = runtime.currentPresentation
runtime.stage = targetStage
runtime.currentPresentation = targetPresentation
toolbarTransitionRuntime = runtime

if duration <= 0 {
    cancelManualToolbarTransition()
    toolbarHostView.renderTransition(
        targetPresentation,
        animated: false
    )
    completion()
    return
}

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

## 修改 3：新增主线程逐帧 driver

新增 `runManualToolbarTransition(from:to:duration:completion:)`。它会：

- 先取消已有手写动画，避免多个 timer 同时写 toolbar frame。
- 使用 `Timer(timeInterval: 1.0 / 60.0, repeats: true)` 在主线程 run loop 的 `.common` mode 中逐帧执行。
- 用 `CACurrentMediaTime()` 计算 elapsed，并 clamp 到 `0...1`。
- 通过 `easeInOutToolbarProgress(_:)` 复刻原来的 easeInOut 动画感觉。
- 每帧调用 `toolbarHostView.renderTransition(..., animated: false)`，不使用 `animator()`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：runManualToolbarTransition(from:to:duration:completion:)
// 新增：主线程 60fps timer driver，每帧直接应用非动画 presentation
private func runManualToolbarTransition(
    from sourcePresentation: CanvasToolbarTransitionPresentation,
    to targetPresentation: CanvasToolbarTransitionPresentation,
    duration: TimeInterval,
    completion: @escaping () -> Void
) {
    cancelManualToolbarTransition()

    let transitionID = UUID()
    toolbarManualTransitionID = transitionID
    let startTime = CACurrentMediaTime()
    let sanitizedDuration = max(duration, 0)

    let timer = Timer(
        timeInterval: 1.0 / 60.0,
        repeats: true
    ) { [weak self] timer in
        guard let self else {
            timer.invalidate()
            return
        }

        guard self.toolbarManualTransitionID == transitionID else {
            timer.invalidate()
            return
        }

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

        guard linearProgress >= 1 else {
            return
        }

        timer.invalidate()
        if self.toolbarManualTransitionTimer === timer {
            self.toolbarManualTransitionTimer = nil
        }
        self.toolbarHostView.renderTransition(
            targetPresentation,
            animated: false
        )
        completion()
    }

    toolbarManualTransitionTimer = timer
    RunLoop.main.add(timer, forMode: .common)
    timer.fire()
}
```

## 修改 4：新增取消与插值 helper

新增 `cancelManualToolbarTransition()`，用于使当前 token 失效并停止 timer。它会在 `duration <= 0`、transition rebase、transition finish 等路径调用，避免旧动画残留。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：cancelManualToolbarTransition()
// 新增：取消旧 timer，并通过刷新 UUID 让旧回调自然失效
private func cancelManualToolbarTransition() {
    toolbarManualTransitionID = UUID()
    toolbarManualTransitionTimer?.invalidate()
    toolbarManualTransitionTimer = nil
}
```

新增 presentation / frame / value 插值函数。阶段 2 目前是完整 frame 插值，也就是 `x/y/width/height` 都按 progress 插值；后续阶段 3 会把 slide-only 场景改成只插值 `x`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：interpolatedToolbarPresentation(from:to:progress:)
// 新增：根据 eased progress 生成每一帧的 toolbar presentation
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

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：easeInOutToolbarProgress(_:)
// 新增：使用余弦 easeInOut 曲线，保持接近原系统动画的速度感
private func easeInOutToolbarProgress(_ progress: CGFloat) -> CGFloat {
    let t = min(max(progress, 0), 1)
    return 0.5 - (cos(t * .pi) / 2)
}
```

## 修改 5：在生命周期关键路径清理 timer

在 transition 完成路径加入 `cancelManualToolbarTransition()`，确保 runtime 清理前没有手写动画继续写 toolbar frame。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：finishToolbarModeTransition(applying:)
// 修改后：完成 transition 时同步清理手写动画 timer
cancelManualToolbarTransition()
toolbarTransitionRuntime = nil
toolbarHostView.completeTransition(applying: settledState)
```

在 transition rebase 路径加入 `cancelManualToolbarTransition()`，避免反向切换或中断时旧 timer 继续写旧 frame。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：rebaseToolbarTransitionRuntime()
// 修改后：rebase 当前 presentation 前后，先取消旧手写动画
runtime.currentPresentation = inferredCurrentToolbarTransitionPresentation(
    from: runtime
)
runtime.pendingLayoutReconcile = true
toolbarTransitionRuntime = runtime
cancelManualToolbarTransition()
toolbarHostView.renderTransition(
    runtime.currentPresentation,
    animated: false
)
```

## 修改 6：更新计划文件状态

本次通过 todo 更新，将阶段 1 对应的 `manual-driver-entry` 标记为已完成。当前代码实际已经把 AppKit 动画入口切到手写 driver；阶段 2 的逐帧 driver 也已经实现。

```markdown
<!-- .cursor/plans/macos-toolbar-manual-animation_6bd0d858.plan.md -->
<!-- todos：manual-driver-entry 状态从 pending 更新为 completed -->
todos:
  - id: manual-driver-entry
    content: 替换 macOS toolbar transition 的 NSAnimationContext 入口为手写 driver
    status: completed
```

## 验证

已执行：

```shell
# terminal
# 验证命令：检查 macOSViewController.swift 的 IDE lints
ReadLints(paths: [
    "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
])
```

结果：无 linter 错误。

已执行：

```shell
# terminal
# 验证命令：macOS arm64 build
xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64'
```

结果：build 通过。

## 仍未完成的内容

阶段 2 只实现主线程逐帧 driver。以下内容仍属于后续阶段：

- 阶段 3：slide-only 场景只插值 `x`，固定 `y/width/height`。
- 阶段 4：为 macOS toolbar host 提供更明确的非动画 frame 应用能力。
- 阶段 5：继续修正 hidden toolbar frame 回落问题。
- 阶段 6：动画结束态与 steady layout 对齐。
