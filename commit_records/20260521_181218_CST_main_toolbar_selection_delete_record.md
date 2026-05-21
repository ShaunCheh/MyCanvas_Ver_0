# 20260521_181218_CST_main_toolbar_selection_delete_record

## 记录范围

- 记录内容：
  - 为主 `toolbar` 新增 selection-aware 删除按钮。
  - 单选 `text` / `markdown` / `hand drawing` 时显示删除按钮；多选时显示“删除选中项”。
  - `iOS` / `macOS` 两端主 `toolbar` 都接入该按钮，并统一复用现有 `deleteSelection(recordHistory: true)` 命令链。
  - 为 `CanvasToolbarStateBuilder` 新增回归测试，锁定删除按钮的显示条件与危险样式。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift`
- 参考现状：
  - 生成本记录前，执行 `date +"%Y%m%d_%H%M%S_%Z"` 得到时间戳：`20260521_181218_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次改动相关文件执行 `git diff --stat -- ...`，结果为：`6 files changed, 194 insertions(+), 1 deletion(-)`。
  - 生成本记录前，针对本次改动相关文件执行 `git status --short -- ...`，结果为：`M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`、`M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`、`M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`、`M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`、`M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`、`M MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift`。
- 本记录不包含：
  - 为 `image` 单选补主 `toolbar` 删除按钮。
  - 在 `selection accessory` 或 context menu 中新增删除入口。
  - `deleteSelection` 执行链本身的语义调整或重构。

## 当前 changes 摘要

- 共享 `toolbar` 合同新增 `CanvasToolbarItemID.deleteSelection`，让主 `toolbar` 能以独立 item 渲染删除按钮。
- `CanvasToolbarStateBuilder` 新增删除按钮状态构造和显示条件判断：单选 `text` / `markdown` / `hand drawing` 时显示，多选时也显示，并用 `.danger` 危险视觉角色标记。
- `iOSViewController` / `macOSViewController` 各自新增 `deleteSelectionButton`，完成按钮注册、初始化和点击事件分发，点击时统一执行 `performCommand(.deleteSelection(recordHistory: true))`。
- `iOSCanvasToolbarHostView` 把 `deleteSelection` 纳入和 `crop` / `multiSelect` / `text` / `markdown` / `handDrawing` 一致的 symbol size 规格，避免按钮视觉尺寸跳变。
- `CanvasToolbarStateBuilderTests` 新增针对单选 `text`、单选 `markdown`、多选，以及已存在 `hand drawing` 场景的删除按钮断言。

## 修改一：主 toolbar 合同新增 `deleteSelection` item id

### 修改前

- 主 `toolbar` 只有新增内容、裁剪、多选、保存、历史等 item id。
- 删除虽然已经有现成命令能力，但主 `toolbar` 状态合同里没有一个可渲染的删除按钮 id。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift（修改前）
// 函数名: 无（CanvasToolbarItemID 枚举）
// 功能说明: 修改前主 toolbar 没有删除按钮对应的 item id，无法在共享状态层里声明删除入口。
enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case multiSelect
    case save
    case text
    case markdown
    case handDrawing
    case importMedia
    case undo
    case redo
}
```

### 修改后

- 新增 `deleteSelection`，让删除按钮进入主 `toolbar` 的共享状态模型。
- 后续 `builder`、host view、platform controller 都可以围绕这个 id 做统一分发。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名: 无（CanvasToolbarItemID 枚举）
// 功能说明: 修改后主 toolbar 拥有独立的删除按钮 item id，供共享状态层和平台层统一识别。
enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case multiSelect
    case deleteSelection
    case save
    case text
    case markdown
    case handDrawing
    case importMedia
    case undo
    case redo
}
```

## 修改二：`CanvasToolbarStateBuilder` 按选择状态注入危险删除按钮

### 修改前

