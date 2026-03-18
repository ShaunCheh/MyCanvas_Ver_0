# 20260318_120117_context_menu_phase2_command_layer_record

## 记录范围

- 记录内容：
  1. 新增共享命令模型 `CanvasCommand`，统一表达 `crop / undo / redo / select / clearSelection`。
  2. 新增 `CanvasCommandCatalog`，统一产出命令标题、图标、启用态、激活态。
  3. 新增 `CanvasCommandExecutor`，统一执行命令并返回刷新原因。
  4. 扩展 `CanvasEditorSession`，把 selection/crop 的可执行条件与历史写入逻辑下沉到共享编辑会话。
  5. 让 `iOS/macOS ViewController` 的按钮入口、选择逻辑、按钮显隐状态都通过 command layer 驱动。
  6. 让 `macOSAppDelegate` 的主菜单触发与校验也通过 command layer 驱动。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift`
- 本记录不包含：
  - `CanvasContextMenuContext`
  - `CanvasContextResolver`
  - `CanvasContextMenuState`
  - `CanvasContextMenuHostView`
  - `macOS` 右键菜单接入
  - `iOS` 长按菜单接入
  - 原始 gif diff

## 修改一：新增共享命令模型 `CanvasCommand`

### 修改前

- 项目里没有共享命令模型。
- `crop / undo / redo / select / clearSelection` 的语义分散在平台 controller 的私有方法里，无法被后续的 context menu 直接复用。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名/类型名: 文件原先不存在
// 功能说明: 修改前没有共享命令模型，平台层只能直接调用各自的私有函数。
// before: file did not exist
```

### 修改后

- 新增 `CanvasCommandID` 作为稳定的命令标识。
- 新增 `CanvasCommand` 作为可执行命令载体，支持参数化的选择命令。
- 新增 `CanvasCommandDescriptor` 与 `CanvasCommandExecutionResult`，为按钮、菜单和后续上下文菜单提供统一输入输出。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名/类型名: CanvasCommandID / CanvasCommand / CanvasCommandDescriptor / CanvasCommandExecutionResult
// 功能说明: 修改后新增共享命令模型，统一描述命令标识、参数、UI 状态和执行结果。
import Foundation

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

    var id: CanvasCommandID {
        switch self {
        case .crop:
            return .crop
        case .undo:
            return .undo
        case .redo:
            return .redo
        case .selectItem:
            return .selectItem
        case .clearSelection:
            return .clearSelection
        }
    }

    // 命令执行可能会让旋转预览/旋转交互态失效，因此先声明统一的旋转取消要求。
    var shouldCancelActiveRotation: Bool {
        switch self {
        case .crop, .undo, .redo, .selectItem, .clearSelection:
            return true
        }
    }

    var shouldResetPointerDragStateWhenCancellingRotation: Bool {
        shouldCancelActiveRotation
    }
}

struct CanvasCommandDescriptor {
    let id: CanvasCommandID
    let title: String
    let systemImageName: String
    let isEnabled: Bool
    let isActive: Bool
}

struct CanvasCommandExecutionResult {
    let refreshReason: String?
}
```

## 修改二：新增命令状态目录 `CanvasCommandCatalog`

### 修改前

- 按钮标题、图标、启用态都在 `iOS/macOS ViewController` 中各自推导。
- 同一个命令在两个平台上存在重复的启用条件和文案映射逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名/类型名: 文件原先不存在
// 功能说明: 修改前没有共享的命令状态目录，按钮和菜单状态在各平台 controller 中重复计算。
// before: file did not exist
```

### 修改后

- 新增 `CanvasCommandCatalog`，把命令描述和 session 状态绑定起来。
- 后续无论是按钮、主菜单还是上下文菜单，只需要通过 `commandID + session` 取 descriptor。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名/类型名: CanvasCommandCatalog.descriptor(for:session:)
// 功能说明: 修改后统一产出命令标题、图标、启用态和激活态，避免平台层重复推导。
import Foundation

