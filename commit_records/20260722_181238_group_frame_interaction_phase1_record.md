# 20260722_181238_group_frame_interaction_phase1_record

## 记录范围

本记录基于当前 `git status --short`、`git diff --stat` 与 `git diff -- MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift` 整理，不包含原始 diff。

当前 changes：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 当前工作区变更
 M MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
```

变更规模：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 git diff --stat 摘要
MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift |   7 +-
MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift  | 193 ++++++++++++++++++++-
2 files changed, 193 insertions(+), 7 deletions(-)
```

本次实施的是 `group-frame-interaction_6e00e0c4.plan.md` 的阶段 1：新增 group 选择态、查询和 frame 更新 API。没有实施 hit-test、overlay、拖拽、缩放或自动归组。

## 修改前

修改前，`CanvasEditorSession` 只有 item selection，selection 状态由 `CanvasInteractionState` 表示。group 只有数据数组 `groups`，没有独立的交互选择态。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - CanvasEditorSession properties 修改前
// 功能说明：旧状态只有 item selection，没有 group selection。
final class CanvasEditorSession {
    let scene = CanvasScene()
    var groups: [CanvasItemGroup] = []
    var camera = CanvasCamera()
    var boardState: CanvasBoardState?
    var interactionState = CanvasInteractionState()
}
```

修改前，`BoardHistorySnapshot` 只记录 item、group 数据、board state 和 item selection。undo/redo 不能恢复 group 选择态。

```swift
// MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift - BoardHistorySnapshot 修改前
// 功能说明：旧 history snapshot 不包含 group interaction state。
struct BoardHistorySnapshot {
    var items: [CanvasBoardItem]
    var groups: [CanvasItemGroup] = []
    var boardState: CanvasBoardState?
    var interactionState: CanvasInteractionState
}
```

修改前，`clearSelection()` 只处理 item selection，后续如果加入 group selection，会无法通过同一个入口清除 group selection。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - clearSelection(recordHistory:) 修改前
// 功能说明：旧 clearSelection 只委托 item selection 替换为空。
@discardableResult
func clearSelection(recordHistory: Bool = false) -> Bool {
    replaceSelection(with: [], recordHistory: recordHistory)
}
```

修改前，删除 item 后会清理 group 成员；如果 group 的 `itemIDs` 变空，会直接删除整个 group。对于后续有 `frame` 的 group 框，这会误删空 group 框。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - removeDeletedItemIDsFromGroups(_:) 修改前
// 功能说明：旧逻辑会删除成员为空的 group，即使它未来可能有独立 frame。
groups = groups.compactMap { group in
    var updatedGroup = group
    updatedGroup.itemIDs.removeAll { itemID in
        deletedItemIDs.contains(itemID)
    }
    return updatedGroup.itemIDs.isEmpty ? nil : updatedGroup
}
```

## 修改后

新增 `CanvasGroupInteractionState`，用于保存当前选中的 group ID。它是交互态，不写入 board document。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - CanvasGroupInteractionState
// 功能说明：保存 group 框交互选择态，后续 hit-test/overlay/拖拽阶段会使用。
struct CanvasGroupInteractionState: Equatable {
    var selectedGroupID: CanvasItemGroupID?

    init(selectedGroupID: CanvasItemGroupID? = nil) {
        self.selectedGroupID = selectedGroupID
    }
}
```

`CanvasEditorSession` 新增 group interaction state 与相关只读属性、查询 API。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - group selection properties
// 功能说明：提供 group selection 查询能力，供后续 hit-test 和 overlay 使用。
var groupInteractionState = CanvasGroupInteractionState()

var selectedGroupID: CanvasItemGroupID? {
    groupInteractionState.selectedGroupID
}

var hasGroupSelection: Bool {
    selectedGroupID != nil
}

var selectedGroup: CanvasItemGroup? {
    selectedGroupID.flatMap(group(withID:))
}

func group(withID groupID: CanvasItemGroupID) -> CanvasItemGroup? {
    groups.first(where: { $0.id == groupID })
}