- `mainToolbarState(...)` 只会在共享状态里拼接 `crop`、`multiSelect`、`save`、`text`、`markdown`、`handDrawing`、`importMedia` 等按钮。
- 删除命令虽然存在于 `CanvasCommandCatalog` 中，但主 `toolbar` 的共享状态构造阶段完全不会考虑它。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift（修改前）
// 函数名: mainToolbarState(session:saveState:placement:supportsHandDrawingEditing:isMultiSelectModeActive:isImportEnabled:showsBackground:includesHistoryItems:)
// 功能说明: 修改前 builder 不会根据当前 selection 生成主 toolbar 的删除按钮状态。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    supportsHandDrawingEditing: Bool = false,
    isMultiSelectModeActive: Bool = false,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true,
    includesHistoryItems: Bool = false
) -> CanvasToolbarState {
    guard session.isReadingModeActive == false else {
        return CanvasToolbarState(
            placement: placement,
            items: [],
            showsBackground: showsBackground
        )
    }

    var itemStates: [CanvasToolbarItemState] = []
    if includesHistoryItems {
        itemStates.append(contentsOf: historyItemStates(session: session))
    }
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(
        multiSelectItemState(
            isActive: isMultiSelectModeActive,
            isEnabled: canToggleMultiSelectMode(session: session)
        )
    )
    itemStates.append(saveItemState(saveState: saveState))
    itemStates.append(textItemState(session: session))
    itemStates.append(markdownItemState(session: session))
    if supportsHandDrawingEditing {
        itemStates.append(handDrawingItemState(session: session))
    }
    itemStates.append(importItemState(isEnabled: isImportEnabled))

    return CanvasToolbarState(
        placement: placement,
        items: itemStates,
        showsBackground: showsBackground
    )
}
```

### 修改后

- `mainToolbarState(...)` 会在 `multiSelect` 后面检查当前 selection 是否应该显示删除按钮。
- 新增 `deleteItemState(session:)`，直接复用 `CanvasCommandCatalog` 里的 `.deleteItem` descriptor，把 `trash` 图标和 `isEnabled` 状态接进来，但在主 `toolbar` 上用 `.danger` 强调危险操作。
- 新增 `shouldShowDeleteItem(...)` / `canShowDeleteForSingleSelection(...)`：
  - 单选 `text` / `markdown` / `handDrawing` 时显示。
  - `isMultiSelectModeActive == true` 时，如果当前 selection 可删，则显示。
  - `selectionCount > 1` 时也显示，确保任何多选状态都不会丢失删除入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名: mainToolbarState(...) / deleteItemState(session:) / shouldShowDeleteItem(session:isMultiSelectModeActive:) / canShowDeleteForSingleSelection(session:)
// 功能说明: 修改后 builder 会把删除按钮作为 selection-aware 的主 toolbar item 注入共享状态，并根据单选类型与多选状态决定显示与否。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    supportsHandDrawingEditing: Bool = false,
    isMultiSelectModeActive: Bool = false,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true,
    includesHistoryItems: Bool = false
) -> CanvasToolbarState {
    guard session.isReadingModeActive == false else {
        return CanvasToolbarState(
            placement: placement,
            items: [],
            showsBackground: showsBackground
        )
    }

    var itemStates: [CanvasToolbarItemState] = []
    if includesHistoryItems {
        itemStates.append(contentsOf: historyItemStates(session: session))
    }
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(
        multiSelectItemState(
            isActive: isMultiSelectModeActive,
            isEnabled: canToggleMultiSelectMode(session: session)
        )
    )
    if shouldShowDeleteItem(
        session: session,
        isMultiSelectModeActive: isMultiSelectModeActive
    ) {
        itemStates.append(deleteItemState(session: session))
    }
    itemStates.append(saveItemState(saveState: saveState))
    itemStates.append(textItemState(session: session))
    itemStates.append(markdownItemState(session: session))
    if supportsHandDrawingEditing {
        itemStates.append(handDrawingItemState(session: session))
    }
    itemStates.append(importItemState(isEnabled: isImportEnabled))

    return CanvasToolbarState(
        placement: placement,
        items: itemStates,
        showsBackground: showsBackground
    )
}

func deleteItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
    let descriptor = commandCatalog.descriptor(
        for: .deleteItem,
        session: session
    )
    let selectionCount = session.selectionCount
    let accessibilityLabel = selectionCount > 1
        ? "Delete selected items"
        : "Delete selected item"
    return CanvasToolbarItemState(
        id: .deleteSelection,
        systemImageName: descriptor.systemImageName,
        isEnabled: descriptor.isEnabled,
        accessibilityLabel: accessibilityLabel,
        visualRole: .danger
    )
}

private func shouldShowDeleteItem(
    session: CanvasEditorSession,
    isMultiSelectModeActive: Bool
) -> Bool {
    guard session.canDeleteSelection else {
        return false
    }

    if isMultiSelectModeActive {
        return true
    }

    if session.selectionCount > 1 {
        return true
    }

    return canShowDeleteForSingleSelection(session: session)
}

private func canShowDeleteForSingleSelection(
    session: CanvasEditorSession
) -> Bool {
    switch session.selectedBoardItemKind {
    case .text, .markdown, .handDrawing:
        return true
    case .image, .none:
        return false
    }
}
```

