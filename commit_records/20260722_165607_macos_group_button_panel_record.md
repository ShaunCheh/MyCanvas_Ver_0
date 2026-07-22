# 20260722_165607_macos_group_button_panel_record

## 记录范围

本记录基于当前 `git status --short` 与 `git diff -- MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 整理，不包含原始 diff。

当前 changes：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 当前工作区变更
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
```

本次修改只涉及 macOS 画布控制器：

- 在 macOS 阅读/编辑按钮左侧新增独立 group 按钮。
- 点击 group 按钮后，在按钮下方显示 group 列表 panel。
- panel 内第一项为“添加group”，点击后调用已有 `editorSession.appendGroup(recordHistory: true)` 新增 group，并刷新列表。
- panel 内部使用 `NSScrollView` 支持 group 列表 overflow 滚动。
- group 按钮与 panel 加入 chrome blocker，避免与右侧工具条布局冲突。
- board 加载、新建、恢复、运行命令后同步刷新 group list。

## 修改前

macOS 顶部 chrome 只有返回按钮和阅读/编辑按钮，没有 iOS 已有的 group 独立入口。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - setupViewHierarchy()
chromeOverlayView.addSubview(contextMenuHostView)
chromeOverlayView.addSubview(backButton)
chromeOverlayView.addSubview(workspaceModeButton)
registerToolbarButtons()
```

布局约束里也只处理 `workspaceModeButton`，没有与其相邻的 group button，也没有下拉/浮层 panel。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - setupConstraints()
workspaceModeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
workspaceModeButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
workspaceModeButton.widthAnchor.constraint(equalToConstant: 44),
workspaceModeButton.heightAnchor.constraint(equalToConstant: 44),
textEditorOverlayView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
```

toolbar 布局 blocker 只把返回按钮和阅读/编辑按钮作为 chrome 占位，没有把 group panel 作为避让区域。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - baseChromeBlockersForToolbarLayout()
appendChromeBlocker(
    kind: .modeToggle,
    for: workspaceModeButton,
    to: &chromeBlockers
)
return chromeBlockers
```

## 修改后

新增 macOS group 按钮和 group panel 属性。按钮使用 `rectangle.3.group` SF Symbol，panel 默认隐藏。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSViewController properties
private let groupListButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.title = ""
    button.toolTip = "Canvas groups"
    button.wantsLayer = true
    button.layer?.cornerRadius = 22
    button.layer?.masksToBounds = true
    button.layer?.borderWidth = 1
    button.contentTintColor = .labelColor
    if let image = NSImage(
        systemSymbolName: "rectangle.3.group",
        accessibilityDescription: "Canvas groups"
    ) {
        button.image = image
        button.imagePosition = .imageOnly
    }
    return button
}()
private let groupListView: macOSCanvasGroupListView = {
    let view = macOSCanvasGroupListView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    return view
}()
```

group button 与 panel 被挂到 chrome overlay，并放在阅读/编辑按钮左侧；panel 在按钮下方右对齐，宽度优先 280，高度 280。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - setupViewHierarchy() / setupConstraints()
chromeOverlayView.addSubview(backButton)
chromeOverlayView.addSubview(groupListButton)
chromeOverlayView.addSubview(workspaceModeButton)
chromeOverlayView.addSubview(groupListView)

groupListButton.trailingAnchor.constraint(equalTo: workspaceModeButton.leadingAnchor, constant: -12),
groupListButton.topAnchor.constraint(equalTo: workspaceModeButton.topAnchor),
groupListButton.widthAnchor.constraint(equalToConstant: 44),
groupListButton.heightAnchor.constraint(equalToConstant: 44),
groupListView.topAnchor.constraint(equalTo: groupListButton.bottomAnchor, constant: 8),
groupListView.trailingAnchor.constraint(equalTo: groupListButton.trailingAnchor),
groupListView.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
groupListView.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, constant: -40),
preferredGroupListWidth,
groupListView.heightAnchor.constraint(equalToConstant: 280),
```

group button 与 panel 也加入 chrome blocker，避免右侧工具条或其他 chrome 区域覆盖 panel。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - baseChromeBlockersForToolbarLayout()
appendChromeBlocker(
    kind: .groupList,
    for: groupListButton,
    to: &chromeBlockers
)
appendChromeBlocker(
    kind: .groupList,
    for: groupListView,
    to: &chromeBlockers
)
```

