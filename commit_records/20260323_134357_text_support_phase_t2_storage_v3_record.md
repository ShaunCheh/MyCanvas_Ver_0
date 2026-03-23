# 20260323_134357_text_support_phase_t2_storage_v3_record

## 记录范围

- 记录内容：
  1. 将 `BoardDocument` 从 `v2 image-only` 升级到 `v3 mixed-item` 持久化格式。
  2. 在文档层新增 `BoardTextColorRecord`、`BoardTextStyleRecord`、`BoardTextItemRecord`、`BoardItemRecord`，让 text item 可以进入 `board.json`。
  3. 在 `BoardItemRecord` 中加入 `v2 -> v3` 的兼容解码逻辑，保证旧图片文档仍可读取。
  4. 更新 `BoardDocumentMapper`，让 mixed runtime 能双向映射到 mixed persisted schema。
  5. 更新 `BoardStore`、`BoardGeometryPreviewBuilder`、`BoardThumbnailRenderer`，把存储/预览链路适配到新文档结构。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
- 本记录不包含：
  - 文本渲染、文本 layer、文本 hit-test
  - 文本创建命令、inline edit 状态、工具栏按钮
  - minimap / board list preview 的文本绘制风格
  - 原始 gif diff
  - git commit / push

## 修改一：`BoardDocument` 升级到 `v3 mixed-item` 文档格式，并兼容 `v2`

### 修改前

- `board.json` 仍是 `v2`，`items` 只能保存 `BoardImageItemRecord`。
- 仓库里还没有文本记录类型，也没有 `type` tag 驱动的 mixed item schema。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: N/A（BoardDocument / BoardImageItemRecord 类型定义）
// 功能说明: 修改前文档格式仍停留在 v2，items 只能存图片记录；board.json 还不能表达 text item。
struct BoardDocument: Codable {
    static let currentFormatVersion = 2
    static let defaultTitle = "Untitled Board"

    let formatVersion: Int
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var boardBaseSize: BoardSizeRecord?
    var boardRect: BoardRectRecord?
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double
    var selectedItemID: UUID?
    var items: [BoardImageItemRecord]
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

```text
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: N/A（类型定义文件）
// 功能说明: 修改前仓库中不存在 `BoardTextColorRecord`、`BoardTextStyleRecord`、`BoardTextItemRecord`、`BoardItemRecord`；
//           旧文档数组也没有 `type` 标记或 `v2` 兼容解码桥。
[类型不存在]
```

### 修改后

- `BoardDocument.currentFormatVersion` 升级到 `3`，并将 `items` 改为 `[BoardItemRecord]`。
- 新增文本记录类型与 `imageItemRecords` / `textItemRecords` 投影，方便存储链路按需消费。
- `BoardItemRecord` 使用 tagged schema 持久化 mixed items，同时在 `init(from:)` 中保留旧 `v2` 图片记录的兜底解码。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: N/A（BoardDocument / BoardTextItemRecord / 投影属性）
// 功能说明: 修改后文档格式切到 v3，items 统一改为 mixed item record；同时保留 image/text 投影，供资产写入与缩略图链路继续按类型消费。
struct BoardDocument: Codable {
    static let currentFormatVersion = 3
    static let defaultTitle = "Untitled Board"

    let formatVersion: Int
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var boardBaseSize: BoardSizeRecord?
    var boardRect: BoardRectRecord?
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double
    var selectedItemID: UUID?
    var items: [BoardItemRecord]

    var imageItemRecords: [BoardImageItemRecord] {
        items.compactMap(\.imageItemRecord)
    }

