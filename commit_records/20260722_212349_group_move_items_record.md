# 20260722_212349_group_move_items_record

## 记录范围

本记录如实对应刚刚完成的 group 移动行为修正：拖动 group 本体时，group frame 和 drag 开始时的成员 item 一起平移；拖动 group 边框 resize handle 时仍只改变 group frame，不移动 item。

本次实际修改的代码文件：

- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前 `git status` 中还存在 `.cursor/plans/group_move_items_a998b21d.plan.md` 的修改；该文件是本次方案记录文件，不属于本记录覆盖的运行时代码改动。

## 修改前

### `CanvasEditorSession` 没有 group 成员几何快照 API

修改前，外部只能读取 group 本身和 group frame，无法从 session 侧拿到当前 group `itemIDs` 对应的 item 初始几何。因此 group drag 状态无法固定“拖拽开始时的成员集合”。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前只暴露 group 和 group frame 查询，没有成员 item 几何快照。
// 函数名：CanvasEditorSession.group(withID:) / groupFrame(withID:)
func group(withID groupID: CanvasItemGroupID) -> CanvasItemGroup? {
    groups.first(where: { $0.id == groupID })
}

func groupFrame(withID groupID: CanvasItemGroupID) -> CGRect? {
    group(withID: groupID)?.frame
}
```

### `CanvasEditorSession` 只能单独更新 group frame

修改前，`updateGroupFrame(...)` 只能写入 group frame。group 本体拖拽调用它时，只会移动框，不会移动框内 item。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前只更新 group frame，不能和成员 item 几何作为一次共享写入。
// 函数名：CanvasEditorSession.updateGroupFrame(withID:to:recordHistory:reconcileMembership:)
@discardableResult
func updateGroupFrame(
    withID groupID: CanvasItemGroupID,
    to frame: CGRect,
    recordHistory: Bool = false,
    reconcileMembership: Bool = true
) -> Bool {
    // ... 校验 group 和 frame
    groups[groupIndex].frame = standardizedFrame
    expandBoardIfNeeded(toInclude: standardizedFrame)
    if reconcileMembership {
        _ = reconcileItemMembership(forGroupID: groupID)
    }

    return true
}
```

### iOS group drag 状态只记录 frame

修改前，iOS 的 `PointerGroupDragState` 只记录 `groupID`、初始 frame 和 pointer 起点，不记录成员 item 的初始几何。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 group drag 状态没有成员 item 几何快照。
// 函数名：iOSViewController.PointerGroupDragState
private struct PointerGroupDragState {
    let groupID: CanvasItemGroupID
    let initialFrame: CGRect
    let dragStartWorldLocation: CGPoint
}
```

### iOS group drag 只移动 group frame

修改前，iOS 的 `moveGroupFrame(...)` 只根据 pointer translation 生成 `proposedFrame`，然后调用 `updateGroupFrame(...)`。这会导致拖动 group 时只有框移动，内部 item 不跟随。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 iOS group 本体拖拽只更新 frame，不移动成员 item。
// 函数名：iOSViewController.moveGroupFrame(using:to:)
let proposedFrame = dragState.initialFrame.offsetBy(
    dx: translation.x,
    dy: translation.y
)
guard editorSession.updateGroupFrame(
    withID: dragState.groupID,
    to: proposedFrame,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: dragState.groupID)
        == proposedFrame.standardized
}
```

### macOS group drag 与 iOS 同样只移动 frame

