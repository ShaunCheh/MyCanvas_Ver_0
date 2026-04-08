# 20260408_130208_toolbar_transition_phase2_ios_controller_record

## 记录范围

- 记录内容：`Phase 2` 的 iOS 控制器编排落地。
- 涉及业务代码文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 写入本记录前的代码状态依据：
  - `git status --short` 仅显示 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `git diff -- "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift"` 显示本次改动集中在 iOS 控制器，主题是 transition runtime、两段式动画、重基线、steady render guard 和 visible frame 反解
- 本记录文件是随后新增的说明材料，不属于本次业务代码改动本身。
- 本记录不包含：
  - `Phase 0` 的共享过渡 contract / geometry
  - `Phase 1` 的 iOS / macOS Host 结构改造
  - `Phase 3` 的 macOS 控制器对称接入
  - `Phase 4` 的 layout reconcile 收口
  - git commit / push

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff
# 功能说明: 在写入本记录前确认当前工作区只包含 iOS 控制器改动，并据此抽取本次“修改前 / 修改后”的真实基线。
git status --short
git diff -- "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift"
```

## 修改一：为 iOS 控制器新增工具栏过渡运行时状态

### 修改前

- `iOSViewController` 里只有 steady-state 的 `toolbarHostView`。
- 控制器没有 `CanvasToolbarTransitionRuntime`，也没有动画驱动器字段。
- 因此控制器无法在一次模式切换里保存“当前展示态 / 当前阶段 / 是否有待收口 layout”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController 属性区
// 功能说明: 修改前控制器只有 toolbarHostView，没有 toolbar transition runtime / animator。
private let toolbarPlacementSolver = CanvasToolbarPlacementSolver()
private let toolbarHostView = iOSCanvasToolbarHostView()
private let textEditorOverlayView = iOSCanvasTextEditorOverlayView()
private let historyButtonsStackView: iOSCanvasChromeStackView = {
    let stackView = iOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()
```

### 修改后

