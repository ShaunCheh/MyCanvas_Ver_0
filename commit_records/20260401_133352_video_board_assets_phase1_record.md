# 20260401_133352_video_board_assets_phase1_record

## 记录范围

- 记录内容：
  1. 新增视频来源模型 `CanvasVideoSource`，用于表达 `board assets` 中的原视频文件引用与封面时间点。
  2. 扩展 `CanvasImageItem`，让视频素材在继续复用现有几何链路的同时，具备独立的 `videoSource` 文档状态。
  3. 改造 `BoardDocument` / `BoardDocumentMapper`，让 `board.json` 能同时保存 `posterImageFilename`、`sourceVideoFilename`、`posterTimeSeconds`，并兼容旧的单 `assetFilename` 结构。
  4. 改造 `BoardStore`，让加载、保存、孤儿资产清理开始按“poster 文件 + source video 文件”的双资产集合工作。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasVideoSource.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
- 本记录不包含：
  - 阶段 2 的 iOS / macOS 视频导入入口与“复制原视频到 assets”实现
  - 阶段 4 的 BoardList / thumbnail / persisted thumbnail 改造
  - 阶段 5 的右键菜单 UI action 扩展
  - 阶段 7 / 8 的视频展示画面编辑页
  - git commit / push

## 修改一：补齐视频来源模型，给运行时 item 一个可持久化的 source video 语义

### 修改前

- 运行时只有 `CanvasImageAsset`，没有独立的视频来源模型。
- `CanvasImageItem` 只能表达“当前显示的 poster 图”，没有地方保存 `source video filename` 与 `poster time`。
- 这意味着即使后续导入了视频，也没有稳定的数据结构把“视频本体引用”和“当前展示帧”分开保存。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: CanvasImageItem.init(...)
// 功能说明: 修改前 item 只有图片资产，没有视频来源字段，因此无法在运行时和文档层挂载 source video 文件名与封面时间点。
struct CanvasImageItem {
    let id: CanvasImageItemID
    let asset: CanvasImageAsset
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var cropRectNormalized: CanvasImageCropRect
    var rotationRadians: CGFloat
}
```

### 修改后

- 新增 `CanvasVideoAssetReference`，专门表示持久化后的视频源文件名。
- 新增 `CanvasVideoSource`，把“原视频文件引用”和“当前封面对应时间点”收拢成一个独立模型。
- 后续阶段导入视频时，`CanvasImageItem` 就可以继续复用现有几何链路，但把视频本体引用交给 `videoSource` 承载。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasVideoSource.swift
// 函数名: CanvasVideoAssetReference.persisted(filename:) / CanvasVideoSource.init(assetReference:posterTimeSeconds:)
// 功能说明: 新增视频来源模型，负责保存 board assets 中的视频源文件名，以及当前封面帧对应的时间点。
struct CanvasVideoAssetReference: Equatable, Hashable {
    let filename: String

    static func persisted(
        filename: String
    ) -> CanvasVideoAssetReference {
        CanvasVideoAssetReference(filename: filename)
    }

    var stableAssetFilename: String {
        filename
    }
}

struct CanvasVideoSource: Equatable, Hashable {
    let assetReference: CanvasVideoAssetReference
    var posterTimeSeconds: Double

    var sourceVideoFilename: String {
        assetReference.stableAssetFilename
    }
}
```

## 修改二：`CanvasImageItem` 新增视频来源状态，并修正视频 item 的复制/历史语义

### 修改前

- `CanvasImageItem` 没有 `videoSource` 字段。
- `duplicated(offsetInWorld:)` 会直接共享同一个 `asset`。
- `matchesDocumentState(_:)` 只比较 `assetReference`，没有比较视频来源信息。
- 这对图片/GIF 没问题，但对视频不够，因为视频 item 后续要“共享 source video、独立 poster 文件”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: CanvasImageItem.duplicated(offsetInWorld:) / CanvasImageItem.matchesDocumentState(_:)
// 功能说明: 修改前复制逻辑始终共享同一个图片资产，历史比较也只看 assetReference，无法表达视频 item 的 source/poster 独立语义。
func duplicated(offsetInWorld: CGPoint) -> CanvasImageItem {
    CanvasImageItem(
        asset: asset,
        center: CGPoint(
            x: center.x + offsetInWorld.x,
            y: center.y + offsetInWorld.y
        ),
        size: size,
        zIndex: zIndex,
        cropRectNormalized: cropRectNormalized,
        rotationRadians: rotationRadians
    )
}

