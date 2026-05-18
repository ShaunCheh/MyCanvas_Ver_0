# 20260518_114133_handDrawing_phase1_schema_record

## 记录范围

- 记录内容：
  - 实施手绘 block 方案的 `阶段 1`，把 `handDrawing` 先落为正式的 runtime/schema 类型。
  - 接通 `CanvasBoardItem`、`BoardDocument`、`BoardDocumentMapper` 的基础建模。
  - 为了让阶段 1 落地后工程仍可编译、预览链不炸，顺带给渲染/缩略图链路加了最小兼容桥接。
  - 新增一条 mapper round-trip 测试，锁定 `handDrawing` 的文档往返契约。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short` 显示：
    - `M MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift`
    - `M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
    - `M MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
    - `M MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
    - `M MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
    - `M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
    - `M MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
    - `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
    - `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
    - `M MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
    - `?? MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift`
  - 生成本记录前，`git diff --stat` 显示：
    - 10 个已跟踪文件共 `413 insertions(+), 6 deletions(-)`
    - `CanvasHandDrawingItem.swift` 为新增未跟踪文件，因此不出现在该统计里
- 本记录不包含：
  - `阶段 2` 的 handDrawing 可变资产覆盖写与 orphan cleanup
  - `阶段 3` 的 handDrawing 专用 render payload 与最终画布显示策略
  - `阶段 5` 的 iOS PencilKit 全屏编辑器、工具栏入口、上下文菜单入口

## 当前 changes 摘要

- 新增了独立的 `CanvasHandDrawingPaperSpec` 与 `CanvasHandDrawingItem`，统一纸张规格、预览图文件名、源 drawing 文件名、复制与文档状态比对逻辑。
- `CanvasBoardItem` 现在正式支持 `.handDrawing`，并补齐了 `CanvasScene`、`BoardHistorySnapshot`、`CanvasSelectionTransformState` 的基础分支。
- `BoardDocument` 的 schema version 从 image contract 解耦，显式提升到 `6`。
- `BoardDocument` / `BoardItemRecord` / `BoardDocumentMapper` 已经能 round-trip `handDrawing`，并通过 `contentRevision` 保留文档级变化锚点。
- 为了保证阶段 1 落完后工程能编译并保持现有预览路径可工作，`CanvasRenderer`、`BoardGeometryPreviewBuilder`、`BoardThumbnailRenderer` 先用 handDrawing 的 `previewImageRecord` 做了最小桥接。
- `BoardSelectionStateMigrationTests` 新增 handDrawing round-trip 测试，锁住这一步的 schema 契约。

## 修改一：新增独立的 handDrawing runtime 模型

### 修改前

- 工程里没有手绘 block 的独立类型。
- 没有统一的纸张规格、预览文件名、源 drawing 文件名、复制与文档状态比对入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift（修改前）
// 类型名: CanvasHandDrawingPaperSpec / CanvasHandDrawingItem
// 功能说明: 修改前该文件不存在，工程里没有 handDrawing 的独立 runtime 模型。
//
// 修改前: 文件不存在
```

### 修改后

- 新增 `CanvasHandDrawingPaperSpec`，默认提供 `square`，并预留未来多尺寸扩展入口。
- 新增 `CanvasHandDrawingItem`，统一手绘元素的预览图资产、空白态、内容修订号、几何、文件名推导与文档状态比较。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift
// 类型名: CanvasHandDrawingPaperSpec / CanvasHandDrawingItem
// 功能说明: 新增 handDrawing 的共享模型，统一纸张规格、文件名推导、几何换算、复制与文档状态比较。
struct CanvasHandDrawingPaperSpec: Equatable {
    static let square = CanvasHandDrawingPaperSpec(
        id: "square",
        size: CGSize(width: 1_024, height: 1_024)
    )

    let id: String
    let size: CGSize
    var aspectRatio: CGFloat { /* 作用: 为后续保持纸张比例做准备 */ }
}

struct CanvasHandDrawingItem {
    var paper: CanvasHandDrawingPaperSpec
    var previewAsset: CanvasImageAsset
    var isEmpty: Bool
    var contentRevision: UUID

    static func defaultPreviewImageFilename(for itemID: CanvasItemID) -> String { /* ... */ }
    static func defaultSourceDrawingFilename(for itemID: CanvasItemID) -> String { /* ... */ }
    static func persistedPreviewAsset(for itemID: CanvasItemID, cgImage: CGImage, logicalPixelSize: CGSize? = nil) -> CanvasImageAsset { /* ... */ }

    func duplicated(offsetInWorld: CGPoint) -> CanvasHandDrawingItem { /* 作用: 复制时生成新的 itemID 与新的预览图文件名 */ }
    func matchesDocumentState(_ other: CanvasHandDrawingItem) -> Bool { /* 作用: 供历史与文档状态比较使用 */ }
}
```

