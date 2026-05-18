# 20260518_121830_hand_drawing_phase3_rendering_geometry_record

## 记录范围

- 记录内容：
  1. 为 handDrawing 拆出独立 `CanvasRenderPayload.handDrawing`，不再借用 `image` 业务语义。
  2. 为 handDrawing 补齐纸张等比缩放、几何写入约束与复制后的尺寸归一化逻辑。
  3. 打通 handDrawing 复制后的 transient payload 注册与保存链，确保新 `itemID` 对应的新资产路径可落盘。
  4. 在 iOS/macOS viewport 增加 handDrawing layer 协调，并为空白手绘 block 补上可见白纸外观。
  5. 新增阶段 3 的几何与存储测试。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S"` -> `20260518_121830`
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift`
- 当前工作区涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift`
- 本记录不包含：
  - 阶段 4 的 minimap / `BoardPreviewSeed` / board list 缩略图
  - 阶段 5 的 iOS PencilKit 全屏编辑器与入口编排
  - git commit / push

## 修改一：渲染快照为 handDrawing 拆出独立 payload

### 修改前

- `CanvasRenderPayload` 只有 `image` / `text` 两种 payload。
- `makeHandDrawingRenderItem(...)` 虽然已经有独立函数，但最后仍然把手绘预览包装成 `.image(CanvasImageRenderPayload)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasRenderPayload / CanvasImageRenderPayload
// 功能说明: 修改前渲染快照只能区分 image 与 text，handDrawing 没有独立渲染语义。
struct CanvasImageRenderPayload {
    let displayContract: CanvasImageDisplayContract
    let contentsRect: CGRect
}

struct CanvasTextRenderPayload {
    let text: String
    let style: CanvasTextStyle
    let zoomScale: CGFloat
}

enum CanvasRenderPayload {
    case image(CanvasImageRenderPayload)
    case text(CanvasTextRenderPayload)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeHandDrawingRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改前 handDrawing 的预览图最终仍回落到 image payload，viewport 无法从 payload 层分辨图片与手绘。
return CanvasRenderItem(
    id: effectiveHandDrawingItem.id,
    // ... 几何字段未改动
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
)
```

### 修改后

- 新增 `CanvasHandDrawingRenderPayload`，显式携带 `previewAssetReference`、`previewCGImage`、`paper`、`isEmpty`。
- `makeHandDrawingRenderItem(...)` 现在输出 `.handDrawing(...)`，后续 viewport / minimap / preview 链能按 item 语义分支，而不是再把手绘当图片特判。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasHandDrawingRenderPayload / CanvasRenderPayload
// 功能说明: 修改后渲染快照新增 handDrawing 专用 payload，主画布消费层可以按类型明确分流。
struct CanvasImageRenderPayload {
    let displayContract: CanvasImageDisplayContract
    let contentsRect: CGRect
}

struct CanvasHandDrawingRenderPayload {
    let previewAssetReference: CanvasImageAssetReference
    let previewCGImage: CGImage
    let paper: CanvasHandDrawingPaperSpec
    let isEmpty: Bool
}

struct CanvasTextRenderPayload {
    let text: String
    let style: CanvasTextStyle
    let zoomScale: CGFloat
}