func matchesDocumentState(_ other: CanvasImageItem) -> Bool {
    id == other.id &&
        assetReference == other.assetReference &&
        center == other.center &&
        size == other.size &&
        zIndex == other.zIndex &&
        cropRectNormalized == other.cropRectNormalized &&
        rotationRadians == other.rotationRadians
}
```

### 修改后

- `CanvasImageItem` 新增 `videoSource`、`isVideo`、`sourceVideoFilename`。
- 视频 item 复制时不再继续共享同一个 poster 资产，而是生成新的 transient poster 资产，避免后面“改一个视频 item 的封面”时把另一个副本一起改掉。
- 历史比较加入 `videoSource`，让 `posterTimeSeconds` 与 `sourceVideoFilename` 成为文档状态的一部分。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: CanvasImageItem.init(...) / CanvasImageItem.duplicated(offsetInWorld:) / CanvasImageItem.matchesDocumentState(_:)
// 功能说明: 修改后视频 item 可以同时持有 poster 图和 source video 引用；复制时 source video 继续共享，但 poster 资产独立；历史比较也会跟踪 videoSource。
struct CanvasImageItem {
    let id: CanvasImageItemID
    let asset: CanvasImageAsset
    var videoSource: CanvasVideoSource?
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var cropRectNormalized: CanvasImageCropRect
    var rotationRadians: CGFloat

    var isVideo: Bool {
        videoSource != nil
    }

    var sourceVideoFilename: String? {
        videoSource?.sourceVideoFilename
    }
}

func duplicated(offsetInWorld: CGPoint) -> CanvasImageItem {
    let duplicatedAsset: CanvasImageAsset
    if isVideo {
        // 视频副本要有自己的 poster 资产，避免后续改封面互相串改。
        duplicatedAsset = CanvasImageAsset.transientImage(
            kind: asset.reference.kind,
            cgImage: asset.posterCGImage,
            logicalPixelSize: asset.logicalPixelSize
        )
    } else {
        duplicatedAsset = asset
    }

    CanvasImageItem(
        asset: duplicatedAsset,
        videoSource: videoSource,
        center: CGPoint(
            x: center.x + offsetInWorld.x,
            y: center.y + offsetInWorld.y
        ),
        size: size,
        zIndex: zIndex,
        cropRectNormalized: cropRectNormalized,
        rotationRadians: rotationRadians
    )
}

func matchesDocumentState(_ other: CanvasImageItem) -> Bool {
    id == other.id &&
        assetReference == other.assetReference &&
        videoSource == other.videoSource &&
        center == other.center &&
        size == other.size &&
        zIndex == other.zIndex &&
        cropRectNormalized == other.cropRectNormalized &&
        rotationRadians == other.rotationRadians
}
```

## 修改三：`BoardImageItemRecord` 从“单图片文件记录”升级为“poster + source video”双资产记录

### 修改前

- `BoardImageItemRecord` 只有一个 `assetFilename`。
- `encode(to:)` 与 `init(from:)` 都只围绕单个文件名工作。
- `BoardDocument` 也只能统计单个图片资产文件，因此 `removeOrphanedAssets` 没法同时保留 poster 文件和 source video 文件。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardImageItemRecord.init(from:) / BoardImageItemRecord.encode(to:) / BoardDocument.imageItemRecords
// 功能说明: 修改前 board.json 里的图片记录只有一个 assetFilename，无法区分当前显示封面图和原视频本体文件。
struct BoardImageItemRecord: Codable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var assetFilename: String
    var assetKind: CanvasImageAssetKind
    var cropRectNormalized: BoardImageCropRecord?
    var rotationRadians: Double?
}

init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    assetFilename = try container.decode(String.self, forKey: .assetFilename)
    assetKind = try container.decodeIfPresent(
        CanvasImageAssetKind.self,
        forKey: .assetKind
    ) ?? CanvasImageAssetKind.inferredPersistedKind(from: assetFilename)
}

