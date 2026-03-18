# 20260318_132759_context_menu_phase7_command_surface_regression_record

## 记录范围

- 记录内容：
  1. 为 `CanvasScene` 增加删除、复制、前移、后移、置顶、置底的共享场景能力，并统一重排 `zIndex`。
  2. 为 `CanvasEditorSession` 增加对应的 `can... / execute...` 能力，把 history、selection、autosave 和 board expand 都收敛到共享层。
  3. 扩展 `CanvasCommand / CanvasCommandCatalog / CanvasCommandExecutor`，补齐 `duplicate / delete / z-order` 命令面。
  4. 扩展 `CanvasContextMenuCommandResolver`，把菜单上下文从“只有 blank/selected/unselected 的基础命令”扩展到 handle / crop / z-order 分组。
  5. 让 `iOS/macOS` controller 在冻结菜单按钮时带上 `resolvedContext`，不再由平台层自己猜菜单启用态。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - `.cursor/plans/上下文菜单分阶段_e62bfffe.plan.md` 的任务状态同步
  - 原始 gif diff

## 修改一：`CanvasScene` 补齐复制、删除与 z-order 共享能力

### 修改前

- `CanvasScene` 只有最基础的 `removeItem(withID:)`，直接按 id 删除。
- 没有共享的 `duplicate / bring forward / send backward / bring to front / send to back`。
- 删除后也不会统一重排 `zIndex`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名/类型名: removeItem(withID:) / orderedItems(from:)
// 功能说明: 修改前 Scene 只有基础删除能力，没有复制与 z-order 调整，也没有统一的 zIndex 归一化流程。
func removeItem(withID id: CanvasImageItemID) {
    items.removeAll(where: { $0.id == id })
}

