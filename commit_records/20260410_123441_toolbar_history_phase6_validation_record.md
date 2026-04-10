# 20260410_123441_toolbar_history_phase6_validation_record

## 记录说明

本记录基于本轮“实施阶段6”时的实际 `git status`、`git diff --stat`、`git diff`、构建命令与测试命令整理，不包含原始 `git diff` 文本。

这次需要如实记录的事实是：

- 本轮没有新增业务代码修改。
- 本轮执行的是 `toolbar_history_convergence` 的阶段 6 验证。
- 当前工作区在创建本记录之前处于代码干净状态：`0 files changed`。

## 时间戳与取证命令

```bash
# 文件路径: /bin/date
# 函数: date
# 说明: 生成本记录文件名前缀使用的时间戳。
date +"%Y%m%d_%H%M%S"
```

```bash
# 文件路径: /usr/bin/git
# 函数: git status --short
# 说明: 核对本轮执行前工作区是否存在未提交业务代码修改。
git status --short
```

```bash
# 文件路径: /usr/bin/git
# 函数: git status --short
# 说明: 本轮执行前该命令返回空输出，表示没有未提交业务代码修改。
# 输出: <empty>
```

```bash
# 文件路径: /usr/bin/git
# 函数: git diff --stat / git diff
# 说明: 核对 toolbar 收敛相关代码文件在本轮执行前是否还有未提交差异。
git diff --stat -- \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift"

git diff -- \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift"
```

```bash
# 文件路径: /usr/bin/git
# 函数: git diff --stat / git diff
# 说明: 上述两个命令在本轮执行前均返回空输出，说明阶段6没有新增代码修改需要落地。
# 输出: <empty>
```

## 本轮执行的真实边界

本轮不是新的代码实现，而是对前面阶段结果做回归验证。验证重点包括：

1. `iOS` 不再残留私有 history UI 入口。
2. `iOS` / `macOS` 都通过共享 toolbar items 渲染 `undo/redo`。
3. `macOS` 的 toolbar、菜单、快捷键三条入口共用同一套命令可用性判断。
4. 阶段 5 清理后的共享 blocker 模型可以继续正常构建。

由于本轮没有发现必须修复的新代码问题，所以阶段 6 没有新增代码改动。

## 核对点一：iOS 共享 toolbar 接线在本轮执行前后保持一致

### 本轮执行前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: toolbarButtonsByID / makeToolbarState()
// 说明: 本轮执行前，iOS 已把 undo/redo 并入共享 toolbar 注册字典，并显式开启 includesHistoryItems。
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

private func makeToolbarState() -> CanvasToolbarState {
    toolbarStateBuilder.mainToolbarState(
        session: editorSession,
        saveState: saveButtonState,
        placement: toolbarPreferredPlacement(),
        includesHistoryItems: true
    )
}
```

### 本轮执行后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: toolbarButtonsByID / makeToolbarState()
// 说明: 本轮执行后代码保持不变；阶段6只验证该状态是否稳定存在，没有新增实现。
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

private func makeToolbarState() -> CanvasToolbarState {
    toolbarStateBuilder.mainToolbarState(
        session: editorSession,
        saveState: saveButtonState,
        placement: toolbarPreferredPlacement(),
        includesHistoryItems: true
    )
}
```

## 核对点二：iOS 私有 history blocker 已移除，且本轮执行前后保持一致

### 本轮执行前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: baseChromeBlockersForToolbarLayout()
// 说明: 本轮执行前 iOS 已不再注入 .historyButtons，只保留真实存在的 blocker。
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

### 本轮执行后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: baseChromeBlockersForToolbarLayout()
// 说明: 本轮执行后代码保持不变；说明阶段6验证没有发现需要把 historyButtons blocker 引回来的问题。
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

## 核对点三：macOS 菜单、toolbar、快捷键共用同一套命令可用性判断

