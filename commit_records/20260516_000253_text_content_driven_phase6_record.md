# 20260516_000253_text_content_driven_phase6_record

## 记录范围

- 记录内容：
  - 实施“文字内容驱动尺寸”计划的 `phase 6`，把字号入口接到 inline text editor 附近，并强制走命令层而不是 view 私有写口。
  - 在 `iOS` / `macOS` 的 inline text editor overlay 中新增离散字号步进控件：`A-` / `A+`。
  - 在 shared command lane 中新增字号增减命令，让字号调整复用 `history`、`undo/redo`、`autosave`、`reading mode gate`。
  - 补充命令级回归测试，锁定“编辑态可执行 / 阅读模式被禁用 / 历史可撤销重做”。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short --untracked-files=all` 显示上述 `10` 个文件处于修改状态。
  - 生成本记录前，`git diff --stat -- ...phase6 files...` 显示共 `591 insertions(+), 27 deletions(-)`。
- 本记录不包含：
  - `phase 7` 的完整手工回归清单
  - 连续滑杆式字号调节
  - context menu 暴露字号命令
  - 额外的字号快捷键设计

## 当前 changes 摘要

- `CanvasCommand` 现在新增 `decreaseTextFontSize` / `increaseTextFontSize` 两个命令，并引入 `shouldCommitActiveInlineTextBeforeExecuting`，专门豁免“字号调整时不要先强制 `commitTextEdit`”。
- `CanvasCommandCatalog` / `CanvasCommandExecutor` / `CanvasContextMenuCommandResolver` 已同步新增或收口对应分支：
  - 命令目录能返回按钮可用性
  - 执行器能真正执行字号修改
  - context menu 暂不暴露这两个命令
- `CanvasEditorSession` 新增 inline 文字字号调整能力：
  - 暴露 `canDecreaseInlineTextFontSize` / `canIncreaseInlineTextFontSize`
  - 暴露 `activeInlineTextItem`
  - 用当前 `draftText + style` 直接更新 scene 中的 text item，并同步重算 intrinsic `size`
  - 记录 `history` 并触发 `autosave`
- `iOS` / `macOS` 的文字编辑 overlay 现在都带有 `A-` / `A+` 按钮与字号标签；controller 通过 closure 把点击事件转成正式命令。
- `syncTextEditorPresentation()` 不再只同步 draft text，还会同步当前字号样式与命令启用态。
- 新增命令级回归测试，锁住：
  - 字号命令不会强制结束 inline text edit
  - 编辑模式可执行 / 阅读模式被 gate
  - 字号调整进入 history，且支持 `undo / redo`

## 修改一：把字号调整收口到 shared command lane

### 修改前

- `CanvasCommandID` / `CanvasCommand` 只有 `beginTextEdit` / `commitTextEdit`，没有字号调整命令。
- `CanvasCommandCatalog` 和 `CanvasCommandExecutor` 也没有字号相关分支，因此 overlay 就算长出按钮，也没有共享业务入口可调。
- `CanvasContextMenuCommandResolver` 只认识既有命令，没机会明确表达“字号命令当前不进 context menu”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift（修改前）
// 函数名: CanvasCommandID / CanvasCommand
// 功能说明: 修改前 command lane 只有进入/提交文字编辑，没有字号增减命令，inline editor 无法通过共享命令层调整文字样式。
enum CanvasCommandID: String {
    case importMedia
    case addTextItem
    case beginTextEdit
    case commitTextEdit
    case crop
    case undo
    case redo
    // ...
}

enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case crop
    case beginCropMode(itemID: CanvasItemID)
    case undo
    case redo
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift（修改前）
// 函数名: descriptor(for:session:context:)
// 功能说明: 修改前 command catalog 只为 Done / Crop 等既有命令生成 descriptor，没有字号按钮可复用的命令描述。
case .commitTextEdit:
    descriptor = CanvasCommandDescriptor(
        id: .commitTextEdit,
        title: "Done",
        systemImageName: "checkmark",
        isEnabled: session.canCommitTextEdit,
        isActive: session.isInlineTextModeActive
    )
case .crop:
    // ...
```

### 修改后

