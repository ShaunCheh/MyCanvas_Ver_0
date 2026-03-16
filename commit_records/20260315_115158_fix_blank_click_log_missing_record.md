# 20260315_115158_fix_blank_click_log_missing_record

## 记录范围

- 记录内容：
  1. 修复 iOS / macOS 在点击空白处时，因极小指针抖动被过早判定为拖动，导致 `ClickSelection` 日志偶发缺失的问题。
  2. 为按下态补充初始坐标，并引入 `4pt` 的拖动激活阈值；只有位移超过阈值时，才真正进入拖动画布或拖动已选中图片的状态。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：原始 gif diff、额外的提交流程。

## 修改一：按下态补充初始坐标

### 修改前

- `PointerDragState.pressed` 只记录命中的图片 ID 和“按下时是否已选中”，不记录按下坐标。
- `handlePrimaryPointerDown(at:)` 进入按下态时，没有保存后续可用于累计位移判断的基准点。
- 这意味着后面的 `pointer move` 只能在收到第一帧位移时立即判定为拖动，无法区分“真正拖动”和“点击过程中的轻微抖动”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerDragState / handlePrimaryPointerDown(at:)
// 功能说明: 修改前 iOS 的按下态不保存初始坐标，后续无法基于按下点判断是否只是轻微手指抖动。
private enum PointerDragState {
    case idle
    case pressed(pressedItemID: CanvasImageItemID?, pressedItemWasSelected: Bool)
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
        pressedItemID: pressedItemID,
        pressedItemWasSelected: pressedItemID == interactionState.selectedItemID
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: PointerDragState / handlePrimaryPointerDown(at:)
// 功能说明: 修改前 macOS 的按下态同样不保存初始坐标，无法区分“真正拖动”和“极小鼠标位移”。
private enum PointerDragState {
    case idle
    case pressed(pressedItemID: CanvasImageItemID?, pressedItemWasSelected: Bool)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case draggingCanvas
}

private func handlePrimaryPointerDown(at location: CGPoint) {
    let pressedItemID = hitTestItemID(at: location)
    pointerDragState = .pressed(
        pressedItemID: pressedItemID,
        pressedItemWasSelected: pressedItemID == interactionState.selectedItemID
    )
}
```

### 修改后

- `PointerDragState.pressed` 新增 `pressedLocation`，明确保存 pointer down 的坐标。
- `handlePrimaryPointerDown(at:)` 进入按下态时同步记录 `pressedLocation`，为后续“是否超过拖动阈值”的判断提供统一基准。
- 这样后续的拖动识别就不再依赖单帧 `previousLocation`，而是依赖“从按下点累计移动了多少”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerDragState / handlePrimaryPointerDown(at:)
// 功能说明: 修改后 iOS 会在按下态中保存 pressedLocation，供拖动阈值判断和首帧拖动位移计算复用。
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
// 功能说明: 修改后 macOS 也在按下态中补充 pressedLocation，供后续拖动激活阈值和首帧拖动位移使用。
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

## 修改二：为拖动切换增加激活阈值

### 修改前

- `handlePrimaryPointerMove(to:from:)` 只要收到第一帧非零位移，就会立刻从 `.pressed` 切换到 `.draggingSelectedItem` 或 `.draggingCanvas`。
- 既有的点击日志打印仍然位于 `handlePrimaryPointerUp(at:)` 的 `.pressed` 分支中，因此一旦在点击过程中先收到一次极小 `mouseDragged` / `touchesMoved`，空白点击就可能不再进入日志分支。
- 结果就是：用户明明执行了空白 click，但由于系统派发了微小位移事件，最终没有产生日志。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前 iOS 只要收到第一帧位移就立刻判定为拖动，轻微抖动也会离开 click 路径。
private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer move \(describe(point: location))")
        return
    }

    switch pointerDragState {
    case let .pressed(pressedItemID, pressedItemWasSelected):
        if pressedItemWasSelected, let pressedItemID {
            pointerDragState = .draggingSelectedItem(itemID: pressedItemID)
            moveSelectedItem(withID: pressedItemID, from: previousLocation, to: location)
        } else {
            pointerDragState = .draggingCanvas
            panCanvas(from: previousLocation, to: location)
        }
    case let .draggingSelectedItem(itemID):
        moveSelectedItem(withID: itemID, from: previousLocation, to: location)
    case .draggingCanvas:
        panCanvas(from: previousLocation, to: location)
    case .idle:
        break
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前 macOS 也会在第一帧位移时立即进入 draggingCanvas 或 draggingSelectedItem，导致空白 click 可能丢失日志。
private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    switch pointerDragState {
    case let .pressed(pressedItemID, pressedItemWasSelected):
        if pressedItemWasSelected, let pressedItemID {
            pointerDragState = .draggingSelectedItem(itemID: pressedItemID)
            moveSelectedItem(withID: pressedItemID, from: previousLocation, to: location)
        } else {
            pointerDragState = .draggingCanvas
            panCanvas(from: previousLocation, to: location)
        }
    case let .draggingSelectedItem(itemID):
        moveSelectedItem(withID: itemID, from: previousLocation, to: location)
    case .draggingCanvas:
        panCanvas(from: previousLocation, to: location)
    case .idle:
        break
    }
}
```

### 修改后

- 两端都新增 `pointerDragActivationDistance = 4`，只有从 `pressedLocation` 到当前位置的累计位移超过 `4pt` 才会切换到拖动态。
- 如果尚未超过阈值，就继续保持在 `.pressed`，让 `handlePrimaryPointerUp(at:)` 仍然能走到既有的 click 日志分支。
- 一旦超过阈值，首帧真正的拖动位移会以 `pressedLocation` 为起点计算，从而保留直观的拖动手感。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:) / hasExceededPointerDragActivationDistance(from:to:)
// 功能说明: 修改后 iOS 为拖动切换增加 4pt 阈值；未超阈值时保留 click 路径，超阈值后再真正进入拖动态。
private static let pointerDragActivationDistance: CGFloat = 4

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