修改前，macOS 的状态和移动逻辑与 iOS 一样，也没有成员几何快照，拖动 group 本体时只更新 group frame。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前 macOS group 本体拖拽只更新 frame，不移动成员 item。
// 函数名：macOSViewController.moveGroupFrame(using:to:)
guard editorSession.updateGroupFrame(
    withID: dragState.groupID,
    to: proposedFrame,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: dragState.groupID)
        == proposedFrame.standardized
}
```

## 修改后

### `CanvasEditorSession` 新增 group 成员几何快照查询

新增 `groupMemberGeometries(withID:)`。它按当前 group 的 `itemIDs` 查找仍存在的 board item，并转换为 `CanvasBoardItemGeometry`。这样 group drag 开始时可以固定成员集合，避免拖动途中因为 membership reconcile 变化导致新 item 突然被带着走。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：按 group.itemIDs 获取当前存在成员 item 的几何快照，供 group drag 固定起始成员集合。
// 函数名：CanvasEditorSession.groupMemberGeometries(withID:)
func groupMemberGeometries(withID groupID: CanvasItemGroupID) -> [CanvasBoardItemGeometry] {
    guard let group = group(withID: groupID) else {
        return []
    }

    return group.itemIDs.compactMap { itemID in
        scene.boardItem(withID: itemID).map(CanvasBoardItemGeometry.init(item:))
    }
}
```

### `CanvasEditorSession` 新增 frame + member geometry 共享写入 API

新增 `updateGroupFrameAndMemberGeometries(...)`，用于在同一次 shared session 调用里更新 group frame 和成员 item 几何。成员 item 更新走现有 `scene.applyBoardItemGeometries(...)`，仍保持 item 几何写入路径集中在 shared 层。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：同步写入 group frame 和成员 item 几何；group 本体拖拽使用该 API。
// 函数名：CanvasEditorSession.updateGroupFrameAndMemberGeometries(withID:to:memberGeometries:recordHistory:reconcileMembership:)
@discardableResult
func updateGroupFrameAndMemberGeometries(
    withID groupID: CanvasItemGroupID,
    to frame: CGRect,
    memberGeometries: [CanvasBoardItemGeometry],
    recordHistory: Bool = false,
    reconcileMembership: Bool = true
) -> Bool {
    // ... 校验 group 和 frame
    let existingMemberGeometries = memberGeometries.filter { geometry in
        scene.boardItem(withID: geometry.itemID) != nil
    }
    let didFrameChange = groups[groupIndex].frame != standardizedFrame
    let didMemberGeometryChange = existingMemberGeometries.contains { geometry in
        guard let item = scene.boardItem(withID: geometry.itemID) else {
            return false
        }

        return CanvasBoardItemGeometry(item: item) != geometry
    }
    guard didFrameChange || didMemberGeometryChange || reconcileMembership else {
        return true
    }

    if didMemberGeometryChange {
        guard let updatedItems = scene.applyBoardItemGeometries(existingMemberGeometries) else {
            return false
        }
        for updatedItem in updatedItems {
            expandBoardIfNeeded(toInclude: updatedItem.worldBounds)
        }
    }

    if didFrameChange {
        groups[groupIndex].frame = standardizedFrame
        expandBoardIfNeeded(toInclude: standardizedFrame)
    }
    if reconcileMembership {
        _ = reconcileItemMembership(forGroupID: groupID)
    }

    return true
}
```

### iOS group drag 状态保存起始成员几何

iOS 的 `PointerGroupDragState` 新增 `initialMemberGeometries`。创建 drag state 时从 `CanvasEditorSession.groupMemberGeometries(withID:)` 读取，固定本次拖拽要跟随移动的成员 item。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS group drag 状态保存拖拽开始时的成员 item 几何。
// 函数名：iOSViewController.PointerGroupDragState
private struct PointerGroupDragState {
    let groupID: CanvasItemGroupID
    let initialFrame: CGRect
    let initialMemberGeometries: [CanvasBoardItemGeometry]
    let dragStartWorldLocation: CGPoint
}
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：创建 iOS group drag state 时记录当前 group 成员几何快照。
// 函数名：iOSViewController.makePointerGroupDragState(groupID:initialViewportLocation:)
return PointerGroupDragState(
    groupID: groupID,
    initialFrame: initialFrame,
    initialMemberGeometries: editorSession.groupMemberGeometries(withID: groupID),
    dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation)
)
```

### iOS group 本体拖拽同步移动 frame 和成员 item