- 新增 `toolbarTransitionRuntime`，统一承接 `Phase 0` 的共享 runtime。
- 新增 `toolbarTransitionAnimator`，用 `UIViewPropertyAnimator` 驱动两段式动画。
- 新增 `isToolbarTransitionActive`，让 steady render / layout pass 能统一判定自己是否处于动画期。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController 属性区
// 功能说明: 修改后控制器新增 transition runtime 和 animator，为后续两段式模式切换动画提供单一状态源。
private let toolbarPlacementSolver = CanvasToolbarPlacementSolver()
private let toolbarHostView = iOSCanvasToolbarHostView()
private var toolbarTransitionRuntime: CanvasToolbarTransitionRuntime?
private var toolbarTransitionAnimator: UIViewPropertyAnimator?
private var isToolbarTransitionActive: Bool {
    toolbarTransitionRuntime != nil
}
private let textEditorOverlayView = iOSCanvasTextEditorOverlayView()
private let historyButtonsStackView: iOSCanvasChromeStackView = {
    let stackView = iOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()
```

## 修改二：模式按钮入口从“直接切 workspaceMode”改为“控制器编排过渡”

### 修改前

- 模式按钮点击后直接切 `workspaceMode`。
- 随后立刻调用：
  - `dismissContextMenu()`
  - `updateWorkspaceModeButtonAppearance()`
  - `updateInlineEditButtonsAppearance()`
  - `requestCanvasRefresh(...)`
  - `scheduleAutosave(...)`
- 这一条链路只有逻辑切换，没有工具栏视觉过渡编排。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleWorkspaceModeButtonTap()
// 功能说明: 修改前点击模式按钮时，直接切 workspaceMode，没有 toolbar transition runtime，也没有分阶段动画入口。
@objc
private func handleWorkspaceModeButtonTap() {
    workspaceMode = workspaceMode.toggled
    dismissContextMenu()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}
```

### 修改后

- 模式按钮点击只负责选择方向：
  - 编辑中点击：`.toReading`
  - 阅读中点击：`.toEditing`
- 具体编排交给 `beginToolbarModeTransition(to:)`。
- 控制器会先做中断重基线，再准备 context，再生成初始 presentation，最后按 stage 进入对应动画阶段。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleWorkspaceModeButtonTap() / beginToolbarModeTransition(to:)
// 功能说明: 修改后模式切换入口不再直接改工具栏展示，而是交给控制器统一编排 transition runtime、initial stage 和 Host presentation。
@objc
private func handleWorkspaceModeButtonTap() {
    beginToolbarModeTransition(
        to: workspaceMode == .editing ? .toReading : .toEditing
    )
}

private func beginToolbarModeTransition(
    to direction: CanvasToolbarTransitionDirection
) {
    let targetMode = toolbarTargetWorkspaceMode(for: direction)
    if let runtime = toolbarTransitionRuntime,
       toolbarTargetWorkspaceMode(for: runtime.context.direction) == targetMode
    {
        return
    }

    dismissContextMenu()
    cancelAndRebaseToolbarTransitionIfNeeded(targetMode: targetMode)

    guard let context = prepareToolbarTransitionContext(direction: direction) else {
        toolbarTransitionAnimator?.stopAnimation(true)
        toolbarTransitionAnimator = nil
        toolbarTransitionRuntime = nil
        updatePreparedToolbarPlacement()
        return
    }

    let initialStage = initialToolbarTransitionStage(
        for: direction,
        context: context
    )
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
    toolbarHostView.renderTransition(initialPresentation)

    switch initialStage {
    case .collapsing, .expanding:
        runToolbarCollapsePhase()
    case .exiting, .entering:
        runToolbarSlidePhase()
    case .steadyVisible, .hidden:
        finishToolbarModeTransition(applying: context.settledState)
    }
}
```

## 修改三：在控制器内接通 `CanvasToolbarTransitionContext` 与两段式动画链路

### 修改前

- 原文件在 `handleWorkspaceModeButtonTap()` 后直接进入 `handlePasteKeyCommand(_:)`。
- 中间没有任何：
  - `prepareToolbarTransitionContext(direction:)`
  - `runToolbarCollapsePhase()`
  - `runToolbarSlidePhase()`
  - `finishToolbarModeTransition(applying:)`
- 也就是说，控制器层之前根本没有工具栏模式动画链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleWorkspaceModeButtonTap() / handlePasteKeyCommand(_:)
// 功能说明: 修改前 handleWorkspaceModeButtonTap() 与 handlePasteKeyCommand(_:) 之间不存在任何 toolbar transition orchestration 函数。
@objc
private func handleWorkspaceModeButtonTap() {
    workspaceMode = workspaceMode.toggled
    dismissContextMenu()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}

@objc
private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
    handlePasteRequest()
}
```

### 修改后

- `prepareToolbarTransitionContext(direction:)` 在控制器里把逻辑切换和视觉过渡拆开：
  - `.toReading`：先抓 visible state / visible frame，再立即切 `workspaceMode = .reading`，然后用旧快照去做 collapse + exit
  - `.toEditing`：先立即切 `workspaceMode = .editing`，再反解 editing steady state 的 visible frame，然后从 offscreen + collapsed 倒放进入
- `runToolbarCollapsePhase()` 和 `runToolbarSlidePhase()` 实际把两段式动画串起来。
- `finishToolbarModeTransition(applying:)` 负责用 steady-state 收口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: prepareToolbarTransitionContext(direction:)
// 功能说明: 修改后控制器在这里统一准备 toReading / toEditing 两种 context，保证 workspaceMode 立即切换，而工具栏仍按共享 geometry 做视觉过渡。
private func prepareToolbarTransitionContext(
    direction: CanvasToolbarTransitionDirection
) -> CanvasToolbarTransitionContext? {
    let configuration = CanvasToolbarTransitionConfiguration()

    switch direction {
    case .toReading:
        let visibleState = makeToolbarState()
        let visibleFrame = currentToolbarTransitionStartFrame(
            fallbackState: visibleState
        )

        applyWorkspaceModeForToolbarTransition(to: .reading)

        let settledState = makeToolbarState()
        guard visibleState.items.isEmpty == false else {
            return nil
        }

        let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
            from: visibleFrame
        )
        let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
            from: collapsedFrame,
            safeBounds: toolbarLayoutSafeBounds()
        )

        return CanvasToolbarTransitionContext(
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

    case .toEditing:
        applyWorkspaceModeForToolbarTransition(to: .editing)

        let visibleState = makeToolbarState()
        guard visibleState.items.isEmpty == false else {
            return nil
        }

        let visibleFrame = resolvedSteadyToolbarFrame(for: visibleState)
        let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
            from: visibleFrame
        )
        let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
            from: collapsedFrame,
            safeBounds: toolbarLayoutSafeBounds()
        )

        return CanvasToolbarTransitionContext(
            direction: direction,
            visibleSnapshot: CanvasToolbarTransitionSnapshot(
                state: visibleState,
                frame: visibleFrame
            ),
            settledState: visibleState,
            frames: CanvasToolbarTransitionFrames(
                visibleFrame: visibleFrame,
                collapsedFrame: collapsedFrame,
                offscreenFrame: offscreenFrame
            ),
            configuration: configuration
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: runToolbarCollapsePhase() / runToolbarSlidePhase() / finishToolbarModeTransition(applying:)
// 功能说明: 修改后 iOS 控制器正式把共享 stage 串成两段式动画：toReading 先收拢再离屏，toEditing 先回屏再展开。
private func runToolbarCollapsePhase() {
    guard let runtime = toolbarTransitionRuntime else {
        return
    }

    let targetStage: CanvasToolbarTransitionStage
    let completion: () -> Void

    switch runtime.context.direction {
    case .toReading:
        targetStage = .collapsing(progress: 1)
        completion = { [weak self] in
            self?.runToolbarSlidePhase()
        }
    case .toEditing:
        targetStage = .expanding(progress: 1)
        completion = { [weak self] in
            guard let self else {
                return
            }
            self.finishToolbarModeTransition(
                applying: runtime.context.settledState
            )
        }
    }

    animateToolbarTransition(
        to: targetStage,
        duration: remainingToolbarTransitionDuration(
            fullDuration: runtime.context.configuration.collapseDuration,
            currentStage: runtime.stage
        ),
        completion: completion
    )
}

private func runToolbarSlidePhase() {
    guard let runtime = toolbarTransitionRuntime else {
        return
    }

    let targetStage: CanvasToolbarTransitionStage
    let completion: () -> Void

    switch runtime.context.direction {
    case .toReading:
        targetStage = .exiting(progress: 1)
        completion = { [weak self] in
            guard let self else {
                return
            }
            self.finishToolbarModeTransition(
                applying: runtime.context.settledState
            )
        }
    case .toEditing:
        targetStage = .entering(progress: 1)
        completion = { [weak self] in
            self?.runToolbarCollapsePhase()
        }
    }

    animateToolbarTransition(
        to: targetStage,
        duration: remainingToolbarTransitionDuration(
            fullDuration: runtime.context.configuration.slideDuration,
            currentStage: runtime.stage
        ),
        completion: completion
    )
}

private func finishToolbarModeTransition(
    applying settledState: CanvasToolbarState
) {
    let pendingLayoutReconcile = toolbarTransitionRuntime?.pendingLayoutReconcile
        ?? true
    toolbarTransitionAnimator = nil
    toolbarTransitionRuntime = nil
    toolbarHostView.completeTransition(applying: settledState)
    if pendingLayoutReconcile {
        updatePreparedToolbarPlacement()
    }
}
```

## 修改四：补上动画中断时的重基线，而不是退回旧 steady frame

### 修改前

- 原来没有任何“再次点击模式按钮时重基线”的控制器逻辑。
- 因为旧实现根本没有 transition runtime，所以也无从读取：
  - 当前 presentation
  - 当前动画帧
  - 当前阶段 progress

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleWorkspaceModeButtonTap()
// 功能说明: 修改前再次点击只会再执行一次直接切 mode，不会基于当前动画中的工具栏位置重建新动画起点。
@objc
private func handleWorkspaceModeButtonTap() {
    workspaceMode = workspaceMode.toggled
    dismissContextMenu()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}
```

### 修改后

- 新增 `cancelAndRebaseToolbarTransitionIfNeeded(targetMode:)`。
- 如果上一段动画还在跑，控制器会先读取当前 presentation / 当前 animated frame，再把新动画起点重建在当前位置，而不是回退到上一次 steady frame。
- `currentToolbarAnimatedFrame(fallback:)` 使用 `toolbarHostView.layer.presentation()?.frame` 优先读取当前视觉帧。
- `initialToolbarTransitionStage(...)` 和 `inferredCurrentToolbarTransitionPresentation(...)` 会从当前几何位置反推 progress。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: cancelAndRebaseToolbarTransitionIfNeeded(targetMode:) / currentToolbarAnimatedFrame(fallback:)
// 功能说明: 修改后如果用户在动画未结束时再次切模式，会先把旧动画停在当前视觉位置，再基于当前 presentation 继续编排新动画。
private func cancelAndRebaseToolbarTransitionIfNeeded(
    targetMode: CanvasWorkspaceMode
) {
    guard var runtime = toolbarTransitionRuntime else {
        return
    }

    guard
        toolbarTargetWorkspaceMode(for: runtime.context.direction) != targetMode
    else {
        return
    }

    runtime.currentPresentation = inferredCurrentToolbarTransitionPresentation(
        from: runtime
    )
    runtime.pendingLayoutReconcile = true
    toolbarTransitionRuntime = runtime

    toolbarTransitionAnimator?.stopAnimation(true)
    toolbarTransitionAnimator = nil
    toolbarHostView.renderTransition(runtime.currentPresentation)
}

private func currentToolbarAnimatedFrame(fallback: CGRect) -> CGRect {
    if let animatedFrame = toolbarHostView.layer.presentation()?.frame,
       let sanitizedAnimatedFrame = CanvasChromeLayoutGeometry.sanitizedRect(
           animatedFrame
       )
    {
        return sanitizedAnimatedFrame
    }

    if let currentFrame = CanvasChromeLayoutGeometry.sanitizedRect(
        toolbarHostView.frame
    ) {
        return currentFrame
    }

    return normalizedToolbarFrame(fallback, fallback: fallback)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: initialToolbarTransitionStage(for:context:) / inferredCurrentToolbarTransitionPresentation(from:)
// 功能说明: 修改后控制器会根据当前 frame 反推 collapsing / exiting / entering / expanding 的进度，避免中断后重新从 0 开始。
private func initialToolbarTransitionStage(
    for direction: CanvasToolbarTransitionDirection,
    context: CanvasToolbarTransitionContext
) -> CanvasToolbarTransitionStage {
    guard let currentPresentation = toolbarTransitionRuntime?.currentPresentation else {
        switch direction {
        case .toReading:
            return .collapsing(progress: 0)
        case .toEditing:
            return .entering(progress: 0)
        }
    }

    let currentFrame = normalizedToolbarFrame(
        currentPresentation.frame,
        fallback: context.frames.visibleFrame
    )
    let collapsedFrame = normalizedToolbarFrame(
        context.frames.collapsedFrame,
        fallback: currentFrame
    )

    switch direction {
    case .toReading:
        let isCollapsed = currentFrame.height <= (collapsedFrame.height + 0.5)
        if isCollapsed {
            return .exiting(
                progress: toolbarLinearProgress(
                    from: collapsedFrame.minX,
                    to: context.frames.offscreenFrame.minX,
                    current: currentFrame.minX
                )
            )
        }
        return .collapsing(progress: 0)

    case .toEditing:
        if currentFrame.height > (collapsedFrame.height + 0.5) {
            let expandingProgress = toolbarLinearProgress(
                from: collapsedFrame.height,
                to: context.frames.visibleFrame.height,
                current: currentFrame.height
            )
            if expandingProgress >= 0.999 {
                return .steadyVisible
            }
            return .expanding(progress: expandingProgress)
        }

        let enteringProgress = toolbarLinearProgress(
            from: context.frames.offscreenFrame.minX,
            to: collapsedFrame.minX,
            current: currentFrame.minX
        )
        if enteringProgress >= 0.999 {
            return .expanding(progress: 0)
        }
        return .entering(progress: enteringProgress)
    }
}
```

## 修改五：给 steady render 与 layout pass 增加 transition guard

### 修改前

- `updatePreparedToolbarPlacement()` 会直接触发 `renderToolbar()` 和 overlay layout。
- `applyToolbarFrame(_:)` 会直接回写 `toolbarHostView.frame`。
- `renderToolbar()` 会直接把 steady-state `CanvasToolbarState` 重新 render 给 Host。
- 这三条路径都会在动画期抢写当前的过渡 presentation。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updatePreparedToolbarPlacement() / applyToolbarFrame(_:) / renderToolbar()
// 功能说明: 修改前这些 steady-state 路径没有 transition guard，动画期间如果被触发，会直接覆盖当前工具栏轨迹。
private func updatePreparedToolbarPlacement() {
    renderToolbar()
    if view.bounds.isEmpty == false {
        view.layoutIfNeeded()
        updateChromeOverlayLayout()
    }
}

private func applyToolbarFrame(_ toolbarFrame: CGRect) {
    if toolbarHostView.frame != toolbarFrame {
        toolbarHostView.frame = toolbarFrame
    }
}

private func renderToolbar() {
    guard isViewLoaded else {
        return
    }

    toolbarHostView.render(makeToolbarState())
}
```

### 修改后

- 三条 steady-state 路径现在都会先检查 `isToolbarTransitionActive`。
- 如果动画正在进行，不再覆盖当前展示，而是只把 `pendingLayoutReconcile` 标记为 `true`，等 completion 后统一收口。
- 这一改动是本次 `Phase 2` 能跑起来的关键保护层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updatePreparedToolbarPlacement() / applyToolbarFrame(_:) / renderToolbar()
// 功能说明: 修改后 steady-state 的 render 与布局回写在动画期只记录 pending reconcile，不再直接覆盖 transition presentation。
private func updatePreparedToolbarPlacement() {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    renderToolbar()
    if view.bounds.isEmpty == false {
        view.layoutIfNeeded()
        updateChromeOverlayLayout()
    }
}

private func applyToolbarFrame(_ toolbarFrame: CGRect) {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    if toolbarHostView.frame != toolbarFrame {
        toolbarHostView.frame = toolbarFrame
    }
}

private func renderToolbar() {
    guard isViewLoaded else {
        return
    }

    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    toolbarHostView.render(makeToolbarState())
}
```

## 修改六：为 `阅读 -> 编辑` 反解 steady visible frame，补 controller 侧几何入口

### 修改前

- 控制器侧只有 `measuredToolbarHostSize()`，它读取的是当前 Host 的测量结果。
- 但在 `阅读 -> 编辑` 时，当前 Host 可能还处于隐藏或离屏状态；旧代码没有 controller 侧入口去反解“编辑态完整工具栏”的 steady frame。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: measuredToolbarHostSize()
// 功能说明: 修改前控制器只会读取当前 Host 的测量尺寸，没有针对目标 steady-state 的独立 frame 反解能力。
private func measuredToolbarHostSize() -> CGSize {
    CanvasChromeLayoutGeometry.sanitizedSize(
        toolbarHostView.measuredContentSize()
    )
}
```

### 修改后

- 新增 `resolvedSteadyToolbarFrame(for:)`，在控制器里直接跑一遍 `CanvasToolbarPlacementPass.resolve(...)`，反解目标 steady-state 的 visible frame。
- 新增 `measuredToolbarHostSize(for:)`，按 `CanvasToolbarState.items` 和 `preferredAxis` 在控制器侧估出目标工具栏尺寸，不依赖当前 Host 正处于何种展示态。
- 这让 `阅读 -> 编辑` 可以从 `offscreenFrame -> collapsedFrame -> visibleFrame` 倒放进入。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: resolvedSteadyToolbarFrame(for:) / measuredToolbarHostSize(for:)
// 功能说明: 修改后阅读态切回编辑态时，控制器可以先反解编辑态完整工具栏的目标 frame，再据此构造 entering / expanding 的几何链路。
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

    return normalizedToolbarFrame(
        placementResult.toolbarFrame,
        fallback: placementResult.toolbarFrame
    )
}

private func measuredToolbarHostSize(
    for state: CanvasToolbarState
) -> CGSize {
    guard state.items.isEmpty == false else {
        return .zero
    }

    let itemCount = CGFloat(state.items.count)
    let stackedLength = (itemCount * CanvasToolbarChromeMetrics.buttonEdge)
        + (max(itemCount - 1, 0) * CanvasToolbarChromeMetrics.spacing)
    let measuredStackSize: CGSize

    switch state.preferredAxis {
    case .horizontal:
        measuredStackSize = CGSize(
            width: stackedLength,
            height: CanvasToolbarChromeMetrics.buttonEdge
        )
    case .vertical:
        measuredStackSize = CGSize(
            width: CanvasToolbarChromeMetrics.buttonEdge,
            height: stackedLength
        )
    }

    return CanvasChromeLayoutGeometry.sanitizedSize(
        CanvasToolbarMeasurement.measuredContentSize(
            forMeasuredStackSize: measuredStackSize
        )
    )
}
```

## 验证情况

- `ReadLints` 检查 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`：无 linter 报错。
- 已执行 iOS Simulator 构建校验，结果通过。

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild
# 功能说明: 对 Phase 2 的 iOS 控制器改动执行工程级构建校验。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-toolbar-phase2-ios" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

- 本次没有附带模拟器中的肉眼动画验收记录。

## 当前结论

- 本次改动如实对应 `Phase 2`：
  - iOS 控制器已经接入 `CanvasToolbarTransitionRuntime`
  - 模式切换入口已经改成两段式动画编排
  - 动画中断时已经支持按当前视觉帧重基线
  - steady render / layout pass 已经加上 transition guard
  - `阅读 -> 编辑` 已经具备目标 steady frame 的控制器侧反解能力
- 当前业务代码改动仍只落在 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`。
