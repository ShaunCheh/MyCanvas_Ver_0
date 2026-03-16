# 20260316_220634_phase_bplus_stage6_command_wiring_validation_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 增加显式 `Undo / Redo` 按钮、history 执行入口与按钮状态刷新。
  2. 在 `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`、`MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift`、`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 接入 `Edit > Undo / Redo` 菜单、快捷键和共享命令链。
  3. 回归验证 `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift` 与 `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift` 的保存恢复、旧文档默认值回退与双平台构建状态。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 仅验证、未改动源码的文件：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
- 本记录不包含：
  - 阶段五的 crop / rotate 交互实现细节
  - 原始 gif diff
  - git commit / push
  - 手动交互录屏
  - 临时 smoke harness 源码（验证后已删除）

## 修改一：iOS 增加显式 Undo / Redo 按钮与 history 状态联动

### 修改前

- iOS 右侧悬浮工具列只有 `Rotate / Crop / Save / Import`，没有文档级 `Undo / Redo` 可见入口。
- `iOSViewController` 虽然已经持有 `BoardHistoryController`，但只会在内部提交 transaction 或记录 change，本身没有 `canUndo / canRedo / performUndo / performRedo` 封装，也没有额外按钮状态刷新。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: cropButton / rotateButton / viewDidLoad / setupViewHierarchy / setupConstraints / setupCropButton / setupRotateButton
// 功能说明: 修改前 iOS 只暴露 Crop / Rotate / Save / Import 四个入口，history 虽然已经落在 controller 内，但 UI 上没有 Undo / Redo。
private let cropButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()
private let rotateButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupRotateButton()
    restorePersistedBoardIfPossible()
    setupCanvasViewport()
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(rotateButton)
    view.addSubview(cropButton)
    view.addSubview(saveButton)
    view.addSubview(importButton)
}

private func setupConstraints() {
    let safeAreaLayoutGuide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        // ... 省略未改动代码 ...
        rotateButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        rotateButton.bottomAnchor.constraint(equalTo: cropButton.topAnchor, constant: -12),
        cropButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        cropButton.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),
        saveButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        saveButton.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -12),
        importButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        importButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
        rotateButton.heightAnchor.constraint(equalToConstant: 40),
        cropButton.heightAnchor.constraint(equalToConstant: 40),
        saveButton.heightAnchor.constraint(equalToConstant: 40),
        importButton.heightAnchor.constraint(equalToConstant: 56)
    ])
}

private func setupCropButton() {
    cropButton.addTarget(self, action: #selector(handleCropButtonTap), for: .touchUpInside)
    updateInlineEditButtonsAppearance()
}

private func setupRotateButton() {
    rotateButton.addTarget(self, action: #selector(handleRotateButtonTap), for: .touchUpInside)
    updateInlineEditButtonsAppearance()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: applyBoardHistorySnapshot(_:) / commitPendingPointerHistoryTransaction(...) / recordImmediateHistoryChange(...) / updateInlineEditButtonsAppearance()
// 功能说明: 修改前 controller 只会“应用 snapshot”和“写入 history”，但没有独立的 Undo / Redo 命令封装，也不会刷新 history 按钮状态。
private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
    }

    requestCanvasRefresh(reason: "apply history snapshot")
}

private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard historyController.commitPendingTransaction(to: currentBoardHistorySnapshot()) else {
        return
    }

    scheduleAutosave(reason: autosaveReason)
}

private func recordImmediateHistoryChange(
    from beforeSnapshot: BoardHistorySnapshot,
    reason: String,
    autosaveReason: String? = nil
) {
    guard historyController.recordChange(
        from: beforeSnapshot,
        to: currentBoardHistorySnapshot(),
        reason: reason
    ) else {
        return
    }

    if let autosaveReason {
        scheduleAutosave(reason: autosaveReason)
    }
}

private func updateInlineEditButtonsAppearance() {
    updateCropButtonAppearance()
    updateRotateButtonAppearance()
}
```

### 修改后