private func orderedItems(from items: [CanvasImageItem]) -> [CanvasImageItem] {
    items.sorted { lhs, rhs in
        if lhs.zIndex == rhs.zIndex {
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return lhs.zIndex < rhs.zIndex
    }
}
```

### 修改后

- `removeItem(withID:)` 改为返回 `Bool`，并在删除后统一归一化 `zIndex`。
- 新增 `duplicateItem(...)`。
- 新增 `canBringItemForward / canSendItemBackward / canBringItemToFront / canSendItemToBack`。
- 新增 `bringItemForward / sendItemBackward / bringItemToFront / sendItemToBack`。
- 新增 `normalizedZOrderItems(...)` 和 `reorderItem(...)`，把顺序调整根因收口到 Scene。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名/类型名: removeItem(withID:) / duplicateItem(withID:offsetInWorld:) / bringItemForward(withID:) / sendItemBackward(withID:) / bringItemToFront(withID:) / sendItemToBack(withID:) / normalizedZOrderItems(from:) / reorderItem(withID:toOrderedIndex:)
// 功能说明: 修改后 Scene 成为 delete、duplicate、z-order 调整的共享根能力入口，并统一维护稳定的 zIndex 排序。
@discardableResult
func removeItem(withID id: CanvasImageItemID) -> Bool {
    var orderedItems = orderedItems()
    guard let index = orderedItems.firstIndex(where: { $0.id == id }) else {
        return false
    }

    orderedItems.remove(at: index)
    items = normalizedZOrderItems(from: orderedItems)
    return true
}

@discardableResult
func duplicateItem(
    withID id: CanvasImageItemID,
    offsetInWorld: CGPoint = .zero
) -> CanvasImageItem? {
    var orderedItems = orderedItems()
    guard let index = orderedItems.firstIndex(where: { $0.id == id }) else {
        return nil
    }

    let sourceItem = orderedItems[index]
    let duplicatedItem = CanvasImageItem(
        cgImage: sourceItem.cgImage,
        center: CGPoint(
            x: sourceItem.center.x + offsetInWorld.x,
            y: sourceItem.center.y + offsetInWorld.y
        ),
        size: sourceItem.size,
        zIndex: sourceItem.zIndex,
        cropRectNormalized: sourceItem.cropRectNormalized,
        rotationRadians: sourceItem.rotationRadians
    )
    orderedItems.insert(duplicatedItem, at: index + 1)
    items = normalizedZOrderItems(from: orderedItems)
    return item(withID: duplicatedItem.id)
}

func canBringItemForward(withID id: CanvasImageItemID) -> Bool {
    guard let index = orderedItems().firstIndex(where: { $0.id == id }) else {
        return false
    }

    return index < (items.count - 1)
}

@discardableResult
func bringItemForward(withID id: CanvasImageItemID) -> CanvasImageItem? {
    guard let currentIndex = orderedItems().firstIndex(where: { $0.id == id }) else {
        return nil
    }

    return reorderItem(
        withID: id,
        toOrderedIndex: currentIndex + 1
    )
}

private func normalizedZOrderItems(
    from orderedItems: [CanvasImageItem]
) -> [CanvasImageItem] {
    orderedItems.enumerated().map { index, item in
        var normalizedItem = item
        normalizedItem.zIndex = CGFloat(index)
        return normalizedItem
    }
}

@discardableResult
private func reorderItem(
    withID id: CanvasImageItemID,
    toOrderedIndex destinationIndex: Int
) -> CanvasImageItem? {
    var orderedItems = orderedItems()
    guard let currentIndex = orderedItems.firstIndex(where: { $0.id == id }) else {
        return nil
    }

    let clampedDestinationIndex = min(
        max(destinationIndex, 0),
        max(orderedItems.count - 1, 0)
    )
    guard currentIndex != clampedDestinationIndex else {
        return nil
    }

    let reorderedItem = orderedItems.remove(at: currentIndex)
    orderedItems.insert(reorderedItem, at: clampedDestinationIndex)
    items = normalizedZOrderItems(from: orderedItems)
    return item(withID: id)
}
```

## 修改二：`CanvasEditorSession` 承接新命令的文档语义

### 修改前

- `CanvasEditorSession` 只承接 `select / clearSelection / crop / undo / redo`。
- 菜单命令面无法从共享层完成 `delete / duplicate / z-order`，平台层如果要做这些动作只能继续写私有逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: canSelectItem(withID:) / selectItem(withID:recordHistory:) / clearSelection(recordHistory:)
// 功能说明: 修改前 session 只承接基础 selection 变更，没有 delete、duplicate 和 z-order 的共享文档语义。
func canSelectItem(withID itemID: CanvasImageItemID) -> Bool {
    interactionState.selectedItemID != itemID
}

@discardableResult
func selectItem(
    withID itemID: CanvasImageItemID,
    recordHistory: Bool = false
) -> Bool {
    guard canSelectItem(withID: itemID) else {
        return false
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    interactionState.selectedItemID = itemID
    syncInlineEditStateWithSelection()

    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "select item"
        )
    }

    return true
}

