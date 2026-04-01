# 20260401_143448_video_boardlist_thumbnail_phase4_record

## 记录范围

- 记录内容：
  1. 抽出共享 `BoardMediaPosterImageResolver`，统一 BoardList / thumbnail 链路里的“媒体封面解析”语义。
  2. 改造 `BoardThumbnailRenderer`，不再默认所有素材都按 `assetFilename + CanvasImagePosterFrameDecoder` 直解，而是按图片/GIF 与视频 poster 分流。
  3. 改造 `BoardPreviewProvider` 的 cache-hit / source-image trace 路径，确保日志链路与 fresh render 使用同一套媒体封面解析逻辑。
  4. 上调 `BoardPersistedThumbnailStore.formatVersion`，强制旧 persisted thumbnail 失效并重建。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardMediaPosterImageResolver.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift`
- 本记录不包含：
  - 阶段 1 / 2 / 3 的视频导入、持久化与运行时 poster-only 展示
  - `BoardPreviewRenderer`、cell/view 层消费 `CGImage` 的逻辑改造
  - 阶段 5 的右键菜单“设置展示画面”
  - git commit / push

## 修改一：抽出共享媒体封面解析器

### 修改前

- `BoardThumbnailRenderer` 默认把所有 `BoardImageItemRecord` 都当成“图片/GIF 资产”。
- 它直接读取 `itemRecord.assetFilename` 对应文件，并用 `CanvasImagePosterFrameDecoder` 解码。
- 这在图片/GIF 下成立，但视频 item 阶段 1/3 之后已经是“双资产”：`sourceVideoFilename` 是源视频，`posterImageFilename` 才是 BoardList 真正该读取的展示图。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: loadAssetPreviewImage(for:assetsDirectoryURL:animatedImagePreviewMode:maxPixelSize:)
// 功能说明: 修改前 thumbnail renderer 把所有 item 都当成 image asset 处理，统一读取 assetFilename 并直接做 poster frame 解码。
private func loadAssetPreviewImage(
    for itemRecord: BoardImageItemRecord,
    assetsDirectoryURL: URL,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode,
    maxPixelSize: Int
) throws -> CGImage {
    let assetURL = assetsDirectoryURL.appendingPathComponent(itemRecord.assetFilename)
    let assetData = try CoordinatedFileIO.readData(at: assetURL)
    let image: CGImage?
    switch animatedImagePreviewMode {
    case .posterFrameOnly:
        image = CanvasImagePosterFrameDecoder.decodePosterFrame(
            from: assetData,
            maxPixelSize: maxPixelSize
        )
    }

    guard let image else {
        throw BoardThumbnailRendererError.invalidBoardImageAsset(
            filename: itemRecord.assetFilename
        )
    }

    return image
}
```

### 修改后

- 新增 `BoardMediaPosterImageResolver`。
- 这个 resolver 会根据 `BoardImageItemRecord.isVideo` 决定封面来源：
  - 图片 / GIF：继续读取 `assetFilename`
  - 视频：明确读取 `posterImageFilename`
- 这样 BoardList、fresh render、trace 链路对“视频缩略图应该取哪张图”的语义完全统一。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardMediaPosterImageResolver.swift
// 函数名: previewAssetFilename(for:) / resolvePreviewImage(for:assetsDirectoryURL:animatedImagePreviewMode:maxPixelSize:)
// 功能说明: 修改后共享 resolver 统一决定某个 item 在 BoardList / thumbnail 链路里该读哪张 poster 图，并负责按图片/GIF 与视频 poster 分流解码。
struct BoardMediaPosterImageResolver {
    private enum PosterSource {
        case imageAsset(filename: String)
        case videoPoster(filename: String)
    }

    func previewAssetFilename(
        for itemRecord: BoardImageItemRecord
    ) -> String {
        switch posterSource(for: itemRecord) {
        case let .imageAsset(filename), let .videoPoster(filename):
            return filename
        }
    }