- 新增 `undoButton` / `redoButton`，并将它们插入到 `Crop` 与 `Save` 之间，和现有悬浮按钮处于同一层级。
- 新增 `handleUndoButtonTap()` / `handleRedoButtonTap()`、`isHistoryCommandAvailable`、`canUndoCommand`、`canRedoCommand`、`performUndoCommand()`、`performRedoCommand()`。
- 在 `commitPendingPointerHistoryTransaction(...)`、`recordImmediateHistoryChange(...)`、`performUndoCommand()`、`performRedoCommand()` 后统一刷新按钮状态。
- `updateInlineEditButtonsAppearance()` 现在同时负责 history 按钮状态，所以进入 inline crop / rotate 草稿态时，`Undo / Redo` 会被禁用，避免未提交草稿和 document-level history 交叉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: undoButton / redoButton / viewDidLoad / setupViewHierarchy / setupConstraints / setupUndoButton / setupRedoButton
// 功能说明: 修改后 iOS controller 在原有右侧工具列中补入显式 Undo / Redo 入口，并和现有按钮共用同一套悬浮布局层级。
private let cropButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()
private let undoButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()
private let redoButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()
private let rotateButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupUndoButton()
    setupRedoButton()
    setupRotateButton()
    restorePersistedBoardIfPossible()
    setupCanvasViewport()
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(rotateButton)
    view.addSubview(cropButton)
    view.addSubview(undoButton)
    view.addSubview(redoButton)
    view.addSubview(saveButton)
    view.addSubview(importButton)
}

private func setupConstraints() {
    let safeAreaLayoutGuide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        // ... 省略未改动代码 ...
        rotateButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        rotateButton.bottomAnchor.constraint(equalTo: cropButton.topAnchor, constant: -12),
        cropButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        cropButton.bottomAnchor.constraint(equalTo: undoButton.topAnchor, constant: -12),
        undoButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        undoButton.bottomAnchor.constraint(equalTo: redoButton.topAnchor, constant: -12),
        redoButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        redoButton.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),
        saveButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        saveButton.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -12),
        importButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        importButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
        rotateButton.heightAnchor.constraint(equalToConstant: 40),
        cropButton.heightAnchor.constraint(equalToConstant: 40),
        undoButton.heightAnchor.constraint(equalToConstant: 40),
        redoButton.heightAnchor.constraint(equalToConstant: 40),
        saveButton.heightAnchor.constraint(equalToConstant: 40),
        importButton.heightAnchor.constraint(equalToConstant: 56)
    ])
}

