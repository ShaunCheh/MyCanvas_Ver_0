# 20260409_125545_closing_delay_root_fix_phase3_boardlist_cache_targeted_upsert_record

## 记录范围

- 记录内容：`closing_delay_root_fix` 计划的 `Phase 3` 实施记录。
- 记录目标：把 `BoardList` 从“每次 return 都全量覆盖”的模型改成“常驻缓存 + targeted upsert”模型，并把 closing target-only 路径接到单板读取能力上。
- 记录依据：本记录基于当前工作树的 `git diff -- MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift` 与修改后的源码内容整理。
- 对应计划文件：`.cursor/plans/closing_delay_root_fix_97b39f82.plan.md`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本记录不包含：`Phase 2` 已新增的 `BoardCatalogLoader.loadCatalogItem(boardID:)` / `BoardStore.loadBoardDocumentEntry(id:userDefaults:)` 实现细节。
- 本记录不包含：`Phase 4` 中移除 `reloadBoardList()` / `collectionView.reloadData()` 的 target-ready UI 快路径。
- 本记录不包含：git commit。

## 问题背景

- `Phase 2` 之后，底层已经具备“单板 catalog 读取”能力，但 `iOSBoardListViewController` 仍然把 closing return 当成一次全量 `refreshBookmarkStatus()`。
- 这意味着即便已经能按 `boardID` 读取单条 `BoardCatalogItem`，`BoardList` 侧仍然没有：
  - 常驻缓存模型
  - `boardID -> index` 的快速定位
  - 单条 `BoardCatalogItem` 的本地 mutation / upsert 能力
- `Phase 3` 的目标不是直接做 UI 快路径，而是先把数据模型和控制器内部 contract 收敛好，让后续 `Phase 4` 可以只关注“如何不触发全量 reload 也拿到目标 rect”。

## 修改一：把 `availableBoards` 升级为常驻缓存，并补齐 mutation 结果类型

### 修改前

- `availableBoards` 只是普通数组。
- 控制器内部没有显式的 mutation 结果类型，后续如果要做单条插入、更新、移动，只能靠外部临时推断。
- 也没有 `boardID` 的快速定位索引。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: BoardListPreparationMode / availableBoards
// 功能说明: 修改前 BoardList 只有 preparation mode 壳，availableBoards 只是简单数组，没有 mutation 结果和 boardID 索引缓存。
private enum BoardListPreparationMode {
    case fullDisplay
    case closingTarget(boardID: UUID)
}

final class iOSBoardListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, iOSBoardListCanvasTransitionInteractionControlling {
    // ... 省略无关成员 ...

    private let catalogLoader = BoardCatalogLoader()
    private let previewProvider = BoardPreviewProvider()
    private var availableBoards: [BoardCatalogItem] = []
    private var selectedEntryID: BoardListEntryID?

    // ... 省略无关成员 ...
}
```

### 修改后

- 新增 `BoardListCatalogMutationChangeKind`，显式描述 `.inserted`、`.updated`、`.moved`、`.unchanged`。
- 新增 `BoardListCatalogMutationResult`，把 `resolvedIndexPath`、`previousIndexPath`、`changeKind` 作为统一输出。
- `availableBoards` 增加 `didSet`，统一重建 `availableBoardIndexByID`，让 `boardID` 定位变成 O(1) 路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: BoardListCatalogMutationChangeKind / BoardListCatalogMutationResult / availableBoards / availableBoardIndexByID
// 功能说明: 修改后 BoardList 具备显式 mutation 结果类型，并把 availableBoards 升级为带 boardID 索引缓存的常驻模型。
private enum BoardListCatalogMutationChangeKind: String {
    case inserted
    case updated
    case moved
    case unchanged
}

private struct BoardListCatalogMutationResult {
    let resolvedIndexPath: IndexPath
    let previousIndexPath: IndexPath?
    let changeKind: BoardListCatalogMutationChangeKind
}

final class iOSBoardListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, iOSBoardListCanvasTransitionInteractionControlling {
    // ... 省略无关成员 ...

    private let catalogLoader = BoardCatalogLoader()
    private let previewProvider = BoardPreviewProvider()
    private var availableBoards: [BoardCatalogItem] = [] {
        didSet {
            rebuildAvailableBoardIndexByID()
        }
    }
    private var availableBoardIndexByID: [UUID: Int] = [:]
    private var selectedEntryID: BoardListEntryID?

    // ... 省略无关成员 ...
}
```

