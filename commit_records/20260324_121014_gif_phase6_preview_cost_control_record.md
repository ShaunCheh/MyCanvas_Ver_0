# 20260324_121014_gif_phase6_preview_cost_control_record

## 记录范围

- 记录内容：
  - 新增共享的 GIF 首帧 poster 解码工具，统一 board list 与持久化 thumbnail 的静态预览入口。
  - 调整 `BoardThumbnailRenderer`，显式按预览模式使用 GIF 首帧，并在一次缩略图渲染中按 `assetFilename` 复用解码结果。
  - 调整 `BoardPersistedThumbnailStore`，统一通过 poster 首帧解码已持久化的 `thumbnail.png`。
  - 调整 `BoardPreviewProvider`，把 board list 的 poster-only 预览策略显式传给缩略图渲染器。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImagePosterFrameDecoder.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- 边界确认：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift`
  - 上述 minimap 链路本阶段保持只走几何，没有引入 GIF 动画，也没有代码改动。
- 本记录不包含：
  - 阶段 0 GIF 语义契约
  - 阶段 1 图片资产模型拆分
  - 阶段 2 导入原始 GIF 资源保留
  - 阶段 3 文档格式与存储迁移
  - 阶段 4 render contract 稳定化
  - 阶段 5 主画布 GIF 播放系统
  - git commit / push

## 修改一：新增共享 poster 首帧解码器，收敛 GIF 静态预览入口

### 修改前

- board list 缩略图和持久化 thumbnail 都是在各自文件里直接调用 `CGImageSourceCreateThumbnailAtIndex(..., 0, ...)` 或 `CGImageSourceCreateImageAtIndex(..., 0, ...)`。
- 这种写法虽然通常也会拿到第 0 帧，但逻辑分散在多个位置，无法明确表达“GIF 预览统一只取首帧 poster”的阶段 6 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: loadAssetImage(for:assetsDirectoryURL:maxPixelSize:)
// 功能说明: 修改前 board list 缩略图渲染器在本地直接创建 CGImageSource，并在函数内部各自解第 0 帧，没有统一的 poster 解码抽象。
private func loadAssetImage(
    for itemRecord: BoardImageItemRecord,
    assetsDirectoryURL: URL,
    maxPixelSize: Int
) throws -> CGImage {
    let assetURL = assetsDirectoryURL.appendingPathComponent(itemRecord.assetFilename)
    let assetData = try CoordinatedFileIO.readData(at: assetURL)
    guard
        let imageSource = CGImageSourceCreateWithData(assetData as CFData, nil)
    else {
        throw BoardThumbnailRendererError.invalidBoardImageAsset(
            filename: itemRecord.assetFilename
        )
    }

    let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 64)
    ]
    if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
        imageSource,
        0,
        thumbnailOptions as CFDictionary
    ) {
        return thumbnail
    }

    let imageOptions: [CFString: Any] = [
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard
        let image = CGImageSourceCreateImageAtIndex(
            imageSource,
            0,
            imageOptions as CFDictionary
        )
    else {
        throw BoardThumbnailRendererError.invalidBoardImageAsset(
            filename: itemRecord.assetFilename
        )
    }

    return image
}
```

### 修改后

- 新增 `CanvasImagePosterFrameDecoder`：
  - `decodePosterFrame(from data:maxPixelSize:)`
  - `decodePosterFrame(from imageSource:maxPixelSize:)`
