# 20260723_204404_macos_group_list_row_width_indent_record

## 背景

本次记录对应 macOS group list 的布局修复。

问题现象：group list 中每一行 card 没有撑满列表宽度，短标题行看起来靠右，长标题行更靠左。原因不是文字右对齐，而是 macOS `NSStackView` 的 arranged subview 没有被显式约束为列表宽度，row 容器宽度由内容 intrinsic size 决定。

目标布局：整张 card 左侧按 group tree depth 缩进，右侧保持对齐；每个 arranged row 先撑满列表内容宽度。

## 修改 1：记录 arranged subview 宽度约束

修改前，`macOSCanvasGroupListView` 没有保存 arranged row 的宽度约束。render 时只移除 arranged subviews，不处理 row 宽度。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView properties
private var renderedGroups: [CanvasItemGroup] = []
private var renderedEditingGroupTitleID: CanvasItemGroupID?
private var programmaticFocusGroupTitleID: CanvasItemGroupID?
```

修改后，新增 `arrangedSubviewWidthConstraints`，用于在每次 layout 时重建「arranged subview == stackWidth」约束。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView properties
private var renderedGroups: [CanvasItemGroup] = []
private var renderedEditingGroupTitleID: CanvasItemGroupID?
private var programmaticFocusGroupTitleID: CanvasItemGroupID?
private var arrangedSubviewWidthConstraints: [NSLayoutConstraint] = []
```

## 修改 2：render 前清理旧宽度约束

修改前，render 只清理 arranged subviews。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.render(groups:editingGroupTitleID:)
var focusedTitleTextField: NSTextField?
stackView.arrangedSubviews.forEach { view in
    stackView.removeArrangedSubview(view)
    view.removeFromSuperview()
}
```

修改后，先 deactivate 旧的 width constraints，再移除旧 row，避免约束引用已移除 view。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.render(groups:editingGroupTitleID:)
var focusedTitleTextField: NSTextField?
arrangedSubviewWidthConstraints.forEach { constraint in
    constraint.isActive = false
}
arrangedSubviewWidthConstraints.removeAll()
stackView.arrangedSubviews.forEach { view in
    stackView.removeArrangedSubview(view)
    view.removeFromSuperview()
}
```

## 修改 3：layout 时强制 arranged rows 撑满列表宽度

修改前，`updateDocumentLayout()` 只设置 `stackView.frame.width`，但没有把这个宽度传递给 arranged subviews。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.updateDocumentLayout()
stackView.frame = CGRect(
    x: 12,
    y: 12,
    width: stackWidth,
    height: max(stackView.frame.height, 1)
)
stackView.layoutSubtreeIfNeeded()
```

修改后，在 layout 前调用 `updateArrangedSubviewWidthConstraints(stackWidth:)`，让 add group row、empty state、group row wrapper 都先撑满 `stackWidth`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.updateDocumentLayout()
stackView.frame = CGRect(
    x: 12,
    y: 12,
    width: stackWidth,
    height: max(stackView.frame.height, 1)
)
updateArrangedSubviewWidthConstraints(stackWidth: stackWidth)
stackView.layoutSubtreeIfNeeded()
```

新增 helper 如下：

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.updateArrangedSubviewWidthConstraints(stackWidth:)
private func updateArrangedSubviewWidthConstraints(stackWidth: CGFloat) {
    arrangedSubviewWidthConstraints.forEach { constraint in
        constraint.isActive = false
    }
    arrangedSubviewWidthConstraints = stackView.arrangedSubviews.map { arrangedSubview in
        arrangedSubview.widthAnchor.constraint(equalToConstant: stackWidth)
    }
    NSLayoutConstraint.activate(arrangedSubviewWidthConstraints)
}
```

## 修改 4：整张 group card 按 depth 缩进，右侧对齐

修改前，`makeGroupRow(...)` 直接返回 card container；`depth` 被加到 card 内部内容的 leading padding 上。由于 container 自己没有撑满列表宽度，就造成短标题行更窄、更靠右。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.makeGroupRow(...)
let container = macOSCanvasChromeOverlayView()
container.translatesAutoresizingMaskIntoConstraints = false
container.wantsLayer = true
container.layer?.cornerRadius = 12

container.addSubview(outerStack)
let leadingIndent = 10 + CGFloat(max(depth, 0)) * 18
NSLayoutConstraint.activate([
    outerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
    outerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leadingIndent),
    outerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
    outerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
    editButton.widthAnchor.constraint(equalToConstant: 32),
    editButton.heightAnchor.constraint(equalToConstant: 32)
])

return container
```

修改后，`makeGroupRow(...)` 返回满宽 `rowContainer`，真正有背景的 `container` 放在里面。`container.leading = rowContainer.leading + depth * 18`，`container.trailing = rowContainer.trailing`，实现整张 card 缩进且右侧对齐；card 内部 padding 固定为 10。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.makeGroupRow(...)
let rowContainer = macOSCanvasChromeOverlayView()
rowContainer.translatesAutoresizingMaskIntoConstraints = false

let container = macOSCanvasChromeOverlayView()
container.translatesAutoresizingMaskIntoConstraints = false
container.wantsLayer = true
container.layer?.cornerRadius = 12

rowContainer.addSubview(container)
container.addSubview(outerStack)
let rowIndent = CGFloat(max(depth, 0)) * 18
NSLayoutConstraint.activate([
    container.topAnchor.constraint(equalTo: rowContainer.topAnchor),
    container.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor, constant: rowIndent),
    container.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
    container.bottomAnchor.constraint(equalTo: rowContainer.bottomAnchor),
    outerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
    outerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
    outerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
    outerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
    editButton.widthAnchor.constraint(equalToConstant: 32),
    editButton.heightAnchor.constraint(equalToConstant: 32)
])

return rowContainer
```

## 验证

已执行并通过：

- `ReadLints`：无 linter errors。
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS'`

## 当前变更文件

- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
