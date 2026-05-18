# 20260518_144714_hand_drawing_kernel_phase1_boundary_schema_record

## 记录范围

- 记录内容：
  1. 为 handDrawing 运行时模型增加 `HandDrawingDocumentID` / `documentID`，拆分 `itemID` 与手绘文档身份。
  2. 升级 `BoardDocument` schema 到 `7`，给 `BoardHandDrawingItemRecord` 增加 `documentID` / `storage`，并保留旧记录的兼容解码入口。
  3. 将 `BoardDocumentMapper`、`BoardHandDrawingAssetLocator`、`BoardStore`、`CanvasEditorSession` 的 handDrawing 资源寻址统一切到 `documentID`。
  4. 补阶段 1 定点测试，验证 round-trip、legacy decode fallback、存储路径隔离与 duplicate 行为。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S"` -> `20260518_144714`
- 参考依据：
  - `git status --short -- MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
  - `git diff --stat -- MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
  - `git diff -- MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
- 当前工作区涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
  - `MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift`
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `M MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
  - `M MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
- `git diff --stat` 摘要：
  - 修改文件：8 个
  - 统计结果：`193 insertions(+), 37 deletions(-)`
  - 改动量最大的是 `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - 其余改动主要集中在运行时 handDrawing 资源寻址与定点测试
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests" -only-testing:"MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests"`
    - 通过
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests"`
    - 通过
  - `ReadLints`
    - 本次修改文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 2 的独立 handDrawing bundle / codec / store 落地
  - 阶段 3 的旧 `.pkdrawing` 懒迁移实现
  - 自研绘图内核、iPad 编辑器 UI、像素橡皮与套索逻辑

## 修改一：`CanvasHandDrawingItem` 拆分 `itemID` 与 `documentID`

### 修改前

- `CanvasHandDrawingItem` 只有 `id`，没有单独的 handDrawing 文档身份。
- preview / source 文件名都直接从 `itemID` 推导。
- duplicate 创建副本时，只会生成新的 `itemID`，没有独立的文档身份。
- history equality 也不会比较文档身份，无法为“board item 引用独立文档”建立稳定边界。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift
// 函数名: CanvasHandDrawingItem.init / previewImageFilename / sourceDrawingFilename / defaultPreviewImageFilename(for:) / defaultSourceDrawingFilename(for:) / duplicated(offsetInWorld:) / matchesDocumentState(_)
// 功能说明: 修改前 handDrawing 的预览图和源稿文件名都直接绑定 itemID，duplicate 后也没有独立文档身份。
struct CanvasHandDrawingItem {
    static let previewImageFileExtension = "png"
    static let sourceDrawingFileExtension = "pkdrawing"
    private static let minimumCanvasDimension: CGFloat = 1

    let id: CanvasItemID
    var paper: CanvasHandDrawingPaperSpec
    var previewAsset: CanvasImageAsset
    var isEmpty: Bool
    var contentRevision: UUID
    // 其余字段省略

    init(
        id: CanvasItemID = UUID(),
        paper: CanvasHandDrawingPaperSpec = .square,
        previewAsset: CanvasImageAsset,
        isEmpty: Bool,
        contentRevision: UUID = UUID(),
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.paper = paper
        self.previewAsset = previewAsset
        self.isEmpty = isEmpty
        self.contentRevision = contentRevision
        // 其余赋值省略
    }

    var previewImageFilename: String {
        Self.defaultPreviewImageFilename(for: id)
    }

    var sourceDrawingFilename: String {
        Self.defaultSourceDrawingFilename(for: id)
    }

    static func defaultPreviewImageFilename(
        for itemID: CanvasItemID
    ) -> String {
        "\(itemID.uuidString).\(previewImageFileExtension)"
    }

    static func defaultSourceDrawingFilename(
        for itemID: CanvasItemID
    ) -> String {
        "\(itemID.uuidString).\(sourceDrawingFileExtension)"
    }

    func duplicated(offsetInWorld: CGPoint) -> CanvasHandDrawingItem {
        let duplicatedID = UUID()
        return CanvasHandDrawingItem(
            id: duplicatedID,
            paper: paper,
            previewAsset: Self.persistedPreviewAsset(
                for: duplicatedID,
                cgImage: previewAsset.posterCGImage,
                logicalPixelSize: previewAsset.logicalPixelSize
            ),
            isEmpty: isEmpty,
            contentRevision: contentRevision,
            // 其余参数省略
        )
    }

