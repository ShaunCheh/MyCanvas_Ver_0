# 20260518_115508_hand_drawing_phase2_persistence_record

## 记录范围

- 记录内容：
  1. 为 handDrawing 新增统一资产定位器与 transient payload。
  2. 将 `BoardStore` 的读取、保存、覆盖写、孤儿清理链路扩展到 handDrawing 的 `.pkdrawing` 与 `.png`。
  3. 让 persisted thumbnail 写入链直接消费 handDrawing 的运行时预览图，避免 board list 继续命中旧缓存。
  4. 新增阶段 2 存储测试，并补齐阶段 2 接口变更后的兼容调用点。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S"` -> `20260518_115508`
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
- 当前工作区涉及文件：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
- 本记录不包含：
  - 阶段 3 的手绘主画布渲染与几何约束
  - 阶段 5 的 iOS PencilKit 全屏编辑器
  - git commit / push

## 修改一：新增 handDrawing 资产定位器与 transient payload

### 修改前

- 项目里没有 handDrawing 专用的资产定位器。
- `BoardSaveSnapshot` 只能承载图片导入的 transient payload，不能把手绘源笔迹与预览 PNG 一并送入保存链。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前项目中没有 handDrawing 资产定位器，也没有承载 drawingData / previewImageData 的专用 transient payload 类型。
// 修改前此文件不存在。
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift
// 函数名: BoardSaveSnapshot.init(...) / transientImageAssetPayload(...)
// 功能说明: 修改前保存快照只认识图片 transient payload；handDrawing 的源笔迹与预览图没有进入统一保存快照。
struct BoardSaveSnapshot {
    let runtimeState: BoardRuntimeState
    let transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload]
    let updateKind: BoardPersistenceUpdateKind

    init(
        runtimeState: BoardRuntimeState,
        transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload] = [:],
        updateKind: BoardPersistenceUpdateKind = .contentAndViewState
    ) {
        self.runtimeState = runtimeState
        self.transientImageAssetPayloads = transientImageAssetPayloads
        self.updateKind = updateKind
    }

    func transientImageAssetPayload(
        for assetReference: CanvasImageAssetReference
    ) -> CanvasTransientImageAssetPayload? {
        transientImageAssetPayloads[assetReference]
    }
}
```

### 修改后

- 新增 `BoardHandDrawingAssetLocator`，把 `<itemID>.png` 与 `<itemID>.pkdrawing` 的文件名和 URL 推导收口到一个地方。
- 新增 `BoardTransientHandDrawingAssetPayload`，把 `drawingData` 与 `previewImageData` 一起挂到 `BoardSaveSnapshot` 上。
- `BoardSaveSnapshot` 现在同时支持“只传 runtimeState”与“显式传入双 payload 字典”两种初始化方式。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift
// 函数名: previewImageURL(in:) / sourceDrawingURL(in:) / BoardTransientHandDrawingAssetPayload.init(...)
// 功能说明: 修改后 handDrawing 的文件名规则、资产 URL 推导、保存期临时二进制数据都由同一组类型承载。
struct BoardHandDrawingAssetLocator {
    let itemID: CanvasItemID

    var previewImageFilename: String {
        CanvasHandDrawingItem.defaultPreviewImageFilename(for: itemID)
    }

    var sourceDrawingFilename: String {
        CanvasHandDrawingItem.defaultSourceDrawingFilename(for: itemID)
    }

    func previewImageURL(in assetsDirectoryURL: URL) -> URL {
        assetsDirectoryURL.appendingPathComponent(previewImageFilename)
    }

    func sourceDrawingURL(in assetsDirectoryURL: URL) -> URL {
        assetsDirectoryURL.appendingPathComponent(sourceDrawingFilename)
    }
}

struct BoardTransientHandDrawingAssetPayload {
    let itemID: CanvasItemID
    let drawingData: Data
    let previewImageData: Data
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift
// 函数名: BoardSaveSnapshot.init(...) / transientImageAssetPayload(...) / transientHandDrawingAssetPayload(...)
// 功能说明: 修改后保存快照同时承载图片与 handDrawing 两类 transient 资源，后续保存链可以直接读取手绘源笔迹与预览 PNG。
struct BoardSaveSnapshot {
    let runtimeState: BoardRuntimeState
    let transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload]
    let transientHandDrawingAssetPayloads: [CanvasItemID: BoardTransientHandDrawingAssetPayload]
    let updateKind: BoardPersistenceUpdateKind

    init(
        runtimeState: BoardRuntimeState,
        updateKind: BoardPersistenceUpdateKind = .contentAndViewState
    ) {
        self.init(
            runtimeState: runtimeState,
            transientImageAssetPayloads: Dictionary(),
            transientHandDrawingAssetPayloads: Dictionary(),
            updateKind: updateKind
        )
    }

    init(
        runtimeState: BoardRuntimeState,
        transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload],
        transientHandDrawingAssetPayloads: [CanvasItemID: BoardTransientHandDrawingAssetPayload],
        updateKind: BoardPersistenceUpdateKind = .contentAndViewState
    ) {
        self.runtimeState = runtimeState
        self.transientImageAssetPayloads = transientImageAssetPayloads
        self.transientHandDrawingAssetPayloads = transientHandDrawingAssetPayloads
        self.updateKind = updateKind
    }

    func transientHandDrawingAssetPayload(
        for itemID: CanvasItemID
    ) -> BoardTransientHandDrawingAssetPayload? {
        transientHandDrawingAssetPayloads[itemID]
    }
}
```