func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(assetFilename, forKey: .assetFilename)
    try container.encode(assetKind, forKey: .assetKind)
}
```

### 修改后

- 文档层新增 `posterImageFilename`、`sourceVideoFilename`、`posterTimeSeconds`。
- 继续保留 `assetFilename` 兼容旧结构，但现在把它对齐到 `posterImageFilename`，让旧的图片读取路径仍能拿到当前显示图。
- 新增 `videoSource` 与 `referencedAssetFilenames`，分别给运行时映射和 orphan 清理使用。
- `BoardDocument` 新增 `referencedAssetFilenames`，开始按整组引用文件工作。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardDocument.referencedAssetFilenames / BoardImageItemRecord.init(from:) / BoardImageItemRecord.encode(to:) / BoardImageItemRecord.videoSource
// 功能说明: 修改后 board.json 可以同时保存 poster 文件、source video 文件与封面时间点，并继续兼容旧的单 assetFilename 记录。
struct BoardImageItemRecord: Codable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var posterImageFilename: String
    var assetKind: CanvasImageAssetKind
    var sourceVideoFilename: String?
    var posterTimeSeconds: Double?
    var cropRectNormalized: BoardImageCropRecord?
    var rotationRadians: Double?
}

init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let legacyAssetFilename = try container.decode(
        String.self,
        forKey: .assetFilename
    )
    posterImageFilename = Self.sanitizedAssetFilename(
        try container.decodeIfPresent(
            String.self,
            forKey: .posterImageFilename
        ) ?? legacyAssetFilename
    )
    sourceVideoFilename = Self.sanitizedOptionalAssetFilename(
        try container.decodeIfPresent(
            String.self,
            forKey: .sourceVideoFilename
        )
    )
    posterTimeSeconds = Self.sanitizedPosterTimeSeconds(
        try container.decodeIfPresent(
            Double.self,
            forKey: .posterTimeSeconds
        )
    )
}

func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    // legacy key 继续写 poster 文件名，保证旧读取路径不至于直接失效。
    try container.encode(posterImageFilename, forKey: .assetFilename)
    try container.encode(posterImageFilename, forKey: .posterImageFilename)
    try container.encodeIfPresent(
        sourceVideoFilename,
        forKey: .sourceVideoFilename
    )
    try container.encodeIfPresent(
        posterTimeSeconds,
        forKey: .posterTimeSeconds
    )
}

var videoSource: CanvasVideoSource? {
    guard let sourceVideoFilename else {
        return nil
    }

    return CanvasVideoSource(
        assetReference: .persisted(filename: sourceVideoFilename),
        posterTimeSeconds: posterTimeSeconds ?? 0
    )
}

var referencedAssetFilenames: Set<String> {
    var filenames: Set<String> = [posterImageFilename]
    if let sourceVideoFilename {
        filenames.insert(sourceVideoFilename)
    }
    return filenames
}

struct BoardDocument {
    var items: [BoardItemRecord]

    var referencedAssetFilenames: Set<String> {
        imageItemRecords.reduce(into: Set<String>()) { partialResult, record in
            partialResult.formUnion(record.referencedAssetFilenames)
        }
    }
}
```

## 修改四：`BoardDocumentMapper` 开始在运行时与文档层之间往返映射 `videoSource`

### 修改前

- 运行时恢复 `CanvasImageItem` 时，只会恢复 `CanvasImageAsset`。
- 保存文档时，也只会把 `assetFilename` 和 `assetKind` 回写到 `BoardImageItemRecord`。
- 即使文档未来带上了视频字段，运行时也不会接住。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: BoardDocumentMapper.makeRuntimeState(from:imageLoader:) / BoardDocumentMapper.makeImageRecord(from:)
// 功能说明: 修改前 Mapper 只在运行时和文档之间传递 poster 图片资产，不传递任何视频来源信息。
CanvasImageItem(
    id: imageRecord.id,
    asset: CanvasImageAsset.persistedImage(
        kind: imageRecord.assetReference.kind,
        filename: imageRecord.assetReference.stableAssetFilename,
        cgImage: try imageLoader(imageRecord)
    ),
    center: imageRecord.center.cgPoint,
    size: imageRecord.size.cgSize,
    zIndex: CGFloat(imageRecord.zIndex),
    cropRectNormalized: imageRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
    rotationRadians: CGFloat(imageRecord.rotationRadians ?? 0)
)

