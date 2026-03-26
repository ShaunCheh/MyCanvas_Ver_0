# 20260326_101121_read_mode_phase4_command_contextmenu_gate_record

## 记录范围

- 记录内容：实施“阅读模式切换”计划的 `Phase 4`，把“阅读模式不能编辑”的语义收敛到共享命令层，而不是只靠 UI 隐藏。
- 记录内容：为 `CanvasCommandID` / `CanvasCommand` 增加阅读模式可执行语义，并让 `CanvasCommandExecutor` 真正阻断这些命令。
- 记录内容：让 `CanvasCommandCatalog` 在阅读模式下统一返回 disabled/inactive 的 command descriptor，保证 toolbar / history buttons / menu 的展示语义与执行语义一致。
- 记录内容：让 `CanvasContextMenuCommandResolver` 在阅读模式下直接返回空菜单，并补上双端模式切换时关闭已打开上下文菜单的收口。
- 记录内容：修掉 `iOSViewController` / `macOSViewController` 在阅读模式下仍可能隐式 `commitTextEdit` 的漏口。
- 涉及源码文件：`MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：Phase 5 输入链门控。
- 本记录不包含：新的持久化字段修改。
- 本记录不包含：原始 gif diff。

## 修改一：为共享命令增加“阅读模式可执行语义”

### 修改前

- `CanvasCommandID` 只有命令枚举值，没有“阅读模式允许/禁止”的共享语义。
- `CanvasCommand` 也只暴露 `id` 和旋转取消行为，是否允许在阅读模式执行完全散落在上层，无法形成统一规则。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名/符号名: CanvasCommandID / CanvasCommand.id / CanvasCommand.shouldCancelActiveRotation
// 功能说明: 修改前共享命令层没有阅读模式执行语义，后续 executor、descriptor、context menu 无法共用一套规则。
enum CanvasCommandID: String {
    case importImages
    case addTextItem
    case beginTextEdit
    case commitTextEdit
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
    case importImages(CanvasImportRequest)
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

    var id: CanvasCommandID {
        switch self {
        case .importImages: return .importImages
        case .addTextItem: return .addTextItem
        case .beginTextEdit: return .beginTextEdit
        case .commitTextEdit: return .commitTextEdit
        case .crop: return .crop
        case .undo: return .undo
        case .redo: return .redo
        case .selectItem: return .selectItem
        case .clearSelection: return .clearSelection
        case .duplicateItem: return .duplicateItem
        case .deleteItem: return .deleteItem
        case .bringItemForward: return .bringItemForward
        case .sendItemBackward: return .sendItemBackward
        case .bringItemToFront: return .bringItemToFront
        case .sendItemToBack: return .sendItemToBack
        }
    }
}
```

### 修改后

- 在 `CanvasCommandID` 上新增 `isAllowedInReadingMode`，把当前命令集统一标记为阅读模式不可执行。
- 在 `CanvasCommand` 上新增同名透传属性，供 executor / descriptor / controller 共用。
- 这样“阅读模式能不能执行命令”的根规则第一次落在共享命令模型本身，而不是散在各个 UI 入口里。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名/符号名: CanvasCommandID.isAllowedInReadingMode / CanvasCommand.isAllowedInReadingMode
// 功能说明: 为共享命令模型增加阅读模式执行语义，作为 executor、descriptor、context menu 的统一真源。
enum CanvasCommandID: String {
    case importImages
    case addTextItem
    case beginTextEdit
    case commitTextEdit
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

    // Current CanvasCommand set only covers document-mutating editing operations.
    // Navigation stays at the controller/input layer, so reading mode blocks all
    // of these commands until explicit read-safe commands are introduced.
    var isAllowedInReadingMode: Bool {
        switch self {
        case .importImages,
             .addTextItem,
             .beginTextEdit,
             .commitTextEdit,
             .crop,
             .undo,
             .redo,
             .selectItem,
             .clearSelection,
             .duplicateItem,
             .deleteItem,
             .bringItemForward,
             .sendItemBackward,
             .bringItemToFront,
             .sendItemToBack:
            return false
        }
    }
}