## 修改二：`BoardDocument` 改为通过定位器统一推导 handDrawing 资产文件名

### 修改前

- `BoardHandDrawingItemRecord` 直接调用 `CanvasHandDrawingItem.default...` 推导文件名。
- `referencedAssetFilenames` 虽然已经把 `.png/.pkdrawing` 纳入集合，但推导逻辑分散在 record 内部多个属性里。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardHandDrawingItemRecord.previewImageFilename / sourceDrawingFilename / referencedAssetFilenames
// 功能说明: 修改前 handDrawing 文件名推导散落在 record 自身属性中，尚未通过独立定位器统一收口。
struct BoardHandDrawingItemRecord: Codable, Equatable {
    // ... 其余字段未改动

    var previewImageFilename: String {
        CanvasHandDrawingItem.defaultPreviewImageFilename(for: id)
    }

    var sourceDrawingFilename: String {
        CanvasHandDrawingItem.defaultSourceDrawingFilename(for: id)
    }

    var referencedAssetFilenames: Set<String> {
        [
            previewImageFilename,
            sourceDrawingFilename
        ]
    }
}
```

### 修改后

- `BoardHandDrawingItemRecord` 新增 `assetLocator`，文件名与引用集合都从定位器读取。
- `BoardItemRecord.referencedAssetFilenames` 继续把 handDrawing 的 `.png/.pkdrawing` 交给孤儿清理链使用。
- 同时顺手去掉了 `.text` 分支里未使用的局部变量绑定。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardHandDrawingItemRecord.previewImageFilename / sourceDrawingFilename / referencedAssetFilenames / assetLocator
// 功能说明: 修改后 handDrawing record 不再自行散落拼文件名，而是通过定位器统一导出预览图文件名、源笔迹文件名与引用集合。
struct BoardHandDrawingItemRecord: Codable, Equatable {
    // ... 其余字段未改动

    var previewImageFilename: String {
        assetLocator.previewImageFilename
    }

    var sourceDrawingFilename: String {
        assetLocator.sourceDrawingFilename
    }

    var referencedAssetFilenames: Set<String> {
        assetLocator.referencedAssetFilenames
    }

    var assetLocator: BoardHandDrawingAssetLocator {
        BoardHandDrawingAssetLocator(itemID: id)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardItemRecord.referencedAssetFilenames
// 功能说明: 修改后文档级引用集合继续覆盖 handDrawing 的两个资产文件，同时移除了 `.text` 分支里无意义的局部变量绑定。
var referencedAssetFilenames: Set<String> {
    switch self {
    case let .image(record):
        return record.referencedAssetFilenames
    case .text:
        return []
    case let .handDrawing(record):
        return record.referencedAssetFilenames
    }
}
```

