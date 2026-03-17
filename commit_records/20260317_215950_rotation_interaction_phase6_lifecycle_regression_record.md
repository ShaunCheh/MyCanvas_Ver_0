# 20260317_215950_rotation_interaction_phase6_lifecycle_regression_record

## 记录范围

- 记录内容：旋转角度 HUD 的阶段 6 生命周期与回归收口。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本次明确未修改：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift`
- 本次重点不是新增视觉元素，而是把“旋转开始 / 持续 / 结束 / 取消 / 切换选中 / 进入裁剪 / 撤销重做 / 历史恢复”的状态收口做完整。

## 阶段结论

- 旋转开始瞬间现在就会触发刷新，HUD 不再依赖“角度先发生变化”。
- 指针取消事件不再提交旋转草稿，而是回滚本次旋转预览、撤销待提交事务并立即隐藏 HUD。
- 旋转中的临时状态被统一为：
  - `rotationPreviewState`
  - `rotationInteractionState`
  - `pointerDragState == .rotatingSelectedItem`
- 外部生命周期入口统一通过专门 helper 收口，避免某些路径只清了一半状态，导致 HUD 残留或旧拖拽继续写草稿。
- minimap 本次无需适配，仍然只感知 `rotationPreviewState`，不感知 `interactionOverlay`。

## 修改一：iOS 将旋转开始 / 取消 / 提交收口为统一旋转生命周期

### 修改前

- `handlePrimaryPointerCancel()` 在旋转分支里直接调用 `commitRotationDraftIfNeeded()`。
- `updateRotationDraft(using:to:)` 只校验 `inlineEditState == nil` 和 `item` 是否存在，没有校验当前选中项和交互态是否还有效。
- `commitRotationDraftIfNeeded()` 在多个 `guard` 失败分支中分散地清理状态。
- `beginRotationInteraction(for:)` 只设置 `rotationInteractionState`，不会立即刷新 HUD。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerCancel() / updateRotationDraft(using:to:) /
//        commitRotationDraftIfNeeded() / beginRotationInteraction(for:)
// 功能说明: 修改前旋转 cancel 会走“提交草稿”，状态清理散落在多个分支里，旋转开始也不会立即刷新 HUD。
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

private func updateRotationDraft(
    using rotateState: PointerRotateState,
    to viewportLocation: CGPoint
) {
    guard
        inlineEditState == nil,
        let item = scene.item(withID: rotateState.itemID)
    else {
        return
    }

    let pointerAngle = angle(
        from: rotateState.referenceCenter,
        to: camera.viewportToWorld(viewportLocation)
    )
    let draftRotationRadians = normalizedCanvasAngle(
        pointerAngle + rotateState.rotationOffsetToPointerAngle
    )
    guard !anglesMatch(
        displayedRotationRadians(for: item),
        draftRotationRadians
    ) else {
        return
    }

    rotationPreviewState = CanvasRotationPreviewState(
        itemID: rotateState.itemID,
        draftRotationRadians: draftRotationRadians
    )
    requestCanvasRefresh(reason: "update rotate draft")
}

private func commitRotationDraftIfNeeded() {
    guard
        let rotationPreviewState,
        let item = scene.item(withID: rotationPreviewState.itemID)
    else {
        clearRotationInteractionState()
        historyController.cancelPendingTransaction()
        return
    }

    guard !anglesMatch(item.rotationRadians, rotationPreviewState.draftRotationRadians) else {
        clearRotationPreviewState()
        clearRotationInteractionState()
        historyController.cancelPendingTransaction()
        return
    }

    guard let rotatedItem = scene.rotateItem(
        withID: rotationPreviewState.itemID,
        to: rotationPreviewState.draftRotationRadians
    ) else {
        clearRotationPreviewState()
        clearRotationInteractionState()
        historyController.cancelPendingTransaction()
        return
    }

    expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
    clearRotationPreviewState()
    clearRotationInteractionState()
    requestCanvasRefresh(reason: "commit rotate item")
    commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
}

private func beginRotationInteraction(for itemID: CanvasImageItemID) {
    guard rotationInteractionState?.itemID != itemID else {
        return
    }

    rotationInteractionState = CanvasRotationInteractionState(itemID: itemID)
}
```

