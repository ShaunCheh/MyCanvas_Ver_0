# 20260318_122027_context_menu_phase3_context_resolver_record

## 记录范围

- 记录内容：
  1. 新增共享上下文模型 `CanvasContextMenuContext`，把菜单/点击/拖拽需要的位置语义统一成共享数据结构。
  2. 新增共享解析器 `CanvasContextResolver`，把 `edit handle -> crop outline -> selected body -> unselected body -> blank` 的命中优先级从平台 controller 中抽出。
  3. 为 `CanvasEditorSession` 增加 `resolveContext(...)` 入口，让 resolver 直接消费 `scene/camera/lastRenderSnapshot/interactionState`。
  4. 让 `iOS/macOS ViewController` 的 pointer down / move / up / history transaction 起点都改为消费 `CanvasContextMenuContext`，不再保留各自的私有 hit test 解析器。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - `CanvasContextMenuState`
  - `CanvasContextMenuHostView`
  - `macOS` secondary click 菜单展示
  - `iOS` long press 菜单展示
  - `CanvasCommandCatalog` / `CanvasCommandExecutor` 的阶段 2 内容
  - `.cursor/plans/上下文菜单分阶段_e62bfffe.plan.md` 的状态同步
  - 原始 gif diff

## 修改一：新增共享上下文模型 `CanvasContextMenuContext`

### 修改前

- 项目里没有“菜单/点击/拖拽共用”的上下文模型。
- 平台层只能在私有枚举里临时表达 `rotateHandle / cropHandle / selectedBody / blank` 等语义，后续上下文菜单无法直接复用。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数名/类型名: 文件原先不存在
// 功能说明: 修改前没有共享上下文模型，位置语义只能留在平台 controller 的私有枚举中。
// before: file did not exist
```

### 修改后

- 新增 `CanvasContextMenuTargetKind`，统一表达位置命中的语义目标。
- 新增 `CanvasContextMenuContext`，统一携带 viewport/world 坐标、目标 item、anchor、当前 selectedItem 和 crop 状态。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数名/类型名: CanvasContextMenuTargetKind / CanvasContextMenuContext
// 功能说明: 修改后新增共享上下文模型，为点击、拖拽和后续上下文菜单提供统一语义载体。
import CoreGraphics
import Foundation

enum CanvasContextMenuTargetKind {
    case rotateHandle
    case cropHandle(role: CanvasCropHandleRole)
    case cropOutline
    case selectionHandle(role: CanvasSelectionHandleRole)
    case selectedItemBody
    case unselectedItemBody
    case blank

    var isEditHandle: Bool {
        switch self {
        case .rotateHandle, .cropHandle, .selectionHandle:
            return true
        case .cropOutline, .selectedItemBody, .unselectedItemBody, .blank:
            return false
        }
    }
}

struct CanvasContextMenuContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasContextMenuTargetKind
    let targetItemID: CanvasImageItemID?
    let anchorRect: CGRect?
    let selectedItemID: CanvasImageItemID?
    let isInlineEditModeActive: Bool
    let isInlineCropModeActive: Bool

    var anchorPoint: CGPoint {
        guard let anchorRect else {
            return invocationViewportPoint
        }

        return CGPoint(
            x: anchorRect.midX,
            y: anchorRect.midY
        )
    }
}
```

## 修改二：新增共享解析器 `CanvasContextResolver`

### 修改前

- `iOS/macOS ViewController` 各自维护一套几乎相同的 `hitTestItemID()`、`hitTestEditHandle()`、`hitTestCropOutline()`、`pointerPressTarget(at:)`。
- 命中优先级虽然一致，但实现被复制在两端，后续菜单如果继续复用只会再复制第三遍。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: hitTestItemID(at:) / hitTestEditHandle(at:) / hitTestCropOutline(at:) / pointerPressTarget(at:)
// 功能说明: 修改前 iOS controller 自己维护位置语义解析和命中优先级；macOS 也有一份几乎相同的实现。
private func hitTestItemID(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    scene.topmostItemID(
        containing: camera.viewportToWorld(viewportLocation)
    )
}

