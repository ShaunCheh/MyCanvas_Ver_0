# 20260316_121542_phase_c_stage3_handle_resize_interaction_record

## 记录范围

- 记录内容：
  1. 将 iOS / macOS controller 的输入状态机从“按下图片 ID”升级为“按压目标”状态机。
  2. 新增 `handle > 图片主体 > 空白` 的命中顺序，并把 handle click / drag 接入现有 pointer 路由。
  3. 基于固定对角点实现四角 handle 的始终等比缩放，并在 resize 后复用现有刷新、扩板与 autosave 链路。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：原始 gif diff、阶段四的 `CanvasScene` 专用 resize API、额外的持久化 schema 变更。

## 修改一：将 controller 输入状态机升级为“按压目标”模型

### 修改前

- `PointerDragState.pressed` 只记录 `pressedItemID` 和 `pressedItemWasSelected`。
- `handlePrimaryPointerDown(at:)` 只会先做一次图片 body 的 hit test，无法区分“点到了选中框四角 handle”还是“点到了图片主体”。
- 这导致 pointer 路由只能在“拖动已选中图片”与“拖动画布”之间二选一，无法为 handle 拖拽单独分出 resize 路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerDragState / handlePrimaryPointerDown(at:)
// 功能说明: 修改前 iOS 只记录 pressedItemID 与 pressedItemWasSelected，无法表达 handle、selectedBody、blank 等不同按压目标。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressedItemID: CanvasImageItemID?,
        pressedItemWasSelected: Bool
    )
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case draggingCanvas
}

private func handlePrimaryPointerDown(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer down \(describe(point: location))")
        return
    }

    let pressedItemID = hitTestItemID(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressedItemID: pressedItemID,
        pressedItemWasSelected: pressedItemID == interactionState.selectedItemID
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: PointerDragState / handlePrimaryPointerDown(at:)
// 功能说明: 修改前 macOS 与 iOS 一样，只知道“按下的是不是已选中图片”，还没有 handle 层级的输入语义。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressedItemID: CanvasImageItemID?,
        pressedItemWasSelected: Bool
    )
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case draggingCanvas
}

private func handlePrimaryPointerDown(at location: CGPoint) {
    let pressedItemID = hitTestItemID(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressedItemID: pressedItemID,
        pressedItemWasSelected: pressedItemID == interactionState.selectedItemID
    )
}
```

### 修改后

- 新增 `PointerPressTarget`，明确区分 `.handle`、`.selectedBody`、`.unselectedItem`、`.blank` 四种按压目标。
- 新增 `PointerResizeState`，把 resize 过程需要的 `itemID`、handle 角色、初始 frame、固定对角点和最小缩放比例打包起来。
- `PointerDragState` 里的 `.pressed` 改为保存 `pressTarget`，并新增 `.resizingSelectedItem(PointerResizeState)`。
- 同时为两端 controller 分别增加 handle 命中热区常量和最小缩放尺寸阈值：iOS 使用更大的 `selectionHandleHitTargetSize` 与 `minimumResizeViewportDimension`，macOS 保持更紧凑的手感。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerPressTarget / PointerResizeState / PointerDragState
// 功能说明: 修改后 iOS 把 handle、图片主体、空白点击都纳入统一按压目标模型，并为 resize 路径准备独立状态。
private enum PointerPressTarget {
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank

    var itemID: CanvasImageItemID? {
        switch self {
        case let .handle(_, itemID), let .selectedBody(itemID), let .unselectedItem(itemID):
            return itemID
        case .blank:
            return nil
        }
    }
}

private struct PointerResizeState {
    let itemID: CanvasImageItemID
    let handleRole: CanvasSelectionHandleRole
    let initialWorldFrame: CGRect
    let fixedOppositeWorldCorner: CGPoint
    let minimumScale: CGFloat
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private static let pointerDragActivationDistance: CGFloat = 4
private static let selectionHandleHitTargetSize: CGFloat = 28
private static let minimumResizeViewportDimension: CGFloat = 28
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: PointerPressTarget / PointerResizeState / PointerDragState
// 功能说明: 修改后 macOS 也切到统一按压目标模型，并保留更适合鼠标交互的较小 handle 热区。
private enum PointerPressTarget {
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank

    var itemID: CanvasImageItemID? {
        switch self {
        case let .handle(_, itemID), let .selectedBody(itemID), let .unselectedItem(itemID):
            return itemID
        case .blank:
            return nil
        }
    }
}

private struct PointerResizeState {
    let itemID: CanvasImageItemID
    let handleRole: CanvasSelectionHandleRole
    let initialWorldFrame: CGRect
    let fixedOppositeWorldCorner: CGPoint
    let minimumScale: CGFloat
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private static let pointerDragActivationDistance: CGFloat = 4
private static let selectionHandleHitTargetSize: CGFloat = 18
private static let minimumResizeViewportDimension: CGFloat = 20
```

