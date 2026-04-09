# 20260409_181025_split_update_time_implementation_record

## 记录说明

本记录基于当前工作区的 `git diff` 与已落地代码整理，不包含原始 `git diff` 文本。

关联计划：`.cursor/plans/split_update_time_d25b3de4.plan.md`

本次实现只覆盖刚刚落地的 12 个 Swift 文件：

- `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
- `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前统计：`12 files changed, 412 insertions(+), 93 deletions(-)`

## 变更目标

这次修改的目标是把单一 `updatedAt` 拆成：

- `contentUpdatedAt`：只代表内容更新时间
- `viewStateUpdatedAt`：只代表视图状态更新时间

同时把以下消费方统一迁到内容时间语义：

- boardlist 排序
- revision token
- persisted thumbnail freshness
- preview 加载链路

这样可以保留视图状态持久化，但不再因为打开画板、缩放、平移、minimap 导航、workspace 切换而把卡片顶到第一行。

## 详细记录

### 1. `BoardDocument.swift`：拆分双时间线并补兼容解码

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数/结构: BoardSummary / BoardRuntimeState / BoardDocument
// 节选: 这里只有单一 updatedAt，内容时间和视图时间完全混在一起。
struct BoardSummary {
    let boardID: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
}

struct BoardRuntimeState {
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var items: [CanvasBoardItem]
    var boardState: CanvasBoardState?
    var camera: CanvasCamera
    var interactionState: CanvasInteractionState
    var workspaceMode: CanvasWorkspaceMode
}

struct BoardDocument: Codable {
    let formatVersion: Int
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var boardBaseSize: BoardSizeRecord?
    var boardRect: BoardRectRecord?
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double
    var selectedItemID: UUID?
    var workspaceMode: CanvasWorkspaceMode?
    var items: [BoardItemRecord]
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数/结构: BoardSummary / BoardRuntimeState / BoardDocument
// 节选: 新增 contentUpdatedAt / viewStateUpdatedAt，并保留 updatedAt 兼容访问器给旧消费点过渡。
struct BoardSummary {
    let boardID: UUID
    let title: String
    let createdAt: Date
    let contentUpdatedAt: Date
    let viewStateUpdatedAt: Date

    var updatedAt: Date {
        contentUpdatedAt
    }
}

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

    var updatedAt: Date {
        contentUpdatedAt
    }
}

struct BoardDocument: Codable {
    // ... 其他字段保持不变
    var contentUpdatedAt: Date
    var viewStateUpdatedAt: Date

    var contentState: BoardDocumentContentState {
        BoardDocumentContentState(
            title: title,
            boardRect: boardRect,
            items: items
        )
    }

    var viewState: BoardDocumentViewState {
        BoardDocumentViewState(
            boardBaseSize: boardBaseSize,
            cameraCenter: cameraCenter,
            cameraZoomScale: cameraZoomScale,
            selectedItemID: selectedItemID,
            workspaceMode: workspaceMode
        )
    }

    init(from decoder: Decoder) throws {
        let legacyUpdatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .updatedAt
        ) ?? createdAt
        contentUpdatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .contentUpdatedAt
        ) ?? legacyUpdatedAt
        viewStateUpdatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .viewStateUpdatedAt
        ) ?? legacyUpdatedAt
    }

    func encode(to encoder: Encoder) throws {
        try container.encode(contentUpdatedAt, forKey: .updatedAt)
        try container.encode(contentUpdatedAt, forKey: .contentUpdatedAt)
        try container.encode(viewStateUpdatedAt, forKey: .viewStateUpdatedAt)
    }
}
```

补充说明：

- 同文件新增了 `BoardDocumentContentState` 与 `BoardDocumentViewState`，作为后续持久化比较的边界模型。
- `BoardImageItemRecord`、`BoardTextItemRecord`、`BoardItemRecord`、`BoardPointRecord`、`BoardRectRecord` 等记录类型统一补了 `Equatable`，用于比较内容域/视图域是否真的发生变化。

### 2. `BoardDocumentMapper.swift`：运行时与文档双向映射切到新字段

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数: makeDocument(from:) / makeRuntimeState(from:imageLoader:)
// 节选: mapper 读写的还是旧的 updatedAt。
return BoardDocument(
    formatVersion: BoardDocument.currentFormatVersion,
    boardID: runtimeState.boardID,
    title: runtimeState.title,
    createdAt: runtimeState.createdAt,
    updatedAt: runtimeState.updatedAt,
    // ...
)

let runtimeState = BoardRuntimeState(
    boardID: document.boardID,
    title: document.title,
    createdAt: document.createdAt,
    updatedAt: document.updatedAt,
    // ...
)
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数: makeDocument(from:) / makeRuntimeState(from:imageLoader:)
// 节选: mapper 已经改成在运行时和持久化之间搬运两条时间线。
return BoardDocument(
    formatVersion: BoardDocument.currentFormatVersion,
    boardID: runtimeState.boardID,
    title: runtimeState.title,
    createdAt: runtimeState.createdAt,
    contentUpdatedAt: runtimeState.contentUpdatedAt,
    viewStateUpdatedAt: runtimeState.viewStateUpdatedAt,
    // ...
)

let runtimeState = BoardRuntimeState(
    boardID: document.boardID,
    title: document.title,
    createdAt: document.createdAt,
    contentUpdatedAt: document.contentUpdatedAt,
    viewStateUpdatedAt: document.viewStateUpdatedAt,
    // ...
)
```