private func hitTestEditHandle(at viewportLocation: CGPoint) -> EditHandleHit? {
    guard let editOverlay = lastRenderSnapshot.editOverlay else {
        return nil
    }

    switch editOverlay.kind {
    case .crop:
        guard
            let handle = editOverlay.handles.first(where: { handle in
                Self.cropHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = handle.role.cropHandleRole
        else {
            return nil
        }

        return .crop(role: role, itemID: editOverlay.itemID)
    case .selection:
        guard
            case let .selection(payload) = editOverlay.payload
        else {
            return nil
        }

        if Self.rotateHandleHitRect(centeredAt: payload.rotateAffordance.handle.screenCenter)
            .contains(viewportLocation)
        {
            return .rotate(itemID: editOverlay.itemID)
        }

        guard
            let handle = editOverlay.handles.first(where: { handle in
                Self.selectionHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = handle.role.selectionHandleRole
        else {
            return nil
        }

        return .resize(role: role, itemID: editOverlay.itemID)
    }
}

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let editHandleHit = hitTestEditHandle(at: viewportLocation) {
        return editHandleHit.pressTarget
    }

    if let cropOutlineItemID = hitTestCropOutline(at: viewportLocation) {
        return .cropOutline(itemID: cropOutlineItemID)
    }

    if isInlineEditModeActive {
        return .blank
    }

    guard let itemID = hitTestItemID(at: viewportLocation) else {
        return .blank
    }

    if itemID == interactionState.selectedItemID {
        return .selectedBody(itemID: itemID)
    }

    return .unselectedItem(itemID: itemID)
}
```

### 修改后

- 新增 `CanvasContextResolverMetrics`，把平台差异参数从 controller 注入进来。
- 新增 `CanvasContextResolver`，统一解析 `edit handle / crop outline / selected body / unselected body / blank`。
- `anchorRect` 优先从 overlay / item 的 screen quad 推导，为后续菜单定位直接提供锚点。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名/类型名: CanvasContextResolverMetrics / CanvasContextResolver.resolveContext(...) / resolveEditHandleTarget(...) / resolveCropOutlineTarget(...)
// 功能说明: 修改后新增共享解析器，把位置命中优先级和 anchor 解析从平台 controller 中抽离。
import CoreGraphics
import Foundation

struct CanvasContextResolverMetrics {
    let selectionHandleHitTargetSize: CGFloat
    let cropHandleHitTargetSize: CGFloat
    let cropOutlineHitTargetWidth: CGFloat
    let rotateHandleHitTargetSize: CGFloat
}

struct CanvasContextResolver {
    func resolveContext(
        at viewportPoint: CGPoint,
        scene: CanvasScene,
        camera: CanvasCamera,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemID: CanvasImageItemID?,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasContextMenuContext {
        let invocationWorldPoint = camera.viewportToWorld(viewportPoint)

        if let resolvedTarget = resolveEditHandleTarget(
            at: viewportPoint,
            renderSnapshot: renderSnapshot,
            interactionMetrics: interactionMetrics
        ) {
            return makeContext(
                viewportPoint: viewportPoint,
                worldPoint: invocationWorldPoint,
                resolvedTarget: resolvedTarget,
                selectedItemID: selectedItemID,
                isInlineEditModeActive: isInlineEditModeActive,
                isInlineCropModeActive: isInlineCropModeActive
            )
        }

        if let resolvedTarget = resolveCropOutlineTarget(
            at: viewportPoint,
            renderSnapshot: renderSnapshot,
            interactionMetrics: interactionMetrics
        ) {
            return makeContext(
                viewportPoint: viewportPoint,
                worldPoint: invocationWorldPoint,
                resolvedTarget: resolvedTarget,
                selectedItemID: selectedItemID,
                isInlineEditModeActive: isInlineEditModeActive,
                isInlineCropModeActive: isInlineCropModeActive
            )
        }

        if isInlineEditModeActive {
            return makeContext(
                viewportPoint: viewportPoint,
                worldPoint: invocationWorldPoint,
                resolvedTarget: ResolvedTarget(targetKind: .blank),
                selectedItemID: selectedItemID,
                isInlineEditModeActive: isInlineEditModeActive,
                isInlineCropModeActive: isInlineCropModeActive
            )
        }

        guard let itemID = scene.topmostItemID(containing: invocationWorldPoint) else {
            return makeContext(
                viewportPoint: viewportPoint,
                worldPoint: invocationWorldPoint,
                resolvedTarget: ResolvedTarget(targetKind: .blank),
                selectedItemID: selectedItemID,
                isInlineEditModeActive: isInlineEditModeActive,
                isInlineCropModeActive: isInlineCropModeActive
            )
        }

        let targetKind: CanvasContextMenuTargetKind =
            itemID == selectedItemID ? .selectedItemBody : .unselectedItemBody

        return makeContext(
            viewportPoint: viewportPoint,
            worldPoint: invocationWorldPoint,
            resolvedTarget: ResolvedTarget(
                targetKind: targetKind,
                targetItemID: itemID,
                anchorRect: itemAnchorRect(
                    for: itemID,
                    renderSnapshot: renderSnapshot
                )
            ),
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive
        )
    }

    private func resolveEditHandleTarget(
        at viewportPoint: CGPoint,
        renderSnapshot: CanvasRenderSnapshot,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> ResolvedTarget? {
        guard let editOverlay = renderSnapshot.editOverlay else {
            return nil
        }

        switch editOverlay.kind {
        case .crop:
            for handle in editOverlay.handles {
                guard let role = handle.role.cropHandleRole else {
                    continue
                }

                let hitRect = rect(
                    centeredAt: handle.screenCenter,
                    size: interactionMetrics.cropHandleHitTargetSize
                )
                if hitRect.contains(viewportPoint) {
                    return ResolvedTarget(
                        targetKind: .cropHandle(role: role),
                        targetItemID: editOverlay.itemID,
                        anchorRect: hitRect
                    )
                }
            }
        case .selection:
            guard case let .selection(payload) = editOverlay.payload else {
                return nil
            }

            let rotateHitRect = rect(
                centeredAt: payload.rotateAffordance.handle.screenCenter,
                size: interactionMetrics.rotateHandleHitTargetSize
            )
            if rotateHitRect.contains(viewportPoint) {
                return ResolvedTarget(
                    targetKind: .rotateHandle,
                    targetItemID: editOverlay.itemID,
                    anchorRect: rotateHitRect
                )
            }

            for handle in editOverlay.handles {
                guard let role = handle.role.selectionHandleRole else {
                    continue
                }

                let hitRect = rect(
                    centeredAt: handle.screenCenter,
                    size: interactionMetrics.selectionHandleHitTargetSize
                )
                if hitRect.contains(viewportPoint) {
                    return ResolvedTarget(
                        targetKind: .selectionHandle(role: role),
                        targetItemID: editOverlay.itemID,
                        anchorRect: hitRect
                    )
                }
            }
        }

        return nil
    }

    private func resolveCropOutlineTarget(
        at viewportPoint: CGPoint,
        renderSnapshot: CanvasRenderSnapshot,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> ResolvedTarget? {
        guard
            let editOverlay = renderSnapshot.editOverlay,
            case let .crop(payload) = editOverlay.payload
        else {
            return nil
        }

        for (start, end) in quadEdges(for: payload.cropScreenQuad) {
            if distance(
                from: viewportPoint,
                toSegmentStart: start,
                segmentEnd: end
            ) <= (interactionMetrics.cropOutlineHitTargetWidth / 2) {
                return ResolvedTarget(
                    targetKind: .cropOutline,
                    targetItemID: editOverlay.itemID,
                    anchorRect: payload.cropScreenQuad.boundingRect.standardized
                )
            }
        }

        return nil
    }

    // ... 省略 makeContext / itemAnchorRect / rect / quadEdges / distance 等辅助函数，实际代码已写入文件
}
```

## 修改三：`CanvasEditorSession` 增加共享上下文解析入口

### 修改前

- `CanvasEditorSession` 只负责 snapshot、history、save 和 command 相关会话能力。
- 位置语义解析仍然停留在平台 controller 中，session 没法直接输出“这个点命中了什么”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: renderer / miniMapRenderer / makeCanvasSnapshot() / makeMiniMapSnapshot()
// 功能说明: 修改前 session 还没有 resolver，也没有对外的 resolveContext(...) 能力。
private let renderer = CanvasRenderer()
private let miniMapRenderer = CanvasMiniMapRenderer()
private let saveCoordinator: BoardSaveCoordinator
private let historyController = BoardHistoryController()

func makeCanvasSnapshot() -> CanvasRenderSnapshot {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    )
    lastRenderSnapshot = snapshot
    return snapshot
}

func makeMiniMapSnapshot() -> CanvasMiniMapSnapshot {
    miniMapRenderer.makeSnapshot(
        context: CanvasMiniMapRenderContext(
            scene: scene,
            boardState: boardState,
            camera: camera,
            imageInlineEditState: inlineEditState,
            imageRotationPreviewState: rotationPreviewState
        )
    )
}
```

### 修改后

- `CanvasEditorSession` 直接持有 `CanvasContextResolver`。
- 通过 `resolveContext(...)` 把 `scene/camera/lastRenderSnapshot/interactionState` 统一喂给共享解析器。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: contextResolver / resolveContext(at:interactionMetrics:)
// 功能说明: 修改后 session 成为平台层访问共享上下文解析器的唯一入口。
private let renderer = CanvasRenderer()
private let miniMapRenderer = CanvasMiniMapRenderer()
private let contextResolver = CanvasContextResolver()
private let saveCoordinator: BoardSaveCoordinator
private let historyController = BoardHistoryController()

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

## 修改四：`iOSViewController` 从私有 hit test 切到共享 resolver

### 修改前

- `iOS` 自己维护 `PointerPressTarget`、`EditHandleHit` 和一整套几何辅助函数。
- `pointerDragState.pressed` 保存的是平台私有 press target，`pointer down / move / up` 都只能依赖 controller 私有解析结果。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: PointerPressTarget / EditHandleHit / PointerDragState
// 功能说明: 修改前 iOS controller 自己定义按下语义模型，无法直接复用到共享菜单上下文。
private enum PointerPressTarget {
    case rotateHandle(itemID: CanvasImageItemID)
    case cropHandle(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
    case cropOutline(itemID: CanvasImageItemID)
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank

    var itemID: CanvasImageItemID? {
        switch self {
        case let .rotateHandle(itemID), let .cropHandle(_, itemID), let .cropOutline(itemID), let .handle(_, itemID), let .selectedBody(itemID), let .unselectedItem(itemID):
            return itemID
        case .blank:
            return nil
        }
    }
}

private enum EditHandleHit {
    case rotate(itemID: CanvasImageItemID)
    case crop(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
    case resize(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    // ... 省略其它 drag state
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: handlePrimaryPointerDown(at:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改前 iOS pointer down 直接依赖 controller 私有命中结果，history 起点判断也绑定私有枚举。
private func handlePrimaryPointerDown(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer down \(describe(point: location))")
        return
    }

    let pressTarget = pointerPressTarget(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressTarget: pressTarget
    )
    beginPointerHistoryTransactionIfNeeded(for: pressTarget)
}

private func beginPointerHistoryTransactionIfNeeded(
    for pressTarget: PointerPressTarget
) {
    let reason: String
    switch pressTarget {
    case .rotateHandle:
        reason = "rotate item"
    case .cropHandle, .cropOutline:
        reason = "crop item"
    case .handle:
        reason = "resize item"
    case .selectedBody:
        reason = "move item"
    case .unselectedItem, .blank:
        return
    }

    editorSession.beginHistoryTransaction(reason: reason)
}
```

### 修改后

- `PointerDragState.pressed` 改为持有 `CanvasContextMenuContext`。
- 新增 `contextResolverMetrics`，把 iOS 平台的命中尺寸参数注入给共享 resolver。
- `pointer down / move / up / history transaction` 全部改为使用 `pressContext.targetKind` 和 `pressContext.targetItemID`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: PointerDragState / contextResolverMetrics / resolveContext(at:)
// 功能说明: 修改后 iOS controller 不再自建 press target，而是消费共享上下文模型。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasContextMenuContext
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private var contextResolverMetrics: CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: Self.selectionHandleHitTargetSize,
        cropHandleHitTargetSize: Self.cropHandleHitTargetSize,
        cropOutlineHitTargetWidth: Self.cropOutlineHitTargetWidth,
        rotateHandleHitTargetSize: Self.rotateHandleHitTargetSize
    )
}

