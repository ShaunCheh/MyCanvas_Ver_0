# 20260723_093550_group_title_edit_phase4_macos_record

## 记录范围

本记录如实对应刚刚实施的 `group_title_edit_e3a274eb` 阶段 4：macOS group list 对齐 iOS 的 group title inline edit，实现每行右侧圆形 pencil 按钮、编辑态 `NSTextField`、Return/失焦提交和刷新流程。

本次实际修改的代码文件：

- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前 `git status` 中还存在 `.cursor/plans/group_title_edit_e3a274eb.plan.md` 的既有修改；本记录只覆盖刚刚阶段 4 的运行时代码改动。

## 修改前

### macOS controller 没有 group title 编辑态

修改前，macOS controller 只记录 group list 是否展开，没有保存当前正在编辑 title 的 group id。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前只保存 group list 展开状态，没有当前 group title 编辑态。
// 函数名：macOSViewController state properties
private var isTransitionInteractionFrozen = false
private var isGroupListVisible = false
private var keyboardShortcutObservationMonitor: Any?
```

### group list button 只接入 add group

修改前，`setupGroupListButton()` 只接入添加 group 的 callback，没有 edit title 和 submit title 的 callback。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前只接入添加 group callback。
// 函数名：macOSViewController.setupGroupListButton()
private func setupGroupListButton() {
    groupListButton.target = self
    groupListButton.action = #selector(handleGroupListButtonClick)
    groupListView.onAddGroupRequested = { [weak self] in
        self?.handleAddGroupRequested()
    }
    updateGroupListPresentation()
}
```

### macOS group list render 不接收 editing id

修改前，`updateGroupListPresentation()` 只把 groups 传给 group list view，row 无法切换为编辑态。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前 macOS group list 渲染时没有当前编辑 group id。
// 函数名：macOSViewController.updateGroupListPresentation()
private func updateGroupListPresentation() {
    groupListView.render(groups: editorSession.groups)
    groupListView.isHidden = isGroupListVisible == false
    groupListButton.toolTip = isGroupListVisible
        ? "Canvas groups: Expanded"
        : "Canvas groups: Collapsed"
}
```

### macOS group row 只有文本内容

修改前，macOS group row 只有 title、metadata、description 的垂直文本布局，没有右侧编辑按钮，也没有 inline `NSTextField`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前 macOS group row 只渲染标题和元信息，不含编辑按钮或可编辑文本框。
// 函数名：macOSCanvasGroupListView.makeGroupRow(for:)
private func makeGroupRow(for group: CanvasItemGroup) -> NSView {
    let container = macOSCanvasChromeOverlayView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.wantsLayer = true
    container.layer?.cornerRadius = 12

    let rowStack = NSStackView()
    rowStack.orientation = .vertical
    rowStack.alignment = .leading
    rowStack.spacing = 4

    let titleLabel = NSTextField(labelWithString: group.displayTitle)
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = .labelColor

    rowStack.addArrangedSubview(titleLabel)
    rowStack.addArrangedSubview(metadataLabel)
    container.addSubview(rowStack)
    return container
}
```

## 修改后

### controller 增加编辑态与 callback 接入

