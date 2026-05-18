# 20260518_152750_hand_drawing_kernel_phase3_lazy_migration_record

## 记录范围

- 记录内容：
  1. 为旧 `.pkdrawing` handDrawing 增加“首次编辑时懒迁移到 bundle”的独立迁移事务链。
  2. 为 bundle 增加 `legacy_backup.pkdrawing` 兜底文件，以及 bundle 自恢复 / 删除能力。
  3. 改造 handDrawing 编辑入口，让 `CanvasEditorSession` 在打开编辑器前显式准备文档，而不是继续盲读 source data。
  4. 为 board 记录增加 storage 切换辅助 API，保证 migration 成功前不污染 `board.json`。
  5. 补 migration / rollback / backup restore / session 入口集成测试。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S"` -> `20260518_152750`
- 说明：
  - 本记录中的“修改前”以阶段 2 完成态为基线，不直接回退到更早版本。
  - 对于本阶段新增文件，修改前如实记录为“文件不存在”。
  - 对于已跟踪文件，本记录结合当前 `git diff`、当前文件内容和阶段 2 记录整理，不放原始 diff。
- 参考依据：
  - `git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
  - `git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
  - `git diff -- MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
  - 阶段 2 记录：
    - `commit_records/20260518_150955_hand_drawing_kernel_phase2_bundle_persistence_record.md`
- 当前工作区涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
- `git diff --stat` 摘要：
  - 已跟踪文件修改：6 个
  - 统计结果：`144 insertions(+), 36 deletions(-)`
  - 未跟踪新增文件：2 个
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests" -only-testing:"MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests"`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 4 的自研文档模型、编辑内核骨架与 preview renderer
  - 阶段 5 之后的新编辑器 UI、像素橡皮、套索移动
  - git commit / push

## 修改一：新增 `HandDrawingMigrationService`，把 legacy 懒迁移、回滚和恢复从编辑入口里拆出来

### 修改前

- 阶段 2 已经能“读 bundle / fallback legacy”，但还没有独立 migration service。
- `CanvasEditorSession.handDrawingEditorContext(for:)` 只会直接读取 source data：
  - 有 transient payload 就直接返回。
  - 没有 payload 就调用 `BoardStore.loadHandDrawingSourceData(...)`。
- 结果是：
  - 首次编辑 legacy handDrawing 时，并不会真正把 storage 切到 `.bundle`。
  - 也没有“迁移成功后再切 storage”的原子事务。
  - 失败时无法显式清理半成品 bundle。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift
// 函数名: 无
// 功能说明: 阶段2完成态下还不存在独立的 handDrawing 懒迁移服务。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: handDrawingEditorContext(for:)
// 功能说明: 阶段2完成态下，编辑入口只负责读取当前 drawingData，不负责 legacy -> bundle 迁移事务。
func handDrawingEditorContext(
    for itemID: CanvasItemID
) throws -> CanvasHandDrawingEditorContext {
    guard let item = scene.handDrawingItem(withID: itemID) else {
        throw CanvasHandDrawingEditingError.invalidHandDrawingItem(
            itemID: itemID
        )
    }

    if let payload = transientHandDrawingAssetPayload(for: itemID) {
        return CanvasHandDrawingEditorContext(
            itemID: itemID,
            paper: item.paper,
            drawingData: payload.drawingData,
            isEmpty: item.isEmpty
        )
    }

    guard let activeBoardID else {
        throw CanvasHandDrawingEditingError.missingBoardIdentity
    }

    do {
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
    } catch {
        throw CanvasHandDrawingEditingError.missingSourceDrawing(
            itemID: itemID
        )
    }
}
```

### 修改后

- 新增 `HandDrawingMigrationService`，把 migration 行为显式收口。
- `prepareDocumentForEditing(...)` 会先解析 board 记录，再按 `storage` 分流：
  - `.bundle`：正常读取 bundle；如果 `document.hdraw` 缺失且 manifest 标记来自 legacy，则尝试用 `legacy_backup.pkdrawing` 恢复。
  - `.legacyFlatAssetPair`：首次编辑时读取旧 `.pkdrawing` / preview，校验 `PKDrawing` 可解码后写入 bundle，并且只有 bundle 写入校验成功后，才更新 `board.json` 里的 storage。
- 若迁移中途失败，会删除半成品 bundle，不污染 board 记录。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift
// 函数名: prepareDocumentForEditing(...) / prepareLegacyDocumentForEditing(...) / resumeLegacyMigrationIfNeeded(...) / restoreDocumentFromLegacyBackupIfPossible(...)
// 功能说明: 修改后 handDrawing 首次编辑的 legacy 懒迁移、失败回滚和 backup 恢复都由独立 service 负责。
enum HandDrawingMigrationService {
    static func prepareDocumentForEditing(
        boardID: UUID,
        itemID: CanvasItemID,
        userDefaults: UserDefaults = .standard
    ) throws -> HandDrawingPreparedEditingDocument {
        let entry = try resolveBoardDocumentEntry(
            boardID: boardID,
            userDefaults: userDefaults
        )
        let record = try resolveHandDrawingRecord(
            boardID: boardID,
            itemID: itemID,
            document: entry.document
        )

        switch record.storage {
        case .bundle:
            return try prepareBundleDocumentForEditing(
                record: record,
                boardDirectoryURL: entry.boardDirectoryURL
            )
        case .legacyFlatAssetPair:
            return try prepareLegacyDocumentForEditing(
                boardID: boardID,
                itemID: itemID,
                record: record,
                entry: entry,
                userDefaults: userDefaults
            )
        }
    }

    private static func prepareLegacyDocumentForEditing(
        boardID: UUID,
        itemID: CanvasItemID,
        record: BoardHandDrawingItemRecord,
        entry: BoardDocumentCatalogEntry,
        userDefaults: UserDefaults
    ) throws -> HandDrawingPreparedEditingDocument {
        let legacyDrawingData = try loadLegacyDrawingData(
            for: record,
            assetsDirectoryURL: entry.assetsDirectoryURL
        )
        try validateLegacyDrawingData(
            legacyDrawingData,
            itemID: itemID
        )
        let legacyPreviewImageData = try loadLegacyPreviewImageData(
            for: record,
            itemID: itemID,
            assetsDirectoryURL: entry.assetsDirectoryURL
        )

        do {
            try HandDrawingDocumentStore.persistDocument(
                documentID: record.documentID,
                paper: record.paper.canvasPaperSpec,
                contentRevision: record.contentRevision,
                isEmpty: record.isEmpty,
                drawingData: legacyDrawingData,
                previewImageData: legacyPreviewImageData,
                previewCGImage: nil,
                boardDirectoryURL: entry.boardDirectoryURL,
                migrationOrigin: .legacyFlatAssetPair,
                legacyBackupDrawingData: legacyDrawingData
            )
            try HandDrawingDocumentStore.validateBundleExists(
                documentID: record.documentID,
                boardDirectoryURL: entry.boardDirectoryURL
            )
            try BoardStore.updateHandDrawingStorage(
                boardID: boardID,
                itemID: itemID,
                storage: .bundle,
                userDefaults: userDefaults
            )
        } catch {
            try? HandDrawingDocumentStore.removeDocumentBundle(
                documentID: record.documentID,
                boardDirectoryURL: entry.boardDirectoryURL
            )
            throw error
        }

        return HandDrawingPreparedEditingDocument(
            record: record.replacingStorage(with: .bundle),
            drawingData: legacyDrawingData,
            didMigrateLegacyDocument: true
        )
    }

    private static func restoreDocumentFromLegacyBackupIfPossible(
        for record: BoardHandDrawingItemRecord,
        boardDirectoryURL: URL
    ) throws -> Data? {
        let manifest = try? HandDrawingDocumentStore.loadManifest(
            documentID: record.documentID,
            boardDirectoryURL: boardDirectoryURL
        )
        guard manifest?.migrationOrigin == .legacyFlatAssetPair else {
            return nil
        }

        let legacyBackupDrawingData = try HandDrawingDocumentStore
            .loadLegacyBackupDrawingData(
                documentID: record.documentID,
                boardDirectoryURL: boardDirectoryURL
            )
        let previewImageData = try HandDrawingDocumentStore.loadPreviewImageData(
            documentID: record.documentID,
            boardDirectoryURL: boardDirectoryURL
        )
        try HandDrawingDocumentStore.persistDocument(
            documentID: record.documentID,
            paper: manifest?.paper.canvasPaperSpec ?? record.paper.canvasPaperSpec,
            contentRevision: manifest?.contentRevision ?? record.contentRevision,
            isEmpty: manifest?.isEmpty ?? record.isEmpty,
            drawingData: legacyBackupDrawingData,
            previewImageData: previewImageData,
            previewCGImage: nil,
            boardDirectoryURL: boardDirectoryURL,
            migrationOrigin: manifest?.migrationOrigin,
            legacyBackupDrawingData: legacyBackupDrawingData
        )
        return legacyBackupDrawingData
    }
}
```

