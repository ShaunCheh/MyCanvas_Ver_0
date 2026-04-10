# 20260410_120656_toolbar_history_phase2_ios_shared_toolbar_record

## 记录说明

本记录基于当前工作区的实际 `changes`、这次对应文件的 `git diff`，以及修改后的当前代码状态整理，不包含原始 `git diff` 文本。

这次记录的是 `toolbar_history_convergence` 的阶段 2 实施结果，实际只涉及 `iOS` 一侧的收敛：

- 把 `undo/redo` 从 `iOS` 私有 `historyButtonsStackView` 正式切回共享 toolbar items。
- 移除旧的独立 history stack 视图接线、约束、blocker 注入和胶囊式外观刷新链。
- 让 `iOSViewController` 像 `macOSViewController` 一样，直接消费共享 `CanvasToolbarStateBuilder` 产出的 `undo/redo`。

当前工作区实际变更文件只有 1 个：

- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`

当前统计：`1 file changed, 10 insertions(+), 101 deletions(-)`

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
# 说明: 确认当前 changes 只包含本次阶段 2 的 iOS 收敛改动，并据此整理下面的“修改前 / 修改后”代码片段。
git status --short

git diff --stat -- \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift"

git diff -- \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift"
```

## 本次修改的真实边界

阶段 1 已经完成了共享 builder 能力和 `macOS` 接入，但 `iOS` 仍保留自己的独立 history UI。那种状态下，`undoButton/redoButton` 既是 `historyButtonsStackView` 的子按钮，又需要进入 `toolbarHostView`，会形成一组明确冲突：

1. 同一组按钮实例会在 `historyButtonsStackView` 和 `toolbarHostView` 之间争抢宿主。
2. 独立 history stack 继续占用右下角 safe area，并通过 `.historyButtons` blocker 参与避让。
3. `updateHistoryButtonsAppearance()` 仍然会把 `undo/redo` 反复改回“标题 + 胶囊”样式，与共享 toolbar host 的 icon-only 样式相互覆盖。

所以这次不是只“把 `.undo/.redo` 加进 `toolbarButtonsByID`”这么简单，而是把和旧 iOS history stack 直接耦合的宿主、布局、blocker 和外观刷新链一起拆掉。

## 修改一：`undo/redo` 从私有 history stack 注册切回共享 toolbar 注册字典

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: historyButtonsStackView / toolbarButtonsByID / historyButtons
// 说明: 修改前 undo/redo 按钮实例存在，但不在 toolbarButtonsByID 中，而是通过独立 historyButtonsStackView 单独挂载。
private let historyButtonsStackView: iOSCanvasChromeStackView = {
    let stackView = iOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
    [
        .crop: cropButton,
        .save: saveButton,
        .text: textButton,
        .importMedia: importButton
    ]
}

private var historyButtons: [UIButton] {
    [undoButton, redoButton]
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: toolbarButtonsByID
// 说明: 修改后 undo/redo 不再通过私有 history stack 单独维护，而是直接注册进共享 toolbar 的按钮字典。
private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .save: saveButton,
        .text: textButton,
        .importMedia: importButton
    ]
}
```

### 这一处修改的实际效果

- `undo/redo` 现在和 `crop/save/text/import` 一样，走同一个 `registerToolbarButtons()` / `toolbarHostView.render(...)` 宿主链路。
- `historyButtonsStackView` 与 `historyButtons` 这两个独立宿主入口被彻底移除，不再保留双轨注册。

## 修改二：拆除独立 history stack 的视图挂载与约束

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: setupViewHierarchy() / setupConstraints() / installHistoryButtons()
// 说明: 修改前 historyButtonsStackView 被挂进 chromeOverlayView，并在右下角占有一组独立约束与安装逻辑。
private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    view.addSubview(transitionInteractionShieldView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(historyButtonsStackView)
    toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
    chromeOverlayView.addSubview(toolbarHostView)
    chromeOverlayView.addSubview(textEditorOverlayView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    chromeOverlayView.addSubview(workspaceModeButton)
    installHistoryButtons()
    registerToolbarButtons()
}

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    let preferredTextEditorWidth = textEditorOverlayView.widthAnchor.constraint(equalToConstant: 320)
    preferredTextEditorWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
        // ... 其他约束省略 ...
        textEditorOverlayView.heightAnchor.constraint(equalToConstant: 148),
        historyButtonsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        historyButtonsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
        undoButton.heightAnchor.constraint(equalToConstant: 40),
        redoButton.heightAnchor.constraint(equalToConstant: 40)
    ])
}

private func installHistoryButtons() {
    historyButtons.forEach { button in
        historyButtonsStackView.addArrangedSubview(button)
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: setupViewHierarchy() / setupConstraints() / registerToolbarButtons()
// 说明: 修改后独立 history stack 的视图挂载、安装逻辑和 40pt 高度约束全部删除，只保留共享 toolbar 的注册入口。
private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    view.addSubview(transitionInteractionShieldView)
    chromeOverlayView.addSubview(miniMapMountView)
    toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
    chromeOverlayView.addSubview(toolbarHostView)
    chromeOverlayView.addSubview(textEditorOverlayView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    chromeOverlayView.addSubview(workspaceModeButton)
    registerToolbarButtons()
}

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    let preferredTextEditorWidth = textEditorOverlayView.widthAnchor.constraint(equalToConstant: 320)
    preferredTextEditorWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
        // ... 其他约束省略 ...
        textEditorOverlayView.heightAnchor.constraint(equalToConstant: 148)
    ])
}

private func registerToolbarButtons() {
    toolbarHostView.registerButtons(toolbarButtonsByID)
}
```

