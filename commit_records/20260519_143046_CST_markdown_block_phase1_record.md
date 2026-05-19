# 20260519_143046_CST_markdown_block_phase1_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown_block_计划_ccecae26.plan.md` 的阶段 1。
  - 把 `markdown` 落为正式的 runtime / schema 类型，打通 `Scene`、`BoardDocument`、`BoardDocumentMapper`、`CanvasCommand`、`CanvasEditorSession` 的最小闭环。
  - 为了保证阶段 1 落地后工程可编译、当前预览链不炸，补了画布 / minimap / thumbnail 的最小兼容桥接。
  - 新增定向测试，锁定 markdown block 的 schema 往返契约与命令骨架行为。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short` 显示上述 18 个文件为已修改状态。
  - 生成本记录前，`git diff --stat` 显示：`18 files changed, 840 insertions(+), 17 deletions(-)`。
- 本记录不包含：
  - 阶段 2 的 markdown 布局测量器与真正 markdown 富文本渲染。
  - 阶段 3 的 resize 语义收敛与选中态悬浮工具条。
  - 阶段 4 / 5 的 iOS / macOS markdown 编辑器入口与编辑 UI。

## 当前 changes 摘要

- 新增 `CanvasMarkdownItem` 与 `BoardMarkdownItemRecord`，把 `markdown` 变成正式的 board item 类型。
- `BoardDocument.currentFormatVersion` 从 `8` 升到 `9`，`board.json` 开始支持 `BoardItemRecord.markdown`。
- `BoardDocumentMapper` 已经可以在 runtime/document 之间往返 markdown item，并且保留容器 `size`，不套用现有 text 的 intrinsic-size 重算语义。
- `CanvasCommand` / `CanvasCommandCatalog` / `CanvasCommandExecutor` / `CanvasEditorSession` 已接入阶段 1 所需的 markdown 命令骨架：新增、开始编辑入口占位、提交占位、内容字号 `+/-`。
- `CanvasRenderer` / `CanvasMiniMapNodeProvider` / `BoardGeometryPreviewBuilder` / `BoardThumbnailRenderer` 已提供最小兼容桥接：阶段 1 先把 markdown 作为 text-compatible 内容走现有显示链。
- 新增 mapper round-trip 与命令策略/历史回退测试，锁定阶段 1 契约。

## 修改一：新增 markdown runtime 模型并接入统一 board 抽象

### 1.1 `CanvasBoardItem`

#### 修改前

- `CanvasBoardItemKind` 只有 `image` / `text` / `handDrawing`。
- `CanvasBoardItem` 没有 `markdown` case，也没有 markdown 专用访问器与共享几何入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift（修改前）
// 类型名: CanvasBoardItemKind / CanvasBoardItem
// 功能说明: 修改前 board item 只覆盖 image、text、handDrawing 三类元素，没有 markdown block 的独立 runtime 模型。
enum CanvasBoardItemKind: Equatable {
    case image
    case text
    case handDrawing
}

enum CanvasBoardItem {
    case image(CanvasImageItem)
    case text(CanvasTextItem)
    case handDrawing(CanvasHandDrawingItem)

    var kind: CanvasBoardItemKind { /* 只分发 image / text / handDrawing */ }
    var textItem: CanvasTextItem? { /* ... */ }
    var handDrawingItem: CanvasHandDrawingItem? { /* ... */ }
    func contains(worldPoint: CGPoint) -> Bool { /* 只覆盖现有三类元素 */ }
}
```

#### 修改后

- 新增 `CanvasMarkdownItem`，把 markdown block 的 `source/style/center/size/zIndex/rotation` 和共享几何统一收进独立模型。
- `CanvasBoardItem` 新增 `.markdown` 与 `markdownItem`，共享几何/命中测试/typed accessor 全部补齐。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift
// 类型名: CanvasMarkdownItem / CanvasBoardItem
// 功能说明: 修改后新增 markdown block 的共享模型，并把它接入统一 board item 的几何、命中测试和 typed accessor。
struct CanvasMarkdownItem {
    let id: CanvasItemID
    var markdownSource: String
    var style: CanvasTextStyle
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat

    var worldBounds: CGRect {
        worldQuad.boundingRect
    }

