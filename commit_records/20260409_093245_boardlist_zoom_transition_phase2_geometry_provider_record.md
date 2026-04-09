# 20260409_093245_boardlist_zoom_transition_phase2_geometry_provider_record

## 记录范围

- 记录内容：实施 `boardlist缩放转场` 计划的 `Phase 2`，补齐 `BoardList` 的 source rect 与 target reveal 提供能力。
- 记录内容：让双端 `BoardList` 在打开时输出 `sourceGeometry`，在返回时复用现有 `pendingRevealBoardID -> revealPendingBoardIfNeeded()` 链路产出 `targetGeometry`。
- 记录内容：让双端 `AppRoot` 在收到 `BoardListCanvasReturnRequest` 后，先请求 `BoardList` 准备 target geometry，再把结果回填到当前 `transitionContext`。
- 记录依据：本记录基于当前工作树的 `git status --short` 与本次相关文件的 `git diff -- [paths]`，并结合修改后的源码内容整理。
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- 本记录不包含：`Phase 3` 的 `AppRoot` 显式状态机与 `TransitionCarrier`。
- 本记录不包含：`Phase 4/5` 的 opening / closing 动画实现。
- 本记录不包含：新的 `.md` 以外文档。
- 本记录不包含：git commit。

## 修改一：双端卡片 cell/item 新增转场几何导出能力

### 修改前

- `iOSBoardCollectionViewCell` / `macOSBoardCollectionItem` 只负责缩略图请求、预览渲染和标题/更多按钮展示。
- 卡片本身没有对外暴露“整体卡片 rect”或“preview rect”，上层即使知道点击的是哪个 entry，也拿不到稳定的 source geometry。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/符号名: requestThumbnail(using:for:displayMode:) / setupView()
// 功能说明: 修改前 iOS cell 只有缩略图与视图装配职责，没有导出转场几何的接口。
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

