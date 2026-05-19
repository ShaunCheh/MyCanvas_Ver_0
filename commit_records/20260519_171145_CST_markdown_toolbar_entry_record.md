# 20260519_171145_CST_markdown_toolbar_entry_record

## 记录范围

- 记录内容：
  - 为主工具栏新增独立的 `Markdown` 按钮入口。
  - 让共享 toolbar 模型、toolbar state builder、iOS/macOS 控制器按钮注册与点击分发都识别 `markdown`。
  - 补齐工具栏状态测试，锁住 `markdown` 按钮的顺序、图标和可见性。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift`
- 参考现状：
  - 针对本次 toolbar 入口相关文件，`git status --short` 显示 `6` 个已跟踪修改文件。
  - 针对本次 toolbar 入口相关文件，`git diff --stat` 显示：`6 files changed, 78 insertions(+), 3 deletions(-)`。
- 本记录不包含：
  - markdown block 阶段 6 的存储/渲染/测试收口内容。
  - 任何 git 提交行为。

```bash
# 命令: git status --short -- "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift" "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift" "MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift" "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" "MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift"
 M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
 M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift
```

```bash
# 命令: git diff --stat -- "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift" "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift" "MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift" "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" "MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift"
 .../Shared/Toolbar/CanvasToolbarState.swift        |  1 +
 .../Shared/Toolbar/CanvasToolbarStateBuilder.swift | 16 +++++++++++++++
 .../iOS/Canvas/iOSCanvasToolbarHostView.swift      |  2 +-
 .../Platform/iOS/iOSViewController.swift           | 21 ++++++++++++++++++++
 .../Platform/macOS/macOSViewController.swift       | 18 +++++++++++++++++
 .../CanvasToolbarStateBuilderTests.swift           | 23 ++++++++++++++++++++--
 6 files changed, 78 insertions(+), 3 deletions(-)
```

## 当前 changes 摘要

- `CanvasToolbarItemID` 新增了独立的 `.markdown` case，主工具栏模型层不再只有 `text / handDrawing / importMedia`。
- `CanvasToolbarStateBuilder` 新增 `markdownItemState(session:)`，并把 `markdown` 插入到主工具栏序列中，位置在 `text` 后、`handDrawing` 前。
- iOS 端新增 `markdownButton` 实例、按钮注册、点击处理，同时补了 `iOSCanvasToolbarHostView` 的图标尺寸配置。
- macOS 端新增 `markdownButton` 实例、按钮注册、点击处理。
- `CanvasToolbarStateBuilderTests` 新增 `markdown` 按钮断言，并同步更新已有按钮顺序测试。

## 修改一：让共享 toolbar 模型拥有独立 `markdown` 项

### 1.1 修改前

- `CanvasToolbarItemID` 没有 `.markdown`。
- 即便命令层已有 `addMarkdownItem`，主工具栏也没有合法的 item identity 可以承载它。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift（修改前）
// 函数名: CanvasToolbarItemID
// 功能说明: 修改前主工具栏枚举没有 markdown case，因此 toolbar 不可能渲染 Markdown 按钮。
enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case multiSelect
    case save
    case text
    case handDrawing
    case importMedia
    case undo
    case redo
}
```

### 1.2 修改后

- `CanvasToolbarItemID` 新增 `.markdown`。
- 后续共享 state builder、iOS/macOS controller、toolbar host 都能用同一套枚举标识这个按钮。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名: CanvasToolbarItemID
// 功能说明: 修改后主工具栏模型拥有独立 markdown item，可被共享 state builder 和双端 controller 统一引用。
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

## 修改二：把 `Markdown` 插入共享主工具栏状态

### 2.1 修改前

- `CanvasToolbarStateBuilder.mainToolbarState(...)` 只会把 `text`、`handDrawing` 和 `importMedia` 追加到主工具栏。
- 工具栏状态构建层没有专门的 `markdownItemState(session:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift（修改前）
// 函数名: mainToolbarState(session:saveState:placement:supportsHandDrawingEditing:isMultiSelectModeActive:isImportEnabled:showsBackground:includesHistoryItems:)
// 功能说明: 修改前主工具栏状态只追加 text / handDrawing / import，没有 markdown。
itemStates.append(saveItemState(saveState: saveState))
itemStates.append(textItemState(session: session))
if supportsHandDrawingEditing {
    itemStates.append(handDrawingItemState(session: session))
}
itemStates.append(importItemState(isEnabled: isImportEnabled))
```