enum CanvasCommand {
    // ... 省略与本次改动无关的 case ...

    var id: CanvasCommandID {
        // ... 省略与本次改动无关的 switch ...
    }

    var isAllowedInReadingMode: Bool {
        id.isAllowedInReadingMode
    }
}
```

### 结果

- 阅读模式可执行策略从 UI 经验规则变成了共享命令语义。
- 后续如果新增真正的“只读安全命令”，只需要在 `CanvasCommandID.isAllowedInReadingMode` 白名单化即可，不必四处补条件。

## 修改二：`CanvasCommandExecutor` 真正阻断阅读模式下的编辑命令

### 修改前

- `canExecute(_:)` 只看命令本身的业务前置条件，比如能否裁剪、能否撤销、能否选中、能否删除。
- 只要这些业务条件满足，阅读模式下的编辑命令仍然会继续进入执行链。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名/符号名: canExecute(_:)
// 功能说明: 修改前 executor 不感知 workspaceMode，阅读模式下只要业务条件满足，编辑命令仍可执行。
func canExecute(_ command: CanvasCommand) -> Bool {
    switch command {
    case let .importImages(request):
        return request.isEmpty == false
    case .addTextItem:
        return session.canAddTextItem
    case let .beginTextEdit(itemID):
        return session.canBeginTextEdit(withID: itemID)
    case .commitTextEdit:
        return session.canCommitTextEdit
    case .crop:
        return session.isInlineCropModeActive || session.canBeginCropMode
    case .undo:
        return session.canUndoCommand
    case .redo:
        return session.canRedoCommand
    case let .selectItem(itemID, _):
        return session.canSelectItem(withID: itemID)
    case .clearSelection:
        return session.canClearSelection
    // ... 省略与本次改动无关的其余命令分支 ...
    }
}
```

### 修改后

- 在 `canExecute(_:)` 最前面新增统一门控：
  - 非阅读模式：保持原有逻辑
  - 阅读模式：只有 `command.isAllowedInReadingMode == true` 才能继续
- 当前命令集全部会在这里被挡住。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名/符号名: canExecute(_:)
// 功能说明: 在共享执行层统一阻断阅读模式下的编辑命令，避免 UI 隐藏后命令仍能执行。
func canExecute(_ command: CanvasCommand) -> Bool {
    guard session.isReadingModeActive == false || command.isAllowedInReadingMode else {
        return false
    }

    switch command {
    case let .importImages(request):
        return request.isEmpty == false
    case .addTextItem:
        return session.canAddTextItem
    case let .beginTextEdit(itemID):
        return session.canBeginTextEdit(withID: itemID)
    case .commitTextEdit:
        return session.canCommitTextEdit
    case .crop:
        return session.isInlineCropModeActive || session.canBeginCropMode
    case .undo:
        return session.canUndoCommand
    case .redo:
        return session.canRedoCommand
    case let .selectItem(itemID, _):
        return session.canSelectItem(withID: itemID)
    case .clearSelection:
        return session.canClearSelection
    // ... 省略与本次改动无关的其余命令分支 ...
    }
}
```

### 结果

- 阅读模式下，编辑命令会在共享执行器入口被统一挡住。
- 即使某个 UI 入口漏掉了按钮隐藏或 `isEnabled` 处理，也不会真的执行到文档变更层。

## 修改三：`CanvasCommandCatalog` 在阅读模式统一返回 disabled/inactive descriptor

### 修改前

- `descriptor(for:session:context:)` 会分别根据 session 当前状态构建各命令的 `isEnabled` / `isActive`。
- 但它不感知 `workspaceMode`，所以阅读模式下仍可能产出 enabled 的 descriptor。
- 这会造成“命令执行层已经不该允许，但描述层还显示可点”的语义割裂。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名/符号名: descriptor(for:session:context:)
// 功能说明: 修改前 descriptor 只根据业务状态生成 isEnabled/isActive，不会在阅读模式下统一压成 disabled。
func descriptor(
    for commandID: CanvasCommandID,
    session: CanvasEditorSession,
    context: CanvasContextMenuContext? = nil
) -> CanvasCommandDescriptor {
    switch commandID {
    case .addTextItem:
        return CanvasCommandDescriptor(
            id: .addTextItem,
            title: "Add Text",
            systemImageName: "textformat",
            isEnabled: session.canAddTextItem,
            isActive: false
        )
    case .commitTextEdit:
        return CanvasCommandDescriptor(
            id: .commitTextEdit,
            title: "Done",
            systemImageName: "checkmark",
            isEnabled: session.canCommitTextEdit,
            isActive: session.isInlineTextModeActive
        )
    case .crop:
        let isActive = session.isInlineCropModeActive
        return CanvasCommandDescriptor(
            id: .crop,
            title: isActive ? "Done" : "Crop",
            systemImageName: isActive ? "checkmark" : "crop",
            isEnabled: isActive || session.canBeginCropMode,
            isActive: isActive
        )
    // ... 省略与本次改动无关的其余分支 ...
    }
}
```

