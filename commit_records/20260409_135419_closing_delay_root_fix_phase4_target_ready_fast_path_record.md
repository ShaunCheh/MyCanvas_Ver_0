# 20260409_135419_closing_delay_root_fix_phase4_target_ready_fast_path_record

## 记录范围

- 记录内容：`closing_delay_root_fix` 计划的 `Phase 4` 实施记录。
- 记录目标：建立 closing target-ready 快路径，让 `requestTargetGeometry -> targetGeometryResolved` 不再因为整页 `reloadData()` 和无关预览工作而阻塞。
- 记录依据：本记录基于当前工作树的 `git diff -- MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift` 与修改后的源码内容整理。
- 对应计划文件：`.cursor/plans/closing_delay_root_fix_97b39f82.plan.md`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 本记录不包含：`Phase 3` 已落地的 `availableBoards` 常驻缓存与基础 `upsertBoardCatalogItem(_:)` 能力说明。
- 本记录不包含：`Phase 5` 中 `BoardPreviewProvider` 的 trace 副作用剥离。
- 本记录不包含：git commit。

## 问题背景

- `Phase 3` 之后，`BoardList` 已经能做单板 `loadCatalogItem(boardID:)` 与本地 `upsertBoardCatalogItem(_:)`。
- 但 closing target-ready 成功路径里仍然调用了 `reloadBoardList()`，内部会继续触发：
  - `collectionView.reloadData()`
  - `cellForItemAt` 的同步 `immediatePreview(...)`
  - 非 thumbnail 情况下的 `requestThumbnail(...)`
- 这意味着 target-ready 虽然已经不是“全量读目录”，但仍然会把“整页 cell 重建 + 无关预览”塞进动画开始前的主线程关键路径。
- `Phase 4` 的目标是把成功路径压缩为：
  - 单板读取
  - 单板 upsert
  - 目标 item 局部 collection mutation
  - 几何解析
  - 交回 `BoardListCanvasTransitionTargetGeometry`

## 修改一：为 closing target-ready 引入显式预览策略与目标准备结果

### 修改前

- `BoardList` 侧只有 `BoardListCatalogMutationResult`。
- `closing target-ready` 没有显式的 preview 策略状态。
- 几何解析结果也只是匿名地从 `transitionTargetGeometry(for:)` 返回一个 `BoardListCanvasTransitionTargetGeometry`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: BoardListCatalogMutationResult / pendingTransitionTargetResolution / closingTransitionTimingState
// 功能说明: 修改前 BoardList 没有显式的 closing preview 策略，也没有封装目标几何解析结果的专用结构体。
private struct BoardListCatalogMutationResult {
    let resolvedIndexPath: IndexPath
    let previousIndexPath: IndexPath?
    let changeKind: BoardListCatalogMutationChangeKind
}

final class iOSBoardListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, iOSBoardListCanvasTransitionInteractionControlling {
    // ... 省略无关成员 ...

    private var pendingTransitionTargetResolution: PendingTransitionTargetResolution?
    private var closingTransitionTimingState: ClosingTransitionTimingState?
    private var isTransitionInteractionFrozen = false

    // ... 省略无关成员 ...
}
```

### 修改后

- 新增 `BoardListPreviewWorkPolicy`：
  - `.normal`
  - `.geometryOnly`
- 新增 `BoardListClosingTargetPreparationResult`，把 `boardID`、`resolvedIndexPath`、`geometry`、`usedFallbackGeometry` 统一封装。
- 控制器新增 `previewWorkPolicy` 状态，专门承载 closing target-ready 期间的预览行为切换。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: BoardListPreviewWorkPolicy / BoardListClosingTargetPreparationResult / previewWorkPolicy
// 功能说明: 修改后 closing target-ready 的几何准备与 preview 策略都变成显式状态，避免继续隐含在 reload 与 pendingRevealBoardID 附近。
private enum BoardListPreviewWorkPolicy: Equatable {
    case normal
    case geometryOnly
}

private struct BoardListClosingTargetPreparationResult {
    let boardID: UUID
    let resolvedIndexPath: IndexPath
    let geometry: BoardListCanvasTransitionTargetGeometry
    let usedFallbackGeometry: Bool
}

final class iOSBoardListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, iOSBoardListCanvasTransitionInteractionControlling {
    // ... 省略无关成员 ...

    private var pendingTransitionTargetResolution: PendingTransitionTargetResolution?
    private var closingTransitionTimingState: ClosingTransitionTimingState?
    private var previewWorkPolicy: BoardListPreviewWorkPolicy = .normal
    private var isTransitionInteractionFrozen = false

    // ... 省略无关成员 ...
}
```