@discardableResult
func clearSelection(recordHistory: Bool = false) -> Bool {
    guard canClearSelection else {
        return false
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    interactionState.selectedItemID = nil
    syncInlineEditStateWithSelection()

    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "clear selection"
        )
    }

    return true
}
```

### 修改后

- 为新命令增加了 `can...` 判定。
- 新增 `deleteItem / duplicateItem / bringItemForward / sendItemBackward / bringItemToFront / sendItemToBack`。
- `duplicateItem` 会显式选中新复制的项，并通过 `duplicateOffsetInWorld()` 产生稳定的视觉偏移。
- 所有新增命令都复用 session 内部的 `currentBoardHistorySnapshot / recordImmediateHistoryChange / syncInlineEditStateWithSelection / expandBoardIfNeeded`，而不是在平台层临时拼装。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: canDeleteItem(withID:) / canDuplicateItem(withID:) / canBringItemForward(withID:) / deleteItem(withID:recordHistory:) / duplicateItem(withID:selectDuplicatedItem:recordHistory:) / bringItemForward(withID:recordHistory:) / sendItemBackward(withID:recordHistory:) / bringItemToFront(withID:recordHistory:) / sendItemToBack(withID:recordHistory:) / duplicateOffsetInWorld()
// 功能说明: 修改后 session 承接新增命令的完整文档语义，把 history、selection、board expand 和 z-order 写入统一收口。
func canDeleteItem(withID itemID: CanvasImageItemID) -> Bool {
    scene.item(withID: itemID) != nil
}

func canDuplicateItem(withID itemID: CanvasImageItemID) -> Bool {
    scene.item(withID: itemID) != nil
}

func canBringItemForward(withID itemID: CanvasImageItemID) -> Bool {
    scene.canBringItemForward(withID: itemID)
}

@discardableResult
func deleteItem(
    withID itemID: CanvasImageItemID,
    recordHistory: Bool = false
) -> Bool {
    guard canDeleteItem(withID: itemID) else {
        return false
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    guard scene.removeItem(withID: itemID) else {
        return false
    }

    if interactionState.selectedItemID == itemID {
        interactionState.selectedItemID = nil
    }
    syncInlineEditStateWithSelection()

    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "delete item"
        )
    }

    return true
}

@discardableResult
func duplicateItem(
    withID itemID: CanvasImageItemID,
    selectDuplicatedItem: Bool = true,
    recordHistory: Bool = false
) -> CanvasImageItem? {
    guard canDuplicateItem(withID: itemID) else {
        return nil
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    guard let duplicatedItem = scene.duplicateItem(
        withID: itemID,
        offsetInWorld: duplicateOffsetInWorld()
    ) else {
        return nil
    }

    expandBoardIfNeeded(toInclude: duplicatedItem.worldBounds)
    if selectDuplicatedItem {
        interactionState.selectedItemID = duplicatedItem.id
    }
    syncInlineEditStateWithSelection()

    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "duplicate item"
        )
    }

    return duplicatedItem
}

func duplicateOffsetInWorld() -> CGPoint {
    let viewportOffset: CGFloat = 24
    let worldOffset = viewportOffset / max(camera.zoomScale, 0.01)
    return CGPoint(
        x: worldOffset,
        y: worldOffset
    )
}
```

## 修改三：命令层扩展到 `duplicate / delete / z-order`

### 修改前

- `CanvasCommandID` 和 `CanvasCommand` 只有 `crop / undo / redo / selectItem / clearSelection`。
- `CanvasCommandCatalog` 只产出这些基础命令的 descriptor。
- `CanvasCommandExecutor` 也只能执行这些基础命令。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名/类型名: CanvasCommandID / CanvasCommand
// 功能说明: 修改前命令模型只覆盖 crop、history 和 selection，无法承载 duplicate、delete、z-order。
enum CanvasCommandID: String {
    case crop
    case undo
    case redo
    case selectItem
    case clearSelection
}

