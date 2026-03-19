# 20260319_185634_canvas_toolbar_phase_d3_overlay_layout_chain_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段D-阶段3` 的实际代码变更。
- 本次实际产物：
- 将 `toolbar -> minimap -> context menu` 收口为统一的 overlay layout pass，不再让 `context menu` 额外走一套临时重建的布局输入链。
- 让 `CanvasContextMenuHostView` 改为直接消费 `CanvasChromeLayoutContext`，避免 host 接口继续拆成 `safeBounds + occupiedRects` 两段原始参数。
- 让 `iOS/macOS` controller 都通过 `performOverlayLayoutPass()` 先落位工具栏，再用已落位的真实 toolbar frame 参与 minimap 与 context menu 的 blocker 计算。
- `iOS` 继续把 `historyButtonsStackView` 纳入 chrome blocker 集；`macOS` 则保持 `backButton + toolbar` 的 blocker 结构。
- context menu 诊断日志改为消费同一帧的 `CanvasChromeLayoutContext`，避免日志链路与真实布局输入脱节。
- 本次未执行：
- 未修改 `CanvasContextMenuLayoutSolver` 的核心放置算法。
- 未修改 `CanvasContextMenuHostView` 中的 `occlusionPolicy = .allowChromeOverlap` 决策。
- 未进入 `阶段D-阶段4` 的拖拽扩展输入与遮挡策略决策。
- 未执行 git commit。

## 本次变更文件

- 修改：`MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前

- 到 `D2` 结束时，工具栏已经可以通过独立 solver 产出 frame，但 overlay 链路仍没有完全统一。
- `updateChromeOverlayLayout()` 虽然会先摆放工具栏，再计算 minimap，但 `updateContextMenuPresentation()` 和 `updateContextMenuLayout()` 仍各自调用 `makeContextMenuLayoutContext()`，导致 context menu 仍保留独立的取数支路。
- `CanvasContextMenuHostView` 的接口还是 `apply(state:safeBounds:occupiedRects:)` / `updateLayout(safeBounds:occupiedRects:)`，controller 仍要自己拆包和重复传参。
- 这意味着工具栏虽然已经具备真实 frame，但它进入 context menu 布局链的方式仍然是“controller 每次临时重组输入”，而不是“统一 overlay pass 产出单一 context”。

### Shared ContextMenu Host 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: apply(state:safeBounds:occupiedRects:) / updateLayout(safeBounds:occupiedRects:)
// 功能说明: 修改前 iOS host 只接收拆开的 safeBounds 与 occupiedRects，controller 仍需自己负责重组 context 并传入。
func apply(
    state: CanvasContextMenuState?,
    safeBounds: CGRect,
    occupiedRects: [CGRect]
) {
    currentState = state

    guard let state, state.isEmpty == false else {
        dismiss()
        return
    }

    rebuildCommandButtons(for: state)
    isHidden = false
    menuContainerView.isHidden = false
    updateLayout(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects
    )
}

func updateLayout(
    safeBounds: CGRect,
    occupiedRects: [CGRect]
) {
    guard let currentState else {
        return
    }

    let preferredSize = preferredMenuSize()
    guard let menuFrame = layoutSolver.resolveMenuFrame(
        anchorPoint: currentState.layoutAnchorPoint,
        preferredSize: preferredSize,
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: layoutConfiguration
    ) else {
        // ...
        return
    }

    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: apply(state:safeBounds:occupiedRects:) / updateLayout(safeBounds:occupiedRects:)
// 功能说明: 修改前 macOS host 也是同样的拆参接口，平台差异只在视图实现，不在布局输入 contract。
func apply(
    state: CanvasContextMenuState?,
    safeBounds: CGRect,
    occupiedRects: [CGRect]
) {
    currentState = state

    guard let state, state.isEmpty == false else {
        dismiss()
        return
    }

    rebuildCommandButtons(for: state)
    isHidden = false
    menuContainerView.isHidden = false
    updateLayout(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects
    )
}

func updateLayout(
    safeBounds: CGRect,
    occupiedRects: [CGRect]
) {
    guard let currentState else {
        return
    }

    let preferredSize = preferredMenuSize()
    guard let menuFrame = layoutSolver.resolveMenuFrame(
        anchorPoint: currentState.layoutAnchorPoint,
        preferredSize: preferredSize,
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: layoutConfiguration
    ) else {
        // ...
        return
    }

    // ...
}
```

### iOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateContextMenuPresentation() / updateContextMenuLayout()
// 功能说明: 修改前 iOS 的 context menu presentation 和 relayout 都各自重新构建一份 context menu layout context，仍未接入统一 overlay pass。
private func updateContextMenuPresentation() {
    let layoutContext = makeContextMenuLayoutContext()
    contextMenuHostView.apply(
        state: contextMenuState,
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects
    )
}

private func updateContextMenuLayout() {
    let layoutContext = makeContextMenuLayoutContext()
    contextMenuHostView.updateLayout(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateChromeOverlayLayout() / applyToolbarPlacement() / makeChromeLayoutContext() / makeContextMenuLayoutContext()
// 功能说明: 修改前 iOS 虽然先解 toolbar 再解 minimap，但 context menu 所用 layout context 仍是后面单独临时重建的，不是统一 pass 的产物。
private func updateChromeOverlayLayout() {
    applyToolbarPlacement()
    let layoutContext = makeChromeLayoutContext()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
    updateContextMenuLayout()
}

private func applyToolbarPlacement() {
    let layoutContext = makeChromeLayoutContext()
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    )?.integral ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }
}
```

### macOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: updateContextMenuPresentation() / updateContextMenuLayout()
// 功能说明: 修改前 macOS 也让 context menu 在 presentation / relayout 两个入口各自取 layout context，链路仍是分叉状态。
private func updateContextMenuPresentation() {
    let layoutContext = makeContextMenuLayoutContext()
    contextMenuHostView.apply(
        state: contextMenuState,
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects
    )
}

private func updateContextMenuLayout() {
    let layoutContext = makeContextMenuLayoutContext()
    contextMenuHostView.updateLayout(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: updateChromeOverlayLayout() / applyToolbarPlacement() / makeChromeLayoutContext() / makeContextMenuLayoutContext()
// 功能说明: 修改前 macOS 同样是“toolbar/minimap 一条链，context menu 再单独取数”的模式，toolbar 还没有正式成为 overlay pass 的产物。
private func updateChromeOverlayLayout() {
    applyToolbarPlacement()
    let layoutContext = makeChromeLayoutContext()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
    updateContextMenuLayout()
}

private func applyToolbarPlacement() {
    let layoutContext = makeChromeLayoutContext()
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    )?.integral ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }
}
```

## 修改后

- `CanvasContextMenuHostView` 双端实现统一切换为 `layoutContext: CanvasChromeLayoutContext` 输入。
- controller 统一新增 `performOverlayLayoutPass()`，把工具栏、minimap、context menu 的布局输入收口到一条流水线。
- `makeChromeLayoutContext(toolbarFrame:)` 改为显式接收已解出的 toolbar frame，从而保证 toolbar blocker 是真实 frame，而不是某个早期静态约束假设。
- `makeContextMenuLayoutContext(chromeLayoutContext:miniMapFrame:)` 改为基于同一帧的 chrome context 和 minimap frame 继续桥接到 context menu host 坐标系。
- `logContextMenuPresentation(...)` 改为直接接收 `CanvasContextMenuState + CanvasChromeLayoutContext`，诊断日志与实际布局输入同源。

### Shared ContextMenu Host 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: apply(state:layoutContext:) / updateLayout(layoutContext:)
// 功能说明: D3 之后，iOS host 直接消费统一的 CanvasChromeLayoutContext，不再要求 controller 拆传 safeBounds 与 occupiedRects。
func apply(
    state: CanvasContextMenuState?,
    layoutContext: CanvasChromeLayoutContext
) {
    currentState = state

    guard let state, state.isEmpty == false else {
        dismiss()
        return
    }

    rebuildCommandButtons(for: state)
    isHidden = false
    menuContainerView.isHidden = false
    updateLayout(layoutContext: layoutContext)
}