## 修改三：`BoardStore` 接入 handDrawing 的读取、覆盖写、校验与孤儿清理

### 修改前

- `BoardStore` 只校验图片与视频资源。
- `saveBoard` 只遍历 `persistedState.imageItems` 持久化图片 poster 与视频资源。
- 没有 `loadHandDrawingSourceData(...)`，也没有 handDrawing 的缺失错误类型、源文件校验函数和覆盖写函数。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: loadBoard(...) / saveBoard(...) / BoardStoreError
// 功能说明: 修改前 BoardStore 只覆盖 image/video 资产；handDrawing 的源笔迹读取、覆盖写、缺失校验和错误报告都不存在。
enum BoardStoreError: LocalizedError {
    case invalidBoardDirectory
    case invalidBoardImageAsset(filename: String)
    case missingBoardVideoAsset(filename: String)
    case failedToEncodeImageAsset(itemID: UUID)
    case missingAnimatedImageSource(itemID: UUID)
}

static func loadBoard(
    id: UUID,
    userDefaults: UserDefaults = .standard
) throws -> BoardRuntimeState {
    // ... 其余路径解析代码未改动
    try validateReferencedVideoAssets(
        for: document.imageItemRecords,
        in: assetsDirectoryURL
    )
    let runtimeState = try BoardDocumentMapper.makeRuntimeState(from: document) { imageRecord in
        // ... 只从图片记录加载 CGImage
    }
    return runtimeState
}

