# 20260410_114600_toolbar_history_phase1_record

## 记录说明

本记录基于当前工作区的实际 `changes`、本次对应文件的 `git diff`，以及修改后的当前代码状态整理，不包含原始 `git diff` 文本。

这次只记录刚刚已经落地的“toolbar history convergence 阶段 1”：

- 共享 `toolbar builder` 具备按需组装 `undo/redo` 的能力。
- `macOS toolbar` 正式接入 `undo/redo` 按钮。
- `iOS` 的独立 `historyButtonsStackView` 这次没有动，仍留待后续阶段收敛。

当前工作区实际变更文件只有 2 个：

- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前统计：`2 files changed, 80 insertions(+), 2 deletions(-)`

## 时间戳与取证命令

```bash
# 文件路径: /bin/date
# 函数: date
# 说明: 生成本记录文件名前缀使用的时间戳。
date +"%Y%m%d_%H%M%S"
```

```bash
# 文件路径: /usr/bin/git
# 函数: git status --short / git diff --stat / git diff
# 说明: 确认当前 changes 仅包含这次阶段 1 的两个代码文件，并据此整理下面的“修改前 / 修改后”代码片段。
git status --short

git diff --stat -- \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"

git diff -- \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
```

## 本次修改的真实边界

这次不是直接开始拆 `iOS` 的独立 history UI，而是先把根因链的前半段补齐：

1. 共享层此前已经有 `CanvasToolbarItemID.undo/.redo`，也有 `CanvasCommandCatalog` 的命令描述，但 `CanvasToolbarStateBuilder.mainToolbarState(...)` 根本不会把它们组装进主工具条。
2. `macOSViewController` 虽然可以执行 `.undo/.redo`，菜单和快捷键也能走通，但 toolbar 没有注册对应按钮，因此不会显示在工具条里。
3. `macOS` 在历史事务提交后没有像 `iOS` 那样主动刷新 history 按钮外观；如果只把按钮加进 toolbar，不补刷新链，启用态会滞后。

因此，这次实际落地的是“共享组装能力 + macOS 工具条接线 + macOS 历史状态刷新”，没有提前进入 iOS 双轨 UI 的拆除。

## 修改一：`CanvasToolbarStateBuilder.swift` 收口共享 history item 组装能力

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数: mainToolbarState(session:saveState:placement:isImportEnabled:showsBackground:)
// 说明: 修改前主工具条只会组装 crop/save/text/import 四个主操作项，undo/redo 虽然已有命令定义，但不会出现在共享 toolbar state 里。
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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数: historyItemStates(session:) / undoItemState(session:) / redoItemState(session:)
// 说明: 修改前共享 builder 内没有专门组装 history item 的入口，所以平台层无法通过统一状态模型拿到 undo/redo。
// 无对应实现。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数: mainToolbarState(session:saveState:placement:isImportEnabled:showsBackground:includesHistoryItems:)
// 说明: 修改后新增 includesHistoryItems 开关，让共享 toolbar 在需要时把 undo/redo 作为起始分组纳入同一条 items 链。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
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
        // 在共享 builder 层统一插入 history items，避免平台侧再各自拼装。
        itemStates.append(contentsOf: historyItemStates(session: session))
    }
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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数: historyItemStates(session:) / undoItemState(session:) / redoItemState(session:)
// 说明: 修改后把 undo/redo 的图标、标题、可用性统一复用 CanvasCommandCatalog，避免平台私有启用态判断继续分叉。
func historyItemStates(session: CanvasEditorSession) -> [CanvasToolbarItemState] {
    [
        undoItemState(session: session),
        redoItemState(session: session)
    ]
}

func undoItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
    let descriptor = commandCatalog.descriptor(
        for: .undo,
        session: session
    )
    return CanvasToolbarItemState(
        id: .undo,
        systemImageName: descriptor.systemImageName,
        isEnabled: descriptor.isEnabled,
        accessibilityLabel: descriptor.title,
        visualRole: .accent
    )
}

func redoItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
    let descriptor = commandCatalog.descriptor(
        for: .redo,
        session: session
    )
    return CanvasToolbarItemState(
        id: .redo,
        systemImageName: descriptor.systemImageName,
        isEnabled: descriptor.isEnabled,
        accessibilityLabel: descriptor.title,
        visualRole: .accent
    )
}
```

### 这一处修改的实际效果

- 共享 toolbar state 终于能按开关产出 `undo/redo`。
- reading mode 语义保持不变，仍然直接返回空 `items`。
- 这一步只是“共享能力补齐”，不会自动影响 `iOS`，因为 `iOS` 这次还没有开启 `includesHistoryItems`。

## 修改二：`macOSViewController.swift` 把 `undo/redo` 正式注册进 toolbar

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: toolbarButtonsByID / viewDidLoad()
// 说明: 修改前 macOS toolbar 只注册 crop/save/text/import，undo/redo 只能走菜单和快捷键，不能出现在工具条中。
private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
    [
        .crop: cropButton,
        .save: saveButton,
        .text: textButton,
        .importMedia: importButton
    ]
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    updatePreparedToolbarPlacement()
    setupTextEditorOverlay()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupTextButton()
    setupBackButton()
    setupWorkspaceModeButton()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: setupUndoButton() / setupRedoButton() / handleUndoButtonClick() / handleRedoButtonClick()
// 说明: 修改前 macOS 控制器中没有 toolbar 级别的 undo/redo 按钮初始化与点击处理函数。
// 无对应实现。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: toolbarButtonsByID / viewDidLoad()
// 说明: 修改后新增 undo/redo 按钮实例，并在 controller 初始化阶段把它们一起接入 toolbar 注册链。
private let undoButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private let redoButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .save: saveButton,
        .text: textButton,
        .importMedia: importButton
    ]
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    updatePreparedToolbarPlacement()
    setupTextEditorOverlay()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupTextButton()
    setupUndoButton()
    setupRedoButton()
    setupBackButton()
    setupWorkspaceModeButton()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: setupUndoButton() / setupRedoButton() / handleUndoButtonClick() / handleRedoButtonClick()
// 说明: 修改后 toolbar 按钮的 target/action 明确落到 controller，并继续复用现有 performCommand(.undo/.redo) 命令执行链。
private func setupUndoButton() {
    undoButton.target = self
    undoButton.action = #selector(handleUndoButtonClick)
    updateInlineEditButtonsAppearance()
}

private func setupRedoButton() {
    redoButton.target = self
    redoButton.action = #selector(handleRedoButtonClick)
    updateInlineEditButtonsAppearance()
}

@objc
private func handleUndoButtonClick() {
    performCommand(.undo)
}

@objc
private func handleRedoButtonClick() {
    performCommand(.redo)
}
```