### 3. `BoardHistorySnapshot.swift`：历史恢复不再强制刷新单一时间戳

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数: replacingDocumentState(with:updatedAt:)
// 节选: 历史恢复会直接注入一个新的 updatedAt。
func replacingDocumentState(
    with snapshot: BoardHistorySnapshot,
    updatedAt: Date = Date()
) -> BoardRuntimeState {
    BoardRuntimeState(
        boardID: boardID,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        items: snapshot.items,
        boardState: snapshot.boardState,
        camera: camera,
        interactionState: snapshot.interactionState,
        workspaceMode: workspaceMode
    )
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数: replacingDocumentState(with:contentUpdatedAt:viewStateUpdatedAt:)
// 节选: 历史恢复默认沿用原有时间线，只在调用方显式传入时才替换对应域。
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
        boardState: snapshot.boardState,
        camera: camera,
        interactionState: snapshot.interactionState,
        workspaceMode: workspaceMode
    )
}
```

### 4. `BoardSaveCoordinator.swift`：为保存链路引入显式更新分类

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift
// 函数/结构: BoardSaveSnapshot
// 节选: 保存快照不区分内容保存和视图保存。
struct BoardSaveSnapshot {
    let runtimeState: BoardRuntimeState
    let transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload]
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift
// 函数/结构: BoardPersistenceUpdateKind / BoardSaveSnapshot
// 节选: 保存快照现在显式携带 updateKind，供存储层判断该 bump 哪条时间线。
enum BoardPersistenceUpdateKind {
    case contentOnly
    case viewStateOnly
    case contentAndViewState

    var affectsContent: Bool {
        switch self {
        case .contentOnly, .contentAndViewState:
            return true
        case .viewStateOnly:
            return false
        }
    }

    var affectsViewState: Bool {
        switch self {
        case .viewStateOnly, .contentAndViewState:
            return true
        case .contentOnly:
            return false
        }
    }
}

struct BoardSaveSnapshot {
    let runtimeState: BoardRuntimeState
    let transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload]
    let updateKind: BoardPersistenceUpdateKind
}
```

### 5. `CanvasEditorSession.swift`：去掉“构造快照就刷新时间”的隐式行为

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数: currentBoardRuntimeState(createBoardIfNeeded:) / scheduleAutosave(reason:) / currentBoardSaveSnapshot(createBoardIfNeeded:)
// 节选: 运行时快照直接写 Date()，autosave 也没有更新类型。
func scheduleAutosave(reason: String) {
    guard let snapshot = currentBoardSaveSnapshot() else {
        return
    }
    saveCoordinator.scheduleAutosave(
        snapshot: snapshot,
        reason: reason
    )
}

func currentBoardRuntimeState(
    createBoardIfNeeded: Bool = false
) -> BoardRuntimeState? {
    // ...
    return BoardRuntimeState(
        boardID: activeBoardID,
        title: activeBoardTitle,
        createdAt: activeBoardCreatedAt,
        updatedAt: Date(),
        items: scene.orderedBoardItems(),
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        workspaceMode: workspaceMode
    )
}

