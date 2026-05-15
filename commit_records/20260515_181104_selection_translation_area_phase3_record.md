# 20260515_181104_selection_translation_area_phase3_record

## 记录范围

- 记录内容：
  - 将 `selectionTranslationArea` 从控制器中的占位分支，接入现有的移动分发链路。
  - 让 iOS / macOS 两个平台在 pointer move 时，都把 `selectionTranslationArea` 与 `selectedItemBody` 统一处理。
  - 让 iOS / macOS 两个平台在 history transaction reason 上，都把 `selectionTranslationArea` 归入 `move item` / `move selection` 语义。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 参考现状：
  - 生成本记录前，`git status --short` 仅显示上述两个控制器文件处于修改状态。
  - `selectionTranslationArea` 的契约层与几何命中层已在此前阶段完成；本次只记录控制器分发接线。
- 本记录不包含：
  - `CanvasEditOverlayHitTester` 的几何命中实现
  - `CanvasContextResolver` / `CanvasClickSelectionResolver` 的契约层映射
  - 任何测试代码变更

## 当前 changes 摘要

- 当前这一轮修改只影响 iOS / macOS 控制器，不涉及 renderer、resolver、scene。
- 修改前，`selectionTranslationArea` 虽然已经能在命中层产出，但控制器收到该 target 后会直接取消事务并回到 `.idle`。
- 修改后，`selectionTranslationArea` 与 `selectedItemBody` 复用同一条移动逻辑：
  - 单选时走 `moveSelectedItem(...)`
  - 多选时走 `moveSelection(...)`
- 同时，history transaction 的 reason 也与 `selectedItemBody` 对齐，不再提前 `return`。

## 修改一：iOS 控制器将 `selectionTranslationArea` 接入移动分支

### 修改前

- `handlePrimaryPointerMove(to:from:)` 中，`selectionTranslationArea` 是单独占位分支。
- 命中该 target 后会：
  - `cancelPendingHistoryTransaction()`
  - `pointerDragState = .idle`
- 因此即使命中层已经产出了 `selectionTranslationArea`，iOS 侧也不会触发真实移动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前 iOS 控制器把 selectionTranslationArea 当作占位 target 处理，命中后直接回到 idle，不进入 moveSelectedItem / moveSelection。
switch pressContext.targetKind {
case let .selectionHandle(handleRole):
    // ...
case let .groupSelectionHandle(handleRole):
    guard let resizeState = makeSelectionResizeState(
        handleRole: handleRole
    ) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .resizingSelection(resizeState)
    resizeSelection(using: resizeState, to: location)
case .selectionTranslationArea:
    editorSession.cancelPendingHistoryTransaction()
    pointerDragState = .idle
case .selectedItemBody:
    guard let itemID = pressContext.targetItemID else {
        pointerDragState = .idle
        return
    }
    // ...
case .unselectedItemBody, .blank:
    // ...
}
```

### 修改后

- `selectionTranslationArea` 和 `selectedItemBody` 合并为同一个 `case`。
- 因此 iOS 控制器现在会把它们都导向同一套移动逻辑。
- 这样命中选区平移热区后，单选/多选都会沿用现有的移动实现，不需要新增 scene 写回路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改后 iOS 控制器将 selectionTranslationArea 并入 selectedItemBody 的移动分支，复用现有 moveSelectedItem / moveSelection 流程。
switch pressContext.targetKind {
case let .selectionHandle(handleRole):
    // ...
case let .groupSelectionHandle(handleRole):
    guard let resizeState = makeSelectionResizeState(
        handleRole: handleRole
    ) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .resizingSelection(resizeState)
    resizeSelection(using: resizeState, to: location)
case .selectionTranslationArea, .selectedItemBody:
    guard let itemID = pressContext.targetItemID else {
        pointerDragState = .idle
        return
    }

    if interactionState.selectionCount > 1 {
        guard let dragState = makeSelectionDragState(
            initialViewportLocation: pressedLocation
        ) else {
            pointerDragState = .idle
            return
        }
        // 多选时继续复用 moveSelection(...)
        // ...
    } else {
        guard let dragState = makeSelectedItemDragState(
            itemID: itemID,
            initialViewportLocation: pressedLocation
        ) else {
            pointerDragState = .idle
            return
        }
        // 单选时继续复用 moveSelectedItem(...)
        // ...
    }
case .unselectedItemBody, .blank:
    // ...
}
```

## 修改二：iOS 控制器将 `selectionTranslationArea` 接入 move history reason

### 修改前

- `beginPointerHistoryTransactionIfNeeded(for:)` 中，`selectionTranslationArea` 单独 `return`。
- 这意味着即使后续真的开始移动，也不会按 `move item` / `move selection` 语义开启历史事务。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改前 iOS 控制器没有把 selectionTranslationArea 纳入 move history reason，而是直接 return。
switch pressContext.targetKind {
case .rotateHandle:
    reason = "rotate item"
case .groupRotateHandle:
    reason = "rotate selection"
case .cropHandle, .cropTranslationArea:
    reason = "crop item"
case .selectionHandle:
    reason = "resize item"
case .groupSelectionHandle:
    reason = "resize selection"
case .selectionTranslationArea:
    return
case .selectedItemBody:
    reason = interactionState.selectionCount > 1
        ? "move selection"
        : "move item"
case .unselectedItemBody, .blank:
    return
}
```

### 修改后

- `selectionTranslationArea` 和 `selectedItemBody` 共用同一个 reason 分支。
- 因此命中选区平移热区开始拖动时，iOS 侧也会进入正确的 move history transaction。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改后 iOS 控制器把 selectionTranslationArea 归入 move item / move selection 的历史事务语义。
switch pressContext.targetKind {
case .rotateHandle:
    reason = "rotate item"
case .groupRotateHandle:
    reason = "rotate selection"
case .cropHandle, .cropTranslationArea:
    reason = "crop item"
case .selectionHandle:
    reason = "resize item"
case .groupSelectionHandle:
    reason = "resize selection"
case .selectionTranslationArea, .selectedItemBody:
    reason = interactionState.selectionCount > 1
        ? "move selection"
        : "move item"
case .unselectedItemBody, .blank:
    return
}
```

