# 20260324_105233_gif_phase3_storage_v4_record

## 记录范围

- 记录内容：
  1. 将 `BoardDocument` 升级到 `v4`，让图片记录显式保存 `assetKind`。
  2. 为图片资产模型补齐稳定落盘文件名规则，避免存储层继续写死 `"\(item.id).png"`。
  3. 改造 `BoardDocumentMapper`，让运行时图片项与“落盘文件名 / 资源类型”解耦。
  4. 改造保存链路，让 `CanvasEditorSession -> BoardSaveCoordinator -> BoardStore` 在保存时携带 transient GIF 原始资源数据。
  5. 改造 `BoardStore`，静态图继续持久化为 `.png`，GIF 则保留原始 `.gif` 文件，并按唯一资产文件集合去重落盘。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageAsset.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
- 本记录不包含：
  - 阶段 0 语义契约
  - 阶段 1 资产模型拆分
  - 阶段 2 导入原始资源保留
  - 阶段 4 渲染契约收口
  - 阶段 5 GIF 自动播放
  - git commit / push

## 修改一：图片资产补齐“稳定落盘文件名”与“后缀推断资源类型”规则

### 修改前

- `CanvasImageAssetKind` 只有 `isAnimated` 语义。
- `CanvasImageAssetReference` 只有 `transient(...)` / `persisted(...)` 构造入口，没有统一的稳定文件名规则。
- 结果是存储层只能在外部手写 `"\(item.id).png"`，GIF 没有统一落盘命名边界。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageAsset.swift
// 函数名: isAnimated / transient(kind:assetID:) / persisted(kind:filename:)
// 功能说明: 修改前图片资产只表达资源种类与存储位置，具体保存成什么文件名、什么后缀，仍由存储层外部硬编码决定。
enum CanvasImageAssetKind: String, Codable, Equatable, Hashable {
    case staticImage
    case animatedGIF

    var isAnimated: Bool {
        self == .animatedGIF
    }
}

struct CanvasImageAssetReference: Equatable, Hashable {
    let kind: CanvasImageAssetKind
    let storage: CanvasImageAssetStorage

    static func transient(
        kind: CanvasImageAssetKind,
        assetID: UUID = UUID()
    ) -> CanvasImageAssetReference {
        CanvasImageAssetReference(
            kind: kind,
            storage: .transient(assetID)
        )
    }

    static func persisted(
        kind: CanvasImageAssetKind,
        filename: String
    ) -> CanvasImageAssetReference {
        CanvasImageAssetReference(
            kind: kind,
            storage: .persisted(filename: filename)
        )
    }
}
```

### 修改后

- `CanvasImageAssetKind` 新增 `preferredPersistedFileExtension`，把“静态图写 `.png`、GIF 写 `.gif`”的规则收口到资产类型自身。
- 新增 `inferredPersistedKind(from:)`，用于旧文档没有 `assetKind` 时从文件名后缀反推资源类型。
- `CanvasImageAssetReference` 新增 `stableAssetFilename`，让 transient 资产也能得到稳定的目标文件名。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageAsset.swift
// 函数名: preferredPersistedFileExtension / inferredPersistedKind(from:) / stableAssetFilename
// 功能说明: 修改后图片资产模型自己定义“应该落成什么后缀”和“如何生成稳定文件名”，存储层不再散落 .png 假设。
enum CanvasImageAssetKind: String, Codable, Equatable, Hashable {
    case staticImage
    case animatedGIF

    var isAnimated: Bool {
        self == .animatedGIF
    }

    var preferredPersistedFileExtension: String {
        switch self {
        case .staticImage:
            return "png"
        case .animatedGIF:
            return "gif"
        }
    }

    static func inferredPersistedKind(
        from filename: String
    ) -> CanvasImageAssetKind {
        let pathExtension = URL(fileURLWithPath: filename)
            .pathExtension
            .lowercased()
        switch pathExtension {
        case "gif":
            return .animatedGIF
        default:
            return .staticImage
        }
    }
}

struct CanvasImageAssetReference: Equatable, Hashable {
    let kind: CanvasImageAssetKind
    let storage: CanvasImageAssetStorage

    var stableAssetFilename: String {
        switch storage {
        case let .transient(assetID):
            return "\(assetID.uuidString).\(kind.preferredPersistedFileExtension)"
        case let .persisted(filename):
            return filename
        }
    }
}
```

## 修改二：`BoardDocument` 从 v3 升级到 v4，图片记录开始显式保存 `assetKind`

### 修改前

