# 20260323_125208_text_support_phase_t1_mixed_runtime_record

## 记录范围

- 记录内容：
  1. 在共享核心层新增 `CanvasTextItem`、`CanvasTextStyle`、`CanvasBoardItem`，为 text/image 共存建立 mixed runtime 基础类型。
  2. 将 `CanvasScene` 从只存 `[CanvasImageItem]` 改为底层存 `[CanvasBoardItem]`，并保留现有图片兼容接口。
  3. 将 `BoardRuntimeState.items` 与 `BoardHistorySnapshot.items` 升级为 mixed items，让运行时快照与 history 可以承载文本项。
  4. 在 `BoardDocumentMapper`、`BoardStore`、`BoardThumbnailRenderer` 中保留 `v2` image-only 桥接，避免在 `T-1` 阶段提前扩大文档格式。
  5. 将 `CanvasEditorSession` 的 runtime/history 快照来源切换到 `scene.orderedBoardItems()`。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 本记录不包含：
  - `BoardDocument v3` / mixed item 持久化格式
  - 文本渲染、文本 layer、文本 hit-test UI
  - 文本创建/编辑命令与工具栏入口
  - minimap / board list preview 的 text 节点
  - 原始 gif diff
  - git commit / push

## 修改一：新增共享 mixed item 类型与统一 item ID

### 修改前

- 共享层只有 `CanvasImageItemID`，还没有 text item 或 mixed item 容器。
- 仓库里不存在 `CanvasBoardItem.swift`，运行时层仍然默认“item == image”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: N/A（顶层类型别名）
// 功能说明: 修改前共享层只有图片专用的 item id，还没有为 text/image 共用的统一 id 留出命名边界。
typealias CanvasImageItemID = UUID
```

```text
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift
// 函数名: N/A（新文件）
// 功能说明: 修改前仓库中不存在 mixed item 类型文件；运行时还没有 `CanvasTextItem` 或 `CanvasBoardItem`。
[文件不存在]
```

### 修改后

- 新增 `CanvasItemID`，并让现有 `CanvasImageItemID` 变成它的别名，先统一 id 空间。
- 新增 `CanvasTextColor`、`CanvasTextStyle`、`CanvasTextItem`、`CanvasBoardItem`，把 text/image 共用的中心点、尺寸、旋转、zIndex、命中测试等运行时语义先建起来。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: N/A（顶层类型别名）
// 功能说明: 修改后先把共享 item id 抽成 `CanvasItemID`，为 image/text 共用选择态、命令参数和 z-order 语义铺路。
typealias CanvasItemID = UUID
typealias CanvasImageItemID = CanvasItemID
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift
// 函数名: N/A（类型定义文件）
// 功能说明: 修改后共享核心首次拥有 text item 与 mixed item 容器；T-1 先铺运行时模型，不提前进入渲染与持久化格式泛化。
enum CanvasBoardItemKind {
    case image
    case text
}

struct CanvasTextColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    static let black = CanvasTextColor(
        red: 0,
        green: 0,
        blue: 0,
        alpha: 1
    )
}

struct CanvasTextStyle: Equatable {
    private static let fallbackFontName = "System"

    var fontName: String
    var fontSize: CGFloat
    var color: CanvasTextColor

    static let `default` = CanvasTextStyle()
}

struct CanvasTextItem {
    let id: CanvasItemID
    var text: String
    var style: CanvasTextStyle
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat

    // 让 text item 和 image item 在 runtime 层先共用相同的几何语义。
    var localFrame: CGRect {
        CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    var worldQuad: CanvasQuad {
        localQuad.map(worldPoint(fromLocal:))
    }

    var worldBounds: CGRect { worldQuad.boundingRect }

    func contains(worldPoint: CGPoint) -> Bool {
        localFrame.contains(localPoint(fromWorld: worldPoint))
    }
}

enum CanvasBoardItem {
    case image(CanvasImageItem)
    case text(CanvasTextItem)

    var id: CanvasItemID {
        switch self {
        case let .image(item):
            return item.id
        case let .text(item):
            return item.id
        }
    }

    var imageItem: CanvasImageItem? {
        guard case let .image(item) = self else {
            return nil
        }

        return item
    }

    var textItem: CanvasTextItem? {
        guard case let .text(item) = self else {
            return nil
        }

        return item
    }
}
```

## 修改二：`CanvasScene` 升级为 mixed item 容器，但保留图片兼容接口

### 修改前