- `CanvasCommandID` / `CanvasCommand` 新增 `decreaseTextFontSize` / `increaseTextFontSize`。
- `CanvasCommand` 新增 `shouldCommitActiveInlineTextBeforeExecuting`，把字号命令从“执行前强制提交 inline text”这一类命令里排除。
- `CanvasCommandCatalog` 可以为两个命令产出 descriptor，直接复用 `session.canDecreaseInlineTextFontSize` / `session.canIncreaseInlineTextFontSize`。
- `CanvasCommandExecutor` 负责把这两个命令下沉到 `CanvasEditorSession.decreaseInlineTextFontSize()` / `increaseInlineTextFontSize()`。
- `CanvasContextMenuCommandResolver` 明确返回 `nil`，保持 phase 6 的字号入口只出现在 inline editor 附近。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名: CanvasCommandID / CanvasCommand / shouldCommitActiveInlineTextBeforeExecuting
// 功能说明: 修改后 command lane 原生承载字号增减命令，并显式声明这两个命令执行前不应先提交当前 inline text draft。
enum CanvasCommandID: String {
    case importMedia
    case addTextItem
    case beginTextEdit
    case commitTextEdit
    case decreaseTextFontSize
    case increaseTextFontSize
    case crop
    case undo
    case redo
    // ...
}

enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case decreaseTextFontSize
    case increaseTextFontSize
    case crop
    // ...

    var shouldCommitActiveInlineTextBeforeExecuting: Bool {
        switch self {
        case .commitTextEdit,
             .decreaseTextFontSize,
             .increaseTextFontSize:
            return false
        case .importMedia,
             .addTextItem,
             .beginTextEdit,
             .crop,
             .beginCropMode,
             .undo,
             .redo:
            return true
        // ... 省略其余 mutation commands ...
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift / MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift / MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名: descriptor(for:session:context:) / canExecute(_:) / execute(_:) / command(for:context:session:)
// 功能说明: 修改后命令目录、执行器与 context menu resolver 同步收口字号命令；overlay 只负责发命令，不直接持有写口。
case .decreaseTextFontSize:
    descriptor = CanvasCommandDescriptor(
        id: .decreaseTextFontSize,
        title: "Smaller Text",
        systemImageName: "minus",
        isEnabled: session.canDecreaseInlineTextFontSize,
        isActive: false
    )
case .increaseTextFontSize:
    descriptor = CanvasCommandDescriptor(
        id: .increaseTextFontSize,
        title: "Larger Text",
        systemImageName: "plus",
        isEnabled: session.canIncreaseInlineTextFontSize,
        isActive: false
    )

case .decreaseTextFontSize:
    return session.canDecreaseInlineTextFontSize
case .increaseTextFontSize:
    return session.canIncreaseInlineTextFontSize

case .decreaseTextFontSize:
    guard let updatedItem = session.decreaseInlineTextFontSize() else {
        return nil
    }
    return CanvasCommandExecutionResult(
        refreshReason: "decrease inline text font size \(updatedItem.id.uuidString)"
    )
case .increaseTextFontSize:
    guard let updatedItem = session.increaseInlineTextFontSize() else {
        return nil
    }
    return CanvasCommandExecutionResult(
        refreshReason: "increase inline text font size \(updatedItem.id.uuidString)"
    )

case .decreaseTextFontSize,
     .increaseTextFontSize:
    return nil
```

## 修改二：Session 在 inline text 编辑期间直接更新 style + size，并修正空草稿提交语义

### 修改前

- `CanvasEditorSession` 只有 `updateTextEditDraft(_:)` 和 `commitTextEdit()`，没有“编辑中直接调字号”的共享写口。
- `commitTextEdit()` 会先判断 `draftText == item.text`，再判断空白文本删除；这在 phase 6 会产生新问题：
  - 如果字号命令已经把 scene text item 用当前 draft 同步成空字符串
  - 随后点 `Done`
  - `draftText == item.text` 会提前命中
  - 空文字项就不会被删除

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift（修改前）
// 函数名: updateTextEditDraft(_:) / commitTextEdit()
// 功能说明: 修改前 Session 只能更新 draft 或最终 commit，没有 inline 字号调整写口，而且 commitTextEdit 的判定顺序会让“已同步到 scene 的空 draft”被误判为 no-op。
@discardableResult
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

@discardableResult
func commitTextEdit() -> CanvasTextEditCommitResult? {
    // ...
    let draftText = inlineEditState.draftText
    if draftText == item.text {
        return CanvasTextEditCommitResult(
            itemID: itemID,
            didDeleteItem: false,
            didChangeDocument: false
        )
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        // ...
    }
    // ...
}
```

### 修改后

- `CanvasEditorSession` 新增：
  - `canDecreaseInlineTextFontSize`
  - `canIncreaseInlineTextFontSize`
  - `activeInlineTextItem`
  - `decreaseInlineTextFontSize()`
  - `increaseInlineTextFontSize()`
  - `adjustInlineTextFontSize(by:)`
- 字号命令会用当前 `inlineEditState.draftText + updatedStyle` 调 `updateTextItemContent(...)`，因此 scene 中的 text、style、size 会保持原子一致。
- 每次字号调整后都会：
  - `expandBoardIfNeeded(toInclude:)`
  - `recordImmediateHistoryChange(...)`
  - 触发 autosave
- `commitTextEdit()` 改为先处理“空白 draft 删除”分支，再处理“draft 与 scene text 相等”的 no-op 分支，专门兜住 phase 6 的空草稿场景。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: canDecreaseInlineTextFontSize / canIncreaseInlineTextFontSize / activeInlineTextItem / decreaseInlineTextFontSize() / increaseInlineTextFontSize() / adjustInlineTextFontSize(by:)
// 功能说明: 修改后 Session 可以在 inline text 编辑期间按步进调整字号，并把 draft text + style + intrinsic size 一起提交到 scene，同时记录 history/autosave。
private static let inlineTextFontSizeStep: CGFloat = 2

var canDecreaseInlineTextFontSize: Bool {
    canAdjustInlineTextFontSize(by: -Self.inlineTextFontSizeStep)
}

var canIncreaseInlineTextFontSize: Bool {
    canAdjustInlineTextFontSize(by: Self.inlineTextFontSizeStep)
}

var activeInlineTextItem: CanvasTextItem? {
    guard
        let inlineEditState,
        inlineEditState.mode == .text
    else {
        return nil
    }

    return scene.textItem(withID: inlineEditState.itemID)
}

@discardableResult
func decreaseInlineTextFontSize() -> CanvasTextItem? {
    adjustInlineTextFontSize(by: -Self.inlineTextFontSizeStep)
}

@discardableResult
func increaseInlineTextFontSize() -> CanvasTextItem? {
    adjustInlineTextFontSize(by: Self.inlineTextFontSizeStep)
}

@discardableResult
private func adjustInlineTextFontSize(by delta: CGFloat) -> CanvasTextItem? {
    guard
        let inlineEditState,
        inlineEditState.mode == .text,
        let item = activeInlineTextItem
    else {
        return nil
    }

    let updatedStyle = adjustedInlineTextStyle(
        from: item.style,
        fontSizeDelta: delta
    )
    guard updatedStyle != item.style else {
        return nil
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    guard let updatedItem = updateTextItemContent(
        withID: item.id,
        text: inlineEditState.draftText,
        style: updatedStyle
    ) else {
        return nil
    }

    expandBoardIfNeeded(toInclude: updatedItem.worldBounds)
    let changeReason = delta < 0
        ? "decrease inline text font size"
        : "increase inline text font size"
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: changeReason,
        autosaveReason: changeReason
    )
    return updatedItem
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: commitTextEdit()
// 功能说明: 修改后 commitTextEdit 先处理空白 draft 删除，再处理 no-op；这样字号命令提前把空 draft 同步进 scene 后，Done 仍会删除空文字项。
let draftText = inlineEditState.draftText
if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    let beforeSnapshot = currentBoardHistorySnapshot()
    guard scene.removeItem(withID: itemID) else {
        return CanvasTextEditCommitResult(
            itemID: itemID,
            didDeleteItem: false,
            didChangeDocument: false
        )
    }
    // ...
}

if draftText == item.text {
    return CanvasTextEditCommitResult(
        itemID: itemID,
        didDeleteItem: false,
        didChangeDocument: false
    )
}

let beforeSnapshot = currentBoardHistorySnapshot()
guard updateTextItemContent(withID: itemID, text: draftText, style: item.style) != nil else {
    // ...
}
```

## 修改三：在 iOS / macOS inline editor 附近加入 `A- / A+`，并通过 controller 发命令

### 修改前

- `iOSCanvasTextEditorOverlayView` / `macOSCanvasTextEditorOverlayView` 只有文本输入区，没有字号控件。
- `apply(text:)` 只会同步 draft text，不会同步字号展示或命令启用态。
- iOS / macOS controller 在 `setupTextEditorOverlay()` 里只接管 text delegate；`syncTextEditorPresentation()` 也只把 draft text 塞回 overlay。
- controller 的 `performCommand(_:)` 会对除 `.commitTextEdit` 外的所有命令先强制 `commitTextEdit`，这会把新的字号命令错误地变成“先结束编辑，再调字号”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift（修改前）
// 函数名: apply(text:)
// 功能说明: 修改前 iOS overlay 只有文本输入区，没有字号步进控件，也没有可供 controller 注入的字号状态。
let textView: iOSCanvasInputObservingTextView = {
    let textView = iOSCanvasInputObservingTextView()
    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.backgroundColor = .clear
    textView.font = .systemFont(ofSize: 17)
    textView.textColor = .label
    // ...
    return textView
}()

func apply(text: String) {
    if textView.text != text {
        textView.text = text
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: performCommand(_:) / setupTextEditorOverlay() / syncTextEditorPresentation()
// 功能说明: 修改前 controller 会在执行除 commit 外的任何命令前强制提交 inline text，而且 overlay 同步只覆盖 draft text。
private func performCommand(_ command: CanvasCommand) {
    guard isTransitionInteractionFrozen == false else {
        return
    }

    if command.id != .commitTextEdit,
       isInlineTextModeActive,
       workspaceMode == .editing
    {
        performCommand(.commitTextEdit)
    }
    // ...
}

private func setupTextEditorOverlay() {
    textEditorOverlayView.textView.delegate = self
    textEditorOverlayView.onObservedShortcut = { [weak self] shortcut in
        self?.handleObservedTextEditorShortcut(shortcut)
    }
    syncTextEditorPresentation()
}

private func syncTextEditorPresentation() {
    // ...
    if textEditorOverlayView.textView.text != inlineEditState.draftText {
        isSyncingTextEditorContent = true
        textEditorOverlayView.apply(text: inlineEditState.draftText)
        isSyncingTextEditorContent = false
    }
    // ...
}
```

### 修改后

- iOS / macOS overlay 都新增：
  - `A-` / `A+` 按钮
  - 字号标签
  - `onDecreaseFontSize` / `onIncreaseFontSize` 回调
  - `apply(text:style:canDecreaseFontSize:canIncreaseFontSize:)`
- iOS / macOS controller 都改为：
  - 在 `setupTextEditorOverlay()` 里把按钮点击转成 `.decreaseTextFontSize` / `.increaseTextFontSize`
  - 在 `syncTextEditorPresentation()` 中同步 draft text、当前 `textItem.style`、命令 enable 状态
  - 在 `performCommand(_:)` 中改用 `command.shouldCommitActiveInlineTextBeforeExecuting`
- macOS controller 额外把 `performCommand(withID:)` 补齐到两个新命令，保证菜单/统一命令入口在类型层是完整的。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift
// 函数名: apply(text:style:canDecreaseFontSize:canIncreaseFontSize:) / handleDecreaseFontSizeTap() / handleIncreaseFontSizeTap()
// 功能说明: 修改后 iOS overlay 在输入框上方增加字号步进控件，并通过 closure 把点击事件抛回 controller，view 本身不直接改业务状态。
private let fontSizeLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    label.textAlignment = .center
    label.textColor = .secondaryLabel
    label.accessibilityLabel = "Font size"
    return label
}()

private let decreaseFontSizeButton = iOSCanvasTextEditorOverlayView.makeFontSizeButton(
    title: "A-",
    accessibilityLabel: "Decrease font size"
)
private let increaseFontSizeButton = iOSCanvasTextEditorOverlayView.makeFontSizeButton(
    title: "A+",
    accessibilityLabel: "Increase font size"
)

var onDecreaseFontSize: (() -> Void)?
var onIncreaseFontSize: (() -> Void)?

func apply(
    text: String,
    style: CanvasTextStyle,
    canDecreaseFontSize: Bool,
    canIncreaseFontSize: Bool
) {
    if textView.text != text {
        textView.text = text
    }
    textView.font = platformFont(for: style)
    fontSizeLabel.text = fontSizeDescription(for: style.fontSize)
    decreaseFontSizeButton.isEnabled = canDecreaseFontSize
    increaseFontSizeButton.isEnabled = canIncreaseFontSize
}

@objc
private func handleDecreaseFontSizeTap() {
    onDecreaseFontSize?()
}

@objc
private func handleIncreaseFontSizeTap() {
    onIncreaseFontSize?()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift
// 函数名: apply(text:style:canDecreaseFontSize:canIncreaseFontSize:) / handleDecreaseFontSizeClick() / handleIncreaseFontSizeClick()
// 功能说明: 修改后 macOS overlay 与 iOS 保持镜像结构，在 AppKit 下提供等价的字号控件与回调出口。
private let fontSizeLabel: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    return label
}()

var onDecreaseFontSize: (() -> Void)?
var onIncreaseFontSize: (() -> Void)?

func apply(
    text: String,
    style: CanvasTextStyle,
    canDecreaseFontSize: Bool,
    canIncreaseFontSize: Bool
) {
    if textView.string != text {
        textView.string = text
    }
    textView.font = platformFont(for: style)
    fontSizeLabel.stringValue = fontSizeDescription(for: style.fontSize)
    decreaseFontSizeButton.isEnabled = canDecreaseFontSize
    increaseFontSizeButton.isEnabled = canIncreaseFontSize
}

@objc
private func handleDecreaseFontSizeClick() {
    onDecreaseFontSize?()
}

@objc
private func handleIncreaseFontSizeClick() {
    onIncreaseFontSize?()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift / MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performCommand(_:) / setupTextEditorOverlay() / syncTextEditorPresentation() / performCommand(withID:)
// 功能说明: 修改后 controller 只把字号按钮转译成命令，并在每次 presentation sync 时把当前样式和 enable 状态注入 overlay；macOS 统一命令入口也补上了两个新 commandID。
if command.shouldCommitActiveInlineTextBeforeExecuting,
   isInlineTextModeActive,
   workspaceMode == .editing
{
    performCommand(.commitTextEdit)
}

private func setupTextEditorOverlay() {
    textEditorOverlayView.textView.delegate = self
    textEditorOverlayView.onDecreaseFontSize = { [weak self] in
        self?.performCommand(.decreaseTextFontSize)
    }
    textEditorOverlayView.onIncreaseFontSize = { [weak self] in
        self?.performCommand(.increaseTextFontSize)
    }
    syncTextEditorPresentation()
}

guard
    let inlineEditState = presentationInlineEditState,
    inlineEditState.mode == .text,
    let textItem = editorSession.activeInlineTextItem
else {
    // ...
}

let decreaseFontSizeDescriptor = commandDescriptor(for: .decreaseTextFontSize)
let increaseFontSizeDescriptor = commandDescriptor(for: .increaseTextFontSize)
isSyncingTextEditorContent = true
textEditorOverlayView.apply(
    text: inlineEditState.draftText,
    style: textItem.style,
    canDecreaseFontSize: decreaseFontSizeDescriptor.isEnabled,
    canIncreaseFontSize: increaseFontSizeDescriptor.isEnabled
)
isSyncingTextEditorContent = false

case .decreaseTextFontSize:
    performCommand(.decreaseTextFontSize)
case .increaseTextFontSize:
    performCommand(.increaseTextFontSize)
```

## 修改四：补字号命令的命令级回归测试

### 修改前

- `CanvasCommandPolicyParityTests` 只覆盖了 `addTextItem`、`commitTextEdit`、`import`、`undo/redo`、selection mutation 等既有命令。
- 没有测试能直接证明：
  - 字号命令在编辑模式可执行
  - 阅读模式会正确禁用
  - 字号命令不会提前结束 inline text edit
  - 字号调整进入 `history`，且能 `undo / redo`

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift（修改前）
// 函数名: testAddTextDescriptorAndExecutorMatchPolicyInEditingMode() / testCommitTextDescriptorResetsActiveStateWhenPolicyBlocksInReadingMode()
// 功能说明: 修改前 command parity 测试只覆盖既有命令，没有覆盖 inline text font size 命令的策略、执行与历史语义。
func testAddTextDescriptorAndExecutorMatchPolicyInEditingMode() {
    // ...
}

func testCommitTextDescriptorResetsActiveStateWhenPolicyBlocksInReadingMode() {
    // ...
}
```

### 修改后

- 新增：
  - `testInlineTextFontSizeCommandsDoNotForceInlineCommit()`
  - `testInlineTextFontSizeDescriptorAndExecutorMatchPolicyInEditingMode()`
  - `testInlineTextFontSizeDescriptorResetsWhenPolicyBlocksInReadingMode()`
  - `testIncreaseTextFontSizeCommandRecordsHistoryAndSupportsUndoRedo()`
- 这样 phase 6 的核心语义都进入自动化保护。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testInlineTextFontSizeCommandsDoNotForceInlineCommit() / testInlineTextFontSizeDescriptorAndExecutorMatchPolicyInEditingMode() / testInlineTextFontSizeDescriptorResetsWhenPolicyBlocksInReadingMode() / testIncreaseTextFontSizeCommandRecordsHistoryAndSupportsUndoRedo()
// 功能说明: 修改后新增字号命令专项回归测试，锁定“不强制 commit”“编辑模式可执行”“阅读模式被 gate”“history/undo/redo 生效”四个关键行为。
func testInlineTextFontSizeCommandsDoNotForceInlineCommit() {
    XCTAssertFalse(CanvasCommand.decreaseTextFontSize.shouldCommitActiveInlineTextBeforeExecuting)
    XCTAssertFalse(CanvasCommand.increaseTextFontSize.shouldCommitActiveInlineTextBeforeExecuting)
    XCTAssertTrue(CanvasCommand.undo.shouldCommitActiveInlineTextBeforeExecuting)
}

func testInlineTextFontSizeDescriptorAndExecutorMatchPolicyInEditingMode() throws {
    let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
    let executor = CanvasCommandExecutor(session: session)
    XCTAssertNotNil(session.addTextItem())
    // ... 校验 descriptor.isEnabled / executor.canExecute / policy == .allow ...
}

func testInlineTextFontSizeDescriptorResetsWhenPolicyBlocksInReadingMode() {
    let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
    let executor = CanvasCommandExecutor(session: session)
    XCTAssertNotNil(session.addTextItem())
    session.workspaceMode = .reading
    // ... 校验 descriptor 失效 / executor.canExecute == false ...
}

func testIncreaseTextFontSizeCommandRecordsHistoryAndSupportsUndoRedo() throws {
    let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
    let executor = CanvasCommandExecutor(session: session)
    let item = try XCTUnwrap(
        session.addTextItem(
            text: "Seed",
            style: CanvasTextStyle(fontSize: 20)
        )
    )
    let originalItem = try XCTUnwrap(session.scene.textItem(withID: item.id))

    XCTAssertTrue(session.updateTextEditDraft("A much longer edited draft"))
    XCTAssertNotNil(executor.execute(.increaseTextFontSize))

    let resizedItem = try XCTUnwrap(session.scene.textItem(withID: item.id))
    XCTAssertGreaterThan(resizedItem.style.fontSize, originalItem.style.fontSize)

    XCTAssertNotNil(executor.execute(.commitTextEdit))
    XCTAssertNotNil(executor.execute(.undo))
    XCTAssertNotNil(executor.execute(.redo))

    let redoneItem = try XCTUnwrap(session.scene.textItem(withID: item.id))
    XCTAssertEqual(redoneItem.style, resizedItem.style)
    XCTAssertEqual(redoneItem.size, resizedItem.size)
}
```

## 验证情况

- `ReadLints` 检查结果：本次改动未引入新的诊断问题。
- `macOS` 定向测试通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionTextContentDrivenTests -only-testing:MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests test`
- `iOS` scheme 构建通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS' build`

## 当前阶段结论

- `phase 6` 已把字号入口放到了 inline text editor 附近，但真正的状态变更仍然全部走 shared command / session 链路，没有长出 controller 私有写口。
- 文字在编辑期间的字号调整现在会同步更新 `style.fontSize`、按当前 `draftText` 重算 intrinsic `size`，并进入 `history / undo / redo / autosave`。
- iOS 与 macOS 的 overlay / controller 语义已保持一致；下一阶段可以继续推进 `phase 7`，集中补自动化与手工回归验证清单。