    func matchesDocumentState(_ other: CanvasMarkdownItem) -> Bool {
        id == other.id &&
            markdownSource == other.markdownSource &&
            style == other.style &&
            center == other.center &&
            size == other.size &&
            zIndex == other.zIndex &&
            rotationRadians == other.rotationRadians
    }
}

enum CanvasBoardItemKind: Equatable {
    case image
    case text
    case markdown
    case handDrawing
}

enum CanvasBoardItem {
    case image(CanvasImageItem)
    case text(CanvasTextItem)
    case markdown(CanvasMarkdownItem)
    case handDrawing(CanvasHandDrawingItem)

    var markdownItem: CanvasMarkdownItem? { /* 作用: 提供 markdown typed accessor */ }
    var kind: CanvasBoardItemKind { /* image / text / markdown / handDrawing 四路分发 */ }
    func contains(worldPoint: CGPoint) -> Bool { /* 作用: 共享命中测试开始覆盖 markdown */ }
}
```

### 1.2 `CanvasScene` / 历史快照 / 选择几何

#### 修改前

- `CanvasScene` 只有 `image` / `text` / `handDrawing` 的 typed API。
- `BoardHistorySnapshot` 和 `CanvasSelectionTransformState` 都还不知道 `.markdown`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift（修改前）
// 函数名: append(_:) / upsert(_:) / textItem(withID:) / duplicatedItem(from:offsetInWorld:)
// 功能说明: 修改前 scene 没有 markdown 的增改查与复制入口。
func append(_ item: CanvasTextItem) { append(.text(item)) }
func append(_ item: CanvasHandDrawingItem) { append(.handDrawing(item)) }

func upsert(_ item: CanvasTextItem) { upsert(.text(item)) }
func upsert(_ item: CanvasHandDrawingItem) { upsert(.handDrawing(item)) }

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
    case let .handDrawing(item):
        return .handDrawing(item.duplicated(offsetInWorld: offsetInWorld))
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift（修改前）
// 函数名: itemsMatch(_:_:)
// 功能说明: 修改前历史比较只覆盖 image / text / handDrawing，没有 markdown 分支。
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
case let (.handDrawing(lhsHandDrawing), .handDrawing(rhsHandDrawing)):
    return lhsHandDrawing.matchesDocumentState(rhsHandDrawing)
default:
    return false
}
```

#### 修改后

- `CanvasScene` 已支持 markdown 的 append / upsert / 查询 / 更新 / 复制。
- 历史比较与选择几何应用都已经把 markdown 接进来，阶段 1 先按普通容器 item 处理。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: append(_:) / upsert(_:) / markdownItem(withID:) / updateMarkdownItem(withID:markdownSource:style:size:) / duplicatedItem(from:offsetInWorld:)
// 功能说明: 修改后 scene 开始支持 markdown item 的最小 CRUD 骨架，为 session / command lane 提供统一入口。
func append(_ item: CanvasMarkdownItem) {
    append(.markdown(item))
}

func upsert(_ item: CanvasMarkdownItem) {
    upsert(.markdown(item))
}

func markdownItem(withID id: CanvasItemID) -> CanvasMarkdownItem? {
    boardItem(withID: id)?.markdownItem
}

func updateMarkdownItem(
    withID id: CanvasItemID,
    markdownSource: String,
    style: CanvasTextStyle,
    size: CGSize
) -> CanvasMarkdownItem? { /* 作用: 为阶段 1 内容字号 +/- 预留统一写入口 */ }