## 修改二：把 handDrawing 接入统一 board item 抽象

### 2.1 `CanvasBoardItem`

#### 修改前

- `CanvasBoardItemKind` 只有 `image` / `text`。
- `CanvasBoardItem` 的共享几何、命中测试、类型访问器都只覆盖这两类。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift（修改前）
// 类型名: CanvasBoardItemKind / CanvasBoardItem
// 功能说明: 修改前 board item 只有 image / text 两类，共享属性和命中测试也只覆盖这两种元素。
enum CanvasBoardItemKind: Equatable {
    case image
    case text
}

enum CanvasBoardItem {
    case image(CanvasImageItem)
    case text(CanvasTextItem)

    var kind: CanvasBoardItemKind {
        switch self {
        case .image:
            return .image
        case .text:
            return .text
        }
    }

    var textItem: CanvasTextItem? { /* ... */ }
    func contains(worldPoint: CGPoint) -> Bool { /* 只处理 image / text */ }
}
```

#### 修改后

- `handDrawing` 成为第三种正式 board item。
- `kind/id/center/size/zIndex/rotation/localFrame/worldQuad/worldBounds/contains/worldPoint` 等共享入口都已补齐。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift
// 类型名: CanvasBoardItemKind / CanvasBoardItem
// 功能说明: 修改后 handDrawing 进入统一 board item 抽象，后续 scene / renderer / storage 都能通过同一套入口处理它。
enum CanvasBoardItemKind: Equatable {
    case image
    case text
    case handDrawing
}

enum CanvasBoardItem {
    case image(CanvasImageItem)
    case text(CanvasTextItem)
    case handDrawing(CanvasHandDrawingItem)

    var kind: CanvasBoardItemKind { /* image / text / handDrawing 三路分发 */ }
    var handDrawingItem: CanvasHandDrawingItem? { /* 作用: 提供 handDrawing 专用访问器 */ }
    var worldBounds: CGRect { /* 作用: 让共享几何路径可直接消费 handDrawing */ }
    func contains(worldPoint: CGPoint) -> Bool { /* 作用: 让命中测试开始覆盖 handDrawing */ }
}
```

### 2.2 `CanvasScene`

#### 修改前

- `append` / `upsert` / `duplicatedItem` 只知道 `image` 和 `text`。
- 没有 `handDrawingItem(withID:)` 之类的按类型读取入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift（修改前）
// 函数名: append(_:) / upsert(_:) / textItem(withID:) / duplicatedItem(from:offsetInWorld:)
// 功能说明: 修改前 scene 只为 image / text 提供 typed 入口，复制分支也只有这两种元素。
func append(_ item: CanvasImageItem) { append(.image(item)) }
func append(_ item: CanvasTextItem) { append(.text(item)) }

func upsert(_ item: CanvasImageItem) { upsert(.image(item)) }
func upsert(_ item: CanvasTextItem) { upsert(.text(item)) }

func textItem(withID id: CanvasItemID) -> CanvasTextItem? {
    boardItem(withID: id)?.textItem
}