iOS 的 `moveGroupFrame(...)` 现在会用同一个 world translation 生成 `proposedFrame` 和 `proposedMemberGeometries`，再调用 `updateGroupFrameAndMemberGeometries(...)` 一起写入。`reconcileMembership` 仍传 `false`，保持 pointer move 期间不每帧重算 membership。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS group 本体拖拽时，用同一个 world delta 平移 frame 和起始成员 item。
// 函数名：iOSViewController.moveGroupFrame(using:to:)
let proposedFrame = dragState.initialFrame.offsetBy(
    dx: translation.x,
    dy: translation.y
)
let proposedMemberGeometries = dragState.initialMemberGeometries.map { geometry in
    CanvasBoardItemGeometry(
        itemID: geometry.itemID,
        center: CGPoint(
            x: geometry.center.x + translation.x,
            y: geometry.center.y + translation.y
        ),
        size: geometry.size,
        rotationRadians: geometry.rotationRadians
    )
}
guard editorSession.updateGroupFrameAndMemberGeometries(
    withID: dragState.groupID,
    to: proposedFrame,
    memberGeometries: proposedMemberGeometries,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: dragState.groupID)
        == proposedFrame.standardized
}
```

### macOS group drag 同步接入同样语义

macOS 的 `PointerGroupDragState` 和 `moveGroupFrame(...)` 与 iOS 保持一致。拖动 group 本体时，frame 和起始成员 item 一起平移。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS group drag 状态保存拖拽开始时的成员 item 几何。
// 函数名：macOSViewController.PointerGroupDragState
private struct PointerGroupDragState {
    let groupID: CanvasItemGroupID
    let initialFrame: CGRect
    let initialMemberGeometries: [CanvasBoardItemGeometry]
    let dragStartWorldLocation: CGPoint
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS group 本体拖拽时，用同一个 world delta 平移 frame 和起始成员 item。
// 函数名：macOSViewController.moveGroupFrame(using:to:)
let proposedMemberGeometries = dragState.initialMemberGeometries.map { geometry in
    CanvasBoardItemGeometry(
        itemID: geometry.itemID,
        center: CGPoint(
            x: geometry.center.x + translation.x,
            y: geometry.center.y + translation.y
        ),
        size: geometry.size,
        rotationRadians: geometry.rotationRadians
    )
}
guard editorSession.updateGroupFrameAndMemberGeometries(
    withID: dragState.groupID,
    to: proposedFrame,
    memberGeometries: proposedMemberGeometries,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: dragState.groupID)
        == proposedFrame.standardized
}
```

## 保持不变的行为

### group resize 仍然只改变 frame

拖动 group 边框 resize handle 时，iOS 和 macOS 仍调用 `updateGroupFrame(..., reconcileMembership: false)`，不会使用 `updateGroupFrameAndMemberGeometries(...)`，因此不会移动或缩放内部 item。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS group resize 仍只更新 frame，不移动成员 item。
// 函数名：iOSViewController.resizeGroupFrame(using:to:)
guard editorSession.updateGroupFrame(
    withID: resizeState.groupID,
    to: proposedFrame,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: resizeState.groupID)
        == proposedFrame.standardized
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS group resize 仍只更新 frame，不移动成员 item。
// 函数名：macOSViewController.resizeGroupFrame(using:to:)
guard editorSession.updateGroupFrame(
    withID: resizeState.groupID,
    to: proposedFrame,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: resizeState.groupID)
        == proposedFrame.standardized
}
```

## 行为变化

- 拖动 group 本体时，group frame 和拖拽开始时 `group.itemIDs` 对应的 item 会一起平移。
- 本次 drag 的跟随成员集合固定为 drag 开始时的成员 item；拖动过程中不会动态加入新 item。
- 拖动 group resize handle 时，只改变 group frame，不移动、不缩放 item。
- pointer move 期间仍不每帧 reconcile membership；最终 membership 继续由现有 pointer commit 前 reconcile 逻辑收敛。
- history/autosave 仍复用已有 pending transaction，frame 变化、成员 item 几何变化和最终 membership 变化会进入同一个 undo entry。

## 验证记录

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：检查本次修改文件的 linter 诊断。
ReadLints: CanvasEditorSession.swift, iOSViewController.swift, macOSViewController.swift
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 macOS target 编译通过。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 iOS Simulator target 编译通过。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' build
```
