# 20260326_181300_boardlist_thumbnail_version_stage1_record

## 记录范围

- 记录目标：记录本次 `boardlist` 缩略图版本治理阶段 1 的实现。
- 阶段目标：先建立统一的缩略图版本常量，并让内存缓存键感知该版本。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailCache.swift`
- 本记录不包含：`thumbnail.png` 元数据读写。
- 本记录不包含：persisted 缩略图失效判定改造。
- 本记录不包含：git commit。

## 修改前：缩略图缓存键不感知渲染版本

- 修改前，`BoardPersistedThumbnailStore` 只有文件名、尺寸和 freshness 相关常量，没有“缩略图像素语义版本”。
- 修改前，`BoardThumbnailCacheKey` 只由 `boardID`、`revisionToken` 和像素尺寸组成。
- 这意味着即使缩略图渲染算法升级，只要 `updatedAt` 没变，内存缓存键就不会因为代码版本变化而失效。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数名: 无（BoardPersistedThumbnailStore 类型级静态常量定义位置）
// 功能说明: 修改前的持久化缩略图存储只声明文件名、最大边长和 freshness 相关常量。
// 关键限制: 这里还没有“缩略图格式/渲染版本”这个统一事实来源。
enum BoardPersistedThumbnailStore {
    static let filename = "thumbnail.png"
    static let maximumLongestSide: CGFloat = 1024
    private static let freshnessTolerance: TimeInterval = 1
    static let animatedImagePreviewSurface: CanvasAnimatedImagePreviewSurface = .persistedThumbnail
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailCache.swift
// 函数名: BoardThumbnailCacheKey.init(item:targetPixelSize:) / cacheKey
// 功能说明: 修改前的内存缓存键只拼接 boardID、revisionToken 和目标像素尺寸。
// 关键限制: 只要文档修订号不变，算法升级不会让 NSCache 的 key 发生变化。
struct BoardThumbnailCacheKey {
    let boardID: UUID
    let revisionToken: String
    let pixelWidth: Int
    let pixelHeight: Int

    init?(
        item: BoardCatalogItem,
        targetPixelSize: CGSize
    ) {
        let normalizedPixelSize = targetPixelSize.normalizedBoardThumbnailPixelSize
        guard normalizedPixelSize.width > 0, normalizedPixelSize.height > 0 else {
            return nil
        }

        boardID = item.boardID
        revisionToken = item.revisionToken
        pixelWidth = Int(normalizedPixelSize.width)
        pixelHeight = Int(normalizedPixelSize.height)
    }

    var cacheKey: NSString {
        "\(boardID.uuidString)-\(revisionToken)-\(pixelWidth)x\(pixelHeight)" as NSString
    }
}
```

## 修改后：建立统一版本常量，并接入内存缓存键

- 修改后，`BoardPersistedThumbnailStore` 新增 `formatVersion`，作为缩略图像素语义的统一版本常量。
- 修改后，`BoardThumbnailCacheKey` 新增 `thumbnailFormatVersion`，并在 `cacheKey` 中拼入 `v\(thumbnailFormatVersion)`。
- 这样做的作用是：后续只要提升缩略图版本常量，内存缓存就会自然失效，不再继续复用旧 key 对应的 `CGImage`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift
// 函数名: 无（BoardPersistedThumbnailStore 类型级静态常量定义位置）
// 功能说明: 修改后新增统一的缩略图格式版本常量，供缓存键和后续 persisted 协议共用。
// 阶段边界: 当前阶段只建立版本契约，还没有把它写进 thumbnail.png 元数据。
enum BoardPersistedThumbnailStore {
    static let filename = "thumbnail.png"
    // Bump this when thumbnail pixels should be regenerated even if the board
    // document itself did not change.
    static let formatVersion = 1
    static let maximumLongestSide: CGFloat = 1024
    private static let freshnessTolerance: TimeInterval = 1
    static let animatedImagePreviewSurface: CanvasAnimatedImagePreviewSurface = .persistedThumbnail
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailCache.swift
// 函数名: BoardThumbnailCacheKey.init(item:targetPixelSize:) / cacheKey
// 功能说明: 修改后把统一的缩略图版本常量接入缓存键，让内存缩略图缓存可以感知渲染算法代际。
// 修复结果: 后续提升 formatVersion 时，旧的 NSCache key 会自动失效，不再继续命中旧图。
struct BoardThumbnailCacheKey {
    let boardID: UUID
    let revisionToken: String
    let thumbnailFormatVersion: Int
    let pixelWidth: Int
    let pixelHeight: Int

    init?(
        item: BoardCatalogItem,
        targetPixelSize: CGSize
    ) {
        let normalizedPixelSize = targetPixelSize.normalizedBoardThumbnailPixelSize
        guard normalizedPixelSize.width > 0, normalizedPixelSize.height > 0 else {
            return nil
        }

        boardID = item.boardID
        revisionToken = item.revisionToken
        thumbnailFormatVersion = BoardPersistedThumbnailStore.formatVersion
        pixelWidth = Int(normalizedPixelSize.width)
        pixelHeight = Int(normalizedPixelSize.height)
    }

    var cacheKey: NSString {
        "\(boardID.uuidString)-\(revisionToken)-v\(thumbnailFormatVersion)-\(pixelWidth)x\(pixelHeight)" as NSString
    }
}
```

## 本次修改后的实际行为

- `BoardThumbnailCache` 现在已经具备“按缩略图版本分桶”的能力。
- 当前阶段还没有改 `BoardPersistedThumbnailStore.loadThumbnailIfFresh(...)`，所以磁盘上的旧 `thumbnail.png` 仍然可能被 `persisted-hit` 复用。
- 当前阶段也没有改 `BoardPreviewProvider` 的 fresh-render 回写逻辑，所以新的高分辨率 persisted 缩略图还不会因为这一步自动重生。
- 也就是说，这一步是后续阶段 2 / 阶段 3 的基础设施，不是最终修复闭环。

## 验证情况

- 已检查 `MyCanvas_Ver_0/Canvas/Storage/BoardPersistedThumbnailStore.swift` 的 lint / 语法诊断：无新增错误。
- 已检查 `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailCache.swift` 的 lint / 语法诊断：无新增错误。
- 已复核本次 diff：修改范围只收敛在上述两个文件，没有提前扩散到 persisted 读取判定或列表调度链路。