    func resolvePreviewImage(
        for itemRecord: BoardImageItemRecord,
        assetsDirectoryURL: URL,
        animatedImagePreviewMode: CanvasAnimatedImagePreviewMode,
        maxPixelSize: Int
    ) throws -> CGImage {
        switch posterSource(for: itemRecord) {
        case let .imageAsset(filename):
            return try loadImageAssetPosterFrame(
                named: filename,
                in: assetsDirectoryURL,
                animatedImagePreviewMode: animatedImagePreviewMode,
                maxPixelSize: maxPixelSize
            )
        case let .videoPoster(filename):
            return try loadVideoPosterImage(
                named: filename,
                in: assetsDirectoryURL,
                maxPixelSize: maxPixelSize
            )
        }
    }

    private func posterSource(
        for itemRecord: BoardImageItemRecord
    ) -> PosterSource {
        if itemRecord.isVideo {
            return .videoPoster(filename: itemRecord.posterImageFilename)
        }

        return .imageAsset(filename: itemRecord.assetFilename)
    }
}
```

## 修改二：`BoardThumbnailRenderer` 改为按 preview poster 文件缓存与取图

### 修改前

- `renderCatalogItemThumbnail(...)` 内部按 `itemRecord.assetFilename` 做 decode size 复用和图片缓存。
- 对视频 item 来说，这个 key 语义不对，因为真正参与预览的不是源视频文件，而是本地 poster 图。
- 同时，`BoardThumbnailRendererError` 里还保留了“invalidBoardImageAsset(filename:)”这种仅面向图片资产的错误命名。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderCatalogItemThumbnail(_:targetPixelSize:animatedImagePreviewMode:contentInset:traceMode:cancellationCheck:)
// 功能说明: 修改前 renderer 的 decode size 复用与图片缓存都绑定 assetFilename，默认假设所有 item 都直接消费 image asset。
private func renderCatalogItemThumbnail(
    _ item: BoardCatalogItem,
    targetPixelSize: CGSize,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode,
    contentInset: CGFloat,
    traceMode: String,
    cancellationCheck: () throws -> Void
) throws -> CGImage? {
    var cachedImagesByFilename: [String: CGImage] = [:]
    var decodeMaxPixelSizesByFilename: [String: Int] = [:]

    return try renderThumbnail(
        itemRecords: item.document.items,
        previewSeed: item.previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: contentInset,
        cancellationCheck: cancellationCheck,
        traceContext: traceContext
    ) { itemRecord, geometry, itemRecords in
        if decodeMaxPixelSizesByFilename.isEmpty {
            decodeMaxPixelSizesByFilename = self.decodeMaxPixelSizesByFilename(
                from: itemRecords,
                geometry: geometry
            )
        }
        let decodeMaxPixelSize = decodeMaxPixelSizesByFilename[
            itemRecord.assetFilename
        ] ?? self.decodeMaxPixelSize(
            for: itemRecord,
            geometry: geometry
        )
        if let cachedImage = cachedImagesByFilename[itemRecord.assetFilename] {
            return cachedImage
        }

        let image = try self.loadAssetPreviewImage(
            for: itemRecord,
            assetsDirectoryURL: item.assetsDirectoryURL,
            animatedImagePreviewMode: animatedImagePreviewMode,
            maxPixelSize: decodeMaxPixelSize
        )
        cachedImagesByFilename[itemRecord.assetFilename] = image
        return image
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 类型/函数: BoardThumbnailRendererError.invalidBoardImageAsset
// 功能说明: 修改前错误类型仍然把失败场景命名成“image asset 无效”，不适合媒体 poster 统一解析后的语义。
enum BoardThumbnailRendererError: LocalizedError {
    case invalidBitmapContext
    case invalidBoardImageAsset(filename: String)
    case invalidRuntimeImageAsset(itemID: UUID)
    case cancelled
}
```

### 修改后