enum CanvasCommand {
    case crop
    case undo
    case redo
    case selectItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)
}
```

### 修改后

- `CanvasCommandID` 和 `CanvasCommand` 增加了 `duplicateItem / deleteItem / bringItemForward / sendItemBackward / bringItemToFront / sendItemToBack`。
- `CanvasCommandCatalog` 增加了带 `context` 的 descriptor 计算，所有与目标 item 相关的命令启用态都依赖 `context.targetItemID`。
- `CanvasCommandExecutor` 现在能统一执行新增命令，并把刷新原因和 autosave 一起返回给平台层。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名/类型名: CanvasCommandID / CanvasCommand / shouldCancelActiveRotation
// 功能说明: 修改后命令模型扩展到 duplicate、delete 和 z-order，并保持与现有 rotation cancel 协议一致。
enum CanvasCommandID: String {
    case crop
    case undo
    case redo
    case selectItem
    case clearSelection
    case duplicateItem
    case deleteItem
    case bringItemForward
    case sendItemBackward
    case bringItemToFront
    case sendItemToBack
}

enum CanvasCommand {
    case crop
    case undo
    case redo
    case selectItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)
    case duplicateItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case deleteItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case bringItemForward(itemID: CanvasImageItemID, recordHistory: Bool)
    case sendItemBackward(itemID: CanvasImageItemID, recordHistory: Bool)
    case bringItemToFront(itemID: CanvasImageItemID, recordHistory: Bool)
    case sendItemToBack(itemID: CanvasImageItemID, recordHistory: Bool)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名/类型名: descriptor(for:session:context:)
// 功能说明: 修改后 command catalog 变成 context-aware，目标 item 相关命令不再由平台层自己猜启用态。
func descriptor(
    for commandID: CanvasCommandID,
    session: CanvasEditorSession,
    context: CanvasContextMenuContext? = nil
) -> CanvasCommandDescriptor {
    switch commandID {
    case .selectItem:
        return CanvasCommandDescriptor(
            id: .selectItem,
            title: "Select",
            systemImageName: "checkmark.circle",
            isEnabled: targetItemID(in: context).map { itemID in
                session.canSelectItem(withID: itemID)
            } ?? false,
            isActive: false
        )
    case .duplicateItem:
        return CanvasCommandDescriptor(
            id: .duplicateItem,
            title: "Duplicate",
            systemImageName: "square.on.square",
            isEnabled: targetItemID(in: context).map { itemID in
                session.canDuplicateItem(withID: itemID)
            } ?? false,
            isActive: false
        )
    case .deleteItem:
        return CanvasCommandDescriptor(
            id: .deleteItem,
            title: "Delete",
            systemImageName: "trash",
            isEnabled: targetItemID(in: context).map { itemID in
                session.canDeleteItem(withID: itemID)
            } ?? false,
            isActive: false
        )
    // ... 省略其他已写入文件的命令 descriptor，实际代码已落盘
    default:
        // ... existing code ...
        fatalError("covered in file")
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名/类型名: canExecute(_:) / execute(_:)
// 功能说明: 修改后 command executor 统一执行新增命令，并把 autosave/refresh reason 与原有命令链保持一致。
func canExecute(_ command: CanvasCommand) -> Bool {
    switch command {
    case let .duplicateItem(itemID, _):
        return session.canDuplicateItem(withID: itemID)
    case let .deleteItem(itemID, _):
        return session.canDeleteItem(withID: itemID)
    case let .bringItemForward(itemID, _):
        return session.canBringItemForward(withID: itemID)
    case let .sendItemBackward(itemID, _):
        return session.canSendItemBackward(withID: itemID)
    case let .bringItemToFront(itemID, _):
        return session.canBringItemToFront(withID: itemID)
    case let .sendItemToBack(itemID, _):
        return session.canSendItemToBack(withID: itemID)
    default:
        // ... existing code ...
        return false
    }
}

func execute(_ command: CanvasCommand) -> CanvasCommandExecutionResult? {
    guard canExecute(command) else {
        return nil
    }

    switch command {
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
    case let .deleteItem(itemID, recordHistory):
        guard session.deleteItem(
            withID: itemID,
            recordHistory: recordHistory
        ) else {
            return nil
        }

        session.scheduleAutosave(reason: "delete item")
        return CanvasCommandExecutionResult(
            refreshReason: "delete item \(itemID.uuidString)"
        )
    // ... 省略其他已写入文件的 z-order 命令执行分支，实际代码已落盘
    default:
        // ... existing code ...
        return nil
    }
}
```

## 修改四：上下文菜单从基础命令扩展到 handle / crop / z-order 分组

### 修改前

- `CanvasContextMenuCommandResolver` 只处理：
  - `blank`
  - `selectedItemBody`
  - `unselectedItemBody`