func groupFrame(withID groupID: CanvasItemGroupID) -> CGRect? {
    group(withID: groupID)?.frame
}
```

新增 group 选择与 group frame 更新能力判断。当前阶段限制为 inline edit 期间不能操作 group。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - group capability APIs
// 功能说明：约束 group selection/frame update 的基础前置条件。
func canSelectGroup(withID groupID: CanvasItemGroupID) -> Bool {
    inlineEditState == nil && group(withID: groupID) != nil
}

func canUpdateGroupFrame(withID groupID: CanvasItemGroupID) -> Bool {
    inlineEditState == nil && group(withID: groupID) != nil
}
```

新增 `selectGroup(...)`。选中 group 时会清空 item selection，避免 item overlay 和 group overlay 后续互相抢状态。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - selectGroup(withID:recordHistory:)
// 功能说明：选中 group，同时清空 item selection；可选择是否记录 history。
@discardableResult
func selectGroup(
    withID groupID: CanvasItemGroupID,
    recordHistory: Bool = false
) -> Bool {
    guard canSelectGroup(withID: groupID) else {
        return false
    }

    let nextGroupInteractionState = CanvasGroupInteractionState(
        selectedGroupID: groupID
    )
    guard groupInteractionState != nextGroupInteractionState || hasSelection else {
        return false
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    groupInteractionState = nextGroupInteractionState
    applySelectionState(
        CanvasNormalizedSelectionState(
            selectedItemIDs: [],
            primarySelectedItemID: nil
        ),
        clearsGroupSelection: false
    )

    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "select group"
        )
    }

    return true
}
```

新增 `clearGroupSelection(...)` 和 `updateGroupFrame(...)`。`updateGroupFrame` 会标准化 frame，并扩展 board bounds。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - clearGroupSelection / updateGroupFrame
// 功能说明：提供后续 group hit-test、拖拽和缩放阶段需要的基础 mutation API。
@discardableResult
func clearGroupSelection(recordHistory: Bool = false) -> Bool {
    guard groupInteractionState.selectedGroupID != nil else {
        return false
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    groupInteractionState = CanvasGroupInteractionState()

    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "clear group selection"
        )
    }

    return true
}

@discardableResult
func updateGroupFrame(
    withID groupID: CanvasItemGroupID,
    to frame: CGRect,
    recordHistory: Bool = false
) -> Bool {
    guard
        canUpdateGroupFrame(withID: groupID),
        let groupIndex = groups.firstIndex(where: { $0.id == groupID })
    else {
        return false
    }

    let standardizedFrame = frame.standardized
    guard standardizedFrame.width > 0,
          standardizedFrame.height > 0,
          standardizedFrame.isNull == false,
          standardizedFrame.isInfinite == false
    else {
        return false
    }

    guard groups[groupIndex].frame != standardizedFrame else {
        return false
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    groups[groupIndex].frame = standardizedFrame
    expandBoardIfNeeded(toInclude: standardizedFrame)

    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "update group frame",
            autosaveReason: "update group frame"
        )
    }

    return true
}
```

`BoardHistorySnapshot` 新增 `groupInteractionState`，并纳入等价比较。这样 undo/redo 的 history 层可以携带 group 选择态。

```swift
// MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift - BoardHistorySnapshot 修改后
// 功能说明：history snapshot 纳入 group interaction state，但不进入 board document。
struct BoardHistorySnapshot {
    var items: [CanvasBoardItem]
    var groups: [CanvasItemGroup] = []
    var boardState: CanvasBoardState?
    var interactionState: CanvasInteractionState
    var groupInteractionState: CanvasGroupInteractionState = CanvasGroupInteractionState()
}

extension BoardHistorySnapshot: Equatable {
    static func == (lhs: BoardHistorySnapshot, rhs: BoardHistorySnapshot) -> Bool {
        itemsMatch(lhs.items, rhs.items) &&
        lhs.groups == rhs.groups &&
        boardStatesMatch(lhs.boardState, rhs.boardState) &&
            lhs.interactionState == rhs.interactionState &&
            lhs.groupInteractionState == rhs.groupInteractionState
    }
}
```

