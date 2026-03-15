# 20260315_113607_canvas_tap_blank_clear_selection_record

## 记录范围

- 记录内容：
  1. 在 iOS / macOS 的 `canvas` 中，点击空白位置时取消当前图片的选中状态。
  2. 保持拖动画布、拖动图片等现有交互不变，只在“点击空白并抬起”这条路径上清空选中。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：原始 gif diff、额外的提交流程。

## 修改一：点击空白处时取消选中

### 修改前

- `pointer up` 的逻辑只处理“按下与抬起仍命中同一图片”时的选中。
- 如果按下和抬起都落在空白位置，控制器会直接 `return`，不会清空当前的 `selectedItemID`。
- 这导致用户点击空白处时，看不到“取消选中”的效果，之前已选中的图片会保持高亮状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:)
// 功能说明: 修改前 iOS 只有命中同一图片时才会更新选中；点击空白处会直接退出，不会清空当前选中项。
private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(pressedItemID, _):
        guard let pressedItemID, hitTestItemID(at: location) == pressedItemID else {
            return
        }

        selectItem(withID: pressedItemID)
    case .draggingSelectedItem, .draggingCanvas, .idle:
        break
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:)
// 功能说明: 修改前 macOS 与 iOS 一样，空白点击不会触发取消选中。
private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(pressedItemID, _):
        guard let pressedItemID, hitTestItemID(at: location) == pressedItemID else {
            return
        }

        selectItem(withID: pressedItemID)
    case .draggingSelectedItem, .draggingCanvas, .idle:
        break
    }
}
```

### 修改后

- `handlePrimaryPointerUp(at:)` 现在会同时判断：
  - 按下命中图片，且抬起仍命中同一图片：保持原有选中逻辑
  - 按下命中空白，且抬起也命中空白：清空当前选中项
- 新增 `clearSelectionIfNeeded()`，专门负责在已有选中项时将 `selectedItemID` 置空并刷新画布。
- 这样可以避免把拖动画布误判为“点击空白取消选中”，因为只有 `.pressed` 状态下的空白点击才会执行这段逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:) / clearSelectionIfNeeded()
// 功能说明: 修改后 iOS 在按下和抬起都位于空白区域时，会取消当前选中图片；拖动画布不受影响。
private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(pressedItemID, _):
        let releasedItemID = hitTestItemID(at: location)
        if let pressedItemID, releasedItemID == pressedItemID {
            selectItem(withID: pressedItemID)
        } else if pressedItemID == nil, releasedItemID == nil {
            clearSelectionIfNeeded()
        }
    case .draggingSelectedItem, .draggingCanvas, .idle:
        break
    }
}

private func clearSelectionIfNeeded() {
    guard interactionState.selectedItemID != nil else {
        return
    }

    interactionState.selectedItemID = nil
    requestCanvasRefresh(reason: "clear selection")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:) / clearSelectionIfNeeded()
// 功能说明: 修改后 macOS 与 iOS 保持一致，只有“空白点击并抬起”才会取消选中，不影响拖动中的状态机。
private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(pressedItemID, _):
        let releasedItemID = hitTestItemID(at: location)
        if let pressedItemID, releasedItemID == pressedItemID {
            selectItem(withID: pressedItemID)
        } else if pressedItemID == nil, releasedItemID == nil {
            clearSelectionIfNeeded()
        }
    case .draggingSelectedItem, .draggingCanvas, .idle:
        break
    }
}

private func clearSelectionIfNeeded() {
    guard interactionState.selectedItemID != nil else {
        return
    }

    interactionState.selectedItemID = nil
    refreshCanvas()
}
```

### 结果

- 现在在 iOS / macOS 上点击空白区域，都会取消当前被选中的图片。
- 点击图片选中、拖动画布、拖动已选中图片等原有交互保持不变。
- 清空选中逻辑只会在 `.pressed` 的空白点击路径上触发，不会误伤拖动手势。