### 2.2 修改后

- 新增 `markdownItemState(session:)`，直接复用命令目录中的 `.addMarkdownItem` descriptor。
- `mainToolbarState(...)` 在 `text` 后插入 `markdown`，让它成为主工具栏固定入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名: mainToolbarState(session:saveState:placement:supportsHandDrawingEditing:isMultiSelectModeActive:isImportEnabled:showsBackground:includesHistoryItems:) / markdownItemState(session:)
// 功能说明: 修改后共享 toolbar state builder 会稳定产出 markdown item，并把它放在 text 后、handDrawing 前。
itemStates.append(saveItemState(saveState: saveState))
itemStates.append(textItemState(session: session))
itemStates.append(markdownItemState(session: session))
if supportsHandDrawingEditing {
    itemStates.append(handDrawingItemState(session: session))
}
itemStates.append(importItemState(isEnabled: isImportEnabled))

func markdownItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
    let descriptor = commandCatalog.descriptor(
        for: .addMarkdownItem,
        session: session
    )
    return CanvasToolbarItemState(
        id: .markdown,
        systemImageName: descriptor.systemImageName,
        isEnabled: descriptor.isEnabled,
        isActive: descriptor.isActive,
        accessibilityLabel: "Add markdown",
        visualRole: .accent
    )
}
```

## 修改三：接通 iOS 端主工具栏按钮实例、图标和点击分发

### 3.1 修改前

- iOS controller 只声明了 `textButton` / `handDrawingButton` 等按钮，没有 `markdownButton`。
- `toolbarButtonsByID` 中没有 `.markdown` 键。
- `viewDidLoad()` 里没有 `setupMarkdownButton()`。
- `iOSCanvasToolbarHostView.symbolConfiguration(for:)` 也没有给 `.markdown` 配置图标尺寸。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: toolbarButtonsByID / viewDidLoad() / setupTextButton()
// 功能说明: 修改前 iOS 端只注册 text、handDrawing 等按钮，没有 markdownButton 及其 setup/handler。
private let textButton: UIButton = {
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
        .handDrawing: handDrawingButton,
        .importMedia: importButton
    ]
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupTextButton()
    setupHandDrawingButton()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift（修改前）
// 函数名: symbolConfiguration(for:)
// 功能说明: 修改前 toolbar host 的图标尺寸分支里没有 markdown。
private func symbolConfiguration(
    for itemID: CanvasToolbarItemID
) -> UIImage.SymbolConfiguration {
    switch itemID {
    case .save, .undo, .redo:
        return UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    case .importMedia:
        return UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    case .crop, .multiSelect, .text, .handDrawing:
        return UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    }
}
```

### 3.2 修改后

