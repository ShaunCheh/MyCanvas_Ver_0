# 20260317_153014_unified_editoverlay_crop_outline_drag_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 中，为 `crop` 模式新增“拖动橙黄色边框移动裁剪框”的输入目标、拖拽状态、边框命中与 local-space 平移求解。
  2. 在 `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 中同步完成同样的边框拖动能力，保持双平台行为对称。
  3. 复用现有 `crop item` 历史事务、`draftCropRectNormalized` 草稿更新与 `commitCropDraftIfNeeded()` 提交流程，不改 shared model / renderer / viewport。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - shared renderer / viewport 结构调整
  - 原始 gif diff
  - git commit / push
  - 逐项手动 UI 回归实测

## 修改一：在 controller 状态机中新增 `cropOutline` 输入目标与边框拖拽状态

### 修改前

- `PointerPressTarget` 只有 `rotateHandle / cropHandle / handle / selectedBody / unselectedItem / blank`。
- `PointerDragState` 只有 `croppingSelectedItem`，没有“移动整个裁剪框”的独立拖拽状态。
- `crop` 只有 handle 命中能进入交互，没有边框拖动语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: PointerPressTarget / PointerCropState / PointerDragState
// 功能说明: 修改前 iOS controller 只区分 crop handle 拖拽，没有 crop outline 的输入目标和拖拽状态。
private enum PointerPressTarget {
    case rotateHandle(itemID: CanvasImageItemID)
    case cropHandle(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank

    var itemID: CanvasImageItemID? {
        switch self {
        case let .rotateHandle(itemID), let .cropHandle(_, itemID), let .handle(_, itemID), let .selectedBody(itemID), let .unselectedItem(itemID):
            return itemID
        case .blank:
            return nil
        }
    }
}

private struct PointerCropState {
    let itemID: CanvasImageItemID
    let handleRole: CanvasCropHandleRole
    let fullImageLocalFrame: CGRect
    let initialLocalFrame: CGRect
    let minimumLocalSize: CGSize
}

private struct PointerRotateState {
    let itemID: CanvasImageItemID
    let referenceCenter: CGPoint
    let rotationOffsetToPointerAngle: CGFloat
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    case croppingSelectedItem(PointerCropState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}
```

### 修改后

- `PointerPressTarget` 新增 `cropOutline(itemID:)`。
- 新增 `PointerCropTranslationState`，保存初始 crop frame、full image frame 和初始 local pointer。
- `PointerDragState` 新增 `movingCropFrame(...)`。
- iOS / macOS 分别新增 `cropOutlineHitTargetWidth`，按平台现有 hit target 尺寸单独调参。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: PointerPressTarget / PointerCropTranslationState / PointerDragState
// 功能说明: 修改后 iOS controller 显式区分 crop outline 输入目标，并为“移动整个裁剪框”引入独立拖拽状态。
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

