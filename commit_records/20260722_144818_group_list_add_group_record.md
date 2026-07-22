# 20260722_144818_Group 列表首项添加 Group 记录

## 记录范围

本记录根据当前 `git diff` 与 working tree changes 整理，记录刚刚将 group 列表第一项改为 `添加group`，并在点击后创建 `group 1`、`group 2` 等新 group 的修改。

当前涉及文件：

- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`

## 1. Session 新增创建 group 的数据入口

### 修改前

group 数据已经由 `CanvasEditorSession.groups` 持有，但没有一个明确的 session 方法负责创建新 group、生成默认名称、进入 history、触发 autosave。UI 如果直接改 `groups`，容易绕开现有保存与撤销逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: recordImmediateHistoryChange(from:reason:autosaveReason:)
// 功能说明: 修改前这里之后直接进入编辑能力判断，没有专门的 append group mutation 入口。
@discardableResult
func recordImmediateHistoryChange(
    from beforeSnapshot: BoardHistorySnapshot,
    reason: String,
    autosaveReason: String? = nil
) -> Bool {
    guard historyController.recordChange(
        from: beforeSnapshot,
        to: currentBoardHistorySnapshot(),
        reason: reason
    ) else {
        return false
    }

    if let autosaveReason {
        scheduleAutosave(reason: autosaveReason)
    }

    return true
}

func canBeginTextEdit(withID itemID: CanvasItemID) -> Bool {
    guard inlineEditState == nil else {
        return false
    }
}
```

### 修改后

新增 `appendGroup(...)`。默认名称按当前已有 group 数量生成：添加前没有 group 时是 `group 1`，已有一行时是 `group 2`。当 `recordHistory` 为 `true` 时，会记录 history，并用 `add group` 作为 autosave reason。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: appendGroup(title:description:itemIDs:recordHistory:)
// 功能说明: 创建新的 board 级 group，生成默认名称，并接入 history/autosave。
@discardableResult
func appendGroup(
    title: String? = nil,
    description: String = "",
    itemIDs: [CanvasItemID] = [],
    recordHistory: Bool = false
) -> CanvasItemGroup {
    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    let nextGroupIndex = groups.count + 1
    let group = CanvasItemGroup(
        title: title ?? "group \(nextGroupIndex)",
        description: description,
        itemIDs: itemIDs
    )
    groups.append(group)

    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "add group",
            autosaveReason: "add group"
        )
    }

    return group
}
```

## 2. Group 列表第一项固定为“添加group”

### 修改前

`iOSCanvasGroupListView.render(groups:)` 只渲染已有 groups；如果为空，就只显示 `No groups yet`。列表里没有第一项“添加group”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: iOSCanvasGroupListView.render(groups:)
// 功能说明: 修改前列表只负责展示已有 group，空列表只展示空状态。
func render(groups: [CanvasItemGroup]) {
    stackView.arrangedSubviews.forEach { view in
        stackView.removeArrangedSubview(view)
        view.removeFromSuperview()
    }

    if groups.isEmpty {
        stackView.addArrangedSubview(
            makeEmptyStateLabel()
        )
        return
    }

    for group in groups {
        stackView.addArrangedSubview(
            makeGroupRow(for: group)
        )
    }
}
```

### 修改后

`render(groups:)` 每次都会先插入 `makeAddGroupRow()`，因此列表第一项固定是 `添加group`。如果当前没有 group，添加入口下面仍会显示空状态；如果已有 group，则添加入口下面显示 `group 1`、`group 2` 等列表项。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: iOSCanvasGroupListView.render(groups:)
// 功能说明: 修改后列表首项固定是“添加group”，后面才是已有 group 或空状态。
func render(groups: [CanvasItemGroup]) {
    stackView.arrangedSubviews.forEach { view in
        stackView.removeArrangedSubview(view)
        view.removeFromSuperview()
    }

    stackView.addArrangedSubview(makeAddGroupRow())

    if groups.isEmpty {
        stackView.addArrangedSubview(
            makeEmptyStateLabel()
        )
        return
    }

    for group in groups {
        stackView.addArrangedSubview(
            makeGroupRow(for: group)
        )
    }
}
```

## 3. “添加group”行接入点击回调

### 修改前

`iOSCanvasGroupListView` 没有对外暴露添加 group 的回调，也没有可点击的添加行。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: iOSCanvasGroupListView
// 功能说明: 修改前 group list view 只有 scrollView 和 stackView，没有 add group 回调。
private final class iOSCanvasGroupListView: UIView {
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = true
        return scrollView
    }()

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 10
        return stackView
    }()
}
```