- `BoardThumbnailRenderer` 注入 `BoardMediaPosterImageResolver`。
- fresh render 缓存与 decodeMaxPixelSize 复用统一改为按 `previewAssetFilename` 走。
- 实际取图逻辑完全委托给 resolver。
- `invalidBoardImageAsset` 被移除，媒体 poster 解码错误统一交给 resolver 抛出。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: init(geometryPreviewBuilder:mediaPosterImageResolver:) / renderCatalogItemThumbnail(...)
// 功能说明: 修改后 renderer 通过共享 resolver 决定 preview asset filename，并用它作为缓存与 decode size 复用键，视频场景下会稳定绑定到 posterImageFilename。
final class BoardThumbnailRenderer {
    private let geometryPreviewBuilder: BoardGeometryPreviewBuilder
    private let mediaPosterImageResolver: BoardMediaPosterImageResolver

    init(
        geometryPreviewBuilder: BoardGeometryPreviewBuilder = BoardGeometryPreviewBuilder(),
        mediaPosterImageResolver: BoardMediaPosterImageResolver = BoardMediaPosterImageResolver()
    ) {
        self.geometryPreviewBuilder = geometryPreviewBuilder
        self.mediaPosterImageResolver = mediaPosterImageResolver
    }

    private func renderCatalogItemThumbnail(
        _ item: BoardCatalogItem,
        targetPixelSize: CGSize,
        animatedImagePreviewMode: CanvasAnimatedImagePreviewMode,
        contentInset: CGFloat,
        traceMode: String,
        cancellationCheck: () throws -> Void
    ) throws -> CGImage? {
        var cachedImagesByFilename: [String: CGImage] = [:]
        var decodeMaxPixelSizesByFilename: [String: Int] = [:]

        return try renderThumbnail(
            itemRecords: item.document.items,
            previewSeed: item.previewSeed,
            targetPixelSize: targetPixelSize,
            contentInset: contentInset,
            cancellationCheck: cancellationCheck,
            traceContext: traceContext
        ) { itemRecord, geometry, itemRecords in
            if decodeMaxPixelSizesByFilename.isEmpty {
                decodeMaxPixelSizesByFilename = self.decodeMaxPixelSizesByFilename(
                    from: itemRecords,
                    geometry: geometry
                )
            }
            let previewAssetFilename = self.mediaPosterImageResolver
                .previewAssetFilename(for: itemRecord)
            let decodeMaxPixelSize = decodeMaxPixelSizesByFilename[
                previewAssetFilename
            ] ?? self.decodeMaxPixelSize(
                for: itemRecord,
                geometry: geometry
            )
            if let cachedImage = cachedImagesByFilename[previewAssetFilename] {
                return cachedImage
            }

            let image = try self.loadAssetPreviewImage(
                for: itemRecord,
                assetsDirectoryURL: item.assetsDirectoryURL,
                animatedImagePreviewMode: animatedImagePreviewMode,
                maxPixelSize: decodeMaxPixelSize
            )
            cachedImagesByFilename[previewAssetFilename] = image
            return image
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: decodeMaxPixelSizesByFilename(from:geometry:) / loadAssetPreviewImage(for:assetsDirectoryURL:animatedImagePreviewMode:maxPixelSize:)
// 功能说明: 修改后 decode size 复用与实际取图都对齐到 resolver，renderer 本身不再内嵌“默认所有 item 都是图片资产”的假设。
private func decodeMaxPixelSizesByFilename(
    from itemRecords: [BoardItemRecord],
    geometry: CanvasMiniMapViewGeometry
) -> [String: Int] {
    var resolvedMaxPixelSizesByFilename: [String: Int] = [:]

    for itemRecord in itemRecords {
        guard case let .image(imageItemRecord) = itemRecord else {
            continue
        }

        let decodeMaxPixelSize = decodeMaxPixelSize(
            for: imageItemRecord,
            geometry: geometry
        )
        let previewAssetFilename = mediaPosterImageResolver
            .previewAssetFilename(for: imageItemRecord)
        let existingPixelSize = resolvedMaxPixelSizesByFilename[
            previewAssetFilename
        ] ?? 0
        resolvedMaxPixelSizesByFilename[previewAssetFilename] = max(
            existingPixelSize,
            decodeMaxPixelSize
        )
    }

    return resolvedMaxPixelSizesByFilename
}

private func loadAssetPreviewImage(
    for itemRecord: BoardImageItemRecord,
    assetsDirectoryURL: URL,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode,
    maxPixelSize: Int
) throws -> CGImage {
    try mediaPosterImageResolver.resolvePreviewImage(
        for: itemRecord,
        assetsDirectoryURL: assetsDirectoryURL,
        animatedImagePreviewMode: animatedImagePreviewMode,
        maxPixelSize: maxPixelSize
    )
}
```

## 修改三：`BoardPreviewProvider` 的 trace 链路与 fresh render 对齐

### 修改前

- `BoardPreviewProvider` 在 cache-hit 后会调用 `logBoardPreviewProviderSourceImagesIfNeeded(...)`。
- 这条 trace 路径自己手动读取 `imageItemRecord.assetFilename`，并直接用 `CanvasImagePosterFrameDecoder` 解码。
- 因此即使 fresh render 已经修好了视频 poster 读取，trace / debug 输出仍然可能继续看错资源。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: logBoardPreviewProviderCacheHit(...) / logBoardPreviewProviderSourceImagesIfNeeded(...)
// 功能说明: 修改前 provider 的 trace 逻辑仍然手动读 assetFilename，对视频 item 不知道应该切到 posterImageFilename。
private func logBoardPreviewProviderCacheHit(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage
) {
    logBoardPreviewProviderSourceImagesIfNeeded(
        phase: phase,
        item: item
    )
}

private func logBoardPreviewProviderSourceImagesIfNeeded(
    phase: String,
    item: BoardCatalogItem,
    maxImageCount: Int = 8,
    maxPixelSize: Int = 128
) {
    for imageItemRecord in imageItemRecords {
        let assetURL = item.assetsDirectoryURL.appendingPathComponent(
            imageItemRecord.assetFilename
        )
        do {
            let assetData = try CoordinatedFileIO.readData(at: assetURL)
            guard
                let image = CanvasImagePosterFrameDecoder.decodePosterFrame(
                    from: assetData,
                    maxPixelSize: maxPixelSize
                )
            else {
                print("decode-failed")
                continue
            }

            print(
                "[BoardList][ThumbnailTrace][SourceImage] " +
                    "itemID=\(imageItemRecord.id.uuidString) " +
                    "assetFilename=\(imageItemRecord.assetFilename) " +
                    "signature=\(BoardThumbnailImageSignature.describe(image))"
            )
        } catch {
            print(
                "[BoardList][ThumbnailTrace][SourceImage] " +
                    "itemID=\(imageItemRecord.id.uuidString) " +
                    "assetFilename=\(imageItemRecord.assetFilename) " +
                    "status=read-failed " +
                    "error=\(error)"
            )
        }
    }
}
```

### 修改后

- `BoardPreviewProvider` 也注入同一个 `BoardMediaPosterImageResolver`。
- cache-hit trace 和 source-image trace 全部复用 resolver。
- 这样 BoardList 首屏、异步 thumbnail、trace 调试看到的“源图片”就跟实际缩略图取图完全一致了。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: init(thumbnailCache:thumbnailRenderer:mediaPosterImageResolver:callbackQueue:) / logBoardPreviewProviderCacheHit(...)
// 功能说明: 修改后 provider 自己也持有共享 resolver，并在 cache-hit trace 时继续沿用同一套媒体封面解析语义。
final class BoardPreviewProvider {
    private let thumbnailCache: BoardThumbnailCache
    private let thumbnailRenderer: BoardThumbnailRenderer
    private let mediaPosterImageResolver: BoardMediaPosterImageResolver
    private let renderQueue: OperationQueue
    private let callbackQueue: DispatchQueue

    init(
        thumbnailCache: BoardThumbnailCache = BoardThumbnailCache(),
        thumbnailRenderer: BoardThumbnailRenderer = BoardThumbnailRenderer(),
        mediaPosterImageResolver: BoardMediaPosterImageResolver = BoardMediaPosterImageResolver(),
        callbackQueue: DispatchQueue = .main
    ) {
        self.thumbnailCache = thumbnailCache
        self.thumbnailRenderer = thumbnailRenderer
        self.mediaPosterImageResolver = mediaPosterImageResolver
        self.callbackQueue = callbackQueue
    }
}

private func logBoardPreviewProviderCacheHit(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage,
    mediaPosterImageResolver: BoardMediaPosterImageResolver
) {
    logBoardPreviewProviderSourceImagesIfNeeded(
        phase: phase,
        item: item,
        mediaPosterImageResolver: mediaPosterImageResolver
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: logBoardPreviewProviderSourceImagesIfNeeded(phase:item:mediaPosterImageResolver:maxImageCount:maxPixelSize:)
// 功能说明: 修改后 provider 的 debug source image 解析与 fresh render 保持一致，视频 item 会打印 posterImageFilename 对应的签名而不是源视频文件。
private func logBoardPreviewProviderSourceImagesIfNeeded(
    phase: String,
    item: BoardCatalogItem,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    maxImageCount: Int = 8,
    maxPixelSize: Int = 128
) {
    for imageItemRecord in imageItemRecords {
        let previewAssetFilename = mediaPosterImageResolver.previewAssetFilename(
            for: imageItemRecord
        )
        do {
            let image = try mediaPosterImageResolver.resolvePreviewImage(
                for: imageItemRecord,
                assetsDirectoryURL: item.assetsDirectoryURL,
                animatedImagePreviewMode: BoardPreviewContent.animatedImagePreviewMode,
                maxPixelSize: maxPixelSize
            )

            print(
                "[BoardList][ThumbnailTrace][SourceImage] " +
                    "phase=\(phase) " +
                    "boardID=\(item.boardID.uuidString) " +
                    "itemID=\(imageItemRecord.id.uuidString) " +
                    "assetFilename=\(previewAssetFilename) " +
                    "signature=\(BoardThumbnailImageSignature.describe(image))"
            )
        } catch {
            print(
                "[BoardList][ThumbnailTrace][SourceImage] " +
                    "phase=\(phase) " +
                    "boardID=\(item.boardID.uuidString) " +
                    "itemID=\(imageItemRecord.id.uuidString) " +
                    "assetFilename=\(previewAssetFilename) " +
                    "status=read-failed " +
                    "error=\(error)"
            )
        }
    }
}
```

## 修改四：提升 persisted thumbnail 格式版本，强制旧像素失效

### 修改前

- `BoardPersistedThumbnailStore.formatVersion` 还是 `2`。
- 阶段 4 改完媒体封面解析后，如果继续命中旧版本 thumbnail，列表首屏仍可能复用历史像素，无法马上看到视频 poster 的新语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 类型/函数: BoardPersistedThumbnailStore.formatVersion
// 功能说明: 修改前 persisted thumbnail 仍沿用旧版本号，历史 thumbnail 仍有机会继续命中。
enum BoardPersistedThumbnailStore {
    static let filename = "thumbnail.png"
    static let formatVersion = 2
    static let maximumLongestSide: CGFloat = 1024
}
```

### 修改后

- `formatVersion` 升到 `3`。
- 现有 `BoardThumbnailCacheKey`、`loadThumbnailIfFresh(...)`、PNG metadata 版本检查机制继续复用，不需要额外改缓存键结构。
- 结果就是旧 persisted thumbnail 自动 miss，然后按新的媒体封面解析逻辑重建。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 类型/函数: BoardPersistedThumbnailStore.formatVersion
// 功能说明: 修改后 persisted thumbnail 版本上调到 3，旧缩略图会因为版本不匹配自动失效并触发重建。
enum BoardPersistedThumbnailStore {
    static let filename = "thumbnail.png"
    static let formatVersion = 3
    static let maximumLongestSide: CGFloat = 1024
}
```

## 结果说明

- BoardList 的 fresh render、cache-hit trace、source-image trace 现在都基于同一套媒体封面解析逻辑。
- 图片 / GIF 继续走原有 poster frame 解码，视频则明确读取本地 `posterImageFilename`。
- persisted thumbnail 因为版本号升级会整体失效重建，避免继续命中阶段 4 之前的旧像素。
- `BoardPreviewRenderer` 和 view/cell 层没有改，仍然只消费 `CGImage`，符合阶段 4 的边界要求。
