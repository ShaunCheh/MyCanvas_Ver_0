# 20260326_100136_read_mode_phase3_presentation_freeze_record

## 记录范围

- 记录内容：实施“阅读模式切换”计划的 `Phase 3`，在不清空真实编辑状态的前提下，冻结阅读模式下的编辑呈现。
- 记录内容：让 `CanvasEditorSession` 产出“展示态”快照，使主画布和小地图在阅读模式下不再显示选中框、裁剪框、旋转 affordance、文本编辑预览。
- 记录内容：让 `CanvasToolbarStateBuilder` 在阅读模式下返回空 `items`，复用现有 toolbar host 的自动隐藏与零尺寸测量链。
- 记录内容：让 iOS / macOS 的 `syncTextEditorPresentation()` 只读取展示态内联编辑状态；iOS 同阶段隐藏 `historyButtonsStackView`，并调整 UI 刷新顺序。
- 涉及源码文件：`MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：命令门控、上下文菜单门控、输入入口门控。
- 本记录不包含：新的持久化字段变更。
- 本记录不包含：原始 gif diff。

## 修改一：`CanvasEditorSession` 新增 presentation 视角，冻结主画布与小地图的编辑呈现

### 修改前

- `makeCanvasSnapshot()` 直接读取真实 `interactionState`、`inlineEditState`、`rotationPreviewState`、`rotationInteractionState`。
- `makeMiniMapSnapshot()` 也直接读取真实 `inlineEditState`、`rotationPreviewState`。
- 这意味着即使切到阅读模式，只要真实状态里还保留着选中项、裁剪草稿、文本编辑草稿或旋转预览，renderer / minimap 仍会把这些编辑痕迹画出来。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/符号名: isReadingModeActive / isEditingModeActive / makeCanvasSnapshot() / makeMiniMapSnapshot()
// 功能说明: 修改前 snapshot 直接消费真实编辑状态，阅读模式不会冻结选中框、裁剪框、旋转预览或文本编辑预览。
var isReadingModeActive: Bool {
    workspaceMode == .reading
}

var isEditingModeActive: Bool {
    workspaceMode == .editing
}

func makeCanvasSnapshot() -> CanvasRenderSnapshot {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    )
    lastRenderSnapshot = snapshot
    return snapshot
}

func makeMiniMapSnapshot() -> CanvasMiniMapSnapshot {
    miniMapRenderer.makeSnapshot(
        context: CanvasMiniMapRenderContext(
            scene: scene,
            boardState: boardState,
            camera: camera,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )
    )
}
```

### 修改后

- 在 `CanvasEditorSession` 内引入只读的 presentation 视角：
  - `presentationInteractionState`
  - `presentationInlineEditState`
  - `presentationRotationPreviewState`
  - `presentationRotationInteractionState`
- 阅读模式下，这些 presentation 状态会返回“清空后的展示态”；编辑模式下，则继续透传真实状态。
- `makeCanvasSnapshot()` / `makeMiniMapSnapshot()` 全部改为消费 presentation 视角，从根上冻结主画布与小地图的编辑呈现。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/符号名: presentationInteractionState / presentationInlineEditState / presentationRotationPreviewState / presentationRotationInteractionState / makeCanvasSnapshot() / makeMiniMapSnapshot()
// 功能说明: 新增展示态视角，在阅读模式下只冻结“画出来的状态”，不清空真实 interactionState / inlineEditState / rotationPreviewState。
var isReadingModeActive: Bool {
    workspaceMode == .reading
}

var isEditingModeActive: Bool {
    workspaceMode == .editing
}

var presentationInteractionState: CanvasInteractionState {
    guard isReadingModeActive else {
        return interactionState
    }

    return CanvasInteractionState()
}

var presentationInlineEditState: CanvasInlineEditState? {
    isReadingModeActive ? nil : inlineEditState
}

var presentationRotationPreviewState: CanvasRotationPreviewState? {
    isReadingModeActive ? nil : rotationPreviewState
}

var presentationRotationInteractionState: CanvasRotationInteractionState? {
    isReadingModeActive ? nil : rotationInteractionState
}

func makeCanvasSnapshot() -> CanvasRenderSnapshot {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: presentationInteractionState,
        inlineEditState: presentationInlineEditState,
        rotationPreviewState: presentationRotationPreviewState,
        rotationInteractionState: presentationRotationInteractionState
    )
    lastRenderSnapshot = snapshot
    return snapshot
}