BoardImageItemRecord(
    id: item.id,
    center: BoardPointRecord(item.center),
    size: BoardSizeRecord(item.size),
    zIndex: Double(item.zIndex),
    assetFilename: item.assetReference.stableAssetFilename,
    assetKind: item.assetKind,
    cropRectNormalized: BoardImageCropRecord(item.cropRectNormalized),
    rotationRadians: Double(item.rotationRadians)
)
```

### 修改后

- 运行时恢复 `CanvasImageItem` 时，会把 `imageRecord.videoSource` 一起恢复进去。
- 保存文档时，会把 `sourceVideoFilename` 与 `posterTimeSeconds` 一起写回记录。
- 这让“存储闭环”具备了最小视频状态往返能力。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: BoardDocumentMapper.makeRuntimeState(from:imageLoader:) / BoardDocumentMapper.makeImageRecord(from:)
// 功能说明: 修改后 Mapper 会把文档层的 source video 信息恢复到运行时 item，并在保存时把运行时的 videoSource 再写回文档。
CanvasImageItem(
    id: imageRecord.id,
    asset: CanvasImageAsset.persistedImage(
        kind: imageRecord.assetReference.kind,
        filename: imageRecord.assetReference.stableAssetFilename,
        cgImage: try imageLoader(imageRecord)
    ),
    videoSource: imageRecord.videoSource,
    center: imageRecord.center.cgPoint,
    size: imageRecord.size.cgSize,
    zIndex: CGFloat(imageRecord.zIndex),
    cropRectNormalized: imageRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
    rotationRadians: CGFloat(imageRecord.rotationRadians ?? 0)
)

BoardImageItemRecord(
    id: item.id,
    center: BoardPointRecord(item.center),
    size: BoardSizeRecord(item.size),
    zIndex: Double(item.zIndex),
    assetFilename: item.assetReference.stableAssetFilename,
    assetKind: item.assetKind,
    posterImageFilename: item.assetReference.stableAssetFilename,
    sourceVideoFilename: item.videoSource?.sourceVideoFilename,
    posterTimeSeconds: item.videoSource?.posterTimeSeconds,
    cropRectNormalized: BoardImageCropRecord(item.cropRectNormalized),
    rotationRadians: Double(item.rotationRadians)
)
```

## 修改五：`BoardStore` 开始按“poster 文件 + source video 文件”处理加载、保存和 orphan 清理

### 修改前

- `loadBoard` 只会读取 `assetFilename` 对应的图片文件，不会校验视频源文件。
- `saveBoard` 只会对单个 `assetFilename` 去重并持久化。
- `removeOrphanedAssets` 的 keep 集只有 `document.imageItemRecords.map(\.assetFilename)`，无法同时保住 poster 文件与 source video 文件。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardStore.loadBoard(id:userDefaults:) / BoardStore.saveBoard(_:userDefaults:) / BoardStore.removeOrphanedAssets(keeping:in:)
// 功能说明: 修改前 BoardStore 仍然把每个图片 item 看成一个单文件资产，既不会校验 source video，也不会把双资产一起加入 orphan keep 集。
let runtimeState = try BoardDocumentMapper.makeRuntimeState(from: document) { imageRecord in
    let assetURL = assetsDirectoryURL.appendingPathComponent(imageRecord.assetFilename)
    let assetData = try CoordinatedFileIO.readData(at: assetURL)
    guard
        let imageSource = CGImageSourceCreateWithData(assetData as CFData, nil),
        let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
        throw BoardStoreError.invalidBoardImageAsset(filename: imageRecord.assetFilename)
    }
    return cgImage
}

var writtenAssetFilenames: Set<String> = []
for item in persistedState.imageItems {
    let assetFilename = item.assetReference.stableAssetFilename
    guard writtenAssetFilenames.insert(assetFilename).inserted else {
        continue
    }

    let assetURL = assetsDirectoryURL.appendingPathComponent(assetFilename)
    try persistImageAssetIfNeeded(
        for: item,
        snapshot: persistedSnapshot,
        to: assetURL
    )
}