func currentBoardSaveSnapshot(
    createBoardIfNeeded: Bool = false
) -> BoardSaveSnapshot? {
    BoardSaveSnapshot(
        runtimeState: runtimeState,
        transientImageAssetPayloads: payloads
    )
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数: applyBoardRuntimeState(_:) / scheduleAutosave(reason:updateKind:) / currentBoardRuntimeState(createBoardIfNeeded:) / currentBoardSaveSnapshot(createBoardIfNeeded:updateKind:)
// 节选: 会话层开始显式记住当前 board 的两条时间线，并把 updateKind 透传到保存链路。
private(set) var activeBoardContentUpdatedAt: Date?
private(set) var activeBoardViewStateUpdatedAt: Date?

func applyBoardRuntimeState(
    _ runtimeState: BoardRuntimeState,
    preserveTransientImageAssetPayloads: Bool = false
) {
    activeBoardID = runtimeState.boardID
    activeBoardTitle = runtimeState.title
    activeBoardCreatedAt = runtimeState.createdAt
    activeBoardContentUpdatedAt = runtimeState.contentUpdatedAt
    activeBoardViewStateUpdatedAt = runtimeState.viewStateUpdatedAt
    // ...
}

func scheduleAutosave(
    reason: String,
    updateKind: BoardPersistenceUpdateKind = .contentAndViewState
) {
    guard let snapshot = currentBoardSaveSnapshot(updateKind: updateKind) else {
        return
    }
    saveCoordinator.scheduleAutosave(
        snapshot: snapshot,
        reason: reason
    )
}

func currentBoardRuntimeState(
    createBoardIfNeeded: Bool = false
) -> BoardRuntimeState? {
    // ...
    return BoardRuntimeState(
        boardID: activeBoardID,
        title: activeBoardTitle,
        createdAt: activeBoardCreatedAt,
        contentUpdatedAt: activeBoardContentUpdatedAt,
        viewStateUpdatedAt: activeBoardViewStateUpdatedAt,
        items: scene.orderedBoardItems(),
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        workspaceMode: workspaceMode
    )
}

func currentBoardSaveSnapshot(
    createBoardIfNeeded: Bool = false,
    updateKind: BoardPersistenceUpdateKind = .contentAndViewState
) -> BoardSaveSnapshot? {
    BoardSaveSnapshot(
        runtimeState: runtimeState,
        transientImageAssetPayloads: payloads,
        updateKind: updateKind
    )
}
```

补充说明：

- `ensureActiveBoardIdentityIfNeeded()` 也同步补了 `activeBoardContentUpdatedAt` 与 `activeBoardViewStateUpdatedAt` 的初始化兜底，避免新建空白板时只有 ID/createdAt，没有时间线。

### 6. `BoardStore.swift`：保存前合并旧文档，只更新发生变化的域

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数: saveBoard(_:userDefaults:) / renameBoard(id:title:userDefaults:) / listBoardDocumentEntries(userDefaults:)
// 节选: 保存时统一写 updatedAt，重命名也直接改 updatedAt，列表排序按 updatedAt 倒序。
var persistedState = snapshot.runtimeState
persistedState.updatedAt = Date()
let persistedSnapshot = BoardSaveSnapshot(
    runtimeState: persistedState,
    transientImageAssetPayloads: snapshot.transientImageAssetPayloads
)
let document = BoardDocumentMapper.makeDocument(from: persistedState)

try removeOrphanedAssets(
    keeping: document.referencedAssetFilenames,
    in: assetsDirectoryURL
)

try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
persistBoardThumbnailIfPossible(
    from: persistedState,
    boardDirectoryURL: boardDirectoryURL
)

document.title = normalizedTitle
document.updatedAt = Date()

return entries.sorted { lhs, rhs in
    if lhs.document.updatedAt == rhs.document.updatedAt {
        return lhs.document.boardID.uuidString < rhs.document.boardID.uuidString
    }
    return lhs.document.updatedAt > rhs.document.updatedAt
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数: saveBoard(_:userDefaults:) / renameBoard(id:title:userDefaults:) / listBoardDocumentEntries(userDefaults:)
// 节选: 保存前先读旧文档，按 updateKind 合并 contentState / viewState，并只 bump 实际变化的时间线。
let boardDocumentURL = boardDirectoryURL.appendingPathComponent(
    boardDocumentFilename
)
let existingDocument: BoardDocument?
if FileManager.default.fileExists(atPath: boardDocumentURL.path) {
    existingDocument = try readBoardDocument(at: boardDocumentURL)
} else {
    existingDocument = nil
}

var document = BoardDocumentMapper.makeDocument(from: snapshot.runtimeState)
if let existingDocument {
    if snapshot.updateKind.affectsContent == false {
        document.replaceContentState(with: existingDocument)
    }
    if snapshot.updateKind.affectsViewState == false {
        document.replaceViewState(with: existingDocument)
    }
}

let now = Date()
let contentChanged = existingDocument.map {
    document.contentState != $0.contentState
} ?? true
let viewStateChanged = existingDocument.map {
    document.viewState != $0.viewState
} ?? true
document.contentUpdatedAt = existingDocument.map {
    contentChanged ? now : $0.contentUpdatedAt
} ?? now
document.viewStateUpdatedAt = existingDocument.map {
    viewStateChanged ? now : $0.viewStateUpdatedAt
} ?? now

var persistedState = snapshot.runtimeState
persistedState.contentUpdatedAt = document.contentUpdatedAt
persistedState.viewStateUpdatedAt = document.viewStateUpdatedAt
```

继续修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数: saveBoard(_:userDefaults:) / renameBoard(id:title:userDefaults:) / listBoardDocumentEntries(userDefaults:)
// 节选: 只有内容变化时才重建 thumbnail、校验资产和更新列表排序语义。
if contentChanged {
    try removeOrphanedAssets(
        keeping: document.referencedAssetFilenames,
        in: assetsDirectoryURL
    )
}

let encodedDocument = try makeDocumentData(for: document)
try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)

