# 20260325_121154_crop_hittester_phase5_pointer_menu_split_record

## 记录范围

- 记录内容：把 `Phase 4` 的控制器本地适配层，继续推进为 `Phase 5` 的 pointer / menu 上下文拆分。
- 目标结果：主 pointer 按下、移动、抬起、history transaction 全部改走独立的 `CanvasPointerPressContext`；长按 / 右键菜单继续保留 `CanvasContextMenuContext`。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift`、`MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`、`MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`、`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`、`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：`Phase 6` 的旧命名清理与 `cropOutlineHitTargetWidth` 重命名。

## 修改一：共享层新增独立的 `CanvasPointerPressContext`

### 修改前

- 共享层虽然已经能识别 `cropTranslationArea`，但内部结果还是直接收敛成 `CanvasContextMenuTargetKind`。
- 这意味着 pointer 主链路仍然只能借道菜单语义，无法拥有独立的目标模型。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolvedTarget(from:) / ResolvedTarget
// 功能说明: 修改前共享命中结果直接存成 CanvasContextMenuTargetKind，还没有独立的 pointer 目标模型。
private func resolvedTarget(
    from hitTarget: CanvasEditOverlayHitTarget
) -> ResolvedTarget {
    let targetKind: CanvasContextMenuTargetKind
    switch hitTarget.kind {
    case .rotateHandle:
        targetKind = .rotateHandle
    case let .selectionHandle(role):
        targetKind = .selectionHandle(role: role)
    case let .cropHandle(role):
        targetKind = .cropHandle(role: role)
    case .cropTranslationArea:
        // Phase 3 expands the shared translation area, but the outward
        // context still reports .cropOutline until controller/menu paths
        // are fully migrated in later stages.
        targetKind = .cropOutline
    }

    return ResolvedTarget(
        targetKind: targetKind,
        editOverlayHitTargetKind: hitTarget.kind,
        targetItemID: hitTarget.itemID,
        anchorRect: hitTarget.anchorRect
    )
}

private struct ResolvedTarget {
    let targetKind: CanvasContextMenuTargetKind
    var editOverlayHitTargetKind: CanvasEditOverlayHitTargetKind? = nil
    var targetItemID: CanvasItemID? = nil
    var anchorRect: CGRect? = nil
}
```

### 修改后

- 新增 `CanvasPointerTargetKind` 和 `CanvasPointerPressContext`，让 pointer 链路拥有和菜单上下文并列的共享模型。
- `targetKind` 现在首先落在 pointer 语义上，后续是否映射成菜单语义由 resolver 单独决定。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
// 函数名: CanvasPointerTargetKind / CanvasPointerPressContext
// 功能说明: 修改后共享层新增独立 pointer 目标模型，专门承接按下时的输入语义。
enum CanvasPointerTargetKind {
    case rotateHandle
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea
    case selectionHandle(role: CanvasSelectionHandleRole)
    case selectedItemBody
    case unselectedItemBody
    case blank

    var debugName: String {
        switch self {
        case .rotateHandle:
            return "rotateHandle"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropTranslationArea:
            return "cropTranslationArea"
        case let .selectionHandle(role):
            return "selectionHandle(\(String(describing: role)))"
        case .selectedItemBody:
            return "selectedItemBody"
        case .unselectedItemBody:
            return "unselectedItemBody"
        case .blank:
            return "blank"
        }
    }
}

struct CanvasPointerPressContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasPointerTargetKind
    let targetItemID: CanvasItemID?
    let anchorRect: CGRect?
}
```

## 修改二：`CanvasContextResolver` 拆成共享命中核心 + pointer/menu 双出口

### 修改前

