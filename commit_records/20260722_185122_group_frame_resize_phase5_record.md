# 20260722_185122_group_frame_resize_phase5_record

## 记录来源

- 时间戳来源：系统命令 `date +"%Y%m%d_%H%M%S"`，输出 `20260722_185122`。
- 记录对象：`group-frame-interaction` 阶段 5，实现 group frame 缩放。
- 参考范围：当前 `git diff` 与工作区 changes。当前 changes 中仍显示 `.cursor/plans/group-frame-interaction_6e00e0c4.plan.md` 的既有变更，本记录只覆盖刚刚阶段 5 对 iOS/macOS controller 的代码改动。

## 修改概览

阶段 5 的核心变化是让 group 框的 8 个 resize handles 可用于缩放 group frame：

- iOS/macOS controller 新增 `PointerGroupResizeState`。
- `PointerDragState` 新增 `resizingGroupFrame`。
- `groupFrameResizeHandle(role:)` 拖过阈值后进入 group frame 缩放。
- 缩放逻辑复用 `CanvasSelectionHandleRole` 的 8 个方向语义。
- 状态保存初始 frame、初始 handle 锚点、pointer 起始 world 坐标和最小尺寸。
- move 时根据 pointer world delta 推动初始 handle 锚点，避免缩放开始时 frame 跳变。
- 最小尺寸约束为 `80 x 60`。
- pointer up/cancel 时提交一次 `"resize group frame"` history/autosave。
- 缩放只改变 group frame，不移动、不缩放框内 item。

## 修改前后说明

### 1. iOS：新增 group resize pointer state

修改前，iOS 只有 `PointerGroupDragState` 和 `draggingGroupFrame`，group frame 只能移动，不能缩放。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型：iOSViewController.PointerGroupDragState, iOSViewController.PointerDragState
// 功能注释：修改前只支持 group frame 拖拽状态，没有 group frame resize 状态。
private struct PointerGroupDragState {
    let groupID: CanvasItemGroupID
    let initialFrame: CGRect
    let dragStartWorldLocation: CGPoint
}

private enum PointerDragState {
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case draggingSelection(CanvasSelectionDragState)
    case draggingGroupFrame(PointerGroupDragState)
    case resizingSelectedItem(PointerResizeState)
}
```

修改后，iOS 新增 `PointerGroupResizeState`，并在 `PointerDragState` 中新增 `resizingGroupFrame`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型：iOSViewController.PointerGroupResizeState, iOSViewController.PointerDragState
// 功能注释：保存 group resize 的初始 frame、handle role、初始锚点、pointer 起点和最小尺寸。
private struct PointerGroupResizeState {
    let groupID: CanvasItemGroupID
    let handleRole: CanvasSelectionHandleRole
    let initialFrame: CGRect
    let initialDraggedAnchor: CGPoint
    let dragStartWorldLocation: CGPoint
    let minimumSize: CGSize
}

private enum PointerDragState {
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case draggingSelection(CanvasSelectionDragState)
    case draggingGroupFrame(PointerGroupDragState)
    case resizingGroupFrame(PointerGroupResizeState)
    case resizingSelectedItem(PointerResizeState)
}
```

### 2. iOS：最小尺寸约束

修改前，controller 只有普通 item resize 的 viewport 最小尺寸常量，group frame 没有独立的 world-space 最小尺寸。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型：iOSViewController static constants
// 功能注释：修改前只有普通 item resize 使用的 viewport 最小尺寸。
private static let minimumResizeViewportDimension: CGFloat = 28
```

修改后，新增 `minimumGroupFrameSize = 80 x 60`，用于 group frame 的 world-space frame 约束。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型：iOSViewController static constants
// 功能注释：group frame 缩放最小尺寸固定为 80 x 60，防止框被缩到不可操作。
private static let minimumResizeViewportDimension: CGFloat = 28
private static let minimumGroupFrameSize = CGSize(width: 80, height: 60)
```

### 3. iOS：从 resize handle 进入缩放

修改前，`groupFrameResizeHandle` 是 no-op，命中 handle 后不会产生缩放行为。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerMove(to:from:)
// 功能注释：修改前 groupFrameResizeHandle 被显式置 idle，阶段 4 只启用了 groupFrameBody 拖拽。
case .groupFrameResizeHandle:
    pointerDragState = .idle