- `BoardDocument.currentFormatVersion` 仍是 `3`。
- `BoardImageItemRecord` 只有 `assetFilename`，没有 `assetKind` 字段。
- 旧逻辑隐含前提是“所有落盘图片都是 `.png` 静态图”，因此 `Codable` 也不需要做类型兼容推断。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: currentFormatVersion / BoardImageItemRecord 字段定义
// 功能说明: 修改前 board.json 仍是 v3，图片记录只保存 assetFilename，无法显式区分静态图和 GIF 资产。
struct BoardDocument: Codable {
    static let currentFormatVersion = 3
    static let targetFormatVersionForImageAssets =
        CanvasImageAssetContract.current.targetDocumentFormatVersion
    static let defaultTitle = "Untitled Board"

    let formatVersion: Int
    // ... 其他字段 ...
}

struct BoardImageItemRecord: Codable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var assetFilename: String
    var cropRectNormalized: BoardImageCropRecord?
    var rotationRadians: Double?
}
```

### 修改后

- `BoardDocument.currentFormatVersion` 升到 `CanvasImageAssetContract.current.targetDocumentFormatVersion`，当前即 `4`。
- `BoardImageItemRecord` 新增 `assetKind`。
- 增加自定义 `init(from:)` / `encode(to:)`：
  - 新文档会显式写出 `assetKind`
  - 旧文档缺少 `assetKind` 时，会通过文件名后缀推断 GIF 或静态图，保证 `v2/v3` 兼容打开
- 新增 `assetReference` 计算属性，供 mapper / store 统一复用。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: currentFormatVersion / init(from:) / encode(to:) / assetReference
// 功能说明: 修改后 board.json 升为 v4，图片记录显式持久化 assetKind；旧文档缺字段时仍可通过文件名后缀推断资源类型。
struct BoardDocument: Codable {
    static let currentFormatVersion =
        CanvasImageAssetContract.current.targetDocumentFormatVersion
    static let targetFormatVersionForImageAssets = currentFormatVersion
    static let defaultTitle = "Untitled Board"

    let formatVersion: Int
    // ... 其他字段 ...
}

struct BoardImageItemRecord: Codable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var assetFilename: String
    var assetKind: CanvasImageAssetKind
    var cropRectNormalized: BoardImageCropRecord?
    var rotationRadians: Double?

    init(
        id: UUID,
        center: BoardPointRecord,
        size: BoardSizeRecord,
        zIndex: Double,
        assetFilename: String,
        assetKind: CanvasImageAssetKind = .staticImage,
        cropRectNormalized: BoardImageCropRecord?,
        rotationRadians: Double?
    ) {
        self.id = id
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.assetFilename = assetFilename
        self.assetKind = assetKind
        self.cropRectNormalized = cropRectNormalized
        self.rotationRadians = rotationRadians
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        center = try container.decode(BoardPointRecord.self, forKey: .center)
        size = try container.decode(BoardSizeRecord.self, forKey: .size)
        zIndex = try container.decode(Double.self, forKey: .zIndex)
        assetFilename = try container.decode(String.self, forKey: .assetFilename)
        assetKind = try container.decodeIfPresent(
            CanvasImageAssetKind.self,
            forKey: .assetKind
        ) ?? CanvasImageAssetKind.inferredPersistedKind(from: assetFilename)
        cropRectNormalized = try container.decodeIfPresent(
            BoardImageCropRecord.self,
            forKey: .cropRectNormalized
        )
        rotationRadians = try container.decodeIfPresent(
            Double.self,
            forKey: .rotationRadians
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(center, forKey: .center)
        try container.encode(size, forKey: .size)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(assetFilename, forKey: .assetFilename)
        try container.encode(assetKind, forKey: .assetKind)
        try container.encodeIfPresent(cropRectNormalized, forKey: .cropRectNormalized)
        try container.encodeIfPresent(rotationRadians, forKey: .rotationRadians)
    }

    var assetReference: CanvasImageAssetReference {
        .persisted(
            kind: assetKind,
            filename: assetFilename
        )
    }
}
```

## 修改三：`BoardDocumentMapper` 不再把图片资产文件名写死为 `item.id.png`

### 修改前