## 修改三：iOS 主 toolbar 接入删除按钮并保持图标尺寸一致

### 修改前

- `iOSViewController` 只预注册了 `crop`、`multiSelect`、`save`、`text`、`markdown`、`handDrawing`、`undo`、`redo`、`import` 按钮。
- `iOSCanvasToolbarHostView.symbolConfiguration(for:)` 也没有 `deleteSelection` 分支，因此即使后面硬塞一个删除按钮，也没有统一的图标尺寸规格。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: 无（toolbar 按钮属性 / toolbarButtonsByID） / setupMultiSelectButton() / handleMultiSelectButtonTap()
// 功能说明: 修改前 iOS 主 toolbar 没有 deleteSelectionButton，也没有把删除入口接到既有 selection 删除命令链上。
// ... 省略其他既有按钮定义。
private let multiSelectButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .multiSelect: multiSelectButton,
        .save: saveButton,
        .text: textButton,
        .markdown: markdownButton,
        .handDrawing: handDrawingButton,
        .importMedia: importButton
    ]
}

private func setupMultiSelectButton() {
    multiSelectButton.addTarget(
        self,
        action: #selector(handleMultiSelectButtonTap),
        for: .touchUpInside
    )
    renderToolbar()
}

@objc
private func handleMultiSelectButtonTap() {
    guard
        editorSession.isInlineEditModeActive == false,
        editorSession.isReadingModeActive == false
    else {
        return
    }

    isMultiSelectModeActive.toggle()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift（修改前）
// 函数名: symbolConfiguration(for:)
// 功能说明: 修改前 deleteSelection 不在统一的 symbol 尺寸分组里。
private func symbolConfiguration(
    for itemID: CanvasToolbarItemID
) -> UIImage.SymbolConfiguration {
    switch itemID {
    case .save, .undo, .redo:
        return UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    case .importMedia:
        return UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    case .crop, .multiSelect, .text, .markdown, .handDrawing:
        return UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    }
}
```

### 修改后

- `iOSViewController` 新增 `deleteSelectionButton`，加入 `toolbarButtonsByID`，并通过 `setupDeleteSelectionButton()` 与 `handleDeleteSelectionButtonTap()` 把点击事件导向 `performCommand(.deleteSelection(recordHistory: true))`。
- `iOSCanvasToolbarHostView` 把 `deleteSelection` 纳入既有 17pt semibold 的方形图标规格，保证删除按钮和周围编辑按钮视觉一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: 无（deleteSelectionButton 属性 / toolbarButtonsByID） / setupDeleteSelectionButton() / handleDeleteSelectionButtonTap()
// 功能说明: 修改后 iOS 主 toolbar 会预注册删除按钮，并把点击事件统一发到现有 deleteSelection 命令链。
// ... 省略其他既有按钮定义。
private let multiSelectButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()
private let deleteSelectionButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .multiSelect: multiSelectButton,
        .deleteSelection: deleteSelectionButton,
        .save: saveButton,
        .text: textButton,
        .markdown: markdownButton,
        .handDrawing: handDrawingButton,
        .importMedia: importButton
    ]
}

private func setupDeleteSelectionButton() {
    deleteSelectionButton.addTarget(
        self,
        action: #selector(handleDeleteSelectionButtonTap),
        for: .touchUpInside
    )
    renderToolbar()
}

@objc
private func handleDeleteSelectionButtonTap() {
    performCommand(.deleteSelection(recordHistory: true))
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: symbolConfiguration(for:)
// 功能说明: 修改后 deleteSelection 和 crop / multiSelect / text / markdown / handDrawing 共用同一档 symbol 尺寸，保持主 toolbar 视觉一致性。
private func symbolConfiguration(
    for itemID: CanvasToolbarItemID
) -> UIImage.SymbolConfiguration {
    switch itemID {
    case .save, .undo, .redo:
        return UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    case .importMedia:
        return UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    case .crop, .multiSelect, .deleteSelection, .text, .markdown, .handDrawing:
        return UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    }
}
```

## 修改四：macOS 主 toolbar 同步接入删除按钮

### 修改前

- `macOSViewController` 的主 `toolbar` 同样没有 `deleteSelectionButton`。
- 多选和删除虽然在命令层已经存在，但主 `toolbar` 没有把这条命令映射到一个可点击的固定按钮上。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift（修改前）
// 函数名: 无（toolbar 按钮属性 / toolbarButtonsByID） / setupMultiSelectButton() / handleMultiSelectButtonClick()
// 功能说明: 修改前 macOS 主 toolbar 没有删除按钮的固定接入点。
// ... 省略其他既有按钮定义。
private let multiSelectButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .multiSelect: multiSelectButton,
        .save: saveButton,
        .text: textButton,
        .markdown: markdownButton,
        .handDrawing: handDrawingButton,
        .importMedia: importButton
    ]
}