- `selectionHandle / rotateHandle / cropOutline / cropHandle` 全部直接返回空菜单。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名/类型名: commandIDs(for:session:) / command(for:context:)
// 功能说明: 修改前菜单分组只覆盖最基础的 blank/selected/unselected，handle 和 crop 相关上下文没有命令面。
func commandIDs(
    for context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> [CanvasCommandID] {
    let candidateIDs: [CanvasCommandID]

    switch context.targetKind {
    case .blank:
        candidateIDs = [
            .clearSelection,
            .undo,
            .redo
        ]
    case .selectedItemBody:
        candidateIDs = [
            .crop,
            .clearSelection,
            .undo,
            .redo
        ]
    case .unselectedItemBody:
        candidateIDs = [
            .selectItem,
            .undo,
            .redo
        ]
    case .rotateHandle, .cropHandle, .cropOutline, .selectionHandle:
        return []
    }

    return candidateIDs.filter { commandID in
        canPresent(
            commandID,
            for: context,
            session: session
        )
    }
}
```

### 修改后

- `commandIDs(...)` 改成先取 `candidateCommandIDs(for:)`，再统一用 `commandCatalog.descriptor(...context:)` 过滤启用态。
- `selectionHandle / rotateHandle` 与 `selectedItemBody` 一样，进入带 `crop + duplicate + delete + z-order + history` 的分组。
- `cropHandle / cropOutline` 也有了自己的命令面。
- `unselectedItemBody` 在保持“不自动改 selection”的前提下，也能直接看到 `duplicate / delete / z-order`。
- 所有需要目标 item 的命令都通过显式 `itemID` 构造成 `CanvasCommand`，不再依赖平台层当前选中项。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名/类型名: commandIDs(for:session:) / command(for:context:) / candidateCommandIDs(for:) / selectedItemCommandIDs(includeCropCommand:)
// 功能说明: 修改后菜单分组扩展到 handle/crop/z-order，且 invocation target 相关命令都显式携带 itemID。
func commandIDs(
    for context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> [CanvasCommandID] {
    candidateCommandIDs(for: context).filter { commandID in
        commandCatalog.descriptor(
            for: commandID,
            session: session,
            context: context
        ).isEnabled
    }
}

func command(
    for commandID: CanvasCommandID,
    context: CanvasContextMenuContext
) -> CanvasCommand? {
    switch commandID {
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
    case .bringItemForward:
        guard let itemID = context.targetItemID else {
            return nil
        }

        return .bringItemForward(
            itemID: itemID,
            recordHistory: true
        )
    // ... 省略其他已写入文件的命令映射，实际代码已落盘
    default:
        // ... existing code ...
        return nil
    }
}

private func candidateCommandIDs(
    for context: CanvasContextMenuContext
) -> [CanvasCommandID] {
    switch context.targetKind {
    case .blank:
        return [
            .clearSelection,
            .undo,
            .redo
        ]
    case .selectedItemBody, .selectionHandle, .rotateHandle:
        return selectedItemCommandIDs(includeCropCommand: true)
    case .unselectedItemBody:
        return [
            .selectItem,
            .duplicateItem,
            .deleteItem,
            .bringItemForward,
            .sendItemBackward,
            .bringItemToFront,
            .sendItemToBack,
            .undo,
            .redo
        ]
    case .cropHandle, .cropOutline:
        return selectedItemCommandIDs(includeCropCommand: true)
    }
}
```

## 修改五：平台层冻结菜单按钮时带上 `resolvedContext`

### 修改前

- `iOS/macOS` controller 冻结菜单按钮时只传 `commandID`，不带 `resolvedContext`。
- 这样平台层虽然能拿到命令列表，但 `descriptor` 的启用态还是缺少命中位置语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: frozenContextMenuCommandStates(for:) / commandDescriptor(for:) / presentContextMenu(for:)
// 功能说明: 修改前 iOS controller 冻结菜单按钮时没有把 resolvedContext 继续传给共享 descriptor。
private func frozenContextMenuCommandStates(
    for commandIDs: [CanvasCommandID]
) -> [CanvasContextMenuCommandState] {
    commandIDs.map { commandID in
        CanvasContextMenuCommandState(
            commandID: commandID,
            descriptor: commandDescriptor(for: commandID)
        )
    }
}

private func commandDescriptor(
    for commandID: CanvasCommandID
) -> CanvasCommandDescriptor {
    commandCatalog.descriptor(
        for: commandID,
        session: editorSession
    )
}
```

### 修改后

- `iOS/macOS` 两端都改为在冻结菜单按钮时把 `resolvedContext` 继续传入 `commandDescriptor(...context:)`。
- `macOS` 还同步扩展了 `performCommand(withID:)` 的 switch，显式覆盖新增命令 id，避免主菜单入口未来误落到未覆盖分支。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: frozenContextMenuCommandStates(for:context:) / commandDescriptor(for:context:) / presentContextMenu(for:)
// 功能说明: 修改后 iOS controller 冻结菜单按钮时会带上 resolvedContext，让共享 descriptor 真正消费位置语义。
private func frozenContextMenuCommandStates(
    for commandIDs: [CanvasCommandID],
    context: CanvasContextMenuContext
) -> [CanvasContextMenuCommandState] {
    commandIDs.map { commandID in
        CanvasContextMenuCommandState(
            commandID: commandID,
            descriptor: commandDescriptor(
                for: commandID,
                context: context
            )
        )
    }
}

private func commandDescriptor(
    for commandID: CanvasCommandID,
    context: CanvasContextMenuContext? = nil
) -> CanvasCommandDescriptor {
    commandCatalog.descriptor(
        for: commandID,
        session: editorSession,
        context: context
    )
}

private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let commandIDs = contextMenuCommandResolver.commandIDs(
        for: resolvedContext,
        session: editorSession
    )
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs,
        context: resolvedContext
    )
    guard commandStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        commandStates: commandStates
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: frozenContextMenuCommandStates(for:context:) / commandDescriptor(for:context:) / performCommand(withID:)
// 功能说明: 修改后 macOS controller 与 iOS 对齐，冻结 descriptor 时继续传递 resolvedContext，并显式覆盖新增命令 id。
private func frozenContextMenuCommandStates(
    for commandIDs: [CanvasCommandID],
    context: CanvasContextMenuContext
) -> [CanvasContextMenuCommandState] {
    commandIDs.map { commandID in
        CanvasContextMenuCommandState(
            commandID: commandID,
            descriptor: commandDescriptor(
                for: commandID,
                context: context
            )
        )
    }
}

private func commandDescriptor(
    for commandID: CanvasCommandID,
    context: CanvasContextMenuContext? = nil
) -> CanvasCommandDescriptor {
    commandCatalog.descriptor(
        for: commandID,
        session: editorSession,
        context: context
    )
}

func performCommand(withID commandID: CanvasCommandID) {
    switch commandID {
    case .crop:
        performCommand(CanvasCommand.crop)
    case .undo:
        performCommand(CanvasCommand.undo)
    case .redo:
        performCommand(CanvasCommand.redo)
    case .selectItem,
         .clearSelection,
         .duplicateItem,
         .deleteItem,
         .bringItemForward,
         .sendItemBackward,
         .bringItemToFront,
         .sendItemToBack:
        break
    }
}
```

## 验证结果

- 已通过 `date +"%Y%m%d_%H%M%S"` 获取本记录时间戳：`20260318_132759`
- 已通过 `ReadLints` 检查本次改动文件，无新增 lint 问题
- 已通过 `xcodebuild` 构建验证：
  - `macOS`: `generic/platform=macOS`
  - `iOS`: `generic/platform=iOS`

## 当前阶段结论

- 阶段 7 已把 `duplicate / delete / z-order` 从菜单展示层往下打通到共享命令层和共享场景层。
- 到这里，上下文菜单的命令不再需要直接调用平台私有编辑方法。
- `iOS/macOS` 两端目前都只保留薄的 UI 装配层，菜单内容、命令启用态、命令执行主体都已经共享。