- `makeRuntimeState(...)` 恢复运行时图片项时，固定使用 `CanvasImageAsset.persistedStaticImage(...)`。
- `makeImageRecord(...)` 保存图片记录时，固定写 `assetFilename: "\(item.id.uuidString).png"`。
- 这意味着 mapper 层默认所有图片持久化结果都是静态 PNG，GIF 资产类型和共享文件名都无法表达。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:) / makeImageRecord(from:)
// 功能说明: 修改前 mapper 既把加载路径锁死成 persisted static image，也把保存文件名锁死成 item.id.png。
static func makeRuntimeState(
    from document: BoardDocument,
    imageLoader: (BoardImageItemRecord) throws -> CGImage
) throws -> BoardRuntimeState {
    let items = try document.items.map { itemRecord in
        switch itemRecord {
        case let .image(imageRecord):
            return CanvasBoardItem.image(
                CanvasImageItem(
                    id: imageRecord.id,
                    asset: CanvasImageAsset.persistedStaticImage(
                        filename: imageRecord.assetFilename,
                        cgImage: try imageLoader(imageRecord)
                    ),
                    center: imageRecord.center.cgPoint,
                    size: imageRecord.size.cgSize,
                    zIndex: CGFloat(imageRecord.zIndex),
                    cropRectNormalized: imageRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
                    rotationRadians: CGFloat(imageRecord.rotationRadians ?? 0)
                )
            )
        // ... 其他分支 ...
        }
    }
    // ...
}

private static func makeImageRecord(from item: CanvasImageItem) -> BoardImageItemRecord {
    BoardImageItemRecord(
        id: item.id,
        center: BoardPointRecord(item.center),
        size: BoardSizeRecord(item.size),
        zIndex: Double(item.zIndex),
        assetFilename: "\(item.id.uuidString).png",
        cropRectNormalized: BoardImageCropRecord(item.cropRectNormalized),
        rotationRadians: Double(item.rotationRadians)
    )
}
```

### 修改后

- `makeRuntimeState(...)` 改为使用 `CanvasImageAsset.persistedImage(kind:filename:cgImage:)`，让运行时恢复时能保留 GIF / 静态图类型。
- `makeImageRecord(...)` 改为写入：
  - `assetFilename: item.assetReference.stableAssetFilename`
  - `assetKind: item.assetKind`
- 这样 mapper 不再把存储层强耦合到 `item.id.png`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:) / makeImageRecord(from:)
// 功能说明: 修改后 mapper 通过 assetReference 恢复和生成图片记录，文件名与资源类型都从资产模型读取，而不再硬编码 PNG 约定。
static func makeRuntimeState(
    from document: BoardDocument,
    imageLoader: (BoardImageItemRecord) throws -> CGImage
) throws -> BoardRuntimeState {
    let items = try document.items.map { itemRecord in
        switch itemRecord {
        case let .image(imageRecord):
            return CanvasBoardItem.image(
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
            )
        // ... 其他分支 ...
        }
    }
    // ...
}

private static func makeImageRecord(from item: CanvasImageItem) -> BoardImageItemRecord {
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
}
```

## 修改四：保存协调器与 EditorSession 改为传递 `BoardSaveSnapshot`

### 修改前

- `BoardSaveCoordinator` 的输入只有 `BoardRuntimeState`。
- `CanvasEditorSession.scheduleAutosave(...)` / `saveBoardNow(...)` 只会采集 `currentBoardRuntimeState(...)`。
- 这样保存链路在进入 `BoardStore` 前已经丢失了阶段 2 挂在 session 里的 transient GIF 原始资源数据。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift
// 函数名: scheduleAutosave(snapshot:reason:onFailure:) / saveImmediately(snapshot:reason:completion:)
// 功能说明: 修改前保存协调器只接收 BoardRuntimeState，无法携带 transient 图片资源 payload。
final class BoardSaveCoordinator {
    func scheduleAutosave(
        snapshot: BoardRuntimeState,
        reason: String,
        onFailure: ((Error) -> Void)? = nil
    ) {
        // ...
    }

    func saveImmediately(
        snapshot: BoardRuntimeState,
        reason: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // ...
    }