```

修改后，`groupFrameResizeHandle(role:)` 创建 `PointerGroupResizeState`，开始 `"resize group frame"` history transaction，并应用第一次缩放。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerMove(to:from:)
// 功能注释：resize handle 拖过阈值后进入 group frame 缩放；role 复用 CanvasSelectionHandleRole。
case let .groupFrameResizeHandle(handleRole):
    guard
        let groupID = pressContext.targetGroupID,
        let groupResizeState = makePointerGroupResizeState(
            groupID: groupID,
            handleRole: handleRole,
            initialViewportLocation: pressedLocation
        )
    else {
        pointerDragState = .idle
        return
    }

    editorSession.beginHistoryTransaction(reason: "resize group frame")
    guard resizeGroupFrame(using: groupResizeState, to: location) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .resizingGroupFrame(groupResizeState)
```

### 4. iOS：缩放中持续更新 frame

修改前，ongoing move 中没有 `resizingGroupFrame` 分支，只能处理普通 item resize、selection resize 等状态。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerMove(to:from:)
// 功能注释：修改前没有 group frame resize 的持续更新分支。
case let .resizingSelectedItem(resizeState):
    resizeSelectedItem(using: resizeState, to: location)
case let .resizingSelection(resizeState):
    resizeSelection(using: resizeState, to: location)
```

修改后，`resizingGroupFrame` 会在 move 时持续调用 `resizeGroupFrame(...)`，只更新 group frame。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerMove(to:from:)
// 功能注释：group frame 缩放过程中持续更新 group frame，不影响框内 item。
case let .resizingGroupFrame(groupResizeState):
    guard resizeGroupFrame(using: groupResizeState, to: location) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }
```

### 5. iOS：创建 group resize state

修改前，没有 group frame resize state 构建 helper。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.makePointerGroupDragState(...)
// 功能注释：修改前只有 group drag state，保存 frame 和 pointer 起点用于平移。
private func makePointerGroupDragState(
    groupID: CanvasItemGroupID,
    initialViewportLocation: CGPoint
) -> PointerGroupDragState?
```

修改后，新增 `makePointerGroupResizeState(...)`。它读取当前 group frame，标准化后保存初始 dragged anchor，并将 pointer 起点转换为 world 坐标。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.makePointerGroupResizeState(...)
// 功能注释：保存缩放起点，避免开始缩放时 frame 跳到 pointer 位置。
private func makePointerGroupResizeState(
    groupID: CanvasItemGroupID,
    handleRole: CanvasSelectionHandleRole,
    initialViewportLocation: CGPoint
) -> PointerGroupResizeState? {
    guard let initialFrame = editorSession.groupFrame(withID: groupID)?.standardized,
          initialFrame.width > 0,
          initialFrame.height > 0
    else {
        return nil
    }

    return PointerGroupResizeState(
        groupID: groupID,
        handleRole: handleRole,
        initialFrame: initialFrame,
        initialDraggedAnchor: groupResizeDraggedAnchor(
            for: handleRole,
            in: initialFrame
        ),
        dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation),
        minimumSize: Self.minimumGroupFrameSize
    )
}
```

### 6. iOS：缩放计算与刷新

修改前，group frame 只有 `moveGroupFrame(...)`，通过 offset 初始 frame 实现平移；没有 resize frame 计算。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.moveGroupFrame(using:to:)
// 功能注释：修改前 group frame 只支持整体平移，不支持根据 handle 调整边界。
private func moveGroupFrame(
    using dragState: PointerGroupDragState,
    to location: CGPoint
) -> Bool
```

修改后，新增 `resizeGroupFrame(...)`。它使用 pointer world delta 推动初始 dragged anchor，再交给 `groupFrame(...)` 生成约束后的 frame。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.resizeGroupFrame(using:to:)
// 功能注释：根据 pointer world delta 缩放 group frame，只更新 group frame，不移动 item。
private func resizeGroupFrame(
    using resizeState: PointerGroupResizeState,
    to location: CGPoint
) -> Bool {
    let currentWorldLocation = camera.viewportToWorld(location)
    let pointerTranslation = CGPoint(
        x: currentWorldLocation.x - resizeState.dragStartWorldLocation.x,
        y: currentWorldLocation.y - resizeState.dragStartWorldLocation.y
    )
    let draggedAnchor = CGPoint(
        x: resizeState.initialDraggedAnchor.x + pointerTranslation.x,
        y: resizeState.initialDraggedAnchor.y + pointerTranslation.y
    )
    let proposedFrame = groupFrame(
        from: resizeState.initialFrame,
        handleRole: resizeState.handleRole,
        draggedAnchor: draggedAnchor,
        minimumSize: resizeState.minimumSize
    )
    guard editorSession.updateGroupFrame(
        withID: resizeState.groupID,
        to: proposedFrame
    ) else {
        return editorSession.groupFrame(withID: resizeState.groupID)
            == proposedFrame.standardized
    }

    requestCanvasRefresh(
        reason: "resize group frame \(String(describing: resizeState.handleRole))"
    )
    return true
}
```

