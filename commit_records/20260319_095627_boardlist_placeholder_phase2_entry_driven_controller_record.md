# 20260319_095627_boardlist_placeholder_phase2_entry_driven_controller_record

## 记录范围

- 记录目标：落实 `BoardList` 占位项方案的阶段 2，把双端 controller 从“真实 board + Open Board 按钮”切换到 `BoardListEntry` 驱动。
- 本阶段目的 1：移除页头 `Open Board` 按钮链，避免后续继续围绕旧按钮做状态维护。
- 本阶段目的 2：让 collection 在“已选目录但 0 个真实画板”时仍然显示，因为此时应该至少显示 `New Board` 占位项。
- 本阶段目的 3：让 iOS 先接上“单击已有画板直接打开”，macOS 保持“单击选中 / 双击打开已有画板”。
- 本阶段目的 4：只做最小 cell 接口桥接，让 cell 能先消费 `BoardListEntry`，占位项样式本身留给阶段 3。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 本记录不包含：阶段 3 的占位项图标和视觉样式实现。
- 本记录不包含：阶段 4 的交互细化与 placeholder / thumbnail 完整隔离。
- 本记录不包含：git commit。

## 修改一：双端 controller 从 `selectedBoardID` 切到 `selectedEntryID`，并引入 `entries`

### 修改前

- 双端 controller 都直接持有：
- `availableBoards: [BoardCatalogItem]`
- `selectedBoardID: UUID?`
- `selectedBoard: BoardCatalogItem?`
- 数据源、选择同步、打开逻辑全部建立在“collection 里只有真实 board”这个前提上。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.selectedBoardID / selectedBoard
// 功能说明: 修改前 macOS controller 只理解真实 board 的选中态，没有为 New Board 占位项预留 entry 层。
private var availableBoards: [BoardCatalogItem] = []
private var selectedBoardID: UUID?

