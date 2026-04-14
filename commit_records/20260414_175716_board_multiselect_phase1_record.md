# 20260414_175716 图板多选阶段1改动记录

本记录基于本轮实际工作区状态整理，参考了 `date`、`git status --short`、`git diff`、`git diff --stat` 与当前文件内容；不直接粘贴原始 `git diff`，而是按“修改前 / 修改后”方式归纳。

## 当前 Changes 快照

```bash
# 命令: git status --short
# 说明: 这是创建本记录前工作区里可见的全部 changes
 M .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
 M MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
 M MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
 M MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
 M MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
```

```bash
# 命令: git diff --stat
# 说明: 这是创建本记录前 diff 体量概览
.../plans/board-multiselect-plan_96ecdbb5.plan.md  |   4 +-
MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift       | 328 ++++++++++++---
MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift  |  36 +-
.../Canvas/Editing/CanvasCommandCatalog.swift      | 155 +++++--
.../Canvas/Editing/CanvasCommandExecutor.swift     |  98 ++++-
.../Canvas/Editing/CanvasEditorSession.swift       | 462 ++++++++++++++++++---
.../CanvasContextMenuCommandResolver.swift         |  50 ++-
.../Platform/iOS/iOSViewController.swift           |   3 +-
.../Platform/macOS/macOSViewController.swift       |   3 +-
MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift   |   3 +-
.../CanvasCommandPolicyParityTests.swift           | 216 ++++++++++
.../CanvasContextMenuActionResolverTests.swift     | 125 ++++++
.../CanvasEditorSessionAlignmentOverlayTests.swift |   3 +-
13 files changed, 1320 insertions(+), 166 deletions(-)
```

阶段 1 的主体改动集中在：

- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
- `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
- `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
- `MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift`

当前 changes 里还包含 `.cursor/plans/board-multiselect-plan_96ecdbb5.plan.md` 的状态同步，以及两处旧测试对 `BoardRuntimeState` 时间字段的兼容修正，后文一并如实登记。

## 1. Session 层把“选择集”收敛成唯一真相

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数: beginTextEdit(withID:) / beginCropModeIfPossible() / selectItem(withID:recordHistory:)
// 说明: 旧实现仍然围绕 interactionState.selectedItemID 运转，只支持“把当前选择替换成单个 item”。
@discardableResult
func beginTextEdit(withID itemID: CanvasItemID) -> Bool {
    guard
        canBeginTextEdit(withID: itemID),
        let item = scene.textItem(withID: itemID)
    else {
        return false
    }

    interactionState.selectedItemID = itemID
    inlineEditState = CanvasInlineEditState(item: item)
    return true
}

@discardableResult
func beginCropModeIfPossible() -> Bool {
    guard
        canBeginCropMode,
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return false
    }

    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    return true
}

@discardableResult
func selectItem(
    withID itemID: CanvasItemID,
    recordHistory: Bool = false
) -> Bool {
    guard canSelectItem(withID: itemID) else {
        return false
    }

    interactionState.selectedItemID = itemID
    syncInlineEditStateWithSelection()
    return true
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数: replaceSelection(with:primarySelectedItemID:recordHistory:) / addToSelection(withID:recordHistory:) / removeFromSelection(withID:recordHistory:) / toggleSelectionMembership(of:recordHistory:)
// 说明: 新实现把“整组选择变更”下沉到 Session，后续 command lane / context menu 都复用这一套真相。
var canDeleteSelection: Bool {
    selectedBoardItems.isEmpty == false
}

var canBringSelectionForward: Bool {
    scene.canBringBoardItemsForward(withIDs: selectedItemIDs)
}

@discardableResult
func replaceSelection(
    with itemIDs: [CanvasItemID],
    primarySelectedItemID: CanvasItemID? = nil,
    recordHistory: Bool = false
) -> Bool {
    let normalizedSelection = normalizedSelectionStateForExistingItems(
        selectedItemIDs: itemIDs,
        primarySelectedItemID: primarySelectedItemID
    )
    guard
        interactionState.selectedItemIDs != normalizedSelection.selectedItemIDs
            || interactionState.primarySelectedItemID != normalizedSelection.primarySelectedItemID
    else {
        return false
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    applySelectionState(normalizedSelection)

    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: normalizedSelection.selectedItemIDs.isEmpty
                ? "clear selection"
                : "replace selection"
        )
    }
    return true
}