if contentChanged {
    for item in persistedState.imageItems {
        // ... 只处理图片 poster 与视频源
    }

    try removeOrphanedAssets(
        keeping: document.referencedAssetFilenames,
        in: assetsDirectoryURL
    )
}
```

### 修改后

- 新增 `missingBoardHandDrawingSourceAsset` 与 `missingHandDrawingAssetPayload` 两个错误分支。
- `loadBoard` 现在会先校验 handDrawing 的 `.pkdrawing` 是否存在。
- 新增 `loadHandDrawingSourceData(...)`，让后续编辑器能按 `boardID + itemID` 读取源笔迹数据。
- `saveBoard` 现在会把 `transientHandDrawingAssetPayloads` 透传到持久化快照，并在 `contentChanged` 时覆盖写 `.pkdrawing` 与 `.png`。
- handDrawing 仍然使用 `document.referencedAssetFilenames` 参与孤儿清理；删除元素后，这两个文件会一起清掉。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardStoreError / loadBoard(...) / loadHandDrawingSourceData(...) / saveBoard(...)
// 功能说明: 修改后 BoardStore 入口层具备 handDrawing 资产读取、缺失校验、payload 透传和保存调度能力。
enum BoardStoreError: LocalizedError {
    case invalidBoardDirectory
    case invalidBoardImageAsset(filename: String)
    case missingBoardVideoAsset(filename: String)
    case missingBoardHandDrawingSourceAsset(filename: String)
    case failedToEncodeImageAsset(itemID: UUID)
    case missingAnimatedImageSource(itemID: UUID)
    case missingHandDrawingAssetPayload(itemID: UUID)
}

static func loadBoard(
    id: UUID,
    userDefaults: UserDefaults = .standard
) throws -> BoardRuntimeState {
    // ... 其余路径解析代码未改动
    try validateReferencedVideoAssets(
        for: document.imageItemRecords,
        in: assetsDirectoryURL
    )
    try validateReferencedHandDrawingAssets(
        for: document.handDrawingItemRecords,
        in: assetsDirectoryURL
    )
    let runtimeState = try BoardDocumentMapper.makeRuntimeState(from: document) { imageRecord in
        // ... 继续通过 preview png 加载 CGImage
    }
    return runtimeState
}

static func loadHandDrawingSourceData(
    boardID: UUID,
    itemID: CanvasItemID,
    userDefaults: UserDefaults = .standard
) throws -> Data {
    let sourceURL = BoardHandDrawingAssetLocator(itemID: itemID)
        .sourceDrawingURL(in: assetsDirectoryURL)
    return try CoordinatedFileIO.readData(at: sourceURL)
}

let persistedSnapshot = BoardSaveSnapshot(
    runtimeState: persistedState,
    transientImageAssetPayloads: snapshot.transientImageAssetPayloads,
    transientHandDrawingAssetPayloads: snapshot.transientHandDrawingAssetPayloads,
    updateKind: snapshot.updateKind
)

if contentChanged {
    for item in persistedState.imageItems {
        // ... 旧的图片 poster / 视频校验逻辑保留
    }

    for item in persistedState.handDrawingItems {
        try persistHandDrawingAssetsIfNeeded(
            for: item,
            snapshot: persistedSnapshot,
            in: assetsDirectoryURL
        )
    }

    try removeOrphanedAssets(
        keeping: document.referencedAssetFilenames,
        in: assetsDirectoryURL
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: validateReferencedHandDrawingAssets(...) / validateHandDrawingSourceAssetExists(...) / persistHandDrawingAssetsIfNeeded(...)
// 功能说明: 修改后 handDrawing 的源笔迹存在性检查、同文件名覆盖写、缺 payload 报错都在 BoardStore 内集中处理。
private static func validateReferencedHandDrawingAssets(
    for handDrawingRecords: [BoardHandDrawingItemRecord],
    in assetsDirectoryURL: URL
) throws {
    for handDrawingRecord in handDrawingRecords {
        try validateHandDrawingSourceAssetExists(
            at: handDrawingRecord.assetLocator.sourceDrawingURL(in: assetsDirectoryURL),
            filename: handDrawingRecord.sourceDrawingFilename
        )
    }
}

private static func validateHandDrawingSourceAssetExists(
    at assetURL: URL,
    filename: String
) throws {
    guard try CoordinatedFileIO.modificationDate(at: assetURL) != nil else {
        throw BoardStoreError.missingBoardHandDrawingSourceAsset(
            filename: filename
        )
    }
}

private static func persistHandDrawingAssetsIfNeeded(
    for item: CanvasHandDrawingItem,
    snapshot: BoardSaveSnapshot,
    in assetsDirectoryURL: URL
) throws {
    let assetLocator = BoardHandDrawingAssetLocator(itemID: item.id)
    let previewImageURL = assetLocator.previewImageURL(in: assetsDirectoryURL)
    let sourceDrawingURL = assetLocator.sourceDrawingURL(in: assetsDirectoryURL)

    if let payload = snapshot.transientHandDrawingAssetPayload(for: item.id) {
        try CoordinatedFileIO.writeData(payload.drawingData, to: sourceDrawingURL)
        try CoordinatedFileIO.writeData(
            payload.previewImageData,
            to: previewImageURL
        )
        return
    }

    guard try CoordinatedFileIO.modificationDate(at: previewImageURL) != nil else {
        throw BoardStoreError.missingHandDrawingAssetPayload(itemID: item.id)
    }
    try validateHandDrawingSourceAssetExists(
        at: sourceDrawingURL,
        filename: assetLocator.sourceDrawingFilename
    )
}
```

## 修改四：persisted thumbnail 写入链改为消费 handDrawing 的运行时预览图

### 修改前