if contentChanged {
    persistBoardThumbnailIfPossible(
        from: persistedState,
        boardDirectoryURL: boardDirectoryURL
    )
}

document.title = normalizedTitle
document.contentUpdatedAt = Date()

return entries.sorted { lhs, rhs in
    if lhs.document.contentUpdatedAt == rhs.document.contentUpdatedAt {
        return lhs.document.boardID.uuidString < rhs.document.boardID.uuidString
    }
    return lhs.document.contentUpdatedAt > rhs.document.contentUpdatedAt
}
```

补充说明：

- 这里是本次根因修复的核心：`view-only` 保存会继续写回文档里的视图态，但不会误伤内容态、缩略图和列表顺序。

### 7. `BoardCatalogItem.swift`：revision token 改为只绑定内容时间

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数/结构: BoardCatalogItem.updatedAt / BoardCatalogItem.revisionToken
// 节选: revision token 直接依赖 updatedAt。
var updatedAt: Date {
    document.updatedAt
}

var revisionToken: String {
    "\(boardID.uuidString)-\(updatedAt.timeIntervalSince1970)"
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数/结构: BoardCatalogItem.contentUpdatedAt / BoardCatalogItem.viewStateUpdatedAt / BoardCatalogItem.revisionToken
// 节选: catalog item 对外同时暴露两条时间线，但 revision 只认内容时间。
var contentUpdatedAt: Date {
    document.contentUpdatedAt
}

var viewStateUpdatedAt: Date {
    document.viewStateUpdatedAt
}

var updatedAt: Date {
    contentUpdatedAt
}

var revisionToken: String {
    "\(boardID.uuidString)-\(contentUpdatedAt.timeIntervalSince1970)"
}
```

### 8. `BoardPersistedThumbnailStore.swift`：persisted thumbnail freshness 改看内容时间

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数: loadThumbnailIfFresh(at:updatedAt:boardID:maxPixelSize:) / isFreshThumbnail(at:updatedAt:)
// 节选: 缩略图新鲜度直接依赖 updatedAt。
static func loadThumbnailIfFresh(
    at thumbnailURL: URL,
    updatedAt: Date,
    boardID: UUID? = nil,
    maxPixelSize: Int
) throws -> BoardPersistedThumbnailStoreLoadResult {
    guard try isFreshThumbnail(at: thumbnailURL, updatedAt: updatedAt) else {
        return .missingOrStale
    }
    // ...
}