## 修改二：`closingTarget(boardID:)` 从全量 refresh 壳切到单板同步

### 修改前

- `performBoardListSync(mode:)` 对 `.closingTarget(boardID:)` 只打日志，然后直接回到 `refreshBookmarkStatus()`。
- 虽然 `Phase 1` 已经把 closing 入口收口到 `prepareTransitionTargetGeometry(...)`，但这里的数据同步仍然是全量路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: performBoardListSync(mode:)
// 功能说明: 修改前 closingTarget 分支仍然直接走 refreshBookmarkStatus()，并未消费 Phase 2 的单板 loader 能力。
private func performBoardListSync(
    mode: BoardListPreparationMode
) {
    switch mode {
    case .fullDisplay:
        refreshBookmarkStatus()
    case let .closingTarget(boardID):
        // Phase 1 keeps closing target prep on the existing refresh path.
        // Later phases will swap this branch to targeted single-board sync.
        logClosingTransitionTiming(
            phase: "performBoardListSync",
            extra:
                "mode=closingTarget " +
                "boardID=\(boardID.uuidString)"
        )
        refreshBookmarkStatus()
    }
}
```

### 修改后

- `.closingTarget(boardID:)` 改为转调 `syncClosingTargetBoard(boardID:)`。
- `syncClosingTargetBoard(boardID:)` 现在直接：
  - 调用 `catalogLoader.loadCatalogItem(boardID:)`
  - 对 `availableBoards` 执行 `upsertBoardCatalogItem(_:)`
  - 维护 `hasSelectedFolder` / `storageErrorMessage` / `selectedEntryID`
  - 更新 header
  - 继续沿用现有 `reloadBoardList() -> revealPendingBoardIfNeeded()` 行为
- 这里仍然保留 `reloadBoardList()`，是为了保持现阶段 UI 语义稳定；真正去掉全量 reload 的工作留到 `Phase 4`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: performBoardListSync(mode:) / syncClosingTargetBoard(boardID:)
// 功能说明: 修改后 closingTarget 分支优先走单板 catalog 加载与本地 upsert，再维持既有 reveal 链，不再一上来全量 refresh。
private func performBoardListSync(
    mode: BoardListPreparationMode
) {
    switch mode {
    case .fullDisplay:
        refreshBookmarkStatus()
    case let .closingTarget(boardID):
        syncClosingTargetBoard(boardID: boardID)
    }
}

private func syncClosingTargetBoard(
    boardID: UUID
) {
    logClosingTransitionTiming(
        phase: "performBoardListSync",
        extra:
            "mode=closingTarget " +
            "boardID=\(boardID.uuidString)"
    )
    dismissActionPanel()
    let bookmarkStatus = FolderBookmarkStore.bookmarkStatus()

    do {
        let loadCatalogItemStart = BoardListCanvasTransitionDebugLogger.now()
        guard let boardItem = try catalogLoader.loadCatalogItem(boardID: boardID) else {
            logClosingTransitionTiming(
                phase: "loadCatalogItemMissing",
                extra: "boardID=\(boardID.uuidString)"
            )
            refreshBookmarkStatus()
            return
        }

        logClosingTransitionTiming(
            phase: "loadCatalogItemSuccess",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - loadCatalogItemStart,
            extra:
                "boardID=\(boardID.uuidString) " +
                "boardCount=\(availableBoards.count)"
        )

        let mutationResult = upsertBoardCatalogItem(boardItem)
        // ... 省略 mutationResult 日志字符串拼接 ...

        hasSelectedFolder = true
        storageErrorMessage = nil
        selectedEntryID = .board(boardID)
        ensureValidSelection()
        applyHeaderState(
            BoardListHeaderStateBuilder.make(
                bookmarkStatus: bookmarkStatus,
                boardCount: availableBoards.count
            )
        )

        let reloadStart = BoardListCanvasTransitionDebugLogger.now()
        reloadBoardList()
        logClosingTransitionTiming(
            phase: "reloadBoardListAfterClosingTargetSync",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - reloadStart,
            extra: "entryCount=\(entries.count)"
        )
    } catch FolderBookmarkStoreError.missingBookmarkData {
        replaceAvailableBoards(with: [])
        selectedEntryID = nil
        hasSelectedFolder = false
        storageErrorMessage = nil
        applyHeaderState(
            BoardListHeaderStateBuilder.make(
                bookmarkStatus: bookmarkStatus
            )
        )
        reloadBoardList()
    } catch {
        logClosingTransitionTiming(
            phase: "loadCatalogItemFailed",
            extra:
                "boardID=\(boardID.uuidString) " +
                "error=\"\(error.localizedDescription)\""
        )
        refreshBookmarkStatus()
    }
}
```