    func matchesDocumentState(_ other: CanvasHandDrawingItem) -> Bool {
        id == other.id &&
            paper == other.paper &&
            isEmpty == other.isEmpty &&
            contentRevision == other.contentRevision &&
            center == other.center &&
            size == other.size &&
            zIndex == other.zIndex &&
            rotationRadians == other.rotationRadians
    }
}
```

### 修改后

- 增加 `typealias HandDrawingDocumentID = UUID`。
- `CanvasHandDrawingItem` 显式持有 `documentID`，并在默认构造时回落到 `id`，保证现有调用点不立刻断链。
- preview / source 文件名改由 `documentID` 推导。
- duplicate 时同时生成新的 `itemID` 和新的 `documentID`。
- `matchesDocumentState(_:)` 增加 `documentID` 比较，避免历史快照忽略文档身份变化。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift
// 函数名: CanvasHandDrawingItem.init / previewImageFilename / sourceDrawingFilename / defaultPreviewImageFilename(for:) / defaultSourceDrawingFilename(for:) / duplicated(offsetInWorld:) / matchesDocumentState(_)
// 功能说明: 修改后 handDrawing 运行时模型把 board item 身份与 handDrawing 文档身份拆开，为后续独立文档包铺边界。
typealias HandDrawingDocumentID = UUID

struct CanvasHandDrawingItem {
    static let previewImageFileExtension = "png"
    static let sourceDrawingFileExtension = "pkdrawing"
    private static let minimumCanvasDimension: CGFloat = 1

    let id: CanvasItemID
    let documentID: HandDrawingDocumentID
    var paper: CanvasHandDrawingPaperSpec
    var previewAsset: CanvasImageAsset
    var isEmpty: Bool
    var contentRevision: UUID
    // 其余字段省略

    init(
        id: CanvasItemID = UUID(),
        documentID: HandDrawingDocumentID? = nil,
        paper: CanvasHandDrawingPaperSpec = .square,
        previewAsset: CanvasImageAsset,
        isEmpty: Bool,
        contentRevision: UUID = UUID(),
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.documentID = documentID ?? id
        self.paper = paper
        self.previewAsset = previewAsset
        self.isEmpty = isEmpty
        self.contentRevision = contentRevision
        // 其余赋值省略
    }

    var previewImageFilename: String {
        Self.defaultPreviewImageFilename(for: documentID)
    }

    var sourceDrawingFilename: String {
        Self.defaultSourceDrawingFilename(for: documentID)
    }

    static func defaultPreviewImageFilename(
        for documentID: HandDrawingDocumentID
    ) -> String {
        "\(documentID.uuidString).\(previewImageFileExtension)"
    }

    static func defaultSourceDrawingFilename(
        for documentID: HandDrawingDocumentID
    ) -> String {
        "\(documentID.uuidString).\(sourceDrawingFileExtension)"
    }

    func duplicated(offsetInWorld: CGPoint) -> CanvasHandDrawingItem {
        let duplicatedID = UUID()
        let duplicatedDocumentID = HandDrawingDocumentID()
        return CanvasHandDrawingItem(
            id: duplicatedID,
            documentID: duplicatedDocumentID,
            paper: paper,
            previewAsset: Self.persistedPreviewAsset(
                for: duplicatedDocumentID,
                cgImage: previewAsset.posterCGImage,
                logicalPixelSize: previewAsset.logicalPixelSize
            ),
            isEmpty: isEmpty,
            contentRevision: contentRevision,
            // 其余参数省略
        )
    }

    func matchesDocumentState(_ other: CanvasHandDrawingItem) -> Bool {
        id == other.id &&
            documentID == other.documentID &&
            paper == other.paper &&
            isEmpty == other.isEmpty &&
            contentRevision == other.contentRevision &&
            center == other.center &&
            size == other.size &&
            zIndex == other.zIndex &&
            rotationRadians == other.rotationRadians
    }
}
```

## 修改二：`BoardDocument` schema 升级，并给 handDrawing record 增加兼容解码入口