新增 group 入口的 setup、展示刷新、点击展开/收起，以及“添加group”处理。新增 group 时使用既有 session 数据层，不重新实现 group 数据结构。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - setupGroupListButton() / updateGroupListPresentation()
private func setupGroupListButton() {
    groupListButton.target = self
    groupListButton.action = #selector(handleGroupListButtonClick)
    groupListView.onAddGroupRequested = { [weak self] in
        self?.handleAddGroupRequested()
    }
    updateGroupListPresentation()
}

private func updateGroupListPresentation() {
    groupListView.render(groups: editorSession.groups)
    groupListView.isHidden = isGroupListVisible == false
    groupListButton.toolTip = isGroupListVisible
        ? "Canvas groups: Expanded"
        : "Canvas groups: Collapsed"

    let appearance = view.effectiveAppearance
    PlatformLayerAppearance.performWithoutAnimations {
        groupListButton.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
            isGroupListVisible
                ? NSColor.tertiaryLabelColor.withAlphaComponent(0.18)
                : NSColor.controlBackgroundColor.withAlphaComponent(0.92),
            for: appearance
        )
        groupListButton.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
            NSColor.separatorColor.withAlphaComponent(0.35),
            for: appearance
        )
    }
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - handleGroupListButtonClick() / handleAddGroupRequested()
@objc
private func handleGroupListButtonClick() {
    isGroupListVisible.toggle()
    updateGroupListPresentation()
    updateChromeOverlayLayout()
}

private func handleAddGroupRequested() {
    _ = editorSession.appendGroup(recordHistory: true)
    updateGroupListPresentation()
    updateInlineEditButtonsAppearance()
    refreshCanvas(reason: "add group")
}
```

新增 `macOSCanvasGroupListView`，用自定义 `NSView` 作为 panel，内部通过 `NSScrollView` 承载 `NSStackView`。第一行固定为“添加group”，空列表显示 `No groups yet`，已有 group 显示标题、item 数量和 description。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.render(groups:)
func render(groups: [CanvasItemGroup]) {
    renderedGroups = groups
    stackView.arrangedSubviews.forEach { view in
        stackView.removeArrangedSubview(view)
        view.removeFromSuperview()
    }

    stackView.addArrangedSubview(makeAddGroupRow())

    if groups.isEmpty {
        stackView.addArrangedSubview(makeEmptyStateLabel())
    } else {
        for group in groups {
            stackView.addArrangedSubview(makeGroupRow(for: group))
        }
    }

    updateDocumentLayout()
}
```

panel 的文档高度会根据当前宽度重新计算，确保文本换行后列表仍能正确滚动。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.updateDocumentLayout()
private func updateDocumentLayout() {
    let contentWidth = max(scrollView.contentView.bounds.width, 0)
    let stackWidth = max(contentWidth - 24, 0)
    stackView.frame = CGRect(
        x: 12,
        y: 12,
        width: stackWidth,
        height: max(stackView.frame.height, 1)
    )
    stackView.layoutSubtreeIfNeeded()
    let stackHeight = max(stackView.fittingSize.height, 0)

    stackView.frame = CGRect(
        x: 12,
        y: 12,
        width: stackWidth,
        height: stackHeight
    )

    documentView.frame = CGRect(
        x: 0,
        y: 0,
        width: contentWidth,
        height: max(
            stackView.frame.maxY + 12,
            scrollView.contentView.bounds.height
        )
    )
}
```

## 刷新时机

本次还把 `updateGroupListPresentation()` 接入以下路径，保证 macOS panel 与当前 board/session 的 group 状态一致：

- `performCommand(_:)` 执行后。
- `restoreBoard(withID:)` 加载 board 后。
- `startNewBoard()` 新建 board 后。
- `restorePersistedBoardIfPossible()` 恢复持久化 board 后。
- `applyBoardRuntimeState(_:)` 应用 runtime state 后。
- `updateAppearance()` 深浅色/外观变化后。

## 验证

已运行 macOS build，结果通过。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 验证命令
xcodebuild -scheme MyCanvas_Ver_0 -destination 'platform=macOS' build > /tmp/mycanvas_macos_group_build.log 2>&1
```

已运行 IDE lint 诊断，`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 无 linter errors。

## 备注

本次没有提交代码。当前记录文件用于描述刚刚的 macOS group button / panel UI 修改。