private func setupUndoButton() {
    undoButton.addTarget(self, action: #selector(handleUndoButtonTap), for: .touchUpInside)
    updateHistoryButtonsAppearance()
}

private func setupRedoButton() {
    redoButton.addTarget(self, action: #selector(handleRedoButtonTap), for: .touchUpInside)
    updateHistoryButtonsAppearance()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleUndoButtonTap / handleRedoButtonTap / isHistoryCommandAvailable / canUndoCommand / canRedoCommand / performUndoCommand / performRedoCommand
// 功能说明: 修改后 controller 对外形成完整的 document-level undo / redo 命令入口，并在执行后统一 apply snapshot + autosave。
@objc
private func handleUndoButtonTap() {
    performUndoCommand()
}

@objc
private func handleRedoButtonTap() {
    performRedoCommand()
}

private var isHistoryCommandAvailable: Bool {
    inlineEditState == nil
}

private var canUndoCommand: Bool {
    isHistoryCommandAvailable && historyController.canUndo
}

private var canRedoCommand: Bool {
    isHistoryCommandAvailable && historyController.canRedo
}

private func performUndoCommand() {
    guard
        canUndoCommand,
        let snapshot = historyController.undo()
    else {
        return
    }

    applyBoardHistorySnapshot(snapshot)
    scheduleAutosave(reason: "undo change")
    updateHistoryButtonsAppearance()
}

private func performRedoCommand() {
    guard
        canRedoCommand,
        let snapshot = historyController.redo()
    else {
        return
    }

    applyBoardHistorySnapshot(snapshot)
    scheduleAutosave(reason: "redo change")
    updateHistoryButtonsAppearance()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: commitPendingPointerHistoryTransaction(...) / recordImmediateHistoryChange(...) / updateInlineEditButtonsAppearance() / updateHistoryButtonsAppearance() / applyUndoButtonAppearance(...) / applyRedoButtonAppearance(...)
// 功能说明: 修改后所有 history 写入点和 inline edit 状态刷新都会同步更新 Undo / Redo 的可用性与外观。
private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard historyController.commitPendingTransaction(to: currentBoardHistorySnapshot()) else {
        return
    }

    scheduleAutosave(reason: autosaveReason)
    updateHistoryButtonsAppearance()
}

private func recordImmediateHistoryChange(
    from beforeSnapshot: BoardHistorySnapshot,
    reason: String,
    autosaveReason: String? = nil
) {
    guard historyController.recordChange(
        from: beforeSnapshot,
        to: currentBoardHistorySnapshot(),
        reason: reason
    ) else {
        return
    }

    if let autosaveReason {
        scheduleAutosave(reason: autosaveReason)
    }

    updateHistoryButtonsAppearance()
}

private func updateInlineEditButtonsAppearance() {
    updateCropButtonAppearance()
    updateRotateButtonAppearance()
    updateHistoryButtonsAppearance()
}

private func updateHistoryButtonsAppearance() {
    updateUndoButtonAppearance()
    updateRedoButtonAppearance()
}

private func updateUndoButtonAppearance() {
    applyUndoButtonAppearance(
        title: "Undo",
        systemImageName: "arrow.uturn.backward",
        backgroundColor: .systemBlue,
        isEnabled: canUndoCommand
    )
}

private func updateRedoButtonAppearance() {
    applyRedoButtonAppearance(
        title: "Redo",
        systemImageName: "arrow.uturn.forward",
        backgroundColor: .systemIndigo,
        isEnabled: canRedoCommand
    )
}

private func applyUndoButtonAppearance(
    title: String,
    systemImageName: String,
    backgroundColor: UIColor,
    isEnabled: Bool
) {
    undoButton.isEnabled = isEnabled
    var configuration = undoButton.configuration ?? UIButton.Configuration.filled()
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    configuration.imagePlacement = .leading
    configuration.imagePadding = 6
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = .white
    configuration.title = title
    configuration.image = UIImage(systemName: systemImageName)
    configuration.baseBackgroundColor = isEnabled ? backgroundColor : .systemGray3
    undoButton.configuration = configuration
}

private func applyRedoButtonAppearance(
    title: String,
    systemImageName: String,
    backgroundColor: UIColor,
    isEnabled: Bool
) {
    redoButton.isEnabled = isEnabled
    var configuration = redoButton.configuration ?? UIButton.Configuration.filled()
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    configuration.imagePlacement = .leading
    configuration.imagePadding = 6
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = .white
    configuration.title = title
    configuration.image = UIImage(systemName: systemImageName)
    configuration.baseBackgroundColor = isEnabled ? backgroundColor : .systemGray3
    redoButton.configuration = configuration
}
```

## 修改二：macOS 通过 root / delegate / controller 打通菜单与快捷键 Undo / Redo 链路

### 修改前

- `macOSAppRootViewController` 只持有私有的 `currentViewController`，外部拿不到当前 canvas controller。
- `macOSAppDelegate` 只负责建窗，没有 `Edit` 菜单，也没有 `Cmd+Z` / `Shift+Cmd+Z` 转发逻辑。
- `macOSViewController` 只有 `applyBoardHistorySnapshot(_:)`，没有暴露给外部菜单调用的统一 undo / redo 执行入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: macOSAppRootViewController.currentViewController
// 功能说明: 修改前 root 只知道“当前子控制器是谁”，但没有对外暴露“当前是不是 canvas controller”。
final class macOSAppRootViewController: NSViewController {
    private let launchCoordinator: AppLaunchCoordinator
    private var currentViewController: NSViewController?

    init(launchCoordinator: AppLaunchCoordinator = AppLaunchCoordinator()) {
        self.launchCoordinator = launchCoordinator
        super.init(nibName: nil, bundle: nil)
    }

    // ... 省略未改动代码 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数名: applicationDidFinishLaunching(_:)
// 功能说明: 修改前 AppDelegate 只负责初始化窗口，尚未接入 Edit 菜单、快捷键和命令校验。
@main
final class macOSAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private static let sharedDelegate = macOSAppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = sharedDelegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FolderBookmarkStore.logStoredBookmarkPresence()
        let viewController = macOSAppRootViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // ... 省略窗口配置代码 ...
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: applyBoardHistorySnapshot(_:) / commitPendingPointerHistoryTransaction(...)
// 功能说明: 修改前 macOS controller 能“应用历史快照”，但外层菜单没有统一的 canUndo / canRedo / performUndo / performRedo 可调用入口。
private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
    }

    refreshCanvas()
}

private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard historyController.commitPendingTransaction(to: currentBoardHistorySnapshot()) else {
        return
    }

    scheduleAutosave(reason: autosaveReason)
}
```

### 修改后

- `macOSAppRootViewController` 新增 `currentCanvasViewController`，把“当前子页面是否为 canvas”从 root 层显式暴露出来。
- `macOSAppDelegate` 现在实现 `NSMenuItemValidation`，并在启动时构建主菜单；`Undo` 对应 `Cmd+Z`，`Redo` 对应 `Shift+Cmd+Z`。
- `macOSViewController` 新增 `canUndoCommand`、`canRedoCommand`、`performUndoCommand()`、`performRedoCommand()`，供 AppDelegate 菜单动作直接调用。
- macOS 没有新增浮动按钮，而是按阶段六计划优先走菜单 / 快捷键路径；菜单启用状态通过 `validateMenuItem(_:)` 动态读取 controller 当前状态，因此无需额外按钮刷新逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: currentCanvasViewController
// 功能说明: 修改后 root 可以安全把“当前 canvas controller”暴露给 AppDelegate，用于菜单命令转发。
final class macOSAppRootViewController: NSViewController {
    private let launchCoordinator: AppLaunchCoordinator
    private var currentViewController: NSViewController?

    var currentCanvasViewController: macOSViewController? {
        currentViewController as? macOSViewController
    }

    init(launchCoordinator: AppLaunchCoordinator = AppLaunchCoordinator()) {
        self.launchCoordinator = launchCoordinator
        super.init(nibName: nil, bundle: nil)
    }

    // ... 省略未改动代码 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数名: applicationDidFinishLaunching(_:) / handleUndoMenuItem(_:) / handleRedoMenuItem(_:) / validateMenuItem(_:) / makeMainMenu() / makeEditMenuItem()
// 功能说明: 修改后 AppDelegate 负责创建 Edit 菜单、绑定快捷键，并通过 root -> canvas controller 的链路转发 Undo / Redo。
@main
final class macOSAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var window: NSWindow?
    private var rootViewController: macOSAppRootViewController?
    private static let sharedDelegate = macOSAppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = sharedDelegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FolderBookmarkStore.logStoredBookmarkPresence()
        let viewController = macOSAppRootViewController()
        rootViewController = viewController
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // ... 省略窗口配置代码 ...
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        NSApp.mainMenu = makeMainMenu()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    @objc
    private func handleUndoMenuItem(_ sender: Any?) {
        rootViewController?.currentCanvasViewController?.performUndoCommand()
    }

    @objc
    private func handleRedoMenuItem(_ sender: Any?) {
        rootViewController?.currentCanvasViewController?.performRedoCommand()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(handleUndoMenuItem(_:)):
            return rootViewController?.currentCanvasViewController?.canUndoCommand ?? false
        case #selector(handleRedoMenuItem(_:)):
            return rootViewController?.currentCanvasViewController?.canRedoCommand ?? false
        default:
            return true
        }
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeApplicationMenuItem())
        mainMenu.addItem(makeEditMenuItem())
        return mainMenu
    }

    private func makeEditMenuItem() -> NSMenuItem {
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(
            title: "Undo",
            action: #selector(handleUndoMenuItem(_:)),
            keyEquivalent: "z"
        )
        undoItem.target = self
        undoItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(
            title: "Redo",
            action: #selector(handleRedoMenuItem(_:)),
            keyEquivalent: "Z"
        )
        redoItem.target = self
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)

        editMenuItem.submenu = editMenu
        return editMenuItem
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: canUndoCommand / canRedoCommand / performUndoCommand() / performRedoCommand()
// 功能说明: 修改后 macOS controller 对外暴露统一 history 命令入口，菜单只负责调用，不直接操作 scene 或 history internals。
private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
    }

    refreshCanvas()
}

