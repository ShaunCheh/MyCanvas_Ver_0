# 20260326_094626_read_mode_phase2_mode_button_blocker_record

## 记录范围

- 记录内容：
  1. 实施“阅读模式切换”计划的 `Phase 2`，在 iOS / macOS 画板右上角新增悬浮模式按钮。
  2. 将模式按钮接入 `chrome blocker` 链，使 toolbar / minimap / context menu 的布局避让能够自动感知它。
  3. 在点击切换、加载 board、新建 board、恢复持久化状态、应用 runtime state 这些路径上刷新按钮图标，并把模式切换纳入 autosave。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - 阅读模式下隐藏工具条
  - 阅读模式下隐藏 iOS 历史按钮
  - 阅读模式下冻结选中框 / 裁剪框 / 文本编辑浮层
  - 阅读模式对命令、上下文菜单、输入入口的统一门控

## 修改一：为 `chrome blocker` 增加 `modeToggle` 语义

### 修改前

- `CanvasChromeBlockerKind` 里还没有右上角模式按钮的独立 blocker 语义。
- 如果直接把它复用成别的 blocker kind，后续排查 occlusion 时语义会混淆。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift
// 函数名/符号名: CanvasChromeBlockerKind
// 功能说明: 修改前 blocker 只覆盖返回键、历史按钮、工具条、小地图、上下文菜单，还没有模式按钮的独立语义。
enum CanvasChromeBlockerKind: String, Sendable {
    case backButton
    case historyButtons
    case toolbar
    case miniMap
    case contextMenu
}
```

### 修改后

- 新增 `modeToggle`，让右上角悬浮模式按钮可以明确进入共享占位链。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift
// 函数名/符号名: CanvasChromeBlockerKind
// 功能说明: 为右上角模式按钮增加独立 blocker kind，供 toolbar / minimap / context menu 统一避让。
enum CanvasChromeBlockerKind: String, Sendable {
    case backButton
    case modeToggle
    case historyButtons
    case toolbar
    case miniMap
    case contextMenu
}
```

### 结果

- 右上角模式按钮现在可以以明确语义进入共享布局避让链。
- 后续如果继续排查 chrome 遮挡问题，可以直接从 `modeToggle` 维度观察布局数据，而不是把它混在别的 blocker 里。

## 修改二：iOS 侧新增右上角模式按钮，并接入承载层与 blocker

### 修改前

- `iOSViewController` 只有左上角 `backButton`，没有右上角 `workspaceModeButton`。
- `viewDidLoad()` 没有模式按钮初始化。
- `setupViewHierarchy()` / `setupConstraints()` / `baseChromeBlockersForToolbarLayout()` 也都没有右上角模式按钮的挂载、约束和避让接入。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: backButton / viewDidLoad() / setupViewHierarchy() / setupConstraints() / baseChromeBlockersForToolbarLayout()
// 功能说明: 修改前 iOS 只有左上角返回键和右下角 history buttons，右上角没有模式按钮，也没有进入 chrome blocker 链。
private let backButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.filled()
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: 17,
        weight: .semibold
    )
    configuration.image = UIImage(systemName: "chevron.left")
    configuration.baseBackgroundColor = .secondarySystemBackground
    configuration.baseForegroundColor = .label
    configuration.cornerStyle = .capsule
    configuration.contentInsets = .zero
    button.configuration = configuration
    button.accessibilityLabel = "Back to board list"
    return button
}()

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
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(historyButtonsStackView)
    toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
    chromeOverlayView.addSubview(toolbarHostView)
    chromeOverlayView.addSubview(textEditorOverlayView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    installHistoryButtons()
    registerToolbarButtons()
}

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        // ... 省略与本次改动无关的约束 ...
        backButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
        backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
        backButton.widthAnchor.constraint(equalToConstant: 44),
        backButton.heightAnchor.constraint(equalToConstant: 44)
    ])
}