private func setupView() {
    contentView.layer.cornerRadius = 12
    contentView.layer.masksToBounds = true
    // ... 省略其余视图装配 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/符号名: requestThumbnail(using:for:displayMode:) / setupView()
// 功能说明: 修改前 macOS item 与 iOS 同构，也没有对外提供卡片几何导出能力。
func requestThumbnail(
    using previewProvider: BoardPreviewProvider,
    for item: BoardCatalogItem,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest(reason: "requestThumbnail-restart")
    let targetPixelSize = targetThumbnailPixelSize(for: displayMode)

    thumbnailRequestToken = previewProvider.requestThumbnail(
        for: item,
        targetPixelSize: targetPixelSize
    ) { [weak self] previewContent in
        guard let self else {
            return
        }
        guard let previewContent else {
            return
        }
        // ... 省略回调校验与 apply ...
    }
}

private func setupView() {
    view.wantsLayer = true
    view.layer?.cornerRadius = 12
    view.layer?.masksToBounds = true
    // ... 省略其余视图装配 ...
}
```

### 修改后

- 双端卡片组件新增 `transitionGeometry(in:)`。
- 该方法会导出：
  - `cardRect`：卡片整体区域
  - `previewRect`：预览区区域；若当前 presentation 隐藏 preview，则返回 `nil`
- 这样 `BoardListViewController` 在拿到 indexPath 后，可以直接把几何信息注入 `BoardListCanvasOpenRequest`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/符号名: transitionGeometry(in:)
// 功能说明: iOS cell 现在可以把卡片整体区域和可见 preview 区域导出到共享转场几何模型中。
func transitionGeometry(
    in coordinateSpaceView: UIView
) -> BoardListCanvasTransitionSourceGeometry {
    contentView.layoutIfNeeded()
    let cardRect = coordinateSpaceView.convert(
        contentView.bounds,
        from: contentView
    )
    let previewRect: CGRect?
    if previewView.isHidden {
        previewRect = nil
    } else {
        previewRect = coordinateSpaceView.convert(
            previewView.bounds,
            from: previewView
        )
    }

    return BoardListCanvasTransitionSourceGeometry(
        cardRect: cardRect,
        previewRect: previewRect
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/符号名: transitionGeometry(in:)
// 功能说明: macOS item 对齐 iOS，实现同构的卡片/preview 几何导出接口。
func transitionGeometry(
    in coordinateSpaceView: NSView
) -> BoardListCanvasTransitionSourceGeometry {
    view.layoutSubtreeIfNeeded()
    let cardRect = coordinateSpaceView.convert(
        view.bounds,
        from: view
    )
    let previewRect: CGRect?
    if previewView.isHidden {
        previewRect = nil
    } else {
        previewRect = coordinateSpaceView.convert(
            previewView.bounds,
            from: previewView
        )
    }

    return BoardListCanvasTransitionSourceGeometry(
        cardRect: cardRect,
        previewRect: previewRect
    )
}
```

## 修改二：双端 `BoardListViewController` 把“点击入口”和“几何解析能力”拆开

### 修改前

- `prepareForDisplay()` 只负责刷新 bookmark/catalog。
- `BoardListViewController` 没有公开的 source provider / target provider。
- 上层只能拿到 open request / return request，无法通过 `BoardList` 进一步解析卡片几何。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: prepareForDisplay()
// 功能说明: 修改前 iOS BoardList 只有“刷新列表”入口，没有 source geometry 或 target reveal provider。
func prepareForDisplay() {
    guard isViewLoaded else {
        return
    }

    refreshBookmarkStatus()
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    // ... 省略其余视图装配 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/符号名: prepareForDisplay()
// 功能说明: 修改前 macOS BoardList 与 iOS 相同，也没有独立的几何提供接口。
func prepareForDisplay() {
    guard isViewLoaded else {
        return
    }

    refreshBookmarkStatus()
}

private func logSelectionTrace(_ phase: String, extra: String = "") {
    // ... 省略日志实现 ...
}
```

### 修改后

- 双端都新增了：
  - `transitionSourceGeometry(for:)`
  - `prepareTransitionTargetGeometry(for:completion:)`
- `prepareTransitionTargetGeometry(...)` 会先设置：
  - `pendingRevealBoardID`
  - `pendingTransitionTargetResolution`
- 如果列表当前已经挂载到窗口，会立刻触发 `refreshBookmarkStatus()`，把返回目标解析统一导向现有 reveal 链。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: transitionSourceGeometry(for:) / prepareTransitionTargetGeometry(for:completion:)
// 功能说明: iOS BoardList 现在对上层暴露统一的 source provider 与 target provider，上层无需感知 collectionView 细节。
func transitionSourceGeometry(
    for entryID: BoardListEntryID
) -> BoardListCanvasTransitionSourceGeometry {
    guard let indexPath = indexPath(for: entryID) else {
        return .init()
    }

    return transitionSourceGeometry(at: indexPath)
}

func prepareTransitionTargetGeometry(
    for boardID: UUID?,
    completion: @escaping (BoardListCanvasTransitionTargetGeometry) -> Void
) {
    pendingTransitionTargetResolution = nil

    guard let boardID else {
        pendingRevealBoardID = nil
        completion(.init())
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

    refreshBookmarkStatus()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/符号名: transitionSourceGeometry(for:) / prepareTransitionTargetGeometry(for:completion:)
// 功能说明: macOS BoardList 对齐 iOS，也把几何采集与 reveal 驱动封装成统一 provider。
func transitionSourceGeometry(
    for entryID: BoardListEntryID
) -> BoardListCanvasTransitionSourceGeometry {
    guard let indexPath = indexPath(for: entryID) else {
        return .init()
    }

    return transitionSourceGeometry(at: indexPath)
}

func prepareTransitionTargetGeometry(
    for boardID: UUID?,
    completion: @escaping (BoardListCanvasTransitionTargetGeometry) -> Void
) {
    pendingTransitionTargetResolution = nil

    guard let boardID else {
        pendingRevealBoardID = nil
        completion(.init())
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

    refreshBookmarkStatus()
}
```

## 修改三：打开 request 现在直接携带 source geometry

### 修改前

- `makeOpenRequest(for:)` 只根据 entry 类型生成业务语义：
  - `.newBoardPlaceholder()`
  - `.existingBoard(boardID:)`
- 虽然 `Phase 1` 已经有 `sourceGeometry` 字段，但 `BoardList` 还没有真正把卡片几何填进去。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: makeOpenRequest(for:)
// 功能说明: 修改前 iOS 打开链只有业务语义，没有把点击卡片的几何信息写入 open request。
private func makeOpenRequest(
    for entry: BoardListEntry
) -> BoardListCanvasOpenRequest {
    switch entry {
    case .newBoardPlaceholder:
        return .newBoardPlaceholder()
    case let .board(item):
        return .existingBoard(boardID: item.boardID)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/符号名: makeOpenRequest(for:)
// 功能说明: 修改前 macOS 打开链也没有把 source rect / preview rect 注入 open request。
private func makeOpenRequest(
    for entry: BoardListEntry
) -> BoardListCanvasOpenRequest {
    switch entry {
    case .newBoardPlaceholder:
        return .newBoardPlaceholder()
    case let .board(item):
        return .existingBoard(boardID: item.boardID)
    }
}
```

### 修改后

- `makeOpenRequest(for:)` 先通过 `transitionSourceGeometry(for: entry.id)` 解析 source geometry。
- 然后把解析结果直接塞进共享的 open request。
- 这样 `AppRoot` 收到 request 的第一时间，就已经具备从哪张卡片放大的几何上下文。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: makeOpenRequest(for:)
// 功能说明: iOS 打开链现在会把 source card rect / preview rect 写入 open request。
private func makeOpenRequest(
    for entry: BoardListEntry
) -> BoardListCanvasOpenRequest {
    let sourceGeometry = transitionSourceGeometry(for: entry.id)
    switch entry {
    case .newBoardPlaceholder:
        return .newBoardPlaceholder(geometry: sourceGeometry)
    case let .board(item):
        return .existingBoard(
            boardID: item.boardID,
            geometry: sourceGeometry
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/符号名: makeOpenRequest(for:)
// 功能说明: macOS 打开链与 iOS 对齐，统一通过共享 request 把 source geometry 往上抛。
private func makeOpenRequest(
    for entry: BoardListEntry
) -> BoardListCanvasOpenRequest {
    let sourceGeometry = transitionSourceGeometry(for: entry.id)
    switch entry {
    case .newBoardPlaceholder:
        return .newBoardPlaceholder(geometry: sourceGeometry)
    case let .board(item):
        return .existingBoard(
            boardID: item.boardID,
            geometry: sourceGeometry
        )
    }
}
```

## 修改四：返回目标解析复用现有 reveal 链，并在 reveal 后产出 `targetGeometry`

### 修改前

- `revealPendingBoardIfNeeded()` / `revealBoard(...)` 只负责滚动到目标卡片。
- 目标解析成功或失败时，都不会给上层任何 geometry 回调。
- 这意味着返回时即使已经知道目标 `boardID`，容器层也拿不到“缩回哪张卡片”的 rect。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: revealPendingBoardIfNeeded() / revealBoard(at:boardID:)
// 功能说明: 修改前 iOS reveal 链只做滚动，不会把解析到的目标几何返回给上层。
private func revealPendingBoardIfNeeded() {
    guard let pendingRevealBoardID else {
        return
    }

    guard let indexPath = indexPath(for: pendingRevealBoardID) else {
        self.pendingRevealBoardID = nil
        return
    }

    DispatchQueue.main.async { [weak self] in
        self?.revealBoard(
            at: indexPath,
            boardID: pendingRevealBoardID
        )
    }
}

private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard pendingRevealBoardID == boardID else {
        return
    }

    collectionView.layoutIfNeeded()
    collectionView.scrollToItem(
        at: indexPath,
        at: .top,
        animated: false
    )
    pendingRevealBoardID = nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/符号名: revealPendingBoardIfNeeded() / revealBoard(at:boardID:)
// 功能说明: 修改前 macOS reveal 链同样只有滚动语义，没有 target geometry 回调。
private func revealPendingBoardIfNeeded() {
    guard let pendingRevealBoardID else {
        return
    }

    guard let indexPath = indexPath(for: pendingRevealBoardID) else {
        self.pendingRevealBoardID = nil
        return
    }

    DispatchQueue.main.async { [weak self] in
        self?.revealBoard(
            at: indexPath,
            boardID: pendingRevealBoardID
        )
    }
}

private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard pendingRevealBoardID == boardID else {
        return
    }

    collectionView.layoutSubtreeIfNeeded()
    collectionView.scrollToItems(
        at: Set([indexPath]),
        scrollPosition: .nearestVerticalEdge
    )
    pendingRevealBoardID = nil
}
```

### 修改后

- 新增 `transitionTargetGeometry(for:)`、`transitionCardRect(at:)`、`finishPendingTransitionTargetResolution(...)`。
- reveal 链在两种情况下都会回调：
  - 目标索引找不到：回调空几何 `.init()`
  - 目标卡片 reveal 完成：回调真实 `targetGeometry`
- 对于不可见 cell/item，会回退到 `layoutAttributesForItem(at:)` 生成 `cardRect`，避免“必须拿到可见实例”才能做返回转场。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: transitionTargetGeometry(for:) / transitionCardRect(at:) / finishPendingTransitionTargetResolution(for:geometry:) / revealPendingBoardIfNeeded() / revealBoard(at:boardID:)
// 功能说明: iOS 侧把原有 reveal 链扩展为“滚动 + 目标几何回填”的统一返回解析链。
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

private func transitionCardRect(at indexPath: IndexPath) -> CGRect? {
    collectionView.layoutIfNeeded()
    guard let layoutAttributes = collectionView.layoutAttributesForItem(at: indexPath) else {
        return nil
    }

    return view.convert(
        layoutAttributes.frame,
        from: collectionView
    )
}

private func finishPendingTransitionTargetResolution(
    for boardID: UUID,
    geometry: BoardListCanvasTransitionTargetGeometry
) {
    guard pendingTransitionTargetResolution?.boardID == boardID else {
        return
    }

    let completion = pendingTransitionTargetResolution?.completion
    pendingTransitionTargetResolution = nil
    completion?(geometry)
}

private func revealPendingBoardIfNeeded() {
    guard let pendingRevealBoardID else {
        return
    }

    guard let indexPath = indexPath(for: pendingRevealBoardID) else {
        finishPendingTransitionTargetResolution(
            for: pendingRevealBoardID,
            geometry: .init()
        )
        self.pendingRevealBoardID = nil
        return
    }

    DispatchQueue.main.async { [weak self] in
        self?.revealBoard(
            at: indexPath,
            boardID: pendingRevealBoardID
        )
    }
}

private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard pendingRevealBoardID == boardID else {
        return
    }

    collectionView.layoutIfNeeded()
    collectionView.scrollToItem(
        at: indexPath,
        at: .top,
        animated: false
    )
    collectionView.layoutIfNeeded()
    finishPendingTransitionTargetResolution(
        for: boardID,
        geometry: transitionTargetGeometry(for: boardID)
    )
    pendingRevealBoardID = nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/符号名: transitionTargetGeometry(for:) / transitionCardRect(at:) / finishPendingTransitionTargetResolution(for:geometry:) / revealPendingBoardIfNeeded() / revealBoard(at:boardID:)
// 功能说明: macOS 侧复用同一条 pendingRevealBoardID 链，在 reveal 完成后统一产出 target geometry。
private func transitionTargetGeometry(
    for boardID: UUID
) -> BoardListCanvasTransitionTargetGeometry {
    guard let indexPath = indexPath(for: boardID) else {
        return .init()
    }

    if let item = collectionView.item(at: indexPath) as? macOSBoardCollectionItem {
        return BoardListCanvasTransitionTargetGeometry(
            cardRect: item.transitionGeometry(in: view).cardRect
        )
    }

    return BoardListCanvasTransitionTargetGeometry(
        cardRect: transitionCardRect(at: indexPath)
    )
}

private func transitionCardRect(at indexPath: IndexPath) -> CGRect? {
    collectionView.layoutSubtreeIfNeeded()
    guard let layoutAttributes = collectionView.collectionViewLayout?
        .layoutAttributesForItem(at: indexPath) else {
        return nil
    }

    return view.convert(
        layoutAttributes.frame,
        from: collectionView
    )
}

private func finishPendingTransitionTargetResolution(
    for boardID: UUID,
    geometry: BoardListCanvasTransitionTargetGeometry
) {
    guard pendingTransitionTargetResolution?.boardID == boardID else {
        return
    }

    let completion = pendingTransitionTargetResolution?.completion
    pendingTransitionTargetResolution = nil
    completion?(geometry)
}

private func revealPendingBoardIfNeeded() {
    guard let pendingRevealBoardID else {
        return
    }

    guard let indexPath = indexPath(for: pendingRevealBoardID) else {
        finishPendingTransitionTargetResolution(
            for: pendingRevealBoardID,
            geometry: .init()
        )
        self.pendingRevealBoardID = nil
        return
    }

    DispatchQueue.main.async { [weak self] in
        self?.revealBoard(
            at: indexPath,
            boardID: pendingRevealBoardID
        )
    }
}

private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard pendingRevealBoardID == boardID else {
        return
    }

    collectionView.layoutSubtreeIfNeeded()
    collectionView.scrollToItems(
        at: Set([indexPath]),
        scrollPosition: .nearestVerticalEdge
    )
    collectionView.layoutSubtreeIfNeeded()
    finishPendingTransitionTargetResolution(
        for: boardID,
        geometry: transitionTargetGeometry(for: boardID)
    )
    pendingRevealBoardID = nil
}
```

## 修改五：双端 `AppRoot` 返回链开始消费 `BoardList` 的 target geometry provider

### 修改前

- `handleCanvasReturnRequest(_:)` 只会：
  - 暂存 `request.transitionContext`
  - 立即 `display(.boardList)`
- 容器层虽然已经拿到了 closing request，但不会主动向 `BoardList` 取回 reveal 后的 target geometry。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: handleCanvasReturnRequest(_:)
// 功能说明: 修改前 iOS AppRoot 返回链只切页，不会补 target geometry。
private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    display(.boardList)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: handleCanvasReturnRequest(_:)
// 功能说明: 修改前 macOS AppRoot 返回链与 iOS 相同，只持有 closing context，不补 target geometry。
private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    display(.boardList)
}
```

### 修改后

- `AppRoot` 返回链现在会先读取 `request.transitionContext.targetBoardID`。
- 然后调用 `boardListViewController.prepareTransitionTargetGeometry(...)`。
- 准备完成后，通过 `updateCurrentTransitionTargetGeometry(...)` 回填到当前的 `transitionContext.targetGeometry`。
- 这样后续 `Phase 3/5` 做协调器和 closing 动画时，容器层已经不需要再改回调契约。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: handleCanvasReturnRequest(_:) / updateCurrentTransitionTargetGeometry(_:expectedBoardID:)
// 功能说明: iOS AppRoot 在返回列表前先请求 BoardList 准备目标几何，并把结果写回当前 closing context。
private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    let targetBoardID = request.transitionContext.targetBoardID
    boardListViewController.prepareTransitionTargetGeometry(
        for: targetBoardID
    ) { [weak self] geometry in
        self?.updateCurrentTransitionTargetGeometry(
            geometry,
            expectedBoardID: targetBoardID
        )
    }
    display(.boardList)
}

private func updateCurrentTransitionTargetGeometry(
    _ geometry: BoardListCanvasTransitionTargetGeometry,
    expectedBoardID: UUID?
) {
    guard
        var context = currentBoardListCanvasTransitionContext,
        context.direction == .closing,
        context.targetBoardID == expectedBoardID
    else {
        return
    }

    context.targetGeometry = geometry
    currentBoardListCanvasTransitionContext = context
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: handleCanvasReturnRequest(_:) / updateCurrentTransitionTargetGeometry(_:expectedBoardID:)
// 功能说明: macOS AppRoot 与 iOS 对齐，把 BoardList reveal 后解析到的目标几何回填到 closing context。
private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    let targetBoardID = request.transitionContext.targetBoardID
    boardListViewController.prepareTransitionTargetGeometry(
        for: targetBoardID
    ) { [weak self] geometry in
        self?.updateCurrentTransitionTargetGeometry(
            geometry,
            expectedBoardID: targetBoardID
        )
    }
    display(.boardList)
}

private func updateCurrentTransitionTargetGeometry(
    _ geometry: BoardListCanvasTransitionTargetGeometry,
    expectedBoardID: UUID?
) {
    guard
        var context = currentBoardListCanvasTransitionContext,
        context.direction == .closing,
        context.targetBoardID == expectedBoardID
    else {
        return
    }

    context.targetGeometry = geometry
    currentBoardListCanvasTransitionContext = context
}
```

## 行为结果

- 打开已有板或新建占位时，`BoardListCanvasOpenRequest` 已经会携带当前卡片的 `sourceGeometry`。
- 返回列表时，`AppRoot` 不再只知道“要回到哪个 boardID”，还会等待 `BoardList` 基于现有 reveal 链准备 `targetGeometry`。
- `BoardList` 现在同时支持：
  - 可见卡片：直接从真实 cell/item 导出 geometry
  - 不可见卡片：回退到 `layoutAttributesForItem(at:)` 解析 `cardRect`
- `pendingRevealBoardID -> revealPendingBoardIfNeeded()` 仍然是唯一的返回目标解析入口，没有新增第二套隐藏路径。

## 校验结果

- 当前工作树在记录前的相关变更为：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 已通过 `ReadLints` 检查上述修改文件，未发现新的 lint 错误。
- 已执行并通过以下语法解析命令：
  - `xcrun --sdk macosx swiftc -frontend -parse "MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionGeometry.swift" "MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionState.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift" "MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift" "MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift"`
- iOS 侧本轮仍以 IDE lint 结果为主，没有额外执行完整 iOS SDK 编译解析。

## 后续衔接

- `Phase 3` 可以直接在现有的 `sourceGeometry` / `targetGeometry` / `transitionContext` 基础上搭 `AppRoot` 协调器。
- 后续如果从 `SnapshotShellCarrier` 升级到 `LiveCanvasCarrier`，仍然复用本阶段产出的 `BoardList` source/target provider，不需要回头重写列表侧几何解析。