## 修改二：将 pointer down / move / up 路由改为 handle 优先

### 修改前

- `handlePrimaryPointerMove(to:from:)` 在超过拖动阈值后，只会在“拖动已选中图片”和“拖动画布”之间切换。
- `handlePrimaryPointerUp(at:)` 也只知道图片 click、空白 click 和 mismatch，完全没有 handle 这一路径。
- 因此即便阶段二已经把四角小方块画出来了，controller 仍然不会把这些可视 handle 识别成独立交互目标。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:)
// 功能说明: 修改前 iOS 只能在 draggingSelectedItem 和 draggingCanvas 之间切换，也没有 handle click 路由。
private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer move \(describe(point: location))")
        return
    }

    switch pointerDragState {
    case let .pressed(pressedLocation, pressedItemID, pressedItemWasSelected):
        guard hasExceededPointerDragActivationDistance(from: pressedLocation, to: location) else {
            return
        }

        if pressedItemWasSelected, let pressedItemID {
            pointerDragState = .draggingSelectedItem(itemID: pressedItemID)
            moveSelectedItem(withID: pressedItemID, from: pressedLocation, to: location)
        } else {
            pointerDragState = .draggingCanvas
            panCanvas(from: pressedLocation, to: location)
        }
    case let .draggingSelectedItem(itemID):
        moveSelectedItem(withID: itemID, from: previousLocation, to: location)
    case .draggingCanvas:
        panCanvas(from: previousLocation, to: location)
    case .idle:
        break
    }
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(_, pressedItemID, _):
        let releasedItemID = hitTestItemID(at: location)
        let previousSelectedItemID = interactionState.selectedItemID
        var clickTarget = "blank"
        var clickResult = "selection_unchanged"
        var affectedItemID: CanvasImageItemID?

        if let pressedItemID, releasedItemID == pressedItemID {
            clickTarget = "image"
            affectedItemID = pressedItemID
            selectItem(withID: pressedItemID)
            if previousSelectedItemID != pressedItemID {
                clickResult = "image_selected"
            }
        } else if pressedItemID == nil, releasedItemID == nil {
            affectedItemID = previousSelectedItemID
            clearSelectionIfNeeded()
            if previousSelectedItemID != nil {
                clickResult = "image_deselected"
            }
        } else {
            clickTarget = "mismatched_hit_test"
            affectedItemID = releasedItemID ?? pressedItemID
        }

        logClickResult(
            target: clickTarget,
            result: clickResult,
            pressedItemID: pressedItemID,
            releasedItemID: releasedItemID,
            previousSelectedItemID: previousSelectedItemID,
            currentSelectedItemID: interactionState.selectedItemID,
            affectedItemID: affectedItemID
        )
    case .draggingSelectedItem, .draggingCanvas, .idle:
        break
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:)
// 功能说明: 修改前 macOS 的 pointer 路由同样没有 handle 分支，拖拽时只会进入移动图片或移动画布。
private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    switch pointerDragState {
    case let .pressed(pressedLocation, pressedItemID, pressedItemWasSelected):
        guard hasExceededPointerDragActivationDistance(from: pressedLocation, to: location) else {
            return
        }

        if pressedItemWasSelected, let pressedItemID {
            pointerDragState = .draggingSelectedItem(itemID: pressedItemID)
            moveSelectedItem(withID: pressedItemID, from: pressedLocation, to: location)
        } else {
            pointerDragState = .draggingCanvas
            panCanvas(from: pressedLocation, to: location)
        }
    case let .draggingSelectedItem(itemID):
        moveSelectedItem(withID: itemID, from: previousLocation, to: location)
    case .draggingCanvas:
        panCanvas(from: previousLocation, to: location)
    case .idle:
        break
    }
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(_, pressedItemID, _):
        let releasedItemID = hitTestItemID(at: location)
        let previousSelectedItemID = interactionState.selectedItemID
        var clickTarget = "blank"
        var clickResult = "selection_unchanged"
        var affectedItemID: CanvasImageItemID?

        if let pressedItemID, releasedItemID == pressedItemID {
            clickTarget = "image"
            affectedItemID = pressedItemID
            selectItem(withID: pressedItemID)
            if previousSelectedItemID != pressedItemID {
                clickResult = "image_selected"
            }
        } else if pressedItemID == nil, releasedItemID == nil {
            affectedItemID = previousSelectedItemID
            clearSelectionIfNeeded()
            if previousSelectedItemID != nil {
                clickResult = "image_deselected"
            }
        } else {
            clickTarget = "mismatched_hit_test"
            affectedItemID = releasedItemID ?? pressedItemID
        }

        logClickResult(
            target: clickTarget,
            result: clickResult,
            pressedItemID: pressedItemID,
            releasedItemID: releasedItemID,
            previousSelectedItemID: previousSelectedItemID,
            currentSelectedItemID: interactionState.selectedItemID,
            affectedItemID: affectedItemID
        )
    case .draggingSelectedItem, .draggingCanvas, .idle:
        break
    }
}
```

### 修改后

- `handlePrimaryPointerDown(at:)` 现在会先通过 `pointerPressTarget(at:)` 得到统一的按压目标。
- `handlePrimaryPointerMove(to:from:)` 在超过阈值后会根据 `pressTarget` 分流：
  - `.handle` 进入 `resizingSelectedItem`
  - `.selectedBody` 进入 `draggingSelectedItem`
  - `.unselectedItem` / `.blank` 继续进入 `draggingCanvas`
- `handlePrimaryPointerUp(at:)` 也新增了 `handle` 这条 click 路径，并保持原有图片选中 / 空白取消选中的 click 日志逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerDown(at:) / handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:)
// 功能说明: 修改后 iOS 以 PointerPressTarget 作为 pointer 路由核心，实现 handle 优先命中和独立 resize 分支。
private func handlePrimaryPointerDown(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer down \(describe(point: location))")
        return
    }

    pointerDragState = .pressed(
        pressedLocation: location,
        pressTarget: pointerPressTarget(at: location)
    )
}

private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer move \(describe(point: location))")
        return
    }

    switch pointerDragState {
    case let .pressed(pressedLocation, pressTarget):
        guard hasExceededPointerDragActivationDistance(from: pressedLocation, to: location) else {
            return
        }

        switch pressTarget {
        case let .handle(handleRole, itemID):
            guard let resizeState = makePointerResizeState(itemID: itemID, handleRole: handleRole) else {
                pointerDragState = .idle
                return
            }

            pointerDragState = .resizingSelectedItem(resizeState)
            resizeSelectedItem(using: resizeState, to: location)
        case let .selectedBody(itemID):
            pointerDragState = .draggingSelectedItem(itemID: itemID)
            moveSelectedItem(withID: itemID, from: pressedLocation, to: location)
        case .unselectedItem, .blank:
            pointerDragState = .draggingCanvas
            panCanvas(from: pressedLocation, to: location)
        }
    case let .draggingSelectedItem(itemID):
        moveSelectedItem(withID: itemID, from: previousLocation, to: location)
    case let .resizingSelectedItem(resizeState):
        resizeSelectedItem(using: resizeState, to: location)
    case .draggingCanvas:
        panCanvas(from: previousLocation, to: location)
    case .idle:
        break
    }
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(_, pressTarget):
        let pressedItemID = pressTarget.itemID
        let releasedHandleHit = hitTestSelectionHandle(at: location)
        let releasedItemID = hitTestItemID(at: location) ?? releasedHandleHit?.itemID
        let previousSelectedItemID = interactionState.selectedItemID
        var clickTarget = "blank"
        var clickResult = "selection_unchanged"
        var affectedItemID: CanvasImageItemID?

        switch pressTarget {
        case let .handle(_, itemID):
            clickTarget = "handle"
            affectedItemID = itemID
        case let .selectedBody(itemID), let .unselectedItem(itemID):
            if releasedItemID == itemID {
                clickTarget = "image"
                affectedItemID = itemID
                selectItem(withID: itemID)
                if previousSelectedItemID != itemID {
                    clickResult = "image_selected"
                }
            } else {
                clickTarget = "mismatched_hit_test"
                affectedItemID = releasedItemID ?? itemID
            }
        case .blank:
            if releasedItemID == nil {
                affectedItemID = previousSelectedItemID
                clearSelectionIfNeeded()
                if previousSelectedItemID != nil {
                    clickResult = "image_deselected"
                }
            } else {
                clickTarget = "mismatched_hit_test"
                affectedItemID = releasedItemID
            }
        }

        logClickResult(
            target: clickTarget,
            result: clickResult,
            pressedItemID: pressedItemID,
            releasedItemID: releasedItemID,
            previousSelectedItemID: previousSelectedItemID,
            currentSelectedItemID: interactionState.selectedItemID,
            affectedItemID: affectedItemID
        )
    case .draggingSelectedItem, .resizingSelectedItem, .draggingCanvas, .idle:
        break
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerDown(at:) / handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:)
// 功能说明: 修改后 macOS 与 iOS 保持同构的 pointer 路由，增加 handle click / drag 分支并保留原有图片与空白点击语义。
private func handlePrimaryPointerDown(at location: CGPoint) {
    pointerDragState = .pressed(
        pressedLocation: location,
        pressTarget: pointerPressTarget(at: location)
    )
}

private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    switch pointerDragState {
    case let .pressed(pressedLocation, pressTarget):
        guard hasExceededPointerDragActivationDistance(from: pressedLocation, to: location) else {
            return
        }

        switch pressTarget {
        case let .handle(handleRole, itemID):
            guard let resizeState = makePointerResizeState(itemID: itemID, handleRole: handleRole) else {
                pointerDragState = .idle
                return
            }

            pointerDragState = .resizingSelectedItem(resizeState)
            resizeSelectedItem(using: resizeState, to: location)
        case let .selectedBody(itemID):
            pointerDragState = .draggingSelectedItem(itemID: itemID)
            moveSelectedItem(withID: itemID, from: pressedLocation, to: location)
        case .unselectedItem, .blank:
            pointerDragState = .draggingCanvas
            panCanvas(from: pressedLocation, to: location)
        }
    case let .draggingSelectedItem(itemID):
        moveSelectedItem(withID: itemID, from: previousLocation, to: location)
    case let .resizingSelectedItem(resizeState):
        resizeSelectedItem(using: resizeState, to: location)
    case .draggingCanvas:
        panCanvas(from: previousLocation, to: location)
    case .idle:
        break
    }
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(_, pressTarget):
        let pressedItemID = pressTarget.itemID
        let releasedHandleHit = hitTestSelectionHandle(at: location)
        let releasedItemID = hitTestItemID(at: location) ?? releasedHandleHit?.itemID
        let previousSelectedItemID = interactionState.selectedItemID
        var clickTarget = "blank"
        var clickResult = "selection_unchanged"
        var affectedItemID: CanvasImageItemID?

        switch pressTarget {
        case let .handle(_, itemID):
            clickTarget = "handle"
            affectedItemID = itemID
        case let .selectedBody(itemID), let .unselectedItem(itemID):
            if releasedItemID == itemID {
                clickTarget = "image"
                affectedItemID = itemID
                selectItem(withID: itemID)
                if previousSelectedItemID != itemID {
                    clickResult = "image_selected"
                }
            } else {
                clickTarget = "mismatched_hit_test"
                affectedItemID = releasedItemID ?? itemID
            }
        case .blank:
            if releasedItemID == nil {
                affectedItemID = previousSelectedItemID
                clearSelectionIfNeeded()
                if previousSelectedItemID != nil {
                    clickResult = "image_deselected"
                }
            } else {
                clickTarget = "mismatched_hit_test"
                affectedItemID = releasedItemID
            }
        }

        logClickResult(
            target: clickTarget,
            result: clickResult,
            pressedItemID: pressedItemID,
            releasedItemID: releasedItemID,
            previousSelectedItemID: previousSelectedItemID,
            currentSelectedItemID: interactionState.selectedItemID,
            affectedItemID: affectedItemID
        )
    case .draggingSelectedItem, .resizingSelectedItem, .draggingCanvas, .idle:
        break
    }
}
```