    var textItemRecords: [BoardTextItemRecord] {
        items.compactMap(\.textItemRecord)
    }
}

struct BoardTextColorRecord: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: CanvasTextColor) {
        self.init(
            red: Double(color.red),
            green: Double(color.green),
            blue: Double(color.blue),
            alpha: Double(color.alpha)
        )
    }

    var canvasTextColor: CanvasTextColor {
        CanvasTextColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

struct BoardTextStyleRecord: Codable {
    var fontName: String
    var fontSize: Double
    var color: BoardTextColorRecord

    init(_ style: CanvasTextStyle) {
        self.init(
            fontName: style.fontName,
            fontSize: Double(style.fontSize),
            color: BoardTextColorRecord(style.color)
        )
    }
}

struct BoardTextItemRecord: Codable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var text: String
    var style: BoardTextStyleRecord
    var rotationRadians: Double?
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: init(from:) / encode(to:)（BoardItemRecord）
// 功能说明: 修改后 board.json 的 item 先用 `type` 区分 image/text；如果读到旧 v2 文档里没有 `type` 的图片记录，则自动回落到 `.image(...)`。
enum BoardItemRecord: Codable {
    case image(BoardImageItemRecord)
    case text(BoardTextItemRecord)

    private enum CodingKeys: String, CodingKey {
        case type
        case image
        case text
    }

    private enum ItemType: String, Codable {
        case image
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let type = try container.decodeIfPresent(ItemType.self, forKey: .type) {
            switch type {
            case .image:
                self = .image(
                    try container.decode(
                        BoardImageItemRecord.self,
                        forKey: .image
                    )
                )
            case .text:
                self = .text(
                    try container.decode(
                        BoardTextItemRecord.self,
                        forKey: .text
                    )
                )
            }
            return
        }

        // v2 documents stored plain image records without a type tag.
        self = .image(try BoardImageItemRecord(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .image(record):
            try container.encode(ItemType.image, forKey: .type)
            try container.encode(record, forKey: .image)
        case let .text(record):
            try container.encode(ItemType.text, forKey: .type)
            try container.encode(record, forKey: .text)
        }
    }
}
```

## 修改二：`BoardDocumentMapper` 从 image-only 映射改为 mixed item 双向映射

### 修改前

- `makeDocument(from:)` 只会把 `runtimeState.imageItems` 写回文档。
- `makeRuntimeState(from:imageLoader:)` 也只会把 `BoardImageItemRecord` 还原成 `.image(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeDocument(from:) / makeRuntimeState(from:imageLoader:)
// 功能说明: 修改前 mapper 仍停留在 image-only 持久化阶段，T-1 通过 assert 明确拒绝非图片项写入旧文档格式。
enum BoardDocumentMapper {
    static func makeDocument(from runtimeState: BoardRuntimeState) -> BoardDocument {
        let imageItems = runtimeState.imageItems
        assert(
            imageItems.count == runtimeState.items.count,
            "BoardDocument v2 can only persist image items before T-2."
        )

        return BoardDocument(
            formatVersion: BoardDocument.currentFormatVersion,
            boardID: runtimeState.boardID,
            title: runtimeState.title,
            createdAt: runtimeState.createdAt,
            updatedAt: runtimeState.updatedAt,
            boardBaseSize: runtimeState.boardState.map { BoardSizeRecord($0.baseSize) },
            boardRect: runtimeState.boardState.map { BoardRectRecord($0.worldRect) },
            cameraCenter: BoardPointRecord(runtimeState.camera.center),
            cameraZoomScale: Double(runtimeState.camera.zoomScale),
            selectedItemID: runtimeState.interactionState.selectedItemID,
            items: imageItems.map(makeImageRecord)
        )
    }

    static func makeRuntimeState(
        from document: BoardDocument,
        imageLoader: (BoardImageItemRecord) throws -> CGImage
    ) throws -> BoardRuntimeState {
        let items = try document.items.map { itemRecord in
            CanvasBoardItem.image(
                CanvasImageItem(
                    id: itemRecord.id,
                    cgImage: try imageLoader(itemRecord),
                    center: itemRecord.center.cgPoint,
                    size: itemRecord.size.cgSize,
                    zIndex: CGFloat(itemRecord.zIndex),
                    cropRectNormalized: itemRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
                    rotationRadians: CGFloat(itemRecord.rotationRadians ?? 0)
                )
            )
        }

        // ... 省略其余 runtimeState 构造代码 ...
    }
}
```

### 修改后

- `makeDocument(from:)` 直接把 `runtimeState.items` 下沉为 `[BoardItemRecord]`。
- `makeRuntimeState(from:imageLoader:)` 按 item 类型分别恢复 `.image(...)` 与 `.text(...)`。
- 新增 `makeItemRecord(from:)` / `makeTextRecord(from:)`，让 mixed runtime 和 mixed persisted schema 正式双向贯通。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeDocument(from:) / makeRuntimeState(from:imageLoader:)
// 功能说明: 修改后 mapper 正式接受 mixed runtime，并在加载时按 image/text 两种 persisted item 还原运行时对象。
enum BoardDocumentMapper {
    static func makeDocument(from runtimeState: BoardRuntimeState) -> BoardDocument {
        return BoardDocument(
            formatVersion: BoardDocument.currentFormatVersion,
            boardID: runtimeState.boardID,
            title: runtimeState.title,
            createdAt: runtimeState.createdAt,
            updatedAt: runtimeState.updatedAt,
            boardBaseSize: runtimeState.boardState.map { BoardSizeRecord($0.baseSize) },
            boardRect: runtimeState.boardState.map { BoardRectRecord($0.worldRect) },
            cameraCenter: BoardPointRecord(runtimeState.camera.center),
            cameraZoomScale: Double(runtimeState.camera.zoomScale),
            selectedItemID: runtimeState.interactionState.selectedItemID,
            items: runtimeState.items.map(makeItemRecord)
        )
    }

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
                        cgImage: try imageLoader(imageRecord),
                        center: imageRecord.center.cgPoint,
                        size: imageRecord.size.cgSize,
                        zIndex: CGFloat(imageRecord.zIndex),
                        cropRectNormalized: imageRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
                        rotationRadians: CGFloat(imageRecord.rotationRadians ?? 0)
                    )
                )
            case let .text(textRecord):
                return CanvasBoardItem.text(
                    CanvasTextItem(
                        id: textRecord.id,
                        text: textRecord.text,
                        style: textRecord.style.canvasTextStyle,
                        center: textRecord.center.cgPoint,
                        size: textRecord.size.cgSize,
                        zIndex: CGFloat(textRecord.zIndex),
                        rotationRadians: CGFloat(textRecord.rotationRadians ?? 0)
                    )
                )
            }
        }

        // ... 省略其余 runtimeState 构造代码 ...
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeItemRecord(from:) / makeTextRecord(from:)
// 功能说明: 修改后 image 与 text 都有明确的 record 生成入口，避免把 mixed item 的分支逻辑散落到主流程里。
private static func makeItemRecord(from item: CanvasBoardItem) -> BoardItemRecord {
    switch item {
    case let .image(imageItem):
        return .image(makeImageRecord(from: imageItem))
    case let .text(textItem):
        return .text(makeTextRecord(from: textItem))
    }
}

private static func makeTextRecord(from item: CanvasTextItem) -> BoardTextItemRecord {
    BoardTextItemRecord(
        id: item.id,
        center: BoardPointRecord(item.center),
        size: BoardSizeRecord(item.size),
        zIndex: Double(item.zIndex),
        text: item.text,
        style: BoardTextStyleRecord(item.style),
        rotationRadians: Double(item.rotationRadians)
    )
}
```

## 修改三：`BoardStore.saveBoard(_:)` 保持图片资产写入边界，但按新文档投影清理 orphan 资源

### 修改前

- `saveBoard(_:)` 已经只为 `persistedState.imageItems` 写 PNG。
- 但 orphan 资产清理仍直接遍历 `document.items.map(\.assetFilename)`，这在 `items` 升级成 mixed item 后不再成立。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: saveBoard(_:)
// 功能说明: 修改前保存路径虽然已经只给图片项写 PNG，但 orphan 清理仍假设 document.items 全都是 BoardImageItemRecord。
let document = BoardDocumentMapper.makeDocument(from: persistedState)

for item in persistedState.imageItems {
    let assetURL = assetsDirectoryURL.appendingPathComponent(
        "\(item.id.uuidString).png"
    )
    let pngData = try makePNGData(for: item.cgImage, itemID: item.id)
    try CoordinatedFileIO.writeData(pngData, to: assetURL)
}

try removeOrphanedAssets(
    keeping: Set(document.items.map(\.assetFilename)),
    in: assetsDirectoryURL
)
```

### 修改后

- PNG 写入边界继续只处理 `imageItems`，不为 text item 生成伪资产。
- orphan 清理切到 `document.imageItemRecords`，让 mixed schema 下的资源生命周期仍然只围绕真实图片资产运转。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: saveBoard(_:)
// 功能说明: 修改后 BoardStore 继续只写图片资产，同时通过 image-only projection 清理无主 PNG，避免 text item 参与 assetFilename 逻辑。
let document = BoardDocumentMapper.makeDocument(from: persistedState)

for item in persistedState.imageItems {
    let assetURL = assetsDirectoryURL.appendingPathComponent(
        "\(item.id.uuidString).png"
    )
    let pngData = try makePNGData(for: item.cgImage, itemID: item.id)
    try CoordinatedFileIO.writeData(pngData, to: assetURL)
}

try removeOrphanedAssets(
    keeping: Set(document.imageItemRecords.map(\.assetFilename)),
    in: assetsDirectoryURL
)
```

## 修改四：`BoardGeometryPreviewBuilder` 开始消费 mixed persisted items，给几何预览补上 text 节点

### 修改前

- `makeSeed(from:)` 虽然从 `document.items` 取数据，但实际辅助函数签名仍写死为 `[BoardImageItemRecord]`。
- 预览节点构建逻辑只会产出 `.image` 节点，无法从 persisted text item 重建几何范围。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名: makeNodes(from:) / makeNode(from:) / makeVisibleWorldQuad(from:)
// 功能说明: 修改前几何预览仍把 persisted item 视为纯图片记录，因此 board list preview / geometry seed 还不能纳入 text item 的世界坐标范围。
private func makeNodes(
    from itemRecords: [BoardImageItemRecord]
) -> [CanvasMiniMapNode] {
    itemRecords
        .compactMap(makeNode)
        .sorted { lhs, rhs in
            if lhs.zIndex == rhs.zIndex {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.zIndex < rhs.zIndex
        }
}

private func makeNode(
    from itemRecord: BoardImageItemRecord
) -> CanvasMiniMapNode? {
    let size = itemRecord.size.cgSize
    guard size.width > 0, size.height > 0 else {
        return nil
    }

    return CanvasMiniMapNode(
        id: itemRecord.id,
        kind: .image,
        worldQuad: makeVisibleWorldQuad(from: itemRecord),
        zIndex: CGFloat(itemRecord.zIndex),
        isPreviewActive: false
    )
}
```

### 修改后

- `BoardGeometryPreviewBuilder` 现在接受 `[BoardItemRecord]`。
- `makeNode(from:)` 按 `.image` / `.text` 分流，并复用统一的几何构造入口生成 `CanvasMiniMapNode`。
- `makeVisibleWorldQuad(...)` 改成只依赖 `center + size + rotationRadians`，因此不需要先解码图片或构建文本 layout，就能恢复持久化几何。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名: makeNodes(from:) / makeNode(from:) / makeNode(id:kind:center:size:zIndex:rotationRadians:)
// 功能说明: 修改后几何预览可以同时从 image/text persisted item 构建 minimap 节点，为后续文本预览链路补上统一的几何来源。
private func makeNodes(
    from itemRecords: [BoardItemRecord]
) -> [CanvasMiniMapNode] {
    itemRecords
        .compactMap(makeNode)
        .sorted { lhs, rhs in
            if lhs.zIndex == rhs.zIndex {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.zIndex < rhs.zIndex
        }
}

private func makeNode(
    from itemRecord: BoardItemRecord
) -> CanvasMiniMapNode? {
    switch itemRecord {
    case let .image(imageRecord):
        return makeNode(
            id: imageRecord.id,
            kind: .image,
            center: imageRecord.center,
            size: imageRecord.size,
            zIndex: imageRecord.zIndex,
            rotationRadians: imageRecord.rotationRadians
        )
    case let .text(textRecord):
        return makeNode(
            id: textRecord.id,
            kind: .text,
            center: textRecord.center,
            size: textRecord.size,
            zIndex: textRecord.zIndex,
            rotationRadians: textRecord.rotationRadians
        )
    }
}

private func makeNode(
    id: UUID,
    kind: CanvasMiniMapNodeKind,
    center: BoardPointRecord,
    size: BoardSizeRecord,
    zIndex: Double,
    rotationRadians: Double?
) -> CanvasMiniMapNode? {
    let resolvedSize = size.cgSize
    guard resolvedSize.width > 0, resolvedSize.height > 0 else {
        return nil
    }

    return CanvasMiniMapNode(
        id: id,
        kind: kind,
        worldQuad: makeVisibleWorldQuad(
            center: center,
            size: size,
            rotationRadians: rotationRadians
        ),
        zIndex: CGFloat(zIndex),
        isPreviewActive: false
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名: makeVisibleWorldQuad(center:size:rotationRadians:)
// 功能说明: 修改后可见世界四边形不再依赖 BoardImageItemRecord，而是只依赖持久化后的几何字段；text item 也能直接复用这条几何恢复路径。
private func makeVisibleWorldQuad(
    center: BoardPointRecord,
    size: BoardSizeRecord,
    rotationRadians: Double?
) -> CanvasQuad {
    // Persisted item size is already the committed visible footprint, so the
    // catalog preview can rebuild board geometry without decoding image assets
    // or creating runtime text layout.
    let localFrame = CGRect(
        x: -size.cgSize.width / 2,
        y: -size.cgSize.height / 2,
        width: size.cgSize.width,
        height: size.cgSize.height
    )
    let localQuad = CanvasQuad(rect: localFrame)
    let worldCenter = center.cgPoint
    let normalizedRotationRadians = normalizedCanvasAngle(
        CGFloat(rotationRadians ?? 0)
    )

    return localQuad.map { localPoint in
        let rotatedPoint = rotated(localPoint, by: normalizedRotationRadians)
        return CGPoint(
            x: rotatedPoint.x + worldCenter.x,
            y: rotatedPoint.y + worldCenter.y
        )
    }
}
```

## 修改五：`BoardThumbnailRenderer` 暂时继续只渲染图片记录，但适配新文档结构

### 修改前

- 缩略图渲染入口直接把 `document.items` 当成图片记录数组传下去。
- 当 `BoardDocument.items` 升级为 `[BoardItemRecord]` 后，这条路径会发生类型不匹配。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(for:targetPixelSize:contentInset:cancellationCheck:) / renderPersistedThumbnail(for:maximumLongestSide:cancellationCheck:)
// 功能说明: 修改前缩略图渲染默认 document.items 全是图片记录；一旦文档进入 mixed schema，这里就需要显式过滤出 image projection。
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
        // ... 省略 image decode ...
    }
}

func renderPersistedThumbnail(
    for runtimeState: BoardRuntimeState,
    maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    // ... 省略前置几何计算 ...
    return try renderThumbnail(
        itemRecords: document.items,
        previewSeed: previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: 0,
        cancellationCheck: cancellationCheck
    ) { itemRecord, _ in
        // ... 省略 runtime image lookup ...
    }
}
```

### 修改后

- 渲染入口显式切到 `document.imageItemRecords`。
- 这让 `T-2` 可以先完成 mixed-item 文档格式升级，而不必在同一阶段里同步实现文本缩略图绘制。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(for:targetPixelSize:contentInset:cancellationCheck:) / renderPersistedThumbnail(for:maximumLongestSide:cancellationCheck:)
// 功能说明: 修改后缩略图渲染明确只消费 image projection；mixed document 可以先落盘，而文本缩略图渲染继续留到后续阶段补齐。
func renderThumbnail(
    for item: BoardCatalogItem,
    targetPixelSize: CGSize,
    contentInset: CGFloat = 10,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    try renderThumbnail(
        itemRecords: item.document.imageItemRecords,
        previewSeed: item.previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: contentInset,
        cancellationCheck: cancellationCheck
    ) { itemRecord, geometry in
        // ... 省略 image decode ...
    }
}

func renderPersistedThumbnail(
    for runtimeState: BoardRuntimeState,
    maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    // ... 省略前置几何计算 ...
    return try renderThumbnail(
        itemRecords: document.imageItemRecords,
        previewSeed: previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: 0,
        cancellationCheck: cancellationCheck
    ) { itemRecord, _ in
        // ... 省略 runtime image lookup ...
    }
}
```

## 验证

```text
// 验证说明: 本阶段完成后，对最近修改文件执行 IDE lints 检查、对全部 Swift 源文件执行 swiftc typecheck，
//           并额外做了一个本地 smoke test（临时脚本，验证完成后已删除）来确认 v2/v3 兼容性。
- ReadLints:
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - 结果：无错误

- swiftc -typecheck:
  - 范围：`MyCanvas_Ver_0` 下全部 `.swift` 源文件
  - 结果：通过

- 本地 smoke test（临时脚本，不纳入仓库）:
  - 验证点：旧 `v2` image-only `board.json` 可被新 `BoardDocument` schema 解码
  - 验证点：新 `v3` mixed document 可 encode/decode，并经 `BoardDocumentMapper` round-trip 回 runtime
  - 结果：通过
```