private func resolveContext(
    at viewportLocation: CGPoint
) -> CanvasContextMenuContext {
    editorSession.resolveContext(
        at: viewportLocation,
        interactionMetrics: contextResolverMetrics
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: handlePrimaryPointerDown(at:) / handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改后 iOS 的按下、拖拽起点、抬起点击判定和 history 起点都统一走共享 resolver 的结果。
private func handlePrimaryPointerDown(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer down \(describe(point: location))")
        return
    }

    let pressContext = resolveContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext
    )
    beginPointerHistoryTransactionIfNeeded(for: pressContext)
}

private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    // ... 省略 guard 和其他 state
    switch pointerDragState {
    case let .pressed(pressedLocation, pressContext):
        switch pressContext.targetKind {
        case .rotateHandle:
            guard let itemID = pressContext.targetItemID else {
                editorSession.cancelPendingHistoryTransaction()
                pointerDragState = .idle
                return
            }
            // ... 旋转逻辑
        case let .cropHandle(handleRole):
            guard let itemID = pressContext.targetItemID else {
                editorSession.cancelPendingHistoryTransaction()
                pointerDragState = .idle
                return
            }
            // ... crop handle 拖拽逻辑
        case .cropOutline:
            guard let itemID = pressContext.targetItemID else {
                editorSession.cancelPendingHistoryTransaction()
                pointerDragState = .idle
                return
            }
            // ... crop outline 平移逻辑
        case let .selectionHandle(handleRole):
            guard let itemID = pressContext.targetItemID else {
                pointerDragState = .idle
                return
            }
            // ... resize 逻辑
        case .selectedItemBody:
            guard let itemID = pressContext.targetItemID else {
                pointerDragState = .idle
                return
            }
            pointerDragState = .draggingSelectedItem(itemID: itemID)
            moveSelectedItem(withID: itemID, from: pressedLocation, to: location)
        case .unselectedItemBody, .blank:
            pointerDragState = .draggingCanvas
            panCanvas(from: pressedLocation, to: location)
        }
    default:
        break
    }
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    // ... 省略 defer
    switch pointerDragState {
    case let .pressed(_, pressContext):
        let pressedItemID = pressContext.targetItemID
        let releasedContext = resolveContext(at: location)
        let releasedItemID = releasedContext.targetItemID
        let previousSelectedItemID = interactionState.selectedItemID

        switch pressContext.targetKind {
        case .rotateHandle, .cropHandle, .cropOutline, .selectionHandle:
            break
        case .selectedItemBody, .unselectedItemBody:
            if let itemID = pressContext.targetItemID,
               releasedItemID == itemID
            {
                selectItem(
                    withID: itemID,
                    recordHistory: true
                )
            }
        case .blank:
            if releasedItemID == nil {
                clearSelectionIfNeeded(recordHistory: true)
            }
        }

        _ = pressedItemID
        _ = previousSelectedItemID
    default:
        break
    }
}