private func duplicatedItem(
    from sourceItem: CanvasBoardItem,
    offsetInWorld: CGPoint
) -> CanvasBoardItem {
    switch sourceItem {
    case let .image(item):
        return .image(item.duplicated(offsetInWorld: offsetInWorld))
    case let .text(item):
        return .text(/* ... */)
    }
}
```

#### 修改后

- scene 已经能 append/upsert/读取/复制 handDrawing。
- 这一步先把最基础的 scene typed API 接起来，为后续 editor session 和 command lane 预留入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: append(_:) / upsert(_:) / handDrawingItem(withID:) / duplicatedItem(from:offsetInWorld:)
// 功能说明: 修改后 scene 对 handDrawing 提供最基础的 typed 入口和复制支持。
func append(_ item: CanvasHandDrawingItem) {
    append(.handDrawing(item))
}

func upsert(_ item: CanvasHandDrawingItem) {
    upsert(.handDrawing(item))
}

func handDrawingItem(withID id: CanvasItemID) -> CanvasHandDrawingItem? {
    boardItem(withID: id)?.handDrawingItem
}

private func duplicatedItem(
    from sourceItem: CanvasBoardItem,
    offsetInWorld: CGPoint
) -> CanvasBoardItem {
    switch sourceItem {
    case let .image(item):
        return .image(item.duplicated(offsetInWorld: offsetInWorld))
    case let .text(item):
        return .text(/* ... */)
    case let .handDrawing(item):
        return .handDrawing(item.duplicated(offsetInWorld: offsetInWorld))
    }
}
```

### 2.3 `BoardHistorySnapshot`

#### 修改前

- 历史快照比较只认 `image` / `text`。
- 新增 `handDrawing` 后，如果不补这层，文档状态比较就会直接落到 `default: false`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift（修改前）
// 函数名: itemsMatch(_:_:)
// 功能说明: 修改前历史快照比较只支持 image / text 两类元素。
switch (lhsItem, rhsItem) {
case let (.image(lhsImage), .image(rhsImage)):
    return lhsImage.matchesDocumentState(rhsImage)
case let (.text(lhsText), .text(rhsText)):
    return lhsText.id == rhsText.id &&
        lhsText.text == rhsText.text &&
        lhsText.style == rhsText.style &&
        lhsText.center == rhsText.center &&
        lhsText.size == rhsText.size &&
        lhsText.zIndex == rhsText.zIndex &&
        lhsText.rotationRadians == rhsText.rotationRadians
default:
    return false
}
```

#### 修改后

- 新增 `handDrawing` 的文档状态比较入口。
- 这里复用了 `CanvasHandDrawingItem.matchesDocumentState(...)`，保持历史比较口径一致。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名: itemsMatch(_:_:)
// 功能说明: 修改后历史快照比较开始支持 handDrawing，并复用 handDrawing 自己的文档状态比较函数。
switch (lhsItem, rhsItem) {
case let (.image(lhsImage), .image(rhsImage)):
    return lhsImage.matchesDocumentState(rhsImage)
case let (.text(lhsText), .text(rhsText)):
    return /* ... */
case let (.handDrawing(lhsHandDrawing), .handDrawing(rhsHandDrawing)):
    return lhsHandDrawing.matchesDocumentState(rhsHandDrawing)
default:
    return false
}
```

### 2.4 `CanvasSelectionTransformState`

#### 修改前

- 选区 resize 的 item 分发只处理 image/text。
- 如果不补这层，handDrawing 虽然进了 `CanvasBoardItem`，也会卡在 transform 路径上。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift（修改前）
// 函数名: resizedItem(_:using:)
// 功能说明: 修改前选区缩放只知道 image 和 text；text 走内容级重算，image 走几何应用。
switch item {
case .image:
    return item.applyingGeometry(scaledItemGeometry) ?? item
case let .text(textItem):
    return .text(
        resizedTextItem(
            textItem,
            scaledCenter: scaledItemGeometry.center,
            scale: resizeDraft.scale
        )
    )
}
```

#### 修改后

- 暂时让 handDrawing 先复用 image 一样的几何应用路径。
- 这只是阶段 1 的可编译兜底，后续阶段 3 还会继续收口“锁定纸张宽高比”的最终规则。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数名: resizedItem(_:using:)
// 功能说明: 修改后 handDrawing 先走几何应用路径，保证新类型能够通过共享 resize 逻辑。
switch item {
case .image:
    return item.applyingGeometry(scaledItemGeometry) ?? item
case let .text(textItem):
    return .text(/* ... */)
case .handDrawing:
    return item.applyingGeometry(scaledItemGeometry) ?? item
}
```