macOS controller 新增 `editingGroupTitleID`，并在 `setupGroupListButton()` 中接入 edit/submit callbacks。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：保存当前正在编辑 title 的 group id。
// 函数名：macOSViewController state properties
private var isTransitionInteractionFrozen = false
private var isGroupListVisible = false
private var editingGroupTitleID: CanvasItemGroupID?
private var keyboardShortcutObservationMonitor: Any?
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：连接 macOS group list view 的 edit 和 submit callbacks。
// 函数名：macOSViewController.setupGroupListButton()
private func setupGroupListButton() {
    groupListButton.target = self
    groupListButton.action = #selector(handleGroupListButtonClick)
    groupListView.onAddGroupRequested = { [weak self] in
        self?.handleAddGroupRequested()
    }
    groupListView.onEditGroupTitleRequested = { [weak self] groupID in
        self?.beginGroupTitleEditing(groupID: groupID)
    }
    groupListView.onGroupTitleSubmitted = { [weak self] groupID, title in
        self?.commitGroupTitleEditing(groupID: groupID, title: title)
    }
    updateGroupListPresentation()
}
```

### render 传入当前 editing group id

`updateGroupListPresentation()` 现在会把 `editingGroupTitleID` 传给 group list view。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：渲染 macOS group list 时传入当前编辑中的 group id。
// 函数名：macOSViewController.updateGroupListPresentation()
private func updateGroupListPresentation() {
    groupListView.render(
        groups: editorSession.groups,
        editingGroupTitleID: editingGroupTitleID
    )
    groupListView.isHidden = isGroupListVisible == false
    groupListButton.toolTip = isGroupListVisible
        ? "Canvas groups: Expanded"
        : "Canvas groups: Collapsed"
}
```

### 新增 macOS 编辑/提交 flow