### 修改后

- 先按原逻辑组装 `descriptor`，再统一经过 `workspaceModeAdjustedDescriptor(...)`。
- 在阅读模式下，只要 `descriptor.id.isAllowedInReadingMode == false`，就统一改成：
  - `isEnabled = false`
  - `isActive = false`
- 这样 toolbar、history buttons、context menu 全部共用同一套阅读模式描述语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名/符号名: descriptor(for:session:context:) / workspaceModeAdjustedDescriptor(_:session:)
// 功能说明: 在共享 descriptor 层统一收口阅读模式命令状态，确保展示语义与执行语义一致。
func descriptor(
    for commandID: CanvasCommandID,
    session: CanvasEditorSession,
    context: CanvasContextMenuContext? = nil
) -> CanvasCommandDescriptor {
    let descriptor: CanvasCommandDescriptor
    switch commandID {
    case .addTextItem:
        descriptor = CanvasCommandDescriptor(
            id: .addTextItem,
            title: "Add Text",
            systemImageName: "textformat",
            isEnabled: session.canAddTextItem,
            isActive: false
        )
    case .commitTextEdit:
        descriptor = CanvasCommandDescriptor(
            id: .commitTextEdit,
            title: "Done",
            systemImageName: "checkmark",
            isEnabled: session.canCommitTextEdit,
            isActive: session.isInlineTextModeActive
        )
    case .crop:
        let isActive = session.isInlineCropModeActive
        descriptor = CanvasCommandDescriptor(
            id: .crop,
            title: isActive ? "Done" : "Crop",
            systemImageName: isActive ? "checkmark" : "crop",
            isEnabled: isActive || session.canBeginCropMode,
            isActive: isActive
        )
    // ... 省略与本次改动无关的其余分支 ...
    }

    return workspaceModeAdjustedDescriptor(
        descriptor,
        session: session
    )
}