@discardableResult
func toggleSelectionMembership(
    of itemID: CanvasItemID,
    recordHistory: Bool = false
) -> Bool {
    if interactionState.selectedItemIDs.contains(itemID) {
        return removeFromSelection(withID: itemID, recordHistory: recordHistory)
    }
    return addToSelection(withID: itemID, recordHistory: recordHistory)
}
```

### 单对象编辑规则同步收口

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数: syncInlineEditStateWithSelection() / beginTextEdit(withID:) / beginCropModeIfPossible()
// 说明: 多选进入 Session 之后，文本内联编辑和 crop 只允许在“恰好单选”时开启。
func syncInlineEditStateWithSelection() {
    guard let inlineEditState else {
        return
    }

    guard
        selectionCount == 1,
        singleSelectedItemID == inlineEditState.itemID
    else {
        self.inlineEditState = nil
        return
    }

    // ... 其他逻辑省略 ...
}

@discardableResult
func beginTextEdit(withID itemID: CanvasItemID) -> Bool {
    // 进入文本编辑前，先把选择状态收敛成单选
    _ = replaceSelection(
        with: [itemID],
        primarySelectedItemID: itemID
    )
    inlineEditState = CanvasInlineEditState(item: item)
    return true
}

@discardableResult
func beginCropModeIfPossible() -> Bool {
    guard
        canBeginCropMode,
        let selectedItemID = singleSelectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return false
    }
    // ... 其他逻辑省略 ...
}
```

### 本次效果

- 选择状态不再由 controller 零散改写，而是由 `CanvasEditorSession` 集中维护。
- 后续阶段要接入 `Command + Click` / 工具条多选时，可以直接调用 `toggleSelectionMembership`，不需要再发明第三套逻辑。
- 文本编辑与裁剪的“只允许单对象”边界已经在 Session 层固定下来，不再依赖 UI 自己兜底。

## 2. Scene 层补齐批量复制 / 删除 / 图层调整 API

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数: removeItem(withID:) / duplicateBoardItem(withID:offsetInWorld:) / reorderBoardItem(withID:toOrderedIndex:)
// 说明: 旧实现只提供单个对象 API；如果要做多选批量命令，只能在上层循环调用，容易把顺序语义写散。
@discardableResult
func removeItem(withID id: CanvasImageItemID) -> Bool {
    var orderedItems = orderedBoardItems()
    guard let index = orderedItems.firstIndex(where: { $0.id == id }) else {
        return false
    }

    orderedItems.remove(at: index)
    items = normalizedZOrderItems(from: orderedItems)
    return true
}