- `renderPersistedThumbnail(for runtimeState:)` 只从 `runtimeState.imageItems` 建立图片字典。
- handDrawing 虽然已经进入文档 schema，但 persisted thumbnail 写入时仍找不到对应的 runtime 预览图。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderPersistedThumbnail(for runtimeState:...)
// 功能说明: 修改前 persisted thumbnail 只看 imageItems；handDrawing 不会把自己的 previewAsset 带入运行时缩略图写入链。
enum BoardThumbnailRendererError: LocalizedError {
    case invalidBitmapContext
    case invalidRuntimeImageAsset(itemID: UUID)
    case cancelled
}

let runtimeItemsByID = Dictionary(
    uniqueKeysWithValues: runtimeState.imageItems.map { ($0.id, $0) }
)

return try renderThumbnail(...) { itemRecord, _, _ in
    guard let runtimeItem = runtimeItemsByID[itemRecord.id] else {
        throw BoardThumbnailRendererError.invalidRuntimeImageAsset(
            itemID: itemRecord.id
        )
    }

    return runtimeItem.posterCGImage
}
```

### 修改后

- 错误名改成 `invalidRuntimePreviewAsset`，语义从“图片资源缺失”改成“运行时预览图缺失”。
- 预览图字典从 `runtimeState.items` 构建，`image` 取 `posterCGImage`，`handDrawing` 取 `previewAsset.posterCGImage`。
- 这样 persisted thumbnail 在保存时就能直接消费 handDrawing 最新预览图，从而跟随 `contentRevision` 和 `contentUpdatedAt` 一起刷新。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: BoardThumbnailRendererError / renderPersistedThumbnail(for runtimeState:...)
// 功能说明: 修改后 persisted thumbnail 的运行时输入从“仅图片 item”扩展为“所有可提供预览图的 item”，handDrawing 直接复用 previewAsset。
enum BoardThumbnailRendererError: LocalizedError {
    case invalidBitmapContext
    case invalidRuntimePreviewAsset(itemID: UUID)
    case cancelled
}

let runtimePreviewImagesByID = runtimeState.items.reduce(
    into: [UUID: CGImage]()
) { partialResult, item in
    switch item {
    case let .image(runtimeImageItem):
        partialResult[runtimeImageItem.id] = runtimeImageItem.posterCGImage
    case let .handDrawing(runtimeHandDrawingItem):
        partialResult[runtimeHandDrawingItem.id] = runtimeHandDrawingItem
            .previewAsset
            .posterCGImage
    case .text:
        break
    }
}

return try renderThumbnail(...) { itemRecord, _, _ in
    guard let previewImage = runtimePreviewImagesByID[itemRecord.id] else {
        throw BoardThumbnailRendererError.invalidRuntimePreviewAsset(
            itemID: itemRecord.id
        )
    }

    // Persisted board thumbnails stay static even for GIF boards; the
    // runtime preview image is the single frame we rasterize into thumbnail.png.
    return previewImage
}
```

## 修改五：补齐阶段 2 接口变更后的兼容调用点

### 修改前

- `BoardDocumentMapper` 仍然使用 `items.map(makeItemRecord)` 的方法引用写法。
- `CanvasEditorSession.currentBoardSaveSnapshot(...)` 返回的 `BoardSaveSnapshot` 只传图片 payload。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeDocument(from:)
// 功能说明: 修改前 mapper 仍直接传方法引用；阶段 2 实际功能不依赖这里变更，但当前代码里顺手改成了显式闭包。
items: runtimeState.items.map(makeItemRecord)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: currentBoardSaveSnapshot(createBoardIfNeeded:updateKind:)
// 功能说明: 修改前编辑会话在组装保存快照时只传图片 payload；handDrawing payload 的字段尚未被补齐。
return BoardSaveSnapshot(
    runtimeState: runtimeState,
    transientImageAssetPayloads: payloads,
    updateKind: updateKind
)
```

### 修改后

- `BoardDocumentMapper` 改成显式闭包调用 `makeItemRecord(from:)`。
- `CanvasEditorSession` 现在至少显式补上 `transientHandDrawingAssetPayloads: [:]`，避免阶段 2 新字段把现有保存链打断。
- 这里仍然只是“占位透传空字典”；真正 handDrawing payload 的生产仍要等后续编辑器阶段接入。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeDocument(from:)
// 功能说明: 修改后 mapper 用显式闭包调用 makeItemRecord(from:)，行为不变，主要用于收口当前实现并避免继续依赖方法引用写法。
items: runtimeState.items.map { item in
    makeItemRecord(from: item)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: currentBoardSaveSnapshot(createBoardIfNeeded:updateKind:)
// 功能说明: 修改后编辑会话即便暂时还不生产 handDrawing payload，也会显式传入空字典，保证新的 BoardSaveSnapshot 接口完整闭合。
return BoardSaveSnapshot(
    runtimeState: runtimeState,
    transientImageAssetPayloads: payloads,
    transientHandDrawingAssetPayloads: [:],
    updateKind: updateKind
)
```