- `CanvasScene` 底层只存 `[CanvasImageItem]`。
- 选择、命中测试、移动、缩放、旋转、复制、z-order 全都只能作用于 image item。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: init(items:) / setItems(_:) / append(_:) / item(withID:) / topmostItem(containing:) / updateItem(withID:_:)
// 功能说明: 修改前 Scene 完全建立在 `[CanvasImageItem]` 之上，任何 item 级操作默认都只可能是图片。
final class CanvasScene {
    private(set) var items: [CanvasImageItem]

    init(items: [CanvasImageItem] = []) {
        self.items = items
    }

    func setItems(_ items: [CanvasImageItem]) {
        self.items = items
    }

    func append(_ item: CanvasImageItem) {
        items.append(item)
    }

    func item(withID id: CanvasImageItemID) -> CanvasImageItem? {
        items.first(where: { $0.id == id })
    }

    func topmostItem(containing worldPoint: CGPoint) -> CanvasImageItem? {
        orderedItems().reversed().first(where: { $0.contains(worldPoint: worldPoint) })
    }

    @discardableResult
    private func updateItem<T>(
        withID id: CanvasImageItemID,
        _ mutate: (inout CanvasImageItem) -> T
    ) -> T? {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return mutate(&items[index])
    }
}
```

### 修改后

- `CanvasScene` 底层改成 `[CanvasBoardItem]`。
- 新增 `boardItem(withID:)`、`textItem(withID:)`、`topmostBoardItem(containing:)`、`resizeBoardItem(...)`、`rotateBoardItem(...)`、`duplicateBoardItem(...)` 等 board-item 级 API。
- 同时保留 `item(withID:)`、`resizeItem(...)`、`rotateItem(...)`、`duplicateItem(...)` 这些 image-compatible 包装层，让当前控制器、渲染器和命令路径继续编译并保持原行为。
- `cropItem(...)` 仍然明确只走 `updateImageItem(...)`，防止 text item 提前误入 crop 逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: boardItem(withID:) / textItem(withID:) / topmostBoardItem(containing:) / resizeBoardItem(...) / rotateBoardItem(...) / duplicateBoardItem(...) / updateBoardItem(withID:_:) / updateImageItem(withID:_:)
// 功能说明: 修改后 Scene 的底层已经能承载 mixed items，但旧的 image-only API 仍被保留，作为 T-1 到 T-3 之间的兼容桥。
final class CanvasScene {
    private(set) var items: [CanvasBoardItem]

    init(items: [CanvasBoardItem] = []) {
        self.items = items
    }

    func setItems(_ items: [CanvasBoardItem]) {
        self.items = items
    }

    func append(_ item: CanvasBoardItem) {
        items.append(item)
    }

    func append(_ item: CanvasImageItem) {
        append(.image(item))
    }

    func append(_ item: CanvasTextItem) {
        append(.text(item))
    }

    func boardItem(withID id: CanvasItemID) -> CanvasBoardItem? {
        items.first(where: { $0.id == id })
    }

    func item(withID id: CanvasImageItemID) -> CanvasImageItem? {
        boardItem(withID: id)?.imageItem
    }

    func textItem(withID id: CanvasItemID) -> CanvasTextItem? {
        boardItem(withID: id)?.textItem
    }

    func topmostBoardItem(containing worldPoint: CGPoint) -> CanvasBoardItem? {
        orderedBoardItems().reversed().first(where: { $0.contains(worldPoint: worldPoint) })
    }

    func topmostItem(containing worldPoint: CGPoint) -> CanvasImageItem? {
        orderedItems().reversed().first(where: { $0.contains(worldPoint: worldPoint) })
    }

    func resizeBoardItem(
        withID id: CanvasItemID,
        toCenter center: CGPoint,
        size: CGSize
    ) -> CanvasBoardItem? {
        updateBoardItem(withID: id) { item in
            item.center = center
            item.size = size
            return item
        }
    }

    func rotateBoardItem(
        withID id: CanvasItemID,
        to rotationRadians: CGFloat
    ) -> CanvasBoardItem? {
        updateBoardItem(withID: id) { item in
            item.rotationRadians = normalizedCanvasAngle(rotationRadians)
            return item
        }
    }

    func duplicateBoardItem(
        withID id: CanvasItemID,
        offsetInWorld: CGPoint = .zero
    ) -> CanvasBoardItem? {
        var orderedItems = orderedBoardItems()
        guard let index = orderedItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let sourceItem = orderedItems[index]
        let duplicatedItem = duplicatedItem(
            from: sourceItem,
            offsetInWorld: offsetInWorld
        )
        orderedItems.insert(duplicatedItem, at: index + 1)
        items = normalizedZOrderItems(from: orderedItems)
        return boardItem(withID: duplicatedItem.id)
    }

    func cropItem(
        withID id: CanvasImageItemID,
        toNormalizedCropRect normalizedCropRect: CanvasImageCropRect
    ) -> CanvasImageItem? {
        updateImageItem(withID: id) { item in
            let updatedLocalFrame = item.localFrame(
                forNormalizedCropRect: normalizedCropRect
            ).standardized
            guard
                updatedLocalFrame.width > 0,
                updatedLocalFrame.height > 0
            else {
                return item
            }

            let updatedCenter = item.worldPoint(
                fromLocal: CGPoint(
                    x: updatedLocalFrame.midX,
                    y: updatedLocalFrame.midY
                )
            )
            item.cropRectNormalized = normalizedCropRect
            item.center = updatedCenter
            item.size = updatedLocalFrame.size
            return item
        }
    }

    @discardableResult
    private func updateBoardItem<T>(
        withID id: CanvasItemID,
        _ mutate: (inout CanvasBoardItem) -> T
    ) -> T? {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return mutate(&items[index])
    }

    @discardableResult
    private func updateImageItem<T>(
        withID id: CanvasImageItemID,
        _ mutate: (inout CanvasImageItem) -> T
    ) -> T? {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        guard case var .image(item) = items[index] else {
            return nil
        }

        let result = mutate(&item)
        items[index] = .image(item)
        return result
    }
}
```