- 统一通过这个工具解码静态预览 poster，明确阶段 6 的语义就是“只取首帧，不播放动画”。
- 这样 board list / persisted thumbnail 后续只要依赖这个工具，就不会再把 GIF 预览逻辑散落到多处。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImagePosterFrameDecoder.swift
// 函数名: decodePosterFrame(from:maxPixelSize:) / decodePosterFrame(from:imageSource:maxPixelSize:)
// 功能说明: 修改后新增共享 poster 首帧解码器；board list 与持久化 thumbnail 都统一通过它解 GIF 首帧，而不是各处分别直接碰 ImageIO。
enum CanvasImagePosterFrameDecoder {
    static func decodePosterFrame(
        from data: Data,
        maxPixelSize: Int? = nil
    ) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        return decodePosterFrame(
            from: imageSource,
            maxPixelSize: maxPixelSize
        )
    }

    static func decodePosterFrame(
        from imageSource: CGImageSource,
        maxPixelSize: Int? = nil
    ) -> CGImage? {
        if let maxPixelSize, maxPixelSize > 0 {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 64)
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                0,
                thumbnailOptions as CFDictionary
            ) {
                return thumbnail
            }
        }

        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateImageAtIndex(
            imageSource,
            0,
            imageOptions as CFDictionary
        )
    }
}
```

## 修改二：`BoardPersistedThumbnailStore` 显式声明持久化 thumbnail 只走 poster 首帧

### 修改前

- `BoardPersistedThumbnailStore.loadThumbnailIfFresh(...)` 自己读 `thumbnail.png`，自己构造 `CGImageSource` 再解第 0 张图。
- 这虽然能得到静态图，但没有把“persisted thumbnail surface 只允许 poster frame”这个契约体现在代码结构里。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数名: loadThumbnailIfFresh(at:updatedAt:maxPixelSize:)
// 功能说明: 修改前持久化 thumbnail 解码逻辑分散在存储层内部，缺少与 GIF poster-only 语义对应的共享入口。
static func loadThumbnailIfFresh(
    at thumbnailURL: URL,
    updatedAt: Date,
    maxPixelSize: Int
) throws -> CGImage? {
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

    let imageOptions: [CFString: Any] = [
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard
        let image = CGImageSourceCreateImageAtIndex(
            imageSource,
            0,
            imageOptions as CFDictionary
        )
    else {
        throw BoardPersistedThumbnailStoreError.invalidPersistedThumbnail
    }

    return image
}
```

### 修改后

- `BoardPersistedThumbnailStore` 新增：
  - `animatedImagePreviewSurface = .persistedThumbnail`
  - `animatedImagePreviewMode`
  - `usesPosterFrameForAnimatedImages`
- `loadThumbnailIfFresh(...)` 现在统一走 `CanvasImagePosterFrameDecoder.decodePosterFrame(...)`，显式绑定到 `.posterFrameOnly` 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数名: animatedImagePreviewMode / usesPosterFrameForAnimatedImages / loadThumbnailIfFresh(at:updatedAt:maxPixelSize:)
// 功能说明: 修改后持久化 thumbnail 明确声明自己属于 persistedThumbnail surface，并统一通过共享 poster 解码器读取静态首帧。
enum BoardPersistedThumbnailStore {
    static let animatedImagePreviewSurface: CanvasAnimatedImagePreviewSurface = .persistedThumbnail

    static var animatedImagePreviewMode: CanvasAnimatedImagePreviewMode {
        CanvasImageAssetContract.current.previewMode(
            for: animatedImagePreviewSurface
        )
    }

    static var usesPosterFrameForAnimatedImages: Bool {
        animatedImagePreviewMode == .posterFrameOnly
    }

    static func loadThumbnailIfFresh(
        at thumbnailURL: URL,
        updatedAt: Date,
        maxPixelSize: Int
    ) throws -> CGImage? {
        let thumbnailData = try CoordinatedFileIO.readData(at: thumbnailURL)
        guard
            usesPosterFrameForAnimatedImages,
            let image = CanvasImagePosterFrameDecoder.decodePosterFrame(
                from: thumbnailData,
                maxPixelSize: maxPixelSize
            )
        else {
            throw BoardPersistedThumbnailStoreError.invalidPersistedThumbnail
        }

        return image
    }
}
```

## 修改三：`BoardThumbnailRenderer` 显式传入 GIF 预览模式，并按资产文件名复用解码结果

### 修改前

- `renderThumbnail(for:targetPixelSize:...)` 没有显式的 animated preview mode 参数。
- 每个图片 item 都会单独调用 `loadAssetImage(...)` 去读取并解码资产；如果多个 item 共享同一个 GIF 资产文件，会在同一次 thumbnail 渲染里重复读取、重复解码。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(for:targetPixelSize:contentInset:cancellationCheck:)
// 功能说明: 修改前 board list 缩略图渲染器没有显式传入 GIF 预览模式，同一资产在同次渲染中也可能被重复读取和重复解码。
func renderThumbnail(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize,
    contentInset: CGFloat = 10,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    try renderThumbnail(
        itemRecords: item.document.items,
        previewSeed: item.previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: contentInset,
        cancellationCheck: cancellationCheck
    ) { itemRecord, geometry in
        let decodeMaxPixelSize = self.decodeMaxPixelSize(
            for: itemRecord,
            geometry: geometry
        )
        return try self.loadAssetImage(
            for: itemRecord,
            assetsDirectoryURL: item.assetsDirectoryURL,
            maxPixelSize: decodeMaxPixelSize
        )
    }
}
```