private func workspaceModeAdjustedDescriptor(
    _ descriptor: CanvasCommandDescriptor,
    session: CanvasEditorSession
) -> CanvasCommandDescriptor {
    guard
        session.isReadingModeActive,
        descriptor.id.isAllowedInReadingMode == false
    else {
        return descriptor
    }

    return CanvasCommandDescriptor(
        id: descriptor.id,
        title: descriptor.title,
        systemImageName: descriptor.systemImageName,
        isEnabled: false,
        isActive: false
    )
}
```

### 结果

- 命令的展示态和执行态第一次统一到了同一条共享规则上。
- 阅读模式下，即便某些 UI 还在显示按钮，它们的 descriptor 也会统一变成 disabled/inactive，不会和 executor 打架。

## 修改四：`CanvasContextMenuCommandResolver` 在阅读模式直接返回空菜单

### 修改前

- `commandIDs(for:session:)` 会先按 `targetKind` 产出候选命令，再用 descriptor 过滤出 enabled 项。
- 它不区分 `workspaceMode`，所以阅读模式下仍可能弹出包含编辑操作的上下文菜单。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名/符号名: commandIDs(for:session:)
// 功能说明: 修改前上下文菜单 resolver 不感知阅读模式，会继续按目标类型生成编辑型菜单项。
func commandIDs(
    for context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> [CanvasCommandID] {
    let candidateIDs = candidateCommandIDs(
        for: context,
        session: session
    )
    let enabledIDs = candidateIDs.filter { commandID in
        commandCatalog.descriptor(
            for: commandID,
            session: session,
            context: context
        ).isEnabled
    }
    let enabledIDSet = Set(enabledIDs)
    let disabledIDs = candidateIDs.filter { enabledIDSet.contains($0) == false }
    print(
        "[Canvas Shared][ContextMenuCommands] " +
        context.debugSummary + " " +
        "candidateIDs=[\(describeContextMenuCommandIDs(candidateIDs))] " +
        "enabledIDs=[\(describeContextMenuCommandIDs(enabledIDs))] " +
        "disabledIDs=[\(describeContextMenuCommandIDs(disabledIDs))]"
    )
    return enabledIDs
}
```

### 修改后