private func beginPointerHistoryTransactionIfNeeded(
    for pressContext: CanvasContextMenuContext
) {
    let reason: String
    switch pressContext.targetKind {
    case .rotateHandle:
        reason = "rotate item"
    case .cropHandle, .cropOutline:
        reason = "crop item"
    case .selectionHandle:
        reason = "resize item"
    case .selectedItemBody:
        reason = "move item"
    case .unselectedItemBody, .blank:
        return
    }

    editorSession.beginHistoryTransaction(reason: reason)
}
```

## 修改五：`macOSViewController` 同步切到共享 resolver

### 修改前

- `macOS` 也维护了一套和 iOS 对称的 `PointerPressTarget / EditHandleHit / hitTest... / pointerPressTarget`。
- 命中尺寸虽然不同，但解析流程和优先级判断完全重复。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: PointerDragState / handlePrimaryPointerDown(at:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改前 macOS controller 同样直接持有私有 press target 和命中解析链，无法与 iOS 共享位置语义。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    // ... 省略其它 drag state
}

private func handlePrimaryPointerDown(at location: CGPoint) {
    let pressTarget = pointerPressTarget(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressTarget: pressTarget
    )
    beginPointerHistoryTransactionIfNeeded(for: pressTarget)
}

private func beginPointerHistoryTransactionIfNeeded(
    for pressTarget: PointerPressTarget
) {
    let reason: String
    switch pressTarget {
    case .rotateHandle:
        reason = "rotate item"
    case .cropHandle, .cropOutline:
        reason = "crop item"
    case .handle:
        reason = "resize item"
    case .selectedBody:
        reason = "move item"
    case .unselectedItem, .blank:
        return
    }

    editorSession.beginHistoryTransaction(reason: reason)
}
```