private func hasExceededPointerDragActivationDistance(
    from pressedLocation: CGPoint,
    to currentLocation: CGPoint
) -> Bool {
    let dx = currentLocation.x - pressedLocation.x
    let dy = currentLocation.y - pressedLocation.y
    let distanceSquared = (dx * dx) + (dy * dy)
    let thresholdSquared = Self.pointerDragActivationDistance * Self.pointerDragActivationDistance
    return distanceSquared >= thresholdSquared
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:) / hasExceededPointerDragActivationDistance(from:to:)
// 功能说明: 修改后 macOS 与 iOS 保持一致，先判断累计位移是否超过 4pt，再决定是否进入拖动态。
private static let pointerDragActivationDistance: CGFloat = 4

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

private func hasExceededPointerDragActivationDistance(
    from pressedLocation: CGPoint,
    to currentLocation: CGPoint
) -> Bool {
    let dx = currentLocation.x - pressedLocation.x
    let dy = currentLocation.y - pressedLocation.y
    let distanceSquared = (dx * dx) + (dy * dy)
    let thresholdSquared = Self.pointerDragActivationDistance * Self.pointerDragActivationDistance
    return distanceSquared >= thresholdSquared
}
```

## 结果

- 现在在 macOS / iOS 上点击空白处时，即使过程中伴随极轻微的 pointer 抖动，也能继续走 click 路径并稳定打印 `ClickSelection` 日志。
- 只有累计位移超过 `4pt` 时，才会真正进入拖动画布或拖动图片的状态，因此不会把正常点击误判为拖动。
- 这次修改没有改变既有的日志结构，只是让已有的 `handlePrimaryPointerUp(at:)` 点击日志分支能够更稳定地被执行。