- 在算出 `candidateIDs` 后，先检查 `session.isReadingModeActive`。
- 阅读模式下直接记录日志并返回 `[]`，采用最严格方案“空菜单”。
- 因为双端 controller 的 `presentContextMenu(...)` 本来就有 `guard commandStates.isEmpty == false else { dismissContextMenu(); return }`，所以这里返回空数组后会自然不弹菜单。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名/符号名: commandIDs(for:session:)
// 功能说明: 在阅读模式下统一返回空上下文菜单，避免任何编辑型 command 继续暴露给用户。
func commandIDs(
    for context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> [CanvasCommandID] {
    let candidateIDs = candidateCommandIDs(
        for: context,
        session: session
    )
    if session.isReadingModeActive {
        print(
            "[Canvas Shared][ContextMenuCommands] " +
            context.debugSummary + " " +
            "candidateIDs=[\(describeContextMenuCommandIDs(candidateIDs))] " +
            "enabledIDs=[] " +
            "disabledIDs=[\(describeContextMenuCommandIDs(candidateIDs))] " +
            "reason=readingMode"
        )
        return []
    }

    let enabledIDs = candidateIDs.filter { commandID in
        commandCatalog.descriptor(
            for: commandID,
            session: session,
            context: context
        ).isEnabled
    }
    let enabledIDSet = Set(enabledIDs)
    let disabledIDs = candidateIDs.filter { enabledIDSet.contains($0) == false }
    print(
        "[Canvas Shared][ContextMenuCommands] " +
        context.debugSummary + " " +
        "candidateIDs=[\(describeContextMenuCommandIDs(candidateIDs))] " +
        "enabledIDs=[\(describeContextMenuCommandIDs(enabledIDs))] " +
        "disabledIDs=[\(describeContextMenuCommandIDs(disabledIDs))]"
    )
    return enabledIDs
}
```

### 结果

- 阅读模式下不会再弹出编辑型上下文菜单。
- 这条规则落在共享 resolver 层，iOS / macOS 自动一起受益，不需要各自再手工删菜单项。

## 修改五：双端控制器补上“阅读模式不隐式提交文本编辑”和“切模式时关闭旧菜单”

### 修改前

- `performCommand(_:)` 在双端都有一条旧逻辑：只要当前是 inline text 模式，执行其他命令前就先递归 `performCommand(.commitTextEdit)`。
- 这条逻辑不区分 `workspaceMode`，所以阅读模式下理论上仍可能触发隐式 `commitTextEdit`。
- 模式按钮点击时也没有显式 `dismissContextMenu()`，如果上下文菜单已经打开，切到阅读模式后旧菜单会残留到下一次用户交互才消失。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: performCommand(_:) / handleWorkspaceModeButtonTap()
// 功能说明: 修改前 iOS 在阅读模式下仍可能隐式 commitTextEdit，切模式时也不会主动关闭已打开的上下文菜单。
private func performCommand(_ command: CanvasCommand) {
    if command.id != .commitTextEdit, isInlineTextModeActive {
        performCommand(.commitTextEdit)
    }

    guard commandExecutor.canExecute(command) else {
        return
    }

    dismissContextMenu()
    // ... 省略与本次改动无关的执行逻辑 ...
}

@objc
private func handleWorkspaceModeButtonTap() {
    workspaceMode = workspaceMode.toggled
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: performCommand(_:) / handleWorkspaceModeButtonClick()
// 功能说明: 修改前 macOS 同样存在阅读模式下隐式 commitTextEdit 和切模式不主动关闭旧菜单的问题。
private func performCommand(_ command: CanvasCommand) {
    if command.id != .commitTextEdit, isInlineTextModeActive {
        performCommand(.commitTextEdit)
    }

    guard commandExecutor.canExecute(command) else {
        return
    }

    dismissContextMenu()
    // ... 省略与本次改动无关的执行逻辑 ...
}

@objc
private func handleWorkspaceModeButtonClick() {
    workspaceMode = workspaceMode.toggled
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    refreshCanvas(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}
```

### 修改后

- 双端的隐式 `commitTextEdit` 逻辑都补上了 `workspaceMode == .editing` 条件。
- 模式按钮点击时先 `dismissContextMenu()`，再刷新按钮、chrome 和画布。
- 这样阅读模式切换不会再通过旧的隐式提交路径偷偷改文档，也不会留下一个已经不该存在的旧上下文菜单。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: performCommand(_:) / handleWorkspaceModeButtonTap()
// 功能说明: iOS 侧补上阅读模式隐式 commitTextEdit 保护，并在切换模式时主动关闭旧上下文菜单。
private func performCommand(_ command: CanvasCommand) {
    if command.id != .commitTextEdit,
       isInlineTextModeActive,
       workspaceMode == .editing
    {
        performCommand(.commitTextEdit)
    }

    guard commandExecutor.canExecute(command) else {
        return
    }

    dismissContextMenu()
    // ... 省略与本次改动无关的执行逻辑 ...
}

@objc
private func handleWorkspaceModeButtonTap() {
    workspaceMode = workspaceMode.toggled
    dismissContextMenu()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: performCommand(_:) / handleWorkspaceModeButtonClick()
// 功能说明: macOS 侧补上阅读模式隐式 commitTextEdit 保护，并在切换模式时主动关闭旧上下文菜单。
private func performCommand(_ command: CanvasCommand) {
    if command.id != .commitTextEdit,
       isInlineTextModeActive,
       workspaceMode == .editing
    {
        performCommand(.commitTextEdit)
    }

    guard commandExecutor.canExecute(command) else {
        return
    }

    dismissContextMenu()
    // ... 省略与本次改动无关的执行逻辑 ...
}

@objc
private func handleWorkspaceModeButtonClick() {
    workspaceMode = workspaceMode.toggled
    dismissContextMenu()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    refreshCanvas(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}
```

### 结果

- 双端都堵上了阅读模式下的隐式文本提交漏口。
- 如果用户是在弹出上下文菜单时切到阅读模式，旧菜单会立即被关闭，UI 不会残留一个与当前模式不一致的交互层。

## 校验

- `ReadLints` 检查通过，未发现以下文件的新 lint 错误：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 使用以下命令完成了共享层与 macOS 侧语法检查，并通过：
  - `xcrun --sdk macosx swiftc -frontend -parse "MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift" "MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift" "MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift" "MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift" "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"`
- iOS 侧当前本地环境仍缺少完整 iOS SDK，本次继续以 IDE lint 结果为主，没有额外执行完整 iOS 编译解析。
