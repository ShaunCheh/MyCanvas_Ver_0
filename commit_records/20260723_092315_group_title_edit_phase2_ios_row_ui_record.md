# 20260723_092315_group_title_edit_phase2_ios_row_ui_record

## 记录范围

本记录如实对应刚刚实施的 `group_title_edit_e3a274eb` 阶段 2：iOS group list 每行增加右侧圆形编辑图标按钮，并补齐 inline title text field 的 UI 支撑。

本次实际修改的代码文件：

- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`

当前 `git status` 中还存在 `.cursor/plans/group_title_edit_e3a274eb.plan.md` 的既有修改；本记录只覆盖刚刚阶段 2 的运行时代码改动。

## 修改前

### controller 没有 group title 编辑态

修改前，iOS controller 只记录 group list 是否展开，没有记录当前哪一个 group title 正在编辑。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前只保存 group list 展开状态，没有当前正在编辑的 group title id。
// 函数名：iOSViewController state properties
private var isTransitionInteractionFrozen = false
private var transitionChromeHidden = false
private var isGroupListVisible = false
private var lastPinchDispatchTimestamp: TimeInterval?
```

### group list render 不接收编辑态

修改前，`updateGroupListPresentation()` 只把 groups 传给 group list view，row 无法根据 editing id 切换 title label / text field。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前渲染 group list 时没有传入当前编辑中的 group id。
// 函数名：iOSViewController.updateGroupListPresentation()
private func updateGroupListPresentation() {
    groupListView.render(groups: editorSession.groups)
    groupListView.isHidden = isGroupListVisible == false
    groupListButton.isSelected = isGroupListVisible
    groupListButton.accessibilityValue = isGroupListVisible ? "Expanded" : "Collapsed"
}
```

### `iOSCanvasGroupListView` 只支持添加 group

修改前，group list view 只有 `onAddGroupRequested`，没有 edit title 或 submit title 的回调入口。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 group list view 只有添加 group 的 callback。
// 函数名：iOSCanvasGroupListView properties
private final class iOSCanvasGroupListView: UIView {
    var onAddGroupRequested: (() -> Void)?
}
```

### group row 只有垂直文本内容

修改前，每个 group row 只有 title、metadata、description 的垂直文本布局，没有右侧编辑按钮，也没有 inline text field。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 row 只渲染 title label 和元信息，没有右侧编辑按钮。
// 函数名：iOSCanvasGroupListView.makeGroupRow(for:)
private func makeGroupRow(for group: CanvasItemGroup) -> UIView {
    let container = UIView()
    container.backgroundColor = .tertiarySystemBackground
    container.layer.cornerRadius = 12
    container.layer.cornerCurve = .continuous

    let rowStack = UIStackView()
    rowStack.translatesAutoresizingMaskIntoConstraints = false
    rowStack.axis = .vertical
    rowStack.alignment = .fill
    rowStack.spacing = 4

    let titleLabel = UILabel()
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 2
    titleLabel.text = group.displayTitle

    rowStack.addArrangedSubview(titleLabel)
    rowStack.addArrangedSubview(metadataLabel)
    container.addSubview(rowStack)
    return container
}
```

## 修改后

### controller 增加 `editingGroupTitleID`

新增 `editingGroupTitleID`，用于记录当前应该进入 inline edit UI 的 group id。阶段 2 只建立状态和渲染通道，真正点击按钮设置该状态会在阶段 3 接入。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：保存当前正在编辑 title 的 group id，驱动 group row title label/text field 切换。
// 函数名：iOSViewController state properties
private var isTransitionInteractionFrozen = false
private var transitionChromeHidden = false
private var isGroupListVisible = false
private var editingGroupTitleID: CanvasItemGroupID?
private var lastPinchDispatchTimestamp: TimeInterval?
```

### group list render 接收编辑态

`updateGroupListPresentation()` 现在把 `editingGroupTitleID` 传给 `groupListView.render(...)`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：渲染 group list 时传入当前编辑中的 group id。
// 函数名：iOSViewController.updateGroupListPresentation()
private func updateGroupListPresentation() {
    groupListView.render(
        groups: editorSession.groups,
        editingGroupTitleID: editingGroupTitleID
    )
    groupListView.isHidden = isGroupListVisible == false
    groupListButton.isSelected = isGroupListVisible
    groupListButton.accessibilityValue = isGroupListVisible ? "Expanded" : "Collapsed"
}
```

### `iOSCanvasGroupListView` 增加编辑与提交 callbacks

`iOSCanvasGroupListView` 现在 conform `UITextFieldDelegate`，并新增编辑请求和 title 提交的 callback。阶段 2 只补齐 view 层出口，实际接入 `renameGroup(...)` 留到阶段 3。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：为 group title inline edit 补齐 view 层 callback 出口。
// 函数名：iOSCanvasGroupListView callbacks
private final class iOSCanvasGroupListView: UIView, UITextFieldDelegate {
    var onAddGroupRequested: (() -> Void)?
    var onEditGroupTitleRequested: ((CanvasItemGroupID) -> Void)?
    var onGroupTitleSubmitted: ((CanvasItemGroupID, String) -> Void)?
}
```