## 修改二：把 closing target 成功路径从整页 `reloadBoardList()` 改成局部 collection mutation

### 修改前

- `prepareTransitionTargetGeometry(...)` 只是挂起 pending completion，然后直接进入 `performBoardListSync(mode: .closingTarget(boardID:))`。
- `syncClosingTargetBoard(boardID:)` 虽然已经单板读取并 `upsertBoardCatalogItem(_:)`，但成功后仍然整页 `reloadBoardList()`。
- 也就是说，`Phase 3` 只是把“数据读取”变成单板，UI 仍然是整页重建。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: prepareTransitionTargetGeometry(for:completion:) / syncClosingTargetBoard(boardID:)
// 功能说明: 修改前 closing target 成功路径虽然已经走单板 catalog load，但最终仍用 reloadBoardList() 触发整页重建。
func prepareTransitionTargetGeometry(
    for boardID: UUID?,
    completion: @escaping (BoardListCanvasTransitionTargetGeometry) -> Void
) {
    pendingTransitionTargetResolution = nil

    // ... 省略 trace 与 pending 状态设置 ...

    guard let boardID else {
        pendingRevealBoardID = nil
        completion(.init())
        closingTransitionTimingState = nil
        return
    }

    pendingRevealBoardID = boardID
    pendingTransitionTargetResolution = PendingTransitionTargetResolution(
        boardID: boardID,
        completion: completion
    )

    guard isViewLoaded, view.window != nil else {
        return
    }

    performBoardListSync(mode: .closingTarget(boardID: boardID))
}

private func syncClosingTargetBoard(
    boardID: UUID
) {
    // ... 省略日志、dismissActionPanel 与 bookmarkStatus ...

    do {
        guard let boardItem = try catalogLoader.loadCatalogItem(boardID: boardID) else {
            refreshBookmarkStatus()
            return
        }

        let mutationResult = upsertBoardCatalogItem(boardItem)
        // ... 省略 mutationResult 日志 ...

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
    } catch {
        refreshBookmarkStatus()
    }
}
```

### 修改后

- `prepareTransitionTargetGeometry(...)` 进入 closing target-ready 时，先把 `previewWorkPolicy` 切到 `.geometryOnly`。
- `performBoardListSync(mode: .fullDisplay)` 会恢复 `.normal`，保证普通展示路径不受影响。
- `syncClosingTargetBoard(boardID:)` 成功后不再调用 `reloadBoardList()`，改为转调 `applyClosingTargetCollectionMutation(...)`。
- `applyClosingTargetCollectionMutation(...)` 按 mutation 类型只对目标 item 做：
  - `.unchanged`：直接结束
  - `.updated`：`reloadItems`
  - `.inserted`：`insertItems`
  - `.moved`：`deleteItems + insertItems`
- 局部 mutation 完成后才继续 `revealPendingBoardIfNeeded()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: prepareTransitionTargetGeometry(for:completion:) / performBoardListSync(mode:) / syncClosingTargetBoard(boardID:) / applyClosingTargetCollectionMutation(_:boardID:)
// 功能说明: 修改后 closing target 成功路径只做单板 mutation 与局部 collection 更新，不再触发整页 reloadData。
func prepareTransitionTargetGeometry(
    for boardID: UUID?,
    completion: @escaping (BoardListCanvasTransitionTargetGeometry) -> Void
) {
    pendingTransitionTargetResolution = nil
    restoreNormalPreviewWorkPolicy()

    // ... 省略 trace 与 pending 状态设置 ...

    guard let boardID else {
        pendingRevealBoardID = nil
        completion(.init())
        closingTransitionTimingState = nil
        return
    }

    pendingRevealBoardID = boardID
    pendingTransitionTargetResolution = PendingTransitionTargetResolution(
        boardID: boardID,
        completion: completion
    )
    previewWorkPolicy = .geometryOnly

    guard isViewLoaded, view.window != nil else {
        return
    }

    performBoardListSync(mode: .closingTarget(boardID: boardID))
}