enum CanvasRenderPayload {
    case image(CanvasImageRenderPayload)
    case handDrawing(CanvasHandDrawingRenderPayload)
    case text(CanvasTextRenderPayload)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeHandDrawingRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改后 handDrawing 的渲染载荷独立输出，只保留纸张规格、空白态和预览图这类主画布需要的显示信息。
return CanvasRenderItem(
    id: effectiveHandDrawingItem.id,
    screenFrame: screenQuad.boundingRect.standardized,
    screenQuad: screenQuad,
    screenCenter: camera.worldToViewport(effectiveHandDrawingItem.center),
    screenBoundsSize: CGSize(
        width: effectiveHandDrawingItem.size.width * camera.zoomScale,
        height: effectiveHandDrawingItem.size.height * camera.zoomScale
    ),
    rotationRadians: effectiveHandDrawingItem.rotationRadians,
    zIndex: effectiveHandDrawingItem.zIndex,
    payload: .handDrawing(
        CanvasHandDrawingRenderPayload(
            previewAssetReference: effectiveHandDrawingItem.previewAsset.reference,
            previewCGImage: effectiveHandDrawingItem.previewAsset.posterCGImage,
            paper: effectiveHandDrawingItem.paper,
            isEmpty: effectiveHandDrawingItem.isEmpty
        )
    )
)
```

## 修改二：手绘纸张比例不再跟随任意几何写入被拉扁

### 修改前

- `CanvasHandDrawingItem` 本身没有“按纸张规格归一化尺寸”的 helper。
- `CanvasSelectionTransformState` 在 `handDrawing` 分支里直接走 `item.applyingGeometry(...)`，与图片共用同一套尺寸写入方式。
- `CanvasScene` 的 `resizeBoardItem(...)` 也是直接把 `center/size` 写回 item，没有给 handDrawing 留专用约束入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift
// 函数名: duplicated(offsetInWorld:)
// 功能说明: 修改前 handDrawing 复制时直接复用原 size；这里没有纸张比例归一化逻辑。
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
        center: CGPoint(
            x: center.x + offsetInWorld.x,
            y: center.y + offsetInWorld.y
        ),
        size: size,
        zIndex: zIndex,
        rotationRadians: rotationRadians
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数名: resizedItem(_:using:) / CanvasBoardItem.applyingGeometry(_:)
// 功能说明: 修改前 handDrawing 和 image 一样直接吃缩放后的 geometry，缺少“锁定纸张宽高比”的专用分支。
private func resizedItem(
    _ item: CanvasBoardItem,
    using resizeDraft: CanvasSelectionResizeDraft
) -> CanvasBoardItem {
    let scaledItemGeometry = scaledGeometry(
        from: CanvasBoardItemGeometry(item: item),
        using: resizeDraft
    )
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
    case .handDrawing:
        return item.applyingGeometry(scaledItemGeometry) ?? item
    }
}

extension CanvasBoardItem {
    func applyingGeometry(
        _ geometry: CanvasBoardItemGeometry
    ) -> CanvasBoardItem? {
        // ... 前置 guard 未改动
        var updatedItem = self
        updatedItem.center = geometry.center
        updatedItem.size = geometry.size
        updatedItem.rotationRadians = geometry.rotationRadians
        return updatedItem
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: resizeBoardItem(withID:toCenter:size:) / resizeBoardItem(withID:toLocalFrame:)
// 功能说明: 修改前 Scene 直接把 size 写回 board item，没有 handDrawing 专用的尺寸归一化入口。
return updateBoardItem(withID: id) { item in
    item.center = center
    item.size = size
    return item
}

return updateBoardItem(withID: id) { item in
    item.center = item.worldPoint(
        fromLocal: CGPoint(
            x: standardizedLocalFrame.midX,
            y: standardizedLocalFrame.midY
        )
    )
    item.size = standardizedLocalFrame.size
    return item
}
```

### 修改后

- `CanvasHandDrawingItem` 新增 `currentPaperScale`、`normalizedCanvasSize(for:)`、`scaledCanvasSize(by:)`、`resized(...)`，把“纸张规格 -> 画布显示尺寸”的归一化规则收口到模型层。
- `CanvasSelectionTransformState` 为 handDrawing 单独走 `resizedHandDrawingItem(...)`，多选缩放时不再把纸张比例拉扁。
- `CanvasBoardItem.applyingGeometry(...)` 与 `CanvasScene.resizedBoardItem(...)` 都对 handDrawing 特化，单选 resize / group resize / duplicated item 都统一落到同一套比例约束。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingItem.swift
// 函数名: currentPaperScale / normalizedCanvasSize(for:) / scaledCanvasSize(by:) / resized(...) / duplicated(offsetInWorld:)
// 功能说明: 修改后 handDrawing 自己负责把任意几何输入归一化回纸张宽高比，复制时也不再原样继承可能失真的 size。
var currentPaperScale: CGFloat {
    let resolvedPaperSize = paper.size
    let widthScale = size.width / max(
        resolvedPaperSize.width,
        Self.minimumCanvasDimension
    )
    let heightScale = size.height / max(
        resolvedPaperSize.height,
        Self.minimumCanvasDimension
    )
    return max(widthScale, heightScale)
}

func normalizedCanvasSize(for proposedSize: CGSize) -> CGSize {
    let resolvedPaperSize = paper.size
    let sanitizedSize = CGSize(
        width: max(proposedSize.width, Self.minimumCanvasDimension),
        height: max(proposedSize.height, Self.minimumCanvasDimension)
    )
    let widthScale = sanitizedSize.width / max(
        resolvedPaperSize.width,
        Self.minimumCanvasDimension
    )
    let heightScale = sanitizedSize.height / max(
        resolvedPaperSize.height,
        Self.minimumCanvasDimension
    )
    let resolvedScale = max(widthScale, heightScale)
    return CGSize(
        width: max(
            resolvedPaperSize.width * resolvedScale,
            Self.minimumCanvasDimension
        ),
        height: max(
            resolvedPaperSize.height * resolvedScale,
            Self.minimumCanvasDimension
        )
    )
}

func resized(
    center: CGPoint,
    proposedSize: CGSize,
    rotationRadians: CGFloat? = nil
) -> CanvasHandDrawingItem {
    CanvasHandDrawingItem(
        id: id,
        paper: paper,
        previewAsset: previewAsset,
        isEmpty: isEmpty,
        contentRevision: contentRevision,
        center: center,
        size: normalizedCanvasSize(for: proposedSize),
        zIndex: zIndex,
        rotationRadians: rotationRadians ?? self.rotationRadians
    )
}

func duplicated(offsetInWorld: CGPoint) -> CanvasHandDrawingItem {
    let duplicatedID = UUID()
    return CanvasHandDrawingItem(
        id: duplicatedID,
        // ... 其余字段未改动
        size: normalizedCanvasSize(for: size),
        zIndex: zIndex,
        rotationRadians: rotationRadians
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数名: resizedItem(_:using:) / resizedHandDrawingItem(_:scaledCenter:scale:) / CanvasBoardItem.applyingGeometry(_:)
// 功能说明: 修改后 handDrawing 在多选缩放和通用 geometry 写入时都走专用归一化路径，而不是继续和 image 共用裸 size 写回。
private func resizedItem(
    _ item: CanvasBoardItem,
    using resizeDraft: CanvasSelectionResizeDraft
) -> CanvasBoardItem {
    let scaledItemGeometry = scaledGeometry(
        from: CanvasBoardItemGeometry(item: item),
        using: resizeDraft
    )
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
    case let .handDrawing(handDrawingItem):
        return .handDrawing(
            resizedHandDrawingItem(
                handDrawingItem,
                scaledCenter: scaledItemGeometry.center,
                scale: resizeDraft.scale
            )
        )
    }
}

private func resizedHandDrawingItem(
    _ item: CanvasHandDrawingItem,
    scaledCenter: CGPoint,
    scale: CGFloat
) -> CanvasHandDrawingItem {
    item.resized(
        center: scaledCenter,
        proposedSize: item.scaledCanvasSize(by: scale)
    )
}

extension CanvasBoardItem {
    func applyingGeometry(
        _ geometry: CanvasBoardItemGeometry
    ) -> CanvasBoardItem? {
        // ... 前置 guard 未改动
        switch self {
        case .image, .text:
            var updatedItem = self
            updatedItem.center = geometry.center
            updatedItem.size = geometry.size
            updatedItem.rotationRadians = geometry.rotationRadians
            return updatedItem
        case let .handDrawing(item):
            return .handDrawing(
                item.resized(
                    center: geometry.center,
                    proposedSize: geometry.size,
                    rotationRadians: geometry.rotationRadians
                )
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: resizeBoardItem(withID:toCenter:size:) / resizeBoardItem(withID:toLocalFrame:) / resizedBoardItem(_:toCenter:size:)
// 功能说明: 修改后 Scene 把 handDrawing 的几何写入收口到 resizedBoardItem(...)，单选 resize 与旋转态 resize 都走同一条比例安全路径。
return updateBoardItem(withID: id) { item in
    item = resizedBoardItem(
        item,
        toCenter: center,
        size: size
    )
    return item
}

return updateBoardItem(withID: id) { item in
    item = resizedBoardItem(
        item,
        toCenter: item.worldPoint(
            fromLocal: CGPoint(
                x: standardizedLocalFrame.midX,
                y: standardizedLocalFrame.midY
            )
        ),
        size: standardizedLocalFrame.size
    )
    return item
}

private func resizedBoardItem(
    _ item: CanvasBoardItem,
    toCenter center: CGPoint,
    size: CGSize
) -> CanvasBoardItem {
    switch item {
    case .image, .text:
        var resizedItem = item
        resizedItem.center = center
        resizedItem.size = size
        return resizedItem
    case let .handDrawing(handDrawingItem):
        return .handDrawing(
            handDrawingItem.resized(
                center: center,
                proposedSize: size
            )
        )
    }
}
```

## 修改三：复制后的 handDrawing 现在会带着新资产路径进入保存链

### 修改前

- `BoardTransientHandDrawingAssetPayload` 只能承载 `previewImageData`，不能直接接受 duplicated item 的 `previewCGImage`。
- `CanvasEditorSession` 只有图片的 transient payload 字典；`duplicateItem(...)` / `duplicateSelection(...)` 只复制场景 item，不会给新 handDrawing 注册源笔迹与预览图 payload。
- `BoardStore.persistHandDrawingAssetsIfNeeded(...)` 只能消费 `previewImageData`，不能在保存期把 `CGImage` 转成 PNG。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift
// 函数名: BoardTransientHandDrawingAssetPayload.init(...)
// 功能说明: 修改前 handDrawing transient payload 只接受 previewImageData，复制出的新 item 不能直接用 runtime CGImage 注册保存材料。
struct BoardTransientHandDrawingAssetPayload {
    let itemID: CanvasItemID
    let drawingData: Data
    let previewImageData: Data

    init(
        itemID: CanvasItemID,
        drawingData: Data,
        previewImageData: Data
    ) {
        self.itemID = itemID
        self.drawingData = drawingData
        self.previewImageData = previewImageData
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: duplicateItem(...) / currentBoardSaveSnapshot(...)
// 功能说明: 修改前会话层没有 handDrawing transient payload 容器；复制后只新增 item，保存快照里 handDrawing payload 仍然是空字典。
private var transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload] = [:]

func duplicateItem(
    withID itemID: CanvasItemID,
    selectDuplicatedItem: Bool = false,
    recordHistory: Bool = false
) -> CanvasBoardItem? {
    guard canDuplicateItem(withID: itemID) else {
        return nil
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    guard let duplicatedItem = scene.duplicateBoardItem(
        withID: itemID,
        offsetInWorld: duplicateOffsetInWorld()
    ) else {
        return nil
    }

    // ... 后续只处理选区、历史、board 扩展
    return duplicatedItem
}

func currentBoardSaveSnapshot(
    createBoardIfNeeded: Bool = false,
    updateKind: BoardPersistenceUpdateKind = .contentAndViewState
) -> BoardSaveSnapshot? {
    // ... runtimeState / image payload 过滤逻辑未改动
    return BoardSaveSnapshot(
        runtimeState: runtimeState,
        transientImageAssetPayloads: payloads,
        transientHandDrawingAssetPayloads: [:],
        updateKind: updateKind
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: persistHandDrawingAssetsIfNeeded(for:snapshot:in:)
// 功能说明: 修改前保存链只会把 payload.previewImageData 原样写盘，无法在保存期兜底编码 previewCGImage。
private static func persistHandDrawingAssetsIfNeeded(
    for item: CanvasHandDrawingItem,
    snapshot: BoardSaveSnapshot,
    in assetsDirectoryURL: URL
) throws {
    let assetLocator = BoardHandDrawingAssetLocator(itemID: item.id)
    let previewImageURL = assetLocator.previewImageURL(in: assetsDirectoryURL)
    let sourceDrawingURL = assetLocator.sourceDrawingURL(in: assetsDirectoryURL)

    if let payload = snapshot.transientHandDrawingAssetPayload(for: item.id) {
        try CoordinatedFileIO.writeData(payload.drawingData, to: sourceDrawingURL)
        try CoordinatedFileIO.writeData(
            payload.previewImageData,
            to: previewImageURL
        )
        return
    }

    // ... 后续沿用已有资产存在性校验
}
```

### 修改后

- `BoardTransientHandDrawingAssetPayload` 现在支持 `previewImageData` 或 `previewCGImage` 二选一。
- `CanvasEditorSession` 新增 `transientHandDrawingAssetPayloads`，复制前先解析源 `.pkdrawing` 数据，复制后按新 `itemID` 注册 payload，并在 `currentBoardSaveSnapshot(...)` 里只保留当前 runtimeState 引用到的 handDrawing payload。
- `BoardStore` 保存时如果拿到的是 `previewCGImage`，会在持久化阶段即时编码为 PNG，再写到 `<itemID>.png`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift
// 函数名: BoardTransientHandDrawingAssetPayload.init(...)
// 功能说明: 修改后 handDrawing transient payload 既可以携带现成 PNG data，也可以只携带 runtime CGImage，让复制链不必提前编码。
struct BoardTransientHandDrawingAssetPayload {
    let itemID: CanvasItemID
    let drawingData: Data
    let previewImageData: Data?
    let previewCGImage: CGImage?

    init(
        itemID: CanvasItemID,
        drawingData: Data,
        previewImageData: Data
    ) {
        self.itemID = itemID
        self.drawingData = drawingData
        self.previewImageData = previewImageData
        previewCGImage = nil
    }

    init(
        itemID: CanvasItemID,
        drawingData: Data,
        previewCGImage: CGImage
    ) {
        self.itemID = itemID
        self.drawingData = drawingData
        previewImageData = nil
        self.previewCGImage = previewCGImage
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: transientHandDrawingAssetPayload(...) / duplicateItem(...) / duplicateSelection(...) / currentBoardSaveSnapshot(...) / preparedHandDrawingDuplicationSourceData(...) / registerDuplicatedHandDrawingPayloads(...)
// 功能说明: 修改后会话层会为 duplicated handDrawing 提前准备 drawingData 与 previewCGImage，并在保存快照中过滤出仍被当前 board 引用的 payload。
private var transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload] = [:]
private var transientHandDrawingAssetPayloads: [CanvasItemID: BoardTransientHandDrawingAssetPayload] = [:]

func transientHandDrawingAssetPayload(
    for itemID: CanvasItemID
) -> BoardTransientHandDrawingAssetPayload? {
    transientHandDrawingAssetPayloads[itemID]
}

func duplicateItem(
    withID itemID: CanvasItemID,
    selectDuplicatedItem: Bool = false,
    recordHistory: Bool = false
) -> CanvasBoardItem? {
    let sourceItems = scene.orderedBoardItems().filter { $0.id == itemID }
    guard
        let sourceDrawingDataByItemID = preparedHandDrawingDuplicationSourceData(
            for: sourceItems
        )
    else {
        return nil
    }
    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    guard let duplicatedItem = scene.duplicateBoardItem(
        withID: itemID,
        offsetInWorld: duplicateOffsetInWorld()
    ) else {
        return nil
    }
    registerDuplicatedHandDrawingPayloads(
        sourceItems: sourceItems,
        duplicatedItems: [duplicatedItem],
        sourceDrawingDataByItemID: sourceDrawingDataByItemID
    )
    // ... 后续选区与历史逻辑未改动
    return duplicatedItem
}

func currentBoardSaveSnapshot(
    createBoardIfNeeded: Bool = false,
    updateKind: BoardPersistenceUpdateKind = .contentAndViewState
) -> BoardSaveSnapshot? {
    // ... runtimeState / image payload 过滤逻辑未改动
    let referencedHandDrawingItemIDs = Set(
        runtimeState.handDrawingItems.map(\.id)
    )
    let handDrawingPayloads = Dictionary(
        uniqueKeysWithValues: transientHandDrawingAssetPayloads.filter {
            referencedHandDrawingItemIDs.contains($0.key)
        }
    )
    return BoardSaveSnapshot(
        runtimeState: runtimeState,
        transientImageAssetPayloads: payloads,
        transientHandDrawingAssetPayloads: handDrawingPayloads,
        updateKind: updateKind
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: persistHandDrawingAssetsIfNeeded(for:snapshot:in:)
// 功能说明: 修改后保存链允许 duplicated handDrawing 只带 previewCGImage 进入快照，并在持久化时统一编码为 PNG。
private static func persistHandDrawingAssetsIfNeeded(
    for item: CanvasHandDrawingItem,
    snapshot: BoardSaveSnapshot,
    in assetsDirectoryURL: URL
) throws {
    let assetLocator = BoardHandDrawingAssetLocator(itemID: item.id)
    let previewImageURL = assetLocator.previewImageURL(in: assetsDirectoryURL)
    let sourceDrawingURL = assetLocator.sourceDrawingURL(in: assetsDirectoryURL)

    if let payload = snapshot.transientHandDrawingAssetPayload(for: item.id) {
        try CoordinatedFileIO.writeData(payload.drawingData, to: sourceDrawingURL)
        let previewImageData: Data
        if let encodedPreviewImageData = payload.previewImageData {
            previewImageData = encodedPreviewImageData
        } else if let previewCGImage = payload.previewCGImage {
            previewImageData = try makePNGData(
                for: previewCGImage,
                itemID: item.id
            )
        } else {
            throw BoardStoreError.missingHandDrawingAssetPayload(itemID: item.id)
        }
        try CoordinatedFileIO.writeData(previewImageData, to: previewImageURL)
        return
    }

    guard try CoordinatedFileIO.modificationDate(at: previewImageURL) != nil else {
        throw BoardStoreError.missingHandDrawingAssetPayload(itemID: item.id)
    }
    try validateHandDrawingSourceAssetExists(
        at: sourceDrawingURL,
        filename: assetLocator.sourceDrawingFilename
    )
}
```

## 修改四：iOS / macOS viewport 为 handDrawing 单独建 layer 协调并补白纸外观

### 修改前

- iOS/macOS 两端 viewport 都只有 `imageLayers` / `textLayers`。
- `refreshItemLayers()` 只识别 `.image` / `.text`，handDrawing 在渲染层没有独立 layer registry，也没有空白纸面的显示样式。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshItemLayers() / imageLayer(for:)
// 功能说明: 修改前 iOS viewport 只维护图片和文本 layer，handDrawing 仍被迫依赖 image 语义。
private var imageLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var textLayers: [CanvasItemID: CanvasTextLayer] = [:]

private func refreshItemLayers() {
    let incomingImageIDs = Set(
        snapshot.items.compactMap { item in
            if case .image = item.payload {
                return item.id
            }
            return nil
        }
    )
    let incomingTextIDs = Set(
        snapshot.items.compactMap { item in
            if case .text = item.payload {
                return item.id
            }
            return nil
        }
    )

    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            let imageLayer = imageLayer(for: item.id)
            refreshImageLayer(
                imageLayer,
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        case let .text(textPayload):
            let textLayer = textLayer(for: item.id)
            textLayer.update(
                with: item,
                textPayload: textPayload,
                contentsScale: contentsScale
            )
        }
    }
}
```

### 修改后

- iOS / macOS 两端都新增 `handDrawingLayers`，并在 `refreshItemLayers()` 里单独追踪 `incomingHandDrawingIDs`。
- `refreshHandDrawingLayer(...)` 内部仍复用 `CanvasImageLayer.updateStaticPresentation(...)`，但外层分支已经按 handDrawing 语义分开。
- 新增 `applyHandDrawingAppearance(...)`，给空白手绘 block 提供白纸背景和边框，避免“空白 block 看不见”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshItemLayers() / refreshHandDrawingLayer(_:with:handDrawingPayload:contentsScale:) / applyHandDrawingAppearance(to:isEmpty:contentsScale:)
// 功能说明: 修改后 iOS viewport 为 handDrawing 建立独立 layer 协调，同时给空白纸面补上白底和边框样式。
private static let handDrawingPaperFillColor = CGColor(gray: 1, alpha: 1)
private static let handDrawingBorderColor = CGColor(
    red: 0.82,
    green: 0.84,
    blue: 0.88,
    alpha: 1
)
private static let emptyHandDrawingBorderColor = CGColor(
    red: 0.68,
    green: 0.72,
    blue: 0.78,
    alpha: 1
)
private static let handDrawingBorderLineWidth: CGFloat = 1
private static let handDrawingCornerRadius: CGFloat = 10

private var imageLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var handDrawingLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var textLayers: [CanvasItemID: CanvasTextLayer] = [:]

private func refreshItemLayers() {
    let incomingHandDrawingIDs = Set(
        snapshot.items.compactMap { item in
            if case .handDrawing = item.payload {
                return item.id
            }
            return nil
        }
    )

    for removedID in existingHandDrawingIDs.subtracting(incomingHandDrawingIDs) {
        handDrawingLayers[removedID]?.removeFromSuperlayer()
        handDrawingLayers[removedID] = nil
    }

    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            // ... 既有图片逻辑未改动
            refreshImageLayer(imageLayer(for: item.id), with: item, imagePayload: imagePayload, contentsScale: contentsScale)
        case let .handDrawing(handDrawingPayload):
            let handDrawingLayer = handDrawingLayer(for: item.id)
            refreshHandDrawingLayer(
                handDrawingLayer,
                with: item,
                handDrawingPayload: handDrawingPayload,
                contentsScale: contentsScale
            )
        case let .text(textPayload):
            textLayer(for: item.id).update(
                with: item,
                textPayload: textPayload,
                contentsScale: contentsScale
            )
        }
    }
}

private func applyHandDrawingAppearance(
    to handDrawingLayer: CanvasImageLayer,
    isEmpty: Bool,
    contentsScale: CGFloat
) {
    handDrawingLayer.backgroundColor = Self.handDrawingPaperFillColor
    handDrawingLayer.borderColor = isEmpty
        ? Self.emptyHandDrawingBorderColor
        : Self.handDrawingBorderColor
    handDrawingLayer.borderWidth = Self.handDrawingBorderLineWidth / max(contentsScale, 1)
    handDrawingLayer.cornerRadius = Self.handDrawingCornerRadius
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshItemLayers() / refreshHandDrawingLayer(_:with:handDrawingPayload:contentsScale:) / handDrawingLayer(for:)
// 功能说明: 修改后 macOS viewport 也同步建立 handDrawing layer registry，保证“macOS 仅预览”路径和 iOS 主画布渲染行为一致。
private var imageLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var handDrawingLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var textLayers: [CanvasItemID: CanvasTextLayer] = [:]

private func refreshItemLayers() {
    let incomingHandDrawingIDs = Set(
        snapshot.items.compactMap { item in
            if case .handDrawing = item.payload {
                return item.id
            }
            return nil
        }
    )

    for removedID in existingHandDrawingIDs.subtracting(incomingHandDrawingIDs) {
        handDrawingLayers[removedID]?.removeFromSuperlayer()
        handDrawingLayers[removedID] = nil
    }

    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            refreshImageLayer(
                imageLayer(for: item.id),
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        case let .handDrawing(handDrawingPayload):
            let handDrawingLayer = handDrawingLayer(for: item.id)
            refreshHandDrawingLayer(
                handDrawingLayer,
                with: item,
                handDrawingPayload: handDrawingPayload,
                contentsScale: contentsScale
            )
        case let .text(textPayload):
            textLayer(for: item.id).update(
                with: item,
                textPayload: textPayload,
                contentsScale: contentsScale
            )
        }
    }
}

private func handDrawingLayer(for itemID: CanvasItemID) -> CanvasImageLayer {
    if let handDrawingLayer = handDrawingLayers[itemID] {
        return handDrawingLayer
    }

    let handDrawingLayer = CanvasImageLayer(itemID: itemID)
    itemsLayer.addSublayer(handDrawingLayer)
    handDrawingLayers[itemID] = handDrawingLayer
    return handDrawingLayer
}
```

## 修改五：为阶段 3 补齐几何约束与复制持久化测试

### 修改前

- `CanvasSelectionTransformStateTests` 只覆盖平移、旋转、文本缩放，不覆盖 handDrawing 的等比缩放。
- `BoardHandDrawingStorageTests` 只覆盖首次保存和覆盖写，不覆盖 duplicated handDrawing 的新资产路径落盘。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift
// 函数名: testResizedMemberItemsScaleTextFontSizeAndRecomputeIntrinsicSize()
// 功能说明: 修改前这里的缩放测试只覆盖 text/image 混合场景，还没有 handDrawing 纸张比例约束用例。
func testResizedMemberItemsScaleTextFontSizeAndRecomputeIntrinsicSize() throws {
    let textStyle = CanvasTextStyle(fontSize: 20)
    let textItem = CanvasTextItem(
        text: "Scale me",
        style: textStyle,
        center: CGPoint(x: 25, y: 25),
        size: CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: "Scale me",
            style: textStyle
        )
    )
    // ... 后续断言未改动
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() / testBoardStoreOverwritesHandDrawingAssetsAndRefreshesPersistedThumbnail()
// 功能说明: 修改前存储测试只锁定首次保存与覆盖写刷新，不覆盖 duplicated handDrawing 的独立资产路径。
func testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() throws {
    // ... 既有首次保存闭环测试
}

func testBoardStoreOverwritesHandDrawingAssetsAndRefreshesPersistedThumbnail() throws {
    // ... 既有覆盖写与 thumbnail 刷新测试
}
```

### 修改后

- 新增 `testResizedMemberItemsNormalizeHandDrawingBackToPaperAspectRatio()`，锁定 handDrawing 在 group resize / selection resize 路径上的等比约束。
- 新增 `testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths()`，验证 duplicated handDrawing 使用新 `itemID` 派生新的 `.pkdrawing/.png`，并能重新加载。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift
// 函数名: testResizedMemberItemsNormalizeHandDrawingBackToPaperAspectRatio()
// 功能说明: 修改后新增 handDrawing 缩放测试，确保纸张被从 60x40 的输入几何拉回到 1:1 的 square paper 比例。
func testResizedMemberItemsNormalizeHandDrawingBackToPaperAspectRatio() throws {
    let handDrawingID = CanvasItemID()
    let handDrawingItem = CanvasHandDrawingItem(
        id: handDrawingID,
        paper: .square,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: handDrawingID,
            cgImage: try makeSelectionTransformTestCGImage()
        ),
        isEmpty: true,
        center: CGPoint(x: 30, y: 20),
        size: CGSize(width: 60, height: 40),
        zIndex: 0,
        rotationRadians: 0
    )
    let snapshot = CanvasSelectionTransformSnapshot(
        primaryItemID: handDrawingID,
        memberItems: [.handDrawing(handDrawingItem)],
        selectionBounds: CGRect(x: 0, y: 0, width: 60, height: 40)
    )

    let resizedItems = try XCTUnwrap(
        snapshot.resizedMemberItems(
            handleRole: .bottomTrailing,
            draggedWorldCorner: CGPoint(x: 120, y: 80),
            minimumScale: 0.1
        )
    )
    let resizedHandDrawingItem = try XCTUnwrap(
        resizedItems.first?.handDrawingItem
    )

    XCTAssertEqual(resizedHandDrawingItem.center, CGPoint(x: 60, y: 40))
    XCTAssertEqual(resizedHandDrawingItem.size, CGSize(width: 120, height: 120))
    XCTAssertEqual(
        resizedHandDrawingItem.size.width / resizedHandDrawingItem.size.height,
        1,
        accuracy: 0.0001
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths()
// 功能说明: 修改后新增 duplicated handDrawing 存储测试，验证新 itemID 派生的新资产路径能被保存、重载并与源 item 分离。
func testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() throws {
    try withTemporaryHandDrawingBoardWorkspace { _, userDefaults in
        let boardID = UUID()
        let sourceItemID = UUID()
        let sourcePreviewImage = try makeHandDrawingTestImage(
            red: 0.2,
            green: 0.55,
            blue: 0.95
        )
        let sourceDrawingData = Data("hand-drawing-duplicate-source".utf8)
        let sourceItem = makeHandDrawingItem(
            id: sourceItemID,
            previewImage: sourcePreviewImage,
            contentRevision: UUID()
        )
        var runtimeState = makeHandDrawingRuntimeState(
            boardID: boardID,
            now: Date(timeIntervalSince1970: 1_720_000_500),
            item: sourceItem
        )

        // ... 先保存源 item

        let duplicatedHandDrawingItem = sourceItem.duplicated(
            offsetInWorld: CGPoint(x: 42, y: 24)
        )
        runtimeState.items = [
            .handDrawing(sourceItem),
            .handDrawing(duplicatedHandDrawingItem)
        ]
        let duplicatedSnapshot = BoardSaveSnapshot(
            runtimeState: runtimeState,
            transientImageAssetPayloads: [:],
            transientHandDrawingAssetPayloads: [
                duplicatedHandDrawingItem.id: BoardTransientHandDrawingAssetPayload(
                    itemID: duplicatedHandDrawingItem.id,
                    drawingData: sourceDrawingData,
                    previewCGImage: duplicatedHandDrawingItem.previewAsset.posterCGImage
                )
            ]
        )

        XCTAssertNotEqual(duplicatedHandDrawingItem.id, sourceItemID)
        XCTAssertNotEqual(
            duplicatedHandDrawingItem.previewImageFilename,
            sourceItem.previewImageFilename
        )
        XCTAssertNotEqual(
            duplicatedHandDrawingItem.sourceDrawingFilename,
            sourceItem.sourceDrawingFilename
        )

        // ... 保存 duplicated item 后，再校验 source / duplicated 两套资产都能被重新加载
    }
}
```

## 验证结果

- `xcodebuild -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64' -only-testing:MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests -only-testing:MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests test`
  - 结果：通过。
- `xcodebuild -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk macosx build`
  - 结果：通过。
- `xcodebuild -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk iphonesimulator build`
  - 结果：通过。
- `ReadLints`
  - 结果：本次涉及文件未发现新增 linter 问题。