private struct PointerCropTranslationState {
    let itemID: CanvasImageItemID
    let fullImageLocalFrame: CGRect
    let initialLocalFrame: CGRect
    let initialPointerLocalPoint: CGPoint
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private static let cropHandleHitTargetSize: CGFloat = 28
private static let cropOutlineHitTargetWidth: CGFloat = 20
private static let minimumCropViewportDimension: CGFloat = 28
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: PointerPressTarget / PointerCropTranslationState / PointerDragState
// 功能说明: macOS 侧同步引入 crop outline 输入目标与边框拖拽状态，保持结构与 iOS 对称。
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

private struct PointerCropTranslationState {
    let itemID: CanvasImageItemID
    let fullImageLocalFrame: CGRect
    let initialLocalFrame: CGRect
    let initialPointerLocalPoint: CGPoint
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private static let cropHandleHitTargetSize: CGFloat = 18
private static let cropOutlineHitTargetWidth: CGFloat = 14
private static let minimumCropViewportDimension: CGFloat = 20
```

## 修改二：新增 `crop` 边框命中测试，并把优先级插入到 `handle > crop outline > blank`

### 修改前

- `hitTestEditHandle(at:)` 在 `crop` 模式下只命中 8 个 handle。
- `pointerPressTarget(at:)` 只要当前在 inline edit mode 且没命中 handle，就直接返回 `.blank`。
- 结果是：橙黄色边框虽然已经被 viewport 画出来，但 controller 没有任何方式把它识别为可拖动区域。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: hitTestEditHandle(at:) / pointerPressTarget(at:)
// 功能说明: 修改前 iOS controller 只把 crop 视为“8 个 handle 可交互”；只要不是 handle，inline edit 下就会直接落到 blank。
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
    case .selection, .rotate:
        if
            case let .rotate(payload) = editOverlay.payload,
            Self.rotateHandleHitRect(centeredAt: payload.handle.screenCenter)
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

- 新增 `hitTestCropOutline(at:)`，直接消费 `editOverlay.payload.crop.cropScreenQuad`。
- 新增 `quadEdges(for:)` 和 `distance(from:toSegmentStart:segmentEnd:)`，用 viewport 空间的四条边做线段距离判定。
- `pointerPressTarget(at:)` 改成先判 handle，再判 crop outline，再根据 inline edit fallback 到 `.blank`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: hitTestCropOutline(at:) / pointerPressTarget(at:) / quadEdges(for:) / distance(from:toSegmentStart:segmentEnd:)
// 功能说明: 修改后 iOS controller 在 crop 模式下新增边框命中；只有不在 8 个 handle 内时，橙黄色边框才会成为新的可拖动目标。
private func hitTestCropOutline(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    guard
        let editOverlay = lastRenderSnapshot.editOverlay,
        case let .crop(payload) = editOverlay.payload
    else {
        return nil
    }

    for (start, end) in Self.quadEdges(for: payload.cropScreenQuad) {
        if Self.distance(
            from: viewportLocation,
            toSegmentStart: start,
            segmentEnd: end
        ) <= (Self.cropOutlineHitTargetWidth / 2) {
            return editOverlay.itemID
        }
    }

    return nil
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

private static func quadEdges(
    for quad: CanvasQuad
) -> [(start: CGPoint, end: CGPoint)] {
    [
        (quad.topLeading, quad.topTrailing),
        (quad.topTrailing, quad.bottomTrailing),
        (quad.bottomTrailing, quad.bottomLeading),
        (quad.bottomLeading, quad.topLeading)
    ]
}

private static func distance(
    from point: CGPoint,
    toSegmentStart start: CGPoint,
    segmentEnd end: CGPoint
) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = (dx * dx) + (dy * dy)
    guard lengthSquared > 0 else {
        return hypot(point.x - start.x, point.y - start.y)
    }

    let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
    let clampedProjection = min(max(projection, 0), 1)
    let closestPoint = CGPoint(
        x: start.x + (clampedProjection * dx),
        y: start.y + (clampedProjection * dy)
    )
    return hypot(point.x - closestPoint.x, point.y - closestPoint.y)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: hitTestCropOutline(at:) / pointerPressTarget(at:) / quadEdges(for:) / distance(from:toSegmentStart:segmentEnd:)
// 功能说明: macOS 侧同步在 crop 模式下新增边框命中，优先级与 iOS 保持完全一致。
private func hitTestCropOutline(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    guard
        let editOverlay = lastRenderSnapshot.editOverlay,
        case let .crop(payload) = editOverlay.payload
    else {
        return nil
    }

    for (start, end) in Self.quadEdges(for: payload.cropScreenQuad) {
        if Self.distance(
            from: viewportLocation,
            toSegmentStart: start,
            segmentEnd: end
        ) <= (Self.cropOutlineHitTargetWidth / 2) {
            return editOverlay.itemID
        }
    }

    return nil
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

## 修改三：把 `cropOutline` 接入 pointer move / up / cancel 与 `crop item` 历史事务

### 修改前

- `.pressed` 状态里只有 `cropHandle` 能转成 crop 拖拽。
- `.croppingSelectedItem` 是唯一会走 `commitCropDraftIfNeeded()` 的 crop 拖拽状态。
- `beginPointerHistoryTransactionIfNeeded(for:)` 只有 `.cropHandle` 会开启 `"crop item"` 事务。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:) / handlePrimaryPointerCancel() / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改前 iOS 只有 crop handle 才会进入 crop 拖拽与 crop history 事务，边框本体没有接线入口。
private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    switch pointerDragState {
    case let .pressed(pressedLocation, pressTarget):
        guard hasExceededPointerDragActivationDistance(from: pressedLocation, to: location) else {
            return
        }

        switch pressTarget {
        case let .rotateHandle(itemID):
            guard let rotateState = makePointerRotateState(
                itemID: itemID,
                initialViewportLocation: pressedLocation
            ) else {
                historyController.cancelPendingTransaction()
                pointerDragState = .idle
                return
            }

            pointerDragState = .rotatingSelectedItem(rotateState)
            updateRotationDraft(using: rotateState, to: location)
        case let .cropHandle(handleRole, itemID):
            guard let cropState = makePointerCropState(itemID: itemID, handleRole: handleRole) else {
                historyController.cancelPendingTransaction()
                pointerDragState = .idle
                return
            }

            pointerDragState = .croppingSelectedItem(cropState)
            updateCropDraft(using: cropState, to: location)
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
    case let .croppingSelectedItem(cropState):
        updateCropDraft(using: cropState, to: location)
    case let .rotatingSelectedItem(rotateState):
        updateRotationDraft(using: rotateState, to: location)
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
        if isInlineEditModeActive {
            historyController.cancelPendingTransaction()
            return
        }

        let pressedItemID = pressTarget.itemID
        let releasedHandleHit = hitTestEditHandle(at: location)
        let releasedItemID = hitTestItemID(at: location) ?? releasedHandleHit?.itemID
        let previousSelectedItemID = interactionState.selectedItemID
        var clickTarget = "blank"
        var clickResult = "selection_unchanged"
        var affectedItemID: CanvasImageItemID?

        switch pressTarget {
        case let .rotateHandle(itemID):
            clickTarget = "rotate_handle"
            affectedItemID = itemID
        case let .cropHandle(_, itemID):
            clickTarget = "crop_handle"
            affectedItemID = itemID
        case let .handle(_, itemID):
            clickTarget = "handle"
            affectedItemID = itemID
        case let .selectedBody(itemID), let .unselectedItem(itemID):
            if releasedItemID == itemID {
                clickTarget = "image"
                affectedItemID = itemID
                selectItem(
                    withID: itemID,
                    recordHistory: true
                )
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
                clearSelectionIfNeeded(recordHistory: true)
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
        historyController.cancelPendingTransaction()
    case .rotatingSelectedItem:
        commitRotationDraftIfNeeded()
    case .croppingSelectedItem:
        commitCropDraftIfNeeded()
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    case .resizingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .draggingCanvas, .idle:
        break
    }
}

private func handlePrimaryPointerCancel() {
    switch pointerDragState {
    case .rotatingSelectedItem:
        commitRotationDraftIfNeeded()
    case .croppingSelectedItem:
        commitCropDraftIfNeeded()
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    case .resizingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .pressed, .draggingCanvas, .idle:
        historyController.cancelPendingTransaction()
    }

    pointerDragState = .idle
}

private func beginPointerHistoryTransactionIfNeeded(
    for pressTarget: PointerPressTarget
) {
    let reason: String
    switch pressTarget {
    case .rotateHandle:
        reason = "rotate item"
    case .cropHandle:
        reason = "crop item"
    case .handle:
        reason = "resize item"
    case .selectedBody:
        reason = "move item"
    case .unselectedItem, .blank:
        return
    }

    historyController.beginTransaction(
        from: currentBoardHistorySnapshot(),
        reason: reason
    )
}
```

### 修改后

- `.pressed` 分支新增 `cropOutline`，拖动阈值一过就创建 translation state 并进入 `.movingCropFrame(...)`。
- `.movingCropFrame` 在 move / up / cancel 中都和既有 crop draft 提交流程对齐。
- click logging 也补上了 `crop_outline`，避免日志断层。
- 历史事务把 `.cropOutline` 与 `.cropHandle` 统一归到 `"crop item"`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:) / handlePrimaryPointerCancel() / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改后 iOS 将 crop outline 正式接入 pointer 状态机，并复用现有 crop item 的事务与提交链路。
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
        case let .rotateHandle(itemID):
            guard let rotateState = makePointerRotateState(
                itemID: itemID,
                initialViewportLocation: pressedLocation
            ) else {
                historyController.cancelPendingTransaction()
                pointerDragState = .idle
                return
            }