@discardableResult
func duplicateBoardItem(
    withID id: CanvasItemID,
    offsetInWorld: CGPoint = .zero
) -> CanvasBoardItem? {
    var orderedItems = orderedBoardItems()
    guard let index = orderedItems.firstIndex(where: { $0.id == id }) else {
        return nil
    }

    let sourceItem = orderedItems[index]
    let duplicatedItem = duplicatedItem(from: sourceItem, offsetInWorld: offsetInWorld)
    orderedItems.insert(duplicatedItem, at: index + 1)
    items = normalizedZOrderItems(from: orderedItems)
    return boardItem(withID: duplicatedItem.id)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数: removeBoardItems(withIDs:) / duplicateBoardItems(withIDs:offsetInWorld:) / bringBoardItemsForward(withIDs:) / sendBoardItemsBackward(withIDs:)
// 说明: 新实现把多选批量变更下沉到 Scene，确保“删除 / 复制 / 调层级”都以同一批次语义修改 items。
@discardableResult
func removeBoardItems(withIDs itemIDs: [CanvasItemID]) -> [CanvasBoardItem] {
    let itemIDSet = Set(itemIDs)
    guard itemIDSet.isEmpty == false else {
        return []
    }

    let orderedItems = orderedBoardItems()
    let removedItems = orderedItems.filter { itemIDSet.contains($0.id) }
    guard removedItems.isEmpty == false else {
        return []
    }

    items = normalizedZOrderItems(
        from: orderedItems.filter { itemIDSet.contains($0.id) == false }
    )
    return removedItems
}

@discardableResult
func duplicateBoardItems(
    withIDs itemIDs: [CanvasItemID],
    offsetInWorld: CGPoint = .zero
) -> [CanvasBoardItem] {
    let itemIDSet = Set(itemIDs)
    guard itemIDSet.isEmpty == false else {
        return []
    }

    let orderedItems = orderedBoardItems()
    var duplicatedItems: [CanvasBoardItem] = []
    var rebuiltItems: [CanvasBoardItem] = []
    var pendingDuplicateRun: [CanvasBoardItem] = []

    func flushPendingDuplicateRun() {
        guard pendingDuplicateRun.isEmpty == false else {
            return
        }

        let duplicatedRun = pendingDuplicateRun.map { sourceItem in
            duplicatedItem(from: sourceItem, offsetInWorld: offsetInWorld)
        }
        rebuiltItems.append(contentsOf: duplicatedRun)
        duplicatedItems.append(contentsOf: duplicatedRun)
        pendingDuplicateRun.removeAll(keepingCapacity: true)
    }

    for item in orderedItems {
        rebuiltItems.append(item)
        if itemIDSet.contains(item.id) {
            pendingDuplicateRun.append(item)
        } else {
            flushPendingDuplicateRun()
        }
    }
    flushPendingDuplicateRun()

    items = normalizedZOrderItems(from: rebuiltItems)
    return duplicatedItems
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数: bringBoardItemsForward(withIDs:) / bringBoardItemsToFront(withIDs:) / sendBoardItemsBackward(withIDs:) / sendBoardItemsToBack(withIDs:)
// 说明: 批量图层调整现在按选择集整体移动，并保留成员之间的相对顺序。
@discardableResult
func bringBoardItemsForward(withIDs itemIDs: [CanvasItemID]) -> Bool {
    let itemIDSet = Set(itemIDs)
    var orderedItems = orderedBoardItems()
    var didChangeOrder = false

    for index in stride(from: orderedItems.count - 2, through: 0, by: -1) {
        let currentItemID = orderedItems[index].id
        let nextItemID = orderedItems[index + 1].id
        guard itemIDSet.contains(currentItemID) else {
            continue
        }
        guard itemIDSet.contains(nextItemID) == false else {
            continue
        }

        orderedItems.swapAt(index, index + 1)
        didChangeOrder = true
    }

    guard didChangeOrder else {
        return false
    }

    items = normalizedZOrderItems(from: orderedItems)
    return true
}
```

### 本次效果

- `CanvasEditorSession` 不需要自己循环删、循环复制、循环挪 zIndex。
- 批量复制会把一段连续选中 run 作为一个整体插到原对象后面，避免成员顺序被打散。
- 批量前移 / 后移 / 置顶 / 置底都统一通过 Scene 层实现，为后续组变换阶段继续下沉几何写入做铺垫。

## 3. Command lane 升级为“selection-aware”语义

### 3.1 `CanvasCommand` 扩展出选择集命令

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数: CanvasCommand
// 说明: 旧命令集只有 target-item 版本，没有“对当前选择集执行批量命令”的表达能力。
enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case crop
    case undo
    case redo
    case selectItem(itemID: CanvasItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)
    case duplicateItem(itemID: CanvasItemID, recordHistory: Bool)
    case deleteItem(itemID: CanvasItemID, recordHistory: Bool)
    case bringItemForward(itemID: CanvasItemID, recordHistory: Bool)
    case sendItemBackward(itemID: CanvasItemID, recordHistory: Bool)
    case bringItemToFront(itemID: CanvasItemID, recordHistory: Bool)
    case sendItemToBack(itemID: CanvasItemID, recordHistory: Bool)
}
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数: CanvasCommand / var id / var shouldCancelActiveRotation
// 说明: 新命令集同时支持 target-item 与 selection-based 两类命令，后者复用原有 commandID 以保持交互策略统一。
enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case crop
    case undo
    case redo
    case selectItem(itemID: CanvasItemID, recordHistory: Bool)
    case toggleSelectionMembership(itemID: CanvasItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)
    case duplicateItem(itemID: CanvasItemID, selectDuplicatedItem: Bool, recordHistory: Bool)
    case duplicateSelection(recordHistory: Bool)
    case deleteItem(itemID: CanvasItemID, recordHistory: Bool)
    case deleteSelection(recordHistory: Bool)
    case bringItemForward(itemID: CanvasItemID, recordHistory: Bool)
    case bringSelectionForward(recordHistory: Bool)
    case sendItemBackward(itemID: CanvasItemID, recordHistory: Bool)
    case sendSelectionBackward(recordHistory: Bool)
    case bringItemToFront(itemID: CanvasItemID, recordHistory: Bool)
    case bringSelectionToFront(recordHistory: Bool)
    case sendItemToBack(itemID: CanvasItemID, recordHistory: Bool)
    case sendSelectionToBack(recordHistory: Bool)
}
```

### 3.2 `CanvasCommandCatalog` 的 enablement 不再只看 target item

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数: descriptor(for:session:context:)
// 说明: 旧目录层总是拿 targetItemID 判定 Duplicate / Delete / Bring / Send 是否可用。
case .duplicateItem:
    descriptor = CanvasCommandDescriptor(
        id: .duplicateItem,
        title: "Duplicate",
        systemImageName: "square.on.square",
        isEnabled: targetItemID(in: context, session: session).map { itemID in
            session.canDuplicateItem(withID: itemID)
        } ?? false,
        isActive: false
    )
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数: descriptor(for:session:context:) / operatesOnCurrentSelection(in:) / duplicateCommandIsEnabled(in:session:)
// 说明: 新目录层先判断菜单动作到底作用于“当前选择集”还是“命中的目标对象”，再决定可用态。
case .beginTextEdit:
    let resolvedTargetItemID = targetItemID(
        in: context,
        session: session
    )
    let usesCurrentSelection = operatesOnCurrentSelection(in: context)
    descriptor = CanvasCommandDescriptor(
        id: .beginTextEdit,
        title: "Edit Text",
        systemImageName: "pencil",
        isEnabled: resolvedTargetItemID.map { itemID in
            if usesCurrentSelection, session.singleSelectedItemID != itemID {
                return false
            }
            return session.canBeginTextEdit(withID: itemID)
        } ?? false,
        isActive: false
    )

private func duplicateCommandIsEnabled(
    in context: CanvasContextMenuContext?,
    session: CanvasEditorSession
) -> Bool {
    if operatesOnCurrentSelection(in: context) {
        return session.canDuplicateSelection
    }

    return targetItemID(in: context, session: session).map { itemID in
        session.canDuplicateItem(withID: itemID)
    } ?? false
}
```

### 3.3 `CanvasCommandExecutor` 真正执行批量命令

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数: canExecute(_:) / execute(_:)
// 说明: 旧执行器只会把命令转发到单对象 API。
case let .duplicateItem(itemID, _):
    return session.canDuplicateItem(withID: itemID)

case let .duplicateItem(itemID, recordHistory):
    guard let duplicatedItem = session.duplicateItem(
        withID: itemID,
        recordHistory: recordHistory
    ) else {
        return nil
    }
    session.scheduleAutosave(reason: "duplicate item")
    return CanvasCommandExecutionResult(
        refreshReason: "duplicate item \(duplicatedItem.id.uuidString)"
    )
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数: canExecute(_:) / execute(_:)
// 说明: 新执行器把 Session 里的多选能力接进 command lane，并保持 history / autosave / refreshReason 走同一套出口。
case let .toggleSelectionMembership(itemID, _):
    return session.canToggleSelectionMembership(withID: itemID)
case .duplicateSelection:
    return session.canDuplicateSelection
case .deleteSelection:
    return session.canDeleteSelection
case .bringSelectionForward:
    return session.canBringSelectionForward

case let .toggleSelectionMembership(itemID, recordHistory):
    guard session.toggleSelectionMembership(
        of: itemID,
        recordHistory: recordHistory
    ) else {
        return nil
    }
    return CanvasCommandExecutionResult(
        refreshReason: "toggle selection membership \(itemID.uuidString)"
    )

case let .duplicateSelection(recordHistory):
    guard let duplicatedItems = session.duplicateSelection(
        recordHistory: recordHistory
    ) else {
        return nil
    }
    session.scheduleAutosave(reason: "duplicate selection")
    return CanvasCommandExecutionResult(
        refreshReason: "duplicate selection \(duplicatedItems.count) items"
    )

case let .deleteSelection(recordHistory):
    guard session.deleteSelection(recordHistory: recordHistory) else {
        return nil
    }
    session.scheduleAutosave(reason: "delete selection")
    return CanvasCommandExecutionResult(
        refreshReason: "delete selection"
    )
```

### 本次效果

- 现在“多选切换 / 批量复制 / 批量删除 / 批量图层”都能从 command lane 统一进历史。
- reading mode 的阻断逻辑不需要新增一套分支，因为 selection-based 命令继续映射回原来的 `CanvasCommandID`。
- target-item 命令依然保留，后续右键命中未选中对象时可以继续只操作目标对象。

## 4. 右键菜单把“目标对象”和“当前选择集”明确分流

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数: command(for:context:)
// 说明: 旧实现无论菜单开在已选对象还是未选对象上，Duplicate / Delete / Bring / Send 都直接作用于 context.targetItemID。
case .duplicateItem:
    guard let itemID = context.targetItemID else {
        return nil
    }
    return .duplicateItem(
        itemID: itemID,
        recordHistory: true
    )

case .deleteItem:
    guard let itemID = context.targetItemID else {
        return nil
    }
    return .deleteItem(
        itemID: itemID,
        recordHistory: true
    )
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数: command(for:context:session:) / operatesOnCurrentSelection(in:)
// 说明: 新实现先判断菜单上下文是否属于“当前选择集”，然后再返回 selection-based 命令或 target-item 命令。
func command(
    for commandID: CanvasCommandID,
    context: CanvasContextMenuContext,
    session _: CanvasEditorSession
) -> CanvasCommand? {
    switch commandID {
    case .duplicateItem:
        if operatesOnCurrentSelection(in: context) {
            return .duplicateSelection(recordHistory: true)
        }
        guard let itemID = context.targetItemID else {
            return nil
        }
        return .duplicateItem(
            itemID: itemID,
            selectDuplicatedItem: false,
            recordHistory: true
        )
    case .deleteItem:
        if operatesOnCurrentSelection(in: context) {
            return .deleteSelection(recordHistory: true)
        }
        guard let itemID = context.targetItemID else {
            return nil
        }
        return .deleteItem(
            itemID: itemID,
            recordHistory: true
        )
    default:
        // ... 其他分支省略 ...
        return nil
    }
}

private func operatesOnCurrentSelection(
    in context: CanvasContextMenuContext
) -> Bool {
    switch context.targetKind {
    case .selectedItemBody,
         .selectionHandle,
         .rotateHandle,
         .cropHandle,
         .cropOutline:
        return true
    case .unselectedItemBody,
         .blank:
        return false
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: performContextMenuAction(_:)
// 说明: Controller 只增加了 session 透传，菜单命令分流逻辑仍然集中在 resolver。
guard let command = contextMenuActionResolver.command(
    for: commandID,
    context: contextMenuState.resolvedContext,
    session: editorSession
) else {
    dismissContextMenu()
    return
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: performContextMenuAction(_:)
// 说明: macOS 与 iOS 的接线保持同构，避免两端在 phase3 之前就开始分叉。
guard let command = contextMenuActionResolver.command(
    for: commandID,
    context: contextMenuState.resolvedContext,
    session: editorSession
) else {
    dismissContextMenu()
    return
}
```

### 本次效果

- 右键点在已选对象上时，批量命令默认作用于整个选择集。
- 右键点在未选对象上时，仍然只操作命中目标，不会先把当前选择改掉。
- `Edit Text` 在多选上下文下也已经被目录层禁掉，避免“多选中误入单文本编辑”。

## 5. 回归测试补齐 phase1 关心的行为

### 5.1 命令链路测试：验证批量选择与批量命令

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数: 旧文件末尾
// 说明: 原文件只覆盖 Add Text / Commit Text / Import Media 与 reading mode policy parity，尚无多选批量命令测试。
func testImportMediaExecutorMatchesPolicyInReadingMode() throws {
    // ... 旧测试逻辑省略 ...
}

// 旧文件到这里结束，尚无 selection-based command 覆盖
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数: testToggleSelectionMembershipExecutorBuildsAndShrinksSelectionSet() / testDuplicateSelectionExecutorSelectsDuplicatedItems() / testDeleteSelectionExecutorRemovesAllSelectedItems() / testBringSelectionForwardExecutorPreservesRelativeOrder() / testTargetDuplicateCommandPreservesCurrentSelection()
// 说明: 新增用例直接验证 command executor 的 phase1 语义，而不是只测 Session 内部细节。
func testToggleSelectionMembershipExecutorBuildsAndShrinksSelectionSet() {
    // 先单选 first，再 toggle second，最后再把 first toggle 掉
    // 期望: selectedItemIDs 与 primarySelectedItemID 按多选规则更新
}

func testDuplicateSelectionExecutorSelectsDuplicatedItems() {
    // 期望: duplicateSelection 复制整组选中项，并把新复制出的 items 设为当前选择
}

func testDeleteSelectionExecutorRemovesAllSelectedItems() {
    // 期望: deleteSelection 一次删除整组选中项，并清空选择
}

func testBringSelectionForwardExecutorPreservesRelativeOrder() {
    // 期望: 组内相对顺序保持不变，只整体向前移动
}

func testTargetDuplicateCommandPreservesCurrentSelection() {
    // 期望: target-item duplicate 不改写当前 selection-based 选择集
}
```

### 5.2 上下文菜单测试：验证 selected / unselected 分流

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数: 旧文件末尾
// 说明: 原文件主要覆盖 GIF / 视频动作与 reading mode / frozen 环境，没有校验多选上下文的命令分流。
func testFrozenEnvironmentReturnsNoActionsEvenInEditingMode() throws {
    // ... 旧测试逻辑省略 ...
}

// 旧文件到这里结束，尚无 selection-based context menu 覆盖
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数: testSelectedContextResolvesDuplicateToSelectionCommand() / testUnselectedContextResolvesDuplicateToTargetCommand() / testMultiSelectionTextContextHidesBeginTextEditAction()
// 说明: 新增用例直接卡住 phase1 设计里最关键的“已选上下文 vs 未选上下文”边界。
func testSelectedContextResolvesDuplicateToSelectionCommand() {
    // 期望: 菜单开在 selectedItemBody 上时，Duplicate 返回 duplicateSelection
}

func testUnselectedContextResolvesDuplicateToTargetCommand() {
    // 期望: 菜单开在 unselectedItemBody 上时，Duplicate 仍返回 duplicateItem(target)
}

func testMultiSelectionTextContextHidesBeginTextEditAction() {
    // 期望: 多选文本上下文下，不再显示 beginTextEdit 命令
}
```

### 本次效果

- 这批测试直接覆盖了 phase1 新引入的共享真相，不再只是测单对象命令。
- 后续 phase3 接入 `Command + Click` 与工具条多选开关时，可以继续复用这些 selection-based 断言。

## 6. 为了打通测试编译，顺手修了两处旧测试的时间字段漂移

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 函数: testBoardDocumentMapperRoundTripsVideoPosterMetadata()
// 说明: 旧测试仍然写 runtimeState.updatedAt，但当前 BoardRuntimeState 只有 contentUpdatedAt / viewStateUpdatedAt。
var runtimeState = makeRuntimeState(
    boardID: boardID,
    now: Date(timeIntervalSince1970: 1_710_000_000),
    item: item
)
runtimeState.title = "Video Mapper"
runtimeState.updatedAt = Date(timeIntervalSince1970: 1_710_000_123)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数: makeAlignmentOverlayTestRuntimeState(items:selectedItemID:)
// 说明: 旧 helper 也仍然用 updatedAt 构造 BoardRuntimeState。
BoardRuntimeState(
    boardID: UUID(),
    title: "Alignment Test Board",
    createdAt: Date(timeIntervalSince1970: 0),
    updatedAt: Date(timeIntervalSince1970: 0),
    items: items,
    boardState: nil,
    camera: CanvasCamera(...),
    interactionState: CanvasInteractionState(selectedItemID: selectedItemID),
    workspaceMode: .editing
)
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 函数: testBoardDocumentMapperRoundTripsVideoPosterMetadata()
// 说明: 测试值拆成 contentUpdatedAt / viewStateUpdatedAt，与当前 runtimeState 契约一致。
var runtimeState = makeRuntimeState(
    boardID: boardID,
    now: Date(timeIntervalSince1970: 1_710_000_000),
    item: item
)
runtimeState.title = "Video Mapper"
runtimeState.contentUpdatedAt = Date(timeIntervalSince1970: 1_710_000_123)
runtimeState.viewStateUpdatedAt = Date(timeIntervalSince1970: 1_710_000_123)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数: makeAlignmentOverlayTestRuntimeState(items:selectedItemID:)
// 说明: helper 改用 contentUpdatedAt / viewStateUpdatedAt，避免 targeted test 在编译阶段就被旧字段拦住。
BoardRuntimeState(
    boardID: UUID(),
    title: "Alignment Test Board",
    createdAt: Date(timeIntervalSince1970: 0),
    contentUpdatedAt: Date(timeIntervalSince1970: 0),
    viewStateUpdatedAt: Date(timeIntervalSince1970: 0),
    items: items,
    boardState: nil,
    camera: CanvasCamera(...),
    interactionState: CanvasInteractionState(selectedItemID: selectedItemID),
    workspaceMode: .editing
)
```

### 本次效果

- 这两处并不是 phase1 业务逻辑本身，但它们确实是本轮为跑通 targeted tests 而做的真实修改。
- 修完之后，测试编译可以继续前进到更靠后的工程校验阶段。

## 7. 当前 working tree 里还有一处计划文件状态同步

### 修改前

```yaml
# 文件路径: .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
# 函数: front matter / todos
# 说明: 当前 changes 里可见这 2 个阶段状态由 pending 改成了 completed。
todos:
  - id: phase0-contract-migration
    content: 升级选择状态契约，完成文档格式迁移与旧数据兼容解码。
    status: pending
  - id: phase1-session-commands
    content: 重构 CanvasEditorSession 与 command lane，让批量选择与批量命令成为共享真相。
    status: pending
```

### 修改后

```yaml
# 文件路径: .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
# 函数: front matter / todos
# 说明: 当前 working tree 里，这 2 个阶段状态已经同步成 completed。
todos:
  - id: phase0-contract-migration
    content: 升级选择状态契约，完成文档格式迁移与旧数据兼容解码。
    status: completed
  - id: phase1-session-commands
    content: 重构 CanvasEditorSession 与 command lane，让批量选择与批量命令成为共享真相。
    status: completed
```

这里仅如实登记当前 changes，不额外展开计划文件本身的业务含义。

## 8. 验证情况

### 8.1 静态检查

```bash
# 命令: ReadLints
# 说明: 对本轮改动的生产代码与测试文件做了 IDE 侧诊断。
# 结果: No linter errors found.
```

### 8.2 定向测试命令

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests
# 说明: 这次只跑 phase1 直接相关的 command / context menu / alignment overlay 测试。
```

### 8.3 实际结果

```bash
# 命令结果: xcodebuild test 最终输出摘要
# 说明: 在修掉本轮引入的编译问题以及两处旧测试字段漂移之后，最终失败点落在工程级校验，而不是 phase1 业务代码本身。
error: Your target is built for macOS but contains embedded content built for the iOS platform (Add To Canvas.appex), which is not allowed.
Testing failed:
    Your target is built for macOS but contains embedded content built for the iOS platform (Add To Canvas.appex), which is not allowed.
```

### 8.4 结论

- 本轮 phase1 生产代码与新增/修正测试已经完成落地。
- `ReadLints` 未发现本轮改动引入的 IDE 诊断问题。
- `xcodebuild test` 的最终阻塞点仍是既有工程配置问题：`macOS` 宿主嵌入了 `iOS` 的 `Add To Canvas.appex`，导致 `ValidateEmbeddedBinary` 失败。
- 该阻塞点与 phase1 的选择集 / 命令链路改造不是同一层问题，但会继续阻止后续完整测试跑通。