### 修改前

- `BoardDocument.currentFormatVersion` 还是 `6`。
- `BoardHandDrawingItemRecord` 只有 `id`，没有单独的 `documentID`。
- 也没有 `storage` 字段，无法提前表达“当前还是 legacy flat asset pair，后续再迁 bundle 模式”。
- `assetLocator` 仍然通过 `itemID` 定位资源文件。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardDocument.currentFormatVersion / BoardHandDrawingItemRecord / assetLocator
// 功能说明: 修改前 board schema 还没有 handDrawing 文档身份字段，record 也没有 storage 形态语义。
struct BoardDocument: Codable {
    // Board schema now evolves independently from image asset internals.
    static let currentFormatVersion = 6
    static let defaultTitle = "Untitled Board"
    // 其余字段省略
}

struct BoardHandDrawingItemRecord: Codable, Equatable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var paper: BoardHandDrawingPaperRecord
    var isEmpty: Bool
    var contentRevision: UUID
    var rotationRadians: Double?

    var previewImageFilename: String {
        assetLocator.previewImageFilename
    }

    var sourceDrawingFilename: String {
        assetLocator.sourceDrawingFilename
    }

    var assetLocator: BoardHandDrawingAssetLocator {
        BoardHandDrawingAssetLocator(itemID: id)
    }
}
```

### 修改后

- schema version 升级到 `7`。
- 新增 `BoardHandDrawingStorageRecord`，当前阶段先落 `.legacyFlatAssetPair`，作为阶段 2/3 之前的显式存储语义。
- `BoardHandDrawingItemRecord` 增加 `documentID`，并提供自定义 `init(from:)` / `encode(to:)`。
- legacy 记录缺少 `documentID` / `storage` 时，会自动回落成 `documentID = id`、`storage = .legacyFlatAssetPair`，为懒迁移保留入口。
- `assetLocator` 切到 `documentID`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardDocument.currentFormatVersion / BoardHandDrawingStorageRecord / BoardHandDrawingItemRecord.init(...) / init(from:) / encode(to:) / assetLocator
// 功能说明: 修改后 board schema 能显式携带 handDrawing 的 documentID 与 storage 形态，并兼容旧记录缺字段场景。
struct BoardDocument: Codable {
    // Board schema now evolves independently from image asset internals.
    static let currentFormatVersion = 7
    static let defaultTitle = "Untitled Board"
    // 其余字段省略
}

enum BoardHandDrawingStorageRecord: String, Codable, Equatable {
    case legacyFlatAssetPair
}

struct BoardHandDrawingItemRecord: Codable, Equatable {
    let id: UUID
    let documentID: HandDrawingDocumentID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var paper: BoardHandDrawingPaperRecord
    var isEmpty: Bool
    var contentRevision: UUID
    var rotationRadians: Double?
    var storage: BoardHandDrawingStorageRecord

    private enum CodingKeys: String, CodingKey {
        case id
        case documentID
        case center
        case size
        case zIndex
        case paper
        case isEmpty
        case contentRevision
        case rotationRadians
        case storage
    }

    init(
        id: UUID,
        documentID: HandDrawingDocumentID? = nil,
        center: BoardPointRecord,
        size: BoardSizeRecord,
        zIndex: Double,
        paper: BoardHandDrawingPaperRecord,
        isEmpty: Bool,
        contentRevision: UUID,
        rotationRadians: Double?,
        storage: BoardHandDrawingStorageRecord = .legacyFlatAssetPair
    ) {
        self.id = id
        self.documentID = documentID ?? id
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.paper = paper
        self.isEmpty = isEmpty
        self.contentRevision = contentRevision
        self.rotationRadians = rotationRadians
        self.storage = storage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        self.init(
            id: id,
            documentID: try container.decodeIfPresent(
                HandDrawingDocumentID.self,
                forKey: .documentID
            ) ?? id,
            center: try container.decode(BoardPointRecord.self, forKey: .center),
            size: try container.decode(BoardSizeRecord.self, forKey: .size),
            zIndex: try container.decode(Double.self, forKey: .zIndex),
            paper: try container.decode(
                BoardHandDrawingPaperRecord.self,
                forKey: .paper
            ),
            isEmpty: try container.decode(Bool.self, forKey: .isEmpty),
            contentRevision: try container.decode(
                UUID.self,
                forKey: .contentRevision
            ),
            rotationRadians: try container.decodeIfPresent(
                Double.self,
                forKey: .rotationRadians
            ),
            storage: try container.decodeIfPresent(
                BoardHandDrawingStorageRecord.self,
                forKey: .storage
            ) ?? .legacyFlatAssetPair
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(documentID, forKey: .documentID)
        try container.encode(center, forKey: .center)
        try container.encode(size, forKey: .size)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(paper, forKey: .paper)
        try container.encode(isEmpty, forKey: .isEmpty)
        try container.encode(contentRevision, forKey: .contentRevision)
        try container.encodeIfPresent(rotationRadians, forKey: .rotationRadians)
        try container.encode(storage, forKey: .storage)
    }

    var assetLocator: BoardHandDrawingAssetLocator {
        BoardHandDrawingAssetLocator(documentID: documentID)
    }
}
```