### 本轮执行前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: canPerformCommand(_:)
// 说明: 本轮执行前，macOS toolbar 可用性已经统一落到 commandDescriptor(for:).isEnabled。
func canPerformCommand(_ commandID: CanvasCommandID) -> Bool {
    isTransitionInteractionFrozen == false &&
        commandDescriptor(for: commandID).isEnabled
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数: validateMenuItem(_:)
// 说明: 本轮执行前，macOS 菜单入口也统一回 currentCanvasViewController.canPerformCommand(.undo/.redo)。
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

### 本轮执行后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: canPerformCommand(_:)
// 说明: 本轮执行后代码保持不变；阶段6验证确认 toolbar 入口仍然走统一命令可用性判断。
func canPerformCommand(_ commandID: CanvasCommandID) -> Bool {
    isTransitionInteractionFrozen == false &&
        commandDescriptor(for: commandID).isEnabled
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数: validateMenuItem(_:)
// 说明: 本轮执行后代码保持不变；阶段6验证确认菜单入口与 toolbar 入口仍然共用同一套判定链路。
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

## 本轮执行的验证命令与结果

```bash
# 文件路径: /usr/bin/xcodebuild
# 函数: xcodebuild -project ... -scheme ... build
# 说明: 对 macOS 与 iOS Simulator 两个目标执行构建验证。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS Simulator" \
  build
```

```bash
# 文件路径: /usr/bin/xcodebuild
# 函数: xcodebuild -project ... -scheme ... test
# 说明: 尝试执行现有 XCTest 套件，作为阶段6的补充回归验证。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  test
```

### 构建与测试结果

- `ReadLints` 检查相关代码文件，无新增问题。
- `macOS build` 通过。
- `iOS Simulator build` 通过。
- `macOS test` 未通过，但失败点与这次 toolbar 收敛无关。

## 测试失败的实际原因

测试失败不是因为 `undo/redo` toolbar 收敛，而是现有测试代码和 `BoardRuntimeState` 当前初始化签名不一致。

### 失败代码片段

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数: makeAlignmentOverlayTestRuntimeState(items:selectedItemID:)
// 说明: 现有测试仍在向 BoardRuntimeState 传入旧的 updatedAt 参数。
private func makeAlignmentOverlayTestRuntimeState(
    items: [CanvasBoardItem],
    selectedItemID: CanvasItemID? = nil
) -> BoardRuntimeState {
    BoardRuntimeState(
        boardID: UUID(),
        title: "Alignment Test Board",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        items: items,
        boardState: nil,
        camera: CanvasCamera(
            center: .zero,
            zoomScale: 1,
            viewportSize: CGSize(width: 600, height: 400)
        ),
        interactionState: CanvasInteractionState(selectedItemID: selectedItemID),
        workspaceMode: .editing
    )
}
```

### 当前模型签名

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数/符号: BoardRuntimeState
// 说明: 当前模型已经拆成 contentUpdatedAt 与 viewStateUpdatedAt，updatedAt 只是只读计算属性。
struct BoardRuntimeState {
    let boardID: UUID
    var title: String
    let createdAt: Date
    var contentUpdatedAt: Date
    var viewStateUpdatedAt: Date
    var items: [CanvasBoardItem]
    var boardState: CanvasBoardState?
    var camera: CanvasCamera
    var interactionState: CanvasInteractionState
    var workspaceMode: CanvasWorkspaceMode

    var updatedAt: Date {
        contentUpdatedAt
    }
}
```

### 这一处验证结论

- `xcodebuild test` 的失败是现有测试代码与当前模型签名脱节。
- 失败文件是 `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`。
- 这不是本轮 `toolbar_history_convergence` 引入的新业务代码问题。

## 本轮无法自动化完成的验证项

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: renderToolbar() / updatePreparedToolbarPlacement()
// 说明: iOS 编辑态按钮可见性、阅读模式下 overlay 避让、以及 toolbar transition 是否有肉眼可见抖动，属于运行时视觉/交互验证，本轮只能做代码级与构建级确认。
// 本轮未新增代码改动。
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: handleUndoButtonClick() / handleRedoButtonClick() / canPerformCommand(_:)
// 说明: macOS toolbar、菜单、快捷键在真实运行中的交互一致性，本轮已做代码链路核对，但仍建议在本机手动点一轮。
// 本轮未新增代码改动。
```

## 修改后的阶段性结论

这次阶段 6 的如实结论是：

1. 本轮没有新增代码改动。
2. 阶段 1 / 2 / 5 产出的代码在静态链路、lint 与双平台构建层面均可通过。
3. 现有 XCTest 套件存在一个与 `BoardRuntimeState` 签名演进相关的既有编译失败，与本轮 toolbar 收敛无关。
4. 原生 UI 的最终视觉与交互表现仍建议在本机手动确认。