## 修改三：把全量覆盖、局部 upsert、排序与 `boardID` 定位统一收口

### 修改前

- `refreshBookmarkStatus()` 全量加载后直接 `availableBoards = boards`。
- 缺 bookmark 和异常分支直接 `availableBoards = []`。
- `indexPath(for boardID:)` 通过 `entries.firstIndex(where:)` 扫描。
- `boardTitle(for boardID:)` 通过 `availableBoards.first(where:)` 扫描。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: refreshBookmarkStatus() / indexPath(for:) / boardTitle(for:)
// 功能说明: 修改前全量覆盖和 boardID 定位逻辑分散在多个函数里，缺少统一的排序与 upsert 收口点。
private func refreshBookmarkStatus() {
    // ... 省略前置日志与 bookmarkStatus ...
    do {
        let boards = try catalogLoader.loadCatalog()
        availableBoards = boards
        hasSelectedFolder = true
        storageErrorMessage = nil
        ensureValidSelection()
        // ... 省略 header 与 reload ...
    } catch FolderBookmarkStoreError.missingBookmarkData {
        availableBoards = []
        selectedEntryID = nil
        hasSelectedFolder = false
        storageErrorMessage = nil
        // ... 省略 header 与 reload ...
    } catch {
        availableBoards = []
        selectedEntryID = nil
        hasSelectedFolder = bookmarkStatus.hasSelectedFolder
        storageErrorMessage = error.localizedDescription
        // ... 省略 header 与 reload ...
    }
}

private func indexPath(for boardID: UUID) -> IndexPath? {
    guard let index = entries.firstIndex(where: { $0.boardID == boardID }) else {
        return nil
    }

    return IndexPath(item: index, section: 0)
}