- `CanvasContextResolver` 只有 `resolveContext(...)` 一个出口。
- `finalize(...)`、日志输出、目标组装都内嵌在菜单上下文分支里，pointer 链路没有单独入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolveContext(at:scene:camera:renderSnapshot:selectedItemID:isInlineEditModeActive:isInlineCropModeActive:interactionMetrics:)
// 功能说明: 修改前 resolver 只有菜单上下文出口，pointer 解析必须依附在 resolveContext 上。
func resolveContext(
    at viewportPoint: CGPoint,
    scene: CanvasScene,
    camera: CanvasCamera,
    renderSnapshot: CanvasRenderSnapshot,
    selectedItemID: CanvasItemID?,
    isInlineEditModeActive: Bool,
    isInlineCropModeActive: Bool,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasContextMenuContext {
    let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
    let editOverlayDescription = describeContextResolverOverlay(renderSnapshot.editOverlay)

    func finalize(
        branch: String,
        resolvedTarget: ResolvedTarget,
        sceneHitItemID: CanvasItemID? = nil
    ) -> CanvasContextMenuContext {
        let context = makeContext(
            viewportPoint: viewportPoint,
            worldPoint: invocationWorldPoint,
            resolvedTarget: resolvedTarget,
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive
        )
        print(
            "[Canvas Shared][ContextResolve] " +
            "branch=\(branch) " +
            "viewportPoint=\(describeContextResolverPoint(viewportPoint)) " +
            "worldPoint=\(describeContextResolverPoint(invocationWorldPoint)) " +
            "viewportBounds=\(describeContextResolverRect(renderSnapshot.viewportBounds)) " +
            "visibleWorldRect=\(describeContextResolverRect(renderSnapshot.visibleWorldRect)) " +
            "selectedItemID=\(describeContextResolverItemID(selectedItemID)) " +
            "sceneHitItemID=\(describeContextResolverItemID(sceneHitItemID)) " +
            "renderItems=\(renderSnapshot.items.count) " +
            "editOverlay=\(editOverlayDescription) " +
            context.debugSummary
        )
        return context
    }

    // ... 之后直接走 editOverlay / blank / itemBody 的菜单上下文返回
}
```

### 修改后

- 新增 `resolvePointerTarget(...)`，专门产出 `CanvasPointerPressContext`。
- 新增私有 `resolveTarget(...)`，把 overlay、inline blank、scene item body 这些判定抽成共享核心。
- `resolveContext(...)` 改为调用 `resolveTarget(...)` 后再映射成 `CanvasContextMenuContext`，从而保留菜单兼容语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolvePointerTarget(at:scene:camera:renderSnapshot:selectedItemID:isInlineEditModeActive:interactionMetrics:) / resolveTarget(...)
// 功能说明: 修改后 resolver 先产出共享的 ResolvedTarget，再分别提供 pointer 和 menu 两个出口。
func resolvePointerTarget(
    at viewportPoint: CGPoint,
    scene: CanvasScene,
    camera: CanvasCamera,
    renderSnapshot: CanvasRenderSnapshot,
    selectedItemID: CanvasItemID?,
    isInlineEditModeActive: Bool,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasPointerPressContext {
    let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
    let resolution = resolveTarget(
        at: viewportPoint,
        invocationWorldPoint: invocationWorldPoint,
        scene: scene,
        renderSnapshot: renderSnapshot,
        selectedItemID: selectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        interactionMetrics: interactionMetrics
    )

    return makePointerPressContext(
        viewportPoint: viewportPoint,
        worldPoint: invocationWorldPoint,
        resolvedTarget: resolution.resolvedTarget
    )
}

private func resolveTarget(
    at viewportPoint: CGPoint,
    invocationWorldPoint: CGPoint,
    scene: CanvasScene,
    renderSnapshot: CanvasRenderSnapshot,
    selectedItemID: CanvasItemID?,
    isInlineEditModeActive: Bool,
    interactionMetrics: CanvasContextResolverMetrics
) -> ResolutionResult {
    if let editOverlayHitTarget = editOverlayHitTester.resolve(
        at: viewportPoint,
        renderSnapshot: renderSnapshot,
        metrics: interactionMetrics
    ) {
        return ResolutionResult(
            branch: contextResolverBranch(for: editOverlayHitTarget),
            resolvedTarget: resolvedTarget(from: editOverlayHitTarget)
        )
    }

    if isInlineEditModeActive {
        return ResolutionResult(
            branch: "inlineEditBlank",
            resolvedTarget: ResolvedTarget(pointerTargetKind: .blank)
        )
    }

    guard let itemID = scene.topmostBoardItemID(containing: invocationWorldPoint) else {
        return ResolutionResult(
            branch: "blank",
            resolvedTarget: ResolvedTarget(pointerTargetKind: .blank)
        )
    }

    let targetKind: CanvasPointerTargetKind =
        itemID == selectedItemID ? .selectedItemBody : .unselectedItemBody

    return ResolutionResult(
        branch: "itemBody",
        resolvedTarget: ResolvedTarget(
            pointerTargetKind: targetKind,
            targetItemID: itemID,
            anchorRect: itemAnchorRect(
                for: itemID,
                renderSnapshot: renderSnapshot
            )
        ),
        sceneHitItemID: itemID
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: makeContext(viewportPoint:worldPoint:resolvedTarget:selectedItemID:isInlineEditModeActive:isInlineCropModeActive:) / contextMenuTargetKind(for:)
// 功能说明: 修改后菜单出口继续兼容旧语义，cropTranslationArea 只在菜单层映射回 cropOutline。
private func makeContext(
    viewportPoint: CGPoint,
    worldPoint: CGPoint,
    resolvedTarget: ResolvedTarget,
    selectedItemID: CanvasItemID?,
    isInlineEditModeActive: Bool,
    isInlineCropModeActive: Bool
) -> CanvasContextMenuContext {
    CanvasContextMenuContext(
        invocationViewportPoint: viewportPoint,
        invocationWorldPoint: worldPoint,
        targetKind: contextMenuTargetKind(
            for: resolvedTarget.pointerTargetKind
        ),
        editOverlayHitTargetKind: resolvedTarget.editOverlayHitTargetKind,
        targetItemID: resolvedTarget.targetItemID,
        anchorRect: resolvedTarget.anchorRect,
        selectedItemID: selectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        isInlineCropModeActive: isInlineCropModeActive
    )
}

private func contextMenuTargetKind(
    for pointerTargetKind: CanvasPointerTargetKind
) -> CanvasContextMenuTargetKind {
    switch pointerTargetKind {
    case .rotateHandle:
        return .rotateHandle
    case let .cropHandle(role):
        return .cropHandle(role: role)
    case .cropTranslationArea:
        return .cropOutline
    case let .selectionHandle(role):
        return .selectionHandle(role: role)
    case .selectedItemBody:
        return .selectedItemBody
    case .unselectedItemBody:
        return .unselectedItemBody
    case .blank:
        return .blank
    }
}
```

## 修改三：`CanvasEditorSession` 新增 pointer 解析入口

### 修改前

- `CanvasEditorSession` 只暴露 `resolveContext(...)`。
- 控制器如果想拿到命中结果，只能取菜单上下文。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: resolveContext(at:interactionMetrics:)
// 功能说明: 修改前 session 只提供菜单上下文解析入口。
func resolveContext(
    at viewportPoint: CGPoint,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasContextMenuContext {
    contextResolver.resolveContext(
        at: viewportPoint,
        scene: scene,
        camera: camera,
        renderSnapshot: lastRenderSnapshot,
        selectedItemID: interactionState.selectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        isInlineCropModeActive: isInlineCropModeActive,
        interactionMetrics: interactionMetrics
    )
}
```

### 修改后

- 新增 `resolvePointerTarget(...)`，直接把 pointer 解析入口挂到 session 上。
- 控制器不再需要直接理解 resolver 的双出口细节。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: resolvePointerTarget(at:interactionMetrics:)
// 功能说明: 修改后 session 同时提供 pointer 解析入口，供平台控制器直接消费。
func resolvePointerTarget(
    at viewportPoint: CGPoint,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasPointerPressContext {
    contextResolver.resolvePointerTarget(
        at: viewportPoint,
        scene: scene,
        camera: camera,
        renderSnapshot: lastRenderSnapshot,
        selectedItemID: interactionState.selectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        interactionMetrics: interactionMetrics
    )
}
```

## 修改四：`iOS` 控制器改为直接消费 `CanvasPointerPressContext`

### 修改前

- `PointerDragState.pressed` 保存的是 `CanvasContextMenuContext`。
- 控制器内部还保留一个 `PointerPressTargetKind` 适配层，用来把菜单上下文翻译回 pointer 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerDragState / PointerPressTargetKind / pointerPressTargetKind(for:)
// 功能说明: 修改前 iOS 控制器仍然把菜单上下文当成按下态数据源，再在本地做一次 target 翻译。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasContextMenuContext
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private enum PointerPressTargetKind {
    case rotateHandle
    case cropHandle(CanvasCropHandleRole)
    case cropTranslationArea
    case selectionHandle(CanvasSelectionHandleRole)
    case selectedItemBody
    case unselectedItemBody
    case blank
}

private func pointerPressTargetKind(
    for pressContext: CanvasContextMenuContext
) -> PointerPressTargetKind {
    if let editOverlayHitTargetKind = pressContext.editOverlayHitTargetKind {
        switch editOverlayHitTargetKind {
        case .rotateHandle:
            return .rotateHandle
        case let .selectionHandle(role):
            return .selectionHandle(role)
        case let .cropHandle(role):
            return .cropHandle(role)
        case .cropTranslationArea:
            return .cropTranslationArea
        }
    }

    switch pressContext.targetKind {
    case .rotateHandle:
        return .rotateHandle
    case let .cropHandle(role):
        return .cropHandle(role)
    case .cropOutline:
        return .cropTranslationArea
    case let .selectionHandle(role):
        return .selectionHandle(role)
    case .selectedItemBody:
        return .selectedItemBody
    case .unselectedItemBody:
        return .unselectedItemBody
    case .blank:
        return .blank
    }
}
```

### 修改后

- `PointerDragState.pressed` 直接保存 `CanvasPointerPressContext`。
- 本地 `PointerPressTargetKind` 适配层被删除，改成直接调用 `resolvePointerPressContext(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerDragState / resolvePointerPressContext(at:)
// 功能说明: 修改后 iOS 控制器直接持有共享 pointer 上下文，不再依赖菜单上下文做中转。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private func resolvePointerPressContext(
    at viewportLocation: CGPoint
) -> CanvasPointerPressContext {
    editorSession.resolvePointerTarget(
        at: viewportLocation,
        interactionMetrics: contextResolverMetrics
    )
}
```

### Pointer 主链路修改前

- `pointer down` 和 `pointer up` 都通过 `resolveContext(...)` 取命中结果。
- `move / up / history` 依赖 `pointerPressTargetKind(for:)` 再做一次本地转换。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerDown(at:) / handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改前 iOS 的 pointer 主链路仍然在消费 CanvasContextMenuContext 与本地适配层。
let pressContext = resolveContext(at: location)
pointerDragState = .pressed(
    pressedLocation: location,
    pressContext: pressContext
)
beginPointerHistoryTransactionIfNeeded(for: pressContext)

switch pointerPressTargetKind(for: pressContext) {
case .rotateHandle:
    // ...
case let .cropHandle(handleRole):
    // ...
case .cropTranslationArea:
    // ...
case let .selectionHandle(handleRole):
    // ...
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}

let releasedContext = resolveContext(at: location)
let releasedItemID = releasedContext.targetItemID

switch pointerPressTargetKind(for: pressContext) {
case .rotateHandle:
    clickTarget = "rotate_handle"
case .cropHandle:
    clickTarget = "crop_handle"
case .cropTranslationArea:
    clickTarget = "crop_translation_area"
case .selectionHandle:
    clickTarget = "handle"
case .selectedItemBody, .unselectedItemBody:
    if case .selectedItemBody = pointerPressTargetKind(for: pressContext),
       beginTextEditIfPossible(for: itemID)
    {
        clickResult = "text_edit_began"
    }
case .blank:
    // ...
}

private func beginPointerHistoryTransactionIfNeeded(
    for pressContext: CanvasContextMenuContext
) {
    let reason: String
    switch pointerPressTargetKind(for: pressContext) {
    case .rotateHandle:
        reason = "rotate item"
    case .cropHandle, .cropTranslationArea:
        reason = "crop item"
    case .selectionHandle:
        reason = "resize item"
    case .selectedItemBody:
        reason = "move item"
    case .unselectedItemBody, .blank:
        return
    }
}
```

### Pointer 主链路修改后

- `pointer down` 与 `pointer up` 改成直接读取 `resolvePointerPressContext(...)`。
- `move / up / history` 统一直接 `switch pressContext.targetKind`，不再经过本地二次翻译。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerDown(at:) / handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改后 iOS 的 pointer 主链路完全切到 CanvasPointerPressContext，主输入状态机不再依赖 CanvasContextMenuContext。
let pressContext = resolvePointerPressContext(at: location)
pointerDragState = .pressed(
    pressedLocation: location,
    pressContext: pressContext
)
beginPointerHistoryTransactionIfNeeded(for: pressContext)

switch pressContext.targetKind {
case .rotateHandle:
    // ...
case let .cropHandle(handleRole):
    // ...
case .cropTranslationArea:
    // ...
case let .selectionHandle(handleRole):
    // ...
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}

let releasedContext = resolvePointerPressContext(at: location)
let releasedItemID = releasedContext.targetItemID

switch pressContext.targetKind {
case .rotateHandle:
    clickTarget = "rotate_handle"
case .cropHandle:
    clickTarget = "crop_handle"
case .cropTranslationArea:
    clickTarget = "crop_translation_area"
case .selectionHandle:
    clickTarget = "handle"
case .selectedItemBody, .unselectedItemBody:
    if case .selectedItemBody = pressContext.targetKind,
       beginTextEditIfPossible(for: itemID)
    {
        clickResult = "text_edit_began"
    }
case .blank:
    // ...
}

private func beginPointerHistoryTransactionIfNeeded(
    for pressContext: CanvasPointerPressContext
) {
    let reason: String
    switch pressContext.targetKind {
    case .rotateHandle:
        reason = "rotate item"
    case .cropHandle, .cropTranslationArea:
        reason = "crop item"
    case .selectionHandle:
        reason = "resize item"
    case .selectedItemBody:
        reason = "move item"
    case .unselectedItemBody, .blank:
        return
    }
}
```

### 菜单链路保留旧入口

- `iOS` 的长按菜单仍然调用 `resolveContext(...)`，说明 pointer 与 menu 已经拆成两条明确入口，而不是互相替代。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleLongPress(at:)
// 功能说明: 修改后 iOS 的菜单链路仍然保留 CanvasContextMenuContext，不会误切到 pointer 上下文。
private func handleLongPress(at location: CGPoint) {
    // ... 省略前置同步与日志
    prepareForLongPressContextMenu()

    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}
```

## 修改五：`macOS` 控制器同步切到独立 pointer 上下文

### 修改前

- `macOS` 和 `iOS` 一样，`pressed` 持有 `CanvasContextMenuContext`。
- 本地保留 `PointerPressTargetKind` 适配层，pointer 主链路仍然借用菜单语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: PointerDragState / PointerPressTargetKind / pointerPressTargetKind(for:)
// 功能说明: 修改前 macOS 控制器与 iOS 镜像一致，仍然通过菜单上下文中转 pointer 语义。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasContextMenuContext
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private enum PointerPressTargetKind {
    case rotateHandle
    case cropHandle(CanvasCropHandleRole)
    case cropTranslationArea
    case selectionHandle(CanvasSelectionHandleRole)
    case selectedItemBody
    case unselectedItemBody
    case blank
}

private func pointerPressTargetKind(
    for pressContext: CanvasContextMenuContext
) -> PointerPressTargetKind {
    if let editOverlayHitTargetKind = pressContext.editOverlayHitTargetKind {
        switch editOverlayHitTargetKind {
        case .rotateHandle:
            return .rotateHandle
        case let .selectionHandle(role):
            return .selectionHandle(role)
        case let .cropHandle(role):
            return .cropHandle(role)
        case .cropTranslationArea:
            return .cropTranslationArea
        }
    }

    switch pressContext.targetKind {
    case .rotateHandle:
        return .rotateHandle
    case let .cropHandle(role):
        return .cropHandle(role)
    case .cropOutline:
        return .cropTranslationArea
    case let .selectionHandle(role):
        return .selectionHandle(role)
    case .selectedItemBody:
        return .selectedItemBody
    case .unselectedItemBody:
        return .unselectedItemBody
    case .blank:
        return .blank
    }
}
```

### 修改后

- `macOS` 同样直接持有 `CanvasPointerPressContext`。
- 主 pointer 链路和 history transaction 也全部改成直接读取 `pressContext.targetKind`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: PointerDragState / resolvePointerPressContext(at:)
// 功能说明: 修改后 macOS 控制器与 iOS 保持镜像实现，pointer 主链路不再经过菜单上下文。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private func resolvePointerPressContext(
    at viewportLocation: CGPoint
) -> CanvasPointerPressContext {
    editorSession.resolvePointerTarget(
        at: viewportLocation,
        interactionMetrics: contextResolverMetrics
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerDown(at:) / handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改后 macOS 的主 pointer 状态机直接消费 CanvasPointerPressContext，与 iOS 的输入链路保持镜像一致。
let pressContext = resolvePointerPressContext(at: location)
pointerDragState = .pressed(
    pressedLocation: location,
    pressContext: pressContext
)
beginPointerHistoryTransactionIfNeeded(for: pressContext)

switch pressContext.targetKind {
case .rotateHandle:
    // ...
case let .cropHandle(handleRole):
    // ...
case .cropTranslationArea:
    // ...
case let .selectionHandle(handleRole):
    // ...
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}

let releasedContext = resolvePointerPressContext(at: location)
let releasedItemID = releasedContext.targetItemID

switch pressContext.targetKind {
case .rotateHandle:
    clickTarget = "rotate_handle"
case .cropHandle:
    clickTarget = "crop_handle"
case .cropTranslationArea:
    clickTarget = "crop_translation_area"
case .selectionHandle:
    clickTarget = "handle"
case .selectedItemBody, .unselectedItemBody:
    if case .selectedItemBody = pressContext.targetKind,
       beginTextEditIfPossible(for: itemID)
    {
        clickResult = "text_edit_began"
    }
case .blank:
    // ...
}

private func beginPointerHistoryTransactionIfNeeded(
    for pressContext: CanvasPointerPressContext
) {
    let reason: String
    switch pressContext.targetKind {
    case .rotateHandle:
        reason = "rotate item"
    case .cropHandle, .cropTranslationArea:
        reason = "crop item"
    case .selectionHandle:
        reason = "resize item"
    case .selectedItemBody:
        reason = "move item"
    case .unselectedItemBody, .blank:
        return
    }
}
```

### 菜单链路保留旧入口

- `macOS` 的右键菜单仍然调用 `resolveContext(...)`，说明两个入口已经按职责拆开。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleSecondaryClick(at:)
// 功能说明: 修改后 macOS 的菜单链路仍然保留 CanvasContextMenuContext，不会混入 pointer 上下文。
private func handleSecondaryClick(at location: CGPoint) {
    // ... 省略前置同步与日志
    prepareForSecondaryClickContextMenu()

    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}
```

## 验证结果

- 已对以上 5 个代码文件和 1 个新增文件执行 `ReadLints` 检查，当前无 linter 错误。
- 当前代码层面的结构结果是：pointer 主链路走 `CanvasPointerPressContext`，菜单链路走 `CanvasContextMenuContext`，两者共享 `CanvasContextResolver.resolveTarget(...)` 的命中判定核心。