## 修改三：扩展 document schema 与 mapper

### 3.1 `BoardDocument`

#### 修改前

- 文档版本号来自 `CanvasImageAssetContract.current.targetDocumentFormatVersion`。
- `referencedAssetFilenames` 只从 image records 收集。
- `BoardItemRecord` 只有 `image/text` 两种 case。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift（修改前）
// 类型名: BoardDocument / BoardItemRecord
// 功能说明: 修改前文档 schema 仍绑定 image contract，BoardItemRecord 也还没有 handDrawing。
struct BoardDocument: Codable {
    static let currentFormatVersion =
        CanvasImageAssetContract.current.targetDocumentFormatVersion
    static let targetFormatVersionForImageAssets = currentFormatVersion

    var imageItemRecords: [BoardImageItemRecord] {
        items.compactMap(\.imageItemRecord)
    }

    var referencedAssetFilenames: Set<String> {
        imageItemRecords.reduce(into: Set<String>()) { partialResult, record in
            partialResult.formUnion(record.referencedAssetFilenames)
        }
    }
}

enum BoardItemRecord: Codable, Equatable {
    case image(BoardImageItemRecord)
    case text(BoardTextItemRecord)
}
```

#### 修改后

- 文档版本号改为显式 `6`，不再绑到 image contract。
- 新增 `BoardHandDrawingPaperRecord`、`BoardHandDrawingItemRecord`。
- `BoardItemRecord` 增加 `.handDrawing`，并把引用资产收集范围扩到所有 item。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 类型名: BoardDocument / BoardHandDrawingPaperRecord / BoardHandDrawingItemRecord / BoardItemRecord
// 功能说明: 修改后文档 schema 正式容纳 handDrawing，同时通过 contentRevision 与推导文件名为后续阶段 2 留出持久化锚点。
struct BoardDocument: Codable {
    static let currentFormatVersion = 6

    var referencedAssetFilenames: Set<String> {
        items.reduce(into: Set<String>()) { partialResult, record in
            partialResult.formUnion(record.referencedAssetFilenames)
        }
    }

    var handDrawingItemRecords: [BoardHandDrawingItemRecord] {
        items.compactMap(\.handDrawingItemRecord)
    }
}

struct BoardHandDrawingPaperRecord: Codable, Equatable {
    var id: String
    var size: BoardSizeRecord
    var canvasPaperSpec: CanvasHandDrawingPaperSpec { /* ... */ }
}

struct BoardHandDrawingItemRecord: Codable, Equatable {
    var paper: BoardHandDrawingPaperRecord
    var isEmpty: Bool
    var contentRevision: UUID

    var previewImageFilename: String { /* 作用: 从 itemID 推导 png 文件名 */ }
    var sourceDrawingFilename: String { /* 作用: 从 itemID 推导 pkdrawing 文件名 */ }
    var referencedAssetFilenames: Set<String> { /* 同时返回 png 与 pkdrawing */ }
    var previewImageRecord: BoardImageItemRecord { /* 作用: 给现有 image loader / thumbnail bridge 复用 */ }
}

enum BoardItemRecord: Codable, Equatable {
    case image(BoardImageItemRecord)
    case text(BoardTextItemRecord)
    case handDrawing(BoardHandDrawingItemRecord)

    var referencedAssetFilenames: Set<String> {
        switch self {
        case let .image(record):
            return record.referencedAssetFilenames
        case .text:
            return []
        case let .handDrawing(record):
            return record.referencedAssetFilenames
        }
    }
}
```

### 3.2 `BoardDocumentMapper`

#### 修改前