## 修改三：macOS 控制器将 `selectionTranslationArea` 接入移动分支

### 修改前

- `handlePrimaryPointerMove(to:from:)` 中，macOS 和 iOS 一样，也把 `selectionTranslationArea` 当成占位 target。
- 命中该 target 时，直接取消事务并回到 `.idle`，不会触发真实移动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前 macOS 控制器同样没有把 selectionTranslationArea 接入真实移动分支。
switch pressContext.targetKind {
case let .selectionHandle(handleRole):
    // ...
case let .groupSelectionHandle(handleRole):
    guard let resizeState = makeSelectionResizeState(
        handleRole: handleRole
    ) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .resizingSelection(resizeState)
    resizeSelection(using: resizeState, to: location)
case .selectionTranslationArea:
    editorSession.cancelPendingHistoryTransaction()
    pointerDragState = .idle
case .selectedItemBody:
    guard let itemID = pressContext.targetItemID else {
        pointerDragState = .idle
        return
    }
    // ...
case .unselectedItemBody, .blank:
    // ...
}
```

### 修改后

- `selectionTranslationArea` 和 `selectedItemBody` 在 macOS 控制器中也合并成同一个 `case`。
- 因此 macOS 和 iOS 在移动分发行为上保持完全对称。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改后 macOS 控制器将 selectionTranslationArea 并入 selectedItemBody 的移动分支，直接复用现有移动实现。
switch pressContext.targetKind {
case let .selectionHandle(handleRole):
    // ...
case let .groupSelectionHandle(handleRole):
    guard let resizeState = makeSelectionResizeState(
        handleRole: handleRole
    ) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .resizingSelection(resizeState)
    resizeSelection(using: resizeState, to: location)
case .selectionTranslationArea, .selectedItemBody:
    guard let itemID = pressContext.targetItemID else {
        pointerDragState = .idle
        return
    }

    if interactionState.selectionCount > 1 {
        guard let dragState = makeSelectionDragState(
            initialViewportLocation: pressedLocation
        ) else {
            pointerDragState = .idle
            return
        }
        // 多选时继续复用 moveSelection(...)
        // ...
    } else {
        guard let dragState = makeSelectedItemDragState(
            itemID: itemID,
            initialViewportLocation: pressedLocation
        ) else {
            pointerDragState = .idle
            return
        }
        // 单选时继续复用 moveSelectedItem(...)
        // ...
    }
case .unselectedItemBody, .blank:
    // ...
}
```

## 修改四：macOS 控制器将 `selectionTranslationArea` 接入 move history reason

### 修改前

- `beginPointerHistoryTransactionIfNeeded(for:)` 中，macOS 也会对 `selectionTranslationArea` 直接 `return`。
- 这使得命中该 target 后，无法进入 `move item` / `move selection` 的历史事务语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改前 macOS 控制器没有把 selectionTranslationArea 纳入 move history reason。
switch pressContext.targetKind {
case .rotateHandle:
    reason = "rotate item"
case .groupRotateHandle:
    reason = "rotate selection"
case .cropHandle, .cropTranslationArea:
    reason = "crop item"
case .selectionHandle:
    reason = "resize item"
case .groupSelectionHandle:
    reason = "resize selection"
case .selectionTranslationArea:
    return
case .selectedItemBody:
    reason = interactionState.selectionCount > 1
        ? "move selection"
        : "move item"
case .unselectedItemBody, .blank:
    return
}
```

### 修改后

- `selectionTranslationArea` 与 `selectedItemBody` 共用同一条 move reason 分支。
- 这样 macOS 拖动选区平移热区时，也会按既有移动事务语义提交历史。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: beginPointerHistoryTransactionIfNeeded(for:)
// 功能说明: 修改后 macOS 控制器把 selectionTranslationArea 与 selectedItemBody 统一归入 move item / move selection 语义。
switch pressContext.targetKind {
case .rotateHandle:
    reason = "rotate item"
case .groupRotateHandle:
    reason = "rotate selection"
case .cropHandle, .cropTranslationArea:
    reason = "crop item"
case .selectionHandle:
    reason = "resize item"
case .groupSelectionHandle:
    reason = "resize selection"
case .selectionTranslationArea, .selectedItemBody:
    reason = interactionState.selectionCount > 1
        ? "move selection"
        : "move item"
case .unselectedItemBody, .blank:
    return
}
```

## 结果边界

- 到本次 `phase 3` 结束时，`selectionTranslationArea` 已经不再只是命中语义，而是正式接入了真实移动分发链路。
- 当前行为边界是：
  - 命中选区平移热区后，单选时复用 `moveSelectedItem(...)`
  - 命中选区平移热区后，多选时复用 `moveSelection(...)`
  - history transaction 也复用既有 `move item` / `move selection` reason
- 本次没有新增新的 scene 写回逻辑，也没有改点击选择语义。

## 验证情况

- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - 当前两个控制器文件的最新内容
- 本次实现阶段已执行并通过：
  - `ReadLints` 检查
  - `xcodebuild -destination "generic/platform=iOS" build`
  - `xcodebuild -destination "generic/platform=macOS" build`