### 修改后

- 新增 `clearRotationTransientState()`，统一清理旋转预览态和旋转交互态。
- 新增 `cancelRotationInteractionIfNeeded(...)`，把“回滚 HUD + 取消事务 + 可选重置拖拽态 + 可选刷新”收敛成一个根因级入口。
- `handlePrimaryPointerCancel()` 旋转分支改为调用 `cancelRotationInteractionIfNeeded(...)`。
- `updateRotationDraft(using:to:)` 新增：
  - 当前图片仍处于选中态
  - 当前 `rotationInteractionState` 仍然对应同一 item
- `beginRotationInteraction(for:)` 立即刷新，让 HUD 在开始拖动瞬间就出现。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerCancel() / updateRotationDraft(using:to:) /
//        commitRotationDraftIfNeeded() / clearRotationTransientState() /
//        beginRotationInteraction(for:) / cancelRotationInteractionIfNeeded(...)
// 功能说明: 修改后 iOS 把旋转交互的开始、提交、取消都统一走同一套临时状态收口逻辑。
private func handlePrimaryPointerCancel() {
    switch pointerDragState {
    case .rotatingSelectedItem:
        cancelRotationInteractionIfNeeded(
            refreshReason: "cancel rotate interaction"
        )
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

private func updateRotationDraft(
    using rotateState: PointerRotateState,
    to viewportLocation: CGPoint
) {
    guard
        inlineEditState == nil,
        interactionState.selectedItemID == rotateState.itemID,
        rotationInteractionState?.itemID == rotateState.itemID,
        let item = scene.item(withID: rotateState.itemID)
    else {
        return
    }

    let pointerAngle = angle(
        from: rotateState.referenceCenter,
        to: camera.viewportToWorld(viewportLocation)
    )
    let draftRotationRadians = normalizedCanvasAngle(
        pointerAngle + rotateState.rotationOffsetToPointerAngle
    )
    guard !anglesMatch(
        displayedRotationRadians(for: item),
        draftRotationRadians
    ) else {
        return
    }

    rotationPreviewState = CanvasRotationPreviewState(
        itemID: rotateState.itemID,
        draftRotationRadians: draftRotationRadians
    )
    requestCanvasRefresh(reason: "update rotate draft")
}

private func commitRotationDraftIfNeeded() {
    guard
        let rotationPreviewState,
        let item = scene.item(withID: rotationPreviewState.itemID)
    else {
        cancelRotationInteractionIfNeeded(
            refreshReason: "discard rotate interaction"
        )
        return
    }

    guard !anglesMatch(item.rotationRadians, rotationPreviewState.draftRotationRadians) else {
        cancelRotationInteractionIfNeeded(
            refreshReason: "discard unchanged rotate interaction"
        )
        return
    }

    guard let rotatedItem = scene.rotateItem(
        withID: rotationPreviewState.itemID,
        to: rotationPreviewState.draftRotationRadians
    ) else {
        cancelRotationInteractionIfNeeded(
            refreshReason: "discard failed rotate interaction"
        )
        return
    }

    expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
    clearRotationTransientState()
    requestCanvasRefresh(reason: "commit rotate item")
    commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
}

private func clearRotationTransientState() {
    clearRotationPreviewState()
    clearRotationInteractionState()
}

private func beginRotationInteraction(for itemID: CanvasImageItemID) {
    guard rotationInteractionState?.itemID != itemID else {
        return
    }

    rotationInteractionState = CanvasRotationInteractionState(itemID: itemID)
    requestCanvasRefresh(reason: "begin rotate interaction")
}

private func cancelRotationInteractionIfNeeded(
    resetPointerDragState: Bool = false,
    refreshReason: String? = nil
) {
    let hadVisibleRotationState =
        rotationPreviewState != nil || rotationInteractionState != nil
    let wasRotating: Bool
    switch pointerDragState {
    case .rotatingSelectedItem:
        wasRotating = true
    default:
        wasRotating = false
    }

    guard hadVisibleRotationState || wasRotating else {
        return
    }

    clearRotationTransientState()
    historyController.cancelPendingTransaction()

    if resetPointerDragState, wasRotating {
        pointerDragState = .idle
    }

    if hadVisibleRotationState, let refreshReason {
        requestCanvasRefresh(reason: refreshReason)
    }
}
```

## 修改二：iOS 把“外部生命周期打断旋转”统一走同一入口

### 修改前

- `applyBoardRuntimeState(_:)`、`applyBoardHistorySnapshot(_:)`、`beginCropModeIfPossible()` 都是分别手动清理旋转相关状态。
- `syncInlineEditStateWithSelection()` 则只在 item 不匹配时各清一半状态，没有处理 `pointerDragState` 和待提交事务。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: applyBoardRuntimeState(_) / applyBoardHistorySnapshot(_) /
//        beginCropModeIfPossible() / syncInlineEditStateWithSelection()
// 功能说明: 修改前外部生命周期只是分散清理 preview/interaction 状态，缺少对旋转拖拽态和 pending transaction 的统一收口。
private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    activeBoardID = runtimeState.boardID
    activeBoardTitle = runtimeState.title
    activeBoardCreatedAt = runtimeState.createdAt
    scene.setItems(runtimeState.items)
    boardState = runtimeState.boardState
    camera = runtimeState.camera
    interactionState = runtimeState.interactionState
    inlineEditState = nil
    clearRotationPreviewState()
    clearRotationInteractionState()
    updateInlineEditButtonsAppearance()
}

private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
        clearRotationPreviewState()
        clearRotationInteractionState()
    }

    requestCanvasRefresh(reason: "apply history snapshot")
}

private func beginCropModeIfPossible() {
    guard
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return
    }

    clearRotationPreviewState()
    clearRotationInteractionState()
    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "enter crop mode")
}

private func syncInlineEditStateWithSelection() {
    if
        let rotationPreviewState,
        interactionState.selectedItemID != rotationPreviewState.itemID
    {
        clearRotationPreviewState()
    }

    if
        let rotationInteractionState,
        interactionState.selectedItemID != rotationInteractionState.itemID
    {
        clearRotationInteractionState()
    }

    // ... 其余 inline edit 同步逻辑保持不变 ...
}
```

### 修改后

- `applyBoardRuntimeState(_:)`、`applyBoardHistorySnapshot(_:)`、`beginCropModeIfPossible()` 在切入自己的主逻辑前，先统一调用 `cancelRotationInteractionIfNeeded(resetPointerDragState: true)`。
- `syncInlineEditStateWithSelection()` 改为先统一判断是否需要打断旋转交互，然后交给同一个 helper 处理。
- 这样外部打断路径不再只是“清局部字段”，而是完整回收：
  - 旋转草稿
  - 旋转 HUD 激活态
  - 正在旋转的 pointer drag state
  - 待提交历史事务

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: applyBoardRuntimeState(_) / applyBoardHistorySnapshot(_) /
//        beginCropModeIfPossible() / syncInlineEditStateWithSelection()
// 功能说明: 修改后所有外部生命周期打断点统一通过 cancelRotationInteractionIfNeeded(...) 收口旋转临时状态。
private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    activeBoardID = runtimeState.boardID
    activeBoardTitle = runtimeState.title
    activeBoardCreatedAt = runtimeState.createdAt
    scene.setItems(runtimeState.items)
    boardState = runtimeState.boardState
    camera = runtimeState.camera
    interactionState = runtimeState.interactionState
    inlineEditState = nil
    updateInlineEditButtonsAppearance()
}

private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        cancelRotationInteractionIfNeeded(resetPointerDragState: true)
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
    }

    requestCanvasRefresh(reason: "apply history snapshot")
}

