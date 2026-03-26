# 20260326_182250_boardlist_thumbnail_version_stage2_record

## 记录范围

- 记录目标：记录本次 `boardlist` 缩略图版本治理阶段 2 的实现。
- 阶段目标：把缩略图版本写进 `thumbnail.png` 元数据，并在读取 persisted 缩略图时先校验版本。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- 本记录不包含：阶段 3 的 fresh-render 高分辨率回写链路。
- 本记录不包含：原始 GIF diff。
- 本记录不包含：git commit。

## 修改前：persisted 缩略图只按文件时间判断“是否可复用”

- 修改前，`BoardPersistedThumbnailStore.loadThumbnailIfFresh(...)` 只看 `thumbnail.png` 的修改时间是否晚于 `updatedAt`。
- 修改前，文件一旦被判为 fresh，就会直接解码 poster frame，没有任何“缩略图格式版本”校验。
- 修改前，`BoardPreviewProvider.loadPersistedThumbnailPreview(...)` 只能把 persisted miss 归因为 `missing-or-stale`，无法识别“这是旧算法生成的 PNG”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数名: loadThumbnailIfFresh(at:updatedAt:boardID:maxPixelSize:)
// 功能说明: 修改前只按文件时间判断 persisted thumbnail 是否 fresh，随后直接解码图片。
// 关键限制: 这里没有读取 PNG 元数据，也没有校验缩略图渲染版本。
static func loadThumbnailIfFresh(
    at thumbnailURL: URL,
    updatedAt: Date,
    boardID: UUID? = nil,
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
        usesPosterFrameForAnimatedImages,
        let image = CanvasImagePosterFrameDecoder.decodePosterFrame(
            from: thumbnailData,
            maxPixelSize: maxPixelSize
        )
    else {
        throw BoardPersistedThumbnailStoreError.invalidPersistedThumbnail
    }

    logPersistedThumbnailImage(
        phase: "load-output",
        boardID: boardID,
        image: image,
        maxPixelSize: maxPixelSize
    )
    return image
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数名: makePNGData(for:)
// 功能说明: 修改前编码 thumbnail.png 时只写入像素数据。
// 关键限制: 持久化文件里没有 embedded version，后续读取时无法区分新旧算法生成的 PNG。
private static func makePNGData(
    for image: CGImage
) throws -> Data {
    let mutableData = NSMutableData()
    guard
        let imageDestination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw BoardPersistedThumbnailStoreError.failedToEncodeThumbnail
    }

    CGImageDestinationAddImage(imageDestination, image, nil)
    guard CGImageDestinationFinalize(imageDestination) else {
        throw BoardPersistedThumbnailStoreError.failedToEncodeThumbnail
    }

    return mutableData as Data
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: loadPersistedThumbnailPreview(for:cacheKey:cancellationCheck:)
// 功能说明: 修改前 Provider 只能区分 persisted-hit 和 missing-or-stale。
// 关键限制: 旧格式 thumbnail.png 即使像素语义已经过时，也会继续走 persisted-hit。
guard
    let persistedThumbnail = try BoardPersistedThumbnailStore.loadThumbnailIfFresh(
        at: item.persistedThumbnailURL,
        updatedAt: item.updatedAt,
        boardID: item.boardID,
        maxPixelSize: decodeMaxPixelSize
    )
else {
    logBoardPreviewProviderDecision(
        phase: "loadPersistedThumbnailPreview",
        boardID: item.boardID,
        revisionToken: item.revisionToken,
        targetPixelSize: cacheKey.pixelSize,
        source: "persisted-miss",
        reason: "missing-or-stale"
    )
    return nil
}
```

## 修改后：写入 embedded version，并在 persisted 读取时显式校验

- 修改后，`BoardPersistedThumbnailStore` 新增 `BoardPersistedThumbnailStoreLoadResult`，把 persisted 读取结果细分为：
  - `.image`
  - `.missingOrStale`
  - `.formatVersionMismatch`
- 修改后，`makePNGData(for:)` 会通过 `CGImageDestinationAddImage(..., properties)` 把当前缩略图版本写进 `thumbnail.png` 的 PNG 元数据。
- 修改后，`loadThumbnailIfFresh(...)` 会先构造 `CGImageSource`，读取 embedded version；版本缺失或不匹配时，不再继续解码旧图，而是返回 `.formatVersionMismatch`。
- 修改后，`BoardPreviewProvider.loadPersistedThumbnailPreview(...)` 能把这类情况明确记录为 `persisted-miss reason=format-version-mismatch`。
- 本阶段同时把 `formatVersion` 从 `1` 提升到 `2`，确保阶段 2 与阶段 1 的缓存桶彻底隔离。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数名: 类型级结果枚举定义 + loadThumbnailIfFresh(at:updatedAt:boardID:maxPixelSize:)
// 功能说明: 修改后 persisted 读取先区分 miss 原因，再决定是否继续解码图片。
// 修复结果: 旧版本 thumbnail.png 会被显式识别为 formatVersion 不匹配，而不是继续走 persisted-hit。
enum BoardPersistedThumbnailStoreLoadResult {
    case image(CGImage)
    case missingOrStale
    case formatVersionMismatch
}

static func loadThumbnailIfFresh(
    at thumbnailURL: URL,
    updatedAt: Date,
    boardID: UUID? = nil,
    maxPixelSize: Int
) throws -> BoardPersistedThumbnailStoreLoadResult {
    guard
        try isFreshThumbnail(
            at: thumbnailURL,
            updatedAt: updatedAt
        )
    else {
        return .missingOrStale
    }

    let thumbnailData = try CoordinatedFileIO.readData(at: thumbnailURL)
    guard let imageSource = CGImageSourceCreateWithData(thumbnailData as CFData, nil)
    else {
        throw BoardPersistedThumbnailStoreError.invalidPersistedThumbnail
    }
    guard persistedThumbnailFormatVersion(from: imageSource) == formatVersion else {
        return .formatVersionMismatch
    }
    guard
        usesPosterFrameForAnimatedImages,
        let image = CanvasImagePosterFrameDecoder.decodePosterFrame(
            from: imageSource,
            maxPixelSize: maxPixelSize
        )
    else {
        throw BoardPersistedThumbnailStoreError.invalidPersistedThumbnail
    }

    logPersistedThumbnailImage(
        phase: "load-output",
        boardID: boardID,
        image: image,
        maxPixelSize: maxPixelSize
    )
    return .image(image)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数名: makePNGData(for:) / pngMetadataProperties() / persistedThumbnailFormatVersion(from:)
// 功能说明: 修改后在写入时把版本写进 PNG metadata，在读取时从同一元数据字段解析版本。
// 修复结果: persisted thumbnail 本身开始携带“这是哪一代渲染算法产物”的协议标记。
private static func makePNGData(
    for image: CGImage
) throws -> Data {
    let mutableData = NSMutableData()
    guard
        let imageDestination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw BoardPersistedThumbnailStoreError.failedToEncodeThumbnail
    }

    CGImageDestinationAddImage(
        imageDestination,
        image,
        pngMetadataProperties() as CFDictionary
    )
    guard CGImageDestinationFinalize(imageDestination) else {
        throw BoardPersistedThumbnailStoreError.failedToEncodeThumbnail
    }

    return mutableData as Data
}

private static func pngMetadataProperties() -> [CFString: Any] {
    [
        kCGImagePropertyPNGDictionary: [
            kCGImagePropertyPNGDescription: formatVersionMetadataValue()
        ]
    ]
}

private static func persistedThumbnailFormatVersion(
    from imageSource: CGImageSource
) -> Int? {
    guard
        let properties = CGImageSourceCopyPropertiesAtIndex(
            imageSource,
            0,
            nil
        ) as? [AnyHashable: Any],
        let pngProperties = properties[kCGImagePropertyPNGDictionary]
            as? [AnyHashable: Any],
        let metadataValue = pngProperties[kCGImagePropertyPNGDescription] as? String
    else {
        return nil
    }

    return parsePersistedThumbnailFormatVersion(from: metadataValue)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: loadPersistedThumbnailPreview(for:cacheKey:cancellationCheck:)
// 功能说明: 修改后 Provider 根据 persisted 读取结果分别记录 miss 原因。
// 修复结果: 旧缩略图版本会明确落到 persisted-miss / format-version-mismatch，不再误记为 persisted-hit。
let persistedThumbnailResult = try BoardPersistedThumbnailStore.loadThumbnailIfFresh(
    at: item.persistedThumbnailURL,
    updatedAt: item.updatedAt,
    boardID: item.boardID,
    maxPixelSize: decodeMaxPixelSize
)
let persistedThumbnail: CGImage
switch persistedThumbnailResult {
case .image(let loadedThumbnail):
    persistedThumbnail = loadedThumbnail
case .missingOrStale:
    logBoardPreviewProviderDecision(
        phase: "loadPersistedThumbnailPreview",
        boardID: item.boardID,
        revisionToken: item.revisionToken,
        targetPixelSize: cacheKey.pixelSize,
        source: "persisted-miss",
        reason: "missing-or-stale"
    )
    return nil
case .formatVersionMismatch:
    logBoardPreviewProviderDecision(
        phase: "loadPersistedThumbnailPreview",
        boardID: item.boardID,
        revisionToken: item.revisionToken,
        targetPixelSize: cacheKey.pixelSize,
        source: "persisted-miss",
        reason: "format-version-mismatch"
    )
    return nil
}
```

## 本次修改后的实际行为

- 旧的 `thumbnail.png` 如果没有 embedded version，或者版本不是当前 `formatVersion=2`，将不再进入 `persisted-hit`。
- 这类旧 persisted 图会被当作 `persisted-miss reason=format-version-mismatch`，从而把列表渲染导向 fresh-render。
- `PersistedImage` 日志现在会带 `formatVersion=` 字段，方便后续直接区分当前写盘协议版本。
- 本阶段仍然没有补 fresh-render 之后的高分辨率 persisted 回写，所以第一次修复后的结果还不会自动沉淀成新的 `thumbnail.png`。

## 验证情况

- 已检查 `MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift` 的 lint / 语法诊断：无新增错误。
- 已检查 `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift` 的 lint / 语法诊断：无新增错误。
- 已复核本次 diff：阶段 2 只收敛在 persisted 元数据读写与 Provider 的 miss 原因分流，没有提前进入阶段 3 的回写链路。