### render 支持编辑行 focus

`render(groups:editingGroupTitleID:)` 会判断每个 row 是否处于编辑态。若当前行渲染出 `UITextField`，会在下一轮主队列自动 focus 并 select all。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：按 editingGroupTitleID 渲染编辑态 row，并在 render 后聚焦当前 text field。
// 函数名：iOSCanvasGroupListView.render(groups:editingGroupTitleID:)
func render(
    groups: [CanvasItemGroup],
    editingGroupTitleID: CanvasItemGroupID?
) {
    var focusedTitleTextField: UITextField?
    // ... 清空旧 row 并添加 Add Group row

    for group in groups {
        let isEditingTitle = group.id == editingGroupTitleID
        stackView.addArrangedSubview(
            makeGroupRow(
                for: group,
                isEditingTitle: isEditingTitle,
                focusedTitleTextField: &focusedTitleTextField
            )
        )
    }

    if let focusedTitleTextField {
        DispatchQueue.main.async { [weak focusedTitleTextField] in
            focusedTitleTextField?.becomeFirstResponder()
            focusedTitleTextField?.selectAll(nil)
        }
    }
}
```

### group row 改为左内容 + 右圆形编辑按钮

`makeGroupRow(...)` 现在改为水平 `outerStack`：左侧是 title/metadata/description，右侧是圆形 edit icon button。非编辑态仍显示 `UILabel`，编辑态则显示 `iOSCanvasGroupTitleTextField`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：group row 支持 title label/text field 切换，并在右侧渲染圆形编辑按钮。
// 函数名：iOSCanvasGroupListView.makeGroupRow(for:isEditingTitle:focusedTitleTextField:)
private func makeGroupRow(
    for group: CanvasItemGroup,
    isEditingTitle: Bool,
    focusedTitleTextField: inout UITextField?
) -> UIView {
    let outerStack = UIStackView()
    outerStack.axis = .horizontal
    outerStack.alignment = .top
    outerStack.spacing = 8

    let rowStack = UIStackView()
    rowStack.axis = .vertical
    rowStack.alignment = .fill
    rowStack.spacing = 4

    if isEditingTitle {
        let titleTextField = iOSCanvasGroupTitleTextField(groupID: group.id)
        titleTextField.text = group.title
        titleTextField.delegate = self
        rowStack.addArrangedSubview(titleTextField)
        focusedTitleTextField = titleTextField
    } else {
        let titleLabel = UILabel()
        titleLabel.text = group.displayTitle
        rowStack.addArrangedSubview(titleLabel)
    }

    let editButton = makeEditGroupTitleButton(for: group)
    outerStack.addArrangedSubview(rowStack)
    outerStack.addArrangedSubview(editButton)
    return container
}
```

### 新增圆形 pencil edit button

每行右侧新增圆形系统图标按钮，只显示 `pencil` 图标，不显示文字，并提供 accessibility label。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：创建每个 group row 右侧的圆形编辑图标按钮。
// 函数名：iOSCanvasGroupListView.makeEditGroupTitleButton(for:)
private func makeEditGroupTitleButton(for group: CanvasItemGroup) -> UIButton {
    let button = UIButton(type: .system)
    button.backgroundColor = .systemBackground
    button.layer.cornerRadius = 16
    button.layer.borderWidth = 1
    button.layer.borderColor = UIColor.separator.cgColor
    button.accessibilityLabel = "Edit group name"

    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "pencil")
    configuration.baseForegroundColor = .label
    button.configuration = configuration
    button.addAction(
        UIAction { [weak self] _ in
            self?.onEditGroupTitleRequested?(group.id)
        },
        for: .touchUpInside
    )
    return button
}
```

### 新增携带 groupID 的 title text field

新增 `iOSCanvasGroupTitleTextField`，用于让 text field delegate 在提交时知道当前编辑的是哪个 group。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：UITextField 携带 group id，供 title submit callback 回传目标 group。
// 函数名：iOSCanvasGroupTitleTextField
private final class iOSCanvasGroupTitleTextField: UITextField {
    let groupID: CanvasItemGroupID

    init(groupID: CanvasItemGroupID) {
        self.groupID = groupID
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        return nil
    }
}
```

## 行为变化

- iOS group list row 结构已具备右侧圆形 pencil 编辑按钮。
- iOS group list row 已具备 title label / inline text field 的切换能力。
- text field 支持 Return 和失焦时把 group id + 文本交给 `onGroupTitleSubmitted` callback。
- 本阶段尚未把 edit button callback 接到 controller 的 `editingGroupTitleID`，也尚未调用 `editorSession.renameGroup(...)`；这些属于阶段 3。

## 验证记录

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：检查 iOSViewController.swift 的 linter 诊断。
ReadLints: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 iOS Simulator target 编译通过。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' build
```