- 新增 `markdownButton`。
- `toolbarButtonsByID` 加入 `.markdown: markdownButton`。
- `viewDidLoad()` 里增加 `setupMarkdownButton()`。
- 点击 `Markdown` 按钮后直接执行 `performCommand(.addMarkdownItem)`。
- iOS toolbar host 为 `.markdown` 复用了与 `.text` 同级的图标尺寸配置。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: toolbarButtonsByID / viewDidLoad() / setupMarkdownButton() / handleMarkdownButtonTap()
// 功能说明: 修改后 iOS 端拥有独立 markdownButton，并把点击动作接到 addMarkdownItem 命令。
private let markdownButton: UIButton = {
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

override func viewDidLoad() {
    super.viewDidLoad()
    setupTextButton()
    setupMarkdownButton()
    setupHandDrawingButton()
}

private func setupMarkdownButton() {
    markdownButton.addTarget(
        self,
        action: #selector(handleMarkdownButtonTap),
        for: .touchUpInside
    )
    renderToolbar()
}

@objc
private func handleMarkdownButtonTap() {
    performCommand(.addMarkdownItem)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: symbolConfiguration(for:)
// 功能说明: 修改后 iOS toolbar host 会为 markdown 按钮应用与 text 同级的图标尺寸配置。
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

## 修改四：接通 macOS 端主工具栏按钮实例和点击分发

### 4.1 修改前

- macOS controller 同样只有 `textButton` / `handDrawingButton` 等按钮，没有 `markdownButton`。
- `toolbarButtonsByID` 没有 `.markdown`。
- `viewDidLoad()` 和按钮 setup 流程里也没有 markdown 对应步骤。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift（修改前）
// 函数名: toolbarButtonsByID / viewDidLoad() / setupTextButton()
// 功能说明: 修改前 macOS 主工具栏没有 markdownButton，也没有对应的 setup 和 click handler。
private let textButton: NSButton = {
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
        .handDrawing: handDrawingButton,
        .importMedia: importButton
    ]
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupTextButton()
    setupHandDrawingButton()
}
```

### 4.2 修改后

- 新增 `markdownButton`。
- `toolbarButtonsByID` 加入 `.markdown: markdownButton`。
- `viewDidLoad()` 中增加 `setupMarkdownButton()`。
- 点击时执行 `performCommand(.addMarkdownItem)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: toolbarButtonsByID / viewDidLoad() / setupMarkdownButton() / handleMarkdownButtonClick()
// 功能说明: 修改后 macOS 端主工具栏拥有独立 markdownButton，并把点击动作派发到 addMarkdownItem 命令。
private let markdownButton: NSButton = {
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

override func viewDidLoad() {
    super.viewDidLoad()
    setupTextButton()
    setupMarkdownButton()
    setupHandDrawingButton()
}

private func setupMarkdownButton() {
    markdownButton.target = self
    markdownButton.action = #selector(handleMarkdownButtonClick)
    renderToolbar()
}

@objc
private func handleMarkdownButtonClick() {
    performCommand(.addMarkdownItem)
}
```

## 修改五：补齐 toolbar 状态测试，锁住 Markdown 按钮顺序和属性

### 5.1 修改前

- `CanvasToolbarStateBuilderTests` 里的顺序断言没有 `markdown`。
- 也没有独立测试去验证 `markdown` item 的图标、可用性和视觉角色。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift（修改前）
// 函数名: testMainToolbarStateIncludesMultiSelectItem() / testMainToolbarStateIncludesHandDrawingItemWhenSupported()
// 功能说明: 修改前 toolbar 顺序断言里没有 markdown，无法锁住新按钮的存在性和插入位置。
XCTAssertEqual(
    state.items.map(\.id),
    [.undo, .redo, .crop, .multiSelect, .save, .text, .importMedia]
)

XCTAssertEqual(
    state.items.map(\.id),
    [.undo, .redo, .crop, .multiSelect, .save, .text, .handDrawing, .importMedia]
)
```

### 5.2 修改后

- 更新原有顺序断言，把 `markdown` 插在 `text` 后。
- 新增 `testMainToolbarStateIncludesMarkdownItem()`，验证 `systemImageName == "text.alignleft"`、accessibility label 和 visual role。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift
// 函数名: testMainToolbarStateIncludesMultiSelectItem() / testMainToolbarStateIncludesMarkdownItem() / testMainToolbarStateIncludesHandDrawingItemWhenSupported()
// 功能说明: 修改后测试会锁住 markdown 按钮在 toolbar 中的顺序、图标和可用性，避免后续入口被回退。
XCTAssertEqual(
    state.items.map(\.id),
    [.undo, .redo, .crop, .multiSelect, .save, .text, .markdown, .importMedia]
)

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

XCTAssertEqual(
    state.items.map(\.id),
    [.undo, .redo, .crop, .multiSelect, .save, .text, .markdown, .handDrawing, .importMedia]
)
```

## 验证记录

- `ReadLints` 检查本次新增 / 修改文件，无新增 linter 问题。
- `CanvasToolbarStateBuilderTests` 通过。
- iOS Simulator 通用构建通过。

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:"MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests"
** TEST SUCCEEDED **
```

```bash
# 命令: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator'
** BUILD SUCCEEDED **
```