## 修改三：mapper / locator / store / session 全链路切到 `documentID`

### 修改前

- `BoardDocumentMapper` 在 runtime <-> document 往返时，只把 `id` 当作资产身份。
- `BoardHandDrawingAssetLocator` 只接受 `itemID`。
- `BoardStore.loadHandDrawingSourceData(...)` 与 `persistHandDrawingAssetsIfNeeded(...)` 都用 `itemID` 找 source / preview 文件。
- `CanvasEditorSession` 的编辑入口、提交回写、新增 handDrawing 三条链路都默认使用 `itemID` 作为 preview / source 资产身份。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeHandDrawingItem(from:previewImage:) / makeHandDrawingRecord(from:)
// 功能说明: 修改前 mapper round-trip handDrawing 时，preview/source 资源身份完全跟随 itemID。
private static func makeHandDrawingItem(
    from handDrawingRecord: BoardHandDrawingItemRecord,
    previewImage: CGImage
) -> CanvasHandDrawingItem {
    CanvasHandDrawingItem(
        id: handDrawingRecord.id,
        paper: handDrawingRecord.paper.canvasPaperSpec,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: handDrawingRecord.id,
            cgImage: previewImage
        ),
        isEmpty: handDrawingRecord.isEmpty,
        contentRevision: handDrawingRecord.contentRevision,
        center: handDrawingRecord.center.cgPoint,
        size: handDrawingRecord.size.cgSize,
        zIndex: CGFloat(handDrawingRecord.zIndex),
        rotationRadians: CGFloat(handDrawingRecord.rotationRadians ?? 0)
    )
}