private func performBoardListSync(
    mode: BoardListPreparationMode
) {
    switch mode {
    case .fullDisplay:
        restoreNormalPreviewWorkPolicy()
        refreshBookmarkStatus()
    case let .closingTarget(boardID):
        syncClosingTargetBoard(boardID: boardID)
    }
}

private func syncClosingTargetBoard(
    boardID: UUID
) {
    // ... 省略日志、dismissActionPanel 与 bookmarkStatus ...

    do {
        guard let boardItem = try catalogLoader.loadCatalogItem(boardID: boardID) else {
            restoreNormalPreviewWorkPolicy()
            refreshBookmarkStatus()
            return
        }

        let mutationResult = upsertBoardCatalogItem(boardItem)
        // ... 省略 mutationResult 日志 ...

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
        applyClosingTargetCollectionMutation(
            mutationResult,
            boardID: boardID
        )
    } catch FolderBookmarkStoreError.missingBookmarkData {
        restoreNormalPreviewWorkPolicy()
        replaceAvailableBoards(with: [])
        selectedEntryID = nil
        hasSelectedFolder = false
        storageErrorMessage = nil
        reloadBoardList()
    } catch {
        restoreNormalPreviewWorkPolicy()
        refreshBookmarkStatus()
    }
}

private func applyClosingTargetCollectionMutation(
    _ mutationResult: BoardListCatalogMutationResult,
    boardID: UUID
) {
    // ... 省略 trace 拼接 ...

    updateCollectionVisibility()
    updateDisplayModeControlState()
    updateCollectionLayout()
    view.layoutIfNeeded()

    let finishMutation: () -> Void = { [weak self] in
        guard let self else {
            return
        }

        self.syncCollectionSelection()
        self.view.layoutIfNeeded()
        self.collectionView.layoutIfNeeded()
        self.revealPendingBoardIfNeeded()
    }

    switch mutationResult.changeKind {
    case .unchanged:
        finishMutation()
    case .updated:
        UIView.performWithoutAnimation {
            self.collectionView.performBatchUpdates({
                self.collectionView.reloadItems(
                    at: [mutationResult.resolvedIndexPath]
                )
            }, completion: { _ in
                finishMutation()
            })
        }
    case .inserted:
        UIView.performWithoutAnimation {
            self.collectionView.performBatchUpdates({
                self.collectionView.insertItems(
                    at: [mutationResult.resolvedIndexPath]
                )
            }, completion: { _ in
                finishMutation()
            })
        }
    case .moved:
        guard let previousIndexPath = mutationResult.previousIndexPath else {
            UIView.performWithoutAnimation {
                self.collectionView.performBatchUpdates({
                    self.collectionView.reloadItems(
                        at: [mutationResult.resolvedIndexPath]
                    )
                }, completion: { _ in
                    finishMutation()
                })
            }
            return
        }

        UIView.performWithoutAnimation {
            self.collectionView.performBatchUpdates({
                self.collectionView.deleteItems(at: [previousIndexPath])
                self.collectionView.insertItems(
                    at: [mutationResult.resolvedIndexPath]
                )
            }, completion: { _ in
                finishMutation()
            })
        }
    }
}
```

## 修改三：把目标几何解析从匿名 helper 提升为显式 target-resolution 结果

### 修改前

- `revealBoard(at:boardID:)` 在滚动到目标位置后，直接调用 `transitionTargetGeometry(for:)`。
- `transitionTargetGeometry(for:)` 只返回 `BoardListCanvasTransitionTargetGeometry`，不会暴露：
  - 实际 resolved indexPath
  - 是否使用了 fallback geometry
- `finishPendingTransitionTargetResolution(...)` 也只接收裸的 geometry。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: transitionTargetGeometry(for:) / revealBoard(at:boardID:) / finishPendingTransitionTargetResolution(for:geometry:)
// 功能说明: 修改前目标几何解析结果只是一份 geometry，本身不携带 resolvedIndexPath 与 fallback 信息。
private func transitionTargetGeometry(
    for boardID: UUID
) -> BoardListCanvasTransitionTargetGeometry {
    guard let indexPath = indexPath(for: boardID) else {
        return .init()
    }

    if let cell = collectionView.cellForItem(at: indexPath) as? iOSBoardCollectionViewCell {
        return BoardListCanvasTransitionTargetGeometry(
            cardRect: cell.transitionGeometry(in: view).cardRect
        )
    }

    return BoardListCanvasTransitionTargetGeometry(
        cardRect: transitionCardRect(at: indexPath)
    )
}

private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    // ... 省略 guard 与日志 ...

    collectionView.layoutIfNeeded()
    collectionView.scrollToItem(
        at: indexPath,
        at: .top,
        animated: false
    )
    collectionView.layoutIfNeeded()
    let geometry = transitionTargetGeometry(for: boardID)
    logClosingTransitionTiming(
        phase: "revealBoardEnd",
        localDuration: BoardListCanvasTransitionDebugLogger.now() - revealStart,
        extra:
            "boardID=\(boardID.uuidString) " +
            "hasCardRect=\(geometry.cardRect != nil)"
    )
    finishPendingTransitionTargetResolution(
        for: boardID,
        geometry: geometry
    )
    pendingRevealBoardID = nil
}
```