    private func enqueueSave(
        snapshot: BoardRuntimeState,
        reason: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        saveQueue.async { [logPrefix] in
            try BoardStore.saveBoard(snapshot)
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: scheduleAutosave(reason:) / saveBoardNow(reason:createBoardIfNeeded:completion:) / currentBoardRuntimeState(createBoardIfNeeded:)
// 功能说明: 修改前 EditorSession 只向保存层传递运行时 board 状态，不会把当前仍被引用的 transient 资源一起打包。
func scheduleAutosave(reason: String) {
    guard let snapshot = currentBoardRuntimeState() else {
        return
    }

    saveCoordinator.scheduleAutosave(
        snapshot: snapshot,
        reason: reason
    )
}

func saveBoardNow(
    reason: String,
    createBoardIfNeeded: Bool = false,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    guard let snapshot = currentBoardRuntimeState(createBoardIfNeeded: createBoardIfNeeded) else {
        completion(.failure(FolderBookmarkStoreError.missingBookmarkData))
        return
    }

    saveCoordinator.saveImmediately(
        snapshot: snapshot,
        reason: reason,
        completion: completion
    )
}
```

### 修改后

- 新增 `BoardSaveSnapshot`，把：
  - `runtimeState`
  - `transientImageAssetPayloads`
 统一作为保存输入。
- `CanvasEditorSession` 新增 `currentBoardSaveSnapshot(...)`，只收集当前 board 里仍被引用的图片资产 payload，避免把已删除 item 的大文件继续传入保存队列。
- 自动保存和手动保存都统一走新的 save snapshot。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift
// 函数名: BoardSaveSnapshot.init(...) / transientImageAssetPayload(for:) / scheduleAutosave(snapshot:reason:onFailure:)
// 功能说明: 修改后保存协调器接收 BoardSaveSnapshot，让存储层能同时拿到运行时 board 状态和 transient GIF 原始资源数据。
struct BoardSaveSnapshot {
    let runtimeState: BoardRuntimeState
    let transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload]

    init(
        runtimeState: BoardRuntimeState,
        transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload] = [:]
    ) {
        self.runtimeState = runtimeState
        self.transientImageAssetPayloads = transientImageAssetPayloads
    }

    func transientImageAssetPayload(
        for assetReference: CanvasImageAssetReference
    ) -> CanvasTransientImageAssetPayload? {
        transientImageAssetPayloads[assetReference]
    }
}

final class BoardSaveCoordinator {
    func scheduleAutosave(
        snapshot: BoardSaveSnapshot,
        reason: String,
        onFailure: ((Error) -> Void)? = nil
    ) {
        // ...
    }

    func saveImmediately(
        snapshot: BoardSaveSnapshot,
        reason: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // ...
    }

    private func enqueueSave(
        snapshot: BoardSaveSnapshot,
        reason: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        saveQueue.async { [logPrefix] in
            try BoardStore.saveBoard(snapshot)
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: scheduleAutosave(reason:) / saveBoardNow(reason:createBoardIfNeeded:completion:) / currentBoardSaveSnapshot(createBoardIfNeeded:)
// 功能说明: 修改后 EditorSession 会把当前 board 引用到的 transient 图片资源一起打包进保存快照，GIF 原始数据不会在保存入口丢失。
func scheduleAutosave(reason: String) {
    guard let snapshot = currentBoardSaveSnapshot() else {
        return
    }

    saveCoordinator.scheduleAutosave(
        snapshot: snapshot,
        reason: reason
    )
}

func saveBoardNow(
    reason: String,
    createBoardIfNeeded: Bool = false,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    guard let snapshot = currentBoardSaveSnapshot(createBoardIfNeeded: createBoardIfNeeded) else {
        completion(.failure(FolderBookmarkStoreError.missingBookmarkData))
        return
    }

    saveCoordinator.saveImmediately(
        snapshot: snapshot,
        reason: reason,
        completion: completion
    )
}

func currentBoardSaveSnapshot(
    createBoardIfNeeded: Bool = false
) -> BoardSaveSnapshot? {
    guard let runtimeState = currentBoardRuntimeState(
        createBoardIfNeeded: createBoardIfNeeded
    ) else {
        return nil
    }

    let referencedAssetReferences = Set(
        runtimeState.imageItems.map(\.assetReference)
    )
    let payloads = Dictionary(
        uniqueKeysWithValues: transientImageAssetPayloads.filter {
            referencedAssetReferences.contains($0.key)
        }
    )
    return BoardSaveSnapshot(
        runtimeState: runtimeState,
        transientImageAssetPayloads: payloads
    )
}
```

## 修改五：`BoardStore` 从“逐 item 导出 PNG”改为“按唯一资产文件集合去重落盘”

### 修改前

- `saveBoard(_ runtimeState:)` 直接遍历 `persistedState.imageItems`。
- 每个图片 item 都写入 `assets/\(item.id.uuidString).png`。
- 写盘逻辑统一调用 `makePNGData(...)`，这意味着 GIF 即便进入了运行时，也会在保存时再次被降格成 PNG。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: saveBoard(_:) / makePNGData(for:itemID:)
// 功能说明: 修改前 BoardStore 默认每个图片 item 各写一份 PNG 文件，无法表达“多个 item 共享同一资源”以及“GIF 保留原始 .gif 文件”。
static func saveBoard(
    _ runtimeState: BoardRuntimeState,
    userDefaults: UserDefaults = .standard
) throws {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        // ...
        var persistedState = runtimeState
        persistedState.updatedAt = Date()
        let document = BoardDocumentMapper.makeDocument(from: persistedState)

        for item in persistedState.imageItems {
            let assetURL = assetsDirectoryURL.appendingPathComponent(
                "\(item.id.uuidString).png"
            )
            let pngData = try makePNGData(
                for: item.posterCGImage,
                itemID: item.id
            )
            try CoordinatedFileIO.writeData(pngData, to: assetURL)
        }

        try removeOrphanedAssets(
            keeping: Set(document.imageItemRecords.map(\.assetFilename)),
            in: assetsDirectoryURL
        )
        // ...
    }
}
```

### 修改后

- `BoardStoreError` 新增 `missingAnimatedImageSource(itemID:)`，用于显式报告“当前 GIF 缺少可落盘原始资源”。
- 新增 `saveBoard(_ snapshot: BoardSaveSnapshot, ...)` 主入口：
  - 先生成 `persistedState`
  - 再生成 `persistedSnapshot`
  - 再根据 `item.assetReference.stableAssetFilename` 去重落盘
- 新增 `persistImageAssetIfNeeded(...)`：
  - `staticImage` 继续编码成 `.png`
  - `animatedGIF` 直接写入 `snapshot.transientImageAssetPayload(...).source.data`
- 保留原有 `saveBoard(_ runtimeState: BoardRuntimeState, ...)` 重载，作为兼容包装层。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardStoreError.missingAnimatedImageSource / saveBoard(_ snapshot:userDefaults:) / saveBoard(_ runtimeState:userDefaults:)
// 功能说明: 修改后 BoardStore 的主保存入口接收 BoardSaveSnapshot，并按稳定资产文件名去重写盘，而不是继续对每个 item 固定导出 PNG。
enum BoardStoreError: LocalizedError {
    case invalidBoardDirectory
    case invalidBoardImageAsset(filename: String)
    case failedToEncodeImageAsset(itemID: UUID)
    case missingAnimatedImageSource(itemID: UUID)
}

static func saveBoard(
    _ snapshot: BoardSaveSnapshot,
    userDefaults: UserDefaults = .standard
) throws {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        // ...
        var persistedState = snapshot.runtimeState
        persistedState.updatedAt = Date()
        let persistedSnapshot = BoardSaveSnapshot(
            runtimeState: persistedState,
            transientImageAssetPayloads: snapshot.transientImageAssetPayloads
        )
        let document = BoardDocumentMapper.makeDocument(from: persistedState)

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
        // ...
    }
}

static func saveBoard(
    _ runtimeState: BoardRuntimeState,
    userDefaults: UserDefaults = .standard
) throws {
    try saveBoard(
        BoardSaveSnapshot(runtimeState: runtimeState),
        userDefaults: userDefaults
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: persistImageAssetIfNeeded(for:snapshot:to:)
// 功能说明: 修改后静态图继续保存 PNG，GIF 则保留原始 .gif 数据；当多个 item 共享同一资产文件名时只写一次。
private static func persistImageAssetIfNeeded(
    for item: CanvasImageItem,
    snapshot: BoardSaveSnapshot,
    to assetURL: URL
) throws {
    if FileManager.default.fileExists(atPath: assetURL.path) {
        return
    }

    switch item.assetKind {
    case .staticImage:
        let pngData = try makePNGData(
            for: item.posterCGImage,
            itemID: item.id
        )
        try CoordinatedFileIO.writeData(pngData, to: assetURL)
    case .animatedGIF:
        guard
            let assetData = snapshot.transientImageAssetPayload(
                for: item.assetReference
            )?.source?.data
        else {
            throw BoardStoreError.missingAnimatedImageSource(itemID: item.id)
        }
        try CoordinatedFileIO.writeData(assetData, to: assetURL)
    }
}
```

## 阶段 3 完成状态

- 已完成：
  - `board.json` 升级到 `v4`
  - 图片记录显式保存 `assetKind`
  - 旧版 `v2/v3` 文档可通过文件名后缀兼容恢复图片资源类型
  - mapper 不再把图片文件名写死为 `item.id.png`
  - 保存链路能携带 transient GIF 原始资源数据
  - `BoardStore` 能按唯一资产文件集合去重落盘
  - 静态图继续写 `.png`
  - GIF 保存为原始 `.gif`
- 未完成：
  - 渲染层的 GIF 展示契约收口
  - `CanvasImageLayer` 的 GIF 帧更新接管
  - 主画布自动播放 GIF
  - board list / minimap / persisted thumbnail 的 GIF 首帧策略收尾验证