private func boardTitle(for boardID: UUID) -> String? {
    availableBoards.first(where: { $0.boardID == boardID })?.title
}
```

### 修改后

- 新增：
  - `replaceAvailableBoards(with:)`
  - `upsertBoardCatalogItem(_:)`
  - `rebuildAvailableBoardIndexByID()`
  - `orderedBoardCatalogItems(_:)`
  - `insertionIndexForBoardCatalogItem(_:)`
  - `boardCatalogItemSortsBefore(_:_:)`
  - `catalogEntryIndexPath(forBoardIndex:)`
- `refreshBookmarkStatus()` 改为统一走 `replaceAvailableBoards(with:)`，确保全量路径也受同一排序和索引策略约束。
- `indexPath(for:)` / `boardTitle(for:)` 改为基于 `availableBoardIndexByID` 定位，避免重复线性扫描。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: replaceAvailableBoards(with:) / upsertBoardCatalogItem(_:) / rebuildAvailableBoardIndexByID() / orderedBoardCatalogItems(_:) / insertionIndexForBoardCatalogItem(_:) / boardCatalogItemSortsBefore(_:_:) / refreshBookmarkStatus() / catalogEntryIndexPath(forBoardIndex:) / indexPath(for:) / boardTitle(for:)
// 功能说明: 修改后全量覆盖与单条 mutation 共用同一套排序、索引重建与 boardID 定位规则。
private func replaceAvailableBoards(
    with boards: [BoardCatalogItem]
) {
    availableBoards = Self.orderedBoardCatalogItems(boards)
}

private func upsertBoardCatalogItem(
    _ item: BoardCatalogItem
) -> BoardListCatalogMutationResult {
    let previousBoardIndex = availableBoardIndexByID[item.boardID]
    let previousItem = previousBoardIndex.flatMap { boardIndex in
        guard availableBoards.indices.contains(boardIndex) else {
            return nil
        }
        return availableBoards[boardIndex]
    }

    if let previousBoardIndex,
       availableBoards.indices.contains(previousBoardIndex) {
        availableBoards.remove(at: previousBoardIndex)
    }

    let resolvedBoardIndex = insertionIndexForBoardCatalogItem(item)
    availableBoards.insert(item, at: resolvedBoardIndex)

    let resolvedIndexPath = catalogEntryIndexPath(
        forBoardIndex: resolvedBoardIndex
    )
    let previousIndexPath = previousBoardIndex.map {
        catalogEntryIndexPath(forBoardIndex: $0)
    }
    let changeKind: BoardListCatalogMutationChangeKind
    if let previousItem,
       let previousBoardIndex {
        if previousBoardIndex == resolvedBoardIndex {
            changeKind =
                previousItem.revisionToken == item.revisionToken
                ? .unchanged
                : .updated
        } else {
            changeKind = .moved
        }
    } else {
        changeKind = .inserted
    }

    return BoardListCatalogMutationResult(
        resolvedIndexPath: resolvedIndexPath,
        previousIndexPath: previousIndexPath,
        changeKind: changeKind
    )
}

private func rebuildAvailableBoardIndexByID() {
    availableBoardIndexByID = Dictionary(
        uniqueKeysWithValues: availableBoards.enumerated().map { index, item in
            (item.boardID, index)
        }
    )
}

private static func orderedBoardCatalogItems(
    _ boards: [BoardCatalogItem]
) -> [BoardCatalogItem] {
    boards.sorted(by: Self.boardCatalogItemSortsBefore)
}

private static func boardCatalogItemSortsBefore(
    _ lhs: BoardCatalogItem,
    _ rhs: BoardCatalogItem
) -> Bool {
    if lhs.updatedAt == rhs.updatedAt {
        return lhs.boardID.uuidString < rhs.boardID.uuidString
    }

    return lhs.updatedAt > rhs.updatedAt
}

private func refreshBookmarkStatus() {
    // ... 省略前置日志与 bookmarkStatus ...
    do {
        let boards = try catalogLoader.loadCatalog()
        replaceAvailableBoards(with: boards)
        // ... 省略 header、selection 与 reload ...
    } catch FolderBookmarkStoreError.missingBookmarkData {
        replaceAvailableBoards(with: [])
        // ... 省略状态清理 ...
    } catch {
        replaceAvailableBoards(with: [])
        // ... 省略错误状态设置 ...
    }
}

private func catalogEntryIndexPath(
    forBoardIndex boardIndex: Int
) -> IndexPath {
    IndexPath(item: boardIndex + 1, section: 0)
}

private func indexPath(for boardID: UUID) -> IndexPath? {
    guard
        hasSelectedFolder,
        storageErrorMessage == nil,
        let boardIndex = availableBoardIndexByID[boardID]
    else {
        return nil
    }

    return catalogEntryIndexPath(forBoardIndex: boardIndex)
}

private func boardTitle(for boardID: UUID) -> String? {
    guard
        let boardIndex = availableBoardIndexByID[boardID],
        availableBoards.indices.contains(boardIndex)
    else {
        return nil
    }

    return availableBoards[boardIndex].title
}
```

## 修改四：现有 `rename` 流程改为消费单板 mutation，而不是回退全量 refresh

### 修改前