private func setupMultiSelectButton() {
    multiSelectButton.target = self
    multiSelectButton.action = #selector(handleMultiSelectButtonClick)
    renderToolbar()
}

@objc
private func handleMultiSelectButtonClick() {
    guard
        editorSession.isInlineEditModeActive == false,
        editorSession.isReadingModeActive == false
    else {
        return
    }

    isMultiSelectModeActive.toggle()
}
```

### 修改后

- `macOSViewController` 新增 `deleteSelectionButton`，加入主 `toolbar` 的固定按钮注册表。
- 新增 `setupDeleteSelectionButton()` / `handleDeleteSelectionButtonClick()`，点击时和 `iOS` 一样统一走 `deleteSelection(recordHistory: true)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: 无（deleteSelectionButton 属性 / toolbarButtonsByID） / setupDeleteSelectionButton() / handleDeleteSelectionButtonClick()
// 功能说明: 修改后 macOS 主 toolbar 和 iOS 一样拥有固定删除按钮，并复用同一条 selection 删除命令链。
// ... 省略其他既有按钮定义。
private let multiSelectButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()
private let deleteSelectionButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .multiSelect: multiSelectButton,
        .deleteSelection: deleteSelectionButton,
        .save: saveButton,
        .text: textButton,
        .markdown: markdownButton,
        .handDrawing: handDrawingButton,
        .importMedia: importButton
    ]
}

private func setupDeleteSelectionButton() {
    deleteSelectionButton.target = self
    deleteSelectionButton.action = #selector(handleDeleteSelectionButtonClick)
    renderToolbar()
}