### 7. iOS：8 向 handle frame 计算

修改前，没有 group frame 专用的 handle anchor 与 frame 计算逻辑。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController
// 功能注释：修改前 group frame resize 没有固定边/固定角规则。
// No group frame resize geometry helpers.
```

修改后，`groupResizeDraggedAnchor(...)` 按 8 个 `CanvasSelectionHandleRole` 取初始锚点；`groupFrame(...)` 根据被拖动锚点和最小尺寸生成标准化 frame。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.groupResizeDraggedAnchor(for:in:)
// 功能注释：根据 handle role 获取初始被拖动锚点，top/leading/trailing/bottom 使用边中点。
private func groupResizeDraggedAnchor(
    for handleRole: CanvasSelectionHandleRole,
    in frame: CGRect
) -> CGPoint {
    let frame = frame.standardized
    switch handleRole {
    case .topLeading:
        return CGPoint(x: frame.minX, y: frame.minY)
    case .top:
        return CGPoint(x: frame.midX, y: frame.minY)
    case .topTrailing:
        return CGPoint(x: frame.maxX, y: frame.minY)
    case .trailing:
        return CGPoint(x: frame.maxX, y: frame.midY)
    case .bottomTrailing:
        return CGPoint(x: frame.maxX, y: frame.maxY)
    case .bottom:
        return CGPoint(x: frame.midX, y: frame.maxY)
    case .bottomLeading:
        return CGPoint(x: frame.minX, y: frame.maxY)
    case .leading:
        return CGPoint(x: frame.minX, y: frame.midY)
    }
}
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.groupFrame(from:handleRole:draggedAnchor:minimumSize:)
// 功能注释：按 handle role 调整对应边或角，并用 80 x 60 最小尺寸约束 frame。
private func groupFrame(
    from initialFrame: CGRect,
    handleRole: CanvasSelectionHandleRole,
    draggedAnchor: CGPoint,
    minimumSize: CGSize
) -> CGRect {
    let frame = initialFrame.standardized
    let minimumWidth = max(minimumSize.width, 1)
    let minimumHeight = max(minimumSize.height, 1)

    switch handleRole {
    case .topLeading:
        let minX = min(draggedAnchor.x, frame.maxX - minimumWidth)
        let minY = min(draggedAnchor.y, frame.maxY - minimumHeight)
        return CGRect(
            x: minX,
            y: minY,
            width: frame.maxX - minX,
            height: frame.maxY - minY
        ).standardized
    case .trailing:
        let maxX = max(draggedAnchor.x, frame.minX + minimumWidth)
        return CGRect(
            x: frame.minX,
            y: frame.minY,
            width: maxX - frame.minX,
            height: frame.height
        ).standardized
    case .bottom:
        let maxY = max(draggedAnchor.y, frame.minY + minimumHeight)
        return CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: maxY - frame.minY
        ).standardized
    default:
        return frame
    }
}
```

说明：实际代码覆盖全部 8 个 handle；上方代码块保留代表性分支，避免记录文件过长。

### 8. iOS：提交 history/autosave

修改前，pointer up/cancel 只提交 group frame move，不提交 resize。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerUp(at:modifiers:)
// 功能注释：修改前只有 draggingGroupFrame 的提交分支。
case .draggingGroupFrame:
    commitPendingPointerHistoryTransaction(autosaveReason: "move group frame")
case .resizingSelectedItem:
    finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
    commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