func updateLayout(layoutContext: CanvasChromeLayoutContext) {
    guard let currentState else {
        return
    }

    let preferredSize = preferredMenuSize()
    guard let menuFrame = layoutSolver.resolveMenuFrame(
        anchorPoint: currentState.layoutAnchorPoint,
        preferredSize: preferredSize,
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: layoutConfiguration
    ) else {
        // ...
        return
    }

    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: apply(state:layoutContext:) / updateLayout(layoutContext:)
// 功能说明: D3 之后，macOS host 也统一为 layoutContext 输入，双端 context menu host 的布局 contract 保持一致。
func apply(
    state: CanvasContextMenuState?,
    layoutContext: CanvasChromeLayoutContext
) {
    currentState = state

    guard let state, state.isEmpty == false else {
        dismiss()
        return
    }

    rebuildCommandButtons(for: state)
    isHidden = false
    menuContainerView.isHidden = false
    updateLayout(layoutContext: layoutContext)
}

func updateLayout(layoutContext: CanvasChromeLayoutContext) {
    guard let currentState else {
        return
    }

    let preferredSize = preferredMenuSize()
    guard let menuFrame = layoutSolver.resolveMenuFrame(
        anchorPoint: currentState.layoutAnchorPoint,
        preferredSize: preferredSize,
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: layoutConfiguration
    ) else {
        // ...
        return
    }

    // ...
}
```

### iOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateContextMenuPresentation() / updateContextMenuLayout(using:)
// 功能说明: 修改后 iOS 的 context menu presentation 与 relayout 都改为消费同一帧 overlay pass 产出的 CanvasChromeLayoutContext。
private func updateContextMenuPresentation() {
    guard isViewLoaded else {
        return
    }

    let layoutContext = performOverlayLayoutPass()
    if let contextMenuState {
        logContextMenuPresentation(
            state: contextMenuState,
            layoutContext: layoutContext
        )
    }
    contextMenuHostView.apply(
        state: contextMenuState,
        layoutContext: layoutContext
    )
}

private func updateContextMenuLayout(
    using layoutContext: CanvasChromeLayoutContext
) {
    contextMenuHostView.updateLayout(layoutContext: layoutContext)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateChromeOverlayLayout() / performOverlayLayoutPass() / applyToolbarPlacement(using:) / resolveMiniMapFrame(in:) / makeChromeLayoutContext(toolbarFrame:) / makeContextMenuLayoutContext(chromeLayoutContext:miniMapFrame:)
// 功能说明: 修改后 iOS 把 toolbar、minimap、context menu 收口到同一条 overlay pass，toolbar blocker 也改为使用已落位的真实 frame。
private func updateChromeOverlayLayout() {
    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateContextMenuLayout(using: contextMenuLayoutContext)
}

private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    let toolbarPlacementContext = makeChromeLayoutContext(
        toolbarFrame: nil
    )
    let toolbarFrame = applyToolbarPlacement(
        using: toolbarPlacementContext
    )
    let chromeLayoutContext = makeChromeLayoutContext(
        toolbarFrame: toolbarFrame
    )
    let miniMapFrame = resolveMiniMapFrame(
        in: chromeLayoutContext
    )
    applyMiniMapFrame(miniMapFrame)
    return makeContextMenuLayoutContext(
        chromeLayoutContext: chromeLayoutContext,
        miniMapFrame: miniMapFrame
    )
}

private func applyToolbarPlacement(
    using layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    )?.integral ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }

    return resolvedFrame
}

private func makeChromeLayoutContext(
    toolbarFrame: CGRect?
) -> CanvasChromeLayoutContext {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(kind: .backButton, for: backButton, to: &chromeBlockers)
    appendChromeBlocker(kind: .historyButtons, for: historyButtonsStackView, to: &chromeBlockers)
    if let toolbarFrame {
        appendChromeBlocker(
            kind: .toolbar,
            rect: toolbarFrame,
            to: &chromeBlockers
        )
    }

    return CanvasChromeLayoutContext(
        safeBounds: chromeOverlayView.safeAreaLayoutGuide.layoutFrame,
        toolbarPreferredPlacement: toolbarPreferredPlacement(),
        toolbarMeasuredSize: measuredToolbarHostSize(),
        chromeBlockers: chromeBlockers
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: logContextMenuPresentation(state:layoutContext:)
// 功能说明: 修改后 iOS 的 context menu 诊断日志直接复用本帧 layoutContext，日志观察值与真实布局输入保持一致。
private func logContextMenuPresentation(
    state: CanvasContextMenuState,
    layoutContext: CanvasChromeLayoutContext
) {
    let occupiedRectsDescription = layoutContext.occupiedRects
        .map(describe(rect:))
        .joined(separator: ", ")
    let commandIDsDescription = state.commandStates
        .map(\.commandID.rawValue)
        .joined(separator: ",")
    let layoutAnchorPoint = contextMenuLayoutAnchorPoint(
        for: state.resolvedContext
    )

    print(
        "[Canvas iOS][ContextMenuPosition] " +
        state.resolvedContext.debugSummary + " " +
        "safeBounds=\(describe(rect: layoutContext.safeBounds)) " +
        "occupiedRects=[\(occupiedRectsDescription)] " +
        "commandIDs=[\(commandIDsDescription)]"
    )
}
```

### macOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: updateContextMenuPresentation() / updateContextMenuLayout(using:)
// 功能说明: 修改后 macOS 也让 context menu presentation 与 relayout 共用同一帧 overlay pass 的 layoutContext。
private func updateContextMenuPresentation() {
    guard isViewLoaded else {
        return
    }

    let layoutContext = performOverlayLayoutPass()
    if let contextMenuState {
        logContextMenuPresentation(
            state: contextMenuState,
            layoutContext: layoutContext
        )
    }
    contextMenuHostView.apply(
        state: contextMenuState,
        layoutContext: layoutContext
    )
}

private func updateContextMenuLayout(
    using layoutContext: CanvasChromeLayoutContext
) {
    contextMenuHostView.updateLayout(layoutContext: layoutContext)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: updateChromeOverlayLayout() / performOverlayLayoutPass() / applyToolbarPlacement(using:) / resolveMiniMapFrame(in:) / makeChromeLayoutContext(toolbarFrame:) / makeContextMenuLayoutContext(chromeLayoutContext:miniMapFrame:)
// 功能说明: 修改后 macOS 同样采用统一 overlay pass，并通过 toolbarFrame 参数把真实 toolbar blocker 带入 minimap/context menu 链路。
private func updateChromeOverlayLayout() {
    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateContextMenuLayout(using: contextMenuLayoutContext)
}

private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    let toolbarPlacementContext = makeChromeLayoutContext(
        toolbarFrame: nil
    )
    let toolbarFrame = applyToolbarPlacement(
        using: toolbarPlacementContext
    )
    let chromeLayoutContext = makeChromeLayoutContext(
        toolbarFrame: toolbarFrame
    )
    let miniMapFrame = resolveMiniMapFrame(
        in: chromeLayoutContext
    )
    applyMiniMapFrame(miniMapFrame)
    return makeContextMenuLayoutContext(
        chromeLayoutContext: chromeLayoutContext,
        miniMapFrame: miniMapFrame
    )
}

private func applyToolbarPlacement(
    using layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    )?.integral ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }

    return resolvedFrame
}