private func beginCropModeIfPossible() {
    guard
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return
    }

    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "enter crop mode")
}

private func syncInlineEditStateWithSelection() {
    let shouldCancelRotationInteraction =
        rotationPreviewState.map { interactionState.selectedItemID != $0.itemID } ?? false ||
        rotationInteractionState.map { interactionState.selectedItemID != $0.itemID } ?? false
    if shouldCancelRotationInteraction {
        cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    }

    // ... 其余 inline edit 同步逻辑保持不变 ...
}
```

## 修改三：macOS 镜像同步 iOS 的旋转开始 / 取消 / 提交收口

### 修改前

- macOS 与 iOS 一样：
  - `handlePrimaryPointerCancel()` 会提交旋转草稿
  - `updateRotationDraft(using:to:)` 缺少“选中项/交互态仍有效”的护栏
  - `commitRotationDraftIfNeeded()` 中散落着多处手动清理
  - `beginRotationInteraction(for:)` 只设状态，不刷新 HUD

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerCancel() / updateRotationDraft(using:to:) /
//        commitRotationDraftIfNeeded() / beginRotationInteraction(for:)
// 功能说明: 修改前 macOS 和 iOS 一样，旋转生命周期没有统一收口，cancel 仍然会走提交逻辑。
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

private func updateRotationDraft(
    using rotateState: PointerRotateState,
    to viewportLocation: CGPoint
) {
    guard
        inlineEditState == nil,
        let item = scene.item(withID: rotateState.itemID)
    else {
        return
    }

    let pointerAngle = angle(
        from: rotateState.referenceCenter,
        to: camera.viewportToWorld(viewportLocation)
    )
    let draftRotationRadians = normalizedCanvasAngle(
        pointerAngle + rotateState.rotationOffsetToPointerAngle
    )
    guard !anglesMatch(
        displayedRotationRadians(for: item),
        draftRotationRadians
    ) else {
        return
    }

    rotationPreviewState = CanvasRotationPreviewState(
        itemID: rotateState.itemID,
        draftRotationRadians: draftRotationRadians
    )
    refreshCanvas()
}

private func commitRotationDraftIfNeeded() {
    guard
        let rotationPreviewState,
        let item = scene.item(withID: rotationPreviewState.itemID)
    else {
        clearRotationInteractionState()
        historyController.cancelPendingTransaction()
        return
    }

    guard !anglesMatch(item.rotationRadians, rotationPreviewState.draftRotationRadians) else {
        clearRotationPreviewState()
        clearRotationInteractionState()
        historyController.cancelPendingTransaction()
        return
    }

    guard let rotatedItem = scene.rotateItem(
        withID: rotationPreviewState.itemID,
        to: rotationPreviewState.draftRotationRadians
    ) else {
        clearRotationPreviewState()
        clearRotationInteractionState()
        historyController.cancelPendingTransaction()
        return
    }

    expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
    clearRotationPreviewState()
    clearRotationInteractionState()
    refreshCanvas()
    commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
}

private func beginRotationInteraction(for itemID: CanvasImageItemID) {
    guard rotationInteractionState?.itemID != itemID else {
        return
    }

    rotationInteractionState = CanvasRotationInteractionState(itemID: itemID)
}
```