var canUndoCommand: Bool {
    inlineEditState == nil && historyController.canUndo
}

var canRedoCommand: Bool {
    inlineEditState == nil && historyController.canRedo
}

func performUndoCommand() {
    guard
        canUndoCommand,
        let snapshot = historyController.undo()
    else {
        return
    }

    applyBoardHistorySnapshot(snapshot)
    scheduleAutosave(reason: "undo change")
}

func performRedoCommand() {
    guard
        canRedoCommand,
        let snapshot = historyController.redo()
    else {
        return
    }

    applyBoardHistorySnapshot(snapshot)
    scheduleAutosave(reason: "redo change")
}
```

## 修改三：保存恢复与旧文档兼容验证

### 修改前

- 阶段六计划里仍明确要求补做两类验证：
  - 平台命令入口是否真正打通。
  - `BoardStore` / `BoardDocumentMapper` 是否还能在保存后重开恢复裁切、旋转和选中状态，并让旧文档缺失新字段时按默认值打开。

### 修改后

- 使用显式 `xcodebuild` 路径分别验证 iOS Simulator Debug 与 macOS Debug。
- 使用临时 `BoardStore` smoke test 验证：
  - round-trip 保存 / 重开会保留 `cropRectNormalized`、`rotationRadians` 与 `selectedItemID`；
  - 旧文档把 `cropRectNormalized` / `rotationRadians` 留空时，会分别回退到 `.fullImage` 与 `0`。
- 临时 smoke harness 只用于验证，已在执行后删除，不属于项目最终源码改动。

```bash
# 功能说明: 阶段六的双平台构建验证命令。
# iOS / macOS 都使用显式 xcodebuild 路径；为绕过当前环境中的 codesign 问题，构建时关闭了 code signing。
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ".build_stage6_ios" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath ".build_stage6_macos" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

