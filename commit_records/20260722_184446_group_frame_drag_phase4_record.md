# 20260722_184446_group_frame_drag_phase4_record

## 记录来源

- 时间戳来源：系统命令 `date +"%Y%m%d_%H%M%S"`，输出 `20260722_184446`。
- 记录对象：`group-frame-interaction` 阶段 4，实现 group frame 拖拽。
- 参考范围：当前 `git diff` 与工作区 changes。当前 changes 中仍显示 `.cursor/plans/group-frame-interaction_6e00e0c4.plan.md` 的既有变更，本记录只覆盖刚刚阶段 4 对 iOS/macOS controller 的代码改动。

## 修改概览

阶段 4 的核心变化是让 group 框本体可以被拖拽移动：

- iOS/macOS controller 新增 `PointerGroupDragState`。
- `PointerDragState` 新增 `draggingGroupFrame`。
- `groupFrameBody` 拖过阈值后进入 group frame 拖拽；`groupFrameResizeHandle` 仍保持 no-op。
- move 时通过 `camera.viewportToWorld` 计算 world-space delta，只移动 group frame，不移动框内 item。
- pointer up/cancel 时提交一次 `"move group frame"` history/autosave。
- macOS 同步更新 pointer state debug 描述。

## 修改前后说明

### 1. Pointer 状态结构

修改前，iOS controller 的 pointer drag 状态只覆盖 item、selection、crop、rotate、arrow、canvas pan 等场景，没有 group frame 拖拽状态。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型：iOSViewController.PointerDragState
// 功能注释：修改前没有 PointerGroupDragState，也没有 draggingGroupFrame，group frame body 命中后无法进入拖拽状态。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext,
        pointerModifiers: CanvasPointerModifiers
    )
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case draggingSelection(CanvasSelectionDragState)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}
```

修改后，iOS 新增 `PointerGroupDragState` 保存拖拽所需的 group id、初始 frame 和起始 world point，并在 `PointerDragState` 中新增 `draggingGroupFrame`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型：iOSViewController.PointerGroupDragState, iOSViewController.PointerDragState
// 功能注释：新增 group frame 拖拽状态，保存初始 frame 与 pointer 起点，用于计算 world-space 平移。
private struct PointerGroupDragState {
    let groupID: CanvasItemGroupID
    let initialFrame: CGRect
    let dragStartWorldLocation: CGPoint
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext,
        pointerModifiers: CanvasPointerModifiers
    )
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case draggingSelection(CanvasSelectionDragState)
    case draggingGroupFrame(PointerGroupDragState)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}
```

macOS 同步新增相同状态，保证跨平台 pointer flow 一致。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数/类型：macOSViewController.PointerGroupDragState, macOSViewController.PointerDragState
// 功能注释：macOS 侧补齐 group frame drag state，字段与 iOS 保持一致。
private struct PointerGroupDragState {
    let groupID: CanvasItemGroupID
    let initialFrame: CGRect
    let dragStartWorldLocation: CGPoint
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext,
        pointerModifiers: CanvasPointerModifiers
    )
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case draggingSelection(CanvasSelectionDragState)
    case draggingGroupFrame(PointerGroupDragState)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}
```

### 2. iOS：从 groupFrameBody 进入拖拽

修改前，iOS 中 `groupFrameBody` 和 `groupFrameResizeHandle` 都是 no-op。用户拖动 group 框时不会移动 group，也不会进入 history transaction。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerMove(to:from:)
// 功能注释：修改前 group frame target 被显式置 idle，避免误触发 canvas pan，但也没有实际拖拽能力。
case .groupFrameBody, .groupFrameResizeHandle:
    pointerDragState = .idle
case .unselectedItemBody, .blank:
    pointerDragState = .draggingCanvas
    panCanvas(from: pressedLocation, to: location)
```

修改后，`groupFrameBody` 在超过拖拽阈值后创建 group drag state，开始 `"move group frame"` history transaction，并立即应用第一次 frame 平移。`groupFrameResizeHandle` 仍然 no-op，留给阶段 5。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerMove(to:from:)
// 功能注释：groupFrameBody 进入 group frame 拖拽；resize handle 暂不启用，等待阶段 5。
case .groupFrameBody:
    guard
        let groupID = pressContext.targetGroupID,
        let groupDragState = makePointerGroupDragState(
            groupID: groupID,
            initialViewportLocation: pressedLocation
        )
    else {
        pointerDragState = .idle
        return
    }

    editorSession.beginHistoryTransaction(reason: "move group frame")
    guard moveGroupFrame(using: groupDragState, to: location) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .draggingGroupFrame(groupDragState)
case .groupFrameResizeHandle:
    pointerDragState = .idle
case .unselectedItemBody, .blank:
    pointerDragState = .draggingCanvas
    panCanvas(from: pressedLocation, to: location)
