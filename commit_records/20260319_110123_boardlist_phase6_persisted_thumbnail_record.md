# 20260319_110123_boardlist_phase6_persisted_thumbnail_record

## 记录范围

- 记录目标：落实 `BoardList` 总计划的阶段 6，把真实缩略图从“列表时临时渲染”升级为“保存链路中的持久化 `thumbnail.png`”。
- 本阶段目的 1：在 `BoardStore.saveBoard(...)` 完成主保存后，best-effort 产出或清理 `thumbnail.png`。
- 本阶段目的 2：让 `BoardPreviewProvider` 优先读取持久化缩略图，只有缺失、损坏或过期时才回退到当前的即时渲染链。
- 本阶段目的 3：避免保存时再去回读磁盘 asset，而是直接利用 `BoardRuntimeState` 的内存图片生成持久化缩略图。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Storage/CoordinatedFileIO.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- 本记录不包含：`New Board` 占位项五阶段改造。
- 本记录不包含：git commit。

## 修改一：补齐持久化缩略图的文件存储层与文件时间读取能力

### 修改前

- `BoardList` 目录模型只知道 `board.json` 和 `assets`，并不知道 `thumbnail.png` 的位置。
- `CoordinatedFileIO` 只有读写数据和删文件能力，没有“读取文件修改时间”的统一入口。
- 这意味着 provider 即使想优先命中磁盘缩略图，也没有统一的路径解析和新鲜度判断规则。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名/类型名: BoardCatalogItem
// 功能说明: 修改前目录项只承载 document、assetsDirectoryURL 和 previewSeed，没有持久化缩略图路径。
import Foundation

struct BoardCatalogItem {
    let document: BoardDocument
    let assetsDirectoryURL: URL
    let previewSeed: BoardPreviewSeed

    var boardID: UUID {
        document.boardID
    }