private func baseChromeBlockersForToolbarLayout() -> [CanvasChromeBlocker] {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(
        kind: .backButton,
        for: backButton,
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

- 新增 `workspaceModeButton`，样式与 `backButton` 对齐，默认展示 `CanvasWorkspaceMode.editing.systemImageName`。
- 在 `viewDidLoad()` 中显式调用 `setupWorkspaceModeButton()`。
- 在 `chromeOverlayView` 上把它作为与 `backButton` 同级的子视图挂到右上角。
- 在 `baseChromeBlockersForToolbarLayout()` 中将其作为 `.modeToggle` 接入避让链。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: workspaceModeButton / viewDidLoad() / setupViewHierarchy() / setupConstraints() / baseChromeBlockersForToolbarLayout()
// 功能说明: 新增 iOS 右上角模式按钮，并把它接入 overlay 承载层、safe area 对称布局和 chrome blocker 链。
private let workspaceModeButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.filled()
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: 17,
        weight: .semibold
    )
    configuration.image = UIImage(
        systemName: CanvasWorkspaceMode.editing.systemImageName
    )
    configuration.baseBackgroundColor = .secondarySystemBackground
    configuration.baseForegroundColor = .label
    configuration.cornerStyle = .capsule
    configuration.contentInsets = .zero
    button.configuration = configuration
    return button
}()

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
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
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
    NSLayoutConstraint.activate([
        // ... 省略与本次改动无关的约束 ...
        backButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
        backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
        backButton.widthAnchor.constraint(equalToConstant: 44),
        backButton.heightAnchor.constraint(equalToConstant: 44),
        workspaceModeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        workspaceModeButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
        workspaceModeButton.widthAnchor.constraint(equalToConstant: 44),
        workspaceModeButton.heightAnchor.constraint(equalToConstant: 44)
    ])
}

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

### 结果

- iOS 侧右上角现在有了与左上角返回键对称的悬浮模式按钮。
- 工具条、小地图、上下文菜单的布局计算会自动把这个按钮视为被占区域，而不是靠额外硬编码偏移规避。

## 修改三：iOS 侧增加模式切换动作与状态恢复刷新

### 修改前

- 控制器里没有 `setupWorkspaceModeButton()`、`updateWorkspaceModeButtonAppearance()`、`handleWorkspaceModeButtonTap()`。
- `restoreBoard()` / `startNewBoard()` / `restorePersistedBoardIfPossible()` / `applyBoardRuntimeState()` 只刷新内联编辑按钮，不刷新模式按钮图标。
- 控制器里也没有 `workspaceMode` 到 `editorSession.workspaceMode` 的显式透传入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: setupBackButton() / handleBackButtonTap() / restoreBoard(withID:) / startNewBoard() / restorePersistedBoardIfPossible() / applyBoardRuntimeState(_:)
// 功能说明: 修改前 iOS 没有模式按钮接线，也没有在 runtime restore 后刷新模式图标。
private func setupBackButton() {
    backButton.addTarget(self, action: #selector(handleBackButtonTap), for: .touchUpInside)
}

@objc
private func handleBackButtonTap() {
    commitActiveTextEditIfNeeded()
    dismissContextMenu()
    onBackToBoardList?()
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
}

private func startNewBoard() {
    editorSession.startNewBoard()
    updateInlineEditButtonsAppearance()
}

private func restorePersistedBoardIfPossible() {
    editorSession.restorePersistedBoardIfPossible()
    updateInlineEditButtonsAppearance()
}

private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    editorSession.applyBoardRuntimeState(runtimeState)
    updateInlineEditButtonsAppearance()
}