### 修改后

- `transitionTargetGeometry(for:)` 被替换为 `resolveTransitionTargetGeometry(for:) -> BoardListClosingTargetPreparationResult?`。
- 新 helper 会显式记录：
  - `resolvedIndexPath`
  - `usedFallbackGeometry`
  - `hasCardRect`
- 新增 `finishPendingTransitionTargetResolution(_ preparationResult:)` 重载，closing trace 里现在能直接看到目标板是走了 cell 几何还是 layout fallback。
- `revealBoard(at:boardID:)` 改为围绕 preparation result 工作。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: resolveTransitionTargetGeometry(for:) / finishPendingTransitionTargetResolution(_:) / revealBoard(at:boardID:)
// 功能说明: 修改后目标几何解析会显式返回 resolvedIndexPath 与 fallback 标志，closing completion 不再只依赖匿名 geometry。
private func resolveTransitionTargetGeometry(
    for boardID: UUID
) -> BoardListClosingTargetPreparationResult? {
    guard let resolvedIndexPath = indexPath(for: boardID) else {
        return nil
    }

    let geometry: BoardListCanvasTransitionTargetGeometry
    let usedFallbackGeometry: Bool
    if let cell = collectionView.cellForItem(
        at: resolvedIndexPath
    ) as? iOSBoardCollectionViewCell {
        geometry = BoardListCanvasTransitionTargetGeometry(
            cardRect: cell.transitionGeometry(in: view).cardRect
        )
        usedFallbackGeometry = false
    } else {
        geometry = BoardListCanvasTransitionTargetGeometry(
            cardRect: transitionCardRect(at: resolvedIndexPath)
        )
        usedFallbackGeometry = true
    }

    logClosingTransitionTiming(
        phase: "resolveTransitionTargetGeometry",
        extra:
            "boardID=\(boardID.uuidString) " +
            "indexPath=[section=\(resolvedIndexPath.section),item=\(resolvedIndexPath.item)] " +
            "usedFallbackGeometry=\(usedFallbackGeometry) " +
            "hasCardRect=\(geometry.cardRect != nil)"
    )
    return BoardListClosingTargetPreparationResult(
        boardID: boardID,
        resolvedIndexPath: resolvedIndexPath,
        geometry: geometry,
        usedFallbackGeometry: usedFallbackGeometry
    )
}