点击 pencil 后进入指定 group 的 title 编辑态。Return 或失焦提交后调用共享 `editorSession.renameGroup(...)`，然后清空编辑态并刷新列表。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：进入指定 group 的 title inline edit 状态。
// 函数名：macOSViewController.beginGroupTitleEditing(groupID:)
private func beginGroupTitleEditing(groupID: CanvasItemGroupID) {
    guard editorSession.group(withID: groupID) != nil else {
        editingGroupTitleID = nil
        updateGroupListPresentation()
        updateChromeOverlayLayout()
        return
    }

    editingGroupTitleID = groupID
    updateGroupListPresentation()
    updateChromeOverlayLayout()
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：提交当前 group title 编辑，写入 editor session 并刷新 group list。
// 函数名：macOSViewController.commitGroupTitleEditing(groupID:title:)
private func commitGroupTitleEditing(
    groupID: CanvasItemGroupID,
    title: String
) {
    guard editingGroupTitleID == groupID else {
        return
    }

    editingGroupTitleID = nil
    _ = editorSession.renameGroup(
        withID: groupID,
        to: title,
        recordHistory: true
    )
    updateGroupListPresentation()
    updateChromeOverlayLayout()
}
```

### `macOSCanvasGroupListView` 支持 editing id 和 callbacks

group list view 现在 conform `NSTextFieldDelegate`，并保存上次渲染的 groups/editing id，确保外观变化重绘时保持编辑态。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS group list view 增加 edit/submit callbacks，并保留 rendered editing id。
// 函数名：macOSCanvasGroupListView properties
private final class macOSCanvasGroupListView: NSView, NSTextFieldDelegate {
    var onAddGroupRequested: (() -> Void)?
    var onEditGroupTitleRequested: ((CanvasItemGroupID) -> Void)?
    var onGroupTitleSubmitted: ((CanvasItemGroupID, String) -> Void)?

    private var renderedGroups: [CanvasItemGroup] = []
    private var renderedEditingGroupTitleID: CanvasItemGroupID?
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：按 editingGroupTitleID 渲染编辑态 row，并在 render 后聚焦 NSTextField。
// 函数名：macOSCanvasGroupListView.render(groups:editingGroupTitleID:)
func render(
    groups: [CanvasItemGroup],
    editingGroupTitleID: CanvasItemGroupID?
) {
    renderedGroups = groups
    renderedEditingGroupTitleID = editingGroupTitleID
    var focusedTitleTextField: NSTextField?
    // ... rebuild rows
    updateDocumentLayout()
    if let focusedTitleTextField {
        DispatchQueue.main.async { [weak self, weak focusedTitleTextField] in
            guard let self, let focusedTitleTextField else {
                return
            }

            self.window?.makeFirstResponder(focusedTitleTextField)
            focusedTitleTextField.selectText(nil)
        }
    }
}
```

### group row 支持圆形 edit button 和 inline `NSTextField`

macOS group row 改为水平布局：左侧文本内容，右侧圆形 pencil 按钮。编辑态时 title label 替换为 `macOSCanvasGroupTitleTextField`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS group row 支持 title label/NSTextField 切换，并在右侧添加圆形编辑按钮。
// 函数名：macOSCanvasGroupListView.makeGroupRow(for:isEditingTitle:focusedTitleTextField:)
private func makeGroupRow(
    for group: CanvasItemGroup,
    isEditingTitle: Bool,
    focusedTitleTextField: inout NSTextField?
) -> NSView {
    let outerStack = NSStackView()
    outerStack.orientation = .horizontal
    outerStack.alignment = .top
    outerStack.spacing = 8

    if isEditingTitle {
        let titleTextField = macOSCanvasGroupTitleTextField(groupID: group.id)
        titleTextField.stringValue = group.title
        titleTextField.delegate = self
        rowStack.addArrangedSubview(titleTextField)
        focusedTitleTextField = titleTextField
    } else {
        let titleLabel = NSTextField(labelWithString: group.displayTitle)
        rowStack.addArrangedSubview(titleLabel)
    }

    let editButton = makeEditGroupTitleButton(for: group)
    outerStack.addArrangedSubview(rowStack)
    outerStack.addArrangedSubview(editButton)
    return container
}
```

### 新增圆形 pencil button 和携带 group id 的控件

新增 `macOSCanvasGroupEditButton` 和 `macOSCanvasGroupTitleTextField`，分别用于携带目标 group id。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：创建 macOS group row 右侧的圆形 pencil 编辑按钮。
// 函数名：macOSCanvasGroupListView.makeEditGroupTitleButton(for:)
private func makeEditGroupTitleButton(for group: CanvasItemGroup) -> NSButton {
    let button = macOSCanvasGroupEditButton(groupID: group.id)
    button.isBordered = false
    button.title = ""
    button.toolTip = "Edit group name"
    button.image = NSImage(
        systemSymbolName: "pencil",
        accessibilityDescription: "Edit group name"
    )
    button.imagePosition = .imageOnly
    button.target = self
    button.action = #selector(handleEditGroupTitleButtonClick(_:))
    return button
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：携带 group id 的 NSTextField，用于 delegate submit 时回传目标 group。
// 函数名：macOSCanvasGroupTitleTextField
private final class macOSCanvasGroupTitleTextField: NSTextField {
    let groupID: CanvasItemGroupID

    init(groupID: CanvasItemGroupID) {
        self.groupID = groupID
        super.init(frame: .zero)
        isEditable = true
        isSelectable = true
        isBordered = true
        drawsBackground = true
        focusRingType = .default
    }
}
```

### Return 和失焦提交

macOS list view 通过 `NSTextFieldDelegate` 处理失焦与 Return，统一调用 `onGroupTitleSubmitted`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：处理 macOS title text field 的失焦和 Return 提交。
// 函数名：macOSCanvasGroupListView.controlTextDidEndEditing / control(_:textView:doCommandBy:)
func controlTextDidEndEditing(_ obj: Notification) {
    guard let textField = obj.object as? NSTextField else {
        return
    }

    submitGroupTitle(from: textField)
}

func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
) -> Bool {
    guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
        return false
    }

    submitGroupTitle(from: control)
    window?.makeFirstResponder(nil)
    return true
}
```

## 行为变化

- macOS group list 每行右侧增加圆形 pencil 编辑图标，无文字。
- 点击 pencil 后当前行 title 变成可编辑 `NSTextField`，并自动 focus/select。
- Return 或失焦会提交到 `editorSession.renameGroup(..., recordHistory: true)`。
- 提交后清空编辑态并刷新 group list。
- 外观变化时，group list 会带着当前 editing id 重新 render。

## 验证记录

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：检查 macOSViewController.swift 的 linter 诊断。
ReadLints: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 macOS target 编译通过。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build
```