try removeOrphanedAssets(
    keeping: Set(document.imageItemRecords.map(\.assetFilename)),
    in: assetsDirectoryURL
)
```

### 修改后

- `loadBoard` 在恢复运行时数据前，会先校验所有 `sourceVideoFilename` 是否存在。
- `saveBoard` 继续写 poster 文件，但对视频 item 会额外校验 `sourceVideoFilename` 指向的本地副本是否存在。
- `removeOrphanedAssets` 开始使用 `document.referencedAssetFilenames`，按整组资产文件保留。
- 当前阶段还没有把视频复制到 `assets`，所以这里做的是“约束收紧”：如果文档引用了视频源文件但本地没有，该 board 会在加载/保存时显式报错。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardStore.loadBoard(id:userDefaults:) / BoardStore.saveBoard(_:userDefaults:) / BoardStore.validateReferencedVideoAssets(for:in:) / BoardStore.validateVideoAssetExists(at:filename:) / BoardStore.removeOrphanedAssets(keeping:in:)
// 功能说明: 修改后 BoardStore 会在 load/save 阶段感知 source video 文件，并把 orphan keep 集从单 assetFilename 升级为整组引用资产文件。
try validateReferencedVideoAssets(
    for: document.imageItemRecords,
    in: assetsDirectoryURL
)

let runtimeState = try BoardDocumentMapper.makeRuntimeState(from: document) { imageRecord in
    let assetURL = assetsDirectoryURL.appendingPathComponent(imageRecord.assetFilename)
    let assetData = try CoordinatedFileIO.readData(at: assetURL)
    guard
        let imageSource = CGImageSourceCreateWithData(assetData as CFData, nil),
        let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
        throw BoardStoreError.invalidBoardImageAsset(filename: imageRecord.assetFilename)
    }
    return cgImage
}

var writtenPosterAssetFilenames: Set<String> = []
var validatedVideoAssetFilenames: Set<String> = []
for item in persistedState.imageItems {
    let posterAssetFilename = item.assetReference.stableAssetFilename
    if writtenPosterAssetFilenames.insert(posterAssetFilename).inserted {
        let assetURL = assetsDirectoryURL.appendingPathComponent(
            posterAssetFilename
        )
        try persistImageAssetIfNeeded(
            for: item,
            snapshot: persistedSnapshot,
            to: assetURL
        )
    }

    if let sourceVideoFilename = item.sourceVideoFilename,
       validatedVideoAssetFilenames.insert(sourceVideoFilename).inserted
    {
        let videoAssetURL = assetsDirectoryURL.appendingPathComponent(
            sourceVideoFilename
        )
        try validateVideoAssetExists(
            at: videoAssetURL,
            filename: sourceVideoFilename
        )
    }
}

try removeOrphanedAssets(
    keeping: document.referencedAssetFilenames,
    in: assetsDirectoryURL
)
```

## 本次结果

- 运行时 item 已经能表达“poster 图 + source video 文件 + poster time”三部分状态。
- `board.json` 已经具备双资产记录能力，并兼容旧的单 `assetFilename` 数据。
- `BoardStore` 已经从“单文件图片假设”向“双资产集合假设”迈出第一步，保存和 orphan 清理都改成按整组引用资产工作。
- 视频 item 的复制语义已提前修正：共享 source video，但 poster 文件语义独立。

## 当前限制

- 现在还没有实现“导入时复制原视频到 `board assets`”，所以 `sourceVideoFilename` 目前只是存储契约已就位。
- 现在还没有实现视频 poster 的生成、替换、缩略图回放与编辑页。
- 当前验证只完成了改动文件的 IDE lint 检查；由于本机没有完整 Xcode，未完成项目级 `xcodebuild` 编译验证。

## 验证情况

- 已通过 `ReadLints` 检查本次改动文件，未发现新的诊断问题。
- 尝试运行 `xcodebuild` 时失败，原因是当前机器的 active developer directory 指向 `CommandLineTools`，不是完整 Xcode。
