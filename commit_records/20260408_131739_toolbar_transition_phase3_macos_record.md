# 20260408_131739_toolbar_transition_phase3_macos_record

## 记录范围

- 记录内容：`Phase 3` 的 macOS 对称落地。
- 涉及业务代码文件：
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- 写入本记录前的代码状态依据：
  - `git status --short` 仅显示两份已修改文件：
    - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
    - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `git diff -- "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" "MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift"` 显示本次改动集中在 macOS 控制器的 transition 编排，以及 macOS Host 内部对 AppKit 动画的承接。
- 本记录文件是随后新增的说明材料，不属于本次业务代码改动本身。
- 本记录不包含：
  - `Phase 0` 的共享过渡 contract / geometry
  - `Phase 1` 的 Host 结构改造
  - `Phase 2` 的 iOS 控制器接入
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
# 功能说明: 在写入本记录前确认当前工作区只包含 Phase 3 的 macOS 改动，并据此抽取本次“修改前 / 修改后”的真实基线。
git status --short
git diff -- "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift"
```

## 修改一：在 macOS 控制器引入共享工具栏过渡运行时

### 修改前

- `macOSViewController` 只有 steady-state 的 `toolbarHostView`。
- 控制器没有 `CanvasToolbarTransitionRuntime`，也没有统一的“当前是否处于工具栏过渡期”判定。
- 因此 macOS 侧还不能像 iOS 一样把模式切换拆成“逻辑立即切换 + 工具栏视觉过渡”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController 属性区
// 功能说明: 修改前 macOS 控制器只有 steady-state 的 toolbarHostView，没有共享过渡 runtime。
private let toolbarPlacementSolver = CanvasToolbarPlacementSolver()
private let toolbarHostView = macOSCanvasToolbarHostView()
private let textEditorOverlayView = macOSCanvasTextEditorOverlayView()
private let miniMapMountView: macOSCanvasChromeOverlayView = {
    let view = macOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = true
    view.isHidden = true
    return view
}()
```

### 修改后

- 新增 `toolbarTransitionRuntime`，直接复用 `Phase 0` 的共享 runtime。
- 新增 `isToolbarTransitionActive`，让 steady render / layout pass 可以统一跳过动画中的工具栏。
- 同时引入 `QuartzCore`，为后面的 `NSAnimationContext + CAMediaTimingFunction` 做准备。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: import 区 / macOSViewController 属性区
// 功能说明: 修改后 macOS 控制器正式持有共享 transition runtime，并为 AppKit 侧动画时序接入 QuartzCore。
import Foundation
import AppKit
import QuartzCore
import UniformTypeIdentifiers

private let toolbarPlacementSolver = CanvasToolbarPlacementSolver()
private let toolbarHostView = macOSCanvasToolbarHostView()
private var toolbarTransitionRuntime: CanvasToolbarTransitionRuntime?
private var isToolbarTransitionActive: Bool {
    toolbarTransitionRuntime != nil
}
private let textEditorOverlayView = macOSCanvasTextEditorOverlayView()
private let miniMapMountView: macOSCanvasChromeOverlayView = {
    let view = macOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = true
    view.isHidden = true
    return view
}()
```

## 修改二：模式按钮入口从“直接切 workspaceMode”改为“beginToolbarModeTransition”

### 修改前

- macOS 模式按钮点击后直接切 `workspaceMode`。
- 然后立刻：
  - `dismissContextMenu()`
  - `updateWorkspaceModeButtonAppearance()`
  - `updateInlineEditButtonsAppearance()`
  - `refreshCanvas(reason:)`
  - `scheduleAutosave(reason:)`
- 这一条链路只做逻辑切换，没有工具栏动画阶段编排。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleWorkspaceModeButtonClick()
// 功能说明: 修改前点击模式按钮时，macOS 侧直接切 workspaceMode，不存在工具栏过渡编排入口。
@objc
private func handleWorkspaceModeButtonClick() {
    workspaceMode = workspaceMode.toggled
    dismissContextMenu()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    refreshCanvas(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}
```

### 修改后

- 模式按钮点击只负责计算方向：
  - 编辑中点击：`.toReading`
  - 阅读中点击：`.toEditing`