- mapper 只在 runtime/document 间处理 image/text。
- 没有 handDrawing 的构造函数、record 生成函数，也没有借用 `previewImageRecord` 的桥接加载逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift（修改前）
// 函数名: makeRuntimeState(from:imageLoader:) / makeItemRecord(from:)
// 功能说明: 修改前 mapper 只认 image / text，两边的 switch 都没有 handDrawing 分支。
let items = try document.items.map { itemRecord in
    switch itemRecord {
    case let .image(imageRecord):
        return CanvasBoardItem.image(/* ... */)
    case let .text(textRecord):
        return CanvasBoardItem.text(makeTextItem(from: textRecord))
    }
}

private static func makeItemRecord(from item: CanvasBoardItem) -> BoardItemRecord {
    switch item {
    case let .image(imageItem):
        return .image(makeImageRecord(from: imageItem))
    case let .text(textItem):
        return .text(makeTextRecord(from: textItem))
    }
}
```

#### 修改后

- mapper 已经能从 `BoardHandDrawingItemRecord` 构建 runtime item。
- 同时也能把 runtime handDrawing 写回文档 record。
- 当前阶段先通过 `previewImageRecord` 复用现有 `imageLoader`，避免阶段 1 就把存储接口全部拆开。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:) / makeItemRecord(from:) / makeHandDrawingItem(from:previewImage:) / makeHandDrawingRecord(from:)
// 功能说明: 修改后 mapper 可以在 runtime/document 之间往返 handDrawing，并用 previewImageRecord 复用现有 imageLoader。
let items = try document.items.map { itemRecord in
    switch itemRecord {
    case let .image(imageRecord):
        return CanvasBoardItem.image(/* ... */)
    case let .text(textRecord):
        return CanvasBoardItem.text(makeTextItem(from: textRecord))
    case let .handDrawing(handDrawingRecord):
        return CanvasBoardItem.handDrawing(
            makeHandDrawingItem(
                from: handDrawingRecord,
                previewImage: try imageLoader(handDrawingRecord.previewImageRecord)
            )
        )
    }
}

private static func makeItemRecord(from item: CanvasBoardItem) -> BoardItemRecord {
    switch item {
    case let .image(imageItem):
        return .image(makeImageRecord(from: imageItem))
    case let .text(textItem):
        return .text(makeTextRecord(from: textItem))
    case let .handDrawing(handDrawingItem):
        return .handDrawing(makeHandDrawingRecord(from: handDrawingItem))
    }
}

private static func makeHandDrawingItem(
    from handDrawingRecord: BoardHandDrawingItemRecord,
    previewImage: CGImage
) -> CanvasHandDrawingItem { /* ... */ }

private static func makeHandDrawingRecord(
    from item: CanvasHandDrawingItem
) -> BoardHandDrawingItemRecord { /* ... */ }
```

## 修改四：为阶段 1 可编译，给渲染/预览链路加最小桥接

### 4.1 `CanvasRenderer`

#### 修改前

- `makeRenderItem(...)` 只有 image/text 两路。
- `makeTextRenderItem(...)` 的兜底分支只会遇到 `.image`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift（修改前）
// 函数名: makeRenderItem(for:camera:inlineEditState:rotationPreviewState:) / makeTextRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 renderer 只为 image / text 生成 render item，没有 handDrawing 的兜底分支。
private func makeRenderItem(
    for item: CanvasBoardItem,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    switch item {
    case let .image(imageItem):
        return makeImageRenderItem(/* ... */)
    case let .text(textItem):
        return makeTextRenderItem(/* ... */)
    }
}

