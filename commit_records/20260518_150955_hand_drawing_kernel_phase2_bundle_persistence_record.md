# 20260518_150955_hand_drawing_kernel_phase2_bundle_persistence_record

## 记录范围

- 记录内容：
  1. 新增 handDrawing 独立文档包持久化层，包括 `HandDrawingBundleLocator`、`HandDrawingManifest`、`HandDrawingDocumentCodec`、`HandDrawingDocumentStore`。
  2. 升级 `BoardDocument` 的 handDrawing storage 语义，使 board 记录能够表达 `.bundle` 与 `.legacyFlatAssetPair` 两种存储形态。
  3. 改造 `BoardDocumentMapper` 与 `BoardStore`，让 handDrawing 的加载、保存、校验、清理从“扁平双文件”升级到“bundle + legacy fallback”双通道。
  4. 补阶段 2 定点测试，验证 bundle round-trip、orphan cleanup、duplicate 独立 bundle、legacy fallback 与旧调用点兼容。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S"` -> `20260518_150955`
- 说明：
  - 本记录中的“修改前”以阶段 1 完成态为基线，不直接使用 `HEAD` 初始状态。
  - 原因是这些文件在阶段 1 已经改过；若直接对照 `HEAD`，会把阶段 1 与阶段 2 混在一起，不够如实。
- 参考依据：
  - `git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingManifest.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift`
  - `git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingManifest.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift`
  - `git diff -- MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingManifest.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift`
  - 阶段 1 记录：
    - `commit_records/20260518_144714_hand_drawing_kernel_phase1_boundary_schema_record.md`
- 当前工作区涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingManifest.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
  - `MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
  - `MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `M MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
  - `M MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
  - `M MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingManifest.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift`
- `git diff --stat` 摘要：
  - 已跟踪文件修改：6 个
  - 统计结果：`440 insertions(+), 54 deletions(-)`
  - 主要改动集中在 `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift` 与 `MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
  - 新增未跟踪文件：5 个
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests" -only-testing:"MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests" -only-testing:"MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests" -only-testing:"MyCanvas_Ver_0Tests/BoardVideoStorageTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests"`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 3 的旧 `.pkdrawing` 懒迁移与回滚
  - 阶段 4 之后的自研文档模型、编辑内核、iPad 编辑器、像素橡皮与套索
  - git commit / push

## 修改一：新增独立 handDrawing bundle 持久化层

### 修改前