### 修改后

`iOSCanvasGroupListView` 新增 `onAddGroupRequested` 回调，并把 `添加group` 做成 `UIButton` 行。点击该行后调用回调，由 controller 决定如何修改 session。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: iOSCanvasGroupListView / makeAddGroupRow() / handleAddGroupButtonTap()
// 功能说明: 列表第一行是可点击按钮，点击后通知 controller 创建 group。
private final class iOSCanvasGroupListView: UIView {
    var onAddGroupRequested: (() -> Void)?

    private func makeAddGroupRow() -> UIButton {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.cgColor

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "plus.circle.fill")
        configuration.imagePadding = 8
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 10,
            leading: 10,
            bottom: 10,
            trailing: 10
        )
        configuration.attributedTitle = AttributedString(
            "添加group",
            attributes: AttributeContainer([
                .font: UIFont.preferredFont(forTextStyle: .headline)
            ])
        )
        button.configuration = configuration
        button.accessibilityLabel = "Add group"
        button.addTarget(
            self,
            action: #selector(handleAddGroupButtonTap),
            for: .touchUpInside
        )
        return button
    }

    @objc
    private func handleAddGroupButtonTap() {
        onAddGroupRequested?()
    }
}
```

## 4. Controller 处理添加请求并刷新列表

### 修改前

`setupGroupListButton()` 只绑定顶部 group 列表按钮的展开/收起事件，没有绑定列表内部的添加请求。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupGroupListButton()
// 功能说明: 修改前只设置 groupListButton 的点击行为，没有处理列表里的 add group。
private func setupGroupListButton() {
    groupListButton.addTarget(
        self,
        action: #selector(handleGroupListButtonTap),
        for: .touchUpInside
    )
    updateGroupListPresentation()
}
```

### 修改后

controller 设置 `groupListView.onAddGroupRequested`，收到点击后调用 `editorSession.appendGroup(recordHistory: true)`，并刷新列表与 overlay layout。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupGroupListButton() / handleAddGroupRequested()
// 功能说明: 把列表内“添加group”点击转成 session mutation，并刷新 group 列表面板。
private func setupGroupListButton() {
    groupListButton.addTarget(
        self,
        action: #selector(handleGroupListButtonTap),
        for: .touchUpInside
    )
    groupListView.onAddGroupRequested = { [weak self] in
        self?.handleAddGroupRequested()
    }
    updateGroupListPresentation()
}

private func handleAddGroupRequested() {
    _ = editorSession.appendGroup(recordHistory: true)
    updateGroupListPresentation()
    updateChromeOverlayLayout()
}
```

## 5. 执行命令后同步刷新 group 列表

### 修改前

执行命令后只更新 inline edit 按钮外观。如果命令改变了历史状态，例如 undo/redo，group 列表可能不会立即刷新。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performCommand(_:)
// 功能说明: 修改前命令执行后没有同步刷新 group 列表显示。
guard let executionResult = commandExecutor.execute(command) else {
    return
}

updateInlineEditButtonsAppearance()

if let refreshReason = executionResult.refreshReason {
    requestCanvasRefresh(reason: refreshReason)
}
```

### 修改后

命令执行后会调用 `updateGroupListPresentation()`，让 undo/redo 等命令恢复 group 状态后，列表内容也跟着刷新。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performCommand(_:)
// 功能说明: 命令执行后刷新 group 列表，避免 UI 展示与 session.groups 不一致。
guard let executionResult = commandExecutor.execute(command) else {
    return
}

updateInlineEditButtonsAppearance()
updateGroupListPresentation()

if let refreshReason = executionResult.refreshReason {
    requestCanvasRefresh(reason: refreshReason)
}
```

## 验证情况

已执行并通过：

- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'`

创建本记录前，当前 `git status --short` 显示本次代码改动为：

- `M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`

本次仅创建记录文件，没有提交 commit。