func makeMiniMapSnapshot() -> CanvasMiniMapSnapshot {
    miniMapRenderer.makeSnapshot(
        context: CanvasMiniMapRenderContext(
            scene: scene,
            boardState: boardState,
            camera: camera,
            inlineEditState: presentationInlineEditState,
            rotationPreviewState: presentationRotationPreviewState
        )
    )
}
```

### 结果

- 阅读模式下，真实选中态、裁剪草稿、文本草稿、旋转预览仍保留在 session 中，不会被破坏。
- 但 renderer 和 minimap 只看到展示态，因此选中框、裁剪框、旋转 affordance、文本预览都会消失。
- 切回编辑模式后，这些真实状态会重新被消费，UI 能恢复到切换前的编辑上下文。

## 修改二：`CanvasToolbarStateBuilder` 在阅读模式直接返回空 `items`

### 修改前

- `mainToolbarState(...)` 无论当前 workspace mode 是什么，都会继续构建 crop / save / text / import 这些 toolbar item。
- 即便 controller 想把 toolbar 隐藏掉，shared builder 仍然会产出编辑向 items，状态语义并不收口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名/符号名: mainToolbarState(session:saveState:placement:isImportEnabled:showsBackground:)
// 功能说明: 修改前 toolbar builder 不区分阅读模式与编辑模式，总是继续生成编辑向 toolbar items。
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
```

### 修改后

- 在 shared builder 最上游直接加 `session.isReadingModeActive` 判断。
- 阅读模式下不再生成任何编辑向 toolbar item，而是返回 `items: []`。
- 这样可以直接复用现有 `toolbar host` 的行为：
  - `render(empty items)` 时自动 `isHidden = true`
  - `syncButtons(with: [])` 会清空 stack
  - `measuredContentSize()` 会回到 `.zero`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名/符号名: mainToolbarState(session:saveState:placement:isImportEnabled:showsBackground:)
// 功能说明: 在阅读模式下直接返回空 toolbar items，从共享状态层根因隐藏工具条，并归零测量尺寸。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true
) -> CanvasToolbarState {
    guard session.isReadingModeActive == false else {
        return CanvasToolbarState(
            placement: placement,
            items: [],
            showsBackground: showsBackground
        )
    }

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
```

### 结果

- 工具条在阅读模式下不是“靠 view controller 硬隐藏”，而是从共享 toolbar state 生成层就不再产出编辑向内容。
- 因为 toolbar host 会同步清空按钮栈并把测量值归零，布局 solver 也不会再为隐藏工具条保留额外占位。

## 修改三：iOS 侧把文本浮层、history buttons、模式切换刷新链统一到展示态

### 修改前

- 点击右上角模式按钮后，只刷新按钮图标和 overlay 布局，不会主动刷新主画布 / minimap。
- `restoreBoard()` / `startNewBoard()` / `restorePersistedBoardIfPossible()` / `applyBoardRuntimeState()` 中，先刷新内联编辑 UI，再刷新模式按钮图标。
- `syncTextEditorPresentation()` 直接消费真实 `inlineEditState`，所以阅读模式下如果真实状态仍在 `.text`，文本编辑浮层依旧会显示。
- `updateInlineEditButtonsAppearance()` 先跑 `updatePreparedToolbarPlacement()`，再更新 `historyButtons`；这会让布局 blocker 有机会读到“旧的 history 可见性”。
- `updateHistoryButtonsAppearance()` 也没有在阅读模式下隐藏 `historyButtonsStackView`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleWorkspaceModeButtonTap() / restoreBoard(withID:) / startNewBoard() / restorePersistedBoardIfPossible() / applyBoardRuntimeState(_:) / syncTextEditorPresentation() / updateInlineEditButtonsAppearance() / updateHistoryButtonsAppearance()
// 功能说明: 修改前 iOS 的模式切换只刷新按钮和 overlay；文本浮层直接吃真实 inlineEditState；history buttons 不会在阅读模式下隐藏。
@objc
private func handleWorkspaceModeButtonTap() {
    workspaceMode = workspaceMode.toggled
    updateWorkspaceModeButtonAppearance()
    updatePreparedToolbarPlacement()
    scheduleAutosave(reason: "toggle workspace mode")
}

private func restoreBoard(withID boardID: UUID) {
    do {
        try editorSession.loadBoard(id: boardID)
    } catch {
        print(
            "[Canvas iOS][RuntimeRestore] " +
            "action=controllerLoadBoard.failed " +
            "boardID=\(boardID.uuidString) " +
            "error=\(error)"
        )
    }
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
}

private func startNewBoard() {
    editorSession.startNewBoard()
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
}

private func restorePersistedBoardIfPossible() {
    editorSession.restorePersistedBoardIfPossible()
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
}

private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    editorSession.applyBoardRuntimeState(runtimeState)
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
}

private func syncTextEditorPresentation() {
    guard isViewLoaded else {
        return
    }

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

    // ... 省略与本次改动无关的文本同步代码 ...
}

private func updateInlineEditButtonsAppearance() {
    updatePreparedToolbarPlacement()
    updateHistoryButtonsAppearance()
    syncTextEditorPresentation()
}

private func updateHistoryButtonsAppearance() {
    updateUndoButtonAppearance()
    updateRedoButtonAppearance()
}
```

### 修改后

- 点击模式按钮后，会先统一刷新编辑向 chrome，再显式触发 `requestCanvasRefresh(reason: "toggle workspace mode")`，把主画布与 minimap 一起刷新。
- runtime restore 系列路径先刷新模式按钮图标，再刷新编辑向 chrome，保证刷新顺序与当前 `workspaceMode` 对齐。
- `syncTextEditorPresentation()` 改为只读 `presentationInlineEditState`，阅读模式下即使真实 text draft 仍存在，也会强制隐藏文本浮层。
- `updateInlineEditButtonsAppearance()` 改为先更新 history buttons，再重跑 toolbar/layout blocker，再同步文本浮层。
- `updateHistoryButtonsAppearance()` 在阅读模式下会先隐藏 `historyButtonsStackView`，确保 blocker 与最终可见态一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleWorkspaceModeButtonTap() / restoreBoard(withID:) / startNewBoard() / restorePersistedBoardIfPossible() / applyBoardRuntimeState(_:) / syncTextEditorPresentation() / updateInlineEditButtonsAppearance() / updateHistoryButtonsAppearance() / presentationInlineEditState / isReadingModeActive
// 功能说明: iOS 阅读模式下统一冻结文本浮层、隐藏 history buttons，并在模式切换或 runtime restore 后同步刷新主画布、minimap 与 chrome。
@objc
private func handleWorkspaceModeButtonTap() {
    workspaceMode = workspaceMode.toggled
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}

private func restoreBoard(withID boardID: UUID) {
    do {
        try editorSession.loadBoard(id: boardID)
    } catch {
        print(
            "[Canvas iOS][RuntimeRestore] " +
            "action=controllerLoadBoard.failed " +
            "boardID=\(boardID.uuidString) " +
            "error=\(error)"
        )
    }
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
}

private func startNewBoard() {
    editorSession.startNewBoard()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
}

private func restorePersistedBoardIfPossible() {
    editorSession.restorePersistedBoardIfPossible()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
}

private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    editorSession.applyBoardRuntimeState(runtimeState)
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
}