- 阶段 1 只完成了 `documentID` 边界拆分，还没有真正的 bundle 目录、manifest、codec、store。
- handDrawing 仍然依赖 `BoardStore` 直接面向 `assets/` 目录读写 preview/source。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/*
// 函数名: 无
// 功能说明: 阶段1完成态下还没有独立 handDrawing bundle 持久化目录，也没有 locator / manifest / codec / store。
// 修改前不存在以下实现：
// - HandDrawingBundleLocator
// - HandDrawingManifest
// - HandDrawingDocumentCodec
// - HandDrawingDocumentStore
```

### 修改后

- 新增 `HandDrawingBundleLocator`，明确 bundle 目录结构：
  - `handdrawings/<documentID>.handdraw/manifest.json`
  - `handdrawings/<documentID>.handdraw/document.hdraw`
  - `handdrawings/<documentID>.handdraw/preview.png`
- 新增 `HandDrawingManifest`，把 paper / `contentRevision` / `isEmpty` / `migrationOrigin` 放进 bundle manifest。
- 新增 `HandDrawingDocumentCodec`，统一 manifest 编解码与 preview PNG 编解码。
- 新增 `HandDrawingDocumentStore`，负责 bundle 的 save/load/validate/orphan cleanup。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift
// 函数名: bundleDirectoryName / previewImageRelativePath / sourceDrawingRelativePath / manifestRelativePath / bundleDirectoryURL(in:) / manifestURL(in:) / documentURL(in:) / previewImageURL(in:)
// 功能说明: 修改后 handDrawing 有了独立 bundle 定位器，board 可以稳定地按 documentID 推导 bundle 目录和内部组件路径。
struct HandDrawingBundleLocator {
    static let handDrawingsDirectoryName = "handdrawings"
    static let bundleFileExtension = "handdraw"
    static let manifestFilename = "manifest.json"
    static let documentFilename = "document.hdraw"
    static let previewFilename = "preview.png"

    let documentID: HandDrawingDocumentID

    var bundleDirectoryName: String {
        "\(documentID.uuidString).\(Self.bundleFileExtension)"
    }

    var previewImageRelativePath: String {
        [
            Self.handDrawingsDirectoryName,
            bundleDirectoryName,
            Self.previewFilename
        ].joined(separator: "/")
    }

    var sourceDrawingRelativePath: String {
        [
            Self.handDrawingsDirectoryName,
            bundleDirectoryName,
            Self.documentFilename
        ].joined(separator: "/")
    }

    func bundleDirectoryURL(in boardDirectoryURL: URL) -> URL {
        handDrawingsDirectoryURL(in: boardDirectoryURL).appendingPathComponent(
            bundleDirectoryName,
            isDirectory: true
        )
    }

    func manifestURL(in boardDirectoryURL: URL) -> URL {
        bundleDirectoryURL(in: boardDirectoryURL).appendingPathComponent(
            Self.manifestFilename
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingManifest.swift
// 函数名: HandDrawingManifestPaperRecord.init(_:) / canvasPaperSpec / HandDrawingManifest.init(...)
// 功能说明: 修改后 manifest 会把 paper、contentRevision、isEmpty 和 migrationOrigin 作为 bundle 元数据持久化。
enum HandDrawingManifestMigrationOrigin: String, Codable, Equatable {
    case legacyFlatAssetPair
}

struct HandDrawingManifestPaperRecord: Codable, Equatable {
    var id: String
    var width: Double
    var height: Double

    init(_ paper: CanvasHandDrawingPaperSpec) {
        id = paper.id
        width = Double(paper.size.width)
        height = Double(paper.size.height)
    }

    var canvasPaperSpec: CanvasHandDrawingPaperSpec {
        CanvasHandDrawingPaperSpec(
            id: id,
            size: CGSize(width: CGFloat(width), height: CGFloat(height))
        )
    }
}

struct HandDrawingManifest: Codable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let documentID: HandDrawingDocumentID
    var paper: HandDrawingManifestPaperRecord
    var contentRevision: UUID
    var isEmpty: Bool
    var migrationOrigin: HandDrawingManifestMigrationOrigin?
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift / MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift
// 函数名: makeManifestData(for:) / decodeManifest(from:) / makePNGData(for:documentID:) / decodePreviewImage(from:documentID:) / persistDocument(...) / loadManifest(...) / loadDocumentData(...) / loadPreviewImage(...) / validateBundleExists(...) / removeOrphanedBundles(...)
// 功能说明: 修改后 handDrawing bundle 的 manifest、document 和 preview 都通过统一 codec/store 读写，不再散落在 BoardStore 里直接拼路径写文件。
enum HandDrawingDocumentCodec {
    static func makeManifestData(for manifest: HandDrawingManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    static func makePNGData(
        for previewImage: CGImage,
        documentID: HandDrawingDocumentID
    ) throws -> Data {
        // PNG 编码逻辑省略
    }
}

enum HandDrawingDocumentStore {
    static func persistDocument(
        documentID: HandDrawingDocumentID,
        paper: CanvasHandDrawingPaperSpec,
        contentRevision: UUID,
        isEmpty: Bool,
        drawingData: Data,
        previewImageData: Data?,
        previewCGImage: CGImage?,
        boardDirectoryURL: URL,
        migrationOrigin: HandDrawingManifestMigrationOrigin? = nil
    ) throws {
        let locator = HandDrawingBundleLocator(documentID: documentID)
        let manifest = HandDrawingManifest(
            documentID: documentID,
            paper: paper,
            contentRevision: contentRevision,
            isEmpty: isEmpty,
            migrationOrigin: migrationOrigin
        )
        // manifest / document / preview 三件套写入逻辑省略
        try CoordinatedFileIO.writeData(
            try HandDrawingDocumentCodec.makeManifestData(for: manifest),
            to: locator.manifestURL(in: boardDirectoryURL)
        )
        try CoordinatedFileIO.writeData(
            drawingData,
            to: locator.documentURL(in: boardDirectoryURL)
        )
    }

    static func removeOrphanedBundles(
        keeping documentIDs: Set<HandDrawingDocumentID>,
        boardDirectoryURL: URL
    ) throws {
        let bundleDirectoryNames = Set(
            documentIDs.map { HandDrawingBundleLocator(documentID: $0).bundleDirectoryName }
        )
        let bundleURLs = try CoordinatedFileIO.contentsOfDirectory(
            at: HandDrawingBundleLocator.handDrawingsDirectoryURL(in: boardDirectoryURL)
        )
        for bundleURL in bundleURLs where bundleDirectoryNames.contains(bundleURL.lastPathComponent) == false {
            try CoordinatedFileIO.removeItemIfExists(at: bundleURL)
        }
    }
}
```

## 修改二：`BoardDocument` 从“只会 legacy”升级到“bundle / legacy 双语义”

### 修改前

- 阶段 1 的 `BoardDocument.currentFormatVersion` 是 `7`。
- `BoardHandDrawingStorageRecord` 只有 `.legacyFlatAssetPair`。
- `previewImageFilename` / `sourceDrawingFilename` / `referencedAssetFilenames` 都直接走旧的 flat asset locator。
- board 层没有“引用了哪些 handDrawing bundle”的集合，因此不能做 bundle 级 orphan cleanup。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardDocument.currentFormatVersion / BoardHandDrawingStorageRecord / previewImageFilename / sourceDrawingFilename / referencedAssetFilenames / assetLocator
// 功能说明: 阶段1完成态下，board schema 只能表达 legacy handDrawing 资产语义，无法表达 bundle 模式。
struct BoardDocument: Codable {
    // Board schema now evolves independently from image asset internals.
    static let currentFormatVersion = 7
}

enum BoardHandDrawingStorageRecord: String, Codable, Equatable {
    case legacyFlatAssetPair
}

struct BoardHandDrawingItemRecord: Codable, Equatable {
    // 其余字段省略

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
        BoardHandDrawingAssetLocator(documentID: documentID)
    }
}
```

### 修改后

- schema version 升到 `8`。
- `BoardHandDrawingStorageRecord` 新增 `.bundle`。
- `BoardHandDrawingItemRecord`：
  - 按 `storage` 分流 preview/source 路径语义
  - `legacyFlatAssetPair` 继续走 `BoardHandDrawingAssetLocator`
  - `bundle` 走 `HandDrawingBundleLocator`
- `BoardDocument` / `BoardItemRecord` 新增 `referencedHandDrawingDocumentIDs`，给 bundle 级 cleanup 提供依据。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardDocument.currentFormatVersion / referencedHandDrawingDocumentIDs / BoardHandDrawingStorageRecord / previewImageFilename / sourceDrawingFilename / referencedAssetFilenames / referencedHandDrawingDocumentIDs / legacyAssetLocator / bundleLocator
// 功能说明: 修改后 board schema 能显式区分 bundle 与 legacy 两种 handDrawing 存储形态，并能收集 bundle 级引用集。
struct BoardDocument: Codable {
    // Board schema now evolves independently from image asset internals.
    static let currentFormatVersion = 8

    var referencedHandDrawingDocumentIDs: Set<HandDrawingDocumentID> {
        items.reduce(into: Set<HandDrawingDocumentID>()) { partialResult, record in
            partialResult.formUnion(record.referencedHandDrawingDocumentIDs)
        }
    }
}

enum BoardHandDrawingStorageRecord: String, Codable, Equatable {
    case legacyFlatAssetPair
    case bundle
}

struct BoardHandDrawingItemRecord: Codable, Equatable {
    // 其余字段省略

    var previewImageFilename: String {
        switch storage {
        case .legacyFlatAssetPair:
            return legacyAssetLocator.previewImageFilename
        case .bundle:
            return bundleLocator.previewImageRelativePath
        }
    }

    var sourceDrawingFilename: String {
        switch storage {
        case .legacyFlatAssetPair:
            return legacyAssetLocator.sourceDrawingFilename
        case .bundle:
            return bundleLocator.sourceDrawingRelativePath
        }
    }

    var referencedAssetFilenames: Set<String> {
        switch storage {
        case .legacyFlatAssetPair:
            return legacyAssetLocator.referencedAssetFilenames
        case .bundle:
            return []
        }
    }

    var referencedHandDrawingDocumentIDs: Set<HandDrawingDocumentID> {
        switch storage {
        case .legacyFlatAssetPair:
            return []
        case .bundle:
            return [documentID]
        }
    }

    var legacyAssetLocator: BoardHandDrawingAssetLocator {
        BoardHandDrawingAssetLocator(documentID: documentID)
    }

    var bundleLocator: HandDrawingBundleLocator {
        HandDrawingBundleLocator(documentID: documentID)
    }
}
```

## 修改三：`BoardDocumentMapper` 与 `BoardStore` 接上 bundle / legacy 双通道

### 修改前

- `BoardDocumentMapper.makeRuntimeState(...)` 只有 `imageLoader`，handDrawing preview 仍假装自己是普通 image asset。
- `makeHandDrawingRecord(...)` 仍然把新 handDrawing 写成 `.legacyFlatAssetPair`。
- `BoardStore`：
  - load 阶段只检查 `assets/`
  - `loadHandDrawingSourceData(...)` 只从 `assets/` 里读
  - `persistHandDrawingAssetsIfNeeded(...)` 只会写扁平 preview/source 双文件
  - orphan cleanup 只会清 `assets/`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:) / makeHandDrawingRecord(from:)
// 功能说明: 阶段1完成态下，mapper 还没有 handDrawing preview 专用 loader，新记录也还默认落成 legacy 存储。
static func makeRuntimeState(
    from document: BoardDocument,
    imageLoader: (BoardImageItemRecord) throws -> CGImage
) throws -> BoardRuntimeState {
    // 其余分支省略
    case let .handDrawing(handDrawingRecord):
        return CanvasBoardItem.handDrawing(
            makeHandDrawingItem(
                from: handDrawingRecord,
                previewImage: try imageLoader(handDrawingRecord.previewImageRecord)
            )
        )
}

private static func makeHandDrawingRecord(
    from item: CanvasHandDrawingItem
) -> BoardHandDrawingItemRecord {
    BoardHandDrawingItemRecord(
        id: item.id,
        documentID: item.documentID,
        // 其余字段省略
        storage: .legacyFlatAssetPair
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: validateReferencedHandDrawingAssets(for:in:) / loadHandDrawingSourceData(boardID:documentID:userDefaults:) / persistHandDrawingAssetsIfNeeded(for:snapshot:in:) / removeOrphanedAssets(keeping:in:)
// 功能说明: 阶段1完成态下，BoardStore 的 handDrawing 主链仍然只认识 assets 目录里的扁平双文件。
try validateReferencedHandDrawingAssets(
    for: document.handDrawingItemRecords,
    in: assetsDirectoryURL
)

static func loadHandDrawingSourceData(
    boardID: UUID,
    documentID: HandDrawingDocumentID,
    userDefaults: UserDefaults = .standard
) throws -> Data {
    let sourceURL = BoardHandDrawingAssetLocator(documentID: documentID)
        .sourceDrawingURL(in: assetsDirectoryURL)
    return try CoordinatedFileIO.readData(at: sourceURL)
}

private static func persistHandDrawingAssetsIfNeeded(
    for item: CanvasHandDrawingItem,
    snapshot: BoardSaveSnapshot,
    in assetsDirectoryURL: URL
) throws {
    let assetLocator = BoardHandDrawingAssetLocator(documentID: item.documentID)
    let previewImageURL = assetLocator.previewImageURL(in: assetsDirectoryURL)
    let sourceDrawingURL = assetLocator.sourceDrawingURL(in: assetsDirectoryURL)
    // preview/source 双文件写入逻辑省略
}

private static func removeOrphanedAssets(
    keeping assetFilenames: Set<String>,
    in assetsDirectoryURL: URL
) throws {
    let assetURLs = try CoordinatedFileIO.contentsOfDirectory(at: assetsDirectoryURL)
    for assetURL in assetURLs where assetFilenames.contains(assetURL.lastPathComponent) == false {
        try CoordinatedFileIO.removeItemIfExists(at: assetURL)
    }
}
```

### 修改后

- `BoardDocumentMapper.makeRuntimeState(...)` 新增 `handDrawingPreviewLoader`，让 handDrawing preview 可以从 bundle 单独加载。
- `makeHandDrawingRecord(...)` 对新 handDrawing 直接写 `.bundle`。
- `BoardStore` 现在会：
  - 读取时根据 `storage` 校验 legacy flat file 或 bundle
  - source data 读取时优先 bundle，再 fallback 到 legacy
  - 保存时根据 record.storage 分流到 legacy 写法或 bundle 写法
  - 内容保存前执行 `normalizePersistedHandDrawingStorage(...)`，保证旧 legacy 文档在普通重存时仍保持 legacy，不被阶段 2 擅自转换
  - orphan cleanup 同时处理 `assets/` 与 `handdrawings/`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:handDrawingPreviewLoader:) / makeHandDrawingRecord(from:)
// 功能说明: 修改后 mapper 能区分普通 image 载入和 handDrawing bundle preview 载入，新 handDrawing 记录默认落成 bundle。
static func makeRuntimeState(
    from document: BoardDocument,
    imageLoader: (BoardImageItemRecord) throws -> CGImage,
    handDrawingPreviewLoader: ((BoardHandDrawingItemRecord) throws -> CGImage)? = nil
) throws -> BoardRuntimeState {
    // 其余分支省略
    case let .handDrawing(handDrawingRecord):
        return CanvasBoardItem.handDrawing(
            makeHandDrawingItem(
                from: handDrawingRecord,
                previewImage: try (
                    handDrawingPreviewLoader?(handDrawingRecord)
                    ?? imageLoader(handDrawingRecord.previewImageRecord)
                )
            )
        )
}

private static func makeHandDrawingRecord(
    from item: CanvasHandDrawingItem
) -> BoardHandDrawingItemRecord {
    BoardHandDrawingItemRecord(
        id: item.id,
        documentID: item.documentID,
        // 其余字段省略
        storage: .bundle
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: loadBoard(id:userDefaults:) / loadHandDrawingSourceData(boardID:documentID:userDefaults:) / validateReferencedHandDrawingAssets(for:boardDirectoryURL:assetsDirectoryURL:) / persistHandDrawingAssetsIfNeeded(for:record:snapshot:boardDirectoryURL:in:) / persistBundleHandDrawingDocumentIfNeeded(for:snapshot:boardDirectoryURL:) / normalizePersistedHandDrawingStorage(in:existingDocument:)
// 功能说明: 修改后 BoardStore 把 handDrawing 存储主链升级为“bundle + legacy fallback”双通道。
try validateReferencedHandDrawingAssets(
    for: document.handDrawingItemRecords,
    boardDirectoryURL: boardDirectoryURL,
    assetsDirectoryURL: assetsDirectoryURL
)
let runtimeState = try BoardDocumentMapper.makeRuntimeState(
    from: document,
    imageLoader: { imageRecord in
        let assetURL = assetsDirectoryURL.appendingPathComponent(
            imageRecord.assetFilename
        )
        return try loadBoardImageAsset(
            at: assetURL,
            filename: imageRecord.assetFilename
        )
    },
    handDrawingPreviewLoader: { handDrawingRecord in
        try loadHandDrawingPreviewImage(
            for: handDrawingRecord,
            boardDirectoryURL: boardDirectoryURL,
            assetsDirectoryURL: assetsDirectoryURL
        )
    }
)

static func loadHandDrawingSourceData(
    boardID: UUID,
    documentID: HandDrawingDocumentID,
    userDefaults: UserDefaults = .standard
) throws -> Data {
    if HandDrawingDocumentStore.bundleExists(
        documentID: documentID,
        boardDirectoryURL: boardDirectoryURL
    ) {
        return try HandDrawingDocumentStore.loadDocumentData(
            documentID: documentID,
            boardDirectoryURL: boardDirectoryURL
        )
    }

    let sourceURL = BoardHandDrawingAssetLocator(documentID: documentID)
        .sourceDrawingURL(in: assetsDirectoryURL)
    return try CoordinatedFileIO.readData(at: sourceURL)
}

if snapshot.updateKind.affectsContent {
    normalizePersistedHandDrawingStorage(
        in: &document,
        existingDocument: existingDocument
    )
}

private static func validateReferencedHandDrawingAssets(
    for handDrawingRecords: [BoardHandDrawingItemRecord],
    boardDirectoryURL: URL,
    assetsDirectoryURL: URL
) throws {
    for handDrawingRecord in handDrawingRecords {
        switch handDrawingRecord.storage {
        case .legacyFlatAssetPair:
            try validateHandDrawingSourceAssetExists(
                at: handDrawingRecord.legacyAssetLocator.sourceDrawingURL(
                    in: assetsDirectoryURL
                ),
                filename: handDrawingRecord.sourceDrawingFilename
            )
        case .bundle:
            try HandDrawingDocumentStore.validateBundleExists(
                documentID: handDrawingRecord.documentID,
                boardDirectoryURL: boardDirectoryURL
            )
        }
    }
}

private static func persistHandDrawingAssetsIfNeeded(
    for item: CanvasHandDrawingItem,
    record: BoardHandDrawingItemRecord,
    snapshot: BoardSaveSnapshot,
    boardDirectoryURL: URL,
    in assetsDirectoryURL: URL
) throws {
    switch record.storage {
    case .legacyFlatAssetPair:
        try persistLegacyHandDrawingAssetsIfNeeded(
            for: item,
            snapshot: snapshot,
            in: assetsDirectoryURL
        )
    case .bundle:
        try persistBundleHandDrawingDocumentIfNeeded(
            for: item,
            snapshot: snapshot,
            boardDirectoryURL: boardDirectoryURL
        )
    }
}

private static func normalizePersistedHandDrawingStorage(
    in document: inout BoardDocument,
    existingDocument: BoardDocument?
) {
    let existingStorageByItemID = Dictionary(
        uniqueKeysWithValues: existingDocument?.handDrawingItemRecords.map {
            ($0.id, $0.storage)
        } ?? []
    )
    document.items = document.items.map { itemRecord in
        guard case let .handDrawing(record) = itemRecord else {
            return itemRecord
        }

        let resolvedStorage = existingStorageByItemID[record.id] ?? .bundle
        return .handDrawing(
            BoardHandDrawingItemRecord(
                id: record.id,
                documentID: record.documentID,
                center: record.center,
                size: record.size,
                zIndex: record.zIndex,
                paper: record.paper,
                isEmpty: record.isEmpty,
                contentRevision: record.contentRevision,
                rotationRadians: record.rotationRadians,
                storage: resolvedStorage
            )
        )
    }
}
```

## 修改四：测试从“扁平文件断言”升级到“bundle / legacy 双验证”

### 修改前

- `BoardHandDrawingStorageTests` 仍然直接验证 `assets/` 目录里的 preview/source 双文件。
- 没有 bundle store 的单测。
- `BoardSelectionStateMigrationTests` 对“新建 handDrawing 记录”的预期还是 `.legacyFlatAssetPair`。
- `BoardVideoStorageTests` 还用旧版 `makeRuntimeState(from:) { ... }` 调用形式。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() / testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths()
// 功能说明: 阶段1完成态下，storage 测试仍然以 assets 目录的扁平 preview/source 双文件为断言目标。
let assetLocator = BoardHandDrawingAssetLocator(documentID: documentID)
let previewURL = assetLocator.previewImageURL(in: assetsDirectoryURL)
let sourceURL = assetLocator.sourceDrawingURL(in: assetsDirectoryURL)
XCTAssertEqual(
    try CoordinatedFileIO.readData(at: sourceURL),
    drawingData
)

func testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() throws {
    // 其余准备代码省略
    let sourceReloadedData = try BoardStore.loadHandDrawingSourceData(
        boardID: boardID,
        documentID: sourceItem.documentID,
        userDefaults: userDefaults
    )
    let duplicatedReloadedData = try BoardStore.loadHandDrawingSourceData(
        boardID: boardID,
        documentID: duplicatedHandDrawingItem.documentID,
        userDefaults: userDefaults
    )
    XCTAssertEqual(sourceReloadedData, sourceDrawingData)
    XCTAssertEqual(duplicatedReloadedData, sourceDrawingData)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift / MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 函数名: testBoardDocumentMapperRoundTripsHandDrawingItem() / testBoardDocumentMapperRoundTripsVideoPosterMetadata()
// 功能说明: 阶段1完成态下，新 handDrawing 记录仍然按 legacy 预期断言；video 测试还使用旧版 mapper 调用签名。
XCTAssertEqual(handDrawingRecord.storage, .legacyFlatAssetPair)
XCTAssertEqual(
    handDrawingRecord.previewImageFilename,
    CanvasHandDrawingItem.defaultPreviewImageFilename(for: documentID)
)

let roundTrippedState = try BoardDocumentMapper.makeRuntimeState(
    from: document
) { _ in
    posterImage
}
```

### 修改后

- `BoardHandDrawingStorageTests`：
  - 新建 handDrawing 改为验证 bundle 三件套存在，且 legacy flat asset 不再被写出
  - duplicate 用例验证两个 item 各自拥有独立 bundle
  - 新增 legacy fallback 用例，验证旧文档仍能继续从 flat file 读取，且普通重存不会被阶段 2 擅自转换
- 新增 `HandDrawingDocumentStoreTests`，专门验证 bundle store 的 round-trip 与 orphan cleanup
- `BoardSelectionStateMigrationTests`：
  - 新建记录的 storage 预期改为 `.bundle`
  - preview filename 预期改成 bundle relative path
  - 旧 payload decode fallback 仍然保留 `.legacyFlatAssetPair` 断言
- `BoardVideoStorageTests` 仅为兼容 `makeRuntimeState` 新签名而做显式 `imageLoader:` 调整

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() / testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() / testBoardStoreLoadHandDrawingSourceDataFallsBackToLegacyFlatAssets()
// 功能说明: 修改后 storage 测试同时覆盖 bundle 持久化、duplicate 独立 bundle，以及 legacy flat asset fallback。
let entry = try XCTUnwrap(
    BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).first
)
let bundleLocator = HandDrawingBundleLocator(documentID: documentID)
let previewURL = bundleLocator.previewImageURL(
    in: entry.boardDirectoryURL
)
let sourceURL = bundleLocator.documentURL(
    in: entry.boardDirectoryURL
)
let legacyAssetLocator = BoardHandDrawingAssetLocator(
    documentID: documentID
)
XCTAssertEqual(
    try CoordinatedFileIO.readData(at: sourceURL),
    drawingData
)
XCTAssertNil(
    try CoordinatedFileIO.modificationDate(
        at: legacyAssetLocator.sourceDrawingURL(in: assetsDirectoryURL)
    )
)
XCTAssertEqual(
    entry.document.handDrawingItemRecords.first?.storage,
    .bundle
)

let sourceBundleLocator = HandDrawingBundleLocator(
    documentID: sourceItem.documentID
)
let duplicatedBundleLocator = HandDrawingBundleLocator(
    documentID: duplicatedHandDrawingItem.documentID
)
XCTAssertNotNil(
    try CoordinatedFileIO.modificationDate(
        at: sourceBundleLocator.bundleDirectoryURL(in: entry.boardDirectoryURL)
    )
)
XCTAssertNotNil(
    try CoordinatedFileIO.modificationDate(
        at: duplicatedBundleLocator.bundleDirectoryURL(in: entry.boardDirectoryURL)
    )
)

func testBoardStoreLoadHandDrawingSourceDataFallsBackToLegacyFlatAssets() throws {
    let legacyItemRecord = BoardHandDrawingItemRecord(
        id: UUID(),
        documentID: documentID,
        center: BoardPointRecord(CGPoint(x: 80, y: 80)),
        size: BoardSizeRecord(CGSize(width: 160, height: 160)),
        zIndex: 1,
        paper: BoardHandDrawingPaperRecord(.square),
        isEmpty: false,
        contentRevision: UUID(),
        rotationRadians: 0,
        storage: .legacyFlatAssetPair
    )

    XCTAssertEqual(
        try BoardStore.loadHandDrawingSourceData(
            boardID: boardID,
            documentID: documentID,
            userDefaults: userDefaults
        ),
        legacyDrawingData
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift
// 函数名: testHandDrawingDocumentStorePersistsBundleRoundTrip() / testHandDrawingDocumentStoreRemovesOrphanedBundles()
// 功能说明: 修改后新增 bundle store 专用测试，验证 manifest/document/preview round-trip 与 orphan bundle 清理。
func testHandDrawingDocumentStorePersistsBundleRoundTrip() throws {
    try HandDrawingDocumentStore.persistDocument(
        documentID: documentID,
        paper: .square,
        contentRevision: contentRevision,
        isEmpty: false,
        drawingData: drawingData,
        previewImageData: nil,
        previewCGImage: previewImage,
        boardDirectoryURL: boardDirectoryURL
    )

    let manifest = try HandDrawingDocumentStore.loadManifest(
        documentID: documentID,
        boardDirectoryURL: boardDirectoryURL
    )
    let loadedDrawingData = try HandDrawingDocumentStore.loadDocumentData(
        documentID: documentID,
        boardDirectoryURL: boardDirectoryURL
    )
    XCTAssertEqual(manifest.documentID, documentID)
    XCTAssertEqual(loadedDrawingData, drawingData)
}

func testHandDrawingDocumentStoreRemovesOrphanedBundles() throws {
    try HandDrawingDocumentStore.removeOrphanedBundles(
        keeping: [keptDocumentID],
        boardDirectoryURL: boardDirectoryURL
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift / MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 函数名: testBoardDocumentMapperRoundTripsHandDrawingItem() / testBoardDocumentMapperRoundTripsVideoPosterMetadata()
// 功能说明: 修改后新 handDrawing 记录的预期改为 bundle，受 mapper 新签名影响的 video 测试也做了显式 imageLoader 调整。
XCTAssertEqual(handDrawingRecord.storage, .bundle)
XCTAssertEqual(
    handDrawingRecord.previewImageFilename,
    HandDrawingBundleLocator(documentID: documentID).previewImageRelativePath
)

let roundTrippedState = try BoardDocumentMapper.makeRuntimeState(
    from: document,
    imageLoader: { _ in
        posterImage
    }
)
```

## 结果小结

- 阶段 2 完成后，新 handDrawing 已经默认保存为独立 bundle，而不是 `assets/` 下的扁平双文件。
- `BoardStore` 已具备“新数据走 bundle、旧数据继续按 legacy 读取”的双通道能力。
- board 文档现在只保留 handDrawing 的引用与展示元数据；真正的手绘内容、preview 和 manifest 已进入独立 bundle。
- 旧 legacy 文档仍能继续工作，并且在未进入阶段 3 迁移逻辑前，不会被阶段 2 普通保存流程擅自转换。
