# 20260323_145902_text_support_phase_t4_text_editing_record

## 记录范围

- 记录内容：
  1. 将 `CanvasInlineEditState` 从 crop-only 升级为同时承载 `crop` / `text` 的双态 inline edit。
  2. 在 `CanvasCommand`、`CanvasCommandExecutor`、`CanvasCommandCatalog`、`CanvasEditorSession` 中补齐最小文本命令链：添加文本、开始编辑、更新 draft、提交编辑。
  3. 在 `CanvasScene` / `CanvasRenderer` / `CanvasImagePresentationResolver` 中补齐文本 draft 回显，并避免 text inline edit 干扰 image crop preview。
  4. 在共享 toolbar / context menu 中加入 icon-only 的文本入口，并让 `crop` 对 text item 变成类型感知。
  5. 为 `iOS` / `macOS` 新增最小文本编辑浮层，并将控制器接到共享命令链。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - `minimap` / `board list preview` / `thumbnail` 的文本闭环
  - 原始 gif diff
  - git commit / push

## 修改一：`CanvasInlineEditState` 从 crop-only 升级为 crop/text 双态

### 修改前

- `CanvasInlineEditMode` 只有 `.crop`。
- `CanvasInlineEditState` 直接绑定 `CanvasImageItemID + CanvasInlineCropSession`，`mode` 恒为 `.crop`，无法承载文本 draft。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名: N/A（CanvasInlineEditMode / CanvasInlineCropSession / CanvasInlineEditState）
// 功能说明: 修改前 inline edit 只服务于图片裁剪；状态结构天然假设目标一定是 image item。
enum CanvasInlineEditMode: Equatable {
    case crop
}

struct CanvasInlineCropSession {
    var draftCropRectNormalized: CanvasImageCropRect
}

struct CanvasInlineEditState {
    let itemID: CanvasImageItemID
    var cropSession: CanvasInlineCropSession

    var mode: CanvasInlineEditMode {
        .crop
    }

    var draftCropRectNormalized: CanvasImageCropRect {
        get {
            return cropSession.draftCropRectNormalized
        }
        set {
            cropSession.draftCropRectNormalized = newValue
        }
    }
}
```

### 修改后

- 新增 `CanvasInlineTextSession` 与 `CanvasInlineEditSession`。
- `CanvasInlineEditState` 改为统一持有 `CanvasItemID`，通过 `session` 分流 `crop` / `text`，同时暴露 `draftCropRectNormalized` 和 `draftText`。
- 文本编辑态仍然完全排除在 `BoardRuntimeState` / `board.json` 之外，只作为瞬时 UI draft。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名: N/A（CanvasInlineEditMode / CanvasInlineTextSession / CanvasInlineEditState）
// 功能说明: 修改后 inline edit 变成 image crop 与 text edit 共存的瞬时编辑态；共享层不再把 inline edit 绑定到 image-only 语义。
enum CanvasInlineEditMode: Equatable {
    case crop
    case text
}

struct CanvasInlineCropSession: Equatable {
    var draftCropRectNormalized: CanvasImageCropRect
}

struct CanvasInlineTextSession: Equatable {
    var draftText: String
}

enum CanvasInlineEditSession: Equatable {
    case crop(CanvasInlineCropSession)
    case text(CanvasInlineTextSession)
}

struct CanvasInlineEditState {
    let itemID: CanvasItemID
    private var session: CanvasInlineEditSession

    var mode: CanvasInlineEditMode {
        switch session {
        case .crop:
            return .crop
        case .text:
            return .text
        }
    }

    var draftCropRectNormalized: CanvasImageCropRect { /* ... */ }
    var draftText: String { /* ... */ }

    init(
        itemID: CanvasItemID,
        draftText: String
    ) {
        self.itemID = itemID
        session = .text(
            CanvasInlineTextSession(
                draftText: draftText
            )
        )
    }

    init(
        item: CanvasTextItem
    ) {
        self.init(
            itemID: item.id,
            draftText: item.text
        )
    }
}
```

## 修改二：共享命令链补齐文本创建、编辑与提交

### 修改前