```

### 3. iOS：拖拽过程持续更新 frame

修改前，iOS 的 ongoing pointer move 只处理 item/selection/crop/rotate 等已有状态，没有 group frame ongoing move 分支。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerMove(to:from:)
// 功能注释：修改前没有 draggingGroupFrame 分支，group frame 无法跟随 pointer move。
case let .draggingSelectedItem(dragState):
    guard let updatedDragState = moveSelectedItem(
        using: dragState,
        to: location
    ) else {
        pointerDragState = .idle
        return
    }
    pointerDragState = .draggingSelectedItem(updatedDragState)
case let .draggingSelection(dragState):
    guard let updatedDragState = moveSelection(
        using: dragState,
        to: location
    ) else {
        pointerDragState = .idle
        return
    }
    pointerDragState = .draggingSelection(updatedDragState)
```

修改后，`draggingGroupFrame` 会在每次 move 时调用 `moveGroupFrame(...)`，只更新 group frame 并刷新 canvas。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerMove(to:from:)
// 功能注释：group frame 拖拽中只更新 group frame，不移动 group 内 item。
case let .draggingGroupFrame(groupDragState):
    guard moveGroupFrame(using: groupDragState, to: location) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }
```

### 4. iOS：创建和移动 group frame 的 helper

修改前，iOS 只有 item/selection drag helper，例如 `makeSelectedItemDragState(...)` 和 `moveSelectedItem(...)`，没有 group frame 专用 helper。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.makeSelectedItemDragState(...)
// 功能注释：修改前只有 item 拖拽状态构建，group frame 没有保存初始 frame 的拖拽状态。
private func makeSelectedItemDragState(
    itemID: CanvasItemID,
    initialViewportLocation: CGPoint
) -> CanvasSelectedItemDragState? {
    guard let movingItem = scene.boardItem(withID: itemID) else {
        return nil
    }

    return CanvasSelectedItemDragState(
        itemID: itemID,
        dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation),
        dragStartCenter: movingItem.center
    )
}
```

修改后，新增 `makePointerGroupDragState(...)` 和 `moveGroupFrame(...)`。移动逻辑基于 pointer world delta 对初始 frame 做 offset，然后调用 `editorSession.updateGroupFrame(...)`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.makePointerGroupDragState(...)
// 功能注释：读取 group 初始 frame，并把 pointer 起点转换到 world 坐标，用于后续计算平移量。
private func makePointerGroupDragState(
    groupID: CanvasItemGroupID,
    initialViewportLocation: CGPoint
) -> PointerGroupDragState? {
    guard let initialFrame = editorSession.groupFrame(withID: groupID) else {
        return nil
    }

    return PointerGroupDragState(
        groupID: groupID,
        initialFrame: initialFrame,
        dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation)
    )
}
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.moveGroupFrame(using:to:)
// 功能注释：根据当前 pointer world 坐标计算平移，更新 group frame；不移动任何 canvas item。
private func moveGroupFrame(
    using dragState: PointerGroupDragState,
    to location: CGPoint
) -> Bool {
    let currentWorldLocation = camera.viewportToWorld(location)
    let translation = CGPoint(
        x: currentWorldLocation.x - dragState.dragStartWorldLocation.x,
        y: currentWorldLocation.y - dragState.dragStartWorldLocation.y
    )
    let proposedFrame = dragState.initialFrame.offsetBy(
        dx: translation.x,
        dy: translation.y
    )
    guard editorSession.updateGroupFrame(
        withID: dragState.groupID,
        to: proposedFrame
    ) else {
        return editorSession.groupFrame(withID: dragState.groupID)
            == proposedFrame.standardized
    }

    requestCanvasRefresh(
        reason: "move group frame by \(describe(point: translation))"
    )
    return true
}
```

### 5. iOS：提交 history/autosave

修改前，pointer up/cancel 只提交 item/selection/crop/resize/arrow 等交互；group frame 没有独立提交分支。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerUp(at:modifiers:)
// 功能注释：修改前没有 draggingGroupFrame，group frame 拖拽不会产生一次性 history/autosave 提交。
case .draggingSelection:
    commitPendingPointerHistoryTransaction(autosaveReason: "move selection")
    clearAlignmentInteractionStateIfNeeded(
        refreshReason: "finish move alignment interaction"
    )
case .resizingSelectedItem:
    finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
    commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
```

修改后，iOS 在 pointer up 和 cancel 中都对 `draggingGroupFrame` 提交 `"move group frame"`，行为对齐现有 item drag 的提交方式。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerUp(at:modifiers:)
// 功能注释：group frame 拖拽结束后提交一次 pending history transaction，并触发 autosave。
case .draggingGroupFrame:
    commitPendingPointerHistoryTransaction(autosaveReason: "move group frame")
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerCancel()
// 功能注释：取消 pointer 时也沿用现有拖拽类交互的提交策略，提交当前 group frame 位置。
case .draggingGroupFrame:
    commitPendingPointerHistoryTransaction(autosaveReason: "move group frame")