private func syncTextEditorPresentation() {
    guard isViewLoaded else {
        return
    }

    guard
        let inlineEditState = presentationInlineEditState,
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

    // ... 省略与本次改动无关的文本同步代码 ...
}

private func updateInlineEditButtonsAppearance() {
    updateHistoryButtonsAppearance()
    updatePreparedToolbarPlacement()
    syncTextEditorPresentation()
}

private func updateHistoryButtonsAppearance() {
    historyButtonsStackView.isHidden = isReadingModeActive
    updateUndoButtonAppearance()
    updateRedoButtonAppearance()
}

private var presentationInlineEditState: CanvasInlineEditState? {
    editorSession.presentationInlineEditState
}

private var isReadingModeActive: Bool {
    editorSession.isReadingModeActive
}
```

### 结果

- iOS 切到阅读模式时，文本浮层会立刻隐藏，即便真实 text draft 仍然保留。
- iOS 的 `historyButtonsStackView` 会在阅读模式下先隐藏，再进入 blocker/layout 计算，不会再出现“视觉已隐藏但布局仍占位”的次序问题。
- 模式切换后会主动刷新主画布和 minimap，因此选中框、裁剪框、旋转 affordance、文本预览都会同步消失。

## 修改四：macOS 侧把文本浮层与模式切换刷新链统一到展示态

### 修改前

- 点击右上角模式按钮后，只刷新按钮图标和 overlay 布局，不会主动刷新主画布 / minimap。
- runtime restore 系列路径中，先刷新内联编辑 UI，再刷新模式按钮图标。
- `syncTextEditorPresentation()` 直接消费真实 `inlineEditState`，阅读模式下如果真实 text draft 还在，文本浮层依旧会显示。
- 控制器内也没有显式的 `presentationInlineEditState` 透传入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleWorkspaceModeButtonClick() / restoreBoard(withID:) / startNewBoard() / restorePersistedBoardIfPossible() / applyBoardRuntimeState(_:) / syncTextEditorPresentation()
// 功能说明: 修改前 macOS 的模式切换不会主动刷新主画布/minimap；文本浮层直接读取真实 inlineEditState，阅读模式无法冻结文本编辑呈现。
@objc
private func handleWorkspaceModeButtonClick() {
    workspaceMode = workspaceMode.toggled
    updateWorkspaceModeButtonAppearance()
    updatePreparedToolbarPlacement()
    scheduleAutosave(reason: "toggle workspace mode")
}

private func restoreBoard(withID boardID: UUID) {
    // ... 省略与本次改动无关的日志代码 ...
    do {
        try editorSession.loadBoard(id: boardID)
    } catch {
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerLoadBoard.failed " +
            "boardID=\(boardID.uuidString) " +
            "error=\(error)"
        )
    }
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
}

private func startNewBoard() {
    // ... 省略与本次改动无关的日志代码 ...
    editorSession.startNewBoard()
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
}

private func restorePersistedBoardIfPossible() {
    // ... 省略与本次改动无关的日志代码 ...
    editorSession.restorePersistedBoardIfPossible()
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
}

private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    // ... 省略与本次改动无关的日志代码 ...
    editorSession.applyBoardRuntimeState(runtimeState)
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
}

private func syncTextEditorPresentation() {
    guard isViewLoaded else {
        return
    }

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

    // ... 省略与本次改动无关的文本同步代码 ...
}
```