## 修改三：补充 handle hit test 与等比缩放几何 helper

### 修改前

- controller 只有 `hitTestItemID(at:)` 和 `moveSelectedItem(...)`，还没有针对 handle 的命中检测。
- 缩放几何也尚不存在，controller 不能根据 pointer 的当前位置与固定对角点重新计算新的 `center + size`。
- 因此选中框四角虽然已经画在 viewport 上，但还只是视觉元素，没有和场景更新逻辑连起来。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: hitTestItemID(at:) / moveSelectedItem(withID:from:to:)
// 功能说明: 修改前 iOS 只有图片 body hit test 和移动图片逻辑，还没有 handle hit test 与 resize helper。
private func hitTestItemID(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    lastRenderSnapshot.items
        .reversed()
        .first(where: { $0.screenFrame.contains(viewportLocation) })?
        .id
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    let previousWorldLocation = camera.viewportToWorld(previousLocation)
    let currentWorldLocation = camera.viewportToWorld(location)
    let deltaInWorld = CGPoint(
        x: currentWorldLocation.x - previousWorldLocation.x,
        y: currentWorldLocation.y - previousWorldLocation.y
    )
    guard deltaInWorld != .zero else {
        return
    }

    scene.moveItem(withID: itemID, by: deltaInWorld)
    if let movedItem = scene.item(withID: itemID) {
        expandBoardIfNeeded(toInclude: movedItem.worldFrame)
    }
    requestCanvasRefresh(reason: "move selected item by \(describe(point: deltaInWorld))")
    scheduleAutosave(reason: "move item")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: hitTestItemID(at:) / moveSelectedItem(withID:from:to:)
// 功能说明: 修改前 macOS 也只有图片 body hit test 与 move item，没有 handle 命中和等比 resize 几何。
private func hitTestItemID(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    lastRenderSnapshot.items
        .reversed()
        .first(where: { $0.screenFrame.contains(viewportLocation) })?
        .id
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    let previousWorldLocation = camera.viewportToWorld(previousLocation)
    let currentWorldLocation = camera.viewportToWorld(location)
    let deltaInWorld = CGPoint(
        x: currentWorldLocation.x - previousWorldLocation.x,
        y: currentWorldLocation.y - previousWorldLocation.y
    )
    guard deltaInWorld != .zero else {
        return
    }

    scene.moveItem(withID: itemID, by: deltaInWorld)
    if let movedItem = scene.item(withID: itemID) {
        expandBoardIfNeeded(toInclude: movedItem.worldFrame)
    }
    refreshCanvas()
    scheduleAutosave(reason: "move item")
}
```

### 修改后

- 新增 `hitTestSelectionHandle(at:)` 与 `pointerPressTarget(at:)`，controller 会优先根据 `lastRenderSnapshot.selectionOverlay.handles` 做 handle hit test。
- 新增 `makePointerResizeState(...)`、`resizeSelectedItem(...)`、`makeResizedWorldFrame(...)` 等一组 resize helper：
  - 先根据当前选中项 world frame 找到固定对角点
  - 再用拖拽中的 world corner 计算宽高缩放比例
  - 最终用同一个 `scale` 同步放大宽高，保证始终等比缩放
- resize 完成后继续复用现有链路：更新 scene item、必要时扩板、刷新画布、触发 autosave。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: hitTestSelectionHandle(at:) / pointerPressTarget(at:) / makePointerResizeState(itemID:handleRole:) / resizeSelectedItem(using:to:) / makeResizedWorldFrame(using:draggedViewportLocation:)
// 功能说明: 修改后 iOS 新增 handle hit test 与等比缩放几何 helper，并在 resize 后沿用现有 refresh + autosave 链路。
private func hitTestSelectionHandle(at viewportLocation: CGPoint) -> (role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)? {
    guard let selectionOverlay = lastRenderSnapshot.selectionOverlay else {
        return nil
    }

    return selectionOverlay.handles.first(where: { handle in
        Self.selectionHandleHitRect(centeredAt: handle.screenCenter).contains(viewportLocation)
    }).map { handle in
        (role: handle.role, itemID: selectionOverlay.itemID)
    }
}

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }

    guard let itemID = hitTestItemID(at: viewportLocation) else {
        return .blank
    }

    if itemID == interactionState.selectedItemID {
        return .selectedBody(itemID: itemID)
    }

    return .unselectedItem(itemID: itemID)
}

private func makePointerResizeState(
    itemID: CanvasImageItemID,
    handleRole: CanvasSelectionHandleRole
) -> PointerResizeState? {
    guard let item = scene.item(withID: itemID) else {
        return nil
    }

    let initialWorldFrame = item.worldFrame.standardized
    guard initialWorldFrame.width > 0, initialWorldFrame.height > 0 else {
        return nil
    }

    let minimumWorldDimension = Self.minimumResizeViewportDimension / camera.zoomScale
    let minimumScale = max(
        minimumWorldDimension / initialWorldFrame.width,
        minimumWorldDimension / initialWorldFrame.height
    )

    return PointerResizeState(
        itemID: itemID,
        handleRole: handleRole,
        initialWorldFrame: initialWorldFrame,
        fixedOppositeWorldCorner: fixedOppositeWorldCorner(for: handleRole, in: initialWorldFrame),
        minimumScale: minimumScale
    )
}

private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedWorldFrame = makeResizedWorldFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        var item = scene.item(withID: resizeState.itemID)
    else {
        return
    }

    guard item.worldFrame.standardized != resizedWorldFrame else {
        return
    }

    item.center = CGPoint(x: resizedWorldFrame.midX, y: resizedWorldFrame.midY)
    item.size = resizedWorldFrame.size
    scene.upsert(item)
    expandBoardIfNeeded(toInclude: resizedWorldFrame)
    requestCanvasRefresh(reason: "resize selected item to \(describe(rect: resizedWorldFrame))")
    scheduleAutosave(reason: "resize item")
}

private func makeResizedWorldFrame(
    using resizeState: PointerResizeState,
    draggedViewportLocation: CGPoint
) -> CGRect? {
    let minimumWidth = resizeState.initialWorldFrame.width * resizeState.minimumScale
    let minimumHeight = resizeState.initialWorldFrame.height * resizeState.minimumScale
    let draggedWorldCorner = constrainedDraggedWorldCorner(
        camera.viewportToWorld(draggedViewportLocation),
        for: resizeState.handleRole,
        oppositeCorner: resizeState.fixedOppositeWorldCorner,
        minimumWidth: minimumWidth,
        minimumHeight: minimumHeight
    )

    let widthScale = abs(draggedWorldCorner.x - resizeState.fixedOppositeWorldCorner.x) / resizeState.initialWorldFrame.width
    let heightScale = abs(draggedWorldCorner.y - resizeState.fixedOppositeWorldCorner.y) / resizeState.initialWorldFrame.height
    let scale = max(widthScale, heightScale, resizeState.minimumScale)
    guard scale.isFinite else {
        return nil
    }

    let resizedSize = CGSize(
        width: resizeState.initialWorldFrame.width * scale,
        height: resizeState.initialWorldFrame.height * scale
    )

    return worldFrame(
        for: resizeState.handleRole,
        withFixedOppositeCorner: resizeState.fixedOppositeWorldCorner,
        size: resizedSize
    )
}

private static func selectionHandleHitRect(centeredAt center: CGPoint) -> CGRect {
    CGRect(
        x: center.x - selectionHandleHitTargetSize / 2,
        y: center.y - selectionHandleHitTargetSize / 2,
        width: selectionHandleHitTargetSize,
        height: selectionHandleHitTargetSize
    ).standardized
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: hitTestSelectionHandle(at:) / pointerPressTarget(at:) / makePointerResizeState(itemID:handleRole:) / resizeSelectedItem(using:to:) / makeResizedWorldFrame(using:draggedViewportLocation:)
// 功能说明: 修改后 macOS 同步新增 handle hit test 与等比 resize helper，并在 refreshCanvas() 后复用 autosave。
private func hitTestSelectionHandle(at viewportLocation: CGPoint) -> (role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)? {
    guard let selectionOverlay = lastRenderSnapshot.selectionOverlay else {
        return nil
    }

    return selectionOverlay.handles.first(where: { handle in
        Self.selectionHandleHitRect(centeredAt: handle.screenCenter).contains(viewportLocation)
    }).map { handle in
        (role: handle.role, itemID: selectionOverlay.itemID)
    }
}

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }

    guard let itemID = hitTestItemID(at: viewportLocation) else {
        return .blank
    }

    if itemID == interactionState.selectedItemID {
        return .selectedBody(itemID: itemID)
    }

    return .unselectedItem(itemID: itemID)
}

private func makePointerResizeState(
    itemID: CanvasImageItemID,
    handleRole: CanvasSelectionHandleRole
) -> PointerResizeState? {
    guard let item = scene.item(withID: itemID) else {
        return nil
    }

    let initialWorldFrame = item.worldFrame.standardized
    guard initialWorldFrame.width > 0, initialWorldFrame.height > 0 else {
        return nil
    }

    let minimumWorldDimension = Self.minimumResizeViewportDimension / camera.zoomScale
    let minimumScale = max(
        minimumWorldDimension / initialWorldFrame.width,
        minimumWorldDimension / initialWorldFrame.height
    )

    return PointerResizeState(
        itemID: itemID,
        handleRole: handleRole,
        initialWorldFrame: initialWorldFrame,
        fixedOppositeWorldCorner: fixedOppositeWorldCorner(for: handleRole, in: initialWorldFrame),
        minimumScale: minimumScale
    )
}

private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedWorldFrame = makeResizedWorldFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        var item = scene.item(withID: resizeState.itemID)
    else {
        return
    }

    guard item.worldFrame.standardized != resizedWorldFrame else {
        return
    }

    item.center = CGPoint(x: resizedWorldFrame.midX, y: resizedWorldFrame.midY)
    item.size = resizedWorldFrame.size
    scene.upsert(item)
    expandBoardIfNeeded(toInclude: resizedWorldFrame)
    refreshCanvas()
    scheduleAutosave(reason: "resize item")
}

private func makeResizedWorldFrame(
    using resizeState: PointerResizeState,
    draggedViewportLocation: CGPoint
) -> CGRect? {
    let minimumWidth = resizeState.initialWorldFrame.width * resizeState.minimumScale
    let minimumHeight = resizeState.initialWorldFrame.height * resizeState.minimumScale
    let draggedWorldCorner = constrainedDraggedWorldCorner(
        camera.viewportToWorld(draggedViewportLocation),
        for: resizeState.handleRole,
        oppositeCorner: resizeState.fixedOppositeWorldCorner,
        minimumWidth: minimumWidth,
        minimumHeight: minimumHeight
    )

    let widthScale = abs(draggedWorldCorner.x - resizeState.fixedOppositeWorldCorner.x) / resizeState.initialWorldFrame.width
    let heightScale = abs(draggedWorldCorner.y - resizeState.fixedOppositeWorldCorner.y) / resizeState.initialWorldFrame.height
    let scale = max(widthScale, heightScale, resizeState.minimumScale)
    guard scale.isFinite else {
        return nil
    }

    let resizedSize = CGSize(
        width: resizeState.initialWorldFrame.width * scale,
        height: resizeState.initialWorldFrame.height * scale
    )

    return worldFrame(
        for: resizeState.handleRole,
        withFixedOppositeCorner: resizeState.fixedOppositeWorldCorner,
        size: resizedSize
    )
}

private static func selectionHandleHitRect(centeredAt center: CGPoint) -> CGRect {
    CGRect(
        x: center.x - selectionHandleHitTargetSize / 2,
        y: center.y - selectionHandleHitTargetSize / 2,
        width: selectionHandleHitTargetSize,
        height: selectionHandleHitTargetSize
    ).standardized
}
```

## 结果

- 现在 iOS / macOS 两端都已经可以把四角小方块当成独立交互目标：point down 会优先命中 handle，拖拽时进入始终等比缩放路径。
- 图片主体拖拽、空白拖拽、图片 click 选中、空白 click 取消选中都继续沿用原有路径，只是在状态机里变成了更明确的按压目标分流。
- 这一步仍然没有实现阶段四的 `CanvasScene` 专用 resize API，当前 resize 仍由 controller 内部通过 `scene.upsert(item)` 完成。