## 修改二：编辑入口上下文不再只带 bytes，而是显式携带 migration 后的文档状态

### 修改前

- `CanvasHandDrawingEditorContext` 只有 `itemID`、`paper`、`drawingData`、`isEmpty`。
- 编辑器入口无法知道：
  - 当前打开的是 legacy 记录还是 bundle 记录
  - 本次打开是否刚刚触发过 migration
  - 当前 `documentID` 是多少

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift
// 函数名: CanvasHandDrawingEditorContext
// 功能说明: 阶段2完成态下，handDrawing 编辑上下文只携带原始 drawing bytes 和空白状态，不暴露 storage / migration 信息。
struct CanvasHandDrawingEditorContext {
    let itemID: CanvasItemID
    let paper: CanvasHandDrawingPaperSpec
    let drawingData: Data
    let isEmpty: Bool
}
```

### 修改后

- `CanvasHandDrawingEditorContext` 新增：
  - `documentID`
  - `storage`
  - `didMigrateLegacyDocument`
- `CanvasEditorSession.handDrawingEditorContext(for:)`：
  - 有 transient payload 时，直接标记为 `.bundle`
  - 否则先走 `HandDrawingMigrationService.prepareDocumentForEditing(...)`
  - 返回给编辑器的是“已准备好可编辑”的文档状态，而不是单纯 source bytes

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift / MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: CanvasHandDrawingEditorContext / handDrawingEditorContext(for:)
// 功能说明: 修改后编辑上下文会显式携带 documentID、storage 和 didMigrateLegacyDocument，让编辑入口拿到 migration 后的真实文档状态。
struct CanvasHandDrawingEditorContext {
    let itemID: CanvasItemID
    let documentID: HandDrawingDocumentID
    let paper: CanvasHandDrawingPaperSpec
    let drawingData: Data
    let isEmpty: Bool
    let storage: BoardHandDrawingStorageRecord
    let didMigrateLegacyDocument: Bool
}

func handDrawingEditorContext(
    for itemID: CanvasItemID
) throws -> CanvasHandDrawingEditorContext {
    guard let item = scene.handDrawingItem(withID: itemID) else {
        throw CanvasHandDrawingEditingError.invalidHandDrawingItem(
            itemID: itemID
        )
    }

    if let payload = transientHandDrawingAssetPayload(for: itemID) {
        return CanvasHandDrawingEditorContext(
            itemID: itemID,
            documentID: item.documentID,
            paper: item.paper,
            drawingData: payload.drawingData,
            isEmpty: item.isEmpty,
            storage: .bundle,
            didMigrateLegacyDocument: false
        )
    }

    let preparedDocument = try HandDrawingMigrationService.prepareDocumentForEditing(
        boardID: activeBoardID,
        itemID: itemID,
        userDefaults: userDefaults
    )
    return CanvasHandDrawingEditorContext(
        itemID: itemID,
        documentID: item.documentID,
        paper: item.paper,
        drawingData: preparedDocument.drawingData,
        isEmpty: item.isEmpty,
        storage: preparedDocument.record.storage,
        didMigrateLegacyDocument: preparedDocument.didMigrateLegacyDocument
    )
}
```