struct CanvasCommandCatalog {
    func descriptor(
        for commandID: CanvasCommandID,
        session: CanvasEditorSession
    ) -> CanvasCommandDescriptor {
        switch commandID {
        case .crop:
            let isActive = session.isInlineCropModeActive
            return CanvasCommandDescriptor(
                id: .crop,
                title: isActive ? "Done" : "Crop",
                systemImageName: isActive ? "checkmark" : "crop",
                isEnabled: isActive || session.canBeginCropMode,
                isActive: isActive
            )
        case .undo:
            return CanvasCommandDescriptor(
                id: .undo,
                title: "Undo",
                systemImageName: "arrow.uturn.backward",
                isEnabled: session.canUndoCommand,
                isActive: false
            )
        case .redo:
            return CanvasCommandDescriptor(
                id: .redo,
                title: "Redo",
                systemImageName: "arrow.uturn.forward",
                isEnabled: session.canRedoCommand,
                isActive: false
            )
        case .selectItem:
            return CanvasCommandDescriptor(
                id: .selectItem,
                title: "Select",
                systemImageName: "checkmark.circle",
                isEnabled: true,
                isActive: false
            )
        case .clearSelection:
            return CanvasCommandDescriptor(
                id: .clearSelection,
                title: "Deselect",
                systemImageName: "xmark.circle",
                isEnabled: session.canClearSelection,
                isActive: false
            )
        }
    }
}
```

## 修改三：新增命令执行器 `CanvasCommandExecutor`

### 修改前

- 命令执行逻辑分散在 `iOS/macOS ViewController` 私有方法中。
- 同一种命令在两个平台上各自处理一次 `undo/redo`、刷新、autosave、selection history。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名/类型名: 文件原先不存在
// 功能说明: 修改前没有共享执行器，命令执行与副作用分散在平台层。
// before: file did not exist
```

### 修改后

- 新增 `CanvasCommandExecutor`，只依赖 `CanvasEditorSession`。
- 统一命令执行前置校验、执行主体和刷新原因返回，后续 context menu 可以直接复用。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名/类型名: CanvasCommandExecutor.canExecute(_:) / CanvasCommandExecutor.execute(_:)
// 功能说明: 修改后把 crop、undo、redo、selection 等命令执行逻辑统一收口到共享层。
import Foundation

final class CanvasCommandExecutor {
    private let session: CanvasEditorSession

    init(session: CanvasEditorSession) {
        self.session = session
    }

    func canExecute(_ command: CanvasCommand) -> Bool {
        switch command {
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
        }
    }

    func execute(_ command: CanvasCommand) -> CanvasCommandExecutionResult? {
        guard canExecute(command) else {
            return nil
        }

        switch command {
        case .crop:
            if session.isInlineCropModeActive {
                guard session.endInlineEditMode() else {
                    return nil
                }

                return CanvasCommandExecutionResult(
                    refreshReason: "exit crop mode"
                )
            }

            guard session.beginCropModeIfPossible() else {
                return nil
            }

            return CanvasCommandExecutionResult(
                refreshReason: "enter crop mode"
            )
        case .undo:
            guard let snapshot = session.undoHistorySnapshot() else {
                return nil
            }

            session.applyBoardHistorySnapshot(snapshot)
            session.scheduleAutosave(reason: "undo change")
            return CanvasCommandExecutionResult(
                refreshReason: "apply history snapshot"
            )
        case .redo:
            guard let snapshot = session.redoHistorySnapshot() else {
                return nil
            }

            session.applyBoardHistorySnapshot(snapshot)
            session.scheduleAutosave(reason: "redo change")
            return CanvasCommandExecutionResult(
                refreshReason: "apply history snapshot"
            )
        case let .selectItem(itemID, recordHistory):
            guard session.selectItem(withID: itemID, recordHistory: recordHistory) else {
                return nil
            }

            return CanvasCommandExecutionResult(
                refreshReason: "select item \(itemID.uuidString)"
            )
        case let .clearSelection(recordHistory):
            guard session.clearSelection(recordHistory: recordHistory) else {
                return nil
            }

            return CanvasCommandExecutionResult(
                refreshReason: "clear selection"
            )
        }
    }
}
```

## 修改四：扩展 `CanvasEditorSession`，下沉命令可执行语义

### 修改前

- `CanvasEditorSession` 只提供 `undo/redo` 能力和基础的 inline crop 生命周期。
- `canBeginCropMode`、`canClearSelection`、`selectItem`、`clearSelection` 这些语义仍然分散在平台 controller 中。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: canUndoCommand / canRedoCommand / beginCropModeIfPossible() / syncInlineEditStateWithSelection()
// 功能说明: 修改前 session 只承载部分共享能力，selection 相关命令语义仍散落在平台 controller。
var canUndoCommand: Bool {
    inlineEditState == nil && historyController.canUndo
}

var canRedoCommand: Bool {
    inlineEditState == nil && historyController.canRedo
}

@discardableResult
func beginCropModeIfPossible() -> Bool {
    guard
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return false
    }

    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    return true
}

func syncInlineEditStateWithSelection() {
    guard let inlineEditState else {
        return
    }

    guard interactionState.selectedItemID == inlineEditState.itemID else {
        self.inlineEditState = nil
        return
    }

    if let item = scene.item(withID: inlineEditState.itemID) {
        self.inlineEditState = CanvasInlineEditState(
            item: item,
            mode: inlineEditState.mode
        )
    }
}
```