private func finishPendingTransitionTargetResolution(
    _ preparationResult: BoardListClosingTargetPreparationResult
) {
    guard pendingTransitionTargetResolution?.boardID == preparationResult.boardID else {
        return
    }

    let resolutionDuration = closingTransitionTimingState?.targetGeometryRequestedAt.map {
        BoardListCanvasTransitionDebugLogger.now() - $0
    }
    logClosingTransitionTiming(
        phase: "finishPendingTransitionTargetResolution",
        localDuration: resolutionDuration,
        extra:
            "boardID=\(preparationResult.boardID.uuidString) " +
            "indexPath=[section=\(preparationResult.resolvedIndexPath.section),item=\(preparationResult.resolvedIndexPath.item)] " +
            "usedFallbackGeometry=\(preparationResult.usedFallbackGeometry) " +
            "hasCardRect=\(preparationResult.geometry.cardRect != nil)"
    )
    let completion = pendingTransitionTargetResolution?.completion
    pendingTransitionTargetResolution = nil
    closingTransitionTimingState = nil
    restoreNormalPreviewWorkPolicy()
    completion?(preparationResult.geometry)
    scheduleVisibleBoardThumbnailRefreshIfNeeded()
}

private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    // ... 省略 guard 与日志 ...

    collectionView.layoutIfNeeded()
    collectionView.scrollToItem(
        at: indexPath,
        at: .top,
        animated: false
    )
    collectionView.layoutIfNeeded()
    let preparationResult = resolveTransitionTargetGeometry(for: boardID)
    logClosingTransitionTiming(
        phase: "revealBoardEnd",
        localDuration: BoardListCanvasTransitionDebugLogger.now() - revealStart,
        extra:
            "boardID=\(boardID.uuidString) " +
            "indexPath=[section=\(preparationResult?.resolvedIndexPath.section ?? indexPath.section),item=\(preparationResult?.resolvedIndexPath.item ?? indexPath.item)] " +
            "usedFallbackGeometry=\(preparationResult?.usedFallbackGeometry ?? true) " +
            "hasCardRect=\(preparationResult?.geometry.cardRect != nil)"
    )
    if let preparationResult {
        finishPendingTransitionTargetResolution(preparationResult)
    } else {
        finishPendingTransitionTargetResolution(
            for: boardID,
            geometry: .init()
        )
    }
    pendingRevealBoardID = nil
}
```

## 修改四：closing 期间切换为 geometry-only 预览，并在完成后补 visible cell 缩略图

### 修改前

- `cellForItemAt` 对所有可请求预览的 board entry 都会同步调用 `previewProvider.immediatePreview(...)`。
- 如果 `previewContent.isThumbnail == false`，还会立刻 `requestThumbnail(...)`。
- `iOSBoardCollectionViewCell` 自身不追踪当前显示内容是不是 thumbnail，因此控制器侧也无法在 closing 结束后只补必要的 visible cell。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: collectionView(_:cellForItemAt:)
// 功能说明: 修改前 cell 配置阶段不区分普通模式与 closing target-ready 模式，所有 board cell 都会进入 immediatePreview / requestThumbnail 链。
func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
) -> UICollectionViewCell {
    // ... 省略 dequeue 与 entry 获取 ...

    let previewContent: BoardPreviewContent
    if entry.canRequestPreview,
       let catalogItem = entry.catalogItem {
        let targetPixelSize = cell.targetThumbnailPixelSize(for: displayMode)
        previewContent = previewProvider.immediatePreview(
            for: catalogItem,
            targetPixelSize: targetPixelSize
        )
    } else {
        previewContent = .empty
    }

    cell.configure(
        with: entry,
        previewContent: previewContent,
        displayMode: displayMode,
        isEditingTitle: entry.boardID.map { $0 == editingBoardID } ?? false,
        onMoreActionsRequested: moreActionsHandler,
        onRenameSubmitted: { [weak self] boardID, title in
            self?.commitRename(boardID: boardID, title: title)
        }
    )

    if entry.canRequestPreview,
       let catalogItem = entry.catalogItem,
       previewContent.isThumbnail == false {
        cell.requestThumbnail(
            using: previewProvider,
            for: catalogItem,
            displayMode: displayMode
        )
    }
    return cell
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/符号名: representedRevisionToken / requestThumbnail(using:for:displayMode:)
// 功能说明: 修改前 cell 不记录当前显示的是 thumbnail 还是 geometry，控制器无法精确判断 closing 后哪些 visible cell 还需要补图。
private var representedRevisionToken: String?
private var thumbnailRequestToken: BoardPreviewRequestToken?
private var onMoreActionsRequested: MoreActionsHandler?
private var onRenameSubmitted: RenameSubmitHandler?
private var currentPresentationStyle: PresentationStyle = .boardGrid
private var isTitleEditingActive = false

func requestThumbnail(
    using previewProvider: BoardPreviewProvider,
    for item: BoardCatalogItem,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()

    thumbnailRequestToken = previewProvider.requestThumbnail(
        for: item,
        targetPixelSize: targetThumbnailPixelSize(for: displayMode)
    ) { [weak self] previewContent in
        guard
            let self,
            let previewContent,
            self.representedBoardID == item.boardID,
            self.representedRevisionToken == item.revisionToken
        else {
            return
        }

        self.previewView.apply(content: previewContent)
    }
}
```