```

修改后，pointer up/cancel 都会对 group frame resize 提交一次 `"resize group frame"`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerUp(at:modifiers:)
// 功能注释：group frame 缩放结束后提交 pending history transaction，并触发 autosave。
case .resizingGroupFrame:
    commitPendingPointerHistoryTransaction(autosaveReason: "resize group frame")
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数：iOSViewController.handlePrimaryPointerCancel()
// 功能注释：取消 pointer 时沿用已有拖拽类交互策略，提交当前 group frame 尺寸。
case .resizingGroupFrame:
    commitPendingPointerHistoryTransaction(autosaveReason: "resize group frame")
```

### 9. macOS：同步新增 resize state 和 flow

修改前，macOS 与 iOS 一样，只支持 `draggingGroupFrame`，`groupFrameResizeHandle` 是 no-op。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数/类型：macOSViewController.PointerDragState
// 功能注释：修改前 macOS 没有 resizingGroupFrame，resize handle 不会进入交互状态。
private enum PointerDragState {
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case draggingSelection(CanvasSelectionDragState)
    case draggingGroupFrame(PointerGroupDragState)
    case resizingSelectedItem(PointerResizeState)
}
```

修改后，macOS 新增与 iOS 对等的 `PointerGroupResizeState`、`resizingGroupFrame` 和 `minimumGroupFrameSize`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数/类型：macOSViewController.PointerGroupResizeState, macOSViewController.PointerDragState
// 功能注释：macOS 侧保存 group resize 的初始几何和 pointer 起点，行为与 iOS 对齐。
private struct PointerGroupResizeState {
    let groupID: CanvasItemGroupID
    let handleRole: CanvasSelectionHandleRole
    let initialFrame: CGRect
    let initialDraggedAnchor: CGPoint
    let dragStartWorldLocation: CGPoint
    let minimumSize: CGSize
}

private enum PointerDragState {
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case draggingSelection(CanvasSelectionDragState)
    case draggingGroupFrame(PointerGroupDragState)
    case resizingGroupFrame(PointerGroupResizeState)
    case resizingSelectedItem(PointerResizeState)
}

private static let minimumGroupFrameSize = CGSize(width: 80, height: 60)
```

### 10. macOS：resize helper、提交和调试描述

修改前，macOS 没有 group resize helper，也没有 `resizingGroupFrame` 的 debug 描述。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.describe(pointerDragState:)
// 功能注释：修改前 debug 描述只能识别 draggingGroupFrame，不能识别 group resize。
case .draggingGroupFrame:
    return "draggingGroupFrame"
case .resizingSelectedItem:
    return "resizingSelectedItem"
```

修改后，macOS 新增 `makePointerGroupResizeState(...)`、`resizeGroupFrame(...)`、`groupResizeDraggedAnchor(...)`、`groupFrame(...)`，并补充 `resizingGroupFrame` debug 描述。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.resizeGroupFrame(using:to:)
// 功能注释：macOS 侧根据 pointer world delta 生成新的 group frame，并刷新 canvas。
private func resizeGroupFrame(
    using resizeState: PointerGroupResizeState,
    to location: CGPoint
) -> Bool {
    let currentWorldLocation = camera.viewportToWorld(location)
    let pointerTranslation = CGPoint(
        x: currentWorldLocation.x - resizeState.dragStartWorldLocation.x,
        y: currentWorldLocation.y - resizeState.dragStartWorldLocation.y
    )
    let draggedAnchor = CGPoint(
        x: resizeState.initialDraggedAnchor.x + pointerTranslation.x,
        y: resizeState.initialDraggedAnchor.y + pointerTranslation.y
    )
    let proposedFrame = groupFrame(
        from: resizeState.initialFrame,
        handleRole: resizeState.handleRole,
        draggedAnchor: draggedAnchor,
        minimumSize: resizeState.minimumSize
    )
    guard editorSession.updateGroupFrame(
        withID: resizeState.groupID,
        to: proposedFrame
    ) else {
        return editorSession.groupFrame(withID: resizeState.groupID)
            == proposedFrame.standardized
    }

    refreshCanvas(
        reason: "resize group frame \(String(describing: resizeState.handleRole))"
    )
    return true
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：macOSViewController.handlePrimaryPointerUp(at:modifiers:), macOSViewController.describe(pointerDragState:)
// 功能注释：group frame resize 结束后提交 history/autosave，并补充 pointer state 日志名称。
case .resizingGroupFrame:
    commitPendingPointerHistoryTransaction(autosaveReason: "resize group frame")

case .resizingGroupFrame:
    return "resizingGroupFrame"
```

## 验证记录

本次阶段 5 修改完成后已做过以下验证：

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