private static func isFreshThumbnail(
    at thumbnailURL: URL,
    updatedAt: Date
) throws -> Bool {
    return modificationDate.timeIntervalSince(updatedAt) >= -freshnessTolerance
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数: loadThumbnailIfFresh(at:contentUpdatedAt:boardID:maxPixelSize:) / isFreshThumbnail(at:contentUpdatedAt:)
// 节选: persisted thumbnail 只随内容变化失效，纯视图变化不会让缩略图过期。
static func loadThumbnailIfFresh(
    at thumbnailURL: URL,
    contentUpdatedAt: Date,
    boardID: UUID? = nil,
    maxPixelSize: Int
) throws -> BoardPersistedThumbnailStoreLoadResult {
    guard try isFreshThumbnail(at: thumbnailURL, contentUpdatedAt: contentUpdatedAt) else {
        return .missingOrStale
    }
    // ...
}

private static func isFreshThumbnail(
    at thumbnailURL: URL,
    contentUpdatedAt: Date
) throws -> Bool {
    return modificationDate.timeIntervalSince(contentUpdatedAt) >= -freshnessTolerance
}
```

### 9. `BoardPreviewProvider.swift`：preview 加载链路切到内容时间 freshness

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数: loadPersistedThumbnailPreview(for:cacheKey:cancellationCheck:)
// 节选: provider 读取 persisted thumbnail 时仍然把 item.updatedAt 当 freshness 基准。
let persistedThumbnailResult = try BoardPersistedThumbnailStore.loadThumbnailIfFresh(
    at: item.persistedThumbnailURL,
    updatedAt: item.updatedAt,
    boardID: item.boardID,
    maxPixelSize: decodeMaxPixelSize
)
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数: loadPersistedThumbnailPreview(for:cacheKey:cancellationCheck:)
// 节选: provider 改成只看 item.contentUpdatedAt，避免视图态保存触发 preview 抖动。
let persistedThumbnailResult = try BoardPersistedThumbnailStore.loadThumbnailIfFresh(
    at: item.persistedThumbnailURL,
    contentUpdatedAt: item.contentUpdatedAt,
    boardID: item.boardID,
    maxPixelSize: decodeMaxPixelSize
)
```

### 10. `iOSBoardListViewController.swift`：boardlist 排序改看内容更新时间

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数: boardCatalogItemSortsBefore(_:_:)
// 节选: iOS boardlist 的插入与重排按 updatedAt 倒序。
private static func boardCatalogItemSortsBefore(
    _ lhs: BoardCatalogItem,
    _ rhs: BoardCatalogItem
) -> Bool {
    if lhs.updatedAt == rhs.updatedAt {
        return lhs.boardID.uuidString < rhs.boardID.uuidString
    }
    return lhs.updatedAt > rhs.updatedAt
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数: boardCatalogItemSortsBefore(_:_:)
// 节选: boardlist 排序改为只按 contentUpdatedAt 倒序，视图态保存不再导致位置上浮。
private static func boardCatalogItemSortsBefore(
    _ lhs: BoardCatalogItem,
    _ rhs: BoardCatalogItem
) -> Bool {
    if lhs.contentUpdatedAt == rhs.contentUpdatedAt {
        return lhs.boardID.uuidString < rhs.boardID.uuidString
    }
    return lhs.contentUpdatedAt > rhs.contentUpdatedAt
}
```

### 11. `iOSViewController.swift`：iOS 端视图态 autosave 显式标记为 `.viewStateOnly`

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: handleZoomGestureEnded() / syncCameraViewportSizeIfNeeded(_:source:) / handleMiniMapNavigate(to:) / applyWorkspaceModeForToolbarTransition(to:) / panCanvas(...) / scheduleAutosave(reason:)
// 节选: iOS 端这些操作都会走默认 autosave，无法区分内容保存和视图保存。
scheduleAutosave(reason: "zoom canvas")
scheduleAutosave(reason: "configure board state")
scheduleAutosave(reason: "navigate canvas via minimap")
scheduleAutosave(reason: "toggle workspace mode")
scheduleAutosave(reason: "pan canvas")

private func scheduleAutosave(reason: String) {
    editorSession.scheduleAutosave(reason: reason)
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: handleZoomGestureEnded() / syncCameraViewportSizeIfNeeded(_:source:) / handleMiniMapNavigate(to:) / applyWorkspaceModeForToolbarTransition(to:) / panCanvas(...) / scheduleAutosave(reason:updateKind:)
// 节选: iOS 端所有纯视图态动作都显式打上 .viewStateOnly。
scheduleAutosave(
    reason: "zoom canvas",
    updateKind: .viewStateOnly
)
scheduleAutosave(
    reason: "configure board state",
    updateKind: .viewStateOnly
)
scheduleAutosave(
    reason: "navigate canvas via minimap",
    updateKind: .viewStateOnly
)
scheduleAutosave(
    reason: "toggle workspace mode",
    updateKind: .viewStateOnly
)
scheduleAutosave(
    reason: "pan canvas",
    updateKind: .viewStateOnly
)

private func scheduleAutosave(
    reason: String,
    updateKind: BoardPersistenceUpdateKind = .contentAndViewState
) {
    editorSession.scheduleAutosave(
        reason: reason,
        updateKind: updateKind
    )
}
```

### 12. `macOSViewController.swift`：macOS 端同步收敛到 `.viewStateOnly`

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: updateCameraViewportSizeIfNeeded(...) / handleIndirectPan(_:) / handleZoom(_:around:) / handleMiniMapNavigate(to:) / applyWorkspaceModeForToolbarTransition(to:) / panCanvas(from:to:) / scheduleAutosave(reason:)
// 节选: macOS 端这些视图动作也默认走统一 autosave。
scheduleAutosave(reason: "configure board state")
scheduleAutosave(reason: "pan canvas")
scheduleAutosave(reason: "zoom canvas")
scheduleAutosave(reason: "navigate canvas via minimap")
scheduleAutosave(reason: "toggle workspace mode")
scheduleAutosave(reason: "drag canvas")

private func scheduleAutosave(reason: String) {
    editorSession.scheduleAutosave(reason: reason)
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: updateCameraViewportSizeIfNeeded(...) / handleIndirectPan(_:) / handleZoom(_:around:) / handleMiniMapNavigate(to:) / applyWorkspaceModeForToolbarTransition(to:) / panCanvas(from:to:) / scheduleAutosave(reason:updateKind:)
// 节选: macOS 端与 iOS 对齐，纯视图态动作全部显式传 .viewStateOnly。
scheduleAutosave(
    reason: "configure board state",
    updateKind: .viewStateOnly
)
scheduleAutosave(
    reason: "pan canvas",
    updateKind: .viewStateOnly
)
scheduleAutosave(
    reason: "zoom canvas",
    updateKind: .viewStateOnly
)
scheduleAutosave(
    reason: "navigate canvas via minimap",
    updateKind: .viewStateOnly
)
scheduleAutosave(
    reason: "toggle workspace mode",
    updateKind: .viewStateOnly
)
scheduleAutosave(
    reason: "drag canvas",
    updateKind: .viewStateOnly
)

private func scheduleAutosave(
    reason: String,
    updateKind: BoardPersistenceUpdateKind = .contentAndViewState
) {
    editorSession.scheduleAutosave(
        reason: reason,
        updateKind: updateKind
    )
}
```

## 结果归纳

本次改造完成后，保存链路的行为从“任何保存都刷新一个总更新时间”变成了“两条时间线分别维护”：

- 内容改动会刷新 `contentUpdatedAt`
- 视图改动会刷新 `viewStateUpdatedAt`
- boardlist 排序、revision token、persisted thumbnail freshness、preview 加载只认 `contentUpdatedAt`

因此，打开 existing board 后直接返回，或只做平移/缩放/minimap/workspaceMode 之类的视图操作，不应该再把卡片移动到第一行；但真正编辑内容后，卡片仍然会按内容更新时间正常前移。

## 验证记录

已完成的验证：

- IDE lint 检查：无新增报错
- iOS 编译验证：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -sdk iphonesimulator -configuration Debug build`
- 编译结果：`BUILD SUCCEEDED`

尚未在本次记录中完成的验证：

- “打开后直接返回，位置不变”的手动交互回归
- “只做视图操作后返回，位置不变”的手动交互回归
- “真实内容修改后返回，卡片仍会上浮”的手动交互回归