### 修改后

- `macOS` 同样改为使用 `CanvasContextMenuContext`。
- 通过 macOS 自己的 hit target 尺寸注入 `CanvasContextResolverMetrics`，但解析逻辑本体已经和 iOS 共享。
- `pointer down / move / up / history transaction` 全部统一读取 `pressContext.targetKind`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: PointerDragState / contextResolverMetrics / resolveContext(at:)
// 功能说明: 修改后 macOS controller 和 iOS 一样，只保留平台参数注入与平台事件桥接。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasContextMenuContext
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private var contextResolverMetrics: CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: Self.selectionHandleHitTargetSize,
        cropHandleHitTargetSize: Self.cropHandleHitTargetSize,
        cropOutlineHitTargetWidth: Self.cropOutlineHitTargetWidth,
        rotateHandleHitTargetSize: Self.rotateHandleHitTargetSize
    )
}

private func resolveContext(
    at viewportLocation: CGPoint
) -> CanvasContextMenuContext {
    editorSession.resolveContext(
        at: viewportLocation,
        interactionMetrics: contextResolverMetrics
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: handlePrimaryPointerDown(at:) / handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:) / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改后 macOS 的交互入口与 iOS 共用同一套位置语义模型和命中优先级。
private func handlePrimaryPointerDown(at location: CGPoint) {
    let pressContext = resolveContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext
    )
    beginPointerHistoryTransactionIfNeeded(for: pressContext)
}