private func makeChromeLayoutContext(
    toolbarFrame: CGRect?
) -> CanvasChromeLayoutContext {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(kind: .backButton, for: backButton, to: &chromeBlockers)
    if let toolbarFrame {
        appendChromeBlocker(
            kind: .toolbar,
            rect: toolbarFrame,
            to: &chromeBlockers
        )
    }

    return CanvasChromeLayoutContext(
        safeBounds: CGRect(
            x: view.bounds.minX + view.safeAreaInsets.left,
            y: view.bounds.minY + view.safeAreaInsets.top,
            width: max(view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right, 0),
            height: max(view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom, 0)
        ).standardized,
        toolbarPreferredPlacement: toolbarPreferredPlacement(),
        toolbarMeasuredSize: measuredToolbarHostSize(),
        chromeBlockers: chromeBlockers
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: logContextMenuPresentation(state:layoutContext:)
// 功能说明: 修改后 macOS 的 context menu 诊断日志也直接绑定本帧 layoutContext，不再单独重建 context menu layout context。
private func logContextMenuPresentation(
    state: CanvasContextMenuState,
    layoutContext: CanvasChromeLayoutContext
) {
    let occupiedRectsDescription = layoutContext.occupiedRects
        .map(describe(rect:))
        .joined(separator: ", ")
    let commandIDsDescription = state.commandStates
        .map(\.commandID.rawValue)
        .joined(separator: ",")
    let layoutAnchorPoint = contextMenuLayoutAnchorPoint(
        for: state.resolvedContext
    )

    print(
        "[Canvas macOS][ContextMenuPosition] " +
        state.resolvedContext.debugSummary + " " +
        "safeBounds=\(describe(rect: layoutContext.safeBounds)) " +
        "occupiedRects=[\(occupiedRectsDescription)] " +
        "commandIDs=[\(commandIDsDescription)]"
    )
}
```

## 验证结果

- 已执行 `ReadLints`，检查以下文件，结果无新增 lint 问题：
- `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 已执行 iOS Debug 构建并通过：
- `DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath ".build/ios-sim" build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" AD_HOC_CODE_SIGNING_ALLOWED=NO`
- 已执行 macOS Debug 构建并通过：
- `DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=macOS" -derivedDataPath ".build/macos" build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## 结果说明

- `D3` 的核心结果不是“又多写了一层 helper”，而是把 toolbar 正式并入 overlay 布局链，controller 对外只剩输入收集、solver 调用和 frame 应用职责。
- 到这一阶段，toolbar 的真实 frame 已经稳定进入 minimap 与 context menu 的 blocker 计算链，为后续 `D4` 讨论拖拽扩展输入与遮挡策略提供了更稳的边界。