private func duplicatedItem(
    from sourceItem: CanvasBoardItem,
    offsetInWorld: CGPoint
) -> CanvasBoardItem {
    switch sourceItem {
    case let .markdown(item):
        return .markdown(
            CanvasMarkdownItem(
                markdownSource: item.markdownSource,
                style: item.style,
                center: CGPoint(
                    x: item.center.x + offsetInWorld.x,
                    y: item.center.y + offsetInWorld.y
                ),
                size: item.size,
                zIndex: item.zIndex,
                rotationRadians: item.rotationRadians
            )
        )
    // 其他 case 省略
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名: itemsMatch(_:_:)
// 功能说明: 修改后历史快照开始把 markdown 纳入文档状态比较，避免 undo/redo 把它判成未知元素。
switch (lhsItem, rhsItem) {
case let (.markdown(lhsMarkdown), .markdown(rhsMarkdown)):
    return lhsMarkdown.matchesDocumentState(rhsMarkdown)
// 其他 case 省略
default:
    return false
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数名: applyingGeometry(_:) / resizedBoardItem(_:toCenter:size:)
// 功能说明: 修改后 markdown 在阶段 1 先按普通容器 item 处理共享几何更新，不提前引入阶段 3 的 resize 特化语义。
switch item {
case .markdown:
    return item.applyingGeometry(scaledItemGeometry) ?? item
// 其他 case 省略
}

switch self {
case .image, .text, .markdown:
    var updatedItem = self
    updatedItem.center = geometry.center
    updatedItem.size = geometry.size
    updatedItem.rotationRadians = geometry.rotationRadians
    return updatedItem
// 其他 case 省略
}
```

## 修改二：扩展 `board.json` schema 与 runtime/document mapper

### 2.1 `BoardDocument`

#### 修改前

- `BoardDocument.currentFormatVersion` 还是 `8`。
- `BoardItemRecord` 只有 `image` / `text` / `handDrawing` 三种 case。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift（修改前）
// 类型名: BoardDocument / BoardItemRecord
// 功能说明: 修改前 board.json 还不认识 markdown item，也没有 markdown records 聚合入口。
struct BoardDocument: Codable {
    static let currentFormatVersion = 8

    var textItemRecords: [BoardTextItemRecord] {
        items.compactMap(\.textItemRecord)
    }

    var handDrawingItemRecords: [BoardHandDrawingItemRecord] {
        items.compactMap(\.handDrawingItemRecord)
    }
}

enum BoardItemRecord: Codable, Equatable {
    case image(BoardImageItemRecord)
    case text(BoardTextItemRecord)
    case handDrawing(BoardHandDrawingItemRecord)
}
```

#### 修改后

- schema 版本升到 `9`。
- 新增 `BoardMarkdownItemRecord`、`BoardItemRecord.markdown`、`markdownItemRecords`、`markdownItems`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 类型名: BoardDocument / BoardMarkdownItemRecord / BoardItemRecord
// 功能说明: 修改后 board.json 开始正式支持 markdown item 的编码、解码、聚合读取与 zIndex / 资产引用分发。
struct BoardDocument: Codable {
    static let currentFormatVersion = 9

    var markdownItemRecords: [BoardMarkdownItemRecord] {
        items.compactMap(\.markdownItemRecord)
    }
}

struct BoardMarkdownItemRecord: Codable, Equatable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var markdownSource: String
    var style: BoardTextStyleRecord
    var rotationRadians: Double?
}

enum BoardItemRecord: Codable, Equatable {
    case image(BoardImageItemRecord)
    case text(BoardTextItemRecord)
    case markdown(BoardMarkdownItemRecord)
    case handDrawing(BoardHandDrawingItemRecord)

    private enum CodingKeys: String, CodingKey {
        case type
        case image
        case text
        case markdown
        case handDrawing
    }
}
```

### 2.2 `BoardDocumentMapper`

#### 修改前

- mapper 只会在 runtime/document 之间往返 `image` / `text` / `handDrawing`。
- `text` 在 load 时会走 intrinsic-size 逻辑，但还没有 markdown 的显式容器尺寸保留语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift（修改前）
// 函数名: makeRuntimeState(from:imageLoader:handDrawingPreviewLoader:) / makeItemRecord(from:)
// 功能说明: 修改前 mapper 没有 markdown case，因此 runtime/document 往返链路不会保留 markdown block。
switch itemRecord {
case let .image(imageRecord):
    return CanvasBoardItem.image(/* ... */)
case let .text(textRecord):
    return CanvasBoardItem.text(makeTextItem(from: textRecord))
case let .handDrawing(handDrawingRecord):
    return CanvasBoardItem.handDrawing(/* ... */)
}

switch item {
case let .image(imageItem):
    return .image(makeImageRecord(from: imageItem))
case let .text(textItem):
    return .text(makeTextRecord(from: textItem))
case let .handDrawing(handDrawingItem):
    return .handDrawing(makeHandDrawingRecord(from: handDrawingItem))
}
```

#### 修改后

- mapper 已支持 markdown item 的双向映射。
- 关键点是 `makeMarkdownItem(from:)` 直接保留文档里的 `size`，避免错误套用 text 的 intrinsic-size 重算。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:handDrawingPreviewLoader:) / makeMarkdownItem(from:) / makeMarkdownRecord(from:)
// 功能说明: 修改后 mapper 能 round-trip markdown item，并显式保留容器 size，作为阶段 1 的尺寸契约。
switch itemRecord {
case let .markdown(markdownRecord):
    return CanvasBoardItem.markdown(
        makeMarkdownItem(from: markdownRecord)
    )
// 其他 case 省略
}

private static func makeMarkdownItem(
    from markdownRecord: BoardMarkdownItemRecord
) -> CanvasMarkdownItem {
    CanvasMarkdownItem(
        id: markdownRecord.id,
        markdownSource: markdownRecord.markdownSource,
        style: markdownRecord.style.canvasTextStyle,
        center: markdownRecord.center.cgPoint,
        size: markdownRecord.size.cgSize,
        zIndex: CGFloat(markdownRecord.zIndex),
        rotationRadians: CGFloat(markdownRecord.rotationRadians ?? 0)
    )
}

private static func makeMarkdownRecord(
    from item: CanvasMarkdownItem
) -> BoardMarkdownItemRecord {
    BoardMarkdownItemRecord(
        id: item.id,
        center: BoardPointRecord(item.center),
        size: BoardSizeRecord(item.size),
        zIndex: Double(item.zIndex),
        markdownSource: item.markdownSource,
        style: BoardTextStyleRecord(item.style),
        rotationRadians: Double(item.rotationRadians)
    )
}
```

## 修改三：补阶段 1 的命令骨架与 session 最小能力

### 3.1 `CanvasCommand`

#### 修改前

- 命令系统没有任何 markdown 相关的命令 ID 或枚举 case。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift（修改前）
// 类型名: CanvasCommandID / CanvasCommand
// 功能说明: 修改前命令系统只覆盖 text、handDrawing、crop、history、selection 等既有能力，没有 markdown 阶段 1 骨架。
enum CanvasCommandID: String {
    case importMedia
    case addTextItem
    case addHandDrawingItem
    case beginTextEdit
    case commitTextEdit
    case decreaseTextFontSize
    case increaseTextFontSize
    case crop
}

enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case addHandDrawingItem(paper: CanvasHandDrawingPaperSpec)
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case decreaseTextFontSize
    case increaseTextFontSize
}
```

#### 修改后

- 命令系统补齐了 markdown 阶段 1 所需的 `add / beginEdit / commit / +/-` 骨架。
- `shouldCommitActiveInlineTextBeforeExecuting` 和 `shouldCancelActiveRotation` 等共享策略也同步纳入这些命令。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 类型名: CanvasCommandID / CanvasCommand
// 功能说明: 修改后 markdown block 已进入统一命令系统，为后续 toolbar / context menu / editor flow 提供稳定命令面。
enum CanvasCommandID: String {
    case addMarkdownItem
    case beginMarkdownEdit
    case commitMarkdownEdit
    case decreaseMarkdownContentSize
    case increaseMarkdownContentSize
    // 其他命令省略
}

enum CanvasCommand {
    case addMarkdownItem
    case beginMarkdownEdit(itemID: CanvasItemID)
    case commitMarkdownEdit
    case decreaseMarkdownContentSize
    case increaseMarkdownContentSize
    // 其他命令省略
}
```

### 3.2 `CanvasEditorSession`

#### 修改前

- session 只有 text / handDrawing 的新增与 inline text 能力。
- 没有 markdown item 的默认创建参数、选中态识别、编辑入口占位、内容字号 `+/-`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift（修改前）
// 函数名: canAddTextItem / canAddHandDrawingItem / addTextItem(text:style:) / addHandDrawingItem(paper:)
// 功能说明: 修改前 session 里没有 markdown block 的默认创建、命令执行能力和选中态读写入口。
var canAddTextItem: Bool {
    inlineEditState == nil
}

var canAddHandDrawingItem: Bool {
    inlineEditState == nil
}

func addTextItem(
    text: String = "Text",
    style: CanvasTextStyle = .default
) -> CanvasTextItem? { /* ... */ }

func addHandDrawingItem(
    paper: CanvasHandDrawingPaperSpec = .square
) -> CanvasHandDrawingItem? { /* ... */ }
```

#### 修改后

- session 新增 markdown 默认内容、默认尺寸、选中态识别、创建、开始编辑占位、提交占位、内容字号 `+/-` 与历史记录。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: canAddMarkdownItem / canBeginMarkdownEdit(withID:) / addMarkdownItem(markdownSource:style:) / adjustMarkdownContentSize(by:)
// 功能说明: 修改后 session 已具备 markdown 阶段 1 的最小能力面，但 commit/edit UI 仍保持占位，不提前进入后续阶段。
private static let markdownContentSizeStep: CGFloat = 2
private static let defaultMarkdownSource = """
## Markdown

Write here.
"""
private static let defaultMarkdownItemSize = CGSize(width: 320, height: 180)

var canAddMarkdownItem: Bool {
    inlineEditState == nil
}

var canCommitMarkdownEdit: Bool {
    false
}

var selectedMarkdownItem: CanvasMarkdownItem? {
    selectedBoardItem?.markdownItem
}

func canBeginMarkdownEdit(withID itemID: CanvasItemID) -> Bool {
    guard inlineEditState == nil else {
        return false
    }
    return scene.markdownItem(withID: itemID) != nil
}

func addMarkdownItem(
    markdownSource: String = CanvasEditorSession.defaultMarkdownSource,
    style: CanvasTextStyle = .default
) -> CanvasMarkdownItem? { /* 作用: 创建 markdown block、写历史、更新选中态 */ }

func beginMarkdownEdit(withID itemID: CanvasItemID) -> Bool { /* 作用: 当前阶段先只切选中态 */ }
func commitMarkdownEdit() -> Bool { false }

func decreaseMarkdownContentSize() -> CanvasMarkdownItem? { /* ... */ }
func increaseMarkdownContentSize() -> CanvasMarkdownItem? { /* ... */ }

private func adjustMarkdownContentSize(by delta: CGFloat) -> CanvasMarkdownItem? {
    guard
        inlineEditState == nil,
        let item = selectedMarkdownItem,
        selectionCount == 1
    else {
        return nil
    }

    let updatedStyle = adjustedInlineTextStyle(
        from: item.style,
        fontSizeDelta: delta
    )
    guard let updatedItem = scene.updateMarkdownItem(
        withID: item.id,
        markdownSource: item.markdownSource,
        style: updatedStyle,
        size: item.size
    ) else {
        return nil
    }
    return updatedItem
}
```

### 3.3 执行器、命令目录、上下文菜单与 macOS 分发

#### 修改前

- 执行器、descriptor、上下文菜单命令解析、macOS 按 `CanvasCommandID` 分发都没有 markdown 分支。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift（修改前）
// 函数名: canExecute(_:) / execute(_:)
// 功能说明: 修改前执行器只能处理 text / handDrawing 相关命令，没有 markdown 命令骨架。
switch command {
case .addTextItem:
    return session.canAddTextItem
case .addHandDrawingItem:
    return session.canAddHandDrawingItem
case .beginTextEdit:
    return session.canBeginTextEdit(withID: itemID)
case .commitTextEdit:
    return session.canCommitTextEdit
case .decreaseTextFontSize:
    return session.canDecreaseInlineTextFontSize
case .increaseTextFontSize:
    return session.canIncreaseInlineTextFontSize
// ...
}
```

#### 修改后

- `CanvasCommandExecutor`、`CanvasCommandCatalog`、`CanvasContextMenuCommandResolver`、`macOSViewController` 已全部补齐 markdown 分支，保证阶段 1 新命令不会在下游 `switch` 里掉到漏 case。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名: canExecute(_:) / execute(_:)
// 功能说明: 修改后执行器已经能接通 markdown 新建、编辑入口占位、内容字号 +/- 等阶段 1 命令。
switch command {
case .addMarkdownItem:
    return session.canAddMarkdownItem
case let .beginMarkdownEdit(itemID):
    return session.canBeginMarkdownEdit(withID: itemID)
case .commitMarkdownEdit:
    return session.canCommitMarkdownEdit
case .decreaseMarkdownContentSize:
    return session.canDecreaseMarkdownContentSize
case .increaseMarkdownContentSize:
    return session.canIncreaseMarkdownContentSize
// ...
}

case .addMarkdownItem:
    guard let addedMarkdownItem = session.addMarkdownItem() else {
        return nil
    }
    return CanvasCommandExecutionResult(
        refreshReason: "add markdown item \(addedMarkdownItem.id.uuidString)"
    )

case .increaseMarkdownContentSize:
    guard let updatedItem = session.increaseMarkdownContentSize() else {
        return nil
    }
    return CanvasCommandExecutionResult(
        refreshReason: "increase markdown content size \(updatedItem.id.uuidString)"
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名: descriptor(for:session:context:)
// 功能说明: 修改后 command descriptor 已为 markdown 提供 title、icon、enabled 状态和上下文目标解析。
case .addMarkdownItem:
    descriptor = CanvasCommandDescriptor(
        id: .addMarkdownItem,
        title: "Add Markdown",
        systemImageName: "text.alignleft",
        isEnabled: session.canAddMarkdownItem,
        isActive: false
    )

case .beginMarkdownEdit:
    descriptor = CanvasCommandDescriptor(
        id: .beginMarkdownEdit,
        title: "Edit Markdown",
        systemImageName: "pencil",
        isEnabled: resolvedTargetItemID.map { itemID in
            session.canBeginMarkdownEdit(withID: itemID)
        } ?? false,
        isActive: false
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名: command(for:context:session:)
// 功能说明: 修改后上下文菜单命令解析与 macOS 命令分发都能识别 markdown 新命令，避免新增 commandID 触发漏分支。
case .addMarkdownItem:
    return .addMarkdownItem
case .beginMarkdownEdit:
    guard let itemID = context.singleEffectiveItemID else {
        return nil
    }
    return .beginMarkdownEdit(itemID: itemID)
case .commitMarkdownEdit:
    return nil
case .decreaseMarkdownContentSize,
     .increaseMarkdownContentSize:
    return nil
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performCommand(withID:)
// 功能说明: 修改后 macOS 端按 commandID 分发时已补齐 markdown 命令，保证桌面端编译与运行路径一致。
case .addMarkdownItem:
    performCommand(.addMarkdownItem)
case .beginMarkdownEdit:
    if let selectedItemID = interactionState.selectedItemID {
        performCommand(.beginMarkdownEdit(itemID: selectedItemID))
    }
case .commitMarkdownEdit:
    performCommand(.commitMarkdownEdit)
case .decreaseMarkdownContentSize:
    performCommand(.decreaseMarkdownContentSize)
case .increaseMarkdownContentSize:
    performCommand(.increaseMarkdownContentSize)
```

## 修改四：为画布 / minimap / thumbnail 提供最小兼容桥接

### 4.1 `CanvasRenderer`

#### 修改前

- 画布渲染只会为 `image` / `text` / `handDrawing` 生成 render item。
- 一旦 runtime 里出现 markdown item，当前渲染链就会漏 case。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift（修改前）
// 函数名: makeRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前画布渲染还没有 markdown item 的 render path。
switch item {
case let .image(imageItem):
    return makeImageRenderItem(/* ... */)
case let .text(textItem):
    return makeTextRenderItem(/* ... */)
case let .handDrawing(handDrawingItem):
    return makeHandDrawingRenderItem(/* ... */)
}
```

#### 修改后

- 阶段 1 先不做真正 markdown 富文本渲染，只把 markdown 临时桥接成 text-compatible payload，保证画布、旋转预览和选中态都可工作。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeRenderItem(for:camera:inlineEditState:rotationPreviewState:) / makeMarkdownRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改后 markdown item 已进入主画布渲染链，但阶段 1 先走 text payload 占位兼容。
switch item {
case let .markdown(markdownItem):
    return makeMarkdownRenderItem(
        for: markdownItem,
        camera: camera,
        rotationPreviewState: rotationPreviewState
    )
// 其他 case 省略
}

private func makeMarkdownRenderItem(
    for item: CanvasMarkdownItem,
    camera: CanvasCamera,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    let screenQuad = camera.worldToViewport(effectiveMarkdownItem.worldQuad)
    return CanvasRenderItem(
        id: effectiveMarkdownItem.id,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(effectiveMarkdownItem.center),
        screenBoundsSize: CGSize(
            width: effectiveMarkdownItem.size.width * camera.zoomScale,
            height: effectiveMarkdownItem.size.height * camera.zoomScale
        ),
        rotationRadians: effectiveMarkdownItem.rotationRadians,
        zIndex: effectiveMarkdownItem.zIndex,
        payload: .text(
            CanvasTextRenderPayload(
                text: effectiveMarkdownItem.markdownSource,
                style: effectiveMarkdownItem.style,
                zoomScale: camera.zoomScale
            )
        )
    )
}
```

### 4.2 minimap / geometry preview / thumbnail

#### 修改前

- minimap text provider 只读 `textItem`。
- geometry preview / thumbnail 也只知道 `text` record，没有 markdown record 的最小桥接。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift（修改前）
// 函数名: CanvasMiniMapTextNodeProvider.makeNodes(context:)
// 功能说明: 修改前 minimap 的 text provider 只消费 textItem，markdown 进来会直接被丢掉。
guard let item = boardItem.textItem else {
    return nil
}

return CanvasMiniMapNode(
    id: item.id,
    kind: .text,
    worldQuad: item.worldQuad,
    zIndex: item.zIndex,
    isPreviewActive: context.inlineEditState?.mode == .text &&
        context.inlineEditState?.itemID == item.id
)
```

#### 修改后

- minimap 把 markdown 先归入 `.text` 节点。
- geometry preview 和 thumbnail 也先把 markdown 走 text-compatible 路径，保证 board list / preview seed / thumbnail 不崩。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
// 函数名: CanvasMiniMapTextNodeProvider.makeNodes(context:)
// 功能说明: 修改后 minimap 会把 markdown item 先视为 text 风格节点，阶段 1 只保证几何预览链稳定。
if let item = boardItem.textItem {
    itemWorldQuad = item.worldQuad
    itemID = item.id
    zIndex = item.zIndex
    isPreviewActive = context.inlineEditState?.mode == .text &&
        context.inlineEditState?.itemID == item.id
} else if let item = boardItem.markdownItem {
    itemWorldQuad = item.worldQuad
    itemID = item.id
    zIndex = item.zIndex
    isPreviewActive = false
} else {
    return nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名: makeNode(from:boardID:documentOrder:)
// 功能说明: 修改后几何 preview seed 已开始识别 markdown record，并把它映射成 text 风格节点。
case let .markdown(markdownRecord):
    return makeNode(
        boardID: boardID,
        documentOrder: documentOrder,
        id: markdownRecord.id,
        kind: .text,
        center: markdownRecord.center,
        size: markdownRecord.size,
        zIndex: markdownRecord.zIndex,
        rotationRadians: markdownRecord.rotationRadians
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:imageProvider:) / decodeMaxPixelSizesByFilename(from:geometry:)
// 功能说明: 修改后 thumbnail 渲染阶段 1 先把 markdown record 包成 BoardTextItemRecord 走现有文字绘制链。
case let .markdown(markdownItemRecord):
    drawTextItem(
        BoardTextItemRecord(
            id: markdownItemRecord.id,
            center: markdownItemRecord.center,
            size: markdownItemRecord.size,
            zIndex: markdownItemRecord.zIndex,
            text: markdownItemRecord.markdownSource,
            style: markdownItemRecord.style,
            rotationRadians: markdownItemRecord.rotationRadians
        ),
        geometry: geometry,
        in: context,
        traceContext: traceContext,
        documentOrder: traceContext.documentOrderByID[markdownItemRecord.id],
        renderOrder: renderOrder
    )

case .text, .markdown:
    continue
```

## 修改五：补阶段 1 定向测试

### 5.1 mapper / schema round-trip

#### 修改前

- 没有测试约束 markdown item 的 runtime/document 往返。
- 也没有测试去锁定“markdown 必须保留显式容器尺寸，而不是像 text 一样重算 intrinsic size”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift（修改前）
// 函数名: testBoardDocumentMapperRoundTripsMarkdownItemPreservingExplicitContainerSize()
// 功能说明: 修改前该测试不存在，markdown schema 往返契约没有被自动化锁住。
//
// 修改前: 文件中不存在该测试函数
```

#### 修改后

- 新增 markdown round-trip 测试，并把测试类标成 `@MainActor`，避免这次新增断言继续叠 actor 隔离警告。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数名: testBoardDocumentMapperRoundTripsMarkdownItemPreservingExplicitContainerSize()
// 功能说明: 新增 markdown runtime/document 往返测试，锁定 formatVersion=9 后的显式容器尺寸契约。
@MainActor
final class BoardSelectionStateMigrationTests: XCTestCase {
    func testBoardDocumentMapperRoundTripsMarkdownItemPreservingExplicitContainerSize() throws {
        let item = CanvasMarkdownItem(
            id: UUID(),
            markdownSource: "## Title\n\nBody",
            style: CanvasTextStyle(fontSize: 20),
            center: CGPoint(x: 140, y: 90),
            size: CGSize(width: 320, height: 180),
            zIndex: 2,
            rotationRadians: .pi / 12
        )

        let document = BoardDocumentMapper.makeDocument(from: runtimeState)
        let markdownRecord = try XCTUnwrap(document.markdownItemRecords.first)
        XCTAssertEqual(markdownRecord.size.cgSize, item.size)

        let roundTrippedState = try BoardDocumentMapper.makeRuntimeState(
            from: document,
            imageLoader: { _ in
                throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
            }
        )
        let roundTrippedItem = try XCTUnwrap(roundTrippedState.markdownItems.first)
        XCTAssertEqual(roundTrippedItem.size, item.size)
        XCTAssertNil(roundTrippedState.boardState)
    }
}
```

### 5.2 命令策略、内容字号与历史回退

#### 修改前

- `CanvasCommandPolicyParityTests` 没有任何 markdown 新命令的策略覆盖。
- 也没有测试 markdown 内容字号 `+/-` 是否会正确写历史并支持 undo/redo。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift（修改前）
// 函数名: testAddMarkdownDescriptorAndExecutorMatchPolicyInEditingMode() / testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo()
// 功能说明: 修改前这两类 markdown 阶段 1 测试不存在，命令骨架没有自动化约束。
//
// 修改前: 文件中不存在上述测试函数
```

#### 修改后

- 新增命令策略测试，验证 reading/editing 模式下 `addMarkdownItem` 的 descriptor / executor / policy 一致性。
- 新增内容字号测试，验证 `increaseMarkdownContentSize` 会改 `style.fontSize`、保留 `size`、并支持 `undo/redo`。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testAddMarkdownDescriptorAndExecutorMatchPolicyInEditingMode() / testAddMarkdownDescriptorAndExecutorMatchPolicyInReadingMode() / testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo()
// 功能说明: 新增 markdown 阶段 1 的命令策略与历史回退测试，锁定 command skeleton 的最小行为面。
func testAddMarkdownDescriptorAndExecutorMatchPolicyInEditingMode() {
    let descriptor = commandCatalog.descriptor(
        for: .addMarkdownItem,
        session: session
    )
    let decision = policy.commandDecision(
        for: .addMarkdownItem,
        workspaceMode: session.workspaceMode
    )

    XCTAssertEqual(decision, .allow)
    XCTAssertTrue(descriptor.isEnabled)
    XCTAssertTrue(executor.canExecute(.addMarkdownItem))
}

func testAddMarkdownDescriptorAndExecutorMatchPolicyInReadingMode() {
    let decision = policy.commandDecision(
        for: .addMarkdownItem,
        workspaceMode: session.workspaceMode
    )

    XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
    XCTAssertFalse(executor.canExecute(.addMarkdownItem))
}

func testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo() throws {
    let item = try XCTUnwrap(
        session.addMarkdownItem(
            markdownSource: "## Seed",
            style: initialStyle
        )
    )
    let originalItem = try XCTUnwrap(session.scene.markdownItem(withID: item.id))

    XCTAssertNotNil(executor.execute(.increaseMarkdownContentSize))

    let resizedItem = try XCTUnwrap(session.scene.markdownItem(withID: item.id))
    XCTAssertGreaterThan(resizedItem.style.fontSize, originalItem.style.fontSize)
    XCTAssertEqual(resizedItem.size, originalItem.size)

    XCTAssertNotNil(executor.execute(.undo))
    XCTAssertNotNil(executor.execute(.redo))
}
```

## 验证结果

- 已执行构建验证：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" build`
  - 结果：成功。
- 已执行定向测试：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" test -only-testing:MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests`
  - 结果：成功。
- 已检查本次改动涉及文件的 lints：
  - 结果：未发现新的 linter errors。