## 修改三：`BoardRuntimeState` 与 `BoardHistorySnapshot` 承载 mixed items

### 修改前

- `BoardRuntimeState.items` 是 `[CanvasImageItem]`。
- `BoardHistorySnapshot.items` 也是 `[CanvasImageItem]`，历史相等性比较只覆盖图片的几何、crop、rotation 字段。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: N/A（BoardRuntimeState）
// 功能说明: 修改前运行时快照只能承载图片项，text item 还没有进入 board runtime 的数据模型。
struct BoardRuntimeState {
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var items: [CanvasImageItem]
    var boardState: CanvasBoardState?
    var camera: CanvasCamera
    var interactionState: CanvasInteractionState
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名: itemsMatch(_:_:)
// 功能说明: 修改前 history snapshot 完全建立在图片项上，文本内容和样式还没有被纳入 undo/redo 比较。
struct BoardHistorySnapshot {
    var items: [CanvasImageItem]
    var boardState: CanvasBoardState?
    var interactionState: CanvasInteractionState
}

private static func itemsMatch(
    _ lhsItems: [CanvasImageItem],
    _ rhsItems: [CanvasImageItem]
) -> Bool {
    guard lhsItems.count == rhsItems.count else {
        return false
    }

    return zip(lhsItems, rhsItems).allSatisfy { lhsItem, rhsItem in
        lhsItem.id == rhsItem.id &&
        lhsItem.center == rhsItem.center &&
        lhsItem.size == rhsItem.size &&
        lhsItem.zIndex == rhsItem.zIndex &&
        lhsItem.cropRectNormalized == rhsItem.cropRectNormalized &&
        lhsItem.rotationRadians == rhsItem.rotationRadians
    }
}
```

### 修改后

- `BoardRuntimeState.items` 升级为 `[CanvasBoardItem]`，并新增 `imageItems` / `textItems` 两个投影，方便在 `T-1` 阶段继续兼容现有图片持久化与缩略图路径。
- `BoardHistorySnapshot.items` 同样升级为 `[CanvasBoardItem]`，相等性比较开始区分 image/text 两种 case；text 会比较内容、样式、几何和 rotation。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: N/A（BoardRuntimeState）
// 功能说明: 修改后运行时快照已经能承载 image/text 混合项，同时通过投影属性保留 image-only 兼容桥接。
struct BoardRuntimeState {
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var items: [CanvasBoardItem]
    var boardState: CanvasBoardState?
    var camera: CanvasCamera
    var interactionState: CanvasInteractionState

    // T-1 keeps persistence and thumbnail generation on the existing image-only
    // path while runtime/history move to mixed item storage.
    var imageItems: [CanvasImageItem] {
        items.compactMap(\.imageItem)
    }

    var textItems: [CanvasTextItem] {
        items.compactMap(\.textItem)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名: itemsMatch(_:_:)
// 功能说明: 修改后 history snapshot 已经能够区分 image/text 两种 item，并为文本项比较内容、样式和几何字段。
struct BoardHistorySnapshot {
    var items: [CanvasBoardItem]
    var boardState: CanvasBoardState?
    var interactionState: CanvasInteractionState
}

private static func itemsMatch(
    _ lhsItems: [CanvasBoardItem],
    _ rhsItems: [CanvasBoardItem]
) -> Bool {
    guard lhsItems.count == rhsItems.count else {
        return false
    }

    return zip(lhsItems, rhsItems).allSatisfy { lhsItem, rhsItem in
        switch (lhsItem, rhsItem) {
        case let (.image(lhsImage), .image(rhsImage)):
            return lhsImage.id == rhsImage.id &&
                lhsImage.center == rhsImage.center &&
                lhsImage.size == rhsImage.size &&
                lhsImage.zIndex == rhsImage.zIndex &&
                lhsImage.cropRectNormalized == rhsImage.cropRectNormalized &&
                lhsImage.rotationRadians == rhsImage.rotationRadians
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
    }
}
```

## 修改四：在 `T-1` 阶段保留 image-only 持久化与缩略图桥接

### 修改前

- `BoardDocumentMapper.makeDocument(from:)` 直接把 `runtimeState.items` 映射到 `BoardImageItemRecord`。
- `BoardStore.saveBoard(...)` 直接遍历 `runtimeState.items` 写 PNG。
- `BoardThumbnailRenderer.renderPersistedThumbnail(...)` 直接把 `runtimeState.items` 建成 `runtimeItemsByID`。
- 这些路径都默认运行时 item 一定是图片。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeDocument(from:) / makeRuntimeState(from:imageLoader:)
// 功能说明: 修改前 mapper 的入参与出参都是 image-only；运行时和文档之间还不存在 mixed item 桥接。
static func makeDocument(from runtimeState: BoardRuntimeState) -> BoardDocument {
    BoardDocument(
        // ...
        items: runtimeState.items.map(makeImageRecord)
    )
}

static func makeRuntimeState(
    from document: BoardDocument,
    imageLoader: (BoardImageItemRecord) throws -> CGImage
) throws -> BoardRuntimeState {
    let items = try document.items.map { itemRecord in
        CanvasImageItem(
            id: itemRecord.id,
            cgImage: try imageLoader(itemRecord),
            center: itemRecord.center.cgPoint,
            size: itemRecord.size.cgSize,
            zIndex: CGFloat(itemRecord.zIndex),
            cropRectNormalized: itemRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
            rotationRadians: CGFloat(itemRecord.rotationRadians ?? 0)
        )
    }

    return BoardRuntimeState(
        // ...
        items: items,
        // ...
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: saveBoard(_:)
// 功能说明: 修改前 save path 默认 runtime items 全是图片，因此直接逐项写 PNG 资产。
for item in runtimeState.items {
    let assetURL = assetsDirectoryURL.appendingPathComponent(
        "\(item.id.uuidString).png"
    )
    let pngData = try makePNGData(for: item.cgImage, itemID: item.id)
    try CoordinatedFileIO.writeData(pngData, to: assetURL)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderPersistedThumbnail(for:maximumLongestSide:cancellationCheck:)
// 功能说明: 修改前运行时缩略图也默认 runtime items 全是图片，并直接从它们建立 id -> image 映射。
guard runtimeState.items.isEmpty == false else {
    return nil
}

let runtimeItemsByID = Dictionary(
    uniqueKeysWithValues: runtimeState.items.map { ($0.id, $0) }
)
```

### 修改后

- `BoardDocumentMapper.makeDocument(from:)` 先取 `runtimeState.imageItems`，并用 `assert` 明确声明：`T-1` 还只能把 image-only runtime 落回 `v2` 文档格式。
- `makeRuntimeState(from:imageLoader:)` 读回来的图片项会被包进 `.image(...)`。
- `BoardStore.saveBoard(...)` 和 `BoardThumbnailRenderer.renderPersistedThumbnail(...)` 改成只消费 `imageItems` 投影，这样 mixed runtime 已经存在，但 `T-1` 还不会误把文本项写成 PNG 资产。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeDocument(from:) / makeRuntimeState(from:imageLoader:)
// 功能说明: 修改后 mapper 在 T-1 阶段只把 image projection 落回旧文档格式，同时把已加载的图片项包装成 `.image(...)` 进入 mixed runtime。
static func makeDocument(from runtimeState: BoardRuntimeState) -> BoardDocument {
    let imageItems = runtimeState.imageItems
    assert(
        imageItems.count == runtimeState.items.count,
        "BoardDocument v2 can only persist image items before T-2."
    )

    return BoardDocument(
        // ...
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

    return BoardRuntimeState(
        // ...
        items: items,
        // ...
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: saveBoard(_:)
// 功能说明: 修改后 save path 只遍历 `persistedState.imageItems`，为 T-1 阶段的 mixed runtime 保留 image-only 资产写入边界。
var persistedState = runtimeState
persistedState.updatedAt = Date()
let document = BoardDocumentMapper.makeDocument(from: persistedState)

for item in persistedState.imageItems {
    let assetURL = assetsDirectoryURL.appendingPathComponent(
        "\(item.id.uuidString).png"
    )
    let pngData = try makePNGData(for: item.cgImage, itemID: item.id)
    try CoordinatedFileIO.writeData(pngData, to: assetURL)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderPersistedThumbnail(for:maximumLongestSide:cancellationCheck:)
// 功能说明: 修改后运行时缩略图也只消费 image projection，避免 T-1 阶段的 mixed runtime 直接冲击现有图片缩略图管线。
let runtimeImageItems = runtimeState.imageItems
guard runtimeImageItems.isEmpty == false else {
    return nil
}

let runtimeItemsByID = Dictionary(
    uniqueKeysWithValues: runtimeImageItems.map { ($0.id, $0) }
)
```

## 修改五：`CanvasEditorSession` 的 runtime/history 快照切到 mixed item 顺序

### 修改前

- `currentBoardHistorySnapshot()` 和 `currentBoardRuntimeState()` 都直接取 `scene.orderedItems()`。
- `nextImageZIndex()` 也是基于 image-only 顺序计算。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: currentBoardHistorySnapshot() / currentBoardRuntimeState(createBoardIfNeeded:) / nextImageZIndex()
// 功能说明: 修改前 session 里生成 snapshot 与 z-order 的地方都只看图片项，text item 还不会进入共享 runtime 快照。
func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
    BoardHistorySnapshot(
        items: scene.orderedItems(),
        boardState: boardState,
        interactionState: interactionState
    )
}

func currentBoardRuntimeState(
    createBoardIfNeeded: Bool = false
) -> BoardRuntimeState? {
    // ...
    return BoardRuntimeState(
        // ...
        items: scene.orderedItems(),
        // ...
    )
}

func nextImageZIndex() -> CGFloat {
    (scene.orderedItems().last?.zIndex ?? -1) + 1
}
```

### 修改后

- `currentBoardHistorySnapshot()` 和 `currentBoardRuntimeState()` 改为直接保留 `scene.orderedBoardItems()`。
- `nextImageZIndex()` 也基于全体 board items 计算，从而保证未来 text/image 混排时，后插入图片仍能拿到正确的顶层 zIndex。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: currentBoardHistorySnapshot() / currentBoardRuntimeState(createBoardIfNeeded:) / nextImageZIndex()
// 功能说明: 修改后 session 的 snapshot 与 z-order 入口已经切到 mixed item 顺序，为后续 text/image 混排保留统一基础。
func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
    BoardHistorySnapshot(
        items: scene.orderedBoardItems(),
        boardState: boardState,
        interactionState: interactionState
    )
}

func currentBoardRuntimeState(
    createBoardIfNeeded: Bool = false
) -> BoardRuntimeState? {
    // ...
    return BoardRuntimeState(
        // ...
        items: scene.orderedBoardItems(),
        // ...
    )
}

func nextImageZIndex() -> CGFloat {
    (scene.orderedBoardItems().last?.zIndex ?? -1) + 1
}
```

## 结果

- 到 `T-1` 为止，运行时、Scene、history 的“item == image”假设已经被拆开，mixed runtime 骨架已经具备。
- 当前代码已经能在共享层承载 `CanvasTextItem`，但这还只是 runtime 层面的能力，文本还没有进入渲染、命令/UI 和持久化格式。
- `BoardDocument.currentFormatVersion` 仍然是 `2`；`BoardDocumentMapper.makeDocument(from:)` 也通过 `assert` 明确限制：在 `T-2` 之前，只允许 image-only runtime 正式落盘。

## 验证

```text
// 验证说明: 本阶段完成后，对最近修改文件执行 IDE lints 检查，并对全部 Swift 源文件执行 swiftc typecheck。
- ReadLints:
  - `MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - 结果：无错误

- swiftc -typecheck:
  - 范围：`MyCanvas_Ver_0` 下全部 `.swift` 源文件
  - 结果：通过
```