### 修改后

- macOS 与 iOS 保持镜像：
  - 新增 `clearRotationTransientState()`
  - 新增 `cancelRotationInteractionIfNeeded(...)`
  - `cancel` 改为回滚而不是提交
  - `beginRotationInteraction(for:)` 立即刷新
  - `updateRotationDraft(using:to:)` 补齐有效性护栏

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerCancel() / updateRotationDraft(using:to:) /
//        commitRotationDraftIfNeeded() / clearRotationTransientState() /
//        beginRotationInteraction(for:) / cancelRotationInteractionIfNeeded(...)
// 功能说明: 修改后 macOS 和 iOS 使用同一套旋转交互收口策略，保证双端行为一致。
private func handlePrimaryPointerCancel() {
    switch pointerDragState {
    case .rotatingSelectedItem:
        cancelRotationInteractionIfNeeded(
            refreshAfterCancellation: true
        )
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

private func updateRotationDraft(
    using rotateState: PointerRotateState,
    to viewportLocation: CGPoint
) {
    guard
        inlineEditState == nil,
        interactionState.selectedItemID == rotateState.itemID,
        rotationInteractionState?.itemID == rotateState.itemID,
        let item = scene.item(withID: rotateState.itemID)
    else {
        return
    }

    let pointerAngle = angle(
        from: rotateState.referenceCenter,
        to: camera.viewportToWorld(viewportLocation)
    )
    let draftRotationRadians = normalizedCanvasAngle(
        pointerAngle + rotateState.rotationOffsetToPointerAngle
    )
    guard !anglesMatch(
        displayedRotationRadians(for: item),
        draftRotationRadians
    ) else {
        return
    }

    rotationPreviewState = CanvasRotationPreviewState(
        itemID: rotateState.itemID,
        draftRotationRadians: draftRotationRadians
    )
    refreshCanvas()
}

private func commitRotationDraftIfNeeded() {
    guard
        let rotationPreviewState,
        let item = scene.item(withID: rotationPreviewState.itemID)
    else {
        cancelRotationInteractionIfNeeded(
            refreshAfterCancellation: true
        )
        return
    }

    guard !anglesMatch(item.rotationRadians, rotationPreviewState.draftRotationRadians) else {
        cancelRotationInteractionIfNeeded(
            refreshAfterCancellation: true
        )
        return
    }

    guard let rotatedItem = scene.rotateItem(
        withID: rotationPreviewState.itemID,
        to: rotationPreviewState.draftRotationRadians
    ) else {
        cancelRotationInteractionIfNeeded(
            refreshAfterCancellation: true
        )
        return
    }

    expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
    clearRotationTransientState()
    refreshCanvas()
    commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
}

private func clearRotationTransientState() {
    clearRotationPreviewState()
    clearRotationInteractionState()
}

private func beginRotationInteraction(for itemID: CanvasImageItemID) {
    guard rotationInteractionState?.itemID != itemID else {
        return
    }

    rotationInteractionState = CanvasRotationInteractionState(itemID: itemID)
    refreshCanvas()
}

private func cancelRotationInteractionIfNeeded(
    resetPointerDragState: Bool = false,
    refreshAfterCancellation: Bool = false
) {
    let hadVisibleRotationState =
        rotationPreviewState != nil || rotationInteractionState != nil
    let wasRotating: Bool
    switch pointerDragState {
    case .rotatingSelectedItem:
        wasRotating = true
    default:
        wasRotating = false
    }

    guard hadVisibleRotationState || wasRotating else {
        return
    }

    clearRotationTransientState()
    historyController.cancelPendingTransaction()

    if resetPointerDragState, wasRotating {
        pointerDragState = .idle
    }

    if hadVisibleRotationState, refreshAfterCancellation {
        refreshCanvas()
    }
}
```

## 修改四：macOS 把外部生命周期打断点也统一收口

### 修改前

- `applyBoardRuntimeState(_:)`、`applyBoardHistorySnapshot(_:)`、`beginCropModeIfPossible()`、`syncInlineEditStateWithSelection()` 都是各自分散清理旋转态。
- 这意味着“状态字段被清了”和“旋转交互已经完整结束”并不是同一件事。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: applyBoardRuntimeState(_) / applyBoardHistorySnapshot(_) /
//        beginCropModeIfPossible() / syncInlineEditStateWithSelection()
// 功能说明: 修改前 macOS 的外部打断路径也只是散落清字段，没有统一处理拖拽态和 pending transaction。
private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    activeBoardID = runtimeState.boardID
    activeBoardTitle = runtimeState.title
    activeBoardCreatedAt = runtimeState.createdAt
    scene.setItems(runtimeState.items)
    boardState = runtimeState.boardState
    camera = runtimeState.camera
    interactionState = runtimeState.interactionState
    inlineEditState = nil
    clearRotationPreviewState()
    clearRotationInteractionState()
    updateInlineEditButtonsAppearance()
}

private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
        clearRotationPreviewState()
        clearRotationInteractionState()
    }

    refreshCanvas()
}

private func beginCropModeIfPossible() {
    guard
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return
    }

    clearRotationPreviewState()
    clearRotationInteractionState()
    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    updateInlineEditButtonsAppearance()
    refreshCanvas()
}

private func syncInlineEditStateWithSelection() {
    if
        let rotationPreviewState,
        interactionState.selectedItemID != rotationPreviewState.itemID
    {
        clearRotationPreviewState()
    }

    if
        let rotationInteractionState,
        interactionState.selectedItemID != rotationInteractionState.itemID
    {
        clearRotationInteractionState()
    }

    // ... 其余 inline edit 同步逻辑保持不变 ...
}
```

### 修改后

- macOS 与 iOS 一样，把所有外部打断入口统一接到 `cancelRotationInteractionIfNeeded(resetPointerDragState: true)`。
- 这样撤销/重做、历史恢复、切换选中项、进入裁剪等路径都不会留下旋转中的悬空状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: applyBoardRuntimeState(_) / applyBoardHistorySnapshot(_) /
//        beginCropModeIfPossible() / syncInlineEditStateWithSelection()
// 功能说明: 修改后 macOS 外部生命周期打断点统一通过 cancelRotationInteractionIfNeeded(...) 结束旋转交互。
private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    activeBoardID = runtimeState.boardID
    activeBoardTitle = runtimeState.title
    activeBoardCreatedAt = runtimeState.createdAt
    scene.setItems(runtimeState.items)
    boardState = runtimeState.boardState
    camera = runtimeState.camera
    interactionState = runtimeState.interactionState
    inlineEditState = nil
    updateInlineEditButtonsAppearance()
}

private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        cancelRotationInteractionIfNeeded(resetPointerDragState: true)
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
    }

    refreshCanvas()
}