### 修改后

- `renderThumbnail(for:...)` 新增 `animatedImagePreviewMode` 参数，默认取 `BoardPreviewContent.animatedImagePreviewMode`。
- 引入两层按 `assetFilename` 的复用：
  - `decodeMaxPixelSizesByFilename`
  - `cachedImagesByFilename`
- `loadAssetPreviewImage(...)` 统一根据 `animatedImagePreviewMode` 走 `CanvasImagePosterFrameDecoder`，现在 GIF board list 预览明确只会取首帧。
- `renderPersistedThumbnail(...)` 也显式带上 `BoardPersistedThumbnailStore.animatedImagePreviewMode`，保证落盘的 `thumbnail.png` 继续是静态首帧。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(for:targetPixelSize:animatedImagePreviewMode:contentInset:cancellationCheck:) / decodeMaxPixelSizesByFilename(from:geometry:) / loadAssetPreviewImage(for:assetsDirectoryURL:animatedImagePreviewMode:maxPixelSize:)
// 功能说明: 修改后缩略图渲染器显式接收 GIF 预览模式，并在一次渲染中按 assetFilename 复用 decode 尺寸和解码结果，避免同一 GIF 被重复解码。
func renderThumbnail(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode =
        BoardPreviewContent.animatedImagePreviewMode,
    contentInset: CGFloat = 10,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    var cachedImagesByFilename: [String: CGImage] = [:]
    var decodeMaxPixelSizesByFilename: [String: Int] = [:]
    try renderThumbnail(
        itemRecords: item.document.items,
        previewSeed: item.previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: contentInset,
        cancellationCheck: cancellationCheck
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
        let existingPixelSize = resolvedMaxPixelSizesByFilename[
            imageItemRecord.assetFilename
        ] ?? 0
        resolvedMaxPixelSizesByFilename[imageItemRecord.assetFilename] = max(
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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderPersistedThumbnail(for:animatedImagePreviewMode:maximumLongestSide:cancellationCheck:)
// 功能说明: 修改后持久化 thumbnail 的生成入口也显式走 persistedThumbnail surface 的 poster-only 策略，保证最终落盘仍是静态 thumbnail.png。
func renderPersistedThumbnail(
    for runtimeState: BoardRuntimeState,
    animatedImagePreviewMode: CanvasAnimatedImagePreviewMode =
        BoardPersistedThumbnailStore.animatedImagePreviewMode,
    maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    // ...
    return try renderThumbnail(
        itemRecords: document.items,
        previewSeed: previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: 0,
        cancellationCheck: cancellationCheck
    ) { itemRecord, _, _ in
        guard let runtimeItem = runtimeItemsByID[itemRecord.id] else {
            throw BoardThumbnailRendererError.invalidRuntimeImageAsset(
                itemID: itemRecord.id
            )
        }

        // Persisted board thumbnails stay static even for GIF boards; the
        // runtime poster is the single frame we rasterize into thumbnail.png.
        guard animatedImagePreviewMode == .posterFrameOnly else {
            return runtimeItem.posterCGImage
        }
        return runtimeItem.posterCGImage
    }
}
```

## 修改四：`BoardPreviewProvider` 显式把 board list 的 poster-only 契约传进渲染器

### 修改前

- `BoardPreviewProvider.loadBestAvailableThumbnail(...)` 直接调用 `thumbnailRenderer.renderThumbnail(for:targetPixelSize:cancellationCheck:)`。
- 虽然 `BoardPreviewContent` 已经有 `.boardList` surface 的语义，但 provider 这一层没有把它明确传进缩略图渲染器。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: loadBestAvailableThumbnail(for:cacheKey:cancellationCheck:)
// 功能说明: 修改前 provider 直接请求缩略图渲染，没有显式把 board list 的 GIF poster-only 预览模式传给渲染器。
private func loadBestAvailableThumbnail(
    for item: BoardCatalogItem,
    cacheKey: BoardThumbnailCacheKey,
    cancellationCheck: () throws -> Void
) throws -> CGImage? {
    // ...
    try cancellationCheck()
    return try thumbnailRenderer.renderThumbnail(
        for: item,
        targetPixelSize: cacheKey.pixelSize,
        cancellationCheck: cancellationCheck
    )
}
```

### 修改后

- `BoardPreviewProvider` 现在显式传入 `BoardPreviewContent.animatedImagePreviewMode`。
- 这样 board list 的 GIF 预览策略不再只是约定，而是通过调用链直接落实到缩略图解码层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: loadBestAvailableThumbnail(for:cacheKey:cancellationCheck:)
// 功能说明: 修改后 provider 显式把 board list 的 GIF poster-only 预览模式传给缩略图渲染器，避免策略只停留在 content 枚举层。
private func loadBestAvailableThumbnail(
    for item: BoardCatalogItem,
    cacheKey: BoardThumbnailCacheKey,
    cancellationCheck: () throws -> Void
) throws -> CGImage? {
    // ...
    try cancellationCheck()
    return try thumbnailRenderer.renderThumbnail(
        for: item,
        targetPixelSize: cacheKey.pixelSize,
        animatedImagePreviewMode: BoardPreviewContent.animatedImagePreviewMode,
        cancellationCheck: cancellationCheck
    )
}
```

## 边界确认：minimap 继续只走几何，本阶段不引入 GIF 动画

- 阶段 6 的目标之一是确保 GIF 只在主画布播放，minimap 不承担任何动画解码或播放责任。
- 本次核对后确认：
  - `CanvasMiniMapRenderer` 仍然只组合节点与几何矩形。
  - `CanvasMiniMapNodeProvider` 仍然只基于 scene / presentation 生成 worldQuad，不涉及图片帧或 `CGImage`。
- 因此 minimap 链路本阶段保持原状，没有代码修改。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: makeSnapshot(context:) / resolveNodes(using:)
// 功能说明: 本阶段确认 minimap renderer 继续只处理节点几何与可见世界范围，不引入 GIF 解码或播放逻辑。
struct CanvasMiniMapRenderer {
    func makeSnapshot(
        context: CanvasMiniMapRenderContext
    ) -> CanvasMiniMapSnapshot {
        let visibleWorldRect = sanitizedWorldRect(context.camera.visibleWorldRect) ?? .zero
        let nodes = resolveNodes(using: context.nodeProviderContext)
        // ... 只组合几何边界与节点列表 ...
        return CanvasMiniMapSnapshot(
            boardWorldRect: boardWorldRect,
            displayWorldRect: displayWorldRect,
            visibleWorldRect: visibleWorldRect,
            nodes: nodes
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
// 函数名: makeNodes(context:)
// 功能说明: 本阶段确认 minimap node provider 继续只从 presentation 提取 worldQuad 和 zIndex，不涉及 GIF 帧内容。
struct CanvasMiniMapImageNodeProvider: CanvasMiniMapNodeProviding {
    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedItems().map { item in
            let presentation = presentationResolver.resolve(
                item: item,
                inlineEditState: context.inlineEditState,
                rotationPreviewState: context.rotationPreviewState
            )
            return CanvasMiniMapNode(
                id: presentation.itemID,
                kind: .image,
                worldQuad: presentation.visibleWorldQuad,
                zIndex: presentation.zIndex,
                isPreviewActive: presentation.isCropPreviewActive || presentation.isRotationPreviewActive
            )
        }
    }
}
```

## 本阶段结果

- board list 缩略图现在显式按 `.boardList` surface 只解 GIF 首帧，不播放 GIF。
- 持久化 `thumbnail.png` 的读取和生成链路都显式按 `.persistedThumbnail` surface 只走 poster 首帧。
- 同一 GIF 资产在一次缩略图渲染中只会读取 / 解码一次，降低多实例 board 的预览成本。
- minimap 继续保持几何-only，GIF 仍然只在主画布播放。