private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    switch pointerDragState {
    case let .pressed(pressedLocation, pressContext):
        switch pressContext.targetKind {
        case .rotateHandle:
            guard let itemID = pressContext.targetItemID else {
                editorSession.cancelPendingHistoryTransaction()
                pointerDragState = .idle
                return
            }
            // ... 旋转逻辑
        case let .cropHandle(handleRole):
            guard let itemID = pressContext.targetItemID else {
                editorSession.cancelPendingHistoryTransaction()
                pointerDragState = .idle
                return
            }
            // ... crop handle 拖拽逻辑
        case .cropOutline:
            guard let itemID = pressContext.targetItemID else {
                editorSession.cancelPendingHistoryTransaction()
                pointerDragState = .idle
                return
            }
            // ... crop outline 平移逻辑
        case let .selectionHandle(handleRole):
            guard let itemID = pressContext.targetItemID else {
                pointerDragState = .idle
                return
            }
            // ... resize 逻辑
        case .selectedItemBody:
            guard let itemID = pressContext.targetItemID else {
                pointerDragState = .idle
                return
            }
            pointerDragState = .draggingSelectedItem(itemID: itemID)
            moveSelectedItem(withID: itemID, from: pressedLocation, to: location)
        case .unselectedItemBody, .blank:
            pointerDragState = .draggingCanvas
            panCanvas(from: pressedLocation, to: location)
        }
    default:
        break
    }
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    switch pointerDragState {
    case let .pressed(_, pressContext):
        let releasedContext = resolveContext(at: location)
        let releasedItemID = releasedContext.targetItemID

        switch pressContext.targetKind {
        case .selectedItemBody, .unselectedItemBody:
            if let itemID = pressContext.targetItemID,
               releasedItemID == itemID
            {
                selectItem(
                    withID: itemID,
                    recordHistory: true
                )
            }
        case .blank:
            if releasedItemID == nil {
                clearSelectionIfNeeded(recordHistory: true)
            }
        default:
            break
        }
    default:
        break
    }
}

private func beginPointerHistoryTransactionIfNeeded(
    for pressContext: CanvasContextMenuContext
) {
    let reason: String
    switch pressContext.targetKind {
    case .rotateHandle:
        reason = "rotate item"
    case .cropHandle, .cropOutline:
        reason = "crop item"
    case .selectionHandle:
        reason = "resize item"
    case .selectedItemBody:
        reason = "move item"
    case .unselectedItemBody, .blank:
        return
    }

    editorSession.beginHistoryTransaction(reason: reason)
}
```

## 验证结果

- 已通过 `date +"%Y%m%d_%H%M%S"` 获取本记录时间戳：`20260318_122027`
- 已通过 `ReadLints` 检查本次改动文件，无新增 lint 问题
- 已通过 `xcodebuild` 构建验证：
  - `macOS`: `generic/platform=macOS`
  - `iOS`: `generic/platform=iOS`

## 当前阶段结论

- 阶段 3 已把“位置点到了什么”从平台私有逻辑抽成共享能力。
- 当前 `iOS/macOS` 已能对同一位置、同一编辑态产出同构的 `CanvasContextMenuContext`。
- 阶段 4 可以直接基于 `resolvedContext + command descriptors` 构建 `CanvasContextMenuState`，不需要再回头复制命中测试逻辑。