## 修改三：bundle 增加 `legacy_backup.pkdrawing`，store 具备 backup 读写与整包清理能力

### 修改前

- 阶段 2 的 bundle 只有三件套：
  - `manifest.json`
  - `document.hdraw`
  - `preview.png`
- `HandDrawingDocumentStore`：
  - `loadPreviewImage(...)` 直接在内部读 preview 并解码
  - `persistDocument(...)` 只能写 manifest/document/preview
  - 没有单独读取 legacy backup 的能力
  - 也没有提供“删除整个 handDrawing bundle”的 API

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift
// 函数名: manifestFilename / documentFilename / previewFilename / manifestRelativePath / previewImageURL(in:)
// 功能说明: 阶段2完成态下，bundle 里只有 manifest/document/preview 三件套，没有 legacy backup 路径约定。
struct HandDrawingBundleLocator {
    static let handDrawingsDirectoryName = "handdrawings"
    static let bundleFileExtension = "handdraw"
    static let manifestFilename = "manifest.json"
    static let documentFilename = "document.hdraw"
    static let previewFilename = "preview.png"

    let documentID: HandDrawingDocumentID

    var manifestRelativePath: String {
        [
            Self.handDrawingsDirectoryName,
            bundleDirectoryName,
            Self.manifestFilename
        ].joined(separator: "/")
    }