switch effectiveBoardItem(from: .text(item), rotationPreviewState: rotationPreviewState) {
case let .text(resolvedTextItem):
    effectiveTextItem = resolvedTextItem
case .image:
    assertionFailure("Expected text item after applying text presentation.")
    effectiveTextItem = item
}
```

#### 修改后

- 当前阶段先新增 `makeHandDrawingRenderItem(...)`。
- 这里临时把 handDrawing 预览桥接到 `CanvasImageRenderPayload`，保证编译与现有 layer pipeline 可继续工作；这不是阶段 3 的最终 render 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeRenderItem(for:camera:inlineEditState:rotationPreviewState:) / makeHandDrawingRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改后 renderer 先把 handDrawing 预览桥接为静态图片 payload，保证阶段 1 新类型可以进入现有画布渲染链。
private func makeRenderItem(
    for item: CanvasBoardItem,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    switch item {
    case let .image(imageItem):
        return makeImageRenderItem(/* ... */)
    case let .text(textItem):
        return makeTextRenderItem(/* ... */)
    case let .handDrawing(handDrawingItem):
        return makeHandDrawingRenderItem(
            for: handDrawingItem,
            camera: camera,
            rotationPreviewState: rotationPreviewState
        )
    }
}

private func makeHandDrawingRenderItem(
    for item: CanvasHandDrawingItem,
    camera: CanvasCamera,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    // 作用: 先把 handDrawing 预览桥接成 static image payload，避免阶段 1 就拆整套 render payload。
    payload: .image(
        CanvasImageRenderPayload(
            displayContract: CanvasImageDisplayContract(
                assetReference: effectiveHandDrawingItem.previewAsset.reference,
                posterCGImage: effectiveHandDrawingItem.previewAsset.posterCGImage,
                allowsAnimatedPlayback: false
            ),
            contentsRect: CanvasImageCropRect.fullImage.cgRect
        )
    )
}
```

### 4.2 `BoardGeometryPreviewBuilder`

#### 修改前

- board list 的几何 seed 只知道 image/text。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift（修改前）
// 函数名: makeNode(from:boardID:documentOrder:)
// 功能说明: 修改前几何 seed 只从 image / text record 生成 minimap node。
switch itemRecord {
case let .image(imageRecord):
    return makeNode(kind: .image, /* ... */)
case let .text(textRecord):
    return makeNode(kind: .text, /* ... */)
}
```

#### 修改后

- handDrawing 已经开始进入几何 seed。
- 当前阶段先把它映射到 `.image` kind，保证列表预览和 minimap 的几何链可继续复用。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名: makeNode(from:boardID:documentOrder:)
// 功能说明: 修改后 handDrawing 先复用 image 类节点，保证阶段 1 的几何 preview pipeline 不断链。
switch itemRecord {
case let .image(imageRecord):
    return makeNode(kind: .image, /* ... */)
case let .text(textRecord):
    return makeNode(kind: .text, /* ... */)
case let .handDrawing(handDrawingRecord):
    return makeNode(
        boardID: boardID,
        documentOrder: documentOrder,
        id: handDrawingRecord.id,
        kind: .image,
        center: handDrawingRecord.center,
        size: handDrawingRecord.size,
        zIndex: handDrawingRecord.zIndex,
        rotationRadians: handDrawingRecord.rotationRadians
    )
}
```

### 4.3 `BoardThumbnailRenderer`

#### 修改前

- 缩略图渲染主循环只有 image/text 两类。
- `decodeMaxPixelSizesByFilename(...)` 也只会扫描 image records。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift（修改前）
// 函数名: renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:traceContext:imageProvider:) / decodeMaxPixelSizesByFilename(from:geometry:)
// 功能说明: 修改前缩略图绘制与解码预算都只覆盖 image / text。
switch itemRecord {
case let .image(imageItemRecord):
    let image = try imageProvider(imageItemRecord, geometry, itemRecords)
    drawLoadedImage(/* ... */)
case let .text(textItemRecord):
    drawTextItem(/* ... */)
}