@objc
private func handleDeleteSelectionButtonClick() {
    performCommand(.deleteSelection(recordHistory: true))
}
```

## 修改五：测试锁定删除按钮的显示规则

### 修改前

- `CanvasToolbarStateBuilderTests` 只覆盖了 `multiSelect`、`markdown`、`handDrawing` 编辑入口、`reading mode` 等既有状态。
- 没有测试去断言主 `toolbar` 在 `text` / `markdown` / `handDrawing` 单选和多选时是否真的会显示删除按钮。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift（修改前）
// 函数名: testMainToolbarStateIncludesMarkdownItem() / testSelectedHandDrawingShowsEditToolbarItemAndHidesCrop()
// 功能说明: 修改前测试只覆盖既有 toolbar 项和 hand drawing 编辑入口，没有删除按钮相关断言。
func testMainToolbarStateIncludesMarkdownItem() throws {
    let session = makeToolbarStateBuilderTestSession()
    let builder = CanvasToolbarStateBuilder()

    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing)
    )

    let markdownItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .markdown })
    )
    XCTAssertEqual(markdownItem.systemImageName, "text.alignleft")
    XCTAssertEqual(markdownItem.accessibilityLabel, "Add markdown")
    XCTAssertTrue(markdownItem.isEnabled)
    XCTAssertEqual(markdownItem.visualRole, .accent)
}

func testSelectedHandDrawingShowsEditToolbarItemAndHidesCrop() throws {
    let session = makeToolbarStateBuilderTestSession()
    let builder = CanvasToolbarStateBuilder()
    let handDrawingItem = try makeToolbarStateBuilderTestHandDrawingItem()
    session.scene.append(handDrawingItem)
    session.interactionState = CanvasInteractionState(
        selectedItemID: handDrawingItem.id
    )

    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing),
        supportsHandDrawingEditing: true
    )

    let handDrawingToolbarItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .handDrawing })
    )
    XCTAssertEqual(handDrawingToolbarItem.accessibilityLabel, "Edit hand drawing")
    XCTAssertEqual(handDrawingToolbarItem.systemImageName, "pencil.and.scribble")
    XCTAssertFalse(state.items.contains(where: { $0.id == .crop }))
}
```

### 修改后

- 新增 `testSelectedTextShowsDeleteToolbarItem()`、`testSelectedMarkdownShowsDeleteToolbarItem()`、`testMultiSelectionShowsDeleteToolbarItem()`。
- 原有 `handDrawing` 测试也补了删除按钮断言，确保“单选 `hand drawing` 显示删除”不会回退。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift
// 函数名: testSelectedTextShowsDeleteToolbarItem() / testSelectedMarkdownShowsDeleteToolbarItem() / testMultiSelectionShowsDeleteToolbarItem() / testSelectedHandDrawingShowsEditToolbarItemAndHidesCrop()
// 功能说明: 修改后测试明确锁定主 toolbar 删除按钮在 text / markdown / hand drawing 单选与多选场景下的显示合同。
func testSelectedTextShowsDeleteToolbarItem() throws {
    let session = makeToolbarStateBuilderTestSession()
    let builder = CanvasToolbarStateBuilder()
    let textItem = CanvasTextItem(
        text: "Delete me",
        center: CGPoint(x: 80, y: 60),
        size: CGSize(width: 180, height: 80)
    )
    session.scene.append(textItem)
    session.interactionState = CanvasInteractionState(selectedItemID: textItem.id)

    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing)
    )

    let deleteItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .deleteSelection })
    )
    XCTAssertEqual(deleteItem.systemImageName, "trash")
    XCTAssertEqual(deleteItem.accessibilityLabel, "Delete selected item")
    XCTAssertEqual(deleteItem.visualRole, .danger)
    XCTAssertTrue(deleteItem.isEnabled)
}