    func previewImageURL(in boardDirectoryURL: URL) -> URL {
        bundleDirectoryURL(in: boardDirectoryURL).appendingPathComponent(
            Self.previewFilename
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift
// 函数名: loadPreviewImage(...) / persistDocument(...)
// 功能说明: 阶段2完成态下，store 只能读写 preview.png 和 document.hdraw，没有 backup 读写和整包删除接口。
static func loadPreviewImage(
    documentID: HandDrawingDocumentID,
    boardDirectoryURL: URL
) throws -> CGImage {
    let locator = HandDrawingBundleLocator(documentID: documentID)
    let previewImageURL = locator.previewImageURL(in: boardDirectoryURL)
    let previewImageData = try CoordinatedFileIO.readData(at: previewImageURL)
    return try HandDrawingDocumentCodec.decodePreviewImage(
        from: previewImageData,
        documentID: documentID
    )
}

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
    // 只写 manifest / document / preview
}
```

### 修改后

- `HandDrawingBundleLocator` 新增 `legacyBackupFilename` 以及对应相对路径 / URL。
- `HandDrawingDocumentStore` 新增：
  - `loadPreviewImageData(...)`
  - `loadLegacyBackupDrawingData(...)`
  - `persistDocument(... legacyBackupDrawingData:)`
  - `removeDocumentBundle(...)`
- 这样 migration service 才能：
  - 在迁移成功后把旧 `.pkdrawing` 保存在 bundle 内部
  - 在 bundle `document.hdraw` 损坏时，用 backup 恢复
  - 在迁移失败时删除半成品 bundle

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingBundleLocator.swift
// 函数名: legacyBackupFilename / legacyBackupRelativePath / legacyBackupURL(in:)
// 功能说明: 修改后 bundle 会额外保存 legacy_backup.pkdrawing，作为 migration 成功后的短期兜底源文件。
struct HandDrawingBundleLocator {
    static let handDrawingsDirectoryName = "handdrawings"
    static let bundleFileExtension = "handdraw"
    static let manifestFilename = "manifest.json"
    static let documentFilename = "document.hdraw"
    static let previewFilename = "preview.png"
    static let legacyBackupFilename = "legacy_backup.pkdrawing"

    let documentID: HandDrawingDocumentID

    var legacyBackupRelativePath: String {
        [
            Self.handDrawingsDirectoryName,
            bundleDirectoryName,
            Self.legacyBackupFilename
        ].joined(separator: "/")
    }

    func legacyBackupURL(in boardDirectoryURL: URL) -> URL {
        bundleDirectoryURL(in: boardDirectoryURL).appendingPathComponent(
            Self.legacyBackupFilename
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift
// 函数名: loadPreviewImageData(...) / loadLegacyBackupDrawingData(...) / persistDocument(...legacyBackupDrawingData:) / removeDocumentBundle(...)
// 功能说明: 修改后 store 能单独读取 preview/raw backup，并支持写入 legacy backup 与删除整个 bundle，为迁移回滚和恢复提供基础设施。
static func loadPreviewImageData(
    documentID: HandDrawingDocumentID,
    boardDirectoryURL: URL
) throws -> Data {
    let locator = HandDrawingBundleLocator(documentID: documentID)
    let previewImageURL = locator.previewImageURL(in: boardDirectoryURL)
    guard try CoordinatedFileIO.modificationDate(at: previewImageURL) != nil else {
        throw HandDrawingDocumentStoreError.missingBundleComponent(
            documentID: documentID,
            component: HandDrawingBundleLocator.previewFilename
        )
    }
    return try CoordinatedFileIO.readData(at: previewImageURL)
}

static func loadLegacyBackupDrawingData(
    documentID: HandDrawingDocumentID,
    boardDirectoryURL: URL
) throws -> Data {
    let locator = HandDrawingBundleLocator(documentID: documentID)
    let legacyBackupURL = locator.legacyBackupURL(in: boardDirectoryURL)
    guard try CoordinatedFileIO.modificationDate(at: legacyBackupURL) != nil else {
        throw HandDrawingDocumentStoreError.missingBundleComponent(
            documentID: documentID,
            component: HandDrawingBundleLocator.legacyBackupFilename
        )
    }
    return try CoordinatedFileIO.readData(at: legacyBackupURL)
}

static func persistDocument(
    documentID: HandDrawingDocumentID,
    paper: CanvasHandDrawingPaperSpec,
    contentRevision: UUID,
    isEmpty: Bool,
    drawingData: Data,
    previewImageData: Data?,
    previewCGImage: CGImage?,
    boardDirectoryURL: URL,
    migrationOrigin: HandDrawingManifestMigrationOrigin? = nil,
    legacyBackupDrawingData: Data? = nil
) throws {
    // 其余 manifest/document/preview 写入逻辑省略
    if let legacyBackupDrawingData {
        try CoordinatedFileIO.writeData(
            legacyBackupDrawingData,
            to: locator.legacyBackupURL(in: boardDirectoryURL)
        )
    }
}

static func removeDocumentBundle(
    documentID: HandDrawingDocumentID,
    boardDirectoryURL: URL
) throws {
    let bundleURL = HandDrawingBundleLocator(documentID: documentID)
        .bundleDirectoryURL(in: boardDirectoryURL)
    try CoordinatedFileIO.removeItemIfExists(at: bundleURL)
}
```

## 修改四：board 记录增加 storage 切换辅助 API，避免 migration 过程污染 `board.json`

### 修改前

- `BoardHandDrawingItemRecord` 没有专门的“只替换 storage”的 helper。
- `BoardStore` 也没有“只把某个 handDrawing record 的 storage 更新为 `.bundle` / `.legacyFlatAssetPair`”的 API。
- `normalizePersistedHandDrawingStorage(...)` 只能在整板保存时手工重建一份 record。
- 这意味着 migration service 如果想安全切 storage，只能自己重写一遍 board record 更新逻辑，边界分散。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift / MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardHandDrawingItemRecord / normalizePersistedHandDrawingStorage(in:existingDocument:)
// 功能说明: 阶段2完成态下，storage 归一化只存在于 saveBoard 内部，没有可复用的 record 替换 helper 和定向更新 API。
struct BoardHandDrawingItemRecord: Codable, Equatable {
    // 其余字段省略

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
        let normalizedRecord = BoardHandDrawingItemRecord(
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
        return .handDrawing(normalizedRecord)
    }
}
```

### 修改后

- `BoardHandDrawingItemRecord` 新增 `replacingStorage(with:)`。
- `BoardStore`：
  - 新增 `missingBoardHandDrawingItem(itemID:)`
  - 新增 `updateHandDrawingStorage(...)`
  - `normalizePersistedHandDrawingStorage(...)` 也改为复用 `replacingStorage(with:)`
- 这样 migration service 可以在 bundle 校验成功后，精确更新单个 handDrawing record 的 storage，而不是重写整条 board 保存逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift / MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: replacingStorage(with:) / updateHandDrawingStorage(...) / normalizePersistedHandDrawingStorage(in:existingDocument:)
// 功能说明: 修改后 board record 的 storage 切换被抽成显式 helper 和 store API，migration 成功后才能原子更新 board.json。
struct BoardHandDrawingItemRecord: Codable, Equatable {
    // 其余字段省略

    func replacingStorage(
        with storage: BoardHandDrawingStorageRecord
    ) -> BoardHandDrawingItemRecord {
        BoardHandDrawingItemRecord(
            id: id,
            documentID: documentID,
            center: center,
            size: size,
            zIndex: zIndex,
            paper: paper,
            isEmpty: isEmpty,
            contentRevision: contentRevision,
            rotationRadians: rotationRadians,
            storage: storage
        )
    }
}

enum BoardStoreError: LocalizedError {
    case invalidBoardDirectory
    case invalidBoardImageAsset(filename: String)
    case missingBoardVideoAsset(filename: String)
    case missingBoardHandDrawingSourceAsset(filename: String)
    case missingBoardHandDrawingItem(itemID: CanvasItemID)
    // 其余 error case 省略
}

static func updateHandDrawingStorage(
    boardID: UUID,
    itemID: CanvasItemID,
    storage: BoardHandDrawingStorageRecord,
    userDefaults: UserDefaults = .standard
) throws {
    var document = try readBoardDocument(at: boardDocumentURL)
    var didUpdateRecord = false
    document.items = document.items.map { itemRecord in
        guard case let .handDrawing(record) = itemRecord else {
            return itemRecord
        }
        guard record.id == itemID else {
            return itemRecord
        }

        didUpdateRecord = true
        guard record.storage != storage else {
            return itemRecord
        }
        return .handDrawing(record.replacingStorage(with: storage))
    }
    guard didUpdateRecord else {
        throw BoardStoreError.missingBoardHandDrawingItem(itemID: itemID)
    }

    let encodedDocument = try makeDocumentData(for: document)
    try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
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
        return .handDrawing(record.replacingStorage(with: resolvedStorage))
    }
}
```

## 修改五：补 migration 定点测试，覆盖迁移成功、回滚、backup 恢复和 session 入口

### 修改前

- 阶段 2 没有专门的 migration 测试文件。
- 只能证明：
  - bundle save/load 正常
  - legacy flat asset fallback 正常
- 但还不能证明：
  - 首次编辑 legacy 时会真正切到 `.bundle`
  - legacy 数据损坏时不会污染 board 记录
  - bundle 损坏后是否能从 `legacy_backup.pkdrawing` 恢复
  - `CanvasEditorSession.handDrawingEditorContext(...)` 是否已经把 migration 接进编辑入口

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
// 函数名: 无
// 功能说明: 阶段2完成态下还没有 migration service 专用测试文件。
// 修改前不存在该文件。
```

### 修改后

- 新增 `HandDrawingMigrationServiceTests.swift`，覆盖四类场景：
  - `testHandDrawingMigrationServiceMigratesLegacyFlatAssetsOnDemand`
  - `testHandDrawingMigrationServiceRollsBackWhenLegacyDrawingIsInvalid`
  - `testHandDrawingMigrationServiceRestoresBundleDocumentFromLegacyBackup`
  - `testCanvasEditorSessionHandDrawingEditorContextMigratesLegacyDocumentBeforeOpen`
- 另外在 session 集成测试中新增 `HandDrawingMigrationServiceTestRetainer.sessions`：
  - 目的是避免 `CanvasEditorSession` 在用例结束时过早释放，撞到当前工程已有的异步 preview 析构问题。
  - 这和现有 `CanvasHandDrawingEditingSessionTests` 的保活策略保持一致。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
// 函数名: testHandDrawingMigrationServiceMigratesLegacyFlatAssetsOnDemand() / testHandDrawingMigrationServiceRollsBackWhenLegacyDrawingIsInvalid() / testHandDrawingMigrationServiceRestoresBundleDocumentFromLegacyBackup() / testCanvasEditorSessionHandDrawingEditorContextMigratesLegacyDocumentBeforeOpen()
// 功能说明: 修改后新增 migration service 专用测试，验证按需迁移、失败回滚、backup 恢复以及 session 入口级 migration。
final class HandDrawingMigrationServiceTests: XCTestCase {
    func testHandDrawingMigrationServiceMigratesLegacyFlatAssetsOnDemand() throws {
        let preparedDocument = try HandDrawingMigrationService.prepareDocumentForEditing(
            boardID: fixture.boardID,
            itemID: fixture.itemID,
            userDefaults: userDefaults
        )

        XCTAssertEqual(preparedDocument.record.storage, .bundle)
        XCTAssertTrue(preparedDocument.didMigrateLegacyDocument)
        XCTAssertEqual(
            try HandDrawingDocumentStore.loadLegacyBackupDrawingData(
                documentID: fixture.documentID,
                boardDirectoryURL: fixture.boardDirectoryURL
            ),
            fixture.drawingData
        )
    }

    func testHandDrawingMigrationServiceRollsBackWhenLegacyDrawingIsInvalid() throws {
        XCTAssertThrowsError(
            try HandDrawingMigrationService.prepareDocumentForEditing(
                boardID: fixture.boardID,
                itemID: fixture.itemID,
                userDefaults: userDefaults
            )
        )
        XCTAssertEqual(
            entry.document.handDrawingItemRecords.first?.storage,
            .legacyFlatAssetPair
        )
        XCTAssertNil(
            try CoordinatedFileIO.modificationDate(
                at: HandDrawingBundleLocator(documentID: fixture.documentID)
                    .bundleDirectoryURL(in: fixture.boardDirectoryURL)
            )
        )
    }

    func testCanvasEditorSessionHandDrawingEditorContextMigratesLegacyDocumentBeforeOpen() throws {
        let session = CanvasEditorSession(
            saveQueueLabel: "HandDrawingMigrationServiceTests.Session",
            logPrefix: "[HandDrawingMigrationServiceTests]",
            userDefaults: userDefaults
        )
        HandDrawingMigrationServiceTestRetainer.sessions.append(session)

        try session.loadBoard(id: fixture.boardID)
        let firstContext = try session.handDrawingEditorContext(for: fixture.itemID)
        let secondContext = try session.handDrawingEditorContext(for: fixture.itemID)

        XCTAssertEqual(firstContext.storage, .bundle)
        XCTAssertTrue(firstContext.didMigrateLegacyDocument)
        XCTAssertEqual(secondContext.storage, .bundle)
        XCTAssertFalse(secondContext.didMigrateLegacyDocument)
    }
}

private enum HandDrawingMigrationServiceTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}
```

## 结果小结

- 阶段 3 完成后，旧 `.pkdrawing` handDrawing 不需要批量升级；在首次打开编辑器时才会按需迁移到 bundle。
- 迁移链路现在具备“先写 bundle、再切 board storage”的原子边界；失败时会清掉半成品 bundle，不会污染 `board.json`。
- bundle 内会额外保留 `legacy_backup.pkdrawing`，使后续 `document.hdraw` 损坏时仍然有恢复入口。
- `CanvasEditorSession` 的 handDrawing 编辑入口已经不再只是“读 source data”，而是显式拿到 migration 后的可编辑文档状态。