`currentBoardHistorySnapshot()` 会保存规范化后的 group interaction state；如果选中的 group 已不存在，会自动清空。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - currentBoardHistorySnapshot()
// 功能说明：history snapshot 只保存仍然有效的 selectedGroupID。
func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
    BoardHistorySnapshot(
        items: scene.orderedBoardItems(),
        groups: groups,
        boardState: boardState,
        interactionState: interactionState,
        groupInteractionState: normalizedGroupInteractionState(
            groupInteractionState
        )
    )
}
```

新增 `normalizedGroupInteractionState(...)`，用于恢复 history 时避免引用不存在的 group。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - normalizedGroupInteractionState(_:)
// 功能说明：保证 group selection 不会指向已经被删除或不存在的 group。
private func normalizedGroupInteractionState(
    _ groupInteractionState: CanvasGroupInteractionState
) -> CanvasGroupInteractionState {
    guard
        let selectedGroupID = groupInteractionState.selectedGroupID,
        group(withID: selectedGroupID) != nil
    else {
        return CanvasGroupInteractionState()
    }

    return groupInteractionState
}
```

`applySelectionState(...)` 新增 `clearsGroupSelection` 参数。默认情况下，选中 item 会清空 group selection；`selectGroup` 内部清空 item selection 时不会反向清空 group selection。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - applySelectionState(_:clearsGroupSelection:)
// 功能说明：实现 item selection 与 group selection 的互斥规则。
private func applySelectionState(
    _ selectionState: CanvasNormalizedSelectionState<CanvasItemID>,
    clearsGroupSelection: Bool = true
) {
    interactionState = CanvasInteractionState(
        selectedItemIDs: selectionState.selectedItemIDs,
        primarySelectedItemID: selectionState.primarySelectedItemID
    )
    if clearsGroupSelection, selectionState.selectedItemIDs.isEmpty == false {
        groupInteractionState = CanvasGroupInteractionState()
    }
    syncInlineEditStateWithSelection()
}
```

`clearSelection()` 现在可以同时清除 item selection 和 group selection。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - clearSelection(recordHistory:) 修改后
// 功能说明：统一清理 item selection 与 group selection。
@discardableResult
func clearSelection(recordHistory: Bool = false) -> Bool {
    guard hasSelection || hasGroupSelection else {
        return false
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    applySelectionState(
        CanvasNormalizedSelectionState(
            selectedItemIDs: [],
            primarySelectedItemID: nil
        ),
        clearsGroupSelection: false
    )
    groupInteractionState = CanvasGroupInteractionState()

    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "clear selection"
        )
    }

    return true
}
```

删除 item 后清理 group 成员时，有 `frame` 的空 group 会被保留，避免 group 框被误删。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - removeDeletedItemIDsFromGroups(_:) 修改后
// 功能说明：有 frame 的 group 即使 itemIDs 为空，也保留 group 框。
groups = groups.compactMap { group in
    var updatedGroup = group
    updatedGroup.itemIDs.removeAll { itemID in
        deletedItemIDs.contains(itemID)
    }
    return updatedGroup.itemIDs.isEmpty && updatedGroup.frame == nil
        ? nil
        : updatedGroup
}
```

## 验证

本次阶段 1 已运行以下验证，结果通过。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 macOS build
xcodebuild -scheme MyCanvas_Ver_0 -destination 'platform=macOS' build > /tmp/mycanvas_group_phase1_macos_build.log 2>&1
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 iOS Simulator build
xcodebuild -scheme MyCanvas_Ver_0 -destination 'generic/platform=iOS Simulator' build > /tmp/mycanvas_group_phase1_ios_build.log 2>&1
```

同时已读取 IDE lint 诊断，以下文件无 linter errors：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 linter 检查范围
MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
```

## 备注

本次没有提交代码，也没有修改计划文件。该记录只描述刚刚实施的 group frame interaction 阶段 1。