```text
# 功能说明: 阶段六的 BoardStore smoke test 关键输出。
[stage6-smoke] saving bookmark
[stage6-smoke] saving board
[stage6-smoke] loading saved board
[stage6-smoke] writing legacy board
[stage6-smoke] loading legacy board
Stage 6 smoke test passed: BoardStore round-trip preserved crop/rotation/selection and legacy defaults loaded correctly.
```

- 验证结果：
  - `ReadLints` 对本次修改的四个源码文件无报错。
  - iOS Simulator Debug build 通过。
  - macOS Debug build 首次常规执行仍在 `CodeSign` 阶段报出 `resource fork, Finder information, or similar detritus not allowed`；关闭 code signing 后重新构建通过，说明源码层面编译与链接正常。
  - `BoardStore` smoke test 在非沙箱执行环境下通过；其首次在 shell 沙箱里的 `NSCocoaErrorDomain Code=256` 失败，来自 bookmark / `NSFileCoordinator` 与沙箱访问限制的组合，而不是 `BoardStore` / `BoardDocumentMapper` 的业务逻辑错误。
  - 手动交互回归尚未执行，因此“菜单快捷键触发手感”和“iOS 按钮点击路径”仍以源码路径与构建验证为主。

## 结论

- 阶段六已经把“文档级 history 能力”真正接到了两个平台的用户可见入口上：
  - iOS 走显式悬浮按钮。
  - macOS 走 `Edit` 菜单与标准快捷键。
- `BoardStore` / `BoardDocumentMapper` 的 round-trip 与旧文档默认值回退在本轮 smoke test 中通过，说明阶段一到阶段五引入的裁切、旋转、选中态字段，在阶段六完成命令接线后仍能正确持久化与恢复。