            pointerDragState = .rotatingSelectedItem(rotateState)
            updateRotationDraft(using: rotateState, to: location)
        case let .cropHandle(handleRole, itemID):
            guard let cropState = makePointerCropState(itemID: itemID, handleRole: handleRole) else {
                historyController.cancelPendingTransaction()
                pointerDragState = .idle
                return
            }

            pointerDragState = .croppingSelectedItem(cropState)
            updateCropDraft(using: cropState, to: location)
        case let .cropOutline(itemID):
            guard let translationState = makePointerCropTranslationState(
                itemID: itemID,
                initialViewportLocation: pressedLocation
            ) else {
                historyController.cancelPendingTransaction()
                pointerDragState = .idle
                return
            }

            pointerDragState = .movingCropFrame(translationState)
            updateTranslatedCropDraft(using: translationState, to: location)
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
    case let .croppingSelectedItem(cropState):
        updateCropDraft(using: cropState, to: location)
    case let .movingCropFrame(translationState):
        updateTranslatedCropDraft(using: translationState, to: location)
    case let .rotatingSelectedItem(rotateState):
        updateRotationDraft(using: rotateState, to: location)
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
        if isInlineEditModeActive {
            historyController.cancelPendingTransaction()
            return
        }

        let pressedItemID = pressTarget.itemID
        let releasedHandleHit = hitTestEditHandle(at: location)
        let releasedItemID = hitTestItemID(at: location) ?? releasedHandleHit?.itemID
        let previousSelectedItemID = interactionState.selectedItemID
        var clickTarget = "blank"
        var clickResult = "selection_unchanged"
        var affectedItemID: CanvasImageItemID?