// 修改前控制器内没有 workspaceMode 透传属性。
```

### 修改后

- 新增 `setupWorkspaceModeButton()` 负责事件接线。
- 新增 `updateWorkspaceModeButtonAppearance()`，让按钮图标与无障碍文本始终显示当前模式，而不是目标模式。
- 新增 `handleWorkspaceModeButtonTap()`，点击后写入 `editorSession.workspaceMode`、刷新按钮、重跑 overlay 布局并触发 autosave。
- 在加载 / 新建 / 恢复 / 应用 runtime state 后都补上 `updateWorkspaceModeButtonAppearance()`，确保按钮图标跟持久化状态一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: setupWorkspaceModeButton() / updateWorkspaceModeButtonAppearance() / handleWorkspaceModeButtonTap() / restoreBoard(withID:) / startNewBoard() / restorePersistedBoardIfPossible() / applyBoardRuntimeState(_:) / workspaceMode
// 功能说明: 为 iOS 模式按钮增加点击切换、图标刷新、runtime restore 刷新，以及到 editorSession.workspaceMode 的显式透传。
private func setupWorkspaceModeButton() {
    workspaceModeButton.addTarget(
        self,
        action: #selector(handleWorkspaceModeButtonTap),
        for: .touchUpInside
    )
    updateWorkspaceModeButtonAppearance()
}

private func updateWorkspaceModeButtonAppearance() {
    var configuration = workspaceModeButton.configuration ?? UIButton.Configuration.filled()
    configuration.image = UIImage(systemName: workspaceMode.systemImageName)
    workspaceModeButton.configuration = configuration
    workspaceModeButton.accessibilityLabel = workspaceMode.accessibilityLabel
    workspaceModeButton.accessibilityValue = workspaceMode.accessibilityValue
}

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

private var workspaceMode: CanvasWorkspaceMode {
    get { editorSession.workspaceMode }
    set { editorSession.workspaceMode = newValue }
}
```

### 结果

- iOS 侧按钮显示的始终是“当前模式”的符号，而不是下一个模式。
- 切换模式后，控制器会立即重刷按钮和 overlay 布局，同时把模式变化纳入现有 autosave。
- 从已有 board 恢复时，按钮图标能和 `BoardRuntimeState.workspaceMode` 保持一致，不会出现 UI 停留在默认图标的问题。

## 修改四：macOS 侧新增右上角模式按钮，并接入承载层与 blocker

### 修改前

- `macOSViewController` 只有左上角 `backButton`，没有与之对称的右上角模式按钮。
- `viewDidLoad()` / `setupViewHierarchy()` / `setupConstraints()` / `baseChromeBlockersForToolbarLayout()` 都还没有这一层接线。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: backButton / viewDidLoad() / setupViewHierarchy() / setupConstraints() / baseChromeBlockersForToolbarLayout()
// 功能说明: 修改前 macOS 只有左上角返回键，右上角没有模式按钮，也没有 blocker 接入点。
private let backButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.title = ""
    button.toolTip = "Back to board list"
    button.wantsLayer = true
    button.layer?.cornerRadius = 22
    button.layer?.masksToBounds = true
    button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
    button.layer?.borderWidth = 1
    button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    button.contentTintColor = .labelColor
    if let image = NSImage(
        systemSymbolName: "chevron.left",
        accessibilityDescription: "Back to board list"
    ) {
        button.image = image
        button.imagePosition = .imageOnly
    } else {
        button.title = "<"
    }
    return button
}()

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
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
}

private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
    chromeOverlayView.addSubview(toolbarHostView)
    chromeOverlayView.addSubview(textEditorOverlayView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    registerToolbarButtons()
}

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        // ... 省略与本次改动无关的约束 ...
        backButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
        backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
        backButton.widthAnchor.constraint(equalToConstant: 44),
        backButton.heightAnchor.constraint(equalToConstant: 44)
    ])
}

