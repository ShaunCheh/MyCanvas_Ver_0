# 20260722_112659_画布 Group 数据结构与 iOS Group 列表按钮记录

## 记录范围

本记录根据当前 `git diff` 与 working tree changes 整理，记录刚刚添加画布内 group 数据结构，以及在 iOS 画布阅读/编辑按钮左侧新增独立 group 列表按钮的修改。

当前涉及文件：

- `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
- `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`

## 1. 添加 board 级 group 数据结构

### 修改前

运行时 board 只有 `items`，没有能表达“多个 item 属于同一个语义集合”的 group 数据。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardRuntimeState
// 功能说明: 修改前 runtime state 只保存画布 item 列表，没有 group 列表。
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
}
```

### 修改后

新增 `CanvasItemGroup`，并在 `BoardRuntimeState` 中增加 `groups`。group 是 board 级语义对象，包含标题、描述和成员 itemID。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: CanvasItemGroup / BoardRuntimeState
// 功能说明: 新增 board 级 group，用于描述一组画布 item 的语义关系。
typealias CanvasItemGroupID = UUID

struct CanvasItemGroup: Equatable, Hashable, Sendable {
    let id: CanvasItemGroupID
    var title: String
    var description: String
    var itemIDs: [CanvasItemID]

    init(
        id: CanvasItemGroupID = UUID(),
        title: String,
        description: String = "",
        itemIDs: [CanvasItemID]
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.itemIDs = Self.normalizedItemIDs(itemIDs)
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled Group" : trimmedTitle
    }
}

struct BoardRuntimeState {
    var items: [CanvasBoardItem]
    var groups: [CanvasItemGroup] = []
}
```

## 2. BoardDocument 升级并持久化 groups

### 修改前

`BoardDocument` 当前格式版本为 `11`，内容状态只比较 `title`、`boardRect`、`items`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardDocument / BoardDocumentContentState
// 功能说明: 修改前文档 schema 没有 groups 字段，contentState 也不会追踪 group 变化。
struct BoardDocument: Codable {
    static let currentFormatVersion = 11

    var workspaceMode: CanvasWorkspaceMode?
    var items: [BoardItemRecord]
}

struct BoardDocumentContentState: Equatable {
    var title: String
    var boardRect: BoardRectRecord?
    var items: [BoardItemRecord]
}
```

### 修改后

`BoardDocument` 升到格式版本 `12`，新增 `groups: [BoardGroupRecord]`，并把 groups 纳入内容状态、编码/解码和内容替换逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardDocument / BoardDocumentContentState / BoardGroupRecord
// 功能说明: 修改后 groups 作为 board 内容的一部分持久化，旧文档缺失 groups 时默认解码为空数组。
struct BoardDocument: Codable {
    static let currentFormatVersion = 12

    var workspaceMode: CanvasWorkspaceMode?
    var groups: [BoardGroupRecord]
    var items: [BoardItemRecord]
}

struct BoardDocumentContentState: Equatable {
    var title: String
    var boardRect: BoardRectRecord?
    var groups: [BoardGroupRecord]
    var items: [BoardItemRecord]
}

struct BoardGroupRecord: Codable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var itemIDs: [UUID]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: init(from:) / encode(to:)
// 功能说明: 解码时兼容旧文档，编码时写出 groups 字段。
groups = try container.decodeIfPresent(
    [BoardGroupRecord].self,
    forKey: .groups
) ?? []

try container.encode(groups, forKey: .groups)
```

## 3. BoardDocumentMapper 支持 group 双向转换

### 修改前

mapper 只把 runtime 的 `items` 转成文档记录，并在读取文档时只恢复 `items`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeDocument(from:) / makeRuntimeState(from:imageLoader:handDrawingPreviewLoader:)
// 功能说明: 修改前 mapper 没有 group 转换路径，保存/加载无法保留 group。
BoardDocument(
    formatVersion: BoardDocument.currentFormatVersion,
    boardID: runtimeState.boardID,
    title: runtimeState.title,
    items: runtimeState.items.map { item in
        makeItemRecord(from: item)
    }
)

let runtimeState = BoardRuntimeState(
    boardID: document.boardID,
    title: document.title,
    items: items,
    workspaceMode: document.workspaceMode ?? .editing
)
```

### 修改后