- 控制器统一交给 `beginToolbarModeTransition(to:)` 做：
  - 中断重基线
  - context 构建
  - initial stage 推导
  - initial presentation 下发
  - 两段式阶段选择

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleWorkspaceModeButtonClick() / beginToolbarModeTransition(to:)
// 功能说明: 修改后 macOS 模式按钮入口与 iOS 同形，切换请求先进入共享 transition runtime，再按 stage 驱动 Host。
@objc
private func handleWorkspaceModeButtonClick() {
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

## 修改三：在 macOS 控制器接通共享 context、两段式动画与 completion 收口

### 修改前

- 原文件在 `handleWorkspaceModeButtonClick()` 之后直接进入 `canTransferContent(from:)`。
- 中间没有任何：
  - `prepareToolbarTransitionContext(direction:)`
  - `runToolbarCollapsePhase()`
  - `runToolbarSlidePhase()`
  - `finishToolbarModeTransition(applying:)`
  - `animateToolbarTransition(to:duration:completion:)`
- 也就是说，macOS 侧在这次修改前并不存在工具栏模式过渡链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleWorkspaceModeButtonClick() / canTransferContent(from:)
// 功能说明: 修改前 handleWorkspaceModeButtonClick() 和 canTransferContent(from:) 之间没有任何 toolbar transition orchestration 代码。
@objc
private func handleWorkspaceModeButtonClick() {
    workspaceMode = workspaceMode.toggled
    dismissContextMenu()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    refreshCanvas(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}

private func canTransferContent(from pasteboard: NSPasteboard) -> Bool {
    isReadingModeActive == false &&
        macOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}
```

### 修改后

- `prepareToolbarTransitionContext(direction:)` 和 iOS 一样，把“逻辑立即切换”和“视觉过渡快照”拆开：
  - `.toReading`：先抓 visible snapshot，再切到阅读态，然后用旧 snapshot 做 `collapsing -> exiting`
  - `.toEditing`：先切到编辑态，再反解编辑态 steady `visibleFrame`，然后做 `entering -> expanding`
- `runToolbarCollapsePhase()` / `runToolbarSlidePhase()` 负责两段式串联。
- `animateToolbarTransition(to:duration:completion:)` 改用 AppKit 的 `NSAnimationContext`。
- `finishToolbarModeTransition(applying:)` 负责在 completion 时重新回到 steady-state。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: prepareToolbarTransitionContext(direction:)
// 功能说明: 修改后 macOS 控制器复用与 iOS 相同的共享 context 语义，不再为平台再定义一套本地 Context / Frames / Presentation。
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
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: runToolbarCollapsePhase() / runToolbarSlidePhase() / animateToolbarTransition(to:duration:completion:) / finishToolbarModeTransition(applying:)
// 功能说明: 修改后 macOS 侧用与 iOS 相同的 stage 语义串起两段式动画，但平台动画句柄改为 NSAnimationContext。
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

private func animateToolbarTransition(
    to targetStage: CanvasToolbarTransitionStage,
    duration: TimeInterval,
    completion: @escaping () -> Void
) {
    guard var runtime = toolbarTransitionRuntime else {
        return
    }

    let targetPresentation = CanvasToolbarTransitionGeometry.presentation(
        for: targetStage,
        context: runtime.context
    )
    let expectedDirection = runtime.context.direction
    runtime.stage = targetStage
    runtime.currentPresentation = targetPresentation
    toolbarTransitionRuntime = runtime

    if duration <= 0 {
        toolbarHostView.renderTransition(targetPresentation)
        completion()
        return
    }

    NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.toolbarHostView.renderTransition(targetPresentation)
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
}

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

## 修改四：补上 macOS 侧的中断重基线与 steady frame 反解

### 修改前

- 原来的 macOS 控制器没有任何“动画中再次点模式切换”的重基线逻辑。
- 同时，控制器侧只有 `measuredToolbarHostSize()`，只会读取当前 Host 的测量值。
- 因此旧代码既不能：
  - 从当前动画帧反推 progress
  - 也不能在 `阅读 -> 编辑` 时独立反解目标 steady `visibleFrame`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: measuredToolbarHostSize()
// 功能说明: 修改前控制器只会读取当前 Host 的测量结果，没有面向目标 steady-state 的独立 frame 反解能力。
private func measuredToolbarHostSize() -> CGSize {
    CanvasChromeLayoutGeometry.sanitizedSize(
        toolbarHostView.measuredContentSize()
    )
}
```

### 修改后

- 新增 `cancelAndRebaseToolbarTransitionIfNeeded(targetMode:)`，中断时先读取当前 presentation，再在当前位置继续。
- 新增 `currentToolbarAnimatedFrame(fallback:)`，优先从 `layer?.presentation()?.frame` 取当前视觉帧。
- 新增 `resolvedSteadyToolbarFrame(for:)` 和 `measuredToolbarHostSize(for:)`，让 `阅读 -> 编辑` 能在控制器侧反解目标 steady frame。
- 新增 `toolbarLinearProgress(...)` / `clampedToolbarTransitionProgress(...)`，用实际几何位置反推当前阶段 progress。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: cancelAndRebaseToolbarTransitionIfNeeded(targetMode:) / currentToolbarAnimatedFrame(fallback:)
// 功能说明: 修改后如果 macOS 侧在动画未结束时再次切模式，会先把当前视觉帧读出来，再以当前位置重建新动画起点。
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
    toolbarHostView.renderTransition(runtime.currentPresentation)
}

private func currentToolbarAnimatedFrame(fallback: CGRect) -> CGRect {
    if let animatedFrame = toolbarHostView.layer?.presentation()?.frame,
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
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: resolvedSteadyToolbarFrame(for:) / measuredToolbarHostSize(for:) / toolbarLinearProgress(from:to:current:)
// 功能说明: 修改后 macOS 控制器可以像 iOS 一样，在控制器侧直接反解目标 steady frame，并根据当前几何位置推回动画进度。
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

private func toolbarLinearProgress(
    from start: CGFloat,
    to end: CGFloat,
    current: CGFloat
) -> CGFloat {
    guard start.isFinite, end.isFinite, current.isFinite else {
        return 0
    }

    let delta = end - start
    guard delta != 0 else {
        return 0
    }

    return clampedToolbarTransitionProgress((current - start) / delta)
}
```

## 修改五：给 macOS steady render / layout pass 增加 transition guard

### 修改前

- `updatePreparedToolbarPlacement()` 会直接触发 steady render 和 overlay layout。
- `applyToolbarFrame(_:)` 会直接改 `toolbarHostView.frame`。
- `renderToolbar()` 会直接把 steady `CanvasToolbarState` 重新 render 给 Host。
- 这些路径在动画过程中都会回写当前工具栏轨迹。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updatePreparedToolbarPlacement() / applyToolbarFrame(_:) / renderToolbar()
// 功能说明: 修改前 steady-state 的渲染和布局路径没有 transition guard，动画期间如果触发，会直接覆盖当前 presentation。
private func updatePreparedToolbarPlacement() {
    renderToolbar()
    if view.bounds.isEmpty == false {
        view.layoutSubtreeIfNeeded()
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

- 三条路径都先检查 `isToolbarTransitionActive`。
- 如果动画正在进行，不再覆盖当前展示，只把 `pendingLayoutReconcile` 记为 `true`。
- 这让 macOS 侧和 iOS 一样，具备了动画期不被 steady render 抢写的保护层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updatePreparedToolbarPlacement() / applyToolbarFrame(_:) / renderToolbar()
// 功能说明: 修改后 steady-state 的渲染和布局回写在动画期只记录 pending reconcile，不再直接覆盖 Host 当前的 transition presentation。
private func updatePreparedToolbarPlacement() {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    renderToolbar()
    if view.bounds.isEmpty == false {
        view.layoutSubtreeIfNeeded()
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

## 修改六：在 macOS Host 内部补上 AppKit 动画承接，但不改公共接口命名

### 修改前

- `macOSCanvasToolbarHostView` 已经有 `renderTransition(_:)`，但内部仍是“立即赋值”：
  - `frame = presentation.frame`
  - `buttonsStackView.alphaValue = ...`
  - `buttonsStackView.layer?.setAffineTransform(...)`
- 也就是说，控制器即便用 `NSAnimationContext` 包裹调用，Host 内部也没有把 frame / alpha / scale 分别转成 AppKit / Core Animation 的可动画属性写入。
- Host 也没有统一清理前一段过渡残留动画。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: init(frame:) / render(_:) / renderTransition(_:) / applyContentTransitionAppearance(alpha:scale:)
// 功能说明: 修改前 macOS Host 虽然已有 transition 接口，但内部仍然是立即赋值，不会真正承接 NSAnimationContext 的动画。
override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(backgroundView)
    addSubview(contentClipView)
    contentClipView.addSubview(buttonsStackView)
    // 其余约束代码保持原样
}

func render(_ state: CanvasToolbarState) {
    isTransitionRendering = false
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.preferredEdge
    transitionInteractivity = true
    backgroundView.isHidden = state.showsBackground == false
    applyContentTransitionAppearance(alpha: 1, scale: 1)
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}

func renderTransition(_ presentation: CanvasToolbarTransitionPresentation) {
    isTransitionRendering = true
    transitionInteractivity = presentation.isInteractive
    backgroundView.isHidden = presentation.showsBackground == false
    if frame != presentation.frame {
        frame = presentation.frame
    }
    syncButtons(with: presentation.itemStates)
    applyContentTransitionAppearance(
        alpha: presentation.contentAlpha,
        scale: presentation.contentScale
    )
    isHidden = presentation.keepsHostVisible == false
}

private func applyContentTransitionAppearance(
    alpha: CGFloat,
    scale: CGFloat
) {
    let clampedAlpha = min(max(alpha, 0), 1)
    let clampedScale = max(scale, 0)
    buttonsStackView.alphaValue = clampedAlpha
    buttonsStackView.layer?.setAffineTransform(
        CGAffineTransform(scaleX: clampedScale, y: clampedScale)
    )
}
```

### 修改后

- Host 内部新增 `QuartzCore` 依赖和 `wantsLayer = true`，让自己成为稳定的 layer-backed 容器。
- steady render 时先 `clearTransitionAnimations()`，避免上一段过渡残留影响 steady-state。
- `renderTransition(_:)` 现在根据 `NSAnimationContext.current.duration` 判断当前是动画写入还是立即写入：
  - frame：走 `animator().setFrameOrigin` / `animator().setFrameSize`
  - alpha：走 `buttonsStackView.animator().alphaValue`
  - scale：走 `CATransaction` 配合 `layer?.setAffineTransform(...)`
- Host 公共接口命名没有变化，仍然只是内部补上 AppKit 的动画承接层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: import 区 / init(frame:) / render(_:) / renderTransition(_:)
// 功能说明: 修改后 Host 仍保留原有公开接口，但内部正式接上 AppKit 动画写入路径。
#if os(macOS)
import AppKit
import QuartzCore

override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    addSubview(backgroundView)
    addSubview(contentClipView)
    contentClipView.addSubview(buttonsStackView)
    // 其余约束代码保持实际文件一致
}

func render(_ state: CanvasToolbarState) {
    clearTransitionAnimations()
    isTransitionRendering = false
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.preferredEdge
    transitionInteractivity = true
    backgroundView.isHidden = state.showsBackground == false
    applyContentTransitionAppearance(alpha: 1, scale: 1, animated: false)
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}

func renderTransition(_ presentation: CanvasToolbarTransitionPresentation) {
    let shouldAnimate = shouldAnimateTransitionChanges
    if shouldAnimate == false {
        clearTransitionAnimations()
    }
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
#endif
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: applyContentTransitionAppearance(alpha:scale:animated:) / shouldAnimateTransitionChanges / applyTransitionFrame(_:animated:) / clearTransitionAnimations()
// 功能说明: 修改后 Host 内部把 frame / alpha / scale 分别落到 AppKit 和 Core Animation 可动画属性上，并在 steady render 前清空残留动画。
private func applyContentTransitionAppearance(
    alpha: CGFloat,
    scale: CGFloat,
    animated: Bool
) {
    let clampedAlpha = min(max(alpha, 0), 1)
    let clampedScale = max(scale, 0)
    if animated {
        buttonsStackView.animator().alphaValue = clampedAlpha
    } else {
        buttonsStackView.alphaValue = clampedAlpha
    }

    CATransaction.begin()
    if animated {
        CATransaction.setAnimationDuration(NSAnimationContext.current.duration)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeInEaseOut)
        )
    } else {
        CATransaction.setDisableActions(true)
    }
    buttonsStackView.layer?.setAffineTransform(
        CGAffineTransform(scaleX: clampedScale, y: clampedScale)
    )
    CATransaction.commit()
}

private var shouldAnimateTransitionChanges: Bool {
    NSAnimationContext.current.duration > 0
}

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

private func clearTransitionAnimations() {
    layer?.removeAllAnimations()
    backgroundView.layer?.removeAllAnimations()
    contentClipView.layer?.removeAllAnimations()
    buttonsStackView.layer?.removeAllAnimations()
}
```

## 验证情况

- `ReadLints` 检查：
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - 结果：无 linter 报错。
- 已执行 macOS 工程构建校验，结果通过。

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild
# 功能说明: 对 Phase 3 的 macOS 控制器与 Host 改动执行工程级构建校验。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-toolbar-phase3-macos" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

- 本次没有附带肉眼动画验收记录。

## 当前结论

- 本次改动如实对应 `Phase 3`：
  - macOS 控制器已按与 iOS 同形的入口命名接入共享 transition runtime
  - macOS 侧已具备 `collapsing / exiting / entering / expanding` 的两段式过渡链路
  - 动画中再次切换时已支持按当前视觉帧重基线
  - steady render / layout pass 已补上 transition guard
  - macOS Host 在不改公共接口命名的前提下，已补上 AppKit 动画承接
- 当前业务代码改动仍只落在两份 macOS 文件：
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