        switch pressTarget {
        case let .rotateHandle(itemID):
            clickTarget = "rotate_handle"
            affectedItemID = itemID
        case let .cropHandle(_, itemID):
            clickTarget = "crop_handle"
            affectedItemID = itemID
        case let .cropOutline(itemID):
            clickTarget = "crop_outline"
            affectedItemID = itemID
        case let .handle(_, itemID):
            clickTarget = "handle"
            affectedItemID = itemID
        case let .selectedBody(itemID), let .unselectedItem(itemID):
            if releasedItemID == itemID {
                clickTarget = "image"
                affectedItemID = itemID
                selectItem(
                    withID: itemID,
                    recordHistory: true
                )
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
                clearSelectionIfNeeded(recordHistory: true)
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
        historyController.cancelPendingTransaction()
    case .rotatingSelectedItem:
        commitRotationDraftIfNeeded()
    case .croppingSelectedItem, .movingCropFrame:
        commitCropDraftIfNeeded()
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    case .resizingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .draggingCanvas, .idle:
        break
    }
}

private func handlePrimaryPointerCancel() {
    switch pointerDragState {
    case .rotatingSelectedItem:
        commitRotationDraftIfNeeded()
    case .croppingSelectedItem, .movingCropFrame:
        commitCropDraftIfNeeded()
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    case .resizingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .pressed, .draggingCanvas, .idle:
        historyController.cancelPendingTransaction()
    }

    pointerDragState = .idle
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

    historyController.beginTransaction(
        from: currentBoardHistorySnapshot(),
        reason: reason
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:) / handlePrimaryPointerCancel() / beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: macOS 侧同步把 crop outline 接入 pointer 状态机与 crop item 历史事务，保证双平台交互一致。
private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    switch pointerDragState {
    case let .pressed(pressedLocation, pressTarget):
        guard hasExceededPointerDragActivationDistance(from: pressedLocation, to: location) else {
            return
        }

        switch pressTarget {
        case let .rotateHandle(itemID):
            guard let rotateState = makePointerRotateState(
                itemID: itemID,
                initialViewportLocation: pressedLocation
            ) else {
                historyController.cancelPendingTransaction()
                pointerDragState = .idle
                return
            }

            pointerDragState = .rotatingSelectedItem(rotateState)
            updateRotationDraft(using: rotateState, to: location)
        case let .cropHandle(handleRole, itemID):
            guard let cropState = makePointerCropState(itemID: itemID, handleRole: handleRole) else {
                historyController.cancelPendingTransaction()
                pointerDragState = .idle
                return
            }

            pointerDragState = .croppingSelectedItem(cropState)
            updateCropDraft(using: cropState, to: location)
        case let .cropOutline(itemID):
            guard let translationState = makePointerCropTranslationState(
                itemID: itemID,
                initialViewportLocation: pressedLocation
            ) else {
                historyController.cancelPendingTransaction()
                pointerDragState = .idle
                return
            }

            pointerDragState = .movingCropFrame(translationState)
            updateTranslatedCropDraft(using: translationState, to: location)
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
    case let .croppingSelectedItem(cropState):
        updateCropDraft(using: cropState, to: location)
    case let .movingCropFrame(translationState):
        updateTranslatedCropDraft(using: translationState, to: location)
    case let .rotatingSelectedItem(rotateState):
        updateRotationDraft(using: rotateState, to: location)
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

    historyController.beginTransaction(
        from: currentBoardHistorySnapshot(),
        reason: reason
    )
}
```

## 修改四：新增基于 item local space 的裁剪框平移草稿求解

### 修改前

- `crop` 只有 handle 驱动的 `updateCropDraft(using:to:)`。
- controller 里没有任何“从按下位置计算平移 delta 并整体移动 crop frame”的 helper。
- 因此即使边框被画出来，也无法把它映射成新的 `draftCropRectNormalized`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updateCropDraft(using:to:) / commitCropDraftIfNeeded()
// 功能说明: 修改前 iOS 只有 handle resize 驱动的 crop 草稿更新，后续直接进入 commit；不存在边框平移相关 helper。
private func updateCropDraft(
    using cropState: PointerCropState,
    to viewportLocation: CGPoint
) {
    guard
        var inlineEditState,
        inlineEditState.mode == .crop,
        inlineEditState.itemID == cropState.itemID,
        let item = scene.item(withID: cropState.itemID)
    else {
        return
    }

    let draggedWorldPoint = camera.viewportToWorld(viewportLocation)
    let draggedLocalPoint = item.localPoint(fromWorld: draggedWorldPoint)
    let cropLocalFrame = constrainedCropLocalFrame(
        draggedLocalPoint,
        for: cropState.handleRole,
        initialLocalFrame: cropState.initialLocalFrame,
        fullImageLocalFrame: cropState.fullImageLocalFrame,
        minimumLocalSize: cropState.minimumLocalSize
    )
    let draftCropRectNormalized = item.normalizedCropRect(fromLocalFrame: cropLocalFrame)
    guard inlineEditState.draftCropRectNormalized != draftCropRectNormalized else {
        return
    }

    inlineEditState.draftCropRectNormalized = draftCropRectNormalized
    self.inlineEditState = inlineEditState
    requestCanvasRefresh(reason: "update crop draft")
}

private func commitCropDraftIfNeeded() {
    guard
        let inlineEditState,
        inlineEditState.mode == .crop,
        let item = scene.item(withID: inlineEditState.itemID)
    else {
        historyController.cancelPendingTransaction()
        return
    }

    guard item.cropRectNormalized != inlineEditState.draftCropRectNormalized else {
        historyController.cancelPendingTransaction()
        return
    }

    guard let croppedItem = scene.cropItem(
        withID: inlineEditState.itemID,
        toNormalizedCropRect: inlineEditState.draftCropRectNormalized
    ) else {
        historyController.cancelPendingTransaction()
        return
    }

    expandBoardIfNeeded(toInclude: croppedItem.worldBounds)
    self.inlineEditState = CanvasInlineEditState(item: croppedItem, mode: .crop)
    requestCanvasRefresh(reason: "commit crop item")
    commitPendingPointerHistoryTransaction(autosaveReason: "crop item")
}
```

### 修改后

- 新增 `makePointerCropTranslationState(...)`，在拖拽开始时记录 `initialLocalFrame / fullImageLocalFrame / initialPointerLocalPoint`。
- 新增 `updateTranslatedCropDraft(...)`，将当前 viewport point 转成 item local point，再调用平移 helper。
- 新增 `translatedCropLocalFrame(...)`，只平移 `origin`，保持当前 crop size 不变，并在 `fullImageLocalFrame` 内做 clamp。
- 最终仍然通过 `normalizedCropRect(fromLocalFrame:)` 写回统一的 `draftCropRectNormalized`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: makePointerCropTranslationState(itemID:initialViewportLocation:) / updateTranslatedCropDraft(using:to:) / translatedCropLocalFrame(_:using:)
// 功能说明: 修改后 iOS 将 crop outline 拖拽统一转成 item local space 平移，再通过 normalizedCropRect 写回共享 draft。
private func makePointerCropTranslationState(
    itemID: CanvasImageItemID,
    initialViewportLocation: CGPoint
) -> PointerCropTranslationState? {
    guard
        let item = scene.item(withID: itemID),
        let inlineEditState,
        inlineEditState.mode == .crop,
        inlineEditState.itemID == itemID
    else {
        return nil
    }

    return PointerCropTranslationState(
        itemID: itemID,
        fullImageLocalFrame: item.fullImageLocalFrame.standardized,
        initialLocalFrame: item.localFrame(
            forNormalizedCropRect: inlineEditState.draftCropRectNormalized
        ).standardized,
        initialPointerLocalPoint: item.localPoint(
            fromWorld: camera.viewportToWorld(initialViewportLocation)
        )
    )
}

private func updateTranslatedCropDraft(
    using translationState: PointerCropTranslationState,
    to viewportLocation: CGPoint
) {
    guard
        var inlineEditState,
        inlineEditState.mode == .crop,
        inlineEditState.itemID == translationState.itemID,
        let item = scene.item(withID: translationState.itemID)
    else {
        return
    }

    let draggedLocalPoint = item.localPoint(
        fromWorld: camera.viewportToWorld(viewportLocation)
    )
    let translatedLocalFrame = translatedCropLocalFrame(
        draggedLocalPoint,
        using: translationState
    )
    let draftCropRectNormalized = item.normalizedCropRect(
        fromLocalFrame: translatedLocalFrame
    )
    guard inlineEditState.draftCropRectNormalized != draftCropRectNormalized else {
        return
    }

    inlineEditState.draftCropRectNormalized = draftCropRectNormalized
    self.inlineEditState = inlineEditState
    requestCanvasRefresh(reason: "update crop draft")
}

private func translatedCropLocalFrame(
    _ draggedLocalPoint: CGPoint,
    using translationState: PointerCropTranslationState
) -> CGRect {
    let initialLocalFrame = translationState.initialLocalFrame.standardized
    let fullImageLocalFrame = translationState.fullImageLocalFrame.standardized
    let delta = CGPoint(
        x: draggedLocalPoint.x - translationState.initialPointerLocalPoint.x,
        y: draggedLocalPoint.y - translationState.initialPointerLocalPoint.y
    )
    let translatedOrigin = CGPoint(
        x: initialLocalFrame.minX + delta.x,
        y: initialLocalFrame.minY + delta.y
    )
    let clampedOrigin = CGPoint(
        x: min(
            max(translatedOrigin.x, fullImageLocalFrame.minX),
            fullImageLocalFrame.maxX - initialLocalFrame.width
        ),
        y: min(
            max(translatedOrigin.y, fullImageLocalFrame.minY),
            fullImageLocalFrame.maxY - initialLocalFrame.height
        )
    )
    return CGRect(
        origin: clampedOrigin,
        size: initialLocalFrame.size
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: makePointerCropTranslationState(itemID:initialViewportLocation:) / updateTranslatedCropDraft(using:to:) / translatedCropLocalFrame(_:using:)
// 功能说明: macOS 侧同步用 item local space 做 crop frame 平移，并通过同样的 clamp 规则保证裁剪框不会超出 full image。
private func makePointerCropTranslationState(
    itemID: CanvasImageItemID,
    initialViewportLocation: CGPoint
) -> PointerCropTranslationState? {
    guard
        let item = scene.item(withID: itemID),
        let inlineEditState,
        inlineEditState.mode == .crop,
        inlineEditState.itemID == itemID
    else {
        return nil
    }

    return PointerCropTranslationState(
        itemID: itemID,
        fullImageLocalFrame: item.fullImageLocalFrame.standardized,
        initialLocalFrame: item.localFrame(
            forNormalizedCropRect: inlineEditState.draftCropRectNormalized
        ).standardized,
        initialPointerLocalPoint: item.localPoint(
            fromWorld: camera.viewportToWorld(initialViewportLocation)
        )
    )
}

private func updateTranslatedCropDraft(
    using translationState: PointerCropTranslationState,
    to viewportLocation: CGPoint
) {
    guard
        var inlineEditState,
        inlineEditState.mode == .crop,
        inlineEditState.itemID == translationState.itemID,
        let item = scene.item(withID: translationState.itemID)
    else {
        return
    }

    let draggedLocalPoint = item.localPoint(
        fromWorld: camera.viewportToWorld(viewportLocation)
    )
    let translatedLocalFrame = translatedCropLocalFrame(
        draggedLocalPoint,
        using: translationState
    )
    let draftCropRectNormalized = item.normalizedCropRect(
        fromLocalFrame: translatedLocalFrame
    )
    guard inlineEditState.draftCropRectNormalized != draftCropRectNormalized else {
        return
    }

    inlineEditState.draftCropRectNormalized = draftCropRectNormalized
    self.inlineEditState = inlineEditState
    refreshCanvas()
}

private func translatedCropLocalFrame(
    _ draggedLocalPoint: CGPoint,
    using translationState: PointerCropTranslationState
) -> CGRect {
    let initialLocalFrame = translationState.initialLocalFrame.standardized
    let fullImageLocalFrame = translationState.fullImageLocalFrame.standardized
    let delta = CGPoint(
        x: draggedLocalPoint.x - translationState.initialPointerLocalPoint.x,
        y: draggedLocalPoint.y - translationState.initialPointerLocalPoint.y
    )
    let translatedOrigin = CGPoint(
        x: initialLocalFrame.minX + delta.x,
        y: initialLocalFrame.minY + delta.y
    )
    let clampedOrigin = CGPoint(
        x: min(
            max(translatedOrigin.x, fullImageLocalFrame.minX),
            fullImageLocalFrame.maxX - initialLocalFrame.width
        ),
        y: min(
            max(translatedOrigin.y, fullImageLocalFrame.minY),
            fullImageLocalFrame.maxY - initialLocalFrame.height
        )
    )
    return CGRect(
        origin: clampedOrigin,
        size: initialLocalFrame.size
    )
}
```

## 验证结果

### lints

- 对以下文件执行 `ReadLints`，结果均为 `No linter errors found.`：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

### 构建验证

```bash
# 功能说明: iOS Simulator Debug 构建验证；沿用工作区内 derivedDataPath 与禁签名参数。
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath ".build/ios-sim" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=NO
```

- 结果：`Exit code 0`，构建通过。

```bash
# 功能说明: macOS Debug 构建验证；沿用工作区内 derivedDataPath 与禁签名参数。
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath ".build/macos" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

- 结果：`Exit code 0`，构建通过。

## 本次未执行的回归项

- 未逐项手动验证 `crop` 边框拖动时，8 个 handle 是否始终保持更高优先级。
- 未逐项手动验证 rotated item 进入 `crop` 模式后，边框拖动方向与 local-space 平移是否完全符合预期。
- 未逐项手动验证 undo / redo、autosave、手动保存、重开恢复，以及“单次手势只生成一条历史记录”。