### 这一处修改的实际效果

- `undo/redo` 不再单独固定在右下角，而是和主 toolbar 一起由 placement solver 管理。
- 旧的 `40pt` 高度约束不再覆盖共享 toolbar host 的方形按钮尺寸策略。

## 修改三：从 iOS toolbar 布局避让链中移除 `.historyButtons` blocker

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: baseChromeBlockersForToolbarLayout()
// 说明: 修改前 historyButtonsStackView 仍作为独立 blocker 参与 toolbar、minimap、context menu 的占位避让。
private func baseChromeBlockersForToolbarLayout() -> [CanvasChromeBlocker] {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(
        kind: .backButton,
        for: backButton,
        to: &chromeBlockers
    )
    appendChromeBlocker(
        kind: .modeToggle,
        for: workspaceModeButton,
        to: &chromeBlockers
    )
    appendChromeBlocker(
        kind: .historyButtons,
        for: historyButtonsStackView,
        to: &chromeBlockers
    )
    return chromeBlockers
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: baseChromeBlockersForToolbarLayout()
// 说明: 修改后只保留 backButton 和 modeToggle 作为基础 blocker，history rect 不再以私有独立占位体的形式存在。
private func baseChromeBlockersForToolbarLayout() -> [CanvasChromeBlocker] {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(
        kind: .backButton,
        for: backButton,
        to: &chromeBlockers
    )
    appendChromeBlocker(
        kind: .modeToggle,
        for: workspaceModeButton,
        to: &chromeBlockers
    )
    return chromeBlockers
}
```

### 这一处修改的实际效果

- `undo/redo` 合并进 toolbar 后，iOS 不再同时维护“toolbar rect + history rect”两套占位几何。
- minimap 和其他 overlay 的避让来源被收敛为单一 toolbar 宿主。

## 修改四：把刷新链从私有 history 外观函数收回共享 toolbar render 路径

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: setupUndoButton() / setupRedoButton() / applyWorkspaceModeForToolbarTransition(to:)
// 说明: 修改前 undo/redo 相关入口在按钮初始化和 workspace mode 切换时都会主动触发私有 history 外观刷新。
private func setupUndoButton() {
    undoButton.addTarget(self, action: #selector(handleUndoButtonTap), for: .touchUpInside)
    updateHistoryButtonsAppearance()
}

private func setupRedoButton() {
    redoButton.addTarget(self, action: #selector(handleRedoButtonTap), for: .touchUpInside)
    updateHistoryButtonsAppearance()
}

private func applyWorkspaceModeForToolbarTransition(
    to targetMode: CanvasWorkspaceMode
) {
    workspaceMode = targetMode
    updateWorkspaceModeButtonAppearance()
    updateHistoryButtonsAppearance()
    syncTextEditorPresentation()
    requestCanvasRefresh(reason: "toggle workspace mode")
    scheduleAutosave(
        reason: "toggle workspace mode",
        updateKind: .viewStateOnly
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: commitPendingPointerHistoryTransaction(autosaveReason:) / recordImmediateHistoryChange(from:reason:autosaveReason:)
// 说明: 修改前历史事务提交后只刷新私有 history 外观，而不是统一回共享 toolbar 的 render/updatePreparedToolbarPlacement 链。
private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard editorSession.commitPendingHistoryTransaction(
        autosaveReason: autosaveReason
    ) else {
        return
    }
    updateHistoryButtonsAppearance()
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
    updateHistoryButtonsAppearance()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: updateInlineEditButtonsAppearance() / updateHistoryButtonsAppearance() / updateUndoButtonAppearance() / updateRedoButtonAppearance()
// 说明: 修改前 updateInlineEditButtonsAppearance() 会先进入独立 history 外观链，再触发共享 toolbar 布局；undo/redo 的标题、颜色和胶囊样式也全部由 controller 私有函数手工覆盖。
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

private func updateUndoButtonAppearance() {
    let descriptor = commandDescriptor(for: .undo)
    applyUndoButtonAppearance(
        title: descriptor.title,
        systemImageName: descriptor.systemImageName,
        backgroundColor: .systemBlue,
        isEnabled: descriptor.isEnabled
    )
}

private func updateRedoButtonAppearance() {
    let descriptor = commandDescriptor(for: .redo)
    applyRedoButtonAppearance(
        title: descriptor.title,
        systemImageName: descriptor.systemImageName,
        backgroundColor: .systemIndigo,
        isEnabled: descriptor.isEnabled
    )
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: setupUndoButton() / setupRedoButton() / applyWorkspaceModeForToolbarTransition(to:)
// 说明: 修改后所有 undo/redo 相关入口统一回 updateInlineEditButtonsAppearance()，让共享 toolbar host 负责最终外观与可用状态渲染。
private func setupUndoButton() {
    undoButton.addTarget(self, action: #selector(handleUndoButtonTap), for: .touchUpInside)
    updateInlineEditButtonsAppearance()
}

private func setupRedoButton() {
    redoButton.addTarget(self, action: #selector(handleRedoButtonTap), for: .touchUpInside)
    updateInlineEditButtonsAppearance()
}

private func applyWorkspaceModeForToolbarTransition(
    to targetMode: CanvasWorkspaceMode
) {
    workspaceMode = targetMode
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    syncTextEditorPresentation()
    requestCanvasRefresh(reason: "toggle workspace mode")
    scheduleAutosave(
        reason: "toggle workspace mode",
        updateKind: .viewStateOnly
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: commitPendingPointerHistoryTransaction(autosaveReason:) / recordImmediateHistoryChange(from:reason:autosaveReason:)
// 说明: 修改后历史栈变化也统一走 updateInlineEditButtonsAppearance()，从而触发共享 toolbar state -> host render 这条正式链路。
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
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: updateInlineEditButtonsAppearance()
// 说明: 修改后 controller 不再单独维护 historyButtonsStackView、标题胶囊样式与颜色；undo/redo 外观完全交给共享 toolbar host 的 applyAppearance(...) 处理。
private func updateInlineEditButtonsAppearance() {
    updatePreparedToolbarPlacement()
    syncTextEditorPresentation()
}
```

### 这一处修改的实际效果

- `iOSViewController` 不再维护一套私有 `undo/redo` 外观函数。
- `undo/redo` 的图标、启用态、显隐状态现在完全由共享 `CanvasToolbarState` 和 `iOSCanvasToolbarHostView` 控制。
- workspace mode 切换、历史事务提交、按钮初始化后的刷新入口都被统一收敛。

## 修改五：让 iOS 真正消费共享 `CanvasToolbarStateBuilder` 产出的 history items

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: makeToolbarState()
// 说明: 修改前 iOS 调共享 builder 时没有开启 includesHistoryItems，因此即使共享层已经具备 history item 组装能力，iOS 也不会显示 undo/redo。
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
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: makeToolbarState()
// 说明: 修改后 iOS 显式开启 includesHistoryItems，让 undo/redo 正式进入共享 toolbar items 结果。
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

- `iOS` 和 `macOS` 现在都通过同一套 shared builder 产出 `undo/redo`。
- 阶段 2 到这里才算真正完成了“两端统一走同一套 toolbar item 组合”的目标。

## 本次没有修改的内容

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数: applyAppearance(_:to:) / symbolConfiguration(for:)
// 说明: 这次没有改 toolbar host 本身；iOS 之所以能切成 icon-only 方形按钮，是因为 host 现有的共享渲染能力已经足够承接 undo/redo。
// 无本次改动。
```

## 修改后的阶段性结论

这次阶段 2 的实际结果是：

1. `iOS` 不再保留独立 `historyButtonsStackView`。
2. `undo/redo` 在 `iOS` 也正式并入共享 toolbar items。
3. 旧的 right-bottom history blocker 和胶囊式按钮外观刷新链已经删除。
4. `iOS` 与 `macOS` 现在都通过 `CanvasToolbarStateBuilder -> CanvasToolbarState -> ToolbarHostView` 这同一条主链渲染 history buttons。

## 本次验证

```bash
# 文件路径: /usr/bin/xcodebuild
# 函数: xcodebuild -project ... -scheme ... build
# 说明: 对 macOS 与 iOS Simulator 两个目标做最小构建验证，确认本次阶段 2 改动没有引入编译错误。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS Simulator" \
  build
```

验证结果：

- `macOS build` 通过。
- `iOS Simulator build` 通过。