for itemRecord in itemRecords {
    guard case let .image(imageItemRecord) = itemRecord else {
        continue
    }
    let decodeMaxPixelSize = decodeMaxPixelSize(for: imageItemRecord, geometry: geometry)
    // ...
}
```

#### 修改后

- handDrawing 现在通过 `previewImageRecord` 进入缩略图绘制。
- `decodeMaxPixelSizesByFilename(...)` 也开始把 handDrawing 的 preview png 算进去。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:traceContext:imageProvider:) / decodeMaxPixelSizesByFilename(from:geometry:)
// 功能说明: 修改后 handDrawing 通过 previewImageRecord 复用现有图片缩略图绘制路径。
switch itemRecord {
case let .image(imageItemRecord):
    let image = try imageProvider(imageItemRecord, geometry, itemRecords)
    drawLoadedImage(/* ... */)
case let .text(textItemRecord):
    drawTextItem(/* ... */)
case let .handDrawing(handDrawingItemRecord):
    let previewImageRecord = handDrawingItemRecord.previewImageRecord
    let image = try imageProvider(previewImageRecord, geometry, itemRecords)
    drawLoadedImage(
        image,
        for: previewImageRecord,
        geometry: geometry,
        in: context,
        traceContext: traceContext,
        documentOrder: traceContext.documentOrderByID[handDrawingItemRecord.id],
        renderOrder: renderOrder
    )
}

for itemRecord in itemRecords {
    let imageItemRecord: BoardImageItemRecord
    switch itemRecord {
    case let .image(record):
        imageItemRecord = record
    case let .handDrawing(record):
        imageItemRecord = record.previewImageRecord
    case .text:
        continue
    }
    let decodeMaxPixelSize = decodeMaxPixelSize(for: imageItemRecord, geometry: geometry)
    // ...
}
```

## 修改五：新增 handDrawing 的 mapper round-trip 测试

### 修改前

- `BoardSelectionStateMigrationTests` 没有覆盖 handDrawing。
- schema 进来以后，如果没有测试，后续很容易在 mapper、preview 文件名推导、`contentRevision` 保留上回退。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift（修改前）
// 函数名: testBoardDocumentMapperRoundTripsMultiSelectionViewState() / testBoardDocumentMapperNormalizesLegacyTextItemSizeOnLoad()
// 功能说明: 修改前测试集只覆盖 selection state migration 与 legacy text size normalize，没有 handDrawing round-trip 验证。
final class BoardSelectionStateMigrationTests: XCTestCase {
    func testBoardDocumentMapperRoundTripsMultiSelectionViewState() throws { /* ... */ }
    func testBoardDocumentMapperNormalizesLegacyTextItemSizeOnLoad() throws { /* ... */ }
}
```

### 修改后

- 新增 `testBoardDocumentMapperRoundTripsHandDrawingItem()`。
- 同时新增 `makeSolidColorPreviewImage(...)`，为测试提供最小可用的 handDrawing preview 图像。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数名: testBoardDocumentMapperRoundTripsHandDrawingItem() / makeSolidColorPreviewImage(red:green:blue:)
// 功能说明: 修改后测试开始锁定 handDrawing 的 document round-trip、paper 保留、contentRevision 保留与 preview 文件名推导。
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
    XCTAssertEqual(handDrawingRecord.paper.canvasPaperSpec, .square)
    XCTAssertEqual(handDrawingRecord.contentRevision, contentRevision)
    // ...
}

private func makeSolidColorPreviewImage(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat
) throws -> CGImage {
    // 作用: 构造最小测试预览图，避免测试依赖外部图片资源。
    // ...
}
```

## 验证

- 已执行 iOS 构建：
  - `xcodebuild -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk iphonesimulator build`
- 已执行 macOS 构建：
  - `xcodebuild -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk macosx build`
- 已执行目标测试：
  - `xcodebuild -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests test`
- 已执行 lints 检查：
  - 本次 touched 文件未发现新增 lint 问题

## 备注

- 这次记录如实包含了 `CanvasRenderer`、`BoardGeometryPreviewBuilder`、`BoardThumbnailRenderer` 的变更。虽然它们不属于阶段 1 计划中的最终目标，但它们确实被修改了，作用是让新增的 `handDrawing` 类型在阶段 1 落地后仍能通过现有编译与预览链路。
- 当前 handDrawing 在 renderer / preview 层仍然是“借用 image 预览图”的过渡方案；后续阶段 3/4 还会把它收口成更明确的独立 render / preview 语义。