### 这一处修改的实际效果

- `macOS toolbar` 终于拥有和共享 state 对应的 `undo/redo` 宿主按钮。
- 菜单、快捷键、toolbar 三条入口仍然共用同一条 `performCommand` 命令链，没有新增平台私有执行分支。
- 这一步只接入 `macOS`，`iOS` 的独立 history UI 尚未拆除。

## 修改三：`macOSViewController.swift` 补齐 history 按钮状态刷新链，并显式启用共享 history items

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: commitPendingPointerHistoryTransaction(autosaveReason:) / recordImmediateHistoryChange(from:reason:autosaveReason:)
// 说明: 修改前历史事务提交后不会主动刷新 toolbar，因此即使后面把 undo/redo 放进 toolbar，也会存在启用态滞后的风险。
private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard editorSession.commitPendingHistoryTransaction(
        autosaveReason: autosaveReason
    ) else {
        return
    }
}

private func recordImmediateHistoryChange(
    from beforeSnapshot: BoardHistorySnapshot,
    reason: String,
    autosaveReason: String? = nil
) {
    guard editorSession.recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: reason,
        autosaveReason: autosaveReason
    ) else {
        return
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: makeToolbarState()
// 说明: 修改前 macOS 调共享 builder 时没有开启 history item 组装，因此共享层即使后来支持 undo/redo，也不会显示到 toolbar。
private func makeToolbarState() -> CanvasToolbarState {
    toolbarStateBuilder.mainToolbarState(
        session: editorSession,
        saveState: saveButtonState,
        placement: toolbarPreferredPlacement()
    )
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: commitPendingPointerHistoryTransaction(autosaveReason:) / recordImmediateHistoryChange(from:reason:autosaveReason:)
// 说明: 修改后在历史栈真实发生变化后立刻刷新 toolbar，从而让 undo/redo 的 enable 状态跟随 historyController 实时变化。
private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard editorSession.commitPendingHistoryTransaction(
        autosaveReason: autosaveReason
    ) else {
        return
    }
    updateInlineEditButtonsAppearance()
}

private func recordImmediateHistoryChange(
    from beforeSnapshot: BoardHistorySnapshot,
    reason: String,
    autosaveReason: String? = nil
) {
    guard editorSession.recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: reason,
        autosaveReason: autosaveReason
    ) else {
        return
    }
    updateInlineEditButtonsAppearance()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: makeToolbarState()
// 说明: 修改后显式开启 includesHistoryItems，让 macOS 成为第一个消费共享 history item 组装能力的平台。
private func makeToolbarState() -> CanvasToolbarState {
    toolbarStateBuilder.mainToolbarState(
        session: editorSession,
        saveState: saveButtonState,
        placement: toolbarPreferredPlacement(),
        includesHistoryItems: true
    )
}
```

### 这一处修改的实际效果

- `macOS` 不仅能显示 `undo/redo`，还能在历史栈变化后及时更新按钮可用性。
- 共享 builder 的新能力已经被真实消费，不会停留在“只改了共享层但平台没接上”的半成品状态。

## 本次没有修改的内容

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: historyButtonsStackView / updateHistoryButtonsAppearance() / makeToolbarState()
// 说明: 这次没有改动 iOS 的独立 history stack；iOS 仍然保留现有胶囊式 history UI，后续阶段才会统一到共享 toolbar items。
// 无本次改动。
```

## 修改后的阶段性结论

这次阶段 1 的实际结果是：

1. 共享 toolbar 模型终于具备了“产出 history items”的正式能力。
2. `macOS` 已经接入这项能力，`undo/redo` 会显示在工具条里。
3. `macOS` 历史状态变化后会刷新 toolbar，避免按钮 enable 状态滞后。
4. `iOS` 仍保持现状，没有提前进入拆除独立 `historyButtonsStackView` 的阶段。

## 本次验证

```bash
# 文件路径: /usr/bin/xcodebuild
# 函数: xcodebuild -project ... -scheme ... build
# 说明: 对当前 macOS 目标做最小构建验证，确认本次阶段 1 改动没有引入编译错误。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  build
```

验证结果：本次构建已通过。