private func baseChromeBlockersForToolbarLayout() -> [CanvasChromeBlocker] {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(
        kind: .backButton,
        for: backButton,
        to: &chromeBlockers
    )
    return chromeBlockers
}
```

### 修改后

- 新增 `workspaceModeButton`，视觉样式与 `backButton` 保持同级风格。
- 在 `viewDidLoad()` 中接入 `setupWorkspaceModeButton()`。
- 在 `chromeOverlayView` 中把它挂到右上角，并通过 `.modeToggle` 进入 blocker 链。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: workspaceModeButton / viewDidLoad() / setupViewHierarchy() / setupConstraints() / baseChromeBlockersForToolbarLayout()
// 功能说明: 新增 macOS 右上角模式按钮，并把它接入 overlay 承载层、safe area 对称布局和 chrome blocker 链。
private let workspaceModeButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.title = ""
    button.wantsLayer = true
    button.layer?.cornerRadius = 22
    button.layer?.masksToBounds = true
    button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
    button.layer?.borderWidth = 1
    button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    button.contentTintColor = .labelColor
    if let image = NSImage(
        systemSymbolName: CanvasWorkspaceMode.editing.systemImageName,
        accessibilityDescription: CanvasWorkspaceMode.editing.accessibilityValue
    ) {
        button.image = image
        button.imagePosition = .imageOnly
    }
    return button
}()

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
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
}

private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
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
    NSLayoutConstraint.activate([
        // ... 省略与本次改动无关的约束 ...
        backButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
        backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
        backButton.widthAnchor.constraint(equalToConstant: 44),
        backButton.heightAnchor.constraint(equalToConstant: 44),
        workspaceModeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        workspaceModeButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
        workspaceModeButton.widthAnchor.constraint(equalToConstant: 44),
        workspaceModeButton.heightAnchor.constraint(equalToConstant: 44)
    ])
}

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

### 结果

- macOS 侧也建立了与 iOS 对称的右上角模式按钮承载层与 blocker 接线。
- 之后无论 toolbar 还是 miniMap 再做 layout pass，都会把这个按钮视为真实占位，而不是视而不见。

## 修改五：macOS 侧增加模式切换动作与状态恢复刷新

### 修改前

- `macOSViewController` 里只有 `setupBackButton()` / `handleBackButtonClick()`。
- 没有 `setupWorkspaceModeButton()`、`updateWorkspaceModeButtonAppearance()`、`handleWorkspaceModeButtonClick()`。
- `restoreBoard()` / `startNewBoard()` / `restorePersistedBoardIfPossible()` / `applyBoardRuntimeState()` 只刷新内联编辑按钮，不会刷新模式按钮图标。
- 控制器里没有显式的 `workspaceMode` 透传属性。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: setupBackButton() / handleBackButtonClick() / restoreBoard(withID:) / startNewBoard() / restorePersistedBoardIfPossible() / applyBoardRuntimeState(_:)
// 功能说明: 修改前 macOS 没有模式按钮接线，也没有在 runtime restore 后刷新模式图标。
private func setupBackButton() {
    backButton.target = self
    backButton.action = #selector(handleBackButtonClick)
}

@objc
private func handleBackButtonClick() {
    commitActiveTextEditIfNeeded()
    dismissContextMenu()
    onBackToBoardList?()
}

private func restoreBoard(withID boardID: UUID) {
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerLoadBoard.begin " +
        "boardID=\(boardID.uuidString) " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
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
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerLoadBoard.end " +
        "boardID=\(boardID.uuidString) " +
        "cameraCenter=\(describe(point: camera.center)) " +
        "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
}

private func startNewBoard() {
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerStartNewBoard.begin " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
    editorSession.startNewBoard()
    updateInlineEditButtonsAppearance()
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerStartNewBoard.end " +
        "cameraCenter=\(describe(point: camera.center)) " +
        "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
}

private func restorePersistedBoardIfPossible() {
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerRestore.begin " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
    editorSession.restorePersistedBoardIfPossible()
    updateInlineEditButtonsAppearance()
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerRestore.end " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "cameraCenter=\(describe(point: camera.center)) " +
        "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
}

private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerApplyRuntimeState.begin " +
        "runtimeBoardID=\(runtimeState.boardID.uuidString) " +
        "runtimeCameraViewportSize=\(describe(size: runtimeState.camera.viewportSize)) " +
        "runtimeSelectedItemID=\(describe(itemID: runtimeState.interactionState.selectedItemID))"
    )
    editorSession.applyBoardRuntimeState(runtimeState)
    updateInlineEditButtonsAppearance()
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerApplyRuntimeState.end " +
        "cameraCenter=\(describe(point: camera.center)) " +
        "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
}

// 修改前控制器内没有 workspaceMode 透传属性。
```

### 修改后