private static func makeHandDrawingRecord(
    from item: CanvasHandDrawingItem
) -> BoardHandDrawingItemRecord {
    BoardHandDrawingItemRecord(
        id: item.id,
        center: BoardPointRecord(item.center),
        size: BoardSizeRecord(item.size),
        zIndex: Double(item.zIndex),
        paper: BoardHandDrawingPaperRecord(item.paper),
        isEmpty: item.isEmpty,
        contentRevision: item.contentRevision,
        rotationRadians: Double(item.rotationRadians)
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift
// 函数名: BoardHandDrawingAssetLocator
// 功能说明: 修改前 locator 只接受 itemID，preview/source 文件名无法独立于 board item 身份存在。
struct BoardHandDrawingAssetLocator {
    let itemID: CanvasItemID

    var previewImageFilename: String {
        CanvasHandDrawingItem.defaultPreviewImageFilename(for: itemID)
    }

    var sourceDrawingFilename: String {
        CanvasHandDrawingItem.defaultSourceDrawingFilename(for: itemID)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: loadHandDrawingSourceData(boardID:itemID:userDefaults:) / persistHandDrawingAssetsIfNeeded(for:snapshot:in:)
// 功能说明: 修改前 BoardStore 读写 handDrawing 资源时统一按 itemID 定位。
static func loadHandDrawingSourceData(
    boardID: UUID,
    itemID: CanvasItemID,
    userDefaults: UserDefaults = .standard
) throws -> Data {
    // 其余目录解析省略
    let sourceURL = BoardHandDrawingAssetLocator(itemID: itemID)
        .sourceDrawingURL(in: assetsDirectoryURL)
    return try CoordinatedFileIO.readData(at: sourceURL)
}

private static func persistHandDrawingAssetsIfNeeded(
    for item: CanvasHandDrawingItem,
    snapshot: BoardSaveSnapshot,
    in assetsDirectoryURL: URL
) throws {
    let assetLocator = BoardHandDrawingAssetLocator(itemID: item.id)
    let previewImageURL = assetLocator.previewImageURL(in: assetsDirectoryURL)
    let sourceDrawingURL = assetLocator.sourceDrawingURL(in: assetsDirectoryURL)
    // 其余写入逻辑省略
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: handDrawingEditorContext(for:) / commitHandDrawingEdit(withID:submission:) / addHandDrawingItem(paper:)
// 功能说明: 修改前 session 在编辑读取、提交回写和新建 handDrawing 时都把 itemID 当成资源身份。
return CanvasHandDrawingEditorContext(
    itemID: itemID,
    paper: item.paper,
    drawingData: try BoardStore.loadHandDrawingSourceData(
        boardID: activeBoardID,
        itemID: itemID,
        userDefaults: userDefaults
    ),
    isEmpty: item.isEmpty
)

item.previewAsset = CanvasHandDrawingItem.persistedPreviewAsset(
    for: item.id,
    cgImage: submission.previewCGImage,
    logicalPixelSize: item.paper.size
)

let itemID = CanvasItemID()
let item = CanvasHandDrawingItem(
    id: itemID,
    paper: paper,
    previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
        for: itemID,
        cgImage: previewImage,
        logicalPixelSize: paper.size
    ),
    isEmpty: true,
    center: camera.center,
    size: normalizedDisplaySize(for: paper.size),
    zIndex: nextBoardItemZIndex()
)
```

### 修改后

- `BoardDocumentMapper` 负责在 runtime / document 往返时保留 `documentID`。
- `BoardHandDrawingAssetLocator` 改成基于 `documentID` 生成 preview / source 路径。
- `BoardStore` 的 source load 与 asset persist 全部改成按 `documentID` 寻址。
- `CanvasEditorSession`：
  - 打开编辑器时按 `documentID` 读取 source。
  - 提交回写 preview 时按 `documentID` 生成 preview filename。
  - 新建 handDrawing 时同时生成新的 `itemID` 与新的 `documentID`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeHandDrawingItem(from:previewImage:) / makeHandDrawingRecord(from:)
// 功能说明: 修改后 mapper 会把 documentID 一起往返，保证 runtime/document round-trip 不丢 handDrawing 文档身份。
private static func makeHandDrawingItem(
    from handDrawingRecord: BoardHandDrawingItemRecord,
    previewImage: CGImage
) -> CanvasHandDrawingItem {
    CanvasHandDrawingItem(
        id: handDrawingRecord.id,
        documentID: handDrawingRecord.documentID,
        paper: handDrawingRecord.paper.canvasPaperSpec,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: handDrawingRecord.documentID,
            cgImage: previewImage
        ),
        isEmpty: handDrawingRecord.isEmpty,
        contentRevision: handDrawingRecord.contentRevision,
        center: handDrawingRecord.center.cgPoint,
        size: handDrawingRecord.size.cgSize,
        zIndex: CGFloat(handDrawingRecord.zIndex),
        rotationRadians: CGFloat(handDrawingRecord.rotationRadians ?? 0)
    )
}

private static func makeHandDrawingRecord(
    from item: CanvasHandDrawingItem
) -> BoardHandDrawingItemRecord {
    BoardHandDrawingItemRecord(
        id: item.id,
        documentID: item.documentID,
        center: BoardPointRecord(item.center),
        size: BoardSizeRecord(item.size),
        zIndex: Double(item.zIndex),
        paper: BoardHandDrawingPaperRecord(item.paper),
        isEmpty: item.isEmpty,
        contentRevision: item.contentRevision,
        rotationRadians: Double(item.rotationRadians),
        storage: .legacyFlatAssetPair
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift
// 函数名: BoardHandDrawingAssetLocator
// 功能说明: 修改后 locator 改为按 documentID 推导 preview/source 文件名，itemID 只保留给 board item 选择与交互。
struct BoardHandDrawingAssetLocator {
    let documentID: HandDrawingDocumentID

    var previewImageFilename: String {
        CanvasHandDrawingItem.defaultPreviewImageFilename(for: documentID)
    }

    var sourceDrawingFilename: String {
        CanvasHandDrawingItem.defaultSourceDrawingFilename(for: documentID)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: loadHandDrawingSourceData(boardID:documentID:userDefaults:) / persistHandDrawingAssetsIfNeeded(for:snapshot:in:)
// 功能说明: 修改后 BoardStore 统一按 documentID 读取和落盘 handDrawing 资源，为后续 bundle 化存储保留入口。
static func loadHandDrawingSourceData(
    boardID: UUID,
    documentID: HandDrawingDocumentID,
    userDefaults: UserDefaults = .standard
) throws -> Data {
    // 其余目录解析省略
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
    // 其余写入逻辑省略
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: handDrawingEditorContext(for:) / commitHandDrawingEdit(withID:submission:) / addHandDrawingItem(paper:)
// 功能说明: 修改后 session 在编辑入口、提交回写和新建 handDrawing 时都改为围绕 documentID 寻址与生成 preview/source 资产。
return CanvasHandDrawingEditorContext(
    itemID: itemID,
    paper: item.paper,
    drawingData: try BoardStore.loadHandDrawingSourceData(
        boardID: activeBoardID,
        documentID: item.documentID,
        userDefaults: userDefaults
    ),
    isEmpty: item.isEmpty
)

item.previewAsset = CanvasHandDrawingItem.persistedPreviewAsset(
    for: item.documentID,
    cgImage: submission.previewCGImage,
    logicalPixelSize: item.paper.size
)

let itemID = CanvasItemID()
let documentID = HandDrawingDocumentID()
let item = CanvasHandDrawingItem(
    id: itemID,
    documentID: documentID,
    paper: paper,
    previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
        for: documentID,
        cgImage: previewImage,
        logicalPixelSize: paper.size
    ),
    isEmpty: true,
    center: camera.center,
    size: normalizedDisplaySize(for: paper.size),
    zIndex: nextBoardItemZIndex()
)
```

## 修改四：补阶段 1 测试，验证 round-trip、legacy fallback 与独立资产路径

### 修改前

- `BoardSelectionStateMigrationTests` 的 round-trip 断言只覆盖 `itemID`、`contentRevision` 和 preview filename，没有覆盖 `documentID` / `storage`。
- 没有专门验证“旧 handDrawing record 缺 `documentID` / `storage` 时能否回落到 `itemID`”。
- `BoardHandDrawingStorageTests` 仍按 `itemID` 定位 source 文件，无法直接证明 duplicate 后有独立文档身份与独立资产路径。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数名: testBoardDocumentMapperRoundTripsHandDrawingItem()
// 功能说明: 修改前 round-trip 测试只验证 itemID 和由 itemID 推导出的 preview filename，没有覆盖 documentID。
func testBoardDocumentMapperRoundTripsHandDrawingItem() throws {
    let itemID = UUID()
    let contentRevision = UUID()
    let previewImage = try makeSolidColorPreviewImage(
        red: 0.1,
        green: 0.2,
        blue: 0.9
    )
    let item = CanvasHandDrawingItem(
        id: itemID,
        paper: .square,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: itemID,
            cgImage: previewImage
        ),
        isEmpty: false,
        contentRevision: contentRevision,
        center: CGPoint(x: 160, y: 90),
        size: CGSize(width: 320, height: 320),
        zIndex: 3,
        rotationRadians: .pi / 8
    )

    let document = BoardDocumentMapper.makeDocument(from: runtimeState)
    let handDrawingRecord = try XCTUnwrap(document.handDrawingItemRecords.first)
    XCTAssertEqual(handDrawingRecord.id, itemID)
    XCTAssertEqual(handDrawingRecord.paper.canvasPaperSpec, .square)
    XCTAssertEqual(handDrawingRecord.contentRevision, contentRevision)
    XCTAssertEqual(
        handDrawingRecord.previewImageFilename,
        CanvasHandDrawingItem.defaultPreviewImageFilename(for: itemID)
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() / testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() / makeHandDrawingItem(id:previewImage:contentRevision:isEmpty:)
// 功能说明: 修改前 storage 测试全部把 itemID 当成资源身份，没有额外的 documentID 断言。
func testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() throws {
    let boardID = UUID()
    let itemID = UUID()
    let item = makeHandDrawingItem(
        id: itemID,
        previewImage: previewImage,
        contentRevision: UUID()
    )

    let assetLocator = BoardHandDrawingAssetLocator(itemID: itemID)
    XCTAssertEqual(
        try BoardStore.loadHandDrawingSourceData(
            boardID: boardID,
            itemID: itemID,
            userDefaults: userDefaults
        ),
        drawingData
    )
}

func testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() throws {
    let duplicatedHandDrawingItem = sourceItem.duplicated(
        offsetInWorld: CGPoint(x: 42, y: 24)
    )
    let sourceReloadedData = try BoardStore.loadHandDrawingSourceData(
        boardID: boardID,
        itemID: sourceItemID,
        userDefaults: userDefaults
    )
    let duplicatedReloadedData = try BoardStore.loadHandDrawingSourceData(
        boardID: boardID,
        itemID: duplicatedHandDrawingItem.id,
        userDefaults: userDefaults
    )
    XCTAssertEqual(sourceReloadedData, sourceDrawingData)
    XCTAssertEqual(duplicatedReloadedData, sourceDrawingData)
}

private func makeHandDrawingItem(
    id: UUID,
    previewImage: CGImage,
    contentRevision: UUID,
    isEmpty: Bool = false
) -> CanvasHandDrawingItem {
    CanvasHandDrawingItem(
        id: id,
        paper: .square,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: id,
            cgImage: previewImage
        ),
        isEmpty: isEmpty,
        contentRevision: contentRevision,
        // 其余参数省略
    )
}
```

### 修改后

- `BoardSelectionStateMigrationTests`：
  - round-trip 用例显式构造 `documentID`，并断言 document / runtime 往返不丢失。
  - 新增 legacy payload decode 用例，验证缺字段时回落到 `documentID = itemID`。
- `BoardHandDrawingStorageTests`：
  - save/load 用例显式构造 `documentID`，并断言 reload 后保留。
  - duplicate 用例按 `documentID` 读取 source，并断言 source / duplicate 各自拥有独立 `documentID`。
  - helper `makeHandDrawingItem(...)` 支持传入 `documentID`，方便后续阶段继续扩展。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数名: testBoardDocumentMapperRoundTripsHandDrawingItem() / testBoardHandDrawingItemRecordDecodesLegacyAssetIdentityFromItemID()
// 功能说明: 修改后测试同时覆盖 documentID round-trip 和 legacy handDrawing record 缺字段时的 fallback decode。
func testBoardDocumentMapperRoundTripsHandDrawingItem() throws {
    let itemID = UUID()
    let documentID = UUID()
    let contentRevision = UUID()
    let previewImage = try makeSolidColorPreviewImage(
        red: 0.1,
        green: 0.2,
        blue: 0.9
    )
    let item = CanvasHandDrawingItem(
        id: itemID,
        documentID: documentID,
        paper: .square,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: documentID,
            cgImage: previewImage
        ),
        isEmpty: false,
        contentRevision: contentRevision,
        center: CGPoint(x: 160, y: 90),
        size: CGSize(width: 320, height: 320),
        zIndex: 3,
        rotationRadians: .pi / 8
    )

    let document = BoardDocumentMapper.makeDocument(from: runtimeState)
    let handDrawingRecord = try XCTUnwrap(document.handDrawingItemRecords.first)
    XCTAssertEqual(handDrawingRecord.id, itemID)
    XCTAssertEqual(handDrawingRecord.documentID, documentID)
    XCTAssertEqual(handDrawingRecord.paper.canvasPaperSpec, .square)
    XCTAssertEqual(handDrawingRecord.contentRevision, contentRevision)
    XCTAssertEqual(handDrawingRecord.storage, .legacyFlatAssetPair)
    XCTAssertEqual(
        handDrawingRecord.previewImageFilename,
        CanvasHandDrawingItem.defaultPreviewImageFilename(for: documentID)
    )

    let roundTrippedItem = try XCTUnwrap(roundTrippedState.handDrawingItems.first)
    XCTAssertEqual(roundTrippedItem.id, item.id)
    XCTAssertEqual(roundTrippedItem.documentID, item.documentID)
    XCTAssertEqual(
        roundTrippedItem.previewAsset.reference.stableAssetFilename,
        item.previewImageFilename
    )
}

func testBoardHandDrawingItemRecordDecodesLegacyAssetIdentityFromItemID() throws {
    let itemID = UUID()
    let contentRevision = UUID()
    let legacyPayload: [String: Any] = [
        "id": itemID.uuidString,
        "center": ["x": 48, "y": 72],
        "size": ["width": 240, "height": 180],
        "zIndex": 2,
        "paper": [
            "id": "square",
            "size": ["width": 1_024, "height": 1_024]
        ],
        "isEmpty": true,
        "contentRevision": contentRevision.uuidString,
        "rotationRadians": Double.pi / 6
    ]
    let decoder = JSONDecoder()
    let record = try decoder.decode(
        BoardHandDrawingItemRecord.self,
        from: try JSONSerialization.data(withJSONObject: legacyPayload)
    )

    XCTAssertEqual(record.id, itemID)
    XCTAssertEqual(record.documentID, itemID)
    XCTAssertEqual(record.storage, .legacyFlatAssetPair)
    XCTAssertEqual(
        record.previewImageFilename,
        CanvasHandDrawingItem.defaultPreviewImageFilename(for: itemID)
    )
    XCTAssertEqual(
        record.sourceDrawingFilename,
        CanvasHandDrawingItem.defaultSourceDrawingFilename(for: itemID)
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() / testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() / makeHandDrawingItem(id:documentID:previewImage:contentRevision:isEmpty:)
// 功能说明: 修改后 storage 测试按 documentID 验证 handDrawing 资源寻址，并断言 duplicate 后 source/preview 路径与文档身份相互独立。
func testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() throws {
    let boardID = UUID()
    let itemID = UUID()
    let documentID = UUID()
    let item = makeHandDrawingItem(
        id: itemID,
        documentID: documentID,
        previewImage: previewImage,
        contentRevision: UUID()
    )

    let assetLocator = BoardHandDrawingAssetLocator(documentID: documentID)
    let loadedItem = try XCTUnwrap(loadedState.handDrawingItems.first)
    XCTAssertEqual(loadedItem.id, item.id)
    XCTAssertEqual(loadedItem.documentID, documentID)
    XCTAssertEqual(
        try BoardStore.loadHandDrawingSourceData(
            boardID: boardID,
            documentID: documentID,
            userDefaults: userDefaults
        ),
        drawingData
    )
}

func testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() throws {
    let duplicatedHandDrawingItem = sourceItem.duplicated(
        offsetInWorld: CGPoint(x: 42, y: 24)
    )
    XCTAssertNotEqual(
        duplicatedHandDrawingItem.previewImageFilename,
        sourceItem.previewImageFilename
    )
    XCTAssertNotEqual(
        duplicatedHandDrawingItem.sourceDrawingFilename,
        sourceItem.sourceDrawingFilename
    )

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
    XCTAssertEqual(loadedSourceItem.documentID, sourceItem.documentID)
    XCTAssertEqual(
        loadedDuplicatedItem.documentID,
        duplicatedHandDrawingItem.documentID
    )
}

private func makeHandDrawingItem(
    id: UUID,
    documentID: HandDrawingDocumentID? = nil,
    previewImage: CGImage,
    contentRevision: UUID,
    isEmpty: Bool = false
) -> CanvasHandDrawingItem {
    CanvasHandDrawingItem(
        id: id,
        documentID: documentID,
        paper: .square,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: documentID ?? id,
            cgImage: previewImage
        ),
        isEmpty: isEmpty,
        contentRevision: contentRevision,
        // 其余参数省略
    )
}
```

## 结果小结

- 阶段 1 完成后，handDrawing 的 board item 身份与手绘文档身份已经在 runtime、schema、mapper、store、session、tests 上形成统一边界。
- 当前仍保持 legacy flat file 持久化语义，没有提前切到 bundle；但 `documentID` 与 `storage` 已经把阶段 2 / 3 所需的迁移支点放到位。
- 现有 handDrawing 渲染、保存、duplicate、编辑回写主链在定点测试下保持可用。