- `commitRename(boardID:title:)` 在 `BoardStore.renameBoard(...)` 成功后，直接调用 `refreshBookmarkStatus()`。
- 这意味着即便只是改了一个 board 的 title，也会把整个 `BoardList` 重新走一遍全量加载。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: commitRename(boardID:title:)
// 功能说明: 修改前 rename 成功后直接触发 refreshBookmarkStatus()，没有复用单板读取与本地 mutation。
private func commitRename(boardID: UUID, title: String) {
    // ... 省略前置校验与 normalizedTitle 处理 ...

    do {
        try BoardStore.renameBoard(id: boardID, title: normalizedTitle)
        editingBoardID = nil
        selectedEntryID = .board(boardID)
        pendingRevealBoardID = boardID
        refreshBookmarkStatus()
    } catch {
        // ... 省略错误处理 ...
    }
}
```

### 修改后

- rename 成功后，优先读取单板 `catalogItem` 并执行 `upsertBoardCatalogItem(_:)`。
- 同步更新：
  - `hasSelectedFolder`
  - `storageErrorMessage`
  - `ensureValidSelection()`
  - header 文案
- 只有在 `loadCatalogItem(boardID:)` 返回 `nil` 时，才 fallback 到 `refreshBookmarkStatus()`。
- 这样现有一条真实用户路径已经开始消费 `Phase 3` 的新模型，而不只是新增内部 helper。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: commitRename(boardID:title:)
// 功能说明: 修改后 rename 成功优先走单板 catalog 加载与 upsert，只在单板 item 缺失时回退全量 refresh。
private func commitRename(boardID: UUID, title: String) {
    // ... 省略前置校验与 normalizedTitle 处理 ...

    do {
        try BoardStore.renameBoard(id: boardID, title: normalizedTitle)
        editingBoardID = nil
        selectedEntryID = .board(boardID)
        pendingRevealBoardID = boardID
        if let catalogItem = try catalogLoader.loadCatalogItem(boardID: boardID) {
            let mutationResult = upsertBoardCatalogItem(catalogItem)
            let previousIndexPathDescription = mutationResult.previousIndexPath.map {
                "[section=\($0.section),item=\($0.item)]"
            } ?? "nil"
            let resolvedIndexPathDescription =
                "[section=\(mutationResult.resolvedIndexPath.section),item=\(mutationResult.resolvedIndexPath.item)]"
            hasSelectedFolder = true
            storageErrorMessage = nil
            ensureValidSelection()
            applyHeaderState(
                BoardListHeaderStateBuilder.make(
                    bookmarkStatus: FolderBookmarkStore.bookmarkStatus(),
                    boardCount: availableBoards.count
                )
            )
            logRenameTrace(
                "commitRenameAppliedCatalogMutation",
                extra:
                    "boardID=\(boardID.uuidString) " +
                    "changeKind=\(mutationResult.changeKind.rawValue) " +
                    "previousIndexPath=\(previousIndexPathDescription) " +
                    "resolvedIndexPath=\(resolvedIndexPathDescription)"
            )
            reloadBoardList()
        } else {
            logRenameTrace(
                "commitRenameCatalogItemMissing",
                extra: "boardID=\(boardID.uuidString)"
            )
            refreshBookmarkStatus()
        }
    } catch {
        // ... 省略错误处理 ...
    }
}
```

## 本阶段结果

- `availableBoards` 现在不再只是“全量加载结果容器”，而是 `BoardList` 内部的长生命周期缓存模型。
- `BoardList` 现在已经具备：
  - 单板 `BoardCatalogItem` 本地 upsert
  - 基于 `boardID` 的快速 index 定位
  - 显式的 mutation 结果表达
- closing target-only 路径已经消费 `Phase 2` 的单板 loader 能力，不再一上来强制全量 `refreshBookmarkStatus()`。
- `pendingRevealBoardID -> revealPendingBoardIfNeeded()` 仍然保持为唯一的 target reveal 入口，这一点没有改变。
- 当前阶段仍然保留 `reloadBoardList()`，所以 UI 层还没有彻底摆脱全量 reload；这正是 `Phase 4` 要继续处理的部分。

## 验证

- 已对 `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift` 执行 `ReadLints`。
- 当前结果：无 linter 报错。
- 本次未执行完整 iOS 构建；因此这里记录的是源码级与静态检查级确认结果。