### 修改后

- `CanvasEditorSession` 现在直接暴露命令层所需的启用条件。
- selection 的改写、inline edit 同步和 history 写入也收口到 session，平台层不再二次实现。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: canBeginCropMode / canClearSelection / canSelectItem(withID:) / selectItem(...) / clearSelection(...)
// 功能说明: 修改后 session 统一承接命令层需要的可执行条件、selection 写入和历史同步逻辑。
var canBeginCropMode: Bool {
    guard let selectedItemID = interactionState.selectedItemID else {
        return false
    }

    return scene.item(withID: selectedItemID) != nil
}

var canClearSelection: Bool {
    interactionState.selectedItemID != nil
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

## 修改五：`iOSViewController` 改为通过 command layer 驱动命令入口

### 修改前

- `iOS` 的按钮点击、selection 修改、`undo/redo` 和 crop 生命周期都在 controller 私有方法里直接处理。
- 这导致平台层既负责 UI，又负责命令定义、命令可执行性判断和执行副作用。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: handleCropButtonTap() / handleUndoButtonTap() / handleRedoButtonTap() / selectItem(...) / clearSelectionIfNeeded(...)
// 功能说明: 修改前 iOS controller 直接处理命令入口与 selection 写入，命令语义与 UI 层紧耦合。
@objc
private func handleCropButtonTap() {
    if isInlineCropModeActive {
        endInlineEditMode(reason: "exit crop mode")
    } else {
        beginCropModeIfPossible()
    }
}

@objc
private func handleUndoButtonTap() {
    performUndoCommand()
}

@objc
private func handleRedoButtonTap() {
    performRedoCommand()
}

private func selectItem(
    withID itemID: CanvasImageItemID,
    recordHistory: Bool = false
) {
    guard interactionState.selectedItemID != itemID else {
        return
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    interactionState.selectedItemID = itemID
    syncInlineEditStateWithSelection()
    requestCanvasRefresh(reason: "select item \(itemID.uuidString)")

    if let beforeSnapshot {
        recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "select item"
        )
    }
}

private func clearSelectionIfNeeded(recordHistory: Bool = false) {
    guard interactionState.selectedItemID != nil else {
        return
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    interactionState.selectedItemID = nil
    syncInlineEditStateWithSelection()
    requestCanvasRefresh(reason: "clear selection")

    if let beforeSnapshot {
        recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "clear selection"
        )
    }
}
```

### 修改后

- 新增 `commandCatalog` 和 `commandExecutor`。
- 新增 `performCommand(_:)` 作为统一命令入口，负责命令可执行性判断、旋转态取消、共享执行和刷新。
- 按钮与 selection 逻辑全部改为走 `CanvasCommand`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: commandDescriptor(for:) / performCommand(_:) / handleCropButtonTap() / handleUndoButtonTap() / handleRedoButtonTap()
// 功能说明: 修改后 iOS controller 只负责桥接平台 UI 到共享命令层，不再自己承接命令执行细节。
private let commandCatalog = CanvasCommandCatalog()
private lazy var commandExecutor = CanvasCommandExecutor(
    session: editorSession
)

private func commandDescriptor(
    for commandID: CanvasCommandID
) -> CanvasCommandDescriptor {
    commandCatalog.descriptor(
        for: commandID,
        session: editorSession
    )
}

private func performCommand(_ command: CanvasCommand) {
    guard commandExecutor.canExecute(command) else {
        return
    }

    if command.shouldCancelActiveRotation {
        cancelRotationInteractionIfNeeded(
            resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
        )
    }

    guard let executionResult = commandExecutor.execute(command) else {
        return
    }

    updateInlineEditButtonsAppearance()

    if let refreshReason = executionResult.refreshReason {
        requestCanvasRefresh(reason: refreshReason)
    }
}

@objc
private func handleCropButtonTap() {
    performCommand(.crop)
}

@objc
private func handleUndoButtonTap() {
    performCommand(.undo)
}

@objc
private func handleRedoButtonTap() {
    performCommand(.redo)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: selectItem(...) / clearSelectionIfNeeded(...)
// 功能说明: 修改后 selection 相关操作不再直接改 interactionState，而是显式走命令层。
private func selectItem(
    withID itemID: CanvasImageItemID,
    recordHistory: Bool = false
) {
    performCommand(
        .selectItem(
            itemID: itemID,
            recordHistory: recordHistory
        )
    )
}

private func clearSelectionIfNeeded(recordHistory: Bool = false) {
    performCommand(.clearSelection(recordHistory: recordHistory))
}
```

## 修改六：`iOSViewController` 的按钮状态改为读取 command descriptor

### 修改前

- crop/undo/redo 的按钮状态由 controller 手动读取 `isInlineCropModeActive`、`selectedItemID`、`canUndoCommand`、`canRedoCommand`。
- 相同的状态推导逻辑未来如果在 context menu 再实现一次，会继续复制。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateCropButtonAppearance() / updateUndoButtonAppearance() / updateRedoButtonAppearance()
// 功能说明: 修改前 iOS 的按钮标题、图标和启用态都由 controller 自己拼装。
private func updateCropButtonAppearance() {
    let isActive = isInlineCropModeActive
    let isEnabled = isActive || interactionState.selectedItemID != nil
    applyCropButtonAppearance(
        title: isActive ? "Done" : "Crop",
        systemImageName: isActive ? "checkmark" : "crop",
        backgroundColor: isActive ? .systemOrange : .systemIndigo,
        isEnabled: isEnabled
    )
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
```

### 修改后

- 三个按钮的状态全部来自 `CanvasCommandDescriptor`。
- 这一步把命令状态的唯一来源固定成了 `commandCatalog + session`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateCropButtonAppearance() / updateUndoButtonAppearance() / updateRedoButtonAppearance()
// 功能说明: 修改后 iOS 的按钮表现统一读取 descriptor，避免平台层重复推导命令状态。
private func updateCropButtonAppearance() {
    let descriptor = commandDescriptor(for: .crop)
    applyCropButtonAppearance(
        title: descriptor.title,
        systemImageName: descriptor.systemImageName,
        backgroundColor: descriptor.isActive ? .systemOrange : .systemIndigo,
        isEnabled: descriptor.isEnabled
    )
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

## 修改七：`macOSViewController` 和 `macOSAppDelegate` 改为通过 command layer 驱动

### 修改前

- `macOSViewController` 和 `iOSViewController` 一样，直接承担命令入口与 selection 写入。
- `macOSAppDelegate` 的主菜单仍然直连 `performUndoCommand()` / `performRedoCommand()`，校验也依赖旧的 `canUndoCommand` / `canRedoCommand`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: handleCropButtonClick() / selectItem(...) / clearSelectionIfNeeded(...) / performUndoCommand() / performRedoCommand()
// 功能说明: 修改前 macOS controller 直接持有命令入口与执行逻辑，和 iOS 一样重复了一套命令层职责。
@objc
private func handleCropButtonClick() {
    if isInlineCropModeActive {
        endInlineEditMode(reason: "exit crop mode")
    } else {
        beginCropModeIfPossible()
    }
}

private func selectItem(
    withID itemID: CanvasImageItemID,
    recordHistory: Bool = false
) {
    guard interactionState.selectedItemID != itemID else {
        return
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    interactionState.selectedItemID = itemID
    syncInlineEditStateWithSelection()
    refreshCanvas()

    if let beforeSnapshot {
        recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "select item"
        )
    }
}

func performUndoCommand() {
    guard
        canUndoCommand,
        let snapshot = editorSession.undoHistorySnapshot()
    else {
        return
    }

    applyBoardHistorySnapshot(snapshot)
    scheduleAutosave(reason: "undo change")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数名/类型名: handleUndoMenuItem(_:) / handleRedoMenuItem(_:) / validateMenuItem(_:)
// 功能说明: 修改前 macOS 主菜单仍然绕过共享命令层，直接调用 controller 的旧 undo/redo 接口。
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
```

### 修改后

- `macOSViewController` 也新增 `commandCatalog`、`commandExecutor`、`performCommand(_:)`。
- 对外只暴露 `canPerformCommand(_:)` 和 `performCommand(withID:)` 给 `AppDelegate` 使用。
- 主菜单触发和校验也切到了共享命令状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: commandDescriptor(for:) / performCommand(_:) / canPerformCommand(_:) / performCommand(withID:)
// 功能说明: 修改后 macOS controller 退化为平台桥接层，只暴露命令查询与触发接口给 AppKit 菜单系统。
private let commandCatalog = CanvasCommandCatalog()
private lazy var commandExecutor = CanvasCommandExecutor(
    session: editorSession
)

private func commandDescriptor(
    for commandID: CanvasCommandID
) -> CanvasCommandDescriptor {
    commandCatalog.descriptor(
        for: commandID,
        session: editorSession
    )
}

private func performCommand(_ command: CanvasCommand) {
    guard commandExecutor.canExecute(command) else {
        return
    }

    if command.shouldCancelActiveRotation {
        cancelRotationInteractionIfNeeded(
            resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
        )
    }

    guard let executionResult = commandExecutor.execute(command) else {
        return
    }

    updateInlineEditButtonsAppearance()

    if executionResult.refreshReason != nil {
        refreshCanvas()
    }
}

func canPerformCommand(_ commandID: CanvasCommandID) -> Bool {
    commandDescriptor(for: commandID).isEnabled
}

func performCommand(withID commandID: CanvasCommandID) {
    switch commandID {
    case .crop:
        performCommand(CanvasCommand.crop)
    case .undo:
        performCommand(CanvasCommand.undo)
    case .redo:
        performCommand(CanvasCommand.redo)
    case .selectItem, .clearSelection:
        break
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: handleCropButtonClick() / selectItem(...) / clearSelectionIfNeeded(...) / updateCropButtonAppearance()
// 功能说明: 修改后 macOS 的按钮入口、selection 和按钮状态也全部改为走共享命令层。
@objc
private func handleCropButtonClick() {
    performCommand(CanvasCommand.crop)
}

private func selectItem(
    withID itemID: CanvasImageItemID,
    recordHistory: Bool = false
) {
    performCommand(
        .selectItem(
            itemID: itemID,
            recordHistory: recordHistory
        )
    )
}

private func clearSelectionIfNeeded(recordHistory: Bool = false) {
    performCommand(.clearSelection(recordHistory: recordHistory))
}

private func updateCropButtonAppearance() {
    let descriptor = commandDescriptor(for: .crop)
    applyCropButtonAppearance(
        title: descriptor.title,
        systemImageName: descriptor.systemImageName,
        tintColor: descriptor.isActive ? .systemOrange : .controlAccentColor,
        isEnabled: descriptor.isEnabled
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数名/类型名: handleUndoMenuItem(_:) / handleRedoMenuItem(_:) / validateMenuItem(_:)
// 功能说明: 修改后 macOS 主菜单通过共享命令层查询启用态并触发命令，和后续上下文菜单保持同一来源。
@objc
private func handleUndoMenuItem(_ sender: Any?) {
    rootViewController?.currentCanvasViewController?.performCommand(withID: .undo)
}

@objc
private func handleRedoMenuItem(_ sender: Any?) {
    rootViewController?.currentCanvasViewController?.performCommand(withID: .redo)
}

func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(handleUndoMenuItem(_:)):
        return rootViewController?.currentCanvasViewController?.canPerformCommand(.undo) ?? false
    case #selector(handleRedoMenuItem(_:)):
        return rootViewController?.currentCanvasViewController?.canPerformCommand(.redo) ?? false
    default:
        return true
    }
}
```

## 验证结果

- 已通过 `date +"%Y%m%d_%H%M%S"` 获取本记录时间戳：`20260318_120117`
- 已通过 `ReadLints` 检查本次改动文件，无新增 lint 问题
- 已通过 `xcodebuild` 构建验证：
  - `macOS`: `generic/platform=macOS`
  - `iOS`: `generic/platform=iOS`

## 当前阶段结论

- 阶段 2 已把“命令是什么”“命令能不能执行”“命令如何执行”从平台 controller 中抽离出来。
- 后续阶段 3 可以直接在 `CanvasContextResolver` 中产出 `CanvasCommandID / CanvasCommand`，而不用再碰平台私有方法。