### 修改后

- `cellForItemAt` 现在会根据 `currentPreviewWorkPolicy()` 分流：
  - `.normal`：沿用原来的 `immediatePreview(...)`
  - `.geometryOnly`：直接使用 `.geometry(catalogItem.previewSeed)`
- `requestThumbnail(...)` 只在 `.normal` 下触发。
- closing target 结束后，会调用 `scheduleVisibleBoardThumbnailRefreshIfNeeded()`，异步为当前 visible board cell 补图。
- `iOSBoardCollectionViewCell` 新增 `currentPreviewContent` 和 `isShowingThumbnailPreview`，让控制器能只对“仍不是 thumbnail 的可见 cell”补发请求。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: currentPreviewWorkPolicy() / restoreNormalPreviewWorkPolicy() / scheduleVisibleBoardThumbnailRefreshIfNeeded() / requestVisibleBoardThumbnailsIfNeeded() / collectionView(_:cellForItemAt:)
// 功能说明: 修改后 closing target-ready 期间可切到 geometryOnly，几何一旦解析完成再异步补 visible cell 缩略图，不再把预览补齐放进 target-ready 前置路径。
private func currentPreviewWorkPolicy() -> BoardListPreviewWorkPolicy {
    previewWorkPolicy
}

private func restoreNormalPreviewWorkPolicy() {
    previewWorkPolicy = .normal
}

private func scheduleVisibleBoardThumbnailRefreshIfNeeded() {
    guard currentPreviewWorkPolicy() == .normal else {
        return
    }

    DispatchQueue.main.async { [weak self] in
        self?.requestVisibleBoardThumbnailsIfNeeded()
    }
}

private func requestVisibleBoardThumbnailsIfNeeded() {
    guard
        currentPreviewWorkPolicy() == .normal,
        isViewLoaded,
        view.window != nil
    else {
        return
    }

    let visibleIndexPaths = collectionView.indexPathsForVisibleItems.sorted {
        if $0.section == $1.section {
            return $0.item < $1.item
        }

        return $0.section < $1.section
    }
    for indexPath in visibleIndexPaths {
        guard
            let entry = entry(at: indexPath),
            let catalogItem = entry.catalogItem,
            let cell = collectionView.cellForItem(at: indexPath) as? iOSBoardCollectionViewCell,
            cell.isShowingThumbnailPreview == false
        else {
            continue
        }

        cell.requestThumbnail(
            using: previewProvider,
            for: catalogItem,
            displayMode: displayMode
        )
    }
}