```

### 6. macOS：从 groupFrameBody 进入拖拽

修改前，macOS 与 iOS 一样，`groupFrameBody` 和 `groupFrameResizeHandle` 都是 no-op。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.handlePrimaryPointerMove(to:from:)
// 功能注释：修改前 group frame 命中不会进入拖拽，只会把 pointer state 置 idle。
case .groupFrameBody, .groupFrameResizeHandle:
    pointerDragState = .idle
case .unselectedItemBody, .blank:
    pointerDragState = .draggingCanvas
    panCanvas(from: pressedLocation, to: location)
```

修改后，macOS 的 `groupFrameBody` 进入 `draggingGroupFrame`，并开始 `"move group frame"` history transaction。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.handlePrimaryPointerMove(to:from:)
// 功能注释：macOS group frame body 拖拽流程与 iOS 保持一致。
case .groupFrameBody:
    guard
        let groupID = pressContext.targetGroupID,
        let groupDragState = makePointerGroupDragState(
            groupID: groupID,
            initialViewportLocation: pressedLocation
        )
    else {
        pointerDragState = .idle
        return
    }

    editorSession.beginHistoryTransaction(reason: "move group frame")
    guard moveGroupFrame(using: groupDragState, to: location) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .draggingGroupFrame(groupDragState)
case .groupFrameResizeHandle:
    pointerDragState = .idle
```

### 7. macOS：移动 helper 与刷新

修改前，macOS 没有 group frame 拖拽 helper。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.moveSelectedItem(using:to:)
// 功能注释：修改前只有 item/selection move helper，group frame 没有独立的 frame update 路径。
private func moveSelectedItem(
    using dragState: CanvasSelectedItemDragState,
    to location: CGPoint
) -> CanvasSelectedItemDragState?
```

修改后，macOS 新增与 iOS 对等的 `makePointerGroupDragState(...)` 和 `moveGroupFrame(...)`，刷新入口使用 `refreshCanvas(...)`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.makePointerGroupDragState(...)
// 功能注释：记录 group 初始 frame 和 pointer world 起点，用于计算拖拽中的 frame offset。
private func makePointerGroupDragState(
    groupID: CanvasItemGroupID,
    initialViewportLocation: CGPoint
) -> PointerGroupDragState? {
    guard let initialFrame = editorSession.groupFrame(withID: groupID) else {
        return nil
    }

    return PointerGroupDragState(
        groupID: groupID,
        initialFrame: initialFrame,
        dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation)
    )
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.moveGroupFrame(using:to:)
// 功能注释：macOS 侧根据 world-space pointer delta 更新 group frame，并刷新 canvas。
private func moveGroupFrame(
    using dragState: PointerGroupDragState,
    to location: CGPoint
) -> Bool {
    let currentWorldLocation = camera.viewportToWorld(location)
    let translation = CGPoint(
        x: currentWorldLocation.x - dragState.dragStartWorldLocation.x,
        y: currentWorldLocation.y - dragState.dragStartWorldLocation.y
    )
    let proposedFrame = dragState.initialFrame.offsetBy(
        dx: translation.x,
        dy: translation.y
    )
    guard editorSession.updateGroupFrame(
        withID: dragState.groupID,
        to: proposedFrame
    ) else {
        return editorSession.groupFrame(withID: dragState.groupID)
            == proposedFrame.standardized
    }

    refreshCanvas(
        reason: "move group frame by \(describe(point: translation))"
    )
    return true
}
```

### 8. macOS：提交和调试描述

修改前，macOS pointer up/cancel 没有 group frame 提交分支，调试描述也不认识 `draggingGroupFrame`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.describe(pointerDragState:)
// 功能注释：修改前 debug 描述没有 draggingGroupFrame，后续日志无法区分 group frame 拖拽状态。
case .draggingSelectedItem:
    return "draggingSelectedItem"
case .draggingSelection:
    return "draggingSelection"
case .resizingSelectedItem:
    return "resizingSelectedItem"
```

修改后，macOS 提交 `"move group frame"`，并补充 debug state 名称。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.handlePrimaryPointerUp(at:modifiers:)
// 功能注释：group frame 拖拽结束后提交一次 pending history transaction，并触发 autosave。
case .draggingGroupFrame:
    commitPendingPointerHistoryTransaction(autosaveReason: "move group frame")
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.describe(pointerDragState:)
// 功能注释：补充 draggingGroupFrame 的日志描述，方便定位 pointer state 流转。
case .draggingGroupFrame:
    return "draggingGroupFrame"
```

## 验证记录

本次阶段 4 修改完成后已做过以下验证：

```bash
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：读取系统时间戳，用于生成本记录文件名和标题。
date +"%Y%m%d_%H%M%S"
```

```bash
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 macOS 目标可编译通过。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build
```

```bash
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 iOS Simulator 目标可编译通过。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' build
```

验证结果：

- `ReadLints`：无 linter errors。
- macOS build：通过。
- iOS Simulator build：通过。