mapper 新增 `makeGroupRecord(from:)` 和 `makeGroup(from:)`，保存时写出 groups，加载时恢复 groups。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeDocument(from:)
// 功能说明: 保存文档时把 runtime groups 转成 BoardGroupRecord。
BoardDocument(
    formatVersion: BoardDocument.currentFormatVersion,
    boardID: runtimeState.boardID,
    title: runtimeState.title,
    groups: runtimeState.groups.map { group in
        makeGroupRecord(from: group)
    },
    items: runtimeState.items.map { item in
        makeItemRecord(from: item)
    }
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeGroup(from:) / makeGroupRecord(from:)
// 功能说明: 文档记录和 runtime group 之间做结构化双向映射。
private static func makeGroup(
    from groupRecord: BoardGroupRecord
) -> CanvasItemGroup {
    CanvasItemGroup(
        id: groupRecord.id,
        title: groupRecord.title,
        description: groupRecord.description,
        itemIDs: groupRecord.itemIDs
    )
}

private static func makeGroupRecord(
    from group: CanvasItemGroup
) -> BoardGroupRecord {
    BoardGroupRecord(
        id: group.id,
        title: group.title,
        description: group.description,
        itemIDs: group.itemIDs
    )
}
```

## 4. 历史快照和 session 接入 groups

### 修改前

历史快照只包含 items、boardState、interactionState；session 也没有独立持有 groups。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名: BoardHistorySnapshot
// 功能说明: 修改前 undo/redo 快照不包含 group 数据。
struct BoardHistorySnapshot {
    var items: [CanvasBoardItem]
    var boardState: CanvasBoardState?
    var interactionState: CanvasInteractionState
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: CanvasEditorSession
// 功能说明: 修改前 session 只通过 scene 管理 items，没有 board 级 groups。
final class CanvasEditorSession {
    let scene = CanvasScene()
    var camera = CanvasCamera()
    var boardState: CanvasBoardState?
}
```

### 修改后

历史快照增加 `groups`，session 也持有 `groups`；加载、保存、历史恢复都会带上 groups。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名: BoardHistorySnapshot / BoardRuntimeState.replacingDocumentState(with:)
// 功能说明: group 变成文档状态的一部分，可随历史快照一起恢复。
struct BoardHistorySnapshot {
    var items: [CanvasBoardItem]
    var groups: [CanvasItemGroup] = []
    var boardState: CanvasBoardState?
    var interactionState: CanvasInteractionState
}

func replacingDocumentState(
    with snapshot: BoardHistorySnapshot,
    contentUpdatedAt: Date? = nil,
    viewStateUpdatedAt: Date? = nil
) -> BoardRuntimeState {
    BoardRuntimeState(
        boardID: boardID,
        title: title,
        createdAt: createdAt,
        contentUpdatedAt: contentUpdatedAt ?? self.contentUpdatedAt,
        viewStateUpdatedAt: viewStateUpdatedAt ?? self.viewStateUpdatedAt,
        items: snapshot.items,
        groups: snapshot.groups,
        boardState: snapshot.boardState,
        camera: camera,
        interactionState: snapshot.interactionState,
        workspaceMode: workspaceMode
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: applyBoardRuntimeState(_:) / currentBoardRuntimeState(createBoardIfNeeded:)
// 功能说明: session 加载 runtime 时恢复 groups，保存 runtime 时写回 groups。
final class CanvasEditorSession {
    let scene = CanvasScene()
    var groups: [CanvasItemGroup] = []
}

groups = runtimeState.groups

return BoardRuntimeState(
    boardID: activeBoardID,
    title: activeBoardTitle,
    createdAt: activeBoardCreatedAt,
    contentUpdatedAt: activeBoardContentUpdatedAt,
    viewStateUpdatedAt: activeBoardViewStateUpdatedAt,
    items: scene.orderedBoardItems(),
    groups: groups,
    boardState: boardState,
    camera: camera,
    interactionState: interactionState,
    workspaceMode: workspaceMode
)
```

## 5. 删除 item 时清理 group 悬空引用

### 修改前

删除 item 后只规范化 selection，没有 group 引用需要维护。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: deleteItem(withID:recordHistory:) / deleteSelection(recordHistory:)
// 功能说明: 修改前删除 item 后只处理 selection 状态。
guard scene.removeBoardItems(withIDs: [itemID]).isEmpty == false else {
    return false
}

_ = normalizeSelectionAfterMutation()
```

### 修改后

删除 item 或 selection 后，会从所有 groups 中移除对应 itemID；如果某个 group 已无成员，会删除该 group，避免保存悬空引用。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: removeDeletedItemIDsFromGroups(_:)
// 功能说明: 删除 item 后同步清理 group 成员，避免 group 指向不存在的 item。
private func removeDeletedItemIDsFromGroups(
    _ deletedItemIDs: Set<CanvasItemID>
) {
    guard deletedItemIDs.isEmpty == false else {
        return
    }

    groups = groups.compactMap { group in
        var updatedGroup = group
        updatedGroup.itemIDs.removeAll { itemID in
            deletedItemIDs.contains(itemID)
        }
        return updatedGroup.itemIDs.isEmpty ? nil : updatedGroup
    }
}
```

## 6. iOS 顶部新增独立 group 按钮

### 修改前

iOS 顶部右侧只有阅读/编辑切换按钮，group 没有独立入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前 chromeOverlayView 只添加 workspaceModeButton，顶部右侧没有 group 列表按钮。
chromeOverlayView.addSubview(backButton)
chromeOverlayView.addSubview(workspaceModeButton)

workspaceModeButton.trailingAnchor.constraint(
    equalTo: safeAreaLayoutGuide.trailingAnchor,
    constant: -20
)
workspaceModeButton.topAnchor.constraint(
    equalTo: safeAreaLayoutGuide.topAnchor,
    constant: 20
)
```

### 修改后

新增 `groupListButton`，位置在阅读/编辑按钮左侧，且是独立按钮，不和阅读/编辑按钮放在同一个形状里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: groupListButton / setupViewHierarchy() / setupConstraints()
// 功能说明: 顶部右侧新增独立 group 按钮，锚定在 workspaceModeButton 左边。
private let groupListButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.filled()
    configuration.image = UIImage(systemName: "rectangle.3.group")
    configuration.baseBackgroundColor = .secondarySystemBackground
    configuration.baseForegroundColor = .label
    configuration.cornerStyle = .capsule
    configuration.contentInsets = .zero
    button.configuration = configuration
    button.accessibilityLabel = "Canvas groups"
    return button
}()

chromeOverlayView.addSubview(backButton)
chromeOverlayView.addSubview(groupListButton)
chromeOverlayView.addSubview(workspaceModeButton)

groupListButton.trailingAnchor.constraint(
    equalTo: workspaceModeButton.leadingAnchor,
    constant: -12
)
groupListButton.topAnchor.constraint(equalTo: workspaceModeButton.topAnchor)
groupListButton.widthAnchor.constraint(equalToConstant: 44)
groupListButton.heightAnchor.constraint(equalToConstant: 44)
```

## 7. iOS 按钮下方新增可滚动 UIView 列表

### 修改前

点击顶部按钮没有 group 列表，也没有用于承载 overflow 的列表 view。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleWorkspaceModeButtonTap()
// 功能说明: 修改前顶部按钮逻辑只负责阅读/编辑模式切换。
@objc
private func handleWorkspaceModeButtonTap() {
    beginToolbarModeTransition(
        to: workspaceMode == .editing ? .toReading : .toEditing
    )
}
```

### 修改后

新增 `iOSCanvasGroupListView`，它是 UIView，内部用 `UIScrollView + UIStackView` 按列表展示 groups；列表锚定在 group 按钮下方，不居中。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: groupListView / setupConstraints()
// 功能说明: group 列表 view 锚定在按钮下方，宽度优先 280，窄屏时允许收缩。
private let groupListView: iOSCanvasGroupListView = {
    let view = iOSCanvasGroupListView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    return view
}()

groupListView.topAnchor.constraint(
    equalTo: groupListButton.bottomAnchor,
    constant: 8
)
groupListView.trailingAnchor.constraint(equalTo: groupListButton.trailingAnchor)
groupListView.leadingAnchor.constraint(
    greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
    constant: 20
)
groupListView.widthAnchor.constraint(
    lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor,
    constant: -40
)
groupListView.heightAnchor.constraint(equalToConstant: 280)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleGroupListButtonTap() / updateGroupListPresentation()
// 功能说明: 点击 group 按钮切换列表显隐，并用当前 session.groups 渲染列表。
@objc
private func handleGroupListButtonTap() {
    isGroupListVisible.toggle()
    updateGroupListPresentation()
    updateChromeOverlayLayout()
}

private func updateGroupListPresentation() {
    groupListView.render(groups: editorSession.groups)
    groupListView.isHidden = isGroupListVisible == false
    groupListButton.isSelected = isGroupListVisible
    groupListButton.accessibilityValue = isGroupListVisible
        ? "Expanded"
        : "Collapsed"
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: iOSCanvasGroupListView
// 功能说明: UIView 承载 group 列表，内部使用 UIScrollView 支持列表 overflow 滚动。
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

    func render(groups: [CanvasItemGroup]) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if groups.isEmpty {
            stackView.addArrangedSubview(makeEmptyStateLabel())
            return
        }

        for group in groups {
            stackView.addArrangedSubview(makeGroupRow(for: group))
        }
    }
}
```

## 8. Chrome blocker 增加 groupList

### 修改前

chrome layout blocker 只有 back、mode toggle、toolbar、minimap、context menu、selection accessory 等类型。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift
// 函数名: CanvasChromeBlockerKind
// 功能说明: 修改前 layout solver 不知道 group 列表按钮/面板会占据空间。
enum CanvasChromeBlockerKind: String, Sendable {
    case backButton
    case modeToggle
    case toolbar
    case miniMap
    case contextMenu
    case selectionAccessory
}
```

### 修改后

新增 `.groupList`，iOS controller 会把 group 按钮和 group 列表面板都加入 chrome blockers。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift
// 函数名: CanvasChromeBlockerKind
// 功能说明: 让 overlay layout 能识别 group 按钮和 group 列表占用区域。
enum CanvasChromeBlockerKind: String, Sendable {
    case backButton
    case groupList
    case modeToggle
    case toolbar
    case miniMap
    case contextMenu
    case selectionAccessory
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: baseChromeBlockersForToolbarLayout()
// 功能说明: 把 group 按钮和已展开的 group 列表纳入 chrome 占用区域。
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

## 9. 测试新增 group round-trip

### 修改前

`BoardVideoStorageTests` 已覆盖视频 poster 元数据的 document mapper round-trip，但没有覆盖 group 保存/加载。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 函数名: testBoardDocumentMapperRoundTripsVideoPosterMetadata()
// 功能说明: 修改前测试重点是视频 poster metadata，不验证 CanvasItemGroup。
let document = BoardDocumentMapper.makeDocument(from: runtimeState)
let roundTrippedState = try BoardDocumentMapper.makeRuntimeState(
    from: document,
    imageLoader: { _ in
        posterImage
    }
)
```

### 修改后

新增 `testBoardDocumentMapperRoundTripsCanvasItemGroups()`，验证 group 的 id、title、description、itemIDs 会写入文档并恢复回 runtime。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 函数名: testBoardDocumentMapperRoundTripsCanvasItemGroups()
// 功能说明: 验证 group 数据可从 runtime 写入 document，并能从 document 恢复回 runtime。
runtimeState.groups = [
    CanvasItemGroup(
        id: groupID,
        title: "Question Evidence",
        description: "Image answers the markdown question.",
        itemIDs: [itemID]
    )
]

let document = BoardDocumentMapper.makeDocument(from: runtimeState)
let groupRecord = try XCTUnwrap(document.groups.first)

XCTAssertEqual(groupRecord.id, groupID)
XCTAssertEqual(groupRecord.title, "Question Evidence")
XCTAssertEqual(groupRecord.description, "Image answers the markdown question.")
XCTAssertEqual(groupRecord.itemIDs, [itemID])

let roundTrippedState = try BoardDocumentMapper.makeRuntimeState(
    from: document,
    imageLoader: { _ in
        posterImage
    }
)
let roundTrippedGroup = try XCTUnwrap(roundTrippedState.groups.first)

XCTAssertEqual(roundTrippedGroup.id, groupID)
XCTAssertEqual(roundTrippedGroup.title, "Question Evidence")
XCTAssertEqual(roundTrippedGroup.description, "Image answers the markdown question.")
XCTAssertEqual(roundTrippedGroup.itemIDs, [itemID])
```

## 验证情况

已执行并通过：

- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64' -only-testing:MyCanvas_Ver_0Tests/BoardVideoStorageTests`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'`

创建本记录前，当前 `git status --short` 显示本次代码改动为：

- `M MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
- `M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
- `M MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
- `M MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift`
- `M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `M MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`

本次仅创建记录文件，没有提交 commit。
