# 20260317_211730_rotation_interaction_phase1_state_boundary_record

## 记录范围

- 记录内容：
  1. 为旋转交互新增独立的瞬时状态 `CanvasRotationInteractionState`。
  2. 在 iOS / macOS 控制器中，把“进入旋转拖动态”与“旋转结束后的清理路径”统一收口。
  3. 为后续 `interactionOverlay` / 角度指示器提供明确的状态边界。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - `CanvasRenderSnapshot` 的 `interactionOverlay` 扩展
  - `CanvasRenderer` 的 HUD 几何生成
  - iOS / macOS viewport 的刻度环、角度数值、文字 layer 渲染
  - 原始 git diff / gif diff / git commit / git push

## 阶段结论

- 这一阶段只完成“状态边界拆分”，不引入可见 UI 变化。
- 修改完成后，系统已经可以独立表达“当前正在旋转交互中”，后续不必再依赖 `rotationPreviewState` 去反推 HUD 是否应显示。

## 修改一：拆分旋转草稿态与旋转交互态

### 修改前

- 只有 `CanvasRotationPreviewState`。
- 它只能表达“当前草稿角度是多少”，不能单独表达“旋转手势是否已经开始”。
- 这会导致后续 HUD 很难在“拖动刚开始但角度尚未变化”时立即出现。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名: 全局状态定义（CanvasRotationPreviewState）
// 功能说明: 修改前只有旋转草稿角度，没有独立状态表达“当前正在旋转交互中”。
struct CanvasRotationPreviewState {
    let itemID: CanvasImageItemID
    var draftRotationRadians: CGFloat
}
```

### 修改后

- 保留 `CanvasRotationPreviewState` 继续负责“图片本体的 draft rotation”。
- 新增 `CanvasRotationInteractionState` 负责“当前旋转交互是否处于激活态”。
- 两者职责拆开后，后续 `interactionOverlay` 可以直接消费 `CanvasRotationInteractionState`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名: 全局状态定义（CanvasRotationPreviewState / CanvasRotationInteractionState）
// 功能说明: 修改后把“角度草稿”和“旋转交互激活态”拆开，为后续 HUD 立即显示提供稳定状态边界。
struct CanvasRotationPreviewState {
    let itemID: CanvasImageItemID
    var draftRotationRadians: CGFloat
}

// 关键点: 单独跟踪旋转手势是否已经开始，避免 HUD 只能靠角度变化来触发。
struct CanvasRotationInteractionState {
    let itemID: CanvasImageItemID
}
```

## 修改二：iOS 在真正进入旋转拖动态时建立独立交互态

### 修改前

- iOS 在 `handlePrimaryPointerMove(to:from:)` 中从 `.pressed` 切到 `.rotatingSelectedItem` 时，只会更新角度草稿。
- 这里没有单独建立“旋转交互已开始”的状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前进入旋转拖动态时，只会更新 draft rotation，没有建立独立的旋转交互态。
case let .rotateHandle(itemID):
    guard let rotateState = makePointerRotateState(
        itemID: itemID,
        initialViewportLocation: pressedLocation
    ) else {
        historyController.cancelPendingTransaction()
        pointerDragState = .idle
        return
    }

    // 关键缺口: 这里只切换拖动态，没有记录“旋转交互已激活”。
    pointerDragState = .rotatingSelectedItem(rotateState)
    updateRotationDraft(using: rotateState, to: location)
```

### 修改后

- 进入 `.rotatingSelectedItem` 后，立即调用 `beginRotationInteraction(for:)`。
- 这样即使后续 `draftRotationRadians` 还没变，交互态也已经独立存在。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改后在真正进入旋转拖动态时，立即建立独立旋转交互态。
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
    // 关键补充: 一旦进入旋转拖动态，立刻建立交互态，供后续 HUD 判断显隐。
    beginRotationInteraction(for: itemID)
    updateRotationDraft(using: rotateState, to: location)
```

同时新增统一 helper，用来收口 iOS 的建态 / 清态逻辑：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: beginRotationInteraction(for:) / clearRotationInteractionState()
// 功能说明: 新增 iOS 侧统一 helper，避免旋转交互态的创建与清理散落在多个分支里。
private func beginRotationInteraction(for itemID: CanvasImageItemID) {
    guard rotationInteractionState?.itemID != itemID else {
        return
    }

    rotationInteractionState = CanvasRotationInteractionState(itemID: itemID)
}