private func beginCropModeIfPossible() {
    guard
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return
    }

    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    updateInlineEditButtonsAppearance()
    refreshCanvas()
}

private func syncInlineEditStateWithSelection() {
    let shouldCancelRotationInteraction =
        rotationPreviewState.map { interactionState.selectedItemID != $0.itemID } ?? false ||
        rotationInteractionState.map { interactionState.selectedItemID != $0.itemID } ?? false
    if shouldCancelRotationInteraction {
        cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    }

    // ... 其余 inline edit 同步逻辑保持不变 ...
}
```

## 验证项：minimap 本次无需适配

- 阶段 6 虽然要求检查 minimap 链路，但核对后确认不需要改代码。
- minimap 仍然只依赖 `imageRotationPreviewState`，不会感知 `interactionOverlay` 或 `rotationInteractionState`。
- 这保证了旋转 HUD 的生命周期不会污染 minimap。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
// 函数名: CanvasMiniMapNodeProviderContext / CanvasMiniMapImageNodeProvider.makeNodes(context:)
// 功能说明: 本次未修改 minimap；当前实现仍只消费 rotation preview，不感知 interaction overlay 的临时 HUD 生命周期。
struct CanvasMiniMapNodeProviderContext {
    let scene: CanvasScene
    let imageInlineEditState: CanvasInlineEditState?
    let imageRotationPreviewState: CanvasRotationPreviewState?
}

struct CanvasMiniMapImageNodeProvider: CanvasMiniMapNodeProviding {
    private let presentationResolver = CanvasImagePresentationResolver()

    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedItems().map { item in
            let presentation = presentationResolver.resolve(
                item: item,
                inlineEditState: context.imageInlineEditState,
                rotationPreviewState: context.imageRotationPreviewState
            )
            return CanvasMiniMapNode(
                id: presentation.itemID,
                kind: .image,
                worldQuad: presentation.visibleWorldQuad,
                zIndex: presentation.zIndex,
                isPreviewActive: presentation.isCropPreviewActive || presentation.isRotationPreviewActive
            )
        }
    }
}
```

## 本阶段完成后的行为变化

1. 旋转开始瞬间即可显示 HUD，即使角度还没有发生数值变化。
2. 指针取消不会再误提交旋转，而是回滚本次交互。
3. 切换选中项、进入裁剪、撤销/重做、历史恢复时，旋转中的临时状态都会被完整回收。
4. iOS / macOS 在旋转 HUD 的生命周期上保持镜像一致。
5. minimap 不感知 interaction overlay，继续只跟随正式的 preview 语义。

## 校验结果

- 已检查以下文件，本次修改未引入新的 lint 问题：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本次未执行 `xcodebuild` 项目级编译校验。