- `CanvasCommandID` / `CanvasCommand` 只有 import、crop、undo/redo、selection、reorder 等命令。
- `CanvasCommandExecutor` 也只认识 crop/history/item 命令；文本编辑没有共享入口。
- `CanvasEditorSession` 只有 crop-only 的 inline edit 入口，无法统一记录文本编辑历史。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名: N/A（CanvasCommandID / CanvasCommand）
// 功能说明: 修改前共享命令层没有“文本创建/编辑/提交”语义，平台层无法把文本编辑接入统一命令执行链。
enum CanvasCommandID: String {
    case importImages
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

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: beginCropModeIfPossible() / endInlineEditMode() / nextImageZIndex()
// 功能说明: 修改前 session 只提供 crop inline edit；文本项虽然能被渲染，但还没有共享的编辑、提交、历史与 autosave 路径。
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
func endInlineEditMode() -> Bool {
    guard inlineEditState != nil else {
        return false
    }

    inlineEditState = nil
    return true
}

func nextImageZIndex() -> CGFloat {
    (scene.orderedBoardItems().last?.zIndex ?? -1) + 1
}
```

### 修改后

- `CanvasCommand` 增加 `addTextItem`、`beginTextEdit`、`commitTextEdit`。
- `CanvasCommandExecutor` 统一把文本命令下沉到 `CanvasEditorSession`，并产出刷新原因。
- `CanvasEditorSession` 新增 `CanvasTextEditCommitResult`、`addTextItem()`、`beginTextEdit()`、`updateTextEditDraft()`、`commitTextEdit()`。
- `commitTextEdit()` 会对空白文本执行删除，并统一记录 history/autosave。
- `addTextItem()` 默认在 `camera.center` 创建文本框，并立即进入 text inline edit。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名: N/A（CanvasCommandID / CanvasCommand）
// 功能说明: 修改后共享命令层具备文本创建与编辑提交语义；平台层可以直接复用现有 performCommand(...) 链路。
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
    // ... 省略已有 item commands ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名: canExecute(_:) / execute(_:)
// 功能说明: 修改后 executor 会统一校验与执行文本命令；controller 不需要绕开命令层自己写文本编辑分支。
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
    // ... 省略其余命令 ...
    }
}

func execute(_ command: CanvasCommand) -> CanvasCommandExecutionResult? {
    switch command {
    case .addTextItem:
        guard let addedTextItem = session.addTextItem() else {
            return nil
        }
        return CanvasCommandExecutionResult(
            refreshReason: "add text item \(addedTextItem.id.uuidString)"
        )
    case let .beginTextEdit(itemID):
        guard session.beginTextEdit(withID: itemID) else {
            return nil
        }
        return CanvasCommandExecutionResult(
            refreshReason: "begin text edit \(itemID.uuidString)"
        )
    case .commitTextEdit:
        guard let commitResult = session.commitTextEdit() else {
            return nil
        }
        let refreshReason: String
        if commitResult.didDeleteItem {
            refreshReason = "delete empty text item \(commitResult.itemID.uuidString)"
        } else if commitResult.didChangeDocument {
            refreshReason = "commit text edit \(commitResult.itemID.uuidString)"
        } else {
            refreshReason = "finish text edit \(commitResult.itemID.uuidString)"
        }
        return CanvasCommandExecutionResult(
            refreshReason: refreshReason
        )
    // ... 省略已有命令 ...
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: beginTextEdit(withID:) / updateTextEditDraft(_:) / commitTextEdit() / addTextItem(text:style:)
// 功能说明: 修改后 session 负责文本编辑生命周期、空白文本删除、history 记录与 autosave，下层 scene / renderer 只消费最终状态或 draft。
struct CanvasTextEditCommitResult {
    let itemID: CanvasItemID
    let didDeleteItem: Bool
    let didChangeDocument: Bool
}

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

func updateTextEditDraft(_ draftText: String) -> Bool {
    guard
        var inlineEditState,
        inlineEditState.mode == .text,
        inlineEditState.draftText != draftText
    else {
        return false
    }

    inlineEditState.draftText = draftText
    self.inlineEditState = inlineEditState
    return true
}

func commitTextEdit() -> CanvasTextEditCommitResult? {
    // 空白文本会直接删除 item，并记录 history/autosave。
    // 非空文本则通过 scene.updateTextItem(...) 提交内容。
    // 未修改内容时只退出 inline edit，不制造无效历史。
    /* ... 省略其余实现 ... */
}

func addTextItem(
    text: String = "Text",
    style: CanvasTextStyle = .default
) -> CanvasTextItem? {
    guard canAddTextItem else {
        return nil
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    let item = CanvasTextItem(
        text: text,
        style: style,
        center: camera.center,
        size: defaultTextItemSize(for: style),
        zIndex: nextBoardItemZIndex()
    )
    scene.append(item)
    interactionState.selectedItemID = item.id
    inlineEditState = CanvasInlineEditState(item: item)
    expandBoardIfNeeded(toInclude: item.worldFrame)
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: "add text item",
        autosaveReason: "add text item"
    )
    return item
}
```

## 修改三：Scene / Renderer 补齐文本 draft 回显，并避免 text inline edit 误触 crop preview

### 修改前

- `CanvasScene` 没有共享的 `updateTextItem(withID:text:)`。
- `CanvasRenderer.makeTextRenderItem(...)` 总是读 `effectiveTextItem.text`，文本 draft 不会实时回显。
- `CanvasImagePresentationResolver` 只要 `inlineEditState?.itemID == item.id` 就认为 crop preview 激活，text inline edit 会误命中 image preview 分支。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift
// 函数名: resolve(item:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 image presentation 只按 itemID 判断 inline edit；一旦未来 inline edit 承载 text，这里就会误把 text draft 当成 crop preview。
func resolve(
    item: CanvasImageItem,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasImagePresentation {
    let isCropPreviewActive = inlineEditState?.itemID == item.id
    let isRotationPreviewActive = rotationPreviewState?.itemID == item.id
    // ... 省略其余逻辑 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeTextRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改前 text render item 只消费持久化内容；平台层的输入控件即使更新 draft，也不会在主画布实时回显。
private func makeTextRenderItem(
    for item: CanvasTextItem,
    camera: CanvasCamera,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    let screenQuad = camera.worldToViewport(effectiveTextItem.worldQuad)
    return CanvasRenderItem(
        // ... 省略几何字段 ...
        payload: .text(
            CanvasTextRenderPayload(
                text: effectiveTextItem.text,
                style: effectiveTextItem.style,
                zoomScale: camera.zoomScale
            )
        )
    )
}
```

### 修改后

- `CanvasScene.updateTextItem(withID:text:)` 成为共享文本写入口。
- `CanvasRenderer.makeTextRenderItem(...)` 接收 `inlineEditState`，当文本项处于 `.text` inline edit 时优先渲染 `draftText`。
- `CanvasImagePresentationResolver` 改成 `inlineEditState?.mode == .crop` 后才进入 crop preview。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: updateTextItem(withID:text:)
// 功能说明: 修改后文本内容提交统一落到 Scene；session 只负责 history/autosave，具体 item mutation 仍由共享 scene 接管。
@discardableResult
func updateTextItem(
    withID id: CanvasItemID,
    text: String
) -> CanvasTextItem? {
    updateBoardItem(withID: id) { item in
        guard case var .text(textItem) = item else {
            return nil
        }

        textItem.text = text
        item = .text(textItem)
        return textItem
    } ?? nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift
// 函数名: resolve(item:inlineEditState:rotationPreviewState:)
// 功能说明: 修改后 image preview 只有在 `.crop` inline edit 命中同一个 image item 时才展开，文本编辑不会误触图片裁剪预览。
func resolve(
    item: CanvasImageItem,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasImagePresentation {
    let isCropPreviewActive =
        inlineEditState?.mode == .crop &&
        inlineEditState?.itemID == item.id
    let isRotationPreviewActive = rotationPreviewState?.itemID == item.id
    // ... 省略其余逻辑 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeTextRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改后 renderer 会优先消费 text inline edit 的 draftText，因此平台层键入时主画布文本内容能实时回显。
private func makeTextRenderItem(
    for item: CanvasTextItem,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    let effectiveTextItem: CanvasTextItem
    switch effectiveBoardItem(
        from: .text(item),
        rotationPreviewState: rotationPreviewState
    ) {
    case let .text(resolvedTextItem):
        effectiveTextItem = resolvedTextItem
    case .image:
        assertionFailure("Expected text item after applying text presentation.")
        effectiveTextItem = item
    }

    let resolvedText: String
    if inlineEditState?.mode == .text, inlineEditState?.itemID == effectiveTextItem.id {
        resolvedText = inlineEditState?.draftText ?? effectiveTextItem.text
    } else {
        resolvedText = effectiveTextItem.text
    }

    return CanvasRenderItem(
        // ... 省略几何字段 ...
        payload: .text(
            CanvasTextRenderPayload(
                text: resolvedText,
                style: effectiveTextItem.style,
                zoomScale: camera.zoomScale
            )
        )
    )
}
```

## 修改四：主工具栏新增 icon-only 文本按钮，并让 toolbar / context menu 按 item 类型感知 `crop`

### 修改前

- `CanvasToolbarItemID` 没有 `.text`。
- `mainToolbarState(...)` 的主工具栏永远是 `[crop, save, import]`。
- `CanvasContextMenuCommandResolver` 对 selected item 总是假设 `crop` 可参与候选，无法对 text item 屏蔽。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名: N/A（CanvasToolbarItemID）
// 功能说明: 修改前主工具栏 item ID 集合中没有文本入口，toolbar host 也无从注册对应按钮。
enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case save
    case importImage
    case undo
    case redo
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名: mainToolbarState(session:saveState:placement:isImportEnabled:showsBackground:)
// 功能说明: 修改前主工具栏固定渲染 crop/save/import 三个按钮，且不会根据选中 item 类型隐藏 crop。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true
) -> CanvasToolbarState {
    CanvasToolbarState(
        placement: placement,
        items: [
            cropItemState(session: session),
            saveItemState(saveState: saveState),
            importItemState(isEnabled: isImportEnabled)
        ],
        showsBackground: showsBackground
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名: selectedItemCommandIDs(includeCropCommand:)
// 功能说明: 修改前 context menu 只知道“要不要包含 crop”，不知道目标 item 是 image 还是 text。
private func selectedItemCommandIDs(
    includeCropCommand: Bool
) -> [CanvasCommandID] {
    var commandIDs: [CanvasCommandID] = []
    if includeCropCommand {
        commandIDs.append(.crop)
    }
    commandIDs.append(contentsOf: [
        .duplicateItem,
        .deleteItem,
        .bringItemForward,
        .sendItemBackward,
        .bringItemToFront,
        .sendItemToBack,
        .clearSelection,
        .undo,
        .redo
    ])
    return commandIDs
}
```

### 修改后

- `CanvasToolbarItemID` 新增 `.text`。
- `CanvasToolbarStateBuilder` 通过 `textItemState(session:)` 在主工具栏加入 icon-only 文本按钮；当文本正在编辑时，该按钮切到 `Done/checkmark`。
- `shouldShowCropItem(session:)` 会在选中文本项时隐藏 `crop`，但图片 crop mode 激活时仍保留原样。
- `CanvasContextMenuCommandResolver` 新增 `targetTextItem` 分支，对 text item 插入 `beginTextEdit`，并屏蔽 `crop`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名: N/A（CanvasToolbarItemID）
// 功能说明: 修改后主工具栏与 toolbar host 能识别独立的文本按钮 ID。
enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case save
    case text
    case importImage
    case undo
    case redo
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名: mainToolbarState(...) / textItemState(session:) / shouldShowCropItem(session:)
// 功能说明: 修改后主工具栏常驻 icon-only 文本按钮；文本编辑时按钮切成 Done，选中文本项时 crop 会从主工具栏消失。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true
) -> CanvasToolbarState {
    var itemStates: [CanvasToolbarItemState] = []
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(saveItemState(saveState: saveState))
    itemStates.append(textItemState(session: session))
    itemStates.append(importItemState(isEnabled: isImportEnabled))

    return CanvasToolbarState(
        placement: placement,
        items: itemStates,
        showsBackground: showsBackground
    )
}

func textItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
    let descriptor = commandCatalog.descriptor(
        for: session.isInlineTextModeActive ? .commitTextEdit : .addTextItem,
        session: session
    )
    return CanvasToolbarItemState(
        id: .text,
        systemImageName: descriptor.systemImageName,
        isEnabled: descriptor.isEnabled,
        isActive: descriptor.isActive,
        accessibilityLabel: descriptor.title == "Done" ? "Done editing text" : "Add text",
        visualRole: descriptor.isActive ? .success : .accent
    )
}

private func shouldShowCropItem(session: CanvasEditorSession) -> Bool {
    guard session.isInlineCropModeActive == false else {
        return true
    }

    return session.selectedBoardItemKind != .text
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名: command(for:context:) / candidateCommandIDs(for:session:) / selectedItemCommandIDs(...) / unselectedItemCommandIDs(...)
// 功能说明: 修改后 context menu 会按 target item 类型注入 Edit Text，并对 text item 禁掉 crop。
func command(
    for commandID: CanvasCommandID,
    context: CanvasContextMenuContext
) -> CanvasCommand? {
    switch commandID {
    case .addTextItem:
        return .addTextItem
    case .beginTextEdit:
        guard let itemID = context.targetItemID else {
            return nil
        }
        return .beginTextEdit(itemID: itemID)
    case .commitTextEdit:
        return .commitTextEdit
    // ... 省略已有命令 ...
    }
}

private func candidateCommandIDs(
    for context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> [CanvasCommandID] {
    let targetTextItem = context.targetItemID.flatMap { itemID in
        session.scene.textItem(withID: itemID)
    }

    switch context.targetKind {
    case .selectedItemBody, .selectionHandle, .rotateHandle:
        return selectedItemCommandIDs(
            includeCropCommand: targetTextItem == nil,
            includeBeginTextEditCommand: targetTextItem != nil
        )
    case .unselectedItemBody:
        return unselectedItemCommandIDs(
            includeBeginTextEditCommand: targetTextItem != nil
        )
    case .cropHandle, .cropOutline:
        return selectedItemCommandIDs(
            includeCropCommand: true,
            includeBeginTextEditCommand: false
        )
    case .blank:
        return [.clearSelection, .undo, .redo]
    }
}
```

## 修改五：`iOS` / `macOS` 新增最小文本编辑浮层，并接入 controller

### 修改前

- `iOSViewController` / `macOSViewController` 没有 `textButton`、没有 text editor overlay、也没有 `UITextViewDelegate` / `NSTextViewDelegate`。
- toolbar button map 中只有 `crop`、`save`、`importImage`。
- controller 不会在点击已选中文本项时进入编辑，也不会在 `import/save/back` 前自动提交文本编辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: N/A（类型声明 / toolbarButtonsByID）
// 功能说明: 修改前 iOS controller 只有图片相关 toolbar 按钮与 import/crop 流程；文本内容虽然可渲染，但没有最小编辑 UI 入口。
final class iOSViewController: UIViewController, PHPickerViewControllerDelegate, UIDropInteractionDelegate {
    private let toolbarHostView = iOSCanvasToolbarHostView()
    private let importButton: UIButton = { /* ... */ }()
    private let saveButton: UIButton = { /* ... */ }()
    private let cropButton: UIButton = { /* ... */ }()

    private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
        [
            .crop: cropButton,
            .save: saveButton,
            .importImage: importButton
        ]
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: N/A（类型声明 / toolbarButtonsByID）
// 功能说明: 修改前 macOS controller 也没有文本按钮与文本输入浮层；桌面端无法在当前架构里提交文本内容编辑。
final class macOSViewController: NSViewController, NSUserInterfaceValidations {
    private let toolbarHostView = macOSCanvasToolbarHostView()
    private let importButton: NSButton = { /* ... */ }()
    private let saveButton: NSButton = { /* ... */ }()
    private let cropButton: NSButton = { /* ... */ }()

    private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
        [
            .crop: cropButton,
            .save: saveButton,
            .importImage: importButton
        ]
    }
}
```

### 修改后

- 新增 `iOSCanvasTextEditorOverlayView.swift` 与 `macOSCanvasTextEditorOverlayView.swift`，作为轻量文本编辑浮层。
- 两端 controller 都新增 `textButton`、`textEditorOverlayView`、文本 delegate、`handleTextButtonTap/Click`、`syncTextEditorPresentation()`。
- 两端都会在进入 import/save/back、点击画布、打开 context menu 前先提交正在编辑的文本。
- 再次点击已选中的 text item，会直接进入 `beginTextEdit(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift
// 函数名: init(frame:) / apply(text:)
// 功能说明: 修改后 iOS 平台有了最小文本编辑浮层；它只承载输入控件与背景样式，不直接操作 scene/history。
final class iOSCanvasTextEditorOverlayView: UIView {
    private let backgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground.withAlphaComponent(0.96)
        view.layer.cornerRadius = 18
        // ... 省略阴影与边框 ...
        return view
    }()

    let textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .label
        textView.tintColor = .systemBlue
        textView.accessibilityLabel = "Text editor"
        return textView
    }()

    func apply(text: String) {
        if textView.text != text {
            textView.text = text
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupTextEditorOverlay() / setupTextButton() / handleTextButtonTap() / commitActiveTextEditIfNeeded() / syncTextEditorPresentation()
// 功能说明: 修改后 iOS controller 把 text button、text overlay、共享命令链和 first responder 管理连成一条闭环。
private func setupTextEditorOverlay() {
    textEditorOverlayView.textView.delegate = self
    syncTextEditorPresentation()
}

private func setupTextButton() {
    textButton.addTarget(self, action: #selector(handleTextButtonTap), for: .touchUpInside)
    updateInlineEditButtonsAppearance()
}

@objc
private func handleTextButtonTap() {
    if isInlineTextModeActive {
        performCommand(.commitTextEdit)
    } else {
        performCommand(.addTextItem)
    }
}

@discardableResult
private func commitActiveTextEditIfNeeded() -> Bool {
    guard isInlineTextModeActive else {
        return false
    }

    performCommand(.commitTextEdit)
    return true
}

private func syncTextEditorPresentation() {
    guard
        let inlineEditState,
        inlineEditState.mode == .text
    else {
        if textEditorOverlayView.textView.isFirstResponder {
            textEditorOverlayView.textView.resignFirstResponder()
        }
        textEditorOverlayView.isHidden = true
        activeTextEditorItemID = nil
        becomeFirstResponder()
        return
    }

    let didChangeEditedItem = activeTextEditorItemID != inlineEditState.itemID
    activeTextEditorItemID = inlineEditState.itemID
    textEditorOverlayView.isHidden = false
    if textEditorOverlayView.textView.text != inlineEditState.draftText {
        isSyncingTextEditorContent = true
        textEditorOverlayView.apply(text: inlineEditState.draftText)
        isSyncingTextEditorContent = false
    }
    if textEditorOverlayView.textView.isFirstResponder == false {
        textEditorOverlayView.textView.becomeFirstResponder()
    }
    if didChangeEditedItem {
        let textLength = textEditorOverlayView.textView.text.utf16.count
        textEditorOverlayView.textView.selectedRange = NSRange(
            location: 0,
            length: textLength
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift
// 函数名: init(frame:) / apply(text:)
// 功能说明: 修改后 macOS 平台也有对等的最小文本编辑浮层；内部使用 NSScrollView + NSTextView 承载输入。
final class macOSCanvasTextEditorOverlayView: NSView {
    private let backgroundView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.96).cgColor
        view.layer?.cornerRadius = 18
        // ... 省略边框与阴影 ...
        return view
    }()

    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }()

    let textView: NSTextView = {
        let textView = NSTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.font = .systemFont(ofSize: 15)
        return textView
    }()

    func apply(text: String) {
        if textView.string != text {
            textView.string = text
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: setupTextEditorOverlay() / setupTextButton() / handleTextButtonClick() / commitActiveTextEditIfNeeded() / syncTextEditorPresentation()
// 功能说明: 修改后 macOS controller 用相同的共享命令链驱动文本编辑；差异只体现在 AppKit 的 first responder 与 NSTextView delegate。
private func setupTextEditorOverlay() {
    textEditorOverlayView.textView.delegate = self
    syncTextEditorPresentation()
}

private func setupTextButton() {
    textButton.target = self
    textButton.action = #selector(handleTextButtonClick)
    updateInlineEditButtonsAppearance()
}

@objc
private func handleTextButtonClick() {
    if isInlineTextModeActive {
        performCommand(.commitTextEdit)
    } else {
        performCommand(.addTextItem)
    }
}

@discardableResult
private func commitActiveTextEditIfNeeded() -> Bool {
    guard isInlineTextModeActive else {
        return false
    }

    performCommand(.commitTextEdit)
    return true
}

private func syncTextEditorPresentation() {
    guard
        let inlineEditState,
        inlineEditState.mode == .text
    else {
        if view.window?.firstResponder === textEditorOverlayView.textView {
            view.window?.makeFirstResponder(canvasViewportView)
        }
        textEditorOverlayView.isHidden = true
        activeTextEditorItemID = nil
        return
    }

    let didChangeEditedItem = activeTextEditorItemID != inlineEditState.itemID
    activeTextEditorItemID = inlineEditState.itemID
    textEditorOverlayView.isHidden = false
    if textEditorOverlayView.textView.string != inlineEditState.draftText {
        isSyncingTextEditorContent = true
        textEditorOverlayView.apply(text: inlineEditState.draftText)
        isSyncingTextEditorContent = false
    }
    if let window = view.window, window.firstResponder !== textEditorOverlayView.textView {
        window.makeFirstResponder(textEditorOverlayView.textView)
    }
    if didChangeEditedItem {
        textEditorOverlayView.textView.selectAll(nil)
    }
}
```

## 验证结果

- `ReadLints`：本次修改涉及文件未发现新的 IDE 诊断错误。
- `xcrun --sdk macosx swiftc -typecheck -target arm64-apple-macos15.0 ...`：通过。
- `iphoneos` / `iphonesimulator` CLI SDK：当前机器不可用，因此未做独立的 iOS `swiftc -typecheck`；本次 iOS 侧以 IDE diagnostics 为主进行静态校验。