- 新增模式按钮接线、图标刷新和点击处理。
- 点击切换时把结果写回 `editorSession.workspaceMode`，然后重刷按钮、重跑 overlay 布局、触发 autosave。
- 在四条 runtime restore 路径上补充 `updateWorkspaceModeButtonAppearance()`，保证按钮图标和持久化状态一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: setupWorkspaceModeButton() / updateWorkspaceModeButtonAppearance() / handleWorkspaceModeButtonClick() / restoreBoard(withID:) / startNewBoard() / restorePersistedBoardIfPossible() / applyBoardRuntimeState(_:) / workspaceMode
// 功能说明: 为 macOS 模式按钮增加点击切换、图标刷新、runtime restore 刷新，以及到 editorSession.workspaceMode 的显式透传。
private func setupWorkspaceModeButton() {
    workspaceModeButton.target = self
    workspaceModeButton.action = #selector(handleWorkspaceModeButtonClick)
    updateWorkspaceModeButtonAppearance()
}

private func updateWorkspaceModeButtonAppearance() {
    workspaceModeButton.toolTip = "\(workspaceMode.accessibilityLabel): \(workspaceMode.accessibilityValue)"
    if let image = NSImage(
        systemSymbolName: workspaceMode.systemImageName,
        accessibilityDescription: workspaceMode.accessibilityValue
    ) {
        workspaceModeButton.image = image
        workspaceModeButton.imagePosition = .imageOnly
    }
}

@objc
private func handleWorkspaceModeButtonClick() {
    workspaceMode = workspaceMode.toggled
    updateWorkspaceModeButtonAppearance()
    updatePreparedToolbarPlacement()
    scheduleAutosave(reason: "toggle workspace mode")
}

private func restoreBoard(withID boardID: UUID) {
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerLoadBoard.begin " +
        "boardID=\(boardID.uuidString) " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
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
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerLoadBoard.end " +
        "boardID=\(boardID.uuidString) " +
        "cameraCenter=\(describe(point: camera.center)) " +
        "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
}

private func startNewBoard() {
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerStartNewBoard.begin " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
    editorSession.startNewBoard()
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerStartNewBoard.end " +
        "cameraCenter=\(describe(point: camera.center)) " +
        "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
}

private func restorePersistedBoardIfPossible() {
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerRestore.begin " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
    editorSession.restorePersistedBoardIfPossible()
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerRestore.end " +
        "viewBounds=\(describe(rect: view.bounds)) " +
        "cameraCenter=\(describe(point: camera.center)) " +
        "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
}

private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerApplyRuntimeState.begin " +
        "runtimeBoardID=\(runtimeState.boardID.uuidString) " +
        "runtimeCameraViewportSize=\(describe(size: runtimeState.camera.viewportSize)) " +
        "runtimeSelectedItemID=\(describe(itemID: runtimeState.interactionState.selectedItemID))"
    )
    editorSession.applyBoardRuntimeState(runtimeState)
    updateInlineEditButtonsAppearance()
    updateWorkspaceModeButtonAppearance()
    print(
        "[Canvas macOS][RuntimeRestore] " +
        "action=controllerApplyRuntimeState.end " +
        "cameraCenter=\(describe(point: camera.center)) " +
        "zoom=\(String(format: "%.4f", Double(camera.zoomScale))) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "selectedItemID=\(describe(itemID: interactionState.selectedItemID))"
    )
}

private var workspaceMode: CanvasWorkspaceMode {
    get { editorSession.workspaceMode }
    set { editorSession.workspaceMode = newValue }
}
```

### 结果

- macOS 侧模式按钮点击后，当前模式会真正写入 `CanvasEditorSession`，而不是只改按钮表象。
- 从持久化状态恢复时，按钮图标、tooltip 和当前模式状态能够保持一致。

## 验证

- `ReadLints` 检查以下文件，未发现新的 lint 错误：
  - `MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 使用以下命令做了 macOS 侧语法检查，并通过：
  - `xcrun --sdk macosx swiftc -frontend -parse "MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift" "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"`
- iOS 侧本地环境仍缺少完整 iOS SDK，本次继续以 IDE lint 结果为主，没有额外执行完整 iOS 编译解析。