    var revisionToken: String {
        "\(boardID.uuidString)-\(updatedAt.timeIntervalSince1970)"
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/CoordinatedFileIO.swift
// 函数名/类型名: CoordinatedFileIO.readData(at:) / writeData(_:to:)
// 功能说明: 修改前文件协调层只负责数据读写，没有统一的 contentModificationDate 读取接口。
static func readData(
    at url: URL,
    fileManager: FileManager = .default
) throws -> Data {
    guard fileManager.fileExists(atPath: url.path) else {
        throw CocoaError(.fileReadNoSuchFile)
    }

    return try coordinateReading(at: url) { coordinatedURL in
        try Data(contentsOf: coordinatedURL)
    }
}

static func writeData(
    _ data: Data,
    to url: URL,
    fileManager: FileManager = .default
) throws {
    try ensureDirectory(at: url.deletingLastPathComponent(), fileManager: fileManager)
    try coordinateWriting(at: url) { coordinatedURL in
        try data.write(to: coordinatedURL, options: .atomic)
    }
}
```

### 修改后

- 新增 `BoardPersistedThumbnailStore`，统一收口：
- `thumbnail.png` 的路径规则
- 按 `displayWorldRect` 推导持久化缩略图尺寸
- PNG 编解码
- 基于文件修改时间和 `updatedAt` 的新鲜度判断
- `CoordinatedFileIO` 同步新增 `modificationDate(at:)`，避免上层各自去摸文件属性。
- `BoardCatalogItem` 增加 `persistedThumbnailURL`，使目录模型天然携带磁盘缩略图入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数名/类型名: BoardPersistedThumbnailStore
// 功能说明: 修改后新增持久化缩略图存储层，统一管理 thumbnail.png 的路径、尺寸、编解码与新鲜度判断。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BoardPersistedThumbnailStore {
    static let filename = "thumbnail.png"
    static let maximumLongestSide: CGFloat = 1024
    private static let freshnessTolerance: TimeInterval = 1

    static func thumbnailURL(
        forBoardDirectoryURL boardDirectoryURL: URL
    ) -> URL {
        boardDirectoryURL.appendingPathComponent(filename)
    }

    static func pixelSize(
        forDisplayWorldRect displayWorldRect: CGRect,
        maximumLongestSide: CGFloat = Self.maximumLongestSide
    ) -> CGSize {
        let sanitizedDisplayWorldRect = displayWorldRect.standardized
        guard
            sanitizedDisplayWorldRect.width > 0,
            sanitizedDisplayWorldRect.height > 0
        else {
            return .zero
        }

        let longestSide = max(
            sanitizedDisplayWorldRect.width,
            sanitizedDisplayWorldRect.height
        )
        let scale = max(maximumLongestSide, 1) / longestSide
        return CGSize(
            width: max((sanitizedDisplayWorldRect.width * scale).rounded(.up), 1),
            height: max((sanitizedDisplayWorldRect.height * scale).rounded(.up), 1)
        )
    }

    static func loadThumbnailIfFresh(
        at thumbnailURL: URL,
        updatedAt: Date,
        maxPixelSize: Int
    ) throws -> CGImage? {
        guard
            try isFreshThumbnail(
                at: thumbnailURL,
                updatedAt: updatedAt
            )
        else {
            return nil
        }

        let thumbnailData = try CoordinatedFileIO.readData(at: thumbnailURL)
        guard
            let imageSource = CGImageSourceCreateWithData(
                thumbnailData as CFData,
                nil
            )
        else {
            throw BoardPersistedThumbnailStoreError.invalidPersistedThumbnail
        }

        let decodeMaxPixelSize = max(maxPixelSize, 64)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: decodeMaxPixelSize
        ]
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            thumbnailOptions as CFDictionary
        ) {
            return thumbnail
        }

        guard
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw BoardPersistedThumbnailStoreError.invalidPersistedThumbnail
        }

        return image
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/CoordinatedFileIO.swift
// 函数名/类型名: CoordinatedFileIO.modificationDate(at:)
// 功能说明: 修改后文件协调层新增统一的修改时间读取能力，供持久化 thumbnail 新鲜度判断复用。
static func modificationDate(
    at url: URL,
    fileManager: FileManager = .default
) throws -> Date? {
    guard fileManager.fileExists(atPath: url.path) else {
        return nil
    }

    return try coordinateReading(at: url) { coordinatedURL in
        try coordinatedURL
            .resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名/类型名: BoardCatalogItem
// 功能说明: 修改后目录项额外携带 persistedThumbnailURL，provider 可以直接优先命中持久化缩略图。
import Foundation

struct BoardCatalogItem {
    let document: BoardDocument
    let persistedThumbnailURL: URL
    let assetsDirectoryURL: URL
    let previewSeed: BoardPreviewSeed

    var boardID: UUID {
        document.boardID
    }

    var revisionToken: String {
        "\(boardID.uuidString)-\(updatedAt.timeIntervalSince1970)"
    }
}
```

## 修改二：把 `thumbnail.png` 接入 `BoardStore.saveBoard(...)` 的保存链

### 修改前

- `BoardStore.saveBoard(...)` 只负责：
- 写入 `assets/*.png`
- 清理 orphan assets
- 写入 `board.json`
- 保存链完成后不会生成任何可复用的缩略图产物，所以列表每次都只能依赖运行时缓存或重新离屏渲染。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名/类型名: BoardStore.saveBoard(_:)
// 功能说明: 修改前保存链只写 assets 和 board.json，不会持久化真实缩略图。
static func saveBoard(
    _ runtimeState: BoardRuntimeState,
    userDefaults: UserDefaults = .standard
) throws {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
        // ... 省略 assets 目录与 document 构造逻辑 ...
        try removeOrphanedAssets(
            keeping: Set(document.items.map(\.assetFilename)),
            in: assetsDirectoryURL
        )

        let boardDocumentURL = boardDirectoryURL.appendingPathComponent(boardDocumentFilename)
        let encodedDocument = try makeDocumentData(for: document)
        try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
    }
}
```

### 修改后

- `BoardStore` 新增私有 `thumbnailRenderer`。
- 保存链仍然先保证主保存成功：`assets -> board.json`。
- 之后再通过 `persistBoardThumbnailIfPossible(...)` best-effort 生成或清理 `thumbnail.png`。
- 这里故意不把缩略图失败升级为主保存失败，避免非关键产物反向污染保存可靠性。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名/类型名: BoardStore.saveBoard(_:) / persistBoardThumbnailIfPossible(from:boardDirectoryURL:)
// 功能说明: 修改后保存链在完成主文件写入后 best-effort 持久化 thumbnail.png，失败只记录日志，不回滚主保存结果。
private static let thumbnailRenderer = BoardThumbnailRenderer()

static func saveBoard(
    _ runtimeState: BoardRuntimeState,
    userDefaults: UserDefaults = .standard
) throws {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
        // ... 省略 assets 目录与 document 构造逻辑 ...
        try removeOrphanedAssets(
            keeping: Set(document.items.map(\.assetFilename)),
            in: assetsDirectoryURL
        )

        let boardDocumentURL = boardDirectoryURL.appendingPathComponent(boardDocumentFilename)
        let encodedDocument = try makeDocumentData(for: document)
        try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
        persistBoardThumbnailIfPossible(
            from: persistedState,
            boardDirectoryURL: boardDirectoryURL
        )
    }
}

private static func persistBoardThumbnailIfPossible(
    from runtimeState: BoardRuntimeState,
    boardDirectoryURL: URL
) {
    do {
        if let thumbnailImage = try thumbnailRenderer.renderPersistedThumbnail(
            for: runtimeState
        ) {
            try BoardPersistedThumbnailStore.writeThumbnail(
                thumbnailImage,
                to: boardDirectoryURL
            )
        } else {
            try BoardPersistedThumbnailStore.removeThumbnail(
                at: boardDirectoryURL
            )
        }
    } catch {
        print(
            "[BoardStore] Failed to persist thumbnail " +
            "boardID=\(runtimeState.boardID.uuidString) " +
            "error=\(error)"
        )
    }
}
```

## 修改三：让目录模型和 provider 优先命中持久化缩略图

### 修改前

- `BoardCatalogLoader` 只把 `document + assetsDirectoryURL + previewSeed` 组装成目录项。
- `BoardPreviewProvider.immediatePreview(...)` 只认内存缓存，不认磁盘缩略图。
- `requestThumbnail(...)` 也会直接回到 `thumbnailRenderer.renderThumbnail(for:item...)` 的即时 asset 渲染链。
- 结果是：即使保存时未来有了缩略图文件，列表层也没有机会优先命中它。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift
// 函数名/类型名: BoardCatalogLoader.loadCatalog()
// 功能说明: 修改前目录加载器不会把 thumbnail.png 的 URL 注入到 BoardCatalogItem。
func loadCatalog() throws -> [BoardCatalogItem] {
    try BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).map { entry in
        BoardCatalogItem(
            document: entry.document,
            assetsDirectoryURL: entry.assetsDirectoryURL,
            previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/类型名: BoardPreviewProvider.immediatePreview(for:targetPixelSize:) / requestThumbnail(for:targetPixelSize:completion:)
// 功能说明: 修改前 provider 只有“内存缓存 -> geometry”与“内存缓存 -> 即时渲染”的两级链路，没有磁盘持久化缩略图入口。
func immediatePreview(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize? = nil
) -> BoardPreviewContent {
    if let targetPixelSize,
       let cacheKey = BoardThumbnailCacheKey(
           item: item,
           targetPixelSize: targetPixelSize
       ),
       let cachedImage = thumbnailCache.image(for: cacheKey) {
        return .thumbnail(cachedImage, item.previewSeed)
    }

    return .geometry(item.previewSeed)
}

@discardableResult
func requestThumbnail(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize,
    completion: @escaping (BoardPreviewContent?) -> Void
) -> BoardPreviewRequestToken {
    // ... 省略缓存命中逻辑 ...
    guard
        let renderedImage = try self.thumbnailRenderer.renderThumbnail(
            for: item,
            targetPixelSize: cacheKey.pixelSize,
            cancellationCheck: {
                if operation.isCancelled || requestToken.isCancelled {
                    throw BoardThumbnailRendererError.cancelled
                }
            }
        )
    else {
        return requestToken
    }
    // ... 省略回调逻辑 ...
}
```

### 修改后

- `BoardCatalogLoader` 通过 `BoardPersistedThumbnailStore.thumbnailURL(...)` 为每个目录项补齐 `persistedThumbnailURL`。
- `BoardPreviewProvider.immediatePreview(...)` 改成：
- 内存缓存
- 持久化缩略图
- geometry
- `requestThumbnail(...)` 改成：
- 内存缓存
- 持久化缩略图
- 即时 asset 渲染
- 这样 provider 的读取优先级就和阶段 6 目标完全对齐了。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift
// 函数名/类型名: BoardCatalogLoader.loadCatalog()
// 功能说明: 修改后目录加载器会把每个 board 对应的 thumbnail.png 路径注入到 BoardCatalogItem，供 provider 优先命中磁盘产物。
func loadCatalog() throws -> [BoardCatalogItem] {
    try BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).map { entry in
        BoardCatalogItem(
            document: entry.document,
            persistedThumbnailURL: BoardPersistedThumbnailStore.thumbnailURL(
                forBoardDirectoryURL: entry.boardDirectoryURL
            ),
            assetsDirectoryURL: entry.assetsDirectoryURL,
            previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/类型名: BoardPreviewProvider.immediatePreview(for:targetPixelSize:) / loadBestAvailableThumbnail(for:cacheKey:cancellationCheck:) / loadPersistedThumbnailPreview(for:cacheKey:cancellationCheck:)
// 功能说明: 修改后 provider 建立“内存缓存 -> 持久化 thumbnail.png -> 即时渲染”的三级回退链，优先利用保存链产出的磁盘缩略图。
func immediatePreview(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize? = nil
) -> BoardPreviewContent {
    guard
        let targetPixelSize,
        let cacheKey = BoardThumbnailCacheKey(
            item: item,
            targetPixelSize: targetPixelSize
        )
    else {
        return .geometry(item.previewSeed)
    }

    if let cachedImage = thumbnailCache.image(for: cacheKey) {
        return .thumbnail(cachedImage, item.previewSeed)
    }

    do {
        if let persistedThumbnail = try loadPersistedThumbnailPreview(
            for: item,
            cacheKey: cacheKey
        ) {
            thumbnailCache.insert(persistedThumbnail, for: cacheKey)
            return .thumbnail(persistedThumbnail, item.previewSeed)
        }
    } catch {
        print(
            "[BoardPreviewProvider] Failed to load persisted thumbnail " +
            "boardID=\(item.boardID.uuidString) " +
            "revision=\(item.revisionToken) " +
            "error=\(error)"
        )
    }

    return .geometry(item.previewSeed)
}

private func loadBestAvailableThumbnail(
    for item: BoardCatalogItem,
    cacheKey: BoardThumbnailCacheKey,
    cancellationCheck: () throws -> Void
) throws -> CGImage? {
    do {
        if let persistedThumbnail = try loadPersistedThumbnailPreview(
            for: item,
            cacheKey: cacheKey,
            cancellationCheck: cancellationCheck
        ) {
            return persistedThumbnail
        }
    } catch BoardThumbnailRendererError.cancelled {
        throw BoardThumbnailRendererError.cancelled
    } catch {
        print(
            "[BoardPreviewProvider] Failed to load persisted thumbnail " +
            "boardID=\(item.boardID.uuidString) " +
            "revision=\(item.revisionToken) " +
            "error=\(error)"
        )
    }

    try cancellationCheck()
    return try thumbnailRenderer.renderThumbnail(
        for: item,
        targetPixelSize: cacheKey.pixelSize,
        cancellationCheck: cancellationCheck
    )
}

private func loadPersistedThumbnailPreview(
    for item: BoardCatalogItem,
    cacheKey: BoardThumbnailCacheKey,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    let decodeMaxPixelSize = max(
        cacheKey.pixelWidth,
        cacheKey.pixelHeight
    )
    guard
        let persistedThumbnail = try BoardPersistedThumbnailStore.loadThumbnailIfFresh(
            at: item.persistedThumbnailURL,
            updatedAt: item.updatedAt,
            maxPixelSize: decodeMaxPixelSize
        )
    else {
        return nil
    }

    try cancellationCheck()
    return try thumbnailRenderer.renderThumbnail(
        fromPersistedThumbnail: persistedThumbnail,
        previewSeed: item.previewSeed,
        targetPixelSize: cacheKey.pixelSize,
        cancellationCheck: cancellationCheck
    )
}
```

## 修改四：重构缩略图渲染器，同时支持“保存时直出”和“列表时重排版”

### 修改前

- `BoardThumbnailRenderer` 只支持一种模式：
- 输入 `BoardCatalogItem`
- 读取磁盘 `assets`
- 按当前 cell 的目标尺寸直接渲染最终预览图
- 这意味着它无法：
- 在保存时直接利用 `BoardRuntimeState.items[*].cgImage`
- 把磁盘里已经持久化好的 `thumbnail.png` 重新排版成 list / grid 需要的目标尺寸

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名/类型名: BoardThumbnailRenderer.renderThumbnail(for:targetPixelSize:contentInset:cancellationCheck:)
// 功能说明: 修改前渲染器只有“基于目录项 + 从 assets 读图”的单一路径，无法服务保存链和持久化缩略图重排版。
func renderThumbnail(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize,
    contentInset: CGFloat = 10,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    guard item.document.items.isEmpty == false else {
        return nil
    }

    let snapshot = geometryPreviewBuilder.makeSnapshot(from: item.previewSeed)
    guard
        let geometry = CanvasMiniMapViewGeometry(
            displayWorldRect: snapshot.displayWorldRect,
            viewBounds: CGRect(origin: .zero, size: targetPixelSize),
            contentInset: contentInset
        )
    else {
        return nil
    }

    // ... 省略 bitmap context 构建与 drawItemRecord(...) ...
    for itemRecord in orderedItemRecords(from: item.document.items) {
        try cancellationCheck()
        try drawItemRecord(
            itemRecord,
            assetsDirectoryURL: item.assetsDirectoryURL,
            geometry: geometry,
            in: context,
            cancellationCheck: cancellationCheck
        )
    }

    try cancellationCheck()
    return context.makeImage()
}
```

### 修改后

- 渲染器新增两条能力：
- `renderPersistedThumbnail(for runtimeState:)`
- 保存时直接吃 `BoardRuntimeState` 的内存图像，避免再回读 asset
- `renderThumbnail(fromPersistedThumbnail:previewSeed:targetPixelSize:)`
- 列表读取磁盘缩略图后，再按当前 target size 重排版到 preview 几何里
- 同时把原来的即时渲染链抽成共享的私有 `renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:imageProvider:)`，避免三条路径各自复制一套绘制逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名/类型名: BoardThumbnailRenderer.renderPersistedThumbnail(for:maximumLongestSide:cancellationCheck:) / renderThumbnail(fromPersistedThumbnail:previewSeed:targetPixelSize:contentInset:cancellationCheck:)
// 功能说明: 修改后渲染器同时支持保存时基于运行时内存图像生成 thumbnail.png，以及列表阶段把持久化缩略图重新排版到当前预览尺寸。
func renderPersistedThumbnail(
    for runtimeState: BoardRuntimeState,
    maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    guard runtimeState.items.isEmpty == false else {
        return nil
    }

    let document = BoardDocumentMapper.makeDocument(from: runtimeState)
    let previewSeed = geometryPreviewBuilder.makeSeed(from: document)
    let snapshot = geometryPreviewBuilder.makeSnapshot(from: previewSeed)
    let targetPixelSize = BoardPersistedThumbnailStore.pixelSize(
        forDisplayWorldRect: snapshot.displayWorldRect,
        maximumLongestSide: maximumLongestSide
    )

    let runtimeItemsByID = Dictionary(
        uniqueKeysWithValues: runtimeState.items.map { ($0.id, $0) }
    )
    return try renderThumbnail(
        itemRecords: document.items,
        previewSeed: previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: 0,
        cancellationCheck: cancellationCheck
    ) { itemRecord, _ in
        guard let runtimeItem = runtimeItemsByID[itemRecord.id] else {
            throw BoardThumbnailRendererError.invalidRuntimeImageAsset(
                itemID: itemRecord.id
            )
        }
        return runtimeItem.cgImage
    }
}

func renderThumbnail(
    fromPersistedThumbnail persistedThumbnail: CGImage,
    previewSeed: BoardPreviewSeed,
    targetPixelSize: CGSize,
    contentInset: CGFloat = 10,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    let normalizedTargetPixelSize = normalizedPixelSize(targetPixelSize)
    let snapshot = geometryPreviewBuilder.makeSnapshot(from: previewSeed)
    guard
        let geometry = CanvasMiniMapViewGeometry(
            displayWorldRect: snapshot.displayWorldRect,
            viewBounds: CGRect(origin: .zero, size: normalizedTargetPixelSize),
            contentInset: contentInset
        ),
        let context = try makeBitmapContext(pixelSize: normalizedTargetPixelSize)
    else {
        return nil
    }

    prepareContext(
        context,
        pixelSize: normalizedTargetPixelSize
    )
    try cancellationCheck()
    context.draw(persistedThumbnail, in: geometry.contentRect)
    try cancellationCheck()
    return context.makeImage()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名/类型名: BoardThumbnailRenderer.renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:imageProvider:)
// 功能说明: 修改后即时渲染、保存直出和磁盘缩略图回排版共用同一套底层 bitmap/context/geometry 管线，避免绘制逻辑三份拷贝。
private func renderThumbnail(
    itemRecords: [BoardImageItemRecord],
    previewSeed: BoardPreviewSeed,
    targetPixelSize: CGSize,
    contentInset: CGFloat,
    cancellationCheck: () throws -> Void,
    imageProvider: (BoardImageItemRecord, CanvasMiniMapViewGeometry) throws -> CGImage
) throws -> CGImage? {
    guard itemRecords.isEmpty == false else {
        return nil
    }

    let normalizedTargetPixelSize = normalizedPixelSize(targetPixelSize)
    let snapshot = geometryPreviewBuilder.makeSnapshot(from: previewSeed)
    guard
        let geometry = CanvasMiniMapViewGeometry(
            displayWorldRect: snapshot.displayWorldRect,
            viewBounds: CGRect(origin: .zero, size: normalizedTargetPixelSize),
            contentInset: contentInset
        ),
        let context = try makeBitmapContext(pixelSize: normalizedTargetPixelSize)
    else {
        return nil
    }

    prepareContext(
        context,
        pixelSize: normalizedTargetPixelSize
    )

    for itemRecord in orderedItemRecords(from: itemRecords) {
        try cancellationCheck()
        let image = try imageProvider(itemRecord, geometry)
        try cancellationCheck()
        drawLoadedImage(
            image,
            for: itemRecord,
            geometry: geometry,
            in: context
        )
    }

    try cancellationCheck()
    return context.makeImage()
}
```

## 验证结果

- 已检查文件：
- `MyCanvas_Ver_0/Canvas/Storage/CoordinatedFileIO.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- `ReadLints` 结果：无新增 lint 错误。
- 已对照阶段 6 相关 `git diff`，确认记录覆盖了：
- 保存链落盘 `thumbnail.png`
- provider 优先命中持久化缩略图
- renderer 支持运行时直出和持久化图重排版
- 本次未执行项目级编译；因此这里的验证范围以代码审查、diff 对照和 lint 为主。