private func clearRotationInteractionState() {
    rotationInteractionState = nil
}
```

## 修改三：iOS 统一补齐旋转交互态的退出清理路径

### 修改前

- `commitRotationDraftIfNeeded()` 只会清理 `rotationPreviewState`。
- `applyBoardHistorySnapshot(_:)`、`beginCropModeIfPossible()`、`syncInlineEditStateWithSelection()` 也只关注 `rotationPreviewState`。
- 这意味着如果后续 HUD 直接挂到独立交互态上，这些路径会有残留风险。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: commitRotationDraftIfNeeded()
// 功能说明: 修改前旋转提交路径只清理角度草稿态，没有统一清理独立交互态。
private func commitRotationDraftIfNeeded() {
    guard
        let rotationPreviewState,
        let item = scene.item(withID: rotationPreviewState.itemID)
    else {
        historyController.cancelPendingTransaction()
        return
    }

    guard !anglesMatch(item.rotationRadians, rotationPreviewState.draftRotationRadians) else {
        clearRotationPreviewState()
        historyController.cancelPendingTransaction()
        return
    }

    guard let rotatedItem = scene.rotateItem(
        withID: rotationPreviewState.itemID,
        to: rotationPreviewState.draftRotationRadians
    ) else {
        clearRotationPreviewState()
        historyController.cancelPendingTransaction()
        return
    }

    expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
    self.rotationPreviewState = nil
    requestCanvasRefresh(reason: "commit rotate item")
    commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
}
```

### 修改后

- 在“无草稿态 / 无角度变化 / rotateItem 失败 / rotateItem 成功”四条退出分支里，都统一清理 `rotationInteractionState`。
- 并且把历史恢复、进入裁剪、选择切换这些非拖拽路径也同步纳入清理范围。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: commitRotationDraftIfNeeded()
// 功能说明: 修改后无论旋转提交成功、失败还是无变化结束，都会同步清理交互态，防止后续 HUD 残留。
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: applyBoardHistorySnapshot(_) / beginCropModeIfPossible() / syncInlineEditStateWithSelection()
// 功能说明: 修改后把历史恢复、进入裁剪、选择切换这些路径也纳入旋转交互态清理范围。
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

    // 关键补充: 选中项一旦变化，也必须同步清理旋转交互态。
    if
        let rotationInteractionState,
        interactionState.selectedItemID != rotationInteractionState.itemID
    {
        clearRotationInteractionState()
    }

    // ... 其余 inline edit 同步逻辑保持不变
}
```

## 修改四：macOS 与 iOS 保持同构的建态 / 清态逻辑

### 修改前

- macOS 的旋转链路与 iOS 同构。
- 但修改前同样只有 `rotationPreviewState`，没有独立的 `rotationInteractionState`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前 macOS 进入旋转拖动态时，也只有 draft rotation，没有独立交互态。
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
```

### 修改后

- macOS 增加了与 iOS 同结构的 `beginRotationInteraction(for:)` / `clearRotationInteractionState()`。
- 同时把旋转提交、历史恢复、进入裁剪、选择切换这些退出路径全部补齐。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:) / beginRotationInteraction(for:) / clearRotationInteractionState()
// 功能说明: 修改后 macOS 与 iOS 保持同构，确保后续 interaction overlay 的状态行为一致。
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
    beginRotationInteraction(for: itemID)
    updateRotationDraft(using: rotateState, to: location)

private func beginRotationInteraction(for itemID: CanvasImageItemID) {
    guard rotationInteractionState?.itemID != itemID else {
        return
    }

    rotationInteractionState = CanvasRotationInteractionState(itemID: itemID)
}

private func clearRotationInteractionState() {
    rotationInteractionState = nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: commitRotationDraftIfNeeded() / applyBoardHistorySnapshot(_) / beginCropModeIfPossible() / syncInlineEditStateWithSelection()
// 功能说明: 修改后 macOS 与 iOS 一样，把所有关键退出路径纳入独立交互态清理范围。
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
```

## 本阶段完成后的代码行为

1. 旋转交互一旦真正进入拖动态，就会建立独立 `rotationInteractionState`。
2. 即使角度草稿还没有变化，后续也已经有独立状态可供 HUD 判定显隐。
3. 旋转结束、旋转失败、无变化结束、进入裁剪、切换选中项、历史恢复这些路径，都会统一清理交互态。
4. 当前阶段仍未把该状态接入 renderer / snapshot / viewport，因此画面上暂时不会出现新的角度指示器。

## 校验结果

- 本轮改动后，对以下文件做过 lint 检查，未发现新增错误：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