## 修改六：新增 handDrawing 阶段 2 存储测试

### 修改前

- 项目里还没有 handDrawing 专用的阶段 2 存储测试文件。
- 因此“首次保存 + 重开读取 + 孤儿清理”和“同文件名二次覆盖 + persisted thumbnail 刷新”都没有专门断言。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前项目中没有 handDrawing 阶段 2 存储测试文件，相关存储闭环没有独立测试锁定。
// 修改前此文件不存在。
```

### 修改后

- 新增 `BoardHandDrawingStorageTests`。
- 第一条测试验证：首次保存时写出 `.pkdrawing/.png`，重新加载后能读回最新源笔迹与预览图，同时孤儿文件会被清理。
- 第二条测试验证：同一 `itemID` 二次编辑后会覆盖原文件，并刷新 persisted thumbnail 与 `contentUpdatedAt`。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() / testBoardStoreOverwritesHandDrawingAssetsAndRefreshesPersistedThumbnail()
// 功能说明: 修改后新增 handDrawing 阶段 2 存储测试，分别锁定首次保存闭环与同文件名覆盖刷新闭环。
final class BoardHandDrawingStorageTests: XCTestCase {
    func testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() throws {
        let snapshot = BoardSaveSnapshot(
            runtimeState: runtimeState,
            transientImageAssetPayloads: [:],
            transientHandDrawingAssetPayloads: [
                itemID: BoardTransientHandDrawingAssetPayload(
                    itemID: itemID,
                    drawingData: drawingData,
                    previewImageData: try makeHandDrawingPNGData(for: previewImage)
                )
            ]
        )

        try BoardStore.saveBoard(snapshot, userDefaults: userDefaults)

        XCTAssertEqual(
            try BoardStore.loadHandDrawingSourceData(
                boardID: boardID,
                itemID: itemID,
                userDefaults: userDefaults
            ),
            drawingData
        )
    }

    func testBoardStoreOverwritesHandDrawingAssetsAndRefreshesPersistedThumbnail() throws {
        try BoardStore.saveBoard(
            BoardSaveSnapshot(
                runtimeState: runtimeState,
                transientImageAssetPayloads: [:],
                transientHandDrawingAssetPayloads: [
                    itemID: BoardTransientHandDrawingAssetPayload(
                        itemID: itemID,
                        drawingData: secondDrawingData,
                        previewImageData: try makeHandDrawingPNGData(
                            for: secondPreviewImage
                        )
                    )
                ]
            ),
            userDefaults: userDefaults
        )

        XCTAssertNotEqual(firstThumbnailSignature, secondThumbnailSignature)
        XCTAssertEqual(
            secondEntry.document.handDrawingItemRecords.first?.contentRevision,
            secondRevision
        )
    }
}
```

## 验证结果

- `BoardHandDrawingStorageTests`：通过。
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk macosx build`：通过。
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk iphonesimulator build`：通过。
- `ReadLints` 针对本次修改文件检查：无新增 linter 错误。