private var selectedBoard: BoardCatalogItem? {
    if let selectedBoardID {
        return availableBoards.first { $0.boardID == selectedBoardID }
    }

    return availableBoards.first
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.selectedBoardID / selectedBoard
// 功能说明: 修改前 iOS controller 同样只围绕真实 board 数组和 selectedBoardID 工作。
private var availableBoards: [BoardCatalogItem] = []
private var selectedBoardID: UUID?

private var selectedBoard: BoardCatalogItem? {
    if let selectedBoardID {
        return availableBoards.first { $0.boardID == selectedBoardID }
    }

    return availableBoards.first
}
```

### 修改后

- 双端 controller 新增：
- `selectedEntryID: BoardListEntryID?`
- `isSyncingSelection`
- `entries: [BoardListEntry]`
- `entries` 的生成方式固定为：
- `hasSelectedFolder && storageErrorMessage == nil` 时，返回 `[.newBoardPlaceholder] + availableBoards.map { .board($0) }`
- 否则返回 `[]`
- 这样阶段 2 先把“占位项进入数据源”这件事做实，但不提前把样式逻辑塞进 shared preview 链。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.selectedEntryID / entries
// 功能说明: 修改后 macOS controller 通过 BoardListEntry 驱动 collection，New Board 占位项被固定前置在数据源里。
private var availableBoards: [BoardCatalogItem] = []
private var selectedEntryID: BoardListEntryID?
private var hasSelectedFolder = false
private var storageErrorMessage: String?
private var isSyncingSelection = false

private var entries: [BoardListEntry] {
    guard hasSelectedFolder, storageErrorMessage == nil else {
        return []
    }

    return [.newBoardPlaceholder] + availableBoards.map { .board($0) }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.selectedEntryID / entries
// 功能说明: 修改后 iOS controller 与 macOS 保持同一套 entry 语义，后续可统一承接 placeholder 与真实 board 的分支处理。
private var availableBoards: [BoardCatalogItem] = []
private var selectedEntryID: BoardListEntryID?
private var hasSelectedFolder = false
private var storageErrorMessage: String?
private var isSyncingSelection = false

private var entries: [BoardListEntry] {
    guard hasSelectedFolder, storageErrorMessage == nil else {
        return []
    }

    return [.newBoardPlaceholder] + availableBoards.map { .board($0) }
}
```

## 修改二：移除 `Open Board` 按钮链，并把 collection 可见性切到 entry 驱动

### 修改前

- 双端 `actionStackView` 都包含：
- `Select Folder`
- `Grid/List`
- `Open Board`
- `reloadBoardList()` 会调用 `updateOpenCanvasButtonState()`。
- `updateDisplayModeControlState()` 和 `updateCollectionVisibility()` 都依赖 `!availableBoards.isEmpty`。
- 这意味着一旦真实 board 数量为 0，collection 会被直接隐藏，也就无法显示固定首位的 `New Board` 占位项。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.setupViewHierarchy() / reloadBoardList() / updateOpenCanvasButtonState() / updateCollectionVisibility()
// 功能说明: 修改前 macOS 仍然围绕 Open Board 按钮驱动状态，并且在 0 个真实 board 时直接隐藏 collection。
actionStackView.addArrangedSubview(selectFolderButton)
actionStackView.addArrangedSubview(displayModeControl)
actionStackView.addArrangedSubview(openCanvasButton)

private func reloadBoardList() {
    collectionView.reloadData()
    updateCollectionVisibility()
    updateDisplayModeControlState()
    updateOpenCanvasButtonState()
    updateCollectionLayout()
    syncCollectionSelection()
}

private func updateOpenCanvasButtonState() {
    openCanvasButton.title = availableBoards.isEmpty
        ? "Create Board"
        : "Open Board"
    openCanvasButton.isEnabled = true
}

private func updateCollectionVisibility() {
    let shouldShowCollection =
        hasSelectedFolder &&
        storageErrorMessage == nil &&
        !availableBoards.isEmpty
    collectionScrollView.isHidden = !shouldShowCollection
    emptyStateLabel.isHidden = shouldShowCollection
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.setupViewHierarchy() / updateOpenCanvasButtonState() / updateCollectionVisibility()
// 功能说明: 修改前 iOS 侧也依赖 Open Board 按钮和 availableBoards.isEmpty，无法在无真实画板时显示占位项。
actionStackView.addArrangedSubview(selectFolderButton)
actionStackView.addArrangedSubview(displayModeControl)
actionStackView.addArrangedSubview(openCanvasButton)

private func updateOpenCanvasButtonState() {
    var configuration = openCanvasButton.configuration ?? UIButton.Configuration.tinted()
    configuration.title = availableBoards.isEmpty
        ? "Create Board"
        : "Open Board"
    openCanvasButton.configuration = configuration
}

private func updateCollectionVisibility() {
    let shouldShowCollection =
        hasSelectedFolder &&
        storageErrorMessage == nil &&
        !availableBoards.isEmpty
    collectionView.isHidden = !shouldShowCollection
    emptyStateLabel.isHidden = shouldShowCollection
}
```

### 修改后

- 双端都移除了 `openCanvasButton` 属性、`setupActions()` 里的绑定、以及 `handleOpenCanvasButton...` 系列方法。
- `actionStackView` 只保留：
- `Select Folder`
- `Grid/List`
- `reloadBoardList()` 不再调用 `updateOpenCanvasButtonState()`。
- `updateDisplayModeControlState()` 现在只依赖：
- `hasSelectedFolder`
- `storageErrorMessage == nil`
- `updateCollectionVisibility()` 现在只要“已选目录且 storage 正常”就显示 collection，因此 0 个真实 board 时也能显示占位项。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.setupViewHierarchy() / reloadBoardList() / updateDisplayModeControlState() / updateCollectionVisibility()
// 功能说明: 修改后 macOS 去掉 Open Board 按钮，collection 是否显示改为由 folder / storage 状态决定，而不再取决于真实 board 数量。
private func setupViewHierarchy() {
    actionStackView.addArrangedSubview(selectFolderButton)
    actionStackView.addArrangedSubview(displayModeControl)
}

private func reloadBoardList() {
    collectionView.reloadData()
    updateCollectionVisibility()
    updateDisplayModeControlState()
    updateCollectionLayout()
    syncCollectionSelection()
}

private func updateDisplayModeControlState() {
    displayModeControl.isEnabled =
        hasSelectedFolder &&
        storageErrorMessage == nil
}

private func updateCollectionVisibility() {
    let shouldShowCollection =
        hasSelectedFolder &&
        storageErrorMessage == nil
    collectionScrollView.isHidden = !shouldShowCollection
    emptyStateLabel.isHidden = shouldShowCollection

    if let storageErrorMessage {
        emptyStateLabel.stringValue = "Storage unavailable: \(storageErrorMessage)"
        return
    }

    emptyStateLabel.stringValue = "Select a storage folder to load boards."
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.setupViewHierarchy() / updateDisplayModeControlState() / updateCollectionVisibility()
// 功能说明: 修改后 iOS 也同步移除 Open Board 按钮，已选目录后 collection 将始终可见，为 New Board 占位项预留展示空间。
private func setupViewHierarchy() {
    actionStackView.addArrangedSubview(selectFolderButton)
    actionStackView.addArrangedSubview(displayModeControl)
}

private func updateDisplayModeControlState() {
    displayModeControl.isEnabled =
        hasSelectedFolder &&
        storageErrorMessage == nil
}

private func updateCollectionVisibility() {
    let shouldShowCollection =
        hasSelectedFolder &&
        storageErrorMessage == nil
    collectionView.isHidden = !shouldShowCollection
    emptyStateLabel.isHidden = shouldShowCollection

    if let storageErrorMessage {
        emptyStateLabel.text = "Storage unavailable: \(storageErrorMessage)"
        return
    }

    emptyStateLabel.text = "Select a storage folder to load boards."
}
```

## 修改三：新增 `performPrimaryAction(for:)` 与 `entry(at:)`，把打开 / 创建行为切到 entry 语义

### 修改前

- 双端都走旧的“选中 board -> `openSelectedBoardIfNeeded()`”模式。
- iOS 侧 `didSelectItemAt` 只更新 `selectedBoardID`，并不会直接打开已有画板。
- macOS 侧双击逻辑直接按 `availableBoards[indexPath.item]` 取 board。
- 这些实现都默认 collection 里只有真实 board。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.openSelectedBoardIfNeeded() / collectionView(_:didSelectItemAt:)
// 功能说明: 修改前 iOS 单击只做选中同步，实际打开仍依赖已移除的 Open Board 按钮。
private func openSelectedBoardIfNeeded() {
    guard let selectedBoard else {
        onCreateBoard?()
        return
    }

    onOpenBoard?(selectedBoard.boardID)
}

func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    selectedBoardID = availableBoards[indexPath.item].boardID
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.handleCollectionViewDoubleClick(_:)
// 功能说明: 修改前 macOS 双击逻辑直接假设 collection 里每一项都是真实 board。
let location = gestureRecognizer.location(in: collectionView)
guard let indexPath = collectionView.indexPathForItem(at: location) else {
    return
}

selectedBoardID = availableBoards[indexPath.item].boardID
collectionView.selectItems(
    at: Set([indexPath]),
    scrollPosition: []
)
openSelectedBoardIfNeeded()
```

### 修改后

- 双端都新增：
- `entry(at:)`
- `performPrimaryAction(for:)`
- `performPrimaryAction(for:)` 统一分派：
- `.newBoardPlaceholder -> onCreateBoard?()`
- `.board(item) -> onOpenBoard?(item.boardID)`
- iOS：
- `didSelectItemAt` 先更新 `selectedEntryID`，再直接执行 `performPrimaryAction(for:)`
- 阶段 2 先把“已有画板单击打开”接通
- macOS：
- 单击选择时只在选中的是 placeholder 才立即执行创建
- 双击时通过 `entry(at:)` 解析被点击项，并且显式过滤掉 placeholder，只对真实 board 执行打开

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.entry(at:) / performPrimaryAction(for:) / collectionView(_:didSelectItemAt:)
// 功能说明: 修改后 iOS 直接基于 BoardListEntry 分发主动作，真实 board 单击打开，placeholder 单击创建。
private func entry(at indexPath: IndexPath) -> BoardListEntry? {
    guard entries.indices.contains(indexPath.item) else {
        return nil
    }

    return entries[indexPath.item]
}

private func performPrimaryAction(for entry: BoardListEntry) {
    guard hasSelectedFolder, storageErrorMessage == nil else {
        return
    }

    switch entry {
    case .newBoardPlaceholder:
        onCreateBoard?()
    case let .board(item):
        onOpenBoard?(item.boardID)
    }
}

func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard
        isSyncingSelection == false,
        let entry = entry(at: indexPath)
    else {
        return
    }

    selectedEntryID = entry.id
    performPrimaryAction(for: entry)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.performPrimaryAction(for:) / handleCollectionViewDoubleClick(_:) / collectionView(_:didSelectItemsAt:)
// 功能说明: 修改后 macOS 保持“单击选中 / 双击打开已有 board”，同时让占位项单击即可创建。
private func performPrimaryAction(for entry: BoardListEntry) {
    guard hasSelectedFolder, storageErrorMessage == nil else {
        return
    }

    switch entry {
    case .newBoardPlaceholder:
        onCreateBoard?()
    case let .board(item):
        onOpenBoard?(item.boardID)
    }
}

@objc
private func handleCollectionViewDoubleClick(_ gestureRecognizer: NSClickGestureRecognizer) {
    let location = gestureRecognizer.location(in: collectionView)
    guard
        let indexPath = collectionView.indexPathForItem(at: location),
        let entry = entry(at: indexPath),
        entry.isPlaceholder == false
    else {
        return
    }

    selectedEntryID = entry.id
    collectionView.selectItems(
        at: Set([indexPath]),
        scrollPosition: []
    )
    performPrimaryAction(for: entry)
}

func collectionView(
    _ collectionView: NSCollectionView,
    didSelectItemsAt indexPaths: Set<IndexPath>
) {
    guard
        isSyncingSelection == false,
        let indexPath = indexPaths.first,
        let entry = entry(at: indexPath)
    else {
        return
    }

    selectedEntryID = entry.id
    if entry.isPlaceholder {
        performPrimaryAction(for: entry)
    }
}
```

## 修改四：双端 cell 做最小接口桥接，从 `BoardCatalogItem` 切到 `BoardListEntry`

### 修改前

- 双端 cell 的 `configure(...)` 都只接 `BoardCatalogItem`。
- 这会导致 controller 虽然切到了 `BoardListEntry`，但 cell 仍然无法直接承接 placeholder entry。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.configure(with:previewContent:displayMode:)
// 功能说明: 修改前 macOS cell 仍然只接受真实 BoardCatalogItem，无法直接承接 New Board 占位项 entry。
func configure(
    with item: BoardCatalogItem,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    representedBoardID = item.boardID
    representedRevisionToken = item.revisionToken
    titleLabel.stringValue = item.title
    previewView.apply(content: previewContent)
    applyDisplayMode(displayMode)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.configure(with:previewContent:displayMode:)
// 功能说明: 修改前 iOS cell 与 macOS 一样，只接受真实 BoardCatalogItem。
func configure(
    with item: BoardCatalogItem,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    representedBoardID = item.boardID
    representedRevisionToken = item.revisionToken
    titleLabel.text = item.title
    previewView.apply(content: previewContent)
    applyDisplayMode(displayMode)
}
```

### 修改后

- 双端 `configure(...)` 都改成直接接收 `BoardListEntry`。
- 阶段 2 先只桥接：
- `representedBoardID = entry.boardID`
- `representedRevisionToken = entry.revisionToken`
- `title = entry.title`
- `previewContent` 仍由 controller 决定：
- 真实 board 走原有 geometry / thumbnail 链
- placeholder 暂时先喂 `.empty`
- 这样阶段 3 可以只专注做样式，而不需要再回头清理 cell API。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.configure(with:previewContent:displayMode:)
// 功能说明: 修改后 macOS cell 先完成对 BoardListEntry 的接口桥接，placeholder 可以先走空 preview 占位，样式细化留给后续阶段。
func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()
    representedBoardID = entry.boardID
    representedRevisionToken = entry.revisionToken
    titleLabel.stringValue = entry.title
    previewView.apply(content: previewContent)
    applyDisplayMode(displayMode)
    view.layoutSubtreeIfNeeded()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.configure(with:previewContent:displayMode:)
// 功能说明: 修改后 iOS cell 同样切到 BoardListEntry，controller 可以先用 .empty 作为 placeholder 的临时渲染内容。
func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()
    representedBoardID = entry.boardID
    representedRevisionToken = entry.revisionToken
    titleLabel.text = entry.title
    previewView.apply(content: previewContent)
    applyDisplayMode(displayMode)
    contentView.layoutIfNeeded()
}
```

## 阶段结果

- 阶段 2 完成后，双端 `BoardList` 的 controller 主链已经不再依赖 `Open Board` 按钮。
- collection 数据源已经从“只有真实 board”过渡到“`BoardListEntry` 驱动”，`New Board` 占位项已经进入数据链。
- iOS 的已有画板单击打开已接通；macOS 仍保持单击选中、双击打开已有画板。
- 当前 placeholder 还只是“空 preview + New Board 文案”的最小占位，专属视觉样式留给下一阶段。

## 验证情况

- 已对以下文件执行 lint 检查，未发现新增问题：
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 本次没有执行工程级编译验证。