func testSelectedMarkdownShowsDeleteToolbarItem() throws {
    let session = makeToolbarStateBuilderTestSession()
    let builder = CanvasToolbarStateBuilder()
    let markdownItem = CanvasMarkdownItem(
        markdownSource: "# Delete me",
        center: CGPoint(x: 100, y: 72),
        size: CGSize(width: 220, height: 140)
    )
    session.scene.append(markdownItem)
    session.interactionState = CanvasInteractionState(
        selectedItemID: markdownItem.id
    )

    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing)
    )

    let deleteItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .deleteSelection })
    )
    XCTAssertEqual(deleteItem.accessibilityLabel, "Delete selected item")
    XCTAssertEqual(deleteItem.visualRole, .danger)
    XCTAssertTrue(deleteItem.isEnabled)
}

func testMultiSelectionShowsDeleteToolbarItem() throws {
    let session = makeToolbarStateBuilderTestSession()
    let builder = CanvasToolbarStateBuilder()
    let firstImageItem = CanvasImageItem(
        asset: CanvasImageAsset.transientStaticImage(
            cgImage: try makeToolbarStateBuilderTestImage()
        ),
        center: CGPoint(x: 60, y: 40),
        size: CGSize(width: 120, height: 80),
        zIndex: 0
    )
    let secondImageItem = CanvasImageItem(
        asset: CanvasImageAsset.transientStaticImage(
            cgImage: try makeToolbarStateBuilderTestImage()
        ),
        center: CGPoint(x: 180, y: 120),
        size: CGSize(width: 96, height: 96),
        zIndex: 1
    )
    session.scene.append(firstImageItem)
    session.scene.append(secondImageItem)
    session.interactionState = CanvasInteractionState(
        selectedItemIDs: [firstImageItem.id, secondImageItem.id],
        primarySelectedItemID: secondImageItem.id
    )

    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing),
        isMultiSelectModeActive: true
    )

    let deleteItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .deleteSelection })
    )
    XCTAssertEqual(deleteItem.accessibilityLabel, "Delete selected items")
    XCTAssertEqual(deleteItem.visualRole, .danger)
    XCTAssertTrue(deleteItem.isEnabled)
}

func testSelectedHandDrawingShowsEditToolbarItemAndHidesCrop() throws {
    let session = makeToolbarStateBuilderTestSession()
    let builder = CanvasToolbarStateBuilder()
    let handDrawingItem = try makeToolbarStateBuilderTestHandDrawingItem()
    session.scene.append(handDrawingItem)
    session.interactionState = CanvasInteractionState(
        selectedItemID: handDrawingItem.id
    )

    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing),
        supportsHandDrawingEditing: true
    )

    let handDrawingToolbarItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .handDrawing })
    )
    let deleteItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .deleteSelection })
    )
    XCTAssertEqual(handDrawingToolbarItem.accessibilityLabel, "Edit hand drawing")
    XCTAssertEqual(handDrawingToolbarItem.systemImageName, "pencil.and.scribble")
    XCTAssertEqual(deleteItem.accessibilityLabel, "Delete selected item")
    XCTAssertEqual(deleteItem.visualRole, .danger)
    XCTAssertFalse(state.items.contains(where: { $0.id == .crop }))
}
```

## 验证情况

- `ReadLints` 检查以下文件，未发现新增问题：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift`
- 已执行构建验证并通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" build`
- 已执行测试验证并通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvasToolbarDeleteTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests" test`

## 结论

- 这次改动没有发明新的删除实现，而是把现有 `deleteSelection` 命令链提升到主 `toolbar`，从而在 `text` / `markdown` / `hand drawing` 单选和多选场景中都提供统一、稳定的删除入口。
- 删除按钮的显示合同被收敛到共享 `toolbar` state builder 中，平台层只负责按钮注册和命令转发，因此后续如果还要把 `image` 单选纳入，只需要在共享显示条件里扩展即可。