### 修改后

- 点击模式按钮后，先刷新编辑向 chrome，再调用 `refreshCanvas(reason: "toggle workspace mode")`，主动刷新主画布与 minimap。
- runtime restore 系列路径全部改为先刷新模式按钮，再刷新编辑向 chrome。
- `syncTextEditorPresentation()` 改为只读 `presentationInlineEditState`，阅读模式下会强制隐藏文本浮层，但不丢失真实 text draft。
- 控制器增加了 `presentationInlineEditState` 透传属性，明确从 `editorSession` 读取展示态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleWorkspaceModeButtonClick() / restoreBoard(withID:) / startNewBoard() / restorePersistedBoardIfPossible() / applyBoardRuntimeState(_:) / syncTextEditorPresentation() / presentationInlineEditState
// 功能说明: macOS 阅读模式下统一冻结文本浮层，并在模式切换或 runtime restore 后同步刷新主画布、minimap 与 chrome。
@objc
private func handleWorkspaceModeButtonClick() {
    workspaceMode = workspaceMode.toggled
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    refreshCanvas(reason: "toggle workspace mode")
    scheduleAutosave(reason: "toggle workspace mode")
}

private func restoreBoard(withID boardID: UUID) {
    // ... 省略与本次改动无关的日志代码 ...
    do {
        try editorSession.loadBoard(id: boardID)
    } catch {
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerLoadBoard.failed " +
            "boardID=\(boardID.uuidString) " +
            "error=\(error)"
        )
    }
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
}

private func startNewBoard() {
    // ... 省略与本次改动无关的日志代码 ...
    editorSession.startNewBoard()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
}

private func restorePersistedBoardIfPossible() {
    // ... 省略与本次改动无关的日志代码 ...
    editorSession.restorePersistedBoardIfPossible()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
}

private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    // ... 省略与本次改动无关的日志代码 ...
    editorSession.applyBoardRuntimeState(runtimeState)
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
}

private func syncTextEditorPresentation() {
    guard isViewLoaded else {
        return
    }

    guard
        let inlineEditState = presentationInlineEditState,
        inlineEditState.mode == .text
    else {
        if view.window?.firstResponder === textEditorOverlayView.textView {
            view.window?.makeFirstResponder(canvasViewportView)
        }
        textEditorOverlayView.isHidden = true
        activeTextEditorItemID = nil
        return
    }

    // ... 省略与本次改动无关的文本同步代码 ...
}

private var presentationInlineEditState: CanvasInlineEditState? {
    editorSession.presentationInlineEditState
}
```

### 结果

- macOS 切到阅读模式时，文本浮层会立即隐藏，但真实文本草稿仍保留在 session 里。
- 切回编辑模式后，controller 又会重新消费真实编辑状态，文本编辑上下文可以恢复。
- 模式切换时主画布与 minimap 会同步刷新，阅读模式下不会再残留旧的选中 / 裁剪 / 旋转可视提示。

## 校验

- `ReadLints` 检查通过，未发现以下文件的新 lint 错误：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 使用以下命令完成了共享层与 macOS 侧语法检查，并通过：
  - `xcrun --sdk macosx swiftc -frontend -parse "MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift" "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift" "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"`
- iOS 侧当前本地环境仍缺少完整 iOS SDK，本次继续以 IDE lint 结果为主，没有额外执行完整 iOS 编译解析。