func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
) -> UICollectionViewCell {
    // ... 省略 dequeue 与 entry 获取 ...

    let previewContent: BoardPreviewContent
    if entry.canRequestPreview,
       let catalogItem = entry.catalogItem {
        switch currentPreviewWorkPolicy() {
        case .normal:
            let targetPixelSize = cell.targetThumbnailPixelSize(for: displayMode)
            previewContent = previewProvider.immediatePreview(
                for: catalogItem,
                targetPixelSize: targetPixelSize
            )
        case .geometryOnly:
            previewContent = .geometry(catalogItem.previewSeed)
        }
    } else {
        previewContent = .empty
    }

    cell.configure(
        with: entry,
        previewContent: previewContent,
        displayMode: displayMode,
        isEditingTitle: entry.boardID.map { $0 == editingBoardID } ?? false,
        onMoreActionsRequested: moreActionsHandler,
        onRenameSubmitted: { [weak self] boardID, title in
            self?.commitRename(boardID: boardID, title: title)
        }
    )

    if entry.canRequestPreview,
       let catalogItem = entry.catalogItem,
       previewContent.isThumbnail == false,
       currentPreviewWorkPolicy() == .normal {
        cell.requestThumbnail(
            using: previewProvider,
            for: catalogItem,
            displayMode: displayMode
        )
    }
    return cell
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/符号名: currentPreviewContent / isShowingThumbnailPreview / configure(with:previewContent:displayMode:isEditingTitle:onMoreActionsRequested:onRenameSubmitted:) / requestThumbnail(using:for:displayMode:)
// 功能说明: 修改后 cell 显式记录当前 previewContent，并向控制器暴露是否已显示 thumbnail，用于 closing 完成后的可见项补图。
private var representedRevisionToken: String?
private var thumbnailRequestToken: BoardPreviewRequestToken?
private var onMoreActionsRequested: MoreActionsHandler?
private var onRenameSubmitted: RenameSubmitHandler?
private var currentPresentationStyle: PresentationStyle = .boardGrid
private var currentPreviewContent: BoardPreviewContent = .empty
private var isTitleEditingActive = false

override func prepareForReuse() {
    super.prepareForReuse()
    // ... 省略已有清理逻辑 ...
    currentPreviewContent = .empty
    previewView.apply(content: .empty)
}

func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode,
    isEditingTitle: Bool = false,
    onMoreActionsRequested: MoreActionsHandler? = nil,
    onRenameSubmitted: RenameSubmitHandler? = nil
) {
    // ... 省略已有状态赋值 ...
    currentPreviewContent = previewContent
    previewView.apply(content: previewContent)
    // ... 省略其余配置 ...
}

var isShowingThumbnailPreview: Bool {
    currentPreviewContent.isThumbnail
}

func requestThumbnail(
    using previewProvider: BoardPreviewProvider,
    for item: BoardCatalogItem,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()

    thumbnailRequestToken = previewProvider.requestThumbnail(
        for: item,
        targetPixelSize: targetThumbnailPixelSize(for: displayMode)
    ) { [weak self] previewContent in
        guard
            let self,
            let previewContent,
            self.representedBoardID == item.boardID,
            self.representedRevisionToken == item.revisionToken
        else {
            return
        }

        self.currentPreviewContent = previewContent
        self.previewView.apply(content: previewContent)
    }
}
```

## 本阶段结果

- closing target-ready 成功路径已经不再依赖整页 `reloadBoardList()` / `collectionView.reloadData()`。
- `prepareTransitionTargetGeometry(...)` 到 `finishPendingTransitionTargetResolution(...)` 之间，现在只围绕目标板做：
  - 单板读取
  - 单板 upsert
  - 局部 collection mutation
  - 目标几何解析
- `cellForItemAt` 在 closing target-ready 期间会切成 `.geometryOnly`，避免无关卡片同步进入 `immediatePreview(...)`。
- target geometry 一旦解析完成，会恢复 `.normal` 预览策略，并异步补当前 visible cell 的 thumbnail。
- `hasCardRect` 的解析路径现在带有更明确的 trace 语义，能区分：
  - 走目标 cell 的真实几何
  - 走 `layoutAttributesForItem(at:)` 的 fallback 几何

## 仍留给后续阶段的工作

- 本阶段没有修改 `BoardPreviewProvider` 内部 trace / cache-hit 的诊断副作用。
- 也就是说，虽然 closing target-ready 已经不再因为整页 reload 被堵住，但 `Phase 5` 仍需要继续处理：
  - `logBoardPreviewProviderCacheHit()`
  - `logBoardPreviewProviderSourceImagesIfNeeded()`
  - trace 驱动下的源图读取与诊断放大

## 验证

- 已对以下文件执行 `ReadLints`：
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 当前结果：无 linter 报错。
- 本次未执行完整 iOS 构建；因此这里记录的是源码级与静态检查级确认结果。
